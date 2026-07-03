// CosmoOS/Data/Models/CanvasDrawingRecord.swift
// GRDB record for persisted canvas drawings

import Foundation
import GRDB

struct CanvasDrawingRecord: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var thinkspaceId: String?
    var drawingType: String
    var shapeKind: String?
    var originX: Double
    var originY: Double
    var width: Double?
    var height: Double?
    var rotation: Double?
    var pathData: String?
    var textContent: String?
    var textWeight: String?
    var strokeColor: String
    var fillColor: String?
    var strokeWidth: Double
    var opacity: Double
    var zIndex: Int?
    var isDeleted: Bool
    var createdAt: String?
    var updatedAt: String?

    static let databaseTableName = "canvas_drawings"

    enum CodingKeys: String, CodingKey {
        case id
        case thinkspaceId = "thinkspace_id"
        case drawingType = "drawing_type"
        case shapeKind = "shape_kind"
        case originX = "origin_x"
        case originY = "origin_y"
        case width
        case height
        case rotation
        case pathData = "path_data"
        case textContent = "text_content"
        case textWeight = "text_weight"
        case strokeColor = "stroke_color"
        case fillColor = "fill_color"
        case strokeWidth = "stroke_width"
        case opacity
        case zIndex = "z_index"
        case isDeleted = "is_deleted"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Cloud Sync Payload

    /// Cloud row for a local canvas_drawings row. Local `id` is the cloud
    /// `uuid` (same contract as canvas_blocks placements). `user_id` and
    /// `_source` are added at push time by SyncEngine.
    /// NOTE: numeric/bool columns MUST use GRDB's typed subscripts — see
    /// CanvasBlockRecord.cloudSyncPayload for the Int64 collapse gotcha.
    static func cloudSyncPayload(row: Row) -> [String: Any]? {
        guard let id = row["id"] as String?, !id.isEmpty else { return nil }
        let now = ISO8601.string(from: Date())
        func orNull(_ value: (some Any)?) -> Any { value.map { $0 as Any } ?? NSNull() }
        return [
            "uuid": id,
            "thinkspace_id": orNull(row["thinkspace_id"] as String?),
            "drawing_type": row["drawing_type"] as String? ?? "freehand",
            "shape_kind": orNull(row["shape_kind"] as String?),
            "origin_x": row["origin_x"] as Double? ?? 0,
            "origin_y": row["origin_y"] as Double? ?? 0,
            "width": orNull(row["width"] as Double?),
            "height": orNull(row["height"] as Double?),
            "rotation": orNull(row["rotation"] as Double?),
            "path_data": orNull(row["path_data"] as String?),
            "text_content": orNull(row["text_content"] as String?),
            "text_weight": orNull(row["text_weight"] as String?),
            "stroke_color": row["stroke_color"] as String? ?? "#1A1A1A",
            "fill_color": orNull(row["fill_color"] as String?),
            "stroke_width": row["stroke_width"] as Double? ?? 2.5,
            "opacity": row["opacity"] as Double? ?? 1,
            "z_index": row["z_index"] as Int? ?? 0,
            "is_deleted": row["is_deleted"] as Bool? ?? false,
            "created_at": row["created_at"] as String? ?? now,
            "updated_at": row["updated_at"] as String? ?? now,
        ]
    }
}

// MARK: - Canvas Drawing Sync Observer

/// GRDB transaction observer that auto-enqueues every LOCAL canvas_drawings
/// insert/update for cloud sync — same architecture as
/// CanvasBlockSyncObserver (drawings are written from DrawingStateManager,
/// undo actions, and lasso operations; the observer catches every writer).
///
/// Echo prevention: remote applies wrap in
/// `CanvasBlockSyncObserver.suppressingSync { }` — this observer honors that
/// same suppression window, so apply sites don't need a second wrapper.
final class CanvasDrawingSyncObserver: TransactionObserver, @unchecked Sendable {
    static let shared = CanvasDrawingSyncObserver()

    private var pendingRowIDs: Set<Int64> = []

    private init() {}

    // MARK: TransactionObserver

    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        eventKind.tableName == CanvasDrawingRecord.databaseTableName
    }

    func databaseDidChange(with event: DatabaseEvent) {
        guard !CanvasBlockSyncObserver.isSuppressingRemoteApply else { return }
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
                        sql: "SELECT * FROM canvas_drawings WHERE rowid IN (\(marks))",
                        arguments: StatementArguments(chunk)
                    )
                    for row in rows {
                        guard let payload = CanvasDrawingRecord.cloudSyncPayload(row: row),
                              let cloudKey = payload["uuid"] as? String,
                              let json = try? JSONSerialization.data(withJSONObject: payload),
                              let jsonString = String(data: json, encoding: .utf8) else { continue }
                        let localVersion = row["_local_version"] as Int? ?? 1

                        let existing = try Row.fetchOne(
                            db,
                            sql: "SELECT id FROM sync_queue WHERE uuid = ? AND table_name = 'canvas_drawings' AND status = 'pending'",
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
                                VALUES (?, 'canvas_drawings', NULL, 'INSERT', ?, ?, 'pending')
                                """,
                                arguments: [cloudKey, jsonString, localVersion]
                            )
                        }
                    }
                }
            }
        } catch {
            PersistenceHealth.note(.syncFailure, context: "CanvasDrawingSyncObserver.enqueue", detail: "\(rowIDs.count) row(s) not enqueued: \(error)")
        }
    }
}
