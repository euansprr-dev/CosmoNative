// CosmoOS/UI/FocusMode/Inquiry/MindMap/InquiryMindMapModel.swift
// Data model + builders for the shared 2D mind map. Two sources:
// a full Deep Dive (Map tab: topic → questions → sub-questions → concepts)
// and a live session research tree (Cmd+M overlay, scoped to the session).

import Foundation
import CoreGraphics

struct MindMapNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case root
        case question
        case subQuestion
        case concept
    }
    var id: String
    var kind: Kind
    var title: String
    var subtitle: String?
    var isActive: Bool = false
    var atomUUID: String?
    var branchNodeId: String?
    var children: [MindMapNode] = []

    var totalCount: Int {
        1 + children.reduce(0) { $0 + $1.totalCount }
    }
}

enum MindMapBuilder {
    static let nodeCap = 80

    /// Full-topic map: deep dive root → deduped root questions → sub-questions,
    /// with concept pages attached as leaves where their extracts route.
    static func buildDeepDive(
        deepDive: Atom,
        questions: [Atom],
        connections: [Atom],
        extracts: [Atom],
        activeQuestionUUID: String? = nil
    ) -> MindMapNode {
        let deduped = DeepDiveOverviewViewModel.dedupeQuestions(questions, extractCount: { question in
            extracts.filter { $0.extractMetadata?.parentQuestionUUID == question.uuid }.count
        })
        let rootQuestions = deduped.filter { $0.questionMetadata?.parentQuestionUUID == nil }
        let childrenByParent = Dictionary(grouping: deduped.filter { $0.questionMetadata?.parentQuestionUUID != nil }) {
            $0.questionMetadata?.parentQuestionUUID ?? ""
        }
        let connectionsByKey = Dictionary(
            connections.compactMap { connection -> (String, Atom)? in
                guard let title = connection.title else { return nil }
                return (ConceptResolver.conceptKey(title), connection)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var budget = nodeCap
        func questionNode(_ question: Atom, depth: Int) -> MindMapNode? {
            guard budget > 0 else { return nil }
            budget -= 1
            let questionExtracts = extracts.filter { $0.extractMetadata?.parentQuestionUUID == question.uuid }
            var children: [MindMapNode] = []
            for child in childrenByParent[question.uuid] ?? [] {
                if let node = questionNode(child, depth: depth + 1) { children.append(node) }
            }
            children.append(contentsOf: conceptLeaves(
                for: questionExtracts,
                connectionsByKey: connectionsByKey,
                budget: &budget
            ))
            return MindMapNode(
                id: "question-\(question.uuid)",
                kind: depth == 0 ? .question : .subQuestion,
                title: question.title ?? "Untitled question",
                subtitle: questionExtracts.isEmpty ? nil : "\(questionExtracts.count) notes",
                isActive: question.uuid == activeQuestionUUID,
                atomUUID: question.uuid,
                children: children
            )
        }

        var branches = rootQuestions.compactMap { questionNode($0, depth: 0) }

        // Concept pages not reachable through any question still belong on the map.
        let attachedConnectionUUIDs = Set(allConceptUUIDs(in: branches))
        for connection in connections where !attachedConnectionUUIDs.contains(connection.uuid) {
            guard budget > 0 else { break }
            budget -= 1
            branches.append(conceptNode(connection))
        }

        return MindMapNode(
            id: "deepdive-\(deepDive.uuid)",
            kind: .root,
            title: deepDive.title ?? "Deep Dive",
            subtitle: branches.isEmpty ? "Start an inquiry to grow the map" : nil,
            atomUUID: deepDive.uuid,
            children: branches
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

    // MARK: - Helpers

    private static func conceptLeaves(
        for extracts: [Atom],
        connectionsByKey: [String: Atom],
        budget: inout Int
    ) -> [MindMapNode] {
        var tally: [String: Int] = [:]
        for extract in extracts {
            for concept in extract.extractMetadata?.conceptNames ?? [] {
                tally[concept, default: 0] += 1
            }
        }
        return tally.sorted { $0.value > $1.value }.prefix(4).compactMap { concept, count in
            guard budget > 0 else { return nil }
            budget -= 1
            let connection = connectionsByKey[ConceptResolver.conceptKey(concept)]
            return MindMapNode(
                id: "concept-\(ConceptResolver.conceptKey(concept))",
                kind: .concept,
                title: connection?.title ?? concept,
                subtitle: count > 1 ? "\(count)" : nil,
                atomUUID: connection?.uuid
            )
        }
    }

    private static func conceptNode(_ connection: Atom) -> MindMapNode {
        MindMapNode(
            id: "concept-\(connection.uuid)",
            kind: .concept,
            title: connection.title ?? "Concept",
            atomUUID: connection.uuid
        )
    }

    private static func allConceptUUIDs(in nodes: [MindMapNode]) -> [String] {
        nodes.flatMap { node -> [String] in
            var uuids: [String] = []
            if node.kind == .concept, let uuid = node.atomUUID { uuids.append(uuid) }
            uuids.append(contentsOf: allConceptUUIDs(in: node.children))
            return uuids
        }
    }
}
