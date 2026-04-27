// CosmoOS/Tests/CosmoOSTests/InquiryPlacementEngineTests.swift

import XCTest
@testable import CosmoOS

final class InquiryPlacementEngineTests: XCTestCase {
    func testAxisShiftBecomesRootQuestion() {
        let active = Atom.new(type: .question, title: "What are the most ancient breathwork practices and why were they used?")
        let decision = InquiryPlacementEngine.placement(
            for: "How does breathing affect frequency and biomagnetic field?",
            fullText: "How does breathing affect frequency and biomagnetic field?",
            context: context(activeQuestion: active)
        )

        XCTAssertEqual(decision.nodeType, .rootQuestion)
        XCTAssertEqual(decision.relationshipType, .rootUnderTopic)
        XCTAssertTrue(decision.appearsInBranchMap)
    }

    func testNarrowingFollowupBecomesChildQuestion() {
        let active = Atom.new(type: .question, title: "How does breathing affect frequency and biomagnetic field?")
        let decision = InquiryPlacementEngine.placement(
            for: "What does frequency or biomagnetic energy affect?",
            fullText: "What does frequency or biomagnetic energy affect?",
            context: context(activeQuestion: active)
        )

        XCTAssertEqual(decision.nodeType, .branchQuestion)
        XCTAssertEqual(decision.relationshipType, .consequenceOf)
        XCTAssertTrue(decision.appearsInBranchMap)
    }

    func testEvidencePromptBecomesOperationalAudit() {
        let decision = InquiryPlacementEngine.placement(
            for: "What stronger sources support or challenge this claim?",
            fullText: "What stronger sources support or challenge this claim?",
            context: context()
        )

        XCTAssertEqual(decision.nodeType, .evidenceQualityInvestigation)
        XCTAssertEqual(decision.relationshipType, .evidenceAuditForClaim)
        XCTAssertFalse(decision.appearsInBranchMap)
    }

    func testFindSourcesBecomesSourceSearchTask() {
        let decision = InquiryPlacementEngine.placement(
            for: "Find stronger sources for the biomagnetic field claim",
            fullText: "Find stronger sources for the biomagnetic field claim",
            context: context()
        )

        XCTAssertEqual(decision.nodeType, .sourceSearchTask)
        XCTAssertEqual(decision.relationshipType, .sourceSearchForQuestion)
        XCTAssertFalse(decision.appearsInBranchMap)
    }

    func testSourceQualityWarningDoesNotCreateQuestionNode() {
        let cards = InquiryPlacementEngine.route(
            text: "Breathing may influence biomagnetic field emission.",
            context: context()
        )

        XCTAssertTrue(cards.contains { $0.kind == .sourceQualityWarning })
        XCTAssertTrue(cards.contains { $0.kind == .evidenceAudit && $0.placement?.appearsInBranchMap == false })
        XCTAssertFalse(cards.contains { $0.title == "New branch question" })
    }

    private func context(activeQuestion: Atom? = nil) -> InquiryPlacementEngine.Context {
        InquiryPlacementEngine.Context(
            deepDiveTitle: "Breathwork",
            activeQuestion: activeQuestion,
            activeQuestionUUID: activeQuestion?.uuid,
            activeBranchNodeId: "active-node",
            sourceTabId: nil,
            originExtractUUID: nil,
            originAction: .saveNote,
            questions: activeQuestion.map { [$0] } ?? [],
            claims: []
        )
    }
}
