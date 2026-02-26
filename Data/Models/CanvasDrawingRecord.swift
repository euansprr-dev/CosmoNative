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
}
