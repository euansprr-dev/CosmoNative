import XCTest
@testable import CosmoOS

final class CosmoInlineAssistantModelsTests: XCTestCase {
    func testOperationAcceptabilityRequiresPendingStatusAndMatchingSourceHash() {
        let source = CosmoEditableSourceSnapshot(
            surfaceID: "note:abc",
            targetID: "note:abc:body",
            kind: .text,
            title: "Launch note",
            text: "Rent: $4,556/mo",
            sourceHash: "hash-1",
            anchors: [.init(id: "line-1", label: "Line 1", utf16Start: 0, utf16Length: 15)]
        )
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "note:abc:body",
            anchorID: "line-1",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: "hash-1",
            rationale: "Use the requested rent number."
        )

        XCTAssertTrue(operation.canApply(against: source))
        XCTAssertFalse(operation.marked(.accepted).canApply(against: source))
        XCTAssertFalse(operation.canApply(against: source.withSourceHash("hash-2")))
    }

    func testDiffEngineBuildsParagraphReplacementHunks() {
        let hunks = CosmoInlineAssistantDiffEngine.hunks(
            original: "Rent: $4,556/mo\nExpenses: $1,800/mo",
            proposed: "Rent: $5,000/mo\nExpenses: $2,100/mo"
        )

        XCTAssertEqual(hunks.map(\.kind), [.removed, .added, .removed, .added])
        XCTAssertEqual(hunks[0].text, "Rent: $4,556/mo")
        XCTAssertEqual(hunks[1].text, "Rent: $5,000/mo")
        XCTAssertEqual(hunks[2].text, "Expenses: $1,800/mo")
        XCTAssertEqual(hunks[3].text, "Expenses: $2,100/mo")
    }
}
