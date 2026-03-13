// CosmoOS/Navigation/MainView.swift
// Sidebar + content area — Command Center is home, Thinkspaces are canvases

import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var database: CosmoDatabase
    @EnvironmentObject var voiceEngine: VoiceEngine
    @EnvironmentObject var glassCenter: CosmoGlassCenter
    @EnvironmentObject var swipeFileEngine: SwipeFileEngine

    // Observe ThinkspaceManager for sidebar visibility changes
    @ObservedObject private var thinkspaceManager = ThinkspaceManager.shared

    @State private var showRadialMenu = false
    @State private var radialMenuPosition: CGPoint = .zero
    @State private var rightClickMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var inAppVoiceHotkeyActive = false

    // Command-K (constellation-based search)
    @State private var showCommandK = false
    @State private var commandKReturnTab: CommandKView.CommandKTab? = nil
    @StateObject private var commandKViewModel = CommandKViewModel()

    // Block context menu (right-click on block)
    @StateObject private var blockFrameTracker = CanvasBlockFrameTracker()
    @State private var rightClickedBlockId: String?
    @State private var showBlockContextMenu = false
    @State private var blockContextMenuPosition: CGPoint = .zero

    // Navigation destination (Command Center is home)
    @State private var currentDestination: SidebarDestination = .commandCenter
    @State private var previousNonDimensionDestination: SidebarDestination = .commandCenter

    // Split-pane system
    @StateObject private var paneManager = PaneManager()

    // Deep work session engine (singleton — survives navigation changes)
    @ObservedObject private var sessionEngine = DeepWorkSessionEngine.shared

    // Cross-thinkspace drag manager (sidebar spring-loaded folders)
    @StateObject private var crossDragManager = CrossThinkspaceDragManager()

    // Activation loading overlay (shown during idea→content navigation)
    @State private var showActivationLoading = false
    @State private var activationLoadingMessage = ""

    // Creator database overlay
    @State private var showCreatorDatabase = false
    @State private var showCreatorProfile = false
    @State private var creatorProfileAtom: Atom?
    @State private var showSettings = false

    // Track last-used thinkspace for T-key shortcut
    @State private var lastThinkspaceId: String?

    // Sticky canvas thinkspace ID — persists when navigating to non-canvas destinations
    // so the CanvasView stays alive and doesn't reload on return
    @State private var canvasThinkspaceId: String? = nil

    var body: some View {
        ZStack {
            // Main layout: sidebar + content area
            mainContentLayout


            // Glass overlay for search results, clarifications, proactive suggestions
            if glassCenter.isVisible {
                VStack {
                    HStack {
                        Spacer()
                        CosmoGlassOverlayView()
                            .environmentObject(glassCenter)
                    }
                    Spacer()
                }
                .zIndex(60)
                .transition(.opacity)
            }

            // Global status indicator (bottom-right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    GlobalStatusPill()
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                }
            }
            .zIndex(40)

            // Focus mode is now rendered inside SplitPaneContainer above (z-index 195 when active)

            // Command-K - The Cognition Hub
            // Revolutionary spatial command center that replaces Finder and sidebars
            if showCommandK {
                CommandKView(initialTab: commandKReturnTab ?? .database)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(200)
            }

            // Instagram Swipe File Modal (manual entry for Instagram content)
            if swipeFileEngine.showInstagramModal {
                // Backdrop
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            swipeFileEngine.cancelInstagramSave()
                        }
                    }
                    .transition(.opacity)

                InstagramSwipeModal(
                    isPresented: $swipeFileEngine.showInstagramModal,
                    pendingItem: swipeFileEngine.pendingInstagramItem,
                    onSave: { hook, transcript in
                        await swipeFileEngine.completeInstagramSave(hook: hook, transcript: transcript)
                    },
                    onCancel: {
                        swipeFileEngine.cancelInstagramSave()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(275)
            }

            // SessionTimerBar — global floating overlay for deep work sessions
            if sessionEngine.activeSession != nil {
                SessionTimerBar(engine: sessionEngine)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .zIndex(50)
            }

            // Radial Menu (right-click creation) - no overlay, just the menu
            if showRadialMenu {
                // Invisible tap catcher to dismiss on click outside (no grey overlay)
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2)) {
                            showRadialMenu = false
                        }
                    }
                    .zIndex(149)

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
                .zIndex(150)
            }

            // Block Context Menu (right-click on block)
            if showBlockContextMenu, let blockId = rightClickedBlockId {
                // Dismiss backdrop
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2)) {
                            showBlockContextMenu = false
                            rightClickedBlockId = nil
                        }
                    }
                    .zIndex(149)

                BlockContextMenu(
                    blockId: blockId,
                    block: blockFrameTracker.trackedBlocks.first(where: { $0.id == blockId }) ?? CanvasBlock.placeholder,
                    position: blockContextMenuPosition,
                    selectedBlockIds: blockFrameTracker.trackedBlocks.filter(\.isSelected).map(\.id),
                    onDismiss: {
                        withAnimation(.spring(response: 0.2)) {
                            showBlockContextMenu = false
                            rightClickedBlockId = nil
                        }
                    }
                )
                .zIndex(150)
            }

            // Gemini thinking indicator (Apple Intelligence-style edge glow)
            GeminiThinkingOverlay()
                .zIndex(280)

            // Creator Database overlay
            if showCreatorDatabase {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showCreatorDatabase = false
                            }
                        }

                    CreatorListView(
                        onSelectCreator: { creatorAtom in
                            creatorProfileAtom = creatorAtom
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showCreatorProfile = true
                            }
                        },
                        onCompare: { _ in },
                        onClose: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showCreatorDatabase = false
                            }
                        }
                    )
                    .frame(maxWidth: 960, maxHeight: 700)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.5), radius: 30)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(285)
            }

            // Creator Profile overlay
            if showCreatorProfile, let profileAtom = creatorProfileAtom {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showCreatorProfile = false
                                creatorProfileAtom = nil
                            }
                        }

                    CreatorProfileView(
                        creatorAtom: profileAtom,
                        onClose: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showCreatorProfile = false
                                creatorProfileAtom = nil
                            }
                        },
                        onCompare: { _ in },
                        onOpenSwipe: { entityId in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showCreatorProfile = false
                                showCreatorDatabase = false
                                creatorProfileAtom = nil
                            }
                            withAnimation(.spring(response: 0.3)) {
                                appState.focusedEntity = EntitySelection(id: entityId, type: .research)
                            }
                        }
                    )
                    .frame(maxWidth: 1000, maxHeight: 750)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.5), radius: 30)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(286)
            }

            // Activation loading overlay (idea → content transition)
            if showActivationLoading {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(.white)

                        Text(activationLoadingMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity)
                .zIndex(290)
            }

            // Loading overlay
            if !database.isReady {
                LoadingView()
                    .zIndex(300)
            } else if let error = database.error {
                ErrorView(message: error)
                    .zIndex(300)
            }
        }
        // Global keyboard shortcuts handled via NSEvent monitor (doesn't steal focus from text fields)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showCommandK)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showRadialMenu)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: showBlockContextMenu)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appState.focusedEntity != nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: glassCenter.isVisible)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: swipeFileEngine.showInstagramModal)
        .animation(.easeInOut(duration: 0.25), value: showActivationLoading)
        .sheet(isPresented: $showSettings) {
            SanctuarySettingsView()
                .frame(width: 720, height: 540)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            withAnimation(.spring(response: 0.2)) {
                showCommandK = true
                appState.isCommandKVisible = true
            }
        }
        // NodeGraph Command-K atom opening handler
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.openAtomFromCommandK)) { notification in
            guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }
            handleOpenAtomFromCommandK(atomUUID: atomUUID)
        }
        // Command-K close handler (from background tap or escape in CommandKView)
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.closeCommandK)) { _ in
            withAnimation(.spring(response: 0.2)) {
                showCommandK = false
                appState.isCommandKVisible = false
                commandKViewModel.clear()
            }
        }
        // Cosmo Window toggle (from menu bar, Telegram, or other sources)
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.CosmoWindow.toggle)) { _ in
            CosmoWindowPanelController.shared.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .enterFocusMode)) { notification in
            if let type = notification.userInfo?["type"] as? EntityType,
               let id = notification.userInfo?["id"] as? Int64 {
                // Track if this focus mode was opened from Command K
                if let tabString = notification.userInfo?["commandKTab"] as? String {
                    switch tabString {
                    case "swipeGallery": commandKReturnTab = .swipeGallery
                    case "ideas": commandKReturnTab = .ideas
                    case "library": commandKReturnTab = .database
                    default: commandKReturnTab = nil
                    }
                } else {
                    commandKReturnTab = nil
                }
                withAnimation(.spring(response: 0.3)) {
                    appState.focusedEntity = EntitySelection(id: id, type: type)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exitFocusMode)) { _ in
            withAnimation(.spring(response: 0.3)) {
                appState.focusedEntity = nil
            }
        }
        // MARK: - Open as Pane
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openAsPane)) { notification in
            if let entityType = notification.userInfo?["type"] as? EntityType,
               let entityId = notification.userInfo?["id"] as? Int64 {
                guard paneManager.canOpen(entityId: entityId, appState: appState) else { return }
                withAnimation(ProMotionSprings.snappy) {
                    paneManager.openPane(.entity(EntitySelection(id: entityId, type: entityType)))
                }
            } else if let thinkspaceId = notification.userInfo?["thinkspaceId"] as? String {
                guard paneManager.canOpenThinkspace(thinkspaceId: thinkspaceId) else { return }
                withAnimation(ProMotionSprings.snappy) {
                    paneManager.openPane(.thinkspace(thinkspaceId: thinkspaceId))
                }
            } else if let rawDimension = notification.userInfo?["dimensionId"] as? String,
                      let dimension = LevelDimension(rawValue: rawDimension) {
                guard paneManager.canOpenDimension(dimension) else { return }
                withAnimation(ProMotionSprings.snappy) {
                    paneManager.openPane(.dimension(dimension))
                }
            } else if notification.userInfo?["commandCenter"] as? Bool == true {
                guard paneManager.canOpenCommandCenter() else { return }
                withAnimation(ProMotionSprings.snappy) {
                    paneManager.openPane(.commandCenter)
                }
            }
            // Dismiss Command-K if it's open
            if showCommandK {
                withAnimation(.spring(response: 0.2)) {
                    showCommandK = false
                    commandKViewModel.clear()
                }
            }
        }
        .onChange(of: appState.focusedEntity) { _, newValue in
            // When focus mode closes, reopen Command K if it was the source
            if newValue == nil, commandKReturnTab != nil {
                // Brief delay so the focus mode dismissal animation completes first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.2)) {
                        // commandKReturnTab is read by CommandKView(initialTab:) at creation
                        showCommandK = true
                    }
                    // Clear after CommandKView is created so it picks up the tab
                    DispatchQueue.main.async {
                        commandKReturnTab = nil
                    }
                }
            }
        }
        .onChange(of: currentDestination) { _, newDest in
            // Track last-used thinkspace for T-key navigation
            if case .thinkspace(let id) = newDest {
                lastThinkspaceId = id
                canvasThinkspaceId = id
            }
            if !newDest.isDimension {
                previousNonDimensionDestination = newDest
            }
            // Switch thinkspace when destination changes
            switch newDest {
            case .commandCenter:
                break // Full-screen dashboard, no thinkspace switch needed
            case .thinkspace(let id):
                if let ts = thinkspaceManager.thinkspaces.first(where: { $0.id == id }) {
                    Task { await thinkspaceManager.switchTo(ts) }
                }
            case .inbox:
                break
            case .dimension:
                break
            }
            // Update Cosmo Window context (panel is now system-wide, always update)
            let vm = CosmoWindowViewModel.shared
            switch newDest {
            case .commandCenter:
                vm.updateContextManually(type: .commandCenter)
            case .inbox:
                vm.updateContextManually(type: .sanctuary)
            case .thinkspace:
                vm.updateContextManually(type: .thinkspaceCanvas)
            case .dimension:
                vm.updateContextManually(type: .sanctuary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addSwipeToCanvas)) { notification in
            guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }

            withAnimation(.spring(response: 0.2)) {
                showCommandK = false
                commandKViewModel.clear()
            }

            navigateToLastThinkspace()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .openEntityOnCanvas,
                    object: nil,
                    userInfo: ["atomUUID": atomUUID]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("addIdeaToCanvas"))) { notification in
            guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }

            withAnimation(.spring(response: 0.2)) {
                showCommandK = false
                commandKViewModel.clear()
            }

            navigateToLastThinkspace()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .openEntityOnCanvas,
                    object: nil,
                    userInfo: ["atomUUID": atomUUID]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.addToCanvas)) { notification in
            guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }

            withAnimation(.spring(response: 0.2)) {
                showCommandK = false
                commandKViewModel.clear()
            }

            navigateToLastThinkspace()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .openEntityOnCanvas,
                    object: nil,
                    userInfo: ["atomUUID": atomUUID]
                )
            }
        }
        // Cmd+K single-click: add item to current canvas (Thinkspace fallback)
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.addItemToCurrentCanvas)) { notification in
            guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }
            // Only handle at MainView level when no focus mode is active (Thinkspace canvas)
            guard appState.focusedEntity == nil else { return }

            withAnimation(.spring(response: 0.2)) {
                showCommandK = false
                commandKViewModel.clear()
            }

            // Fetch atom and add to Thinkspace canvas
            Task { @MainActor in
                if let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                    let entityType = mapAtomTypeToEntityType(atom.type)
                    navigateToLastThinkspace()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(
                            name: .openEntityOnCanvas,
                            object: nil,
                            userInfo: ["type": entityType, "id": atom.id ?? Int64(0)]
                        )
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToThinkspace)) { notification in
            // Switch to the selected Thinkspace from Command-K
            if let id = notification.userInfo?["id"] as? Int64 {
                Task {
                    if let atom = try? await AtomRepository.shared.fetch(id: id),
                       let thinkspace = ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == atom.uuid }) {
                        await ThinkspaceManager.shared.switchTo(thinkspace)
                        lastThinkspaceId = atom.uuid
                        currentDestination = .thinkspace(id: atom.uuid)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openCreatorDatabase"))) { _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                showCreatorDatabase = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openCreatorProfile"))) { notification in
            guard let creatorUUID = notification.userInfo?["creatorUUID"] as? String else { return }
            Task { @MainActor in
                if let atom = try? await AtomRepository.shared.fetch(uuid: creatorUUID) {
                    creatorProfileAtom = atom
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showCreatorProfile = true
                    }
                }
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showCreatorDatabase)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showCreatorProfile)
        .onAppear {
            setupRightClickMonitor()
            setupGlobalKeyMonitor()
            configureProMotion()
            Task {
                await DimensionWorkspaceCoordinator.shared.start()
            }
            // No thinkspace switch needed — Command Center is full-screen now
        }
        .onDisappear {
            removeRightClickMonitor()
            removeGlobalKeyMonitor()
        }
        // Satellite navigation handlers (legacy notifications → new routing)
        .onReceive(NotificationCenter.default.publisher(for: .sanctuaryThinkspaceRequested)) { _ in
            navigateToLastThinkspace()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sanctuaryPlannerumRequested)) { _ in
            // Plannerum is now a zone inside Command Center
            currentDestination = .commandCenter
        }
        // Voice navigation handler
        .onReceive(NotificationCenter.default.publisher(for: .voiceNavigationRequested)) { notification in
            guard let destination = notification.userInfo?["destination"] as? String else { return }
            handleVoiceNavigation(to: destination)
        }
        // Command Center navigation (from other systems)
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.navigateToCommandCenter)) { _ in
            currentDestination = .commandCenter
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.navigateToDimension)) { notification in
            guard let payload = CosmoNotification.Navigation.DimensionPayload(from: notification) else { return }
            currentDestination = .dimension(payload.dimension)
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openDimensionAsPane)) { notification in
            guard let payload = CosmoNotification.Navigation.DimensionPayload(from: notification) else { return }
            guard paneManager.canOpenDimension(payload.dimension) else { return }
            withAnimation(ProMotionSprings.snappy) {
                paneManager.openPane(.dimension(payload.dimension))
            }
            if showCommandK {
                withAnimation(.spring(response: 0.2)) {
                    showCommandK = false
                    commandKViewModel.clear()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.navigateToThinkspaceById)) { notification in
            guard let payload = CosmoNotification.Navigation.ThinkspacePayload(from: notification) else { return }
            currentDestination = .thinkspace(id: payload.thinkspaceId)
        }
        // Open block in focus mode by UUID (used by promoteToContent, context panels, etc.)
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openBlockInFocusMode)) { notification in
            guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }
            handleOpenBlockInFocusMode(atomUUID: atomUUID)
        }
    }

    // MARK: - Main Content Layout (extracted to avoid type-checker timeout)

    @ViewBuilder
    private var mainContentLayout: some View {
        ZStack {
            HStack(spacing: 0) {
                UnifiedSidebar(
                    currentDestination: $currentDestination,
                    thinkspaceManager: thinkspaceManager
                )
                .environmentObject(crossDragManager)
                .zIndex(200)

                SplitPaneContainer(paneManager: paneManager) {
                    ZStack {
                        destinationContent
                        focusModeOverlay
                    }
                }
                .zIndex(appState.focusedEntity != nil ? 195 : 10)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appState.focusedEntity != nil)
            }

            // Cross-thinkspace floating drag preview
            if crossDragManager.isOverSidebar || crossDragManager.hasThinkspaceSwitched,
               let block = crossDragManager.draggedBlock {
                CrossThinkspaceDragPreview(block: block)
                    .position(crossDragManager.floatingPosition)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .zIndex(10000)
                    .allowsHitTesting(false)
            }
        }
        .background(DS.surface)
        .onAppear {
            setupCrossThinkspaceDragCallbacks()
        }
    }

    /// Wire up cross-thinkspace drag manager callbacks
    private func setupCrossThinkspaceDragCallbacks() {
        crossDragManager.onThinkspaceSwitch = { [weak crossDragManager] (targetId: String) in
            guard let manager = crossDragManager else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                currentDestination = .thinkspace(id: targetId)
            }
            // After switch, block is no longer "over sidebar" visually
            // but manager keeps tracking for final placement
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                manager.isOverSidebar = false
            }
        }

        crossDragManager.onDropComplete = { (block: CanvasBlock, targetThinkspaceId: String, dropPosition: CGPoint) in
            // Move the block in the database
            let hasSwitched = crossDragManager.hasThinkspaceSwitched
            Task {
                let engine = SpatialEngine()
                let finalPosition = hasSwitched ? dropPosition : .zero
                await engine.moveBlockToThinkspace(
                    block.id,
                    newThinkspaceId: targetThinkspaceId,
                    position: finalPosition
                )

                // Post notification so the target CanvasView can reload
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.crossThinkspaceDropBlock,
                    object: nil,
                    userInfo: [
                        "blockId": block.id,
                        "entityUuid": block.entityUuid,
                        "thinkspaceId": targetThinkspaceId,
                        "positionX": finalPosition.x,
                        "positionY": finalPosition.y
                    ]
                )

                // Navigate to the target thinkspace if not already there
                if !hasSwitched {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        currentDestination = .thinkspace(id: targetThinkspaceId)
                    }
                }
            }
        }
    }

    /// The thinkspace ID for the current canvas destination (Command Center or a thinkspace)
    private var activeCanvasThinkspaceId: String? {
        switch currentDestination {
        case .commandCenter: return ThinkspaceManager.commandCenterUUID
        case .thinkspace(let id): return id
        case .inbox, .dimension: return nil
        }
    }

    /// Whether the current destination is a thinkspace canvas
    private var isCanvasDestination: Bool {
        if case .thinkspace = currentDestination { return true }
        return false
    }

    @ViewBuilder
    private var destinationContent: some View {
        ZStack {
            // Canvas layer — ALWAYS alive, hidden when a non-canvas destination is active.
            // Preserves all @StateObject engines, loaded blocks, zoom/pan state, and
            // notification observers so returning to a thinkspace is instant.
            if canvasThinkspaceId != nil {
                CanvasView(thinkspaceId: canvasThinkspaceId, isActive: isCanvasDestination)
                    .environmentObject(appState)
                    .environmentObject(database)
                    .environmentObject(voiceEngine)
                    .environmentObject(blockFrameTracker)
                    .environmentObject(crossDragManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(isCanvasDestination && appState.focusedEntity == nil ? 1.0 : 0)
                    .allowsHitTesting(isCanvasDestination && appState.focusedEntity == nil)
            }

            // Non-canvas destinations rendered on top when active
            if case .inbox = currentDestination {
                Text("Inbox")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.bg)
                    .transition(.opacity)
            } else if case .commandCenter = currentDestination {
                CommandCenterDashboard()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.bg)
                    .transition(.opacity)
            } else if case .dimension(let dimension) = currentDestination {
                DimensionWorkspaceView(
                    dimension: dimension,
                    onBack: restoreFromDimension
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.bg)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var focusModeOverlay: some View {
        if let focusEntity = appState.focusedEntity {
            FocusModeView(entity: focusEntity)
                .environmentObject(appState)
                .environmentObject(database)
                .environmentObject(voiceEngine)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    /// Handle voice navigation to Command Center, Thinkspace, etc.
    private func handleVoiceNavigation(to destination: String) {
        switch destination.lowercased() {
        case "plannerum", "planning", "sanctuary", "home", "command center":
            currentDestination = .commandCenter
        case "thinkspace", "canvas":
            navigateToLastThinkspace()
        case "cognitive":
            currentDestination = .dimension(.cognitive)
        case "creative":
            currentDestination = .dimension(.creative)
        case "physiological", "health":
            currentDestination = .dimension(.physiological)
        case "behavioral":
            currentDestination = .dimension(.behavioral)
        case "knowledge":
            currentDestination = .dimension(.knowledge)
        case "reflection", "journal":
            currentDestination = .dimension(.reflection)
        default:
            break
        }
    }

    // MARK: - Open Block in Focus Mode by UUID

    /// Handles the openBlockInFocusMode notification (from promoteToContent, context panels, etc.)
    /// Fetches the atom by UUID, determines its type, and navigates to the appropriate focus mode.
    private func handleOpenBlockInFocusMode(atomUUID: String) {
        // Show loading overlay
        withAnimation(.easeOut(duration: 0.2)) {
            activationLoadingMessage = "Opening content..."
            showActivationLoading = true
        }

        // Close any overlays that might be open
        withAnimation(.spring(response: 0.2)) {
            showCommandK = false
        }

        Task { @MainActor in
            do {
                if let atom = try await AtomRepository.shared.fetch(uuid: atomUUID) {
                    let entityType = mapAtomTypeToEntityType(atom.type)
                    let entityId = atom.id ?? 0

                    // Brief delay for the loading overlay to be visible
                    try? await Task.sleep(nanoseconds: 300_000_000)

                    // Dismiss current focus mode if one is open, then navigate
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appState.focusedEntity = nil
                    }

                    // Small delay to allow the previous focus mode to close
                    try? await Task.sleep(nanoseconds: 200_000_000)

                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appState.focusedEntity = EntitySelection(id: entityId, type: entityType)
                        showActivationLoading = false
                    }
                } else {
                    print("MainView: handleOpenBlockInFocusMode — atom not found: \(atomUUID)")
                    withAnimation(.easeOut(duration: 0.2)) {
                        showActivationLoading = false
                    }
                }
            } catch {
                print("MainView: handleOpenBlockInFocusMode failed: \(error)")
                withAnimation(.easeOut(duration: 0.2)) {
                    showActivationLoading = false
                }
            }
        }
    }

    // MARK: - Navigation Helpers

    /// Whether the current destination is a thinkspace
    private var isThinkspaceActive: Bool {
        if case .thinkspace = currentDestination { return true }
        return false
    }

    /// Navigate to the last-used thinkspace (or the first available)
    private func navigateToLastThinkspace() {
        if let id = lastThinkspaceId {
            currentDestination = .thinkspace(id: id)
        } else if let first = thinkspaceManager.thinkspaces.first {
            lastThinkspaceId = first.id
            currentDestination = .thinkspace(id: first.id)
        }
    }

    private func restoreFromDimension() {
        guard currentDestination.isDimension else { return }
        currentDestination = previousNonDimensionDestination
    }

    // MARK: - Global Keyboard Monitor
    /// Uses NSEvent monitor for Escape key, keyboard shortcuts, and Ctrl+Z undo/redo fallback
    private func setupGlobalKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            // Escape to dismiss overlays (only on keyDown) — peels back one layer at a time
            if event.type == .keyDown, event.keyCode == 53 {  // Escape key
                // 1. Instagram modal
                if swipeFileEngine.showInstagramModal {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        swipeFileEngine.cancelInstagramSave()
                    }
                    return nil
                }

                // 2. Creator Profile
                if showCreatorProfile {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showCreatorProfile = false
                        creatorProfileAtom = nil
                    }
                    return nil
                }

                // 4. Creator Database
                if showCreatorDatabase {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showCreatorDatabase = false
                    }
                    return nil
                }

                // 5. Command-K
                if showCommandK {
                    withAnimation(.spring(response: 0.2)) {
                        showCommandK = false
                        appState.isCommandKVisible = false
                        commandKViewModel.clear()
                    }
                    return nil
                }

                // 6. Radial menu
                if showRadialMenu {
                    withAnimation(.spring(response: 0.2)) {
                        showRadialMenu = false
                    }
                    return nil
                }

                // 7. Block context menu
                if showBlockContextMenu {
                    withAnimation(.spring(response: 0.2)) {
                        showBlockContextMenu = false
                        rightClickedBlockId = nil
                    }
                    return nil
                }

                // 8. Focus mode
                if appState.focusedEntity != nil {
                    withAnimation(.spring(response: 0.2)) {
                        appState.focusedEntity = nil
                    }
                    return nil
                }

                // 9. Close most recent pane
                if paneManager.isActive {
                    withAnimation(ProMotionSprings.snappy) {
                        paneManager.closeLastPane()
                    }
                    return nil
                }

                // 10. Dismiss glass cards
                if glassCenter.isVisible {
                    glassCenter.clearAll()
                    return nil
                }

                // 11. Navigate back out of a dimension workspace
                if currentDestination.isDimension {
                    restoreFromDimension()
                    return nil
                }

                // 12. Navigate from thinkspace back to Command Center
                if isThinkspaceActive {
                    currentDestination = .commandCenter
                    return nil
                }

                // 13. On Command Center — no action (home state)
            }

            // P key — navigate to Command Center (from anywhere)
            if event.type == .keyDown,
               event.keyCode == 35,  // P key
               !event.modifierFlags.contains(.command),
               !isFirstResponderTextField() {
                currentDestination = .commandCenter
                return nil
            }

            // T key — navigate to last-used thinkspace
            if event.type == .keyDown,
               event.keyCode == 17,  // T key
               !event.modifierFlags.contains(.command),
               !isFirstResponderTextField() {
                navigateToLastThinkspace()
                return nil
            }

            // Cmd+\ — toggle sidebar visibility
            if event.type == .keyDown,
               event.keyCode == 42,  // \ key
               event.modifierFlags.contains(.command),
               !isFirstResponderTextField() {
                ThinkspaceManager.shared.isSidebarVisible.toggle()
                return nil
            }

            // N key — quick-add task (Command Center only)
            if event.type == .keyDown,
               event.keyCode == 45,  // N key
               !event.modifierFlags.contains(.command),
               !isFirstResponderTextField() {
                if case .commandCenter = currentDestination {
                    NotificationCenter.default.post(
                        name: Notification.Name("com.cosmo.commandCenter.quickAddTask"),
                        object: nil
                    )
                    return nil
                }
            }

            // S key — start deep work session (Command Center only)
            if event.type == .keyDown,
               event.keyCode == 1,  // S key
               !event.modifierFlags.contains(.command),
               !isFirstResponderTextField() {
                if case .commandCenter = currentDestination,
                   sessionEngine.activeSession == nil {
                    sessionEngine.startSession(
                        taskUUID: nil,
                        taskTitle: "Quick Session",
                        intent: .deepThink,
                        plannedMinutes: 25
                    )
                    return nil
                }
            }

            // Command Center keyboard navigation (arrow keys, Enter, Space, Tab, Delete)
            if event.type == .keyDown,
               !event.modifierFlags.contains(.command),
               !isFirstResponderTextField() {
                if case .commandCenter = currentDestination {
                    let keyCode = event.keyCode
                    // Arrow Up (126), Arrow Down (125), Enter (36), Space (49), Tab (48), Delete (51)
                    if [126, 125, 36, 49, 48, 51].contains(keyCode) {
                        NotificationCenter.default.post(
                            name: Notification.Name("com.cosmo.commandCenter.keyboardAction"),
                            object: nil,
                            userInfo: ["keyCode": keyCode]
                        )
                        return nil
                    }
                }
            }

            // L key — open Command-K to Library tab
            if event.type == .keyDown,
               event.keyCode == 37,  // L key
               !event.modifierFlags.contains(.command),
               !isFirstResponderTextField() {
                withAnimation(.spring(response: 0.2)) {
                    showCommandK = true
                    appState.isCommandKVisible = true
                }
                return nil
            }

            // Cmd+Shift+C - Open command bar typing mode
            if event.type == .keyDown,
               event.keyCode == 8,  // C key
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.shift),
               !isFirstResponderTextField() {
                NotificationCenter.default.post(name: .activateCommandBarTyping, object: nil)
                return nil  // Consume event
            }

            // Option+A - now handled by system-wide HotkeyManager → CosmoWindowPanelController

            // Ctrl+Z / Ctrl+Shift+Z for undo/redo (fallback when not in text field)
            // Only handle when not typing in a text field (check first responder)
            if event.type == .keyDown,
               event.keyCode == 6,  // Z key
               event.modifierFlags.contains(.control),
               !isFirstResponderTextField() {
                if event.modifierFlags.contains(.shift) {
                    // Ctrl+Shift+Z = Redo
                    NotificationCenter.default.post(name: .performRedo, object: nil)
                } else {
                    // Ctrl+Z = Undo
                    NotificationCenter.default.post(name: .performUndo, object: nil)
                }
                return nil  // Consume event
            }

            // In-app voice hotkey (consume to prevent macOS beep)
            if handleInAppVoiceHotkey(event) {
                return nil
            }

            return event  // Pass through to text fields and other responders
        }
    }

    /// Check if the current first responder is a text field (to avoid stealing keyboard input)
    private func isFirstResponderTextField() -> Bool {
        guard let window = NSApp.keyWindow,
              let firstResponder = window.firstResponder else { return false }

        // Check if it's a text view or text field
        return firstResponder is NSTextView || firstResponder is NSTextField
    }

    /// Handles the configured voice hotkey while CosmoOS is focused.
    /// Returns true if the event was handled and should be consumed.
    private func handleInAppVoiceHotkey(_ event: NSEvent) -> Bool {
        // Only handle when app is active (prevents weird cross-app interception)
        guard NSApp.isActive else { return false }

        // Don't steal command-based shortcuts (system/app menus)
        if event.modifierFlags.contains(.command) { return false }

        // Avoid triggering while editing text (prevents accidental voice starts)
        if isTextInputFocused(in: event.window) { return false }

        let hotkey = HotkeyManager.shared.currentHotkey
        let requiredMods = hotkey.modifierFlags
        let cgFlags = event.cgEvent?.flags ?? CGEventFlags(rawValue: 0)
        let hasRequiredMods = cgFlags.contains(requiredMods)

        // Modifier-only hotkeys (e.g. Fn) are handled in HotkeyManager via event tap.
        // We keep the in-app monitor focused on key-based hotkeys to avoid swallowing modifier events.
        if hotkey.keyCode < 0 { return false }

        let isOurKey = Int(event.keyCode) == hotkey.keyCode

        switch event.type {
        case .keyDown:
            if isOurKey, hasRequiredMods {
                if !inAppVoiceHotkeyActive {
                    inAppVoiceHotkeyActive = true
                    Task { @MainActor in
                        await voiceEngine.startRecording()
                    }
                }
                return true // consume to prevent beep
            }

        case .keyUp:
            // Consume keyUp if we were activated OR if modifiers are still held to prevent beep
            if isOurKey, (inAppVoiceHotkeyActive || hasRequiredMods) {
                if inAppVoiceHotkeyActive {
                    inAppVoiceHotkeyActive = false
                    Task { @MainActor in
                        await voiceEngine.stopRecording()
                    }
                }
                return true
            }

        case .flagsChanged:
            // If activated and required modifiers were released, stop recording
            if inAppVoiceHotkeyActive, !hasRequiredMods {
                inAppVoiceHotkeyActive = false
                Task { @MainActor in
                    await voiceEngine.stopRecording()
                }
                // Don't consume modifier changes; just ensure voice state is consistent
                return false
            }

        default:
            break
        }

        return false
    }

    private func isTextInputFocused(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }

        if responder is NSTextView ||
            responder is NSTextField ||
            responder is NSSecureTextField {
            return true
        }

        // SwiftUI text inputs can appear as internal responder types
        let responderType = String(describing: type(of: responder))
        if responderType.contains("NSTextInputContext") ||
            responderType.contains("FieldEditor") ||
            responderType.contains("TextField") ||
            responderType.contains("TextEditor") {
            return true
        }

        return false
    }

    private func removeGlobalKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Right-Click Monitor
    private func setupRightClickMonitor() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            // Get click location in window coordinates
            guard let window = event.window else { return event }

            let windowPoint = event.locationInWindow
            let windowHeight = window.frame.height

            // Convert to SwiftUI coordinates (flip Y)
            let screenPoint = CGPoint(
                x: windowPoint.x,
                y: windowHeight - windowPoint.y
            )

            // Don't intercept right-clicks on the sidebar — let SwiftUI contextMenu handle them
            let sidebarWidth = crossDragManager.sidebarWidth
            if screenPoint.x < sidebarWidth + 4 {
                return event
            }

            // Don't show menus when overlays are active or not on a thinkspace
            guard isThinkspaceActive, !showCommandK, appState.focusedEntity == nil else {
                return event
            }

            // Hit-test against tracked block frames
            if let hitBlockId = blockFrameTracker.hitTest(at: screenPoint) {
                // Show block context menu
                rightClickedBlockId = hitBlockId
                blockContextMenuPosition = screenPoint
                withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                    showBlockContextMenu = true
                    showRadialMenu = false
                }
            } else {
                // Show radial menu on empty canvas (existing behavior)
                radialMenuPosition = screenPoint
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    showRadialMenu = true
                    showBlockContextMenu = false
                }
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
        switch action.type {
        case .createNote:
            createNewEntity(type: .note, at: radialMenuPosition)
        case .createIdea:
            createNewEntity(type: .idea, at: radialMenuPosition)
        case .createTask:
            createNewEntity(type: .task, at: radialMenuPosition)
        case .createContent:
            createNewEntity(type: .content, at: radialMenuPosition)
        case .createResearch:
            createNewEntity(type: .research, at: radialMenuPosition)
        case .createConnection:
            createNewEntity(type: .connection, at: radialMenuPosition)
        case .researchAgent:
            createCosmoAIBlock(at: radialMenuPosition)
        case .fromDatabase:
            // From Database opens Command-K, handled in Focus Mode views
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.openCommandK, object: nil)
        }
    }

    private func createNewEntity(type: EntityType, at position: CGPoint) {
        print("📦 MainView.createNewEntity: Posting notification for \(type) at \(position)")
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.createEntityAtPosition,
            object: nil,
            userInfo: ["type": type, "position": position]
        )
    }

    private func createCosmoAIBlock(at position: CGPoint) {
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.createCosmoAIBlock,
            object: nil,
            userInfo: ["position": position]
        )
    }

    // MARK: - Legacy Transition Stubs (removed — navigation is now instant via currentDestination)

    // MARK: - NodeGraph Command-K Atom Opening

    /// Handles opening an atom from Command-K by UUID
    /// Fetches the atom type and routes to the appropriate view
    private func handleOpenAtomFromCommandK(atomUUID: String) {
        // Close Command-K first
        withAnimation(.spring(response: 0.2)) {
            showCommandK = false
            commandKViewModel.clear()
        }

        // Fetch atom and open in appropriate mode
        Task { @MainActor in
            do {
                // Look up atom by UUID to get its type and ID
                if let atom = try await AtomRepository.shared.fetch(uuid: atomUUID) {
                    // Map AtomType to EntityType for navigation
                    let entityType = mapAtomTypeToEntityType(atom.type)

                    // Always open in focus mode — works from any view
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(
                            name: .enterFocusMode,
                            object: nil,
                            userInfo: ["type": entityType, "id": atom.id ?? 0]
                        )
                    }
                }
            } catch {
                print("⚠️ Failed to open atom from Command-K: \(error)")
            }
        }
    }

    /// Maps AtomType to EntityType for navigation
    private func mapAtomTypeToEntityType(_ atomType: AtomType) -> EntityType {
        switch atomType {
        case .idea:
            return .idea
        case .task, .scheduleBlock:
            return .task
        case .content, .contentDraft:
            return .content
        case .research:
            return .research
        case .connection, .clientProfile:
            return .connection
        case .project:
            return .project
        case .note:
            return .note
        default:
            return .idea  // Default fallback
        }
    }

    // MARK: - ProMotion Configuration (120Hz)
    /// Configures the window for maximum refresh rate (120Hz on ProMotion displays)
    /// This is critical for smooth animations on M1 Pro/Max/M2/M3/M4 Macs with ProMotion
    private func configureProMotion() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }

            // 1. Enable layer-backing for the entire window (required for high refresh rate)
            window.contentView?.wantsLayer = true
            window.contentView?.layerContentsRedrawPolicy = .onSetNeedsDisplay

            // 2. Configure the window's backing layer for maximum frame rate
            if let layer = window.contentView?.layer {
                // Disable implicit animations that can throttle frame rate
                CATransaction.begin()
                CATransaction.setDisableActions(true)

                // Set the layer to redraw asynchronously for better performance
                layer.drawsAsynchronously = true

                // Use default contents placement for best performance
                layer.contentsGravity = .center

                CATransaction.commit()
            }

            // 3. Ensure the window is using the best available display mode
            window.displaysWhenScreenProfileChanges = true

            // 4. Mark window as high performance for the system
            // This hints to macOS that this window should get priority rendering
            window.isOpaque = false  // Allows compositing optimizations
            window.hasShadow = true

            print("✅ ProMotion configured: Window optimized for 120Hz rendering")
        }

        // 5. Prevent App Nap - ensures full performance even when not frontmost
        // This prevents macOS from throttling the app's rendering
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "CosmoOS requires smooth 120Hz rendering"
        )

        print("✅ App Nap disabled for maximum performance")
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        ZStack {
            CosmoColors.softWhite.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Animated logo
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [CosmoColors.lavender, CosmoColors.skyBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse)

                Text("CosmoOS")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(CosmoColors.textPrimary)

                ProgressView()
                    .scaleEffect(1.2)
                    .tint(CosmoColors.lavender)

                Text("Initializing your cognitive space...")
                    .font(.subheadline)
                    .foregroundColor(CosmoColors.textSecondary)
            }
            .padding(60)
            .background(CosmoColors.glassGrey.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

// MARK: - Error View
struct ErrorView: View {
    let message: String

    var body: some View {
        ZStack {
            CosmoColors.softWhite.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(CosmoColors.softRed)

                Text("Error")
                    .font(.title.bold())
                    .foregroundColor(CosmoColors.textPrimary)

                Text(message)
                    .font(.body)
                    .foregroundColor(CosmoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
                .tint(CosmoColors.softRed)
            }
            .padding(50)
            .frame(maxWidth: 400)
            .background(CosmoColors.glassGrey.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

// MARK: - Additional Notifications
// Note: Most canvas notifications are now defined in CosmoNotifications.swift
// Use CosmoNotification.Canvas.* for consistency

// MARK: - Previews

#Preview("Main View") {
    MainView()
        .environmentObject(AppState())
        .environmentObject(CosmoDatabase.shared)
        .environmentObject(VoiceEngine.shared)
        .environmentObject(CosmoGlassCenter.shared)
        .environmentObject(SwipeFileEngine.shared)
        .frame(width: 1200, height: 800)
}

#Preview("Loading View") {
    LoadingView()
        .frame(width: 400, height: 300)
}

#Preview("Error View") {
    ErrorView(message: "Something went wrong. Please try again.")
        .frame(width: 500, height: 400)
}
