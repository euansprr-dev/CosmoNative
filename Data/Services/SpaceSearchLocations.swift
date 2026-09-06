import Foundation
import GRDB

/// A location describes where an original is reachable. Resolving it never files
/// the item or changes its authored parent, group membership, or canvas position.
public struct SpaceSearchLocation: Hashable, Sendable, Identifiable {
    public let spaceID: String
    public let spaceTitle: String
    public let ancestorUUIDs: [String]
    public let path: [String]
    public var id: String { spaceID }
    public var breadcrumb: String { path.joined(separator: " › ") }
}

struct SpaceSearchNode: Sendable {
    var uuid: String
    var title: String
    var type: String
    var parentUUID: String?
    var isGroup = false
    var memberUUIDs: [String] = []
}

enum SpaceSearchLocationIndex {
    static let commandCenterID = "00000000-CC00-4000-A000-COMMANDCENTER"

    /// Keep the best structural path per ancestor. A Group reached directly
    /// can later gain the richer Page → Book → Group path. Per-trail cycle
    /// checks and strictly improving integer scores bound shared-Group traversal;
    /// equal scores retain the first path from the deterministic edge order.
    static func build(requestedIDs: [String], nodes: [SpaceSearchNode], memberships: [String: Set<String>]) -> [String: [SpaceSearchLocation]] {
        let byID = nodes.reduce(into: [String: SpaceSearchNode]()) { result, node in result[node.uuid] = node }
        struct Edge { var uuid: String; var authored: Bool }
        var parents: [String: [Edge]] = [:]
        for node in nodes {
            if node.type == "note", !node.isGroup, let parent = node.parentUUID,
               let target = byID[parent], target.type == "note", !target.isGroup, parent != node.uuid {
                parents[node.uuid, default: []].append(Edge(uuid: parent, authored: true))
            }
            if node.isGroup {
                for id in Set(node.memberUUIDs) where id != node.uuid {
                    parents[id, default: []].append(Edge(uuid: node.uuid, authored: false))
                }
            }
        }
        for id in parents.keys {
            parents[id]?.sort { lhs, rhs in
                if lhs.authored != rhs.authored { return lhs.authored }
                return lhs.uuid < rhs.uuid
            }
        }
        var result: [String: [SpaceSearchLocation]] = [:]
        for source in Set(requestedIDs) {
            guard let original = byID[source], original.type != "thinkspace" else { continue }
            var queue: [(uuid: String, trail: [String], authored: Int)] = [(source, [source], 0)]
            var cursor = 0
            var best: [String: (authored: Int, depth: Int)] = [source: (0, 0)]
            var candidates: [String: (location: SpaceSearchLocation, authored: Int)] = [:]
            while cursor < queue.count {
                let current = queue[cursor]; cursor += 1
                guard let score = best[current.uuid], score.authored == current.authored,
                      score.depth == current.trail.count - 1 else { continue }
                for spaceID in memberships[current.uuid, default: []] {
                    guard spaceID != commandCenterID, let space = byID[spaceID], space.type == "thinkspace" else { continue }
                    let ancestors = Array(current.trail.dropFirst().reversed())
                    let path = [space.title] + ancestors.compactMap { byID[$0]?.title }
                    let next = SpaceSearchLocation(spaceID: spaceID, spaceTitle: space.title, ancestorUUIDs: ancestors, path: path)
                    let previous = candidates[spaceID]
                    if previous == nil || current.authored > previous!.authored ||
                        (current.authored == previous!.authored && ancestors.count > previous!.location.ancestorUUIDs.count) ||
                        (current.authored == previous!.authored && ancestors.count == previous!.location.ancestorUUIDs.count && next.breadcrumb < previous!.location.breadcrumb) {
                        candidates[spaceID] = (next, current.authored)
                    }
                }
                for edge in parents[current.uuid, default: []] where byID[edge.uuid] != nil && !current.trail.contains(edge.uuid) {
                    let authored = current.authored + (edge.authored ? 1 : 0), depth = current.trail.count
                    if let previous = best[edge.uuid], authored < previous.authored ||
                        (authored == previous.authored && depth <= previous.depth) { continue }
                    best[edge.uuid] = (authored, depth)
                    queue.append((edge.uuid, current.trail + [edge.uuid], authored))
                }
            }
            result[source] = candidates.values.map(\.location).sorted {
                if $0.spaceTitle != $1.spaceTitle { return $0.spaceTitle.localizedStandardCompare($1.spaceTitle) == .orderedAscending }
                return $0.spaceID < $1.spaceID
            }
        }
        return result
    }
}

extension AtomRepository {
    /// Batched path lookup. Only structural JSON is read; rich documents and media
    /// are not hydrated for a search breadcrumb. References are not membership.
    public func searchSpaceLocations(for uuids: [String]) async throws -> [String: [SpaceSearchLocation]] {
        let ids = Array(Set(uuids)).sorted()
        guard !ids.isEmpty else { return [:] }
        return try await CosmoDatabase.shared.asyncRead { db in
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let rows = try Row.fetchAll(db, sql: """
                SELECT uuid, title, type,
                    CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.spaceComposition.parentUUID') END AS parent,
                    CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.spaceComposition.kind') END AS kind,
                    CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.spaceComposition.memberUUIDs') END AS members
                FROM atoms WHERE is_deleted = 0 AND (type IN ('note', 'thinkspace') OR uuid IN (\(placeholders)))
                """, arguments: StatementArguments(ids))
            let nodes = rows.map { row -> SpaceSearchNode in
                let rawMembers: String? = row["members"]
                let members = rawMembers.flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
                let kind: String? = row["kind"]
                return SpaceSearchNode(uuid: row["uuid"], title: row["title"] ?? "Untitled", type: row["type"],
                    parentUUID: row["parent"], isGroup: kind == "group", memberUUIDs: members)
            }
            let memberships = try Row.fetchAll(db, sql: """
                SELECT DISTINCT entity_uuid AS atom, thinkspace_id AS space
                FROM canvas_blocks WHERE document_type = 'home' AND document_id = 0 AND is_deleted = 0
                    AND thinkspace_id IS NOT NULL AND entity_uuid IS NOT NULL
                """).reduce(into: [String: Set<String>]()) { result, row in
                    let uuid: String = row["atom"], spaceID: String = row["space"]
                    result[uuid, default: []].insert(spaceID)
                }
            return SpaceSearchLocationIndex.build(requestedIDs: ids, nodes: nodes, memberships: memberships)
        }
    }
}
