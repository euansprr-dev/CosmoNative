// CosmoOS/Navigation/MainNotificationRouter.swift
// Zero-size host for MainView's NotificationCenter routing (perf audit W14).
//
// These handlers used to ride as ~45 .onReceive modifiers directly on
// MainView's ~3000-line body, so every body evaluation re-diffed the whole
// subscription stack above destinationContent and the overlay tree. Here they
// subscribe on a Color.clear leaf instead: pure state writes go through
// bindings, and anything that needs MainView's private choreography
// (Command-K presentation, trail moves, pane routing) calls back through
// `Actions`.

import SwiftUI
import AppKit
import Combine

/// AtomType → EntityType mapping for navigation, shared by MainView and the
/// notification router.
enum MainAtomEntityTypeMap {
    static func entityType(for atomType: AtomType) -> EntityType {
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
        case .extract, .question:
            // Inquiry captures open the peek reader — the old .idea fallback
            // dumped them into the Idea workbench, which even wrote idea
            // metadata onto extract atoms.
            return .extract
        default:
            return .idea
        }
    }
}

struct MainNotificationRouter: View {
    /// MainView choreography the router can't reach through a binding.
    struct Actions {
        var presentCommandK: () -> Void
        var preserveCommandKBehindFocusMode: () -> Void
        var openAtomFromCommandK: (_ atomUUID: String) -> Void
        var goToObjectFromCommandK: (_ atomUUID: String) -> Void
        var closeCommandK: () -> Void
        /// Guarded twin: closing an already-closed palette would still clear
        /// its view model, losing preserved search state.
        var closeCommandKIfOpen: () -> Void
        var applyWorkbench: (Workbench) -> Void
        var navigateTrailBack: () -> Void
        var navigateTrailForward: () -> Void
        var jumpTrail: (NavigationTrail.Moment) -> Void
        var openBlockInFocusMode: (_ atomUUID: String, _ asPane: Bool, _ restoreCommandKOnFocusClose: Bool) -> Void
        var handleVoiceNavigation: (_ destination: String) -> Void
        var toggleSidebar: () -> Void
        var openBrowserURL: (_ url: URL, _ title: String?, _ disposition: BrowserOpenDisposition) -> Void
        var openCollaboratorPane: (_ atomUUID: String, _ presetId: String?) -> Void
        var openInlineAssistantPane: () -> Void
        var navigateToLastThinkspace: () -> Void
        var fileAtomIntoThinkspace: (_ atomUUID: String, _ targetThinkspaceId: String) -> Void
        var switchToThinkspace: (_ atomID: Int64) -> Void
        var openCreatorProfile: (_ creatorUUID: String) -> Void
    }

    // Plain references, deliberately unobserved — handlers only touch these
    // inside notification closures, never in body.
    let appState: AppState
    let paneManager: PaneManager

    @Binding var currentDestination: SidebarDestination
    @Binding var inboxRoute: SidebarInboxRoute
    @Binding var ideasBoardRequest: String?
    @Binding var commandKReturnTab: CommandKTab?
    @Binding var showSettings: Bool
    @Binding var showWorkbenchComposer: Bool
    @Binding var spokesPillar: Atom?
    @Binding var isThinkspaceLibraryActive: Bool
    @Binding var showCreatorDatabase: Bool

    let actions: Actions

    var body: some View {
        ZStack {
            destinationReceivers
            focusAndTrailReceivers
            paneReceivers
            canvasReceivers
            commandKReceivers
        }
        .frame(width: 0, height: 0)
    }

    // MARK: - Destinations & Sidebar

    private var destinationReceivers: some View {
        Color.clear
            // ⌥⌘N — jump to the inbox with the capture field focused (InboxView
            // focuses the field when it receives the same notification).
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inbox.focusCaptureField)) { _ in
                inboxRoute = .global
                currentDestination = .inbox
            }
            // Command Center "to triage" chip and other deep links into the queue.
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inbox.open)) { _ in
                inboxRoute = .global
                currentDestination = .inbox
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.navigateToCommandCenter)) { _ in
                currentDestination = .commandCenter
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openSwipeGallery)) { notification in
                // The capture receipt (and anything else) can name the ROOM it
                // wants: a "Swiped · Newsletter" click lands in Newsletters, not
                // the posts home. Posts and unknown genres keep the old landing.
                if let raw = notification.userInfo?["genre"] as? String,
                   let genre = SwipeGenre.resolve(raw), genre != .post {
                    currentDestination = .swipeFile(section: .genre(genre))
                } else {
                    currentDestination = .swipeFile(section: .home)
                }
                actions.closeCommandK()
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openIdeas)) { notification in
                ideasBoardRequest = notification.userInfo?["clientUUID"] as? String
                currentDestination = .ideas
                actions.closeCommandK()
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.navigateToThinkspaceById)) { notification in
                guard let payload = CosmoNotification.Navigation.ThinkspacePayload(from: notification) else { return }
                currentDestination = .thinkspace(id: payload.thinkspaceId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceNavigationRequested)) { notification in
                guard let destination = notification.userInfo?["destination"] as? String else { return }
                actions.handleVoiceNavigation(destination)
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.thinkspaceModeChanged)) { notification in
                let isLibrary = notification.userInfo?["isLibrary"] as? Bool ?? false
                withAnimation(ProMotionSprings.gentle) {
                    isThinkspaceLibraryActive = isLibrary
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
                FocusModeEditorBlur.clearFirstResponder(in: NSApp.keyWindow)
                showSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.toggleSidebar)) { _ in
                actions.toggleSidebar()
            }
    }

    // MARK: - Focus Modes, Trail & Workbenches

    private var focusAndTrailReceivers: some View {
        Color.clear
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
                    let sourceFrame = (notification.userInfo?["sourceFrame"] as? NSValue)?.rectValue
                    FocusNavigationCoordinator.shared.open(
                        entity: EntitySelection(id: id, type: type),
                        sourceFrame: sourceFrame
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .exitFocusMode)) { _ in
                FocusNavigationCoordinator.shared.close()
            }
            // UUID-keyed navigation from Command Center surfaces: task play routes
            // its primary linked atom here, and task-title mention pills post the
            // same name. The coordinator owns the actual open.
            .onReceive(NotificationCenter.default.publisher(for: .init("com.cosmo.navigateToAtom"))) { notification in
                guard let uuid = notification.userInfo?["uuid"] as? String else { return }
                FocusNavigationCoordinator.shared.open(atomUUID: uuid)
                // Secondary linked atoms ride along as panes (play-task fan-out).
                guard let paneUUIDs = notification.userInfo?["paneAtomUUIDs"] as? [String],
                      !paneUUIDs.isEmpty else { return }
                Task { @MainActor in
                    for paneUUID in paneUUIDs {
                        guard let atom = try? await AtomRepository.shared.fetch(uuid: paneUUID),
                              let atomId = atom.id else { continue }
                        NotificationCenter.default.post(
                            name: CosmoNotification.Navigation.openAsPane,
                            object: nil,
                            userInfo: [
                                "id": atomId,
                                "type": AtomWindowViewModel.entityType(for: atom.type)
                            ]
                        )
                    }
                }
            }
            // Open block in focus mode by UUID (used by promoteToContent, context panels, etc.)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openBlockInFocusMode)) { notification in
                guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }
                let shouldOpenAsPane = notification.userInfo?["asPane"] as? Bool == true
                let shouldRestoreCommandK = notification.userInfo?["restoreCommandKOnFocusClose"] as? Bool ?? true
                actions.openBlockInFocusMode(atomUUID, shouldOpenAsPane, shouldRestoreCommandK)
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.applyWorkbench)) { notification in
                guard let uuid = notification.userInfo?["uuid"] as? String else { return }
                Task { @MainActor in
                    await WorkbenchStore.shared.loadIfNeeded()
                    guard let bench = WorkbenchStore.shared.workbenches.first(where: { $0.uuid == uuid }) else { return }
                    actions.applyWorkbench(bench)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.composeWorkbench)) { _ in
                showWorkbenchComposer = true
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.trailStepBack)) { _ in
                // Esc/back from a study surface: retrace the trail like the back
                // arrow; with no history left, settle back onto the canvas.
                if NavigationTrail.shared.canGoBack {
                    actions.navigateTrailBack()
                } else {
                    FocusNavigationCoordinator.shared.close()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.trailStepForward)) { _ in
                actions.navigateTrailForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.trailJump)) { notification in
                guard let momentId = notification.userInfo?["momentId"] as? String,
                      let uuid = UUID(uuidString: momentId),
                      let moment = NavigationTrail.shared.backStack.first(where: { $0.id == uuid }) else { return }
                actions.jumpTrail(moment)
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.compileSpokes)) { notification in
                guard let entityId = notification.userInfo?["id"] as? Int64 else { return }
                Task { @MainActor in
                    guard let atom = try? await AtomRepository.shared.fetch(id: entityId) else { return }
                    withAnimation(ProMotionSprings.modal) {
                        spokesPillar = atom
                    }
                }
            }
    }

    // MARK: - Peek, Panes & Assistant Surfaces

    private var paneReceivers: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.peekEntity)) { notification in
                let anchor = (notification.userInfo?["anchor"] as? NSValue)?.rectValue

                if let entityType = notification.userInfo?["type"] as? EntityType,
                   let entityId = notification.userInfo?["id"] as? Int64 {
                    PeekController.shared.peek(
                        .entity(EntitySelection(id: entityId, type: entityType)),
                        from: anchor
                    )
                    return
                }

                // String-payload variant (Command-K actions post [String: String])
                if let uuid = notification.userInfo?["uuid"] as? String {
                    Task { @MainActor in
                        guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
                              let atomId = atom.id else { return }
                        let entityType = MainAtomEntityTypeMap.entityType(for: atom.type)
                        PeekController.shared.peek(
                            .entity(EntitySelection(id: atomId, type: entityType)),
                            from: anchor
                        )
                    }
                }
            }
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
                } else if notification.userInfo?["commandCenter"] as? Bool == true {
                    guard paneManager.canOpenCommandCenter() else { return }
                    withAnimation(ProMotionSprings.snappy) {
                        paneManager.openPane(.commandCenter)
                    }
                } else if notification.userInfo?["swipeGallery"] as? Bool == true {
                    withAnimation(ProMotionSprings.snappy) {
                        if paneManager.canOpenSwipeGallery() {
                            paneManager.openPane(.swipeGallery)
                        } else {
                            paneManager.activatePane(PaneContent.swipeGallery.id)
                        }
                    }
                }
                // Dismiss Command-K if it's open
                actions.closeCommandKIfOpen()
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openWebBrowserPane)) { notification in
                let url = (notification.userInfo?["url"] as? URL)
                    ?? (notification.userInfo?["urlString"] as? String).flatMap(URL.init(string:))
                guard let url else { return }

                let title = notification.userInfo?["title"] as? String
                let disposition = (notification.userInfo?["disposition"] as? String)
                    .flatMap(BrowserOpenDisposition.init(rawValue:)) ?? .reuse
                actions.openBrowserURL(url, title, disposition)
                actions.closeCommandKIfOpen()
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openCosmoWindowPane)) { _ in
                withAnimation(ProMotionSprings.snappy) {
                    paneManager.openOrActivateCosmoWindow()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openCollaboratorPane)) { notification in
                guard let payload = CosmoNotification.Navigation.CollaboratorPanePayload(from: notification) else { return }
                actions.openCollaboratorPane(payload.atomUUID, payload.presetId)
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openInlineAssistant)) { _ in
                actions.openInlineAssistantPane()
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openInlineAssistantPane)) { _ in
                actions.openInlineAssistantPane()
            }
            // onReceive, not onChange: nothing here may observe the assistant
            // store (its composerText publishes per keystroke and its run
            // state per stream event).
            .onReceive(CosmoInlineAssistantStore.shared.$isPaneRequested.removeDuplicates()) { isRequested in
                guard isRequested else { return }
                actions.openInlineAssistantPane()
                CosmoInlineAssistantStore.shared.dismissPaneRequest()
            }
            // Legacy Cosmo toggle requests now open the inline assistant surface.
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.CosmoWindow.toggle)) { _ in
                CosmoAssistantHotkeyRouter.openFromOptionA()
            }
            // Atom Window toggle + open (floating atom viewer)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.AtomWindow.toggle)) { _ in
                AtomWindowPanelController.shared.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.AtomWindow.openAtom)) { notification in
                if let uuid = notification.userInfo?["uuid"] as? String {
                    AtomWindowPanelController.shared.show(atomUUID: uuid)
                }
            }
    }

    // MARK: - Canvas Placement & Creators

    private var canvasReceivers: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .addSwipeToCanvas)) { notification in
                guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }

                actions.closeCommandK()

                actions.navigateToLastThinkspace()
                // Queued placement: delivered the moment the canvas is mounted, active,
                // and observing — posts immediately when it already is (no timer race).
                CanvasPendingPlacementQueue.shared.enqueue(
                    name: .openEntityOnCanvas,
                    userInfo: ["atomUUID": atomUUID]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("addIdeaToCanvas"))) { notification in
                guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }

                actions.closeCommandK()

                actions.navigateToLastThinkspace()
                CanvasPendingPlacementQueue.shared.enqueue(
                    name: .openEntityOnCanvas,
                    userInfo: ["atomUUID": atomUUID]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("addIdeaBoardToCanvas"))) { notification in
                let clientUUID = notification.userInfo?["clientUUID"] as? String ?? ""
                let clientName = notification.userInfo?["clientName"] as? String ?? "Client"

                actions.closeCommandK()

                actions.navigateToLastThinkspace()
                CanvasPendingPlacementQueue.shared.enqueue(
                    name: Notification.Name("createIdeaBoardBlock"),
                    userInfo: [
                        "clientUUID": clientUUID,
                        "clientName": clientName
                    ]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.addToCanvas)) { notification in
                guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }

                actions.closeCommandK()

                actions.navigateToLastThinkspace()
                CanvasPendingPlacementQueue.shared.enqueue(
                    name: .openEntityOnCanvas,
                    userInfo: ["atomUUID": atomUUID]
                )
            }
            // Cmd+K single-click: add item to current canvas (Thinkspace fallback)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.addItemToCurrentCanvas)) { notification in
                guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }
                // Research/Connection focus modes host their own canvases and
                // consume this notification themselves. Every other focus mode has
                // no canvas, so fall through to the thinkspace placement below —
                // the verb must never silently no-op.
                if let focused = appState.focusedEntity,
                   focused.type == .research || focused.type == .connection {
                    return
                }

                actions.closeCommandK()

                // Fetch atom and add to Thinkspace canvas
                Task { @MainActor in
                    if let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                        let entityType = MainAtomEntityTypeMap.entityType(for: atom.type)
                        actions.navigateToLastThinkspace()
                        CanvasPendingPlacementQueue.shared.enqueue(
                            name: .openEntityOnCanvas,
                            userInfo: ["type": entityType, "id": atom.id ?? Int64(0)]
                        )
                    }
                }
            }
            // ⌘K filing verb: drop an atom onto a thinkspace result — moves its
            // block there (or creates one) WITHOUT navigating. The user is filing,
            // not visiting.
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.moveAtomToThinkspace)) { notification in
                guard let atomUUID = notification.userInfo?["atomUUID"] as? String,
                      let targetThinkspaceId = notification.userInfo?["targetThinkspaceId"] as? String else { return }
                actions.fileAtomIntoThinkspace(atomUUID, targetThinkspaceId)
            }
            // Switch to the selected Thinkspace from Command-K
            .onReceive(NotificationCenter.default.publisher(for: .switchToThinkspace)) { notification in
                if let id = notification.userInfo?["id"] as? Int64 {
                    actions.switchToThinkspace(id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openCreatorDatabase"))) { _ in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showCreatorDatabase = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openCreatorProfile"))) { notification in
                guard let creatorUUID = notification.userInfo?["creatorUUID"] as? String else { return }
                actions.openCreatorProfile(creatorUUID)
            }
    }

    // MARK: - Command-K Presentation

    private var commandKReceivers: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
                actions.presentCommandK()
            }
            // NodeGraph Command-K atom opening handler
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.openAtomFromCommandK)) { notification in
                guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }
                actions.openAtomFromCommandK(atomUUID)
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.goToObjectFromCommandK)) { notification in
                guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }
                actions.goToObjectFromCommandK(atomUUID)
            }
            // Command-K close handler (from background tap or escape in CommandKView)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.closeCommandK)) { _ in
                actions.closeCommandK()
            }
            // Command-K hide handler — keeps view alive but hidden behind focus mode
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.hideCommandK)) { _ in
                actions.preserveCommandKBehindFocusMode()
            }
    }
}
