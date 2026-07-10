// CosmoOS/Core/CosmoApp.swift
// Main application entry point for the first Cognition OS

import SwiftUI
import AppKit
import GRDB

@main
struct CosmoApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var database = CosmoDatabase.shared
    @StateObject private var voiceEngine = VoiceEngine.shared
    @StateObject private var cosmoCore = CosmoCore.shared
    @StateObject private var semanticSearch = SemanticSearchEngine.shared
    @StateObject private var notifications = ProactiveNotificationService.shared
    @StateObject private var syncEngine = SyncEngine.shared
    @StateObject private var statePersistence = StatePersistence.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var glassCenter = CosmoGlassCenter.shared
    @StateObject private var swipeFileEngine = SwipeFileEngine.shared
    @StateObject private var cosmoAgent = CosmoAgentService.shared

    @State private var voicePillWindow: VoicePillWindowController?
    @State private var voicePillHideWorkItem: DispatchWorkItem?
    // NOTE: Global floating dock removed - using in-app dock + spacebar voice overlay instead

    @State private var themeRefreshID = UUID()
    @State private var interactiveStartupTask: Task<Void, Never>?

    var body: some Scene {
        WindowGroup {
            MainView()
                .id(themeRefreshID)
                .preferredColorScheme(ThemeManager.shared.isDark ? .dark : .light)
                .environmentObject(appState)
                .environmentObject(database)
                .environmentObject(voiceEngine)
                .environmentObject(cosmoCore)
                .environmentObject(semanticSearch)
                .environmentObject(syncEngine)
                .environmentObject(statePersistence)
                .environmentObject(networkMonitor)
                .environmentObject(glassCenter)
                .environmentObject(swipeFileEngine)
                .environmentObject(cosmoAgent)
                .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Theme.changed)) { _ in
                    themeRefreshID = UUID()
                }
                .onAppear {
                    initializeApp()
                }
                .onOpenURL { url in
                    // Handle Supabase OAuth callback (cosmoos://auth/callback?...)
                    // The official Supabase SDK handles this automatically
                    // via its internal session listener
                    print("📲 OAuth callback received: \(url.scheme ?? "")://\(url.host ?? "")")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CosmoCommands()
        }
    }

    private func initializeApp() {
        // Interval from here to MainView's first onAppear ≈ blocking launch work.
        AppPerformanceInstrumentation.event("app-init-start")
        // Migrate Supabase credentials from hardcoded to Keychain (one-time)
        APIKeys.seedSupabaseIfNeeded()

        // Session distiller: turns idle inline-assistant sessions into durable
        // memory (fires on app-resign-active and session switches).
        CosmoSessionDistiller.shared.activate()

        // Check for existing Supabase Auth session BEFORE starting Telegram bridge.
        // This ensures isSignedIn is set before the bridge decides whether to poll or skip.
        Task {
            await SupabaseAuthService.shared.checkExistingSession()
            if SupabaseAuthService.shared.isSignedIn {
                RealtimeSyncService.shared.startListening()
                PromptTemplateStore.shared.syncAllTemplatesToCloud()
            }
            // NOW start the Telegram bridge — it checks isSignedIn to skip polling when cloud agent is active
            if APIKeys.hasTelegramBot {
                await TelegramBridgeService.shared.start()
            }

            // Inbox hygiene: drain stuck pending captures through the classifier
            // queue and dismiss captures another system already consumed.
            InboxIngestService.shared.reconcileOnLaunch()

            // Recall-index reconciliation: catch atoms that are missing from
            // the semantic index OR stale (content changed since indexing).
            // Deferred so it never competes with interactive startup.
            try? await Task.sleep(for: .seconds(60))
            _ = await RecallIndexer.shared.backfill()

            // Version-history maintenance: apply the tiered retention policy
            // (at most once per day; cheap no-op otherwise).
            await AtomRevisionPruner.pruneIfDue()
        }

        // Observe system wake to process swipes captured while asleep
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                SwipeProcessingService.shared.scanForPendingSwipes()
            }
        }

        // Observe app termination to flush pending saves before exit
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Flush every registered dirty editing surface synchronously (canvas
            // blocks, sticky notes, swipe study — anything with a debounced save),
            // then give active focus modes their notification-based flush.
            MainActor.assumeIsolated {
                DirtyEditorRegistry.shared.flushAll()
            }
            NotificationCenter.default.post(name: .cosmoAppWillTerminate, object: nil)
        }

        // Restore UI state
        restoreUIState()

        // Initialize voice system (hotkey registered immediately, speech/LLM loaded async)
        // Hotkey registration happens in VoiceEngine.init() for immediate availability
        // Speech recognition TCC is handled gracefully without crashing
        Task {
            await voiceEngine.initialize()
        }
        startInteractiveStartupPipeline()

        // Register Swipe File hotkey (Cmd+Shift+S)
        print("📋 Registering Swipe File hotkey callback...")
        HotkeyManager.shared.registerSwipeFileHotkey { [weak swipeFileEngine] in
            print("📋 Swipe File callback invoked!")
            Task { @MainActor in
                if let engine = swipeFileEngine {
                    print("📋 Calling captureFromClipboard...")
                    await engine.captureFromClipboard()
                } else {
                    print("⚠️ SwipeFileEngine is nil in callback!")
                }
            }
        }
        print("📋 Swipe File hotkey callback registered")

        // Setup command bar (hidden by default, revealed on activation)
        voicePillWindow = VoicePillWindowController()
        // voicePillWindow?.setupTriggerZone()  // Disabled — settings cog replaces trigger zone

        // Register Option-C hotkey to open command bar typing mode
        HotkeyManager.shared.registerCommandBarTypingHotkey {
            NotificationCenter.default.post(name: .activateCommandBarTyping, object: nil)
        }
        print("⌨️ Option-C hotkey registered for command bar typing")

        // Option+A opens the inline assistant instead of the retired floating Cosmo Window.
        HotkeyManager.shared.registerCosmoWindowHotkey {
            Task { @MainActor in
                CosmoAssistantHotkeyRouter.openFromOptionA()
            }
        }
        print("⌨️ Inline assistant hotkey registered (⌥A)")

        // Initialize the floating Atom Window (⌥E)
        // Force singleton creation so its NSEvent monitors are active immediately
        // (CGEvent tap may not be available without Accessibility permission)
        _ = AtomWindowPanelController.shared
        HotkeyManager.shared.registerAtomWindowHotkey {
            Task { @MainActor in
                AtomWindowPanelController.shared.toggle()
            }
        }
        print("📄 Atom Window panel initialized (⌥E hotkey registered)")

        // Initialize the Capture Anywhere panel (configurable hotkey, default ⌥C)
        _ = CaptureOverlayPanelController.shared
        HotkeyManager.shared.registerCaptureHotkey {
            Task { @MainActor in
                CaptureOverlayPanelController.shared.toggle()
            }
        }
        print("📥 Capture Anywhere panel initialized (\(HotkeyManager.shared.captureHotkey.displayName) hotkey registered)")

        // Menu-bar leaf: click opens the capture panel, drops capture instantly.
        CaptureStatusItemController.shared.install()

        // Observe voice engine state for recording indicator updates
        NotificationCenter.default.addObserver(
            forName: .voiceRecordingStateChanged,
            object: nil,
            queue: .main
        ) { notification in
            if let isRecording = notification.userInfo?["isRecording"] as? Bool {
                print("🎤 Recording state: \(isRecording)")
                if isRecording {
                    voicePillWindow?.show()  // Reveal pill with listening mode
                }
                // Dismiss is handled by CommandBarView's onChange after flash
            }
        }

        // Listen for entity open requests
        NotificationCenter.default.addObserver(
            forName: .openEntity,
            object: nil,
            queue: .main
        ) { [weak appState, weak statePersistence] notification in
            if let type = notification.userInfo?["type"] as? EntityType,
               let id = notification.userInfo?["id"] as? Int64 {
                Task { @MainActor in
                    appState?.selectedEntity = EntitySelection(id: id, type: type)
                    statePersistence?.saveLastOpenedEntity(type: type, id: id)
                }
            }
        }

        // Inquiry Workspace: open Deep Dive Overview by UUID
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.Inquiry.openDeepDive,
            object: nil,
            queue: .main
        ) { notification in
            guard let uuid = notification.userInfo?["uuid"] as? String else { return }
            Task { @MainActor in
                guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
                      let id = atom.id else { return }
                FocusNavigationCoordinator.shared.open(entity: EntitySelection(id: id, type: .deepDive))
            }
        }

        // Inquiry Workspace: start (or resume) an Inquiry Session
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.Inquiry.startInquiry,
            object: nil,
            queue: .main
        ) { [weak appState] notification in
            guard let anchorUUID = notification.userInfo?["anchorUUID"] as? String,
                  let anchorTypeRaw = notification.userInfo?["anchorType"] as? String else { return }
            let resumeSessionUUID = notification.userInfo?["resumeSessionUUID"] as? String
            let mainQuestionTitle = notification.userInfo?["mainQuestionTitle"] as? String
            let rootQuestionUUID = notification.userInfo?["rootQuestionUUID"] as? String
            Task { @MainActor in
                await InquirySessionLauncher.shared.launch(
                    anchorUUID: anchorUUID,
                    anchorType: anchorTypeRaw,
                    resumeSessionUUID: resumeSessionUUID,
                    mainQuestionTitle: mainQuestionTitle,
                    rootQuestionUUID: rootQuestionUUID,
                    appState: appState
                )
            }
        }

        // Listen for undo/redo commands (from menu bar Cmd+Z / Cmd+Shift+Z)
        NotificationCenter.default.addObserver(
            forName: .performUndo,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await CosmoUndoManager.shared.undo()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .performRedo,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await CosmoUndoManager.shared.redo()
            }
        }

        // Listen for navigation (to persist state)
        NotificationCenter.default.addObserver(
            forName: .navigateToSection,
            object: nil,
            queue: .main
        ) { [weak appState, weak statePersistence] notification in
            if let section = notification.userInfo?["section"] as? NavigationSection {
                Task { @MainActor in
                    appState?.selectedSection = section
                    statePersistence?.saveSelectedSection(section)
                }
            }
        }

        // Telegram bridge is started in the auth Task above (after checkExistingSession)
        // to prevent race condition where polling starts before isSignedIn is set.
        AgentProactiveScheduler.shared.scheduleAll()

        print("✅ CosmoOS initialized")
        print("   🧠 Cosmo AI: Ready")
        print("   🔍 Semantic Search: Indexing...")
        print("   🔔 Proactive Notifications: Enabled")
        print("   🔄 Sync Engine: \(networkMonitor.isConnected ? "Online" : "Offline")")
        print("   💾 State Persistence: Loaded")
        print("   📋 Swipe File: ⌘⇧S Hotkey Registered")
        print("   🤖 Cosmo Agent: \(APIKeys.hasTelegramBot ? "Telegram Active" : "Configure in Settings")")
    }

    private func restoreUIState() {
        // Restore selected section
        appState.selectedSection = statePersistence.getSelectedSection()

        // Restore last opened entity
        if let lastEntity = statePersistence.getLastOpenedEntity() {
            appState.selectedEntity = EntitySelection(id: lastEntity.id, type: lastEntity.type)
        }
    }

    private func startInteractiveStartupPipeline() {
        interactiveStartupTask?.cancel()
        interactiveStartupTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            await BuiltInRules.seedIfNeeded()
            await MainActor.run {
                AutomationDispatcher.shared.start()
            }

            guard !Task.isCancelled else { return }
            await NoteRepairService.shared.repairNotesIfNeeded()

            guard !Task.isCancelled else { return }
            await LessonExtractor.shared.migrateExistingLessons()

            guard !Task.isCancelled else { return }
            await LessonExtractor.shared.migrateEnforcementLevels()

            guard !Task.isCancelled else { return }
            await LessonExtractor.shared.migrateModuleLessonsToAtoms()

            guard !Task.isCancelled else { return }
            await semanticSearch.indexAllEntities()

            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                SwipeProcessingService.shared.scanForPendingSwipes()
            }
        }
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var selectedSection: NavigationSection = .home {  // Start on home canvas
        didSet { VoiceContextStore.shared.selectedSection = selectedSection }
    }
    @Published var selectedEntity: EntitySelection? = nil {
        didSet { VoiceContextStore.shared.selectedEntity = selectedEntity }
    }
    @Published var focusedEntity: EntitySelection? = nil {  // For Focus Mode (full-screen editing)
        didSet { VoiceContextStore.shared.focusedEntity = focusedEntity }
    }
    @Published var isLoading = false
    @Published var error: String? = nil
    @Published var isCommandKVisible = false

    init() {
        // Initialize app state
        print("🚀 CosmoOS initializing...")

        // Prime voice context with initial state
        VoiceContextStore.shared.selectedSection = selectedSection
        VoiceContextStore.shared.selectedEntity = selectedEntity
        VoiceContextStore.shared.focusedEntity = focusedEntity

        // Listen for navigation commands from voice
        NotificationCenter.default.addObserver(
            forName: .navigateToSection,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let section = notification.object as? NavigationSection {
                Task { @MainActor in
                    self?.selectedSection = section
                }
            }
        }

        // NOTE: `.enterFocusMode` is handled exclusively by MainView, which
        // routes it through FocusTransitionCoordinator — a second observer
        // here used to race it with an unanimated `focusedEntity` set.
    }

    /// When a block tries to enter focus mode with an invalid id (<=0),
    /// create the backing entity immediately and return its id.
    ///
    /// Routes through AtomRepository — the legacy ideas/content/tasks/research
    /// tables stopped syncing or appearing in atom-based UI after
    /// migrate_legacy_to_atoms; rows created there were stranded (invisible
    /// everywhere = user content silently lost).
    @MainActor
    static func createEntityForFocusMode(type: EntityType) async -> Int64? {
        let atomType: AtomType?
        let title: String
        switch type {
        case .idea: atomType = .idea; title = "New Idea"
        case .content: atomType = .content; title = "New Content"
        case .task: atomType = .task; title = "New Task"
        case .research: atomType = .research; title = "New Research"
        case .connection: atomType = .connection; title = "New Concept"
        default: atomType = nil; title = ""
        }
        guard let atomType else { return nil }

        do {
            let created = try await AtomRepository.shared.create(Atom.new(type: atomType, title: title))
            return created.id
        } catch {
            print("❌ Failed to create focus mode entity (\(type.rawValue)): \(error)")
            PersistenceHealth.note(.writeFailure, context: "createEntityForFocusMode(\(type.rawValue))", detail: error.localizedDescription)
            return nil
        }
    }
}

// MARK: - Navigation Section
public enum NavigationSection: String, CaseIterable, Identifiable, Sendable {
    case home = "Home"
    case today = "Today"
    case ideas = "Ideas"
    case content = "Content"
    case connections = "Connections"
    case research = "Research"
    case projects = "Projects"
    case calendar = "Calendar"
    case canvas = "Canvas"
    case library = "Library"
    case cosmo = "Cosmo"

    public var id: String { rawValue }

    /// User-facing name. Raw values are persisted (StatePersistence) and
    /// routed on, so the connections→Concepts rename lives here only.
    public var displayName: String {
        self == .connections ? "Concepts" : rawValue
    }

    public static var allCases: [NavigationSection] {
        [.home, .today, .ideas, .content, .connections, .research, .calendar, .canvas, .library, .cosmo]
    }

    public var icon: String {
        switch self {
        case .home: return "house.fill"
        case .today: return "calendar.badge.clock"
        case .ideas: return "lightbulb.fill"
        case .content: return "doc.text.fill"
        case .connections: return "person.2.fill"
        case .research: return "magnifyingglass"
        case .projects: return "folder.fill"
        case .calendar: return "calendar"
        case .canvas: return "square.on.square.dashed"
        case .library: return "books.vertical.fill"
        case .cosmo: return "brain.head.profile"
        }
    }
}

// MARK: - Entity Selection
public struct EntitySelection: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let type: EntityType

    public var navigationId: String {
        "\(type.rawValue)_\(id)"
    }

    public init(id: Int64, type: EntityType) {
        self.id = id
        self.type = type
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
    }
}

// MARK: - Entity Type
public enum EntityType: String, Codable, Sendable {
    case idea
    case content
    case connection
    case research
    case task
    case project
    case note
    case thinkspace  // Saved Thinkspace canvas configurations
    case cosmo
    case cosmoAI = "cosmo_ai"  // Live AI block on canvas
    case calendar
    case journal
    case swipeFile = "swipe_file"  // Curated content swipe file
    case image                     // Native image blocks on canvas
    case stickyNote = "sticky_note" // Square sticky note blocks on canvas
    case liveQuery = "live_query"   // Live query block that auto-updates with matching atoms
    case ideaBoard = "idea_board"   // Client idea board — live-updating idea list from Command-K
    case template                   // Smart templatable block (user-defined structured blocks)
    case deepDive = "deep_dive"     // Inquiry Workspace: Deep Dive portal block (mastery topic home)
    case inquirySession = "inquiry_session"  // Inquiry Workspace: live inquiry session (focus mode)
    case portal                     // Window into another thinkspace (region miniature, travel on open)

    public var icon: String {
        switch self {
        case .idea: return "lightbulb.fill"
        case .content: return "doc.text.fill"
        case .connection: return "person.2.fill"
        case .research: return "magnifyingglass"
        case .task: return "checkmark.circle.fill"
        case .project: return "folder.fill"
        case .note: return "note.text"
        case .stickyNote: return "square.and.pencil"
        case .thinkspace: return "rectangle.3.group"
        case .cosmo, .cosmoAI: return "brain.head.profile"
        case .calendar: return "calendar"
        case .journal: return "book.fill"
        case .swipeFile: return "bookmark.fill"
        case .image: return "photo.fill"
        case .liveQuery: return "bolt.horizontal.fill"
        case .ideaBoard: return "list.bullet.rectangle.portrait.fill"
        case .template: return "rectangle.3.group.fill"
        case .deepDive: return "circle.hexagongrid.circle.fill"
        case .inquirySession: return "rectangle.split.3x1.fill"
        case .portal: return "arrow.up.forward.app"
        }
    }

    public var color: Color {
        switch self {
        case .idea: return DS.entityIdea
        case .content: return DS.entityContent
        case .connection: return DS.entityConnection
        case .research: return DS.entityResearch
        case .task: return DS.entityTask
        case .project: return DS.entityContent  // Projects share content blue
        case .note: return DS.entityNote
        case .stickyNote: return DS.entityStickyNote
        case .thinkspace: return DS.accent
        case .cosmo: return DS.accent
        case .cosmoAI: return DS.accent
        case .calendar: return DS.entityTask
        case .journal: return DS.entityNote
        case .swipeFile: return DS.entitySwipe
        case .image: return DS.entityImage
        case .liveQuery: return DS.accent
        case .ideaBoard: return DS.entityIdea
        case .template: return DS.accent
        case .deepDive: return DS.accent
        case .inquirySession: return DS.accent
        case .portal: return DS.accent
        }
    }
}

// MARK: - Menu Commands
struct CosmoCommands: Commands {
    var body: some Commands {
        // Settings (⌘,) - proper macOS Preferences handling
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        // New Item commands
        CommandGroup(replacing: .newItem) {
            Button("New Idea") {
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.createEntityAtPosition,
                    object: nil,
                    userInfo: ["type": EntityType.idea]
                )
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("New Task") {
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.createEntityAtPosition,
                    object: nil,
                    userInfo: ["type": EntityType.task]
                )
            }
            .keyboardShortcut("t", modifiers: [.command])

            Divider()

            Button("Capture to Inbox") {
                NotificationCenter.default.post(name: CosmoNotification.Inbox.focusCaptureField, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("Command Palette") {
                NotificationCenter.default.post(name: .showCommandPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button("Toggle Cosmo") {
                CosmoAssistantHotkeyRouter.openFromOptionA()
            }
            .keyboardShortcut("a", modifiers: [.option])

            // Menu-path twin of the global capture hotkey — keeps Capture
            // Anywhere reachable when Accessibility permission is missing.
            Button("Capture Anywhere") {
                CaptureOverlayPanelController.shared.toggle()
            }
            .keyboardShortcut("c", modifiers: [.option])
        }

        // Native macOS View menu entries for the active Inquiry Workspace.
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Trash…") {
                NotificationCenter.default.post(name: .cosmoOpenTrash, object: nil)
            }

            Divider()

            Button("Inquiry: Research") {
                NotificationCenter.default.post(
                    CosmoNotification.Inquiry.layoutRequested,
                    payload: CosmoNotification.Inquiry.LayoutPayload(mode: .research)
                )
            }

            Button("Inquiry: Read") {
                NotificationCenter.default.post(
                    CosmoNotification.Inquiry.layoutRequested,
                    payload: CosmoNotification.Inquiry.LayoutPayload(mode: .read)
                )
            }

            Button("Inquiry: Write") {
                NotificationCenter.default.post(
                    CosmoNotification.Inquiry.layoutRequested,
                    payload: CosmoNotification.Inquiry.LayoutPayload(mode: .write)
                )
            }

            Button("Inquiry: Map") {
                NotificationCenter.default.post(
                    CosmoNotification.Inquiry.layoutRequested,
                    payload: CosmoNotification.Inquiry.LayoutPayload(mode: .map)
                )
            }

            Button("Inquiry: Review") {
                NotificationCenter.default.post(
                    CosmoNotification.Inquiry.layoutRequested,
                    payload: CosmoNotification.Inquiry.LayoutPayload(mode: .review)
                )
            }

            Divider()

            Button("Focus Inquiry Thinking Dock") {
                NotificationCenter.default.post(name: CosmoNotification.Inquiry.focusThinkingDock, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Button("Refresh Inquiry Sources") {
                NotificationCenter.default.post(name: CosmoNotification.Inquiry.refreshSources, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button("Crystallize Inquiry Session") {
                NotificationCenter.default.post(name: CosmoNotification.Inquiry.crystallizeActive, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }

        // Pasteboard commands (⌘C / ⌘X / ⌘V / ⌘A)
        // When an NSTextView is first responder, route to the responder chain.
        // Otherwise, Paste posts a notification so the canvas can handle image/URL paste.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                if BlockSelectionClipboardTarget.send(.cut) {
                    return
                }

                if !FocusModeTextClipboardTarget.send(.cut, in: NSApp.keyWindow) {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("x", modifiers: [.command])

            Button("Copy") {
                if BlockSelectionClipboardTarget.send(.copy) {
                    return
                }

                if !FocusModeTextClipboardTarget.send(.copy, in: NSApp.keyWindow) {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button("Paste") {
                if FocusModeTextClipboardTarget.send(.paste, in: NSApp.keyWindow) {
                    return
                }

                if let window = NSApp.keyWindow,
                   let firstResponder = window.firstResponder,
                   firstResponder is NSTextView {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                } else {
                    NotificationCenter.default.post(name: .performCanvasPaste, object: nil)
                }
            }
            .keyboardShortcut("v", modifiers: [.command])

            Button("Select All") {
                if BlockSelectionClipboardTarget.send(.selectAll) {
                    return
                }

                if !FocusModeTextClipboardTarget.send(.selectAll, in: NSApp.keyWindow) {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("a", modifiers: [.command])
        }

        // Undo/Redo commands (⌘Z / ⌘⇧Z)
        // When an NSTextView is first responder, route to the responder chain
        // so the text view's built-in NSUndoManager handles character-level undo.
        // Otherwise, route to CosmoUndoManager for canvas operations.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if let window = NSApp.keyWindow,
                   let firstResponder = window.firstResponder,
                   firstResponder is NSTextView {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } else {
                    NotificationCenter.default.post(name: .performUndo, object: nil)
                }
            }
            .keyboardShortcut("z", modifiers: [.command])

            Button("Redo") {
                if let window = NSApp.keyWindow,
                   let firstResponder = window.firstResponder,
                   firstResponder is NSTextView {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                } else {
                    NotificationCenter.default.post(name: .performRedo, object: nil)
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        
        // Text Formatting commands (⌘B / ⌘I)
        CommandGroup(after: .textFormatting) {
            Button("Bold") {
                EditorCommandBus.shared.toggleFormatting(.bold)
            }
            .keyboardShortcut("b", modifiers: [.command])

            Button("Italic") {
                EditorCommandBus.shared.toggleFormatting(.italic)
            }
            .keyboardShortcut("i", modifiers: [.command])
            
            Divider()
            
            Button("Heading 1") {
                EditorCommandBus.shared.toggleFormatting(.heading1)
            }
            .keyboardShortcut("1", modifiers: [.command])
            
            Button("Heading 2") {
                EditorCommandBus.shared.toggleFormatting(.heading2)
            }
            .keyboardShortcut("2", modifiers: [.command])
        }

        CommandGroup(replacing: .help) {
            Button("Cosmo Help") {
                // TODO: Open help
            }
        }
    }
}

// MARK: - Undo/Redo/Paste Notification Names
extension Notification.Name {
    static let performUndo = Notification.Name("com.cosmo.performUndo")
    static let performRedo = Notification.Name("com.cosmo.performRedo")
    static let performCanvasPaste = Notification.Name("com.cosmo.performCanvasPaste")
    static let toggleCalendarWindow = Notification.Name("com.cosmo.toggleCalendarWindow")
}
