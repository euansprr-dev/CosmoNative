// CosmoOS/UI/FocusMode/Inquiry/MindMap/InquiryMindMapLayoutEngine.swift
// Pure tidy-tree layout for the mind map: root at left-center, branches fan
// out to the right. Children stack vertically inside their subtree band and
// every parent is vertically centered on its children's span. Deterministic
// and unit-testable — no SwiftUI here.

import Foundation
import CoreGraphics

struct MindMapEdge: Identifiable, Equatable {
    var id: String          // "\(parentId)->\(childId)"
    var from: CGPoint       // Parent's right-edge midpoint
    var to: CGPoint         // Child's left-edge midpoint
    var branchIndex: Int    // Index of the top-level branch (for coloring)
    var toActive: Bool
}

struct MindMapLayout: Equatable {
    var positions: [String: CGPoint]   // Node id → center
    var depths: [String: Int]
    var size: CGSize
    var edges: [MindMapEdge]
}

enum MindMapLayoutEngine {

    static func layout(
        root: MindMapNode,
        nodeSize: (MindMapNode) -> CGSize,
        columnGap: CGFloat = 64,
        rowGap: CGFloat = 16,
        padding: CGFloat = 48
    ) -> MindMapLayout {
        // Pass 1: per-depth column widths.
        var columnWidths: [CGFloat] = []
        measureColumns(root, depth: 0, nodeSize: nodeSize, into: &columnWidths)
        var columnX: [CGFloat] = []
        var cursor = padding
        for width in columnWidths {
            columnX.append(cursor + width / 2)
            cursor += width + columnGap
        }

        // Pass 2: subtree heights.
        var heights: [String: CGFloat] = [:]
        measureHeight(root, nodeSize: nodeSize, rowGap: rowGap, into: &heights)

        // Pass 3: assign positions.
        var positions: [String: CGPoint] = [:]
        var depths: [String: Int] = [:]
        var edges: [MindMapEdge] = []
        assign(
            root, depth: 0, top: padding, branchIndex: -1,
            nodeSize: nodeSize, rowGap: rowGap,
            columnX: columnX, heights: heights,
            positions: &positions, depths: &depths, edges: &edges
        )

        let width = (columnX.last ?? padding) + (columnWidths.last ?? 0) / 2 + padding
        let height = (heights[root.id] ?? 0) + padding * 2
        return MindMapLayout(positions: positions, depths: depths, size: CGSize(width: width, height: height), edges: edges)
    }

    // MARK: - Passes

    private static func measureColumns(
        _ node: MindMapNode,
        depth: Int,
        nodeSize: (MindMapNode) -> CGSize,
        into widths: inout [CGFloat]
    ) {
        let width = nodeSize(node).width
        if depth >= widths.count {
            widths.append(width)
        } else {
            widths[depth] = max(widths[depth], width)
        }
        for child in node.children {
            measureColumns(child, depth: depth + 1, nodeSize: nodeSize, into: &widths)
        }
    }

    @discardableResult
    private static func measureHeight(
        _ node: MindMapNode,
        nodeSize: (MindMapNode) -> CGSize,
        rowGap: CGFloat,
        into heights: inout [String: CGFloat]
    ) -> CGFloat {
        let ownHeight = nodeSize(node).height
        guard !node.children.isEmpty else {
            heights[node.id] = ownHeight
            return ownHeight
        }
        var childrenHeight: CGFloat = 0
        for (index, child) in node.children.enumerated() {
            childrenHeight += measureHeight(child, nodeSize: nodeSize, rowGap: rowGap, into: &heights)
            if index < node.children.count - 1 { childrenHeight += rowGap }
        }
        let height = max(ownHeight, childrenHeight)
        heights[node.id] = height
        return height
    }

    private static func assign(
        _ node: MindMapNode,
        depth: Int,
        top: CGFloat,
        branchIndex: Int,
        nodeSize: (MindMapNode) -> CGSize,
        rowGap: CGFloat,
        columnX: [CGFloat],
        heights: [String: CGFloat],
        positions: inout [String: CGPoint],
        depths: inout [String: Int],
        edges: inout [MindMapEdge]
    ) {
        let bandHeight = heights[node.id] ?? nodeSize(node).height
        let center = CGPoint(
            x: columnX.indices.contains(depth) ? columnX[depth] : 0,
            y: top + bandHeight / 2
        )
        positions[node.id] = center
        depths[node.id] = depth

        var childTop = top + (bandHeight - childrenSpan(node, heights: heights, rowGap: rowGap)) / 2
        for (index, child) in node.children.enumerated() {
            let childBranchIndex = depth == 0 ? index : branchIndex
            let childHeight = heights[child.id] ?? nodeSize(child).height
            assign(
                child, depth: depth + 1, top: childTop, branchIndex: childBranchIndex,
                nodeSize: nodeSize, rowGap: rowGap,
                columnX: columnX, heights: heights,
                positions: &positions, depths: &depths, edges: &edges
            )
            let childCenter = positions[child.id] ?? .zero
            edges.append(MindMapEdge(
                id: "\(node.id)->\(child.id)",
                from: CGPoint(x: center.x + nodeSize(node).width / 2, y: center.y),
                to: CGPoint(x: childCenter.x - nodeSize(child).width / 2, y: childCenter.y),
                branchIndex: childBranchIndex,
                toActive: child.isActive
            ))
            childTop += childHeight + rowGap
        }
    }

    private static func childrenSpan(
        _ node: MindMapNode,
        heights: [String: CGFloat],
        rowGap: CGFloat
    ) -> CGFloat {
        guard !node.children.isEmpty else { return 0 }
        let total = node.children.reduce(CGFloat(0)) { $0 + (heights[$1.id] ?? 0) }
        return total + rowGap * CGFloat(node.children.count - 1)
    }
}
