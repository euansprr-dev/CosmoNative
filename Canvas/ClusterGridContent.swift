// CosmoOS/Canvas/ClusterGridContent.swift
// Grid mode rendering for clusters — 4-column layout of full block views

import SwiftUI

struct ClusterGridContent: View {

    let cluster: CanvasCluster
    let clusterColor: Color
    let blocks: [CanvasBlock]
    let onOpenFocusMode: (String) -> Void

    @StateObject private var expansionManager = BlockExpansionManager()

    private let columnCount = 4
    private let gridSpacing: CGFloat = 12
    private let gridPadding: CGFloat = 12

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
                }
            }
            .padding(gridPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(expansionManager)
    }

    // MARK: - Block View Dispatch

    @ViewBuilder
    private func gridBlockView(for block: CanvasBlock) -> some View {
        let blockView = blockContent(for: block)
            .frame(width: block.defaultSize.width, height: block.defaultSize.height)
            .allowsHitTesting(false)

        GeometryReader { geo in
            let cellWidth = geo.size.width
            let scale = min(cellWidth / block.defaultSize.width, 1.0)
            let scaledHeight = block.defaultSize.height * scale

            blockView
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: cellWidth, height: scaledHeight, alignment: .topLeading)
        }
        .aspectRatio(
            block.defaultSize.width / block.defaultSize.height,
            contentMode: .fit
        )
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
        default:
            FloatingBlockView(block: block)
        }
    }

    // MARK: - Data

    private var memberBlocks: [CanvasBlock] {
        let uuids = Set(cluster.blockUUIDs)
        return blocks.filter { uuids.contains($0.entityUuid) }
    }
}
