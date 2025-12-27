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
    var createdAt: String?
    var updatedAt: String?
    var syncedAt: String?
    var isDeleted: Bool
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
        case isDeleted = "is_deleted"
        case localVersion = "_local_version"
        case serverVersion = "_server_version"
        case syncVersion = "_sync_version"
        case localPending = "_local_pending"
    }
    
    // MARK: - Factory Methods
    static func from(_ block: CanvasBlock, documentType: String, documentId: Int, thinkspaceId: String? = nil) -> CanvasBlockRecord {
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
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            syncedAt: nil,
            isDeleted: false,
            localVersion: 1,
            serverVersion: 0,
            syncVersion: 0,
            localPending: 0
        )
    }
}
