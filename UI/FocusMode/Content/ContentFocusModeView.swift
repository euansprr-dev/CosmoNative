// CosmoOS/UI/FocusMode/Content/ContentFocusModeView.swift
// Main Content Focus Mode container — unified single-page editor
// February 2026

import SwiftUI
import Combine
import GRDB
import AppKit

// MARK: - Content Focus Mode View

/// Unified single-page Content Focus Mode.
/// Left sidebar (outline/hooks/core idea) + center editor + right sidebar (context OR polish).
struct ContentFocusModeView: View {
    // MARK: - Properties

    let atom: Atom
    let onClose: () -> Void

    // MARK: - State

    @StateObject private var viewModel: ContentFocusModeViewModel
    @State private var showAICollaborator = false
    @State private var showSettings = false
    @State private var editableTitle: String
    @State private var titleDocument: RichDocument = .empty
    @State private var draftDocument: RichDocument = .empty
    @StateObject private var writingEngine = UnifiedWritingEngine()

    /// Local draft content — decoupled from @Published viewModel to avoid full view re-renders on every keystroke
    @State private var localDraftContent: String = ""

    /// Typewriter mode — cursor stays vertically centered while typing
    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @AppStorage("typewriterMode") private var typewriterMode = false

    /// Tracks the last AI-generated draft content so we can detect user edits for lesson extraction
    @State private var lastAIGeneratedDraft: String?

    /// Currently selected text in the draft editor (empty when no selection)
    @State private var selectedText: String = ""

    /// Polish mode: when active, highlights appear on text + right sidebar swaps to polish analysis
    @State private var isPolishModeActive: Bool = false

    /// Polish analysis for Hemingway highlights
    @State private var polishAnalysis: WritingAnalysis?

    // Inline AI state (moved from ContentDraftView)
    @State private var selectionInfo: DraftSelectionInfo = .empty
    @State private var inlineAIState: InlineAIState = .idle
    @StateObject private var inlineAssistant = AIWritingAssistant()
    @State private var textContentHeight: CGFloat = 400
    @State private var draftEditorOrigin: CGPoint = .zero
    @State private var selectedRephraseIndex: Int = 0

    // Auto-save state
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var saveState: DraftSaveState = .idle
    private let autoSaveDelay: TimeInterval = 1.5

    // Debounced polish analysis
    @State private var polishDebounceTask: Task<Void, Never>?

    // AI Draft generation state
    @State private var isGeneratingDraft = false
    @State private var draftGenerationError: String?

    // Left sidebar visibility
    @State private var sidebarVisible: Bool = false

    enum DraftSaveState { case idle, saving, saved }

    enum ContentLayoutMode { case compact, regular, full }

    // Feature flag: when true, the embedded AI Collaborator is hidden (replaced by global Cosmo window)
    @AppStorage("cosmoWindowEnabled") private var cosmoWindowEnabled = true

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneActive) private var isPaneActive

    // Responsive layout
    @State private var layoutMode: ContentLayoutMode = .full

    private var editorMaxWidth: CGFloat {
        switch layoutMode {
        case .compact: return .infinity
        case .regular: return 640
        case .full: return 780
        }
    }

    private var editorHorizontalPadding: CGFloat {
        switch layoutMode {
        case .compact: return 20
        case .regular: return 32
        case .full: return 48
        }
    }

    private var editorTopPadding: CGFloat {
        switch layoutMode {
        case .compact: return 20
        case .regular: return 32
        case .full: return 48
        }
    }

    private var editorBottomPadding: CGFloat {
        switch layoutMode {
        case .compact: return 24
        case .regular: return 40
        case .full: return 60
        }
    }

    private var topSpacerHeight: CGFloat {
        switch layoutMode {
        case .compact: return 40
        case .regular: return 56
        case .full: return 72
        }
    }

    private var titleFontSize: CGFloat {
        switch layoutMode {
        case .compact: return 24
        case .regular: return 28
        case .full: return 34
        }
    }

    private var titleMinHeight: CGFloat {
        switch layoutMode {
        case .compact: return 40
        case .regular: return 48
        case .full: return 60
        }
    }

    private func updateLayoutMode(for width: CGFloat) {
        let newMode: ContentLayoutMode
        if width < 500 { newMode = .compact }
        else if width < 900 { newMode = .regular }
        else { newMode = .full }
        if layoutMode != newMode { layoutMode = newMode }
    }

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._editableTitle = State(initialValue: atom.title ?? "Untitled Content")
        self._viewModel = StateObject(wrappedValue: ContentFocusModeViewModel(atom: atom))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            DS.bg
                .ignoresSafeArea()

            // Main content
            VStack(spacing: 0) {
                // Top bar spacer
                Spacer().frame(height: topSpacerHeight)

                // Unified editor or post-creation phase
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Top bar overlay (fixed)
            VStack {
                topBar
                Spacer()
            }
            .zIndex(10)

            // Left sidebar trigger + overlay (UniversalFocusSidebar)
            if ContentFocusModeState.stepForPhase(viewModel.displayPhase) != nil {
                leftSidebarOverlay
                    .zIndex(50)
            }

            if ContentFocusModeState.stepForPhase(viewModel.displayPhase) != nil {
                floatingPolishButtonOverlay
                    .zIndex(40)
            }

            // AI Collaborator floating popover (hidden when global Cosmo window is enabled)
            if !cosmoWindowEnabled && showAICollaborator {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ContentAICollaboratorView(
                            engine: writingEngine,
                            isVisible: $showAICollaborator,
                            contentAtom: atom,
                            state: $viewModel.state
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity),
                            removal: .scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity)
                        ))
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 64)
                }
                .zIndex(100)
            }

            // Pane close button overlay
            if isPaneContext {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(DS.buttonText)
                                .foregroundStyle(DS.textMuted)
                                .frame(width: 28, height: 28)
                                .background(DS.border, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.top, 16)
                    }
                    Spacer()
                }
            }

            // XP award animation overlay
            if let xp = viewModel.xpAwarded {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("+\(xp) XP")
                            .font(DS.title2)
                            .foregroundStyle(DS.green)
                            .shadow(color: DS.green.opacity(0.5), radius: 8)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            ))
                        Spacer()
                    }
                    .padding(.bottom, 80)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.xpAwarded)
                .zIndex(200)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.xpAwarded)
        .animation(ProMotionSprings.snappy, value: showAICollaborator)
        .animation(ProMotionSprings.snappy, value: isPolishModeActive)
        .onAppear {
            AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
            viewModel.loadState()
            localDraftContent = viewModel.state.draftContent
            draftDocument = viewModel.state.richDraftDocument ?? RichDocument.migrateLegacy(viewModel.state.draftContent)
            titleDocument = RichDocumentPersistence.loadAtomDocument(
                field: .title,
                metadata: atom.metadata,
                fallbackPlainText: atom.title
            )
            editableTitle = RichDocumentPersistence.titlePlainText(from: titleDocument)
            viewModel.startObservingState()
            Task {
                await viewModel.searchRelatedAtoms()
            }
            // Migration: auto-open sidebar if in brainstorm step (not in pane mode), auto-activate polish if in polish step
            if viewModel.state.currentStep == .brainstorm && !isPaneContext {
                sidebarVisible = true
            } else if viewModel.state.currentStep == .polish {
                isPolishModeActive = true
                updatePolishAnalysis()
            }
            // Register context provider for global Cosmo window
            let provider = ContentContextProvider(atom: atom, stateRef: { [viewModel] in viewModel.state }, phaseRef: { [viewModel] in viewModel.displayPhase })
            if !isPaneContext || isPaneActive {
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onChange(of: isPaneActive) { _, isActive in
            if isActive {
                let provider = ContentContextProvider(atom: atom, stateRef: { [viewModel] in viewModel.state }, phaseRef: { [viewModel] in viewModel.displayPhase })
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .task {
            // Initialize engine with persisted conversation (only when legacy AI Collaborator is active)
            guard !cosmoWindowEnabled else { return }
            await writingEngine.initialize(
                contentAtom: atom,
                existingMessages: viewModel.state.conversationHistory,
                existingSummary: viewModel.state.conversationSummary
            )
        }
        .onDisappear {
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
            // If the rich document is stale (debounced serialization hasn't flushed),
            // rebuild it from the authoritative plain text to avoid saving stale content
            if draftDocument.plainText != localDraftContent && !localDraftContent.isEmpty {
                draftDocument = RichDocument.migrateLegacy(localDraftContent)
            }
            // Sync local draft to viewModel state before closing
            viewModel.state.draftContent = localDraftContent
            viewModel.state.richDraftDocument = draftDocument
            // Sync engine conversation to state before saving (only when legacy AI Collaborator is active)
            if !cosmoWindowEnabled {
                viewModel.state.conversationHistory = writingEngine.messages
                viewModel.state.conversationSummary = writingEngine.conversationSummary
            }
            // Extract lessons from user edits to AI-generated draft before closing
            extractLessonsIfEdited()
            viewModel.saveOnClose()
        }
        .onReceive(NotificationCenter.default.publisher(for: .unifiedEngineDraftUpdate)) { notification in
            // Capture AI-generated draft as the baseline for lesson extraction
            if let content = notification.userInfo?["content"] as? String, !content.isEmpty {
                lastAIGeneratedDraft = content
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmoAppWillTerminate)) { _ in
            // Flush View-local state to ViewModel before the ViewModel's termination
            // handler calls writeToAtomSync() — onDisappear doesn't fire on app quit
            viewModel.state.draftContent = localDraftContent
            viewModel.state.richDraftDocument = draftDocument
        }
        .onChange(of: viewModel.state.draftContent) { _, newValue in
            // Sync external draft updates (AI engine, tool executor) back to local state
            if newValue != localDraftContent {
                localDraftContent = newValue
                draftDocument = viewModel.state.richDraftDocument ?? RichDocument.migrateLegacy(newValue)
            }
        }
        .onChange(of: viewModel.state.currentStep) { oldStep, newStep in
            // Clear selection when switching steps
            selectedText = ""
            // Extract lessons when advancing phases (user may have edited AI draft)
            extractLessonsIfEdited()

            guard !cosmoWindowEnabled else { return }
            writingEngine.handlePhaseTransition(from: oldStep, to: newStep, state: viewModel.state)
        }
        .onChange(of: writingEngine.isProcessing) { wasProcessing, isProcessing in
            // Persist conversation to DB directly (bypasses @Published state to avoid
            // render cascade that was crashing the app on the second message).
            // The engine owns the live messages array; we only sync to
            // viewModel.state in onDisappear for full-state persistence.
            guard !cosmoWindowEnabled else { return }
            if wasProcessing && !isProcessing {
                let msgs = writingEngine.messages
                let summary = writingEngine.conversationSummary
                let uuid = atom.uuid
                Task.detached(priority: .utility) {
                    await ContentFocusModeViewModel.persistConversationDirect(
                        atomUUID: uuid, messages: msgs, summary: summary
                    )
                }
            }
        }
        .onKeyPress(.escape) {
            if !cosmoWindowEnabled && showAICollaborator {
                showAICollaborator = false
                return .handled
            }
            onClose()
            return .handled
        }
        .sheet(isPresented: $showSettings) {
            SanctuarySettingsView()
                .frame(width: 720, height: 540)
        }
    }

    /// Toggle AI Collaborator — called from Cmd+J shortcut via keyboardShortcut
    private func toggleAICollaborator() {
        withAnimation(ProMotionSprings.snappy) {
            showAICollaborator.toggle()
        }
    }

    /// Compare the current draft against the last AI-generated draft and extract
    /// writing lessons + store the experience if the user made meaningful edits.
    private func extractLessonsIfEdited() {
        guard let previousDraft = lastAIGeneratedDraft,
              !previousDraft.isEmpty else { return }
        let currentDraft = localDraftContent
        guard !currentDraft.isEmpty, previousDraft != currentDraft else { return }

        // Resolve client UUID and content format from atom metadata
        let contentMeta = atom.metadataValue(as: ContentAtomMetadata.self)
        let clientUUID = contentMeta?.clientProfileUUID.flatMap { UUID(uuidString: $0) }
        let contentFormat = contentMeta?.platform?.rawValue ?? "unknown"

        // Clear baseline so we don't double-extract
        lastAIGeneratedDraft = nil

        Task {
            _ = await LessonExtractor.shared.extractLessons(
                generated: previousDraft,
                edited: currentDraft,
                clientUUID: clientUUID,
                contentFormat: contentFormat
            )
            await ExperienceBufferService.shared.storeExperience(
                generated: previousDraft,
                edited: currentDraft,
                clientUUID: clientUUID,
                contentFormat: contentFormat
            )
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if ContentFocusModeState.stepForPhase(viewModel.displayPhase) != nil {
            // Creation phase — unified editor
            unifiedEditorContent
        } else {
            // Post-creation phase
            PostCreationPhaseView(
                phase: viewModel.displayPhase,
                atom: atom,
                state: $viewModel.state,
                onAdvancePhase: { phase in
                    viewModel.goToPhase(phase)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Unified Editor Content

    private var unifiedEditorContent: some View {
        HStack(spacing: 0) {
            // Center: Editor area
            editorArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right sidebar: Polish sidebar only (hidden in compact pane mode)
            if isPolishModeActive && layoutMode != .compact {
                ContentPolishSidebar(
                    state: $viewModel.state,
                    atom: atom,
                    analysis: polishAnalysis
                )
                .frame(width: layoutMode == .regular ? 260 : 320)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(DS.bg)
        // Keyboard shortcuts for inline AI
        .background(inlineAIKeyboardShortcuts)
    }

    // MARK: - Left Sidebar Overlay

    @ViewBuilder
    private var leftSidebarOverlay: some View {
        // Trigger zone at left edge + sidebar overlay
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                FocusSidebarTrigger(isVisible: $sidebarVisible)
                    .frame(maxHeight: .infinity)
            }
            .overlay(alignment: .topLeading) {
                UniversalFocusSidebar(
                    title: "Context",
                    icon: "sidebar.left",
                    accentColor: CosmoMentionColors.content,
                    isVisible: $sidebarVisible,
                    isLocked: .constant(false)
                ) {
                    ContentOutlineSidebarContent(
                        state: $viewModel.state,
                        atom: atom,
                        writingEngine: cosmoWindowEnabled ? nil : writingEngine
                    )
                }
                .padding(.leading, 16)
                .padding(.top, 80) // Below top bar
            }
    }

    // MARK: - Editor Area

    private var editorArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Centered editor with NSTextView
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Title (editable)
                        CosmoDocumentEditor(
                            document: $titleDocument,
                            fontSize: titleFontSize,
                            placeholder: "Untitled Content",
                            allowSlashCommands: false,
                            allowMentions: true,
                            allowSelectionMenu: false,
                            allowImages: false,
                            singleLine: true,
                            baseFontWeight: .semibold,
                            onPlainTextChange: { plainText in
                                editableTitle = plainText
                            },
                            onStructuredDocumentChange: { document, plainText in
                                titleDocument = document
                                editableTitle = plainText
                                viewModel.updateTitleDocument(document, plainTitle: plainText)
                            }
                        )
                        .frame(minHeight: titleMinHeight)
                        .padding(.bottom, 8)

                        // Description subtitle
                        if !viewModel.state.contentDescription.isEmpty {
                            Text(viewModel.state.contentDescription)
                                .font(DS.body)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(3)
                                .padding(.bottom, 20)
                        }

                        LinearGradient(
                            colors: [DS.accent.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 2)
                        .frame(maxWidth: 430, alignment: .leading)
                        .padding(.bottom, 24)

                        // AI Draft button — visible when draft is empty
                        if localDraftContent.isEmpty {
                            aiDraftButton
                        }

                        // Draft editor — NSTextView for selection tracking
                        CosmoDocumentEditor(
                            document: $draftDocument,
                            fontSize: 17,
                            placeholder: "Start writing...",
                            allowSlashCommands: true,
                            allowMentions: true,
                            allowSelectionMenu: true,
                            allowImages: true,
                            typewriterMode: typewriterMode,
                            polishHighlights: isPolishModeActive ? polishAnalysis : nil,
                            onSelectionChanged: { snapshot in
                                handleSelectionChange(
                                    DraftSelectionInfo(
                                        text: snapshot.text,
                                        range: snapshot.range,
                                        rectInEditor: snapshot.rectInEditor
                                    )
                                )
                            },
                            onContentHeightChange: { measuredHeight in
                                textContentHeight = max(400, measuredHeight)
                            },
                            onAIAction: { action in
                                triggerInlineAction(action)
                            },
                            onCustomPrompt: { prompt in
                                triggerCustomPrompt(prompt)
                            },
                            onDocumentChange: { document, plainText in
                                localDraftContent = plainText
                                draftDocument = document
                                triggerAutoSave()
                                if isPolishModeActive { debouncedPolishUpdate() }
                            }
                        )
                        .frame(minHeight: max(textContentHeight, geo.size.height - 150))
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: DraftEditorFrameKey.self,
                                                value: proxy.frame(in: .named("editorOverlay")))
                            }
                        )
                    }
                    .frame(maxWidth: editorMaxWidth)
                    .padding(.top, editorTopPadding)
                    .padding(.bottom, editorBottomPadding)
                    .padding(.horizontal, editorHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)

                // Inline AI Result Popover
                if case .processing = inlineAIState {
                    inlineResultPopover
                        .position(
                            x: min(max(draftEditorOrigin.x + selectionInfo.rectInEditor.midX, 180), geo.size.width - 180),
                            y: max(draftEditorOrigin.y + selectionInfo.rectInEditor.minY - 80, 60)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                } else if inlineAIState == .showingResult {
                    inlineResultPopover
                        .position(
                            x: min(max(draftEditorOrigin.x + selectionInfo.rectInEditor.midX, 180), geo.size.width - 180),
                            y: max(draftEditorOrigin.y + selectionInfo.rectInEditor.minY - 80, 60)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                }
            }
            .coordinateSpace(name: "editorOverlay")
            .onPreferenceChange(DraftEditorFrameKey.self) { frame in
                draftEditorOrigin = frame.origin
            }
            .onAppear { updateLayoutMode(for: geo.size.width) }
            .onChange(of: geo.size) { _, newSize in
                updateLayoutMode(for: newSize.width)
            }
        }
    }

    // MARK: - AI Draft Button

    @ViewBuilder
    private var aiDraftButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isGeneratingDraft {
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(DS.accent)
                    Text("Opus is writing your draft...")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.vertical, 24)
            } else {
                Button(action: generateAIDraft) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(DS.caption)
                        Text("Generate Draft with Opus")
                            .font(DS.buttonText)
                    }
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(DS.accentSoft)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.radiusSmall)
                                    .stroke(DS.accent.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if let error = draftGenerationError {
                Text(error)
                    .font(DS.footnote)
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
    }

    private func generateAIDraft() {
        isGeneratingDraft = true
        draftGenerationError = nil
        Task {
            if let engine = cosmoWindowEnabled ? nil : writingEngine {
                await engine.generateDraft()
                await MainActor.run {
                    isGeneratingDraft = false
                    if let error = engine.error {
                        draftGenerationError = "Draft generation failed: \(error)"
                    }
                }
            } else {
                await MainActor.run {
                    draftGenerationError = "Use Cosmo window to generate drafts"
                    isGeneratingDraft = false
                }
            }
        }
    }

    // MARK: - Floating Polish Button

    @ViewBuilder
    private var floatingPolishButtonOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()

                if ContentFocusModeState.stepForPhase(viewModel.displayPhase) != nil {
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            isPolishModeActive.toggle()
                            if isPolishModeActive { updatePolishAnalysis() }
                        }
                    } label: {
                        polishToggleLabel
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var polishToggleLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(DS.buttonText)
            Text("Polish")
                .font(DS.caption)
        }
        .foregroundStyle(isPolishModeActive ? DS.green : DS.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(isPolishModeActive ? DS.green.opacity(0.15) : DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(isPolishModeActive ? DS.green.opacity(0.3) : DS.border, lineWidth: 1)
        )
    }

    // MARK: - Polish Analysis

    private func updatePolishAnalysis() {
        let text = localDraftContent
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            polishAnalysis = nil
            return
        }
        polishAnalysis = WritingAnalyzer.shared.analyze(text: text)
    }

    private func debouncedPolishUpdate() {
        polishDebounceTask?.cancel()
        polishDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            updatePolishAnalysis()
        }
    }

    // MARK: - Inline AI

    @ViewBuilder
    private var inlineAIKeyboardShortcuts: some View {
        Group {
            Button(action: { triggerInlineAction(.expand) }) { EmptyView() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button(action: { triggerInlineAction(.condense) }) { EmptyView() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button(action: { triggerInlineAction(.rephrase) }) { EmptyView() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(action: { triggerInlineAction(.continueWriting) }) { EmptyView() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    @ViewBuilder
    private var inlineResultPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(DS.accent)
                    .font(DS.subheadline)
                Text("AI Suggestion")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.text)
                Spacer()
                Button(action: { dismissInlineAI() }) {
                    Image(systemName: "xmark")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(DS.border).frame(height: 1)

            // Body
            if inlineAssistant.isProcessing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(DS.accent)
                    Text("Generating...")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if let result = inlineAssistant.currentResult {
                inlineResultBody(result)
            } else if let error = inlineAssistant.error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(DS.title3)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(DS.footnote)
                        .foregroundStyle(DS.textSecondary)
                    Button(action: { dismissInlineAI() }) {
                        Text("Dismiss")
                            .font(DS.caption)
                            .foregroundStyle(DS.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .stroke(DS.borderActive, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        )
    }

    @ViewBuilder
    private func inlineResultBody(_ result: AIWritingResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Action tag
            HStack(spacing: 4) {
                Image(systemName: result.action.iconName)
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent)
                Text(result.action.displayName)
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(DS.accent.opacity(0.15)))

            // Diff preview
            if result.action == .continueWriting {
                let continuation = String(result.suggestedText.dropFirst(result.originalText.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ScrollView {
                    Text(continuation)
                        .font(DS.footnote)
                        .foregroundStyle(.green.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(DS.borderSubtle))
            } else {
                let diffWords = inlineAssistant.computeWordDiff(
                    original: result.originalText,
                    suggested: result.suggestedText
                )
                ScrollView {
                    InlineDiffText(words: diffWords)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(DS.borderSubtle))
            }

            // Accept / Reject
            HStack(spacing: 8) {
                Button(action: { acceptInlineResult(result) }) {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark").font(DS.caption2)
                        Text("Accept").font(DS.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DS.accent))
                }
                .buttonStyle(.plain)

                Button(action: { dismissInlineAI() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark").font(DS.caption2)
                        Text("Reject").font(DS.caption)
                    }
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DS.border))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    // MARK: - Inline AI Actions

    private func handleSelectionChange(_ info: DraftSelectionInfo) {
        selectionInfo = info
        selectedText = info.text
    }

    private func triggerInlineAction(_ action: AIWritingAction) {
        let text = selectionInfo.text
        guard !text.isEmpty else { return }

        withAnimation(ProMotionSprings.snappy) {
            inlineAIState = .processing(action)
        }

        if action == .rephrase { selectedRephraseIndex = 0 }

        let engineAction: UnifiedWritingEngine.InlineEditAction?
        switch action {
        case .expand: engineAction = .expand
        case .condense: engineAction = .condense
        case .rephrase: engineAction = .rephrase
        case .continueWriting: engineAction = nil
        }

        Task {
            let engine = cosmoWindowEnabled ? nil : writingEngine

            if let engineAction = engineAction, let engine = engine {
                let result = await engine.inlineEdit(
                    action: engineAction,
                    selectedText: text,
                    context: surroundingContext() ?? text
                )
                if let result = result {
                    await MainActor.run {
                        inlineAssistant.currentResult = AIWritingResult(
                            originalText: text,
                            suggestedText: result,
                            action: action,
                            variants: nil
                        )
                    }
                }
            } else if let engineAction = engineAction {
                let contextText = surroundingContext() ?? text
                let result: AIWritingResult?
                switch engineAction {
                case .expand:
                    result = await inlineAssistant.expand(text: text, context: contextText)
                case .condense:
                    result = await inlineAssistant.condense(text: text, context: contextText)
                case .rephrase:
                    result = await inlineAssistant.rephrase(text: text, context: contextText)
                }
                if let result = result {
                    await MainActor.run { inlineAssistant.currentResult = result }
                }
            } else {
                let outlineTexts = viewModel.state.outline.filter { !$0.isCompleted }.map(\.text)
                _ = await inlineAssistant.continueWriting(
                    text: text,
                    outline: outlineTexts,
                    coreIdea: viewModel.state.contentDescription
                )
            }

            await MainActor.run {
                withAnimation(ProMotionSprings.snappy) { inlineAIState = .showingResult }
            }
        }
    }

    private func triggerCustomPrompt(_ prompt: String) {
        let text = selectionInfo.text
        guard !text.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) { inlineAIState = .processing(.rephrase) }
        Task {
            _ = await inlineAssistant.expand(text: text, context: "Custom instruction: \(prompt)")
            await MainActor.run {
                withAnimation(ProMotionSprings.snappy) { inlineAIState = .showingResult }
            }
        }
    }

    private func surroundingContext() -> String? {
        let draft = localDraftContent
        guard draft.count > 200 else { return draft }
        let nsString = draft as NSString
        let selRange = selectionInfo.range
        let contextStart = max(0, selRange.location - 250)
        let contextEnd = min(nsString.length, selRange.location + selRange.length + 250)
        let contextRange = NSRange(location: contextStart, length: contextEnd - contextStart)
        return nsString.substring(with: contextRange)
    }

    private func acceptInlineResult(_ result: AIWritingResult) {
        let replacement: String
        if result.action == .rephrase, let variants = result.variants, selectedRephraseIndex < variants.count {
            replacement = variants[selectedRephraseIndex]
        } else {
            replacement = result.suggestedText
        }

        if result.action == .continueWriting {
            localDraftContent = replacement
            draftDocument = RichDocument.migrateLegacy(replacement)
        } else {
            draftDocument = draftDocumentByReplacingSelection(with: replacement, originalText: result.originalText)
            localDraftContent = draftDocument.plainText
        }
        viewModel.state.richDraftDocument = draftDocument

        triggerAutoSave()
        dismissInlineAI()
    }

    private func draftDocumentByReplacingSelection(with replacement: String, originalText: String) -> RichDocument {
        let currentPlainText = localDraftContent as NSString
        var replacementRange = selectionInfo.range

        if replacementRange.location == NSNotFound || replacementRange.location + replacementRange.length > currentPlainText.length {
            replacementRange = currentPlainText.range(of: originalText)
        }

        guard replacementRange.location != NSNotFound else {
            return RichDocument.migrateLegacy(localDraftContent.replacingOccurrences(of: originalText, with: replacement))
        }

        let attributed = NSMutableAttributedString(
            attributedString: RichDocumentSerializer.attributedString(from: draftDocument, fontSize: 16, darkMode: false)
        )
        let attributedPlainText = attributed.string as NSString

        guard replacementRange.location + replacementRange.length <= attributedPlainText.length else {
            return RichDocument.migrateLegacy(currentPlainText.replacingCharacters(in: replacementRange, with: replacement))
        }

        attributed.replaceCharacters(
            in: replacementRange,
            with: NSAttributedString(
                string: replacement,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16),
                    .foregroundColor: NSColor(CosmoColors.textPrimary)
                ]
            )
        )
        return RichDocumentSerializer.document(from: attributed)
    }

    private func dismissInlineAI() {
        withAnimation(ProMotionSprings.snappy) {
            inlineAIState = .idle
            inlineAssistant.currentResult = nil
            inlineAssistant.error = nil
        }
    }

    // MARK: - Auto-save

    private func triggerAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(ProMotionSprings.snappy) { saveState = .saving }
                    // Sync local draft to viewModel state only at save time (avoids per-keystroke @Published churn)
                    viewModel.state.draftContent = localDraftContent
                    viewModel.state.richDraftDocument = draftDocument
                    viewModel.state.lastModified = Date()
                    // Write directly to DB — skip the notification + ViewModel debounce (was adding 1.5s extra delay)
                    viewModel.writeToAtom()
                    withAnimation(ProMotionSprings.snappy) { saveState = .saved }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(ProMotionSprings.gentle) { saveState = .idle }
                    }
                }
            } catch {}
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            // Main sidebar toggle (standalone only)
            if !isPaneContext {
                Button {
                    withAnimation(ProMotionSprings.sidebar) {
                        isSidebarHidden.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSidebarHidden ? DS.textMuted : DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.border, in: Circle())
                }
                .buttonStyle(.plain)
                .help(isSidebarHidden ? "Show sidebar (⌘\\)" : "Hide sidebar (⌘\\)")
            }

            // Back button (hidden in pane mode — X button handles close)
            if !isPaneContext {
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(DS.buttonText)
                        Text("Back")
                            .font(DS.callout)
                    }
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DS.border, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Editable title
            Text(editableTitle.isEmpty ? "Content title..." : editableTitle)
                .font(DS.headline)
                .foregroundStyle(editableTitle.isEmpty ? DS.textMuted : DS.text)
                .lineLimit(1)
                .frame(maxWidth: layoutMode == .compact ? 180 : 300, alignment: .leading)

            // Type badge (hidden in compact mode)
            if layoutMode != .compact {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(DS.caption2)
                    Text("Content")
                        .font(DS.caption2)
                        .tracking(0.5)
                }
                .foregroundStyle(DS.entityContent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DS.entityContent.opacity(0.12), in: Capsule())
            }

            Spacer()

            // Word + character count pill — selection-aware
            if !localDraftContent.isEmpty {
                let textToCount = selectedText.isEmpty ? localDraftContent : selectedText
                let words = textToCount.split(whereSeparator: \.isWhitespace).count
                let chars = textToCount.count
                Text("\(words) words · \(chars) chars")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.border, in: Capsule())
            }

            // Focus mode sidebar toggle
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    sidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(DS.callout)
                    .foregroundStyle(sidebarVisible ? DS.entityContent : DS.textSecondary)
                    .padding(8)
                    .background(
                        sidebarVisible ? DS.entityContent.opacity(0.15) : DS.border,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, layoutMode == .compact ? 12 : 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    DS.bg.opacity(0.95),
                    DS.bg.opacity(0.8),
                    DS.bg.opacity(0.4),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: layoutMode == .compact ? 80 : 120)
            .allowsHitTesting(false)
        , alignment: .top)
    }

}

// MARK: - Content Focus Mode ViewModel

@MainActor
class ContentFocusModeViewModel: ObservableObject {
    // MARK: - Published State

    @Published var state: ContentFocusModeState
    @Published var xpAwarded: Int? = nil  // Set briefly to show XP animation
    @Published var displayPhase: ContentPhase = .ideation  // Currently displayed phase (UI-driven)

    // MARK: - Properties

    private var atom: Atom
    private var autoSaveTask: Task<Void, Never>?
    private let autoSaveDelay: TimeInterval = 1.5
    private var saveNotificationCancellable: AnyCancellable?
    private var toolNotificationCancellables: Set<AnyCancellable> = []
    private(set) var isInitialLoad = true
    private var writeSequence: Int = 0
    private var isClosed = false

    // MARK: - Initialization

    private var terminationCancellable: AnyCancellable?

    init(atom: Atom) {
        self.atom = atom
        self.state = ContentFocusModeState(atomUUID: atom.uuid)

        // Flush pending saves synchronously when the app is about to terminate
        terminationCancellable = NotificationCenter.default
            .publisher(for: .cosmoAppWillTerminate)
            .sink { [weak self] _ in
                guard let self, !self.isClosed else { return }
                self.writeSequence += 1  // Invalidate in-flight async writes
                self.writeToAtomSync()
            }
    }

    private var phaseChangeCancellable: AnyCancellable?

    deinit {
        autoSaveTask?.cancel()
        saveNotificationCancellable?.cancel()
        phaseChangeCancellable?.cancel()
        terminationCancellable?.cancel()
        toolNotificationCancellables.removeAll()
    }

    // MARK: - State Observation

    /// Listen for save notifications from child views.
    /// Every child view calls state.save() which posts .contentFocusStateSaved.
    /// We debounce and write to the atom in the database.
    func startObservingState() {
        let atomUUID = atom.uuid
        saveNotificationCancellable = NotificationCenter.default
            .publisher(for: .contentFocusStateSaved)
            .filter { notification in
                notification.userInfo?["atomUUID"] as? String == atomUUID
            }
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.isInitialLoad else {
                    print("💾 Content focus: debounced save skipped (isInitialLoad=\(self?.isInitialLoad ?? true))")
                    return
                }
                print("💾 Content focus: debounced save firing")
                self.writeToAtom()
            }

        // Subscribe to unified engine tool notifications so AI tool calls
        // (outline, hooks, description, draft) actually update the UI state.
        toolNotificationCancellables.removeAll()

        NotificationCenter.default.publisher(for: .unifiedEngineOutlineUpdate)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, !self.isClosed,
                      let items = notification.userInfo?["items"] as? [OutlineItem] else { return }
                self.state.outline = items
                self.state.isAISuggestedOutline = true
                self.state.lastModified = Date()
                self.writeToAtom()
            }
            .store(in: &toolNotificationCancellables)

        NotificationCenter.default.publisher(for: .unifiedEngineHooksUpdate)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, !self.isClosed,
                      let hooks = notification.userInfo?["hooks"] as? [String] else { return }
                self.state.hooks = hooks
                self.state.lastModified = Date()
                self.writeToAtom()
            }
            .store(in: &toolNotificationCancellables)

        NotificationCenter.default.publisher(for: .unifiedEngineDescriptionUpdate)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, !self.isClosed,
                      let description = notification.userInfo?["description"] as? String else { return }
                self.state.contentDescription = description
                self.state.lastModified = Date()
                self.writeToAtom()
            }
            .store(in: &toolNotificationCancellables)

        NotificationCenter.default.publisher(for: .unifiedEngineDraftUpdate)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, !self.isClosed,
                      let content = notification.userInfo?["content"] as? String else { return }
                // Convert carousel/thread JSON to readable slide format for display.
                // Raw JSON stays in atom.body (written by handleWriteDraft); draftContent
                // gets the human-readable version for the editor and read_draft tool.
                self.state.draftContent = AgentToolExecutor.renderDraftForDisplay(content)
                self.state.richDraftDocument = RichDocument.migrateLegacy(self.state.draftContent)
                self.state.lastModified = Date()
                self.writeToAtom()
            }
            .store(in: &toolNotificationCancellables)

        NotificationCenter.default.publisher(for: .unifiedEngineSectionEdit)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, !self.isClosed,
                      let newContent = notification.userInfo?["newContent"] as? String else { return }
                let sectionId = notification.userInfo?["sectionIdentifier"] as? String ?? ""
                self.state.pushAIUndo(
                    previousContent: self.state.draftContent,
                    sectionIdentifier: sectionId,
                    description: "AI edit: \(sectionId)"
                )
                self.state.draftContent = newContent
                self.state.richDraftDocument = RichDocument.migrateLegacy(newContent)
                self.state.lastModified = Date()
                self.writeToAtom()
            }
            .store(in: &toolNotificationCancellables)

        // Observe phase changes from PostCreationPhaseView actions
        phaseChangeCancellable = NotificationCenter.default
            .publisher(for: .contentPhaseChanged)
            .filter { $0.userInfo?["atomUUID"] as? String == atomUUID }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.isClosed else { return }
                Task {
                    if let freshAtom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                        self.atom = freshAtom
                        self.objectWillChange.send()
                    }
                }
            }
    }

    // MARK: - State Management

    /// Load state directly from the atom's body + metadata fields.
    func loadState() {
        isInitialLoad = true
        print("📖 Content focus: loadState for atom \(atom.uuid) (id: \(atom.id ?? -1))")

        // Read state from atom metadata (the single source of truth)
        if let savedState = ContentFocusModeState.from(atom: atom) {
            print("📖 Content focus: restored state (step: \(savedState.currentStep.rawValue), desc: \(savedState.contentDescription.prefix(30)), outline: \(savedState.outline.count) items)")
            state = savedState
        } else {
            // No saved focus state yet — initialize from atom fields
            if let body = atom.body, !body.isEmpty {
                state.draftContent = body
                state.richDraftDocument = RichDocument.migrateLegacy(body)
            }
            if let metadata = atom.metadata,
               let data = metadata.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Migrate legacy coreIdea to contentDescription
                if let desc = dict["contentDescription"] as? String {
                    state.contentDescription = desc
                } else if let coreIdea = dict["coreIdea"] as? String {
                    state.contentDescription = coreIdea
                }
                // Load hooks — check both "hooks" and "inheritedHooks" keys
                if let hooks = dict["hooks"] as? [String] {
                    state.hooks = hooks
                } else if let hooks = dict["inheritedHooks"] as? [String] {
                    state.hooks = hooks
                }
                // Load outline from metadata
                if let outlineData = dict["outline"],
                   let outlineJSON = try? JSONSerialization.data(withJSONObject: outlineData),
                   let items = try? JSONDecoder().decode([OutlineItem].self, from: outlineJSON) {
                    state.outline = items
                }
            }
        }

        // Initialize displayPhase from atom metadata (the persisted pipeline phase)
        displayPhase = currentPhase

        // Mark initial load complete after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isInitialLoad = false
        }
    }

    /// Write current state directly to the atom in the database.
    /// This is the ONLY save path — no UserDefaults.
    /// Uses a write sequence number so stale writes (from debounced handlers
    /// that fire after a step transition) are discarded.
    func writeToAtom() {
        state.lastModified = Date()
        let stateCopy = state
        let atomUUID = atom.uuid
        writeSequence += 1
        let mySequence = writeSequence

        print("💾 Content focus: writing to atom \(atomUUID) (step: \(stateCopy.currentStep.rawValue), seq: \(mySequence), desc: \(stateCopy.contentDescription.prefix(30)), outline: \(stateCopy.outline.count) items)")

        Task {
            // Check if a newer write has been queued — if so, skip this one
            guard mySequence == self.writeSequence else {
                print("💾 Content focus: skipping stale write seq \(mySequence) (latest: \(self.writeSequence))")
                return
            }

            do {
                try await CosmoDatabase.shared.asyncWrite { db in
                    // Read existing metadata to preserve non-focus-state keys
                    var existingMetadata: String? = nil
                    if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]),
                       let existing: String = row["metadata"] {
                        existingMetadata = existing
                    }

                    let fields = stateCopy.toAtomFields(existingMetadata: existingMetadata)

                    try db.execute(
                        sql: """
                        UPDATE atoms
                        SET body = ?,
                            metadata = COALESCE(?, metadata),
                            updated_at = ?,
                            _local_version = _local_version + 1,
                            _local_pending = 1
                        WHERE uuid = ?
                        """,
                        arguments: [
                            fields.body,
                            fields.metadata,
                            ISO8601DateFormatter().string(from: Date()),
                            atomUUID
                        ]
                    )
                    print("💾 Content focus: wrote to atom \(atomUUID) seq \(mySequence), rows affected: \(db.changesCount)")
                }
                // Sync: queue for Supabase push so content drafts don't only live locally
                if let updatedAtom = try? await CosmoDatabase.shared.asyncRead({ db in
                    try Atom.filter(Column("uuid") == atomUUID).fetchOne(db)
                }) {
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom)
                }
            } catch {
                print("❌ Content focus: failed to write to atom: \(error)")
            }
        }
    }

    /// Synchronous write — blocks the calling thread until the DB write completes.
    /// Use ONLY in save-on-close paths where the app may terminate before an async write finishes.
    func writeToAtomSync() {
        state.lastModified = Date()
        let stateCopy = state
        let atomUUID = atom.uuid

        print("💾 Content focus: sync writing to atom \(atomUUID)")

        do {
            try CosmoDatabase.shared.write { db in
                var existingMetadata: String? = nil
                if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]),
                   let existing: String = row["metadata"] {
                    existingMetadata = existing
                }

                let fields = stateCopy.toAtomFields(existingMetadata: existingMetadata)

                try db.execute(
                    sql: """
                    UPDATE atoms
                    SET body = ?,
                        metadata = COALESCE(?, metadata),
                        updated_at = ?,
                        _local_version = _local_version + 1,
                        _local_pending = 1
                    WHERE uuid = ?
                    """,
                    arguments: [
                        fields.body,
                        fields.metadata,
                        ISO8601DateFormatter().string(from: Date()),
                        atomUUID
                    ]
                )
                print("💾 Content focus: sync wrote to atom \(atomUUID), rows affected: \(db.changesCount)")
            }
            // Sync: queue for Supabase push
            Task {
                if let updatedAtom = try? await CosmoDatabase.shared.asyncRead({ db in
                    try Atom.filter(Column("uuid") == atomUUID).fetchOne(db)
                }) {
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom)
                }
            }
        } catch {
            print("❌ Content focus: sync write failed: \(error)")
        }
    }

    /// Called when view disappears — force immediate synchronous save
    func saveOnClose() {
        print("💾 Content focus: saveOnClose for atom \(atom.uuid)")
        isClosed = true
        autoSaveTask?.cancel()
        // Cancel debounced notification subscription to prevent stale writes after close
        saveNotificationCancellable?.cancel()
        saveNotificationCancellable = nil
        phaseChangeCancellable?.cancel()
        phaseChangeCancellable = nil
        toolNotificationCancellables.removeAll()
        writeSequence += 1  // Invalidate any in-flight async writes from writeToAtom()
        writeToAtomSync()
    }

    /// Persist conversation messages directly to the atom's metadata in GRDB
    /// without touching any @Published state. Called from Task.detached in the
    /// onChange(of: isProcessing) handler to avoid SwiftUI render cascades.
    static func persistConversationDirect(
        atomUUID: String,
        messages: [WritingMessage],
        summary: String
    ) async {
        let recentMessages = Array(messages.suffix(30))

        do {
            try await CosmoDatabase.shared.asyncWrite { db in
                guard let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]),
                      let existingStr: String = row["metadata"],
                      let existingData = existingStr.data(using: .utf8),
                      var dict = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
                    return
                }

                // Encode conversation history
                if !recentMessages.isEmpty,
                   let messagesData = try? JSONEncoder().encode(recentMessages),
                   let messagesArray = try? JSONSerialization.jsonObject(with: messagesData) {
                    dict["conversationHistory"] = messagesArray
                } else {
                    dict["conversationHistory"] = nil
                }

                dict["conversationSummary"] = summary.isEmpty ? nil : summary

                // Write merged metadata back
                if let metadataData = try? JSONSerialization.data(withJSONObject: dict),
                   let metadataStr = String(data: metadataData, encoding: .utf8) {
                    try db.execute(
                        sql: """
                        UPDATE atoms
                        SET metadata = ?,
                            updated_at = ?,
                            _local_version = _local_version + 1
                        WHERE uuid = ?
                        """,
                        arguments: [
                            metadataStr,
                            ISO8601DateFormatter().string(from: Date()),
                            atomUUID
                        ]
                    )
                }
            }
            print("💾 Content focus: persisted conversation (\(recentMessages.count) msgs) for \(atomUUID)")
            // Sync: queue conversation history for Supabase push
            if let updatedAtom = try? await CosmoDatabase.shared.asyncRead({ db in
                try Atom.filter(Column("uuid") == atomUUID).fetchOne(db)
            }) {
                await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom)
            }
        } catch {
            print("❌ Content focus: persistConversationDirect failed: \(error)")
        }
    }

    // MARK: - Phase Accessors

    var currentPhase: ContentPhase {
        // Read from atom metadata, default to mapping from ContentStep
        if let metadata = atom.metadataValue(as: ContentAtomMetadata.self) {
            return metadata.phase
        }
        return stepToPhase(state.currentStep)
    }

    var phaseEnteredAt: Date? {
        if let metadata = atom.metadataValue(as: ContentAtomMetadata.self),
           let dateStr = metadata.phaseEnteredAt {
            return ISO8601DateFormatter().date(from: dateStr)
        }
        return nil
    }

    func goToPhase(_ phase: ContentPhase) {
        let currentIdx = ContentPhase.allCases.firstIndex(of: displayPhase) ?? 0
        let targetIdx = ContentPhase.allCases.firstIndex(of: phase) ?? 0

        if targetIdx > currentIdx {
            // Moving forward — call advancePhase() to award XP
            advanceToPhase(phase)
        } else {
            // Moving backward — update display phase and step if applicable
            withAnimation(ProMotionSprings.focusTransition) {
                displayPhase = phase
            }
            if let step = ContentFocusModeState.stepForPhase(phase) {
                goToStep(step)
            }
        }
    }

    /// Advance forward through phases, calling ContentPipelineService for each step.
    private func advanceToPhase(_ targetPhase: ContentPhase) {
        // Flush current focus state to DB before pipeline advances
        // (ensures hooks/description survive the phase transition write)
        writeToAtom()

        Task {
            let pipelineService = ContentPipelineService()
            var currentIdx = ContentPhase.allCases.firstIndex(of: displayPhase) ?? 0
            let targetIdx = ContentPhase.allCases.firstIndex(of: targetPhase) ?? 0

            while currentIdx < targetIdx {
                do {
                    _ = try await pipelineService.advancePhase(contentUUID: atom.uuid)
                    let xp = ContentPhase.allCases[currentIdx + 1].completionXP
                    if xp > 0 {
                        xpAwarded = xp
                        // Clear after animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            self?.xpAwarded = nil
                        }
                    }
                    currentIdx += 1
                    print("Content focus: advanced to \(ContentPhase.allCases[currentIdx].displayName), XP: \(xp)")

                    // Refresh atom from DB to get updated metadata
                    if let freshAtom = try? await AtomRepository.shared.fetch(uuid: atom.uuid) {
                        atom = freshAtom
                    }
                } catch {
                    print("Content focus: advancePhase failed: \(error)")
                    break
                }
            }

            // Update displayPhase to the target
            withAnimation(ProMotionSprings.focusTransition) {
                displayPhase = targetPhase
            }

            // Update the step UI to match
            if let step = ContentFocusModeState.stepForPhase(targetPhase) {
                goToStep(step)
            } else {
                // Post-creation phase — just notify the UI to refresh
                objectWillChange.send()
            }
        }
    }

    private func stepToPhase(_ step: ContentStep) -> ContentPhase {
        switch step {
        case .brainstorm: return .ideation
        case .draft: return .draft
        case .polish: return .polish
        }
    }

    // MARK: - Navigation

    func goToStep(_ step: ContentStep) {
        print("📝 Content focus: goToStep → \(step.rawValue)")

        // Cancel any pending debounced writes from the PREVIOUS step
        // to prevent stale state from overwriting the new step
        saveNotificationCancellable?.cancel()
        saveNotificationCancellable = nil

        withAnimation(ProMotionSprings.focusTransition) {
            state.currentStep = step
        }
        writeToAtom()

        // Re-subscribe to save notifications for the new step
        startObservingState()
    }

    // MARK: - Title Update

    private var titleUpdateTask: Task<Void, Never>?

    func updateTitle(_ newTitle: String) {
        updateTitleDocument(RichDocument.migrateLegacy(newTitle), plainTitle: newTitle)
    }

    func updateTitleDocument(_ document: RichDocument, plainTitle: String) {
        titleUpdateTask?.cancel()
        titleUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s debounce
            guard !Task.isCancelled else { return }
            let titleDocument = RichDocumentPersistence.normalizedTitleDocument(
                document.isEmpty ? RichDocument.migrateLegacy(plainTitle) : document
            )
            let trimmed = RichDocumentPersistence.titlePlainText(from: titleDocument)
            let uuid = atom.uuid
            do {
                try await CosmoDatabase.shared.asyncWrite { db in
                    var existingMetadata: String?
                    if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid]) {
                        existingMetadata = row["metadata"]
                    }
                    let fields = RichDocumentPersistence.writeAtomDocuments(
                        existingMetadata: existingMetadata,
                        titleDocument: titleDocument
                    )
                    try db.execute(
                        sql: """
                        UPDATE atoms SET title = ?, metadata = ?, updated_at = ?, _local_version = _local_version + 1
                        WHERE uuid = ?
                        """,
                        arguments: [RichDocumentPersistence.nilIfEmpty(trimmed), fields.metadata, ISO8601DateFormatter().string(from: Date()), uuid]
                    )
                }
            } catch {
                print("❌ Content focus: title update failed: \(error)")
            }
        }
    }

    // MARK: - Related Atoms Search

    func searchRelatedAtoms() async {
        let query = [atom.title ?? "", state.contentDescription]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !query.isEmpty else { return }

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 10
            )

            // Don't update state if the view has been closed
            guard !isClosed else { return }

            // Convert to RelatedAtomRef, excluding the current atom
            let refs = results
                .filter { $0.entityUUID != atom.uuid }
                .prefix(8)
                .map { result in
                    RelatedAtomRef(
                        atomUUID: result.entityUUID ?? "",
                        title: result.title,
                        type: AtomType(rawValue: result.entityType.rawValue) ?? .idea,
                        relevanceScore: result.combinedScore,
                        preview: result.preview
                    )
                }

            state.relatedAtoms = Array(refs)
            // Use notification-based save instead of direct writeToAtom()
            // to avoid racing with step transitions
            state.save()
        } catch {
            print("❌ Content focus: related atoms search failed: \(error)")
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ContentFocusModeView_Previews: PreviewProvider {
    static var previews: some View {
        ContentFocusModeView(
            atom: Atom.new(
                type: .content,
                title: "How to Build a Second Brain",
                body: ""
            ),
            onClose: { print("Close") }
        )
        .frame(width: 1200, height: 800)
    }
}
#endif

// MARK: - Cosmo Context Provider

@MainActor
class ContentContextProvider: CosmoContextProvider {
    private let atom: Atom
    private let stateRef: () -> ContentFocusModeState
    private let phaseRef: () -> ContentPhase

    init(atom: Atom, stateRef: @escaping () -> ContentFocusModeState, phaseRef: @escaping () -> ContentPhase) {
        self.atom = atom
        self.stateRef = stateRef
        self.phaseRef = phaseRef
    }

    var contextType: CosmoContextType { .contentFocusMode }

    var contextSummary: String {
        let phase = phaseRef()
        return "Content: \(atom.title ?? "Untitled") — \(phase.displayName)"
    }

    var contextData: CosmoContextData {
        let state = stateRef()
        let phase = phaseRef()
        var viewData: [String: String] = [
            "phase": phase.displayName,
            "step": state.currentStep.rawValue,
            "outlineItems": "\(state.outline.count)"
        ]

        if !state.contentDescription.isEmpty {
            viewData["description"] = String(state.contentDescription.prefix(300))
        }
        if !state.hooks.isEmpty {
            viewData["hooks"] = state.hooks.prefix(3).joined(separator: " | ")
        }
        if !state.draftContent.isEmpty {
            viewData["draftWordCount"] = "\(state.draftContent.split(separator: " ").count)"
            viewData["draftExcerpt"] = String(state.draftContent.prefix(500))
        }

        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "content",
            currentAtomTitle: atom.title,
            viewSpecificData: viewData
        )
    }

    var availableActions: [CosmoWindowAction] { [] }
}

// MARK: - Preference Key for draft editor position tracking

private struct DraftEditorFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
