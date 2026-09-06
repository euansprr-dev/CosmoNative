import Foundation

/// Read-only wire projection shared by Mac and iPhone. No graph operation writes
/// inferred structure back into atoms or treats a reference as Page containment.
public struct SpaceMapRelation: Equatable, Sendable {
    public var type: String
    public var targetID: String
    public init(type: String, targetID: String) { self.type = type; self.targetID = targetID }
}

public struct SpaceMapRecord: Equatable, Sendable {
    public var id: String
    public var type: String
    public var title: String
    public var metadata: String?
    public var structured: String?
    public var links: [SpaceMapRelation]
    public init(id: String, type: String, title: String, metadata: String? = nil,
                structured: String? = nil, links: [SpaceMapRelation] = []) {
        self.id = id; self.type = type; self.title = title
        self.metadata = metadata; self.structured = structured; self.links = links
    }
}

public struct SpaceMapNode: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case root, concept, page, question, material, group }
    public var id: String
    public var atomID: String?
    public var kind: Kind
    public var title: String
    public var subtitle: String?
    public var children: [SpaceMapNode] = []
    public var isSection = false
    public var isMatch = false
}

public struct SpaceMapEdge: Equatable, Sendable, Identifiable {
    public var fromID: String
    public var toID: String
    public var relation: String
    public var id: String { [fromID, toID].sorted().joined(separator: "~") }
}

public struct SpaceMapGraph: Equatable, Sendable {
    public var root: SpaceMapNode
    public var links: [SpaceMapEdge]
    public var omittedCount: Int
    public var omittedLinkCount: Int
    public var matchCount: Int
}

public enum SpaceMapGraphBuilder {
    private static let relationshipTypes: Set<String> = [
        "connection", "concept_link", "related", "links_to", "linked_from", "source",
        "question_linked_connection", "question_source", "output_from_inquiry", "output_from_deep_dive",
        "content_from_deep_dive", "content_to_idea", "idea_to_content", "origin_idea", "parent_idea",
        "extract_promoted_to", "extract_from_source", "extract_in_question", "session_used_source"
    ]

    /// The loader fetches these one-hop targets only. It must not recursively
    /// expand the global knowledge graph beyond a Space's actual references.
    public static func referencedIDs(in records: [SpaceMapRecord]) -> Set<String> {
        Set(records.flatMap { record -> [String] in
            let meta = object(record.metadata), data = object(record.structured)
            let composition = meta["spaceComposition"] as? [String: Any] ?? [:]
            var ids = record.links.filter { relationshipTypes.contains($0.type) || $0.type.hasPrefix("deep_dive_") }.map(\.targetID)
            ids += (composition["references"] as? [[String: Any]] ?? []).compactMap { $0["sourceUUID"] as? String }
            ids += (composition["memberUUIDs"] as? [String] ?? [])
            ids += ["sourceUUID", "promotedToUUID", "parentConnectionUUID", "pageContentSourceUUID", "mainQuestionUUID"].compactMap { meta[$0] as? String }
            ids += (data["relatedConceptUUIDs"] as? [String] ?? [])
            ids += (data["sources"] as? [[String: Any]] ?? []).compactMap { $0["sourceUUID"] as? String }
            ids += (data["sourceRefs"] as? [[String: Any]] ?? []).compactMap { $0["sourceUUID"] as? String }
            ids += (data["sourceTabs"] as? [[String: Any]] ?? []).compactMap { $0["sourceUUID"] as? String }
            for item in connectionItems(data) {
                ids += ["linkedConnectionUUID", "sourceAtomUUID"].compactMap { item[$0] as? String }
            }
            if let origin = composition["origin"] as? [String: Any], let id = origin["sourceUUID"] as? String { ids.append(id) }
            return ids.filter { !$0.isEmpty }
        })
    }

    public static func build(spaceID: String, title: String, records: [SpaceMapRecord], memberIDs: Set<String>,
                             topicID: String? = nil, showMaterials: Bool = false, query: String = "",
                             nodeLimit: Int = 240) -> SpaceMapGraph {
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let metadata = byID.mapValues { object($0.metadata) }
        let structured = byID.mapValues { object($0.structured) }
        let profiles = Set(records.filter { $0.type == "deep_dive" }.map(\.id))
        var scoped: Set<String>
        if let topicID {
            scoped = Set(records.filter { metadata[$0.id]?["parentDeepDiveUUID"] as? String == topicID }.map(\.id))
            scoped.insert(topicID)
            scoped.formUnion(byID[topicID]?.links.filter { $0.type.hasPrefix("deep_dive_") }.map(\.targetID) ?? [])
        } else {
            scoped = memberIDs.union(profiles)
            scoped.formUnion(records.filter { profiles.contains(metadata[$0.id]?["parentDeepDiveUUID"] as? String ?? "") }.map(\.id))
            for id in profiles { scoped.formUnion(byID[id]?.links.filter { $0.type.hasPrefix("deep_dive_") }.map(\.targetID) ?? []) }
        }
        // References expand scope once, and referenced Pages bring their authored
        // ancestors, never unrelated items from another topic or Space.
        scoped.formUnion(referencedIDs(in: scoped.compactMap { byID[$0] }))
        if topicID != nil {
            let topicScope = scoped
            for record in records where memberIDs.contains(record.id) && record.type == "note" {
                if !referencedIDs(in: [record]).isDisjoint(with: topicScope) { scoped.insert(record.id) }
            }
        }
        for id in scoped.sorted() {
            var cursor = id, visited = Set<String>()
            while visited.insert(cursor).inserted,
                  let composition = metadata[cursor]?["spaceComposition"] as? [String: Any],
                  let parent = composition["parentUUID"] as? String, memberIDs.contains(parent) {
                scoped.insert(parent); cursor = parent
            }
        }
        var kinds: [String: SpaceMapNode.Kind] = [:]
        for id in scoped {
            guard let record = byID[id] else { continue }
            let composition = metadata[id]?["spaceComposition"] as? [String: Any]
            switch record.type {
            case "connection": kinds[id] = .concept
            case "note": kinds[id] = composition?["kind"] as? String == "group" ? (showMaterials ? .material : nil) : .page
            case "question": kinds[id] = .question
            case "research", "idea", "content", "image", "file", "swipe", "task", "lexicon_entry":
                if showMaterials { kinds[id] = .material }
            default: break
            }
        }
        var parents: [String: String] = [:]
        for (id, kind) in kinds {
            let meta = metadata[id] ?? [:]
            let composition = meta["spaceComposition"] as? [String: Any] ?? [:]
            let parent: String?
            switch kind {
            case .concept: parent = meta["parentConnectionUUID"] as? String
            case .page: parent = composition["parentUUID"] as? String
            case .question: parent = meta["parentQuestionUUID"] as? String
            default: parent = nil
            }
            if let parent, parent != id, kinds[parent] == kind { parents[id] = parent }
        }
        // Explicit question/concept assignments take precedence over promoted
        // evidence. Names and title overlap never manufacture hierarchy.
        var promotedByQuestion: [String: [String: Int]] = [:]
        for record in byID.values {
            if let question = metadata[record.id]?["parentQuestionUUID"] as? String,
               let concept = metadata[record.id]?["promotedToUUID"] as? String, kinds[concept] == .concept {
                promotedByQuestion[question, default: [:]][concept, default: 0] += 1
            }
        }
        for id in kinds.keys.sorted() where kinds[id] == .question && parents[id] == nil {
            let direct = (structured[id]?["relatedConceptUUIDs"] as? [String] ?? []) +
                (byID[id]?.links.filter { $0.type == "question_linked_connection" }.map(\.targetID) ?? [])
            if let concept = direct.sorted().first(where: { kinds[$0] == .concept }) { parents[id] = concept; continue }
            let counts = promotedByQuestion[id] ?? [:]
            parents[id] = counts.keys.sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0, default: 0] > counts[$1, default: 0] }.first
        }
        parents = acyclicParents(parents)
        let ordered = kinds.keys.sorted {
            let leftOrder = (metadata[$0]?["spaceComposition"] as? [String: Any])?["sortOrder"] as? Double ?? 0
            let rightOrder = (metadata[$1]?["spaceComposition"] as? [String: Any])?["sortOrder"] as? Double ?? 0
            if kinds[$0] == .page, kinds[$1] == .page, leftOrder != rightOrder { return leftOrder < rightOrder }
            let left = byID[$0]?.title ?? "", right = byID[$1]?.title ?? ""
            return left == right ? $0 < $1 : left.localizedStandardCompare(right) == .orderedAscending
        }
        let children = Dictionary(grouping: ordered.filter { parents[$0] != nil }, by: { parents[$0]! })
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = Set(ordered.filter { normalizedQuery.isEmpty || byID[$0]?.title.localizedStandardContains(normalizedQuery) == true })
        var visible = matches
        for id in matches { var cursor = parents[id]; while let parent = cursor { visible.insert(parent); cursor = parents[parent] } }
        // Breadth-first admission retains every admitted node's ancestry and
        // avoids a single large branch consuming the entire render budget.
        var queue = ordered.filter { parents[$0] == nil && visible.contains($0) }, admitted = Set<String>(), index = 0
        let limit = max(1, nodeLimit)
        while index < queue.count, admitted.count < limit {
            let id = queue[index]; index += 1
            admitted.insert(id); queue += (children[id] ?? []).filter { visible.contains($0) }
        }
        func node(_ id: String) -> SpaceMapNode {
            let kind = kinds[id] ?? .material
            let childNodes = (children[id] ?? []).filter { admitted.contains($0) }.map(node)
            return SpaceMapNode(id: id, atomID: id, kind: kind, title: byID[id]?.title ?? "Untitled",
                subtitle: kind == .page ? "Page" : kind == .material ? byID[id]?.type.replacingOccurrences(of: "_", with: " ").capitalized : nil,
                children: childNodes, isSection: metadata[id]?["isSection"] as? Bool == true,
                isMatch: !normalizedQuery.isEmpty && matches.contains(id))
        }
        let top = ordered.filter { parents[$0] == nil && admitted.contains($0) }
        var branches = top.filter { kinds[$0] == .concept }.map(node)
        for (kind, label) in [(SpaceMapNode.Kind.page, "Pages"), (.question, "Questions"), (.material, "Materials & work")] {
            let nodes = top.filter { kinds[$0] == kind }.map(node)
            if !nodes.isEmpty { branches.append(SpaceMapNode(id: "space-map-\(kind.rawValue)-\(spaceID)", kind: .group, title: label, subtitle: "\(nodes.count)", children: nodes)) }
        }
        var edges: [SpaceMapEdge] = [], seen = Set<String>()
        func edge(_ from: String, _ to: String, _ relation: String) {
            guard from != to, admitted.contains(from), admitted.contains(to), parents[from] != to, parents[to] != from else { return }
            let value = SpaceMapEdge(fromID: from, toID: to, relation: relation)
            if seen.insert(value.id).inserted { edges.append(value) }
        }
        for id in scoped.sorted() {
            guard let record = byID[id] else { continue }
            for link in record.links where relationshipTypes.contains(link.type) {
                if link.type == "output_from_inquiry", let question = metadata[link.targetID]?["mainQuestionUUID"] as? String {
                    edge(id, question, link.type)
                } else { edge(id, link.targetID, link.type) }
            }
            let meta = metadata[id] ?? [:], data = structured[id] ?? [:]
            let composition = meta["spaceComposition"] as? [String: Any] ?? [:]
            for ref in composition["references"] as? [[String: Any]] ?? [] { if let source = ref["sourceUUID"] as? String { edge(id, source, "source") } }
            for member in composition["memberUUIDs"] as? [String] ?? [] { edge(id, member, "member") }
            if let origin = composition["origin"] as? [String: Any], let source = origin["sourceUUID"] as? String { edge(id, source, "adapted_from") }
            for concept in data["relatedConceptUUIDs"] as? [String] ?? [] { edge(id, concept, "question_linked_connection") }
            for item in connectionItems(data) {
                if let target = item["linkedConnectionUUID"] as? String { edge(id, target, "connection") }
                if let source = item["sourceAtomUUID"] as? String {
                    if byID[source]?.type == "extract", let origin = metadata[source]?["sourceUUID"] as? String {
                        edge(id, origin, "evidence")
                    } else { edge(id, source, "source") }
                }
            }
            if let source = meta["pageContentSourceUUID"] as? String { edge(id, source, "source") }
            if let source = meta["sourceUUID"] as? String {
                if let concept = meta["promotedToUUID"] as? String { edge(concept, source, "evidence") }
                if let question = meta["parentQuestionUUID"] as? String { edge(question, source, "question_source") }
            }
            for source in data["sources"] as? [[String: Any]] ?? [] { if let target = source["sourceUUID"] as? String { edge(id, target, "question_source") } }
            if let question = meta["mainQuestionUUID"] as? String {
                let sourceRefs = (data["sourceRefs"] as? [[String: Any]] ?? []) + (data["sourceTabs"] as? [[String: Any]] ?? [])
                for source in sourceRefs { if let target = source["sourceUUID"] as? String { edge(question, target, "session_used_source") } }
                for source in record.links where source.type == "session_used_source" { edge(question, source.targetID, source.type) }
            }
        }
        let root = SpaceMapNode(id: "space-map-root-\(spaceID)-\(topicID ?? "all")", atomID: spaceID, kind: .root,
                                title: topicID.flatMap { byID[$0]?.title } ?? title, children: branches)
        return SpaceMapGraph(root: root, links: Array(edges.prefix(480)), omittedCount: visible.count - admitted.count,
                             omittedLinkCount: max(0, edges.count - 480), matchCount: matches.count)
    }

    public static func acyclicParents(_ source: [String: String]) -> [String: String] {
        var result = source
        var settled = Set<String>()
        for id in source.keys.sorted() {
            var path: [String] = [], positions: [String: Int] = [:], cursor: String? = id
            while let current = cursor, !settled.contains(current) {
                if let cycleStart = positions[current] {
                    // Cut inside the cycle, preserving valid branches that lead
                    // into it. The chosen edge is independent of input order.
                    if let cut = path[cycleStart...].min() { result.removeValue(forKey: cut) }
                    break
                }
                positions[current] = path.count; path.append(current)
                cursor = result[current]
            }
            settled.formUnion(path)
        }
        return result
    }

    private static func connectionItems(_ data: [String: Any]) -> [[String: Any]] {
        (data["sections"] as? [[String: Any]] ?? []).flatMap { $0["items"] as? [[String: Any]] ?? [] }
    }

    private static func object(_ json: String?) -> [String: Any] {
        guard let data = json?.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
