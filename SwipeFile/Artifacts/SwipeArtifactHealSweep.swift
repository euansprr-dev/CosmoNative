// CosmoOS/SwipeFile/Artifacts/SwipeArtifactHealSweep.swift
// Nothing captured stays stranded.
//
// Posts have a whole retry ladder (Railway backoff, stale reclaim, manual
// Retry). Artifact kinds had NONE: SwipePageDecomposition and
// SwipeFrameDecomposition ran exactly once, at capture, on this Mac — so a
// failed pass, a crash mid-capture, or a swipe captured on the iPhone (where
// no decomposer exists at all) sat "partial"/"pending" forever. The July 29
// "she sells" frame set — analyzed hours before the genre-emitting analyzer
// shipped, stranded genre-less in Screenshots — is the founding member.
//
// This sweep is the artifact twin of the post pipeline's self-heal: it rides
// SwipeMediaMirrorCoordinator.kick (called every sync cycle, so an iPhone
// capture is picked up within one cycle of syncing down), derives candidacy
// from STATE — status + units + age, never history — and bounds itself with
// a local attempts ledger so a permanently broken swipe stops costing model
// calls after three tries.
//
// CANDIDACY IS PURE (`healAction(for:now:)`) and pinned by
// SwipeArtifactHealSweepTests. The runner re-fetches by uuid before acting
// (PERSIST-BY-UUID law) and re-checks after, clearing the ledger on success.

import Foundation

// MARK: - Sweep

@MainActor
enum SwipeArtifactHealSweep {

    /// What a pass may do to one swipe.
    enum HealAction: Equatable {
        /// Render → slice → read from the captured URL (page kinds).
        case decomposePage(url: String)
        /// Re-run vision + craft over the swipe's own attachments (frames).
        case reanalyzeFrames
        /// Analysis is fine but the filing never happened (rows analyzed
        /// before genre existed): one cheap classifier call, no craft re-run.
        case classifyGenre
    }

    /// Model calls per pass. A pass rides every sync cycle, so a small cap
    /// still drains a backlog within the hour without ever bursting spend.
    static let maxHealsPerPass = 5
    /// A swipe gets this many attempts before the sweep leaves it to the
    /// manual Retry seat. Matches the worker's cloudRetryCount philosophy.
    static let maxAttempts = 3
    /// Minimum spacing between attempts on one swipe.
    static let retrySpacing: TimeInterval = 60 * 60
    /// A page younger than this may still be mid-capture on this Mac.
    static let pageSettleAge: TimeInterval = 3 * 60
    /// Frames get longer — the inline vision+craft pass can take a while.
    static let frameSettleAge: TimeInterval = 10 * 60

    private static var isRunning = false

    // MARK: Candidacy (pure — tests pin every branch)

    /// nil = healthy, foreign, or not this sweep's business. Deliberately
    /// state-derived: status + units + age, never "what happened before"
    /// (`feedback_no_bandaids`). Posts belong to the worker's ladder; flows
    /// are member lists with nothing to decompose; single-unit notes carry
    /// their own text.
    static func healAction(for atom: Atom, now: Date) -> HealAction? {
        guard atom.researchMetadata?.isSwipeFile == true, !atom.isDeleted else { return nil }
        let status = atom.researchMetadata?.processingStatus ?? "pending"
        let age = now.timeIntervalSince(ISO8601.date(from: atom.updatedAt) ?? .distantPast)

        switch atom.swipeKind {
        case .page:
            // Units present + complete = healthy. Anything short of complete
            // with a URL to re-render is healable — including "extracting"
            // (a crash mid-capture) and "pending" (an iPhone capture that has
            // no decomposer of its own; the Mac is its processor).
            if ["pending", "extracting", "partial", "extraction_failed"].contains(status),
               age > pageSettleAge,
               let url = atom.swipeArtifact?.capturedURL ?? atom.researchMetadata?.url,
               !url.isEmpty {
                return .decomposePage(url: url)
            }
            return genreBackfillAction(for: atom, status: status)

        case .frame:
            // "partial" covers both a failed craft pass AND a pass that ran
            // before the analyzer emitted genre (the "she sells" state) — one
            // re-run heals both, and success flips the status to complete,
            // ending candidacy.
            if ["pending", "analyzing", "partial", "extraction_failed"].contains(status),
               age > frameSettleAge,
               !atom.swipeArtifactUnits.isEmpty {
                return .reanalyzeFrames
            }
            return genreBackfillAction(for: atom, status: status)

        case .note:
            return genreBackfillAction(for: atom, status: status)

        case .post, .flow:
            return nil
        }
    }

    /// Complete-but-unfiled: the analysis is healthy, the envelope just never
    /// got a genre (analyzed before genre existed, or the craft verdict
    /// answered nothing). One cheap classifier call; the TERMINAL rule writes
    /// even a structural-fallback verdict to the envelope, ending candidacy.
    private static func genreBackfillAction(for atom: Atom, status: String) -> HealAction? {
        guard status == "complete",
              let artifact = atom.swipeArtifact,
              artifact.genre == nil,
              artifact.genreLockedByUser != true,
              !artifact.units.isEmpty
        else { return nil }
        return .classifyGenre
    }

    // MARK: Runner

    /// One bounded pass. Kicked by SwipeMediaMirrorCoordinator every sync
    /// cycle; cheap no-op when the library is healthy.
    static func runPassIfNeeded() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        guard let atoms = try? await AtomRepository.shared.fetchAll(type: .research) else { return }
        let now = Date()
        var ledger = SwipeHealLedger.load()
        var healed = 0

        for atom in atoms {
            guard healed < maxHealsPerPass else { break }
            guard let action = healAction(for: atom, now: now) else {
                // Healthy again (or no longer ours) — forget its strikes.
                ledger.clear(atom.uuid)
                continue
            }
            guard ledger.mayAttempt(atom.uuid, now: now,
                                    maxAttempts: maxAttempts, spacing: retrySpacing) else { continue }

            ledger.recordAttempt(atom.uuid, now: now)
            ledger.save()
            healed += 1

            let uuid = atom.uuid
            let note = atom.body?.trimmed
            switch action {
            case .decomposePage(let url):
                guard let pageURL = URL(string: url) else { continue }
                await SwipePageDecomposition.run(swipeUUID: uuid, url: pageURL, note: note)
            case .reanalyzeFrames:
                await SwipeFrameDecomposition.run(swipeUUID: uuid, note: note)
            case .classifyGenre:
                await classifyGenre(atom: atom, note: note)
            }

            // Success ends the story: complete → never a candidate again, and
            // the strikes are erased so a FUTURE failure gets a fresh three.
            if let live = try? await AtomRepository.shared.fetch(uuid: uuid),
               live.researchMetadata?.processingStatus == "complete" {
                ledger.clear(uuid)
            }
        }
        ledger.save()
    }

    /// One cheap classifier call for a complete-but-unfiled swipe. The write
    /// is DIRECT (not fill-only): the TERMINAL rule stores even a structural
    /// fallback in the envelope so this row never re-candidates — a decided
    /// "genuinely just screenshots" is a real answer, not an absence.
    private static func classifyGenre(atom: Atom, note: String?) async {
        guard let artifact = atom.swipeArtifact else { return }
        let copy = artifact.orderedUnits.compactMap(\.copy).filter { !$0.trimmed.isEmpty }

        let verdict: SwipeGenreClassifier.Verdict?
        if !copy.isEmpty {
            let text = ([artifact.pageTitle ?? atom.title ?? ""] + copy).joined(separator: "\n")
            verdict = await SwipeGenreClassifier.classify(
                pageText: text, url: artifact.capturedURL ?? atom.researchMetadata?.url, note: note
            )
        } else {
            let images = await SwipeFrameDecomposition.imageBytes(for: artifact)
            guard !images.isEmpty else { return }
            verdict = await SwipeGenreClassifier.classify(images: images, note: note, unitCopy: [])
        }
        guard let verdict,
              let live = try? await AtomRepository.shared.fetch(uuid: atom.uuid),
              live.swipeArtifact?.genre == nil,
              live.swipeArtifact?.genreLockedByUser != true else { return }
        let updated = live.withSwipeGenre(verdict.genre, lockedByUser: false)
        _ = try? await AtomRepository.shared.update(updated)
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
    }
}

// MARK: - Attempts ledger

/// Local JSON beside swipe_patterns.json — heal attempts are THIS Mac's
/// operational memory, not shared state, so they never touch the sync
/// surface (no new ResearchMetadata field, no iOS twin obligation).
struct SwipeHealLedger: Codable {
    struct Entry: Codable {
        var attempts: Int
        var lastAttempt: Date
    }

    var entries: [String: Entry] = [:]

    static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cosmoDir = appSupport.appendingPathComponent("CosmoOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: cosmoDir, withIntermediateDirectories: true)
        return cosmoDir.appendingPathComponent("swipe_heal_ledger.json")
    }

    static func load() -> SwipeHealLedger {
        guard let data = try? Data(contentsOf: fileURL),
              let ledger = try? JSONDecoder().decode(SwipeHealLedger.self, from: data) else {
            return SwipeHealLedger()
        }
        return ledger
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    func mayAttempt(_ uuid: String, now: Date, maxAttempts: Int, spacing: TimeInterval) -> Bool {
        guard let entry = entries[uuid] else { return true }
        guard entry.attempts < maxAttempts else { return false }
        return now.timeIntervalSince(entry.lastAttempt) >= spacing
    }

    mutating func recordAttempt(_ uuid: String, now: Date) {
        var entry = entries[uuid] ?? Entry(attempts: 0, lastAttempt: .distantPast)
        entry.attempts += 1
        entry.lastAttempt = now
        entries[uuid] = entry
    }

    mutating func clear(_ uuid: String) {
        entries.removeValue(forKey: uuid)
    }
}
