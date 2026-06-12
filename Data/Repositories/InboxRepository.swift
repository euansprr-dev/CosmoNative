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
        try await database.asyncWrite { db in
            var mutable = item
            try mutable.insert(db)
            return mutable
        }
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
        try await database.asyncWrite { db in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return }
            // Never resurrect a dismissed/actioned item — a slow classifier
            // result landing after the user triaged must not clobber status.
            guard item.status == .pending || item.status == .classified else { return }
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
            try item.update(db)
        }
    }

    // MARK: - Actions

    func markActioned(uuid: String) async throws {
        try await database.asyncWrite { db in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return }
            item.status = .actioned
            item.actionedAt = ISO8601.string(from: Date())
            try item.update(db)
        }
    }

    func dismiss(uuid: String) async throws {
        try await database.asyncWrite { db in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return }
            item.status = .dismissed
            item.actionedAt = ISO8601.string(from: Date())
            try item.update(db)
        }
    }

    func markRead(uuid: String) async throws {
        try await database.asyncWrite { db in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return }
            item.isRead = true
            try item.update(db)
        }
    }

    /// Merge keys into the item's JSON metadata column — used to persist a
    /// durable undo source (e.g. the pre-merge target body) before a merge.
    func updateMetadata(uuid: String, merging fields: [String: String]) async throws {
        try await database.asyncWrite { db in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return }
            var dict: [String: Any] = [:]
            if let existing = item.metadata,
               let data = existing.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dict = parsed
            }
            for (key, value) in fields {
                dict[key] = value
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let merged = String(data: data, encoding: .utf8) {
                item.metadata = merged
                try item.update(db)
            }
        }
    }

    func fetch(uuid: String) async throws -> InboxItem? {
        try await database.asyncRead { db in
            try InboxItem
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }
    }

    func restore(_ item: InboxItem) async throws {
        try await database.asyncWrite { db in
            if try InboxItem.filter(Column("uuid") == item.uuid).fetchOne(db) != nil {
                try item.update(db)
            } else {
                var mutable = item
                try mutable.insert(db)
            }
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

    /// Honestly-unsorted items — candidates for the lazy LLM taxonomy pass
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
    /// Data-safety pass, June 2026: this used to hard-DELETE rows — inbox items
    /// aren't synced, so pruning was permanent and unrecoverable. It now exports
    /// the rows to a JSON archive on disk BEFORE deleting, so housekeeping can
    /// never destroy the only copy of a capture. (Currently has no callers.)
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
        print("🗄️ Inbox pruning archived \(prunable.count) item(s) to \(archiveURL.lastPathComponent)")
    }
}
