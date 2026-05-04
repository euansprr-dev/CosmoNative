import XCTest
@testable import CosmoOS

final class CosmoWindowRoutingTests: XCTestCase {
    func testBypassesFlashRouterForFollowUpAboutCapturedContent() {
        let recentAssistant = [
            "Captured Instagram swipe.",
            "Saved idea: The hook is worth adapting."
        ]

        XCTAssertTrue(
            CosmoWindowViewModel.shouldBypassFlashRouter(
                text: "turn this into a carousel",
                recentAssistantContents: recentAssistant
            )
        )
    }

    func testDoesNotBypassFlashRouterWithoutCaptureHistory() {
        XCTAssertFalse(
            CosmoWindowViewModel.shouldBypassFlashRouter(
                text: "turn this into a carousel",
                recentAssistantContents: ["I can help think through that."]
            )
        )
    }
}
