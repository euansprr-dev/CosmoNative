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
    @StateObject private var writingEngine = UnifiedWritingEngine()

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
    @State private var showCustomPrompt = false
    @State private var customPromptText = ""
    @StateObject private var inlineAssistant = AIWritingAssistant()
    @State private var textContentHeight: CGFloat = 400
    @State private var editorAreaFrame: CGRect = .zero
    @State private var selectedRephraseIndex: Int = 0

    // Auto-save state
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var saveState: DraftSaveState = .idle
    private let autoSaveDelay: TimeInterval = 1.5

    // AI Draft generation state
    @State private var isGeneratingDraft = false
    @State private var draftGenerationError: String?

    // Left sidebar visibility
    @State private var sidebarVisible: Bool = false

    enum DraftSaveState { case idle, saving, saved }

    // Feature flag: when true, the embedded AI Collaborator is hidden (replaced by global Cosmo window)
    @AppStorage("cosmoWindowEnabled") private var cosmoWindowEnabled = true

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneActive) private var isPaneActive

    private let editorMaxWidth: CGFloat = 780

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
            // Background — zen dark with subtle radial glow
            Color(red: 0.031, green: 0.031, blue: 0.051)
                .ignoresSafeArea()
                .overlay(
                    RadialGradient(
                        colors: [DS.accent.opacity(0.03), .clear],
                        center: .center,
                        startRadius: 100,
                        endRadius: 600
                    )
                    .ignoresSafeArea()
                )

            // Main content
            VStack(spacing: 0) {
                // Top bar spacer
                Spacer().frame(height: 72)

                // Unified editor or post-creation phase
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom bar
                unifiedBottomBar
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

            // Settings cog overlay
            VStack {
                HStack {
                    Spacer()
                    if isPaneContext {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.textMuted)
                                .frame(width: 28, height: 28)
                                .background(DS.border, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(DS.textMuted)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }
                Spacer()
            }

            // XP award animation overlay
            if let xp = viewModel.xpAwarded {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("+\(xp) XP")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(DS.green)
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
            viewModel.loadState()
            viewModel.startObservingState()
            Task {
                await viewModel.searchRelatedAtoms()
            }
            // Migration: auto-open sidebar if in brainstorm step, auto-activate polish if in polish step
            if viewModel.state.currentStep == .brainstorm {
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
        let currentDraft = viewModel.state.draftContent
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
            // Post-creation phase — unchanged
            HStack(spacing: 0) {
                PostCreationPhaseView(
                    phase: viewModel.displayPhase,
                    atom: atom,
                    state: $viewModel.state,
                    onAdvancePhase: { phase in
                        viewModel.goToPhase(phase)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ContentContextPanel(
                    atom: atom,
                    state: $viewModel.state,
                    isVisible: viewModel.state.isContextPanelVisible
                )
            }
        }
    }

    // MARK: - Unified Editor Content

    private var unifiedEditorContent: some View {
        HStack(spacing: 0) {
            // Center: Editor area
            editorArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right sidebar: Context panel OR Polish sidebar
            if isPolishModeActive {
                ContentPolishSidebar(
                    state: $viewModel.state,
                    atom: atom,
                    analysis: polishAnalysis
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ContentContextPanel(
                    atom: atom,
                    state: $viewModel.state,
                    isVisible: viewModel.state.isContextPanelVisible
                )
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
                    title: "Outline",
                    icon: "list.bullet.indent",
                    accentColor: CosmoMentionColors.content,
                    isVisible: $sidebarVisible
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
                        TextField("Untitled Content", text: $editableTitle)
                            .textFieldStyle(.plain)
                            .font(DS.pageTitle)
                            .foregroundColor(DS.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)

                        // Description subtitle
                        if !viewModel.state.contentDescription.isEmpty {
                            Text(viewModel.state.contentDescription)
                                .font(DS.body)
                                .foregroundColor(DS.textSecondary)
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
                        if viewModel.state.draftContent.isEmpty {
                            aiDraftButton
                        }

                        // Draft editor — NSTextView for selection tracking
                        DraftEditorTextView(
                            text: $viewModel.state.draftContent,
                            contentHeight: $textContentHeight,
                            polishHighlights: isPolishModeActive ? polishAnalysis : nil,
                            onSelectionChanged: { info in
                                handleSelectionChange(info)
                            },
                            onTextChanged: {
                                triggerAutoSave()
                                if isPolishModeActive { updatePolishAnalysis() }
                            }
                        )
                        .frame(height: max(400, textContentHeight))
                    }
                    .frame(maxWidth: editorMaxWidth)
                    .padding(.vertical, 48)
                    .padding(.horizontal, 48)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)

                // Inline AI Action Bar — floats above selection
                if inlineAIState == .showingBar && !selectionInfo.text.isEmpty {
                    inlineActionBar
                        .position(
                            x: min(max(selectionInfo.rectInEditor.midX, 120), geo.size.width - 120),
                            y: max(selectionInfo.rectInEditor.minY - 50, 20)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }

                // Inline AI Result Popover
                if case .processing = inlineAIState {
                    inlineResultPopover
                        .position(
                            x: min(max(selectionInfo.rectInEditor.midX, 180), geo.size.width - 180),
                            y: max(selectionInfo.rectInEditor.minY - 80, 60)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                } else if inlineAIState == .showingResult {
                    inlineResultPopover
                        .position(
                            x: min(max(selectionInfo.rectInEditor.midX, 180), geo.size.width - 180),
                            y: max(selectionInfo.rectInEditor.minY - 80, 60)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                }
            }
            .onAppear {
                editorAreaFrame = geo.frame(in: .global)
            }
            .onChange(of: geo.size) { _, _ in
                editorAreaFrame = geo.frame(in: .global)
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }
                .padding(.vertical, 24)
            } else {
                Button(action: generateAIDraft) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                        Text("Generate Draft with Opus")
                            .font(DS.buttonText)
                    }
                    .foregroundColor(DS.accent)
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
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.8))
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

    // MARK: - Unified Bottom Bar

    private var unifiedBottomBar: some View {
        HStack(spacing: 12) {
            // Left: Save status
            if saveState != .idle {
                HStack(spacing: 4) {
                    if saveState == .saving {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(DS.textMuted)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.accent)
                    }
                    Text(saveState == .saving ? "Saving..." : "Saved")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textMuted)
                }
                .transition(.opacity)
            }

            Spacer()

            // Center: Phase name
            Text(viewModel.displayPhase.displayName)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DS.textMuted)
                .tracking(0.24)

            // Word count — selection-aware
            if !viewModel.state.draftContent.isEmpty {
                let textToCount = selectedText.isEmpty ? viewModel.state.draftContent : selectedText
                let words = textToCount.split(whereSeparator: \.isWhitespace).count
                Text("\(words) words")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(DS.textMuted)
            }

            Spacer()

            // Polish toggle
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
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(height: 48)
        .background(
            Rectangle()
                .fill(DS.bg)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DS.border)
                        .frame(height: 1)
                }
        )
    }

    @ViewBuilder
    private var polishToggleLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
            Text("Polish")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(isPolishModeActive ? Color(hex: "#34D399") : DS.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(isPolishModeActive ? Color(hex: "#34D399").opacity(0.15) : DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(isPolishModeActive ? Color(hex: "#34D399").opacity(0.3) : DS.border, lineWidth: 1)
        )
    }

    // MARK: - Polish Analysis

    private func updatePolishAnalysis() {
        let text = viewModel.state.draftContent
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            polishAnalysis = nil
            return
        }
        polishAnalysis = WritingAnalyzer.shared.analyze(text: text)
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
    private var inlineActionBar: some View {
        HStack(spacing: 2) {
            inlineBarButton(icon: "arrow.up.left.and.arrow.down.right", label: "Expand", action: .expand)
            inlineBarButton(icon: "arrow.down.right.and.arrow.up.left", label: "Condense", action: .condense)
            inlineBarButton(icon: "arrow.triangle.2.circlepath", label: "Rephrase", action: .rephrase)

            Rectangle()
                .fill(DS.borderActive)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)

            Button(action: {
                withAnimation(ProMotionSprings.snappy) { showCustomPrompt.toggle() }
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DS.borderActive, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        )
        .overlay(alignment: .bottom) {
            if showCustomPrompt {
                customPromptField
                    .offset(y: 46)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func inlineBarButton(icon: String, label: String, action: AIWritingAction) -> some View {
        Button(action: { triggerInlineAction(action) }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(DS.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(DS.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var customPromptField: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.system(size: 11))
                .foregroundColor(DS.accent.opacity(0.7))

            TextField("Custom instruction...", text: $customPromptText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.text)
                .onSubmit {
                    guard !customPromptText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    triggerCustomPrompt(customPromptText)
                    customPromptText = ""
                    showCustomPrompt = false
                }

            Button(action: {
                guard !customPromptText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                triggerCustomPrompt(customPromptText)
                customPromptText = ""
                showCustomPrompt = false
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(DS.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.accent.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        )
    }

    @ViewBuilder
    private var inlineResultPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(DS.accent)
                    .font(.system(size: 12))
                Text("AI Suggestion")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)
                Spacer()
                Button(action: { dismissInlineAI() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textMuted)
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
                        .font(.system(size: 11))
                        .foregroundColor(DS.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if let result = inlineAssistant.currentResult {
                inlineResultBody(result)
            } else if let error = inlineAssistant.error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(DS.textSecondary)
                    Button(action: { dismissInlineAI() }) {
                        Text("Dismiss")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.accent)
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
                    .font(.system(size: 10))
                    .foregroundColor(DS.accent)
                Text(result.action.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.accent)
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
                        .font(.system(size: 11))
                        .foregroundColor(.green.opacity(0.9))
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
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        Text("Accept").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DS.accent))
                }
                .buttonStyle(.plain)

                Button(action: { dismissInlineAI() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        Text("Reject").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(DS.textSecondary)
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

        if info.text.isEmpty || info.range.length == 0 {
            if inlineAIState == .showingBar {
                withAnimation(ProMotionSprings.snappy) {
                    inlineAIState = .idle
                    showCustomPrompt = false
                }
            }
        } else {
            if inlineAIState == .idle {
                withAnimation(ProMotionSprings.snappy) {
                    inlineAIState = .showingBar
                }
            }
        }
    }

    private func triggerInlineAction(_ action: AIWritingAction) {
        let text = selectionInfo.text
        guard !text.isEmpty else { return }

        withAnimation(ProMotionSprings.snappy) {
            inlineAIState = .processing(action)
            showCustomPrompt = false
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
        let draft = viewModel.state.draftContent
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
            viewModel.state.draftContent = replacement
        } else {
            let nsString = viewModel.state.draftContent as NSString
            let range = selectionInfo.range
            if range.location + range.length <= nsString.length {
                viewModel.state.draftContent = nsString.replacingCharacters(in: range, with: replacement)
            } else {
                viewModel.state.draftContent = viewModel.state.draftContent.replacingOccurrences(
                    of: result.originalText, with: replacement
                )
            }
        }

        triggerAutoSave()
        dismissInlineAI()
    }

    private func dismissInlineAI() {
        withAnimation(ProMotionSprings.snappy) {
            inlineAIState = .idle
            inlineAssistant.currentResult = nil
            inlineAssistant.error = nil
            showCustomPrompt = false
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
                    viewModel.state.lastModified = Date()
                    viewModel.state.save()
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
            // Back button
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DS.border, in: Capsule())
            }
            .buttonStyle(.plain)

            // Editable title
            TextField("Content title...", text: $editableTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.text)
                .frame(maxWidth: 300)
                .onChange(of: editableTitle) { _, _ in
                    viewModel.updateTitle(editableTitle)
                }

            // Type badge
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                Text("Content")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(OnyxTypography.labelTracking)
            }
            .foregroundColor(OnyxColors.Dimension.creative)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(OnyxColors.Dimension.creative.opacity(0.12), in: Capsule())

            Spacer()

            // Word + character count pill — selection-aware
            if !viewModel.state.draftContent.isEmpty {
                let textToCount = selectedText.isEmpty ? viewModel.state.draftContent : selectedText
                let words = textToCount.split(whereSeparator: \.isWhitespace).count
                let chars = textToCount.count
                Text("\(words) words · \(chars) chars")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.border, in: Capsule())
            }
        }
        .padding(.horizontal, 20)
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
            .frame(height: 120)
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

    init(atom: Atom) {
        self.atom = atom
        self.state = ContentFocusModeState(atomUUID: atom.uuid)
    }

    private var phaseChangeCancellable: AnyCancellable?

    deinit {
        autoSaveTask?.cancel()
        saveNotificationCancellable?.cancel()
        phaseChangeCancellable?.cancel()
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
                            _local_version = _local_version + 1
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
            } catch {
                print("❌ Content focus: failed to write to atom: \(error)")
            }
        }
    }

    /// Called when view disappears — force immediate save
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
        writeToAtom()
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
        titleUpdateTask?.cancel()
        titleUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s debounce
            guard !Task.isCancelled else { return }
            let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let uuid = atom.uuid
            do {
                try await CosmoDatabase.shared.asyncWrite { db in
                    try db.execute(
                        sql: """
                        UPDATE atoms SET title = ?, updated_at = ?, _local_version = _local_version + 1
                        WHERE uuid = ?
                        """,
                        arguments: [trimmed, ISO8601DateFormatter().string(from: Date()), uuid]
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
