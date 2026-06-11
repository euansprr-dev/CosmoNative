import XCTest
@testable import CosmoOS

@MainActor
final class PaneManagerInlineAssistantPaneTests: XCTestCase {
    func testInlineAssistantPaneHasStableIDAndMinimalChrome() {
        let content = PaneContent.inlineAssistant
        XCTAssertEqual(content.id, "inlineAssistant")
        XCTAssertEqual(content.chromeStyle, .minimal)
    }

    func testOpenOrActivateInlineAssistantDoesNotDuplicatePane() {
        let manager = PaneManager()
        manager.openOrActivateInlineAssistant()
        manager.openOrActivateInlineAssistant()

        XCTAssertEqual(manager.panes.filter { $0.id == "inlineAssistant" }.count, 1)
        XCTAssertEqual(manager.activePaneId, "inlineAssistant")
    }

    func testOptionAHotkeyRouterOpensInlineAssistantInsteadOfCosmoWindow() {
        let inlineExpectation = expectation(
            forNotification: CosmoNotification.Navigation.openInlineAssistant,
            object: nil
        )
        let floatingWindowExpectation = expectation(
            forNotification: CosmoNotification.CosmoWindow.toggle,
            object: nil
        )
        floatingWindowExpectation.isInverted = true

        CosmoAssistantHotkeyRouter.openFromOptionA(activateApp: false)

        wait(for: [inlineExpectation, floatingWindowExpectation], timeout: 0.1)
    }
}
