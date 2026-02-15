// CosmoOS/Canvas/CanvasConnectionLinesLayer.swift
// Container that queries graph edges and renders all visible pulse lines on the canvas

import SwiftUI

/// Renders knowledge pulse lines between related blocks on the canvas.
/// Queries the graph for edges where both source and target are visible, then
/// draws animated bezier connections.
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

    // MARK: - Constants

    private enum Constants {
        static let maxVisibleLines = 50
        static let minLineLength: CGFloat = 20
        static let maxLineLength: CGFloat = 2000
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
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate

            ZStack {
                ForEach(visibleEdges, id: \.deduplicationKey) { edge in
                    if let fromBlock = blocksByUUID[edge.sourceUUID],
                       let toBlock = blocksByUUID[edge.targetUUID] {

                        let fromPos = blockScreenPosition(fromBlock)
                        let toPos = blockScreenPosition(toBlock)
                        let distance = hypot(toPos.x - fromPos.x, toPos.y - fromPos.y)

                        if distance >= Constants.minLineLength && distance <= Constants.maxLineLength {
                            // Calculate edge-to-edge endpoints so line is visible between blocks
                            let edgePoints = edgeEndpoints(
                                from: fromPos, fromSize: fromBlock.size,
                                to: toPos, toSize: toBlock.size
                            )

                            KnowledgePulseLineView(
                                from: edgePoints.start,
                                to: edgePoints.end,
                                weight: edge.combinedWeight,
                                edgeType: edge.type ?? .contextual,
                                animationPhase: phase
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .onChange(of: blockUUIDs) { _, _ in
            fetchEdges()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.graphNodeUpdated)) { _ in
            fetchEdges()
        }
        .onAppear {
            fetchEdges()
        }
        .onDisappear {
            loadTask?.cancel()
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

    // MARK: - Position Mapping

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
        return min(byWidth, byHeight) + 8 // +8pt padding outside the block
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
