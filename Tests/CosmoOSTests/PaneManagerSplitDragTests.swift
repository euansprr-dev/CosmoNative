import XCTest
@testable import CosmoOS

/// Two continuous width streams feed one flag — the main-split divider drag
/// and window live resize. The flag does NOT freeze the deck: it only tells
/// `.tracksSteps` panes to follow the coarse width ladder, because a body
/// that deep re-laying-out per width event can wedge the main thread (July 28
/// assistant-pane resize livelock). Every other pane resizes live.
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
        XCTAssertFalse(manager.isWidthStreamWindowResize)
        XCTAssertFalse(manager.isWidthStreamActive)

        manager.beginWindowLiveResize()
        XCTAssertTrue(manager.isWidthStreamWindowResize)
        XCTAssertTrue(manager.isWidthStreamActive)

        manager.endWindowLiveResize()
        XCTAssertFalse(manager.isWidthStreamWindowResize)
        XCTAssertFalse(manager.isWidthStreamActive)
    }

    func testCombinedFreezeStaysOnWhileEitherStreamIsLive() {
        let manager = PaneManager()

        // Window resize begins, then a divider drag starts mid-resize.
        manager.beginWindowLiveResize()
        manager.beginMainSplitDrag()
        XCTAssertTrue(manager.isWidthStreamActive)

        // Ending one stream must not thaw while the other is still live.
        manager.endWindowLiveResize()
        XCTAssertTrue(manager.isWidthStreamActive, "divider drag still live")

        manager.endMainSplitDrag()
        XCTAssertFalse(manager.isWidthStreamActive)
    }

    func testEndWindowLiveResizeIsIdempotent() {
        // The AppKit shim thaws both on viewDidEndLiveResize and when the
        // observer leaves a mid-resize window — the double call must be safe.
        let manager = PaneManager()
        manager.beginWindowLiveResize()

        manager.endWindowLiveResize()
        manager.endWindowLiveResize()
        XCTAssertFalse(manager.isWidthStreamWindowResize)
        XCTAssertFalse(manager.isWidthStreamActive)
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

    // MARK: - Width stream behavior

    /// The regression the ladder was scoped to fix: a swipe/idea/browser pane
    /// used to sit at a stale width for the whole drag and snap on drop. Only
    /// the assistant family may ever do that.
    func testOnlyTheAssistantFamilyStepsItsWidth() {
        let live: [PaneContent] = [
            .entity(EntitySelection(id: 1, type: .idea)),
            .thinkspace(thinkspaceId: "ts"),
            .commandCenter,
            .swipeGallery,
            .webBrowser(url: URL(string: "https://example.com")!, title: nil)
        ]
        for pane in live {
            XCTAssertEqual(pane.widthStreamBehavior, .tracksLive, "\(pane.id) must resize live")
        }

        let target = CollaborationTarget(
            source: .focusMode,
            entityID: 1,
            entityType: .idea,
            atomUUID: "uuid",
            title: "Idea"
        )
        let stepped: [PaneContent] = [
            .cosmoWindow,
            .inlineAssistant,
            .collaborator(target: target, presetId: nil)
        ]
        for pane in stepped {
            XCTAssertEqual(pane.widthStreamBehavior, .tracksSteps, "\(pane.id) must step")
        }
    }

    /// Jitter inside one rung is the old livelock's worst case — hundreds of
    /// events travelling almost no distance. It must cost zero re-layouts.
    func testSteppedWidthHoldsItsRungUntilAFullStepIsTravelled() {
        let step = PaneSlotPresentationPolicy.widthStreamStep

        for delta in stride(from: CGFloat(0), to: step, by: 6) {
            XCTAssertEqual(
                PaneSlotPresentationPolicy.steppedWidth(live: 600 + delta, adopted: 600),
                600,
                "a \(delta)pt move inside the rung must not re-lay-out"
            )
            XCTAssertEqual(
                PaneSlotPresentationPolicy.steppedWidth(live: 600 - delta, adopted: 600),
                600,
                "the deadband is symmetric"
            )
        }
    }

    func testSteppedWidthAdoptsTheLiveWidthOnceTheRungIsCrossed() {
        let step = PaneSlotPresentationPolicy.widthStreamStep

        XCTAssertEqual(PaneSlotPresentationPolicy.steppedWidth(live: 600 + step, adopted: 600), 600 + step)
        XCTAssertEqual(PaneSlotPresentationPolicy.steppedWidth(live: 600 - step, adopted: 600), 600 - step)
        // It lands on the live width, not on a quantized grid — so the rung a
        // stream ends on is the width the body actually wants.
        XCTAssertEqual(PaneSlotPresentationPolicy.steppedWidth(live: 723, adopted: 600), 723)
    }

    /// A pane opened mid-drag has no rung to hold, so it must lay out at the
    /// live width rather than at some inherited neighbour's width.
    func testSteppedWidthTakesTheLiveWidthWhenThereIsNoRungYet() {
        XCTAssertEqual(PaneSlotPresentationPolicy.steppedWidth(live: 512, adopted: nil), 512)
    }

    /// Re-layouts are bounded by distance travelled, never by stream duration
    /// — that is the property that stops a stream queueing work faster than
    /// it retires it.
    func testRelayoutCountIsBoundedByDistanceNotEventCount() {
        let step = PaneSlotPresentationPolicy.widthStreamStep
        let travel: CGFloat = 900
        var adopted: CGFloat = 400
        var relayouts = 0

        // 1800 events (a slow, dense drag) covering 900pt.
        for event in 1...1800 {
            let live = 400 + travel * CGFloat(event) / 1800
            let next = PaneSlotPresentationPolicy.steppedWidth(live: live, adopted: adopted)
            if next != adopted {
                relayouts += 1
                adopted = next
            }
        }

        XCTAssertLessThanOrEqual(relayouts, Int((travel / step).rounded(.up)))
        XCTAssertGreaterThan(relayouts, 0, "the body must visibly move during the drag")
    }
}
