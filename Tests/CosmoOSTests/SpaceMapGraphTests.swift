import XCTest
@testable import CosmoOS

final class SpaceMapGraphTests: XCTestCase {
    private func flatten(_ node: SpaceMapNode) -> [SpaceMapNode] { [node] + node.children.flatMap(flatten) }

    func testAuthoredHierarchyIsPreservedAndReferencesDoNotBecomeChildren() throws {
        let records = [
            SpaceMapRecord(id: "book", type: "note", title: "Book", metadata: #"{"spaceComposition":{"kind":"book"}}"#),
            SpaceMapRecord(id: "page", type: "note", title: "Page", metadata: #"{"spaceComposition":{"kind":"page","parentUUID":"book","references":[{"sourceUUID":"concept"}]}}"#),
            SpaceMapRecord(id: "concept", type: "connection", title: "Concept")
        ]
        let graph = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: records, memberIDs: ["book", "page"])
        let book = try XCTUnwrap(flatten(graph.root).first { $0.id == "book" })
        XCTAssertEqual(book.children.map(\.id), ["page"])
        XCTAssertEqual(flatten(graph.root).first { $0.id == "concept" }?.children.isEmpty, true)
        XCTAssertTrue(graph.links.contains { Set([$0.fromID, $0.toID]) == ["page", "concept"] })
        XCTAssertEqual(Set(flatten(graph.root).map(\.id)).count, flatten(graph.root).count)
    }

    func testTitleSimilarityNeverInventsAConceptParent() {
        let graph = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: [
            .init(id: "a", type: "connection", title: "Sleep"),
            .init(id: "b", type: "connection", title: "Sleep pressure")
        ], memberIDs: ["a", "b"])
        XCTAssertEqual(graph.root.children.map(\.id), ["a", "b"])
    }

    func testTopicScopeDoesNotPullInAnUnrelatedPageFromTheSpace() {
        let records = [
            SpaceMapRecord(id: "topic", type: "deep_dive", title: "Sleep", links: [.init(type: "deep_dive_connection", targetID: "concept")]),
            SpaceMapRecord(id: "concept", type: "connection", title: "Sleep pressure"),
            SpaceMapRecord(id: "linked-page", type: "note", title: "Sleep notes", metadata: #"{"spaceComposition":{"kind":"page","references":[{"sourceUUID":"concept"}]}}"#),
            SpaceMapRecord(id: "other-page", type: "note", title: "Travel notes")
        ]
        let graph = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: records, memberIDs: ["linked-page", "other-page"], topicID: "topic")
        let ids = Set(flatten(graph.root).compactMap(\.atomID))
        XCTAssertTrue(ids.contains("concept")); XCTAssertTrue(ids.contains("linked-page"))
        XCTAssertFalse(ids.contains("other-page"))
    }

    func testSearchRetainsAuthoredAncestorsAndHighlightsOnlyMatches() throws {
        let records = [
            SpaceMapRecord(id: "book", type: "note", title: "Handbook", metadata: #"{"spaceComposition":{"kind":"book"}}"#),
            SpaceMapRecord(id: "page", type: "note", title: "Sleep pressure", metadata: #"{"spaceComposition":{"kind":"page","parentUUID":"book"}}"#)
        ]
        let graph = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: records, memberIDs: ["book", "page"], query: "pressure")
        let book = try XCTUnwrap(flatten(graph.root).first { $0.id == "book" })
        XCTAssertFalse(book.isMatch); XCTAssertEqual(book.children.first?.isMatch, true)
        XCTAssertEqual(graph.matchCount, 1)
    }

    func testCorruptCyclesProduceUniqueReachableNodes() {
        let records = [
            SpaceMapRecord(id: "a", type: "connection", title: "A", metadata: #"{"parentConnectionUUID":"b"}"#),
            SpaceMapRecord(id: "b", type: "connection", title: "B", metadata: #"{"parentConnectionUUID":"a"}"#)
        ]
        let graph = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: records, memberIDs: ["a", "b"])
        let ids = flatten(graph.root).compactMap(\.atomID).filter { $0 != "space" }
        XCTAssertEqual(Set(ids), ["a", "b"]); XCTAssertEqual(ids.count, 2)
    }

    func testNodeLimitReportsOmissionsAndKeepsAdmittedAncestors() {
        let records = (0..<20).map { index in
            SpaceMapRecord(id: "page-\(index)", type: "note", title: "Page \(index)", metadata: index == 0 ? nil : "{\"spaceComposition\":{\"parentUUID\":\"page-\(index - 1)\"}}")
        }
        let graph = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: records, memberIDs: Set(records.map(\.id)), nodeLimit: 4)
        XCTAssertEqual(graph.omittedCount, 16)
        let ids = Set(flatten(graph.root).compactMap(\.atomID)).subtracting(["space"])
        XCTAssertEqual(ids, Set((0..<4).map { "page-\($0)" }))
    }

    func testAbsentTargetsAndMalformedMetadataDoNotCreatePlaceholderObjects() {
        let record = SpaceMapRecord(id: "page", type: "note", title: "Page", metadata: "broken", links: [.init(type: "source", targetID: "missing")])
        let graph = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: [record], memberIDs: ["page"])
        XCTAssertTrue(flatten(graph.root).allSatisfy { $0.id != "missing" })
        XCTAssertTrue(graph.links.isEmpty)
        XCTAssertEqual(SpaceMapGraphBuilder.referencedIDs(in: [record]), ["missing"])
    }

    func testEvidenceAndWorkProvenanceUsesSavedSessionQuestion() {
        let records = [
            SpaceMapRecord(id: "topic", type: "deep_dive", title: "Topic"),
            SpaceMapRecord(id: "question", type: "question", title: "Question", metadata: #"{"parentDeepDiveUUID":"topic"}"#),
            SpaceMapRecord(id: "session", type: "inquiry_session", title: "Session", metadata: #"{"parentDeepDiveUUID":"topic","mainQuestionUUID":"question"}"#,
                structured: #"{"sourceRefs":[{"sourceUUID":"source"}]}"#),
            SpaceMapRecord(id: "source", type: "research", title: "Paper"),
            SpaceMapRecord(id: "work", type: "content", title: "Article", links: [.init(type: "output_from_inquiry", targetID: "session")])
        ]
        let graph = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: records, memberIDs: ["work"], showMaterials: true)
        XCTAssertTrue(graph.links.contains { Set([$0.fromID, $0.toID]) == ["question", "source"] })
        XCTAssertTrue(graph.links.contains { Set([$0.fromID, $0.toID]) == ["work", "question"] })
        XCTAssertFalse(flatten(graph.root).contains { $0.atomID == "session" })
    }

    func testNativeConceptSectionLinksAppearWithoutDenormalizedAtomLinks() {
        let concept = SpaceMapRecord(id: "concept", type: "connection", title: "Concept",
            structured: #"{"sections":[{"items":[{"linkedConnectionUUID":"related"},{"sourceAtomUUID":"source"}]}]}"#)
        let graph = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: [concept,
            .init(id: "related", type: "connection", title: "Related"), .init(id: "source", type: "research", title: "Source")],
            memberIDs: ["concept"], showMaterials: true)
        XCTAssertEqual(SpaceMapGraphBuilder.referencedIDs(in: [concept]), ["related", "source"])
        XCTAssertTrue(graph.links.contains { Set([$0.fromID, $0.toID]) == ["concept", "related"] })
        XCTAssertTrue(graph.links.contains { Set([$0.fromID, $0.toID]) == ["concept", "source"] })
    }

    func testCycleRepairPreservesTheValidBranchLeadingIntoTheCycle() {
        XCTAssertEqual(SpaceMapGraphBuilder.acyclicParents(["a": "b", "b": "c", "c": "b"]), ["a": "b", "c": "b"])
    }

    func testTopicReferencesDoNotExpandDependingOnRecordOrder() {
        let records = [
            SpaceMapRecord(id: "topic", type: "deep_dive", title: "Topic", links: [.init(type: "deep_dive_connection", targetID: "concept")]),
            SpaceMapRecord(id: "concept", type: "connection", title: "Concept"),
            SpaceMapRecord(id: "direct", type: "note", title: "Direct", links: [.init(type: "source", targetID: "concept")]),
            SpaceMapRecord(id: "indirect", type: "note", title: "Indirect", links: [.init(type: "source", targetID: "direct")])
        ]
        let first = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: records, memberIDs: ["direct", "indirect"], topicID: "topic")
        let reversed = SpaceMapGraphBuilder.build(spaceID: "space", title: "Space", records: Array(records.reversed()), memberIDs: ["direct", "indirect"], topicID: "topic")
        XCTAssertEqual(first, reversed)
        XCTAssertFalse(flatten(first.root).contains { $0.atomID == "indirect" })
    }
}
