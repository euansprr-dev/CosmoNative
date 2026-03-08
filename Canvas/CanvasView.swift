// CosmoOS/Canvas/CanvasView.swift
// SwiftUI wrapper for Metal canvas with floating blocks

import SwiftUI
import GRDB
import UniformTypeIdentifiers

struct CanvasView: View {
    /// The thinkspace ID this canvas displays — passed directly to avoid race conditions
    let thinkspaceId: String?

    @StateObject private var spatialEngine = SpatialEngine()
    @StateObject private var expansionManager = BlockExpansionManager()
    @StateObject private var connectManager = DragToConnectManager()
    @StateObject private var drawingState = DrawingStateManager()
    @StateObject private var clusterEngine = CanvasClusterEngine()
    @EnvironmentObject var voiceEngine: VoiceEngine
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var blockFrameTracker: CanvasBlockFrameTracker
    @EnvironmentObject var crossDragManager: CrossThinkspaceDragManager

    @State private var canvasSize: CGSize = .zero
    @State private var selectedBlockId: String?
    @State private var dragOffset: CGSize = .zero

    // Canvas panning state
    @State private var canvasOffset: CGSize = .zero
    @GestureState private var panOffset: CGSize = .zero

    // Canvas zoom state - smooth, Apple Silicon optimized
    @State private var canvasScale: CGFloat = 1.0
    @GestureState private var magnificationState: CGFloat = 1.0
    @State private var scrollWheelMonitor: Any?
    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 3.0
    private let zoomSensitivity: CGFloat = 0.008  // For scroll wheel

    // PERFORMANCE: Track drag offsets separately from @Published blocks to avoid full re-renders
    @State private var blockDragOffsets: [String: CGSize] = [:]
    @State private var draggingBlockId: String? = nil

    // PERFORMANCE: Dedicated cluster drag state — avoids N writes to blockDragOffsets per frame,
    // preventing connection line recomputation and linear search cascades during drag.
    @State private var clusterDragTranslation: CGSize = .zero

    // Inbox blocks state
    @State private var inboxBlocks: [InboxViewBlock] = []

    // PERFORMANCE: Drag offsets for inbox blocks - separate from array to avoid re-renders during drag
    @State private var inboxBlockDragOffsets: [UUID: CGSize] = [:]
    @State private var draggingInboxBlockId: UUID? = nil

    // Thinkspace sidebar state
    @State private var isSidebarVisible = false
    @State private var showSettings = false
    @StateObject private var thinkspaceManager = ThinkspaceManager.shared

    // Zoom/pan persistence
    @State private var zoomPanSaveTask: Task<Void, Never>?

    // PERF: Debounced frame tracker update — only needed for right-click hit testing
    @State private var frameUpdateTask: Task<Void, Never>?

    // Block UUIDs consumed by non-canvas clusters — computed live from clusterEngine state.
    // No caching needed; iterating a handful of clusters is negligible.

    // Ambient knowledge panel
    @StateObject private var ambientEngine = AmbientFieldEngine()
    @State private var showAmbientPanel = false

    // Crystallization heatmap
    @State private var showCrystallizationHeatmap = false
    @StateObject private var crystallizationEngine = CrystallizationEngine.shared

    // Incubation engine (spaced repetition heartbeat)
    @StateObject private var incubationEngine = IncubationEngine.shared

    // Lasso synthesis workspace
    @State private var showSynthesisWorkspace = false
    @State private var synthesisSourceBlockIds: [String] = []

    // Cluster/zone creation popover
    @State private var showClusterPopover = false
    @State private var clusterPopoverBlockIds: [String] = []
    @State private var clusterPopoverPosition: CGPoint = .zero
    @State private var zonePopoverRect: CGRect = .zero

    // Minimap overlay
    @State private var showMinimap = false

    // Trisociative collision engine
    @StateObject private var trisociativeEngine = TrisociativeEngine.shared

    // Provocation engine (AI devil's advocate)
    @StateObject private var provocationEngine = ProvocationEngine.shared

    // Cluster drag state
    @State private var draggingClusterId: UUID? = nil
    @State private var draggingClusterMemberUUIDs: Set<String> = []

    // Notification observer management - prevent duplicate registrations
    @State private var observersRegistered = false

    // PERF: Cached set of block IDs with media content — avoids string ops per block per render
    @State private var mediaContentBlockIds: Set<String> = []

    // MARK: - Canvas Content (broken out for type-checking performance)

    private var canvasContent: some View {
        GeometryReader { geo in
            let screenCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                // Background always fills the screen (infinite canvas)
                canvasBackground

                // Scrim for expansion
                ExpansionScrim()

                // Blocks container - scaled as a unit around screen center
                // This keeps blocks at their relative positions while zooming
                ZStack {
                    // Cluster zones (auto-chunked + user-created, behind blocks)
                    CanvasClusterLayer(
                        clusters: clusterEngine.allClusters,
                        blocks: spatialEngine.blocks,
                        canvasSize: geo.size,
                        canvasOffset: canvasOffset,
                        scaledPanOffset: scaledPanOffset,
                        effectiveScale: effectiveScale,
                        dropTargetClusterId: clusterEngine.dropTargetClusterId,
                        selectedClusterId: clusterEngine.selectedClusterId,
                        resizingClusterId: clusterEngine.resizingClusterId,
                        clusterDragOffset: draggingClusterId != nil ? clusterDragTranslation : nil,
                        onRenameCluster: { id, newName in
                            clusterEngine.renameUserCluster(id: id, to: newName)
                        },
                        onRemoveCluster: { id in
                            clusterEngine.removeUserCluster(id: id)
                        },
                        onSelectCluster: { id in
                            clusterEngine.selectCluster(id)
                            // Deselect any selected block
                            if id != nil { selectedBlockId = nil }
                        },
                        onDragCluster: { id, translation in
                            handleClusterDrag(clusterId: id, translation: translation)
                        },
                        onDragEndCluster: { id, translation in
                            handleClusterDragEnd(clusterId: id, translation: translation)
                        },
                        onResizeCluster: { id, delta, edge in
                            clusterEngine.resizeCluster(id: id, delta: delta, edge: edge, blocks: spatialEngine.blocks)
                        },
                        onResizeEndCluster: { id in
                            clearClusterDragPreview(clusterId: id)
                            clusterEngine.commitClusterResize(id: id, blocks: spatialEngine.blocks)
                        },
                        onChangeViewMode: { id, mode in
                            clusterEngine.setViewMode(for: id, mode: mode, blocks: spatialEngine.blocks)
                        },
                        onChangeBoardGrouping: { id, grouping in
                            clusterEngine.setBoardGrouping(for: id, grouping: grouping)
                        },
                        onChangeColor: { id, colorIndex in
                            clusterEngine.changeClusterColor(id: id, colorIndex: colorIndex)
                        },
                        onChangeSortOrder: { id, order in
                            clusterEngine.setSortOrder(for: id, order: order)
                        },
                        onToggleListExpand: { clusterId, blockUUID in
                            clusterEngine.toggleListExpand(clusterId: clusterId, blockUUID: blockUUID)
                        },
                        onBoardColumnDrop: { event in
                            clusterEngine.applyBoardDrop(event: event, blocks: &spatialEngine.blocks)
                        },
                        onClusterViewDrop: { event in
                            // Transfer block between clusters (grid/list drag-and-drop)
                            if let sourceCluster = clusterEngine.allClusters.first(where: { $0.blockUUIDs.contains(event.blockUUID) }),
                               sourceCluster.id != event.targetClusterId {
                                clusterEngine.removeBlockFromCluster(blockUUID: event.blockUUID, clusterId: sourceCluster.id, blocks: spatialEngine.blocks)
                            }
                            clusterEngine.addBlockToCluster(blockUUID: event.blockUUID, clusterId: event.targetClusterId, blocks: spatialEngine.blocks)
                        },
                        onOpenFocusMode: { uuid in
                            if let block = spatialEngine.blocks.first(where: { $0.entityUuid == uuid }),
                               block.entityId > 0 {
                                NotificationCenter.default.post(
                                    name: .enterFocusMode,
                                    object: nil,
                                    userInfo: [
                                        "type": block.entityType,
                                        "id": block.entityId
                                    ]
                                )
                            }
                        },
                        expandedBlockUUIDs: clusterEngine.expandedBlockUUIDs
                    )

                    blocksLayer
                    inboxBlocksLayer

                    // Connection lines render ON TOP of blocks so they're visible.
                    // Blocks have opaque backgrounds that would completely hide lines
                    // drawn behind them. allowsHitTesting(false) prevents interaction interference.
                    CanvasConnectionLinesLayer(
                        blocks: spatialEngine.blocks,
                        canvasOffset: canvasOffset,
                        scaledPanOffset: scaledPanOffset,
                        effectiveScale: effectiveScale,
                        blockDragOffsets: blockDragOffsets
                    )

                    // Drag-to-connect overlay (canvas coordinates, inside scaled container
                    // so it shares the same coordinate space as blocks and final connection lines)
                    DragToConnectOverlay(
                        connectManager: connectManager,
                        blocks: spatialEngine.blocks,
                        canvasOffset: canvasOffset,
                        scaledPanOffset: scaledPanOffset,
                        effectiveScale: effectiveScale
                    )
                }
                .scaleEffect(effectiveScale, anchor: UnitPoint(
                    x: screenCenter.x / geo.size.width,
                    y: screenCenter.y / geo.size.height
                ))

                // Drawing elements layer (screen coordinates, outside scaled container
                // to prevent frame clipping at non-100% zoom levels)
                CanvasDrawingsLayer(
                    drawingState: drawingState,
                    canvasOffset: canvasOffset,
                    scaledPanOffset: scaledPanOffset,
                    effectiveScale: effectiveScale,
                    screenCenter: screenCenter
                )

                // Drawing gesture capture (screen coordinates, outside scaled container)
                CanvasDrawingGestureLayer(
                    drawingState: drawingState,
                    canvasOffset: canvasOffset,
                    scaledPanOffset: scaledPanOffset,
                    effectiveScale: effectiveScale,
                    screenCenter: screenCenter
                )

                // Provocation markers overlay (screen coordinates, on top of blocks)
                ProvocationOverlay(provocationEngine: provocationEngine)
            }
            .environmentObject(expansionManager)
            .overlay(alignment: .bottomTrailing) {
                // Zoom indicator
                zoomIndicator
            }
            .overlay(alignment: .topTrailing) {
                // Drawing tools + settings cog + view layers
                VStack(alignment: .trailing, spacing: 0) {
                    // Top row: drawing toolbar + cog
                    HStack(spacing: 0) {
                        CanvasDrawingToolbar(drawingState: drawingState)

                        // Settings cog
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(DS.textMuted)
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    // View layers toolbar (below cog, right-aligned)
                    CanvasViewLayersToolbar(
                        showCrystallizationHeatmap: $showCrystallizationHeatmap,
                        provocationEngine: provocationEngine,
                        clusterEngine: clusterEngine,
                        blockUUIDs: spatialEngine.blocks.map { $0.entityUuid }
                    )
                }
                .padding(.trailing, 16)
                .padding(.top, 16)
            }
            .sheet(isPresented: $showSettings) {
                SanctuarySettingsView()
                    .frame(width: 720, height: 540)
            }
            // Thinkspace sidebar trigger zone (left edge)
            .overlay(alignment: .leading) {
                ThinkspaceSidebarTrigger(isVisible: $isSidebarVisible)
                    .frame(maxHeight: .infinity)
            }
            // Thinkspace sidebar
            .overlay(alignment: .leading) {
                ThinkspaceSidebar(
                    manager: thinkspaceManager,
                    isVisible: $isSidebarVisible
                )
                .padding(.leading, 16)
                .padding(.top, 60)  // Below command bar
            }
            // Ambient knowledge panel (right edge)
            .overlay(alignment: .trailing) {
                if showAmbientPanel, let selectedId = selectedBlockId {
                    let blockUUID = spatialEngine.blocks.first(where: { $0.id == selectedId })?.entityUuid ?? ""
                    AmbientKnowledgePanel(
                        engine: ambientEngine,
                        sourceBlockUUID: blockUUID,
                        onClose: { showAmbientPanel = false }
                    )
                    .padding(.trailing, 16)
                    .padding(.top, 60)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            // Trisociative collision tray (bottom-left)
            .overlay(alignment: .bottomLeading) {
                CollisionTray(engine: trisociativeEngine)
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
            }
            // PERF: Debounced frame tracker updates — only needed for right-click hit testing,
            // so 100ms delay is imperceptible. Previously ran 60-120x/sec during pan/zoom.
            .onChange(of: spatialEngine.blocks.count) { _, _ in
                scheduleFrameUpdate(screenCenter: screenCenter)
                clusterEngine.scheduleRecompute(blocks: spatialEngine.blocks)
                clusterEngine.updateUserClusterBounds(blocks: spatialEngine.blocks)
                rebuildMediaContentCache()
            }
            .onChange(of: canvasOffset) { _, _ in
                scheduleFrameUpdate(screenCenter: screenCenter)
                debouncedSaveZoomPan()
            }
            .onChange(of: canvasScale) { _, _ in
                scheduleFrameUpdate(screenCenter: screenCenter)
                debouncedSaveZoomPan()
            }
        }
        // NOTE: Removed .drawingGroup() from here - it was breaking async image loading
        // in ResearchCard, InboxViewBlockView thumbnails, etc. GPU acceleration is applied
        // selectively to specific components (GridPatternView, RadialMenuView) instead.
    }

    // MARK: - Zoom Indicator
    private var zoomIndicator: some View {
        Group {
            if effectiveScale != 1.0 {
                HStack(spacing: 8) {
                    // Zoom level display
                    Text("\(Int(effectiveScale * 100))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(DS.textSecondary)

                    // Reset zoom button
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            canvasScale = 1.0
                        }
                    } label: {
                        Image(systemName: "1.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DS.surfaceElevated, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(DS.borderActive, lineWidth: 1)
                )
                .shadow(color: DS.accent.opacity(0.1), radius: 8, y: 2)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.spring(response: 0.3), value: effectiveScale != 1.0)
    }

    private var inboxBlocksLayer: some View {
        ForEach(inboxBlocks, id: \.id) { block in
            let blockId = block.id
            InboxViewBlockView(
                block: block,
                onDragStart: {
                    draggingInboxBlockId = blockId
                },
                onDrag: { translation in
                    // Store offset separately - don't mutate array during drag for smooth performance
                    // Scale by inverse of zoom so dragging feels natural
                    inboxBlockDragOffsets[blockId] = CGSize(
                        width: translation.width / effectiveScale,
                        height: translation.height / effectiveScale
                    )
                },
                onDragEnd: {
                    // Commit offset to actual position
                    if let index = inboxBlocks.firstIndex(where: { $0.id == blockId }),
                       let offset = inboxBlockDragOffsets[blockId] {
                        inboxBlocks[index].x += offset.width
                        inboxBlocks[index].y += offset.height
                    }
                    // Clear drag state and persist
                    inboxBlockDragOffsets.removeValue(forKey: blockId)
                    draggingInboxBlockId = nil
                    saveInboxBlockPositions()
                }
            )
            .position(
                x: block.x + canvasOffset.width + scaledPanOffset.width + (inboxBlockDragOffsets[blockId]?.width ?? 0),
                y: block.y + canvasOffset.height + scaledPanOffset.height + (inboxBlockDragOffsets[blockId]?.height ?? 0)
            )
            .zIndex(draggingInboxBlockId == blockId ? 1000 : Double(block.zIndex))
            .transition(.asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .scale(scale: 0.98).combined(with: .opacity)
            ))
        }
    }

    private var canvasBackground: some View {
        ZStack {
            // Visual background with GPU acceleration
            ZStack {
                // Layer 1: Warm parchment canvas base
                DS.canvas
                    .ignoresSafeArea()

                // Layer 2: Subtle aurora gradient zones (2-3% opacity)
                ThinkspaceAuroraView()
                    .ignoresSafeArea()

                // Layer 3: Infinite tiling grid — warm gray dots
                GridPatternView(
                    offset: CGSize(
                        width: canvasOffset.width + scaledPanOffset.width,
                        height: canvasOffset.height + scaledPanOffset.height
                    ),
                    scale: effectiveScale
                )
                    .ignoresSafeArea()

                // Layer 4: Film grain overlay — static pre-rendered texture (zero per-frame cost)
                FilmGrainOverlay(opacity: 0.025)
                    .ignoresSafeArea()
            }
            .drawingGroup() // GPU-accelerate visual background (no interactive elements)

            // Pan gesture layer - transparent but captures hits
            panGestureBackground
        }
    }

    private func blockDragOffset(for block: CanvasBlock) -> CGSize {
        if draggingClusterMemberUUIDs.contains(block.entityUuid) {
            return clusterDragTranslation
        }
        return blockDragOffsets[block.id] ?? .zero
    }

    private var blocksLayer: some View {
        ForEach(spatialEngine.blocks.filter { !clusterConsumedBlockUUIDs.contains($0.entityUuid) }, id: \.id) { block in
            CanvasBlockContainer(
                block: block,
                canvasOffset: canvasOffset,
                scaledPanOffset: scaledPanOffset,
                dragOffset: blockDragOffset(for: block),
                isDragTarget: draggingBlockId == block.id,
                isMediaContent: mediaContentBlockIds.contains(block.id),
                isHeartbeating: incubationEngine.heartbeatingUUIDs.contains(block.entityUuid),
                isClusterMember: selectedClusterMemberUUIDs.contains(block.entityUuid),
                isDraggingClusterMember: draggingClusterMemberUUIDs.contains(block.entityUuid),
                heatmapOpacity: heatmapOpacity(for: block),
                expansionOpacity: expansionManager.opacity(for: block.id),
                expansionZIndex: expansionManager.zIndex(for: block.id),
                isCrossThinkspaceDragging: crossDragManager.isOverSidebar && crossDragManager.draggedBlock?.id == block.id,
                onDragChanged: { translation in
                    if NSEvent.modifierFlags.contains(.option) {
                        let blockCanvasX = block.position.x + canvasOffset.width + scaledPanOffset.width
                        let blockCanvasY = block.position.y + canvasOffset.height + scaledPanOffset.height
                        if !connectManager.isActive {
                            connectManager.beginConnection(from: block, center: CGPoint(x: blockCanvasX, y: blockCanvasY))
                        }
                        connectManager.updateDrag(to: CGPoint(
                            x: blockCanvasX + translation.width,
                            y: blockCanvasY + translation.height
                        ))
                        connectManager.checkTarget(
                            blocks: spatialEngine.blocks,
                            canvasOffset: canvasOffset,
                            scaledPanOffset: scaledPanOffset
                        )
                    } else {
                        handleDragOptimized(blockId: block.id, translation: translation)
                    }
                },
                onDragEnded: { translation in
                    if connectManager.isActive {
                        if let targetId = connectManager.hoveredTargetBlockId,
                           let targetBlock = spatialEngine.blocks.first(where: { $0.id == targetId }) {
                            connectManager.completeConnection(targetBlock: targetBlock)
                        } else {
                            connectManager.cancel()
                        }
                    } else {
                        handleDragEndOptimized(blockId: block.id, translation: translation)
                    }
                },
                onDoubleTap: {
                    if [.idea, .content, .research, .connection, .cosmoAI].contains(block.entityType) {
                        NotificationCenter.default.post(
                            name: .enterFocusMode,
                            object: nil,
                            userInfo: ["type": block.entityType, "id": block.entityId]
                        )
                    }
                }
            )
        }
    }

    /// Block UUIDs consumed by non-canvas clusters (list/board) — hidden from normal blocksLayer
    private var clusterConsumedBlockUUIDs: Set<String> {
        var s = Set<String>()
        for c in clusterEngine.userClusters where c.viewMode != .canvas {
            s.formUnion(c.blockUUIDs)
        }
        return s
    }

    /// While a cluster is selected, its member blocks should not steal pointer events.
    /// This guarantees cluster drag/resize gestures receive input deterministically.
    private var selectedClusterMemberUUIDs: Set<String> {
        guard let clusterId = clusterEngine.selectedClusterId else { return [] }
        return Set(clusterEngine.memberBlockUUIDs(for: clusterId))
    }

    // blockView(for:) has been extracted into CanvasBlockContainer (see bottom of file)
    // for Equatable-based SwiftUI diffing — only changed blocks re-render.


    /// PERF: Rebuild the media content cache when blocks change
    private func rebuildMediaContentCache() {
        var ids = Set<String>()
        for block in spatialEngine.blocks where block.entityType == .research {
            let url = (block.metadata["url"] ?? "").lowercased()
            if url.contains("youtube") || url.contains("youtu.be") ||
               url.contains("instagram") || url.contains("tiktok") ||
               block.metadata["isSwipeFile"] == "true" {
                ids.insert(block.id)
            }
        }
        mediaContentBlockIds = ids
    }

    private var panGestureBackground: some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(drawingState.toolMode == .select)
            .onTapGesture {
                // Only deselect the previously selected block (not the whole array)
                if let prevId = selectedBlockId,
                   let prevIndex = spatialEngine.blocks.firstIndex(where: { $0.id == prevId }) {
                    spatialEngine.blocks[prevIndex].isSelected = false
                }
                selectedBlockId = nil
                clusterEngine.selectCluster(nil)
                drawingState.clearSelection()

                // Post notification AFTER state change is complete
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .blurAllBlocks, object: nil)
                }
            }
            .simultaneousGesture(
                // Pan gesture — simultaneous so it doesn't block tap-to-deselect
                // minimumDistance: 10 gives taps room to register before becoming drags
                DragGesture(minimumDistance: 10)
                    .updating($panOffset) { value, state, _ in
                        // Store raw translation - will be scaled when applied
                        state = value.translation
                    }
                    .onEnded { value in
                        // Scale by 1/effectiveScale so panning feels natural at any zoom level
                        // When zoomed out, a 100px drag should move the canvas 100px on screen
                        canvasOffset.width += value.translation.width / effectiveScale
                        canvasOffset.height += value.translation.height / effectiveScale
                    }
            )
            .simultaneousGesture(
                // Trackpad pinch-to-zoom gesture
                MagnifyGesture()
                    .updating($magnificationState) { value, state, _ in
                        state = value.magnification
                    }
                    .onEnded { value in
                        // Commit pinch scale without extra animation. The gesture state's
                        // magnification resets to 1.0 at end; animating this commit can
                        // produce a visible snap/bounce in drawing overlays.
                        let newScale = canvasScale * value.magnification
                        canvasScale = min(max(newScale, minScale), maxScale)
                    }
            )
    }

    // Computed property for effective zoom level during gesture
    private var effectiveScale: CGFloat {
        let gestureScale = canvasScale * magnificationState
        return min(max(gestureScale, minScale), maxScale)
    }

    // Scaled pan offset - divide by zoom so panning feels natural at any zoom level
    private var scaledPanOffset: CGSize {
        CGSize(
            width: panOffset.width / effectiveScale,
            height: panOffset.height / effectiveScale
        )
    }

    /// Convert screen coordinates to canvas coordinates (accounting for zoom and pan)
    /// Use this when creating blocks from screen positions (like right-click)
    private func screenToCanvasPosition(_ screenPos: CGPoint) -> CGPoint {
        let screenCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        // Reverse the container scale transform
        let canvasX = (screenPos.x - screenCenter.x) / effectiveScale + screenCenter.x - canvasOffset.width - scaledPanOffset.width
        let canvasY = (screenPos.y - screenCenter.y) / effectiveScale + screenCenter.y - canvasOffset.height - scaledPanOffset.height

        return CGPoint(x: canvasX, y: canvasY)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            canvasContent
                .onAppear {
                    canvasSize = geometry.size

                // Register context provider for global Cosmo window
                let provider = CanvasContextProvider(spatialEngine: spatialEngine)
                CosmoWindowViewModel.shared.updateContext(provider: provider)

                // Load persisted blocks from database for this ThinkSpace
                Task { @MainActor in
                    await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
                    drawingState.loadDrawings(thinkspaceId: thinkspaceId)
                    await repairLegacyBlocksIfNeeded()
                    rebuildMediaContentCache()
                    

                    // Restore persisted zoom/pan for current thinkspace
                    if let tsId = thinkspaceId,
                       let ts = thinkspaceManager.thinkspaces.first(where: { $0.id == tsId }) {
                        canvasScale = CGFloat(ts.zoomLevel)
                        canvasOffset = ts.panOffset
                    }

                    // Load user-created clusters
                    await clusterEngine.loadUserClusters(
                        thinkspaceId: thinkspaceId,
                        blocks: spatialEngine.blocks
                    )
                    
                }

                // Load persisted inbox blocks
                loadInboxBlockPositions()

                // Register notification observers only once
                guard !observersRegistered else { return }
                observersRegistered = true

                // Listen for voice-driven placement commands
                NotificationCenter.default.addObserver(
                    forName: .placeBlocksOnCanvas,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handlePlaceBlocks(notification: notification, canvasSize: canvasSize)
                }

                // Listen for move commands
                NotificationCenter.default.addObserver(
                    forName: .moveCanvasBlocks,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleMoveBlocks(notification: notification)
                }

                // Listen for arrangement commands (MAGICAL!)
                NotificationCenter.default.addObserver(
                    forName: .arrangeCanvasBlocks,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleArrangeBlocks(notification: notification, canvasSize: canvasSize)
                }

                // Listen for Cosmo AI block creation
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.createCosmoAIBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCreateCosmoAIBlock(notification: notification)
                }

                // Listen for Note block creation
                NotificationCenter.default.addObserver(
                    forName: .createNoteBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCreateNoteBlock(notification: notification)
                }

                // Listen for block selection (from CosmoBlockWrapper)
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.blockSelected,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    if let blockId = notification.userInfo?["blockId"] as? String {
                        handleTap(blockId: blockId)
                    }
                }

                // Listen for block removal
                NotificationCenter.default.addObserver(
                    forName: .removeBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleRemoveBlock(notification: notification)
                }

                // Listen for generic entity creation (from radial menu)
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.createEntityAtPosition,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCreateEntityAtPosition(notification: notification)
                }

                // Listen for calendar window opening
                NotificationCenter.default.addObserver(
                    forName: .openCalendarWindow,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleOpenCalendarWindow(notification: notification)
                }

                // Listen for inbox block creation
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.createInboxBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCreateInboxBlock(notification: notification)
                }

                // Listen for inbox block closure
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.closeInboxBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCloseInboxBlock(notification: notification)
                }

                // Listen for inbox block position updates (drag)
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.updateInboxBlockPosition,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateInboxBlockPosition(notification: notification)
                }

                // Listen for inbox block size updates (resize)
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.updateInboxBlockSize,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateInboxBlockSize(notification: notification)
                }

                // Listen for block content updates (saves to database)
                NotificationCenter.default.addObserver(
                    forName: .updateBlockContent,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateBlockContent(notification: notification)
                }

                // Listen for block metadata updates (e.g., Note color)
                NotificationCenter.default.addObserver(
                    forName: .updateBlockMetadata,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateBlockMetadata(notification: notification)
                }
                
                // Listen for block size updates (e.g., Note resize)
                NotificationCenter.default.addObserver(
                    forName: .updateBlockSize,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateBlockSize(notification: notification)
                }
                
                // Listen for save block size (after resize ends)
                NotificationCenter.default.addObserver(
                    forName: .saveBlockSize,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleSaveBlockSize(notification: notification)
                }

                // Listen for research block creation (from URL capture)
                NotificationCenter.default.addObserver(
                    forName: .createResearchBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCreateResearchBlock(notification: notification)
                }

                // Listen for block expansion voice commands
                NotificationCenter.default.addObserver(
                    forName: .expandSelectedBlock,
                    object: nil,
                    queue: .main
                ) { [self] _ in
                    handleExpandSelectedBlock()
                }

                NotificationCenter.default.addObserver(
                    forName: .collapseExpandedBlock,
                    object: nil,
                    queue: .main
                ) { [self] _ in
                    Task { @MainActor in
                        withAnimation(BlockAnimations.collapse) {
                            expansionManager.collapse()
                        }
                    }
                }

                NotificationCenter.default.addObserver(
                    forName: .closeSelectedBlock,
                    object: nil,
                    queue: .main
                ) { [self] _ in
                    if let blockId = selectedBlockId {
                        Task {
                            await spatialEngine.removeBlock(blockId)
                        }
                    }
                }

                NotificationCenter.default.addObserver(
                    forName: .openBlockInFocusMode,
                    object: nil,
                    queue: .main
                ) { [self] _ in
                    handleOpenSelectedBlockInFocusMode()
                }

                // Smart block reference handlers (by ID)
                NotificationCenter.default.addObserver(
                    forName: .deleteSpecificBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleDeleteSpecificBlock(notification: notification)
                }

                NotificationCenter.default.addObserver(
                    forName: .duplicateBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleDuplicateBlock(notification: notification)
                }

                NotificationCenter.default.addObserver(
                    forName: .moveBlockToTime,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleMoveBlockToTime(notification: notification)
                }

                // Smart block reference handlers (by content search)
                NotificationCenter.default.addObserver(
                    forName: .deleteBlockByContent,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleDeleteBlockByContent(notification: notification)
                }

                NotificationCenter.default.addObserver(
                    forName: .expandBlockByContent,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleExpandBlockByContent(notification: notification)
                }

                NotificationCenter.default.addObserver(
                    forName: .duplicateBlockByContent,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleDuplicateBlockByContent(notification: notification)
                }

                NotificationCenter.default.addObserver(
                    forName: .moveBlockByContentToTime,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleMoveBlockByContentToTime(notification: notification)
                }

                // Listen for entity placement from voice commands (LLM-First)
                NotificationCenter.default.addObserver(
                    forName: .placeEntityOnCanvas,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handlePlaceEntityOnCanvas(notification: notification)
                }

                // Listen for block resize commands
                NotificationCenter.default.addObserver(
                    forName: .resizeSelectedBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleResizeSelectedBlock(notification: notification)
                }

                // Listen for opening entity on canvas (from Cmd+K)
                NotificationCenter.default.addObserver(
                    forName: .openEntityOnCanvas,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleOpenEntityOnCanvas(notification: notification)
                }

                // Listen for ambient pull-to-canvas
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.pullAmbientToCanvas,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handlePullAmbientToCanvas(notification: notification)
                }

                // Listen for lasso-enclosed blocks — show choice popover (cluster vs synthesize)
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.lassoEnclosedBlocks,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        if let blockIds = notification.userInfo?["blockIds"] as? [String], blockIds.count >= 2 {
                            // Compute center position of lassoed blocks for popover placement
                            let lassoBlocks = spatialEngine.blocks.filter { blockIds.contains($0.id) }
                            let avgX = lassoBlocks.map(\.position.x).reduce(0, +) / max(CGFloat(lassoBlocks.count), 1)
                            let avgY = lassoBlocks.map(\.position.y).reduce(0, +) / max(CGFloat(lassoBlocks.count), 1)

                            // Convert to screen coords
                            let screenCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                            let canvasX = avgX + canvasOffset.width + scaledPanOffset.width
                            let canvasY = avgY + canvasOffset.height + scaledPanOffset.height
                            let screenX = screenCenter.x + (canvasX - screenCenter.x) * effectiveScale
                            let screenY = screenCenter.y + (canvasY - screenCenter.y) * effectiveScale

                            clusterPopoverBlockIds = blockIds
                            clusterPopoverPosition = CGPoint(x: screenX, y: screenY - 60)
                            withAnimation(ProMotionSprings.snappy) {
                                showClusterPopover = true
                            }
                            drawingState.toolMode = .select
                        }
                    }
                }

                // Listen for zone drawn — show zone creation popover
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.zoneDrawn,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        if let rectX = notification.userInfo?["rectX"] as? CGFloat,
                           let rectY = notification.userInfo?["rectY"] as? CGFloat,
                           let rectW = notification.userInfo?["rectW"] as? CGFloat,
                           let rectH = notification.userInfo?["rectH"] as? CGFloat,
                           let popoverX = notification.userInfo?["popoverX"] as? CGFloat,
                           let popoverY = notification.userInfo?["popoverY"] as? CGFloat {
                            zonePopoverRect = CGRect(x: rectX, y: rectY, width: rectW, height: rectH)
                            clusterPopoverBlockIds = []  // Empty = zone mode
                            clusterPopoverPosition = CGPoint(x: popoverX, y: popoverY)
                            withAnimation(ProMotionSprings.snappy) {
                                showClusterPopover = true
                            }
                            drawingState.toolMode = .select
                        }
                    }
                }

                // Listen for cluster creation from context menu
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.createClusterFromSelection,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        if let blockIds = notification.userInfo?["blockIds"] as? [String],
                           let position = notification.userInfo?["position"] as? CGPoint {
                            clusterPopoverBlockIds = blockIds
                            clusterPopoverPosition = position
                            withAnimation(ProMotionSprings.snappy) {
                                showClusterPopover = true
                            }
                        }
                    }
                }

                // Listen for focus mode entry to record incubation interactions
                NotificationCenter.default.addObserver(
                    forName: .enterFocusMode,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    if let entityId = notification.userInfo?["id"] as? Int64 {
                        // Find the block UUID for this entity
                        if let block = spatialEngine.blocks.first(where: { $0.entityId == entityId }) {
                            Task { @MainActor in
                                await incubationEngine.recordInteraction(uuid: block.entityUuid)
                            }
                        }
                    }
                }

                // Listen for cross-thinkspace block drop (block moved from another thinkspace)
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.crossThinkspaceDropBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        guard let targetThinkspaceId = notification.userInfo?["thinkspaceId"] as? String,
                              targetThinkspaceId == thinkspaceId,
                              let entityUuid = notification.userInfo?["entityUuid"] as? String else { return }

                        // Reload blocks to pick up the transferred block
                        await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
                        rebuildMediaContentCache()
                        
                    }
                }

                // Listen for Cmd+V paste (routed via CosmoCommands pasteboard group)
                NotificationCenter.default.addObserver(
                    forName: .performCanvasPaste,
                    object: nil,
                    queue: .main
                ) { [self] _ in
                    guard !appState.isCommandKVisible else { return }
                    Task { await handleCanvasPaste() }
                }

                // MARK: - Scroll Wheel Zoom (Mouse)
                // Set up scroll wheel event monitor for smooth mouse zoom
                // Uses Option+scroll for zoom to avoid conflicting with normal scrolling
                scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
                    // Only handle scroll wheel zoom when Option key is held
                    // or when using a mouse (no momentum phase means mouse wheel)
                    let isMouseWheel = event.momentumPhase == [] && event.phase == []
                    let isOptionHeld = event.modifierFlags.contains(.option)

                    if isMouseWheel || isOptionHeld {
                        // Use scrollingDeltaY for zoom
                        let delta = event.scrollingDeltaY
                        if abs(delta) > 0.1 {  // Threshold to avoid micro-zooms
                            let zoomFactor = 1.0 + (delta * zoomSensitivity)
                            let newScale = canvasScale * zoomFactor

                            withAnimation(.easeOut(duration: 0.12)) {
                                canvasScale = min(max(newScale, minScale), maxScale)
                            }

                            // Consume the event when zooming
                            return nil
                        }
                    }
                    return event
                }
            }
            .onDisappear {
                // Clean up scroll wheel event monitor
                if let monitor = scrollWheelMonitor {
                    NSEvent.removeMonitor(monitor)
                    scrollWheelMonitor = nil
                }
            }
            .onChange(of: thinkspaceId) { _, newId in
                // Reload canvas content when switching between Command Center ↔ thinkspaces
                Task { @MainActor in
                    await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: newId)
                    drawingState.loadDrawings(thinkspaceId: newId)
                    CosmoUndoManager.shared.clearHistory()

                    // Restore zoom/pan for the new thinkspace
                    if let tsId = newId,
                       let ts = thinkspaceManager.thinkspaces.first(where: { $0.id == tsId }) {
                        canvasScale = CGFloat(ts.zoomLevel)
                        canvasOffset = ts.panOffset
                    } else {
                        canvasScale = 1.0
                        canvasOffset = .zero
                    }

                    // Reload clusters
                    await clusterEngine.loadUserClusters(
                        thinkspaceId: newId,
                        blocks: spatialEngine.blocks
                    )
                    rebuildMediaContentCache()
                    
                }
            }
            // Keyboard handler for ESC to collapse expanded blocks / dismiss overlays
            .onKeyPress(.escape) {
                if showMinimap {
                    withAnimation(ProMotionSprings.snappy) {
                        showMinimap = false
                    }
                    return .handled
                }
                if showClusterPopover {
                    withAnimation(ProMotionSprings.snappy) {
                        showClusterPopover = false
                    }
                    return .handled
                }
                if expansionManager.isAnyBlockExpanded {
                    withAnimation(BlockAnimations.collapse) {
                        expansionManager.collapse()
                    }
                    return .handled
                }
                return .ignored
            }
            // TAB: Toggle minimap navigator (skip when Command-K is open — Tab cycles tabs there)
            .onKeyPress(.tab) {
                guard !appState.isCommandKVisible else { return .ignored }
                withAnimation(ProMotionSprings.snappy) {
                    showMinimap.toggle()
                }
                return .handled
            }
            // Cmd+Shift+H: Toggle crystallization heatmap
            .onKeyPress(characters: .init(charactersIn: "hH")) { press in
                guard press.modifiers.contains(.command), press.modifiers.contains(.shift) else {
                    return .ignored
                }
                withAnimation(ProMotionSprings.snappy) {
                    showCrystallizationHeatmap.toggle()
                }
                return .handled
            }
            // Cmd+Shift+K: Toggle ambient knowledge panel
            .onKeyPress(characters: .init(charactersIn: "kK")) { press in
                guard press.modifiers.contains(.command), press.modifiers.contains(.shift) else {
                    return .ignored
                }
                withAnimation(ProMotionSprings.snappy) {
                    showAmbientPanel.toggle()
                }
                return .handled
            }
            // Cmd+Shift+P: Trigger provocation scan on visible blocks
            .onKeyPress(characters: .init(charactersIn: "pP")) { press in
                guard press.modifiers.contains(.command), press.modifiers.contains(.shift) else {
                    return .ignored
                }
                let visibleUUIDs = spatialEngine.blocks.map { $0.entityUuid }
                Task {
                    await provocationEngine.scanBlocks(atomUUIDs: visibleUUIDs)
                }
                return .handled
            }
            // Cmd+V paste is handled via .performCanvasPaste notification
            // (routed from CosmoCommands pasteboard CommandGroup)
            // Synthesis workspace overlay
            .sheet(isPresented: $showSynthesisWorkspace) {
                synthesisWorkspaceOverlay
                    .frame(minWidth: 900, minHeight: 600)
            }
            // Cluster creation popover
            .overlay {
                if showClusterPopover {
                    clusterCreationOverlay
                }
            }
            // Minimap navigator overlay
            .overlay {
                if showMinimap {
                    minimapOverlay
                }
            }
        }
    }

    // MARK: - Synthesis Workspace

    @ViewBuilder
    private var synthesisWorkspaceOverlay: some View {
        SynthesisWorkspaceLoader(
            blockIds: synthesisSourceBlockIds,
            blocks: spatialEngine.blocks,
            onCreateConnection: { result in
                Task {
                    await createSynthesisConnection(result: result)
                }
                showSynthesisWorkspace = false
            },
            onDismiss: {
                showSynthesisWorkspace = false
            }
        )
    }

    private func createSynthesisConnection(result: LassoSynthesisResult) async {
        let atomRepo = AtomRepository.shared

        // Build synthesis metadata
        let synthMeta = SynthesisMetadata(
            sourceAtomUUIDs: result.sourceAtomUUIDs,
            themes: result.themes,
            openQuestions: result.openQuestions,
            evidenceSpans: result.evidenceSpans,
            synthesizedAt: ISO8601DateFormatter().string(from: Date())
        )

        let metadataJSON: String
        if let data = try? JSONEncoder().encode(synthMeta),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        // Create bidirectional links to all source atoms
        let links: [AtomLink] = result.sourceAtomUUIDs.map {
            AtomLink(linkType: .related, uuid: $0)
        }

        do {
            let connectionAtom = try await atomRepo.create(
                type: .connection,
                title: result.suggestedTitle,
                body: result.synthesizedArgument,
                metadata: metadataJSON,
                links: links
            )

            // Calculate center position of source blocks for placement
            let sourceBlocks = spatialEngine.blocks.filter { block in
                synthesisSourceBlockIds.contains(block.id)
            }
            let avgX = sourceBlocks.map(\.position.x).reduce(0, +) / max(CGFloat(sourceBlocks.count), 1)
            let avgY = sourceBlocks.map(\.position.y).reduce(0, +) / max(CGFloat(sourceBlocks.count), 1)
            let position = CGPoint(x: avgX, y: avgY + 300) // Place below source cluster

            let canvasBlock = CanvasBlock.fromAtom(connectionAtom, position: position)
            await spatialEngine.addBlock(canvasBlock, persist: true)

            print("Synthesis: Created connection '\(result.suggestedTitle)' linking \(result.sourceAtomUUIDs.count) sources")
        } catch {
            print("Synthesis: Failed to create connection — \(error)")
        }
    }

    // MARK: - Cluster Creation Overlay

    @ViewBuilder
    private var clusterCreationOverlay: some View {
        // Dismiss backdrop
        Color.clear
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(ProMotionSprings.snappy) {
                    showClusterPopover = false
                }
            }

        ClusterCreationPopover(
            blockIds: clusterPopoverBlockIds,
            position: clusterPopoverPosition,
            onCreateCluster: { name, colorIndex in
                let thinkspaceId = thinkspaceManager.currentThinkspace?.id
                if clusterPopoverBlockIds.isEmpty {
                    // Zone mode — create empty zone cluster
                    clusterEngine.createZoneCluster(
                        name: name,
                        colorIndex: colorIndex,
                        boundingRect: zonePopoverRect,
                        thinkspaceId: thinkspaceId
                    )
                } else {
                    // Lasso mode — convert block IDs to entity UUIDs for cluster membership
                    let blockUUIDs = spatialEngine.blocks
                        .filter { clusterPopoverBlockIds.contains($0.id) }
                        .map { $0.entityUuid }
                    clusterEngine.createUserCluster(
                        name: name,
                        colorIndex: colorIndex,
                        blockUUIDs: blockUUIDs,
                        blocks: spatialEngine.blocks,
                        thinkspaceId: thinkspaceId
                    )
                }
                withAnimation(ProMotionSprings.snappy) {
                    showClusterPopover = false
                }
            },
            onDismiss: {
                withAnimation(ProMotionSprings.snappy) {
                    showClusterPopover = false
                }
            }
        )
    }

    // MARK: - Minimap Overlay

    @ViewBuilder
    private var minimapOverlay: some View {
        CanvasMinimapOverlay(
            blocks: spatialEngine.blocks,
            clusters: clusterEngine.allClusters,
            currentViewport: computeCurrentViewport(),
            onNavigate: { canvasPosition, animated in
                navigateTo(canvasPosition: canvasPosition, animated: animated)
            },
            onDismiss: {
                withAnimation(ProMotionSprings.snappy) {
                    showMinimap = false
                }
            }
        )
    }

    /// Compute current viewport rect in canvas coordinates
    private func computeCurrentViewport() -> CGRect {
        let viewWidth = canvasSize.width / effectiveScale
        let viewHeight = canvasSize.height / effectiveScale
        let centerX = canvasSize.width / 2 - canvasOffset.width
        let centerY = canvasSize.height / 2 - canvasOffset.height
        return CGRect(
            x: centerX - viewWidth / 2,
            y: centerY - viewHeight / 2,
            width: viewWidth,
            height: viewHeight
        )
    }

    /// Move viewport to center on a canvas position, optionally animated
    private func navigateTo(canvasPosition: CGPoint, animated: Bool = true) {
        let screenCenterX = canvasSize.width / 2
        let screenCenterY = canvasSize.height / 2
        let newOffset = CGSize(
            width: screenCenterX - canvasPosition.x,
            height: screenCenterY - canvasPosition.y
        )
        if animated {
            withAnimation(ProMotionSprings.snappy) {
                canvasOffset = newOffset
            }
        } else {
            canvasOffset = newOffset
        }
    }

    // MARK: - Crystallization Heatmap

    /// Returns opacity multiplier for a block when heatmap mode is active
    private func heatmapOpacity(for block: CanvasBlock) -> CGFloat {
        guard showCrystallizationHeatmap else { return 1.0 }
        let level = crystallizationEngine.levels[block.entityUuid] ?? .raw
        switch level {
        case .raw: return 0.3
        case .highlighted: return 0.5
        case .distilled: return 0.7
        case .connected: return 0.85
        case .crystallized: return 1.0
        }
    }

    // MARK: - Legacy Block Repair

    /// Repairs persisted canvas blocks that have invalid entity IDs (<= 0) by creating
    /// corresponding DB rows and updating the canvas_blocks record in-place.
    @MainActor
    private func repairLegacyBlocksIfNeeded() async {
        let repairableTypes: Set<EntityType> = [.idea, .content, .research, .task, .connection]
        let indicesToRepair = spatialEngine.blocks.indices.filter { idx in
            let b = spatialEngine.blocks[idx]
            return repairableTypes.contains(b.entityType) && b.entityId <= 0
        }

        guard !indicesToRepair.isEmpty else { return }

        print("🛠️ Repairing \(indicesToRepair.count) legacy canvas blocks with invalid entity IDs...")

        for idx in indicesToRepair {
            var block = spatialEngine.blocks[idx]

            // Capture values before async closures to avoid Swift concurrency issues
            let blockTitle = block.title
            let blockUuid = block.entityUuid

            do {
                switch block.entityType {
                case .idea:
                    let savedIdea = try await CosmoDatabase.shared.asyncWrite { db -> Idea in
                        var idea = Idea.new(
                            title: blockTitle.isEmpty ? "New Idea" : blockTitle,
                            content: ""
                        )
                        // Preserve the block UUID so future linking stays consistent
                        if !blockUuid.isEmpty { idea.uuid = blockUuid }
                        try idea.insert(db)
                        return idea
                    }
                    block.entityId = savedIdea.id ?? -1
                    block.entityUuid = savedIdea.uuid

                case .content:
                    let savedContent = try await CosmoDatabase.shared.asyncWrite { db -> CosmoContent in
                        var content = CosmoContent.new(
                            title: blockTitle.isEmpty ? "New Content" : blockTitle,
                            body: ""
                        )
                        if !blockUuid.isEmpty { content.uuid = blockUuid }
                        try content.insert(db)
                        return content
                    }
                    block.entityId = savedContent.id ?? -1
                    block.entityUuid = savedContent.uuid

                case .task:
                    let savedTask = try await CosmoDatabase.shared.asyncWrite { db -> CosmoTask in
                        var task = CosmoTask.new(
                            title: blockTitle.isEmpty ? "New Task" : blockTitle,
                            status: "todo"
                        )
                        if !blockUuid.isEmpty { task.uuid = blockUuid }
                        try task.insert(db)
                        return task
                    }
                    block.entityId = savedTask.id ?? -1
                    block.entityUuid = savedTask.uuid

                case .research:
                    let savedResearch = try await CosmoDatabase.shared.asyncWrite { db -> Research in
                        var research = Research.new(
                            title: blockTitle.isEmpty ? "New Research" : blockTitle,
                            query: nil,
                            url: nil,
                            sourceType: .unknown
                        )
                        if !blockUuid.isEmpty { research.uuid = blockUuid }
                        try research.insert(db)
                        return research
                    }
                    block.entityId = savedResearch.id ?? -1
                    block.entityUuid = savedResearch.uuid

                case .connection:
                    let savedConnection = try await CosmoDatabase.shared.asyncWrite { db -> Atom in
                        var connection = Atom.new(type: .connection, title: blockTitle.isEmpty ? "New Connection" : blockTitle)
                        if !blockUuid.isEmpty { connection.uuid = blockUuid }
                        try connection.insert(db)
                        return connection
                    }
                    block.entityId = savedConnection.id ?? -1
                    block.entityUuid = savedConnection.uuid

                default:
                    break
                }

                // Apply updates in-memory + persist to canvas_blocks
                spatialEngine.blocks[idx] = block
                await spatialEngine.saveBlock(block)
                print("🛠️ Repaired block \(block.id) → \(block.entityType.rawValue) id=\(block.entityId)")
            } catch {
                print("❌ Failed to repair block \(block.id) (\(block.entityType.rawValue)): \(error)")
            }
        }
    }

    // MARK: - Computed Properties

    // MARK: - Calendar Window Handler
    private func handleOpenCalendarWindow(notification: Notification) {
        // Check if a calendar block already exists - focus it instead of creating duplicate
        if let existingCalendar = spatialEngine.blocks.first(where: { $0.entityType == .calendar }) {
            // Scroll canvas to center on existing calendar
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                canvasOffset = CGSize(
                    width: -existingCalendar.position.x + canvasSize.width / 2,
                    height: -existingCalendar.position.y + canvasSize.height / 2
                )
            }
            selectedBlockId = existingCalendar.id
            print("📅 Focused existing calendar window")
            return
        }

        // Calculate center position in canvas coordinates
        // Use window frame if canvasSize not available, accounting for any canvas offset
        let viewportSize: CGSize
        if canvasSize.width > 0 && canvasSize.height > 0 {
            viewportSize = canvasSize
        } else if let window = NSApp.keyWindow {
            viewportSize = window.contentView?.frame.size ?? CGSize(width: 1440, height: 900)
        } else {
            viewportSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        }

        // Center in current viewport, accounting for canvas pan offset
        let position = CGPoint(
            x: viewportSize.width / 2 - canvasOffset.width - scaledPanOffset.width,
            y: viewportSize.height / 2 - canvasOffset.height - scaledPanOffset.height
        )

        let block = CanvasBlock.calendarBlock(position: position)

        Task {
            await spatialEngine.addBlock(block, persist: true)
        }

        print("📅 Opened calendar window at \(position)")
    }

    // MARK: - Research Block Creation Handler
    private func handleCreateResearchBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let researchId = userInfo["researchId"] as? Int64 else {
            return
        }

        // Get position from notification or use center
        let screenPosition: CGPoint
        if let pos = userInfo["position"] as? CGPoint {
            screenPosition = pos
        } else {
            screenPosition = CGPoint(
                x: canvasSize.width / 2,
                y: canvasSize.height / 2
            )
        }

        // Convert screen position to canvas position (accounting for zoom)
        let position = screenToCanvasPosition(screenPosition)

        let block = CanvasBlock(
            position: position,
            size: CGSize(width: 300, height: 280),
            entityType: .research,
            entityId: researchId,
            entityUuid: UUID().uuidString,
            title: "Research",
            subtitle: nil,
            metadata: ["created": ISO8601DateFormatter().string(from: Date())]
        )

        Task {
            await spatialEngine.addBlock(block, persist: true)
        }

        print("🔬 Created research block for ID \(researchId)")
    }

    // MARK: - Block Content Update Handler
    private func handleUpdateBlockContent(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String else {
            return
        }

        let content = userInfo["content"] as? String ?? ""
        let title = userInfo["title"] as? String

        // Find the block
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }

        let block = spatialEngine.blocks[blockIndex]

        // For note and content blocks, save content to metadata and persist
        // Both use metadata-based storage (not atoms table)
        if block.entityType == .note || block.entityType == .content {
            spatialEngine.blocks[blockIndex].metadata["content"] = content
            if let title = title {
                spatialEngine.blocks[blockIndex].metadata["title"] = title
                let defaultTitle = block.entityType == .note ? "Note" : "Content"
                spatialEngine.blocks[blockIndex].title = title.isEmpty ? defaultTitle : title
            }
            Task {
                await spatialEngine.saveBlock(spatialEngine.blocks[blockIndex])
                let blockTypeName = block.entityType == .note ? "note" : "content"
                print("📝 Saved \(blockTypeName) to ThinkSpace")
            }
            return
        }

        // For other entity types, create or update database entry
        if block.entityId == -1 && !content.isEmpty {
            Task {
                await createDatabaseEntryForBlock(block: block, content: content)
            }
        } else if block.entityId != -1 {
            Task {
                await updateDatabaseEntry(block: block, content: content)
            }
        }
    }

    // MARK: - Block Metadata Update Handler
    private func handleUpdateBlockMetadata(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let metadata = userInfo["metadata"] as? [String: String] else {
            return
        }

        // Find the block and update its metadata
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }

        // Merge new metadata with existing
        for (key, value) in metadata {
            spatialEngine.blocks[blockIndex].metadata[key] = value
        }

        // Persist to database
        Task {
            await spatialEngine.saveBlock(spatialEngine.blocks[blockIndex])
        }
    }
    
    // MARK: - Block Size Update Handler
    private func handleUpdateBlockSize(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let size = userInfo["size"] as? CGSize else {
            return
        }
        
        // Find the block and update its size in memory
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }
        
        spatialEngine.blocks[blockIndex].size = size

        // Also update position if provided (for anchored resizing)
        if let position = userInfo["position"] as? CGPoint {
            spatialEngine.blocks[blockIndex].position = position
        }

        // Recompute cluster bounds so zones expand/shrink with resized blocks
        clusterEngine.updateUserClusterBounds(blocks: spatialEngine.blocks)
    }

    // MARK: - Zoom/Pan Persistence

    private func debouncedSaveZoomPan() {
        // PERF: Skip Task allocation if a save is already pending — the trailing-edge
        // debounce will capture the latest values when it fires.
        if let existing = zoomPanSaveTask, !existing.isCancelled {
            return
        }
        zoomPanSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            zoomPanSaveTask = nil
            let blockIds = spatialEngine.blocks.map(\.id)
            await thinkspaceManager.saveCurrentState(
                zoomLevel: Double(canvasScale),
                panOffset: canvasOffset,
                blockIds: blockIds
            )
        }
    }

    // MARK: - PERF: Debounced Frame Tracker

    /// Schedule a frame tracker update with 100ms debounce.
    /// The frame tracker is only used for right-click hit testing, so slight delay is fine.
    private func scheduleFrameUpdate(screenCenter: CGPoint) {
        frameUpdateTask?.cancel()
        let capturedCenter = screenCenter
        frameUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            blockFrameTracker.updateFrames(
                blocks: spatialEngine.blocks,
                canvasOffset: canvasOffset,
                scaledPanOffset: scaledPanOffset,
                effectiveScale: effectiveScale,
                screenCenter: capturedCenter
            )
        }
    }

    // MARK: - Save Block Size Handler
    private func handleSaveBlockSize(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let newSize = userInfo["size"] as? CGSize else {
            return
        }

        // Find the block and persist to database
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }

        // Register undo action if old size was provided
        if let oldSize = userInfo["oldSize"] as? CGSize {
            if oldSize != newSize {
                CosmoUndoManager.shared.register(
                    ResizeBlockAction(blockId: blockId, oldSize: oldSize, newSize: newSize, spatialEngine: spatialEngine)
                )
            }
        }

        // Update the spatial engine block with the new size before saving
        spatialEngine.blocks[blockIndex].size = newSize

        Task {
            await spatialEngine.saveBlock(spatialEngine.blocks[blockIndex])
        }
    }

    private func createDatabaseEntryForBlock(block: CanvasBlock, content: String) async {
        // Create database entry based on entity type
        // This makes the block searchable in Cmd+K
        do {
            switch block.entityType {
            case .idea:
                let idea = try await CosmoDatabase.shared.asyncWrite { db -> Idea in
                    var mutableIdea = Idea.new(
                        title: String(content.prefix(50)),
                        content: content
                    )
                    mutableIdea.uuid = block.entityUuid
                    try mutableIdea.insert(db)
                    mutableIdea.id = db.lastInsertedRowID
                    return mutableIdea
                }

                // Update block with real entity ID
                if let index = spatialEngine.blocks.firstIndex(where: { $0.id == block.id }) {
                    spatialEngine.blocks[index].entityId = idea.id ?? -1
                }
                print("💡 Created idea in database: \(idea.title ?? "Untitled")")

            case .note:
                // Notes are saved as metadata on the block, not as separate entities
                if let index = spatialEngine.blocks.firstIndex(where: { $0.id == block.id }) {
                    spatialEngine.blocks[index].metadata["content"] = content
                    await spatialEngine.saveBlock(spatialEngine.blocks[index])
                }
                print("📝 Saved note content")

            default:
                break
            }
        } catch {
            print("❌ Failed to create database entry: \(error)")
        }
    }

    private func updateDatabaseEntry(block: CanvasBlock, content: String) async {
        // Update existing database entry
        do {
            switch block.entityType {
            case .idea:
                try await CosmoDatabase.shared.asyncWrite { db in
                    if var idea = try Idea.fetchOne(db, key: block.entityId) {
                        idea.content = content
                        idea.updatedAt = ISO8601DateFormatter().string(from: Date())
                        try idea.save(db)
                    }
                }
                print("💡 Updated idea in database")

            case .note:
                if let index = spatialEngine.blocks.firstIndex(where: { $0.id == block.id }) {
                    spatialEngine.blocks[index].metadata["content"] = content
                    await spatialEngine.saveBlock(spatialEngine.blocks[index])
                }

            default:
                break
            }
        } catch {
            print("❌ Failed to update database entry: \(error)")
        }
    }

    // MARK: - Entity Creation Handler
    private func handleCreateEntityAtPosition(notification: Notification) {
        // If Focus Mode is active, forward to Focus Mode's DocumentBlocksLayer
        if appState.focusedEntity != nil {
            print("📦 handleCreateEntityAtPosition: forwarding to Focus Mode")
            NotificationCenter.default.post(
                name: .createEntityInFocusMode,
                object: nil,
                userInfo: notification.userInfo
            )
            return
        }

        guard let userInfo = notification.userInfo,
              let entityType = userInfo["type"] as? EntityType else {
            print("⚠️ handleCreateEntityAtPosition: missing userInfo or entityType")
            return
        }

        print("📦 handleCreateEntityAtPosition: received \(entityType)")

        var screenPosition = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        if let pos = userInfo["position"] as? CGPoint {
            screenPosition = pos
        }

        // Convert screen position to canvas position (accounting for zoom)
        let position = screenToCanvasPosition(screenPosition)

        print("📦 Creating \(entityType) block at position: \(position)")

        // Optional prefilled content (e.g. “Save as Idea” from Cosmo AI)
        let prefillContent = userInfo["content"] as? String
        let prefillTitle = userInfo["title"] as? String

        // Create appropriate block based on entity type
        let block: CanvasBlock
        switch entityType {
        case .idea:
            // Create entity immediately so the block never shows "not found"
            createIdeaBlock(at: position, prefillContent: prefillContent, prefillTitle: prefillTitle)
            return
        case .content:
            createContentBlock(at: position, prefillBody: prefillContent, prefillTitle: prefillTitle)
            return
        case .task:
            createTaskBlock(at: position, prefillTitle: prefillTitle, prefillDescription: prefillContent)
            return
        case .research:
            createNewResearchBlock(at: position, prefillTitle: prefillTitle, prefillSummary: prefillContent)
            return
        case .connection:
            // Connection requires async database creation - handled separately
            createConnectionBlock(at: position)
            return
        case .note:
            block = CanvasBlock.noteBlock(position: position)
        case .cosmoAI:
            block = CanvasBlock.cosmoAIBlock(position: position)
        default:
            // For other types, create a generic block
            block = CanvasBlock(
                position: position,
                size: CGSize(width: 280, height: 180),
                entityType: entityType,
                entityId: -1,
                entityUuid: UUID().uuidString,
                title: "New \(entityType)",
                subtitle: nil,
                metadata: ["created": ISO8601DateFormatter().string(from: Date())]
            )
        }

        Task {
            await spatialEngine.addBlock(block, persist: true)

        }

        print("✨ Created \(entityType) block at \(position)")
    }

    // MARK: - Gesture Handlers (Optimized)

    /// Optimized drag handler - updates only local @State, not @Published blocks array
    /// This prevents full view hierarchy re-renders during drag
    private func handleDragOptimized(blockId: String, translation: CGSize) {
        // Gesture translation is already in canvas space (the block's local coordinate space
        // inside the scaled container), so use it directly — no scale division needed.
        // Dividing by effectiveScale would double-scale since scaleEffect already transforms
        // the gesture coordinate space.
        blockDragOffsets[blockId] = translation
        draggingBlockId = blockId

        // Mark selected (one-time update)
        if selectedBlockId != blockId {
            selectedBlockId = blockId
            clusterEngine.selectCluster(nil)
        }

        // Cross-thinkspace drag detection: check if cursor is over the sidebar
        if let block = spatialEngine.blocks.first(where: { $0.id == blockId }) {
            checkCrossThinkspaceDrag(block: block, translation: translation)
        }

        // Check if dragged block is near a cluster zone (for drop highlight)
        if let block = spatialEngine.blocks.first(where: { $0.id == blockId }) {
            let draggedPosition = CGPoint(
                x: block.position.x + translation.width,
                y: block.position.y + translation.height
            )
            clusterEngine.updateDropTarget(for: draggedPosition)
        }
    }

    /// Detect when a dragged block enters the sidebar zone for cross-thinkspace transfer
    private func checkCrossThinkspaceDrag(block: CanvasBlock, translation: CGSize) {
        let mouseLocation = NSEvent.mouseLocation
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        // Convert screen coords to window coords
        let windowPoint = window.convertPoint(fromScreen: mouseLocation)
        let sidebarWidth = crossDragManager.sidebarWidth

        if windowPoint.x < sidebarWidth {
            // Cursor is over the sidebar
            if !crossDragManager.isDragging {
                crossDragManager.beginDrag(block: block, sourceThinkspaceId: thinkspaceId)
            }
            crossDragManager.enterSidebar()

            // Update cursor position (flip Y for SwiftUI coords — use content view height, not window frame)
            let contentHeight = window.contentView?.bounds.height ?? window.frame.height
            let flippedY = contentHeight - windowPoint.y
            crossDragManager.updateCursorPosition(CGPoint(x: windowPoint.x, y: flippedY))
        } else if crossDragManager.isOverSidebar {
            // Cursor left the sidebar, return to normal canvas drag
            crossDragManager.exitSidebar()
        } else if !crossDragManager.isDragging {
            // Start tracking even when not over sidebar (so we have block info ready)
            crossDragManager.beginDrag(block: block, sourceThinkspaceId: thinkspaceId)
        }
    }

    /// Optimized drag end - commits position to @Published array and database
    private func handleDragEndOptimized(blockId: String, translation: CGSize) {
        // Cross-thinkspace drag: if block is over sidebar, handle transfer instead of normal drop
        if crossDragManager.isDragging && crossDragManager.isOverSidebar {
            blockDragOffsets.removeValue(forKey: blockId)
            draggingBlockId = nil
            // The crossDragManager's NSEvent mouseUp handler or completeDrop will handle the rest
            let mouseLocation = NSEvent.mouseLocation
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                let windowPoint = window.convertPoint(fromScreen: mouseLocation)
                let contentHeight = window.contentView?.bounds.height ?? window.frame.height
                let flippedY = contentHeight - windowPoint.y
                crossDragManager.completeDrop(screenPosition: CGPoint(x: windowPoint.x, y: flippedY))
            }
            return
        }

        // If cross drag was active but cursor is back on canvas, just cancel it
        if crossDragManager.isDragging {
            crossDragManager.cancel()
        }

        // Gesture translation is already in canvas space (scaleEffect transforms the
        // gesture coordinate space), so use it directly without dividing by effectiveScale.

        // PERF: Batch all state mutations into a single transaction so SwiftUI
        // coalesces them into one render pass instead of three separate evaluations.
        var oldPosition: CGPoint = .zero
        var newPosition: CGPoint = .zero
        if let index = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) {
            oldPosition = spatialEngine.blocks[index].position
            newPosition = CGPoint(
                x: oldPosition.x + translation.width,
                y: oldPosition.y + translation.height
            )
            // Batch: commit position + clear drag state in one pass
            spatialEngine.blocks[index].position = newPosition
            blockDragOffsets.removeValue(forKey: blockId)
            draggingBlockId = nil

            // Fire-and-forget position save to database
            spatialEngine.updateBlockPosition(blockId, position: newPosition)

            // Register undo action (only if position actually changed)
            if oldPosition != newPosition {
                CosmoUndoManager.shared.register(
                    MoveBlockAction(blockId: blockId, oldPosition: oldPosition, newPosition: newPosition, spatialEngine: spatialEngine)
                )
            }
        } else {
            // Block not found — still clear drag state
            blockDragOffsets.removeValue(forKey: blockId)
            draggingBlockId = nil
        }

        // Update frame tracker after position change
        let screenCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        blockFrameTracker.updateFrames(
            blocks: spatialEngine.blocks,
            canvasOffset: canvasOffset,
            scaledPanOffset: scaledPanOffset,
            effectiveScale: effectiveScale,
            screenCenter: screenCenter
        )

        // Check cluster zone membership after drag
        if let block = spatialEngine.blocks.first(where: { $0.id == blockId }) {
            updateClusterMembership(for: block)
        }
    }

    /// Update cluster membership when a block is dragged into/out of a user cluster zone.
    /// Uses a generous proximity check (80pt outset) so blocks dropped near a cluster get absorbed.
    private func updateClusterMembership(for block: CanvasBlock) {
        let blockUUID = block.entityUuid
        let position = block.position

        // Clear the visual drop target highlight
        clusterEngine.clearDropTarget()

        // Check if block landed inside or near any user cluster zone (proximity-based)
        if let targetCluster = clusterEngine.nearestDropTargetCluster(for: position) {
            // Add to target cluster if not already a member
            if !targetCluster.blockUUIDs.contains(blockUUID) {
                clusterEngine.addBlockToCluster(
                    blockUUID: blockUUID,
                    clusterId: targetCluster.id,
                    blocks: spatialEngine.blocks
                )
            }
        }

        // Remove from clusters where the block has been dragged far away.
        // Use a slightly larger rect so small movements within the zone don't eject.
        let ejectInset: CGFloat = -40  // 40pt grace zone before ejecting
        for cluster in clusterEngine.userClusters {
            let expandedRect = cluster.boundingRect.insetBy(dx: ejectInset, dy: ejectInset)
            if cluster.blockUUIDs.contains(blockUUID) && !expandedRect.contains(position) {
                clusterEngine.removeBlockFromCluster(
                    blockUUID: blockUUID,
                    clusterId: cluster.id,
                    blocks: spatialEngine.blocks
                )
            }
        }

        // Recompute bounds so the zone visually expands to include the new block
        clusterEngine.updateUserClusterBounds(blocks: spatialEngine.blocks)
        // Recompute filtered blocks since cluster membership affects which blocks are visible
        
    }

    // MARK: - Cluster Drag Handlers

    /// Handle live cluster drag — single state write instead of N per-block writes
    private func handleClusterDrag(clusterId: UUID, translation: CGSize) {
        // Don't drag while a resize gesture is active (handles fire both)
        guard clusterEngine.resizingClusterId == nil else { return }

        if draggingClusterId != clusterId {
            draggingClusterId = clusterId
            draggingClusterMemberUUIDs = Set(clusterEngine.memberBlockUUIDs(for: clusterId))
        }
        clusterDragTranslation = translation
    }

    /// Commit cluster drag — move all member blocks to their new positions
    private func handleClusterDragEnd(clusterId: UUID, translation: CGSize) {
        // Don't commit drag if a resize gesture was active
        guard clusterEngine.resizingClusterId == nil else { return }

        let memberUUIDs: Set<String> = {
            if draggingClusterId == clusterId, !draggingClusterMemberUUIDs.isEmpty {
                return draggingClusterMemberUUIDs
            }
            return Set(clusterEngine.memberBlockUUIDs(for: clusterId))
        }()

        // Commit final positions
        for index in spatialEngine.blocks.indices {
            let block = spatialEngine.blocks[index]
            guard memberUUIDs.contains(block.entityUuid) else { continue }

            let newPosition = CGPoint(
                x: block.position.x + translation.width,
                y: block.position.y + translation.height
            )
            spatialEngine.blocks[index].position = newPosition
            spatialEngine.updateBlockPosition(block.id, position: newPosition)
        }

        // Move the cluster zone rect itself. This prevents list/board clusters from snapping
        // back to their previous origin and avoids grow-only recompute artifacts for canvas mode.
        clusterEngine.offsetClusterRect(id: clusterId, by: translation)

        // Clear cluster drag state
        clusterDragTranslation = .zero
        draggingClusterId = nil
        draggingClusterMemberUUIDs = []

        // Persist moved cluster + member block positions
        clusterEngine.persistAfterMove()
    }

    /// Clears any live drag preview offsets for a specific cluster.
    private func clearClusterDragPreview(clusterId: UUID) {
        clusterDragTranslation = .zero
        if draggingClusterId == clusterId {
            draggingClusterId = nil
            draggingClusterMemberUUIDs = []
        }
    }

    // Legacy handlers (kept for compatibility with other callers)
    private func handleDrag(blockId: String, translation: CGSize) {
        handleDragOptimized(blockId: blockId, translation: translation)
    }

    private func handleDragEnd(blockId: String) {
        if let offset = blockDragOffsets[blockId] {
            handleDragEndOptimized(blockId: blockId, translation: offset)
        }
    }

    private func handleTap(blockId: String) {
        // Only mutate the two blocks that actually changed (old selection + new selection)
        // to avoid copying/reassigning the entire blocks array and triggering a full canvas re-render.
        let previousId = selectedBlockId
        selectedBlockId = blockId

        // Deselect previous
        if let prevId = previousId, prevId != blockId,
           let prevIndex = spatialEngine.blocks.firstIndex(where: { $0.id == prevId }) {
            spatialEngine.blocks[prevIndex].isSelected = false
        }

        // Select new
        if let newIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) {
            spatialEngine.blocks[newIndex].isSelected = true
        }

        // Update ambient knowledge context if panel is visible
        if showAmbientPanel, let block = spatialEngine.blocks.first(where: { $0.id == blockId }) {
            let queryText = [block.title, block.subtitle ?? ""].joined(separator: " ")
            ambientEngine.updateContext(focusAtomUUID: block.entityUuid, currentText: queryText)
        }
    }

    // MARK: - Voice Command Handlers
    private func handlePlaceBlocks(notification: Notification, canvasSize: CGSize) {
        guard let userInfo = notification.userInfo,
              let query = userInfo["query"] as? String,
              let entityTypeString = userInfo["entityType"] as? String,
              let quantity = userInfo["quantity"] as? Int else {
            return
        }

        // Ignore if Focus Mode is active (let DocumentBlocksLayer handle it)
        if appState.focusedEntity != nil {
            print("🚫 CanvasView ignoring placement command because Focus Mode is active")
            return
        }

        let entityType = EntityType(rawValue: entityTypeString) ?? .idea
        let layoutString = userInfo["layout"] as? String ?? "orbital"
        let layout = LayoutStyle(rawValue: layoutString) ?? .orbital

        // Optional: place relative to an anchor block ("to the right of this block", etc.)
        let anchorBlockId = userInfo["anchorBlockId"] as? String
        let placement = (userInfo["placement"] as? String)?.lowercased()
        let spacing = userInfo["spacing"] as? CGFloat ?? 360

        var centerOverride: CGPoint? = nil
        if let anchorBlockId,
           let placement,
           let anchor = spatialEngine.blocks.first(where: { $0.id == anchorBlockId }) {
            let dx = (anchor.size.width / 2) + spacing
            let dy = (anchor.size.height / 2) + spacing

            switch placement {
            case "right":
                centerOverride = CGPoint(x: anchor.position.x + dx, y: anchor.position.y)
            case "left":
                centerOverride = CGPoint(x: anchor.position.x - dx, y: anchor.position.y)
            case "above", "up", "top":
                centerOverride = CGPoint(x: anchor.position.x, y: anchor.position.y + dy)
            case "below", "under", "down", "bottom":
                centerOverride = CGPoint(x: anchor.position.x, y: anchor.position.y - dy)
            default:
                break
            }
        }

        Task {
            try? await spatialEngine.placeBlocks(
                query: query,
                entityType: entityType,
                quantity: quantity,
                layout: layout,
                canvasSize: canvasSize,
                centerOverride: centerOverride
            )
        }
    }

    private func handleMoveBlocks(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let directionString = userInfo["direction"] as? String else {
            return
        }

        let direction = Direction(rawValue: directionString) ?? .right
        let distance = userInfo["distance"] as? CGFloat ?? 100

        spatialEngine.moveBlocks(direction: direction, distance: distance)
    }

    // MARK: - Magical Arrangement Handler
    private func handleArrangeBlocks(notification: Notification, canvasSize: CGSize) {
        guard let userInfo = notification.userInfo,
              let styleString = userInfo["style"] as? String,
              let style = LayoutStyle(rawValue: styleString) else {
            return
        }

        // Instant, magical arrangement!
        spatialEngine.arrangeBlocks(style: style, canvasSize: canvasSize)
    }

    // MARK: - Cosmo AI Block Creation
    private func handleCreateCosmoAIBlock(notification: Notification) {
        // Skip if focus mode is active - FocusCanvasView handles it there
        guard appState.focusedEntity == nil else {
            print("⏭️ Skipping Cosmo AI block creation on main canvas - focus mode active")
            return
        }

        var screenPosition = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        if let userInfo = notification.userInfo,
           let pos = userInfo["position"] as? CGPoint {
            screenPosition = pos
        }

        // Convert screen position to canvas position (accounting for zoom)
        let canvasPosition = screenToCanvasPosition(screenPosition)

        let query = notification.userInfo?["query"] as? String
        let mode = notification.userInfo?["mode"] as? String

        // Create the Cosmo AI block with query and mode for auto-execution
        let block = CanvasBlock.cosmoAIBlock(position: canvasPosition, query: query, mode: mode)

        Task {
            await spatialEngine.addBlock(block, persist: true)
        }

        if let query = query, !query.isEmpty {
            print("✨ Created Cosmo AI block with auto-query: \(query)")
        } else {
            print("✨ Created Cosmo AI block at \(canvasPosition)")
        }
    }

    // MARK: - Note Block Creation
    private func handleCreateNoteBlock(notification: Notification) {
        var screenPosition = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        if let userInfo = notification.userInfo,
           let pos = userInfo["position"] as? CGPoint {
            screenPosition = pos
        }

        // Convert screen position to canvas position (accounting for zoom)
        let canvasPosition = screenToCanvasPosition(screenPosition)

        // Create the note block
        let block = CanvasBlock.noteBlock(position: canvasPosition)

        Task {
            await spatialEngine.addBlock(block, persist: true)
        }

        print("📝 Created note block at \(canvasPosition)")
    }

    // MARK: - Block Removal
    private func handleRemoveBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String else {
            return
        }

        // Snapshot block before removal for undo
        if let block = spatialEngine.blocks.first(where: { $0.id == blockId }) {
            CosmoUndoManager.shared.register(
                DeleteBlockAction(block: block, spatialEngine: spatialEngine)
            )
        }

        Task {
            await spatialEngine.removeBlock(blockId)
        }
    }

    // MARK: - Inbox Block Handlers

    private func handleCreateInboxBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let block = userInfo["block"] as? InboxViewBlock else {
            print("⚠️ No inbox block in notification")
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            inboxBlocks.append(block)
        }

        // Persist immediately so the new block survives app restart
        saveInboxBlockPositions()

        print("📬 Created inbox block: \(block.title)")
    }

    private func handleCloseInboxBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String else {
            print("⚠️ No blockId in close notification")
            return
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            inboxBlocks.removeAll { $0.id.uuidString == blockId }
        }

        // Persist the removal so it doesn't reappear on app restart
        saveInboxBlockPositions()

        print("📪 Closed inbox block: \(blockId)")
    }

    private func handleUpdateInboxBlockPosition(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockIdString = userInfo["blockId"] as? String,
              let blockId = UUID(uuidString: blockIdString),
              let x = userInfo["x"] as? CGFloat,
              let y = userInfo["y"] as? CGFloat else {
            print("⚠️ Invalid inbox block position update")
            return
        }

        let isDragging = userInfo["isDragging"] as? Bool ?? false

        if let index = inboxBlocks.firstIndex(where: { $0.id == blockId }) {
            // Update position immediately (no animation during drag for smooth tracking)
            inboxBlocks[index].x = x
            inboxBlocks[index].y = y

            // Only save to UserDefaults when drag ends (not during drag)
            if !isDragging {
                saveInboxBlockPositions()
                print("📍 Saved inbox block position: \(blockIdString) -> (\(x), \(y))")
            }
        }
    }

    private func handleUpdateInboxBlockSize(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockIdString = userInfo["blockId"] as? String,
              let blockId = UUID(uuidString: blockIdString),
              let width = userInfo["width"] as? CGFloat,
              let height = userInfo["height"] as? CGFloat else {
            print("⚠️ Invalid inbox block size update")
            return
        }

        if let index = inboxBlocks.firstIndex(where: { $0.id == blockId }) {
            // Update size
            inboxBlocks[index].width = width
            inboxBlocks[index].height = height

            // Apply position adjustment to keep top-left corner anchored
            if let posAdjustX = userInfo["positionAdjustX"] as? CGFloat,
               let posAdjustY = userInfo["positionAdjustY"] as? CGFloat {
                inboxBlocks[index].x += posAdjustX
                inboxBlocks[index].y += posAdjustY
            }

            // Persist to UserDefaults
            saveInboxBlockPositions()
            print("📐 Saved inbox block size: \(blockIdString) -> (\(width) x \(height))")
        }
    }

    private func saveInboxBlockPositions() {
        do {
            let data = try JSONEncoder().encode(inboxBlocks)
            UserDefaults.standard.set(data, forKey: "inboxBlockPositions")
        } catch {
            print("⚠️ Failed to save inbox block positions: \(error)")
        }
    }

    private func loadInboxBlockPositions() {
        guard let data = UserDefaults.standard.data(forKey: "inboxBlockPositions") else { return }
        do {
            let blocks = try JSONDecoder().decode([InboxViewBlock].self, from: data)
            inboxBlocks = blocks
            print("📬 Loaded \(blocks.count) inbox blocks from storage")
        } catch {
            print("⚠️ Failed to load inbox block positions: \(error)")
        }
    }

    // MARK: - Block Expansion Voice Command Handlers

    private func handleExpandSelectedBlock() {
        guard let blockId = selectedBlockId else {
            print("⚠️ No block selected to expand")
            return
        }

        withAnimation(BlockAnimations.expand) {
            expansionManager.expand(blockId)
        }
    }

    private func handleOpenSelectedBlockInFocusMode() {
        guard let blockId = selectedBlockId,
              let block = spatialEngine.blocks.first(where: { $0.id == blockId }) else {
            print("⚠️ No block selected to open in focus mode")
            return
        }

        // Only applicable types can enter focus mode
        if [.idea, .content, .research, .connection].contains(block.entityType) {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": block.entityType, "id": block.entityId]
            )
        }
    }

    // MARK: - Smart Block Reference Handlers (by ID)

    private func handleDeleteSpecificBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String else {
            return
        }

        Task {
            await spatialEngine.removeBlock(blockId)
        }
        print("🗑️ Deleted block by ID: \(blockId)")
    }

    private func handleDuplicateBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let block = spatialEngine.blocks.first(where: { $0.id == blockId }) else {
            return
        }

        // Create duplicate with offset position
        var newBlock = block
        newBlock.position = CGPoint(x: block.position.x + 50, y: block.position.y + 50)

        Task {
            await spatialEngine.addBlock(newBlock, persist: true)
        }
        print("📋 Duplicated block: \(blockId)")
    }

    private func handleMoveBlockToTime(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let time = userInfo["time"] as? String else {
            return
        }

        // Post to scheduler system to handle time-based placement
        NotificationCenter.default.post(
            name: .voiceCreateScheduleBlock,
            object: nil,
            userInfo: [
                "blockId": blockId,
                "time": time
            ]
        )
        print("📍 Moving block \(blockId) to time: \(time)")
    }

    // MARK: - Smart Block Reference Handlers (by Content Search)

    private func handleDeleteBlockByContent(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let searchQuery = userInfo["searchQuery"] as? String else {
            return
        }

        let entityType = userInfo["entityType"] as? String

        // Find block matching search query
        if let matchingBlock = findBlockByContent(searchQuery, entityType: entityType) {
            Task {
                await spatialEngine.removeBlock(matchingBlock.id)
            }
            print("🗑️ Deleted block matching '\(searchQuery)'")
        } else {
            print("⚠️ No block found matching '\(searchQuery)'")
        }
    }

    private func handleExpandBlockByContent(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let searchQuery = userInfo["searchQuery"] as? String else {
            return
        }

        let entityType = userInfo["entityType"] as? String

        // Find and expand block matching search query
        if let matchingBlock = findBlockByContent(searchQuery, entityType: entityType) {
            withAnimation(BlockAnimations.expand) {
                expansionManager.expand(matchingBlock.id)
            }
            print("📐 Expanded block matching '\(searchQuery)'")
        } else {
            print("⚠️ No block found matching '\(searchQuery)'")
        }
    }

    private func handleDuplicateBlockByContent(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let searchQuery = userInfo["searchQuery"] as? String else {
            return
        }

        let entityType = userInfo["entityType"] as? String

        // Find and duplicate block matching search query
        if let matchingBlock = findBlockByContent(searchQuery, entityType: entityType) {
            var newBlock = matchingBlock
            newBlock.position = CGPoint(x: matchingBlock.position.x + 50, y: matchingBlock.position.y + 50)

            Task {
                await spatialEngine.addBlock(newBlock, persist: true)
            }
            print("📋 Duplicated block matching '\(searchQuery)'")
        } else {
            print("⚠️ No block found matching '\(searchQuery)'")
        }
    }

    private func handleMoveBlockByContentToTime(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let searchQuery = userInfo["searchQuery"] as? String,
              let time = userInfo["time"] as? String else {
            return
        }

        let entityType = userInfo["entityType"] as? String

        // Find block and move to calendar time
        if let matchingBlock = findBlockByContent(searchQuery, entityType: entityType) {
            NotificationCenter.default.post(
                name: .voiceCreateScheduleBlock,
                object: nil,
                userInfo: [
                    "blockId": matchingBlock.id,
                    "title": matchingBlock.title,
                    "time": time
                ]
            )
            print("📍 Moving block matching '\(searchQuery)' to time: \(time)")
        } else {
            print("⚠️ No block found matching '\(searchQuery)'")
        }
    }

    // MARK: - Voice Command Handlers (LLM-First)

    /// Handle placing a newly created entity on canvas from voice command
    private func handlePlaceEntityOnCanvas(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let entityType = userInfo["entityType"] as? String,
              let title = userInfo["title"] as? String else {
            print("⚠️ placeEntityOnCanvas: Missing required fields")
            return
        }

        let entityId = userInfo["entityId"] as? Int64 ?? -1
        let entityUUID = userInfo["entityUUID"] as? String ?? UUID().uuidString
        let content = userInfo["content"] as? String ?? ""
        let positionString = userInfo["position"] as? String ?? "center"
        let targetBlockQuery = userInfo["targetBlockQuery"] as? String

        // Resolve position using PositionResolver
        let canvasSize = spatialEngine.blocks.isEmpty
            ? CGSize(width: 1920, height: 1080)
            : CGSize(width: 1920, height: 1080) // Will be updated by canvas bounds

        let position = PositionResolver.shared.resolve(
            positionString,
            targetBlockQuery: targetBlockQuery,
            canvasSize: canvasSize,
            selectedBlock: spatialEngine.blocks.first { $0.isSelected },
            allBlocks: spatialEngine.blocks
        )

        // Find non-overlapping position
        let finalPosition = PositionResolver.shared.findNonOverlappingPosition(
            near: position,
            existingBlocks: spatialEngine.blocks,
            canvasSize: canvasSize
        )

        // Create the block
        let block = CanvasBlock(
            position: finalPosition,
            size: CGSize(width: 280, height: 200),
            entityType: EntityType(rawValue: entityType) ?? .idea,
            entityId: entityId,
            entityUuid: entityUUID,
            title: title,
            subtitle: content.isEmpty ? "Created by voice" : String(content.prefix(100)),
            metadata: ["created": ISO8601DateFormatter().string(from: Date())]
        )

        // Add to canvas with spring animation
        Task { @MainActor in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                spatialEngine.blocks.append(block)
            }
            await spatialEngine.saveBlock(block)
            print("✅ Placed \(entityType) block on canvas: \(title) at \(finalPosition)")
        }
    }

    /// Handle block resize from voice command
    private func handleResizeSelectedBlock(notification: Notification) {
        guard let selectedBlock = spatialEngine.blocks.first(where: { $0.isSelected }),
              let index = spatialEngine.blocks.firstIndex(where: { $0.id == selectedBlock.id }) else {
            print("⚠️ resizeSelectedBlock: No block selected")
            return
        }

        let width = notification.userInfo?["width"] as? CGFloat
        let height = notification.userInfo?["height"] as? CGFloat
        let scale = notification.userInfo?["scale"] as? CGFloat ?? 1.0

        // Calculate new size
        var newSize = selectedBlock.size
        if let w = width { newSize.width = w }
        if let h = height { newSize.height = h }
        if scale != 1.0 {
            newSize.width *= scale
            newSize.height *= scale
        }

        // Apply resize with animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            spatialEngine.blocks[index].size = newSize
        }

        // Recompute cluster bounds so zones expand/shrink with resized blocks
        clusterEngine.updateUserClusterBounds(blocks: spatialEngine.blocks)

        print("✅ Resized block to \(newSize)")
    }

    // MARK: - Entity Creation Helpers (Immediate DB-backed blocks)

    private func createIdeaBlock(at position: CGPoint, prefillContent: String? = nil, prefillTitle: String? = nil) {
        Task { @MainActor in
            do {
                let content = prefillContent ?? ""
                let titleFromContent: String = prefillTitle ?? {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return "New Idea" }
                    let firstLine = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? trimmed
                    return String(firstLine.prefix(60))
                }()

                let savedIdea = try await CosmoDatabase.shared.asyncWrite { db -> Idea in
                    var idea = Idea.new(title: titleFromContent, content: content)
                    try idea.insert(db)
                    idea.id = db.lastInsertedRowID
                    return idea
                }

                let block = CanvasBlock.fromIdea(savedIdea, position: position)
                await spatialEngine.addBlock(block, persist: true)
                print("💡 Created idea block: ID \(savedIdea.id ?? -1)")
            } catch {
                print("❌ Failed to create idea in database: \(error)")

                // Fallback: create block without database entry (temporary)
                let fallbackBlock = CanvasBlock(
                    position: position,
                    size: CGSize(width: 280, height: 200),
                    entityType: .idea,
                    entityId: -1,
                    entityUuid: UUID().uuidString,
                    title: "New Idea",
                    subtitle: "Tap to edit...",
                    metadata: ["created": ISO8601DateFormatter().string(from: Date())]
                )
                await spatialEngine.addBlock(fallbackBlock, persist: false)
            }
        }
    }

    private func createContentBlock(at position: CGPoint, prefillBody: String? = nil, prefillTitle: String? = nil) {
        Task { @MainActor in
            do {
                let title = prefillTitle ?? "New Content"
                let savedAtom = try await AtomRepository.shared.createContent(
                    title: title,
                    body: prefillBody
                )

                let block = CanvasBlock.fromAtom(savedAtom, position: position)
                await spatialEngine.addBlock(block, persist: true)
                print("✅ Created content block: ID \(savedAtom.id ?? -1)")
            } catch {
                print("❌ Failed to create content atom: \(error)")
            }
        }
    }

    private func createTaskBlock(at position: CGPoint, prefillTitle: String? = nil, prefillDescription: String? = nil) {
        Task { @MainActor in
            do {
                let title = prefillTitle ?? "New Task"
                let savedTask = try await CosmoDatabase.shared.asyncWrite { db -> CosmoTask in
                    var task = CosmoTask.new(title: title, status: "todo")
                    if let description = prefillDescription {
                        task.description = description
                    }
                    try task.insert(db)
                    task.id = db.lastInsertedRowID
                    return task
                }

                let block = CanvasBlock.fromTask(savedTask, position: position)
                await spatialEngine.addBlock(block, persist: true)
                print("✅ Created task block: ID \(savedTask.id ?? -1)")
            } catch {
                print("❌ Failed to create task in database: \(error)")

                let fallbackBlock = CanvasBlock(
                    position: position,
                    size: CGSize(width: 280, height: 140),
                    entityType: .task,
                    entityId: -1,
                    entityUuid: UUID().uuidString,
                    title: prefillTitle ?? "New Task",
                    subtitle: nil,
                    metadata: ["status": "todo", "created": ISO8601DateFormatter().string(from: Date())]
                )
                await spatialEngine.addBlock(fallbackBlock, persist: false)
            }
        }
    }

    private func createNewResearchBlock(at position: CGPoint, prefillTitle: String? = nil, prefillSummary: String? = nil) {
        Task { @MainActor in
            do {
                let title = prefillTitle ?? "New Research"
                let savedResearch = try await CosmoDatabase.shared.asyncWrite { db -> Research in
                    var research = Research.new(title: title, query: nil, url: nil, sourceType: .unknown)
                    if let summary = prefillSummary {
                        research.summary = summary
                    }
                    try research.insert(db)
                    research.id = db.lastInsertedRowID
                    return research
                }

                let block = CanvasBlock.fromResearch(savedResearch, position: position)
                await spatialEngine.addBlock(block, persist: true)
                print("🔬 Created research block: ID \(savedResearch.id ?? -1)")
            } catch {
                print("❌ Failed to create research in database: \(error)")

                let fallbackBlock = CanvasBlock(
                    position: position,
                    size: CGSize(width: 300, height: 220),
                    entityType: .research,
                    entityId: -1,
                    entityUuid: UUID().uuidString,
                    title: prefillTitle ?? "New Research",
                    subtitle: "Start researching...",
                    metadata: ["created": ISO8601DateFormatter().string(from: Date())]
                )
                await spatialEngine.addBlock(fallbackBlock, persist: false)
            }
        }
    }

    // MARK: - Connection Creation Helper

    /// Creates a new Connection in the database and adds a block for it
    private func createConnectionBlock(at position: CGPoint) {
        print("🔗 createConnectionBlock called at position: \(position)")

        Task { @MainActor in
            do {
                // Create connection in database
                print("🔗 Creating connection in database...")
                let savedConnection = try await CosmoDatabase.shared.asyncWrite { db -> Atom in
                    var connection = Atom.new(type: .connection, title: "New Connection")
                    try connection.insert(db)
                    connection.id = db.lastInsertedRowID
                    print("🔗 Connection inserted with id: \(connection.id ?? -999)")
                    return connection
                }

                print("🔗 Database write complete, connection id: \(savedConnection.id ?? -999)")

                // Create block with real connection ID
                let block = CanvasBlock(
                    position: position,
                    size: CGSize(width: 320, height: 280),
                    entityType: .connection,
                    entityId: savedConnection.id ?? -1,
                    entityUuid: savedConnection.uuid,
                    title: "New Connection",
                    subtitle: "Define your mental model...",
                    metadata: ["created": ISO8601DateFormatter().string(from: Date())]
                )

                await spatialEngine.addBlock(block, persist: true)
                print("🔗 Created connection block: ID \(savedConnection.id ?? -1)")

            } catch {
                print("❌ Failed to create connection in database: \(error)")
                print("❌ Error details: \(error.localizedDescription)")

                // Fallback: create block without database entry (temporary)
                // This ensures the user sees something even if DB fails
                let fallbackBlock = CanvasBlock(
                    position: position,
                    size: CGSize(width: 320, height: 280),
                    entityType: .connection,
                    entityId: -1,
                    entityUuid: UUID().uuidString,
                    title: "New Connection",
                    subtitle: "Define your mental model...",
                    metadata: ["created": ISO8601DateFormatter().string(from: Date())]
                )

                await spatialEngine.addBlock(fallbackBlock, persist: false)
                print("⚠️ Created fallback connection block without database entry")
            }
        }
    }

    // MARK: - Open Entity On Canvas (from Cmd+K)

    /// Opens an existing entity as a floating block on the canvas,
    /// or focuses/scrolls to it if it already exists.
    /// Supports two notification formats:
    ///   - `["type": EntityType, "id": Int64]` (from code paths that have both)
    ///   - `["atomUUID": String]` (from addSwipeToCanvas, addIdeaToCanvas, etc.)
    private func handleOpenEntityOnCanvas(notification: Notification) {
        guard let userInfo = notification.userInfo else {
            print("⚠️ handleOpenEntityOnCanvas: missing userInfo")
            return
        }

        // Path 1: Direct type + id (from code paths that have both)
        if let entityType = userInfo["type"] as? EntityType,
           let entityId = userInfo["id"] as? Int64 {
            Task {
                // Try to fetch atom for rich metadata
                let atom = try? await AtomRepository.shared.fetch(id: entityId)
                await openOrCreateBlock(entityType: entityType, entityId: entityId, atom: atom)
            }
            return
        }

        // Path 2: atomUUID (from addSwipeToCanvas, addIdeaToCanvas, etc.)
        if let atomUUID = userInfo["atomUUID"] as? String {
            Task {
                guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else {
                    print("⚠️ handleOpenEntityOnCanvas: atom not found for UUID \(atomUUID)")
                    return
                }
                let entityType = EntityType(rawValue: atom.type.rawValue) ?? .research
                let entityId = atom.id ?? Int64(0)
                await openOrCreateBlock(entityType: entityType, entityId: entityId, atom: atom)
            }
            return
        }

        print("⚠️ handleOpenEntityOnCanvas: missing type/id or atomUUID")
    }

    /// Creates or focuses an existing canvas block for the given entity.
    /// When an `atom` is provided, uses `CanvasBlock.fromAtom` for proper metadata and sizing.
    @MainActor
    private func openOrCreateBlock(entityType: EntityType, entityId: Int64, atom: Atom? = nil) async {
        // Check if a block for this entity already exists (match by entityId or by UUID)
        let existingBlock: CanvasBlock? = {
            if let atom = atom {
                return spatialEngine.blocks.first(where: {
                    ($0.entityType == entityType && $0.entityId == entityId) ||
                    $0.entityUuid == atom.uuid
                })
            }
            return spatialEngine.blocks.first(where: {
                $0.entityType == entityType && $0.entityId == entityId
            })
        }()

        if let existingBlock = existingBlock {
            // Focus and scroll to existing block
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                canvasOffset = CGSize(
                    width: -existingBlock.position.x + canvasSize.width / 2,
                    height: -existingBlock.position.y + canvasSize.height / 2
                )
            }

            // Select it - batch update to avoid race conditions
            var updatedBlocks = spatialEngine.blocks
            for index in updatedBlocks.indices {
                updatedBlocks[index].isSelected = (updatedBlocks[index].id == existingBlock.id)
            }
            spatialEngine.blocks = updatedBlocks
            selectedBlockId = existingBlock.id

            print("📍 Focused existing \(entityType) block for entity ID \(entityId)")
            return
        }

        // Calculate center position for new block
        let position = CGPoint(
            x: canvasSize.width / 2 - canvasOffset.width,
            y: canvasSize.height / 2 - canvasOffset.height
        )

        // Create block — use CanvasBlock.fromAtom when atom is available for rich metadata + proper sizing
        let block: CanvasBlock
        if let atom = atom {
            block = CanvasBlock.fromAtom(atom, position: position)
        } else {
            // Fallback: no atom available, create with basic metadata
            switch entityType {
            case .idea, .content, .research, .connection:
                block = CanvasBlock(
                    position: position,
                    size: CGSize(width: 320, height: 280),
                    entityType: entityType,
                    entityId: entityId,
                    entityUuid: UUID().uuidString,
                    title: entityType.rawValue.capitalized,
                    subtitle: nil,
                    metadata: [:]
                )
            default:
                // For other types, open Focus Mode instead
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": entityType, "id": entityId]
                )
                return
            }
        }

        await spatialEngine.addBlock(block, persist: true)
        selectedBlockId = block.id

        print("🆕 Created \(entityType) floating block for entity ID \(entityId)")
    }

    // MARK: - Cmd+V Paste to Canvas (Images + URLs)

    /// Handles Cmd+V paste: checks for image data first, then falls back to URL classification
    private func handleCanvasPaste() async {
        // Check for image data on clipboard first
        let pasteboard = NSPasteboard.general

        // Try image data (screenshots, copied images)
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            await handleImagePaste(data: imageData, originalFilename: nil)
            return
        }

        // Try file URL (copied image file from Finder)
        if let fileURLData = pasteboard.data(forType: .fileURL),
           let fileURL = URL(dataRepresentation: fileURLData, relativeTo: nil),
           let uti = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
           uti.conforms(to: .image),
           let data = try? Data(contentsOf: fileURL) {
            await handleImagePaste(data: data, originalFilename: fileURL.lastPathComponent)
            return
        }

        // Fall through to URL handling
        guard let clipboardString = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardString.isEmpty else { return }

        // Only handle URLs
        let lower = clipboardString.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return }

        // Classify URL
        let classifier = SwipeURLClassifier()
        let classification = classifier.classify(clipboardString)

        // Don't create blocks for raw text (shouldn't happen given URL guard, but be safe)
        guard classification.isUrl else { return }

        // Create atom based on classification
        var atom: Atom
        let isYouTube = classification.sourceType == .youtube || classification.sourceType == .youtubeShort

        if isYouTube {
            // YouTube → research atom (NOT swipe)
            atom = Research.new(
                title: "YouTube Video",
                url: clipboardString,
                sourceType: classification.sourceType
            )
            atom.processingStatus = "pending"
            if let videoId = classification.contentId {
                var richContent = ResearchRichContent()
                richContent.sourceType = classification.sourceType
                richContent.videoId = videoId
                atom.setRichContent(richContent)
            }
        } else {
            // Social platforms → swipe atom
            switch classification.sourceType {
            case .instagram, .instagramReel, .instagramPost, .instagramCarousel:
                let igType: ResearchRichContent.InstagramContentType = {
                    switch classification.sourceType {
                    case .instagramReel: return .reel
                    case .instagramCarousel: return .carousel
                    default: return .post
                    }
                }()
                atom = Atom.swipeFromInstagram(
                    instagramId: classification.contentId ?? "",
                    url: clipboardString,
                    hook: nil,
                    type: igType
                )
            case .twitter, .xPost:
                atom = Atom.swipeFromXPost(
                    tweetId: classification.contentId ?? "",
                    url: clipboardString,
                    hook: nil
                )
            case .threads:
                atom = Atom.swipeFromThreads(
                    threadId: classification.contentId ?? "",
                    url: clipboardString,
                    hook: nil
                )
            case .tiktok:
                atom = Atom.newSwipeFile(
                    url: clipboardString,
                    hook: nil,
                    sourceType: .tiktok,
                    contentSource: .clipboard
                )
            default:
                // Generic URL → research atom (not swipe)
                atom = Research.new(
                    title: "Research",
                    url: clipboardString,
                    sourceType: classification.sourceType
                )
                atom.processingStatus = "pending"
            }
        }

        // Save atom to database
        do {
            try await CosmoDatabase.shared.asyncWrite { db in
                try atom.insert(db)
            }
        } catch {
            print("⚠️ [CanvasView] Failed to save pasted atom: \(error)")
            return
        }

        // Create block at center of current viewport
        let position = CGPoint(
            x: canvasSize.width / 2 - canvasOffset.width,
            y: canvasSize.height / 2 - canvasOffset.height
        )
        let block = CanvasBlock.fromAtom(atom, position: position)
        await spatialEngine.addBlock(block, persist: true)
        selectedBlockId = block.id
        rebuildMediaContentCache()
        

        print("📋 Pasted \(classification.sourceType.rawValue) URL → canvas block (uuid: \(atom.uuid))")

        // Trigger background processing
        let atomUUID = atom.uuid
        let sourceType = classification.sourceType
        Task {
            await processCanvasPastedAtom(uuid: atomUUID, sourceType: sourceType, contentId: classification.contentId)
        }
    }

    /// Handles pasting image data from clipboard — saves to disk, creates atom + block
    private func handleImagePaste(data: Data, originalFilename: String?) async {
        do {
            let result = try ImageStore.save(data, originalFilename: originalFilename)
            let imageMeta = ImageMetadata(
                imagePath: result.path,
                originalFilename: originalFilename,
                width: result.width,
                height: result.height,
                fileSize: data.count
            )
            let metadataJson = try? JSONEncoder().encode(imageMeta)
            let metadataString = metadataJson.flatMap { String(data: $0, encoding: .utf8) }
            let atom = Atom.new(
                type: .image,
                title: originalFilename ?? "Image",
                body: result.path,
                metadata: metadataString
            )
            try await CosmoDatabase.shared.asyncWrite { db in
                var mutableAtom = atom
                try mutableAtom.insert(db)
            }
            let position = CGPoint(
                x: canvasSize.width / 2 - canvasOffset.width,
                y: canvasSize.height / 2 - canvasOffset.height
            )
            let block = CanvasBlock.fromAtom(atom, position: position)
            await spatialEngine.addBlock(block, persist: true)
            selectedBlockId = block.id
            
            print("📋 Pasted image → canvas block (uuid: \(atom.uuid))")
        } catch {
            print("⚠️ [CanvasView] Failed to paste image: \(error)")
        }
    }

    /// Background processing for a pasted atom — transcription, analysis, metadata enrichment
    private func processCanvasPastedAtom(uuid: String, sourceType: ResearchRichContent.SourceType, contentId: String?) async {
        let isYouTube = sourceType == .youtube || sourceType == .youtubeShort

        if isYouTube, let videoId = contentId {
            // YouTube research: fetch metadata + captions via YouTubeProcessor
            do {
                let ytData = try await YouTubeProcessor.shared.process(videoId: videoId)

                // Update atom with fetched data
                if var atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    atom.title = ytData.title
                    atom.body = ytData.transcript.map(\.text).joined(separator: " ")
                    atom.thumbnailUrl = ytData.thumbnailURL?.absoluteString
                    atom.processingStatus = "complete"

                    // Update rich content with transcript
                    var richContent = atom.richContent ?? ResearchRichContent()
                    richContent.transcript = atom.body
                    richContent.transcriptStatus = ytData.transcriptStatus.rawValue
                    richContent.title = ytData.title
                    richContent.author = ytData.channelName
                    atom.setRichContent(richContent)

                    try await CosmoDatabase.shared.asyncWrite { db in
                        try atom.update(db)
                    }
                    print("✅ [CanvasView] YouTube processing complete for \(uuid)")
                }
            } catch {
                print("⚠️ [CanvasView] YouTube processing failed for \(uuid): \(error)")
                // Mark as complete even on failure so shimmer stops
                if var atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    atom.processingStatus = "complete"
                    try? await CosmoDatabase.shared.asyncWrite { db in try atom.update(db) }
                }
            }
        } else {
            // Swipe processing: use existing pipeline
            SwipeProcessingService.shared.processSwipeInBackground(uuid: uuid)
            // SwipeProcessingService runs asynchronously — wait for it to finish
            // Poll briefly to detect completion for notification
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                if !SwipeProcessingService.shared.isProcessing(uuid: uuid) { break }
            }
        }

        // Post completion notification so block views can refresh
        NotificationCenter.default.post(
            name: .canvasAtomProcessed,
            object: nil,
            userInfo: ["atomUUID": uuid]
        )
    }

    // MARK: - Ambient Pull-to-Canvas

    private func handlePullAmbientToCanvas(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let atomUUID = userInfo["atomUUID"] as? String,
              let sourceBlockUUID = userInfo["sourceBlockUUID"] as? String else { return }

        Task { @MainActor in
            guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else {
                print("AmbientPull: atom not found for UUID \(atomUUID)")
                return
            }

            // Position 200px to the right of the source block
            let sourceBlock = spatialEngine.blocks.first(where: { $0.entityUuid == sourceBlockUUID })
            let position: CGPoint
            if let source = sourceBlock {
                position = CGPoint(
                    x: source.position.x + source.size.width + 200,
                    y: source.position.y
                )
            } else {
                position = CGPoint(
                    x: canvasSize.width / 2 - canvasOffset.width + 200,
                    y: canvasSize.height / 2 - canvasOffset.height
                )
            }

            // Create canvas block from atom
            let block = CanvasBlock.fromAtom(atom, position: position)

            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                spatialEngine.blocks.append(block)
            }
            await spatialEngine.saveBlock(block)

            // Create bidirectional AtomLink between source and pulled atom
            await createBidirectionalLink(sourceUUID: sourceBlockUUID, targetUUID: atomUUID)

            print("Ambient: Pulled \(atom.type.rawValue) '\(atom.title ?? "Untitled")' to canvas")
        }
    }

    /// Creates a bidirectional .related link between two atoms
    @MainActor
    private func createBidirectionalLink(sourceUUID: String, targetUUID: String) async {
        // Link source -> target
        if var sourceAtom = try? await AtomRepository.shared.fetch(uuid: sourceUUID) {
            var links = sourceAtom.linksList
            guard !links.contains(where: { $0.uuid == targetUUID && $0.type == AtomLinkType.related.rawValue }) else { return }
            links.append(AtomLink(linkType: .related, uuid: targetUUID))
            if let data = try? JSONEncoder().encode(links),
               let json = String(data: data, encoding: .utf8) {
                sourceAtom.links = json
                sourceAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
                sourceAtom.localVersion += 1
                try? await AtomRepository.shared.update(sourceAtom)
            }
        }

        // Link target -> source
        if var targetAtom = try? await AtomRepository.shared.fetch(uuid: targetUUID) {
            var links = targetAtom.linksList
            guard !links.contains(where: { $0.uuid == sourceUUID && $0.type == AtomLinkType.related.rawValue }) else { return }
            links.append(AtomLink(linkType: .related, uuid: sourceUUID))
            if let data = try? JSONEncoder().encode(links),
               let json = String(data: data, encoding: .utf8) {
                targetAtom.links = json
                targetAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
                targetAtom.localVersion += 1
                try? await AtomRepository.shared.update(targetAtom)
            }
        }
    }

    // MARK: - Content Search Helper

    private func findBlockByContent(_ query: String, entityType: String?) -> CanvasBlock? {
        let lowercaseQuery = query.lowercased()

        return spatialEngine.blocks.first { block in
            // Filter by entity type if specified
            if let typeString = entityType, typeString != "any" {
                if let type = EntityType(rawValue: typeString), block.entityType != type {
                    return false
                }
            }

            // Match against title or subtitle
            let titleMatch = block.title.lowercased().contains(lowercaseQuery)
            let subtitleMatch = block.subtitle?.lowercased().contains(lowercaseQuery) ?? false

            return titleMatch || subtitleMatch
        }
    }
}

// MARK: - Floating Block View
struct FloatingBlockView: View {
    let block: CanvasBlock
    @State private var isHovered = false
    private let referenceSize = CGSize(width: 280, height: 180)

    private var contentScale: CGFloat {
        let area = max(block.size.width * block.size.height, 1)
        let referenceArea = referenceSize.width * referenceSize.height
        return max(sqrt(area / referenceArea), 0.5)
    }

    private var unscaledSize: CGSize {
        CGSize(
            width: block.size.width / contentScale,
            height: block.size.height / contentScale
        )
    }

    // Get the pastel color for this entity type
    private var blockColor: Color {
        switch block.entityType {
        case .idea: return DS.entityIdea
        case .content: return DS.entityContent
        case .task: return DS.entityTask
        case .research: return DS.entityResearch
        case .note: return DS.entityNote
        case .cosmoAI: return DS.accent
        default: return DS.textMuted
        }
    }

    var body: some View {
        WindowChromeView(
            title: block.title,
            icon: block.entityType.icon,
            iconColor: blockColor,
            onClose: {
                NotificationCenter.default.post(
                    name: .removeBlock,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            },
            onMinimize: nil,
            onMaximize: {
                // Enter focus mode
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": block.entityType, "id": block.entityId]
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Subtitle/content preview
                if let subtitle = block.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(DS.textSecondary)
                        .lineLimit(4)
                }

                Spacer()

                // Metadata footer
                HStack(spacing: 8) {
                    ForEach(Array(block.metadata.prefix(2)), id: \.key) { key, value in
                        Text("\(key): \(value)")
                            .font(.system(size: 10))
                            .foregroundColor(DS.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(DS.borderSubtle.opacity(0.4))
                            .cornerRadius(4)
                    }

                    Spacer()

                    if block.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(DS.textMuted)
                    }
                }
            }
            .padding(12)
            .frame(width: unscaledSize.width, height: max(unscaledSize.height - 36, 0))
        }
        .frame(width: unscaledSize.width, height: unscaledSize.height)
        .scaleEffect(contentScale, anchor: .topLeading)
        .frame(width: block.size.width, height: block.size.height, alignment: .topLeading)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                NotificationCenter.default.post(
                    name: .openEntity,
                    object: nil,
                    userInfo: ["type": block.entityType, "id": block.entityId]
                )
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": block.entityType, "id": block.entityId]
                )
            } label: {
                Label("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Divider()

            Button {
                NotificationCenter.default.post(
                    name: .toggleBlockPin,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            } label: {
                Label(block.isPinned ? "Unpin" : "Pin to Home", systemImage: block.isPinned ? "pin.slash" : "pin")
            }

            Button {
                NotificationCenter.default.post(
                    name: .duplicateBlock,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Divider()

            Button(role: .destructive) {
                NotificationCenter.default.post(
                    name: .removeBlock,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            } label: {
                Label("Remove from Canvas", systemImage: "trash")
            }
        }
    }
}

// MARK: - Canvas Controls
struct CanvasControls: View {
    @ObservedObject var spatialEngine: SpatialEngine

    var body: some View {
        Button(action: { spatialEngine.clearCanvas() }) {
            Image(systemName: "trash")
                .font(.system(size: 16))
                .foregroundColor(DS.textSecondary)
                .frame(width: 40, height: 40)
                .background(DS.surfaceElevated)
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grid Pattern View (Infinite Tiling — Greenhouse Light Mode)
struct GridPatternView: View {
    var offset: CGSize = .zero  // Canvas pan offset for infinite tiling
    var scale: CGFloat = 1.0    // Zoom scale for infinite canvas effect

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            // Base spacing adjusted by scale - when zoomed out, dots appear closer together
            let baseSpacing: CGFloat = 40
            let spacing = baseSpacing * scale

            // Dot size also scales (but with a minimum to stay visible)
            let dotSize = max(1.5, 2.5 * scale)

            // Calculate offset modulo spacing for seamless tiling
            let offsetX = offset.width.truncatingRemainder(dividingBy: spacing)
            let offsetY = offset.height.truncatingRemainder(dividingBy: spacing)

            // Draw grid dots with offset - extends beyond visible area for smooth panning
            let startX = offsetX - spacing
            let startY = offsetY - spacing
            let endX = size.width + spacing
            let endY = size.height + spacing

            for x in stride(from: startX, to: endX, by: spacing) {
                for y in stride(from: startY, to: endY, by: spacing) {
                    let halfDot = dotSize / 2
                    let rect = CGRect(x: x - halfDot, y: y - halfDot, width: dotSize, height: dotSize)
                    // Warm gray dots visible on parchment canvas
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color(hex: "D8D7D3").opacity(0.5))
                    )
                }
            }
        }
    }
}

// MARK: - Thinkspace Aurora View (Subtle gradient zones)
struct ThinkspaceAuroraView: View {
    var body: some View {
        ZStack {
            // Top-left purple aurora
            RadialGradient(
                colors: [
                    DS.accent.opacity(0.015),
                    Color.clear
                ],
                center: UnitPoint(x: 0.1, y: 0.1),
                startRadius: 50,
                endRadius: 400
            )

            // Bottom-right green aurora
            RadialGradient(
                colors: [
                    Color(hex: "10B981").opacity(0.02),
                    Color.clear
                ],
                center: UnitPoint(x: 0.9, y: 0.85),
                startRadius: 50,
                endRadius: 350
            )

            // Center subtle blue
            RadialGradient(
                colors: [
                    Color(hex: "3B82F6").opacity(0.015),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.5),
                startRadius: 100,
                endRadius: 500
            )
        }
    }
}

// MARK: - Thinkspace Film Grain (REMOVED — replaced with static FilmGrainOverlay)
// ThinkspaceFilmGrain was generating ~11,500 random ellipses per frame.
// Now uses FilmGrainOverlay from Core/FilmGrainOverlay.swift which pre-generates
// a tiled CGImage once and reuses it. Same visual effect, zero per-frame cost.

// MARK: - Per-Block Container (Equatable diffing)
/// Extracted from blockView(for:) so SwiftUI can diff each block independently.
/// When only one block's `isSelected` changes, SwiftUI skips re-evaluating all other
/// CanvasBlockContainer instances whose inputs haven't changed.
struct CanvasBlockContainer: View, Equatable {
    let block: CanvasBlock
    let canvasOffset: CGSize
    let scaledPanOffset: CGSize
    let dragOffset: CGSize
    let isDragTarget: Bool
    let isMediaContent: Bool
    let isHeartbeating: Bool
    let isClusterMember: Bool
    let isDraggingClusterMember: Bool
    let heatmapOpacity: CGFloat
    let expansionOpacity: Double
    let expansionZIndex: Double
    let isCrossThinkspaceDragging: Bool

    // Closures — excluded from Equatable comparison
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: ((CGSize) -> Void)?
    var onDoubleTap: (() -> Void)?

    @EnvironmentObject private var expansionManager: BlockExpansionManager

    static func == (lhs: CanvasBlockContainer, rhs: CanvasBlockContainer) -> Bool {
        lhs.block == rhs.block &&
        lhs.canvasOffset == rhs.canvasOffset &&
        lhs.scaledPanOffset == rhs.scaledPanOffset &&
        lhs.dragOffset == rhs.dragOffset &&
        lhs.isDragTarget == rhs.isDragTarget &&
        lhs.isMediaContent == rhs.isMediaContent &&
        lhs.isHeartbeating == rhs.isHeartbeating &&
        lhs.isClusterMember == rhs.isClusterMember &&
        lhs.isDraggingClusterMember == rhs.isDraggingClusterMember &&
        lhs.heatmapOpacity == rhs.heatmapOpacity &&
        lhs.expansionOpacity == rhs.expansionOpacity &&
        lhs.expansionZIndex == rhs.expansionZIndex &&
        lhs.isCrossThinkspaceDragging == rhs.isCrossThinkspaceDragging
    }

    var body: some View {
        blockContent
            .expansionAware(blockId: block.id)
            .heartbeatAnimation(isActive: isHeartbeating)
            .position(
                x: block.position.x + canvasOffset.width + scaledPanOffset.width + dragOffset.width,
                y: block.position.y + canvasOffset.height + scaledPanOffset.height + dragOffset.height
            )
            .scaleEffect(block.scale)
            .rotationEffect(.degrees(block.rotation))
            .opacity(isCrossThinkspaceDragging ? 0 : block.opacity * expansionOpacity * heatmapOpacity)
            .zIndex(isDragTarget ? 1000 : (expansionZIndex + Double(block.zIndex)))
            .allowsHitTesting(!isClusterMember)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { gesture in
                        onDragChanged?(gesture.translation)
                    }
                    .onEnded { gesture in
                        onDragEnded?(gesture.translation)
                    }
            )
            .onTapGesture(count: 2) {
                onDoubleTap?()
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 0.95).combined(with: .opacity)
            ))
            .transaction { tx in
                if isDraggingClusterMember {
                    tx.animation = nil
                }
            }
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.entityType {
        case .cosmoAI:
            CosmoAIBlockView(block: block)
        case .note:
            NoteBlockView(block: block)
        case .calendar:
            CalendarWindowView(block: block)
        case .research:
            if isMediaContent {
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
        case .image:
            ImageBlockView(block: block)
        default:
            FloatingBlockView(block: block)
        }
    }
}

// MARK: - Metal Canvas Representable
struct MetalCanvasViewRepresentable: NSViewRepresentable {
    let blocks: [CanvasBlock]
    let gridEnabled: Bool

    func makeNSView(context: Context) -> MetalCanvasView {
        let view = MetalCanvasView(frame: .zero)
        view.gridEnabled = gridEnabled
        return view
    }

    func updateNSView(_ nsView: MetalCanvasView, context: Context) {
        nsView.blocks = blocks
        nsView.gridEnabled = gridEnabled
    }
}

// MARK: - Notifications
extension Notification.Name {
    // Note: placeBlocksOnCanvas, moveCanvasBlocks, expandSelectedBlock, closeSelectedBlock, and resizeSelectedBlock are defined in VoiceNotifications.swift
    // Unified with CosmoNotification.Navigation to prevent mismatched notification names
    static let enterFocusMode = CosmoNotification.Navigation.enterFocusMode
    static let openBlockInFocusMode = CosmoNotification.Navigation.openBlockInFocusMode
    static let openEntityOnCanvas = CosmoNotification.Navigation.openEntityOnCanvas
    static let createEntityInFocusMode = CosmoNotification.Navigation.createEntityInFocusMode
    static let switchToThinkspace = CosmoNotification.Navigation.switchToThinkspace

    static let toggleBlockPin = Notification.Name("toggleBlockPin")
    static let duplicateBlock = Notification.Name("duplicateBlock")
    static let removeBlock = Notification.Name("removeBlock")
    static let arrangeCanvasBlocks = Notification.Name("arrangeCanvasBlocks")
    static let createNoteBlock = Notification.Name("createNoteBlock")
    static let collapseExpandedBlock = Notification.Name("collapseExpandedBlock")
    static let addSwipeToCanvas = Notification.Name("addSwipeToCanvas")
    static let canvasAtomProcessed = Notification.Name("canvasAtomProcessed")
}

// MARK: - Cosmo Context Provider

@MainActor
class CanvasContextProvider: CosmoContextProvider {
    private weak var spatialEngine: SpatialEngine?

    init(spatialEngine: SpatialEngine) {
        self.spatialEngine = spatialEngine
    }

    var contextType: CosmoContextType { .thinkspaceCanvas }

    var contextSummary: String {
        let count = spatialEngine?.blocks.count ?? 0
        return "\(count) blocks on canvas"
    }

    var contextData: CosmoContextData {
        guard let blocks = spatialEngine?.blocks else {
            return CosmoContextData(viewSpecificData: ["blockCount": "0"])
        }

        var viewData: [String: String] = [
            "blockCount": "\(blocks.count)"
        ]

        // Summarize block types
        var typeCounts: [String: Int] = [:]
        for block in blocks {
            let type = block.entityType.rawValue
            typeCounts[type, default: 0] += 1
        }
        viewData["blockTypes"] = typeCounts.map { "\($0.key): \($0.value)" }.joined(separator: ", ")

        // Include titles of visible blocks (up to 20)
        let titles = blocks.prefix(20).compactMap { $0.title }.filter { !$0.isEmpty }
        if !titles.isEmpty {
            viewData["blockTitles"] = titles.joined(separator: " | ")
        }

        return CosmoContextData(
            viewSpecificData: viewData,
            visibleItemCount: blocks.count
        )
    }

    var availableActions: [CosmoWindowAction] { [] }
}
