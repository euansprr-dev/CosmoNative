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
import Combine

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

    // MARK: - Atlas sweep throttle

    private var lastSweepAt: Date = .distantPast
    private var sweepTask: Task<Void, Never>?
    private let sweepThrottle: TimeInterval = 10 * 60

    /// The retired taxonomy pass's fixed rationale — the provenance mark that
    /// lets the one-time repair find its folder-only filings.
    static let legacyTaxonomyRationale = "Filed by the taxonomy pass — it reads each destination's actual contents before assigning."
    private let sweepRepairFlag = "inbox.atlasSweepRepair.v1"

    // MARK: - Synced-in captures

    private var syncObservationCancellable: AnyCancellable?

    private init() {}

    /// Classification stays owned by this service's queue: captures created on
    /// the iPhone arrive via sync as `.pending` rows written straight into
    /// GRDB (never through `ingest`). Observe the repository and funnel them
    /// into the same queue — idempotent, the drain re-fetches and re-checks
    /// `.pending` before classifying, so stale or duplicate enqueues no-op.
    private func startObservingSyncedCaptures() {
        guard syncObservationCancellable == nil else { return }
        syncObservationCancellable = inboxRepo.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self else { return }
                for item in items where item.status == .pending {
                    self.enqueueForClassification(item.uuid)
                }
            }
    }

    /// One-shot cloud backfill: rows created before the inbox became a synced
    /// domain (July 2026) never went through tracked writes — queue them once
    /// so the iPhone starts populated. Queue rows survive offline; the sync
    /// engine retries until the Supabase tables exist.
    private func backfillCloudSyncIfNeeded() {
        let key = "inboxCloudBackfill_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        Task { @MainActor in
            do {
                for item in try await self.inboxRepo.fetchActive() {
                    await ChangeTracker.shared.trackInsert(table: InboxItem.databaseTableName, entity: item)
                }
                let lanes = try await CaptureDestinationRepository.shared.fetchActive()
                let archived = (try? await CaptureDestinationRepository.shared.fetchArchived()) ?? []
                for lane in lanes + archived {
                    await ChangeTracker.shared.trackInsert(table: CaptureDestination.databaseTableName, entity: lane)
                }
                for capture in try await CapturedItemRepository.shared.fetchRecent(limit: 500) {
                    await ChangeTracker.shared.trackInsert(table: CapturedItem.databaseTableName, entity: capture)
                }
                UserDefaults.standard.set(true, forKey: key)
                print("📥 [InboxIngest] Cloud backfill queued (inbox items, lanes, lane captures)")
            } catch {
                // Flag stays unset — retried on next launch.
                print("⚠️ [InboxIngest] Cloud backfill failed: \(error)")
            }
        }
    }

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
        if capture.preset != nil {
            // The user chose this destination (topic alias) — stamp it so topic
            // inboxes can tell user-routed captures from classifier suggestions.
            metadata = mergedMetadata(metadata, adding: [InboxItem.explicitDestinationMetadataKey: "true"])
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
                // A page scan still owed its LLM transcript classifies as
                // gibberish and locks it in (the transcript upgrade only
                // touches still-pending items). Wait — the transcription
                // worker re-enqueues after the transcript lands, and its
                // attempt cap clears the flag on hopeless pages.
                if await Self.shouldDeferClassification(item: item) {
                    continue
                }
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

    /// Re-enqueue a still-pending item whose deferred classification can now
    /// run — called by the transcription worker when a transcript lands (or
    /// it gives up on a page).
    func reclassifyIfPending(uuid: String) {
        enqueueForClassification(uuid)
    }

    /// A capture that names attachments (`attachmentUUIDs` in metadata, set
    /// by the iPhone) must not classify until every named row has synced in
    /// AND finished (or exhausted) its LLM transcription pass. Rows can land
    /// after their inbox item — classifying early reads the Vision gibberish.
    /// Progress is guaranteed: the worker re-enqueues on completion, and
    /// every sync pull republishes pending items into this queue.
    static func shouldDeferClassification(item: InboxItem) async -> Bool {
        guard let metadata = item.metadata,
              let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expected = dict["attachmentUUIDs"] as? [String], !expected.isEmpty
        else { return false }

        guard let rows = try? await MediaAttachmentRepository.shared.fetch(
            owner: .inboxItem, ownerUUID: item.uuid
        ) else { return true }

        if rows.count < expected.count { return true }
        return rows.contains { row in
            row.metadata?.contains(#""needsLLMPass":true"#) == true
        }
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
        await storeClassification(result, for: item, context: "InboxIngestService.classifyAndStore")
    }

    /// The ONE persistence path for classification results — capture-time and
    /// sweep results store identically (full bundle, route kind, honest
    /// rationale) and share the auto-grow rule.
    private func storeClassification(
        _ result: InboxClassificationEngine.ClassificationResult,
        for item: InboxItem,
        context: String
    ) async {
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
            await autoGrowIfUnmistakable(itemUUID: item.uuid, bundle: result.recommendationBundle)
        } catch {
            print("⚠️ [InboxIngest] Failed to store classification for \(item.uuid): \(error)")
            PersistenceHealth.note(.writeFailure, context: context, detail: "classification store failed for \(item.uuid): \(error.localizedDescription)")
        }
    }

    /// The self-draining path for thought captures: an unmistakable
    /// `feedSeedling` primary applies itself. Mass accrues automatically;
    /// the receipt lands in history ("Grew …") with full undo; the queue
    /// only holds captures that actually need a human decision. Feeding is
    /// the ONLY auto-applied verb — it creates no atom, touches no canvas,
    /// and never names anything.
    private func autoGrowIfUnmistakable(itemUUID: String, bundle: InboxRecommendationBundle) async {
        guard let primary = bundle.primaryRecommendation,
              primary.kind == .feedSeedling,
              primary.confidence >= InboxRoutingConfig.shared.seedlingAutoGrowMinConfidence,
              let fresh = try? await inboxRepo.fetch(uuid: itemUUID),
              fresh.status == .classified, !fresh.isDeleted else { return }
        do {
            _ = try await InboxActionExecutor.shared.executeFeedSeedling(item: fresh, recommendation: primary)
        } catch {
            // The suggestion pill is still there — the user can grow it by hand.
            print("⚠️ [InboxIngest] Auto-grow failed for \(itemUUID): \(error)")
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
        startObservingSyncedCaptures()
        backfillCloudSyncIfNeeded()
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

    // MARK: - The Atlas sweep (Stage 3)

    /// Called when the inbox becomes visible. Batches unsorted items through
    /// ONE Atlas call speaking the same move grammar as capture-time routing
    /// (concepts, questions, material, folders) — never per-item, never in
    /// the background. Captures the sweep abstains on stay honestly unsorted
    /// and are re-read against the atlas as it grows.
    func runAtlasSweepIfNeeded() {
        guard Date().timeIntervalSince(lastSweepAt) > sweepThrottle else { return }
        guard sweepTask == nil else { return }
        lastSweepAt = Date()

        sweepTask = Task { @MainActor [weak self] in
            defer { self?.sweepTask = nil }
            guard let self else { return }
            await self.repairLegacyTaxonomyRowsIfNeeded()
            do {
                let unsorted = try await self.inboxRepo.fetchUnsorted(limit: self.config.sweepBatchLimit)
                guard !unsorted.isEmpty else { return }

                let payload = unsorted.map { (uuid: $0.uuid, title: $0.title, text: $0.rawText) }
                let results = await InboxClassificationEngine.shared.sweepClassify(items: payload)
                guard !results.isEmpty else { return }

                for item in unsorted {
                    guard let result = results[item.uuid] else { continue }
                    await self.storeClassification(result, for: item, context: "InboxIngestService.atlasSweep")
                }
                print("📥 [InboxIngest] Atlas sweep routed \(results.count)/\(unsorted.count) unsorted item(s)")
            } catch {
                print("⚠️ [InboxIngest] Atlas sweep failed: \(error)")
            }
        }
    }

    /// One-time repair (July 2026): the retired folders-only taxonomy pass
    /// stamped every filing with one fixed rationale. Those suggestion-only
    /// rows reset to honest `unsorted`, so the sweeps re-route them under the
    /// full grammar. Anything the user already acted on is untouched — both
    /// here (status filter) and in updateClassification's own guard.
    private func repairLegacyTaxonomyRowsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: sweepRepairFlag) else { return }
        do {
            let filed = try await inboxRepo.fetchClassified(
                rationale: Self.legacyTaxonomyRationale,
                limit: 500
            )
            for item in filed {
                try await inboxRepo.updateClassification(
                    uuid: item.uuid,
                    classification: .unsorted,
                    confidence: 0,
                    title: item.title
                )
            }
            UserDefaults.standard.set(true, forKey: sweepRepairFlag)
            if !filed.isEmpty {
                print("📥 [InboxIngest] Sweep repair reset \(filed.count) taxonomy-filed row(s) for re-routing")
            }
        } catch {
            // Flag stays unset — the next sweep retries the repair.
            print("⚠️ [InboxIngest] Sweep repair failed: \(error)")
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
