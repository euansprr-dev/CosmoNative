// CosmoOS/Tests/CosmoOSTests/DeepDiveConceptScopeTests.swift
// A Deep Dive's concept population = linked pages ∪ concepts resident on its
// OWN thinkspace canvas. Manually created concept blocks join the map exactly
// like crystallized ones — core when unparented, nested when a parent claims
// them — and never leak in from other thinkspaces.

import XCTest
@testable import CosmoOS

final class DeepDiveConceptScopeTests: XCTestCase {

    // MARK: - Union (pure)

    func testMergedConnectionUUIDsKeepsLinkOrderThenPlacementOrder() {
        let merged = InquiryRepository.mergedConnectionUUIDs(
            linked: ["c-1", "c-2"],
            thinkspaceResident: ["c-3", "c-4"]
        )
        XCTAssertEqual(merged, ["c-1", "c-2", "c-3", "c-4"])
    }

    func testMergedConnectionUUIDsCollapsesDuplicatesToFirstAppearance() {
        // A concept both linked AND placed on the canvas is one concept.
        let merged = InquiryRepository.mergedConnectionUUIDs(
            linked: ["c-1", "c-2", "c-1"],
            thinkspaceResident: ["c-2", "c-3"]
        )
        XCTAssertEqual(merged, ["c-1", "c-2", "c-3"])
    }

    func testMergedConnectionUUIDsDropsEmptyEntries() {
        let merged = InquiryRepository.mergedConnectionUUIDs(
            linked: ["", "c-1"],
            thinkspaceResident: [""]
        )
        XCTAssertEqual(merged, ["c-1"])
    }

    // MARK: - Thinkspace scope (pure)

    func testThinkspaceScopePrimaryFirstThenParentsDeduped() {
        var dive = Atom.new(type: .deepDive, title: "Breathwork")
        dive = dive.withMetadata(DeepDiveMetadata(
            parentThinkspaceUUIDs: ["ts-2", "ts-1"],
            primaryThinkspaceUUID: "ts-1"
        ))
        XCTAssertEqual(InquiryRepository.thinkspaceScopeUUIDs(for: dive), ["ts-1", "ts-2"])
    }

    func testThinkspaceScopeEmptyForUnparentedDive() {
        let dive = Atom.new(type: .deepDive, title: "Spark")
        XCTAssertEqual(InquiryRepository.thinkspaceScopeUUIDs(for: dive), [])
    }

    // MARK: - Manual concepts on the map

    private func connection(_ uuid: String, title: String, parentUUID: String? = nil) -> Atom {
        var atom = Atom.new(type: .connection, title: title)
        atom.uuid = uuid
        if let parentUUID {
            atom = atom.withMetadata(ConnectionHierarchyMetadata(parentConnectionUUID: parentUUID))
        }
        return atom
    }

    func testManuallyCreatedConceptsAreCoreBranchesAlongsideCrystallizedOnes() {
        var dive = Atom.new(type: .deepDive, title: "Self-improvement")
        dive.uuid = "dd-1"
        // c-1 came from crystallization; c-2/c-3 were made by hand on the
        // thinkspace canvas — the builder treats the merged list uniformly.
        let graph = MindMapBuilder.buildDeepDive(
            deepDive: dive,
            questions: [],
            connections: [
                connection("c-1", title: "Flow state"),
                connection("c-2", title: "Breathing"),
                connection("c-3", title: "Box breathing")   // Token subset → nests under Breathing.
            ],
            extracts: []
        )
        let coreIDs = graph.root.children.filter { $0.kind == .coreConcept }.map(\.id)
        XCTAssertTrue(coreIDs.contains("concept-c-1"))
        XCTAssertTrue(coreIDs.contains("concept-c-2"))
        XCTAssertFalse(coreIDs.contains("concept-c-3"))
        let breathing = graph.root.children.first { $0.id == "concept-c-2" }
        XCTAssertTrue(breathing?.children.contains { $0.id == "concept-c-3" } == true)
        XCTAssertEqual(breathing?.children.first { $0.id == "concept-c-3" }?.kind, .childConcept)
    }

    func testManualConceptWithPinnedParentNestsUnderIt() {
        var dive = Atom.new(type: .deepDive, title: "Self-improvement")
        dive.uuid = "dd-1"
        let graph = MindMapBuilder.buildDeepDive(
            deepDive: dive,
            questions: [],
            connections: [
                connection("c-1", title: "Recovery"),
                connection("c-2", title: "Cold exposure", parentUUID: "c-1")
            ],
            extracts: []
        )
        XCTAssertEqual(graph.root.children.count, 1)
        XCTAssertEqual(graph.root.children.first?.id, "concept-c-1")
        XCTAssertTrue(graph.root.children.first?.children.contains { $0.id == "concept-c-2" } == true)
    }

    // MARK: - Deterministic anchoring

    func testTitleMatchAnchorPrefersMostSpecificKey() {
        var question = Atom.new(type: .question, title: "How does box breathing work?")
        question.uuid = "q-1"
        question = question.withMetadata(QuestionMetadata(status: .open))
        let connections = [
            connection("c-1", title: "Breathing"),
            connection("c-2", title: "Box breathing")
        ]
        let anchor = MindMapBuilder.anchorConcept(
            for: question,
            extracts: [],
            connections: connections,
            connectionsByUUID: Dictionary(uniqueKeysWithValues: connections.map { ($0.uuid, $0) })
        )
        XCTAssertEqual(anchor, "c-2")
    }

    func testCoreBranchOrderIsDeterministicAcrossInputOrder() {
        var dive = Atom.new(type: .deepDive, title: "Self-improvement")
        dive.uuid = "dd-1"
        let list = [
            connection("c-b", title: "Beta"),
            connection("c-a", title: "Alpha"),
            connection("c-c", title: "Gamma")
        ]
        let forward = MindMapBuilder.buildDeepDive(
            deepDive: dive, questions: [], connections: list, extracts: []
        ).root.children.map(\.id)
        let reversed = MindMapBuilder.buildDeepDive(
            deepDive: dive, questions: [], connections: Array(list.reversed()), extracts: []
        ).root.children.map(\.id)
        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward, ["concept-c-a", "concept-c-b", "concept-c-c"])   // Equal weight → title order.
    }
}
