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

    @State private var showCommandPalette = false
    @State private var showSettings = false
    @State private var showRadialMenu = false
    @State private var radialMenuPosition: CGPoint = .zero
    @State private var rightClickMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var inAppVoiceHotkeyActive = false

    // NodeGraph Command-K (new constellation-based search)
    @State private var showNodeGraphCommandK = false
    @StateObject private var commandKViewModel = CommandKViewModel()

    // Feature flag for new Command-K (set to true to use NodeGraph constellation)
    private let useNodeGraphCommandK = true

    // Sanctuary state - NOW THE DEFAULT HOME VIEW
    @State private var showingSanctuary = true  // Changed: Sanctuary is now the default entry point
    @StateObject private var sanctuaryChoreographer = AnimationChoreographer()

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
                        showSettings: $showSettings,
                        showCommandPalette: $showCommandPalette
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
            if useNodeGraphCommandK {
                // NodeGraph OS Command-K (new constellation-based search)
                if showNodeGraphCommandK {
                    CommandKView()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(200)
                }
            } else {
                // Legacy Command Hub
                if showCommandPalette {
                    CommandHubView(isPresented: $showCommandPalette)
                        .environmentObject(voiceEngine)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(200)
                }
            }

            // Settings Panel
            if showSettings {
                // Backdrop
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2)) {
                            showSettings = false
                        }
                    }

                SettingsView(isPresented: $showSettings)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(250)
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

            // Gemini thinking indicator (Apple Intelligence-style edge glow)
            GeminiThinkingOverlay()
                .zIndex(280)

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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showCommandPalette)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showNodeGraphCommandK)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showRadialMenu)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appState.focusedEntity != nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: glassCenter.isVisible)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: swipeFileEngine.showInstagramModal)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showingSanctuary)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: showingPlannerum)
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            withAnimation(.spring(response: 0.2)) {
                if useNodeGraphCommandK {
                    showNodeGraphCommandK = true
                } else {
                    showCommandPalette = true
                }
            }
        }
        // NodeGraph Command-K atom opening handler
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.openAtomFromCommandK)) { notification in
            guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }
            handleOpenAtomFromCommandK(atomUUID: atomUUID)
        }
        // NodeGraph Command-K close handler (from background tap or escape in CommandKView)
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.closeCommandK)) { _ in
            withAnimation(.spring(response: 0.2)) {
                showNodeGraphCommandK = false
                commandKViewModel.clear()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            withAnimation(.spring(response: 0.2)) {
                showSettings = true
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

                if showSettings || showCommandPalette || showNodeGraphCommandK || showRadialMenu || appState.focusedEntity != nil {
                    withAnimation(.spring(response: 0.2)) {
                        if showSettings {
                            showSettings = false
                        } else if showNodeGraphCommandK {
                            showNodeGraphCommandK = false
                            commandKViewModel.clear()
                        } else if showCommandPalette {
                            showCommandPalette = false
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
            radialMenuPosition = CGPoint(
                x: windowPoint.x,
                y: windowHeight - windowPoint.y
            )

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
            // Research Agent is handled in Focus Mode views
            break
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
            showNodeGraphCommandK = false
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
                        if [EntityType.idea, .content, .research, .connection].contains(entityType) {
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
