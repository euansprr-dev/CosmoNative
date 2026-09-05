import Foundation
import GRDB

struct SpaceCanvasPlacementChange: Codable, Sendable {
    var itemUUID: String
    var before: SpaceCompositionPlacement?
    var after: SpaceCompositionPlacement?
    var hiddenBefore: Bool
    var hiddenAfter: Bool
    var memberBefore: Bool?
    var memberAfter: Bool?
    var referenceBefore: SpaceCompositionReference?
    var referenceAfter: SpaceCompositionReference?
    var memberIndex: Int?
}

struct SpaceCanvasDrawingChange: Codable, Sendable {
    var id: String
    var before: SpaceCanvasDrawing?
    var after: SpaceCanvasDrawing?
}

struct SpaceCanvasClusterChange: Codable, Sendable {
    var id: String
    var before: SpaceCanvasCluster?
    var after: SpaceCanvasCluster?
}

/// A patch contains only fields owned by one gesture. Its inverse never restores
/// an entire atom snapshot over newer writing or another canvas operation.
struct SpaceCanvasPatch: Codable, Sendable {
    var placements: [SpaceCanvasPlacementChange] = []
    var drawings: [SpaceCanvasDrawingChange] = []
    var clusters: [SpaceCanvasClusterChange] = []
    var isEmpty: Bool { placements.isEmpty && drawings.isEmpty && clusters.isEmpty }
    var reversed: SpaceCanvasPatch {
        SpaceCanvasPatch(placements: placements.map {
            SpaceCanvasPlacementChange(itemUUID: $0.itemUUID, before: $0.after, after: $0.before,
                hiddenBefore: $0.hiddenAfter, hiddenAfter: $0.hiddenBefore,
                memberBefore: $0.memberAfter, memberAfter: $0.memberBefore,
                referenceBefore: $0.referenceAfter, referenceAfter: $0.referenceBefore, memberIndex: $0.memberIndex)
        }, drawings: drawings.map { .init(id: $0.id, before: $0.after, after: $0.before) },
            clusters: clusters.map { .init(id: $0.id, before: $0.after, after: $0.before) })
    }
}

/// SQL boundary for a scoped canvas. There is deliberately no canvas_blocks or
/// canvas_drawings writer here. Root membership is neither moved nor recreated.
enum SpaceCanvasPersistence {
    static func container(_ uuid: String, db: Database) throws -> Atom {
        guard let atom = try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db),
              atom.type == .note else { throw SpaceCompositionError.notFound }
        _ = try atom.decodedSpaceComposition()
        return atom
    }

    static func items(in container: Atom, db: Database) throws -> [Atom] {
        let value = try container.decodedSpaceComposition() ?? SpaceCompositionMetadata()
        var result: [Atom]
        if value.kind == .group {
            let ids = value.memberUUIDs
            let fetched = try Atom.filter(ids.contains(Column("uuid"))).filter(Column("is_deleted") == false).fetchAll(db)
            let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.uuid, $0) })
            var seen = Set<String>()
            result = ids.compactMap { seen.insert($0).inserted ? byID[$0] : nil }
        } else {
            result = try Atom.fetchAll(db, sql: """
                SELECT * FROM atoms WHERE is_deleted = 0 AND json_valid(metadata)
                AND json_extract(metadata, '$.spaceComposition.parentUUID') = ?
                """, arguments: [container.uuid])
            result.sort {
                let a = $0.spaceComposition?.sortOrder ?? 0, b = $1.spaceComposition?.sortOrder ?? 0
                return a == b ? $0.uuid < $1.uuid : a < b
            }
            // Explicitly arranged reference originals are real material cards,
            // not authored children and never part of the reading order.
            let placed = Set(value.placements.map(\.itemUUID))
            let sourceIDs = value.references.map(\.sourceUUID).filter { placed.contains($0) }
            let existing = Set(result.map(\.uuid))
            let sources = try Atom.filter(sourceIDs.filter { !existing.contains($0) }.contains(Column("uuid")))
                .filter(Column("is_deleted") == false).fetchAll(db)
            result += sources.sorted { $0.uuid < $1.uuid }
        }
        return result
    }

    @discardableResult
    static func apply(_ patch: SpaceCanvasPatch, to containerUUID: String, db: Database) throws -> Atom {
        let atom = try container(containerUUID, db: db)
        var value = try atom.decodedSpaceComposition() ?? SpaceCompositionMetadata()
        var canvas = try atom.decodedSpaceCanvas()
        for change in patch.placements {
            guard change.itemUUID != containerUUID else { throw SpaceCompositionError.cycle }
            guard value.placements.first(where: { $0.itemUUID == change.itemUUID }) == change.before,
                  canvas.hiddenItemUUIDs.contains(change.itemUUID) == change.hiddenBefore else {
                throw SpaceCompositionError.conflict
            }
            if let expected = change.memberBefore {
                guard value.kind == .group, value.memberUUIDs.contains(change.itemUUID) == expected else { throw SpaceCompositionError.conflict }
            }
            if let before = change.referenceBefore {
                guard value.references.first(where: { $0.id == before.id }) == before else { throw SpaceCompositionError.conflict }
            } else if let after = change.referenceAfter {
                guard !value.references.contains(where: { $0.id == after.id }) else { throw SpaceCompositionError.conflict }
            }
            if change.after != nil || change.memberAfter == true || change.referenceAfter != nil {
                guard let item = try Atom.filter(Column("uuid") == change.itemUUID).filter(Column("is_deleted") == false).fetchOne(db) else {
                    throw SpaceCompositionError.notFound
                }
                let belongs = value.kind == .group ? value.memberUUIDs.contains(item.uuid) :
                    item.spaceComposition?.parentUUID == containerUUID || value.references.contains(where: { $0.sourceUUID == item.uuid })
                guard belongs || change.memberAfter == true || change.referenceAfter != nil else { throw SpaceCompositionError.invalidParent }
                if change.memberAfter == true { try validateGroupEdge(parent: containerUUID, child: item, db: db) }
            }
            if let member = change.memberAfter {
                value.memberUUIDs.removeAll { $0 == change.itemUUID }
                if member { value.memberUUIDs.insert(change.itemUUID, at: min(value.memberUUIDs.count, max(0, change.memberIndex ?? value.memberUUIDs.count))) }
            }
            if let id = change.referenceBefore?.id ?? change.referenceAfter?.id {
                value.references.removeAll { $0.id == id }
                if let reference = change.referenceAfter { value.references.append(reference) }
            }
            value.placements.removeAll { $0.itemUUID == change.itemUUID }
            if let placement = change.after { try placement.validate(); value.placements.append(placement) }
            canvas.hiddenItemUUIDs.removeAll { $0 == change.itemUUID }
            if change.hiddenAfter { canvas.hiddenItemUUIDs.append(change.itemUUID) }
        }
        for change in patch.drawings {
            guard canvas.drawings.first(where: { $0.id == change.id }) == change.before else { throw SpaceCompositionError.conflict }
            canvas.drawings.removeAll { $0.id == change.id }
            if let drawing = change.after {
                guard drawing.id == change.id else { throw SpaceCompositionError.invalidMetadata }
                try drawing.validate(); canvas.drawings.append(drawing)
            }
        }
        for change in patch.clusters {
            guard canvas.clusters.first(where: { $0.id == change.id }) == change.before else { throw SpaceCompositionError.conflict }
            canvas.clusters.removeAll { $0.id == change.id }
            if let cluster = change.after { try cluster.validate(); canvas.clusters.append(cluster) }
        }
        var updated = try atom.replacingSpaceComposition(value).replacingSpaceCanvas(canvas)
        updated.updatedAt = ISO8601.string(from: Date())
        updated.localVersion = atom.localVersion + 1
        try db.execute(sql: """
            UPDATE atoms SET metadata = ?, updated_at = ?, _local_version = ?, _local_pending = 1
            WHERE uuid = ? AND is_deleted = 0
            """, arguments: [updated.metadata, updated.updatedAt, updated.localVersion, atom.uuid])
        return updated
    }

    private static func validateGroupEdge(parent: String, child: Atom, db: Database) throws {
        var pending = [child], visited = Set<String>()
        while let atom = pending.popLast() {
            guard atom.uuid != parent else { throw SpaceCompositionError.cycle }
            guard visited.insert(atom.uuid).inserted else { continue }
            guard let metadata = try atom.decodedSpaceComposition(), metadata.kind == .group else { continue }
            pending += try Atom.filter(metadata.memberUUIDs.contains(Column("uuid"))).filter(Column("is_deleted") == false).fetchAll(db)
        }
    }
}
