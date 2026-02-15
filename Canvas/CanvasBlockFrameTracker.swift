// CosmoOS/Canvas/CanvasBlockFrameTracker.swift
// Shared frame tracker for hit-testing blocks in screen space

import SwiftUI

@MainActor
final class CanvasBlockFrameTracker: ObservableObject {
    @Published var blockFrames: [String: CGRect] = [:]  // blockId -> screen-space rect
    var trackedBlocks: [CanvasBlock] = []  // Updated alongside frames

    /// Hit-test a screen point against tracked block frames.
    /// Returns the block ID of the topmost block at that point, if any.
    func hitTest(at point: CGPoint) -> String? {
        // Check blocks in reverse zIndex order (highest first)
        let sortedBlockIds = blockFrames.keys.sorted { id1, id2 in
            let z1 = trackedBlocks.first(where: { $0.id == id1 })?.zIndex ?? 0
            let z2 = trackedBlocks.first(where: { $0.id == id2 })?.zIndex ?? 0
            return z1 > z2
        }

        for blockId in sortedBlockIds {
            if let frame = blockFrames[blockId], frame.contains(point) {
                return blockId
            }
        }
        return nil
    }

    /// Update all block frames based on current canvas state.
    func updateFrames(
        blocks: [CanvasBlock],
        canvasOffset: CGSize,
        scaledPanOffset: CGSize,
        effectiveScale: CGFloat,
        screenCenter: CGPoint
    ) {
        self.trackedBlocks = blocks
        var newFrames: [String: CGRect] = [:]
        for block in blocks {
            // Calculate screen position (same math as CanvasView.blockView position)
            let canvasX = block.position.x + canvasOffset.width + scaledPanOffset.width
            let canvasY = block.position.y + canvasOffset.height + scaledPanOffset.height

            // Apply scale transform around screen center
            let scaledX = screenCenter.x + (canvasX - screenCenter.x) * effectiveScale
            let scaledY = screenCenter.y + (canvasY - screenCenter.y) * effectiveScale

            // Block size (scaled)
            let scaledWidth = block.size.width * effectiveScale * block.scale
            let scaledHeight = block.size.height * effectiveScale * block.scale

            // Frame centered on position
            newFrames[block.id] = CGRect(
                x: scaledX - scaledWidth / 2,
                y: scaledY - scaledHeight / 2,
                width: scaledWidth,
                height: scaledHeight
            )
        }
        blockFrames = newFrames
    }
}
