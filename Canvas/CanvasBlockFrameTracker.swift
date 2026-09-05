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
    private var changeNotificationScheduled = false

    /// Update the rendered size for a block. Posts notification if changed significantly.
    func update(blockId: String, size: CGSize) {
        let old = sizes[blockId]
        let threshold: CGFloat = 2
        if old == nil
            || abs((old?.width ?? 0) - size.width) > threshold
            || abs((old?.height ?? 0) - size.height) > threshold {
            sizes[blockId] = size
            scheduleChangeNotification()
        }
    }

    /// Many blocks report new sizes within the same layout pass (e.g. while
    /// resizing or after a thinkspace switch); observers only need one wake-up
    /// per pass, so coalesce the posts instead of firing once per block.
    private func scheduleChangeNotification() {
        guard !changeNotificationScheduled else { return }
        changeNotificationScheduled = true
        Task { @MainActor in
            await Task.yield()
            changeNotificationScheduled = false
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

// MARK: - Right-Click Hit Result

/// What the right-click monitor found under the cursor. The monitor owns the
/// response: block menu, radial creation menu, or handing the event back to
/// SwiftUI (expanded cluster UI renders its own interactive content).
enum CanvasRightClickHit: Equatable {
    case block(String)
    /// Inside a cluster whose members render as list/board/grid UI — the
    /// blocks' canvas positions are meaningless there, so neither a block
    /// menu nor the radial menu is correct. The event passes through.
    case expandedCluster
    case empty
}

// MARK: - Block Frame Tracker

/// INVARIANT: hit-testing must agree with what the canvas actually renders.
/// Geometry is therefore stored in CANVAS space for the same block set the
/// render snapshot draws (blocks consumed by non-canvas-mode clusters are
/// excluded), and the click point is converted with the LIVE viewport
/// transform at click time — pan/zoom can never leave the tracker stale.
@MainActor
final class CanvasBlockFrameTracker: ObservableObject {
    /// Screen-space rects for overlay consumers (provocation markers, lasso
    /// selection). Derived from the canvas-space rects + the transform passed
    /// to `update`/`refreshScreenFrames`; right-click hit-testing does NOT
    /// read these.
    @Published var blockFrames: [String: CGRect] = [:]
    /// The renderable block set (cluster-consumed blocks excluded), matching
    /// `CanvasRenderSnapshot`'s notion of what is visible on the canvas.
    private(set) var trackedBlocks: [CanvasBlock] = []

    // Canvas-space geometry — transform-independent, so it only changes when
    // block/cluster data changes, never on pan/zoom.
    private var blockCanvasRects: [String: CGRect] = [:]
    private var expandedClusterCanvasRects: [CGRect] = []
    /// Block ids sorted topmost-first (zIndex desc, id desc — the exact
    /// reverse of the render pipeline's draw order).
    private var hitTestOrder: [String] = []

    /// Reads the owning canvas's live viewport transform at click time.
    /// Set by the hosting CanvasView; nil until a canvas registers (or after
    /// its viewport engine is gone) — hit-testing then declines the event.
    var liveTransformProvider: (@MainActor () -> CanvasViewportTransform?)?

    /// False while the thinkspace shows a non-canvas surface (library mode).
    /// The canvas world is only a backdrop there — its blocks must not
    /// capture right-clicks that belong to the overlay UI.
    var isCanvasSurfaceActive = true

    /// Chrome floating over the canvas (the tray) in window-flipped screen
    /// space. A right-click inside one belongs to that chrome's own SwiftUI
    /// context menu — never to the radial or block menus underneath.
    var chromeExclusionRects: [String: CGRect] = [:]

    /// Hit-test a right-click. Returns nil when the canvas surface isn't the
    /// active interaction layer — the caller must pass the event through.
    func rightClickHitTest(at screenPoint: CGPoint) -> CanvasRightClickHit? {
        guard isCanvasSurfaceActive else { return nil }
        if chromeExclusionRects.values.contains(where: { $0.contains(screenPoint) }) { return nil }
        guard let transform = liveTransformProvider?() ?? nil else { return nil }

        let canvasPoint = transform.screenToCanvas(screenPoint)
        for blockId in hitTestOrder {
            if let rect = blockCanvasRects[blockId], rect.contains(canvasPoint) {
                return .block(blockId)
            }
        }
        if expandedClusterCanvasRects.contains(where: { $0.contains(canvasPoint) }) {
            return .expandedCluster
        }
        return .empty
    }

    /// Rebuild tracked geometry from current canvas data. Blocks belonging to
    /// clusters in list/board/grid view modes render inside the cluster's own
    /// UI, not at their canvas positions, so they are excluded — mirroring
    /// `CanvasRenderDataSnapshot.clusterConsumedBlockUUIDs`.
    func update(
        blocks: [CanvasBlock],
        userClusters: [CanvasCluster],
        transform: CanvasViewportTransform
    ) {
        var consumedUUIDs = Set<String>()
        var expandedRects: [CGRect] = []
        for cluster in userClusters where cluster.viewMode != .canvas {
            consumedUUIDs.formUnion(cluster.blockUUIDs)
            expandedRects.append(cluster.boundingRect)
        }

        let renderable = blocks.filter { !consumedUUIDs.contains($0.entityUuid) }
        trackedBlocks = renderable
        expandedClusterCanvasRects = expandedRects

        var canvasRects: [String: CGRect] = [:]
        canvasRects.reserveCapacity(renderable.count)
        for block in renderable {
            // Blocks are positioned by center; autoHeight blocks can render
            // taller than their model size, so use the reported size.
            let actualSize = BlockRenderedSizeCache.shared.renderedSize(for: block)
            let width = actualSize.width * block.scale
            let height = actualSize.height * block.scale
            canvasRects[block.id] = CGRect(
                x: block.position.x - width / 2,
                y: block.position.y - height / 2,
                width: width,
                height: height
            )
        }
        blockCanvasRects = canvasRects

        // Topmost-first: reverse of the render pipeline's (zIndex asc, id asc)
        // draw order so ties resolve to the block drawn on top.
        hitTestOrder = renderable
            .sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex { return lhs.id > rhs.id }
                return lhs.zIndex > rhs.zIndex
            }
            .map(\.id)

        refreshScreenFrames(transform: transform)
    }

    /// Recompute the screen-space `blockFrames` from stored canvas rects.
    /// Overlay consumers that need up-to-the-frame screen geometry (lasso
    /// completion) call this with the transform they were handed.
    func refreshScreenFrames(transform: CanvasViewportTransform) {
        var newFrames: [String: CGRect] = [:]
        newFrames.reserveCapacity(blockCanvasRects.count)
        for (blockId, canvasRect) in blockCanvasRects {
            newFrames[blockId] = transform.canvasRectToScreen(canvasRect)
        }
        blockFrames = newFrames
    }
}
