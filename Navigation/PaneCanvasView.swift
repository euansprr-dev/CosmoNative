// CosmoOS/Navigation/PaneCanvasView.swift
// Lightweight canvas view for rendering thinkspace blocks inside split panes.
// Does NOT register NotificationCenter observers — avoids collision with main CanvasView.

import SwiftUI

struct PaneCanvasView: View {
    let thinkspaceId: String

    @StateObject private var spatialEngine = SpatialEngine()
    @StateObject private var frameTracker = CanvasBlockFrameTracker()

    // Canvas panning
    @State private var canvasOffset: CGSize = .zero
    @GestureState private var panOffset: CGSize = .zero

    // Canvas zoom
    @State private var canvasScale: CGFloat = 1.0
    @GestureState private var magnificationState: CGFloat = 1.0
    private let minScale: CGFloat = 0.3
    private let maxScale: CGFloat = 3.0

    // Block selection and drag
    @State private var selectedBlockId: String?
    @State private var blockDragOffsets: [String: CGSize] = [:]
    @State private var draggingBlockId: String?

    // MARK: - Computed Properties

    private var effectiveScale: CGFloat {
        let gestureScale = canvasScale * magnificationState
        return min(max(gestureScale, minScale), maxScale)
    }

    private var scaledPanOffset: CGSize {
        CGSize(
            width: panOffset.width / effectiveScale,
            height: panOffset.height / effectiveScale
        )
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let screenCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                // Background + pan/zoom gesture capture
                canvasBackground

                // Blocks container — scaled as a unit around screen center
                ZStack {
                    blocksLayer(screenCenter: screenCenter)
                }
                .scaleEffect(effectiveScale, anchor: UnitPoint(
                    x: screenCenter.x / max(geo.size.width, 1),
                    y: screenCenter.y / max(geo.size.height, 1)
                ))
            }
            .overlay(alignment: .bottomTrailing) {
                zoomIndicator
            }
        }
        .task {
            await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
        }
    }

    // MARK: - Canvas Background

    private var canvasBackground: some View {
        ZStack {
            // Visual layers (GPU accelerated)
            ZStack {
                CosmoColors.thinkspaceVoid
                    .ignoresSafeArea()

                GridPatternView(
                    offset: CGSize(
                        width: canvasOffset.width + scaledPanOffset.width,
                        height: canvasOffset.height + scaledPanOffset.height
                    ),
                    scale: effectiveScale
                )
                .ignoresSafeArea()
            }
            .drawingGroup()

            // Transparent hit area for pan/zoom gestures
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    deselectAll()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .updating($panOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            canvasOffset.width += value.translation.width / effectiveScale
                            canvasOffset.height += value.translation.height / effectiveScale
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .updating($magnificationState) { value, state, _ in
                            state = value.magnification
                        }
                        .onEnded { value in
                            let newScale = canvasScale * value.magnification
                            canvasScale = min(max(newScale, minScale), maxScale)
                        }
                )
        }
    }

    // MARK: - Blocks Layer

    @ViewBuilder
    private func blocksLayer(screenCenter: CGPoint) -> some View {
        ForEach(spatialEngine.blocks) { block in
            blockView(for: block)
                .position(
                    x: block.position.x + canvasOffset.width + scaledPanOffset.width + (blockDragOffsets[block.id]?.width ?? 0),
                    y: block.position.y + canvasOffset.height + scaledPanOffset.height + (blockDragOffsets[block.id]?.height ?? 0)
                )
                .scaleEffect(block.scale)
                .zIndex(draggingBlockId == block.id ? 1000 : Double(block.zIndex))
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { gesture in
                            blockDragOffsets[block.id] = gesture.translation
                            draggingBlockId = block.id
                            if selectedBlockId != block.id {
                                selectedBlockId = block.id
                            }
                        }
                        .onEnded { gesture in
                            commitDrag(blockId: block.id, translation: gesture.translation)
                        }
                )
                .onTapGesture(count: 2) {
                    if [.idea, .content, .research, .connection, .cosmoAI].contains(block.entityType) {
                        NotificationCenter.default.post(
                            name: .enterFocusMode,
                            object: nil,
                            userInfo: ["type": block.entityType, "id": block.entityId]
                        )
                    }
                }
                .onTapGesture(count: 1) {
                    selectBlock(block.id)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            selectedBlockId == block.id
                                ? CosmoColors.thinkspacePurple.opacity(0.6)
                                : Color.clear,
                            lineWidth: 2
                        )
                        .allowsHitTesting(false)
                )
        }
    }

    // MARK: - Block View Router

    @ViewBuilder
    private func blockView(for block: CanvasBlock) -> some View {
        switch block.entityType {
        case .cosmoAI:
            CosmoAIBlockView(block: block)
        case .note:
            NoteBlockView(block: block)
        case .research:
            if hasMediaContent(block) {
                MediaBlockView(block: block)
            } else {
                ResearchBlockView(block: block)
            }
        case .connection:
            ConnectionBlockView(block: block)
        case .idea:
            IdeaBlockView(block: block)
        case .content:
            ContentBlockView(block: block)
        case .task:
            TaskBlockView(block: block)
        default:
            placeholderBlock(for: block)
        }
    }

    private func hasMediaContent(_ block: CanvasBlock) -> Bool {
        let url = (block.metadata["url"] ?? "").lowercased()
        return url.contains("youtube") || url.contains("youtu.be") ||
               url.contains("instagram") || url.contains("tiktok") ||
               block.metadata["isSwipeFile"] == "true"
    }

    @ViewBuilder
    private func placeholderBlock(for block: CanvasBlock) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(CosmoColors.glassGrey.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(CosmoColors.glassGrey.opacity(0.3), lineWidth: 1)
            )
            .overlay(
                Text(block.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
                    .padding(12)
            )
            .frame(width: block.size.width, height: block.size.height)
    }

    // MARK: - Zoom Indicator

    private var zoomIndicator: some View {
        Text("\(Int(effectiveScale * 100))%")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
            )
            .padding(12)
            .opacity(effectiveScale == 1.0 ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: effectiveScale)
    }

    // MARK: - Actions

    private func selectBlock(_ blockId: String) {
        var updatedBlocks = spatialEngine.blocks
        for index in updatedBlocks.indices {
            updatedBlocks[index].isSelected = (updatedBlocks[index].id == blockId)
        }
        spatialEngine.blocks = updatedBlocks
        selectedBlockId = blockId
    }

    private func deselectAll() {
        var updatedBlocks = spatialEngine.blocks
        for index in updatedBlocks.indices {
            updatedBlocks[index].isSelected = false
        }
        spatialEngine.blocks = updatedBlocks
        selectedBlockId = nil
    }

    private func commitDrag(blockId: String, translation: CGSize) {
        if let index = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) {
            let newPosition = CGPoint(
                x: spatialEngine.blocks[index].position.x + translation.width,
                y: spatialEngine.blocks[index].position.y + translation.height
            )
            spatialEngine.blocks[index].position = newPosition
            spatialEngine.updateBlockPosition(blockId, position: newPosition)
        }

        blockDragOffsets.removeValue(forKey: blockId)
        draggingBlockId = nil
    }
}
