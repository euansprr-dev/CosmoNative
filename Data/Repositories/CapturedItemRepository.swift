// CosmoOS/Data/Repositories/CapturedItemRepository.swift
// Durable intake records for raw captures and their routing lifecycle.

import Combine
import Foundation
import GRDB

@MainActor
final class CapturedItemRepository: ObservableObject {
    static let shared = CapturedItemRepository()

    @Published private(set) var recentItems: [CapturedItem] = []

    private let database = CosmoDatabase.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeRecentItems()
    }

    private func observeRecentItems() {
        guard database.isReady else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.observeRecentItems()
            }
            return
        }

        database.observe { db in
            try CapturedItem
                .filter(Column("status") != CapturedItemStatus.archived.rawValue)
                .order(Column("createdAt").desc)
                .limit(250)
                .fetchAll(db)
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("CapturedItemRepository observation failed: \(error)")
                }
            },
            receiveValue: { [weak self] items in
                self?.recentItems = items
            }
        )
        .store(in: &cancellables)
    }

    @discardableResult
    func create(_ item: CapturedItem) async throws -> CapturedItem {
        let saved = try await database.asyncWrite { db in
            var mutable = item
            mutable.syncUpdatedAt = ISO8601.string(from: Date())
            try mutable.insert(db)
            try CaptureSyncOutbox.enqueue(db, table: "captured_items", uuid: mutable.uuid)
            return mutable
        }
        await ChangeTracker.shared.trackInsert(table: CapturedItem.databaseTableName, entity: saved)
        return saved
    }

    /// Version-bump + stamp shared by tracked mutations (the Atom pattern:
    /// the write and the ChangeTracker payload carry the same post-bump
    /// `_local_version`, so push bookkeeping can mark the queue row synced).
    private nonisolated static func prepareTrackedUpdate(_ item: inout CapturedItem) {
        item.localVersion += 1
        let now = ISO8601.string(from: Date())
        item.updatedAt = now
        item.syncUpdatedAt = now
    }

    private func track(_ item: CapturedItem?) async {
        guard let item else { return }
        await ChangeTracker.shared.trackUpdate(
            table: CapturedItem.databaseTableName,
            entity: item,
            skipVersionIncrement: true
        )
    }

    func fetch(uuid: String) async throws -> CapturedItem? {
        try await database.asyncRead { db in
            try CapturedItem
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }
    }

    /// Newest captures across all lanes — used by the one-shot cloud backfill.
    func fetchRecent(limit: Int = 500) async throws -> [CapturedItem] {
        try await database.asyncRead { db in
            try CapturedItem
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetch(destinationId: String?, limit: Int = 100) async throws -> [CapturedItem] {
        try await database.asyncRead { db in
            var request = CapturedItem
                .filter(Column("status") != CapturedItemStatus.archived.rawValue)

            if let destinationId {
                request = request.filter(Column("captureDestinationId") == destinationId)
            } else {
                request = request.filter(Column("captureDestinationId") == nil)
            }

            return try request
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func updateRouting(
        uuid: String,
        destinationId: String?,
        parsedCommand: String?,
        parsedIntent: String?,
        confidence: Double,
        status: CapturedItemStatus,
        createdObjectIds: [String] = [],
        parentDeepDiveId: String? = nil,
        parentInquirySessionId: String? = nil,
        parentQuestionId: String? = nil,
        parentProjectId: String? = nil
    ) async throws {
        let updated = try await database.asyncWrite { db -> CapturedItem? in
            guard var item = try CapturedItem
                .filter(Column("uuid") == uuid)
                .fetchOne(db) else { return nil }

            item.captureDestinationId = destinationId
            item.parsedCommand = parsedCommand
            item.parsedIntent = parsedIntent
            item.routingConfidence = confidence
            item.status = status
            item.createdObjectIdsJSON = encodeCapturedItemArray(createdObjectIds)
            item.parentDeepDiveId = parentDeepDiveId
            item.parentInquirySessionId = parentInquirySessionId
            item.parentQuestionId = parentQuestionId
            item.parentProjectId = parentProjectId
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            try CaptureSyncOutbox.enqueue(db, table: "captured_items", uuid: item.uuid)
            return item
        }
        await track(updated)
    }

    /// The user corrected a lane capture's text. Writes `cleanText` — the
    /// display source every lane row (both platforms) reads first — leaving
    /// `rawText` as the original capture's provenance.
    func editText(uuid: String, to newText: String) async throws {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let updated = try await database.asyncWrite { db -> CapturedItem? in
            guard var item = try CapturedItem.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            guard item.cleanText != trimmed else { return nil }
            item.cleanText = trimmed
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            try CaptureSyncOutbox.enqueue(db, table: "captured_items", uuid: item.uuid)
            return item
        }
        await track(updated)
    }

    func attachMedia(capturedItemId: String, mediaIds: [String]) async throws {
        let updated = try await database.asyncWrite { db -> CapturedItem? in
            guard var item = try CapturedItem
                .filter(Column("uuid") == capturedItemId)
                .fetchOne(db) else { return nil }
            let merged = Array(NSOrderedSet(array: item.mediaAttachmentIds + mediaIds)) as? [String] ?? item.mediaAttachmentIds + mediaIds
            item.mediaAttachmentIdsJSON = encodeCapturedItemArray(merged)
            Self.prepareTrackedUpdate(&item)
            try item.update(db)
            try CaptureSyncOutbox.enqueue(db, table: "captured_items", uuid: item.uuid)
            return item
        }
        await track(updated)
    }
}

private func encodeCapturedItemArray(_ value: [String]) -> String {
    guard let data = try? JSONEncoder().encode(value) else { return "[]" }
    return String(data: data, encoding: .utf8) ?? "[]"
}
