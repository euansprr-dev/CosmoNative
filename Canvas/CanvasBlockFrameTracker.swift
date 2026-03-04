// CosmoOS/Canvas/CanvasBlockFrameTracker.swift
// Shared frame tracker for hit-testing blocks in screen space

import SwiftUI

// MARK: - Block Rendered Size Cache

/// Stores actual rendered sizes reported by CosmoBlockWrapper via GeometryReader.
/// Used by CanvasConnectionLinesLayer to compute accurate line endpoints
/// for autoHeight blocks whose rendered size exceeds their model `block.size`.
@MainActor
final class BlockRenderedSizeCache {
    static let shared = BlockRenderedSizeCache()

    private(set) var sizes: [String: CGSize] = [:]

    /// Update the rendered size for a block. Posts notification if changed significantly.
    func update(blockId: String, size: CGSize) {
        let old = sizes[blockId]
        let threshold: CGFloat = 2
        if old == nil
            || abs((old?.width ?? 0) - size.width) > threshold
            || abs((old?.height ?? 0) - size.height) > threshold {
            sizes[blockId] = size
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.blockRenderedSizeChanged,
                object: nil
            )
        }
    }

    /// Look up actual rendered size, falling back to model size
    func renderedSize(for block: CanvasBlock) -> CGSize {
        sizes[block.id] ?? block.size
    }
}

// MARK: - Block Frame Tracker

@MainActor
final class CanvasBlockFrameTracker: ObservableObject {
    @Published var blockFrames: [String: CGRect] = [:]  // blockId -> screen-space rect
    var trackedBlocks: [CanvasBlock] = []  // Updated alongside frames
    // PERF: Pre-built zIndex map for O(1) lookup in hitTest (was O(n) per comparison)
    private var zIndexMap: [String: Int] = [:]

    /// Hit-test a screen point against tracked block frames.
    /// Returns the block ID of the topmost block at that point, if any.
    func hitTest(at point: CGPoint) -> String? {
        // PERF: Sort using pre-built map — O(n log n) instead of O(n^2 log n)
        let sortedBlockIds = blockFrames.keys.sorted { id1, id2 in
            zIndexMap[id1, default: 0] > zIndexMap[id2, default: 0]
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
        // PERF: Build zIndex lookup map for O(1) access in hitTest
        var newZIndex: [String: Int] = [:]
        for block in blocks {
            newZIndex[block.id] = block.zIndex
        }
        self.zIndexMap = newZIndex

        var newFrames: [String: CGRect] = [:]
        for block in blocks {
            // Calculate screen position (same math as CanvasView.blockView position)
            let canvasX = block.position.x + canvasOffset.width + scaledPanOffset.width
            let canvasY = block.position.y + canvasOffset.height + scaledPanOffset.height

            // Apply scale transform around screen center
            let scaledX = screenCenter.x + (canvasX - screenCenter.x) * effectiveScale
            let scaledY = screenCenter.y + (canvasY - screenCenter.y) * effectiveScale

            // Block size (scaled) — use actual rendered size for autoHeight blocks
            let actualSize = BlockRenderedSizeCache.shared.renderedSize(for: block)
            let scaledWidth = actualSize.width * effectiveScale * block.scale
            let scaledHeight = actualSize.height * effectiveScale * block.scale

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
