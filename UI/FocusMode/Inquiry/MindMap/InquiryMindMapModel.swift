// CosmoOS/UI/FocusMode/Inquiry/MindMap/InquiryMindMapModel.swift
// Data model + builders for the shared 2D mind map. Two sources:
// a full Deep Dive (Map tab — CONCEPT-FIRST: topic → core concepts →
// child concepts, with questions as subordinate satellites) and a live
// session research tree (Cmd+M overlay, question-based, scoped to the session).

import Foundation
import CoreGraphics

struct MindMapNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case root
        case coreConcept       // Top-level pillar of the deep dive
        case childConcept      // Nested concept page
        case seedling          // Incubating concept mass (no page yet)
        case question          // Satellite under its concept (or session-tree branch)
        case subQuestion
        case questionGroup     // "Open questions" bucket / "+N more" overflow
        case page              // Authored Space Page, with its own containment
        case material          // A source or work linked to the Space
    }
    var id: String
    var kind: Kind
    var title: String
    var subtitle: String?
    var isActive: Bool = false
    var isRipe: Bool = false   // Seedlings only: ready for development
    /// Cartographer scaffolding: a grouping page with no notes of its own yet.
    /// Styled as a chapter header until research makes it a real concept.
    var isSection: Bool = false
    /// A PROPOSED section — not yet real. Rendered dashed with accept/✕
    /// controls; `proposalKey` routes the ruling.
    var isGhost: Bool = false
    var proposalKey: String? = nil
    /// Set by `pruned(root:collapsed:)`: how many descendants are folded away.
    var collapsedCount: Int = 0
    var atomUUID: String?
    var branchNodeId: String?
    var children: [MindMapNode] = []

    var totalCount: Int {
        1 + children.reduce(0) { $0 + $1.totalCount }
    }

    var isConcept: Bool {
        kind == .coreConcept || kind == .childConcept
    }
}

/// A non-tree edge between two concept nodes (cross-connection hyperlink).
struct MindMapConceptLink: Identifiable, Hashable {
    var fromNodeId: String
    var toNodeId: String
    var id: String { "\(fromNodeId)~\(toNodeId)" }
}

/// The full-topic map: a tidy tree plus the concept cross-links layered on it.
struct MindMapGraph {
    var root: MindMapNode
    var conceptLinks: [MindMapConceptLink] = []
    /// Ghost-proposal edges: proposed section → each member it would gather.
    var ghostLinks: [MindMapConceptLink] = []
}

enum MindMapBuilder {
    static let nodeCap = 80
    static let questionsPerConcept = 5
    static let conceptLinkCap = 12
    static let seedlingCap = 12

    /// Full-topic map, concept-first: deep dive root → core concepts (pages
    /// with no parent) → child concepts (via ConnectionHierarchyMetadata, with
    /// a title token-subset fallback for legacy pages) → anchored questions as
    /// subordinate satellites. Questions no concept claims collapse into one
    /// "Open questions" bucket instead of flooding the top level.
    static func buildDeepDive(
        deepDive: Atom,
        questions: [Atom],
        connections: [Atom],
        extracts: [Atom],
        seedbed: [IncubatingConcept] = [],
        activeQuestionUUID: String? = nil,
        includeQuestions: Bool = true
    ) -> MindMapGraph {
        let connectionsByUUID = Dictionary(uniqueKeysWithValues: connections.map { ($0.uuid, $0) })
        let parentByUUID = conceptParents(connections: connections, connectionsByUUID: connectionsByUUID)
        let childConceptsByParent = Dictionary(grouping: connections.filter { parentByUUID[$0.uuid] != nil }) {
            parentByUUID[$0.uuid] ?? ""
        }

        var promotedCounts: [String: Int] = [:]
        for extract in extracts {
            if let target = extract.extractMetadata?.promotedToUUID {
                promotedCounts[target, default: 0] += 1
            }
        }

        // Question anchoring: which concept does each root question feed?
        let deduped = DeepDiveOverviewViewModel.dedupeQuestions(questions, extractCount: { question in
            extracts.filter { $0.extractMetadata?.parentQuestionUUID == question.uuid }.count
        })
        let rootQuestions = deduped.filter { $0.questionMetadata?.parentQuestionUUID == nil }
        let subQuestionsByParent = Dictionary(grouping: deduped.filter { $0.questionMetadata?.parentQuestionUUID != nil }) {
            $0.questionMetadata?.parentQuestionUUID ?? ""
        }
        var anchoredQuestions: [String: [Atom]] = [:]   // concept UUID → root questions
        var unanchored: [Atom] = []
        if includeQuestions {
            for question in rootQuestions {
                if let anchor = anchorConcept(
                    for: question,
                    extracts: extracts,
                    connections: connections,
                    connectionsByUUID: connectionsByUUID
                ) {
                    anchoredQuestions[anchor, default: []].append(question)
                } else {
                    unanchored.append(question)
                }
            }
        }

        // Subtree weight (notes in a concept + all descendants) drives ordering.
        func subtreeWeight(_ uuid: String) -> Int {
            let own = promotedCounts[uuid] ?? 0
            let anchored = (anchoredQuestions[uuid] ?? []).count
            let children = (childConceptsByParent[uuid] ?? []).reduce(0) { $0 + subtreeWeight($1.uuid) }
            return own + anchored + children + 1
        }

        // Weight ties break on title then uuid so the map never reshuffles
        // between identical rebuilds (Swift's sort is not stable).
        func orderedByWeight(_ list: [Atom]) -> [Atom] {
            list.sorted { lhs, rhs in
                let lhsWeight = subtreeWeight(lhs.uuid)
                let rhsWeight = subtreeWeight(rhs.uuid)
                if lhsWeight != rhsWeight { return lhsWeight > rhsWeight }
                if lhs.title != rhs.title { return (lhs.title ?? "") < (rhs.title ?? "") }
                return lhs.uuid < rhs.uuid
            }
        }

        var budget = nodeCap

        func questionNode(_ question: Atom, depth: Int) -> MindMapNode? {
            guard budget > 0 else { return nil }
            budget -= 1
            let noteCount = extracts.filter { $0.extractMetadata?.parentQuestionUUID == question.uuid }.count
            let children = (subQuestionsByParent[question.uuid] ?? [])
                .compactMap { questionNode($0, depth: depth + 1) }
            return MindMapNode(
                id: "question-\(question.uuid)",
                kind: depth == 0 ? .question : .subQuestion,
                title: question.title ?? "Untitled question",
                subtitle: noteCount > 0 ? notesLabel(noteCount) : nil,
                isActive: question.uuid == activeQuestionUUID,
                atomUUID: question.uuid,
                children: children
            )
        }

        func conceptNode(_ connection: Atom, depth: Int) -> MindMapNode? {
            guard budget > 0 else { return nil }
            budget -= 1
            var children: [MindMapNode] = []
            // Child concepts first — they ARE the structure.
            for child in orderedByWeight(childConceptsByParent[connection.uuid] ?? []) {
                if let node = conceptNode(child, depth: depth + 1) { children.append(node) }
            }
            // Then the questions this concept is being interrogated through.
            let anchored = (anchoredQuestions[connection.uuid] ?? [])
                .sorted { lhs, rhs in
                    let lhsCount = extracts.filter { $0.extractMetadata?.parentQuestionUUID == lhs.uuid }.count
                    let rhsCount = extracts.filter { $0.extractMetadata?.parentQuestionUUID == rhs.uuid }.count
                    if lhsCount != rhsCount { return lhsCount > rhsCount }
                    return lhs.uuid < rhs.uuid
                }
            for question in anchored.prefix(questionsPerConcept) {
                if let node = questionNode(question, depth: 0) { children.append(node) }
            }
            if anchored.count > questionsPerConcept, budget > 0 {
                budget -= 1
                children.append(MindMapNode(
                    id: "more-questions-\(connection.uuid)",
                    kind: .questionGroup,
                    title: "+\(anchored.count - questionsPerConcept) more questions"
                ))
            }
            let noteCount = promotedCounts[connection.uuid] ?? 0
            let branchCount = (childConceptsByParent[connection.uuid] ?? []).count
            // Scaffolding stays a "section" only until research reaches it —
            // its own promoted notes graduate it into a normal concept card.
            let isSection = connection.metadataValue(as: ConnectionHierarchyMetadata.self)?.isSection == true
                && noteCount == 0
            var subtitleParts: [String] = []
            if isSection, branchCount > 0 {
                subtitleParts.append("\(branchCount) concept\(branchCount == 1 ? "" : "s")")
            } else {
                if noteCount > 0 { subtitleParts.append(notesLabel(noteCount)) }
                if branchCount > 0 { subtitleParts.append("\(branchCount) branch\(branchCount == 1 ? "" : "es")") }
            }
            return MindMapNode(
                id: "concept-\(connection.uuid)",
                kind: depth == 0 ? .coreConcept : .childConcept,
                title: connection.title ?? "Concept",
                subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
                isSection: isSection,
                atomUUID: connection.uuid,
                children: children
            )
        }

        // Core concepts (no parent) are the map's primary branches.
        var branches = orderedByWeight(connections.filter { parentByUUID[$0.uuid] == nil })
            .compactMap { conceptNode($0, depth: 0) }

        // Seedlings: incubating concept mass orbits its parent concept (merge
        // target, then parentConceptName match), else the root. Ripe first,
        // capped so the map stays legible — visible mass, zero canvas clutter.
        let connectionByKey = Dictionary(
            connections.compactMap { connection -> (String, String)? in
                guard let title = connection.title, !title.isEmpty else { return nil }
                let key = ConceptResolver.conceptKey(title)
                return key.isEmpty ? nil : (key, connection.uuid)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let displaySeedlings = seedbed
            .filter { $0.status == .incubating && !$0.pendingItems.isEmpty }
            .sorted { lhs, rhs in
                let lhsRipe = ConceptRipeness.evaluate(lhs).isRipe
                let rhsRipe = ConceptRipeness.evaluate(rhs).isRipe
                if lhsRipe != rhsRipe { return lhsRipe }
                return lhs.pendingItems.count > rhs.pendingItems.count
            }
            .prefix(seedlingCap)
        for seedling in displaySeedlings where budget > 0 {
            budget -= 1
            let verdict = ConceptRipeness.evaluate(seedling)
            let pending = seedling.pendingItems.count
            let node = MindMapNode(
                id: "seedling-\(seedling.conceptKey)",
                kind: .seedling,
                title: seedling.name,
                subtitle: verdict.reason.map { "Ripe · \($0)" } ?? "\(pending) capture\(pending == 1 ? "" : "s")",
                isRipe: verdict.isRipe
            )
            let anchorUUID = seedling.mergeTargetConnectionUUID
                ?? seedling.parentConceptName.flatMap { connectionByKey[ConceptResolver.conceptKey($0)] }
            if let anchorUUID, appendChild(node, toNodeId: "concept-\(anchorUUID)", in: &branches) {
                continue
            }
            branches.append(node)
        }

        // Leftover questions live in ONE muted bucket — never as top-level peers.
        if !unanchored.isEmpty, budget > 0 {
            budget -= 1
            let bucketChildren = unanchored.compactMap { questionNode($0, depth: 0) }
            branches.append(MindMapNode(
                id: "open-questions",
                kind: .questionGroup,
                title: "Open questions",
                subtitle: "\(unanchored.count)",
                children: bucketChildren
            ))
        }

        let root = MindMapNode(
            id: "deepdive-\(deepDive.uuid)",
            kind: .root,
            title: deepDive.title ?? "Deep Dive",
            subtitle: branches.isEmpty ? "Start an inquiry to grow the map" : nil,
            atomUUID: deepDive.uuid,
            children: branches
        )
        return MindMapGraph(
            root: root,
            conceptLinks: conceptLinks(root: root, connections: connections, parentByUUID: parentByUUID)
        )
    }

    /// Session-scoped map from the live research tree.
    static func buildSessionTree(
        tree: ResearchTreeDocument,
        rootTitle: String,
        questionTitle: (String?) -> String,
        countsLabel: (String?) -> String?,
        activeQuestionUUID: String?
    ) -> MindMapNode {
        var budget = nodeCap
        func walk(_ nodeId: String, depth: Int) -> MindMapNode? {
            guard budget > 0,
                  let node = tree.nodes[nodeId],
                  node.kind == .question,
                  node.meta.visibility != .hidden else { return nil }
            budget -= 1
            let children = node.childNodeIds
                .sorted { (tree.nodes[$0]?.branchOrder ?? 0) < (tree.nodes[$1]?.branchOrder ?? 0) }
                .compactMap { walk($0, depth: depth + 1) }
            let title = node.atomUUID.map { questionTitle($0) } ?? (node.meta.label ?? "Untitled")
            return MindMapNode(
                id: "node-\(node.id)",
                kind: depth == 0 ? .question : .subQuestion,
                title: title,
                subtitle: countsLabel(node.atomUUID),
                isActive: node.atomUUID != nil && node.atomUUID == activeQuestionUUID,
                atomUUID: node.atomUUID,
                branchNodeId: node.id,
                children: children
            )
        }

        let branches = tree.rootQuestionNodeIds.compactMap { walk($0, depth: 0) }
        return MindMapNode(
            id: "session-root",
            kind: .root,
            title: rootTitle,
            children: branches
        )
    }

    /// "1 note" / "3 notes" — the map's one count voice.
    static func notesLabel(_ count: Int) -> String {
        count == 1 ? "1 note" : "\(count) notes"
    }

    // MARK: - Ghost proposals

    /// Layers the Cartographer's GROUP proposals onto the map as ghost
    /// section nodes: each ghost lands beside its first member branch with
    /// dashed edges to every member. Nest proposals stay off the tree (they
    /// render as tending rows) — only groups earn a ghost.
    static func addingGhostProposals(
        _ graph: MindMapGraph,
        proposals: [ConceptCartographerProposal]
    ) -> MindMapGraph {
        var graph = graph
        for proposal in proposals {
            guard case .group(let name, let memberUUIDs) = proposal.kind else { continue }
            let presentIds = Set(collectNodeIds(graph.root))
            let memberNodeIds = memberUUIDs.map { "concept-\($0)" }.filter { presentIds.contains($0) }
            guard memberNodeIds.count >= 2 else { continue }
            let ghost = MindMapNode(
                id: "ghost-\(proposal.key)",
                kind: .coreConcept,
                title: name,
                subtitle: "Proposed · \(memberNodeIds.count) concepts",
                isSection: true,
                isGhost: true,
                proposalKey: proposal.key
            )
            // Beside its first member, so the dashed edges stay short.
            let insertIndex = graph.root.children.firstIndex { memberNodeIds.contains($0.id) }
                ?? graph.root.children.count
            graph.root.children.insert(ghost, at: insertIndex)
            graph.ghostLinks += memberNodeIds.map {
                MindMapConceptLink(fromNodeId: ghost.id, toNodeId: $0)
            }
        }
        return graph
    }

    private static func collectNodeIds(_ node: MindMapNode) -> [String] {
        [node.id] + node.children.flatMap(collectNodeIds)
    }

    // MARK: - Collapse

    /// Pure fold: children of collapsed nodes are removed before layout, and
    /// the folded node remembers how many descendants it hides ("+N" badge).
    static func pruned(root: MindMapNode, collapsed: Set<String>) -> MindMapNode {
        var copy = root
        if collapsed.contains(copy.id), !copy.children.isEmpty {
            copy.collapsedCount = copy.totalCount - 1
            copy.children = []
            return copy
        }
        copy.children = copy.children.map { pruned(root: $0, collapsed: collapsed) }
        return copy
    }

    /// Recursively appends `child` to the node with `toNodeId` inside a value
    /// tree. Returns false when the target is not present (caller falls back
    /// to a top-level attach).
    private static func appendChild(_ child: MindMapNode, toNodeId targetId: String, in nodes: inout [MindMapNode]) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == targetId {
                nodes[index].children.append(child)
                return true
            }
            if appendChild(child, toNodeId: targetId, in: &nodes[index].children) {
                return true
            }
        }
        return false
    }

    // MARK: - Concept hierarchy

    /// Parent map for the concept tree. Precedence per connection:
    /// 1. Persisted `ConnectionHierarchyMetadata.parentConnectionUUID`
    ///    (validated: parent exists on this dive, no self-reference).
    /// 2. Legacy fallback: another page whose title tokens are a proper subset
    ///    of this one's ("Breathing" ⊂ "Box breathing" ⇒ nest under it).
    /// Cycles from persisted data break deterministically (offending edge cut).
    static func conceptParents(
        connections: [Atom],
        connectionsByUUID: [String: Atom]
    ) -> [String: String] {
        var parentByUUID: [String: String] = [:]
        for connection in connections {
            if let parent = connection.metadataValue(as: ConnectionHierarchyMetadata.self)?.parentConnectionUUID,
               parent != connection.uuid,
               connectionsByUUID[parent] != nil {
                parentByUUID[connection.uuid] = parent
            }
        }

        let tokensByUUID: [String: Set<String>] = connections.reduce(into: [:]) { partial, connection in
            let key = ConceptResolver.conceptKey(connection.title ?? "")
            partial[connection.uuid] = Set(key.split(separator: " ").map(String.init))
        }
        for connection in connections where parentByUUID[connection.uuid] == nil {
            // An explicit top-level choice must survive legacy title heuristics.
            if connection.metadataValue(as: ConnectionHierarchyMetadata.self)?.parentPinnedByUser == true { continue }
            guard let ownTokens = tokensByUUID[connection.uuid], ownTokens.count >= 2 else { continue }
            let candidates = connections.filter { other in
                guard other.uuid != connection.uuid,
                      let otherTokens = tokensByUUID[other.uuid],
                      !otherTokens.isEmpty, otherTokens != ownTokens else { return false }
                return otherTokens.isSubset(of: ownTokens)
            }
            // Most specific parent (largest token overlap) wins; ties break
            // on uuid so the hierarchy is identical across rebuilds.
            if let best = candidates.min(by: { lhs, rhs in
                let lhsCount = tokensByUUID[lhs.uuid]?.count ?? 0
                let rhsCount = tokensByUUID[rhs.uuid]?.count ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.uuid < rhs.uuid
            }) {
                parentByUUID[connection.uuid] = best.uuid
            }
        }

        // Break cycles: walk each ancestry; on revisit, cut the edge where the
        // walk started so both nodes surface as core rather than vanishing.
        for uuid in parentByUUID.keys.sorted() {
            var visited: Set<String> = [uuid]
            var cursor = parentByUUID[uuid]
            while let current = cursor {
                if visited.contains(current) {
                    parentByUUID[uuid] = nil
                    break
                }
                visited.insert(current)
                cursor = parentByUUID[current]
            }
        }
        return parentByUUID
    }

    /// Which concept a root question feeds, by strongest available signal:
    /// promoted extracts → capture-time concept tags → question-title match.
    static func anchorConcept(
        for question: Atom,
        extracts: [Atom],
        connections: [Atom],
        connectionsByUUID: [String: Atom]
    ) -> String? {
        let questionExtracts = extracts.filter { $0.extractMetadata?.parentQuestionUUID == question.uuid }

        // Tally ties break on uuid — Dictionary iteration order is unordered,
        // so a bare `.max`/`.first` made anchoring flip between rebuilds.
        func dominant(in tally: [String: Int]) -> String? {
            tally.min { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }?.key
        }

        var promotedTally: [String: Int] = [:]
        for extract in questionExtracts {
            if let target = extract.extractMetadata?.promotedToUUID, connectionsByUUID[target] != nil {
                promotedTally[target, default: 0] += 1
            }
        }
        if let anchor = dominant(in: promotedTally) { return anchor }

        let connectionByKey = Dictionary(
            connections.compactMap { connection -> (String, String)? in
                guard let title = connection.title, !title.isEmpty else { return nil }
                return (ConceptResolver.conceptKey(title), connection.uuid)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var tagTally: [String: Int] = [:]
        for extract in questionExtracts {
            for concept in extract.extractMetadata?.conceptNames ?? [] {
                if let uuid = connectionByKey[ConceptResolver.conceptKey(concept)] {
                    tagTally[uuid, default: 0] += 1
                }
            }
        }
        if let anchor = dominant(in: tagTally) { return anchor }

        let questionKey = ConceptResolver.conceptKey(
            ConceptResolver.conceptName(fromQuestion: question.title ?? "")
        )
        guard questionKey.count >= 4 else { return nil }
        // Most specific (longest) matching key wins; ties break on key.
        return connectionByKey
            .filter { key, _ in key.count >= 4 && (questionKey.contains(key) || key.contains(questionKey)) }
            .min { lhs, rhs in
                if lhs.key.count != rhs.key.count { return lhs.key.count > rhs.key.count }
                return lhs.key < rhs.key
            }?
            .value
    }

    // MARK: - Cross-link edges

    /// Hyperlink pairs between concept nodes both present on the map, minus
    /// pairs already joined by a tree edge. Capped to stay legible.
    private static func conceptLinks(
        root: MindMapNode,
        connections: [Atom],
        parentByUUID: [String: String]
    ) -> [MindMapConceptLink] {
        var presentUUIDs = Set<String>()
        func collect(_ node: MindMapNode) {
            if node.isConcept, let uuid = node.atomUUID { presentUUIDs.insert(uuid) }
            node.children.forEach(collect)
        }
        collect(root)

        var seen = Set<String>()
        var links: [MindMapConceptLink] = []
        for connection in connections {
            guard presentUUIDs.contains(connection.uuid) else { continue }
            for link in connection.linksList
            where link.type == AtomLinkType.connection.rawValue
                && link.entityType == AtomType.connection.rawValue
                && presentUUIDs.contains(link.uuid) {
                let pairKey = [connection.uuid, link.uuid].sorted().joined(separator: "~")
                guard !seen.contains(pairKey),
                      parentByUUID[connection.uuid] != link.uuid,
                      parentByUUID[link.uuid] != connection.uuid else { continue }
                seen.insert(pairKey)
                links.append(MindMapConceptLink(
                    fromNodeId: "concept-\(connection.uuid)",
                    toNodeId: "concept-\(link.uuid)"
                ))
                if links.count >= conceptLinkCap { return links }
            }
        }
        return links
    }
}
