// CosmoOS/UI/Sanctuary/Dimensions/Knowledge/KnowledgeConstellation.swift
// Knowledge Constellation - 3D knowledge graph visualization
// Phase 7: Following SANCTUARY_UI_SPEC_V2.md section 3.5

import SwiftUI

// MARK: - Knowledge Constellation View

/// 3D visualization of the knowledge graph
public struct KnowledgeConstellation: View {

    // MARK: - Properties

    let nodes: [KnowledgeNode]
    let edges: [KnowledgeEdge]
    let positions: [NodePosition]
    let clusters: [KnowledgeCluster]
    let onNodeTap: (KnowledgeNode) -> Void

    @State private var isVisible: Bool = false
    @State private var rotationAngle: Double = 0
    @State private var isAutoRotating: Bool = true
    @State private var scale: CGFloat = 1.0
    @State private var hoveredNode: UUID?

    // MARK: - Initialization

    public init(
        nodes: [KnowledgeNode],
        edges: [KnowledgeEdge],
        positions: [NodePosition],
        clusters: [KnowledgeCluster],
        onNodeTap: @escaping (KnowledgeNode) -> Void
    ) {
        self.nodes = nodes
        self.edges = edges
        self.positions = positions
        self.clusters = clusters
        self.onNodeTap = onNodeTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("3D KNOWLEDGE CONSTELLATION")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Constellation canvas
            ZStack {
                // Background
                constellationBackground

                // Graph visualization
                GeometryReader { geometry in
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    ZStack {
                        // Edges
                        ForEach(edges) { edge in
                            edgeLine(for: edge, center: center, size: geometry.size)
                        }

                        // Cluster backgrounds
                        ForEach(clusters) { cluster in
                            clusterBackground(for: cluster, center: center, size: geometry.size)
                        }

                        // Nodes
                        ForEach(nodes) { node in
                            nodeView(for: node, center: center, size: geometry.size)
                        }
                    }
                    .rotationEffect(.degrees(rotationAngle))
                    .scaleEffect(scale)
                }
                .frame(height: 400)
                .clipped()

                // Legend
                legendOverlay
            }
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                    .fill(SanctuaryColors.Glass.highlight)
            )

            // Controls
            controlBar
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
            startAutoRotation()
        }
    }

    // MARK: - Background

    private var constellationBackground: some View {
        ZStack {
            // Deep space gradient
            RadialGradient(
                colors: [
                    SanctuaryColors.Dimensions.knowledge.opacity(0.1),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 300
            )

            // Star field effect
            ForEach(0..<50, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(Double.random(in: 0.1...0.3)))
                    .frame(width: CGFloat.random(in: 1...2))
                    .position(
                        x: CGFloat.random(in: 0...400),
                        y: CGFloat.random(in: 0...400)
                    )
            }
        }
    }

    // MARK: - Node View

    private func nodeView(for node: KnowledgeNode, center: CGPoint, size: CGSize) -> some View {
        let position = positions.first { $0.nodeID == node.id }
        let x = center.x + CGFloat(position?.x ?? 0) * (size.width / 300)
        let y = center.y + CGFloat(position?.y ?? 0) * (size.height / 300)
        let isHovered = hoveredNode == node.id

        return Button(action: { onNodeTap(node) }) {
            ZStack {
                // Glow effect
                if node.isActive || isHovered {
                    Circle()
                        .fill(Color(hex: node.type.color).opacity(0.3))
                        .frame(width: isHovered ? 40 : 30, height: isHovered ? 40 : 30)
                        .blur(radius: 8)
                }

                // Node circle
                Circle()
                    .fill(node.isActive ?
                        Color(hex: node.type.color) :
                        SanctuaryColors.Glass.border
                    )
                    .frame(width: nodeSize(for: node), height: nodeSize(for: node))

                // Icon
                Image(systemName: node.type.iconName)
                    .font(.system(size: 8))
                    .foregroundColor(node.isActive ? .white : SanctuaryColors.Text.tertiary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .position(x: x, y: y)
        .scaleEffect(isHovered ? 1.2 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            hoveredNode = hovering ? node.id : nil
        }
    }

    private func nodeSize(for node: KnowledgeNode) -> CGFloat {
        let baseSize: CGFloat = 16
        let accessBonus = min(CGFloat(node.accessCount) / 50, 1) * 8
        return baseSize + accessBonus
    }

    // MARK: - Edge Line

    private func edgeLine(for edge: KnowledgeEdge, center: CGPoint, size: CGSize) -> some View {
        let sourcePos = positions.first { $0.nodeID == edge.sourceNodeID }
        let targetPos = positions.first { $0.nodeID == edge.targetNodeID }

        let startX = center.x + CGFloat(sourcePos?.x ?? 0) * (size.width / 300)
        let startY = center.y + CGFloat(sourcePos?.y ?? 0) * (size.height / 300)
        let endX = center.x + CGFloat(targetPos?.x ?? 0) * (size.width / 300)
        let endY = center.y + CGFloat(targetPos?.y ?? 0) * (size.height / 300)

        return Path { path in
            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(x: endX, y: endY))
        }
        .stroke(
            LinearGradient(
                colors: [
                    SanctuaryColors.Dimensions.knowledge.opacity(edge.strength * 0.6),
                    SanctuaryColors.Dimensions.knowledge.opacity(edge.strength * 0.3)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: edgeWidth(for: edge), lineCap: .round)
        )
    }

    private func edgeWidth(for edge: KnowledgeEdge) -> CGFloat {
        if edge.strength >= 0.7 { return 2 }
        if edge.strength >= 0.4 { return 1.5 }
        return 1
    }

    // MARK: - Cluster Background

    private func clusterBackground(for cluster: KnowledgeCluster, center: CGPoint, size: CGSize) -> some View {
        let clusterNodes = nodes.filter { $0.clusterID == cluster.id }
        let clusterPositions = positions.filter { pos in clusterNodes.contains { $0.id == pos.nodeID } }

        guard !clusterPositions.isEmpty else {
            return AnyView(EmptyView())
        }

        let avgX = clusterPositions.map { $0.x }.reduce(0, +) / Double(clusterPositions.count)
        let avgY = clusterPositions.map { $0.y }.reduce(0, +) / Double(clusterPositions.count)

        let x = center.x + CGFloat(avgX) * (size.width / 300)
        let y = center.y + CGFloat(avgY) * (size.height / 300)

        return AnyView(
            VStack(spacing: 2) {
                Text(cluster.name.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)
            }
            .position(x: x, y: y - 50)
        )
    }

    // MARK: - Legend

    private var legendOverlay: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("NODE LEGEND:")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            HStack(spacing: SanctuaryLayout.Spacing.md) {
                legendItem(icon: "circle.fill", label: "Active (recent)", color: SanctuaryColors.Dimensions.knowledge)
                legendItem(icon: "circle", label: "Dormant (7+ days)", color: SanctuaryColors.Text.tertiary)
            }

            Text("Line thickness = Connection strength")
                .font(.system(size: 8))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.background.opacity(0.9))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(SanctuaryLayout.Spacing.md)
    }

    private func legendItem(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(color)

            Text(label)
                .font(.system(size: 8))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            controlButton(icon: "arrow.counterclockwise", label: "ROTATE") {
                withAnimation(.easeOut(duration: 0.5)) {
                    rotationAngle -= 45
                }
            }

            controlButton(icon: isAutoRotating ? "pause.fill" : "play.fill", label: isAutoRotating ? "PAUSE" : "AUTO") {
                isAutoRotating.toggle()
                if isAutoRotating { startAutoRotation() }
            }

            controlButton(icon: "plus.magnifyingglass", label: "ZOOM") {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = min(2.0, scale + 0.2)
                }
            }

            controlButton(icon: "minus.magnifyingglass", label: "ZOOM") {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = max(0.5, scale - 0.2)
                }
            }

            controlButton(icon: "arrow.down.backward.and.arrow.up.forward", label: "RESET") {
                withAnimation(.easeOut(duration: 0.5)) {
                    rotationAngle = 0
                    scale = 1.0
                }
            }

            Spacer()

            // Stats
            HStack(spacing: SanctuaryLayout.Spacing.lg) {
                statLabel(value: "\(nodes.count)", label: "nodes")
                statLabel(value: "\(edges.count)", label: "edges")
                statLabel(value: "\(clusters.count)", label: "clusters")
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 12))

                Text(label)
                    .font(.system(size: 7, weight: .medium))
            }
            .foregroundColor(SanctuaryColors.Dimensions.knowledge)
            .padding(.horizontal, SanctuaryLayout.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(SanctuaryColors.Dimensions.knowledge.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func statLabel(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }

    // MARK: - Auto Rotation

    private func startAutoRotation() {
        guard isAutoRotating else { return }

        withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
            rotationAngle += 360
        }
    }
}

// MARK: - Node Detail Panel

/// Detail panel shown when a node is tapped
public struct NodeDetailPanel: View {

    let node: KnowledgeNode
    let connectedNodes: [KnowledgeNode]
    let edges: [KnowledgeEdge]
    let onDismiss: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                Image(systemName: node.type.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: node.type.color))

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text(node.type.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Metadata
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                metadataRow(label: "CREATED", value: formattedDate(node.createdDate))
                metadataRow(label: "LAST ACCESSED", value: formattedDate(node.lastAccessedDate))
                metadataRow(label: "ACCESS COUNT", value: "\(node.accessCount)")
            }

            // Tags
            if !node.tags.isEmpty {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    Text("TAGS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    FlowLayout(spacing: 6) {
                        ForEach(node.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10))
                                .foregroundColor(SanctuaryColors.Dimensions.knowledge)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(SanctuaryColors.Dimensions.knowledge.opacity(0.1))
                                )
                        }
                    }
                }
            }

            // Connected nodes
            if !connectedNodes.isEmpty {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                    Text("CONNECTED TO:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    ForEach(connectedNodes.prefix(5)) { connected in
                        connectionRow(for: connected)
                    }
                }
            }

            // Notes
            if !node.notes.isEmpty {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    Text("RECENT NOTES:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    ForEach(node.notes.prefix(2), id: \.self) { note in
                        Text("• \(note)")
                            .font(.system(size: 11))
                            .foregroundColor(SanctuaryColors.Text.secondary)
                    }
                }
            }

            // Actions
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                actionButton(icon: "note.text", label: "Add Note")
                actionButton(icon: "link", label: "Link Node")
                actionButton(icon: "archivebox", label: "Archive")
            }
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Spacer()

            Text(value)
                .font(.system(size: 11))
                .foregroundColor(SanctuaryColors.Text.secondary)
        }
    }

    private func connectionRow(for node: KnowledgeNode) -> some View {
        let edge = edges.first { $0.sourceNodeID == self.node.id && $0.targetNodeID == node.id }

        return HStack(spacing: SanctuaryLayout.Spacing.sm) {
            Circle()
                .fill(node.isActive ? Color(hex: node.type.color) : SanctuaryColors.Glass.border)
                .frame(width: 8, height: 8)

            Text(node.title)
                .font(.system(size: 11))
                .foregroundColor(SanctuaryColors.Text.primary)

            if let edge = edge {
                Text("(\(String(format: "%.2f", edge.strength)))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                if let description = edge.description {
                    Text("— \(description)")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func actionButton(icon: String, label: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))

                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(SanctuaryColors.Dimensions.knowledge)
            .padding(.horizontal, SanctuaryLayout.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(SanctuaryColors.Dimensions.knowledge.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                            .stroke(SanctuaryColors.Dimensions.knowledge.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Flow Layout

fileprivate struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct KnowledgeConstellation_Previews: PreviewProvider {
    static var previews: some View {
        let data = KnowledgeDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            KnowledgeConstellation(
                nodes: data.nodes,
                edges: data.edges,
                positions: data.nodePositions,
                clusters: data.clusters,
                onNodeTap: { _ in }
            )
            .padding()
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}
#endif
