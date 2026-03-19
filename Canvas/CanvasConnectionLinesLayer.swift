// CosmoOS/Canvas/CanvasConnectionLinesLayer.swift
// Container that queries graph edges and renders all visible pulse lines on the canvas
// Lives OUTSIDE the scaled ZStack — renders in screen coordinates to prevent clipping
// PERF: Throttled 15fps animation, cached endpoints, single-pass edge filtering

import SwiftUI

/// Renders knowledge pulse lines between related blocks on the canvas.
/// Queries the graph for edges where both source and target are visible, then
/// draws animated bezier connections. Supports tap-to-select and delete.
///
/// NOTE: This layer renders OUTSIDE the scaled ZStack to prevent clipping at non-100% zoom.
/// Paths are computed in canvas space then transformed to screen space via CGAffineTransform.
@MainActor
struct CanvasConnectionLinesLayer: View {

    // MARK: - Parameters

    let blocks: [CanvasBlock]
    let transform: CanvasViewportTransform
    let activeBlockDrag: ActiveCanvasDragState<String>
    var isActive: Bool = true

    // MARK: - State

    @State private var edges: [GraphEdge] = []
    @State private var loadTask: Task<Void, Never>?
    @State private var animationPhase: Double = 0
    @State private var selectedEdgeKey: String?
    @State private var deleteTask: Task<Void, Never>?
    @State private var pulseTimer: Timer?

    // PERF: Cached derived data — recomputed only on data changes, not every frame
    @State private var cachedVisibleEdges: [GraphEdge] = []
    /// Endpoints in canvas space (used for hit testing after transform)
    @State private var cachedCanvasEndpoints: [String: (start: CGPoint, end: CGPoint)] = [:]
    /// Paths in canvas space (transformed to screen space at render time)
    @State private var cachedCanvasPaths: [String: Path] = [:]

    // PERF: Throttle endpoint recomputation during drag to ~30fps with trailing edge
    @State private var dragEndpointThrottleTask: Task<Void, Never>?
    @State private var needsTrailingRecompute = false

    // MARK: - Constants

    private enum Constants {
        static let maxVisibleLines = 50
        static let minLineLength: CGFloat = 20
        static let maxLineLength: CGFloat = 2000
        static let hitTestWidth: CGFloat = 24
        /// Gap between block edge and line endpoint so lines don't overlap blocks
        static let edgePaddingGap: CGFloat = 6
        /// Pulse animation frame rate — 15fps is more than enough for subtle energy flow
        static let pulseFrameRate: TimeInterval = 1.0 / 15.0
    }

    private var blockGeometrySignature: [String] {
        blocks.map {
            [
                $0.entityUuid,
                "\(Int(($0.position.x * 1000).rounded()))",
                "\(Int(($0.position.y * 1000).rounded()))",
                "\(Int(($0.size.width * 1000).rounded()))",
                "\(Int(($0.size.height * 1000).rounded()))",
                "\(Int(($0.scale * 1000).rounded()))",
            ].joined(separator: "|")
        }
    }

    /// Affine transform from inner-ZStack space → screen space.
    /// Matches the `.scaleEffect(effectiveScale, anchor: .center)` on the blocks container.
    /// Points in the inner ZStack are `block.position + contentOffset + dragOffset`.
    /// The scaleEffect scales around `screenCenter = viewportSize / 2`.
    ///
    /// NOTE: Does NOT use `canvasToScreenAffineTransform()` which has a bug
    /// (wrong operation order produces incorrect positions at non-100% zoom).
    private var screenTransform: CGAffineTransform {
        let s = transform.effectiveScale
        let cx = transform.screenCenter.x
        let cy = transform.screenCenter.y
        // Scale around (cx, cy): x' = s*x + cx*(1-s), y' = s*y + cy*(1-s)
        return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: cx * (1 - s), ty: cy * (1 - s))
    }

    // MARK: - Body

    var body: some View {
        let xform = screenTransform
        // Pre-compute screen-space paths and endpoints for rendering + hit testing
        let screenPaths = cachedCanvasPaths.mapValues { $0.applying(xform) }
        let screenEndpoints = cachedCanvasEndpoints.mapValues { ep in
            (
                start: ep.start.applying(xform),
                end: ep.end.applying(xform)
            )
        }

        ZStack {
            // Visual layer (no hit testing — decorative animated lines)
            CanvasConnectionVisualRenderer(
                edges: cachedVisibleEdges,
                cachedPaths: screenPaths,
                animationPhase: animationPhase,
                effectiveScale: transform.effectiveScale
            )
            .allowsHitTesting(false)

            // Hit-test layer — invisible wide paths that respond to taps
            // PERF: Uses same endpoints as visual layer
            ForEach(cachedVisibleEdges, id: \.deduplicationKey) { edge in
                if let endpoints = screenEndpoints[edge.deduplicationKey] {
                    connectionHitArea(edge: edge, from: endpoints.start, to: endpoints.end)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Dismiss overlay — when a connection is selected, tapping anywhere
            // else on the canvas should deselect it (placed behind delete button)
            if selectedEdgeKey != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(ProMotionSprings.snappy) {
                            selectedEdgeKey = nil
                        }
                        // Also deselect any selected blocks
                        NotificationCenter.default.post(name: .blurAllBlocks, object: nil)
                    }
            }

            // Delete button for selected connection
            if let selectedKey = selectedEdgeKey,
               let edge = cachedVisibleEdges.first(where: { $0.deduplicationKey == selectedKey }),
               let endpoints = screenEndpoints[edge.deduplicationKey] {
                connectionDeleteButton(edge: edge, from: endpoints.start, to: endpoints.end)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: edges) { _, _ in
            recomputeVisibleEdgesAndEndpoints()
        }
        .onChange(of: blocks.map(\.entityUuid)) { _, _ in
            fetchEdges()
            recomputeVisibleEdgesAndEndpoints()
        }
        .onChange(of: transform.contentOffset) { _, _ in
            recomputeEndpoints()
        }
        .onChange(of: transform.effectiveScale) { _, _ in
            recomputeEndpoints()
        }
        .onChange(of: blockGeometrySignature) { _, _ in
            recomputeEndpoints()
        }
        .onChange(of: activeBlockDrag) { _, _ in
            throttledRecomputeEndpoints()
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
            if isActive { startPulseTimer() }
            // Delayed recompute to catch rendered size cache updates
            // (GeometryReader reports actual sizes after first layout pass)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                recomputeEndpoints()
            }
        }
        .onDisappear {
            loadTask?.cancel()
            deleteTask?.cancel()
            pulseTimer?.invalidate()
            pulseTimer = nil
        }
        .onChange(of: isActive) { _, active in
            if active {
                startPulseTimer()
            } else {
                pulseTimer?.invalidate()
                pulseTimer = nil
            }
        }
    }

    // MARK: - Pulse Timer

    /// 15fps timer for subtle energy flow animation — replaces 120fps TimelineView
    private func startPulseTimer() {
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
                // Fire trailing edge if any updates were skipped
                if needsTrailingRecompute {
                    needsTrailingRecompute = false
                    recomputeEndpoints()
                }
            }
        } else {
            // Mark that we need a trailing update when throttle expires
            needsTrailingRecompute = true
        }
    }

    /// Compute endpoints for a single edge in **canvas space** (pre-scale coordinates).
    /// These match the block positions inside the scaled ZStack.
    private func computeCanvasEndpoints(for edge: GraphEdge, blocksByUUID: [String: CanvasBlock]) -> (start: CGPoint, end: CGPoint)? {
        guard let fromBlock = blocksByUUID[edge.sourceUUID],
              let toBlock = blocksByUUID[edge.targetUUID] else { return nil }

        let fromPos = blockCanvasPosition(fromBlock)
        let toPos = blockCanvasPosition(toBlock)
        let distance = hypot(toPos.x - fromPos.x, toPos.y - fromPos.y)

        guard distance >= Constants.minLineLength && distance <= Constants.maxLineLength else { return nil }

        let fromActualSize = BlockRenderedSizeCache.shared.renderedSize(for: fromBlock)
        let toActualSize = BlockRenderedSizeCache.shared.renderedSize(for: toBlock)
        let fromRendered = CGSize(width: fromActualSize.width * fromBlock.scale, height: fromActualSize.height * fromBlock.scale)
        let toRendered = CGSize(width: toActualSize.width * toBlock.scale, height: toActualSize.height * toBlock.scale)

        return edgeEndpoints(
            from: fromPos, fromSize: fromRendered,
            to: toPos, toSize: toRendered
        )
    }

    // MARK: - Hit Area

    /// Invisible wide bezier path that accepts taps to select a connection
    @ViewBuilder
    private func connectionHitArea(edge: GraphEdge, from: CGPoint, to: CGPoint) -> some View {
        let control = bezierControl(from: from, to: to)
        let hitPath = Path { path in
            path.move(to: from)
            path.addQuadCurve(to: to, control: control)
        }.strokedPath(StrokeStyle(lineWidth: Constants.hitTestWidth, lineCap: .round))

        hitPath
            .fill(Color.white.opacity(0.001))
            .onTapGesture {
                withAnimation(ProMotionSprings.snappy) {
                    if selectedEdgeKey == edge.deduplicationKey {
                        selectedEdgeKey = nil
                    } else {
                        selectedEdgeKey = edge.deduplicationKey
                    }
                }
            }
    }

    // MARK: - Delete Button

    @ViewBuilder
    private func connectionDeleteButton(edge: GraphEdge, from: CGPoint, to: CGPoint) -> some View {
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
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(DS.red)
                    .shadow(color: .black.opacity(0.15), radius: 6)
            )
        }
        .buttonStyle(.plain)
        .position(x: midpoint.x, y: midpoint.y - 20)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Bezier Control Point

    /// Shared control point calculation matching KnowledgePulseLineView
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

    /// Block position in canvas coordinate space (matching the positions inside the scaled ZStack),
    /// including live drag offset so lines follow blocks during drag
    private func blockCanvasPosition(_ block: CanvasBlock) -> CGPoint {
        let dragOffset = activeBlockDrag.translation(for: block.id)
        return CGPoint(
            x: block.position.x + transform.contentOffset.width + dragOffset.width,
            y: block.position.y + transform.contentOffset.height + dragOffset.height
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

/// Renders connection lines using SwiftUI Path shapes in screen coordinates.
/// Paths are pre-transformed from canvas space via CGAffineTransform.
private struct CanvasConnectionVisualRenderer: View {
    let edges: [GraphEdge]
    let cachedPaths: [String: Path]
    let animationPhase: Double
    let effectiveScale: CGFloat

    var body: some View {
        ZStack {
            ForEach(edges, id: \.deduplicationKey) { edge in
                if let path = cachedPaths[edge.deduplicationKey] {
                    ConnectionLineShape(
                        edge: edge,
                        path: path,
                        animationPhase: animationPhase,
                        effectiveScale: effectiveScale
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Individual connection line rendered as SwiftUI Path strokes (glow + gradient pulse).
private struct ConnectionLineShape: View {
    let edge: GraphEdge
    let path: Path
    let animationPhase: Double
    let effectiveScale: CGFloat

    var body: some View {
        let weight = edge.combinedWeight
        let baseWidth = 1.0 + CGFloat(weight)
        let modulation = 0.1 * CGFloat(sin(animationPhase * 0.308))
        // Scale line width by effectiveScale so it matches the scaled block visuals
        let lineWidth = (baseWidth + modulation) * effectiveScale
        let baseOpacity = 0.15 + weight * 0.20
        let pulseProgress = CGFloat((animationPhase * 0.192).truncatingRemainder(dividingBy: 1.0))
        let stop1 = max(0, min(pulseProgress, 0.79))
        let stop2 = max(stop1 + 0.001, min(pulseProgress + 0.08, 0.89))
        let stop3 = max(stop2 + 0.001, min(pulseProgress + 0.16, 0.99))
        let lineColor = DS.textMuted

        ZStack {
            // Glow stroke
            path.stroke(
                lineColor.opacity(baseOpacity * 0.3),
                style: StrokeStyle(
                    lineWidth: lineWidth * 2.5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            // Main stroke with gradient pulse
            path.stroke(
                LinearGradient(
                    stops: [
                        .init(color: lineColor.opacity(baseOpacity * 0.4), location: 0),
                        .init(color: lineColor.opacity(baseOpacity), location: stop1),
                        .init(color: lineColor.opacity(baseOpacity * 0.7), location: stop2),
                        .init(color: lineColor.opacity(baseOpacity), location: stop3),
                        .init(color: lineColor.opacity(baseOpacity * 0.4), location: 1),
                    ],
                    startPoint: UnitPoint(x: 0, y: 0),
                    endPoint: UnitPoint(x: 1, y: 1)
                ),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
