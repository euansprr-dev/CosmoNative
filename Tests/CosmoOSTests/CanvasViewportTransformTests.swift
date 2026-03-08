import XCTest
@testable import CosmoOS

final class CanvasViewportTransformTests: XCTestCase {
    func testCanvasPointRoundTripsThroughScreenSpace() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1200, height: 800),
            committedOffset: CGSize(width: 180, height: -90),
            gesturePanOffset: CGSize(width: 60, height: 30),
            committedScale: 1.4,
            gestureMagnification: 1.1,
            minScale: 0.25,
            maxScale: 3.0
        )

        let original = CGPoint(x: 320, y: 470)
        let screenPoint = transform.canvasToScreen(original)
        let roundTrip = transform.screenToCanvas(screenPoint)

        XCTAssertEqual(roundTrip.x, original.x, accuracy: 0.001)
        XCTAssertEqual(roundTrip.y, original.y, accuracy: 0.001)
    }

    func testVisibleCanvasRectUsesCombinedPanAndZoom() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1000, height: 800),
            committedOffset: CGSize(width: 100, height: -50),
            committedScale: 2.0
        )

        XCTAssertEqual(transform.visibleCanvasRect.origin.x, 150, accuracy: 0.001)
        XCTAssertEqual(transform.visibleCanvasRect.origin.y, 250, accuracy: 0.001)
        XCTAssertEqual(transform.visibleCanvasRect.width, 500, accuracy: 0.001)
        XCTAssertEqual(transform.visibleCanvasRect.height, 400, accuracy: 0.001)
    }
}

final class ActiveCanvasDragStateTests: XCTestCase {
    func testTranslationOnlyAppliesToActiveIdentifier() {
        var dragState = ActiveCanvasDragState<String>()
        dragState.begin(id: "block-1", translation: CGSize(width: 42, height: -18))

        XCTAssertTrue(dragState.isDragging)
        XCTAssertEqual(dragState.translation(for: "block-1").width, 42, accuracy: 0.001)
        XCTAssertEqual(dragState.translation(for: "block-2"), .zero)

        dragState.clear()

        XCTAssertFalse(dragState.isDragging)
        XCTAssertEqual(dragState.translation, .zero)
    }
}

final class CanvasVisibilityIndexTests: XCTestCase {
    func testVisibilityIndexUsesPreloadRectForNearViewportBlocks() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1000, height: 800),
            committedOffset: .zero,
            committedScale: 1.0
        )
        let visibility = CanvasVisibilityIndex(transform: transform, preloadInset: 100)

        let nearEdgeBlock = CanvasBlock(
            id: "visible",
            position: CGPoint(x: -40, y: 400),
            size: CGSize(width: 120, height: 120),
            entityType: .note,
            entityId: 1,
            entityUuid: "visible-uuid",
            title: "Visible"
        )
        let farBlock = CanvasBlock(
            id: "hidden",
            position: CGPoint(x: -240, y: 400),
            size: CGSize(width: 120, height: 120),
            entityType: .note,
            entityId: 2,
            entityUuid: "hidden-uuid",
            title: "Hidden"
        )

        XCTAssertTrue(visibility.isBlockVisible(nearEdgeBlock))
        XCTAssertFalse(visibility.isBlockVisible(farBlock))
    }
}

@MainActor
final class CanvasDrawingStrokeCacheTests: XCTestCase {
    func testWidthChangesInvalidateCachedFreehandPath() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 80, y: 0),
        ]

        let thinStroke = CanvasDrawing(
            id: "drawing-1",
            drawingType: .freehand,
            pathPoints: points,
            pathWidths: [2, 2, 2],
            strokeWidth: 2
        )
        let thickStroke = CanvasDrawing(
            id: "drawing-1",
            drawingType: .freehand,
            pathPoints: points,
            pathWidths: [12, 12, 12],
            strokeWidth: 2
        )

        let cache = CanvasDrawingStrokeCache()
        let thinBounds = try XCTUnwrap(cache.rendering(for: thinStroke)?.path.boundingRect)
        let thickBounds = try XCTUnwrap(cache.rendering(for: thickStroke)?.path.boundingRect)

        XCTAssertLessThan(thinBounds.height, thickBounds.height)
    }
}
