// CosmoOS/Tests/CosmoOSTests/ConnectionStagingGateTests.swift
// Stage-time gate for concept-board proposals: operations the apply path
// would deterministically refuse (read-only `↳ handled:` lines, unlocatable
// anchors, cross-section spans) must bounce back to the model at staging.
// A pending op with no ghost row anywhere is a phantom capture the user can
// never review (July 26 bug: receipt said "1 capture waiting in your board"
// while the board showed nothing — the op anchored a handled objection's
// rebuttal line).

import XCTest
@testable import CosmoOS

final class ConnectionStagingGateTests: XCTestCase {

    private var model: ConnectionSurfaceModel!

    override func setUp() {
        super.setUp()
        let example = ConnectionItem(content: "The IKEA effect demo")
        var objection = ConnectionItem(content: "Nobody values what they didn't build")
        objection.handling = ObjectionHandling(
            text: "Ownership transfers through co-creation",
            linkedRefs: [ConnectionBoardItemRef(section: .examples, itemID: example.id)]
        )
        let sections = ConnectionSectionType.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { type -> ConnectionSection in
                var section = ConnectionSection(type: type)
                if type == .beliefsObjections { section.addItem(objection) }
                if type == .examples { section.addItem(example) }
                return section
            }
        model = ConnectionSurfaceSerializer.serialize(
            title: "Manifestation", conceptType: .framework, sections: sections
        )
    }

    private func operation(
        kind: CosmoAssistantProposalOperationKind,
        anchorID: String? = nil,
        originalText: String? = nil,
        proposedText: String? = nil
    ) -> CosmoAssistantProposalOperation {
        CosmoAssistantProposalOperation(
            kind: kind,
            targetID: "connection:X:sections",
            anchorID: anchorID,
            originalText: originalText,
            proposedText: proposedText,
            sourceHash: "h",
            rationale: "test"
        )
    }

    private func issues(_ operations: [CosmoAssistantProposalOperation]) -> [String] {
        ConnectionSurfaceSerializer.stagingIssues(operations: operations, in: model)
    }

    // MARK: - Read-only handled line (the phantom-capture bug)

    func testInsertionAnchoredOnHandledLineBounces() {
        let op = operation(
            kind: .textInsertion,
            originalText: "↳ handled: Ownership transfers through co-creation",
            proposedText: "- People procrastinate instead of acting"
        )
        let issues = issues([op])
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("handle_objection"), "must redirect to the dedicated tool: \(issues)")
    }

    func testReplacementOfHandledLineBounces() {
        let op = operation(
            kind: .textReplacement,
            originalText: "↳ handled: Ownership transfers through co-creation",
            proposedText: "↳ handled: A sharper rebuttal"
        )
        let issues = issues([op])
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("handle_objection"))
    }

    func testReplacementSpanningObjectionAndHandlingBounces() {
        let op = operation(
            kind: .textReplacement,
            originalText: "- Nobody values what they didn't build\n  ↳ handled: Ownership transfers through co-creation",
            proposedText: "- Rewritten objection with new handling"
        )
        let issues = issues([op])
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("handle_objection"))
    }

    // MARK: - Legit operations must pass (never over-block)

    func testInsertionAnchoredOnObjectionBulletPasses() {
        let op = operation(
            kind: .textInsertion,
            originalText: "- Nobody values what they didn't build",
            proposedText: "- People procrastinate instead of acting"
        )
        XCTAssertTrue(issues([op]).isEmpty)
    }

    func testInsertionViaSectionAnchorIDPasses() {
        let op = operation(
            kind: .textInsertion,
            anchorID: ConnectionSurfaceSerializer.anchorID(for: .beliefsObjections),
            proposedText: "- People procrastinate instead of acting"
        )
        XCTAssertTrue(issues([op]).isEmpty)
    }

    func testTitleEditPasses() {
        let op = operation(
            kind: .textReplacement,
            originalText: "# Manifestation",
            proposedText: "# Manifestation Engine"
        )
        XCTAssertTrue(issues([op]).isEmpty, "title edits review in the Manuscript diff — not this gate's business")
    }

    func testConceptTypeEditPasses() {
        let typeLine = model.text
            .components(separatedBy: "\n")
            .first { $0.hasPrefix("Type:") }
        let op = operation(
            kind: .textReplacement,
            originalText: typeLine,
            proposedText: "Type: Framework"
        )
        XCTAssertTrue(issues([op]).isEmpty, "the Type: line is the one editable .meta line")
    }

    func testHeaderCoveringReplacementThatKeepsHeaderPasses() {
        let op = operation(
            kind: .textReplacement,
            originalText: "\(ConnectionSurfaceSerializer.headerLine(for: .examples))\n- The IKEA effect demo",
            proposedText: "\(ConnectionSurfaceSerializer.headerLine(for: .examples))\n- The IKEA effect, retold"
        )
        XCTAssertTrue(issues([op]).isEmpty)
    }

    // MARK: - Structural refusals apply would also make

    func testUnmatchedInsertionAnchorBounces() {
        let op = operation(
            kind: .textInsertion,
            originalText: "- This bullet exists nowhere on the board",
            proposedText: "- Something new"
        )
        let issues = issues([op])
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("matches nothing"))
    }

    func testInsertionNamingAnotherSectionBounces() {
        let op = operation(
            kind: .textInsertion,
            originalText: ConnectionSurfaceSerializer.headerLine(for: .beliefsObjections),
            proposedText: "\(ConnectionSurfaceSerializer.headerLine(for: .examples))\n- If you decided you were a millionaire"
        )
        XCTAssertEqual(issues([op]).count, 1)
    }

    func testIssueCarriesOperationNumber() {
        let good = operation(
            kind: .textInsertion,
            originalText: "- Nobody values what they didn't build",
            proposedText: "- A fine bullet"
        )
        let bad = operation(
            kind: .textReplacement,
            originalText: "↳ handled: Ownership transfers through co-creation",
            proposedText: "↳ handled: rewrite"
        )
        let issues = issues([good, bad])
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].hasPrefix("Operation 2:"))
    }
}
