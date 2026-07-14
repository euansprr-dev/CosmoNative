// CosmoOS/UI/FocusMode/Inquiry/MindMap/InquiryMindMapView.swift
// Shared 2D mind map: root at left, branches fanning right with colored
// bezier edges. Powers both the Deep Dive Map tab and the in-session overlay.

import SwiftUI

@MainActor
struct InquiryMindMapView: View {
    let root: MindMapNode
    /// Cross-connection hyperlinks rendered as dashed curves (Map tab only).
    var conceptLinks: [MindMapConceptLink] = []
    /// Concepts the user can move a node under via the context menu.
    var reparentTargets: [(uuid: String, title: String)] = []
    /// Persists a user-chosen parent (child UUID, new parent UUID or nil = top level).
    var onReparent: ((String, String?) -> Void)?
    let onSelect: (MindMapNode) -> Void

    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var scale: CGFloat = 1
    /// The scale a pinch started from — MagnifyGesture reports the gesture's
    /// own magnification, so without this anchor every new pinch snapped the
    /// map back toward 1×.
    @State private var pinchBaseScale: CGFloat = 1
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
        .overlay(alignment: .bottomTrailing) { resetControl }
        .onAppear { hasAppeared = true }
    }

    /// Quiet reset affordance — double-click already resets, but nothing on
    /// screen said so; the control also carries the tooltip that teaches it.
    @ViewBuilder
    private var resetControl: some View {
        if scale != 1 || offset != .zero {
            Button(action: resetViewport) {
                Image(systemName: "arrow.counterclockwise")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(DS.space16)
            .transition(.opacity)
            .help("Reset the view (or double-click anywhere)")
            .accessibilityLabel("Reset map view")
        }
    }

    // MARK: - Content

    private var mapContent: some View {
        ZStack(alignment: .topLeading) {
            linkEdgesCanvas
            edgesCanvas
            ForEach(flattenedNodes) { node in
                nodeCard(node)
            }
        }
    }

    /// Cross-connection hyperlinks: quiet dashed curves beneath the tree —
    /// the "everything is interlinked" layer without breaking the hierarchy.
    @ViewBuilder
    private var linkEdgesCanvas: some View {
        if !conceptLinks.isEmpty {
            Canvas { context, _ in
                for link in conceptLinks {
                    guard let from = layout.positions[link.fromNodeId],
                          let to = layout.positions[link.toNodeId] else { continue }
                    var path = Path()
                    path.move(to: from)
                    let control = CGPoint(
                        x: (from.x + to.x) / 2,
                        y: min(from.y, to.y) - 36
                    )
                    path.addQuadCurve(to: to, control: control)
                    context.stroke(
                        path,
                        with: .color(CosmoMentionColors.connection.opacity(0.28)),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 4])
                    )
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .accessibilityHidden(true)
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
                    with: .color(color.opacity(edge.toActive ? 0.9 : 0.65)),
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
        .contextMenu { conceptContextMenu(node) }
        .position(layout.positions[node.id] ?? .zero)
        .opacity(hasAppeared ? 1 : 0)
        .animation(ProMotionSprings.gentle.delay(Double(depth) * 0.06), value: hasAppeared)
    }

    /// "Move under…" reparenting for concept nodes — the user's final say
    /// over the map hierarchy (pinned; crystallization never overrides it).
    @ViewBuilder
    private func conceptContextMenu(_ node: MindMapNode) -> some View {
        if node.isConcept, let uuid = node.atomUUID {
            Button("Open as pane") { ConnectionLinkOpener.open(uuid: uuid) }
            if let onReparent {
                Menu("Move under") {
                    Button("Top level") { onReparent(uuid, nil) }
                    Divider()
                    ForEach(reparentTargets.filter { $0.uuid != uuid }, id: \.uuid) { target in
                        Button(target.title) { onReparent(uuid, target.uuid) }
                    }
                }
            }
        }
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
                scale = min(2.0, max(0.4, pinchBaseScale * value.magnification))
            }
            .onEnded { _ in
                pinchBaseScale = scale
            }
    }

    private func resetViewport() {
        withAnimation(ProMotionSprings.gentle) {
            offset = .zero
            dragStart = .zero
            scale = 1
            pinchBaseScale = 1
        }
    }

    private func initialCenteringOffset(in container: CGSize) -> CGSize {
        guard container.height > 0 else { return .zero }
        let verticalSlack = container.height - layout.size.height * scale
        // Small trees float centered both ways — a root pinned to the left
        // edge of a wide viewport read as a layout accident.
        let horizontalSlack = container.width - layout.size.width * scale
        return CGSize(
            width: max(0, horizontalSlack / 2),
            height: max(0, verticalSlack / 2)
        )
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
