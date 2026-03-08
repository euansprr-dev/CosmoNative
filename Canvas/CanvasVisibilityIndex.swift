import SwiftUI

struct CanvasVisibilityIndex: Equatable {
    var visibleRect: CGRect
    var preloadInset: CGFloat = 320

    init(transform: CanvasViewportTransform, preloadInset: CGFloat = 320) {
        self.visibleRect = transform.visibleCanvasRect
        self.preloadInset = preloadInset
    }

    var preloadRect: CGRect {
        visibleRect.insetBy(dx: -preloadInset, dy: -preloadInset)
    }

    func intersects(_ rect: CGRect) -> Bool {
        preloadRect.intersects(rect)
    }

    func contains(_ point: CGPoint) -> Bool {
        preloadRect.contains(point)
    }

    func isBlockVisible(_ block: CanvasBlock) -> Bool {
        let blockRect = CGRect(
            x: block.position.x - block.size.width / 2,
            y: block.position.y - block.size.height / 2,
            width: block.size.width,
            height: block.size.height
        )
        return intersects(blockRect)
    }
}
