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
    @State private var hasInitializedViewport = false

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

    // Right-click radial menu
    @State private var showRadialMenu = false
    @State private var radialMenuPosition: CGPoint = .zero
    @State private var rightClickMonitor: Any?
    @State private var paneFrame: CGRect = .zero
    @State private var paneSize: CGSize = .zero

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

    private var paneViewportTransform: CanvasViewportTransform {
        CanvasViewportTransform(
            viewportSize: paneSize,
            committedOffset: canvasOffset,
            gesturePanOffset: CGSize(
                width: panOffset.width + spacePanOffset.width,
                height: panOffset.height + spacePanOffset.height
            ),
            committedScale: canvasScale,
            gestureMagnification: magnificationState,
            minScale: minScale,
            maxScale: maxScale
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
            let viewportTransform = CanvasViewportTransform(
                viewportSize: geo.size,
                committedOffset: canvasOffset,
                gesturePanOffset: CGSize(
                    width: panOffset.width + spacePanOffset.width,
                    height: panOffset.height + spacePanOffset.height
                ),
                committedScale: canvasScale,
                gestureMagnification: magnificationState,
                minScale: minScale,
                maxScale: maxScale
            )
            let compositorTransform = CanvasCompositorTransform(viewportTransform: viewportTransform)

            ZStack {
                // Background + pan/zoom gesture capture
                canvasBackground(transform: viewportTransform)

                // Blocks container — offset and scaled as a single canvas world.
                ZStack {
                    // Cluster zones (behind blocks)
                    CanvasClusterLayer(
                        clusters: clusterEngine.allClusters,
                        blocks: spatialEngine.blocks,
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

                    blocksLayer
                }
                .offset(
                    x: compositorTransform.contentOffset.width,
                    y: compositorTransform.contentOffset.height
                )
                .scaleEffect(compositorTransform.effectiveScale, anchor: compositorTransform.anchor)

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

                // Radial menu overlay
                if showRadialMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.2)) {
                                showRadialMenu = false
                            }
                        }

                    RadialMenuView(
                        position: radialMenuPosition,
                        onSelect: { action in
                            handleRadialAction(action)
                            withAnimation(.spring(response: 0.2)) {
                                showRadialMenu = false
                            }
                        },
                        onDismiss: {
                            withAnimation(.spring(response: 0.2)) {
                                showRadialMenu = false
                            }
                        }
                    )
                    .zIndex(500)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                zoomIndicator
            }
            .task(id: thinkspaceId) {
                await loadPaneThinkspace(in: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                paneSize = newSize
                guard !hasInitializedViewport, hasRenderableContent else { return }
                applyInitialViewport(in: newSize)
            }
            .onAppear {
                paneSize = geo.size
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { paneFrame = geo.frame(in: .global) }
                    .onChange(of: geo.size) { _, _ in paneFrame = geo.frame(in: .global) }
            }
        )
        .onAppear {
            setupKeyMonitor()
            setupRightClickMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
            removeRightClickMonitor()
        }
    }

    // MARK: - Event Monitors

    private func setupKeyMonitor() {
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

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        isSpaceHeld = false
    }

    private func setupRightClickMonitor() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard let window = event.window else { return event }

            let windowPoint = event.locationInWindow
            let windowHeight = window.frame.height

            // Convert to SwiftUI coordinates (flip Y)
            let screenPoint = CGPoint(
                x: windowPoint.x,
                y: windowHeight - windowPoint.y
            )

            // Check if click is within this pane's frame (global coordinates)
            // paneFrame uses SwiftUI's .global coordinate space (origin at top-left)
            guard paneFrame.width > 0, paneFrame.height > 0 else { return event }

            // Convert pane frame from SwiftUI global to window coordinates
            // SwiftUI .global has origin at top-left of window content area
            let inPane = screenPoint.x >= paneFrame.minX
                && screenPoint.x <= paneFrame.maxX
                && screenPoint.y >= paneFrame.minY
                && screenPoint.y <= paneFrame.maxY

            guard inPane else { return event }

            // Convert to pane-local coordinates for menu positioning
            let paneLocalPoint = CGPoint(
                x: screenPoint.x - paneFrame.minX,
                y: screenPoint.y - paneFrame.minY
            )

            radialMenuPosition = paneLocalPoint
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                showRadialMenu = true
            }

            return nil // Consume the event
        }
    }

    private func removeRightClickMonitor() {
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickMonitor = nil
        }
    }

    // MARK: - Radial Menu Actions

    private func handleRadialAction(_ action: RadialAction) {
        let canvasPosition = paneViewportTransform.screenToCanvas(radialMenuPosition)

        switch action.type {
        case .createNote:
            createNoteBlock(at: canvasPosition)
        case .createStickyNote:
            createStickyNoteBlock(at: canvasPosition)
        case .createContent:
            createEntityBlock(type: .content, at: canvasPosition)
        case .createIdea:
            createEntityBlock(type: .idea, at: canvasPosition)
        case .createConnection:
            createEntityBlock(type: .connection, at: canvasPosition)
        case .createResearch:
            createEntityBlock(type: .research, at: canvasPosition)
        case .createTask:
            createEntityBlock(type: .task, at: canvasPosition)
        case .createDeepDive:
            createEntityBlock(type: .deepDive, at: canvasPosition)
        default:
            break
        }
    }

    // MARK: - Block Creation

    private func createNoteBlock(at position: CGPoint) {
        Task { @MainActor in
            do {
                let createdAtom = try await AtomRepository.shared.create(type: .note)
                let block = CanvasBlock.fromAtom(createdAtom, position: position)
                await spatialEngine.addBlock(block, persist: true)
            } catch {
                // Fallback without DB
                let block = CanvasBlock.noteBlock(position: position)
                await spatialEngine.addBlock(block, persist: true)
            }
        }
    }

    private func createStickyNoteBlock(at position: CGPoint) {
        Task { @MainActor in
            let block = CanvasBlock.stickyNoteBlock(position: position)
            await spatialEngine.addBlock(block, persist: true)
        }
    }

    private func createEntityBlock(type: EntityType, at position: CGPoint) {
        Task { @MainActor in
            do {
                if type == .deepDive {
                    let deepDive = try await InquiryRepository.shared.createDeepDive(title: "New Deep Dive")
                    let block = CanvasBlock.fromAtom(deepDive, position: position)
                    await spatialEngine.addBlock(block, persist: true)
                    return
                }

                let atomType: AtomType = {
                    switch type {
                    case .idea: return .idea
                    case .content: return .content
                    case .connection: return .connection
                    case .research: return .research
                    case .task: return .task
                    default: return .note
                    }
                }()

                let newAtom = Atom.new(type: atomType)
                let atomId = try await CosmoDatabase.shared.asyncWrite { db -> Int64 in
                    var mutableAtom = newAtom
                    try mutableAtom.insert(db)
                    return db.lastInsertedRowID
                }

                var createdAtom = newAtom
                createdAtom.id = atomId
                let block = CanvasBlock.fromAtom(createdAtom, position: position)
                await spatialEngine.addBlock(block, persist: true)
            } catch {
                print("❌ PaneCanvasView: Failed to create \(type) block: \(error)")
            }
        }
    }

    // MARK: - Canvas Background

    private func canvasBackground(transform: CanvasViewportTransform) -> some View {
        ZStack {
            // Visual layers (GPU accelerated)
            ZStack {
                CosmoColors.thinkspaceVoid
                    .ignoresSafeArea()
            }
            .drawingGroup()

            GridPatternView(transform: transform)
                .ignoresSafeArea()

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

    private var hasRenderableContent: Bool {
        !spatialEngine.blocks.isEmpty || !clusterEngine.allClusters.isEmpty
    }

    private var contentBounds: CGRect? {
        let blockRects = spatialEngine.blocks.map { block in
            CGRect(
                x: block.position.x - block.size.width / 2,
                y: block.position.y - block.size.height / 2,
                width: block.size.width,
                height: block.size.height
            )
        }
        let clusterRects = clusterEngine.allClusters.map(\.boundingRect)
        let rects = blockRects + clusterRects
        guard var bounds = rects.first else { return nil }
        for rect in rects.dropFirst() {
            bounds = bounds.union(rect)
        }
        return bounds
    }

    // MARK: - Blocks Layer

    @ViewBuilder
    private var blocksLayer: some View {
        ForEach(spatialEngine.blocks.filter { !clusterConsumedBlockUUIDs.contains($0.entityUuid) }, id: \.id) { block in
            blockView(for: block)
                .position(
                    x: block.position.x + (blockDragOffsets[block.id]?.width ?? 0),
                    y: block.position.y + (blockDragOffsets[block.id]?.height ?? 0)
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

    @MainActor
    private func loadPaneThinkspace(in viewportSize: CGSize) async {
        hasInitializedViewport = false
        await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
        await clusterEngine.loadUserClusters(
            thinkspaceId: thinkspaceId,
            blocks: spatialEngine.blocks
        )
        clusterEngine.scheduleRecompute(blocks: spatialEngine.blocks)
        applyInitialViewport(in: viewportSize)
    }

    private func applyInitialViewport(in viewportSize: CGSize) {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }

        guard let bounds = contentBounds else {
            canvasScale = 1.0
            canvasOffset = .zero
            hasInitializedViewport = true
            return
        }

        let paddedBounds = bounds.insetBy(dx: -72, dy: -72)
        let widthScale = viewportSize.width / max(paddedBounds.width, 1)
        let heightScale = viewportSize.height / max(paddedBounds.height, 1)

        // Panes should open with the whole thinkspace visible, but avoid zooming in past 100%.
        let targetScale = max(min(min(widthScale, heightScale), 1.0), minScale)

        canvasScale = targetScale
        canvasOffset = CGSize(
            width: viewportSize.width / 2 - paddedBounds.midX,
            height: viewportSize.height / 2 - paddedBounds.midY
        )
        hasInitializedViewport = true
    }
}
