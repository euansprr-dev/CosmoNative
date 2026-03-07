// CosmoOS/Canvas/CanvasConnectionLinesLayer.swift
// Container that queries graph edges and renders all visible pulse lines on the canvas
// PERF: Throttled 15fps animation, cached endpoints, single-pass edge filtering

import SwiftUI

/// Renders knowledge pulse lines between related blocks on the canvas.
/// Queries the graph for edges where both source and target are visible, then
/// draws animated bezier connections. Supports tap-to-select and delete.
@MainActor
struct CanvasConnectionLinesLayer: View {

    // MARK: - Parameters

    let blocks: [CanvasBlock]
    let canvasOffset: CGSize
    let scaledPanOffset: CGSize
    let effectiveScale: CGFloat
    /// Live drag offsets from CanvasView so lines follow blocks during drag
    var blockDragOffsets: [String: CGSize] = [:]

    // MARK: - State

    @State private var edges: [GraphEdge] = []
    @State private var loadTask: Task<Void, Never>?
    @State private var animationPhase: Double = 0
    @State private var selectedEdgeKey: String?
    @State private var deleteTask: Task<Void, Never>?
    @State private var pulseTimer: Timer?

    // PERF: Cached derived data — recomputed only on data changes, not every frame
    @State private var cachedVisibleEdges: [GraphEdge] = []
    @State private var cachedEndpoints: [String: (start: CGPoint, end: CGPoint)] = [:]

    // PERF: Throttle endpoint recomputation during drag to ~15fps
    @State private var dragEndpointThrottleTask: Task<Void, Never>?

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

    // MARK: - Body

    var body: some View {
        ZStack {
            // Visual layer (no hit testing — decorative animated lines)
            // PERF: No TimelineView — driven by 15fps timer updating animationPhase
            ZStack {
                ForEach(cachedVisibleEdges, id: \.deduplicationKey) { edge in
                    if let endpoints = cachedEndpoints[edge.deduplicationKey] {
                        KnowledgePulseLineView(
                            from: endpoints.start,
                            to: endpoints.end,
                            weight: edge.combinedWeight,
                            edgeType: edge.type ?? .contextual,
                            animationPhase: animationPhase
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            // Hit-test layer — invisible wide paths that respond to taps
            // PERF: Uses same cachedEndpoints as visual layer
            ForEach(cachedVisibleEdges, id: \.deduplicationKey) { edge in
                if let endpoints = cachedEndpoints[edge.deduplicationKey] {
                    connectionHitArea(edge: edge, from: endpoints.start, to: endpoints.end)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Delete button for selected connection
            if let selectedKey = selectedEdgeKey,
               let edge = cachedVisibleEdges.first(where: { $0.deduplicationKey == selectedKey }),
               let endpoints = cachedEndpoints[edge.deduplicationKey] {
                connectionDeleteButton(edge: edge, from: endpoints.start, to: endpoints.end)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: edges) { _, _ in
            recomputeVisibleEdgesAndEndpoints()
        }
        .onChange(of: blocks.count) { _, _ in
            fetchEdges()
        }
        .onChange(of: canvasOffset) { _, _ in
            recomputeEndpoints()
        }
        .onChange(of: scaledPanOffset) { _, _ in
            recomputeEndpoints()
        }
        .onChange(of: blockDragOffsets) { _, _ in
            throttledRecomputeEndpoints()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.graphNodeUpdated)) { _ in
            fetchEdges()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.blockSelected)) { _ in
            // Deselect connection when a block is selected
            selectedEdgeKey = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.blockRenderedSizeChanged)) { _ in
            // Recompute endpoints when a block's actual rendered size changes (e.g. autoHeight expansion)
            recomputeEndpoints()
        }
        .onAppear {
            fetchEdges()
            startPulseTimer()
        }
        .onDisappear {
            loadTask?.cancel()
            deleteTask?.cancel()
            pulseTimer?.invalidate()
            pulseTimer = nil
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

    // MARK: - Cached Computation

    /// Recompute both visible edges and their endpoints (on data changes)
    private func recomputeVisibleEdgesAndEndpoints() {
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

        // Compute endpoints for all visible edges
        var endpoints: [String: (start: CGPoint, end: CGPoint)] = [:]
        for edge in visibleResult {
            if let ep = computeEndpoints(for: edge, blocksByUUID: blocksByUUID) {
                endpoints[edge.deduplicationKey] = ep
            }
        }
        cachedEndpoints = endpoints
    }

    /// Recompute only endpoints when canvas position changes (edges stay the same)
    private func recomputeEndpoints() {
        let blocksByUUID = Dictionary(blocks.map { ($0.entityUuid, $0) }, uniquingKeysWith: { first, _ in first })
        var endpoints: [String: (start: CGPoint, end: CGPoint)] = [:]
        for edge in cachedVisibleEdges {
            if let ep = computeEndpoints(for: edge, blocksByUUID: blocksByUUID) {
                endpoints[edge.deduplicationKey] = ep
            }
        }
        cachedEndpoints = endpoints
    }

    /// Throttled endpoint recomputation during drag — ~15fps (every 66ms).
    /// Connection lines don't need pixel-perfect tracking during active drag;
    /// they snap to final positions on drag end via the onChange(of: canvasOffset) path.
    private func throttledRecomputeEndpoints() {
        guard dragEndpointThrottleTask == nil else { return }
        // Fire immediately for first frame, then throttle
        recomputeEndpoints()
        dragEndpointThrottleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(66))
            dragEndpointThrottleTask = nil
        }
    }

    /// Compute endpoints for a single edge
    private func computeEndpoints(for edge: GraphEdge, blocksByUUID: [String: CanvasBlock]) -> (start: CGPoint, end: CGPoint)? {
        guard let fromBlock = blocksByUUID[edge.sourceUUID],
              let toBlock = blocksByUUID[edge.targetUUID] else { return nil }

        let fromPos = blockScreenPosition(fromBlock)
        let toPos = blockScreenPosition(toBlock)
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

    // MARK: - Position & Endpoint Helpers

    /// Block position in the canvas coordinate space (before scaleEffect is applied),
    /// including live drag offset so lines follow blocks during drag
    private func blockScreenPosition(_ block: CanvasBlock) -> CGPoint {
        let dragOffset = blockDragOffsets[block.id] ?? .zero
        return CGPoint(
            x: block.position.x + canvasOffset.width + scaledPanOffset.width + dragOffset.width,
            y: block.position.y + canvasOffset.height + scaledPanOffset.height + dragOffset.height
        )
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
