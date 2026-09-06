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
        if CaptureSyncOutbox.tables.contains(table) {
            await pushCurrentCapture(table: table, uuid: uuid)
            return
        }
        ConsoleLog.verbose("trackInsert table=\(table) uuid=\(uuid)", subsystem: .sync)

        // One encode serves both the offline queue row and the immediate push.
        let encoded = await Self.encodeEntity(entity)

        // Pending shield + queue upsert in ONE writer transaction
        await recordChange(
            table: table,
            uuid: uuid,
            rowId: entity.id,
            operation: "INSERT",
            dataJson: encoded,
            incrementVersion: false,
            markPending: true
        )

        // Fire-and-forget immediate push to Supabase
        immediatePush(table: table, uuid: uuid, encodedEntity: encoded, operation: "INSERT")
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
        if CaptureSyncOutbox.tables.contains(table) {
            await pushCurrentCapture(table: table, uuid: uuid)
            return
        }
        ConsoleLog.verbose("trackUpdate table=\(table) uuid=\(uuid) changedFields=\(changedFields ?? ["all"]) skipVersionIncrement=\(skipVersionIncrement)", subsystem: .sync)

        // One encode serves both the offline queue row and the immediate push.
        let encoded = await Self.encodeEntity(entity)

        // Version bump + pending shield + queue upsert in ONE writer
        // transaction (was three — every keystroke-driven save queued three
        // transactions behind the single pool writer).
        await recordChange(
            table: table,
            uuid: uuid,
            rowId: entity.id,
            operation: "UPDATE",
            dataJson: encoded,
            incrementVersion: !skipVersionIncrement,
            markPending: true
        )

        // Fire-and-forget immediate push to Supabase
        immediatePush(table: table, uuid: uuid, encodedEntity: encoded, operation: "UPDATE")
    }

    private func pushCurrentCapture(table: String, uuid: String) async {
        do {
            let current = try await database.asyncWrite { db in
                try CaptureSyncOutbox.enqueue(db, table: table, uuid: uuid)
            }
            guard current != nil else { return }
            guard SupabaseSyncTrafficPolicy.allowsNetworkSync else { return }
            // One uploader owns capture writes; an older immediate request
            // must not land after a newer batch and overwrite its content.
            SyncEngine.shared.requestCapturePush()
        } catch {
            PersistenceHealth.note(.syncFailure, context: "ChangeTracker.capture(\(uuid.prefix(8)))", detail: String(describing: error))
        }
    }

    // MARK: - Track Delete
    func trackDelete(
        table: String,
        uuid: String,
        rowId: Int64?
    ) async {
        // Add to sync queue (no version bump, no pending shield — matches the
        // historical delete path exactly)
        await recordChange(
            table: table,
            uuid: uuid,
            rowId: rowId,
            operation: "DELETE",
            dataJson: nil,
            incrementVersion: false,
            markPending: false
        )

        // Fire-and-forget immediate delete
        guard SupabaseSyncTrafficPolicy.allowsNetworkSync else { return }
        Task.detached { @MainActor in
            guard let client = SupabaseClient.shared, client.isAuthenticated else { return }
            do {
                try await client.softDelete(table: table, uuid: uuid)
                // Mark synced in queue
                try? await CosmoDatabase.shared.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE sync_queue SET status = 'synced', synced_at = ? WHERE uuid = ? AND table_name = ? AND status = 'pending'",
                        arguments: [ISO8601.string(from: Date()), uuid, table]
                    )
                }
            } catch {
                // Stays in sync_queue for batch retry
            }
        }
    }

    // MARK: - Encode (off-main)

    /// Encode the entity to its queue/push JSON. `nonisolated async` so the
    /// encode runs on the global executor — a fat metadata column (rich note
    /// documents run to hundreds of KB) must never JSON round-trip on the
    /// main thread. (The class is @MainActor; a plain method would encode on
    /// main despite any comment claiming otherwise — that was the July bug.)
    private nonisolated static func encodeEntity<T: Encodable>(_ entity: T) async -> String? {
        guard let data = try? JSONEncoder().encode(entity) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Immediate Push (Fire-and-Forget)

    /// Push a change to Supabase immediately without blocking.
    /// If it fails (offline, auth issue), the sync_queue entry remains for batch retry.
    /// All payload preparation (JSON parse, field stripping, JSONB conversion)
    /// happens inside the detached task, off the main actor; only the
    /// SupabaseClient access is main-bound.
    private func immediatePush(
        table: String,
        uuid: String,
        encodedEntity: String?,
        operation: String
    ) {
        guard SupabaseSyncTrafficPolicy.allowsNetworkSync else { return }
        guard let encodedEntity else { return }
        ConsoleLog.verbose("immediatePush table=\(table) uuid=\(uuid) op=\(operation)", subsystem: .sync)

        Task.detached {
            guard let data = encodedEntity.data(using: .utf8),
                  var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            let serverVersion = payload["_server_version"] as? Int ?? 0
            // The exact local version this push carries. Bookkeeping below is scoped
            // to it so an edit made while this push is in flight stays pending and
            // gets its own push, instead of being silently marked synced.
            let pushedLocalVersion = payload["_local_version"] as? Int ?? 0

            // Remove local-only fields + GRDB autoincrement id (conflicts with Postgres serial)
            payload.removeValue(forKey: "id")
            payload.removeValue(forKey: "_local_version")
            payload.removeValue(forKey: "_server_version")
            payload.removeValue(forKey: "_sync_version")
            payload.removeValue(forKey: "_local_pending")

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

            let writeDisposition: SyncWriteDisposition = SyncWriteDisposition.resolve(
                requestedOperation: operation,
                serverVersion: serverVersion
            )

            nonisolated(unsafe) let preparedPayload = payload
            await Self.performPush(
                table: table,
                uuid: uuid,
                operation: operation,
                preparedPayload: preparedPayload,
                writeDisposition: writeDisposition,
                pushedLocalVersion: pushedLocalVersion
            )
        }
    }

    private static func performPush(
        table: String,
        uuid: String,
        operation: String,
        preparedPayload: [String: Any],
        writeDisposition: SyncWriteDisposition,
        pushedLocalVersion: Int
    ) async {
            guard let client = SupabaseClient.shared, client.isAuthenticated else {
                ConsoleLog.verbose("immediatePush skipped no client or not authenticated uuid=\(uuid)", subsystem: .sync)
                return
            }
            guard let userId = client.currentUserId else { return }

            var payload = preparedPayload
            // Add cloud fields
            payload["user_id"] = userId
            payload["_source"] = "mac"

            do {
                switch writeDisposition {
                case .upsert:
                    try await client.upsert(table: table, data: payload, onConflict: "uuid")
                case .update:
                    try await client.update(table: table, uuid: uuid, data: payload)
                }

                // Mark synced in queue + update server version — scoped to the version
                // actually pushed. A newer local edit (higher local_version) keeps its
                // pending row and pending flag so it is never claimed as synced.
                do {
                    try await CosmoDatabase.shared.asyncWrite { db in
                        try db.execute(
                            sql: "UPDATE sync_queue SET status = 'synced', synced_at = ? WHERE uuid = ? AND table_name = ? AND status = 'pending' AND local_version <= ?",
                            arguments: [ISO8601.string(from: Date()), uuid, table, pushedLocalVersion]
                        )
                        // A successful push carries the row's full current content,
                        // superseding any older dead-lettered payload for it.
                        try SyncQueueReconciler.clearSupersededDeadLetters(
                            db, uuid: uuid, table: table, upToVersion: pushedLocalVersion
                        )
                        // Suppressed: this is push bookkeeping, not a local edit —
                        // the table observers (canvas_blocks, atoms) must not
                        // re-enqueue it or every successful push loops forever.
                        try CanvasBlockSyncObserver.suppressingSync {
                            try db.execute(
                                sql: """
                                    UPDATE \(table)
                                    SET _server_version = MAX(_server_version, ?),
                                        _local_pending = CASE WHEN _local_version > ? THEN _local_pending ELSE 0 END
                                    WHERE uuid = ?
                                    """,
                                arguments: [pushedLocalVersion, pushedLocalVersion, uuid]
                            )
                        }
                    }
                } catch {
                    PersistenceHealth.note(.syncFailure, context: "ChangeTracker.immediatePush(\(uuid.prefix(8)))", detail: "post-push bookkeeping failed: \(error)")
                }
                ConsoleLog.verbose("immediatePush success table=\(table) uuid=\(uuid) op=\(operation) pushedVersion=\(pushedLocalVersion)", subsystem: .sync)
            } catch {
                print("[SYNC] ⚠️ immediatePush FAILED — table=\(table) uuid=\(uuid) op=\(operation) error=\(error)")
                // sync_queue entry remains for batch retry by SyncEngine
            }
    }

    // MARK: - Record Change (one transaction)

    /// Version bump + pending shield + sync_queue upsert in a single writer
    /// transaction. These were three separate `asyncWrite`s (plus a separate
    /// read for the version), which serialized four round-trips through the
    /// pool's one writer per tracked change.
    private func recordChange(
        table: String,
        uuid: String,
        rowId: Int64?,
        operation: String,
        dataJson: String?,
        incrementVersion: Bool,
        markPending: Bool
    ) async {
        do {
            try await database.asyncWrite { db in
                // Suppressed: version + shield bookkeeping, not content — the
                // queue upsert below is the explicit enqueue for the change.
                try CanvasBlockSyncObserver.suppressingSync {
                    if incrementVersion {
                        try db.execute(
                            sql: "UPDATE \(table) SET _local_version = _local_version + 1 WHERE uuid = ?",
                            arguments: [uuid]
                        )
                    }
                    if markPending {
                        try db.execute(
                            sql: "UPDATE \(table) SET _local_pending = 1 WHERE uuid = ?",
                            arguments: [uuid]
                        )
                    }
                }

                // Typed GRDB subscript (`as Int?`), NEVER `as? Int`: SQLite
                // integers come back as Int64 and the untyped cast silently
                // fails — that exact cast once pinned every queued change to
                // local_version = 1 (the manufactured-orphan bug).
                let versionRow = try Row.fetchOne(
                    db,
                    sql: "SELECT _local_version FROM \(table) WHERE uuid = ?",
                    arguments: [uuid]
                )
                let localVersion = (versionRow?["_local_version"] as Int?) ?? 1

                // Scoped by table too: canvas_blocks rows share the entity's
                // uuid, so a uuid-only match would swallow one table's op
                // with the other's.
                let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT id FROM sync_queue WHERE uuid = ? AND table_name = ? AND status = 'pending'",
                    arguments: [uuid, table]
                )

                if let existingId = existing?["id"] as Int64? {
                    try db.execute(
                        sql: """
                        UPDATE sync_queue
                        SET operation = ?, data = ?, local_version = ?, created_at = ?
                        WHERE id = ?
                        """,
                        arguments: [
                            operation,
                            dataJson,
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
                        arguments: [uuid, table, rowId, operation, dataJson, localVersion]
                    )
                }
            }
        } catch {
            // If the pending shield doesn't get set, an inbound remote change
            // can immediately overwrite the just-edited row — must be visible.
            PersistenceHealth.note(.syncFailure, context: "ChangeTracker.recordChange(\(uuid.prefix(8)))", detail: String(describing: error))
            print("❌ Failed to record change: \(error)")
        }
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
