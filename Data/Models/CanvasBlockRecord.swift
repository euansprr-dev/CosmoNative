// CosmoOS/Data/Models/CanvasBlockRecord.swift
// Database record for canvas blocks - GRDB model

import Foundation
import GRDB

struct CanvasBlockRecord: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var uuid: String?
    var userId: String?
    var documentType: String
    var documentId: Int
    var documentUuid: String?
    var entityId: Int
    var entityUuid: String?
    var entityType: String
    var entityTitle: String?
    var positionX: Int
    var positionY: Int
    var width: Int?
    var height: Int?
    var isCollapsed: Bool?
    var zone: String?
    var noteContent: String?
    var zIndex: Int?
    /// Whether the block is pinned to the document content (scrolls with content)
    /// When false, the block stays fixed on screen (follows viewport)
    var isPinned: Bool?
    /// UUID of the Thinkspace this block belongs to (nil = global/default canvas)
    var thinkspaceId: String?
    /// A row is a space MEMBERSHIP; `isPlaced` says whether it also has a spot
    /// on the canvas (nil = pre-migration row = placed). Unplaced members wait
    /// in the canvas tray and show in the space's library and board.
    var isPlaced: Bool?
    var createdAt: String?
    var updatedAt: String?
    var syncedAt: String?
    var isDeleted: Bool
    /// UUID of the referenced Atom (mirrors Supabase atom_uuid column)
    var atomUuid: String?
    var localVersion: Int?
    var serverVersion: Int?
    var syncVersion: Int?
    var localPending: Int?

    static let databaseTableName = "canvas_blocks"

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case userId = "user_id"
        case documentType = "document_type"
        case documentId = "document_id"
        case documentUuid = "document_uuid"
        case entityId = "entity_id"
        case entityUuid = "entity_uuid"
        case entityType = "entity_type"
        case entityTitle = "entity_title"
        case positionX = "position_x"
        case positionY = "position_y"
        case width
        case height
        case isCollapsed = "is_collapsed"
        case zone
        case noteContent = "note_content"
        case zIndex = "z_index"
        case isPinned = "is_pinned"
        case thinkspaceId = "thinkspace_id"
        case isPlaced = "is_placed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
        case isDeleted = "is_deleted"
        case atomUuid = "atom_uuid"
        case localVersion = "_local_version"
        case serverVersion = "_server_version"
        case syncVersion = "_sync_version"
        case localPending = "_local_pending"
    }
    
    // MARK: - Cloud Sync Payload

    /// Cloud `canvas_blocks` payload for a local row, keyed by PLACEMENT id
    /// (`uuid` = local `id`). The old convention keyed cloud rows by entity
    /// uuid, which collapsed an entity's placements across thinkspaces into a
    /// single cloud row. One placement = one cloud row.
    ///
    /// `user_id` and `_source` are added at push time (SyncEngine.pushChange /
    /// ChangeTracker.immediatePush). The local `metadata` column is excluded —
    /// the cloud table has no such column and PostgREST rejects unknown keys.
    /// NOTE: numeric/bool columns MUST use GRDB's typed subscript (`as Int?`,
    /// `as Bool?`) — GRDB stores SQLite integers as Int64, so an `as? Int`
    /// cast on the untyped subscript silently fails and every numeric field
    /// collapses to its fallback (positions became 0, is_deleted became false).
    static func cloudSyncPayload(row: Row) -> [String: Any]? {
        guard let id = row["id"] as String?, !id.isEmpty else { return nil }
        let now = ISO8601.string(from: Date())
        func orNull(_ value: (some Any)?) -> Any { value.map { $0 as Any } ?? NSNull() }
        return [
            "uuid": id,
            "atom_uuid": row["entity_uuid"] as String? ?? "",
            "thinkspace_id": orNull(row["thinkspace_id"] as String?),
            "position_x": row["position_x"] as Int? ?? 0,
            "position_y": row["position_y"] as Int? ?? 0,
            "width": row["width"] as Int? ?? 320,
            "height": row["height"] as Int? ?? 340,
            "z_index": row["z_index"] as Int? ?? 0,
            "is_collapsed": row["is_collapsed"] as Bool? ?? false,
            "is_pinned": row["is_pinned"] as Bool? ?? false,
            "is_placed": row["is_placed"] as Bool? ?? true,
            "document_type": orNull(row["document_type"] as String?),
            "document_id": orNull(row["document_id"] as Int?),
            "document_uuid": orNull(row["document_uuid"] as String?),
            "entity_id": orNull(row["entity_id"] as Int?),
            "entity_uuid": orNull(row["entity_uuid"] as String?),
            "entity_type": orNull(row["entity_type"] as String?),
            "entity_title": orNull(row["entity_title"] as String?),
            "zone": orNull(row["zone"] as String?),
            "note_content": orNull(row["note_content"] as String?),
            "is_deleted": row["is_deleted"] as Bool? ?? false,
            "created_at": row["created_at"] as String? ?? now,
            "updated_at": row["updated_at"] as String? ?? now,
        ]
    }

    // MARK: - Factory Methods
    static func from(
        _ block: CanvasBlock,
        documentType: String,
        documentId: Int,
        thinkspaceId: String? = nil,
        isPlaced: Bool = true
    ) -> CanvasBlockRecord {
        return CanvasBlockRecord(
            id: block.id,
            uuid: block.entityUuid,
            userId: nil,
            documentType: documentType,
            documentId: documentId,
            documentUuid: nil,
            entityId: Int(block.entityId),
            entityUuid: block.entityUuid,
            entityType: block.entityType.rawValue,
            entityTitle: block.title,
            positionX: Int(block.position.x),
            positionY: Int(block.position.y),
            width: Int(block.size.width),
            height: Int(block.size.height),
            isCollapsed: false,
            zone: nil,
            noteContent: nil,
            zIndex: block.zIndex,
            isPinned: block.isPinned,
            thinkspaceId: thinkspaceId,
            isPlaced: isPlaced,
            createdAt: ISO8601.string(from: Date()),
            updatedAt: ISO8601.string(from: Date()),
            syncedAt: nil,
            isDeleted: false,
            atomUuid: block.entityUuid,
            localVersion: 1,
            serverVersion: 0,
            syncVersion: 0,
            localPending: 0
        )
    }
}

// MARK: - Canvas Block Sync Observer

/// GRDB transaction observer that auto-enqueues every LOCAL canvas_blocks
/// insert/update for cloud sync.
///
/// Why an observer instead of instrumenting call sites: canvas_blocks is
/// written by raw SQL from ~14 files (SpatialEngine, DocumentBlocksLayer,
/// block views, agent tools, …) and none of them were sync-tracked — which is
/// exactly how months of placements never reached the cloud. Observing the
/// table catches every current and future writer.
///
/// Echo prevention: remote-apply writers (ConflictResolver, tombstone applies,
/// Realtime) wrap their writes in `suppressingSync { }` so pulled changes are
/// never re-enqueued as local edits.
///
/// Hard DELETEs are ignored — the row is gone before we could resolve its id.
/// The only production hard-delete path (AtomRepository.hardDelete) tracks its
/// own cloud deletions.
final class CanvasBlockSyncObserver: TransactionObserver, @unchecked Sendable {
    static let shared = CanvasBlockSyncObserver()

    // Writer-queue-confined: GRDB invokes observer callbacks on the database
    // writer queue, and suppression is only toggled inside write closures
    // executing on that same queue — no locking needed.
    private var suppressionDepth = 0
    private var pendingRowIDs: Set<Int64> = []

    private init() {}

    /// Wrap remote-apply writes (must be called INSIDE a database write
    /// closure) so they are not re-enqueued for push.
    static func suppressingSync<T>(_ body: () throws -> T) rethrows -> T {
        shared.suppressionDepth += 1
        defer { shared.suppressionDepth -= 1 }
        return try body()
    }

    /// True while a remote apply is in flight on the writer queue. Other
    /// table observers (canvas_drawings) honor the same suppression window,
    /// so every remote-apply site keeps wrapping in ONE suppressingSync call.
    static var isSuppressingRemoteApply: Bool {
        shared.suppressionDepth > 0
    }

    // MARK: TransactionObserver

    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        eventKind.tableName == CanvasBlockRecord.databaseTableName
    }

    func databaseDidChange(with event: DatabaseEvent) {
        guard suppressionDepth == 0 else { return }
        switch event.kind {
        case .insert, .update:
            pendingRowIDs.insert(event.rowID)
        case .delete:
            break
        }
    }

    func databaseDidCommit(_ db: Database) {
        guard !pendingRowIDs.isEmpty else { return }
        let rowIDs = pendingRowIDs
        pendingRowIDs.removeAll()
        Task { @MainActor in
            await Self.enqueueForSync(rowIDs: rowIDs)
        }
    }

    func databaseDidRollback(_ db: Database) {
        pendingRowIDs.removeAll()
    }

    // MARK: Enqueue

    /// Fetch the committed rows and upsert sync_queue entries. Operation is
    /// always INSERT — the push path maps non-atom INSERTs to an upsert on
    /// `uuid`, which covers both new and edited placements. The periodic
    /// SyncEngine pass flushes the queue.
    @MainActor
    private static func enqueueForSync(rowIDs: Set<Int64>) async {
        let ids = Array(rowIDs)
        do {
            try await CosmoDatabase.shared.asyncWrite { db in
                for chunkStart in stride(from: 0, to: ids.count, by: 100) {
                    let chunk = Array(ids[chunkStart..<min(chunkStart + 100, ids.count)])
                    let marks = chunk.map { _ in "?" }.joined(separator: ",")
                    let rows = try Row.fetchAll(
                        db,
                        sql: "SELECT * FROM canvas_blocks WHERE rowid IN (\(marks))",
                        arguments: StatementArguments(chunk)
                    )
                    for row in rows {
                        guard let payload = CanvasBlockRecord.cloudSyncPayload(row: row),
                              let cloudKey = payload["uuid"] as? String,
                              let json = try? JSONSerialization.data(withJSONObject: payload),
                              let jsonString = String(data: json, encoding: .utf8) else { continue }
                        let localVersion = row["_local_version"] as Int? ?? 1

                        let existing = try Row.fetchOne(
                            db,
                            sql: "SELECT id FROM sync_queue WHERE uuid = ? AND table_name = 'canvas_blocks' AND status = 'pending'",
                            arguments: [cloudKey]
                        )
                        if let existingId = existing?["id"] as? Int64 {
                            try db.execute(
                                sql: "UPDATE sync_queue SET operation = 'INSERT', data = ?, local_version = ?, created_at = ? WHERE id = ?",
                                arguments: [jsonString, localVersion, Int64(Date().timeIntervalSince1970 * 1000), existingId]
                            )
                        } else {
                            try db.execute(
                                sql: """
                                INSERT INTO sync_queue (uuid, table_name, row_id, operation, data, local_version, status)
                                VALUES (?, 'canvas_blocks', NULL, 'INSERT', ?, ?, 'pending')
                                """,
                                arguments: [cloudKey, jsonString, localVersion]
                            )
                        }
                    }
                }
            }
        } catch {
            PersistenceHealth.note(.syncFailure, context: "CanvasBlockSyncObserver.enqueue", detail: "\(rowIDs.count) row(s) not enqueued: \(error)")
        }
    }
}
