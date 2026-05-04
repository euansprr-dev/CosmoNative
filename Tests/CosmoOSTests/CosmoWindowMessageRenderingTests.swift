import XCTest
@testable import CosmoOS

final class CosmoWindowMessageRenderingTests: XCTestCase {
    func testTimelineTextSelectionIsDisabledToAvoidSelectionOverlayLayoutLoop() {
        XCTAssertFalse(CosmoWindowMessageRenderingPolicy.allowsTimelineTextSelection)
    }
}
