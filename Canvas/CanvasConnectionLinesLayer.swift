// CosmoOS/Canvas/CanvasConnectionLinesLayer.swift
// Container that queries graph edges and renders all visible pulse lines on the canvas.
// Lives INSIDE the world layer, between cluster zones and blocks: lines paint above
// zone fills but under every card, and pan/zoom moves them through the world's
// compositor transform with zero per-frame line work.
// PERF: Throttled 15fps animation, cached endpoints, single-pass edge filtering

import SwiftUI

struct CanvasConnectionGeometrySignature: Equatable {
    let blockKeys: [BlockKey]

    init(blocks: [CanvasBlock]) {
        self.blockKeys = blocks.map(BlockKey.init)
    }

    struct BlockKey: Equatable {
        let entityUuid: String
        let positionX: Int
        let positionY: Int
        let width: Int
        let height: Int
        let scale: Int

        init(block: CanvasBlock) {
            self.entityUuid = block.entityUuid
            self.positionX = Self.quantize(block.position.x)
            self.positionY = Self.quantize(block.position.y)
            self.width = Self.quantize(block.size.width)
            self.height = Self.quantize(block.size.height)
            self.scale = Self.quantize(block.scale)
        }

        private static func quantize(_ value: CGFloat) -> Int {
            Int((value * 1000).rounded())
        }

        private static func quantize(_ value: Double) -> Int {
            Int((value * 1000).rounded())
        }
    }
}

/// Everything that can move a rendered endpoint without a live gesture:
/// block geometry (position saves, undo, sync) AND cluster state — a cluster
/// switching to list/board/grid consumes its members off the canvas, and a
/// cluster resize session previews new member positions per tick (the caller
/// folds that tick into `blockDataRevision`).
struct CanvasConnectionGeometryInvalidationKey: Equatable {
    let blockDataRevision: Int
    let clusterDataRevision: Int
}

/// Equatable snapshot of the live gestures that move blocks mid-drag —
/// single-block drags AND cluster-zone drags (whose member blocks ride the
/// zone's translation). Endpoint recomputation watches this so lines follow
/// both kinds of drag.
struct CanvasConnectionDragSignature: Equatable {
    let blockDragId: String?
    let blockTranslation: CGSize
    let clusterDragId: UUID?
    let clusterTranslation: CGSize

    init(
        blockDragId: String?,
        blockTranslation: CGSize,
        clusterDragId: UUID?,
        clusterTranslation: CGSize
    ) {
        self.blockDragId = blockDragId
        self.blockTranslation = blockTranslation
        self.clusterDragId = clusterDragId
        self.clusterTranslation = clusterTranslation
    }

    @MainActor
    init(interaction: CanvasInteractionState) {
        self.init(
            blockDragId: interaction.activeBlockDragId,
            blockTranslation: interaction.blockDragTranslation,
            clusterDragId: interaction.draggingClusterId,
            clusterTranslation: interaction.clusterDragTranslation
        )
    }
}

struct CanvasConnectionPulsePolicy {
    static func shouldRun(isActive: Bool, visibleEdgeCount: Int, isLiveGesture: Bool = false) -> Bool {
        isActive && visibleEdgeCount > 0 && !isLiveGesture
    }
}

/// Renders knowledge pulse lines between related blocks on the canvas.
/// Queries the graph for edges where both source and target are visible, then
/// draws animated bezier connections. Supports tap-to-select and delete.
///
/// NOTE: This layer renders in RAW CANVAS coordinates inside the world layer —
/// the world host applies pan/zoom as a compositor transform, so gesture frames
/// never re-render a line. Z-order comes from ZStack placement: above cluster
/// zone fills, below every block. Hit-testing composes the same way — a card
/// over a line wins the click, a line over a zone wins the click.
///
/// The caller must pass only blocks that actually render at their canvas
/// positions (blocks consumed by list/board/grid clusters excluded) — lines to
/// consumed blocks would point at empty canvas.
@MainActor
struct CanvasConnectionLinesLayer: View {

    // MARK: - Parameters

    let blocks: [CanvasBlock]
    let geometryInvalidationKey: CanvasConnectionGeometryInvalidationKey
    /// Read live (not passed as a value) so mid-drag endpoint updates keep
    /// flowing even though the parent body no longer re-evaluates per frame.
    let interaction: CanvasInteractionState
    /// Quantized world scale — used only to keep hit width and the delete
    /// pill screen-constant while the world zooms.
    let effectiveScale: CGFloat
    var isActive: Bool = true
    /// True while a pan/zoom gesture is live — the pulse animation pauses so
    /// gesture frames stay pure compositor work.
    var isLiveGesture: Bool = false

    private var dragSignature: CanvasConnectionDragSignature {
        CanvasConnectionDragSignature(interaction: interaction)
    }

    // MARK: - State

    @State private var edges: [GraphEdge] = []
    @State private var loadTask: Task<Void, Never>?
    @State private var animationPhase: Double = 0
    @State private var selectedEdgeKey: String?
    @State private var deleteTask: Task<Void, Never>?
    @State private var pulseTimer: Timer?

    // PERF: Cached derived data — recomputed only on data changes, not every frame
    @State private var cachedVisibleEdges: [GraphEdge] = []
    /// Endpoints in canvas space (shared by paths, hit shapes, delete pill)
    @State private var cachedCanvasEndpoints: [String: (start: CGPoint, end: CGPoint)] = [:]
    @State private var cachedCanvasPaths: [String: Path] = [:]

    // PERF: Throttle endpoint recomputation during drag to ~30fps with trailing edge
    @State private var dragEndpointThrottleTask: Task<Void, Never>?
    @State private var needsTrailingRecompute = false
    /// Escaping tasks bump this instead of calling recompute directly: a Task
    /// captures the view struct BY VALUE, so a direct recompute from one reads
    /// stale `blocks` — after a drag ended it would overwrite the committed
    /// endpoints with pre-drag positions and detach the lines until the next
    /// unrelated invalidation. The tick's onChange runs on the CURRENT value.
    @State private var deferredRecomputeTick = 0

    // MARK: - Constants

    private enum Constants {
        static let maxVisibleLines = 50
        static let minLineLength: CGFloat = 20
        /// Hit width in SCREEN pixels (divided by scale into canvas units)
        static let hitTestWidth: CGFloat = 24
        /// Gap between block edge and line endpoint so lines don't overlap blocks
        static let edgePaddingGap: CGFloat = 6
        /// Pulse animation frame rate — 15fps is more than enough for subtle energy flow
        static let pulseFrameRate: TimeInterval = 1.0 / 15.0
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dismiss underlay — while a connection is selected, any click not
            // claimed by a card above or a line hit shape deselects it.
            if selectedEdgeKey != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissConnectionSelection()
                    }
            }

            // Visual layer (no hit testing — decorative animated lines)
            CanvasConnectionVisualRenderer(
                edges: cachedVisibleEdges,
                cachedPaths: cachedCanvasPaths,
                animationPhase: animationPhase,
                selectedEdgeKey: selectedEdgeKey
            )
            .allowsHitTesting(false)

            // Hit shapes — one clear view per edge whose hit region is the
            // stroked path. Cards render above this whole layer, so a click
            // over a card can never steal a line underneath it.
            connectionHitShapes

            // Delete button for selected connection
            if let selectedKey = selectedEdgeKey,
               let edge = cachedVisibleEdges.first(where: { $0.deduplicationKey == selectedKey }),
               let endpoints = cachedCanvasEndpoints[selectedKey] {
                connectionDeleteButton(edge: edge, from: endpoints.start, to: endpoints.end)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: edges) { _, _ in
            recomputeVisibleEdgesAndEndpoints()
        }
        .onChange(of: geometryInvalidationKey) { _, _ in
            fetchEdges()
            recomputeVisibleEdgesAndEndpoints()
        }
        .onChange(of: dragSignature) { _, _ in
            throttledRecomputeEndpoints()
        }
        .onChange(of: deferredRecomputeTick) { _, _ in
            recomputeEndpoints()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.graphNodeUpdated)) { _ in
            fetchEdges()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.blockSelected)) { _ in
            // Deselect connection when a block is selected
            selectedEdgeKey = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .blurAllBlocks)) { _ in
            // Deselect connection when canvas background is tapped
            selectedEdgeKey = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.blockRenderedSizeChanged)) { _ in
            // Recompute endpoints when a block's actual rendered size changes (e.g. autoHeight expansion)
            recomputeEndpoints()
        }
        .onAppear {
            fetchEdges()
            updatePulseTimer()
            // Delayed recompute to catch rendered size cache updates
            // (GeometryReader reports actual sizes after first layout pass)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                deferredRecomputeTick &+= 1
            }
        }
        .onDisappear {
            loadTask?.cancel()
            deleteTask?.cancel()
            pulseTimer?.invalidate()
            pulseTimer = nil
        }
        .onChange(of: isActive) { _, active in
            updatePulseTimer()
        }
        .onChange(of: isLiveGesture) { _, _ in
            updatePulseTimer()
        }
    }

    // MARK: - Hit Shapes

    private var connectionHitShapes: some View {
        let hitWidth = Constants.hitTestWidth / max(effectiveScale, 0.001)
        return ForEach(cachedVisibleEdges, id: \.deduplicationKey) { edge in
            if let path = cachedCanvasPaths[edge.deduplicationKey] {
                Color.clear
                    .contentShape(
                        path.strokedPath(
                            StrokeStyle(lineWidth: hitWidth, lineCap: .round, lineJoin: .round)
                        )
                    )
                    .onTapGesture {
                        selectConnection(edge)
                    }
            }
        }
    }

    // MARK: - Selection

    private func selectConnection(_ edge: GraphEdge) {
        withAnimation(ProMotionSprings.snappy) {
            if selectedEdgeKey == edge.deduplicationKey {
                selectedEdgeKey = nil
            } else {
                selectedEdgeKey = edge.deduplicationKey
            }
        }
    }

    private func dismissConnectionSelection() {
        withAnimation(ProMotionSprings.snappy) {
            selectedEdgeKey = nil
        }
        // Also deselect any selected blocks.
        NotificationCenter.default.post(name: .blurAllBlocks, object: nil)
    }

    // MARK: - Pulse Timer

    /// 15fps timer for subtle energy flow animation — replaces 120fps TimelineView
    private func updatePulseTimer() {
        if CanvasConnectionPulsePolicy.shouldRun(
            isActive: isActive,
            visibleEdgeCount: cachedVisibleEdges.count,
            isLiveGesture: isLiveGesture
        ) {
            startPulseTimer()
        } else {
            pulseTimer?.invalidate()
            pulseTimer = nil
        }
    }

    private func startPulseTimer() {
        guard pulseTimer == nil else { return }
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: Constants.pulseFrameRate, repeats: true) { _ in
            Task { @MainActor in
                animationPhase = Date().timeIntervalSinceReferenceDate
            }
        }
    }

    // MARK: - Cached Computation (all in canvas space)

    /// Recompute both visible edges and their endpoints (on data changes)
    private func recomputeVisibleEdgesAndEndpoints() {
        let signpost = CanvasPerformanceInstrumentation.signposter.beginInterval("connection-recompute")
        let blocksByUUID = Dictionary(blocks.map { ($0.entityUuid, $0) }, uniquingKeysWith: { first, _ in first })
        let uuidSet = Set(blocks.map { $0.entityUuid })
        var seenPairs = Set<String>()
        var visibleResult: [GraphEdge] = []

        for edge in edges {
            guard uuidSet.contains(edge.sourceUUID) && uuidSet.contains(edge.targetUUID) else { continue }
            let sorted = [edge.sourceUUID, edge.targetUUID].sorted()
            let pairKey = "\(sorted[0]):\(sorted[1]):\(edge.edgeType)"
            guard seenPairs.insert(pairKey).inserted else { continue }
            visibleResult.append(edge)
            if visibleResult.count >= Constants.maxVisibleLines { break }
        }

        cachedVisibleEdges = visibleResult

        // Compute endpoints in canvas space for all visible edges
        var endpoints: [String: (start: CGPoint, end: CGPoint)] = [:]
        var paths: [String: Path] = [:]
        for edge in visibleResult {
            if let ep = computeCanvasEndpoints(for: edge, blocksByUUID: blocksByUUID) {
                endpoints[edge.deduplicationKey] = ep
                paths[edge.deduplicationKey] = canvasPath(from: ep.start, to: ep.end)
            }
        }
        cachedCanvasEndpoints = endpoints
        cachedCanvasPaths = paths
        updatePulseTimer()
        CanvasPerformanceInstrumentation.signposter.endInterval("connection-recompute", signpost)
    }

    /// Recompute only endpoints when block geometry changes (edges stay the same)
    private func recomputeEndpoints() {
        let signpost = CanvasPerformanceInstrumentation.signposter.beginInterval("connection-endpoints")
        let blocksByUUID = Dictionary(blocks.map { ($0.entityUuid, $0) }, uniquingKeysWith: { first, _ in first })
        var endpoints: [String: (start: CGPoint, end: CGPoint)] = [:]
        var paths: [String: Path] = [:]
        for edge in cachedVisibleEdges {
            if let ep = computeCanvasEndpoints(for: edge, blocksByUUID: blocksByUUID) {
                endpoints[edge.deduplicationKey] = ep
                paths[edge.deduplicationKey] = canvasPath(from: ep.start, to: ep.end)
            }
        }
        cachedCanvasEndpoints = endpoints
        cachedCanvasPaths = paths
        CanvasPerformanceInstrumentation.signposter.endInterval("connection-endpoints", signpost)
    }

    /// Throttled endpoint recomputation during drag — ~30fps (every 33ms).
    /// Uses leading + trailing edge pattern so lines always snap to the
    /// final position even when intermediate frames are skipped.
    private func throttledRecomputeEndpoints() {
        if dragEndpointThrottleTask == nil {
            // Fire immediately for first frame
            recomputeEndpoints()
            dragEndpointThrottleTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(33))
                dragEndpointThrottleTask = nil
                // Trailing edge rides the tick, NOT a direct recompute — this
                // task holds a stale copy of the view struct (see the tick's
                // doc comment for the drag-end detach bug that caused).
                if needsTrailingRecompute {
                    needsTrailingRecompute = false
                    deferredRecomputeTick &+= 1
                }
            }
        } else {
            // Mark that we need a trailing update when throttle expires
            needsTrailingRecompute = true
        }
    }

    /// Compute endpoints for a single edge in **canvas space** (pre-scale coordinates).
    /// These match the block positions inside the world layer.
    private func computeCanvasEndpoints(for edge: GraphEdge, blocksByUUID: [String: CanvasBlock]) -> (start: CGPoint, end: CGPoint)? {
        guard let fromBlock = blocksByUUID[edge.sourceUUID],
              let toBlock = blocksByUUID[edge.targetUUID] else { return nil }

        let fromPos = blockCanvasPosition(fromBlock)
        let toPos = blockCanvasPosition(toBlock)
        let distance = hypot(toPos.x - fromPos.x, toPos.y - fromPos.y)

        // Only a minimum: overlapping blocks get no line. Linked blocks far
        // apart always keep their line — a distance cap here silently
        // "disconnected" pairs the moment they were dragged apart.
        guard distance >= Constants.minLineLength else { return nil }

        let fromActualSize = BlockRenderedSizeCache.shared.renderedSize(for: fromBlock)
        let toActualSize = BlockRenderedSizeCache.shared.renderedSize(for: toBlock)
        let fromRendered = CGSize(width: fromActualSize.width * fromBlock.scale, height: fromActualSize.height * fromBlock.scale)
        let toRendered = CGSize(width: toActualSize.width * toBlock.scale, height: toActualSize.height * toBlock.scale)

        return edgeEndpoints(
            from: fromPos, fromSize: fromRendered,
            to: toPos, toSize: toRendered
        )
    }

    // MARK: - Delete Button

    @ViewBuilder
    private func connectionDeleteButton(edge: GraphEdge, from: CGPoint, to: CGPoint) -> some View {
        // Counter-scale so the pill stays screen-constant while the world zooms.
        let counterScale = 1 / max(effectiveScale, 0.001)
        let midpoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)

        Button {
            deleteConnection(edge: edge)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                Text("Remove Link")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(DS.red)
                    .shadow(color: .black.opacity(0.15), radius: 6)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(counterScale)
        // Transition must wrap the pill BEFORE .position — after it, the scale
        // anchors to the full-canvas frame and the button flies in from screen center.
        .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
        .position(x: midpoint.x, y: midpoint.y - 20 * counterScale)
    }

    // MARK: - Bezier Control Point

    /// Control point calculation — DragToConnectOverlay mirrors this so the
    /// drag preview curve matches the final rendered line exactly.
    private func bezierControl(from: CGPoint, to: CGPoint) -> CGPoint {
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return CGPoint(x: midX, y: midY) }

        let perpX = -dy / length
        let perpY = dx / length
        let offset = length * 0.15
        let direction: CGFloat = from.x + from.y < to.x + to.y ? 1 : -1

        return CGPoint(
            x: midX + perpX * offset * direction,
            y: midY + perpY * offset * direction
        )
    }

    // MARK: - Delete Connection

    private func deleteConnection(edge: GraphEdge) {
        let sourceUUID = edge.sourceUUID
        let targetUUID = edge.targetUUID

        // Register undo action before deleting
        CosmoUndoManager.shared.register(
            DeleteConnectionAction(sourceUUID: sourceUUID, targetUUID: targetUUID)
        )

        selectedEdgeKey = nil

        deleteTask = Task {
            do {
                // Remove link from source atom
                if let sourceAtom = try await AtomRepository.shared.fetch(uuid: sourceUUID) {
                    let updated = sourceAtom.removingLink(toUUID: targetUUID)
                    try await AtomRepository.shared.update(updated)
                    try await NodeGraphEngine.shared.handleAtomUpdated(updated, changedFields: ["links"])
                }

                // Remove link from target atom
                if let targetAtom = try await AtomRepository.shared.fetch(uuid: targetUUID) {
                    let updated = targetAtom.removingLink(toUUID: sourceUUID)
                    try await AtomRepository.shared.update(updated)
                    try await NodeGraphEngine.shared.handleAtomUpdated(updated, changedFields: ["links"])
                }

                // Re-fetch edges to update display
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.graphNodeUpdated,
                    object: nil,
                    userInfo: ["atomUUID": sourceUUID]
                )
            } catch {
                print("CanvasConnectionLinesLayer: delete failed: \(error)")
            }
        }
    }

    // MARK: - Position & Endpoint Helpers (Canvas Space)

    /// Block position in raw canvas coordinate space, including live drag
    /// offset — from a single-block drag OR a cluster-zone drag carrying the
    /// block — so lines follow blocks during both gestures.
    private func blockCanvasPosition(_ block: CanvasBlock) -> CGPoint {
        let dragOffset = interaction.dragOffset(forBlockId: block.id, entityUuid: block.entityUuid)
        return CGPoint(
            x: block.position.x + dragOffset.width,
            y: block.position.y + dragOffset.height
        )
    }

    private func canvasPath(from: CGPoint, to: CGPoint) -> Path {
        let control = bezierControl(from: from, to: to)
        return Path { path in
            path.move(to: from)
            path.addQuadCurve(to: to, control: control)
        }
    }

    /// Calculate line endpoints just outside block edges with a small gap
    /// so lines connect cleanly without overlapping blocks.
    private func edgeEndpoints(
        from: CGPoint, fromSize: CGSize,
        to: CGPoint, toSize: CGSize
    ) -> (start: CGPoint, end: CGPoint) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let angle = atan2(dy, dx)

        let fromHalfW = fromSize.width / 2
        let fromHalfH = fromSize.height / 2
        let toHalfW = toSize.width / 2
        let toHalfH = toSize.height / 2

        let startOffset = edgePadding(halfWidth: fromHalfW, halfHeight: fromHalfH, angle: angle) + Constants.edgePaddingGap
        let start = CGPoint(
            x: from.x + cos(angle) * startOffset,
            y: from.y + sin(angle) * startOffset
        )

        let endOffset = edgePadding(halfWidth: toHalfW, halfHeight: toHalfH, angle: angle + .pi) + Constants.edgePaddingGap
        let end = CGPoint(
            x: to.x + cos(angle + .pi) * endOffset,
            y: to.y + sin(angle + .pi) * endOffset
        )

        return (start, end)
    }

    /// Distance from center to edge of a rectangle at a given angle
    private func edgePadding(halfWidth: CGFloat, halfHeight: CGFloat, angle: CGFloat) -> CGFloat {
        let cosA = abs(cos(angle))
        let sinA = abs(sin(angle))
        guard cosA > 0.001 && sinA > 0.001 else {
            return cosA > sinA ? halfWidth : halfHeight
        }
        let byWidth = halfWidth / cosA
        let byHeight = halfHeight / sinA
        return min(byWidth, byHeight)
    }

    // MARK: - Data Loading

    private func fetchEdges() {
        loadTask?.cancel()
        let uuids = blocks.map { $0.entityUuid }
        loadTask = Task {
            guard uuids.count >= 2 else {
                edges = []
                return
            }
            do {
                let engine = GraphQueryEngine()
                let fetched = try await engine.getEdgesForBlocks(uuids: uuids)
                guard !Task.isCancelled else { return }
                edges = fetched
            } catch {
                print("CanvasConnectionLinesLayer: fetchEdges failed: \(error)")
            }
        }
    }
}

// MARK: - Visual Renderer

/// Style resolver — color, dash pattern, and relative weight per edge type.
/// Explicit/reference links feel solid (structural), semantic/conceptual feel
/// dashed (inferred). Contextual sits in between.
private struct EdgeStyle {
    let color: Color
    let dash: [CGFloat]
    /// Multiplier applied to base width (structural edges feel slightly heavier)
    let widthMultiplier: CGFloat

    static func forType(_ type: GraphEdgeType) -> EdgeStyle {
        switch type {
        case .explicit:
            return EdgeStyle(color: DS.entityResearch, dash: [], widthMultiplier: 1.0)
        case .reference:
            return EdgeStyle(color: DS.entityConnection, dash: [], widthMultiplier: 1.0)
        case .semantic:
            return EdgeStyle(color: DS.entityIdea, dash: [2, 4], widthMultiplier: 0.85)
        case .conceptual:
            return EdgeStyle(color: DS.entityNote, dash: [5, 4], widthMultiplier: 0.85)
        case .contextual:
            return EdgeStyle(color: DS.entityContent, dash: [8, 5], widthMultiplier: 0.9)
        case .transitive:
            return EdgeStyle(color: DS.textMuted, dash: [1, 5], widthMultiplier: 0.75)
        }
    }

    static func forRawType(_ raw: String) -> EdgeStyle {
        forType(GraphEdgeType(rawValue: raw) ?? .explicit)
    }
}

/// Renders connection lines from cached canvas-space paths. The world layer's
/// compositor transform carries them through pan/zoom — nothing here rebuilds.
private struct CanvasConnectionVisualRenderer: View {
    let edges: [GraphEdge]
    let cachedPaths: [String: Path]
    let animationPhase: Double
    let selectedEdgeKey: String?

    var body: some View {
        ZStack {
            ForEach(edges, id: \.deduplicationKey) { edge in
                if let path = cachedPaths[edge.deduplicationKey] {
                    ConnectionLineShape(
                        edge: edge,
                        path: path,
                        animationPhase: animationPhase,
                        isSelected: selectedEdgeKey == edge.deduplicationKey,
                        isDimmed: selectedEdgeKey != nil && selectedEdgeKey != edge.deduplicationKey
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Individual connection line rendered as SwiftUI Path strokes (glow + gradient pulse).
///
/// PERF: the glow is LAYERED SOFT STROKES, never `.blur` — a blur filter
/// forces an offscreen render pass per edge, re-run 15×/sec by the pulse
/// timer even while the canvas sits idle. Two wide low-opacity strokes read
/// as the same soft halo and stay pure display-list work.
private struct ConnectionLineShape: View {
    let edge: GraphEdge
    let path: Path
    let animationPhase: Double
    let isSelected: Bool
    let isDimmed: Bool

    var body: some View {
        let style = EdgeStyle.forRawType(edge.edgeType)
        let weight = edge.combinedWeight
        let baseWidth = (1.0 + CGFloat(weight)) * style.widthMultiplier
        let modulation = 0.1 * CGFloat(sin(animationPhase * 0.308))
        // Width is in canvas units — the world transform scales it with the
        // blocks, so lines and cards zoom together. Selected edges thicken
        // slightly to feel grasped.
        let selectionMul: CGFloat = isSelected ? 1.4 : 1.0
        let lineWidth = (baseWidth + modulation) * selectionMul

        // Opacity envelope: selected brightens, dimmed recedes, otherwise neutral.
        // The neutral/dimmed opacities were tuned for the light canvas, where a
        // faint line still reads as dark ink on paper. On the near-black dark
        // canvas the same opacity washes the typed color out to a dim grey, so
        // lift unselected lines there to read as clearly lighter ink. Selected
        // edges are already bright and stay put.
        let darkLift: Double = DS.palette.isDark ? 2.0 : 1.0
        let selectionOpacity: Double = {
            if isSelected { return 0.75 }
            if isDimmed   { return 0.08 * darkLift }
            return (0.15 + weight * 0.20) * darkLift
        }()

        let pulseProgress = CGFloat((animationPhase * 0.192).truncatingRemainder(dividingBy: 1.0))
        let stop1 = max(0, min(pulseProgress, 0.79))
        let stop2 = max(stop1 + 0.001, min(pulseProgress + 0.08, 0.89))
        let stop3 = max(stop2 + 0.001, min(pulseProgress + 0.16, 0.99))
        let lineColor = style.color
        let glowColor = isSelected ? DS.accentGlow : lineColor
        let glowOpacity = selectionOpacity * (isSelected ? 0.8 : 0.3)

        ZStack {
            // Glow halo — outer wash + inner core approximate the old
            // Gaussian falloff without any filter pass.
            path.stroke(
                glowColor.opacity(glowOpacity * 0.35),
                style: StrokeStyle(
                    lineWidth: lineWidth * (isSelected ? 4.6 : 3.4),
                    lineCap: .round,
                    lineJoin: .round,
                    dash: style.dash
                )
            )
            path.stroke(
                glowColor.opacity(glowOpacity * 0.55),
                style: StrokeStyle(
                    lineWidth: lineWidth * (isSelected ? 2.6 : 2.0),
                    lineCap: .round,
                    lineJoin: .round,
                    dash: style.dash
                )
            )

            // Main stroke — typed gradient pulse with per-edge dash pattern
            path.stroke(
                LinearGradient(
                    stops: [
                        .init(color: lineColor.opacity(selectionOpacity * 0.4), location: 0),
                        .init(color: lineColor.opacity(selectionOpacity), location: stop1),
                        .init(color: lineColor.opacity(selectionOpacity * 0.7), location: stop2),
                        .init(color: lineColor.opacity(selectionOpacity), location: stop3),
                        .init(color: lineColor.opacity(selectionOpacity * 0.4), location: 1),
                    ],
                    startPoint: UnitPoint(x: 0, y: 0),
                    endPoint: UnitPoint(x: 1, y: 1)
                ),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: style.dash
                )
            )
        }
        .animation(ProMotionSprings.gentle, value: isSelected)
        .animation(ProMotionSprings.gentle, value: isDimmed)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
