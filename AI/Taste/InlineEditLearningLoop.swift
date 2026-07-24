// CosmoOS/AI/Taste/InlineEditLearningLoop.swift
// MainActor orchestration for edit-loop learning: opens episodes at review
// verdicts, watches surface activity, and settles episodes at deterministic
// choke points — quiet surface, document close, an overlapping AI re-edit
// (the attribution firewall), and app resign. Settled episodes emit
// TasteStore signals; the distiller compresses them into beliefs.
// July 2026

import Foundation
import AppKit

@MainActor
final class InlineEditLearningLoop {
    static let shared = InlineEditLearningLoop()

    /// A surface must be typing-quiet this long before accepted edits count
    /// as settled (the user has moved on).
    static let quietInterval: TimeInterval = 480
    /// A rejection's follow-up ask only counts this close to the verdict.
    static let rejectionReasonTTL: TimeInterval = 600
    /// Surfaces whose edits can teach: text documents with owned providers.
    static let learnableSurfacePrefixes: Set<String> = ["content", "note", "idea"]

    private var lastActivityBySurface: [String: Date] = [:]
    /// Open-episode counts per surface — the cheap gate that keeps every
    /// hot-path hook O(1) when nothing is being watched.
    private var openEpisodeCounts: [String: Int] = [:]
    private var pendingRejection: (episodeID: String, surfaceID: String, clientUuid: String?, skillId: String, aiText: String, at: Date)?
    private var sweepTask: Task<Void, Never>?
    private var resignObserver: NSObjectProtocol?
    private var didBootstrap = false

    private init() {}

    // MARK: - Bootstrap

    /// Restores open-episode bookkeeping after an app restart and settles
    /// anything that went stale while the app was closed.
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        observeAppResign()
        let open = await InlineEditEpisodeStore.openEpisodes()
        guard !open.isEmpty else { return }
        for episode in open {
            openEpisodeCounts[episode.surfaceId, default: 0] += 1
        }
        // Everything from a previous launch is by definition past the quiet
        // window — settle it against the atom's current text.
        for episode in open {
            await settle(episode)
        }
    }

    // MARK: - Episode opening

    struct VerdictContext {
        var operationID: UUID
        var surfaceID: String
        var targetID: String
        var skillID: String?
        var ask: String
        var verdict: InlineEditEpisode.Verdict
        /// The staged text (byte-exact applied text for accepts).
        var aiText: String
        var originalText: String?
        /// The document BEFORE the accept applied (== current for rejects).
        var preApplyText: String
        /// Where the edit landed/would land in `preApplyText`.
        var appliedRange: Range<String.Index>?
        /// The document AFTER the accept applied (== current for rejects).
        var postApplyText: String
    }

    /// Called from the store at verdict time. Opens an episode when the edit
    /// is learnable; silently does nothing otherwise.
    func reviewVerdictDelivered(_ context: VerdictContext) async {
        guard Self.isLearnableSurface(context.surfaceID),
              InlineEditHarvester.hasSubstantialLine(context.aiText) else { return }

        let clientUuid = await Self.clientUuid(forSurfaceID: context.surfaceID)
        // Accepted: the applied region (offset math into the post-apply text).
        // Rejected: the document is unchanged — the region the user might
        // self-write is where the ORIGINAL text sits, placement.range itself.
        let anchors: (before: String?, after: String?)
        if context.verdict == .rejected, let range = context.appliedRange {
            anchors = InlineEditAnchorExtractor.anchors(forRegion: range, in: context.postApplyText)
        } else {
            anchors = InlineEditAnchorExtractor.anchors(
                around: context.appliedRange,
                preApplyText: context.preApplyText,
                appliedText: context.aiText,
                in: context.postApplyText
            )
        }
        let slideRole = context.appliedRange.map {
            InlineEditSlideRole.role(inText: context.preApplyText, atLocation: $0.lowerBound)
        } ?? nil

        let episode = InlineEditEpisode(
            id: context.operationID.uuidString,
            surfaceId: context.surfaceID,
            targetId: context.targetID,
            clientUuid: clientUuid,
            skillId: context.skillID ?? CosmoInlineAssistantSkillID.inlineEdit.rawValue,
            ask: String(context.ask.prefix(300)),
            verdict: context.verdict.rawValue,
            aiText: String(context.aiText.prefix(2_000)),
            originalText: context.originalText.map { String($0.prefix(2_000)) },
            slideRole: slideRole,
            anchorBefore: anchors.before,
            anchorAfter: anchors.after,
            outcome: InlineEditEpisode.Outcome.settling.rawValue,
            settledText: nil,
            magnitude: nil,
            userReason: nil,
            createdAt: ISO8601.string(from: Date()),
            settledAt: nil
        )
        await InlineEditEpisodeStore.insert(episode)
        openEpisodeCounts[context.surfaceID, default: 0] += 1

        if context.verdict == .rejected {
            pendingRejection = (
                episodeID: episode.id,
                surfaceID: context.surfaceID,
                clientUuid: clientUuid,
                skillId: episode.skillId,
                aiText: episode.aiText,
                at: Date()
            )
        }
        ensureSweepRunning()
    }

    // MARK: - Hot-path signals

    /// Stamped from the surface registry's activation path (per keystroke,
    /// already-coalesced). One dictionary write — nothing else.
    func noteUserActivity(surfaceID: String) {
        lastActivityBySurface[surfaceID] = Date()
    }

    /// The user spoke right after rejecting: that ask is the labeled WHY.
    /// State-based — no keyword matching; scope and recency are the gates.
    func captureRejectionReasonIfPending(prompt: String, sessionSurfaceID: String) {
        guard let pending = pendingRejection else { return }
        defer { pendingRejection = nil }
        guard Date().timeIntervalSince(pending.at) <= Self.rejectionReasonTTL,
              pending.surfaceID == sessionSurfaceID else { return }
        let reason = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }

        let episodeID = pending.episodeID
        let clientUuid = pending.clientUuid
        let aiText = pending.aiText
        Task {
            await InlineEditEpisodeStore.attachReason(id: episodeID, reason: reason)
            await TasteStore.record(
                kind: .editRejected,
                clientUuid: clientUuid,
                content: """
                REJECTED AI EDIT: "\(aiText.prefix(200))"
                USER'S FOLLOW-UP (the why): "\(reason.prefix(200))"
                """
            )
            await TasteDistiller.distillIfDue(clientUuid: clientUuid)
        }
    }

    // MARK: - Settle triggers

    /// The attribution firewall: BEFORE a new accepted edit applies to a
    /// surface, any open episode whose region the incoming edit touches (or
    /// that can no longer be located at all) is harvested — everything in the
    /// document at this instant is human-authored.
    func harvestBeforeApply(
        surfaceID: String,
        preApplyText: String,
        incomingRange: Range<String.Index>?
    ) async {
        guard openEpisodeCounts[surfaceID, default: 0] > 0 else { return }
        let open = await InlineEditEpisodeStore.openEpisodes(surfaceId: surfaceID)
        for episode in open {
            guard let episodeRange = Self.locateEpisodeRegion(episode, in: preApplyText) else {
                // Unlocatable now means unattributable later — harvest with
                // the guards while the text is still purely the user's.
                await settle(episode, currentText: preApplyText)
                continue
            }
            if let incomingRange, episodeRange.overlaps(incomingRange) {
                await settle(episode, currentText: preApplyText)
            }
        }
    }

    /// A closing document settles its episodes against its final text —
    /// grabbed by the registry before the provider is released.
    func surfaceWillClose(surfaceID: String, finalText: String) {
        guard openEpisodeCounts[surfaceID, default: 0] > 0 else { return }
        Task {
            let open = await InlineEditEpisodeStore.openEpisodes(surfaceId: surfaceID)
            for episode in open {
                await settle(episode, currentText: finalText)
            }
        }
    }

    /// Whether the registry needs to snapshot a closing surface's text for us.
    func hasOpenEpisodes(surfaceID: String) -> Bool {
        openEpisodeCounts[surfaceID, default: 0] > 0
    }

    /// Rollback is not a verdict: the rolled-back operations' episodes vanish.
    func rollbackDiscardedOperations(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let stringIDs = ids.map(\.uuidString)
        Task {
            let open = await InlineEditEpisodeStore.openEpisodes()
            let removed = open.filter { stringIDs.contains($0.id) }
            await InlineEditEpisodeStore.delete(ids: stringIDs)
            for episode in removed {
                self.decrementOpenCount(surfaceID: episode.surfaceId)
            }
        }
        if let pending = pendingRejection, stringIDs.contains(pending.episodeID) {
            pendingRejection = nil
        }
    }

    // MARK: - Sweep (quiet surfaces)

    private func ensureSweepRunning() {
        guard sweepTask == nil else { return }
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self else { return }
                let hasOpen = await self.settleQuietSurfaces()
                if !hasOpen {
                    await self.stopSweep()
                    return
                }
            }
        }
    }

    private func stopSweep() {
        sweepTask?.cancel()
        sweepTask = nil
    }

    /// Settles episodes whose surface has been typing-quiet past the window.
    /// Returns whether any episodes remain open (keeps the sweep alive).
    private func settleQuietSurfaces() async -> Bool {
        let open = await InlineEditEpisodeStore.openEpisodes()
        guard !open.isEmpty else {
            openEpisodeCounts = [:]
            return false
        }
        let now = Date()
        for episode in open {
            let created = ISO8601.date(from: episode.createdAt) ?? now
            let lastActivity = lastActivityBySurface[episode.surfaceId] ?? .distantPast
            let quietSince = max(created, lastActivity)
            if now.timeIntervalSince(quietSince) >= Self.quietInterval {
                await settle(episode)
            }
        }
        return !openEpisodeCounts.isEmpty
    }

    private func observeAppResign() {
        guard resignObserver == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let open = await InlineEditEpisodeStore.openEpisodes()
                for episode in open {
                    await InlineEditLearningLoop.shared.settle(episode)
                }
            }
        }
    }

    // MARK: - Settling

    /// Resolves the surface's current text (live provider first, the atom on
    /// disk second) and runs the harvester.
    private func settle(_ episode: InlineEditEpisode) async {
        let currentText: String?
        if let provider = CosmoEditableSurfaceRegistry.shared.provider(surfaceID: episode.surfaceId) {
            currentText = provider.editableSnapshot().text
        } else {
            currentText = await Self.loadSurfaceText(surfaceID: episode.surfaceId)
        }
        guard let currentText else {
            await InlineEditEpisodeStore.markSettled(
                id: episode.id, outcome: .discarded, settledText: nil, magnitude: nil
            )
            decrementOpenCount(surfaceID: episode.surfaceId)
            return
        }
        await settle(episode, currentText: currentText)
    }

    func settle(_ episode: InlineEditEpisode, currentText: String) async {
        guard episode.isOpen else { return }
        let outcome = InlineEditHarvester.harvest(.init(
            verdict: episode.verdictKind,
            aiText: episode.aiText,
            originalText: episode.originalText,
            anchorBefore: episode.anchorBefore,
            anchorAfter: episode.anchorAfter,
            currentText: currentText
        ))

        switch outcome {
        case .untouched:
            await InlineEditEpisodeStore.markSettled(
                id: episode.id, outcome: .untouched, settledText: nil, magnitude: nil
            )
            if episode.verdictKind == .accepted {
                await TasteStore.record(
                    kind: .editAccepted,
                    clientUuid: episode.clientUuid,
                    content: "Accepted edit survived review untouched\(Self.roleSuffix(episode)): \"\(episode.aiText.prefix(280))\""
                )
            }
        case .tweak(let settledText, let magnitude, let punctuationOnly):
            await InlineEditEpisodeStore.markSettled(
                id: episode.id, outcome: .tweak, settledText: settledText, magnitude: magnitude
            )
            await TasteStore.record(
                kind: .editTweak,
                clientUuid: episode.clientUuid,
                content: Self.tweakSignalContent(
                    episode: episode, settledText: settledText, punctuationOnly: punctuationOnly
                )
            )
            // The pair itself joins the exemplar bank — retrieved few-shot
            // into future edit runs on similar asks.
            await EditExemplarBank.ingest(from: episode, settledText: settledText)
        case .rewrite:
            await InlineEditEpisodeStore.markSettled(
                id: episode.id, outcome: .rewrite, settledText: nil, magnitude: nil
            )
            await TasteStore.record(
                kind: .editRejected,
                clientUuid: episode.clientUuid,
                content: "User fully rewrote an accepted AI edit (weak signal — may be a topic pivot, judge the approach only)\(Self.roleSuffix(episode)): \"\(episode.aiText.prefix(240))\""
            )
        case .discarded:
            await InlineEditEpisodeStore.markSettled(
                id: episode.id, outcome: .discarded, settledText: nil, magnitude: nil
            )
        }
        decrementOpenCount(surfaceID: episode.surfaceId)
        if outcome != .discarded {
            await TasteDistiller.distillIfDue(clientUuid: episode.clientUuid)
        }
    }

    private func decrementOpenCount(surfaceID: String) {
        let next = openEpisodeCounts[surfaceID, default: 1] - 1
        if next <= 0 {
            openEpisodeCounts.removeValue(forKey: surfaceID)
        } else {
            openEpisodeCounts[surfaceID] = next
        }
    }

    // MARK: - Helpers

    static func isLearnableSurface(_ surfaceID: String) -> Bool {
        guard let prefix = surfaceID.split(separator: ":").first else { return false }
        return learnableSurfacePrefixes.contains(String(prefix))
    }

    private static func tweakSignalContent(
        episode: InlineEditEpisode,
        settledText: String,
        punctuationOnly: Bool
    ) -> String {
        let header = episode.verdictKind == .accepted
            ? "AI WROTE: \"\(episode.aiText.prefix(230))\"\nUSER MADE IT: \"\(settledText.prefix(230))\""
            : "AI OFFERED (rejected): \"\(episode.aiText.prefix(230))\"\nUSER WROTE INSTEAD: \"\(settledText.prefix(230))\""
        var notes: [String] = []
        if let role = episode.slideRole { notes.append("slide: \(role)") }
        notes.append("skill: \(episode.skillId)")
        if punctuationOnly { notes.append("punctuation-level change") }
        return "\(header)\n(\(notes.joined(separator: "; ")))"
    }

    private static func roleSuffix(_ episode: InlineEditEpisode) -> String {
        episode.slideRole.map { " (slide: \($0))" } ?? ""
    }

    /// Client scoping is strictly walled: only the surface atom's own client
    /// UUID counts. Notes/ideas (no client) accrue to the personal profile.
    static func clientUuid(forSurfaceID surfaceID: String) async -> String? {
        let parts = surfaceID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "content",
              let atom = try? await AtomRepository.shared.fetch(uuid: parts[1]) else { return nil }
        return atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID
    }

    /// Where the episode's text sits in `text` right now: the AI text itself
    /// first, the anchor-bounded span second, nil when neither locates.
    static func locateEpisodeRegion(
        _ episode: InlineEditEpisode,
        in text: String
    ) -> Range<String.Index>? {
        if let direct = CosmoInlineDiffLocator.range(of: episode.aiText, in: text) {
            return direct
        }
        let beforeRange = episode.anchorBefore.flatMap { CosmoInlineDiffLocator.range(of: $0, in: text) }
        let afterRange = episode.anchorAfter.flatMap { CosmoInlineDiffLocator.range(of: $0, in: text) }
        if let beforeRange, let afterRange, beforeRange.upperBound <= afterRange.lowerBound {
            return beforeRange.upperBound..<afterRange.lowerBound
        }
        return nil
    }

    /// Loads a closed surface's text straight from the atom — the settle
    /// path's fallback when no live view holds the document.
    static func loadSurfaceText(surfaceID: String) async -> String? {
        let parts = surfaceID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let atom = try? await AtomRepository.shared.fetch(uuid: parts[1]) else { return nil }
        let field: RichDocumentField = parts[0] == "content" ? .draft : .body
        return RichDocumentPersistence.loadAtomDocument(
            field: field,
            metadata: atom.metadata,
            fallbackPlainText: atom.body
        ).plainText
    }
}

// MARK: - Anchor extraction (pure)

/// The applied region's untouched neighbors — the AI edit didn't write them,
/// so the user's tweaks usually leave them standing, and they relocate the
/// region after the surrounding document shifts.
enum InlineEditAnchorExtractor {
    static let anchorLineCount = 2

    static func anchors(
        around appliedRange: Range<String.Index>?,
        preApplyText: String,
        appliedText: String,
        in postApplyText: String
    ) -> (before: String?, after: String?) {
        // `appliedRange` is in PRE-apply coordinates, but a replacement leaves
        // everything before its lower bound untouched — the same character
        // offset opens the applied region in the post-apply text. Offset math
        // beats re-searching: a repeated line (deliberate hook echo) would
        // re-locate at its FIRST occurrence and anchor the wrong region.
        if let appliedRange {
            let lowerOffset = preApplyText.distance(from: preApplyText.startIndex, to: appliedRange.lowerBound)
            if lowerOffset <= postApplyText.count {
                let lower = postApplyText.index(postApplyText.startIndex, offsetBy: lowerOffset)
                let upperOffset = min(lowerOffset + appliedText.count, postApplyText.count)
                let upper = postApplyText.index(postApplyText.startIndex, offsetBy: upperOffset)
                return anchors(forRegion: lower..<upper, in: postApplyText)
            }
        }
        // Append-fallback placements (no resolved range): find the applied
        // text by search — for appends it sits at the document tail, unique.
        guard let found = CosmoInlineDiffLocator.range(of: appliedText, in: postApplyText) else {
            return (nil, nil)
        }
        return anchors(forRegion: found, in: postApplyText)
    }

    static func anchors(
        forRegion region: Range<String.Index>,
        in text: String
    ) -> (before: String?, after: String?) {
        let head = String(text[..<region.lowerBound])
        let tail = String(text[region.upperBound...])
        let beforeLines = InlineEditHarvester.lines(of: head).suffix(anchorLineCount)
        let afterLines = InlineEditHarvester.lines(of: tail).prefix(anchorLineCount)
        return (
            before: beforeLines.isEmpty ? nil : beforeLines.joined(separator: "\n"),
            after: afterLines.isEmpty ? nil : afterLines.joined(separator: "\n")
        )
    }
}
