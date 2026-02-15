// CosmoOS/Navigation/MainView.swift
// Spatial-first main view - NO sidebar, canvas is home

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

    // Settings removed from Thinkspace — access via Sanctuary gear icon
    @State private var showRadialMenu = false
    @State private var radialMenuPosition: CGPoint = .zero
    @State private var rightClickMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var inAppVoiceHotkeyActive = false

    // Command-K (constellation-based search)
    @State private var showCommandK = false
    @StateObject private var commandKViewModel = CommandKViewModel()

    // Block context menu (right-click on block)
    @StateObject private var blockFrameTracker = CanvasBlockFrameTracker()
    @State private var rightClickedBlockId: String?
    @State private var showBlockContextMenu = false
    @State private var blockContextMenuPosition: CGPoint = .zero

    // Sanctuary state - NOW THE DEFAULT HOME VIEW
    @State private var showingSanctuary = true  // Changed: Sanctuary is now the default entry point
    @StateObject private var sanctuaryChoreographer = AnimationChoreographer()

    // Activation loading overlay (shown during idea→content navigation)
    @State private var showActivationLoading = false
    @State private var activationLoadingMessage = ""

    // Creator database overlay
    @State private var showCreatorDatabase = false
    @State private var showCreatorProfile = false
    @State private var creatorProfileAtom: Atom?

    // Satellite navigation state
    @State private var showingPlannerum = false
    @State private var showingThinkspace = false  // When true, shows Canvas (existing behavior)

    var body: some View {
        ZStack {
            // Pure canvas view - the spatial workspace
            // With fade/blur/scale when Sanctuary is open (simulates z-depth)
            CanvasView()
                .environmentObject(appState)
                .environmentObject(database)
                .environmentObject(voiceEngine)
                .environmentObject(blockFrameTracker)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showingSanctuary ? 0.3 : 1.0)
                .blur(radius: showingSanctuary ? 15 : 0)
                .scaleEffect(showingSanctuary ? 0.92 : 1.0)  // Simulates z-translate back
                .animation(.easeInOut(duration: 0.4), value: showingSanctuary)

            // Top-left Level Orb (entry point to Sanctuary)
            // Offset when sidebar is visible to avoid overlap
            VStack {
                HStack {
                    CanvasLevelOrbView {
                        openSanctuary()
                    }
                    .padding(.leading, thinkspaceManager.isSidebarVisible ? 300 : 16)
                    .padding(.top, 12)
                    .opacity(showingSanctuary ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: showingSanctuary)
                    .animation(ProMotionSprings.snappy, value: thinkspaceManager.isSidebarVisible)

                    Spacer()
                }
                Spacer()
            }
            .zIndex(45)

            // Top-right controls (voice indicator + settings)
            VStack {
                HStack {
                    Spacer()
                    TopRightControls(
                        showCommandK: $showCommandK
                    )
                    .environmentObject(voiceEngine)
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
            .zIndex(50)
            .opacity(showingSanctuary ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: showingSanctuary)

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

            // Focus mode overlay (when editing an entity)
            if let focusEntity = appState.focusedEntity {
                FocusModeView(entity: focusEntity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(100)
            }

            // Command-K - The Cognition Hub
            // Revolutionary spatial command center that replaces Finder and sidebars
            if showCommandK {
                CommandKView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(200)
            }

            // Settings accessible via Sanctuary gear icon

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

            // Sanctuary Overlay (neural interface dashboard)
            if showingSanctuary && !showingPlannerum {
                SanctuaryView()
                    .environmentObject(sanctuaryChoreographer)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(180)
                    .onTapGesture {
                        // Tap outside to dismiss
                        closeSanctuary()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 50)
                            .onEnded { value in
                                // Swipe down to dismiss
                                if value.translation.height > 50 {
                                    closeSanctuary()
                                }
                            }
                    )
            }

            // Plannerum Overlay (holographic planning command chamber)
            // Full takeover view - replaces Sanctuary when navigating
            if showingPlannerum {
                PlannerumView(onDismiss: {
                    closePlannerum()
                })
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .leading)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .zIndex(190)
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
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showingSanctuary)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: showingPlannerum)
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            withAnimation(.spring(response: 0.2)) {
                showCommandK = true
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
                commandKViewModel.clear()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            // Settings now live in Sanctuary — navigate there
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showingSanctuary = true
                showingThinkspace = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .enterFocusMode)) { notification in
            if let type = notification.userInfo?["type"] as? EntityType,
               let id = notification.userInfo?["id"] as? Int64 {
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
        .onReceive(NotificationCenter.default.publisher(for: .addSwipeToCanvas)) { notification in
            guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }

            // Close Command-K first
            withAnimation(.spring(response: 0.2)) {
                showCommandK = false
                commandKViewModel.clear()
            }

            // Add to canvas after a brief delay for animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationCenter.default.post(
                    name: .openEntityOnCanvas,
                    object: nil,
                    userInfo: ["atomUUID": atomUUID]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("addIdeaToCanvas"))) { notification in
            guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }

            // Close Command-K first
            withAnimation(.spring(response: 0.2)) {
                showCommandK = false
                commandKViewModel.clear()
            }

            // Add to canvas after a brief delay for animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationCenter.default.post(
                    name: .openEntityOnCanvas,
                    object: nil,
                    userInfo: ["atomUUID": atomUUID]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToThinkspace)) { notification in
            // Switch to the selected Thinkspace from Command-K (world-switch)
            if let id = notification.userInfo?["id"] as? Int64 {
                // First navigate to Thinkspace with world-switch animation
                navigateToThinkspace()
                // Then switch to the specific Thinkspace
                Task {
                    if let atom = try? await AtomRepository.shared.fetch(id: id),
                       let thinkspace = ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == atom.uuid }) {
                        await ThinkspaceManager.shared.switchTo(thinkspace)
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
        }
        .onDisappear {
            removeRightClickMonitor()
            removeGlobalKeyMonitor()
        }
        // Satellite navigation handlers (world-switch transitions)
        .onReceive(NotificationCenter.default.publisher(for: .sanctuaryThinkspaceRequested)) { _ in
            // Navigate from Sanctuary to Canvas (Thinkspace)
            navigateToThinkspace()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sanctuaryPlannerumRequested)) { _ in
            // Navigate from Sanctuary to Plannerum
            navigateToPlannerum()
        }
        // Voice navigation handler - routes "go to plannerum", "open thinkspace", etc.
        .onReceive(NotificationCenter.default.publisher(for: .voiceNavigationRequested)) { notification in
            guard let destination = notification.userInfo?["destination"] as? String else { return }
            handleVoiceNavigation(to: destination)
        }
        // Open block in focus mode by UUID (used by promoteToContent, context panels, etc.)
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openBlockInFocusMode)) { notification in
            guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }
            handleOpenBlockInFocusMode(atomUUID: atomUUID)
        }
    }

    /// Handle voice navigation to Plannerum, Thinkspace, or Sanctuary
    /// Uses unified world-switching transitions
    private func handleVoiceNavigation(to destination: String) {
        switch destination.lowercased() {
        case "plannerum", "planning":
            navigateToPlannerum()
        case "thinkspace", "canvas":
            navigateToThinkspace()
        case "sanctuary", "home":
            navigateToSanctuary()
        default:
            // For other destinations, keep existing behavior
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
            showingSanctuary = false
            showingPlannerum = false
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

    // MARK: - Unified World-Switching Navigation

    /// Navigate to Planarium with world-switch animation
    private func navigateToPlannerum() {
        withAnimation(ProMotionSprings.worldSwitch) {
            showingSanctuary = true
            showingPlannerum = true
        }
    }

    /// Navigate to Thinkspace with world-switch animation
    private func navigateToThinkspace() {
        withAnimation(ProMotionSprings.worldSwitch) {
            showingPlannerum = false
            showingSanctuary = false
            showingThinkspace = true
        }
    }

    /// Navigate to Sanctuary with world-switch animation
    private func navigateToSanctuary() {
        withAnimation(ProMotionSprings.worldSwitch) {
            showingPlannerum = false
            showingSanctuary = true
        }
        // Start the choreographer for entry animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sanctuaryChoreographer.startEntrySequence()
        }
    }

    // MARK: - Global Keyboard Monitor
    /// Uses NSEvent monitor for Escape key, and Ctrl+Z undo/redo fallback
    /// (menu bar handles ⌘K, ⌘,, ⌘Z, ⌘⇧Z but Ctrl+Z is also common on Mac)
    private func setupGlobalKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            // Escape to dismiss overlays (only on keyDown)
            if event.type == .keyDown, event.keyCode == 53 {  // Escape key
                if swipeFileEngine.showInstagramModal {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        swipeFileEngine.cancelInstagramSave()
                    }
                    return nil  // Consume event
                }

                // Close Plannerum first if open (returns to Sanctuary)
                if showingPlannerum {
                    closePlannerum()
                    return nil  // Consume event
                }

                // Return from Thinkspace (Canvas) to Sanctuary with world-switch
                if showingThinkspace && !showingSanctuary {
                    navigateToSanctuary()
                    showingThinkspace = false
                    return nil  // Consume event
                }

                // Close Sanctuary if open (and Plannerum is not)
                if showingSanctuary {
                    closeSanctuary()
                    return nil  // Consume event
                }

                if showBlockContextMenu {
                    withAnimation(.spring(response: 0.2)) {
                        showBlockContextMenu = false
                        rightClickedBlockId = nil
                    }
                    return nil  // Consume event
                }

                if showCreatorProfile {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showCreatorProfile = false
                        creatorProfileAtom = nil
                    }
                    return nil
                }

                if showCreatorDatabase {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showCreatorDatabase = false
                    }
                    return nil
                }

                if showCommandK || showRadialMenu || appState.focusedEntity != nil {
                    withAnimation(.spring(response: 0.2)) {
                        if showCommandK {
                            showCommandK = false
                            commandKViewModel.clear()
                        } else if showRadialMenu {
                            showRadialMenu = false
                        } else if appState.focusedEntity != nil {
                            appState.focusedEntity = nil
                        }
                    }
                    return nil  // Consume event
                }

                // Dismiss glass cards with Escape
                if glassCenter.isVisible {
                    glassCenter.clearAll()
                    return nil
                }
            }

            // P key - Open Plannerum from Sanctuary (world-switch)
            if event.type == .keyDown,
               event.keyCode == 35,  // P key
               showingSanctuary,
               !showingPlannerum,
               !isFirstResponderTextField() {
                navigateToPlannerum()
                return nil  // Consume event
            }

            // T key - Open Thinkspace from Sanctuary (world-switch)
            if event.type == .keyDown,
               event.keyCode == 17,  // T key
               showingSanctuary,
               !showingPlannerum,
               !isFirstResponderTextField() {
                navigateToThinkspace()
                return nil  // Consume event
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

            // Don't show menus when overlays are active
            guard !showingSanctuary, !showingPlannerum, !showCommandK, appState.focusedEntity == nil else {
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

    // MARK: - Sanctuary Transitions

    /// Opens the Sanctuary with the choreographed entry animation
    /// Canvas fades, blurs, and z-translates back while Sanctuary materializes
    private func openSanctuary() {
        // Start the entry sequence animation
        sanctuaryChoreographer.reset()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            showingSanctuary = true
            showingThinkspace = false  // Reset Thinkspace state when returning to Sanctuary
        }

        // Start the internal choreographer for staggered element animations
        sanctuaryChoreographer.startEntrySequence()
    }

    /// Closes the Sanctuary with the choreographed exit animation
    /// Elements fade in reverse order, then canvas is restored
    private func closeSanctuary() {
        // Start exit sequence - choreographer handles the staggered animations
        sanctuaryChoreographer.startExitSequence {
            // After animation completes, hide the container
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingSanctuary = false
            }
        }
    }

    /// Closes Plannerum and returns to Sanctuary
    /// Uses unified world-switch transition
    private func closePlannerum() {
        withAnimation(ProMotionSprings.worldSwitch) {
            showingPlannerum = false
        }
        // Re-enter Sanctuary with fresh animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sanctuaryChoreographer.startEntrySequence()
        }
    }

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

                    // Route to canvas or focus mode based on type
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        // Swipe files always open in focus mode
                        if atom.isSwipeFileAtom {
                            NotificationCenter.default.post(
                                name: .enterFocusMode,
                                object: nil,
                                userInfo: ["type": entityType, "id": atom.id ?? 0]
                            )
                        } else if [EntityType.idea, .content, .research, .connection].contains(entityType) {
                            // Open as floating block on canvas
                            NotificationCenter.default.post(
                                name: .openEntityOnCanvas,
                                object: nil,
                                userInfo: ["type": entityType, "id": atom.id ?? 0]
                            )
                        } else {
                            // Open in focus mode
                            NotificationCenter.default.post(
                                name: .enterFocusMode,
                                object: nil,
                                userInfo: ["type": entityType, "id": atom.id ?? 0]
                            )
                        }
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

// MARK: - Spatial Canvas View (Wrapper)
struct SpatialCanvasView: View {
    var body: some View {
        CanvasView()
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
