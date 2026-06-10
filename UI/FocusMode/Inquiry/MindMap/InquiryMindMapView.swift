// CosmoOS/UI/FocusMode/Inquiry/MindMap/InquiryMindMapView.swift
// Shared 2D mind map: root at left, branches fanning right with colored
// bezier edges. Powers both the Deep Dive Map tab and the in-session overlay.

import SwiftUI

@MainActor
struct InquiryMindMapView: View {
    let root: MindMapNode
    let onSelect: (MindMapNode) -> Void

    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var hasAppeared = false

    private var layout: MindMapLayout {
        MindMapLayoutEngine.layout(root: root, nodeSize: { InquiryMindMapNodeCard.size(for: $0) })
    }

    var body: some View {
        GeometryReader { proxy in
            mapContent
                .frame(width: layout.size.width, height: layout.size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(initialCenteringOffset(in: proxy.size))
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(panGesture)
                .gesture(zoomGesture)
                .onTapGesture(count: 2) { resetViewport() }
        }
        .clipped()
        .onAppear { hasAppeared = true }
    }

    // MARK: - Content

    private var mapContent: some View {
        ZStack(alignment: .topLeading) {
            edgesCanvas
            ForEach(flattenedNodes) { node in
                nodeCard(node)
            }
        }
    }

    private var edgesCanvas: some View {
        Canvas { context, _ in
            for edge in layout.edges {
                var path = Path()
                path.move(to: edge.from)
                let midX = (edge.from.x + edge.to.x) / 2
                path.addCurve(
                    to: edge.to,
                    control1: CGPoint(x: midX, y: edge.from.y),
                    control2: CGPoint(x: midX, y: edge.to.y)
                )
                let color = Self.branchColor(edge.branchIndex)
                if edge.toActive {
                    context.stroke(path, with: .color(color.opacity(0.25)), lineWidth: 5)
                }
                context.stroke(
                    path,
                    with: .color(color.opacity(edge.toActive ? 0.9 : 0.55)),
                    style: StrokeStyle(lineWidth: edge.toActive ? 2 : 1.5, lineCap: .round)
                )
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .accessibilityHidden(true)
    }

    private func nodeCard(_ node: MindMapNode) -> some View {
        let depth = layout.depths[node.id] ?? 0
        return InquiryMindMapNodeCard(
            node: node,
            branchColor: Self.branchColor(branchIndex(of: node)),
            onSelect: onSelect
        )
        .position(layout.positions[node.id] ?? .zero)
        .opacity(hasAppeared ? 1 : 0)
        .animation(ProMotionSprings.gentle.delay(Double(depth) * 0.06), value: hasAppeared)
    }

    // MARK: - Gestures & viewport

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: dragStart.width + value.translation.width,
                    height: dragStart.height + value.translation.height
                )
            }
            .onEnded { _ in dragStart = offset }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(2.0, max(0.4, value.magnification))
            }
    }

    private func resetViewport() {
        withAnimation(ProMotionSprings.gentle) {
            offset = .zero
            dragStart = .zero
            scale = 1
        }
    }

    private func initialCenteringOffset(in container: CGSize) -> CGSize {
        guard container.height > 0 else { return .zero }
        let verticalSlack = container.height - layout.size.height * scale
        return CGSize(width: 0, height: max(0, verticalSlack / 2))
    }

    // MARK: - Helpers

    private var flattenedNodes: [MindMapNode] {
        func flatten(_ node: MindMapNode) -> [MindMapNode] {
            [node] + node.children.flatMap(flatten)
        }
        return flatten(root)
    }

    /// Which top-level branch a node descends from (root itself = -1).
    private func branchIndex(of node: MindMapNode) -> Int {
        guard node.id != root.id else { return -1 }
        for (index, branch) in root.children.enumerated() {
            if branch.id == node.id || contains(branch, nodeId: node.id) { return index }
        }
        return -1
    }

    private func contains(_ node: MindMapNode, nodeId: String) -> Bool {
        node.children.contains { $0.id == nodeId || contains($0, nodeId: nodeId) }
    }

    static func branchColor(_ index: Int) -> Color {
        guard index >= 0 else { return DS.accent }
        let palette: [Color] = [
            DS.accent,
            CosmoColors.idea,
            DS.orange,
            CosmoMentionColors.connection,
            CosmoColors.research,
            CosmoColors.note
        ]
        return palette[index % palette.count]
    }
}
