// CosmoOS/Navigation/PaneCanvasView.swift
// Lightweight canvas view for rendering thinkspace blocks inside split panes.
// Does NOT register NotificationCenter observers — avoids collision with main CanvasView.

import SwiftUI
import AppKit

struct PaneCanvasView: View {
    let thinkspaceId: String

    @StateObject private var spatialEngine = SpatialEngine()
    @StateObject private var clusterEngine = CanvasClusterEngine()
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

    // Space+drag pan (hand tool)
    @State private var keyMonitor: Any?
    @State private var isSpaceHeld = false
    @State private var spacePanOffset: CGSize = .zero

    // MARK: - Computed Properties

    private var effectiveScale: CGFloat {
        let gestureScale = canvasScale * magnificationState
        return min(max(gestureScale, minScale), maxScale)
    }

    private var scaledPanOffset: CGSize {
        let combinedPan = CGSize(
            width: panOffset.width + spacePanOffset.width,
            height: panOffset.height + spacePanOffset.height
        )
        return CGSize(
            width: combinedPan.width / effectiveScale,
            height: combinedPan.height / effectiveScale
        )
    }

    /// Blocks consumed by clusters in list/board/grid mode (rendered inside cluster, not individually)
    private var clusterConsumedBlockUUIDs: Set<String> {
        var s = Set<String>()
        for c in clusterEngine.userClusters where c.viewMode != .canvas {
            s.formUnion(c.blockUUIDs)
        }
        return s
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
                    // Cluster zones (behind blocks)
                    CanvasClusterLayer(
                        clusters: clusterEngine.allClusters,
                        blocks: spatialEngine.blocks,
                        canvasSize: geo.size,
                        canvasOffset: canvasOffset,
                        scaledPanOffset: scaledPanOffset,
                        effectiveScale: effectiveScale,
                        onOpenFocusMode: { uuid in
                            if let block = spatialEngine.blocks.first(where: { $0.entityUuid == uuid }),
                               block.entityId > 0 {
                                NotificationCenter.default.post(
                                    name: .enterFocusMode,
                                    object: nil,
                                    userInfo: ["type": block.entityType, "id": block.entityId]
                                )
                            }
                        }
                    )

                    blocksLayer(screenCenter: screenCenter)
                }
                .scaleEffect(effectiveScale, anchor: UnitPoint(
                    x: screenCenter.x / max(geo.size.width, 1),
                    y: screenCenter.y / max(geo.size.height, 1)
                ))

                // Space+drag pan overlay (hand tool)
                if isSpaceHeld {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    spacePanOffset = value.translation
                                }
                                .onEnded { value in
                                    canvasOffset.width += value.translation.width / effectiveScale
                                    canvasOffset.height += value.translation.height / effectiveScale
                                    spacePanOffset = .zero
                                }
                        )
                        .onAppear { NSCursor.openHand.push() }
                        .onDisappear {
                            NSCursor.pop()
                            spacePanOffset = .zero
                        }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                zoomIndicator
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [self] event in
                if event.keyCode == 49 { // space bar
                    let pressed = event.type == .keyDown
                    if pressed != isSpaceHeld {
                        isSpaceHeld = pressed
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            isSpaceHeld = false
        }
        .task {
            await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
            await clusterEngine.loadUserClusters(
                thinkspaceId: thinkspaceId,
                blocks: spatialEngine.blocks
            )
            clusterEngine.scheduleRecompute(blocks: spatialEngine.blocks)
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
                    transform: CanvasViewportTransform(
                        viewportSize: .zero,
                        committedOffset: canvasOffset,
                        gesturePanOffset: panOffset,
                        committedScale: canvasScale,
                        gestureMagnification: magnificationState,
                        minScale: minScale,
                        maxScale: maxScale
                    )
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
        ForEach(spatialEngine.blocks.filter { !clusterConsumedBlockUUIDs.contains($0.entityUuid) }, id: \.id) { block in
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
            .fill(DS.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DS.border, lineWidth: 1)
            )
            .overlay(
                Text(block.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(2)
                    .padding(12)
            )
            .frame(width: block.size.width, height: block.size.height)
            .dsRestingShadow()
    }

    // MARK: - Zoom Indicator

    private var zoomIndicator: some View {
        Text("\(Int(effectiveScale * 100))%")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(DS.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(DS.surfaceElevated)
                    .overlay(Capsule().stroke(DS.border, lineWidth: 1))
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
