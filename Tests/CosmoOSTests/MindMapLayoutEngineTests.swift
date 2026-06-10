// CosmoOS/Tests/CosmoOSTests/MindMapLayoutEngineTests.swift
// Pins the deterministic tidy-tree layout: no sibling overlap, parents
// centered on their children, x monotonic with depth, and builder dedup.

import XCTest
@testable import CosmoOS

final class MindMapLayoutEngineTests: XCTestCase {

    private let uniformSize: (MindMapNode) -> CGSize = { _ in CGSize(width: 200, height: 60) }

    private func node(_ id: String, children: [MindMapNode] = []) -> MindMapNode {
        MindMapNode(id: id, kind: .question, title: id, children: children)
    }

    func testLayoutIsDeterministic() {
        let root = node("root", children: [node("a"), node("b", children: [node("b1"), node("b2")])])
        let first = MindMapLayoutEngine.layout(root: root, nodeSize: uniformSize)
        let second = MindMapLayoutEngine.layout(root: root, nodeSize: uniformSize)
        XCTAssertEqual(first, second)
    }

    func testNoSiblingOverlap() {
        let root = node("root", children: (0..<5).map { node("child-\($0)") })
        let layout = MindMapLayoutEngine.layout(root: root, nodeSize: uniformSize, rowGap: 16)
        let ys = (0..<5).compactMap { layout.positions["child-\($0)"]?.y }.sorted()
        for pair in zip(ys, ys.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1 - pair.0, 60 + 16, "Siblings must not overlap")
        }
    }

    func testParentCenteredOnChildren() {
        let root = node("root", children: [node("a"), node("b"), node("c")])
        let layout = MindMapLayoutEngine.layout(root: root, nodeSize: uniformSize)
        let childYs = ["a", "b", "c"].compactMap { layout.positions[$0]?.y }
        let expectedCenter = (childYs.min()! + childYs.max()!) / 2
        XCTAssertEqual(layout.positions["root"]?.y ?? 0, expectedCenter, accuracy: 0.5)
    }

    func testXMonotonicInDepth() {
        let root = node("root", children: [node("a", children: [node("a1", children: [node("a1a")])])])
        let layout = MindMapLayoutEngine.layout(root: root, nodeSize: uniformSize)
        let xs = ["root", "a", "a1", "a1a"].compactMap { layout.positions[$0]?.x }
        XCTAssertEqual(xs, xs.sorted())
        XCTAssertEqual(Set(xs).count, xs.count, "Each depth gets its own column")
    }

    func testEdgesConnectParentToEveryChild() {
        let root = node("root", children: [node("a"), node("b")])
        let layout = MindMapLayoutEngine.layout(root: root, nodeSize: uniformSize)
        XCTAssertEqual(layout.edges.count, 2)
        XCTAssertTrue(layout.edges.allSatisfy { $0.from.x < $0.to.x })
    }

    func testBranchIndexColorsTopLevelBranches() {
        let root = node("root", children: [
            node("a", children: [node("a1")]),
            node("b")
        ])
        let layout = MindMapLayoutEngine.layout(root: root, nodeSize: uniformSize)
        let edgeToA = layout.edges.first { $0.id == "root->a" }
        let edgeToA1 = layout.edges.first { $0.id == "a->a1" }
        let edgeToB = layout.edges.first { $0.id == "root->b" }
        XCTAssertEqual(edgeToA?.branchIndex, 0)
        XCTAssertEqual(edgeToA1?.branchIndex, 0)   // Inherits its top-level branch
        XCTAssertEqual(edgeToB?.branchIndex, 1)
    }

    func testSizeContainsAllNodes() {
        let root = node("root", children: (0..<4).map { node("c\($0)") })
        let layout = MindMapLayoutEngine.layout(root: root, nodeSize: uniformSize)
        for position in layout.positions.values {
            XCTAssertLessThanOrEqual(position.x + 100, layout.size.width)
            XCTAssertLessThanOrEqual(position.y + 30, layout.size.height)
        }
    }

    // MARK: - Builder

    func testDeepDiveBuilderDedupsQuestions() {
        var deepDive = Atom.new(type: .deepDive, title: "Breathwork")
        deepDive.uuid = "dd-1"
        var q1 = Atom.new(type: .question, title: "What is pranayama?")
        q1.uuid = "q-1"
        q1 = q1.withMetadata(QuestionMetadata(parentDeepDiveUUID: "dd-1", status: .open))
        var q2 = Atom.new(type: .question, title: "what is pranayama")
        q2.uuid = "q-2"
        q2 = q2.withMetadata(QuestionMetadata(parentDeepDiveUUID: "dd-1", status: .open))

        let root = MindMapBuilder.buildDeepDive(
            deepDive: deepDive,
            questions: [q1, q2],
            connections: [],
            extracts: []
        )
        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(root.kind, .root)
    }

    func testSessionTreeBuilderMarksActiveQuestion() {
        var tree = ResearchTreeDocument.bootstrap(rootQuestionAtomUUID: "q-root")
        tree.appendRootQuestion(atomUUID: "q-other", label: "Another question")
        let root = MindMapBuilder.buildSessionTree(
            tree: tree,
            rootTitle: "Breathwork",
            questionTitle: { $0 == "q-root" ? "Main question" : "Another question" },
            countsLabel: { _ in nil },
            activeQuestionUUID: "q-root"
        )
        let active = root.children.first { $0.atomUUID == "q-root" }
        XCTAssertEqual(active?.isActive, true)
        XCTAssertEqual(root.children.count, 2)
    }
}
