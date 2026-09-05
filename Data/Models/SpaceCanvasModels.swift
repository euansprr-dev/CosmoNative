import Foundation

/// Portable canvas annotations. These are owned by the container, never by a
/// root canvas row. The wire shape is shared with CosmoCoreKit.
struct SpaceCanvasPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var w: Double?
}

struct SpaceCanvasDrawing: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var drawingType: String
    var shapeKind: String?
    var originX: Double
    var originY: Double
    var width: Double?
    var height: Double?
    var rotation: Double
    var points: [SpaceCanvasPoint]?
    var textContent: String?
    var textWeight: String?
    var strokeColor: String
    var fillColor: String?
    var strokeWidth: Double
    var opacity: Double
    var zIndex: Int

    func validate() throws {
        let bounded: (Double) -> Bool = { $0.isFinite && abs($0) <= 1_000_000_000 }
        guard !id.isEmpty, ["shape", "freehand", "text"].contains(drawingType),
              bounded(originX), bounded(originY), rotation.isFinite,
              width.map({ bounded($0) && $0 >= 0 }) ?? true,
              height.map({ bounded($0) && $0 >= 0 }) ?? true,
              strokeWidth.isFinite, (0...1_000).contains(strokeWidth),
              opacity.isFinite, (0...1).contains(opacity),
              points?.allSatisfy({ bounded($0.x) && bounded($0.y) && ($0.w.map { $0.isFinite && (0...1_000).contains($0) } ?? true) }) ?? true
        else { throw SpaceCompositionError.invalidPlacement }
    }
}

/// Existing canvas regions retain their mature Grid/List/Board presentation.
/// Membership here is visual grouping only; Page order and Group atoms stay separate.
struct SpaceCanvasCluster: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var blockUUIDs: [String]
    var colorIndex: Int
    var synthesis: String?
    var synthesisUpdatedAt: String?
    var originX: Double?
    var originY: Double?
    var rectWidth: Double?
    var rectHeight: Double?
    var manualWidth: Double?
    var manualHeight: Double?
    var isZone: Bool?
    var zoneType: String?
    var intent: String?
    var viewMode: String?
    var sortOrder: String?
    var boardGrouping: String?

    func validate() throws {
        guard UUID(uuidString: id) != nil, colorIndex >= 0,
              [originX, originY, rectWidth, rectHeight, manualWidth, manualHeight].compactMap({ $0 })
                .allSatisfy({ $0.isFinite && abs($0) <= 1_000_000_000 }) else { throw SpaceCompositionError.invalidMetadata }
    }
}

struct SpaceCanvasContent: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var drawings: [SpaceCanvasDrawing] = []
    var clusters: [SpaceCanvasCluster] = []
    /// An explicit hidden placement differs from a member that has never been
    /// arranged. Older clients retain this optional subtree without rewriting it.
    var hiddenItemUUIDs: [String] = []

    enum CodingKeys: String, CodingKey { case schemaVersion, drawings, hiddenItemUUIDs, clusters }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        drawings = try values.decodeIfPresent([SpaceCanvasDrawing].self, forKey: .drawings) ?? []
        clusters = try values.decodeIfPresent([SpaceCanvasCluster].self, forKey: .clusters) ?? []
        hiddenItemUUIDs = try values.decodeIfPresent([String].self, forKey: .hiddenItemUUIDs) ?? []
        try validate()
    }
    func validate() throws {
        guard schemaVersion == 1 else { throw SpaceCompositionError.unsupportedVersion(schemaVersion) }
        guard Set(drawings.map(\.id)).count == drawings.count else { throw SpaceCompositionError.invalidMetadata }
        for drawing in drawings { try drawing.validate() }
        guard Set(clusters.map(\.id)).count == clusters.count else { throw SpaceCompositionError.invalidMetadata }
        for cluster in clusters { try cluster.validate() }
    }
}

extension Atom {
    func decodedSpaceCanvas() throws -> SpaceCanvasContent {
        _ = try decodedSpaceComposition()
        guard let metadata, let data = metadata.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let composition = object["spaceComposition"] as? [String: Any],
              let canvas = composition["canvas"] else { return SpaceCanvasContent() }
        return try JSONDecoder().decode(SpaceCanvasContent.self, from: JSONSerialization.data(withJSONObject: canvas))
    }

    /// Replaces only fields this version understands, retaining future fields
    /// in both the composition and canvas namespaces.
    func replacingSpaceCanvas(_ canvas: SpaceCanvasContent) throws -> Atom {
        try canvas.validate()
        _ = try decodedSpaceCanvas()
        let compositionValue = try decodedSpaceComposition() ?? SpaceCompositionMetadata()
        let base = try replacingSpaceComposition(compositionValue)
        var object = try JSONSerialization.jsonObject(with: Data((base.metadata ?? "{}").utf8)) as? [String: Any] ?? [:]
        var composition = object["spaceComposition"] as? [String: Any] ?? [:]
        var raw = composition["canvas"] as? [String: Any] ?? [:]
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(canvas)) as? [String: Any] ?? [:]
        // Patch records by stable id so edits also preserve fields introduced
        // by newer clients inside other annotations and regions.
        func mergedRecords(_ key: String, ownedKeys: [String]) -> [[String: Any]] {
            let previous = raw[key] as? [[String: Any]] ?? []
            var byID: [String: [String: Any]] = [:]
            for record in previous { if let id = record["id"] as? String { byID[id] = record } }
            return (encoded[key] as? [[String: Any]] ?? []).map { record in
                var merged = (record["id"] as? String).flatMap { byID[$0] } ?? [:]
                for field in ownedKeys { merged[field] = record[field] }
                return merged
            }
        }
        raw["drawings"] = mergedRecords("drawings", ownedKeys: ["id", "drawingType", "shapeKind", "originX", "originY",
            "width", "height", "rotation", "points", "textContent", "textWeight", "strokeColor", "fillColor", "strokeWidth", "opacity", "zIndex"])
        raw["clusters"] = mergedRecords("clusters", ownedKeys: ["id", "name", "blockUUIDs", "colorIndex", "synthesis", "synthesisUpdatedAt",
            "originX", "originY", "rectWidth", "rectHeight", "manualWidth", "manualHeight", "isZone", "zoneType", "intent", "viewMode", "sortOrder", "boardGrouping"])
        for key in ["schemaVersion", "hiddenItemUUIDs"] { raw[key] = encoded[key] }
        composition["canvas"] = raw
        object["spaceComposition"] = composition
        var updated = base
        updated.metadata = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        return updated
    }
}
