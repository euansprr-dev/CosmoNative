// CosmoOS/Canvas/CanvasView.swift
// SwiftUI wrapper for Metal canvas with floating blocks

import SwiftUI
import GRDB

struct CanvasView: View {
    @StateObject private var spatialEngine = SpatialEngine()
    @StateObject private var expansionManager = BlockExpansionManager()
    @StateObject private var connectManager = DragToConnectManager()
    @EnvironmentObject var voiceEngine: VoiceEngine
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var blockFrameTracker: CanvasBlockFrameTracker

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

    // Inbox blocks state
    @State private var inboxBlocks: [InboxViewBlock] = []

    // PERFORMANCE: Drag offsets for inbox blocks - separate from array to avoid re-renders during drag
    @State private var inboxBlockDragOffsets: [UUID: CGSize] = [:]
    @State private var draggingInboxBlockId: UUID? = nil

    // Thinkspace sidebar state
    @State private var isSidebarVisible = false
    @StateObject private var thinkspaceManager = ThinkspaceManager.shared

    // Notification observer management - prevent duplicate registrations
    @State private var observersRegistered = false

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
                    blocksLayer
                    inboxBlocksLayer

                    // Connection lines render ON TOP of blocks so they're visible.
                    // Blocks have opaque backgrounds that would completely hide lines
                    // drawn behind them. allowsHitTesting(false) prevents interaction interference.
                    CanvasConnectionLinesLayer(
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
                .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: effectiveScale)

                // Drag-to-connect overlay (screen coordinates, outside scaled container)
                DragToConnectOverlay(
                    connectManager: connectManager,
                    blocks: spatialEngine.blocks,
                    canvasOffset: canvasOffset,
                    scaledPanOffset: scaledPanOffset,
                    effectiveScale: effectiveScale
                )
            }
            .environmentObject(expansionManager)
            .overlay(alignment: .topLeading) {
                // Controls overlay stays at screen coordinates (not zoomed)
                controlsOverlay
            }
            .overlay(alignment: .bottomTrailing) {
                // Zoom indicator
                zoomIndicator
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
            // Update block frame tracker for right-click hit-testing
            .onChange(of: spatialEngine.blocks.count) { _, _ in
                blockFrameTracker.updateFrames(
                    blocks: spatialEngine.blocks,
                    canvasOffset: canvasOffset,
                    scaledPanOffset: scaledPanOffset,
                    effectiveScale: effectiveScale,
                    screenCenter: screenCenter
                )
            }
            .onChange(of: canvasOffset) { _, _ in
                blockFrameTracker.updateFrames(
                    blocks: spatialEngine.blocks,
                    canvasOffset: canvasOffset,
                    scaledPanOffset: scaledPanOffset,
                    effectiveScale: effectiveScale,
                    screenCenter: screenCenter
                )
            }
            .onChange(of: canvasScale) { _, _ in
                blockFrameTracker.updateFrames(
                    blocks: spatialEngine.blocks,
                    canvasOffset: canvasOffset,
                    scaledPanOffset: scaledPanOffset,
                    effectiveScale: effectiveScale,
                    screenCenter: screenCenter
                )
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
                        .foregroundColor(.white.opacity(0.7))

                    // Reset zoom button
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            canvasScale = 1.0
                        }
                    } label: {
                        Image(systemName: "1.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CosmoColors.thinkspaceTertiary, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: CosmoColors.thinkspacePurple.opacity(0.2), radius: 8, y: 2)
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
                // Layer 1: Deep void base
                CosmoColors.thinkspaceVoid
                    .ignoresSafeArea()

                // Layer 2: Subtle aurora gradient zones (2-3% opacity)
                ThinkspaceAuroraView()
                    .ignoresSafeArea()

                // Layer 3: Infinite tiling grid - dark mode
                GridPatternView(
                    offset: CGSize(
                        width: canvasOffset.width + scaledPanOffset.width,
                        height: canvasOffset.height + scaledPanOffset.height
                    ),
                    scale: effectiveScale
                )
                    .ignoresSafeArea()

                // Layer 4: Film grain overlay
                ThinkspaceFilmGrain()
                    .ignoresSafeArea()
            }
            .drawingGroup() // GPU-accelerate visual background (no interactive elements)

            // Pan gesture layer - transparent but captures hits
            panGestureBackground
        }
    }

    private var blocksLayer: some View {
        ForEach(spatialEngine.blocks) { block in
            blockView(for: block)
        }
        // NOTE: Removed .drawingGroup() - it was breaking async image loading in blocks
        // like ResearchBlockView that load thumbnails asynchronously. GPU acceleration
        // is applied at the component level (GridPatternView, etc.) instead.
    }

    @ViewBuilder
    private func blockView(for block: CanvasBlock) -> some View {
        Group {
            switch block.entityType {
            case .cosmoAI:
                CosmoAIBlockView(block: block)
            case .note:
                NoteBlockView(block: block)
            case .calendar:
                CalendarWindowView(block: block)
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
        .expansionAware(blockId: block.id)
        // Position in canvas space (zoom is applied to container)
        .position(
            x: block.position.x + canvasOffset.width + scaledPanOffset.width + (blockDragOffsets[block.id]?.width ?? 0),
            y: block.position.y + canvasOffset.height + scaledPanOffset.height + (blockDragOffsets[block.id]?.height ?? 0)
        )
        // Block's own scale only (zoom is applied to container)
        .scaleEffect(block.scale)
        .rotationEffect(.degrees(block.rotation))
        .opacity(block.opacity * expansionManager.opacity(for: block.id))
        .zIndex(draggingBlockId == block.id ? 1000 : (expansionManager.zIndex(for: block.id) + Double(block.zIndex)))
        .gesture(
            DragGesture(minimumDistance: 2) // Small threshold to avoid accidental drags
                .onChanged { gesture in
                    if NSEvent.modifierFlags.contains(.option) {
                        // Option+drag: connection mode
                        let screenCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                        if !connectManager.isActive {
                            let blockX = block.position.x + canvasOffset.width + scaledPanOffset.width
                            let blockY = block.position.y + canvasOffset.height + scaledPanOffset.height
                            let scaledX = screenCenter.x + (blockX - screenCenter.x) * effectiveScale
                            let scaledY = screenCenter.y + (blockY - screenCenter.y) * effectiveScale
                            connectManager.beginConnection(from: block, center: CGPoint(x: scaledX, y: scaledY))
                        }
                        // Update drag point (gesture location is relative to block)
                        let blockScreenX = screenCenter.x + (block.position.x + canvasOffset.width + scaledPanOffset.width - screenCenter.x) * effectiveScale
                        let blockScreenY = screenCenter.y + (block.position.y + canvasOffset.height + scaledPanOffset.height - screenCenter.y) * effectiveScale
                        connectManager.updateDrag(to: CGPoint(
                            x: blockScreenX + gesture.translation.width,
                            y: blockScreenY + gesture.translation.height
                        ))
                        connectManager.checkTarget(
                            blocks: spatialEngine.blocks,
                            canvasOffset: canvasOffset,
                            scaledPanOffset: scaledPanOffset,
                            effectiveScale: effectiveScale,
                            screenCenter: screenCenter
                        )
                    } else {
                        // Normal drag: move block
                        handleDragOptimized(blockId: block.id, translation: gesture.translation)
                    }
                }
                .onEnded { gesture in
                    if connectManager.isActive {
                        // Complete or cancel connection
                        if let targetId = connectManager.hoveredTargetBlockId,
                           let targetBlock = spatialEngine.blocks.first(where: { $0.id == targetId }) {
                            connectManager.completeConnection(targetBlock: targetBlock)
                        } else {
                            connectManager.cancel()
                        }
                    } else {
                        handleDragEndOptimized(blockId: block.id, translation: gesture.translation)
                    }
                }
        )
        // NOTE: Single tap is handled by CosmoBlockWrapper via notification
        // Double tap for focus mode (only for entity types that support it)
        .onTapGesture(count: 2) {
            if [.idea, .content, .research, .connection, .cosmoAI].contains(block.entityType) {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": block.entityType, "id": block.entityId]
                )
            }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        ))
    }

    private var controlsOverlay: some View {
        VStack {
            HStack {
                if distanceFromOrigin > 400 {
                    CanvasRecenterButton {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            canvasOffset = .zero
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                Spacer()
                CanvasControls(spatialEngine: spatialEngine)
                    .padding()
            }
            Spacer()
        }
        .animation(.spring(response: 0.3), value: distanceFromOrigin > 400)
    }

    private var panGestureBackground: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                // Clear selection when tapping background (blur active blocks)
                // CRITICAL: Batch update to avoid multiple @Published notifications
                var updatedBlocks = spatialEngine.blocks
                for index in updatedBlocks.indices {
                    updatedBlocks[index].isSelected = false
                }
                spatialEngine.blocks = updatedBlocks
                selectedBlockId = nil

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
                        // Clamp scale to reasonable bounds with spring animation
                        let newScale = canvasScale * value.magnification
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            canvasScale = min(max(newScale, minScale), maxScale)
                        }
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

                // Load persisted blocks from database for current ThinkSpace
                Task { @MainActor in
                    let thinkspaceId = thinkspaceManager.currentThinkspace?.id
                    await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
                    await repairLegacyBlocksIfNeeded()
                }

                // Load persisted inbox blocks
                loadInboxBlockPositions()

                // Register notification observers only once
                guard !observersRegistered else { return }
                observersRegistered = true
                print("📡 Registering notification observers (first time only)")

                // Listen for ThinkSpace changes to reload blocks
                NotificationCenter.default.addObserver(
                    forName: CosmoNotification.Canvas.thinkspaceChanged,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        // Get thinkspaceId - could be String or NSNull (for default canvas)
                        let thinkspaceId: String?
                        if let id = notification.userInfo?["thinkspaceId"] as? String {
                            thinkspaceId = id
                        } else {
                            thinkspaceId = nil
                        }
                        await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
                        print("🔄 Reloaded blocks for ThinkSpace: \(thinkspaceId ?? "default")")
                    }
                }

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

                            // Smooth animation for zoom
                            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
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
            // Keyboard handler for ESC to collapse expanded blocks
            .onKeyPress(.escape) {
                if expansionManager.isAnyBlockExpanded {
                    withAnimation(BlockAnimations.collapse) {
                        expansionManager.collapse()
                    }
                    return .handled
                }
                return .ignored
            }
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
                    let savedConnection = try await CosmoDatabase.shared.asyncWrite { db -> Connection in
                        var connection = Connection.new(title: blockTitle.isEmpty ? "New Connection" : blockTitle)
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

    /// Distance from canvas origin (0,0) - used to show recenter button
    private var distanceFromOrigin: CGFloat {
        let totalOffsetX = canvasOffset.width + scaledPanOffset.width
        let totalOffsetY = canvasOffset.height + scaledPanOffset.height
        return sqrt(totalOffsetX * totalOffsetX + totalOffsetY * totalOffsetY)
    }

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
    }
    
    // MARK: - Save Block Size Handler
    private func handleSaveBlockSize(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String else {
            return
        }
        
        // Find the block and persist to database
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }
        
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
        // Scale translation by inverse of zoom so dragging feels natural
        // When zoomed out, 1px cursor movement = larger canvas movement
        let scaledTranslation = CGSize(
            width: translation.width / effectiveScale,
            height: translation.height / effectiveScale
        )
        blockDragOffsets[blockId] = scaledTranslation
        draggingBlockId = blockId

        // Mark selected (one-time update)
        if selectedBlockId != blockId {
            selectedBlockId = blockId
        }
    }

    /// Optimized drag end - commits position to @Published array and database
    private func handleDragEndOptimized(blockId: String, translation: CGSize) {
        // Scale translation by inverse of zoom to match canvas space
        let scaledTranslation = CGSize(
            width: translation.width / effectiveScale,
            height: translation.height / effectiveScale
        )

        // Commit final position to the @Published array (triggers one re-render)
        if let index = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) {
            let newPosition = CGPoint(
                x: spatialEngine.blocks[index].position.x + scaledTranslation.width,
                y: spatialEngine.blocks[index].position.y + scaledTranslation.height
            )
            spatialEngine.blocks[index].position = newPosition

            // Fire-and-forget position save to database
            spatialEngine.updateBlockPosition(blockId, position: newPosition)
        }

        // Clear local drag state
        blockDragOffsets.removeValue(forKey: blockId)
        draggingBlockId = nil

        // Update frame tracker after position change
        let screenCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        blockFrameTracker.updateFrames(
            blocks: spatialEngine.blocks,
            canvasOffset: canvasOffset,
            scaledPanOffset: scaledPanOffset,
            effectiveScale: effectiveScale,
            screenCenter: screenCenter
        )
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
        // CRITICAL FIX: Batch the selection update to avoid multiple @Published notifications
        // which can cause race conditions in Swift's type metadata system

        // 1. Create updated blocks array in one operation
        var updatedBlocks = spatialEngine.blocks
        for index in updatedBlocks.indices {
            updatedBlocks[index].isSelected = (updatedBlocks[index].id == blockId)
        }

        // 2. Single atomic assignment triggers only ONE objectWillChange
        spatialEngine.blocks = updatedBlocks
        selectedBlockId = blockId

        // 3. Post voice notification AFTER the UI update is complete
        // Use async to ensure SwiftUI has finished processing the state change
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .blockSelected,
                object: nil,
                userInfo: ["blockId": blockId]
            )
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
        // Create content block without database entry (same pattern as Note blocks)
        // Content is stored in metadata and persisted to canvas_blocks table
        var metadata: [String: String] = [
            "created": ISO8601DateFormatter().string(from: Date())
        ]

        if let title = prefillTitle, !title.isEmpty {
            metadata["title"] = title
        }
        if let body = prefillBody, !body.isEmpty {
            metadata["content"] = body
        }

        let block = CanvasBlock(
            position: position,
            size: CGSize(width: 320, height: 280),  // Match Note block size
            entityType: .content,
            entityId: -1,  // No database entry - content stored in metadata
            entityUuid: UUID().uuidString,
            title: prefillTitle ?? "Content",
            subtitle: nil,
            metadata: metadata
        )

        Task {
            await spatialEngine.addBlock(block, persist: true)
            print("📄 Created content block (metadata-based)")
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
                let savedConnection = try await CosmoDatabase.shared.asyncWrite { db -> Connection in
                    var connection = Connection.new(title: "New Connection")
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
    private func handleOpenEntityOnCanvas(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let entityType = userInfo["type"] as? EntityType,
              let entityId = userInfo["id"] as? Int64 else {
            print("⚠️ handleOpenEntityOnCanvas: missing userInfo or entity details")
            return
        }
        
        // Check if a block for this entity already exists
        if let existingBlock = spatialEngine.blocks.first(where: { 
            $0.entityType == entityType && $0.entityId == entityId 
        }) {
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
        
        // Create new block for the entity
        let position = CGPoint(
            x: canvasSize.width / 2 - canvasOffset.width,
            y: canvasSize.height / 2 - canvasOffset.height
        )
        
        // Create block based on entity type
        let block: CanvasBlock
        switch entityType {
        case .idea:
            block = CanvasBlock(
                position: position,
                size: CGSize(width: 320, height: 280),
                entityType: .idea,
                entityId: entityId,
                entityUuid: UUID().uuidString,
                title: "Idea",
                subtitle: nil,
                metadata: [:]
            )
        case .content:
            block = CanvasBlock(
                position: position,
                size: CGSize(width: 320, height: 280),
                entityType: .content,
                entityId: entityId,
                entityUuid: UUID().uuidString,
                title: "Content",
                subtitle: nil,
                metadata: [:]
            )
        case .research:
            block = CanvasBlock(
                position: position,
                size: CGSize(width: 320, height: 280),
                entityType: .research,
                entityId: entityId,
                entityUuid: UUID().uuidString,
                title: "Research",
                subtitle: nil,
                metadata: [:]
            )
        case .connection:
            block = CanvasBlock(
                position: position,
                size: CGSize(width: 320, height: 280),
                entityType: .connection,
                entityId: entityId,
                entityUuid: UUID().uuidString,
                title: "Connection",
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
        
        Task {
            await spatialEngine.addBlock(block, persist: true)
            
            // Select the new block
            await MainActor.run {
                selectedBlockId = block.id
            }
        }
        
        print("🆕 Created \(entityType) floating block for entity ID \(entityId)")
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

    // Get the pastel color for this entity type
    private var blockColor: Color {
        switch block.entityType {
        case .idea: return CosmoColors.lavender
        case .content: return CosmoColors.skyBlue
        case .task: return CosmoColors.coral
        case .research: return CosmoColors.emerald
        case .note: return CosmoColors.note
        case .cosmoAI: return CosmoColors.cosmoAI
        default: return CosmoColors.glassGrey
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
                        .foregroundColor(CosmoColors.textSecondary)
                        .lineLimit(4)
                }

                Spacer()

                // Metadata footer
                HStack(spacing: 8) {
                    ForEach(Array(block.metadata.prefix(2)), id: \.key) { key, value in
                        Text("\(key): \(value)")
                            .font(.system(size: 10))
                            .foregroundColor(CosmoColors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(CosmoColors.glassGrey.opacity(0.4))
                            .cornerRadius(4)
                    }

                    Spacer()

                    if block.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(CosmoColors.textTertiary)
                    }
                }
            }
            .padding(12)
            .frame(width: block.size.width, height: block.size.height - 36) // Subtract title bar height
        }
        .frame(width: block.size.width, height: block.size.height)
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
                .foregroundColor(CosmoColors.textSecondary)
                .frame(width: 40, height: 40)
                .background(CosmoColors.softWhite)
                .cornerRadius(10)
                .shadow(color: CosmoColors.glassGrey.opacity(0.4), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Canvas Recenter Button
/// Appears when canvas is panned far from origin, allows quick return to center
private struct CanvasRecenterButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 12, weight: .medium))
                Text("Recenter")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isHovered ? CosmoColors.textPrimary : CosmoColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CosmoColors.softWhite, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(CosmoColors.glassGrey.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: CosmoColors.glassGrey.opacity(isHovered ? 0.6 : 0.4), radius: isHovered ? 10 : 6, y: 2)
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Grid Pattern View (Infinite Tiling - Dark Mode)
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
                    // Dark grid color at 10% opacity
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(CosmoColors.thinkspaceGrid.opacity(0.1))
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
                    CosmoColors.thinkspacePurple.opacity(0.025),
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

// MARK: - Thinkspace Film Grain
struct ThinkspaceFilmGrain: View {
    var body: some View {
        Canvas { context, size in
            // Create subtle noise pattern
            for _ in 0..<Int(size.width * size.height / 200) {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                let grainSize = CGFloat.random(in: 0.5...1.5)
                let opacity = Double.random(in: 0.01...0.03)

                let rect = CGRect(x: x, y: y, width: grainSize, height: grainSize)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(opacity))
                )
            }
        }
        .blendMode(.overlay)
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
    static let enterFocusMode = Notification.Name("enterFocusMode")
    static let toggleBlockPin = Notification.Name("toggleBlockPin")
    static let duplicateBlock = Notification.Name("duplicateBlock")
    static let removeBlock = Notification.Name("removeBlock")
    // showCommandPalette is now defined in VoiceNotifications.swift
    static let arrangeCanvasBlocks = Notification.Name("arrangeCanvasBlocks")
    static let createNoteBlock = Notification.Name("createNoteBlock")
    static let collapseExpandedBlock = Notification.Name("collapseExpandedBlock")
    static let openBlockInFocusMode = Notification.Name("openBlockInFocusMode")
    static let openEntityOnCanvas = Notification.Name("openEntityOnCanvas")
    static let createEntityInFocusMode = Notification.Name("createEntityInFocusMode")
    static let switchToThinkspace = Notification.Name("switchToThinkspace")
    static let addSwipeToCanvas = Notification.Name("addSwipeToCanvas")
}
