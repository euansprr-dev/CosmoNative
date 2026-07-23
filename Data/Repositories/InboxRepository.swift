// CosmoOS/Data/Repositories/InboxRepository.swift
// Repository for Smart Triage Inbox items with GRDB observation
// March 2026

import GRDB
import Foundation
import Combine

@MainActor
class InboxRepository: ObservableObject {
    static let shared = InboxRepository()

    private let database = CosmoDatabase.shared

    @Published var items: [InboxItem] = []
    @Published var unreadCount: Int = 0

    private var itemsObservationCancellable: AnyCancellable?
    private var unreadObservationCancellable: AnyCancellable?

    /// Re-subscription backoff after a ValueObservation completes with failure —
    /// one decode error must not permanently freeze the inbox.
    private let observationRetryBackoffs: [TimeInterval] = [1, 5, 30]

    private init() {
        observeItems()
        observeUnreadCount()
    }

    // MARK: - Observation

    private func observeItems(retryAttempt: Int = 0) {
        guard database.isReady else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.observeItems(retryAttempt: retryAttempt)
            }
            return
        }

        itemsObservationCancellable = database.observe { db in
            try InboxItem
                .filter(Column("status") == InboxItemStatus.pending.rawValue ||
                        Column("status") == InboxItemStatus.classified.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    print("⚠️ [InboxRepository] Observation failed: \(error)")
                    PersistenceHealth.note(.decodeFailure, context: "InboxRepository.observeItems", detail: error.localizedDescription)
                    self?.scheduleObservationRetry(retryAttempt: retryAttempt) { repo, attempt in
                        repo.observeItems(retryAttempt: attempt)
                    }
                }
            },
            receiveValue: { [weak self] items in
                self?.items = items
            }
        )
    }

    private func observeUnreadCount(retryAttempt: Int = 0) {
        guard database.isReady else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.observeUnreadCount(retryAttempt: retryAttempt)
            }
            return
        }

        unreadObservationCancellable = database.observe { db in
            try InboxItem
                .filter(Column("isRead") == false)
                .filter(Column("status") == InboxItemStatus.pending.rawValue ||
                        Column("status") == InboxItemStatus.classified.rawValue)
                .fetchCount(db)
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                if case .failure = completion {
                    self?.scheduleObservationRetry(retryAttempt: retryAttempt) { repo, attempt in
                        repo.observeUnreadCount(retryAttempt: attempt)
                    }
                }
            },
            receiveValue: { [weak self] count in
                self?.unreadCount = count
            }
        )
    }

    private func scheduleObservationRetry(retryAttempt: Int, resubscribe: @escaping @MainActor (InboxRepository, Int) -> Void) {
        let backoff = observationRetryBackoffs[min(retryAttempt, observationRetryBackoffs.count - 1)]
        DispatchQueue.main.asyncAfter(deadline: .now() + backoff) { [weak self] in
            guard let self else { return }
            resubscribe(self, retryAttempt + 1)
        }
    }

    // MARK: - Create

    @discardableResult
    func create(_ item: InboxItem) async throws -> InboxItem {
        let saved = try await database.asyncWrite { db in
            var mutable = item
            mutable.syncUpdatedAt = ISO8601.string(from: Date())
            try mutable.insert(db)
            return mutable
        }
        await ChangeTracker.shared.trackInsert(table: InboxItem.databaseTableName, entity: saved)
        return saved
    }

    /// Version-bump + stamp shared by every tracked mutation: the write and
    /// the ChangeTracker call must carry the SAME post-bump `_local_version`
    /// so push bookkeeping can mark the queue row synced (the Atom pattern).
    private nonisolated static func prepareTrackedUpdate(_ item: inout InboxItem) {
        item.localVersion += 1
        item.syncUpdatedAt = ISO8601.string(from: Date())
    }

    private func track(_ item: InboxItem?) async {
        guard let item else { return }
        await ChangeTracker.shared.trackUpdate(
            table: InboxItem.databaseTableName,
            entity: item,
            skipVersionIncrement: true
        )
    }

    // MARK: - Update Classification

    func updateClassification(
        uuid: String,
        classification: InboxClassification,
        confidence: Double,
        title: String?,
        mergeTargetUuid: String? = nil,
        mergeTargetTitle: String? = nil,
        mergeTargetType: String? = nil,
        mergePreview: String? = nil,
        placeThinkspaceId: String? = nil,
        placeThinkspaceName: String? = nil,
        placeAtomType: String? = nil,
        recommendations: String? = nil,
        primaryRouteKind: String? = nil,
        destinationPath: String? = nil,
        rationale: String? = nil,
        placementPlanSummary: String? = nil
    ) async throws {
        let updated = try await database.asyncWrite { db -> InboxItem? in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            // Never resurrect a dismissed/actioned item — a slow classifier
            // result landing after the user triaged must not clobber status.
            guard item.status == .pending || item.status == .classified else { return nil }
            item.classification = classification
            item.confidence = confidence
            item.title = title ?? item.title
            item.mergeTargetUuid = mergeTargetUuid
            item.mergeTargetTitle = mergeTargetTitle
            item.mergeTargetType = mergeTargetType
            item.mergePreview = mergePreview
            item.placeThinkspaceId = placeThinkspaceId
            item.placeThinkspaceName = placeThinkspaceName
            item.placeAtomType = placeAtomType
            item.recommendations = recommendations
            item.primaryRouteKind = primaryRouteKind
            item.destinationPath = destinationPath
            item.rationale = rationale
            item.placementPlanSummary = placementPlanSummary
            item.status = .classified
            item.classifiedAt = ISO8601.string(from: Date())
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            return item
        }
        await track(updated)
    }

    /// Physical capture: replace a pending capture's draft text with the
    /// finished handwriting transcript (the iPhone saved before its LLM pass
    /// ran, or had no key). Pre-classification only — a classified or triaged
    /// item's text is never rewritten under the user.
    func upgradeRawText(uuid: String, to newText: String) async throws {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let updated = try await database.asyncWrite { db -> InboxItem? in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            guard item.status == .pending else { return nil }
            item.rawText = trimmed
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            return item
        }
        await track(updated)
    }

    /// The user corrected a capture's text in the inspector. Active-queue
    /// items only — a triaged/dismissed row's text is never rewritten under
    /// its own history. Unlike `upgradeRawText` (a pre-classification scan
    /// transcript swap) this also allows classified rows: fixing a typo must
    /// not require un-classifying first. The Mac's suggestion is left intact.
    func editRawText(uuid: String, to newText: String) async throws {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let updated = try await database.asyncWrite { db -> InboxItem? in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            guard item.status == .pending || item.status == .classified else { return nil }
            guard item.rawText != trimmed else { return nil }
            item.rawText = trimmed
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            return item
        }
        await track(updated)
    }

    // MARK: - Actions

    func markActioned(uuid: String) async throws {
        let updated = try await database.asyncWrite { db -> InboxItem? in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            item.status = .actioned
            item.actionedAt = ISO8601.string(from: Date())
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            return item
        }
        await track(updated)
    }

    func dismiss(uuid: String) async throws {
        let updated = try await database.asyncWrite { db -> InboxItem? in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            item.status = .dismissed
            item.actionedAt = ISO8601.string(from: Date())
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            return item
        }
        await track(updated)
    }

    func markRead(uuid: String) async throws {
        let updated = try await database.asyncWrite { db -> InboxItem? in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            item.isRead = true
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            return item
        }
        await track(updated)
    }

    /// User confirmed a suggested topic placement: stamp the destination as
    /// explicit so the deep dive's inbox owns it from now on.
    func confirmPlacement(uuid: String, thinkspaceId: String, thinkspaceName: String?) async throws {
        let updated = try await database.asyncWrite { db -> InboxItem? in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            guard item.status == .pending || item.status == .classified else { return nil }
            item.placeThinkspaceId = thinkspaceId
            item.placeThinkspaceName = thinkspaceName ?? item.placeThinkspaceName
            item.classification = .place
            item.status = .classified
            Self.mergeMetadata(&item, fields: [InboxItem.explicitDestinationMetadataKey: "true"])
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            return item
        }
        await track(updated)
    }

    /// User removed a capture from a topic's inbox: drop the placement if it
    /// pointed there and suppress the topic so suggestions don't resurface it.
    /// The capture itself stays alive in the main inbox.
    func removeFromTopic(uuid: String, topicUUID: String) async throws {
        let updated = try await database.asyncWrite { db -> InboxItem? in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            if item.placeThinkspaceId == topicUUID {
                item.placeThinkspaceId = nil
                item.placeThinkspaceName = nil
                // A .place with no target would strand the main-inbox action;
                // without a recommendation bundle the item is honestly unsorted.
                if item.classification == .place && item.recommendations == nil {
                    item.classification = .unsorted
                }
                var metadata = item.metadataDictionary
                metadata.removeValue(forKey: InboxItem.explicitDestinationMetadataKey)
                if let data = try? JSONSerialization.data(withJSONObject: metadata),
                   let encoded = String(data: data, encoding: .utf8) {
                    item.metadata = encoded
                }
            }
            var suppressed = (item.metadataDictionary[InboxItem.suppressedTopicsMetadataKey] as? String)?
                .split(separator: ",").map(String.init) ?? []
            if !suppressed.contains(topicUUID) {
                suppressed.append(topicUUID)
            }
            Self.mergeMetadata(&item, fields: [InboxItem.suppressedTopicsMetadataKey: suppressed.joined(separator: ",")])
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            return item
        }
        await track(updated)
    }

    private nonisolated static func mergeMetadata(_ item: inout InboxItem, fields: [String: String]) {
        var dict = item.metadataDictionary
        for (key, value) in fields {
            dict[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let merged = String(data: data, encoding: .utf8) else { return }
        item.metadata = merged
    }

    /// Merge keys into the item's JSON metadata column — used to persist a
    /// durable undo source (e.g. the pre-merge target body) before a merge.
    func updateMetadata(uuid: String, merging fields: [String: String]) async throws {
        let updated = try await database.asyncWrite { db -> InboxItem? in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            var dict: [String: Any] = [:]
            if let existing = item.metadata,
               let data = existing.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dict = parsed
            }
            for (key, value) in fields {
                dict[key] = value
            }
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let merged = String(data: data, encoding: .utf8) else { return nil }
            item.metadata = merged
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            return item
        }
        await track(updated)
    }

    func fetch(uuid: String) async throws -> InboxItem? {
        try await database.asyncRead { db in
            try InboxItem
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }
    }

    func restore(_ item: InboxItem) async throws {
        let (saved, wasInsert) = try await database.asyncWrite { db -> (InboxItem, Bool) in
            if var existing = try InboxItem.filter(Column("uuid") == item.uuid).fetchOne(db) {
                // Carry the LIVE row's sync bookkeeping — the caller's snapshot
                // may hold a stale _local_version from before later triage writes.
                var restored = item
                restored.id = existing.id
                restored.localVersion = existing.localVersion
                restored.serverVersion = existing.serverVersion
                restored.syncVersion = existing.syncVersion
                Self.prepareTrackedUpdate(&restored)
                try restored.update(db)
                existing = restored
                return (existing, false)
            } else {
                var mutable = item
                mutable.syncUpdatedAt = ISO8601.string(from: Date())
                try mutable.insert(db)
                return (mutable, true)
            }
        }
        if wasInsert {
            await ChangeTracker.shared.trackInsert(table: InboxItem.databaseTableName, entity: saved)
        } else {
            await track(saved)
        }
    }

    // MARK: - Queries

    func fetchActive() async throws -> [InboxItem] {
        try await database.asyncRead { db in
            try InboxItem
                .filter(Column("status") == InboxItemStatus.pending.rawValue ||
                        Column("status") == InboxItemStatus.classified.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Items still awaiting classification — drained by InboxIngestService's
    /// queue on launch so "classifying" can never be a permanent state.
    func fetchPending() async throws -> [InboxItem] {
        try await database.asyncRead { db in
            try InboxItem
                .filter(Column("status") == InboxItemStatus.pending.rawValue)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    /// Suggestion-only rows the retired folders-only taxonomy pass filed,
    /// identified by its fixed rationale string. Fetched once by the first
    /// Atlas sweep's repair so those filings re-enter the full move grammar.
    /// (The status filter keeps anything the user already acted on untouched.)
    func fetchClassified(rationale: String, limit: Int) async throws -> [InboxItem] {
        try await database.asyncRead { db in
            try InboxItem
                .filter(Column("status") == InboxItemStatus.classified.rawValue)
                .filter(Column("rationale") == rationale)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Honestly-unsorted items — candidates for the batched Atlas sweep
    /// that runs when the inbox becomes visible.
    func fetchUnsorted(limit: Int) async throws -> [InboxItem] {
        try await database.asyncRead { db in
            try InboxItem
                .filter(Column("status") == InboxItemStatus.classified.rawValue)
                .filter(Column("classification") == InboxClassification.unsorted.rawValue ||
                        Column("classification") == InboxClassification.new.rawValue ||
                        Column("classification") == nil)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func countUnread() async throws -> Int {
        try await database.asyncRead { db in
            try InboxItem
                .filter(Column("isRead") == false)
                .filter(Column("status") == InboxItemStatus.pending.rawValue ||
                        Column("status") == InboxItemStatus.classified.rawValue)
                .fetchCount(db)
        }
    }

    /// Fetch recently triaged items for empty state display
    func fetchRecentHistory(limit: Int = 3) async throws -> [InboxItem] {
        try await database.asyncRead { db in
            try InboxItem
                .filter(Column("status") == InboxItemStatus.actioned.rawValue ||
                        Column("status") == InboxItemStatus.dismissed.rawValue)
                .order(Column("actionedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Count items triaged this week
    func countTriagedThisWeek() async throws -> Int {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let weekStartStr = ISO8601.string(from: weekStart)
        return try await database.asyncRead { db in
            try InboxItem
                .filter(Column("status") == InboxItemStatus.actioned.rawValue)
                .filter(Column("actionedAt") >= weekStartStr)
                .fetchCount(db)
        }
    }

    /// Archive old actioned/dismissed items (housekeeping).
    ///
    /// Data-safety pass, June 2026: this used to hard-DELETE rows — pruning was
    /// permanent and unrecoverable. It now exports the rows to a JSON archive on
    /// disk BEFORE deleting, so housekeeping can never destroy the only copy of
    /// a capture. Since the inbox became a synced domain (July 2026), each pruned
    /// row is also tracked as a DELETE so the cloud copy is tombstoned and other
    /// devices drop it too. (Currently has no callers.)
    func pruneOldItems(olderThanDays days: Int = 30) async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let cutoffStr = ISO8601.string(from: cutoff)

        let prunable = try await database.asyncRead { db in
            try InboxItem
                .filter(Column("status") == InboxItemStatus.actioned.rawValue ||
                        Column("status") == InboxItemStatus.dismissed.rawValue)
                .filter(Column("actionedAt") < cutoffStr)
                .fetchAll(db)
        }
        guard !prunable.isEmpty else { return }

        // Archive first — refuse to delete anything that didn't make it to disk.
        let archiveDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cosmo")
            .appendingPathComponent("inbox-archive")
        try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let archiveURL = archiveDir.appendingPathComponent("inbox-pruned-\(formatter.string(from: Date())).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(prunable).write(to: archiveURL)

        let archivedUuids = prunable.map(\.uuid)
        try await database.asyncWrite { db in
            try InboxItem
                .filter(archivedUuids.contains(Column("uuid")))
                .deleteAll(db)
        }
        for item in prunable {
            await ChangeTracker.shared.trackDelete(
                table: InboxItem.databaseTableName,
                uuid: item.uuid,
                rowId: item.id
            )
        }
        print("🗄️ Inbox pruning archived \(prunable.count) item(s) to \(archiveURL.lastPathComponent)")
    }
}
