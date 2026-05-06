import SwiftUI

/// Shared pan/zoom transform used by canvas-based surfaces.
/// Keeps viewport math in one place so rendering and hit-testing agree.
struct CanvasViewportTransform: Equatable {
    var viewportSize: CGSize
    var committedOffset: CGSize
    var gesturePanOffset: CGSize = .zero
    var committedScale: CGFloat = 1.0
    var gestureMagnification: CGFloat = 1.0
    var minScale: CGFloat = 0.25
    var maxScale: CGFloat = 3.0

    var screenCenter: CGPoint {
        CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    var effectiveScale: CGFloat {
        min(max(committedScale * gestureMagnification, minScale), maxScale)
    }

    /// Gesture pan is collected in screen space and converted back into canvas space.
    var scaledPanOffset: CGSize {
        CGSize(
            width: gesturePanOffset.width / effectiveScale,
            height: gesturePanOffset.height / effectiveScale
        )
    }

    var contentOffset: CGSize {
        CGSize(
            width: committedOffset.width + scaledPanOffset.width,
            height: committedOffset.height + scaledPanOffset.height
        )
    }

    var visibleCanvasRect: CGRect {
        let width = viewportSize.width / effectiveScale
        let height = viewportSize.height / effectiveScale
        let center = CGPoint(
            x: screenCenter.x - contentOffset.width,
            y: screenCenter.y - contentOffset.height
        )
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    func canvasToScreen(_ point: CGPoint) -> CGPoint {
        let translated = CGPoint(
            x: point.x + contentOffset.width,
            y: point.y + contentOffset.height
        )
        return CGPoint(
            x: screenCenter.x + (translated.x - screenCenter.x) * effectiveScale,
            y: screenCenter.y + (translated.y - screenCenter.y) * effectiveScale
        )
    }

    func screenToCanvas(_ point: CGPoint) -> CGPoint {
        let unscaledX = screenCenter.x + (point.x - screenCenter.x) / effectiveScale
        let unscaledY = screenCenter.y + (point.y - screenCenter.y) / effectiveScale
        return CGPoint(
            x: unscaledX - contentOffset.width,
            y: unscaledY - contentOffset.height
        )
    }

    func canvasRectToScreen(_ rect: CGRect) -> CGRect {
        let minPoint = canvasToScreen(rect.origin)
        let maxPoint = canvasToScreen(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: min(minPoint.x, maxPoint.x),
            y: min(minPoint.y, maxPoint.y),
            width: abs(maxPoint.x - minPoint.x),
            height: abs(maxPoint.y - minPoint.y)
        )
    }

    /// Affine transform that maps canvas-space paths into screen space.
    func canvasToScreenAffineTransform() -> CGAffineTransform {
        let scale = effectiveScale
        return CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: screenCenter.x * (1 - scale) + contentOffset.width * scale,
            ty: screenCenter.y * (1 - scale) + contentOffset.height * scale
        )
    }

    /// Affine transform for points already expressed in content space
    /// (`canvas point + contentOffset`). This matches the scaled canvas container.
    func contentToScreenAffineTransform() -> CGAffineTransform {
        let scale = effectiveScale
        return CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: screenCenter.x * (1 - scale),
            ty: screenCenter.y * (1 - scale)
        )
    }

    func committedOnly() -> CanvasViewportTransform {
        CanvasViewportTransform(
            viewportSize: viewportSize,
            committedOffset: committedOffset,
            gesturePanOffset: .zero,
            committedScale: committedScale,
            gestureMagnification: 1,
            minScale: minScale,
            maxScale: maxScale
        )
    }
}

/// Compositor-facing transform for the SwiftUI canvas world layer.
/// Blocks and clusters remain positioned in raw canvas coordinates; the
/// enclosing layer receives this offset and scale so pan/zoom can move the
/// world as one compositor transform instead of relaying coordinates through
/// every child view.
struct CanvasCompositorTransform: Equatable {
    let contentOffset: CGSize
    let effectiveScale: CGFloat
    let anchor: UnitPoint
    private let transform: CanvasViewportTransform

    init(viewportTransform: CanvasViewportTransform) {
        self.transform = viewportTransform
        self.contentOffset = viewportTransform.contentOffset
        self.effectiveScale = viewportTransform.effectiveScale

        let viewportSize = viewportTransform.viewportSize
        if viewportSize.width > 0, viewportSize.height > 0 {
            self.anchor = UnitPoint(
                x: viewportTransform.screenCenter.x / viewportSize.width,
                y: viewportTransform.screenCenter.y / viewportSize.height
            )
        } else {
            self.anchor = .center
        }
    }

    func screenPoint(forCanvasPoint point: CGPoint) -> CGPoint {
        let translated = CGPoint(
            x: point.x + contentOffset.width,
            y: point.y + contentOffset.height
        )
        let center = transform.screenCenter
        return CGPoint(
            x: center.x + (translated.x - center.x) * effectiveScale,
            y: center.y + (translated.y - center.y) * effectiveScale
        )
    }
}

struct CanvasGridPatternMetrics: Equatable {
    let tileSize: CGFloat
    let rawDotSize: CGFloat
    let planeOrigin: CGPoint
    let planeSize: CGSize
    let scaleAnchor: UnitPoint

    init(
        transform: CanvasViewportTransform,
        viewportSize: CGSize,
        tileSize: CGFloat = 40,
        baseDotSize: CGFloat = 2.5,
        minimumScreenDotSize: CGFloat = 0.75,
        preloadTileCount: CGFloat = 2
    ) {
        self.tileSize = tileSize
        self.rawDotSize = max(baseDotSize, minimumScreenDotSize / max(transform.effectiveScale, 0.001))

        let padding = tileSize * preloadTileCount
        let visibleRect = transform.visibleCanvasRect.insetBy(dx: -padding, dy: -padding)
        let minX = floor(visibleRect.minX / tileSize) * tileSize
        let minY = floor(visibleRect.minY / tileSize) * tileSize
        let maxX = ceil(visibleRect.maxX / tileSize) * tileSize
        let maxY = ceil(visibleRect.maxY / tileSize) * tileSize
        self.planeOrigin = CGPoint(x: minX, y: minY)
        self.planeSize = CGSize(
            width: max(maxX - minX, tileSize),
            height: max(maxY - minY, tileSize)
        )

        if viewportSize.width > 0, viewportSize.height > 0 {
            self.scaleAnchor = UnitPoint(
                x: transform.screenCenter.x / viewportSize.width,
                y: transform.screenCenter.y / viewportSize.height
            )
        } else {
            self.scaleAnchor = .center
        }
    }
}
