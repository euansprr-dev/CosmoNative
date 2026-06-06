import XCTest
@testable import CosmoOS

final class CanvasViewportTransformTests: XCTestCase {
    func testEmptySpaceDoubleClickZoomsInByTwentyFivePercent() {
        let zoomedScale = CanvasZoomPolicy.emptySpaceDoubleClickScale(
            currentScale: 1.2,
            minScale: 0.25,
            maxScale: 3.0
        )

        XCTAssertEqual(zoomedScale, 1.5, accuracy: 0.001)
    }

    func testEmptySpaceDoubleClickZoomRespectsMaximumScale() {
        let zoomedScale = CanvasZoomPolicy.emptySpaceDoubleClickScale(
            currentScale: 2.8,
            minScale: 0.25,
            maxScale: 3.0
        )

        XCTAssertEqual(zoomedScale, 3.0, accuracy: 0.001)
    }

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

    func testCanvasAffineTransformMatchesPointwiseConversionAcrossPanAndZoom() {
        let transforms = [
            CanvasViewportTransform(
                viewportSize: CGSize(width: 1200, height: 800),
                committedOffset: CGSize(width: 180, height: -90),
                gesturePanOffset: CGSize(width: 60, height: 30),
                committedScale: 1.4,
                gestureMagnification: 1.1
            ),
            CanvasViewportTransform(
                viewportSize: CGSize(width: 900, height: 700),
                committedOffset: CGSize(width: -240, height: 160),
                gesturePanOffset: CGSize(width: -80, height: 45),
                committedScale: 0.35,
                gestureMagnification: 0.8
            ),
            CanvasViewportTransform(
                viewportSize: CGSize(width: 1440, height: 960),
                committedOffset: CGSize(width: 20, height: 300),
                gesturePanOffset: CGSize(width: 120, height: -90),
                committedScale: 2.6,
                gestureMagnification: 1.4
            )
        ]
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 320, y: 470),
            CGPoint(x: -180, y: 920),
            CGPoint(x: 1_500, y: -640)
        ]

        for transform in transforms {
            let affine = transform.canvasToScreenAffineTransform()
            for point in points {
                let affinePoint = point.applying(affine)
                let pointwise = transform.canvasToScreen(point)
                XCTAssertEqual(affinePoint.x, pointwise.x, accuracy: 0.001)
                XCTAssertEqual(affinePoint.y, pointwise.y, accuracy: 0.001)
            }
        }
    }

    func testContentAffineTransformMatchesCanvasPointsWithOffsetAlreadyApplied() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1000, height: 800),
            committedOffset: CGSize(width: -120, height: 260),
            gesturePanOffset: CGSize(width: 150, height: -90),
            committedScale: 1.75,
            gestureMagnification: 0.7
        )
        let canvasPoint = CGPoint(x: 480, y: 260)
        let contentPoint = CGPoint(
            x: canvasPoint.x + transform.contentOffset.width,
            y: canvasPoint.y + transform.contentOffset.height
        )

        let affinePoint = contentPoint.applying(transform.contentToScreenAffineTransform())
        let pointwise = transform.canvasToScreen(canvasPoint)

        XCTAssertEqual(affinePoint.x, pointwise.x, accuracy: 0.001)
        XCTAssertEqual(affinePoint.y, pointwise.y, accuracy: 0.001)
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

final class CanvasKeyboardShortcutPolicyTests: XCTestCase {
    func testTabTogglesMinimapOnlyWhenCanvasCanOwnShortcut() {
        XCTAssertTrue(
            CanvasKeyboardShortcutPolicy.shouldToggleMinimap(
                keyCode: 48,
                eventType: .keyDown,
                isActive: true,
                isCommandKVisible: false,
                hasFocusedEntity: false,
                isTextInputFocused: false
            )
        )

        XCTAssertFalse(
            CanvasKeyboardShortcutPolicy.shouldToggleMinimap(
                keyCode: 48,
                eventType: .keyDown,
                isActive: true,
                isCommandKVisible: false,
                hasFocusedEntity: false,
                isTextInputFocused: true
            )
        )

        XCTAssertFalse(
            CanvasKeyboardShortcutPolicy.shouldToggleMinimap(
                keyCode: 48,
                eventType: .keyDown,
                isActive: false,
                isCommandKVisible: false,
                hasFocusedEntity: false,
                isTextInputFocused: false
            )
        )
    }
}

final class CanvasImageDropControllerTests: XCTestCase {
    func testAcceptsFinderFileURLAndImageTypes() {
        XCTAssertTrue(CanvasImageDropController.accepts([.fileURL]))
        XCTAssertTrue(CanvasImageDropController.accepts([.png]))
        XCTAssertTrue(CanvasImageDropController.accepts([.jpeg]))
    }

    func testRejectsNonImageNonFileTypes() {
        XCTAssertFalse(CanvasImageDropController.accepts([.plainText]))
        XCTAssertFalse(CanvasImageDropController.accepts([.url]))
    }

    func testImageTitleStripsFilenameExtension() {
        XCTAssertEqual(CanvasImageDropController.imageTitle(originalFilename: "desktop-shot.png"), "desktop-shot")
        XCTAssertEqual(CanvasImageDropController.imageTitle(originalFilename: nil), "Image")
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
    func testWidthChangesInvalidateCachedFreehandPath() throws {
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
