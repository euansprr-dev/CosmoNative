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
    /// Tracks whether the user has edited the draft — blocks observation overwrites
    @State private var draftEditedLocally = false

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

    // Scriptorium V2 state
    @State private var zenMode: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var isContinuation: Bool = false
    @State private var cosmoExpanded: Bool = false
    @StateObject private var cosmoSession: FocusCosmoSession

    // Inherited context for the right marginalia (source / swipes / framework / brand / hooks)
    @State private var sourceIdeaAtom: Atom?
    @State private var matchedSwipeAtoms: [Atom] = []
    @State private var inheritedFramework: String?
    @State private var clientProfileAtom: Atom?
    @State private var availableClientProfiles: [Atom] = []
    @State private var coreIdeaExpanded: Bool = false
    @State private var hoveredSwipeUUID: String?

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
        self._cosmoSession = StateObject(wrappedValue: FocusCosmoSession(
            atomUUID: atom.uuid,
            atomTitle: atom.title,
            contextKind: .content
        ))
    }

    // MARK: - Body — The Scriptorium

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if ContentFocusModeState.stepForPhase(viewModel.displayPhase) != nil {
                scriptoriumBody
            } else {
                // Post-creation phase — wrap in Atelier header chrome
                VStack(spacing: 0) {
                    scriptoriumHeader
                    PostCreationPhaseView(
                        phase: viewModel.displayPhase,
                        atom: atom,
                        state: $viewModel.state,
                        onAdvancePhase: { phase in viewModel.goToPhase(phase) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // XP award — italic serif gilt, no glow
            if let xp = viewModel.xpAwarded {
                VStack {
                    Spacer()
                    Text("+\(xp) · \(viewModel.state.currentStep.label.lowercased()) complete")
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(DS.gilt)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 120)
                }
                .animation(.easeOut(duration: 0.6), value: viewModel.xpAwarded)
                .zIndex(200)
            }
        }
        .animation(.easeOut(duration: 0.4), value: viewModel.xpAwarded)
        .animation(ProMotionSprings.snappy, value: zenMode)
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
            // If the atom landed here in brainstorm (legacy), bump to draft
            if viewModel.state.currentStep == .brainstorm {
                viewModel.state.currentStep = .draft
            }
            if viewModel.state.currentStep == .polish {
                isPolishModeActive = true
                updatePolishAnalysis()
            }
            // Check if this mount is a direct continuation from Idea Focus
            // (user just pressed "begin writing →"). If so, skip the stagger
            // and cross-fade the whole page in place.
            isContinuation = FocusTransitionCoordinator.shared.consumePromotion(matching: atom.uuid)
            if isContinuation {
                withAnimation(.easeOut(duration: 0.26)) {
                    hasAppeared = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.45).delay(0.05)) {
                    hasAppeared = true
                }
            }
            // Load inherited context (source idea, swipes, framework, client profile)
            // for the right marginalia sections.
            Task { await loadInheritedContext() }
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
            print("[FOCUS-CONTENT] onDisappear — uuid=\(atom.uuid) localDraftLen=\(localDraftContent.count) vmDraftLen=\(viewModel.state.draftContent.count) draftDocPlainLen=\(draftDocument.plainText.count) draftPreview=\"\(String(localDraftContent.prefix(80)))\"")
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
            // Snapshot current state — CosmoDocumentEditor's flushPendingSync may not have
            // propagated yet (child onDisappear order is not guaranteed). Save immediately
            // with what we have, then the deferred onDocumentChange from flushPendingSync
            // will trigger another save via triggerAutoSave if the text was stale.
            if draftDocument.plainText != localDraftContent && !localDraftContent.isEmpty {
                print("[FOCUS-CONTENT] onDisappear — rebuilding stale draftDocument from localDraftContent (docLen=\(draftDocument.plainText.count) vs localLen=\(localDraftContent.count))")
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
            // Sync external draft updates (AI engine, tool executor) back to local state.
            // Skip if user has edited locally — prevents auto-save observation echo
            // from overwriting text typed since the save started.
            if newValue != localDraftContent, !draftEditedLocally {
                print("[FOCUS-CONTENT] onChange(vmDraftContent) APPLYING external update — uuid=\(atom.uuid) newLen=\(newValue.count) localLen=\(localDraftContent.count) preview=\"\(String(newValue.prefix(60)))\"")
                localDraftContent = newValue
                draftDocument = viewModel.state.richDraftDocument ?? RichDocument.migrateLegacy(newValue)
            } else if newValue != localDraftContent, draftEditedLocally {
                print("[FOCUS-CONTENT] onChange(vmDraftContent) SKIPPED — draftEditedLocally=true uuid=\(atom.uuid) vmLen=\(newValue.count) localLen=\(localDraftContent.count)")
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

    // MARK: - Scriptorium body (draft + polish steps)

    /// The Atelier-style stagger runs on fresh opens. When this mount came
    /// directly from an Idea Focus `begin writing →` press, we want the whole
    /// page to cross-fade in as a single movement instead — that's what sells
    /// the "same page, now a manuscript" feel. These two helpers pick the right
    /// mode per element.
    private func continuationStagger(_ delay: Double) -> Double {
        isContinuation ? 0 : delay
    }

    private var scriptoriumBody: some View {
        VStack(spacing: 0) {
            // Whisper-thin nav — zen ornament stays visible so you can always exit zen mode
            scriptoriumHeader
                .atelierStaggerIn(delay: continuationStagger(0.05), appeared: hasAppeared)

            // Page-wide title hero + step ledger — centered to the whole window,
            // not just the manuscript column. This is what makes the page feel
            // like a single composition rather than a left-heavy layout.
            VStack(spacing: DS.space20) {
                scriptoriumTitleHero
                    .atelierStaggerIn(delay: continuationStagger(0.12), appeared: hasAppeared)
                scriptoriumStepLedger
                    .atelierStaggerIn(delay: continuationStagger(0.20), appeared: hasAppeared)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DS.space12)
            .padding(.bottom, DS.space24)
            .opacity(zenMode ? 0 : 1)

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Margins are outside the scroll view so they stay pinned
                    // while only the center manuscript column scrolls.
                    HStack(spacing: 0) {
                        Spacer(minLength: DS.space24)

                        HStack(alignment: .top, spacing: DS.space24) {
                            scriptoriumLeftMargin
                                .frame(width: 200, alignment: .leading)
                                .padding(.top, DS.space12)
                                .opacity(zenMode ? 0 : 1)
                                .allowsHitTesting(!zenMode)
                                .atelierStaggerIn(delay: continuationStagger(0.28), appeared: hasAppeared)

                            ScrollView {
                                scriptoriumManuscript(height: geo.size.height)
                                    .atelierStaggerIn(delay: continuationStagger(0.36), appeared: hasAppeared)
                                    .padding(.top, DS.space4)
                                    .padding(.bottom, DS.space20)
                            }
                            .scrollIndicators(.hidden)

                            scriptoriumRightMargin
                                .frame(width: 220, alignment: .leading)
                                .padding(.top, DS.space12)
                                .opacity(zenMode ? 0 : 1)
                                .allowsHitTesting(!zenMode)
                                .atelierStaggerIn(delay: continuationStagger(0.44), appeared: hasAppeared)
                        }
                        .frame(maxWidth: 1244)

                        Spacer(minLength: DS.space24)
                    }
                    .padding(.top, DS.space4)

                    // Inline AI Result Popover — preserved verbatim
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

                    // Word & character counter — bottom left, updates on text selection
                    wordCharCounter
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
        .background(inlineAIKeyboardShortcuts)
    }

    // MARK: - Scriptorium manuscript (title hero + step ledger + rich editor)

    private func scriptoriumManuscript(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            // Title editor — serif display, chromeless (matches Atelier)
            TextField("untitled content", text: $editableTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.displaySerif)
                .foregroundStyle(DS.text)
                .tracking(-0.5)
                .lineLimit(1...3)
                .onChange(of: editableTitle) { _, newTitle in
                    viewModel.updateTitle(newTitle)
                }

            // Metadata line
            HStack(spacing: DS.space8) {
                Text(formattedCreatedDate)
                Text("·")
                if !viewModel.state.contentDescription.isEmpty {
                    Text(viewModel.state.contentDescription)
                        .lineLimit(1)
                } else {
                    Text("no description")
                }
            }
            .font(DS.dateSerif)
            .italic()
            .foregroundStyle(DS.inkFaded)

            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(width: 120, height: 0.5)

            if localDraftContent.isEmpty {
                aiDraftButton
            }

            // Main draft editor — machinery preserved exactly
            CosmoDocumentEditor(
                document: $draftDocument,
                fontSize: 17,
                placeholder: "begin writing…",
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
                onAIAction: { action in triggerInlineAction(action) },
                onCustomPrompt: { prompt in triggerCustomPrompt(prompt) },
                onDocumentChange: { document, plainText in
                    let changed = plainText != localDraftContent
                    print("[FOCUS-CONTENT] onDocumentChange(draft) — changed=\(changed) len=\(plainText.count) preview=\"\(String(plainText.prefix(60)))\" uuid=\(atom.uuid)")
                    localDraftContent = plainText
                    draftDocument = document
                    draftEditedLocally = true
                    triggerAutoSave()
                    if isPolishModeActive { debouncedPolishUpdate() }
                }
            )
            .frame(minHeight: max(textContentHeight, height - 200), alignment: .top)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: DraftEditorFrameKey.self,
                                    value: proxy.frame(in: .named("editorOverlay")))
                }
            )

            scriptoriumCTA
                .padding(.top, DS.space24)
                .atelierStaggerIn(delay: continuationStagger(0.52), appeared: hasAppeared)
        }
        .frame(width: 760, alignment: .leading)
    }

    // MARK: - Scriptorium header (quiet nav + zen ornament)

    private var scriptoriumHeader: some View {
        HStack(spacing: DS.space12) {
            if !isPaneContext {
                Button(action: onClose) {
                    HStack(spacing: DS.space6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("back")
                            .font(DS.dateSerif)
                            .italic()
                    }
                    .foregroundStyle(DS.inkFaded)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go back")
                .opacity(zenMode ? 0 : 1)
                .allowsHitTesting(!zenMode)
            }
            Spacer()
            // Zen ornament is always visible — it's the only way to exit zen mode
            ZenOrnament(isOn: $zenMode)
            if isPaneContext {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.inkFaded)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, DS.space8)
                .accessibilityLabel("Close pane")
                .opacity(zenMode ? 0 : 1)
                .allowsHitTesting(!zenMode)
            }
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
    }

    // MARK: - Title hero (smallCaps status ornament)

    private var scriptoriumTitleHero: some View {
        Text(statusOrnamentLabel)
            .font(DS.smallCaps)
            .tracking(2.2)
            .foregroundStyle(DS.giltMuted)
            .frame(maxWidth: .infinity)
    }

    private var statusOrnamentLabel: String {
        let status: String
        if let step = ContentFocusModeState.stepForPhase(viewModel.displayPhase) {
            status = step.rawValue.uppercased()
        } else {
            status = viewModel.displayPhase.rawValue.uppercased()
        }
        return "· · · CONTENT · \(status) · · ·"
    }

    private var formattedCreatedDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: atom.createdAt)
            ?? ISO8601DateFormatter().date(from: atom.createdAt)
            ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date).lowercased()
    }

    // MARK: - Step ledger (i ─── ii)

    private var scriptoriumStepLedger: some View {
        let currentStep = viewModel.state.currentStep
        return HStack(spacing: 0) {
            Spacer()
            stepLedgerNumeral("i", label: "draft", isCurrent: currentStep == .draft, isCompleted: currentStep == .polish) {
                viewModel.goToStep(.draft)
            }
            Rectangle()
                .fill(currentStep == .polish ? DS.gilt.opacity(0.5) : DS.sepiaSubtle)
                .frame(width: 48, height: 0.5)
                .padding(.horizontal, DS.space8)
            stepLedgerNumeral("ii", label: "polish", isCurrent: currentStep == .polish, isCompleted: false) {
                viewModel.goToStep(.polish)
                isPolishModeActive = true
                updatePolishAnalysis()
            }
            Spacer()
        }
    }

    private func stepLedgerNumeral(_ numeral: String, label: String, isCurrent: Bool, isCompleted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(numeral)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(isCurrent ? DS.gilt : (isCompleted ? DS.gilt.opacity(0.6) : DS.giltMuted))
                Text(label)
                    .font(DS.smallCaps)
                    .tracking(1.6)
                    .foregroundStyle(isCurrent ? DS.text : DS.inkFaded)
                if isCurrent {
                    Rectangle()
                        .fill(DS.gilt)
                        .frame(width: 3, height: 3)
                        .rotationEffect(.degrees(45))
                        .padding(.top, 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Left marginalia (hooks + outline + core idea  /  score swaps in polish)

    private var scriptoriumLeftMargin: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            if isPolishModeActive, viewModel.state.contentScorecard != nil {
                scoreMarginaliaSection
            }
            if !viewModel.state.hooks.isEmpty {
                hooksMarginaliaSection
            }
            outlineMarginaliaSection
            if !viewModel.state.contentDescription.isEmpty {
                coreIdeaMarginaliaSection
            }
        }
    }

    private var outlineMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("OUTLINE", countText: viewModel.state.outline.isEmpty ? nil : "\(viewModel.state.outline.count)")
            if viewModel.state.outline.isEmpty {
                Text("no outline yet")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(DS.inkFaded.opacity(0.6))
            } else {
                ForEach(Array(viewModel.state.outline.enumerated()), id: \.element.id) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                        Text(romanNumeral(for: idx + 1))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(DS.giltMuted)
                            .frame(width: 24, alignment: .leading)
                        Text(item.title)
                            .font(DS.callout)
                            .foregroundStyle(DS.text)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var coreIdeaMarginaliaSection: some View {
        let desc = viewModel.state.contentDescription
        let needsTruncation = desc.count > 140
        return VStack(alignment: .leading, spacing: DS.space6) {
            MarginaliaLabel("CORE IDEA")
            Text(desc)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.text)
                .lineLimit(coreIdeaExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
            if needsTruncation {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        coreIdeaExpanded.toggle()
                    }
                } label: {
                    Text(coreIdeaExpanded ? "show less" : "show more…")
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(DS.gilt.opacity(0.75))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, DS.space2)
            }
        }
    }

    private var scoreMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("SCORE")
            Text("analyzing…")
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(DS.inkFaded.opacity(0.6))
            // Full scorecard dimension render will ship in V1.5 — polish analysis
            // (WritingAnalyzer) still drives inline highlights via polishAnalysis.
        }
    }

    // MARK: - Right marginalia (SOURCE · SWIPES · FRAMEWORK · BRAND · HOOKS)

    private var scriptoriumRightMargin: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            if sourceIdeaAtom != nil {
                sourceMarginaliaSection
            }
            if !matchedSwipeAtoms.isEmpty {
                swipesMarginaliaSection
            }
            if let framework = inheritedFramework, !framework.isEmpty {
                frameworkMarginaliaSection(framework)
            }
            if clientProfileAtom != nil || !availableClientProfiles.isEmpty {
                brandMarginaliaSection
            }
            FocusCosmoPanel(session: cosmoSession, isExpanded: $cosmoExpanded)
                .task { await cosmoSession.load() }
        }
    }

    @ViewBuilder
    private var sourceMarginaliaSection: some View {
        if let idea = sourceIdeaAtom {
            Button {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openBlockInFocusMode,
                    object: nil,
                    userInfo: ["atomUUID": idea.uuid]
                )
            } label: {
                VStack(alignment: .leading, spacing: DS.space10) {
                    MarginaliaLabel("SOURCE")
                    HStack(alignment: .top, spacing: DS.space8) {
                        Rectangle()
                            .fill(DS.entityIdea.opacity(0.25))
                            .frame(width: 3)
                            .frame(maxHeight: .infinity)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.title ?? "untitled idea")
                                .font(.system(size: 14, weight: .regular, design: .serif))
                                .foregroundStyle(DS.text)
                                .lineLimit(2)
                            if let body = idea.body, !body.isEmpty {
                                Text(String(body.prefix(80)))
                                    .font(DS.dateSerif)
                                    .italic()
                                    .foregroundStyle(DS.inkFaded)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open source idea")
        }
    }

    private var swipesMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("SWIPES", countText: "\(matchedSwipeAtoms.count) matched")
            ForEach(matchedSwipeAtoms.prefix(3), id: \.uuid) { swipe in
                swipeMarginaliaRow(swipe)
            }
        }
    }

    private func swipeMarginaliaRow(_ swipe: Atom) -> some View {
        let isHovered = hoveredSwipeUUID == swipe.uuid
        return Button {
            openAtomInPane(swipe.uuid)
        } label: {
            HStack(alignment: .top, spacing: DS.space8) {
                Rectangle()
                    .fill(DS.entitySwipe.opacity(isHovered ? 0.55 : 0.18))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 1) {
                    Text(swipe.title ?? "untitled")
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                    if let hook = swipe.researchMetadata?.hook {
                        Text(hook)
                            .font(DS.caption2)
                            .foregroundStyle(DS.inkFaded)
                            .lineLimit(1)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, DS.space4)
            .padding(.horizontal, DS.space6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.vellum.opacity(isHovered ? 0.55 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredSwipeUUID = hovering ? swipe.uuid : nil
            }
        }
        .accessibilityLabel("Open swipe \(swipe.title ?? "untitled")")
    }

    private func openAtomInPane(_ uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid, "asPane": true]
        )
    }

    private func frameworkMarginaliaSection(_ framework: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            MarginaliaLabel("FRAMEWORK")
            Text(framework)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(DS.text)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var brandMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            MarginaliaLabel("BRAND")
            brandPickerMenu
            if let profile = clientProfileAtom,
               let meta = profile.metadataValue(as: ClientProfileMetadata.self) {
                brandVoiceBullets(meta)
            }
        }
    }

    private var brandPickerMenu: some View {
        Menu {
            ForEach(availableClientProfiles, id: \.uuid) { profile in
                Button {
                    assignClientProfile(profile)
                } label: {
                    HStack {
                        Text(profile.title ?? "unnamed")
                        if profile.uuid == clientProfileAtom?.uuid {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if availableClientProfiles.isEmpty {
                Text("no client profiles available")
            }
            if clientProfileAtom != nil {
                Divider()
                Button(role: .destructive) {
                    clearClientProfile()
                } label: {
                    Label("remove brand", systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: DS.space6) {
                Text(brandMenuTitle)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.gilt.opacity(0.7))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Select client profile")
    }

    private var brandMenuTitle: String {
        if let profile = clientProfileAtom {
            return (profile.title ?? "unnamed").lowercased()
        }
        return "pick brand"
    }

    @ViewBuilder
    private func brandVoiceBullets(_ meta: ClientProfileMetadata) -> some View {
        let bullets = collectBrandBullets(meta).prefix(3)
        if !bullets.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.gilt.opacity(0.6))
                        Text(bullet)
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.text)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func assignClientProfile(_ profile: Atom) {
        clientProfileAtom = profile
        viewModel.state.clientProfileUUID = profile.uuid
        viewModel.state.save()
    }

    private func clearClientProfile() {
        clientProfileAtom = nil
        viewModel.state.clientProfileUUID = nil
        viewModel.state.save()
    }

    private func collectBrandBullets(_ meta: ClientProfileMetadata) -> [String] {
        var bullets: [String] = []
        if let niche = meta.niche, !niche.isEmpty { bullets.append(niche) }
        if let voice = meta.voiceNotes, !voice.isEmpty {
            bullets.append(String(voice.prefix(50)))
        }
        if let audience = meta.targetAudience, !audience.isEmpty {
            bullets.append(String(audience.prefix(50)))
        }
        if let story = meta.brandStory, !story.isEmpty, bullets.count < 3 {
            bullets.append(String(story.prefix(50)))
        }
        return bullets
    }

    private var hooksMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("HOOKS", countText: "\(viewModel.state.hooks.count)")
            ForEach(Array(viewModel.state.hooks.prefix(3).enumerated()), id: \.offset) { idx, hook in
                HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                    Text(romanNumeral(for: idx + 1) + ".")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(DS.giltMuted)
                        .frame(width: 22, alignment: .leading)
                    Text(hook)
                        .font(DS.caption)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Word & character counter (bottom-left overlay)

    private var counterValues: (words: Int, chars: Int) {
        let text = selectedText.isEmpty ? localDraftContent : selectedText
        let words = text.split(whereSeparator: \.isWhitespace).count
        let chars = text.count
        return (words, chars)
    }

    private var wordCharCounter: some View {
        let words = counterValues.words
        let chars = counterValues.chars
        let isSelection = !selectedText.isEmpty
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.space8) {
                Text("\(words)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)
                Text(words == 1 ? "word" : "words")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(DS.inkFaded.opacity(0.7))
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.sepiaSubtle)
                Text("\(chars)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)
                Text(chars == 1 ? "char" : "chars")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(DS.inkFaded.opacity(0.7))
            }
            if isSelection {
                Text("selection")
                    .font(DS.caption2)
                    .foregroundStyle(DS.gilt.opacity(0.6))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, DS.space20)
        .padding(.bottom, DS.space20)
        .opacity(localDraftContent.isEmpty || zenMode ? 0 : 1)
        .allowsHitTesting(false)
        .animation(ProMotionSprings.snappy, value: isSelection)
    }

    // MARK: - CTA

    private var scriptoriumCTA: some View {
        HStack {
            Spacer()
            GiltBracketedCTA(
                title: ctaTitle,
                disabled: localDraftContent.isEmpty,
                action: advanceFromCTA
            )
            .keyboardShortcut(.return, modifiers: [.command])
            Spacer()
        }
    }

    private var ctaTitle: String {
        switch viewModel.state.currentStep {
        case .brainstorm, .draft: return "polish it"
        case .polish: return "ship it"
        }
    }

    private func advanceFromCTA() {
        switch viewModel.state.currentStep {
        case .brainstorm, .draft:
            viewModel.goToPhase(.polish)
            isPolishModeActive = true
            updatePolishAnalysis()
        case .polish:
            viewModel.goToPhase(.scheduled)
        }
    }

    // MARK: - Helpers

    private func romanNumeral(for value: Int) -> String {
        let numerals: [(Int, String)] = [
            (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")
        ]
        var result = ""
        var n = value
        for (val, letters) in numerals {
            while n >= val {
                result += letters
                n -= val
            }
        }
        return result.isEmpty ? "\(value)" : result
    }

    // MARK: - AI Draft Button

    @ViewBuilder
    private var aiDraftButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isGeneratingDraft {
                AIWritingProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                Button(action: generateAIDraft) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(DS.caption)
                        Text("Generate Draft")
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

        let contentUUID = atom.uuid

        Task {
            do {
                // Call cloud engine on Railway directly — runs the full pipeline:
                // Block 1 (codex) + Block 2 (client) + Block 3A (blueprint)
                // → single session: plan → write_draft → self-edit
                // The engine reads all context from the content atom in Supabase
                let result = try await CloudWritingClient.shared.generateDraft(
                    contentUUID: contentUUID,
                    userDirection: viewModel.state.contentDescription.isEmpty
                        ? nil : viewModel.state.contentDescription
                )

                // The engine's write_draft tool saved to atom.body via Supabase
                // Fetch the updated atom to get the draft
                if let updated = try? await AtomRepository.shared.fetch(uuid: contentUUID),
                   let body = updated.body, !body.isEmpty {
                    await MainActor.run {
                        // Reset local-edit guard so onChange won't block this update
                        draftEditedLocally = false
                        let richDoc = RichDocument.migrateLegacy(body)
                        // Set both rich document and plain text on viewModel
                        viewModel.state.richDraftDocument = richDoc
                        viewModel.state.draftContent = body
                        // Directly update editor bindings (belt-and-suspenders)
                        localDraftContent = body
                        draftDocument = richDoc
                        lastAIGeneratedDraft = body
                        viewModel.state.save()
                    }
                }

                await MainActor.run {
                    isGeneratingDraft = false
                    if !result.success {
                        draftGenerationError = result.error ?? result.message
                    }
                }
            } catch {
                await MainActor.run {
                    isGeneratingDraft = false
                    draftGenerationError = error.localizedDescription
                }
            }
        }
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

    // MARK: - Inherited Context Loading

    /// Loads the source idea, matched swipes, inherited framework, and client
    /// profile from the content atom's metadata. Mirrors the loader used by
    /// `ContentContextPanel.loadInheritedContext()`, minus the intelligence /
    /// meta-pattern pieces that don't render in the marginalia.
    private func loadInheritedContext() async {
        guard let metadata = atom.metadataValue(as: ContentAtomMetadata.self) else { return }

        // Source idea
        if let ideaUUID = metadata.sourceIdeaUUID,
           let idea = try? await AtomRepository.shared.fetch(uuid: ideaUUID) {
            await MainActor.run { self.sourceIdeaAtom = idea }
        }

        // Matched swipes — at most 5, we only show 3
        if let swipeUUIDs = metadata.inheritedSwipeUUIDs {
            var loaded: [Atom] = []
            for uuid in swipeUUIDs.prefix(5) {
                if let swipe = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    loaded.append(swipe)
                }
            }
            if !loaded.isEmpty {
                await MainActor.run { self.matchedSwipeAtoms = loaded }
            }
        }

        // Framework (string)
        if let framework = metadata.inheritedFramework, !framework.isEmpty {
            await MainActor.run { self.inheritedFramework = framework }
        }

        // Client profile atom (brand voice lives in its metadata)
        if let clientUUID = metadata.clientProfileUUID,
           let client = try? await AtomRepository.shared.fetch(uuid: clientUUID) {
            await MainActor.run { self.clientProfileAtom = client }
        }

        // All available client profiles for the brand picker menu
        let profiles = (try? await AtomRepository.shared.fetchAll(type: .clientProfile)) ?? []
        await MainActor.run { self.availableClientProfiles = profiles }
    }

    // MARK: - Auto-save

    private func triggerAutoSave() {
        print("[FOCUS-CONTENT] triggerAutoSave() — \(autoSaveDelay)s debounce starting uuid=\(atom.uuid) localDraftLen=\(localDraftContent.count)")
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
                guard !Task.isCancelled else {
                    print("[FOCUS-CONTENT] triggerAutoSave() CANCELLED uuid=\(atom.uuid)")
                    return
                }
                print("[FOCUS-CONTENT] triggerAutoSave() debounce elapsed — uuid=\(atom.uuid) localDraftLen=\(localDraftContent.count) draftPreview=\"\(String(localDraftContent.prefix(80)))\"")
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

}

// MARK: - Zen Ornament (concentric circles → toggles zen mode)

struct ZenOrnament: View {
    @Binding var isOn: Bool
    @State private var hover: Bool = false

    var body: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { isOn.toggle() }
        } label: {
            ZStack {
                Circle()
                    .stroke(DS.gilt.opacity(0.25), lineWidth: 0.4)
                    .frame(width: 18, height: 18)
                Circle()
                    .stroke(DS.gilt.opacity(0.5), lineWidth: 0.6)
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(DS.gilt)
                    .frame(width: 3, height: 3)
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .scaleEffect(hover ? 1.08 : 1)
            .rotationEffect(.degrees(hover ? 0.5 : 0))
            .animation(ProMotionSprings.snappy, value: hover)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(".", modifiers: [.command])
        .onHover { hover = $0 }
        .help(isOn ? "Exit zen mode (⌘.)" : "Zen mode (⌘.)")
        .accessibilityLabel(isOn ? "Exit zen mode" : "Zen mode")
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

        print("[FOCUS-CONTENT-VM] writeToAtom() — uuid=\(atomUUID) seq=\(mySequence) step=\(stateCopy.currentStep.rawValue) draftLen=\(stateCopy.draftContent.count) draftPreview=\"\(String(stateCopy.draftContent.prefix(80)))\" outline=\(stateCopy.outline.count)items")

        Task {
            // Check if a newer write has been queued — if so, skip this one
            guard mySequence == self.writeSequence else {
                print("[FOCUS-CONTENT-VM] writeToAtom() SKIPPED stale — uuid=\(atomUUID) seq=\(mySequence) latest=\(self.writeSequence)")
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
                    print("[FOCUS-CONTENT-VM] writeToAtom() DB write DONE — uuid=\(atomUUID) seq=\(mySequence) rows=\(db.changesCount)")
                }
                // Sync: queue for Supabase push so content drafts don't only live locally
                if let updatedAtom = try? await CosmoDatabase.shared.asyncRead({ db in
                    try Atom.filter(Column("uuid") == atomUUID).fetchOne(db)
                }) {
                    // skipVersionIncrement: raw SQL already did _local_version + 1
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                }
            } catch {
                print("[FOCUS-CONTENT-VM] writeToAtom() FAILED — uuid=\(atomUUID) error=\(error)")
            }
        }
    }

    /// Synchronous write — blocks the calling thread until the DB write completes.
    /// Use ONLY in save-on-close paths where the app may terminate before an async write finishes.
    func writeToAtomSync() {
        state.lastModified = Date()
        let stateCopy = state
        let atomUUID = atom.uuid

        print("[FOCUS-CONTENT-VM] writeToAtomSync() — uuid=\(atomUUID) step=\(stateCopy.currentStep.rawValue) draftLen=\(stateCopy.draftContent.count) draftPreview=\"\(String(stateCopy.draftContent.prefix(80)))\"")

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
                print("[FOCUS-CONTENT-VM] writeToAtomSync() DONE — uuid=\(atomUUID) rows=\(db.changesCount)")
            }
            // Sync: queue for Supabase push
            Task {
                if let updatedAtom = try? await CosmoDatabase.shared.asyncRead({ db in
                    try Atom.filter(Column("uuid") == atomUUID).fetchOne(db)
                }) {
                    // skipVersionIncrement: raw SQL already did _local_version + 1
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                }
            }
        } catch {
            print("[FOCUS-CONTENT-VM] writeToAtomSync() FAILED — uuid=\(atomUUID) error=\(error)")
        }
    }

    /// Called when view disappears — force immediate synchronous save
    func saveOnClose() {
        print("[FOCUS-CONTENT-VM] saveOnClose() — uuid=\(atom.uuid) draftLen=\(state.draftContent.count) draftPreview=\"\(String(state.draftContent.prefix(80)))\" step=\(state.currentStep.rawValue)")
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
