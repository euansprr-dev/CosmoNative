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

    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeItems()
        observeUnreadCount()
    }

    // MARK: - Observation

    private func observeItems() {
        guard database.isReady else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.observeItems()
            }
            return
        }

        database.observe { db in
            try InboxItem
                .filter(Column("status") == InboxItemStatus.pending.rawValue ||
                        Column("status") == InboxItemStatus.classified.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("⚠️ [InboxRepository] Observation failed: \(error)")
                }
            },
            receiveValue: { [weak self] items in
                self?.items = items
            }
        )
        .store(in: &cancellables)
    }

    private func observeUnreadCount() {
        guard database.isReady else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.observeUnreadCount()
            }
            return
        }

        database.observe { db in
            try InboxItem
                .filter(Column("isRead") == false)
                .filter(Column("status") == InboxItemStatus.pending.rawValue ||
                        Column("status") == InboxItemStatus.classified.rawValue)
                .fetchCount(db)
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { _ in },
            receiveValue: { [weak self] count in
                self?.unreadCount = count
            }
        )
        .store(in: &cancellables)
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
        placeAtomType: String? = nil
    ) async throws {
        try await database.asyncWrite { db in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return }
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
            item.status = .classified
            item.classifiedAt = ISO8601DateFormatter().string(from: Date())
            try item.update(db)
        }
    }

    // MARK: - Actions

    func markActioned(uuid: String) async throws {
        try await database.asyncWrite { db in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return }
            item.status = .actioned
            item.actionedAt = ISO8601DateFormatter().string(from: Date())
            try item.update(db)
        }
    }

    func dismiss(uuid: String) async throws {
        try await database.asyncWrite { db in
            guard var item = try InboxItem.filter(Column("uuid") == uuid).fetchOne(db) else { return }
            item.status = .dismissed
            item.actionedAt = ISO8601DateFormatter().string(from: Date())
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

    func countUnread() async throws -> Int {
        try await database.asyncRead { db in
            try InboxItem
                .filter(Column("isRead") == false)
                .filter(Column("status") == InboxItemStatus.pending.rawValue ||
                        Column("status") == InboxItemStatus.classified.rawValue)
                .fetchCount(db)
        }
    }

    /// Delete old actioned/dismissed items (housekeeping)
    func pruneOldItems(olderThanDays days: Int = 30) async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let cutoffStr = ISO8601DateFormatter().string(from: cutoff)
        try await database.asyncWrite { db in
            try InboxItem
                .filter(Column("status") == InboxItemStatus.actioned.rawValue ||
                        Column("status") == InboxItemStatus.dismissed.rawValue)
                .filter(Column("actionedAt") < cutoffStr)
                .deleteAll(db)
        }
    }
}
