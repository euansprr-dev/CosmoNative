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
