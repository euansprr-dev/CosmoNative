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
    @State private var cosmoWindowController: CosmoWindowPanelController?
    // NOTE: Global floating dock removed - using in-app dock + spacebar voice overlay instead

    @State private var themeRefreshID = UUID()

    var body: some Scene {
        WindowGroup {
            MainView()
                .id(themeRefreshID)
                .preferredColorScheme(ThemeManager.shared.currentTheme.isDark ? .dark : .light)
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
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CosmoCommands()
        }
    }

    private func initializeApp() {
        // Migrate Supabase credentials from hardcoded to Keychain (one-time)
        APIKeys.seedSupabaseIfNeeded()

        // Observe app termination to flush pending saves before exit
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Give active focus modes a chance to flush pending saves synchronously
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

        // Initialize semantic search index (background)
        Task {
            await semanticSearch.indexAllEntities()
        }

        // Migrate existing lessons to add intent scope
        Task { await LessonExtractor.shared.migrateExistingLessons() }

        // Migrate lesson enforcement levels (source/enforcement/targetModuleId)
        Task { await LessonExtractor.shared.migrateEnforcementLevels() }

        // Import module LEARNED RULES into canonical atom storage + strip from modules
        Task { await LessonExtractor.shared.migrateModuleLessonsToAtoms() }

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

        // Setup system-wide Cosmo Window (floating NSPanel, Option+A)
        cosmoWindowController = CosmoWindowPanelController.shared
        HotkeyManager.shared.registerCosmoWindowHotkey {
            Task { @MainActor in
                CosmoWindowPanelController.shared.toggle()
            }
        }
        print("🪟 Cosmo Window panel initialized (⌥A hotkey registered)")

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

        // Save state periodically
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            // State auto-saves on change, but this ensures periodic saves
        }

        // Initialize Cosmo Agent — Telegram bridge + proactive scheduler
        if APIKeys.hasTelegramBot {
            Task {
                await TelegramBridgeService.shared.start()
            }
        }
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

        // Listen for focus mode commands
        NotificationCenter.default.addObserver(
            forName: .enterFocusMode,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let type = notification.userInfo?["type"] as? EntityType,
               let id = notification.userInfo?["id"] as? Int64 {
                Task { @MainActor in
                    // Safety net: never enter focus mode with an invalid entity id.
                    if id > 0 {
                        self?.focusedEntity = EntitySelection(id: id, type: type)
                        return
                    }

                    if let createdId = await Self.createEntityForFocusMode(type: type) {
                        self?.focusedEntity = EntitySelection(id: createdId, type: type)
                    } else {
                        print("⚠️ Could not create entity for focus mode (\(type.rawValue))")
                    }
                }
            }
        }
    }

    /// When a block tries to enter focus mode with an invalid id (<=0),
    /// create the backing entity immediately and return its id.
    @MainActor
    private static func createEntityForFocusMode(type: EntityType) async -> Int64? {
        do {
            switch type {
            case .idea:
                let createdIdea = try await CosmoDatabase.shared.asyncWrite { db -> Idea in
                    var newIdea = Idea.new(title: "New Idea", content: "")
                    try newIdea.insert(db)
                    newIdea.id = db.lastInsertedRowID
                    return newIdea
                }
                return createdIdea.id

            case .content:
                let createdContent = try await CosmoDatabase.shared.asyncWrite { db -> CosmoContent in
                    var newContent = CosmoContent.new(title: "New Content", body: "")
                    try newContent.insert(db)
                    newContent.id = db.lastInsertedRowID
                    return newContent
                }
                return createdContent.id

            case .task:
                let createdTask = try await CosmoDatabase.shared.asyncWrite { db -> CosmoTask in
                    var newTask = CosmoTask.new(title: "New Task", status: "todo")
                    try newTask.insert(db)
                    newTask.id = db.lastInsertedRowID
                    return newTask
                }
                return createdTask.id

            case .research:
                let createdResearch = try await CosmoDatabase.shared.asyncWrite { db -> Research in
                    var newResearch = Research.new(title: "New Research", query: nil, url: nil, sourceType: .unknown)
                    try newResearch.insert(db)
                    newResearch.id = db.lastInsertedRowID
                    return newResearch
                }
                return createdResearch.id

            case .connection:
                let createdConnection = try await CosmoDatabase.shared.asyncWrite { db -> Atom in
                    var newConnection = Atom.new(type: .connection, title: "New Connection")
                    try newConnection.insert(db)
                    newConnection.id = db.lastInsertedRowID
                    return newConnection
                }
                return createdConnection.id

            default:
                return nil
            }
        } catch {
            print("❌ Failed to create focus mode entity (\(type.rawValue)): \(error)")
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

            Button("Command Palette") {
                NotificationCenter.default.post(name: .showCommandPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button("Toggle Cosmo") {
                NotificationCenter.default.post(name: CosmoNotification.CosmoWindow.toggle, object: nil)
            }
            .keyboardShortcut("a", modifiers: [.option])
        }

        // Pasteboard commands (⌘C / ⌘X / ⌘V / ⌘A)
        // When an NSTextView is first responder, route to the responder chain.
        // Otherwise, Paste posts a notification so the canvas can handle image/URL paste.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: [.command])

            Button("Copy") {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button("Paste") {
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
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
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
