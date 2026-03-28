// CosmoOS/Sync/ChangeTracker.swift
// Tracks local changes and queues them for invisible sync
// Phase 1: Added immediate push (fire-and-forget) alongside queue for instant cloud sync
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
            print("[SYNC] ⚠️ Cannot track entity without UUID")
            return
        }
        print("[SYNC] trackInsert — table=\(table) uuid=\(uuid)")

        // Mark as pending locally
        await markAsPending(table: table, uuid: uuid)

        // Add to sync queue (offline buffer)
        await queueChange(
            uuid: uuid,
            table: table,
            rowId: entity.id,
            operation: "INSERT",
            entity: entity
        )

        // Fire-and-forget immediate push to Supabase
        await immediatePush(table: table, uuid: uuid, entity: entity, operation: "INSERT")
    }

    // MARK: - Track Update
    /// Track a local update for sync.
    /// - Parameter skipVersionIncrement: Set to `true` when the caller already incremented
    ///   `_local_version` via raw SQL (e.g. `_local_version = _local_version + 1`).
    ///   Prevents double-bumping the version which causes optimistic lock conflicts.
    func trackUpdate<T: Syncable>(
        table: String,
        entity: T,
        changedFields: [String]? = nil,
        skipVersionIncrement: Bool = false
    ) async {
        guard let uuid = entity.getUUID() else { return }
        print("[SYNC] trackUpdate — table=\(table) uuid=\(uuid) changedFields=\(changedFields ?? ["all"]) skipVersionIncrement=\(skipVersionIncrement)")

        // Increment local version (skip if caller already did it via raw SQL)
        if !skipVersionIncrement {
            await incrementLocalVersion(table: table, uuid: uuid)
        }

        // Mark as pending
        await markAsPending(table: table, uuid: uuid)

        // Add to sync queue (offline buffer)
        await queueChange(
            uuid: uuid,
            table: table,
            rowId: entity.id,
            operation: "UPDATE",
            entity: entity
        )

        // Fire-and-forget immediate push to Supabase
        await immediatePush(table: table, uuid: uuid, entity: entity, operation: "UPDATE")
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

        // Fire-and-forget immediate delete
        Task.detached { @MainActor in
            guard let client = SupabaseClient.shared, client.isAuthenticated else { return }
            do {
                try await client.softDelete(table: table, uuid: uuid)
                // Mark synced in queue
                try? await CosmoDatabase.shared.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE sync_queue SET status = 'synced', synced_at = ? WHERE uuid = ? AND status = 'pending'",
                        arguments: [ISO8601DateFormatter().string(from: Date()), uuid]
                    )
                }
            } catch {
                // Stays in sync_queue for batch retry
            }
        }
    }

    // MARK: - Immediate Push (Fire-and-Forget)

    /// Push a change to Supabase immediately without blocking.
    /// If it fails (offline, auth issue), the sync_queue entry remains for batch retry.
    private func immediatePush<T: Encodable>(
        table: String,
        uuid: String,
        entity: T,
        operation: String
    ) async {
        print("[SYNC] immediatePush — table=\(table) uuid=\(uuid) op=\(operation)")
        Task.detached { @MainActor in
            guard let client = SupabaseClient.shared, client.isAuthenticated else {
                print("[SYNC] immediatePush SKIPPED — no client or not authenticated uuid=\(uuid)")
                return
            }
            guard let userId = client.currentUserId else { return }

            // Serialize entity
            guard let data = try? JSONEncoder().encode(entity),
                  var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            // Remove local-only fields + GRDB autoincrement id (conflicts with Postgres serial)
            payload.removeValue(forKey: "id")
            payload.removeValue(forKey: "_local_version")
            payload.removeValue(forKey: "_server_version")
            payload.removeValue(forKey: "_sync_version")
            payload.removeValue(forKey: "_local_pending")

            // Add cloud fields
            payload["user_id"] = userId
            payload["_source"] = "mac"

            // Convert JSON TEXT fields to objects for JSONB
            if table == "atoms" {
                for key in ["structured", "metadata", "links"] {
                    if let jsonString = payload[key] as? String,
                       !jsonString.isEmpty,
                       let jsonData = jsonString.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: jsonData) {
                        payload[key] = parsed
                    }
                }
            }

            do {
                switch operation {
                case "INSERT":
                    try await client.upsert(table: table, data: payload, onConflict: "uuid")
                case "UPDATE":
                    try await client.update(table: table, uuid: uuid, data: payload)
                default:
                    break
                }

                // Mark synced in queue + update server version
                try? await CosmoDatabase.shared.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE sync_queue SET status = 'synced', synced_at = ? WHERE uuid = ? AND status = 'pending'",
                        arguments: [ISO8601DateFormatter().string(from: Date()), uuid]
                    )
                    try db.execute(
                        sql: "UPDATE \(table) SET _server_version = _local_version, _local_pending = 0 WHERE uuid = ?",
                        arguments: [uuid]
                    )
                }
                print("[SYNC] immediatePush SUCCESS — table=\(table) uuid=\(uuid) op=\(operation)")
            } catch {
                print("[SYNC] ⚠️ immediatePush FAILED — table=\(table) uuid=\(uuid) op=\(operation) error=\(error)")
                // sync_queue entry remains for batch retry by SyncEngine
            }
        }
    }

    // MARK: - Queue Change
    private func queueChange<T: Encodable>(
        uuid: String,
        table: String,
        rowId: Int64?,
        operation: String,
        entity: T?
    ) async {
        var dataJson: String? = nil
        if let entity = entity {
            if let data = try? JSONEncoder().encode(entity),
               let json = String(data: data, encoding: .utf8) {
                dataJson = json
            }
        }

        let localVersion = await getCurrentLocalVersion(table: table, uuid: uuid)
        let dataJsonCopy = dataJson

        do {
            try await database.asyncWrite { db in
                let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT id FROM sync_queue WHERE uuid = ? AND status = 'pending'",
                    arguments: [uuid]
                )

                if let existingId = existing?["id"] as? Int64 {
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
                    try db.execute(
                        sql: """
                        INSERT INTO sync_queue (uuid, table_name, row_id, operation, data, local_version, status)
                        VALUES (?, ?, ?, ?, ?, ?, 'pending')
                        """,
                        arguments: [uuid, table, rowId, operation, dataJsonCopy, localVersion]
                    )
                }
            }
        } catch {
            print("❌ Failed to queue change: \(error)")
        }
    }

    // MARK: - Mark as Pending
    private func markAsPending(table: String, uuid: String) async {
        print("[SYNC] markAsPending — table=\(table) uuid=\(uuid)")
        try? await database.asyncWrite { db in
            try db.execute(
                sql: "UPDATE \(table) SET _local_pending = 1 WHERE uuid = ?",
                arguments: [uuid]
            )
        }
    }

    // MARK: - Increment Local Version
    private func incrementLocalVersion(table: String, uuid: String) async {
        print("[SYNC] incrementLocalVersion — table=\(table) uuid=\(uuid)")
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

extension Syncable {
    func getUUID() -> String? {
        return (self as? HasUUID)?.uuid
    }
}

protocol HasUUID {
    var uuid: String { get }
}

extension HasUUID {
    var uuidOptional: String? { uuid }
}

// Empty entity for delete operations
private struct EmptyEntity: Codable {}
