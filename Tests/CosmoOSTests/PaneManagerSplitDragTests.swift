import XCTest
@testable import CosmoOS

/// The content-layout freeze exists because a heavy pane body re-laying-out
/// per width event can wedge the main thread (July 28 assistant-pane resize
/// livelock). Two continuous width streams feed it — the main-split divider
/// drag and window live resize — and the deck consults one combined flag.
/// Slots keep tracking the width; content re-lays once when the stream ends.
@MainActor
final class PaneManagerSplitDragTests: XCTestCase {

    func testBeginAndEndMainSplitDragToggleTheFreezeFlag() {
        let manager = PaneManager()
        XCTAssertFalse(manager.isDraggingMainSplit)

        manager.beginMainSplitDrag()
        XCTAssertTrue(manager.isDraggingMainSplit)

        manager.endMainSplitDrag()
        XCTAssertFalse(manager.isDraggingMainSplit)
    }

    func testUpdateMainSplitStillMovesRatioWhileDragIsLive() {
        let manager = PaneManager()
        manager.openOrActivateCosmoWindow()
        XCTAssertEqual(manager.mainSplitRatio, 0.5)

        manager.beginMainSplitDrag()
        manager.updateMainSplit(delta: 100, totalWidth: 1000)
        XCTAssertEqual(manager.mainSplitRatio, 0.6, accuracy: 0.0001)
        XCTAssertTrue(manager.isDraggingMainSplit, "ratio updates must not end the drag freeze")

        manager.endMainSplitDrag()
        XCTAssertEqual(manager.mainSplitRatio, 0.6, accuracy: 0.0001, "drag end must not reset the ratio")
    }

    func testWindowLiveResizeTogglesTheFreezeFlag() {
        let manager = PaneManager()
        XCTAssertFalse(manager.isWindowLiveResizing)
        XCTAssertFalse(manager.isPaneContentLayoutFrozen)

        manager.beginWindowLiveResize()
        XCTAssertTrue(manager.isWindowLiveResizing)
        XCTAssertTrue(manager.isPaneContentLayoutFrozen)

        manager.endWindowLiveResize()
        XCTAssertFalse(manager.isWindowLiveResizing)
        XCTAssertFalse(manager.isPaneContentLayoutFrozen)
    }

    func testCombinedFreezeStaysOnWhileEitherStreamIsLive() {
        let manager = PaneManager()

        // Window resize begins, then a divider drag starts mid-resize.
        manager.beginWindowLiveResize()
        manager.beginMainSplitDrag()
        XCTAssertTrue(manager.isPaneContentLayoutFrozen)

        // Ending one stream must not thaw while the other is still live.
        manager.endWindowLiveResize()
        XCTAssertTrue(manager.isPaneContentLayoutFrozen, "divider drag still live")

        manager.endMainSplitDrag()
        XCTAssertFalse(manager.isPaneContentLayoutFrozen)
    }

    func testEndWindowLiveResizeIsIdempotent() {
        // The AppKit shim thaws both on viewDidEndLiveResize and when the
        // observer leaves a mid-resize window — the double call must be safe.
        let manager = PaneManager()
        manager.beginWindowLiveResize()

        manager.endWindowLiveResize()
        manager.endWindowLiveResize()
        XCTAssertFalse(manager.isWindowLiveResizing)
        XCTAssertFalse(manager.isPaneContentLayoutFrozen)
    }

    func testUpdateMainSplitClampsToRatioBounds() {
        let manager = PaneManager()
        manager.openOrActivateCosmoWindow()

        manager.updateMainSplit(delta: -10_000, totalWidth: 1000)
        XCTAssertEqual(manager.mainSplitRatio, 0.25)

        manager.updateMainSplit(delta: 10_000, totalWidth: 1000)
        XCTAssertEqual(manager.mainSplitRatio, 0.75)

        manager.updateMainSplit(delta: 50, totalWidth: 0)
        XCTAssertEqual(manager.mainSplitRatio, 0.75, "zero total width must be a no-op, not a NaN")
    }
}
