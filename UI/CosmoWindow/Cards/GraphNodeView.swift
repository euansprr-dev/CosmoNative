// CosmoOS/UI/CosmoWindow/Cards/GraphNodeView.swift
// Mini knowledge graph visualization with radial layout

import SwiftUI

struct GraphNodeView: View {
    let data: GraphViewData

    private let centerRadius: CGFloat = 28
    private let nodeRadius: CGFloat = 20
    private let orbitRadius: CGFloat = 100

    private var visibleNodes: [GraphNodeData] {
        Array(data.nodes.prefix(15))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            graphHeader
            graphCanvas
        }
        .padding(16)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: DS.text.opacity(0.06), radius: 8, y: 4)
    }

    // MARK: - Subviews

    private var graphHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.caption)
                .accessibilityLabel("Knowledge graph")
            Text("Knowledge Graph")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(DS.textSecondary)
    }

    private var graphCanvas: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                edgeLines(center: center)
                outerNodes(center: center)
                centerNode(at: center)
            }
        }
        .frame(height: 260)
    }

    // MARK: - Graph Elements

    private func edgeLines(center: CGPoint) -> some View {
        ForEach(Array(data.edges.enumerated()), id: \.offset) { _, edge in
            let sourcePos = nodePosition(uuid: edge.sourceUuid, center: center)
            let targetPos = nodePosition(uuid: edge.targetUuid, center: center)
            Path { path in
                path.move(to: sourcePos)
                path.addLine(to: targetPos)
            }
            .stroke(DS.border, lineWidth: 1)
        }
    }

    private func outerNodes(center: CGPoint) -> some View {
        let peripheralNodes = visibleNodes.filter { $0.uuid != data.centerUuid }
        return ForEach(Array(peripheralNodes.enumerated()), id: \.element.uuid) { index, node in
            let pos = peripheralPosition(index: index, total: peripheralNodes.count, center: center)
            nodeCircle(node: node, radius: nodeRadius, at: pos)
        }
    }

    private func centerNode(at center: CGPoint) -> some View {
        let node = visibleNodes.first { $0.uuid == data.centerUuid }
        return Group {
            if let node {
                nodeCircle(node: node, radius: centerRadius, at: center, isCenter: true)
            }
        }
    }

    private func nodeCircle(node: GraphNodeData, radius: CGFloat, at position: CGPoint, isCenter: Bool = false) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(isCenter ? DS.accent : nodeColor(for: node.type))
                .frame(width: radius * 2, height: radius * 2)
                .overlay(
                    Image(systemName: nodeIcon(for: node.type))
                        .font(isCenter ? .caption : .caption2)
                        .foregroundStyle(DS.textOnAccent)
                        .accessibilityLabel("\(node.type) node")
                )
            Text(node.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 60)
        }
        .position(position)
    }

    // MARK: - Layout Helpers

    private func peripheralPosition(index: Int, total: Int, center: CGPoint) -> CGPoint {
        guard total > 0 else { return center }
        let angle = (2 * .pi / Double(total)) * Double(index) - .pi / 2
        return CGPoint(
            x: center.x + orbitRadius * cos(angle),
            y: center.y + orbitRadius * sin(angle)
        )
    }

    private func nodePosition(uuid: String, center: CGPoint) -> CGPoint {
        if uuid == data.centerUuid { return center }
        let peripheralNodes = visibleNodes.filter { $0.uuid != data.centerUuid }
        guard let index = peripheralNodes.firstIndex(where: { $0.uuid == uuid }) else { return center }
        return peripheralPosition(index: index, total: peripheralNodes.count, center: center)
    }

    private func nodeColor(for type: String) -> Color {
        switch type.lowercased() {
        case "idea": return DS.entityIdea
        case "research": return DS.entityResearch
        case "content": return DS.entityContent
        case "note": return DS.entityNote
        case "connection": return DS.entityConnection
        case "swipe": return DS.entitySwipe
        case "task": return DS.entityTask
        default: return DS.textMuted
        }
    }

    private func nodeIcon(for type: String) -> String {
        switch type.lowercased() {
        case "idea": return "lightbulb.fill"
        case "research": return "magnifyingglass"
        case "content": return "doc.text.fill"
        case "note": return "note.text"
        case "connection": return "person.fill"
        case "swipe": return "rectangle.stack.fill"
        case "task": return "checkmark.circle.fill"
        default: return "circle.fill"
        }
    }
}
