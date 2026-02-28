// CosmoOS/Canvas/CanvasConnectionLinesLayer.swift
// Container that queries graph edges and renders all visible pulse lines on the canvas

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

    // MARK: - State

    @State private var edges: [GraphEdge] = []
    @State private var loadTask: Task<Void, Never>?
    @State private var animationPhase: Double = 0
    @State private var selectedEdgeKey: String?
    @State private var deleteTask: Task<Void, Never>?

    // MARK: - Constants

    private enum Constants {
        static let maxVisibleLines = 50
        static let minLineLength: CGFloat = 20
        static let maxLineLength: CGFloat = 2000
        static let hitTestWidth: CGFloat = 24
    }

    // MARK: - Computed

    /// Map of entityUuid -> block for quick lookup
    private var blocksByUUID: [String: CanvasBlock] {
        Dictionary(blocks.map { ($0.entityUuid, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Block UUIDs currently on canvas
    private var blockUUIDs: [String] {
        blocks.map { $0.entityUuid }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Visual layer (no hit testing — decorative animated lines)
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate

                ZStack {
                    ForEach(visibleEdges, id: \.deduplicationKey) { edge in
                        if let endpoints = endpointsForEdge(edge) {
                            KnowledgePulseLineView(
                                from: endpoints.start,
                                to: endpoints.end,
                                weight: edge.combinedWeight,
                                edgeType: edge.type ?? .contextual,
                                animationPhase: phase
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .allowsHitTesting(false)

            // Hit-test layer — invisible wide paths that respond to taps
            ForEach(visibleEdges, id: \.deduplicationKey) { edge in
                if let endpoints = endpointsForEdge(edge) {
                    connectionHitArea(edge: edge, from: endpoints.start, to: endpoints.end)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Delete button for selected connection
            if let selectedKey = selectedEdgeKey,
               let edge = visibleEdges.first(where: { $0.deduplicationKey == selectedKey }),
               let endpoints = endpointsForEdge(edge) {
                connectionDeleteButton(edge: edge, from: endpoints.start, to: endpoints.end)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: blockUUIDs) { _, _ in
            fetchEdges()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.graphNodeUpdated)) { _ in
            fetchEdges()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.blockSelected)) { _ in
            // Deselect connection when a block is selected
            selectedEdgeKey = nil
        }
        .onAppear {
            fetchEdges()
        }
        .onDisappear {
            loadTask?.cancel()
            deleteTask?.cancel()
        }
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
                    .fill(Color.red.opacity(0.8))
                    .shadow(color: .black.opacity(0.4), radius: 6)
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

    // MARK: - Edge Filtering

    /// Edges where both source and target are on canvas, deduplicated by
    /// unordered UUID pair so bidirectional directed edges (A->B, B->A) render
    /// only one line, limited to max count.
    private var visibleEdges: [GraphEdge] {
        let uuidSet = Set(blockUUIDs)
        var seenPairs = Set<String>()
        var result: [GraphEdge] = []

        for edge in edges {
            guard uuidSet.contains(edge.sourceUUID) && uuidSet.contains(edge.targetUUID) else { continue }

            // Use sorted UUID pair as dedup key to collapse A->B and B->A
            let sorted = [edge.sourceUUID, edge.targetUUID].sorted()
            let pairKey = "\(sorted[0]):\(sorted[1]):\(edge.edgeType)"
            guard seenPairs.insert(pairKey).inserted else { continue }

            result.append(edge)
            if result.count >= Constants.maxVisibleLines { break }
        }

        return result
    }

    // MARK: - Position & Endpoint Helpers

    /// Compute visible edge endpoints for a given edge, or nil if blocks not found or too close/far
    private func endpointsForEdge(_ edge: GraphEdge) -> (start: CGPoint, end: CGPoint)? {
        guard let fromBlock = blocksByUUID[edge.sourceUUID],
              let toBlock = blocksByUUID[edge.targetUUID] else { return nil }

        let fromPos = blockScreenPosition(fromBlock)
        let toPos = blockScreenPosition(toBlock)
        let distance = hypot(toPos.x - fromPos.x, toPos.y - fromPos.y)

        guard distance >= Constants.minLineLength && distance <= Constants.maxLineLength else { return nil }

        // Use actual rendered size (base size * block scale)
        let fromRendered = CGSize(width: fromBlock.size.width * fromBlock.scale, height: fromBlock.size.height * fromBlock.scale)
        let toRendered = CGSize(width: toBlock.size.width * toBlock.scale, height: toBlock.size.height * toBlock.scale)

        return edgeEndpoints(
            from: fromPos, fromSize: fromRendered,
            to: toPos, toSize: toRendered
        )
    }

    /// Block position in the canvas coordinate space (before scaleEffect is applied)
    private func blockScreenPosition(_ block: CanvasBlock) -> CGPoint {
        CGPoint(
            x: block.position.x + canvasOffset.width + scaledPanOffset.width,
            y: block.position.y + canvasOffset.height + scaledPanOffset.height
        )
    }

    /// Calculate line endpoints at the edges of blocks (not centers) so lines
    /// are visible between blocks rather than hidden under them.
    private func edgeEndpoints(
        from: CGPoint, fromSize: CGSize,
        to: CGPoint, toSize: CGSize
    ) -> (start: CGPoint, end: CGPoint) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let angle = atan2(dy, dx)

        // Calculate intersection with block edge using the block's half-dimensions
        let fromHalfW = fromSize.width / 2
        let fromHalfH = fromSize.height / 2
        let toHalfW = toSize.width / 2
        let toHalfH = toSize.height / 2

        // Offset start point from source block edge
        let startOffset = edgePadding(halfWidth: fromHalfW, halfHeight: fromHalfH, angle: angle)
        let start = CGPoint(
            x: from.x + cos(angle) * startOffset,
            y: from.y + sin(angle) * startOffset
        )

        // Offset end point from target block edge (opposite direction)
        let endOffset = edgePadding(halfWidth: toHalfW, halfHeight: toHalfH, angle: angle + .pi)
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
            // Nearly axis-aligned — use the relevant half-dimension
            return cosA > sinA ? halfWidth : halfHeight
        }
        // Intersection with rectangle edge
        let byWidth = halfWidth / cosA
        let byHeight = halfHeight / sinA
        return min(byWidth, byHeight)
    }

    // MARK: - Data Loading

    private func fetchEdges() {
        loadTask?.cancel()
        let uuids = blockUUIDs
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
