// CosmoOS/Tests/CosmoOSTests/MindMapBuilderTests.swift
// Concept-first Deep Dive map: concepts form the hierarchy, questions hang
// beneath the concept they feed, leftovers collapse into one bucket.

import XCTest
@testable import CosmoOS

final class MindMapBuilderTests: XCTestCase {

    // MARK: - Fixtures

    private func deepDive(_ title: String = "Self-improvement") -> Atom {
        var atom = Atom.new(type: .deepDive, title: title)
        atom.uuid = "dd-1"
        return atom
    }

    private func connection(
        _ uuid: String,
        title: String,
        parentUUID: String? = nil,
        pinned: Bool? = nil,
        links: [AtomLink] = []
    ) -> Atom {
        var atom = Atom.new(type: .connection, title: title)
        atom.uuid = uuid
        if parentUUID != nil || pinned != nil {
            atom = atom.withMetadata(ConnectionHierarchyMetadata(
                parentConnectionUUID: parentUUID,
                parentPinnedByUser: pinned
            ))
        }
        if !links.isEmpty {
            atom = atom.withLinks(links)
        }
        return atom
    }

    private func question(_ uuid: String, title: String, parentQuestionUUID: String? = nil) -> Atom {
        var atom = Atom.new(type: .question, title: title)
        atom.uuid = uuid
        return atom.withMetadata(QuestionMetadata(
            parentQuestionUUID: parentQuestionUUID,
            status: .open
        ))
    }

    private func extract(
        _ uuid: String,
        questionUUID: String? = nil,
        promotedToUUID: String? = nil,
        concepts: [String]? = nil
    ) -> Atom {
        var metadata = ExtractMetadata(kind: .claim, parentQuestionUUID: questionUUID)
        metadata.promotedToUUID = promotedToUUID
        metadata.conceptNames = concepts
        var atom = Atom.new(type: .extract, title: "Extract", body: "Extract body")
        atom.uuid = uuid
        return atom.withMetadata(metadata)
    }

    private func build(
        questions: [Atom] = [],
        connections: [Atom] = [],
        extracts: [Atom] = [],
        includeQuestions: Bool = true
    ) -> MindMapGraph {
        MindMapBuilder.buildDeepDive(
            deepDive: deepDive(),
            questions: questions,
            connections: connections,
            extracts: extracts,
            includeQuestions: includeQuestions
        )
    }

    private func node(_ id: String, in root: MindMapNode) -> MindMapNode? {
        if root.id == id { return root }
        for child in root.children {
            if let found = node(id, in: child) { return found }
        }
        return nil
    }

    // MARK: - Concept-first structure

    func testConceptsFormTopLevelAndQuestionsNestUnderAnchor() {
        let graph = build(
            questions: [question("q-1", title: "What is flow state?")],
            connections: [connection("c-1", title: "Flow state")],
            extracts: [extract("e-1", questionUUID: "q-1", promotedToUUID: "c-1")]
        )
        let concept = node("concept-c-1", in: graph.root)
        XCTAssertEqual(concept?.kind, .coreConcept)
        XCTAssertEqual(graph.root.children.first?.id, "concept-c-1")   // Concept is L1.
        XCTAssertEqual(concept?.children.first?.id, "question-q-1")    // Question hangs beneath it.
        XCTAssertEqual(concept?.children.first?.kind, .question)
    }

    func testPersistedParentNestsChildConcept() {
        let graph = build(connections: [
            connection("c-1", title: "Peak human experience"),
            connection("c-2", title: "Flow state", parentUUID: "c-1")
        ])
        XCTAssertEqual(graph.root.children.count, 1)                    // Only the core concept at L1.
        let core = node("concept-c-1", in: graph.root)
        XCTAssertEqual(core?.kind, .coreConcept)
        let child = node("concept-c-2", in: graph.root)
        XCTAssertEqual(child?.kind, .childConcept)
        XCTAssertTrue(core?.children.contains { $0.id == "concept-c-2" } == true)
    }

    func testLegacyTokenSubsetNesting() {
        let graph = build(connections: [
            connection("c-1", title: "Breathing"),
            connection("c-2", title: "Box breathing")   // No persisted parent.
        ])
        let parent = node("concept-c-1", in: graph.root)
        XCTAssertTrue(parent?.children.contains { $0.id == "concept-c-2" } == true)
        XCTAssertEqual(graph.root.children.count, 1)
    }

    func testCycleInPersistedParentsBreaksSafely() {
        let graph = build(connections: [
            connection("c-1", title: "Alpha", parentUUID: "c-2"),
            connection("c-2", title: "Omega", parentUUID: "c-1")
        ])
        // The cycle is cut — both nodes still render, at least one as core.
        XCTAssertNotNil(node("concept-c-1", in: graph.root))
        XCTAssertNotNil(node("concept-c-2", in: graph.root))
        XCTAssertFalse(graph.root.children.isEmpty)
    }

    // MARK: - Question anchoring

    func testAnchorFallsBackToConceptTags() {
        let graph = build(
            questions: [question("q-1", title: "How do breath holds work?")],
            connections: [connection("c-1", title: "CO2 tolerance")],
            extracts: [extract("e-1", questionUUID: "q-1", concepts: ["CO2 tolerance"])]
        )
        let concept = node("concept-c-1", in: graph.root)
        XCTAssertTrue(concept?.children.contains { $0.id == "question-q-1" } == true)
    }

    func testAnchorFallsBackToTitleMatch() {
        let graph = build(
            questions: [question("q-1", title: "What is flow state?")],
            connections: [connection("c-1", title: "Flow state")]
        )
        let concept = node("concept-c-1", in: graph.root)
        XCTAssertTrue(concept?.children.contains { $0.id == "question-q-1" } == true)
    }

    func testUnanchoredQuestionsCollapseIntoOneBucket() {
        let graph = build(
            questions: [
                question("q-1", title: "Totally unrelated mystery?"),
                question("q-2", title: "Another stray puzzle?")
            ],
            connections: [connection("c-1", title: "Flow state")]
        )
        let bucket = node("open-questions", in: graph.root)
        XCTAssertEqual(bucket?.kind, .questionGroup)
        XCTAssertEqual(bucket?.children.count, 2)
        // Bucket is last; questions are never top-level peers of concepts.
        XCTAssertEqual(graph.root.children.last?.id, "open-questions")
        XCTAssertFalse(graph.root.children.contains { $0.kind == .question })
    }

    func testConceptsOnlyFilterDropsAllQuestions() {
        let graph = build(
            questions: [question("q-1", title: "What is flow state?")],
            connections: [connection("c-1", title: "Flow state")],
            extracts: [extract("e-1", questionUUID: "q-1", promotedToUUID: "c-1")],
            includeQuestions: false
        )
        XCTAssertNil(node("question-q-1", in: graph.root))
        XCTAssertNil(node("open-questions", in: graph.root))
        XCTAssertNotNil(node("concept-c-1", in: graph.root))
    }

    func testSubQuestionsStayUnderTheirParentQuestion() {
        let graph = build(
            questions: [
                question("q-1", title: "What is flow state?"),
                question("q-2", title: "How is it measured?", parentQuestionUUID: "q-1")
            ],
            connections: [connection("c-1", title: "Flow state")],
            extracts: [extract("e-1", questionUUID: "q-1", promotedToUUID: "c-1")]
        )
        let parentQuestion = node("question-q-1", in: graph.root)
        XCTAssertTrue(parentQuestion?.children.contains { $0.id == "question-q-2" } == true)
        XCTAssertEqual(node("question-q-2", in: graph.root)?.kind, .subQuestion)
    }

    // MARK: - Cross-links

    func testConceptLinksSkipParentChildPairs() {
        let linked = connection(
            "c-2", title: "Vagus nerve",
            links: [AtomLink(type: AtomLinkType.connection.rawValue, uuid: "c-1", entityType: AtomType.connection.rawValue)]
        )
        let child = connection(
            "c-3", title: "Flow state", parentUUID: "c-1",
            links: [AtomLink(type: AtomLinkType.connection.rawValue, uuid: "c-1", entityType: AtomType.connection.rawValue)]
        )
        let graph = build(connections: [connection("c-1", title: "Breathwork"), linked, child])
        // c-2 ↔ c-1 is a genuine cross-link; c-3 → c-1 is already a tree edge.
        XCTAssertEqual(graph.conceptLinks.count, 1)
        XCTAssertTrue(graph.conceptLinks.contains {
            Set([$0.fromNodeId, $0.toNodeId]) == Set(["concept-c-2", "concept-c-1"])
        })
    }

    // MARK: - Promotion cycle guard (pure)

    func testCreatesCycleDetection() {
        XCTAssertTrue(ConnectionPromotionService.createsCycle(
            child: "a", parent: "b", parentByUUID: ["b": "c", "c": "a"]
        ))
        XCTAssertFalse(ConnectionPromotionService.createsCycle(
            child: "a", parent: "b", parentByUUID: ["b": "c"]
        ))
        XCTAssertTrue(ConnectionPromotionService.createsCycle(
            child: "a", parent: "a", parentByUUID: [:]
        ))
    }
}
