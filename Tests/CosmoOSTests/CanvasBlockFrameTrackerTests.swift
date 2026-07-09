import XCTest
@testable import CosmoOS

/// Right-click hit-testing must agree with what the canvas renders:
/// canvas-space geometry for renderable blocks only, converted with the
/// LIVE viewport transform at click time.
@MainActor
final class CanvasBlockFrameTrackerTests: XCTestCase {

    private func makeBlock(
        id: String,
        position: CGPoint,
        size: CGSize = CGSize(width: 200, height: 120),
        zIndex: Int = 0,
        uuid: String? = nil
    ) -> CanvasBlock {
        CanvasBlock(
            id: id,
            position: position,
            size: size,
            zIndex: zIndex,
            entityType: .idea,
            entityId: 1,
            entityUuid: uuid ?? "\(id)-uuid",
            title: id
        )
    }

    private func makeTransform(
        offset: CGSize = .zero,
        scale: CGFloat = 1.0,
        viewport: CGSize = CGSize(width: 1_200, height: 800)
    ) -> CanvasViewportTransform {
        CanvasViewportTransform(
            viewportSize: viewport,
            committedOffset: offset,
            committedScale: scale
        )
    }

    private func makeTracker(transform: @escaping () -> CanvasViewportTransform) -> CanvasBlockFrameTracker {
        let tracker = CanvasBlockFrameTracker()
        tracker.liveTransformProvider = { transform() }
        return tracker
    }

    func testHitsBlockUnderCursorAtZoomedOutTransform() {
        let transform = makeTransform(offset: CGSize(width: -300, height: 150), scale: 0.4)
        let tracker = makeTracker { transform }
        let block = makeBlock(id: "hit-target", position: CGPoint(x: 500, y: 400))

        tracker.update(blocks: [block], userClusters: [], transform: transform)

        let screenPoint = transform.canvasToScreen(block.position)
        XCTAssertEqual(tracker.rightClickHitTest(at: screenPoint), .block("hit-target"))

        // Just outside the block's edge must miss.
        let outsideCanvasPoint = CGPoint(x: 500 + 101, y: 400)
        let outsideScreen = transform.canvasToScreen(outsideCanvasPoint)
        XCTAssertEqual(tracker.rightClickHitTest(at: outsideScreen), .empty)
    }

    func testPanAndZoomAfterUpdateNeverGoesStale() {
        // The tracker was last fed at identity; the user then pans and zooms.
        var liveTransform = makeTransform()
        let tracker = makeTracker { liveTransform }
        let block = makeBlock(id: "pan-target", position: CGPoint(x: 500, y: 400))

        tracker.update(blocks: [block], userClusters: [], transform: liveTransform)

        // Pan + zoom WITHOUT another tracker update.
        liveTransform = makeTransform(offset: CGSize(width: 900, height: -350), scale: 1.8)

        let screenPoint = liveTransform.canvasToScreen(block.position)
        XCTAssertEqual(tracker.rightClickHitTest(at: screenPoint), .block("pan-target"))

        // The block's OLD screen position must no longer hit.
        let staleScreenPoint = makeTransform().canvasToScreen(block.position)
        XCTAssertNotEqual(tracker.rightClickHitTest(at: staleScreenPoint), .block("pan-target"))
    }

    func testClusterConsumedBlocksAreNotHitTestable() {
        let transform = makeTransform()
        let tracker = makeTracker { transform }
        let consumed = makeBlock(id: "consumed", position: CGPoint(x: 500, y: 400))
        let cluster = CanvasCluster(
            id: UUID(),
            name: "Board cluster",
            blockUUIDs: [consumed.entityUuid],
            colorIndex: 0,
            boundingRect: CGRect(x: 300, y: 250, width: 500, height: 400),
            isCollapsed: false,
            isUserCreated: true,
            viewMode: .board
        )

        tracker.update(blocks: [consumed], userClusters: [cluster], transform: transform)

        // The consumed block's canvas position lies inside the expanded
        // cluster — the click belongs to the cluster's own UI, never to the
        // invisible block, and never to the radial menu.
        let screenPoint = transform.canvasToScreen(consumed.position)
        XCTAssertEqual(tracker.rightClickHitTest(at: screenPoint), .expandedCluster)
        XCTAssertTrue(tracker.trackedBlocks.isEmpty)

        // Outside the cluster: genuinely empty canvas.
        let outside = transform.canvasToScreen(CGPoint(x: 1_000, y: 1_000))
        XCTAssertEqual(tracker.rightClickHitTest(at: outside), .empty)
    }

    func testCanvasModeClusterMembersRemainHitTestable() {
        let transform = makeTransform()
        let tracker = makeTracker { transform }
        let member = makeBlock(id: "free-member", position: CGPoint(x: 500, y: 400))
        let cluster = CanvasCluster(
            id: UUID(),
            name: "Canvas cluster",
            blockUUIDs: [member.entityUuid],
            colorIndex: 0,
            boundingRect: CGRect(x: 300, y: 250, width: 500, height: 400),
            isCollapsed: false,
            isUserCreated: true,
            viewMode: .canvas
        )

        tracker.update(blocks: [member], userClusters: [cluster], transform: transform)

        let screenPoint = transform.canvasToScreen(member.position)
        XCTAssertEqual(tracker.rightClickHitTest(at: screenPoint), .block("free-member"))
    }

    func testTopmostZIndexWinsOnOverlap() {
        let transform = makeTransform()
        let tracker = makeTracker { transform }
        let bottom = makeBlock(id: "bottom", position: CGPoint(x: 500, y: 400), zIndex: 1)
        let top = makeBlock(id: "top", position: CGPoint(x: 520, y: 410), zIndex: 5)

        tracker.update(blocks: [bottom, top], userClusters: [], transform: transform)

        let overlapPoint = transform.canvasToScreen(CGPoint(x: 510, y: 405))
        XCTAssertEqual(tracker.rightClickHitTest(at: overlapPoint), .block("top"))
    }

    func testSuspendedSurfaceDeclinesTheEvent() {
        let transform = makeTransform()
        let tracker = makeTracker { transform }
        let block = makeBlock(id: "library-hidden", position: CGPoint(x: 500, y: 400))
        tracker.update(blocks: [block], userClusters: [], transform: transform)

        tracker.isCanvasSurfaceActive = false
        let screenPoint = transform.canvasToScreen(block.position)
        XCTAssertNil(tracker.rightClickHitTest(at: screenPoint))

        tracker.isCanvasSurfaceActive = true
        XCTAssertEqual(tracker.rightClickHitTest(at: screenPoint), .block("library-hidden"))
    }

    func testMissingTransformProviderDeclinesTheEvent() {
        let tracker = CanvasBlockFrameTracker()
        let transform = makeTransform()
        let block = makeBlock(id: "orphan", position: CGPoint(x: 500, y: 400))
        tracker.update(blocks: [block], userClusters: [], transform: transform)

        XCTAssertNil(tracker.rightClickHitTest(at: transform.canvasToScreen(block.position)))
    }

    func testScreenFramesStayAvailableForOverlayConsumers() {
        let transform = makeTransform(offset: CGSize(width: 120, height: -60), scale: 1.5)
        let tracker = makeTracker { transform }
        let block = makeBlock(id: "overlay-frame", position: CGPoint(x: 500, y: 400))

        tracker.update(blocks: [block], userClusters: [], transform: transform)

        let expected = transform.canvasRectToScreen(
            CGRect(x: 400, y: 340, width: 200, height: 120)
        )
        let frame = tracker.blockFrames["overlay-frame"]
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.origin.x ?? -1, expected.origin.x, accuracy: 0.001)
        XCTAssertEqual(frame?.origin.y ?? -1, expected.origin.y, accuracy: 0.001)
        XCTAssertEqual(frame?.width ?? -1, expected.width, accuracy: 0.001)
        XCTAssertEqual(frame?.height ?? -1, expected.height, accuracy: 0.001)

        // refreshScreenFrames retargets the same canvas rects to a new transform.
        let newTransform = makeTransform(offset: CGSize(width: -400, height: 90), scale: 0.5)
        tracker.refreshScreenFrames(transform: newTransform)
        let refreshed = tracker.blockFrames["overlay-frame"]
        let refreshedExpected = newTransform.canvasRectToScreen(
            CGRect(x: 400, y: 340, width: 200, height: 120)
        )
        XCTAssertEqual(refreshed?.origin.x ?? -1, refreshedExpected.origin.x, accuracy: 0.001)
        XCTAssertEqual(refreshed?.origin.y ?? -1, refreshedExpected.origin.y, accuracy: 0.001)
    }
}
