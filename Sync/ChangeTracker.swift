// CosmoOS/Sync/ChangeTracker.swift
// Tracks local changes and queues them for invisible sync
// UI NEVER blocks - changes are tracked asynchronously

import Foundation
import GRDB

@MainActor
class ChangeTracker: ObservableObject {
    static let shared = ChangeTracker()

    private let database = CosmoDatabase.shared

    private init() {}

    // MARK: - Track Insert
    func trackInsert<T: Syncable>(
        table: String,
        entity: T
    ) async {
        guard let uuid = entity.getUUID() else {
            print("⚠️ Cannot track entity without UUID")
            return
        }

        // Mark as pending locally
        await markAsPending(table: table, uuid: uuid)

        // Add to sync queue
        await queueChange(
            uuid: uuid,
            table: table,
            rowId: entity.id,
            operation: "INSERT",
            entity: entity
        )
    }

    // MARK: - Track Update
    func trackUpdate<T: Syncable>(
        table: String,
        entity: T,
        changedFields: [String]? = nil
    ) async {
        guard let uuid = entity.getUUID() else { return }

        // Increment local version
        await incrementLocalVersion(table: table, uuid: uuid)

        // Mark as pending
        await markAsPending(table: table, uuid: uuid)

        // Add to sync queue
        await queueChange(
            uuid: uuid,
            table: table,
            rowId: entity.id,
            operation: "UPDATE",
            entity: entity
        )
    }

    // MARK: - Track Delete
    func trackDelete(
        table: String,
        uuid: String,
        rowId: Int64?
    ) async {
        // Add to sync queue
        await queueChange(
            uuid: uuid,
            table: table,
            rowId: rowId,
            operation: "DELETE",
            entity: nil as EmptyEntity?
        )
    }

    // MARK: - Queue Change
    private func queueChange<T: Encodable>(
        uuid: String,
        table: String,
        rowId: Int64?,
        operation: String,
        entity: T?
    ) async {
        // Serialize entity to JSON
        var dataJson: String? = nil
        if let entity = entity {
            if let data = try? JSONEncoder().encode(entity),
               let json = String(data: data, encoding: .utf8) {
                dataJson = json
            }
        }

        // Get current local version
        let localVersion = await getCurrentLocalVersion(table: table, uuid: uuid)
        let dataJsonCopy = dataJson

        do {
            try await database.asyncWrite { db in
                // Check if there's already a pending change for this uuid
                let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT id FROM sync_queue WHERE uuid = ? AND status = 'pending'",
                    arguments: [uuid]
                )

                if let existingId = existing?["id"] as? Int64 {
                    // Update existing queue entry
                    try db.execute(
                        sql: """
                        UPDATE sync_queue
                        SET operation = ?, data = ?, local_version = ?, created_at = ?
                        WHERE id = ?
                        """,
                        arguments: [
                            operation,
                            dataJsonCopy,
                            localVersion,
                            Int64(Date().timeIntervalSince1970 * 1000),
                            existingId
                        ]
                    )
                } else {
                    // Insert new queue entry
                    try db.execute(
                        sql: """
                        INSERT INTO sync_queue (uuid, table_name, row_id, operation, data, local_version, status)
                        VALUES (?, ?, ?, ?, ?, ?, 'pending')
                        """,
                        arguments: [uuid, table, rowId, operation, dataJsonCopy, localVersion]
                    )
                }
            }

            print("📝 Queued \(operation) for \(table):\(uuid)")

        } catch {
            print("❌ Failed to queue change: \(error)")
        }
    }

    // MARK: - Mark as Pending
    private func markAsPending(table: String, uuid: String) async {
        try? await database.asyncWrite { db in
            try db.execute(
                sql: "UPDATE \(table) SET _local_pending = 1 WHERE uuid = ?",
                arguments: [uuid]
            )
        }
    }

    // MARK: - Increment Local Version
    private func incrementLocalVersion(table: String, uuid: String) async {
        try? await database.asyncWrite { db in
            try db.execute(
                sql: "UPDATE \(table) SET _local_version = _local_version + 1 WHERE uuid = ?",
                arguments: [uuid]
            )
        }
    }

    // MARK: - Get Current Local Version
    private func getCurrentLocalVersion(table: String, uuid: String) async -> Int {
        let result = try? await database.asyncRead { db in
            try Row.fetchOne(
                db,
                sql: "SELECT _local_version FROM \(table) WHERE uuid = ?",
                arguments: [uuid]
            )
        }

        return result?["_local_version"] as? Int ?? 1
    }
}

// MARK: - Syncable Protocol
protocol Syncable: Encodable {
    var id: Int64? { get }
    func getUUID() -> String?
}

// Extension to provide default UUID access
extension Syncable {
    func getUUID() -> String? {
        // Models have uuid as optional String property
        return (self as? HasUUID)?.uuid
    }
}

protocol HasUUID {
    var uuid: String { get }
}

// Extension to provide optional uuid for backwards compatibility
extension HasUUID {
    var uuidOptional: String? { uuid }
}

// Empty entity for delete operations
private struct EmptyEntity: Codable {}
