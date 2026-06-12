// CosmoOS/Data/Services/InboxIngestService.swift
// The single choke point for inbox ingestion — every capture path (Telegram,
// in-app capture bar, voice, cloud sync, topic aliases) funnels through here.
//
// The membership contract (INBOX_REVAMP_PLAN.md §1): an item enters the inbox
// iff it was explicitly captured AND no other system consumed it. Ideas created
// for a client, lane-routed captures, and inquiry extracts are *consumed* —
// they never double-enter triage.
//
// Classification is owned by this service's queue, not by call sites — the bug
// class where a fallback path created items and never classified them (stuck
// forever in "Needs your judgment") cannot recur.
// June 2026 — Inbox Revamp

import Foundation
import GRDB

@MainActor
final class InboxIngestService {
    static let shared = InboxIngestService()

    private let inboxRepo = InboxRepository.shared
    private let atomRepo = AtomRepository.shared
    private let database = CosmoDatabase.shared
    private let config = InboxRoutingConfig.shared

    /// Window inside which "an atom with identical content already exists"
    /// means the capture was consumed by another flow (agent created the idea,
    /// lane routed the note) rather than coincidence.
    private let consumedWindowAtIngest: TimeInterval = 20 * 60
    private let consumedWindowAtReconcile: TimeInterval = 14 * 24 * 3600

    // MARK: - Classification queue

    private var queuedItemUuids: [String] = []
    private var queuedSet: Set<String> = []
    private var drainTask: Task<Void, Never>?

    // MARK: - Taxonomy pass throttle

    private var lastTaxonomyPassAt: Date = .distantPast
    private var taxonomyPassTask: Task<Void, Never>?
    private let taxonomyPassThrottle: TimeInterval = 10 * 60

    private init() {}

    // MARK: - Ingest

    struct RawCapture {
        let source: InboxSource
        let rawText: String
        var title: String? = nil
        var metadata: String? = nil
        /// Cloud transport atom uuid — used for dedupe and search exclusion.
        var sourceAtomUuid: String? = nil
        var excludedAtomUUIDs: [String] = []
        /// Pre-routed destination (e.g. Telegram topic alias → deep dive inbox).
        var preset: PresetPlacement? = nil
    }

    struct PresetPlacement {
        let thinkspaceId: String
        let thinkspaceName: String?
    }

    enum IngestOutcome {
        /// Another system owns this capture — no inbox item was created.
        case consumed(reason: String)
        /// The capture is in the inbox awaiting (or carrying) a classification.
        case enqueued(InboxItem)
        /// The DB write failed after retries — the capture was NOT saved.
        /// Callers must report this honestly and preserve their copy of the text.
        case failed(String)
    }

    /// Ingest a capture. When `classifyImmediately` is true the call awaits
    /// classification (used by Telegram replies that echo the suggestion);
    /// otherwise classification happens on the background queue.
    @discardableResult
    func ingest(_ capture: RawCapture, classifyImmediately: Bool = false) async -> IngestOutcome {
        let text = capture.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .consumed(reason: "empty capture") }

        // Dedupe: one inbox item per cloud transport atom, ever.
        if let sourceAtomUuid = capture.sourceAtomUuid,
           await inboxItemExists(sourceAtomUuid: sourceAtomUuid) {
            return .consumed(reason: "already converted")
        }

        // Consumed rule: if an atom with this exact content was just created,
        // another flow (agent idea creation, lane routing) already acted on the
        // message — triage would be second-guessing a decision already made.
        // Quick-capture is exempt (the user is looking at the inbox; nothing
        // else could have consumed it), and short phrases are exempt (title-only
        // matches on a few tokens kill real captures).
        if capture.preset == nil,
           capture.source != .quickCapture,
           Self.normalized(text).split(separator: " ").count >= 6,
           let existing = await matchingAtom(forText: text, title: capture.title, within: consumedWindowAtIngest) {
            return .consumed(reason: "atom \(existing.uuid) already created from this capture")
        }

        var metadata = capture.metadata
        if let sourceAtomUuid = capture.sourceAtomUuid {
            metadata = mergedMetadata(metadata, adding: ["sourceAtomUuid": sourceAtomUuid])
        }

        var item = InboxItem.new(
            source: capture.source,
            rawText: text,
            title: capture.title,
            metadata: metadata
        )

        // Pre-routed captures (topic aliases) arrive already placed.
        if let preset = capture.preset {
            item.placeThinkspaceId = preset.thinkspaceId
            item.placeThinkspaceName = preset.thinkspaceName
            item.classification = .place
            item.confidence = 1.0
            item.status = .classified
        }

        // Bounded retry: a transient SQLITE_BUSY must not lose a capture.
        let saved: InboxItem
        do {
            saved = try await createWithRetry(item)
        } catch {
            print("⚠️ [InboxIngest] Failed to create inbox item after retries: \(error)")
            PersistenceHealth.note(
                .writeFailure,
                context: "InboxIngestService.ingest",
                detail: "inbox item create failed after retries (\(capture.source.rawValue)): \(error.localizedDescription)"
            )
            return .failed(error.localizedDescription)
        }

        NotificationCenter.default.post(name: CosmoNotification.Inbox.itemAdded, object: nil)

        if capture.preset != nil {
            return .enqueued(saved)
        }

        if classifyImmediately {
            await classifyAndStore(item: saved, excludedAtomUUIDs: capture.excludedAtomUUIDs)
            let refreshed = (try? await inboxRepo.fetch(uuid: saved.uuid)) ?? saved
            return .enqueued(refreshed)
        }

        enqueueForClassification(saved.uuid)
        return .enqueued(saved)
    }

    /// Initial attempt plus three retries with short backoff (200ms/500ms/1s)
    /// before surfacing failure — a transient SQLITE_BUSY must not lose a capture.
    private func createWithRetry(_ item: InboxItem) async throws -> InboxItem {
        let backoffs: [Duration] = [.milliseconds(200), .milliseconds(500), .seconds(1)]
        do {
            return try await inboxRepo.create(item)
        } catch {
            var lastError = error
            for backoff in backoffs {
                try? await Task.sleep(for: backoff)
                do {
                    return try await inboxRepo.create(item)
                } catch {
                    lastError = error
                    print("⚠️ [InboxIngest] create retry failed: \(error)")
                }
            }
            throw lastError
        }
    }

    // MARK: - Classification queue

    private func enqueueForClassification(_ uuid: String) {
        guard !queuedSet.contains(uuid) else { return }
        queuedSet.insert(uuid)
        queuedItemUuids.append(uuid)
        drainQueueIfNeeded()
    }

    private func drainQueueIfNeeded() {
        guard drainTask == nil else { return }
        drainTask = Task { @MainActor [weak self] in
            while let self, let uuid = self.dequeueNext() {
                guard let item = try? await self.inboxRepo.fetch(uuid: uuid),
                      item.status == .pending else { continue }
                await self.classifyAndStore(item: item, excludedAtomUUIDs: [])
            }
            self?.drainTask = nil
        }
    }

    private func dequeueNext() -> String? {
        guard !queuedItemUuids.isEmpty else { return nil }
        let uuid = queuedItemUuids.removeFirst()
        queuedSet.remove(uuid)
        return uuid
    }

    private func classifyAndStore(item: InboxItem, excludedAtomUUIDs: [String]) async {
        var excluded = excludedAtomUUIDs
        if let sourceAtomUuid = sourceAtomUuid(of: item) {
            excluded.append(sourceAtomUuid)
        }

        let result = await InboxClassificationEngine.shared.classify(
            text: item.rawText,
            source: item.source,
            excludedAtomUUIDs: excluded,
            preferredTitle: item.title
        )

        do {
            try await inboxRepo.updateClassification(
                uuid: item.uuid,
                classification: result.classification,
                confidence: result.confidence,
                title: result.title,
                mergeTargetUuid: result.mergeTarget?.atomUuid,
                mergeTargetTitle: result.mergeTarget?.atomTitle,
                mergeTargetType: result.mergeTarget?.atomType,
                mergePreview: result.mergeTarget?.preview,
                placeThinkspaceId: result.placeTarget?.thinkspaceId,
                placeThinkspaceName: result.placeTarget?.thinkspaceName,
                placeAtomType: result.placeTarget?.suggestedAtomType,
                recommendations: result.recommendationBundle.encodedJSONString,
                primaryRouteKind: result.recommendationBundle.primaryRecommendation?.kind.rawValue,
                destinationPath: result.recommendationBundle.primaryRecommendation?.destinationPath,
                rationale: result.recommendationBundle.primaryRecommendation?.rationale,
                placementPlanSummary: result.recommendationBundle.primaryRecommendation?.placementPlan?.summary
            )
        } catch {
            print("⚠️ [InboxIngest] Failed to store classification for \(item.uuid): \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxIngestService.classifyAndStore", detail: "classification store failed for \(item.uuid): \(error.localizedDescription)")
        }
    }

    // MARK: - Launch reconciliation

    /// Run once at startup: drain stuck `pending` items through the queue and
    /// dismiss captures that another system already turned into atoms (the
    /// client-idea double-entries). "Classifying" can no longer be permanent.
    ///
    /// Auto-dismissal requires either provenance (`sourceCaptureUuid` in the
    /// atom's metadata pointing back at this capture) or an exact normalized
    /// match with ≥ 6 tokens on an atom created within the last 7 days —
    /// the old any-text/14-day rule false-positively killed real captures.
    func reconcileOnLaunch() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let active = try await self.inboxRepo.fetchActive()
                guard !active.isEmpty else { return }

                let recentAtoms = await self.recentUserAtoms(within: self.consumedWindowAtReconcile)
                let textMatchCutoff = Date().addingTimeInterval(-7 * 24 * 3600)

                var dismissed = 0
                for item in active {
                    if let match = Self.reconcileMatch(for: item, in: recentAtoms, textMatchCutoff: textMatchCutoff) {
                        do {
                            try await self.inboxRepo.dismiss(uuid: item.uuid)
                            dismissed += 1
                            print("📥 [InboxIngest] Reconcile.autoDismiss: capture \(item.uuid) → atom \(match.atom.uuid) (\(match.reason)); restorable from Recently dismissed")
                        } catch {
                            print("⚠️ [InboxIngest] Reconcile dismiss failed for \(item.uuid): \(error)")
                            PersistenceHealth.note(.writeFailure, context: "InboxIngestService.reconcileOnLaunch", detail: "dismiss failed: \(error.localizedDescription)")
                        }
                        continue
                    }
                    if item.status == .pending {
                        self.enqueueForClassification(item.uuid)
                    }
                }
                if dismissed > 0 {
                    print("📥 [InboxIngest] Reconcile: dismissed \(dismissed) already-consumed capture(s)")
                }
            } catch {
                print("⚠️ [InboxIngest] Reconcile failed: \(error)")
            }
        }
    }

    /// An atom that proves this capture was already consumed. Provenance wins;
    /// otherwise an exact normalized text match needs ≥ 6 tokens and a young atom.
    private static func reconcileMatch(
        for item: InboxItem,
        in atoms: [Atom],
        textMatchCutoff: Date
    ) -> (atom: Atom, reason: String)? {
        // (a) Provenance: the atom records which capture it was created from.
        let provenanceNeedle = "\"sourceCaptureUuid\":\"\(item.uuid)\""
        if let provenanced = atoms.first(where: { $0.metadata?.contains(provenanceNeedle) == true }) {
            return (provenanced, "provenance")
        }

        // (b) Exact normalized text match — long enough to be unambiguous, recent enough to be causal.
        let key = normalized(item.rawText)
        guard key.split(separator: " ").count >= 6 else { return nil }
        let match = atoms.first { atom in
            guard let created = ISO8601.date(from: atom.createdAt), created >= textMatchCutoff else { return false }
            if let body = atom.body, normalized(body) == key { return true }
            if let title = atom.title, normalized(title) == key { return true }
            return false
        }
        return match.map { ($0, "text match") }
    }

    // MARK: - Lazy taxonomy pass (Stage 3)

    /// Called when the inbox becomes visible. Batches unsorted items through
    /// one taxonomy-teaching Flash call — never per-item, never in the background.
    func runTaxonomyPassIfNeeded() {
        guard Date().timeIntervalSince(lastTaxonomyPassAt) > taxonomyPassThrottle else { return }
        guard taxonomyPassTask == nil else { return }
        lastTaxonomyPassAt = Date()

        taxonomyPassTask = Task { @MainActor [weak self] in
            defer { self?.taxonomyPassTask = nil }
            guard let self else { return }
            do {
                let unsorted = try await self.inboxRepo.fetchUnsorted(limit: self.config.taxonomyPassBatchLimit)
                guard !unsorted.isEmpty else { return }

                let payload = unsorted.map { (uuid: $0.uuid, title: $0.title, text: $0.rawText) }
                let assignments = await InboxRoutingEngine.shared.taxonomyPass(items: payload)
                guard !assignments.isEmpty else { return }

                let itemsByUuid = Dictionary(uniqueKeysWithValues: unsorted.map { ($0.uuid, $0) })
                for assignment in assignments {
                    guard let item = itemsByUuid[assignment.itemUuid] else { continue }
                    let destinationPath = assignment.clusterName.map { "\(assignment.thinkspaceName) › \($0)" }
                        ?? assignment.thinkspaceName
                    do {
                        try await self.inboxRepo.updateClassification(
                            uuid: item.uuid,
                            classification: .place,
                            confidence: self.config.taxonomyPassConfidence,
                            title: item.title,
                            placeThinkspaceId: assignment.thinkspaceId,
                            placeThinkspaceName: assignment.thinkspaceName,
                            placeAtomType: AtomType.note.rawValue,
                            destinationPath: destinationPath,
                            rationale: "Filed by the taxonomy pass — it reads each destination's actual contents before assigning."
                        )
                    } catch {
                        print("⚠️ [InboxIngest] Taxonomy pass store failed for \(item.uuid): \(error)")
                        PersistenceHealth.note(.writeFailure, context: "InboxIngestService.taxonomyPass", detail: "classification store failed for \(item.uuid): \(error.localizedDescription)")
                    }
                }
                print("📥 [InboxIngest] Taxonomy pass placed \(assignments.count)/\(unsorted.count) unsorted item(s)")
            } catch {
                print("⚠️ [InboxIngest] Taxonomy pass failed: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func inboxItemExists(sourceAtomUuid: String) async -> Bool {
        let needle = "\"sourceAtomUuid\":\"\(sourceAtomUuid)\""
        let row = (try? await database.asyncRead { db in
            try Row.fetchOne(
                db,
                sql: "SELECT 1 FROM inbox_items WHERE metadata LIKE ? LIMIT 1",
                arguments: ["%\(needle)%"]
            )
        }) ?? nil
        return row != nil
    }

    /// An existing atom whose content is *identical* to the capture — the
    /// signature of a capture another flow already acted on. This is an
    /// identity check, not similarity: no thresholds, no guessing.
    private func matchingAtom(forText text: String, title: String?, within window: TimeInterval) async -> Atom? {
        let textKey = Self.normalized(text)
        let titleKey = title.map(Self.normalized)
        guard !textKey.isEmpty else { return nil }

        let recent = await recentUserAtoms(within: window)
        return recent.first { atom in
            if let body = atom.body, Self.normalized(body) == textKey { return true }
            if let atomTitle = atom.title {
                let key = Self.normalized(atomTitle)
                if key == textKey { return true }
                if let titleKey, !titleKey.isEmpty, key == titleKey { return true }
            }
            return false
        }
    }

    private func recentUserAtoms(within window: TimeInterval) async -> [Atom] {
        let cutoff = Date().addingTimeInterval(-window)
        let types: [AtomType] = [.note, .idea, .research, .content, .connection, .task]
        let atoms = (try? await atomRepo.fetchAll(types: types)) ?? []
        return atoms.filter { atom in
            guard !atom.isDeleted else { return false }
            guard let created = ISO8601.date(from: atom.createdAt) else { return false }
            return created >= cutoff
        }
    }

    private func sourceAtomUuid(of item: InboxItem) -> String? {
        guard let metadata = item.metadata,
              let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict["sourceAtomUuid"] as? String
    }

    private func mergedMetadata(_ existing: String?, adding fields: [String: String]) -> String? {
        var dict: [String: Any] = [:]
        if let existing,
           let data = existing.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = parsed
        }
        for (key, value) in fields {
            dict[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return existing }
        return String(data: data, encoding: .utf8)
    }

    private static func normalized(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
