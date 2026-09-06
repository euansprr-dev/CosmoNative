// CosmoOS/Navigation/MainView.swift
// Sidebar + content area — Command Center is home, Thinkspaces are canvases

import SwiftUI
import AppKit
import WebKit

final class MainRightClickRoutingState: ObservableObject {
    private var sidebarIsHidden = true
    private var sidebarInteractionWidth: CGFloat = 0
    private let sidebarRightClickSlop: CGFloat

    init(sidebarRightClickSlop: CGFloat = 20) {
        self.sidebarRightClickSlop = sidebarRightClickSlop
    }

    func updateSidebar(isHidden: Bool, interactionWidth: CGFloat) {
        sidebarIsHidden = isHidden
        sidebarInteractionWidth = max(0, interactionWidth)
    }

    func shouldBypassCanvasMenuForSidebar(windowPoint: CGPoint) -> Bool {
        !sidebarIsHidden && windowPoint.x < sidebarInteractionWidth + sidebarRightClickSlop
    }
}

struct CommandKPresentationState: Equatable {
    enum Event {
        case present
        case close
        case preserveBehindFocusMode
    }

    var isVisible: Bool
    var isPreservedBehindFocusMode: Bool
    var searchFocusRequest: Int = 0

    var isVisibleToApp: Bool {
        isVisible
    }

    mutating func apply(_ event: Event) {
        switch event {
        case .present:
            isVisible = true
            isPreservedBehindFocusMode = false
            searchFocusRequest += 1
        case .close:
            isVisible = false
            isPreservedBehindFocusMode = false
        case .preserveBehindFocusMode:
            isVisible = false
            isPreservedBehindFocusMode = true
        }
    }
}

enum CommandKFocusRestorePolicy {
    static func shouldPreservePalette(wasVisible: Bool, presentation: CommandKOpenPresentation) -> Bool {
        wasVisible && presentation == .focusMode
    }

    static func returnTab(
        _ currentReturnTab: CommandKTab?,
        restoreOnFocusClose: Bool
    ) -> CommandKTab? {
        restoreOnFocusClose ? currentReturnTab : nil
    }
}

enum MainKeyboardShortcutPolicy {
    /// Floating panels own their keyboard grammar. Whole-block selection is
    /// document input even after its NSTextView has resigned first responder.
    @MainActor
    static func reservesDocumentKeyboard(in window: NSWindow?) -> Bool {
        window is NSPanel || BlockSelectionClipboardTarget.isActive(in: window)
    }

    static func isTextInputFocused(in window: NSWindow?) -> Bool {
        isTypingTarget(window?.firstResponder)
    }

    static func isTypingTarget(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }

        if responder is NSTextView ||
            responder is NSTextField ||
            responder is NSSecureTextField {
            return true
        }

        if let responderView = responder as? NSView,
           responderView.isWebViewOrDescendant {
            return true
        }

        let responderType = String(describing: type(of: responder))
        return responderType.contains("NSTextInputContext") ||
            responderType.contains("FieldEditor") ||
            responderType.contains("TextField") ||
            responderType.contains("TextEditor") ||
            responderType.contains("WK")
    }
}

private extension NSView {
    var isWebViewOrDescendant: Bool {
        if self is WKWebView {
            return true
        }

        var currentSuperview = superview
        while let view = currentSuperview {
            if view is WKWebView {
                return true
            }
            currentSuperview = view.superview
        }

        return false
    }
}

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var database: CosmoDatabase
    // CosmoGlassCenter and SwipeFileEngine are deliberately NOT observed here:
    // glassCenter's streamingContent publishes per AI stream chunk and the
    // swipe engine publishes per capture step — each publish re-ran this whole
    // body. Their overlay branches live in MainGlassOverlayHost /
    // MainInstagramModalHost below (leaf views that observe the singletons
    // themselves); event handlers reference the singletons directly.

    // Observe ThinkspaceManager for sidebar visibility changes
    // @Observable — a plain reference; SwiftUI tracks only the properties
    // this body actually reads, not every manager mutation.
    private let thinkspaceManager = ThinkspaceManager.shared

    @State private var showRadialMenu = false
    @State private var radialMenuPosition: CGPoint = .zero
    @State private var rightClickMonitor: Any?
    @State private var keyMonitor: Any?
    @StateObject private var rightClickRoutingState = MainRightClickRoutingState()

    // Command-K (constellation-based search)
    @State private var showCommandK = false
    @State private var commandKReturnTab: CommandKTab? = nil
    @State private var commandKBehindFocusMode = false
    @State private var commandKSearchFocusRequest = 0
    @State private var commandKViewModel = CommandKViewModel()
    @State private var clearCommandKAfterDismissal = false
    @State private var pickerPreviousResponder: NSResponder?
    @State private var pickerPreviousWindow: NSWindow?

    // Block context menu (right-click on block).
    // Plain @State reference, NOT @StateObject: MainView reads only the
    // non-published trackedBlocks inside handlers/menu branches, while the
    // tracker's blockFrames publish every 100ms during canvas pan/zoom —
    // observing it re-ran this whole body on each publish. Consumers that
    // need updates still observe it via .environmentObject.
    @State private var blockFrameTracker = CanvasBlockFrameTracker()
    @State private var rightClickedBlockId: String?
    @State private var showBlockContextMenu = false
    @State private var blockContextMenuPosition: CGPoint = .zero

    // Database picker (from radial menu "Database" option)
    @State private var showDatabasePicker = false
    @State private var databasePickerPosition: CGPoint = .zero


    // Navigation destination (Command Center is home)
    @State private var currentDestination: SidebarDestination = .commandCenter
    @State private var showWorkbenchComposer = false
    @State private var spokesPillar: Atom?
    @State private var inboxRoute: SidebarInboxRoute = .global
    /// A ⌘K jump can land the Ideas surface on a client's board.
    @State private var ideasBoardRequest: String? = nil
    @State private var commandCenterViewModel = CommandCenterDashboardViewModel()
    @State private var inboxViewModel = InboxViewModel()
    @State private var swipeLibraryViewModel = SwipeLibraryViewModel()
    @State private var swipeDiscoverModel = SwipeDiscoverModel()
    @State private var ideasPageModel = IdeasPageModel()
    @State private var pipelinePageModel = PipelinePageModel()
    @State private var clientsPageModel = ClientsPageModel()
    // Simple sidebar state: closed/open. Open sidebar reserves layout space.
    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @AppStorage("unifiedSidebarContext") private var activeSidebarContext: SidebarContext = .thinkspaces
    @State private var sidebarPanelWidth: CGFloat = UnifiedSidebarMetrics.defaultExpandedWidth
    @State private var sidebarInteractionWidth: CGFloat = 0
    @State private var sidebarReservedWidth: CGFloat = UnifiedSidebarMetrics.defaultExpandedWidth
    @State private var isSidebarHoverRevealed = false
    /// Focus modes are full-screen surfaces, so the sidebar rides OVER them as
    /// an on-demand overlay: the trail-island toggle (or ⌘\) flips this, and
    /// any focus change resets it. Never persisted — every focus entrance
    /// starts full-screen regardless of the sidebar's docked preference.
    @State private var isSidebarFocusRevealed = false
    /// A space wears its own chrome row (sidebar toggle + trail island
    /// embedded), so the floating global copies stand down on a space.
    private var isSpaceDestination: Bool {
        if case .thinkspace = currentDestination { return true }
        return false
    }
    /// The Space composer sheet (create / settings) — presented from the
    /// sidebar, the space chrome row, and the row context menu.
    @State private var spaceComposerRequest: SpaceComposerRequest?
    @State private var isHoveringSidebarRevealTrigger = false
    @State private var isHoveringSidebarPanel = false
    @State private var sidebarHoverCloseTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Split-pane system
    // @Observable — plain @State reference; MainView invalidates only on the
    // properties it reads (panes), never on divider-drag ratio writes.
    @State private var paneManager = PaneManager()
    @State private var pageFocusPresentation = PageFocusPresentation()

    // Deep work session engine: referenced in event handlers only — MainView
    // must NOT observe it (its elapsedSeconds publishes every second during a
    // session, which re-ran this whole body at 1Hz).

    // Cross-thinkspace drag manager (sidebar spring-loaded folders).
    // Held as plain @State — NOT observed here: its floatingPosition mutates
    // per pointer frame mid-drag; CrossThinkspaceDragPreviewHost is the only
    // view that observes it (CanvasView gets it via environmentObject).
    @State private var crossDragManager = CrossThinkspaceDragManager()

    @State private var focusModeNavigationTask: Task<Void, Never>?
    @State private var focusModeNavigationRequestID = UUID()
    @State private var thinkspaceSwitchTask: Task<Void, Never>?
    @State private var thinkspaceSwitchRequestID = UUID()
    @State private var creatorProfileLoadTask: Task<Void, Never>?
    @State private var creatorProfileLoadRequestID = UUID()
    @State private var commandKNavigationTask: Task<Void, Never>?
    @State private var commandKNavigationRequestID = UUID()

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


            // App-wide NotificationCenter routing subscribes on this zero-size
            // host, so an arriving notification diffs a Color.clear leaf
            // instead of this whole shell (perf audit W14).
            notificationRouter


            // Glass overlay for search results, clarifications, proactive suggestions
            MainGlassOverlayHost()
                .zIndex(60)

            // Timed goal prompt (top-right): session crossed a task/habit time goal
            VStack {
                HStack {
                    Spacer()
                    TimedGoalPromptView()
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                }
                Spacer()
            }
            .zIndex(41)

            // Swipe capture receipt. ⌘⇧S fires from anywhere in the app, so its
            // confirmation is app-level rather than page-level — and it names
            // the kind the router inferred, because the user never chose it.
            SwipeIntakeReceiptOverlay()
                .zIndex(42)

            // Data-safety guard rails: save-failure banner + Trash sheet.
            PersistenceGuardRailsOverlay()
                .zIndex(70)

            // Offline-launch / expired-session reassurance (top-center).
            OfflineReassuranceOverlay()
                .zIndex(80)

            // The First Constellation: first-launch threshold — Sign in with
            // Apple or continue offline. Above everything; shows only when
            // this Mac holds no workspace at all.
            WelcomeGateOverlay()
                .zIndex(200)

            CompanionAssistantDock(
                panes: paneManager,
                isSuppressed: pageFocusPresentation.isFocused || showSettings || showCommandK || appState.focusedEntity?.type == .deepDive || appState.focusedEntity?.type == .inquirySession
            )
            .opacity(pageFocusPresentation.isFocused ? 0 : 1)
            .allowsHitTesting(!pageFocusPresentation.isFocused)
            .accessibilityHidden(pageFocusPresentation.isFocused)
            .zIndex(45)

            // Focus mode is now rendered inside SplitPaneContainer above (z-index 195 when active)

            // Command-K - The Cognition Hub
            // The host owns the entire entrance/exit. Its live hit-test gate
            // releases the workspace immediately on close, and it unmounts
            // the glass only after the visible surfaces have finished leaving.
            CommandKOverlayHost(
                initialTab: commandKReturnTab ?? .database,
                isPresented: showCommandK,
                searchFocusRequest: commandKSearchFocusRequest,
                viewModel: commandKViewModel,
                onDismissed: finishCommandKDismissal
            )
            .zIndex(200)

            // Instagram Swipe File Modal (manual entry for Instagram content)
            MainInstagramModalHost()
                .zIndex(275)


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

            // Database Picker (from radial menu "Database" option)
            if showDatabasePicker {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2)) {
                            showDatabasePicker = false
                        }
                    }
                    .zIndex(149)

                CanvasDatabasePicker(
                    position: databasePickerPosition,
                    onSelect: { atom in
                        showDatabasePicker = false
                        placeAtomOnCanvas(atom, at: databasePickerPosition)
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.2)) {
                            showDatabasePicker = false
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
                    FloatingOverlayBackdrop {
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
                    .floatingOverlayPanel()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(285)
            }

            // Creator Profile overlay
            if showCreatorProfile, let profileAtom = creatorProfileAtom {
                ZStack {
                    FloatingOverlayBackdrop {
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
                            FocusNavigationCoordinator.shared.open(
                                entity: EntitySelection(id: entityId, type: .research)
                            )
                        }
                    )
                    .frame(maxWidth: 1000, maxHeight: 750)
                    .floatingOverlayPanel()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(286)
            }

            // Settings floating overlay
            if showSettings {
                settingsOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(287)
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
        .environment(\.pageFocusPresentation, pageFocusPresentation)
        // Global keyboard shortcuts handled via NSEvent monitor (doesn't steal focus from text fields)
        // Command-K animates locally in its host; presentation never sends a
        // window-wide animation transaction through the workspace or results.
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showRadialMenu)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: showBlockContextMenu)
        // The glass-overlay and Instagram-modal springs moved INTO their leaf
        // hosts (MainGlassOverlayHost / MainInstagramModalHost) with identical
        // curves — driving them here required observing the publishers.
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showSettings)
        // MARK: - Workbenches
        .sheet(isPresented: $showWorkbenchComposer) {
            WorkbenchComposerView(
                snapshot: WorkspaceSnapshot.capture(destination: currentDestination, paneManager: paneManager),
                destinationName: trailDescriptor(for: currentDestination).title,
                onSave: { name, glyph, tintHex in
                    let snapshot = WorkspaceSnapshot.capture(destination: currentDestination, paneManager: paneManager)
                    showWorkbenchComposer = false
                    Task { await WorkbenchStore.shared.create(name: name, glyph: glyph, tintHex: tintHex, snapshot: snapshot) }
                },
                onCancel: { showWorkbenchComposer = false }
            )
        }
        // MARK: - Space composer (create / settings)
        .sheet(item: $spaceComposerRequest) { request in
            SpaceComposerView(
                model: SpaceComposerModel(mode: composerMode(for: request)),
                onDone: { created in
                    let mode = request.mode
                    spaceComposerRequest = nil
                    // The composer posts `spaceComposerDidCreate` itself (once);
                    // the shell only travels to the new space.
                    guard let created, case .create = mode else { return }
                    currentDestination = .thinkspace(id: created.id)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.presentSpaceComposer)) { notification in
            guard let request = SpaceComposerRequest(from: notification) else { return }
            FocusModeEditorBlur.clearFirstResponder(in: NSApp.keyWindow)
            spaceComposerRequest = request
        }
        // MARK: - Studio › Pipeline / Clients jumps
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openPipeline)) { notification in
            let info = notification.userInfo
            if let raw = info?["view"] as? String, let view = PipelineView(rawValue: raw) {
                pipelinePageModel.view = view
            }
            if let clientUUID = info?["clientUUID"] as? String {
                pipelinePageModel.scope = .client(uuid: clientUUID)
            } else if let id = info?["thinkspaceId"] as? String {
                pipelinePageModel.scope = .space(thinkspaceId: id)
            } else if info?["unassigned"] as? Bool == true {
                pipelinePageModel.scope = .unassigned
            } else if info?["allContent"] as? Bool == true {
                pipelinePageModel.scope = .all
            }
            currentDestination = info?["tab"] as? String == "ideas" ? .ideas : .pipeline
            closeCommandKIfOpen()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openClients)) { notification in
            if let clientUUID = notification.userInfo?["clientUUID"] as? String {
                currentDestination = .client(id: clientUUID)
            } else {
                currentDestination = .clients
            }
            closeCommandKIfOpen()
        }
        .onReceive(NotificationCenter.default.publisher(for: CommandKSpaceService.willOpenWorkspace)) { _ in
            // A result replaces the previous route; closing its old document
            // must not resurrect that document's search palette.
            commandKReturnTab = nil
            commandKBehindFocusMode = false
        }
        .onChange(of: appState.focusedEntity) { _, newValue in
            pageFocusPresentation.exit()
            if let newValue {
                recordTrailArrival(forFocus: newValue)
            } else {
                recordTrailArrival(for: currentDestination)
            }
            if let newValue {
                recordFocusModeAccess(for: newValue)
                cancelSidebarHoverClose()
                isHoveringSidebarRevealTrigger = false
                isHoveringSidebarPanel = false
                isSidebarHoverRevealed = false
            }
            // The overlay reveal is per-focus-surface: entering, swapping, or
            // exiting a focus mode always resets to full-screen.
            isSidebarFocusRevealed = false

            // When focus mode closes, reveal Command-K if the prior command
            // asked to return here. The view model is preserved in MainView;
            // the full-screen palette host is recreated only when visible.
            if newValue == nil, commandKBehindFocusMode {
                presentCommandK()
                commandKReturnTab = nil
            } else if newValue == nil, commandKReturnTab != nil {
                // Legacy fallback: CMD+K was destroyed but tab was tracked
                let navigationRequestID = commandKNavigationRequestID
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard commandKNavigationRequestID == navigationRequestID,
                          commandKReturnTab != nil, appState.focusedEntity == nil else { return }
                    presentCommandK()
                    DispatchQueue.main.async {
                        commandKReturnTab = nil
                    }
                }
            }
        }
        .onChange(of: currentDestination) { _, newDest in
            AppPerformanceInstrumentation.event("destination-switch")
            pageFocusPresentation.exit()
            // Dismiss focus mode when navigating via sidebar
            FocusNavigationCoordinator.shared.close()
            // Track last-used thinkspace for T-key navigation
            if case .thinkspace(let id) = newDest {
                lastThinkspaceId = id
                canvasThinkspaceId = id
            }
            // Switch thinkspace when destination changes
            switch newDest {
            case .commandCenter:
                break // Full-screen dashboard, no thinkspace switch needed
            case .thinkspace(let id):
                switchToThinkspaceForDestination(id: id)
            case .inbox:
                break
            case .discover, .swipeFile, .ideas, .pipeline, .clients, .client:
                break
            }
            syncSidebarContext(with: newDest)
            // Update Cosmo Window context (panel is now system-wide, always update)
            let vm = CosmoWindowViewModel.shared
            switch newDest {
            case .commandCenter:
                vm.updateContextManually(type: .commandCenter)
            case .inbox:
                vm.updateContextManually(type: .inbox)
            case .thinkspace:
                vm.updateContextManually(type: .thinkspaceCanvas)
            case .discover, .swipeFile, .ideas, .pipeline, .clients, .client:
                vm.updateContextManually(type: .commandCenter)
            }
            recordTrailArrival(for: newDest)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showCreatorDatabase)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showCreatorProfile)
        .onAppear {
            FocusNavigationCoordinator.shared.appState = appState
            FocusNavigationCoordinator.shared.pageFocusPresentation = pageFocusPresentation
            setupRightClickMonitor()
            setupGlobalKeyMonitor()
            configureProMotion()
            // No thinkspace switch needed — Command Center is full-screen now
        }
        .onDisappear {
            removeRightClickMonitor()
            removeGlobalKeyMonitor()
            focusModeNavigationTask?.cancel()
            thinkspaceSwitchTask?.cancel()
            creatorProfileLoadTask?.cancel()
            commandKNavigationTask?.cancel()
        }
    }

    // MARK: - Notification Router

    private var notificationRouter: some View {
        MainNotificationRouter(
            appState: appState,
            paneManager: paneManager,
            currentDestination: $currentDestination,
            inboxRoute: $inboxRoute,
            ideasBoardRequest: $ideasBoardRequest,
            commandKReturnTab: $commandKReturnTab,
            showSettings: $showSettings,
            showWorkbenchComposer: $showWorkbenchComposer,
            spokesPillar: $spokesPillar,
            showCreatorDatabase: $showCreatorDatabase,
            actions: notificationRouterActions
        )
    }

    private var notificationRouterActions: MainNotificationRouter.Actions {
        .init(
            presentCommandK: presentCommandK,
            presentCommandKPicker: presentCommandKPicker,
            preserveCommandKBehindFocusMode: preserveCommandKBehindFocusMode,
            openAtomFromCommandK: { handleOpenAtomFromCommandK(atomUUID: $0, spaceID: $1) },
            goToObjectFromCommandK: handleGoToObjectFromCommandK(atomUUID:),
            closeCommandK: { closeCommandK() },
            closeCommandKIfOpen: closeCommandKIfOpen,
            applyWorkbench: applyWorkbench(_:),
            navigateTrailBack: navigateTrailBack,
            navigateTrailForward: navigateTrailForward,
            jumpTrail: jumpTrail(to:),
            openBlockInFocusMode: { handleOpenBlockInFocusMode(atomUUID: $0, asPane: $1, restoreCommandKOnFocusClose: $2) },
            handleVoiceNavigation: handleVoiceNavigation(to:),
            toggleSidebar: handleGlobalSidebarToggle,
            openBrowserURL: openBrowserURL(_:title:disposition:),
            openCollaboratorPane: handleOpenCollaboratorPane(atomUUID:presetId:),
            openInlineAssistantPane: openInlineAssistantPane,
            navigateToLastThinkspace: navigateToLastThinkspace,
            addCommandKOriginal: { commandKViewModel.addSelectedOriginals(fallbackUUID: $0) },
            fileAtomIntoThinkspace: { atomUUIDs, targetThinkspaceId in
                Task { @MainActor in
                    await fileAtomIntoThinkspace(atomUUIDs: atomUUIDs, targetThinkspaceId: targetThinkspaceId)
                }
            },
            switchToThinkspace: handleSwitchToThinkspace(atomID:),
            openCreatorProfile: handleOpenCreatorProfile(creatorUUID:)
        )
    }

    // MARK: - Main Content Layout (extracted to avoid type-checker timeout)

    @ViewBuilder
    private var mainContentLayout: some View {
        GeometryReader { geo in
            let sidebarLayout = sidebarLayoutMetrics(for: geo.size)
            let contentPushOffset = MainSidebarContentLayoutPolicy.contentLeadingInset(
                for: appState.focusedEntity?.type == .note ? .commandCenter : currentDestination,
                isSidebarVisible: !pageFocusPresentation.isFocused && isSidebarVisible,
                isSidebarHidden: isSidebarHidden,
                isHoverRevealed: isSidebarHoverRevealed,
                isFocusModeActive: isFocusModeActive,
                isPageFocused: pageFocusPresentation.isFocused,
                sidebarReservedWidth: sidebarLayout.reservedWidth
            )

            ZStack(alignment: .topLeading) {
                SplitPaneContainer(paneManager: paneManager) {
                    ZStack {
                        // LAYOUT-INERT LAW: the destination layer renders
                        // inside a GeometryReader window that always reports
                        // the proposal. A ZStack sizes to its children's
                        // UNION and re-proposes it to every sibling, so any
                        // destination with an incompressible minimum wider
                        // than a squeezed main slot (the Today dashboard's
                        // two-column ~1111pt, the warm canvas) was forcing
                        // the focus overlay to lay out wider than its slot
                        // and render centred-and-clipped beside an open
                        // pane deck. Oversized destinations clip at the
                        // trailing edge instead — the same visual they had
                        // when the slot clipped the inflated union, but the
                        // overflow no longer poisons siblings.
                        GeometryReader { destinationWindow in
                            destinationContent(contentPushOffset: contentPushOffset)
                                .frame(
                                    width: destinationWindow.size.width,
                                    height: destinationWindow.size.height,
                                    alignment: .topLeading
                                )
                                .clipped()
                        }
                        focusModeOverlay(contentPushOffset: contentPushOffset)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .zIndex(appState.focusedEntity != nil ? 195 : 10)
                // The one implicit driver for focus enter/exit AND doc→doc
                // swaps (full value, not `!= nil`, so swaps retrigger it).
                .animation(ProMotionSprings.focusTransition, value: appState.focusedEntity)
                .animation(sidebarAnimation, value: contentPushOffset)

                // In a focus mode the sidebar is a transient overlay above the
                // full-screen focus surface (zIndex 196 > the container's 195);
                // outside focus it's the docked panel at its usual layer.
                if !pageFocusPresentation.isFocused && (isFocusModeActive ? isSidebarFocusRevealed : isSidebarVisible) {
                    sidebarPanel(cornerRadius: sidebarLayout.cornerRadius)
                        .padding(.leading, sidebarLayout.leadingInset)
                        .padding(.trailing, sidebarLayout.trailingInset)
                        .padding(.vertical, sidebarLayout.verticalInset)
                        .frame(
                            width: sidebarLayout.reservedWidth,
                            height: geo.size.height,
                            alignment: .leading
                        )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .onHover { handleSidebarPanelHover($0) }
                        .zIndex(appState.focusedEntity != nil ? 196 : 20)
                }

                if isSidebarHidden && !isFocusModeActive {
                    sidebarHoverRevealTrigger(height: geo.size.height)
                        .zIndex(200)

                    // A space's chrome row carries its own toggle island.
                    if !isSidebarHoverRevealed && (!isSpaceDestination || appState.focusedEntity?.type == .note) {
                        sidebarToggleButton
                            .zIndex(202)
                    }
                }

                // Host isolation: the manager's floatingPosition writes per
                // pointer frame during a cross-thinkspace drag — only this
                // host re-evaluates, never MainView's body.
                CrossThinkspaceDragPreviewHost(manager: crossDragManager)
                    .zIndex(10000)

                // Every focus mode draws the trail island inside its own
                // chrome row (NavigationTrailIsland) so it shares the islands'
                // baseline — the global copy shows only outside focus modes.
                // A space's chrome row embeds one the same way, so the
                // floating copy stands down on every space.
                if !pageFocusPresentation.isFocused && appState.focusedEntity == nil && !isSpaceDestination {
                    NavigationTrailChrome(
                        onBack: { navigateTrailBack() },
                        onForward: { navigateTrailForward() },
                        onJump: { jumpTrail(to: $0) }
                    )
                    .padding(.top, CosmoChromeMetrics.topInset)
                    // 70 = toggle island (16 inset + 44 capsule + 10 gap) —
                    // the trail rides beside the sidebar toggle on one baseline.
                    .padding(.leading, isSidebarVisible ? sidebarLayout.reservedWidth + 8 : 70)
                    .zIndex(201)
                    .transition(.opacity)
                }

                // Spokes Compiler — pillar → platform package staging board
                if let pillar = spokesPillar {
                    Color.black.opacity(0.06)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(ProMotionSprings.snappy) { spokesPillar = nil }
                        }
                        .zIndex(267)
                        .transition(.opacity)

                    SpokesCompilerView(
                        pillar: pillar,
                        onClose: {
                            withAnimation(ProMotionSprings.snappy) { spokesPillar = nil }
                        }
                    )
                    .frame(width: geo.size.width * 0.78, height: geo.size.height * 0.84)
                    .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 24)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .zIndex(268)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }

                // Peek — Quick Look-style preview overlay (above panes, below Command-K)
                PeekOverlayView(
                    onOpenFocus: { entity in
                        FocusNavigationCoordinator.shared.open(entity: entity)
                    },
                    onOpenPane: { entity in
                        guard paneManager.canOpen(entityId: entity.id, appState: appState) else { return }
                        withAnimation(ProMotionSprings.focusTransition) {
                            paneManager.openPane(.entity(entity))
                        }
                    }
                )
                .zIndex(295)
            }
            .background {
                appSceneBackdrop
            }
            .animation(sidebarAnimation, value: isSidebarHidden)
            .animation(sidebarAnimation, value: isSidebarHoverRevealed)
            .animation(sidebarAnimation, value: isSidebarFocusRevealed)
            .animation(sidebarAnimation, value: sidebarPanelWidth)
            .animation(routeContentTransitionAnimation, value: currentDestination)
            .onAppear {
                syncSidebarContext(with: currentDestination)
                restoreSidebarState()
                setupCrossThinkspaceDragCallbacks()
                updateSidebarInteractionWidth(reservedWidth: sidebarLayout.reservedWidth)
                recordTrailArrival(for: currentDestination)
                Task { await WorkbenchStore.shared.loadIfNeeded() }
            }
            .task {
                // Swipe thumbnails start warming at t=0, ahead of everything
                // else in this task: the manifest replays last session's keys
                // straight off disk with no database query, so opening the
                // Swipe File in the first seconds of a launch still paints
                // finished cards. It also prunes the (previously unbounded)
                // thumbnail folder.
                SwipeThumbnailPrewarmer.shared.warmFromManifest()

                // Warm Command-K's search index, recents, and domain counts
                // after launch settles, so the first ⌘K open animates over
                // preloaded state instead of querying mid-spring.
                try? await Task.sleep(for: .seconds(2))
                for _ in 0..<16 where !database.isReady {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard database.isReady else { return }
                await commandKViewModel.prewarmForAppLaunch()
                await prewarmCanvasForAppLaunch()
                // Studio/Ideas and the neighbour-thinkspace warm run
                // CONCURRENTLY — appended serially, Studio/Ideas inherited
                // every sleep in the canvas tail and warmed at t≈4–7s, late
                // enough for a fast first click to hit the cold path anyway.
                // Both are pool reads; no writer contention.
                async let studioWarm: Void = prewarmStudioAndIdeasForAppLaunch()
                async let neighbourWarm: Void = prewarmNeighbourThinkspacesForAppLaunch()
                _ = await (studioWarm, neighbourWarm)
            }
            .onDisappear {
                cancelSidebarHoverClose()
            }
            .onChange(of: geo.size) { _, newSize in
                updateSidebarInteractionWidth(
                    reservedWidth: sidebarLayoutMetrics(for: newSize).reservedWidth
                )
            }
            .onChange(of: isSidebarHidden) { _, _ in
                if !isSidebarHidden {
                    cancelSidebarHoverClose()
                    isSidebarHoverRevealed = false
                }
                updateSidebarInteractionWidth(reservedWidth: sidebarLayout.reservedWidth)
            }
            .onChange(of: isSidebarHoverRevealed) { _, _ in
                updateSidebarInteractionWidth(reservedWidth: sidebarLayout.reservedWidth)
            }
            .onChange(of: sidebarPanelWidth) { _, _ in
                updateSidebarInteractionWidth(reservedWidth: sidebarLayout.reservedWidth)
            }
            .onChange(of: pageFocusPresentation.isFocused) { _, _ in
                updateSidebarInteractionWidth(reservedWidth: sidebarLayout.reservedWidth)
            }
        }
    }

    private func sidebarPanel(cornerRadius: CGFloat) -> some View {
        UnifiedSidebar(
            // Wrapped so sidebar navigation ALWAYS leaves an open focus mode —
            // the onChange path only fires when the destination actually
            // changes, which misses "navigate to the place already underneath".
            currentDestination: Binding(
                get: { currentDestination },
                set: { newDestination in
                    if appState.focusedEntity != nil || pageFocusPresentation.isFocused {
                        FocusNavigationCoordinator.shared.close()
                    }
                    currentDestination = newDestination
                }
            ),
            inboxRoute: $inboxRoute,
            activeContext: $activeSidebarContext,
            panelWidth: $sidebarPanelWidth,
            thinkspaceManager: thinkspaceManager,
            commandCenterViewModel: commandCenterViewModel,
            pipelineModel: pipelinePageModel,
            cornerRadius: cornerRadius,
            showsDestinationContext: appState.focusedEntity?.type != .note,
            sidebarButtonTitle: sidebarButtonTitle,
            sidebarButtonHelp: sidebarButtonHelp,
            onClose: { handleSidebarButtonPress() },
            // Rows guard same-destination writes (e.g. Today clicked while
            // Today already sits under a focus overlay), so the binding
            // wrapper above never fires for them — every row action still
            // reports here, making this the one place that guarantees
            // sidebar navigation always leaves focus mode.
            onNavigate: {
                if appState.focusedEntity != nil || pageFocusPresentation.isFocused {
                    FocusNavigationCoordinator.shared.close()
                }
            }
        )
        .environmentObject(crossDragManager)
    }

    private func sidebarHoverRevealTrigger(height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.001))
            .contentShape(Rectangle())
            .frame(width: UnifiedSidebarMetrics.hoverRevealTriggerWidth, height: height)
            .onHover { handleSidebarRevealTriggerHover($0) }
            .accessibilityHidden(true)
    }

    /// The app shell's copy of the ONE sidebar toggle (ghost manner), on the
    /// shared chrome baseline so it aligns with the floating trail capsule
    /// and every focus header's embedded copy.
    private var sidebarToggleButton: some View {
        SidebarToggleIsland(style: .floating)
            .padding(.top, CosmoChromeMetrics.topInset)
            .padding(.leading, CosmoChromeMetrics.sideInset)
            .onHover { handleSidebarRevealTriggerHover($0) }
    }

    private var isSidebarVisible: Bool {
        MainSidebarHoverRevealPolicy.isSidebarVisible(
            isSidebarHidden: isSidebarHidden,
            isHoverRevealed: isSidebarHoverRevealed
        )
    }

    private var isFocusModeActive: Bool {
        pageFocusPresentation.isFocused ||
            (appState.focusedEntity != nil && appState.focusedEntity?.type != .note)
    }

    private var sidebarAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.sidebar
    }

    private var routeContentTransitionAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.24)
    }

    private func restoreSidebarState() {
        sidebarPanelWidth = UnifiedSidebarMetrics.clampedExpandedWidth(
            StatePersistence.shared.getSidebarWidth()
        )
    }

    private func closeSidebar() {
        cancelSidebarHoverClose()
        isHoveringSidebarRevealTrigger = false
        isHoveringSidebarPanel = false
        withAnimation(sidebarAnimation) {
            isSidebarHidden = true
            isSidebarHoverRevealed = false
        }
    }

    private var isSidebarTransientlyRevealed: Bool {
        MainSidebarButtonPolicy.shouldPersistTransientReveal(
            isSidebarHidden: isSidebarHidden,
            isHoverRevealed: isSidebarHoverRevealed
        )
    }

    private var sidebarButtonTitle: String {
        isSidebarTransientlyRevealed ? "Keep sidebar open" : "Close sidebar"
    }

    private var sidebarButtonHelp: String {
        isSidebarTransientlyRevealed ? "Keep sidebar open (Cmd+\\)" : "Close sidebar (Cmd+\\)"
    }

    private func handleSidebarButtonPress() {
        if isFocusModeActive {
            // The focus-mode overlay closes without touching the docked
            // preference — full-screen focus stays full-screen next time.
            withAnimation(sidebarAnimation) {
                isSidebarFocusRevealed = false
            }
        } else if isSidebarTransientlyRevealed {
            openSidebarPersistently()
        } else {
            closeSidebar()
        }
    }

    private struct SidebarLayoutMetrics {
        var leadingInset: CGFloat
        var trailingInset: CGFloat
        var verticalInset: CGFloat
        var cornerRadius: CGFloat
        var reservedWidth: CGFloat
    }

    private func sidebarLayoutMetrics(for size: CGSize) -> SidebarLayoutMetrics {
        let allowsInset = size.width >= 860 && size.height >= 500
        let horizontalInset = allowsInset ? UnifiedSidebarMetrics.floatingMargin : 0
        let verticalInset = allowsInset ? UnifiedSidebarMetrics.floatingMargin : 0
        return SidebarLayoutMetrics(
            leadingInset: horizontalInset,
            trailingInset: horizontalInset,
            verticalInset: verticalInset,
            cornerRadius: allowsInset ? UnifiedSidebarMetrics.panelCornerRadius : 0,
            reservedWidth: sidebarPanelWidth + horizontalInset + horizontalInset
        )
    }

    /// Mount the canvas hidden with the last-visited thinkspace so the first
    /// real visit presents an already-built tree (blocks, glass materials,
    /// text layout all warm) instead of paying the full cold mount on click.
    /// Every visit after the first already relies on this "always alive"
    /// behavior — this just makes the first visit look like the rest.
    ///
    /// Deliberately does NOT go through `thinkspaceManager.switchTo` — a
    /// hidden prewarm must not touch recency or `currentThinkspace`.
    private func prewarmCanvasForAppLaunch() async {
        // The user may have already opened a thinkspace — canvas is mounted.
        guard canvasThinkspaceId == nil else { return }

        // Let launch work settle before paying the one-time mount cost.
        try? await Task.sleep(for: .milliseconds(800))

        // ThinkspaceManager loads its list in its own init task.
        for _ in 0..<10 where thinkspaceManager.sidebarThinkspaces.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard canvasThinkspaceId == nil else { return }

        // Recency-sorted; prefer the persisted last-opened space.
        let candidates = thinkspaceManager.sidebarThinkspaces
        let persistedId = thinkspaceManager.persistedLastThinkspaceId
        guard let targetId = candidates.first(where: { $0.id == persistedId })?.id
                ?? candidates.first?.id else { return }

        canvasThinkspaceId = targetId
    }

    /// Once the hidden mount has loaded its own space, warm the snapshot
    /// cache for the next most-recent spaces so their first open is instant
    /// too (CanvasView's prewarm guard never clobbers real visits). Split
    /// from prewarmCanvasForAppLaunch so its settle sleep doesn't serialize
    /// the Studio/Ideas warm behind it.
    private func prewarmNeighbourThinkspacesForAppLaunch() async {
        guard let targetId = canvasThinkspaceId else { return }
        try? await Task.sleep(for: .milliseconds(1500))
        for thinkspace in thinkspaceManager.sidebarThinkspaces.prefix(3) where thinkspace.id != targetId {
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.prewarmThinkspace,
                object: nil,
                userInfo: ["thinkspaceId": thinkspace.id]
            )
        }
    }

    /// Warms the Studio (swipe home) and Ideas destinations at launch — the
    /// same instances the sidebar navigates to, so the first click paints the
    /// finished page instead of a skeleton (or a boards-first partial while
    /// the library decode runs). Runs after the ⌘K/canvas prewarms in the
    /// launch task, so it never competes with the visible startup path;
    /// `loadIfNeeded`/`prewarmIfNeeded` make a real visit racing this a no-op.
    private func prewarmStudioAndIdeasForAppLaunch() async {
        await SwipeBoardStore.shared.loadIfNeeded()
        await swipeLibraryViewModel.prewarmIfNeeded()
        await swipeDiscoverModel.loadIfNeeded()
        await ideasPageModel.prewarmIfNeeded()
        // Restored UI state can land the launch on a non-home destination,
        // leaving Today cold until first visit — warm it here (guarded; a
        // real visit racing this is a no-op).
        if currentDestination != .commandCenter {
            await commandCenterViewModel.startInitialLoadIfNeeded()
        }
    }

    private func switchToThinkspaceForDestination(id: String) {
        guard thinkspaceManager.currentThinkspace?.id != id else { return }
        guard let thinkspace = thinkspaceManager.thinkspaces.first(where: { $0.id == id }) else { return }

        thinkspaceSwitchTask?.cancel()
        let requestID = UUID()
        thinkspaceSwitchRequestID = requestID
        thinkspaceSwitchTask = Task { @MainActor in
            guard thinkspaceSwitchRequestID == requestID, !Task.isCancelled else { return }
            await thinkspaceManager.switchTo(thinkspace)
            guard thinkspaceSwitchRequestID == requestID, !Task.isCancelled else { return }
        }
    }

    private func updateSidebarInteractionWidth(reservedWidth: CGFloat? = nil) {
        let nextReservedWidth = reservedWidth ?? sidebarReservedWidth
        let nextInteractionWidth = !pageFocusPresentation.isFocused && isSidebarVisible ? nextReservedWidth : 0

        if sidebarReservedWidth != nextReservedWidth {
            sidebarReservedWidth = nextReservedWidth
        }

        if sidebarInteractionWidth != nextInteractionWidth {
            sidebarInteractionWidth = nextInteractionWidth
        }

        if crossDragManager.sidebarWidth != nextInteractionWidth {
            crossDragManager.sidebarWidth = nextInteractionWidth
        }

        rightClickRoutingState.updateSidebar(
            isHidden: !isSidebarVisible,
            interactionWidth: nextInteractionWidth
        )
    }

    private func toggleSidebarFromKeyboard() {
        cancelSidebarHoverClose()
        isHoveringSidebarRevealTrigger = false
        isHoveringSidebarPanel = false
        withAnimation(sidebarAnimation) {
            isSidebarHidden.toggle()
            isSidebarHoverRevealed = false
        }
    }

    /// One toggle for every entry point (⌘\, the trail-island button): inside
    /// a focus mode it flips the transient overlay; outside it flips the
    /// persistent docked state.
    private func handleGlobalSidebarToggle() {
        if pageFocusPresentation.exit() { return }
        if isFocusModeActive {
            withAnimation(sidebarAnimation) {
                isSidebarFocusRevealed.toggle()
            }
        } else {
            toggleSidebarFromKeyboard()
        }
    }

    private func openSidebarPersistently() {
        cancelSidebarHoverClose()
        isHoveringSidebarRevealTrigger = false
        isHoveringSidebarPanel = false
        withAnimation(sidebarAnimation) {
            isSidebarHidden = false
            isSidebarHoverRevealed = false
        }
    }

    private func handleSidebarRevealTriggerHover(_ hovering: Bool) {
        isHoveringSidebarRevealTrigger = hovering

        guard isSidebarHidden, !isFocusModeActive else {
            if !isSidebarHidden {
                cancelSidebarHoverClose()
            }
            return
        }

        if hovering {
            revealSidebarForHover()
        } else {
            scheduleSidebarHoverCloseIfNeeded()
        }
    }

    private func handleSidebarPanelHover(_ hovering: Bool) {
        isHoveringSidebarPanel = hovering

        if hovering {
            cancelSidebarHoverClose()
        } else {
            scheduleSidebarHoverCloseIfNeeded()
        }
    }

    private func revealSidebarForHover() {
        cancelSidebarHoverClose()

        guard isSidebarHidden, !isSidebarHoverRevealed else { return }

        withAnimation(sidebarAnimation) {
            isSidebarHoverRevealed = true
        }
    }

    private func scheduleSidebarHoverCloseIfNeeded() {
        cancelSidebarHoverClose()

        guard MainSidebarHoverRevealPolicy.shouldCloseTransientReveal(
            isSidebarHidden: isSidebarHidden,
            isHoverRevealed: isSidebarHoverRevealed,
            isHoveringRevealTrigger: isHoveringSidebarRevealTrigger,
            isHoveringSidebarPanel: isHoveringSidebarPanel
        ) else { return }

        sidebarHoverCloseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            guard MainSidebarHoverRevealPolicy.shouldCloseTransientReveal(
                isSidebarHidden: isSidebarHidden,
                isHoverRevealed: isSidebarHoverRevealed,
                isHoveringRevealTrigger: isHoveringSidebarRevealTrigger,
                isHoveringSidebarPanel: isHoveringSidebarPanel
            ) else { return }

            withAnimation(sidebarAnimation) {
                isSidebarHoverRevealed = false
            }
        }
    }

    private func cancelSidebarHoverClose() {
        sidebarHoverCloseTask?.cancel()
        sidebarHoverCloseTask = nil
    }

    private func syncSidebarContext(with destination: SidebarDestination) {
        let next: SidebarContext
        switch destination {
        case .commandCenter:
            next = .commandCenter
        case .inbox:
            next = .inbox
        case .thinkspace:
            next = .thinkspaces
        case .discover, .swipeFile:
            next = .swipeFile
        case .ideas, .pipeline, .clients, .client:
            next = .content
        }
        // @AppStorage — every assignment is a UserDefaults write on the
        // switch path; Studio↔Ideas↔Discover all map to the same context.
        guard activeSidebarContext != next else { return }
        activeSidebarContext = next
    }

    @ViewBuilder
    private var appSceneBackdrop: some View {
        if appState.focusedEntity != nil {
            DS.bg.ignoresSafeArea()
        } else if isCanvasDestination {
            canvasSidebarBackdrop
        } else {
            DS.bg.ignoresSafeArea()
        }
    }

    private var canvasSidebarBackdrop: some View {
        ZStack {
            DS.canvas.ignoresSafeArea()
            ThinkspaceAuroraView().ignoresSafeArea()
            FilmGrainOverlay(opacity: DS.palette.isDark ? 0.014 : 0.010)
                .blendMode(DS.palette.isDark ? .screen : .multiply)
                .ignoresSafeArea()
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
            Task { @MainActor in
                // Land the block at the target space's last-known viewport center
                // (never a (0,0) placeholder — window-space drops refine it below).
                let finalPosition: CGPoint
                if let targetSpace = ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == targetThinkspaceId }) {
                    let viewportSize = NSApp.keyWindow?.contentView?.bounds.size
                        ?? NSApp.mainWindow?.contentView?.bounds.size
                        ?? CGSize(width: 1200, height: 800)
                    finalPosition = CGPoint(
                        x: viewportSize.width / 2 - targetSpace.panOffset.width,
                        y: viewportSize.height / 2 - targetSpace.panOffset.height
                    )
                } else {
                    finalPosition = CGPoint(x: 200, y: 200)
                }

                // Persist the move directly — a throwaway SpatialEngine carries the
                // wrong context and previously stamped position (0,0).
                do {
                    try await SpatialEngine.persistCrossThinkspaceMove(
                        blockId: block.id,
                        targetThinkspaceId: targetThinkspaceId,
                        position: finalPosition
                    )
                } catch {
                    PersistenceHealth.note(.writeFailure, context: "canvas.crossThinkspaceDrop", detail: "block \(block.id) → \(targetThinkspaceId): \(error)")
                    print("❌ Cross-thinkspace move failed: \(error)")
                    return
                }

                // Notify the canvas: the source engine drops the block from memory
                // immediately; the target reloads (and resolves window-space drops).
                // Routed through the pending-placement queue so a not-yet-mounted
                // canvas can't miss it.
                var userInfo: [String: Any] = [
                    "blockId": block.id,
                    "entityUuid": block.entityUuid,
                    "thinkspaceId": targetThinkspaceId,
                    "positionX": finalPosition.x,
                    "positionY": finalPosition.y
                ]
                if hasSwitched {
                    userInfo["positionSpace"] = "screen"
                    userInfo["screenPosition"] = dropPosition
                }
                CanvasPendingPlacementQueue.shared.enqueue(
                    name: CosmoNotification.Canvas.crossThinkspaceDropBlock,
                    userInfo: userInfo
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
        case .inbox: return nil
        case .discover: return nil
        case .swipeFile: return nil
        case .ideas, .pipeline, .clients, .client: return nil
        }
    }

    /// Whether the current destination is a thinkspace canvas
    private var isCanvasDestination: Bool {
        if case .thinkspace = currentDestination { return true }
        return false
    }

    @ViewBuilder
    private func destinationContent(contentPushOffset: CGFloat) -> some View {
        ZStack {
            // Canvas layer — ALWAYS alive, hidden when a non-canvas destination is active.
            // Preserves all @StateObject engines, loaded blocks, zoom/pan state, and
            // notification observers so returning to a thinkspace is instant.
            //
            // LAYOUT-INERT LAW: the keep-alive canvas renders inside a
            // GeometryReader window that always reports the proposal. The
            // canvas's own incompressible minimum (~1111pt of chrome) must
            // never reach this ZStack: a ZStack sizes to its children's
            // union and re-proposes it to EVERY sibling, so a hidden canvas
            // wider than a squeezed main slot (open pane deck, narrow
            // window) was forcing destinations and focus modes to lay out
            // hundreds of points wider than their slot and get clipped.
            if canvasThinkspaceId != nil {
                GeometryReader { canvasWindow in
                    CanvasView(thinkspaceId: canvasThinkspaceId, isActive: isCanvasDestination)
                        .environmentObject(appState)
                        .environmentObject(database)
                        .environmentObject(blockFrameTracker)
                        .environmentObject(crossDragManager)
                        .frame(
                            width: canvasWindow.size.width,
                            height: canvasWindow.size.height,
                            alignment: .topLeading
                        )
                        .clipped()
                }
                .opacity(isCanvasDestination && appState.focusedEntity == nil ? 1.0 : 0)
                .allowsHitTesting(isCanvasDestination && appState.focusedEntity == nil)
                .accessibilityHidden(!isCanvasDestination || appState.focusedEntity != nil)
            }

            // Non-canvas destinations rendered on top when active
            if case .inbox = currentDestination {
                InboxView(viewModel: inboxViewModel, route: $inboxRoute)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.bg)
                    .offset(x: contentPushOffset)
                    .transition(.opacity)
            } else if case .commandCenter = currentDestination {
                CommandCenterDashboard(
                    viewModel: commandCenterViewModel,
                    showsInternalSidebar: false
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.bg)
                    .offset(x: contentPushOffset)
                    .transition(.opacity)
            } else if case .discover(let section) = currentDestination {
                Group {
                    if section == .creators {
                        SwipeCreatorsPage(model: swipeDiscoverModel)
                    } else {
                        SwipeDiscoverPage(model: swipeDiscoverModel) {
                            currentDestination = .discover(section: .creators)
                        }
                    }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.bg)
                    .offset(x: contentPushOffset)
                    .transition(.opacity)
            } else if case .swipeFile(let section) = currentDestination {
                Group {
                    // The swipe file is one page now — old Library (.all) links land there too.
                    if section == .home || section == .all {
                        SwipeHomePage(
                            viewModel: swipeLibraryViewModel,
                            discoverModel: swipeDiscoverModel
                        ) { destination in
                            currentDestination = destination
                        }
                    } else if section == .boards {
                        SwipeBoardsHubPage(viewModel: swipeLibraryViewModel) { boardID in
                            currentDestination = .swipeFile(section: .board(boardID))
                        }
                    } else {
                        SwipeLibraryPage(viewModel: swipeLibraryViewModel, section: section)
                    }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.bg)
                    .offset(x: contentPushOffset)
                    .transition(.opacity)
            } else if isContentDestination {
                ContentWorkspacePage(
                    destination: $currentDestination, boardRequest: $ideasBoardRequest,
                    pipelineModel: pipelinePageModel, ideasModel: ideasPageModel,
                    clientsModel: clientsPageModel
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.bg)
                .padding(.leading, contentPushOffset)
                .transition(.opacity)
            }
        }
    }

    /// True when the focused entity is a study surface (deep dive / inquiry):
    /// these keep the navigation trail and swap in like destinations, not modals.
    private var isContentDestination: Bool {
        switch currentDestination {
        case .ideas, .pipeline, .clients, .client: return true
        default: return false
        }
    }

    private var isStudyFocus: Bool {
        appState.focusedEntity?.type == .deepDive || appState.focusedEntity?.type == .inquirySession
    }

    @ViewBuilder
    private func focusModeOverlay(contentPushOffset: CGFloat) -> some View {
        if let focusEntity = appState.focusedEntity {
            let isStudy = focusEntity.type == .deepDive || focusEntity.type == .inquirySession
            // The idea bench and concept workspace arrive as a plain
            // crossfade, not the bloom: the scale transition over their hosted
            // scroll panels makes macOS 26 drop the panel subtree's first
            // compositor commit — the inspector came up fully laid out and
            // hit-testable but never drew until it was manually closed and
            // reopened (July 2026; the connection inspector is visible by
            // default, so its first open always seats a panel). Study surfaces
            // already crossfade; every other focus mode keeps the bloom.
            let usesPlainFade = isStudy
                || focusEntity.type == .note
                || focusEntity.type == .idea
                || focusEntity.type == .connection
            FocusModeView(entity: focusEntity)
                .padding(.leading, focusEntity.type == .note ? contentPushOffset : 0)
                // A Page's paper and cover wash run under the sidebar column too.
                .pageAtmosphereHost(isActive: focusEntity.type == .note)
                .environment(\.unifiedPageNavigationInset,
                    focusEntity.type == .note && isSidebarHidden && !isSidebarHoverRevealed && !pageFocusPresentation.isFocused ? 60 : 0)
                // Seat the Page once at its final Focus width. TextKit layout
                // must not follow the sidebar's per-frame spring proposals.
                .animation(nil, value: pageFocusPresentation.isFocused)
                .id(focusEntity)
                .environmentObject(appState)
                .environmentObject(database)
                // Pages occupy the regular document slot beside the app
                // sidebar. Other entities keep their existing full-screen
                // surface and transition.
                .transition(usesPlainFade ? .opacity : focusModeBloomTransition)
        }
    }

    /// The document bloom: grows from the click point on entry and recedes
    /// toward it on exit (FocusNavigationCoordinator captures the anchor at
    /// open time). Reduce Motion gets a plain crossfade.
    private var focusModeBloomTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.97, anchor: FocusNavigationCoordinator.shared.entranceAnchor)
                .combined(with: .opacity)
    }

    /// Handle voice navigation to Command Center, Thinkspace, etc.
    private func handleVoiceNavigation(to destination: String) {
        switch destination.lowercased() {
        case "plannerum", "planning", "sanctuary", "home", "command center":
            currentDestination = .commandCenter
        case "thinkspace", "canvas":
            navigateToLastThinkspace()
        default:
            break
        }
    }

    // MARK: - Open Block in Focus Mode by UUID

    /// Handles the openBlockInFocusMode notification (from promoteToContent, context panels, etc.)
    /// Fetches the atom by UUID, determines its type, and navigates to the appropriate focus mode.
    private func handleOpenBlockInFocusMode(
        atomUUID: String,
        asPane: Bool = false,
        restoreCommandKOnFocusClose: Bool = true
    ) {
        focusModeNavigationTask?.cancel()
        let requestID = UUID()
        focusModeNavigationRequestID = requestID

        if asPane {
            focusModeNavigationTask = Task { @MainActor in
                do {
                    guard let atom = try await AtomRepository.shared.fetch(uuid: atomUUID) else {
                        guard focusModeNavigationRequestID == requestID, !Task.isCancelled else { return }
                        print("MainView: handleOpenBlockInFocusMode — atom not found: \(atomUUID)")
                        return
                    }
                    guard focusModeNavigationRequestID == requestID, !Task.isCancelled else { return }

                    let entityType = mapAtomTypeToEntityType(atom.type)
                    guard let entityId = atom.id else {
                        print("MainView: handleOpenBlockInFocusMode pane skipped — atom has no id: \(atomUUID)")
                        return
                    }
                    guard paneManager.canOpen(entityId: entityId, appState: appState) else { return }
                    guard focusModeNavigationRequestID == requestID, !Task.isCancelled else { return }

                    withAnimation(ProMotionSprings.snappy) {
                        paneManager.openPane(.entity(EntitySelection(id: entityId, type: entityType)))
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard focusModeNavigationRequestID == requestID, !Task.isCancelled else { return }
                    print("MainView: handleOpenBlockInFocusMode pane failed: \(error)")
                }
            }
            return
        }

        // Close any overlays that might be open
        commandKReturnTab = CommandKFocusRestorePolicy.returnTab(
            commandKReturnTab,
            restoreOnFocusClose: restoreCommandKOnFocusClose
        )
        closeCommandK(clearViewModel: false)

        // Preload-then-present: the coordinator fetches the atom first (the
        // current screen stays live — no loading chrome), then plays one
        // focusTransition. Covers fresh opens and doc→doc swaps alike.
        FocusNavigationCoordinator.shared.open(atomUUID: atomUUID)
    }

    private func recordFocusModeAccess(for selection: EntitySelection) {
        Task {
            _ = try? await AtomRepository.shared.recordAccess(entityId: selection.id, accessType: .view)
        }
    }

    // MARK: - Navigation Trail

    private func trailDescriptor(for destination: SidebarDestination) -> (title: String, glyph: String) {
        switch destination {
        case .commandCenter: return ("Command Center", "square.grid.2x2")
        case .inbox: return ("Inbox", "tray")
        case .discover: return ("Discover", "safari")
        case .swipeFile: return ("Swipe File", "bookmark")
        case .ideas: return ("Ideas", "lightbulb")
        case .pipeline: return ("Pipeline", "rectangle.split.3x1")
        case .clients: return ("Clients", "person.crop.circle")
        case .client(let id):
            let name = clientsPageModel.rows.first(where: { $0.uuid == id })?.name
            return (name ?? "Client", "person.crop.circle")
        case .thinkspace(let id):
            let name = thinkspaceManager.thinkspaces.first(where: { $0.id == id })?.name
            return (name ?? "Thinkspace", "rectangle.3.group")
        }
    }

    /// A composer request names a space by id; the model wants the live
    /// `Thinkspace`. An edit request for a space that no longer exists
    /// degrades to creating a new one rather than showing an empty sheet.
    private func composerMode(for request: SpaceComposerRequest) -> SpaceComposerModel.Mode {
        switch request.mode {
        case .create(let parentId):
            return .create(parentId: parentId)
        case .edit(let thinkspaceId):
            if let space = thinkspaceManager.currentThinkspace, space.id == thinkspaceId {
                return .edit(space)
            }
            if let space = thinkspaceManager.thinkspaces.first(where: { $0.id == thinkspaceId }) {
                return .edit(space)
            }
            return .create(parentId: nil)
        }
    }

    private func recordTrailArrival(for destination: SidebarDestination) {
        // A space arrival names its view — the store resolves the opening
        // view synchronously from the manager's cache, before the async switch.
        if case .thinkspace(let id) = destination {
            if let atom = SpaceWorkspaceStore.shared.selectedItem(in: id) {
                NavigationTrail.shared.recordArrival(.spaceItem(thinkspaceId: id, itemUUID: atom.uuid),
                    title: atom.title ?? "Untitled", glyph: atom.spaceCompositionKind?.symbol ?? "doc.text")
                return
            }
            let view = SpaceViewStore.shared.activeView(for: id)
            let name = thinkspaceManager.thinkspaces.first(where: { $0.id == id })?.identityLabel ?? "Space"
            NavigationTrail.shared.recordArrival(
                .spaceView(thinkspaceId: id, view: view),
                title: view == .canvas ? name : "\(name) · \(view.title)",
                glyph: view.trailGlyph
            )
            return
        }
        let descriptor = trailDescriptor(for: destination)
        NavigationTrail.shared.recordArrival(
            .sidebar(destination),
            title: descriptor.title,
            glyph: descriptor.glyph
        )
    }

    private func recordTrailArrival(forFocus entity: EntitySelection) {
        let fallbackTitle = entity.type.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        NavigationTrail.shared.recordArrival(
            .focusMode(entity),
            title: fallbackTitle,
            glyph: entity.type.icon
        )
        Task { @MainActor in
            guard let atom = try? await AtomRepository.shared.fetch(id: entity.id),
                  let title = atom.title, !title.isEmpty else { return }
            NavigationTrail.shared.refineTitle(title, for: .focusMode(entity))
        }
    }

    private func navigateTrailBack() {
        guard let moment = NavigationTrail.shared.stepBack() else { return }
        AppPerformanceInstrumentation.trace("TRAIL back → \(moment.title)")
        applyTrailMoment(moment)
    }

    private func navigateTrailForward() {
        guard let moment = NavigationTrail.shared.stepForward() else { return }
        AppPerformanceInstrumentation.trace("TRAIL forward → \(moment.title)")
        applyTrailMoment(moment)
    }

    private func jumpTrail(to moment: NavigationTrail.Moment) {
        guard let landed = NavigationTrail.shared.jumpBack(to: moment.id) else { return }
        applyTrailMoment(landed)
    }

    // MARK: - Workbenches

    /// Restore a workbench: main content settles first, panes cascade in,
    /// focus and pin land last. Whole choreography under ~600ms.
    private func applyWorkbench(_ bench: Workbench) {
        FocusNavigationCoordinator.shared.close()
        currentDestination = bench.snapshot.sidebarDestination

        paneManager.closeAllPanes()
        Task { @MainActor in
            let resolved = await bench.snapshot.resolvedPanes()
            for (index, content) in resolved.contents.enumerated() {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 140 : 70))
                withAnimation(ProMotionSprings.focusTransition) {
                    paneManager.openPane(content)
                }
            }
            withAnimation(ProMotionSprings.focusTransition) {
                if let focusedId = resolved.focusedId {
                    paneManager.focusPane(focusedId)
                }
                paneManager.pinnedPaneId = resolved.pinnedId
            }
            await WorkbenchStore.shared.markUsed(uuid: bench.uuid)
        }
    }

    private func applyWorkbench(atPosition index: Int) {
        Task { @MainActor in
            await WorkbenchStore.shared.loadIfNeeded()
            let benches = WorkbenchStore.shared.workbenches
            guard benches.indices.contains(index) else { return }
            applyWorkbench(benches[index])
        }
    }

    /// Apply a trail moment by replaying the destination's own transition —
    /// the trail never invents a new one.
    private func applyTrailMoment(_ moment: NavigationTrail.Moment) {
        NavigationTrail.shared.applyingJump {
            switch moment.destination {
            case .sidebar(let destination):
                FocusNavigationCoordinator.shared.close()
                currentDestination = destination
                // Landing on a thinkspace moment means its library root —
                // any folder opened after that moment closes with the jump.
                if case .thinkspace = destination {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Navigation.showLibraryFolder,
                        object: nil
                    )
                }
            case .focusMode(let entity):
                FocusNavigationCoordinator.shared.open(entity: entity, anchorOverride: .center)
            case .spaceView(let thinkspaceId, let view):
                FocusNavigationCoordinator.shared.close()
                SpaceWorkspaceStore.shared.showRoot(view, in: thinkspaceId)
                currentDestination = .thinkspace(id: thinkspaceId)
                // Landing on a space's library view means its root — any
                // folder opened after that moment closes with the jump.
                if view == .library {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Navigation.showLibraryFolder,
                        object: nil
                    )
                }
            case .spaceItem(let thinkspaceId, let itemUUID):
                Task { @MainActor in
                    let store = SpaceWorkspaceStore.shared
                    await store.load(thinkspaceId)
                    guard NavigationTrail.shared.current?.id == moment.id else { return }
                    guard let atom = store.snapshots[thinkspaceId]?.atomsByUUID[itemUUID] else {
                        NavigationTrail.shared.prune { $0.destination == moment.destination }
                        NavigationTrail.shared.applyingJump {
                            FocusNavigationCoordinator.shared.close()
                            store.showRoot(.canvas, in: thinkspaceId)
                            currentDestination = .thinkspace(id: thinkspaceId)
                        }
                        store.report(SpaceCompositionError.notFound, in: thinkspaceId)
                        return
                    }
                    NavigationTrail.shared.applyingJump {
                        FocusNavigationCoordinator.shared.close()
                        store.open(atom, in: thinkspaceId)
                        currentDestination = .thinkspace(id: thinkspaceId)
                    }
                }
            case .libraryFolder(let thinkspaceId, let folderID):
                FocusNavigationCoordinator.shared.close()
                SpaceViewStore.shared.select(.library, for: thinkspaceId, source: .trail)
                currentDestination = .thinkspace(id: thinkspaceId)
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.showLibraryFolder,
                    object: nil,
                    userInfo: ["folderID": folderID]
                )
            }
        }
    }

    private var focusedPaneIsBrowser: Bool {
        guard let id = paneManager.focusedPaneId else { return false }
        return paneManager.panes.first(where: { $0.id == id })?.webURL != nil
    }

    /// Route a browser open through BrowserPaneRouter: reuse navigates the
    /// existing browser pane in place; newPane/split open beside it. At the
    /// browser cap the router falls back to navigating the focused pane.
    private func openBrowserURL(_ url: URL, title: String?, disposition: BrowserOpenDisposition) {
        let focusedBrowserPaneId = paneManager.focusedPaneId.flatMap { id in
            paneManager.panes.first(where: { $0.id == id && $0.webURL != nil })?.id
        } ?? paneManager.browserPanes.last?.id

        let action = BrowserPaneRouter.route(
            url: url,
            disposition: disposition,
            paneShowingURL: BrowserPaneRegistry.shared.paneId(showing: url),
            focusedBrowserPaneId: focusedBrowserPaneId,
            canOpenNewPane: paneManager.canOpenBrowserPane()
        )

        withAnimation(ProMotionSprings.snappy) {
            switch action {
            case .activateExisting(let paneId):
                paneManager.focusPane(paneId)
            case .navigateExisting(let paneId, let url):
                BrowserPaneRegistry.shared.navigate(paneId: paneId, to: url)
                paneManager.focusPane(paneId)
            case .openNewPane(let besideCurrent):
                let content = PaneContent.webBrowser(url: url, title: title)
                if besideCurrent {
                    paneManager.openPaneBeside(content)
                } else {
                    paneManager.openPane(content)
                }
            case nil:
                break
            }
        }
    }

    private func handleOpenCollaboratorPane(atomUUID: String, presetId: String?) {
        Task { @MainActor in
            do {
                guard let atom = try await AtomRepository.shared.fetch(uuid: atomUUID) else { return }
                let entityType = mapAtomTypeToEntityType(atom.type)
                guard CollaboratorPreset.deepen.compatibleSurfaces.contains(entityType) else { return }

                let entityId = atom.id ?? 0
                let selection = EntitySelection(id: entityId, type: entityType)

                let source: CollaborationTargetSource
                if appState.focusedEntity == selection {
                    source = .focusMode
                } else if let activePaneId = paneManager.activePaneId,
                          paneManager.entitySelection(forPaneID: activePaneId) == selection {
                    source = .pane(paneID: activePaneId)
                } else if let ownerPaneId = paneManager.contextOwnerPaneId,
                          paneManager.entitySelection(forPaneID: ownerPaneId) == selection {
                    source = .pane(paneID: ownerPaneId)
                } else if let paneID = paneManager.paneID(for: selection) {
                    source = .pane(paneID: paneID)
                } else {
                    source = .focusMode
                }

                let target = CollaborationTarget(
                    source: source,
                    entityID: entityId,
                    entityType: entityType,
                    atomUUID: atom.uuid,
                    title: atom.title ?? "Untitled"
                )

                withAnimation(ProMotionSprings.snappy) {
                    paneManager.openOrActivateCollaborator(target: target, presetId: presetId)
                }
                paneManager.pushContextOwnerToVoiceStore()

                await CosmoWindowViewModel.shared.activateCollaborator(target: target, presetID: presetId)
            } catch {
                print("MainView: handleOpenCollaboratorPane failed: \(error)")
            }
        }
    }

    private func openInlineAssistantPane() {
        withAnimation(ProMotionSprings.snappy) {
            CompanionAssistantCoordinator.shared.openPane(using: paneManager)
        }
    }

    private var isInlineAssistantPaneOpen: Bool {
        paneManager.panes.contains { $0.id == PaneContent.inlineAssistant.id }
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

    /// ⌘K thinkspace pick: task-juggled so a rapid second pick cancels the
    /// first fetch and stale results never land.
    private func handleSwitchToThinkspace(atomID: Int64) {
        thinkspaceSwitchTask?.cancel()
        let requestID = UUID()
        thinkspaceSwitchRequestID = requestID
        thinkspaceSwitchTask = Task { @MainActor in
            if let atom = try? await AtomRepository.shared.fetch(id: atomID),
               let thinkspace = ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == atom.uuid }) {
                guard thinkspaceSwitchRequestID == requestID, !Task.isCancelled else { return }
                await ThinkspaceManager.shared.switchTo(thinkspace)
                guard thinkspaceSwitchRequestID == requestID, !Task.isCancelled else { return }
                lastThinkspaceId = atom.uuid
                currentDestination = .thinkspace(id: atom.uuid)
            }
        }
    }

    /// Creator profile open by UUID — same cancel-and-stale-guard recipe.
    private func handleOpenCreatorProfile(creatorUUID: String) {
        creatorProfileLoadTask?.cancel()
        let requestID = UUID()
        creatorProfileLoadRequestID = requestID
        creatorProfileLoadTask = Task { @MainActor in
            if let atom = try? await AtomRepository.shared.fetch(uuid: creatorUUID) {
                guard creatorProfileLoadRequestID == requestID, !Task.isCancelled else { return }
                creatorProfileAtom = atom
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showCreatorProfile = true
                }
            }
        }
    }

    /// Adding an original keeps every other Space membership and never
    /// assigns a canvas position. The Space writer owns the batch and undo.
    @MainActor
    private func fileAtomIntoThinkspace(atomUUIDs: [String], targetThinkspaceId: String) async {
        do {
            try await SpaceCompositionService.addOriginals(atomUUIDs, in: targetThinkspaceId)
            commandKViewModel.actionStatusMessage = "Added to Space"
        } catch {
            commandKViewModel.actionStatusMessage = error.localizedDescription
        }
    }

    private func applyCommandKPresentation(
        _ event: CommandKPresentationState.Event,
        clearViewModel: Bool = false
    ) {
        var state = CommandKPresentationState(
            isVisible: showCommandK,
            isPreservedBehindFocusMode: commandKBehindFocusMode,
            searchFocusRequest: commandKSearchFocusRequest
        )
        state.apply(event)

        withTransaction(Transaction(animation: nil)) {
            // A rapid reopen supersedes the outgoing completion, but a normal
            // close still starts the next search with a clean query.
            if state.isVisible, clearCommandKAfterDismissal {
                commandKViewModel.clear()
            }
            clearCommandKAfterDismissal = !state.isVisible && clearViewModel
            showCommandK = state.isVisible
            commandKBehindFocusMode = state.isPreservedBehindFocusMode
            commandKSearchFocusRequest = state.searchFocusRequest
            appState.isCommandKVisible = state.isVisibleToApp
        }
    }

    private func finishCommandKDismissal() {
        guard !showCommandK, clearCommandKAfterDismissal else { return }
        commandKViewModel.clear()
        clearCommandKAfterDismissal = false
        if let responder = pickerPreviousResponder { pickerPreviousWindow?.makeFirstResponder(responder) }
        pickerPreviousResponder = nil
        pickerPreviousWindow = nil
    }

    private func presentCommandKPicker(_ request: CommandKPickerRequest) {
        guard commandKViewModel.selectionPicker?.isConfirming != true else { return }
        if !showCommandK {
            pickerPreviousWindow = NSApp.keyWindow
            pickerPreviousResponder = NSApp.keyWindow?.firstResponder
        }
        applyCommandKPresentation(.present)
        commandKViewModel.beginSelectionPicker(request)
    }

    private func presentCommandK() {
        let replacingPicker = commandKViewModel.isSelectionPicker
        if replacingPicker {
            guard commandKViewModel.selectionPicker?.isConfirming != true else { return }
            commandKViewModel.clear()
        }
        guard !showCommandK || replacingPicker else { applyCommandKPresentation(.present); return }
        let context: CommandKSpaceContext?
        if case .thinkspace(let id) = currentDestination,
           let space = ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == id }) {
            let store = SpaceWorkspaceStore.shared
            let location = store.location(id)
            let atom = store.selectedItem(in: id)
            let path = atom.flatMap { item in store.snapshots[id].map { CommandKSpaceService.navigationPath(to: item.uuid, in: $0) } } ?? []
            context = CommandKSpaceContext(spaceID: id, spaceTitle: space.name,
                containerUUID: location.itemUUID, containerTitle: atom?.title,
                containerKind: atom?.spaceCompositionKind, view: location.itemUUID == nil ? nil : location.view,
                path: path.map { $0.title ?? "Untitled" })
        } else { context = nil }
        applyCommandKPresentation(.present)
        commandKViewModel.captureSpaceContext(context)
    }

    private func closeCommandK(clearViewModel: Bool = true) {
        guard commandKViewModel.selectionPicker?.isConfirming != true else { return }
        if commandKViewModel.isSelectionPicker { commandKViewModel.selectionPickerTask?.cancel() }
        if showCommandK {
            FocusModeEditorBlur.clearFirstResponder(in: NSApp.keyWindow)
        }
        applyCommandKPresentation(.close, clearViewModel: clearViewModel)
    }

    private func preserveCommandKBehindFocusMode() {
        applyCommandKPresentation(.preserveBehindFocusMode)
    }

    /// Guarded twin for notification-driven dismissal: closing an
    /// already-closed palette would still clear its view model, losing
    /// preserved search state.
    private func closeCommandKIfOpen() {
        if showCommandK || commandKBehindFocusMode {
            closeCommandK()
        }
    }

    private func isCommandKShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasOnlyCommand = flags.contains(.command)
            && !flags.contains(.shift)
            && !flags.contains(.option)
            && !flags.contains(.control)
        let character = event.charactersIgnoringModifiers?.lowercased()

        return hasOnlyCommand && (event.keyCode == 40 || character == "k")
    }

    // MARK: - Global Keyboard Monitor
    /// Uses NSEvent monitor for Escape key, keyboard shortcuts, and Ctrl+Z undo/redo fallback
    private func setupGlobalKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            guard !MainKeyboardShortcutPolicy.reservesDocumentKeyboard(in: event.window) else { return event }
            // Cmd+K should always reopen the shared palette, including while a focus mode is active.
            // If Command-K is already visible, let the event continue so its Actions shortcut can handle it.
            if event.type == .keyDown,
               isCommandKShortcut(event) {
                if !showCommandK {
                    presentCommandK()
                    return nil
                }
                return event
            }

            // Escape to dismiss overlays (only on keyDown) — peels back one layer at a time
            if event.type == .keyDown, event.keyCode == 53 {  // Escape key
                if showCommandK, commandKViewModel.isSelectionPicker {
                    commandKViewModel.cancelSelectionPicker()
                    return nil
                }
                // 0. Peek overlay
                if PeekController.shared.isPresented {
                    withAnimation(ProMotionSprings.snappy) {
                        PeekController.shared.dismiss()
                    }
                    return nil
                }

                // 0c. Spokes Compiler
                if spokesPillar != nil {
                    withAnimation(ProMotionSprings.snappy) {
                        spokesPillar = nil
                    }
                    return nil
                }

                // 0d. Deep canvas overlays (place capture, flow picker/inspector, portal picker)
                if CanvasEscapeCoordinator.shared.dismissTopOverlay() {
                    return nil
                }

                // 1. Instagram modal
                if SwipeFileEngine.shared.showInstagramModal {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        SwipeFileEngine.shared.cancelInstagramSave()
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

                // 5. Command-K — peel the Ask-Cortex answer, then the composer
                // form, then the actions panel, then the palette
                if showCommandK {
                    if commandKViewModel.askSession != nil {
                        commandKViewModel.askSession = nil
                        return nil
                    }
                    if commandKViewModel.isComposerFocused {
                        commandKViewModel.isComposerFocused = false
                        return nil
                    }
                    if commandKViewModel.isActionPanelPresented {
                        commandKViewModel.isActionPanelPresented = false
                        return nil
                    }
                    closeCommandK()
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

                // 7c. Slash / mention / selection menu open in a block editor —
                // dismiss just the menu (leaving the typed / or @ in place),
                // never the whole focus mode / page.
                if EditorOverlayEscapeCoordinator.shared.dismissTopOverlay() {
                    return nil
                }

                // Page Focus only changes visibility; Escape first restores
                // the same editor with its sidebar and pane arrangement.
                if pageFocusPresentation.exit() { return nil }

                // 8. Focus mode
                if appState.focusedEntity != nil {
                    FocusNavigationCoordinator.shared.close()
                    return nil
                }

                // 9. Close most recent pane
                if paneManager.isActive {
                    withAnimation(ProMotionSprings.snappy) {
                        paneManager.closeFocusedPane()
                    }
                    return nil
                }

                // 10. Dismiss glass cards
                if CosmoGlassCenter.shared.isVisible {
                    CosmoGlassCenter.shared.clearAll()
                    return nil
                }

                // 11. Navigate from thinkspace back to Command Center
                if isThinkspaceActive {
                    currentDestination = .commandCenter
                    return nil
                }

                // 12. On Command Center — no action (home state)
            }

            // Cmd+[ / Cmd+] — universal back/forward through the navigation trail
            if event.type == .keyDown,
               event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control),
               !isKeyboardInputReserved() {
                if event.keyCode == 33 {  // [
                    navigateTrailBack()
                    return nil
                }
                if event.keyCode == 30 {  // ]
                    navigateTrailForward()
                    return nil
                }
            }

            // ⌘1…⌘n — switch the current space's view (the page-level
            // ⌘digit grammar Ideas uses for Desk/All). Routed here, not as
            // hidden buttons: the keep-alive canvas is mounted on every
            // destination and must never answer while Ideas owns ⌘1/⌘2.
            if event.type == .keyDown,
               case .thinkspace(let spaceId) = currentDestination,
               let index = SpaceKeyboardShortcutPolicy.viewIndex(
                   keyCode: event.keyCode,
                   modifiers: event.modifierFlags,
                   enabledCount: SpaceViewStore.shared.renderableViews(for: spaceId).count,
                   isThinkspaceActive: true,
                   hasFocusedEntity: appState.focusedEntity != nil,
                   isCommandKVisible: showCommandK,
                   isTextInputFocused: isKeyboardInputReserved()
               ) {
                SpaceViewStore.shared.select(index: index, for: spaceId)
                return nil
            }

            // Space closes an open Peek (Quick Look parity)
            if event.type == .keyDown,
               event.keyCode == 49,
               !event.modifierFlags.contains(.command),
               PeekController.shared.isPresented,
               !isKeyboardInputReserved() {
                withAnimation(ProMotionSprings.snappy) {
                    PeekController.shared.dismiss()
                }
                return nil
            }

            // Workbenches: Ctrl+1…9 apply, Cmd+Ctrl+B save current layout
            if event.type == .keyDown,
               !isKeyboardInputReserved() {
                let benchFlags = event.modifierFlags
                if benchFlags.contains(.control), !benchFlags.contains(.command),
                   !benchFlags.contains(.option), !benchFlags.contains(.shift) {
                    let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
                    if let digit = digitKeyCodes[event.keyCode] {
                        applyWorkbench(atPosition: digit - 1)
                        return nil
                    }
                }
                if benchFlags.contains(.control), benchFlags.contains(.command),
                   !benchFlags.contains(.option), !benchFlags.contains(.shift),
                   event.keyCode == 11 {  // B
                    showWorkbenchComposer = true
                    return nil
                }
            }

            // Pane deck: Cmd+Ctrl+1…6 focus by position, Cmd+Shift+[ / ] cycle, Cmd+Opt+P pin
            if event.type == .keyDown,
               paneManager.isActive,
               !isKeyboardInputReserved() {
                let flags = event.modifierFlags
                if flags.contains(.command), flags.contains(.control), !flags.contains(.shift), !flags.contains(.option) {
                    let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6]
                    if let digit = digitKeyCodes[event.keyCode] {
                        withAnimation(ProMotionSprings.focusTransition) {
                            paneManager.focusPane(atPosition: digit - 1)
                        }
                        return nil
                    }
                }
                if flags.contains(.command), flags.contains(.shift), !flags.contains(.option), !flags.contains(.control) {
                    if event.keyCode == 30 {  // ]
                        withAnimation(ProMotionSprings.focusTransition) {
                            paneManager.cycleFocus(forward: true)
                        }
                        return nil
                    }
                    if event.keyCode == 33 {  // [
                        withAnimation(ProMotionSprings.focusTransition) {
                            paneManager.cycleFocus(forward: false)
                        }
                        return nil
                    }
                }
                if flags.contains(.command), flags.contains(.option), !flags.contains(.shift), event.keyCode == 35 {  // P
                    withAnimation(ProMotionSprings.focusTransition) {
                        paneManager.togglePin()
                    }
                    return nil
                }
            }

            // P key — navigate to Command Center (from anywhere)
            if event.type == .keyDown,
               event.keyCode == 35,  // P key
               !event.modifierFlags.contains(.command),
               !isKeyboardInputReserved() {
                currentDestination = .commandCenter
                return nil
            }

            // Cmd+T — new browser pane beside the current one, scoped to a
            // focused browser pane (the research browser's only "new tab").
            if event.type == .keyDown,
               event.keyCode == 17,  // T key
               event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option),
               focusedPaneIsBrowser {
                // Bypass the router: a new tab is always a fresh pane, even
                // when another pane sits on the start page.
                if paneManager.canOpenBrowserPane() {
                    withAnimation(ProMotionSprings.snappy) {
                        paneManager.openPaneBeside(
                            .webBrowser(url: CosmoBrowserURLResolver.defaultHomeURL, title: nil)
                        )
                    }
                }
                return nil
            }

            // T key — navigate to last-used thinkspace
            if event.type == .keyDown,
               event.keyCode == 17,  // T key
               !event.modifierFlags.contains(.command),
               !isKeyboardInputReserved() {
                navigateToLastThinkspace()
                return nil
            }

            // Cmd+\ — toggle sidebar visibility (focus-aware: overlays in focus modes)
            if event.type == .keyDown,
               event.keyCode == 42,  // \ key
               event.modifierFlags.contains(.command),
               !isKeyboardInputReserved() {
                handleGlobalSidebarToggle()
                return nil
            }

            // N key — quick-add task (Command Center only)
            if event.type == .keyDown,
               event.keyCode == 45,  // N key
               !event.modifierFlags.contains(.command),
               !isKeyboardInputReserved() {
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
               !isKeyboardInputReserved() {
                if case .commandCenter = currentDestination,
                   DeepWorkSessionEngine.shared.activeSession == nil {
                    DeepWorkSessionEngine.shared.startSession(
                        taskUUID: nil,
                        taskTitle: "Quick Session",
                        intent: .deepThink,
                        plannedMinutes: 25
                    )
                    return nil
                }
            }

            // ⌥⌘←/→ — page the Command Center's viewed day (chevrons' keyboard twin)
            if event.type == .keyDown,
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.option),
               [123, 124].contains(event.keyCode),
               !isKeyboardInputReserved() {
                if case .commandCenter = currentDestination {
                    NotificationCenter.default.post(
                        name: Notification.Name("com.cosmo.commandCenter.keyboardAction"),
                        object: nil,
                        userInfo: ["keyCode": event.keyCode, "modifiers": event.modifierFlags.rawValue]
                    )
                    return nil
                }
            }

            // Command Center keyboard navigation (arrow keys, Enter, Space, Tab, Delete)
            if event.type == .keyDown,
               !event.modifierFlags.contains(.command),
               !isKeyboardInputReserved() {
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
               !isKeyboardInputReserved() {
                presentCommandK()
                return nil
            }

            // Option+A - now handled by system-wide HotkeyManager → inline assistant

            // Ctrl+Z / Ctrl+Shift+Z for undo/redo (fallback when not in text field)
            // Only handle when not typing in a text field (check first responder)
            if event.type == .keyDown,
               event.keyCode == 6,  // Z key
               event.modifierFlags.contains(.control),
               !isKeyboardInputReserved() {
                if event.modifierFlags.contains(.shift) {
                    // Ctrl+Shift+Z = Redo
                    NotificationCenter.default.post(name: .performRedo, object: nil)
                } else {
                    // Ctrl+Z = Undo
                    NotificationCenter.default.post(name: .performUndo, object: nil)
                }
                return nil  // Consume event
            }

            return event  // Pass through to text fields and other responders
        }
    }

    /// Check if the current first responder owns keyboard input.
    private func isKeyboardInputReserved() -> Bool {
        MainKeyboardShortcutPolicy.isTextInputFocused(in: NSApp.keyWindow)
    }

    private func isTextInputFocused(in window: NSWindow?) -> Bool {
        MainKeyboardShortcutPolicy.isTextInputFocused(in: window)
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
            if rightClickRoutingState.shouldBypassCanvasMenuForSidebar(windowPoint: windowPoint) {
                return event
            }

            // Don't intercept right-clicks in the pane column — let the pane's own monitor handle them
            // SplitPaneContainer fills the full window width (canvas extends behind sidebar),
            // so pane column starts at windowWidth * mainSplitRatio + divider
            if paneManager.isActive {
                let paneColumnStart = window.frame.width * paneManager.mainSplitRatio + 6
                if screenPoint.x > paneColumnStart {
                    return event
                }
            }

            // Don't show menus when overlays are active or not on a thinkspace
            guard isThinkspaceActive, !showCommandK,
                  appState.focusedEntity == nil else {
                return event
            }

            // Hit-test in canvas space with the live transform (canvas fills
            // full window width). Returns nil when the canvas isn't the
            // active surface (library mode) — the event belongs to SwiftUI.
            let canvasLocalPoint = screenPoint
            switch blockFrameTracker.rightClickHitTest(at: canvasLocalPoint) {
            case .block(let hitBlockId):
                rightClickedBlockId = hitBlockId
                blockContextMenuPosition = screenPoint
                withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                    showBlockContextMenu = true
                    showRadialMenu = false
                }
            case .empty:
                // Radial creation menu on empty canvas (existing behavior)
                radialMenuPosition = screenPoint
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    showRadialMenu = true
                    showBlockContextMenu = false
                }
            case .expandedCluster, nil:
                // List/board/grid cluster UI (or an unregistered canvas) owns
                // this click — neither canvas menu is correct here.
                return event
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
        case .createStickyNote:
            createNewEntity(type: .stickyNote, at: radialMenuPosition)
        case .createDeepDive:
            createNewEntity(type: .deepDive, at: radialMenuPosition)
        case .researchAgent:
            createCosmoAIBlock(at: radialMenuPosition)
        case .fromDatabase:
            databasePickerPosition = radialMenuPosition
            showDatabasePicker = true
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

    private func placeAtomOnCanvas(_ atom: Atom, at position: CGPoint) {
        // Map AtomType to EntityType, handling cases where raw values differ
        let entityType: EntityType
        switch atom.type {
        case .templateInstance, .blockTemplate:
            entityType = .template
        default:
            entityType = EntityType(rawValue: atom.type.rawValue) ?? .note
        }

        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.createEntityAtPosition,
            object: nil,
            userInfo: [
                "type": entityType,
                "position": position,
                "existingAtomUUID": atom.uuid
            ]
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

    // MARK: - Settings Overlay

    @ViewBuilder
    private var settingsOverlay: some View {
        ZStack {
            CortexOverlayBackdrop {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showSettings = false
                }
            }

            CosmoSettingsView(onClose: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showSettings = false
                }
            })
            .settingsGlassPanel()
        }
    }

    /// Handles opening an atom from Command-K by UUID
    /// Fetches the atom type and routes to the appropriate view
    private func handleOpenAtomFromCommandK(atomUUID: String, spaceID: String? = nil) {
        navigateCommandKObject(atomUUID, exactSpaceID: spaceID, revealLocation: false)
    }

    private func handleGoToObjectFromCommandK(atomUUID: String) {
        navigateCommandKObject(atomUUID, exactSpaceID: nil, revealLocation: true)
    }

    private func navigateCommandKObject(_ uuid: String, exactSpaceID: String?, revealLocation: Bool) {
        commandKNavigationTask?.cancel()
        let requestID = UUID()
        commandKNavigationRequestID = requestID
        let origin = commandKViewModel.spaceContext
        let paletteWasVisible = showCommandK
        // The new result owns its own return intent. Clear the old one before
        // an awaited workspace open can close the previous focused entity.
        commandKReturnTab = nil
        commandKBehindFocusMode = false
        commandKViewModel.actionStatusMessage = nil
        commandKNavigationTask = Task { @MainActor in
            do {
                let presentation = try await CommandKSpaceService.openAtom(uuid, exactSpaceID: exactSpaceID,
                    preferredSpaceID: origin?.spaceID, revealLocation: revealLocation)
                guard commandKNavigationRequestID == requestID, !Task.isCancelled else { return }
                if CommandKFocusRestorePolicy.shouldPreservePalette(wasVisible: paletteWasVisible, presentation: presentation) {
                    commandKReturnTab = .database
                    preserveCommandKBehindFocusMode()
                } else {
                    closeCommandK()
                }
            } catch is CancellationError {
                return
            } catch {
                guard commandKNavigationRequestID == requestID, !Task.isCancelled else { return }
                commandKViewModel.actionStatusMessage = error.localizedDescription
            }
        }
    }

    /// Maps AtomType to EntityType for navigation (shared with the
    /// notification router).
    private func mapAtomTypeToEntityType(_ atomType: AtomType) -> EntityType {
        MainAtomEntityTypeMap.entityType(for: atomType)
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
                    .foregroundStyle(CosmoColors.textPrimary)

                ProgressView()
                    .scaleEffect(1.2)
                    .tint(CosmoColors.lavender)

                Text("Initializing your cognitive space...")
                    .font(.subheadline)
                    .foregroundStyle(CosmoColors.textSecondary)
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
                    .foregroundStyle(CosmoColors.softRed)

                Text("Error")
                    .font(.title.bold())
                    .foregroundStyle(CosmoColors.textPrimary)

                Text(message)
                    .font(.body)
                    .foregroundStyle(CosmoColors.textSecondary)
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

// MARK: - Persistence Guard Rails (Data-Safety Pass, June 2026)

/// Notification that opens the Trash sheet (posted by the app menu command).
extension Notification.Name {
    static let cosmoOpenTrash = Notification.Name("com.cosmo.nav.openTrash")
}

/// Self-contained overlay hosting the save-failure banner and the Trash sheet.
/// Lives in MainView's ZStack; everything it needs is observed internally so
/// MainView itself stays unchanged.
struct PersistenceGuardRailsOverlay: View {
    @State private var bannerText: String?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var showTrash = false

    var body: some View {
        VStack {
            if let bannerText {
                saveFailureBanner(bannerText)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .sheet(isPresented: $showTrash) {
            CosmoTrashView()
        }
        .onReceive(NotificationCenter.default.publisher(for: PersistenceHealth.incidentRecorded)) { notification in
            handleIncident(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmoOpenTrash)) { _ in
            showTrash = true
        }
    }

    private func saveFailureBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Save problem")
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
            Button("Dismiss") {
                withAnimation { bannerText = nil }
            }
            .buttonStyle(.plain)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.orange.opacity(0.35), lineWidth: 1))
        .padding(.top, 14)
    }

    private func handleIncident(_ notification: Notification) {
        guard let kind = notification.userInfo?["kind"] as? String,
              kind == PersistenceHealth.IncidentKind.writeFailure.rawValue
                  || kind == PersistenceHealth.IncidentKind.syncFailure.rawValue else { return }
        let context = notification.userInfo?["context"] as? String ?? "a recent change"
        withAnimation {
            bannerText = kind == PersistenceHealth.IncidentKind.syncFailure.rawValue
                ? "Cloud sync issue (\(context)) — changes are safe locally and will retry."
                : "A save failed (\(context)) — recent changes may not be persisted."
        }
        bannerDismissTask?.cancel()
        bannerDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            withAnimation { bannerText = nil }
        }
    }
}

/// Trash: every soft-deleted atom, restorable in one click. Backs the guarantee
/// that nothing the user deletes is unrecoverable until they explicitly purge it.
struct CosmoTrashView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleted: [Atom] = []
    @State private var isLoading = true
    @State private var purgeCandidate: Atom?

    var body: some View {
        VStack(spacing: 0) {
            trashHeader
            Divider()
            trashContent
        }
        .frame(width: 540, height: 480)
        .task { await reload() }
        .confirmationDialog(
            "Permanently delete \"\(purgeCandidate?.title ?? "item")\"? This cannot be undone.",
            isPresented: Binding(get: { purgeCandidate != nil }, set: { if !$0 { purgeCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let atom = purgeCandidate {
                    Task { await purge(atom) }
                }
            }
            Button("Cancel", role: .cancel) { purgeCandidate = nil }
        }
    }

    private var trashHeader: some View {
        HStack {
            Label("Trash", systemImage: "trash")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var trashContent: some View {
        if isLoading {
            Spacer()
            ProgressView()
            Spacer()
        } else if deleted.isEmpty {
            Spacer()
            Text("Trash is empty")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            List(deleted, id: \.uuid) { atom in
                trashRow(atom)
            }
            .listStyle(.inset)
        }
    }

    private func trashRow(_ atom: Atom) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(atom))
                    .font(.callout)
                    .lineLimit(1)
                Text("\(atom.type.rawValue) · deleted \(atom.updatedAt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Restore") {
                Task { await restore(atom) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(minHeight: 44)
            Button {
                purgeCandidate = atom
            } label: {
                Image(systemName: "xmark.bin")
                    .accessibilityLabel("Delete permanently")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
        }
    }

    private func displayTitle(_ atom: Atom) -> String {
        if let title = atom.title, !title.isEmpty { return title }
        if let body = atom.body, !body.isEmpty { return String(body.prefix(60)) }
        return "Untitled"
    }

    private func reload() async {
        isLoading = true
        deleted = (try? await AtomRepository.shared.fetchDeleted()) ?? []
        isLoading = false
    }

    private func restore(_ atom: Atom) async {
        do {
            try await AtomRepository.shared.restore(uuid: atom.uuid)
            deleted.removeAll { $0.uuid == atom.uuid }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Trash.restore(\(atom.uuid.prefix(8)))", detail: error.localizedDescription)
        }
    }

    private func purge(_ atom: Atom) async {
        do {
            try await AtomRepository.shared.hardDelete(uuid: atom.uuid, confirmed: true)
            deleted.removeAll { $0.uuid == atom.uuid }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Trash.purge(\(atom.uuid.prefix(8)))", detail: error.localizedDescription)
        }
        purgeCandidate = nil
    }
}

// MARK: - Cross-Thinkspace Drag Preview Host

/// The one view that observes CrossThinkspaceDragManager. Its
/// `floatingPosition` publishes on every pointer frame during a
/// cross-thinkspace drag — isolating the observation here keeps those
/// 120Hz writes from re-evaluating MainView's whole body.
private struct CrossThinkspaceDragPreviewHost: View {
    @ObservedObject var manager: CrossThinkspaceDragManager

    var body: some View {
        if manager.isOverSidebar || manager.hasThinkspaceSwitched,
           let block = manager.draggedBlock {
            CrossThinkspaceDragPreview(block: block)
                .position(manager.floatingPosition)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Glass Overlay Host

/// The one view that observes CosmoGlassCenter. Its `streamingContent`
/// publishes on every AI stream chunk — isolating the observation here keeps
/// those publishes from re-evaluating MainView's whole body. The spring is
/// the same curve MainView used to carry on `glassCenter.isVisible`.
private struct MainGlassOverlayHost: View {
    @ObservedObject private var glassCenter = CosmoGlassCenter.shared

    var body: some View {
        ZStack {
            if glassCenter.isVisible {
                VStack {
                    HStack {
                        Spacer()
                        CosmoGlassOverlayView()
                            .environmentObject(glassCenter)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: glassCenter.isVisible)
    }
}

// MARK: - Instagram Modal Host

/// The one view that observes SwipeFileEngine (its processing state publishes
/// per capture step). Same isolation pattern as MainGlassOverlayHost; the
/// spring is the curve MainView used to carry on `showInstagramModal`.
private struct MainInstagramModalHost: View {
    @ObservedObject private var swipeFileEngine = SwipeFileEngine.shared

    var body: some View {
        ZStack {
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
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: swipeFileEngine.showInstagramModal)
    }
}
