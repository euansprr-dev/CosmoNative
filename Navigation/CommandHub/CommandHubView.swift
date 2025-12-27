// CosmoOS/Navigation/CommandHub/CommandHubView.swift
// The Cognition Hub - Revolutionary Ctrl+K Command Center
// Replaces Finder, sidebars, and traditional navigation with spatial thinking

import SwiftUI

// MARK: - Command Hub View
struct CommandHubView: View {
    @Binding var isPresented: Bool
    @StateObject private var engine = CommandHubEngine()
    @StateObject private var captureController = CommandHubCaptureController()
    @EnvironmentObject var voiceEngine: VoiceEngine
    @EnvironmentObject var appState: AppState

    // MARK: - State
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var hubSize: CGSize = CGSize(width: 680, height: 560)
    @State private var isExpanded = false
    @State private var selectedFilter: EntityType? = nil
    @State private var showLibrary = true
    @State private var appearAnimationComplete = false
    @State private var creatingEntityTypes: Set<CircleAppType> = [] // Debounce flag
    @State private var currentMode: CommandHubMode = .library
    @State private var showProjectCreationModal = false

    @FocusState private var isSearchFocused: Bool
    @GestureState private var resizeDrag: CGSize = .zero

    // Size constraints
    private let minSize = CGSize(width: 560, height: 420)
    private let maxSize = CGSize(width: 900, height: 800)
    private let expandedSize = CGSize(width: 800, height: 680)

    var body: some View {
        ZStack {
            // Scrim background
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissHub()
                }

            // Main Hub Container
            VStack(spacing: 0) {
                // Drag handle for repositioning
                DragHandle()
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Search Bar Section
                HubSearchBar(
                    query: $query,
                    isListening: voiceEngine.isRecording,
                    onVoiceToggle: toggleVoice,
                    onSubmit: executeSearch,
                    onPaste: { pasted in
                        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.looksLikeURL, URLClassifier.classify(trimmed) != nil {
                            // Treat paste as capture intent, not a search query.
                            query = ""
                        }
                        captureController.handlePaste(pasted)
                    }
                )
                .focused($isSearchFocused)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Divider with dynamic label
                HStack {
                    Text(currentMode == .library ? "LIBRARY" : "INBOX VIEWS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(CosmoColors.textTertiary)

                    Rectangle()
                        .fill(CosmoColors.glassGrey.opacity(0.5))
                        .frame(height: 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // Mode-specific content with horizontal scroll animation
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Library Browser
                        LibraryBrowser(
                            query: query,
                            selectedFilter: $selectedFilter,
                            onEntitySingleTap: handleEntitySingleTap,
                            onEntityDoubleTap: handleEntityDoubleTap,
                            captureState: captureController.state,
                            onCaptureAction: handleCaptureAction
                        )
                        .frame(width: geometry.size.width)

                        // Inbox Views Mode
                        InboxViewsMode(
                            selectedIndex: $selectedIndex,
                            onSelect: handleInboxViewSelection
                        )
                        .frame(width: geometry.size.width)
                    }
                    .offset(x: currentMode == .library ? 0 : -geometry.size.width)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentMode)
                }
                .opacity(appearAnimationComplete ? 1 : 0)
                .offset(y: appearAnimationComplete ? 0 : 15)
                .clipped()

                // Bottom bar with mode indicator and voice status
                HStack(spacing: 0) {
                    // Mode tabs (left section)
                    HStack(spacing: 16) {
                        ModeTabButton(title: "Library", isActive: currentMode == .library) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                currentMode = .library
                                selectedIndex = 0
                            }
                        }
                        
                        Text("·")
                            .foregroundColor(CosmoColors.textTertiary.opacity(0.4))
                        
                        ModeTabButton(title: "Inbox", isActive: currentMode == .inboxViews) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                currentMode = .inboxViews
                                selectedIndex = 0
                                query = ""
                            }
                        }
                    }
                    
                    Spacer()

                    // Context-aware mode indicator
                    if engine.isContextAwareMode {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 10))
                            Text("Sorted by relevance")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(CosmoColors.lavender)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CosmoColors.lavender.opacity(0.1), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else {
                        // Tab hint (only show when not in context mode)
                        HStack(spacing: 4) {
                            KeyboardKey(symbol: "tab")
                            Text("Switch")
                                .font(.system(size: 10))
                                .foregroundColor(CosmoColors.textTertiary)
                        }
                    }

                    Spacer()

                    // Voice status (right section)
                    if voiceEngine.isRecording || voiceEngine.isProcessing {
                        MiniVoiceStatus(
                            isRecording: voiceEngine.isRecording,
                            isProcessing: voiceEngine.isProcessing,
                            audioLevels: voiceEngine.audioLevels
                        )
                    } else {
                        HStack(spacing: 4) {
                            KeyboardKey(symbol: "space")
                            Text("Voice")
                                .font(.system(size: 10))
                                .foregroundColor(CosmoColors.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Rectangle()
                        .fill(CosmoColors.glassGrey.opacity(0.08))
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(CosmoColors.glassGrey.opacity(0.2))
                        .frame(height: 1)
                }
            }
            .frame(
                width: currentSize.width,
                height: currentSize.height
            )
            .background(hubBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(hubBorder)
            // Optimized single shadow (GPU-friendly)
            .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
            .compositingGroup()
            // NOTE: Removed .drawingGroup() - it breaks TextField input, Menu buttons,
            // and other interactive elements (they show prohibited signs)
            .overlay(alignment: .bottomTrailing) {
                ResizeHandle(size: $hubSize, minSize: minSize, maxSize: maxSize)
                    .padding(8)
            }
            .scaleEffect(isPresented ? 1.0 : 0.95)
            .opacity(isPresented ? 1.0 : 0)
        }
        .onAppear {
            isSearchFocused = true
            engine.loadDefaults()

            // Staggered appearance animation
            withAnimation(HubSprings.overlay.delay(0.1)) {
                appearAnimationComplete = true
            }
        }
        .onChange(of: query) { _, newValue in
            selectedIndex = 0
            engine.search(newValue)
        }
        .onKeyPress(.escape) {
            dismissHub()
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.return) {
            executeSelected()
            return .handled
        }
        .onKeyPress(.tab) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                currentMode = currentMode == .library ? .inboxViews : .library
                selectedIndex = 0
                if currentMode == .inboxViews {
                    query = ""
                }
            }
            return .handled
        }
        .sheet(isPresented: $showProjectCreationModal) {
            ProjectCreationModal(
                isPresented: $showProjectCreationModal,
                onProjectCreated: { project in
                    handleInboxViewSelection(.projectInbox(
                        projectUuid: project.uuid,
                        projectName: project.title ?? "Untitled",
                        projectIcon: "💼",
                        projectColor: project.color
                    ))
                }
            )
        }
    }

    // MARK: - Computed Properties

    private var currentSize: CGSize {
        CGSize(
            width: clamp(hubSize.width + resizeDrag.width, min: minSize.width, max: maxSize.width),
            height: clamp(hubSize.height + resizeDrag.height, min: minSize.height, max: maxSize.height)
        )
    }

    private var hubBackground: some View {
        ZStack {
            // Base glass layer
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            // Soft white overlay for readability
            RoundedRectangle(cornerRadius: 20)
                .fill(CosmoColors.softWhite.opacity(0.85))

            // Subtle gradient overlay
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.clear,
                            CosmoColors.lavender.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var hubBorder: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.8),
                        Color.white.opacity(0.4),
                        CosmoColors.glassGrey.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    // MARK: - Actions

    private func dismissHub() {
        withAnimation(HubSprings.overlay) {
            isPresented = false
        }
    }

    private func toggleVoice() {
        Task {
            if voiceEngine.isRecording {
                await voiceEngine.stopRecording()
            } else {
                await voiceEngine.startRecording()
            }
        }
    }

    private func handleCircleAppTap(_ appType: CircleAppType) {
        // Debounce: prevent duplicate creations
        guard !creatingEntityTypes.contains(appType) else {
            print("⚠️ Already creating \(appType.rawValue), ignoring duplicate tap")
            return
        }
        
        creatingEntityTypes.insert(appType)
        
        dismissHub()

        // Post notification to create on canvas
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch appType {
            case .calendar:
                NotificationCenter.default.post(name: .openCalendarWindow, object: nil)
            case .ideas:
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.createEntityAtPosition,
                    object: nil,
                    userInfo: ["type": EntityType.idea, "position": CGPoint(x: 500, y: 400)]
                )
            case .content:
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.createEntityAtPosition,
                    object: nil,
                    userInfo: ["type": EntityType.content, "position": CGPoint(x: 500, y: 400)]
                )
            case .connections:
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.createEntityAtPosition,
                    object: nil,
                    userInfo: ["type": EntityType.connection, "position": CGPoint(x: 500, y: 400)]
                )
            case .projects:
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.createEntityAtPosition,
                    object: nil,
                    userInfo: ["type": EntityType.project, "position": CGPoint(x: 500, y: 400)]
                )
            case .research:
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.createEntityAtPosition,
                    object: nil,
                    userInfo: ["type": EntityType.research, "position": CGPoint(x: 500, y: 400)]
                )
            }
            
            // Clear debounce flag after creation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                creatingEntityTypes.remove(appType)
            }
        }
    }

    // MARK: - Single-click: Create floating block
    private func handleEntitySingleTap(_ entity: LibraryEntity) {
        dismissHub()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Check if focus mode is active
            if appState.focusedEntity != nil {
                // Create block in focus mode canvas
                NotificationCenter.default.post(
                    name: .createEntityInFocusMode,
                    object: nil,
                    userInfo: ["type": entity.type, "id": entity.entityId]
                )
            } else {
                // Create block on home canvas
                NotificationCenter.default.post(
                    name: .openEntityOnCanvas,
                    object: nil,
                    userInfo: ["type": entity.type, "id": entity.entityId]
                )
            }
        }
    }

    // MARK: - Double-click: Open in focus mode
    private func handleEntityDoubleTap(_ entity: LibraryEntity) {
        dismissHub()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": entity.type, "id": entity.entityId]
            )
        }
    }

    private func executeSearch() {
        if let firstResult = engine.results.first {
            handleResultSelection(firstResult)
        }
    }

    private func handleCaptureAction(_ state: CommandHubCaptureController.State) {
        switch state {
        case .duplicate(let existingId, _):
            handleEntityDoubleTap(LibraryEntity(
                entityId: existingId,
                type: .research,
                title: "Saved Research",
                preview: ""
            ))
        case .failed:
            captureController.retry()
        case .capturing(let capture):
            // Open in focus if user clicks the capture card.
            handleEntityDoubleTap(LibraryEntity(
                entityId: capture.researchId,
                type: .research,
                title: capture.titleHint,
                preview: ""
            ))
        default:
            break
        }
    }

    private func executeSelected() {
        if query.isEmpty {
            if selectedIndex < engine.defaultItems.count {
                handleResultSelection(engine.defaultItems[selectedIndex])
            }
        } else {
            if selectedIndex < engine.results.count {
                handleResultSelection(engine.results[selectedIndex])
            }
        }
    }

    private func handleResultSelection(_ result: PaletteResult) {
        dismissHub()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch result.type {
            case .entity(let entityType, let id):
                // For Thinkspaces - switch to that Thinkspace
                if entityType == .thinkspace {
                    NotificationCenter.default.post(
                        name: .switchToThinkspace,
                        object: nil,
                        userInfo: ["id": id]
                    )
                }
                // For Ideas, Content, Research, Connections - open as floating block on canvas
                else if [.idea, .content, .research, .connection].contains(entityType) {
                    NotificationCenter.default.post(
                        name: .openEntityOnCanvas,
                        object: nil,
                        userInfo: ["type": entityType, "id": id]
                    )
                } else {
                    // For other types, use Focus Mode
                    NotificationCenter.default.post(
                        name: .enterFocusMode,
                        object: nil,
                        userInfo: ["type": entityType, "id": id]
                    )
                }
            case .command(let command):
                executeCommand(command)
            case .category(let section):
                NotificationCenter.default.post(name: .navigateToSection, object: section)
            case .create(let entityType):
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.createEntityAtPosition,
                    object: nil,
                    userInfo: ["type": entityType, "position": CGPoint(x: 500, y: 400)]
                )
            case .saveURL(let urlString, let urlType):
                Task {
                    await processAndSaveURL(urlString, type: urlType)
                }
            }
        }
    }

    private func executeCommand(_ command: String) {
        switch command {
        case "open_calendar", "open_calendar_window":
            NotificationCenter.default.post(name: .openCalendarWindow, object: nil)
        case "open_cosmo":
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.createCosmoAIBlock,
                object: nil,
                userInfo: ["position": CGPoint(x: 500, y: 400)]
            )
        default:
            break
        }
    }

    // MARK: - Inbox View Selection Handler
    private func handleInboxViewSelection(_ selection: InboxViewSelection) {
        if case .createProject = selection {
            showProjectCreationModal = true
            return
        }

        dismissHub()

        let canvasCenter = CGPoint(x: 500, y: 400)
        let block: InboxViewBlock

        switch selection {
        case .general, .generalInbox:
            block = InboxViewBlock.general(at: canvasCenter)
        case .allUncommitted:
            block = InboxViewBlock.allUncommitted(at: canvasCenter)
        case .recentlyPromoted:
            block = InboxViewBlock.recentlyPromoted(at: canvasCenter)
        case .projectInbox(let projectUuid, let projectName, let projectIcon, let projectColor):
            block = InboxViewBlock.projectInbox(
                projectUuid: projectUuid,
                projectName: projectName,
                projectIcon: projectIcon,
                projectColor: projectColor,
                at: canvasCenter
            )
        case .statusFilter:
            block = InboxViewBlock.general(at: canvasCenter)  // Status filter not implemented
        case .typeFilter(let entityType):
            block = InboxViewBlock.typeFilter(entityType: entityType, at: canvasCenter)
        case .createProject:
            return  // Handled above
        }

        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.createInboxBlock,
            object: nil,
            userInfo: ["block": block]
        )
    }

    private func processAndSaveURL(_ urlString: String, type: URLType) async {
        guard let url = URL(string: urlString) else { return }

        do {
            let research = try await ResearchProcessor.shared.processURL(url, type: type)
            NotificationCenter.default.post(
                name: .createResearchBlock,
                object: nil,
                userInfo: ["researchId": research.id ?? 0, "position": CGPoint(x: 500, y: 400)]
            )
        } catch {
            print("❌ Failed to process URL: \(error)")
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = query.isEmpty ? engine.defaultItems.count : engine.results.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}

// MARK: - Drag Handle
struct DragHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(CosmoColors.glassGrey)
            .frame(width: 40, height: 4)
    }
}

// MARK: - Resize Handle
struct ResizeHandle: View {
    @Binding var size: CGSize
    let minSize: CGSize
    let maxSize: CGSize

    @GestureState private var dragOffset: CGSize = .zero
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isHovered ? CosmoColors.textSecondary : CosmoColors.textTertiary)
            .frame(width: 20, height: 20)
            .background(
                Circle()
                    .fill(isHovered ? CosmoColors.glassGrey.opacity(0.5) : Color.clear)
            )
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        size.width = clamp(size.width + value.translation.width, min: minSize.width, max: maxSize.width)
                        size.height = clamp(size.height + value.translation.height, min: minSize.height, max: maxSize.height)

                        // Persist to UserDefaults
                        UserDefaults.standard.set(size.width, forKey: "CommandHubWidth")
                        UserDefaults.standard.set(size.height, forKey: "CommandHubHeight")
                    }
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}

// MARK: - Hub Spring Animations
enum HubSprings {
    /// For hub entrance/exit
    static let overlay = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// For Circle Apps hover
    static let snappy = Animation.spring(response: 0.2, dampingFraction: 0.7)

    /// For cards stagger
    static let stagger = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let staggerDelay: Double = 0.04

    /// For press feedback
    static let press = Animation.spring(response: 0.15, dampingFraction: 0.6)

    /// For hover lift
    static let hover = Animation.spring(response: 0.2, dampingFraction: 0.8)
}

// MARK: - Circle App Types
enum CircleAppType: String, CaseIterable {
    case calendar
    case ideas
    case content
    case connections
    case projects
    case research

    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .ideas: return "lightbulb.fill"
        case .content: return "doc.text.fill"
        case .connections: return "link.circle.fill"
        case .projects: return "folder.fill"
        case .research: return "magnifyingglass"
        }
    }

    var label: String {
        switch self {
        case .calendar: return "Calendar"
        case .ideas: return "Ideas"
        case .content: return "Content"
        case .connections: return "Connections"
        case .projects: return "Projects"
        case .research: return "Research"
        }
    }

    var color: Color {
        switch self {
        case .calendar: return CosmoColors.coral
        case .ideas: return CosmoColors.lavender
        case .content: return CosmoColors.skyBlue
        case .connections: return CosmoMentionColors.connection
        case .projects: return CosmoColors.emerald
        case .research: return CosmoColors.emerald
        }
    }

    var entityType: EntityType {
        switch self {
        case .calendar: return .calendar
        case .ideas: return .idea
        case .content: return .content
        case .connections: return .connection
        case .projects: return .project
        case .research: return .research
        }
    }
}

// MARK: - Library Entity
struct LibraryEntity: Identifiable {
    let id = UUID()
    let entityId: Int64
    let type: EntityType
    let title: String
    let preview: String
    let metadata: [String: String]
    let updatedAt: Date?

    init(entityId: Int64, type: EntityType, title: String, preview: String, metadata: [String: String] = [:], updatedAt: Date? = nil) {
        self.entityId = entityId
        self.type = type
        self.title = title
        self.preview = preview
        self.metadata = metadata
        self.updatedAt = updatedAt
    }
}

// MARK: - Mode Tab Button
struct ModeTabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? CosmoColors.textPrimary : CosmoColors.textTertiary)
                
                // Active indicator underline
                Rectangle()
                    .fill(isActive ? CosmoColors.lavender : Color.clear)
                    .frame(width: isActive ? 24 : 0, height: 2)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isActive)
            }
        }
        .buttonStyle(.plain)
        .opacity(isHovered && !isActive ? 0.7 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Mini Voice Status (for bottom bar)
struct MiniVoiceStatus: View {
    let isRecording: Bool
    let isProcessing: Bool
    let audioLevels: [Float]
    
    var body: some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(isRecording ? CosmoColors.emerald : CosmoColors.lavender)
                .frame(width: 6, height: 6)
                .scaleEffect(isRecording ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: isRecording)
            
            // Status text
            Text(isProcessing ? "Thinking..." : "Listening...")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isRecording ? CosmoColors.emerald : CosmoColors.lavender)
            
            // Mini waveform bars
            if isRecording {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(CosmoColors.emerald)
                            .frame(width: 2, height: barHeight(for: i))
                    }
                }
                .frame(height: 12)
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let level = index < audioLevels.count ? CGFloat(audioLevels[index]) : 0.3
        return 4 + level * 8
    }
}

// MARK: - Preview
#if DEBUG
struct CommandHubView_Previews: PreviewProvider {
    static var previews: some View {
        CommandHubView(isPresented: .constant(true))
            .environmentObject(VoiceEngine.shared)
            .frame(width: 800, height: 700)
            .background(CosmoColors.canvasBackground)
    }
}
#endif
