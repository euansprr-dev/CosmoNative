// CosmoOS/Canvas/ClusterGridContent.swift
// Grid mode rendering for clusters — masonry layout with fixed-width columns
// March 2026: Added drag-and-drop between clusters
// March 2026: Masonry layout with type-specific cell heights

import SwiftUI

// MARK: - Cluster Transfer Event

/// Represents a block being moved from one cluster to another via drag-and-drop.
struct ClusterTransferEvent {
    let blockUUID: String
    let targetClusterId: UUID
}

// MARK: - Masonry Layout

/// Packed grid layout: each cell keeps its natural width and rows wrap with
/// a small gap, avoiding invisible column spans around document-style blocks.
struct ClusterMasonryLayout: Layout {
    let columnWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let availableWidth = resolvedWidth(proposal.width, sizes: sizes)
        let placements = placements(for: sizes, availableWidth: availableWidth)

        // Return the full proposed width so the layout fills available space
        return CGSize(width: availableWidth, height: placements.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let placements = placements(for: sizes, availableWidth: bounds.width)

        for (index, subview) in subviews.enumerated() {
            let placement = placements.items[index]
            subview.place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                anchor: .topLeading,
                proposal: .init(width: placement.size.width, height: placement.size.height)
            )
        }
    }

    private struct Placement {
        let origin: CGPoint
        let size: CGSize
    }

    private func resolvedWidth(_ proposedWidth: CGFloat?, sizes: [CGSize]) -> CGFloat {
        max(proposedWidth ?? columnWidth, sizes.map(\.width).max() ?? columnWidth)
    }

    private func placements(for sizes: [CGSize], availableWidth: CGFloat) -> (items: [Placement], height: CGFloat) {
        var items: [Placement] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        let rowWidth = max(availableWidth, sizes.map(\.width).max() ?? columnWidth)

        for size in sizes {
            if cursor.x > 0, cursor.x + size.width > rowWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }

            items.append(Placement(origin: cursor, size: size))
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (items, items.isEmpty ? 0 : cursor.y + rowHeight)
    }
}

// MARK: - Grid Content

struct ClusterGridContent: View {

    let cluster: CanvasCluster
    let clusterColor: Color
    let blocks: [CanvasBlock]
    let isDropTargeted: Bool
    let onOpenFocusMode: (String) -> Void

    /// Fixed column width for all grid cells
    private static let masonryColumnWidth: CGFloat = 220
    private static let masonrySpacing: CGFloat = 10

    /// Minimum cell height to ensure readability
    private static let minCellHeight: CGFloat = 120

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ClusterMasonryLayout(columnWidth: Self.masonryColumnWidth, spacing: Self.masonrySpacing) {
                ForEach(memberBlocks, id: \.id) { block in
                    gridBlockView(for: block)
                        .onTapGesture(count: 2) {
                            onOpenFocusMode(block.entityUuid)
                        }
                        .onDrag { dragProvider(for: block) }
                }

                // Drop placeholder
                if isDropTargeted {
                    dropPlaceholder
                }
            }
            .padding(Self.masonrySpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Drop Placeholder

    private var dropPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(
                clusterColor.opacity(0.5),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(clusterColor.opacity(0.06))
            )
            .frame(width: Self.masonryColumnWidth, height: 200)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(clusterColor.opacity(0.5))
                    Text("Drop here")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(clusterColor.opacity(0.5))
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(ProMotionSprings.snappy, value: isDropTargeted)
    }

    // MARK: - Block View Dispatch

    /// Compute grid cell height from the block's canonical default size so that
    /// all blocks of the same type get identical heights regardless of canvas resizing.
    /// Research blocks use media-type-aware sizing for correct aspect ratios.
    private func gridCellHeight(for block: CanvasBlock) -> CGFloat {
        Self.canonicalCellHeight(for: block)
    }

    /// Canonical cell height for a block in the masonry grid.
    /// Static so it can be reused by `estimatedGridHeight` without a view instance.
    static func canonicalCellHeight(for block: CanvasBlock) -> CGFloat {
        let ref: CGSize
        if block.entityType == .research,
           let url = block.metadata["url"], !url.isEmpty {
            let mediaType = CanvasBlock.detectMediaTypeFromURL(url)
            switch mediaType {
            case .reel:     ref = CGSize(width: 220, height: 420)
            case .youtube:  ref = CGSize(width: 320, height: 230)
            case .carousel: ref = CGSize(width: 300, height: 350)
            case .generic:  ref = block.defaultSize
            }
        } else {
            ref = block.defaultSize
        }
        guard ref.width > 0 else { return minCellHeight }
        let width = canonicalCellWidth(for: block)
        let scale = width / ref.width
        return max(minCellHeight, ref.height * scale)
    }

    static func canonicalCellWidth(for block: CanvasBlock) -> CGFloat {
        switch block.entityType {
        case .note, .content:
            return CanvasBlock.documentBlockSize.width
        default:
            return masonryColumnWidth
        }
    }

    /// Estimate the total masonry layout height for a set of blocks without rendering.
    /// Used by `CanvasClusterEngine.fitClusterRectForMode` for accurate adaptive sizing.
    static func estimatedGridHeight(blocks: [CanvasBlock], availableWidth: CGFloat) -> CGFloat {
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        let maxCellWidth = blocks.map { canonicalCellWidth(for: $0) }.max() ?? masonryColumnWidth
        let rowWidth = max(availableWidth, maxCellWidth)

        for block in blocks {
            let cellWidth = canonicalCellWidth(for: block)
            let cellHeight = canonicalCellHeight(for: block)

            if cursorX > 0, cursorX + cellWidth > rowWidth {
                cursorX = 0
                cursorY += rowHeight + masonrySpacing
                rowHeight = 0
            }

            cursorX += cellWidth + masonrySpacing
            rowHeight = max(rowHeight, cellHeight)
        }

        return blocks.isEmpty ? 0 : cursorY + rowHeight
    }

    static func orderedMemberBlocks(for cluster: CanvasCluster, blocks: [CanvasBlock]) -> [CanvasBlock] {
        let blocksByUUID = Dictionary(blocks.map { ($0.entityUuid, $0) }, uniquingKeysWith: { first, _ in first })
        return cluster.blockUUIDs.compactMap { blocksByUUID[$0] }
    }

    @ViewBuilder
    private func gridBlockView(for block: CanvasBlock) -> some View {
        let cellHeight = gridCellHeight(for: block)
        let cellWidth = Self.canonicalCellWidth(for: block)

        // Pass a block copy whose size matches the cell so
        // CosmoBlockWrapper lays content out at the cell dimensions
        // instead of pixel-scaling from the original size.
        let gridBlock: CanvasBlock = {
            var b = block
            b.size = CGSize(width: cellWidth, height: cellHeight)
            b.isSelected = false
            return b
        }()

        blockContent(for: gridBlock)
            .frame(width: cellWidth, height: cellHeight)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
    }

    @ViewBuilder
    private func blockContent(for block: CanvasBlock) -> some View {
        switch block.entityType {
        case .cosmoAI:
            CosmoAIBlockView(block: block)
        case .note:
            NoteBlockView(block: block)
        case .research:
            ResearchBlockView(block: block)
        case .connection:
            ConnectionBlockView(block: block)
        case .idea:
            IdeaBlockView(block: block)
        case .content:
            ContentBlockView(block: block)
        case .task:
            TaskBlockView(block: block)
        case .stickyNote:
            StickyNoteBlockView(block: block)
        default:
            FloatingBlockView(block: block)
        }
    }

    // MARK: - Data

    private var memberBlocks: [CanvasBlock] {
        Self.orderedMemberBlocks(for: cluster, blocks: blocks)
    }

    private func dragProvider(for block: CanvasBlock) -> NSItemProvider {
        ClusterViewDragSession.sourceClusterId = cluster.id
        return NSItemProvider(object: block.entityUuid as NSString)
    }
}
