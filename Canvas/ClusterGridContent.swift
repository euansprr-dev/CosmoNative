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

// MARK: - Grid Hydration Policy

/// Cluster grids used to mount EVERY member card eagerly — a 30-document
/// cluster sized to show two cards still typeset all 30 inside the
/// thinkspace-swap frame (the masonry `Layout` + ScrollView pair has no
/// laziness). Hydration renders real cards only near the visible band and
/// fills the rest in background waves shortly after mount, so scrolling
/// never reveals a placeholder and the fully-loaded steady state still
/// arrives within ~a second.
///
/// This is safe against layout shift by construction: masonry cell sizes are
/// CANONICAL (pure functions of block type — see `canonicalCellHeight`), so
/// a placeholder occupies exactly the frame its card will.
enum ClusterGridHydrationPolicy {
    /// Cells within this distance of the visible band render real content.
    static let preloadMargin: CGFloat = 900
    /// Scroll updates are bucketed to this granularity so tracking the band
    /// costs a handful of state writes per viewport of scrolling, never one
    /// per frame (the cortex-scroll law).
    static let bandQuantum: CGFloat = 240
    /// Before the first scroll geometry arrives, hydrate this many leading
    /// cells — covers any plausible visible arrangement at mount.
    static let initialHydrationCount = 8
    /// Background waves: let the switch entry animation settle, then mount
    /// the remainder a few cards per beat, top-to-bottom.
    static let waveDelay: Duration = .milliseconds(600)
    static let waveInterval: Duration = .milliseconds(120)
    static let waveSize = 5

    static func quantizedBand(minY: CGFloat, maxY: CGFloat) -> ClosedRange<CGFloat> {
        let lower = (minY / bandQuantum).rounded(.down) * bandQuantum
        let upper = (maxY / bandQuantum).rounded(.up) * bandQuantum
        return lower...max(lower, upper)
    }

    static func isNearBand(cellFrame: CGRect, band: ClosedRange<CGFloat>) -> Bool {
        cellFrame.maxY > band.lowerBound - preloadMargin
            && cellFrame.minY < band.upperBound + preloadMargin
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

    private struct ScrollBand: Equatable {
        let band: ClosedRange<CGFloat>
        let contentWidth: CGFloat
    }

    /// Monotonic: cells hydrate (scroll proximity or background wave) and
    /// never de-hydrate — scrolling back up must not churn view teardown.
    @State private var hydratedBlockIds: Set<String> = []
    @State private var visibleBand: ClosedRange<CGFloat> = 0...0
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        let members = memberBlocks
        let cellFrames = Self.cellFrames(
            blocks: members,
            availableWidth: max(contentWidth - Self.masonrySpacing * 2, Self.masonryColumnWidth)
        )
        ScrollView(.vertical, showsIndicators: false) {
            masonryGrid(members: members, cellFrames: cellFrames)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onScrollGeometryChange(for: ScrollBand.self, of: { geometry in
            // Quantized INSIDE the transform: identical buckets mean the
            // action (and its state writes) never runs per scroll frame.
            ScrollBand(
                band: ClusterGridHydrationPolicy.quantizedBand(
                    minY: geometry.visibleRect.minY,
                    maxY: geometry.visibleRect.maxY
                ),
                contentWidth: geometry.containerSize.width
            )
        }) { _, newValue in
            visibleBand = newValue.band
            contentWidth = newValue.contentWidth
            hydrateCellsNearBand()
        }
        .task(id: cluster.blockUUIDs) {
            await runHydrationWaves()
        }
    }

    private func masonryGrid(members: [CanvasBlock], cellFrames: [CGRect]) -> some View {
        ClusterMasonryLayout(columnWidth: Self.masonryColumnWidth, spacing: Self.masonrySpacing) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, block in
                gridBlockView(
                    for: block,
                    hydrated: isHydrated(block: block, index: index, cellFrames: cellFrames)
                )
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

    // MARK: - Hydration

    private func isHydrated(block: CanvasBlock, index: Int, cellFrames: [CGRect]) -> Bool {
        if hydratedBlockIds.contains(block.id) { return true }
        // Before the first scroll geometry lands, frames are width-guessed —
        // hydrate by position in the masonry order instead.
        guard contentWidth > 0 else { return index < ClusterGridHydrationPolicy.initialHydrationCount }
        guard index < cellFrames.count else { return true }
        return ClusterGridHydrationPolicy.isNearBand(cellFrame: cellFrames[index], band: visibleBand)
    }

    /// Fold band-covered cells into the monotonic hydrated set so scrolling
    /// away never unmounts them.
    private func hydrateCellsNearBand() {
        let members = memberBlocks
        let cellFrames = Self.cellFrames(
            blocks: members,
            availableWidth: max(contentWidth - Self.masonrySpacing * 2, Self.masonryColumnWidth)
        )
        for (index, block) in members.enumerated() where index < cellFrames.count {
            if ClusterGridHydrationPolicy.isNearBand(cellFrame: cellFrames[index], band: visibleBand) {
                hydratedBlockIds.insert(block.id)
            }
        }
    }

    /// Background hydration: after the switch/cluster entry settles, mount
    /// the remaining cards a few per beat in masonry order, so the cluster
    /// reaches its fully-loaded steady state without a single-frame burst.
    private func runHydrationWaves() async {
        try? await Task.sleep(for: ClusterGridHydrationPolicy.waveDelay)
        while !Task.isCancelled {
            let pending = memberBlocks.map(\.id).filter { !hydratedBlockIds.contains($0) }
            guard !pending.isEmpty else { return }
            hydratedBlockIds.formUnion(pending.prefix(ClusterGridHydrationPolicy.waveSize))
            try? await Task.sleep(for: ClusterGridHydrationPolicy.waveInterval)
        }
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
        cellFrames(blocks: blocks, availableWidth: availableWidth)
            .map(\.maxY)
            .max() ?? 0
    }

    /// Deterministic masonry cell frames from CANONICAL sizes — the same
    /// greedy row-packing `ClusterMasonryLayout` performs, but computable
    /// without a view (hydration decides per-cell visibility from these, and
    /// they match the real layout because every grid cell is framed to its
    /// canonical size before measurement).
    static func cellFrames(blocks: [CanvasBlock], availableWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        frames.reserveCapacity(blocks.count)
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

            frames.append(CGRect(x: cursorX, y: cursorY, width: cellWidth, height: cellHeight))
            cursorX += cellWidth + masonrySpacing
            rowHeight = max(rowHeight, cellHeight)
        }

        return frames
    }

    static func orderedMemberBlocks(for cluster: CanvasCluster, blocks: [CanvasBlock]) -> [CanvasBlock] {
        let blocksByUUID = Dictionary(blocks.map { ($0.entityUuid, $0) }, uniquingKeysWith: { first, _ in first })
        return cluster.blockUUIDs.compactMap { blocksByUUID[$0] }
    }

    @ViewBuilder
    private func gridBlockView(for block: CanvasBlock, hydrated: Bool) -> some View {
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

        Group {
            if hydrated {
                blockContent(for: gridBlock)
            } else {
                // Layout-identical stand-in for cells far below the fold —
                // a quiet card back, replaced by the real card before the
                // user can scroll to it (proximity margin + hydration waves).
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(DS.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusMedium)
                            .strokeBorder(clusterColor.opacity(0.10), lineWidth: 1)
                    )
            }
        }
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
