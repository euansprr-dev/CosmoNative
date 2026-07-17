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
        let raw = committedScale * gestureMagnification
        if raw >= minScale { return min(raw, maxScale) }
        // Below the zoom floor the canvas keeps shrinking with square-root
        // resistance instead of pinning — live feedback that the gesture is
        // carrying through (into the Constellation) rather than hitting a
        // wall. Commits still clamp to minScale, so this only shows during
        // a live gesture.
        guard minScale > 0, raw > 0 else { return minScale }
        let resisted = minScale * pow(raw / minScale, 0.45)
        return max(resisted, minScale * 0.6)
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

    /// The committed offset that centers `point` in the viewport at the current
    /// scale (no live gesture). Derivation: `canvasToScreen(p) == screenCenter`
    /// requires `p + contentOffset == screenCenter`.
    func centeringOffset(for point: CGPoint) -> CGSize {
        CGSize(
            width: screenCenter.x - point.x,
            height: screenCenter.y - point.y
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

enum CanvasZoomPolicy {
    private static let emptySpaceDoubleClickZoomFactor: CGFloat = 1.25

    static func emptySpaceDoubleClickScale(
        currentScale: CGFloat,
        minScale: CGFloat,
        maxScale: CGFloat
    ) -> CGFloat {
        min(max(currentScale * emptySpaceDoubleClickZoomFactor, minScale), maxScale)
    }
}

struct CanvasSessionViewportState: Equatable {
    var zoomLevel: CGFloat
    var panOffset: CGSize

    static let defaultOpening = CanvasSessionViewportState()

    init(
        zoomLevel: CGFloat = 1.0,
        panOffset: CGSize = .zero
    ) {
        self.zoomLevel = zoomLevel
        self.panOffset = panOffset
    }
}

enum CanvasSessionViewportPolicy {
    static func openingViewport(
        remembered: CanvasSessionViewportState?,
        persisted: CanvasSessionViewportState?
    ) -> CanvasSessionViewportState {
        remembered ?? .defaultOpening
    }
}

@MainActor
final class CanvasSessionViewportStore {
    static let shared = CanvasSessionViewportStore()

    private var viewports: [String: CanvasSessionViewportState] = [:]

    private init() {}

    func remember(_ viewport: CanvasSessionViewportState, for thinkspaceId: String?) {
        viewports[key(for: thinkspaceId)] = viewport
    }

    func rememberedViewport(for thinkspaceId: String?) -> CanvasSessionViewportState? {
        viewports[key(for: thinkspaceId)]
    }

    func openingViewport(
        for thinkspaceId: String?,
        persisted: CanvasSessionViewportState? = nil
    ) -> CanvasSessionViewportState {
        CanvasSessionViewportPolicy.openingViewport(
            remembered: rememberedViewport(for: thinkspaceId),
            persisted: persisted
        )
    }

    private func key(for thinkspaceId: String?) -> String {
        thinkspaceId ?? "__default__"
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
    let screenSpacing: CGFloat
    let screenDotSize: CGFloat
    let screenGridOrigin: CGPoint

    init(
        transform: CanvasViewportTransform,
        viewportSize: CGSize,
        tileSize: CGFloat = 40,
        baseDotSize: CGFloat = 2.5,
        minimumScreenDotSize: CGFloat = 1.0,
        preloadTileCount: CGFloat = 2
    ) {
        self.tileSize = tileSize
        let safeScale = max(transform.effectiveScale, 0.001)
        self.rawDotSize = max(baseDotSize, minimumScreenDotSize / safeScale)
        self.screenSpacing = max(tileSize * safeScale, 1)
        self.screenDotSize = max(baseDotSize * safeScale, minimumScreenDotSize)
        self.screenGridOrigin = transform.canvasToScreen(.zero)

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

/// Layout plan for rendering the dot grid as a tiled image instead of a
/// per-frame Path: one tiny cached tile, a frame phase-aligned to the canvas
/// origin, and a small correction scale. Panning becomes a pure compositor
/// translation; the tile itself only changes when zoom crosses a ~2% bucket.
struct CanvasGridTilePlan: Equatable {
    /// Spacing the tile is drawn at (quantized so the tile cache stays small).
    let tileSpacing: CGFloat
    let tileDotSize: CGFloat
    let tileMultiplier: Int
    /// actual screen spacing / tileSpacing — applied via scaleEffect
    /// (top-leading anchor) so dot positions stay exact despite quantization.
    let correctionScale: CGFloat
    /// Top-left placement offset (≤ 0 in both axes) phasing the tile pattern
    /// so dots land at `screenGridOrigin + n·spacing`, matching the old
    /// path-drawn grid exactly.
    let origin: CGPoint
    /// Frame size in unscaled (pre-correction) units.
    let frameSize: CGSize

    /// Multiplicative quantization bucket (~2%) — invisible after the
    /// correction scale, but bounds the tile cache across a whole session.
    private static let spacingQuantum: CGFloat = 1.02

    init?(
        screenSpacing: CGFloat,
        screenDotSize: CGFloat,
        screenGridOrigin: CGPoint,
        viewportSize: CGSize
    ) {
        guard screenSpacing.isFinite, screenSpacing >= 1,
              screenDotSize.isFinite, screenDotSize > 0,
              screenGridOrigin.x.isFinite, screenGridOrigin.y.isFinite,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return nil
        }

        let quantum = Self.spacingQuantum
        let bucket = (log(screenSpacing) / log(quantum)).rounded()
        let quantizedSpacing = pow(quantum, bucket)
        let correction = screenSpacing / quantizedSpacing

        self.tileSpacing = quantizedSpacing
        self.tileDotSize = screenDotSize / correction
        self.tileMultiplier = CanvasGridPatternCache.tileMultiplier(for: quantizedSpacing)
        self.correctionScale = correction

        // Dots sit at tile-local (i + 0.5)·spacing, so a dot lands on screen
        // at origin + (k + 0.5)·screenSpacing. Aligning with the canvas grid
        // (dots at screenGridOrigin + n·spacing) needs the frame's top-left
        // at (screenGridOrigin − spacing/2) mod screenTile, shifted ≤ 0.
        let screenTile = screenSpacing * CGFloat(tileMultiplier)
        func phase(_ target: CGFloat) -> CGFloat {
            var remainder = (target - screenSpacing / 2)
                .truncatingRemainder(dividingBy: screenTile)
            if remainder > 0 { remainder -= screenTile }
            return remainder
        }
        let originPoint = CGPoint(x: phase(screenGridOrigin.x), y: phase(screenGridOrigin.y))
        self.origin = originPoint

        // Cover from the (negative) origin across the viewport plus one tile
        // of slack; sized in unscaled units because .frame applies before
        // the correction scaleEffect.
        self.frameSize = CGSize(
            width: (viewportSize.width - originPoint.x + screenTile) / correction,
            height: (viewportSize.height - originPoint.y + screenTile) / correction
        )
    }

    /// Screen-space x position of the dot at tile index `index` along x.
    /// Exposed for tests: must equal `screenGridOrigin + n·screenSpacing`.
    func screenDotCenterX(index: Int) -> CGFloat {
        origin.x + (CGFloat(index) + 0.5) * tileSpacing * correctionScale
    }
}

// MARK: - 120Hz Viewport State

/// The single owner of pan/zoom values for the canvas.
///
/// Gesture ticks mutate this object instead of CanvasView `@State`/
/// `@GestureState` so the ~6,000-line CanvasView body never re-evaluates on
/// a pan frame. Only the tiny views that must move every frame read the live
/// fields (`CanvasWorldTransformHost`, `CanvasLiveTransformReader` wrappers
/// around the grid / connection-line / drawing layers). World content reads
/// `quantizedTransform`, which only changes when a live pan crosses a 640pt
/// bucket or a live zoom crosses a 0.125 bucket
/// (`CanvasViewportSnapshotPolicy`), and matches the raw transform exactly
/// whenever no gesture is live.
@MainActor
@Observable
final class CanvasViewportEngine {
    // Committed values — change on gesture commit or programmatic jumps.
    private(set) var committedOffset: CGSize = .zero
    private(set) var committedScale: CGFloat = 1.0
    private(set) var viewportSize: CGSize = .zero

    // Live gesture values — change every frame during a gesture.
    private(set) var gesturePanOffset: CGSize = .zero
    private(set) var spacePanOffset: CGSize = .zero
    private(set) var gestureMagnification: CGFloat = 1.0
    private(set) var clusterMagnification: CGFloat = 1.0

    // Derived, bucket-quantized — world content reads these instead of the
    // live fields so its invalidation rate is bucket crossings, not frames.
    private(set) var quantizedTransform: CanvasViewportTransform
    private(set) var isLiveGesture = false

    let minScale: CGFloat
    let maxScale: CGFloat

    init(minScale: CGFloat = 0.25, maxScale: CGFloat = 3.0) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.quantizedTransform = CanvasViewportTransform(
            viewportSize: .zero,
            committedOffset: .zero,
            committedScale: 1.0,
            minScale: minScale,
            maxScale: maxScale
        )
    }

    /// Full live transform. Handlers and gesture closures may read this
    /// freely (no observation happens outside body evaluation); view bodies
    /// must only read it if they intend to re-evaluate on every gesture frame.
    var transform: CanvasViewportTransform {
        CanvasViewportTransform(
            viewportSize: viewportSize,
            committedOffset: committedOffset,
            gesturePanOffset: CGSize(
                width: gesturePanOffset.width + spacePanOffset.width,
                height: gesturePanOffset.height + spacePanOffset.height
            ),
            committedScale: committedScale,
            gestureMagnification: gestureMagnification * clusterMagnification,
            minScale: minScale,
            maxScale: maxScale
        )
    }

    // MARK: Mutations — every write path refreshes the quantized mirror

    func setCommittedOffset(_ offset: CGSize) {
        guard committedOffset != offset else { return }
        committedOffset = offset
        refreshDerived()
    }

    func setCommittedScale(_ scale: CGFloat) {
        guard committedScale != scale else { return }
        committedScale = scale
        refreshDerived()
    }

    func setViewportSize(_ size: CGSize) {
        guard viewportSize != size else { return }
        viewportSize = size
        refreshDerived()
    }

    func setGesturePan(_ translation: CGSize) {
        guard gesturePanOffset != translation else { return }
        gesturePanOffset = translation
        refreshDerived()
    }

    func setSpacePan(_ translation: CGSize) {
        guard spacePanOffset != translation else { return }
        spacePanOffset = translation
        refreshDerived()
    }

    func setGestureMagnification(_ magnification: CGFloat) {
        guard gestureMagnification != magnification else { return }
        gestureMagnification = magnification
        refreshDerived()
    }

    func setClusterMagnification(_ magnification: CGFloat) {
        guard clusterMagnification != magnification else { return }
        clusterMagnification = magnification
        refreshDerived()
    }

    /// Clears every live gesture field. Replaces `@GestureState` auto-reset:
    /// called on gesture end and from the interruption paths (canvas
    /// deactivation, thinkspace switch, unmount) so a cancelled gesture can
    /// never leave the world stuck mid-pan.
    func resetLiveGesture() {
        guard gesturePanOffset != .zero ||
                spacePanOffset != .zero ||
                gestureMagnification != 1.0 ||
                clusterMagnification != 1.0 else { return }
        gesturePanOffset = .zero
        spacePanOffset = .zero
        gestureMagnification = 1.0
        clusterMagnification = 1.0
        refreshDerived()
    }

    private func refreshDerived() {
        let live = gesturePanOffset != .zero ||
            spacePanOffset != .zero ||
            abs(gestureMagnification - 1) > 0.0001 ||
            abs(clusterMagnification - 1) > 0.0001
        if isLiveGesture != live {
            isLiveGesture = live
        }
        let quantized = CanvasViewportSnapshotPolicy.snapshotTransform(
            for: transform,
            isLiveGesture: live
        )
        if quantizedTransform != quantized {
            quantizedTransform = quantized
        }
    }
}

/// 120Hz interaction state — block and cluster drags.
///
/// The id/membership fields change only at drag start/end while the
/// translation fields change every frame, and they are separate stored
/// properties so @Observable tracking stays surgical: a block host that
/// isn't part of the active drag reads only the stable fields and is never
/// invalidated by a drag frame; the dragged block (or the dragged cluster's
/// members) read the translation and move.
@MainActor
@Observable
final class CanvasInteractionState {
    private(set) var activeBlockDragId: String?
    private(set) var blockDragTranslation: CGSize = .zero

    private(set) var draggingClusterId: UUID?
    private(set) var clusterDragTranslation: CGSize = .zero
    private(set) var draggingClusterMemberUUIDs: Set<String> = []

    /// Per-frame position of the cluster drop-preview ghost. Lives here (not
    /// on CanvasView @State) so a drag over a cluster invalidates only the
    /// preview host, never CanvasView.body.
    private(set) var dropPreviewPosition: CGPoint = .zero

    /// Snapshot in the legacy struct shape for consumers that keep one
    /// (connection lines' throttled endpoint recompute).
    var blockDrag: ActiveCanvasDragState<String> {
        var state = ActiveCanvasDragState<String>()
        if let id = activeBlockDragId {
            state.begin(id: id, translation: blockDragTranslation)
        }
        return state
    }

    func updateBlockDrag(id: String, translation: CGSize) {
        if activeBlockDragId != id { activeBlockDragId = id }
        if blockDragTranslation != translation { blockDragTranslation = translation }
    }

    func clearBlockDrag() {
        if activeBlockDragId != nil { activeBlockDragId = nil }
        if blockDragTranslation != .zero { blockDragTranslation = .zero }
    }

    func updateDropPreviewPosition(_ position: CGPoint) {
        if dropPreviewPosition != position { dropPreviewPosition = position }
    }

    func beginClusterDrag(id: UUID, memberUUIDs: Set<String>) {
        if draggingClusterId != id { draggingClusterId = id }
        if draggingClusterMemberUUIDs != memberUUIDs { draggingClusterMemberUUIDs = memberUUIDs }
    }

    func updateClusterDrag(translation: CGSize) {
        if clusterDragTranslation != translation { clusterDragTranslation = translation }
    }

    func clearClusterDrag() {
        if draggingClusterId != nil { draggingClusterId = nil }
        if clusterDragTranslation != .zero { clusterDragTranslation = .zero }
        if !draggingClusterMemberUUIDs.isEmpty { draggingClusterMemberUUIDs = [] }
    }

    /// Per-frame offset for a block host. Reads the per-frame translation
    /// fields only when this block is actually part of the active drag.
    func dragOffset(forBlockId id: String, entityUuid: String) -> CGSize {
        if draggingClusterId != nil, draggingClusterMemberUUIDs.contains(entityUuid) {
            return clusterDragTranslation
        }
        if activeBlockDragId == id {
            return blockDragTranslation
        }
        return .zero
    }

    /// Per-frame offset for a cluster zone; only the dragged cluster's host
    /// tracks the translation.
    func clusterDragOffset(for id: UUID) -> CGSize {
        draggingClusterId == id ? clusterDragTranslation : .zero
    }
}

/// The only view that applies the live world transform. Gesture frames
/// invalidate just this body — a compositor transform update on already-built
/// `content` — never the canvas body that constructed the content.
struct CanvasWorldTransformHost<Content: View>: View {
    let viewportState: CanvasViewportEngine
    @ViewBuilder var content: Content

    var body: some View {
        let compositor = CanvasCompositorTransform(viewportTransform: viewportState.transform)
        content
            .offset(
                x: compositor.contentOffset.width,
                y: compositor.contentOffset.height
            )
            .scaleEffect(compositor.effectiveScale, anchor: compositor.anchor)
    }
}

/// Hands the live transform to screen-space layers (grid, connection lines,
/// drawings, zoom chrome) without making the enclosing body a dependency of
/// every gesture frame: only this reader's body re-evaluates per tick, and it
/// re-invokes the stored content closure with a fresh transform.
struct CanvasLiveTransformReader<Content: View>: View {
    let viewportState: CanvasViewportEngine
    @ViewBuilder var content: (CanvasViewportTransform) -> Content

    var body: some View {
        content(viewportState.transform)
    }
}

enum CanvasViewportSnapshotPolicy {
    private static let livePanBucketSize: CGFloat = 640
    private static let liveScaleBucketSize: CGFloat = 0.125
    private static let idleMinimumPreloadInset: CGFloat = 640
    private static let liveMinimumPreloadInset: CGFloat = 1_500

    static func snapshotTransform(
        for transform: CanvasViewportTransform,
        isLiveGesture: Bool
    ) -> CanvasViewportTransform {
        guard isLiveGesture else { return transform }

        return CanvasViewportTransform(
            viewportSize: transform.viewportSize,
            committedOffset: quantizedOffset(transform.contentOffset, bucketSize: livePanBucketSize),
            gesturePanOffset: .zero,
            committedScale: quantizedScale(
                transform.effectiveScale,
                bucketSize: liveScaleBucketSize,
                minScale: transform.minScale,
                maxScale: transform.maxScale
            ),
            gestureMagnification: 1,
            minScale: transform.minScale,
            maxScale: transform.maxScale
        )
    }

    static func preloadInset(
        viewportSize: CGSize,
        isLiveGesture: Bool,
        blockCount: Int
    ) -> CGFloat {
        let maxViewportDimension = max(viewportSize.width, viewportSize.height)
        let fallbackInset = isLiveGesture ? liveMinimumPreloadInset : idleMinimumPreloadInset
        guard maxViewportDimension.isFinite, maxViewportDimension > 0 else {
            return fallbackInset
        }

        let requestedInset = isLiveGesture
            ? max(maxViewportDimension * 1.5, liveMinimumPreloadInset)
            : max(maxViewportDimension * 0.75, idleMinimumPreloadInset)

        return min(requestedInset, preloadCap(forBlockCount: blockCount))
    }

    private static func preloadCap(forBlockCount blockCount: Int) -> CGFloat {
        switch blockCount {
        case ..<200:
            return 3_200
        case ..<600:
            return 2_400
        default:
            return 1_600
        }
    }

    private static func quantizedOffset(_ offset: CGSize, bucketSize: CGFloat) -> CGSize {
        CGSize(
            width: quantized(offset.width, bucketSize: bucketSize),
            height: quantized(offset.height, bucketSize: bucketSize)
        )
    }

    private static func quantizedScale(
        _ scale: CGFloat,
        bucketSize: CGFloat,
        minScale: CGFloat,
        maxScale: CGFloat
    ) -> CGFloat {
        min(max(quantized(scale, bucketSize: bucketSize), minScale), maxScale)
    }

    private static func quantized(_ value: CGFloat, bucketSize: CGFloat) -> CGFloat {
        guard bucketSize > 0 else { return value }
        return (value / bucketSize).rounded(.toNearestOrAwayFromZero) * bucketSize
    }
}
