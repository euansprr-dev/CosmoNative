// CosmoOS/Canvas/ClusterGridContent.swift
// Grid mode rendering for clusters — 4-column layout of full block views
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
    let onOpenFocusMode: (String) -> Void
    var onDrop: ((ClusterTransferEvent) -> Void)?

    @StateObject private var expansionManager = BlockExpansionManager()
    @State private var isDropTargeted = false

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
                        .onDrag { NSItemProvider(object: block.entityUuid as NSString) }
                }

                // Drop placeholder
                if isDropTargeted {
                    dropPlaceholder
                }
            }
            .padding(gridPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(expansionManager)
        .onDrop(
            of: [.text],
            delegate: ClusterGridDropDelegate(
                targetClusterId: cluster.id,
                isDropTargeted: $isDropTargeted,
                onDrop: onDrop
            )
        )
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
            .aspectRatio(320.0 / 340.0, contentMode: .fit)
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

    @ViewBuilder
    private func gridBlockView(for block: CanvasBlock) -> some View {
        let blockView = blockContent(for: block)
            .frame(width: block.defaultSize.width, height: block.defaultSize.height)

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

// MARK: - Grid Drop Delegate

private struct ClusterGridDropDelegate: DropDelegate {
    let targetClusterId: UUID
    @Binding var isDropTargeted: Bool
    let onDrop: ((ClusterTransferEvent) -> Void)?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        withAnimation(ProMotionSprings.snappy) {
            isDropTargeted = true
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(ProMotionSprings.snappy) {
            isDropTargeted = false
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(ProMotionSprings.snappy) {
            isDropTargeted = false
        }
        let providers = info.itemProviders(for: [.text])
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.text", options: nil) { item, _ in
                let blockUUID: String?
                if let data = item as? Data {
                    blockUUID = String(data: data, encoding: .utf8)
                } else if let text = item as? String {
                    blockUUID = text
                } else if let text = item as? NSString {
                    blockUUID = text as String
                } else {
                    blockUUID = nil
                }
                guard let blockUUID else { return }
                DispatchQueue.main.async {
                    onDrop?(ClusterTransferEvent(
                        blockUUID: blockUUID,
                        targetClusterId: targetClusterId
                    ))
                }
            }
        }
        return true
    }
}
