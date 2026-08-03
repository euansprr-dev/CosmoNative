// CosmoOS/Tests/CosmoOSTests/ConnectionOrphanedCaptureTests.swift
// Render-time honesty for concept-board staging: a pending operation that
// resolved when staged can stop resolving later (the user edits or deletes
// the bullet its anchor quoted while the capture is still pending). Those
// orphans must come back from stagedInserts / captureReceiptState — named
// and dismissible — instead of silently inflating the receipt's "captures
// waiting" count while the board ghost-renders nothing. Twin of the
// stage-time gate covered by ConnectionStagingGateTests.

import XCTest
@testable import CosmoOS

final class ConnectionOrphanedCaptureTests: XCTestCase {

    private var sections: [ConnectionSection]!
    private var model: ConnectionSurfaceModel!

    override func setUp() {
        super.setUp()
        let example = ConnectionItem(content: "The IKEA effect demo")
        let objection = ConnectionItem(content: "Nobody values what they didn't build")
        sections = ConnectionSectionType.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { type -> ConnectionSection in
                var section = ConnectionSection(type: type)
                if type == .beliefsObjections { section.addItem(objection) }
                if type == .examples { section.addItem(example) }
                return section
            }
        model = serialize(sections)
    }

    private func serialize(_ sections: [ConnectionSection]) -> ConnectionSurfaceModel {
        ConnectionSurfaceSerializer.serialize(
            title: "Manifestation", conceptType: .framework, sections: sections
        )
    }

    /// The board after the user deletes the Examples bullet a capture was
    /// anchored on — the render-time drift under test.
    private func sectionsWithoutExample() -> [ConnectionSection] {
        sections.map { section in
            guard section.type == .examples else { return section }
            var stripped = section
            stripped.items.removeAll()
            return stripped
        }
    }

    private func operation(
        kind: CosmoAssistantProposalOperationKind,
        anchorID: String? = nil,
        originalText: String? = nil,
        proposedText: String? = nil,
        status: CosmoProposalStatus = .pending
    ) -> CosmoAssistantProposalOperation {
        CosmoAssistantProposalOperation(
            kind: kind,
            targetID: "connection:X:sections",
            anchorID: anchorID,
            originalText: originalText,
            proposedText: proposedText,
            sourceHash: "h",
            rationale: "test",
            status: status
        )
    }

    private func receiptState(
        _ operations: [CosmoAssistantProposalOperation],
        in model: ConnectionSurfaceModel? = nil
    ) -> ConnectionCaptureReceiptState {
        ConnectionSurfaceSerializer.captureReceiptState(
            operations: operations,
            proposalID: UUID(),
            in: model ?? self.model
        )
    }

    // MARK: - Placement classification

    func testValidInsertionPlacesInSection() {
        let op = operation(
            kind: .textInsertion,
            originalText: "- Nobody values what they didn't build",
            proposedText: "- People procrastinate instead of acting"
        )
        let state = receiptState([op])
        XCTAssertEqual(state.sectionCount, 1)
        XCTAssertEqual(state.manuscriptCount, 0)
        XCTAssertTrue(state.orphans.isEmpty)
    }

    func testTitleEditReviewsInManuscript() {
        let op = operation(
            kind: .textReplacement,
            originalText: "# Manifestation",
            proposedText: "# Manifestation Engine"
        )
        let state = receiptState([op])
        XCTAssertEqual(state.manuscriptCount, 1)
        XCTAssertEqual(state.sectionCount, 0)
        XCTAssertTrue(state.orphans.isEmpty, "title edits review in the Manuscript diff, never orphaned")
    }

    func testConceptTypeEditReviewsInManuscript() {
        let typeLine = model.text.components(separatedBy: "\n").first { $0.hasPrefix("Type:") }
        let op = operation(
            kind: .textReplacement,
            originalText: typeLine,
            proposedText: "Type: Framework"
        )
        XCTAssertEqual(receiptState([op]).manuscriptCount, 1)
    }

    func testHeaderCoveringRewriteReviewsInManuscript() {
        let op = operation(
            kind: .textReplacement,
            originalText: "\(ConnectionSurfaceSerializer.headerLine(for: .examples))\n- The IKEA effect demo",
            proposedText: "\(ConnectionSurfaceSerializer.headerLine(for: .examples))\n- The IKEA effect, retold"
        )
        let state = receiptState([op])
        XCTAssertEqual(state.manuscriptCount, 1)
        XCTAssertTrue(state.orphans.isEmpty)
    }

    // MARK: - Render-time drift → orphans

    func testInsertionAnchoredOnDeletedBulletOrphans() {
        let op = operation(
            kind: .textInsertion,
            originalText: "- The IKEA effect demo",
            proposedText: "- People procrastinate instead of acting"
        )
        let drifted = serialize(sectionsWithoutExample())
        XCTAssertEqual(receiptState([op]).sectionCount, 1, "sanity: resolves before the board changes")
        let state = receiptState([op], in: drifted)
        XCTAssertEqual(state.sectionCount, 0)
        XCTAssertEqual(state.orphans.count, 1)
        XCTAssertEqual(state.orphans[0].operationID, op.id)
        XCTAssertEqual(state.orphans[0].summary, "People procrastinate instead of acting")
    }

    func testReplacementOfEditedBulletOrphans() {
        let op = operation(
            kind: .textReplacement,
            originalText: "- The IKEA effect demo",
            proposedText: "- The IKEA effect, retold sharper"
        )
        let state = receiptState([op], in: serialize(sectionsWithoutExample()))
        XCTAssertEqual(state.orphans.count, 1)
        XCTAssertEqual(state.placedCount, 0)
    }

    func testSettledOperationsAreNotClassified() {
        let applied = operation(
            kind: .textInsertion,
            originalText: "- The IKEA effect demo",
            proposedText: "- Something",
            status: .applied
        )
        let rejected = operation(
            kind: .textInsertion,
            originalText: "- The IKEA effect demo",
            proposedText: "- Something else",
            status: .rejected
        )
        let state = receiptState([applied, rejected], in: serialize(sectionsWithoutExample()))
        XCTAssertEqual(state, ConnectionCaptureReceiptState())
    }

    func testConflictedOperationsStillClassify() {
        // A ✓ on a drifted ghost row conflicts at apply; the op must then
        // surface as an orphan, not vanish while staying counted.
        let op = operation(
            kind: .textInsertion,
            originalText: "- The IKEA effect demo",
            proposedText: "- Something",
            status: .conflicted
        )
        XCTAssertEqual(receiptState([op], in: serialize(sectionsWithoutExample())).orphans.count, 1)
    }

    func testOrphanSummaryFallsBackToRationale() {
        let op = operation(
            kind: .textReplacement,
            originalText: "- The IKEA effect demo",
            proposedText: "   "
        )
        let state = receiptState([op], in: serialize(sectionsWithoutExample()))
        XCTAssertEqual(state.orphans.first?.summary, "test")
    }

    // MARK: - stagedInserts partition

    @MainActor
    func testStagedInsertsReturnsOrphansSeparately() {
        let placeable = operation(
            kind: .textInsertion,
            originalText: "- Nobody values what they didn't build",
            proposedText: "- People procrastinate instead of acting"
        )
        let orphan = operation(
            kind: .textInsertion,
            originalText: "- The IKEA effect demo",
            proposedText: "- A capture the board changed under"
        )
        let proposal = CosmoAssistantProposal(
            prompt: "capture",
            surfaceID: "connection:X",
            title: "Staged",
            summary: "s",
            operations: [placeable, orphan]
        )
        let staged = ConnectionSurfaceSerializer.stagedInserts(
            from: [proposal],
            atomUUID: "X",
            title: "Manifestation",
            conceptType: .framework,
            sections: sectionsWithoutExample()
        )
        let ghostOps = staged.bySection.values.flatMap { $0 }.map(\.operationID)
        XCTAssertEqual(ghostOps, [placeable.id])
        XCTAssertEqual(staged.orphaned.map(\.operationID), [orphan.id])
        XCTAssertEqual(staged.manuscript?.id, proposal.id)
    }

    // MARK: - Receipt copy honesty

    func testReceiptCopyAllPlacedInSections() {
        let copy = ConceptCaptureReceiptCopy.make(
            pendingCount: 2,
            resolvedCount: 0,
            state: ConnectionCaptureReceiptState(sectionCount: 2)
        )
        XCTAssertEqual(copy.headline, "2 captures waiting in your board")
        XCTAssertEqual(copy.subtitle, "Review each in its section, then ✓ or ✗ there.")
        XCTAssertNil(copy.orphanNotice)
        XCTAssertTrue(copy.showsAcceptAll)
    }

    func testReceiptCopyManuscriptOnly() {
        // A title/type edit reviews in the Manuscript woven diff — the
        // "review each in its section" line would point at nothing.
        let copy = ConceptCaptureReceiptCopy.make(
            pendingCount: 1,
            resolvedCount: 0,
            state: ConnectionCaptureReceiptState(manuscriptCount: 1)
        )
        XCTAssertEqual(copy.headline, "1 capture waiting in your board")
        XCTAssertEqual(copy.subtitle, "Review in the Manuscript view, then ✓ or ✗ there.")
    }

    func testReceiptCopyMixedPlacedAndOrphaned() {
        let orphan = ConnectionOrphanedCapture(proposalID: UUID(), operationID: UUID(), summary: "Lost bullet")
        let copy = ConceptCaptureReceiptCopy.make(
            pendingCount: 3,
            resolvedCount: 0,
            state: ConnectionCaptureReceiptState(sectionCount: 1, manuscriptCount: 1, orphans: [orphan])
        )
        XCTAssertEqual(copy.headline, "2 captures waiting in your board", "orphans must not inflate the waiting count")
        XCTAssertEqual(copy.orphanNotice, "1 more can't be placed: the board changed under it.")
        XCTAssertTrue(copy.showsAcceptAll)
        XCTAssertTrue(copy.showsDismissAll)
    }

    func testReceiptCopyAllOrphaned() {
        let orphan = ConnectionOrphanedCapture(proposalID: UUID(), operationID: UUID(), summary: "Lost bullet")
        let copy = ConceptCaptureReceiptCopy.make(
            pendingCount: 1,
            resolvedCount: 0,
            state: ConnectionCaptureReceiptState(orphans: [orphan])
        )
        XCTAssertEqual(copy.headline, "1 capture can't be placed")
        XCTAssertEqual(copy.subtitle, "The board changed under it. Dismiss it, or ask me to restage.")
        XCTAssertNil(copy.orphanNotice, "the headline already carries the news")
        XCTAssertFalse(copy.showsAcceptAll, "nothing is placeable, accept-all would be a lie")
        XCTAssertTrue(copy.showsDismissAll)
    }

    func testReceiptCopyWithoutLiveBoardKeepsStageTimeTruth() {
        let copy = ConceptCaptureReceiptCopy.make(pendingCount: 2, resolvedCount: 0, state: nil)
        XCTAssertEqual(copy.headline, "2 captures waiting in your board")
        XCTAssertEqual(copy.subtitle, "Review each in its section, then ✓ or ✗ there.")
        XCTAssertTrue(copy.showsAcceptAll)
    }

    func testReceiptCopyNothingPending() {
        let done = ConceptCaptureReceiptCopy.make(pendingCount: 0, resolvedCount: 2, state: nil)
        XCTAssertEqual(done.headline, "Added to your board")
        XCTAssertFalse(done.showsDismissAll)
        let empty = ConceptCaptureReceiptCopy.make(pendingCount: 0, resolvedCount: 0, state: nil)
        XCTAssertEqual(empty.headline, "Nothing captured")
    }
}
