// CosmoOS/Tests/CosmoOSTests/InquiryLiveRouterTests.swift
// Pure-logic tests for the hybrid async router: payload parsing safety
// (never trust invented UUIDs) and apply-plan computation.

import XCTest
@testable import CosmoOS

final class InquiryLiveRouterTests: XCTestCase {

    private let validUUIDs: Set<String> = ["q-1", "q-2"]

    // MARK: - Parsing

    func testParsesValidPayload() {
        let raw = """
        {"units":[
          {"text":"Slow exhales raise vagal tone","kind":"speculativeClaim","targetQuestionUUID":"q-1","newBranchTitle":null,"conceptNames":["Vagal tone"],"confidence":0.85},
          {"text":"Box breathing: 4-4-4-4","kind":"practice","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":[],"confidence":0.9}
        ]}
        """
        let units = InquiryLiveRouter.parseUnits(raw: raw, validQuestionUUIDs: validUUIDs)
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[0].kind, .speculativeClaim)
        XCTAssertEqual(units[0].targetQuestionUUID, "q-1")
        XCTAssertEqual(units[0].conceptNames, ["Vagal tone"])
        XCTAssertEqual(units[1].kind, .practice)
        XCTAssertNil(units[1].targetQuestionUUID)
    }

    func testParsesFencedPayload() {
        let raw = """
        ```json
        {"units":[{"text":"A claim","kind":"claim","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":[],"confidence":0.8}]}
        ```
        """
        XCTAssertEqual(InquiryLiveRouter.parseUnits(raw: raw, validQuestionUUIDs: []).count, 1)
    }

    func testMalformedPayloadReturnsEmpty() {
        XCTAssertTrue(InquiryLiveRouter.parseUnits(raw: "not json at all", validQuestionUUIDs: []).isEmpty)
        XCTAssertTrue(InquiryLiveRouter.parseUnits(raw: #"{"units":"oops"}"#, validQuestionUUIDs: []).isEmpty)
    }

    func testInventedQuestionUUIDIsDropped() {
        let raw = """
        {"units":[{"text":"A claim","kind":"claim","targetQuestionUUID":"made-up-uuid","newBranchTitle":null,"conceptNames":[],"confidence":0.8}]}
        """
        let units = InquiryLiveRouter.parseUnits(raw: raw, validQuestionUUIDs: validUUIDs)
        XCTAssertNil(units.first?.targetQuestionUUID)
    }

    func testCapsAtThreeUnitsAndOneBranch() {
        let raw = """
        {"units":[
          {"text":"a","kind":"claim","newBranchTitle":"Branch one","conceptNames":[],"confidence":0.8},
          {"text":"b","kind":"claim","newBranchTitle":"Branch two","conceptNames":[],"confidence":0.8},
          {"text":"c","kind":"claim","conceptNames":[],"confidence":0.8},
          {"text":"d","kind":"claim","conceptNames":[],"confidence":0.8}
        ]}
        """
        let units = InquiryLiveRouter.parseUnits(raw: raw, validQuestionUUIDs: [])
        XCTAssertEqual(units.count, 3)
        XCTAssertEqual(units.compactMap(\.newBranchTitle).count, 1)
    }

    func testUnknownKindIsSkipped() {
        let raw = """
        {"units":[{"text":"a","kind":"banana","conceptNames":[],"confidence":0.8}]}
        """
        XCTAssertTrue(InquiryLiveRouter.parseUnits(raw: raw, validQuestionUUIDs: []).isEmpty)
    }

    // MARK: - Apply plan

    private func refinement(_ units: [InquiryLiveRouter.RoutedUnit]) -> InquiryLiveRouter.Refinement {
        InquiryLiveRouter.Refinement(decisionId: "decision-1", units: units)
    }

    private func unit(
        _ text: String,
        kind: ExtractKind,
        target: String? = nil,
        branch: String? = nil,
        concepts: [String] = []
    ) -> InquiryLiveRouter.RoutedUnit {
        InquiryLiveRouter.RoutedUnit(
            text: text,
            kind: kind,
            targetQuestionUUID: target,
            newBranchTitle: branch,
            conceptNames: concepts,
            confidence: 0.8
        )
    }

    func testConfirmationIsNoOp() {
        let plan = InquiryLiveRouter.applyPlan(
            for: refinement([unit("Original text", kind: .claim)]),
            originalText: "Original text",
            originalKind: .claim,
            originalQuestionUUID: "q-1"
        )
        XCTAssertTrue(plan.isNoOp)
        XCTAssertNil(plan.original.newKind)
        XCTAssertNil(plan.original.newText)
        XCTAssertTrue(plan.additions.isEmpty)
    }

    func testKindCorrection() {
        let plan = InquiryLiveRouter.applyPlan(
            for: refinement([unit("A trial found X", kind: .evidence)]),
            originalText: "A trial found X",
            originalKind: .note,
            originalQuestionUUID: "q-1"
        )
        XCTAssertFalse(plan.isNoOp)
        XCTAssertEqual(plan.original.newKind, .evidence)
        XCTAssertTrue(plan.summary.contains("Note → Evidence"))
    }

    func testSplitProducesAdditionsAndTrimsOriginal() {
        let plan = InquiryLiveRouter.applyPlan(
            for: refinement([
                unit("First thought", kind: .claim),
                unit("Second thought", kind: .question, branch: "A new branch?"),
                unit("Third thought", kind: .practice)
            ]),
            originalText: "First thought Second thought Third thought",
            originalKind: .note,
            originalQuestionUUID: "q-1"
        )
        XCTAssertEqual(plan.original.newText, "First thought")
        XCTAssertEqual(plan.additions.count, 2)
        XCTAssertTrue(plan.summary.contains("Split into 3 parts"))
        XCTAssertTrue(plan.summary.contains("New branch proposed"))
    }

    func testQuestionMoveDetected() {
        let plan = InquiryLiveRouter.applyPlan(
            for: refinement([unit("Text", kind: .claim, target: "q-2")]),
            originalText: "Text",
            originalKind: .claim,
            originalQuestionUUID: "q-1"
        )
        XCTAssertEqual(plan.original.targetQuestionUUID, "q-2")
        XCTAssertFalse(plan.isNoOp)
    }

    func testSameQuestionTargetIsNotAMove() {
        let plan = InquiryLiveRouter.applyPlan(
            for: refinement([unit("Text", kind: .claim, target: "q-1")]),
            originalText: "Text",
            originalKind: .claim,
            originalQuestionUUID: "q-1"
        )
        XCTAssertNil(plan.original.targetQuestionUUID)
        XCTAssertTrue(plan.isNoOp)
    }

    func testEmptyRefinementIsNoOp() {
        let plan = InquiryLiveRouter.applyPlan(
            for: refinement([]),
            originalText: "Text",
            originalKind: .note,
            originalQuestionUUID: nil
        )
        XCTAssertTrue(plan.isNoOp)
    }

    // MARK: - Decision persistence model

    func testLiveRoutingDecisionRoundtrips() throws {
        let decision = InquiryLiveRoutingDecision(
            id: "decision-1",
            sourceExtractUUID: "e-1",
            summary: "Split into 2 parts",
            destinations: [
                .init(extractUUID: "e-1", kind: .claim, questionUUID: "q-1", conceptNames: ["Pranayama"])
            ]
        )
        let data = try JSONEncoder().encode(decision)
        let decoded = try JSONDecoder().decode(InquiryLiveRoutingDecision.self, from: data)
        XCTAssertEqual(decoded.id, "decision-1")
        XCTAssertEqual(decoded.destinations.first?.kind, .claim)
    }

    func testLegacySessionStructuredDecodesWithoutDecisions() throws {
        let tree = ResearchTreeDocument.bootstrap(rootQuestionAtomUUID: nil)
        let treeJSON = String(data: try JSONEncoder().encode(tree), encoding: .utf8)!
        let legacy = #"{"researchTree": \#(treeJSON)}"#
        let decoded = try JSONDecoder().decode(InquirySessionStructured.self, from: Data(legacy.utf8))
        XCTAssertTrue(decoded.liveRoutingDecisions.isEmpty)
    }
}
