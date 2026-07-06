// CosmoOS/Data/Repositories/CaptureRequestRepository.swift
// Scan-request records (the Mac → iPhone camera relay) with tracked-write
// semantics — requests are born here, the phone mutates status/pageCount,
// both directions ride the standard sync pipeline.

import Foundation
import GRDB

@MainActor
final class CaptureRequestRepository {
    static let shared = CaptureRequestRepository()

    private let database = CosmoDatabase.shared
    private init() {}

    @discardableResult
    func create(_ request: CaptureRequest) async throws -> CaptureRequest {
        let saved = try await database.asyncWrite { db in
            var mutable = request
            mutable.syncUpdatedAt = ISO8601.string(from: Date())
            try mutable.insert(db)
            mutable.id = db.lastInsertedRowID
            return mutable
        }
        await ChangeTracker.shared.trackInsert(table: CaptureRequest.databaseTableName, entity: saved)
        return saved
    }

    func fetch(uuid: String) async throws -> CaptureRequest? {
        try await database.asyncRead { db in
            try CaptureRequest.filter(Column("uuid") == uuid).fetchOne(db)
        }
    }

    @discardableResult
    func trackedMutation(
        uuid: String,
        _ mutate: @Sendable @escaping (inout CaptureRequest) -> Bool
    ) async throws -> CaptureRequest? {
        let updated = try await database.asyncWrite { db -> CaptureRequest? in
            guard var request = try CaptureRequest.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            guard mutate(&request) else { return nil }
            request.localVersion += 1
            request.syncUpdatedAt = ISO8601.string(from: Date())
            try request.update(db)
            return request
        }
        if let updated {
            await ChangeTracker.shared.trackUpdate(
                table: CaptureRequest.databaseTableName,
                entity: updated,
                skipVersionIncrement: true
            )
        }
        return updated
    }

    func cancel(uuid: String) async throws {
        _ = try await trackedMutation(uuid: uuid) { request in
            guard request.status == .pending || request.status == .claimed || request.status == .streaming else { return false }
            request.status = .cancelled
            return true
        }
    }
}
