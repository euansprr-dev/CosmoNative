// CosmoOS/Canvas/ClusterGridContent.swift
// Grid mode rendering for clusters — 3-column layout of full block views
// March 2026: Added drag-and-drop between clusters

import SwiftUI

// MARK: - Cluster Transfer Event

/// Represents a block being moved from one cluster to another via drag-and-drop.
struct ClusterTransferEvent {
    let blockUUID: String
    let targetClusterId: UUID
}

// MARK: - Grid Content

struct ClusterGridContent: View {

    let cluster: CanvasCluster
    let clusterColor: Color
    let blocks: [CanvasBlock]
    let isDropTargeted: Bool
    let onOpenFocusMode: (String) -> Void

    private let columnCount = 3
    private let gridSpacing: CGFloat = 10
    private let gridPadding: CGFloat = 10

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columnCount)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: gridColumns, alignment: .center, spacing: gridSpacing) {
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
            .padding(gridPadding)
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
            .aspectRatio(Self.gridAspectRatio, contentMode: .fit)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(clusterColor.opacity(0.5))
                    Text("Drop here")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(clusterColor.opacity(0.5))
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(ProMotionSprings.snappy, value: isDropTargeted)
    }

    // MARK: - Block View Dispatch

    /// Uniform aspect ratio used for every cell so the grid looks consistent.
    private static let gridAspectRatio: CGFloat = 4.0 / 3.5

    @ViewBuilder
    private func gridBlockView(for block: CanvasBlock) -> some View {
        GeometryReader { geo in
            let cellWidth = geo.size.width
            let cellHeight = geo.size.height

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
        .aspectRatio(Self.gridAspectRatio, contentMode: .fit)
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
        let uuids = Set(cluster.blockUUIDs)
        return blocks.filter { uuids.contains($0.entityUuid) }
    }

    private func dragProvider(for block: CanvasBlock) -> NSItemProvider {
        ClusterViewDragSession.sourceClusterId = cluster.id
        return NSItemProvider(object: block.entityUuid as NSString)
    }
}
