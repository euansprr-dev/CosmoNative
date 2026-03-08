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
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: screenCenter.x, y: screenCenter.y)
        transform = transform.scaledBy(x: effectiveScale, y: effectiveScale)
        transform = transform.translatedBy(x: -screenCenter.x, y: -screenCenter.y)
        return transform.translatedBy(x: contentOffset.width, y: contentOffset.height)
    }
}
