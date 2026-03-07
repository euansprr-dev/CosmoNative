import XCTest
@testable import CosmoOS

@MainActor
final class VoiceCommandRouterTests: XCTestCase {
    func testRelevantIdeasInFocusModeRoutesToBringRelatedBlocks() async throws {
        let router = VoiceCommandRouter()

        let ctx = VoiceContextSnapshot(
            selectedSection: .home,
            selectedEntity: nil,
            focusedEntity: EntitySelection(id: 123, type: .content),
            selectedBlockId: nil
        )

        let result = try await router.route(
            "open the three most relevant ideas to the document i currently have open",
            context: ctx,
            executeActions: false
        )

        switch result.action {
        case .bringRelatedBlocks:
            break
        default:
            XCTFail("Expected bringRelatedBlocks, got \(result.action)")
        }

        XCTAssertEqual(result.parameters["count"] as? Int, 3)
    }

    func testSearchAndPlaceCanAnchorToSelectedBlock() async throws {
        let router = VoiceCommandRouter()

        let ctx = VoiceContextSnapshot(
            selectedSection: .home,
            selectedEntity: nil,
            focusedEntity: nil,
            selectedBlockId: "block-123"
        )

        let result = try await router.route(
            "bring up three ideas about productivity to the right of this block",
            context: ctx,
            executeActions: false
        )

        switch result.action {
        case .searchAndPlace:
            break
        default:
            XCTFail("Expected searchAndPlace, got \(result.action)")
        }

        XCTAssertEqual(result.parameters["anchorBlockId"] as? String, "block-123")
        XCTAssertEqual(result.parameters["placement"] as? String, "right")
        XCTAssertEqual(result.parameters["quantity"] as? Int, 3)
    }

    func testRouteSmokeDoesNotThrowForSimpleNavigation() async throws {
        let router = VoiceCommandRouter()

        let result = try await router.route(
            "go to calendar",
            context: VoiceContextStore.shared.snapshot(),
            executeActions: false
        )

        switch result.action {
        case .navigate(let section):
            XCTAssertEqual(section, .calendar)
        default:
            XCTFail("Expected navigate(.calendar), got \(result.action)")
        }
    }
}

@MainActor
final class ExplicitLessonCaptureTests: XCTestCase {
    private let explicitLessonMessage = """
    Please save this as a lesson for future reference:

    Never have that 3 beat pattern in sentences like "X. Y. Z.", always use commas, dots, or elipsis. (example: "The VA loan covers 100% of the purchase price. No down payment. No PMI." should be "The VA loan covers 100% of the purchase price so you don't need any downpayment".

    This makes everything MUCH more conversational.
    """

    func testExplicitLessonParserExtractsFullRuleAndEvidence() {
        let request = ExplicitLessonCaptureParser.parse(explicitLessonMessage)

        XCTAssertNotNil(request)
        XCTAssertEqual(
            request?.rule,
            #"Never have that 3 beat pattern in sentences like "X. Y. Z.", always use commas, dots, or elipsis. (example: "The VA loan covers 100% of the purchase price. No down payment. No PMI." should be "The VA loan covers 100% of the purchase price so you don't need any downpayment"."#
        )
        XCTAssertEqual(request?.category, "voice")
        XCTAssertEqual(request?.evidence, "This makes everything MUCH more conversational.")
    }

    func testExplicitLessonParserIgnoresLessonQueries() {
        XCTAssertNil(ExplicitLessonCaptureParser.parse("What lessons have you learned?"))
        XCTAssertNil(ExplicitLessonCaptureParser.parse("show my lessons"))
    }

    func testTelegramLessonFastPathOnlyMatchesExplicitLessonRequests() {
        XCTAssertTrue(TelegramBridgeService.shouldUseExplicitLessonFastPath(explicitLessonMessage))
        XCTAssertFalse(TelegramBridgeService.shouldUseExplicitLessonFastPath("Idea: build a calculator app"))
    }

    func testFlashLiteGuardForcesLessonRequestsToAgentFallback() {
        XCTAssertTrue(FlashLiteRouter.shouldForceAgentFallback(explicitLessonMessage))
        XCTAssertFalse(FlashLiteRouter.shouldForceAgentFallback("Idea: build a calculator app"))
    }
}
