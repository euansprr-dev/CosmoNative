import XCTest
@testable import CosmoOS

final class AtomWindowChromeContextTests: XCTestCase {
    func testContextDefaultsToAbsentOutsideAtomWindow() {
        XCTAssertNil(AtomWindowChromeContext.defaultValue)
    }

    func testVisibleControlsReflectCurrentAtomCapabilities() {
        let state = AtomWindowChromeState(
            title: "Call Notes",
            typeIcon: "note.text",
            typeColor: .note,
            canGoBack: true,
            canGoForward: false,
            canBookmark: true,
            isBookmarked: false
        )

        XCTAssertEqual(state.title, "Call Notes")
        XCTAssertEqual(state.typeIcon, "note.text")
        XCTAssertTrue(state.canGoBack)
        XCTAssertFalse(state.canGoForward)
        XCTAssertTrue(state.canBookmark)
        XCTAssertFalse(state.isBookmarked)
    }
}
