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
        try await database.asyncWrite { db in
            let mutable = item
            try mutable.insert(db)
            return mutable
        }
    }

    func fetch(uuid: String) async throws -> CapturedItem? {
        try await database.asyncRead { db in
            try CapturedItem
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
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
        try await database.asyncWrite { db in
            guard var item = try CapturedItem
                .filter(Column("uuid") == uuid)
                .fetchOne(db) else { return }

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
            item.updatedAt = ISO8601DateFormatter().string(from: Date())
            try item.update(db)
        }
    }

    func attachMedia(capturedItemId: String, mediaIds: [String]) async throws {
        try await database.asyncWrite { db in
            guard var item = try CapturedItem
                .filter(Column("uuid") == capturedItemId)
                .fetchOne(db) else { return }
            let merged = Array(NSOrderedSet(array: item.mediaAttachmentIds + mediaIds)) as? [String] ?? item.mediaAttachmentIds + mediaIds
            item.mediaAttachmentIdsJSON = encodeCapturedItemArray(merged)
            item.updatedAt = ISO8601DateFormatter().string(from: Date())
            try item.update(db)
        }
    }
}

private func encodeCapturedItemArray(_ value: [String]) -> String {
    guard let data = try? JSONEncoder().encode(value) else { return "[]" }
    return String(data: data, encoding: .utf8) ?? "[]"
}
