// CosmoOS/UI/FocusMode/Content/ContentFocusModeView.swift
// Main Content Focus Mode container — unified single-page editor
// February 2026

import SwiftUI
import Combine
import GRDB
import AppKit

// MARK: - Content Focus Mode View

enum ContentFocusLayoutPolicy {
    static func showsMarginaliaRails(
        isPaneContext: Bool,
        zenMode: Bool,
        layoutMode: ContentFocusModeView.ContentLayoutMode,
        availableWidth: CGFloat
    ) -> Bool {
        guard !isPaneContext, !zenMode, layoutMode != .compact else { return false }
        return availableWidth >= 980
    }

    static func manuscriptWidth(
        availableWidth: CGFloat,
        preferredWritingWidth: CGFloat,
        isPaneContext: Bool,
        zenMode: Bool,
        layoutMode: ContentFocusModeView.ContentLayoutMode
    ) -> CGFloat {
        if isPaneContext {
            return min(preferredWritingWidth, max(320, availableWidth - 48))
        }

        if layoutMode == .compact {
            return max(320, availableWidth - DS.space40)
        }

        let sideAllowance: CGFloat = zenMode ? DS.space48 : 580
        let available = max(360, availableWidth - sideAllowance)
        return min(preferredWritingWidth, available)
    }
}

enum ContentFocusWritePolicy {
    static func allowsWrite(existingMetadata: String?, snapshotLastModified: Date) -> Bool {
        guard let existingModified = persistedModifiedTime(from: existingMetadata) else {
            return true
        }

        return snapshotLastModified.timeIntervalSince1970 + 0.000001 >= existingModified
    }

    private static func persistedModifiedTime(from metadata: String?) -> TimeInterval? {
        guard let metadata,
              let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let unix = dict["lastModifiedUnix"] as? TimeInterval {
            return unix
        }

        if let modifiedString = dict["lastModified"] as? String,
           let date = ISO8601.date(from: modifiedString) {
            return date.timeIntervalSince1970
        }

        return nil
    }
}

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
    /// Non-nil while the inline assistant has staged reviewable changes for this draft —
    /// drives the in-document diff that temporarily replaces the editor.
    @State private var draftReviewProposal: CosmoAssistantProposal?
    @State private var draftHeadingOutline: [RichHeadingOutlineEntry] = []
    @State private var draftNavigationTargetID: UUID?
    @StateObject private var writingEngine = UnifiedWritingEngine()
    @StateObject private var writingAIAssistant = ContentWritingAssistant()

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

    /// Polish analysis for Hemingway highlights
    @State private var polishAnalysis: WritingAnalysis?

    // Inline AI state (moved from ContentDraftView)
    @State private var selectionInfo: DraftSelectionInfo = .empty
    @State private var inlineAIState: InlineAIState = .idle
    @StateObject private var inlineAssistant = AIWritingAssistant()
    @State private var draftEditorOrigin: CGPoint = .zero
    @State private var selectedRephraseIndex: Int = 0
    @State private var showWritingAICard = false
    @State private var focusBandRange: NSRange?
    @State private var manuscriptScrollView: NSScrollView?
    @State private var manuscriptScrollMetrics = ManuscriptScrollMetrics()
    @State private var isActivelyTyping = false
    @State private var typingActivityTask: Task<Void, Never>?

    // Auto-save state
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var saveState: DraftSaveState = .idle
    private let autoSaveDelay: TimeInterval = 1.5

    private var focusBackground: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveBackground : DS.documentBackground }
    private var focusSurface: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveSurface : DS.documentSurface }
    private var focusSurfaceElevated: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveSurfaceElevated : DS.documentSurface }
    private var focusText: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveText : DS.documentText }
    private var focusTextSecondary: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveTextSecondary : DS.documentTextSecondary }
    private var focusTextMuted: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveTextMuted : DS.documentTextMuted }
    private var focusBorder: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveBorder : DS.documentBorder }
    /// Polish mode derives from the selected step so Draft can never keep stale polish highlights.
    private var isPolishModeActive: Bool { viewModel.state.currentStep.enablesPolishHighlights }

    // Debounced polish analysis
    @State private var polishDebounceTask: Task<Void, Never>?
    @State private var polishAnalysisRequestID = UUID()

    // AI Draft generation state
    @State private var isGeneratingDraft = false
    @State private var draftGenerationError: String?

    // Scriptorium V2 state
    @State private var zenMode: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var isContinuation: Bool = false
    @Namespace private var ledgerNamespace
    @FocusState private var focusedOutlineItemID: UUID?
    @State private var brandExpanded = false

    // Inherited context for the right marginalia (source / swipes / framework / brand / hooks)
    @State private var sourceIdeaAtom: Atom?
    @State private var matchedSwipeAtoms: [Atom] = []
    @State private var inheritedFramework: String?
    @State private var clientProfileAtom: Atom?
    @State private var availableClientProfiles: [Atom] = []
    @State private var hoveredSwipeUUID: String?
    @State private var showSwipeAttachmentEditor = false

    enum DraftSaveState { case idle, saving, saved }

    enum ContentLayoutMode { case compact, regular, full }

    enum WritingWidthMode: String, CaseIterable, Identifiable {
        case narrow
        case comfort
        case wide
        case immersive

        var id: String { rawValue }

        var label: String {
            switch self {
            case .narrow: return "Narrow"
            case .comfort: return "Comfort"
            case .wide: return "Wide"
            case .immersive: return "Immersive"
            }
        }

        var width: CGFloat {
            switch self {
            case .narrow: return 680
            case .comfort: return 860
            case .wide: return 980
            case .immersive: return 1_120
            }
        }
    }

    enum WritingFocusBandMode: String, CaseIterable, Identifiable {
        case off
        case paragraph
        case sentence
        case block

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off: return "Off"
            case .paragraph: return "Paragraph"
            case .sentence: return "Sentence"
            case .block: return "Block"
            }
        }
    }

    // Feature flag: when true, the embedded AI Collaborator is hidden (replaced by global Cosmo window)
    @AppStorage("cosmoWindowEnabled") private var cosmoWindowEnabled = true

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner

    // Responsive layout
    @State private var layoutMode: ContentLayoutMode = .full
    @AppStorage("contentFocusWritingWidthMode") private var writingWidthModeRaw = WritingWidthMode.comfort.rawValue
    @AppStorage("contentFocusBandMode") private var focusBandModeRaw = WritingFocusBandMode.off.rawValue

    private var editorMaxWidth: CGFloat {
        writingWidthMode.width
    }

    private var writingWidthMode: WritingWidthMode {
        WritingWidthMode(rawValue: writingWidthModeRaw) ?? .comfort
    }

    private var focusBandMode: WritingFocusBandMode {
        WritingFocusBandMode(rawValue: focusBandModeRaw) ?? .off
    }

    private var sideRailOpacity: Double {
        if zenMode { return 0 }
        return isActivelyTyping ? 0.34 : 1
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

    private func manuscriptWidth(availableWidth: CGFloat) -> CGFloat {
        ContentFocusLayoutPolicy.manuscriptWidth(
            availableWidth: availableWidth,
            preferredWritingWidth: writingWidthMode.width,
            isPaneContext: isPaneContext,
            zenMode: zenMode,
            layoutMode: layoutMode
        )
    }

    private var manuscriptEditorHeightOffset: CGFloat {
        zenMode ? 96 : 140
    }

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._editableTitle = State(initialValue: atom.title ?? "Untitled Content")
        self._viewModel = StateObject(wrappedValue: ContentFocusModeViewModel(atom: atom))
    }

    // MARK: - Body — The Scriptorium

    var body: some View {
        ZStack {
            focusBackground
                .ignoresSafeArea()
                .overlay {
                    FocusModeEditorBlurTapLayer()
                        .ignoresSafeArea()
                }

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
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(DS.gilt)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 120)
                }
                .animation(ProMotionSprings.cardEntrance, value: viewModel.xpAwarded)
                .zIndex(200)
            }
        }
        .animation(ProMotionSprings.gentle, value: viewModel.xpAwarded)
        .animation(ProMotionSprings.snappy, value: zenMode)
        .animation(ProMotionSprings.snappy, value: isPolishModeActive)
        .focusImmersiveEntryTransition()
        .onAppear {
            AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
            viewModel.loadState()
            localDraftContent = viewModel.state.draftContent
            draftDocument = viewModel.state.richDraftDocument ?? RichDocument.migrateLegacy(viewModel.state.draftContent)
            updateDraftHeadingOutline(from: draftDocument)
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
            let provider = ContentContextProvider(
                atom: atom,
                stateRef: { [viewModel] in viewModel.state },
                phaseRef: { [viewModel] in viewModel.displayPhase },
                draftTextRef: { [self] in self.localDraftContent },
                applyDraftEdit: { [self] operation in
                    try await self.applyInlineAssistantDraftEdit(operation)
                }
            )
            if !isPaneContext || isPaneContextOwner {
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
            ContentFocusWritingAIScope.shared.activate(atomUUID: atom.uuid) {
                openWritingAI()
            }
        }
        .onChange(of: isPaneContextOwner) { _, isOwner in
            if isOwner {
                let provider = ContentContextProvider(
                    atom: atom,
                    stateRef: { [viewModel] in viewModel.state },
                    phaseRef: { [viewModel] in viewModel.displayPhase },
                    draftTextRef: { [self] in self.localDraftContent },
                    applyDraftEdit: { [self] operation in
                        try await self.applyInlineAssistantDraftEdit(operation)
                    }
                )
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onReceive(CosmoInlineAssistantStore.shared.$proposals) { proposals in
            draftReviewProposal = proposals.last { proposal in
                proposal.hasReviewableOperations && proposal.matches(
                    surfaceID: inlineAssistantContentSurfaceID,
                    targetID: inlineAssistantContentTargetID,
                    activeAtomUUID: atom.uuid
                )
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
            ContentFocusWritingAIScope.shared.deactivate(atomUUID: atom.uuid)
            typingActivityTask?.cancel()
            polishDebounceTask?.cancel()
            persistCurrentEditorSnapshot(reason: "onDisappear")
        }
        .onReceive(NotificationCenter.default.publisher(for: .unifiedEngineDraftUpdate)) { notification in
            let targetUUID = notification.userInfo?["contentUUID"] as? String
                ?? notification.userInfo?["uuid"] as? String
            if let targetUUID, targetUUID != atom.uuid { return }

            // Capture AI-generated draft as the baseline for lesson extraction
            if let content = notification.userInfo?["content"] as? String, !content.isEmpty {
                lastAIGeneratedDraft = content
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .contentFocusOpenWritingAI)) { _ in
            openWritingAI()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmoAppWillTerminate)) { _ in
            // onDisappear does not reliably fire on app quit. Copy the live editor
            // snapshot and synchronously write it here so notification ordering cannot
            // leave the ViewModel's termination handler saving stale draft content.
            typingActivityTask?.cancel()
            polishDebounceTask?.cancel()
            persistCurrentEditorSnapshot(reason: "termination")
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
        }
        .onChange(of: viewModel.state.draftContent) { _, newValue in
            // Sync external draft updates (AI engine, tool executor) back to local state.
            // Skip if user has edited locally — prevents auto-save observation echo
            // from overwriting text typed since the save started.
            if newValue != localDraftContent, !draftEditedLocally {
                print("[FOCUS-CONTENT] onChange(vmDraftContent) APPLYING external update — uuid=\(atom.uuid) newLen=\(newValue.count) localLen=\(localDraftContent.count) preview=\"\(String(newValue.prefix(60)))\"")
                localDraftContent = newValue
                draftDocument = viewModel.state.richDraftDocument ?? RichDocument.migrateLegacy(newValue)
                updateDraftHeadingOutline(from: draftDocument)
            } else if newValue != localDraftContent, draftEditedLocally {
                print("[FOCUS-CONTENT] onChange(vmDraftContent) SKIPPED — draftEditedLocally=true uuid=\(atom.uuid) vmLen=\(newValue.count) localLen=\(localDraftContent.count)")
            }
        }
        .onChange(of: viewModel.state.currentStep) { oldStep, newStep in
            // Clear selection when switching steps
            selectedText = ""
            if newStep.enablesPolishHighlights {
                updatePolishAnalysis()
            } else {
                polishDebounceTask?.cancel()
                polishAnalysis = nil
            }
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
            if showWritingAICard {
                showWritingAICard = false
                return .handled
            }
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
        .sheet(isPresented: $showSwipeAttachmentEditor) {
            ContentSwipeAttachmentEditor(
                currentSwipeUUIDs: viewModel.currentInheritedSwipeUUIDs,
                currentBlueprintUUID: viewModel.currentBlueprintSwipeUUID
            ) { swipeUUIDs, blueprintUUID in
                await viewModel.saveSwipeAttachments(swipeUUIDs: swipeUUIDs, blueprintUUID: blueprintUUID)
                await loadInheritedContext()
            }
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

    /// Clearance the scroll surfaces reserve at rest so content starts below the
    /// floating toolbar — but slides *under* the glass once scrolling.
    private var scriptoriumToolbarClearance: CGFloat { 64 }

    private var scriptoriumBody: some View {
        // The toolbar is an overlay, not a layout row: the manuscript and margins
        // extend the full height and refract through the glass as they scroll.
        scriptoriumScrollStage
            .overlay(alignment: .top) {
                scriptoriumHeader
                    .atelierStaggerIn(delay: continuationStagger(0.05), appeared: hasAppeared)
            }
    }

    private var scriptoriumScrollStage: some View {
            GeometryReader { geo in
                let showMarginaliaRails = ContentFocusLayoutPolicy.showsMarginaliaRails(
                    isPaneContext: isPaneContext,
                    zenMode: zenMode,
                    layoutMode: layoutMode,
                    availableWidth: geo.size.width
                )

                ZStack(alignment: .topLeading) {
                    // Margins are outside the scroll view so they stay pinned
                    // while only the center manuscript column scrolls.
                    HStack(spacing: 0) {
                        Spacer(minLength: DS.space24)

                        HStack(alignment: .top, spacing: showMarginaliaRails ? DS.space24 : 0) {
                            if showMarginaliaRails {
                                scriptoriumMarginScroll(width: 260,
                                    height: max(0, geo.size.height - DS.space4)
                                ) {
                                    scriptoriumLeftMargin
                                }
                                    .opacity(sideRailOpacity)
                                    .atelierStaggerIn(delay: continuationStagger(0.28), appeared: hasAppeared)
                            }

                            ScrollView {
                                scriptoriumManuscript(height: geo.size.height, availableWidth: geo.size.width)
                                    .atelierStaggerIn(delay: continuationStagger(0.36), appeared: hasAppeared)
                                    .padding(.top, DS.space4)
                                    .padding(.bottom, DS.space20)
                                    .background(ScrollViewIntrospector { scrollView in
                                        manuscriptScrollView = scrollView
                                    } onMetricsChange: { metrics in
                                        manuscriptScrollMetrics = metrics
                                    })
                            }
                            .scrollIndicators(.hidden)
                            .scrollEdgeEffectStyle(.soft, for: .vertical)
                            // Rest below the floating toolbar, scroll under its glass.
                            .contentMargins(.top, scriptoriumToolbarClearance, for: .scrollContent)
                            .overlay(alignment: .trailing) {
                                PremiumManuscriptScrollbar(metrics: manuscriptScrollMetrics)
                                    .padding(.trailing, DS.space4)
                                    .padding(.top, scriptoriumToolbarClearance + DS.space8)
                                    .padding(.bottom, DS.space8)
                            }
                            .frame(height: max(0, geo.size.height - DS.space4), alignment: .top)

                            if showMarginaliaRails {
                                scriptoriumMarginScroll(width: 220,
                                    height: max(0, geo.size.height - DS.space4)
                                ) {
                                    scriptoriumRightMargin
                                }
                                    .opacity(sideRailOpacity)
                                    .atelierStaggerIn(delay: continuationStagger(0.44), appeared: hasAppeared)
                            }
                        }
                        .frame(maxWidth: 1244)

                        Spacer(minLength: DS.space24)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .padding(.top, DS.space4)
                    .background(FocusModeEditorBlurTapLayer())

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

                    if showWritingAICard {
                        writingAICardOverlay(in: geo.size)
                            .zIndex(150)
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
        .background(inlineAIKeyboardShortcuts)
    }

    // MARK: - Scriptorium manuscript (title hero + step ledger + rich editor)

    /// Margins scroll silently — the manuscript's scrollbar is the only one on
    /// the page; margin overflow fades at the edges instead of growing chrome.
    /// Like the manuscript, they rest below the toolbar and slide under its glass.
    private func scriptoriumMarginScroll<Content: View>(
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            content()
                .frame(width: width, alignment: .leading)
                .padding(.bottom, DS.space20)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .contentMargins(.top, scriptoriumToolbarClearance, for: .scrollContent)
        .frame(width: width, height: height, alignment: .top)
    }

    private func scriptoriumManuscript(height: CGFloat, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            if !zenMode {
                manuscriptTitleEditor
                    .transition(.opacity.combined(with: .offset(y: -16)))
            }

            // Date ornament — the core idea lives in the left margin, so the meta
            // row no longer echoes the title text.
            Text(formattedCreatedDate)
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(focusTextMuted)

            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(width: 120, height: 0.5)

            if localDraftContent.isEmpty {
                aiDraftButton
            }

            // Main draft editor — replaced by an in-document diff while a reviewed
            // assistant proposal is pending, then restored once changes are resolved.
            if let review = draftReviewProposal {
                CosmoInlineDiffReviewView(
                    store: CosmoInlineAssistantStore.shared,
                    proposal: review,
                    sourceText: localDraftContent,
                    bodyFont: .system(size: 17),
                    textColor: focusText,
                    onAcceptOperation: { operationID in
                        Task { await acceptInlineAssistantDraftReview(operationID: operationID) }
                    },
                    onRejectOperation: { operationID in
                        Task { await rejectInlineAssistantDraftReview(operationID: operationID) }
                    }
                )
                .frame(
                    minHeight: max(400, height - manuscriptEditorHeightOffset),
                    alignment: .top
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
            CosmoDocumentEditor(
                document: $draftDocument,
                fontSize: 17,
                placeholder: "begin writing…",
                darkMode: DS.usesImmersiveFocusAppearance,
                overrideTextColor: NSColor(focusText),
                allowSlashCommands: true,
                allowMentions: true,
                allowSelectionMenu: true,
                allowImages: true,
                typewriterMode: typewriterMode,
                polishHighlights: viewModel.state.currentStep.enablesPolishHighlights ? polishAnalysis : nil,
                onSelectionChanged: { snapshot in
                    handleSelectionChange(
                        DraftSelectionInfo(
                            text: snapshot.text,
                            range: snapshot.range,
                            rectInEditor: snapshot.rectInEditor
                        )
                    )
                },
                onAIAction: { action in triggerInlineAction(action) },
                onCustomPrompt: { prompt in triggerCustomPrompt(prompt) },
                onWritingAIRequest: { openWritingAI() },
                focusBandRange: focusBandRange,
                focusBandRangeProvider: { plainText, selectionRange in
                    focusBandRange(for: selectionRange, mode: focusBandMode, in: plainText)
                },
                navigationTargetID: draftNavigationTargetID,
                onPlainTextChange: { plainText in
                    handleDraftPlainTextChange(plainText)
                },
                onDocumentChange: { document, plainText in
                    let changed = plainText != localDraftContent
                    print("[FOCUS-CONTENT] onDocumentChange(draft) — changed=\(changed) len=\(plainText.count) preview=\"\(String(plainText.prefix(60)))\" uuid=\(atom.uuid)")
                    localDraftContent = plainText
                    draftDocument = document
                    updateDraftHeadingOutline(from: document)
                    draftEditedLocally = true
                    markTypingActive()
                    updateFocusBand()
                    scheduleTypewriterScroll()
                    triggerAutoSave()
                    if isPolishModeActive { debouncedPolishUpdate() }
                }
            )
            .frame(
                minHeight: max(400, height - manuscriptEditorHeightOffset),
                alignment: .top
            )
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: DraftEditorFrameKey.self,
                                    value: proxy.frame(in: .named("editorOverlay")))
                }
            )
            }

            scriptoriumCTA
                .padding(.top, DS.space24)
                .atelierStaggerIn(delay: continuationStagger(0.52), appeared: hasAppeared)
        }
        .frame(width: manuscriptWidth(availableWidth: availableWidth), alignment: .leading)
    }

    // MARK: - Scriptorium header (quiet nav + zen ornament)

    private var scriptoriumHeader: some View {
        ZStack {
            if zenMode {
                // Zen: the glass toolbar dematerializes — only the ornament (the
                // sole exit) and the fixed title remain over the paper.
                HStack {
                    Spacer()
                    ZenOrnament(isOn: $zenMode)
                }
                scriptoriumFixedTitleHeader
                    .padding(.horizontal, isPaneContext ? 72 : 180)
                    .transition(.opacity.combined(with: .offset(y: 14)))
            } else {
                scriptoriumToolbar
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
        .background(FocusModeEditorBlurTapLayer())
    }

    private var scriptoriumToolbar: some View {
        HStack(spacing: DS.space12) {
            if !isPaneContext {
                Button(action: onClose) {
                    HStack(spacing: DS.space6) {
                        Image(systemName: "chevron.left")
                            .font(DS.buttonText)
                        Text("Back")
                            .font(DS.callout)
                    }
                    .foregroundStyle(focusTextSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go back")
                .help("Back (Esc)")
            }
            Spacer(minLength: DS.space8)
            toolbarCenterSlot
            Spacer(minLength: DS.space8)
            writingSurfaceControls
            ZenOrnament(isOn: $zenMode)
            if isPaneContext {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(DS.caption)
                        .foregroundStyle(focusTextMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, DS.space8)
                .accessibilityLabel("Close pane")
                .help("Close")
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space6)
        .background(FocusModeEditorBlurTapLayer())
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)
        .opacity(isActivelyTyping ? 0.25 : 1)
        .animation(ProMotionSprings.gentle, value: isActivelyTyping)
        .onHover { hovering in
            if hovering { wakeChrome() }
        }
    }

    /// Center of the command row: the step ledger during draft/polish, a quiet
    /// phase label in the post-creation phases.
    @ViewBuilder
    private var toolbarCenterSlot: some View {
        if ContentFocusModeState.stepForPhase(viewModel.displayPhase) != nil {
            toolbarLedger
        } else {
            Text(viewModel.displayPhase.rawValue.uppercased())
                .font(DS.smallCaps)
                .tracking(2.2)
                .foregroundStyle(DS.giltMuted)
        }
    }

    private func wakeChrome() {
        typingActivityTask?.cancel()
        withAnimation(ProMotionSprings.gentle) {
            isActivelyTyping = false
        }
    }

    private var writingSurfaceControls: some View {
        HStack(spacing: DS.space6) {
            Button {
                openWritingAI()
            } label: {
                Image(systemName: "sparkles")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(showWritingAICard ? DS.gilt : focusTextMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.glassCardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(showWritingAICard ? DS.gilt.opacity(0.35) : DS.glassBorder, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("Writing AI (Option+A)")
            .accessibilityLabel("Open Writing AI")

            Menu {
                ForEach(WritingWidthMode.allCases) { mode in
                    Button {
                        writingWidthModeRaw = mode.rawValue
                    } label: {
                        Label(mode.label, systemImage: writingWidthMode == mode ? "checkmark" : "text.alignleft")
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(focusTextMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.glassCardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(DS.glassBorder, lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Writing width")

            Menu {
                ForEach(WritingFocusBandMode.allCases) { mode in
                    Button {
                        focusBandModeRaw = mode.rawValue
                        updateFocusBand()
                    } label: {
                        Label(mode.label, systemImage: focusBandMode == mode ? "checkmark" : "scope")
                    }
                }
                Divider()
                Button {
                    typewriterMode.toggle()
                } label: {
                    Label(typewriterMode || zenMode ? "Typewriter on" : "Typewriter off", systemImage: typewriterMode || zenMode ? "checkmark" : "arrow.down.to.line.compact")
                }
            } label: {
                Image(systemName: "scope")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(focusBandMode == .off ? focusTextMuted : DS.gilt)
                    .frame(width: 28, height: 28)
                    .background(DS.glassCardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(DS.glassBorder, lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Focus band")
        }
    }

    private var manuscriptTitleEditor: some View {
        TextField("untitled content", text: $editableTitle, axis: .vertical)
            .textFieldStyle(.plain)
            .font(DS.displaySerif)
            .foregroundStyle(focusText)
            .tracking(-0.5)
            .lineLimit(1...3)
            .onChange(of: editableTitle) { _, newTitle in
                viewModel.updateTitle(newTitle)
            }
    }

    private var scriptoriumFixedTitleHeader: some View {
        TextField("untitled content", text: $editableTitle, axis: .vertical)
            .textFieldStyle(.plain)
            .font(DS.compactTitleSerif)
            .foregroundStyle(focusText)
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .onChange(of: editableTitle) { _, newTitle in
                viewModel.updateTitle(newTitle)
            }
            .frame(maxWidth: 760)
            .accessibilityLabel("Content title")
    }

    private var formattedCreatedDate: String {
        let date = ISO8601.date(from: atom.createdAt) ?? Date()
        return CosmoDateFormatters.monthDay.string(from: date).lowercased()
    }

    // MARK: - Step ledger (i ─── ii)

    private var toolbarLedger: some View {
        let currentStep = viewModel.state.currentStep
        return HStack(spacing: DS.space8) {
            toolbarLedgerStep("i", label: "draft", shortcut: "1", isCurrent: currentStep == .draft, isCompleted: currentStep == .polish) {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.goToStep(.draft)
                }
            }
            Rectangle()
                .fill(currentStep == .polish ? DS.gilt.opacity(0.5) : DS.sepiaSubtle)
                .frame(width: 24, height: 0.5)
            toolbarLedgerStep("ii", label: "polish", shortcut: "2", isCurrent: currentStep == .polish, isCompleted: false) {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.goToStep(.polish)
                }
                updatePolishAnalysis()
            }
        }
    }

    private func toolbarLedgerStep(_ numeral: String, label: String, shortcut: KeyEquivalent, isCurrent: Bool, isCompleted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                if isCurrent {
                    // The gilt diamond travels between steps via matchedGeometryEffect.
                    Rectangle()
                        .fill(DS.gilt)
                        .frame(width: 3, height: 3)
                        .rotationEffect(.degrees(45))
                        .matchedGeometryEffect(id: "ledger-diamond", in: ledgerNamespace)
                }
                Text(numeral)
                    .font(DS.caption.weight(.bold).monospaced())
                    .foregroundStyle(isCurrent ? DS.gilt : (isCompleted ? DS.gilt.opacity(0.6) : DS.giltMuted))
                if layoutMode != .compact {
                    Text(label)
                        .font(DS.smallCaps)
                        .tracking(1.2)
                        .foregroundStyle(isCurrent ? focusText : focusTextMuted)
                }
            }
            .padding(.horizontal, DS.space6)
            .padding(.vertical, DS.space4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .help("\(label.capitalized) (⌘\(shortcut.character))")
        .accessibilityLabel(label)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: - Left marginalia (hooks + outline + core idea  /  score swaps in polish)

    private var scriptoriumLeftMargin: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            if isPolishModeActive, viewModel.state.contentScorecard != nil {
                scoreMarginaliaSection
            }
            hooksAndOutlineMarginaliaGroup
            if !viewModel.state.contentDescription.isEmpty {
                coreIdeaMarginaliaSection
            }
        }
    }

    private var hooksAndOutlineMarginaliaGroup: some View {
        scriptoriumMarginaliaContainer {
            VStack(alignment: .leading, spacing: DS.space18) {
                if !viewModel.state.hooks.isEmpty {
                    hooksMarginaliaSection
                }
                if !draftHeadingOutline.isEmpty {
                    draftSectionsMarginaliaSection
                }
                outlineMarginaliaSection
            }
        }
    }

    private var draftSectionsMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("SECTIONS", countText: "\(draftHeadingOutline.count)")
            VStack(alignment: .leading, spacing: DS.space6) {
                ForEach(draftHeadingOutline) { entry in
                    Button {
                        navigateToDraftHeading(entry)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
                            Text(entry.level == 1 ? "¶" : "›")
                                .font(DS.caption2)
                                .foregroundStyle(DS.giltMuted)
                                .frame(width: 10, alignment: .leading)
                            Text(entry.title)
                                .font(entry.level == 1 ? DS.caption : DS.caption2)
                                .foregroundStyle(entry.level == 1 ? focusText : focusTextMuted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, CGFloat(entry.level - 1) * DS.space8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Go to \(entry.title)")
                }
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
                    .foregroundStyle(focusTextMuted.opacity(0.6))
            } else {
                ForEach(Array(viewModel.state.outline.enumerated()), id: \.element.id) { idx, item in
                    HStack(alignment: .top, spacing: DS.space8) {
                        Text(romanNumeral(for: idx + 1))
                            .font(DS.footnote.monospaced())
                            .foregroundStyle(DS.giltMuted)
                            .frame(width: 24, alignment: .leading)
                            .padding(.top, 2)
                        TextField("Outline item", text: marginaliaOutlineTitleBinding(for: item.id), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(DS.callout)
                            .foregroundStyle(focusText)
                            .lineSpacing(2)
                            // Quiet glance by default; the full text opens while editing.
                            .lineLimit(focusedOutlineItemID == item.id ? nil : 2)
                            .focused($focusedOutlineItemID, equals: item.id)
                            .animation(ProMotionSprings.gentle, value: focusedOutlineItemID)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var coreIdeaMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            MarginaliaLabel("CORE IDEA")
            TextField("Core idea", text: marginaliaCoreIdeaBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(focusText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var marginaliaCoreIdeaBinding: Binding<String> {
        Binding(
            get: {
                if !viewModel.state.contentDescription.isEmpty { return viewModel.state.contentDescription }
                return viewModel.state.coreIdea
            },
            set: { newValue in
                viewModel.state.coreIdea = newValue
                viewModel.state.contentDescription = newValue
                viewModel.state.lastModified = Date()
                viewModel.state.save()
            }
        )
    }

    private func marginaliaOutlineTitleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.state.outline.first(where: { $0.id == id })?.title ?? ""
            },
            set: { newValue in
                viewModel.state.updateOutlineItem(id: id, title: newValue)
                viewModel.state.lastModified = Date()
                viewModel.state.save()
            }
        )
    }

    private var scoreMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("SCORE")
            Text("analyzing…")
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(focusTextMuted.opacity(0.6))
            // Full scorecard dimension render will ship in V1.5 — polish analysis
            // (WritingAnalyzer) still drives inline highlights via polishAnalysis.
        }
    }

    // MARK: - Right marginalia (SOURCE · SWIPES · FRAMEWORK · BRAND · HOOKS)

    private var scriptoriumRightMargin: some View {
        scriptoriumMarginaliaContainer {
            VStack(alignment: .leading, spacing: DS.space18) {
                rightMarginaliaSections
            }
        }
    }

    @ViewBuilder
    private var rightMarginaliaSections: some View {
        Group {
            if sourceIdeaAtom != nil {
                sourceMarginaliaSection
            }
            if sourceIdeaAtom != nil || !matchedSwipeAtoms.isEmpty {
                swipesMarginaliaSection
            }
            if let framework = inheritedFramework, !framework.isEmpty {
                frameworkMarginaliaSection(framework)
            }
            if clientProfileAtom != nil || !availableClientProfiles.isEmpty {
                brandMarginaliaSection
            }
            cosmoWritingMarginaliaSection
        }
    }

    /// Marginalia are typographic columns on the paper — no boxes; grouping is
    /// done by spacing and the smallCaps labels alone (Things law).
    private func scriptoriumMarginaliaContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, DS.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cosmoWritingMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            MarginaliaLabel("COSMO WRITING")
            Button {
                openWritingAI()
            } label: {
                HStack(spacing: DS.space6) {
                    Image(systemName: "sparkles")
                        .font(DS.caption.weight(.semibold))
                    Text("open assistant →")
                        .font(DS.dateSerif)
                        .italic()
                }
                .foregroundStyle(DS.gilt.opacity(0.78))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Cosmo Writing assistant")

            if !selectedText.isEmpty {
                Button {
                    submitWritingAI(action: .tighten)
                } label: {
                    Text("improve selected text")
                        .font(DS.caption2)
                        .foregroundStyle(focusTextMuted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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
                                .font(DS.dateSerif)
                                .foregroundStyle(focusText)
                                .lineLimit(3)
                            if let body = idea.body, !body.isEmpty {
                                Text(body)
                                    .font(DS.dateSerif)
                                    .italic()
                                    .foregroundStyle(focusTextMuted)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open source idea")
            .help("Open source idea")
        }
    }

    private var swipesMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            if let blueprint = currentBlueprintAtom {
                MarginaliaLabel("BLUEPRINT")
                swipeMarginaliaRow(blueprint, removeLabel: "Remove blueprint") {
                    Task {
                        let remaining = matchedSwipeAtoms.filter { $0.uuid != blueprint.uuid }.map(\.uuid)
                        await viewModel.saveSwipeAttachments(swipeUUIDs: remaining, blueprintUUID: remaining.first)
                        await loadInheritedContext()
                    }
                }
            } else {
                MarginaliaLabel("BLUEPRINT")
                Button {
                    showSwipeAttachmentEditor = true
                } label: {
                    Text("select blueprint →")
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(focusTextMuted.opacity(0.7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !supportingSwipeAtoms.isEmpty {
                VStack(alignment: .leading, spacing: DS.space8) {
                    MarginaliaLabel("RELATED SWIPES", countText: "\(supportingSwipeAtoms.count)")
                    ForEach(supportingSwipeAtoms, id: \.uuid) { swipe in
                        swipeMarginaliaRow(swipe, removeLabel: "Remove swipe \(swipe.title ?? "untitled")") {
                            Task {
                                let remaining = matchedSwipeAtoms.filter { $0.uuid != swipe.uuid }.map(\.uuid)
                                let blueprintUUID = currentBlueprintAtom?.uuid == swipe.uuid
                                    ? remaining.first
                                    : currentBlueprintAtom?.uuid
                                await viewModel.saveSwipeAttachments(swipeUUIDs: remaining, blueprintUUID: blueprintUUID)
                                await loadInheritedContext()
                            }
                        }
                    }
                }
            }

            Button {
                showSwipeAttachmentEditor = true
            } label: {
                Text(matchedSwipeAtoms.isEmpty ? "add references →" : "edit references →")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(DS.gilt.opacity(0.7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func swipeMarginaliaRow(
        _ swipe: Atom,
        removeLabel: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredSwipeUUID == swipe.uuid
        return HStack(alignment: .top, spacing: DS.space8) {
            Button {
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
                            .foregroundStyle(focusText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let hook = swipe.researchMetadata?.hook {
                            Text(hook)
                                .font(DS.caption2)
                                .foregroundStyle(focusTextMuted)
                                .fixedSize(horizontal: false, vertical: true)
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

            Spacer(minLength: 0)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.buttonText)
                    .foregroundStyle(focusTextMuted)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removeLabel)
        }
    }

    private var currentBlueprintAtom: Atom? {
        let blueprintUUID = viewModel.currentBlueprintSwipeUUID ?? matchedSwipeAtoms.first?.uuid
        guard let blueprintUUID else { return matchedSwipeAtoms.first }
        return matchedSwipeAtoms.first(where: { $0.uuid == blueprintUUID }) ?? matchedSwipeAtoms.first
    }

    private var supportingSwipeAtoms: [Atom] {
        guard let currentBlueprintAtom else { return matchedSwipeAtoms }
        return matchedSwipeAtoms.filter { $0.uuid != currentBlueprintAtom.uuid }
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
                .font(DS.dateSerif)
                .foregroundStyle(focusText)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var brandMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            MarginaliaLabel("BRAND")
            HStack(spacing: DS.space6) {
                brandPickerMenu
                // The profile details are a disclosure, not a dump — Cosmo reads
                // the full profile on demand, so the margin only needs the name.
                if clientProfileAtom?.metadataValue(as: ClientProfileMetadata.self) != nil {
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            brandExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(DS.microIcon)
                            .foregroundStyle(focusTextMuted)
                            .rotationEffect(.degrees(brandExpanded ? 180 : 0))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(brandExpanded ? "Hide brand notes" : "Show brand notes")
                    .accessibilityLabel(brandExpanded ? "Hide brand notes" : "Show brand notes")
                }
            }
            if brandExpanded,
               let profile = clientProfileAtom,
               let meta = profile.metadataValue(as: ClientProfileMetadata.self) {
                brandVoiceBullets(meta)
                    .transition(.opacity.combined(with: .offset(y: -4)))
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
                    .font(DS.dateSerif)
                    .foregroundStyle(focusText)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(DS.microIcon)
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
        let bullets = collectBrandBullets(meta)
        if !bullets.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: DS.space6) {
                        Text("·")
                            .font(DS.footnote)
                            .foregroundStyle(DS.gilt.opacity(0.6))
                            .padding(.top, 2)
                        Text(bullet)
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(focusText)
                            .lineLimit(2)
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
            bullets.append(voice)
        }
        if let audience = meta.targetAudience, !audience.isEmpty {
            bullets.append(audience)
        }
        if let story = meta.brandStory, !story.isEmpty {
            bullets.append(story)
        }
        return bullets
    }

    private var hooksMarginaliaSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("HOOKS", countText: "\(viewModel.state.hooks.count)")
            ForEach(Array(viewModel.state.hooks.enumerated()), id: \.offset) { idx, _ in
                HStack(alignment: .top, spacing: DS.space8) {
                    Text(romanNumeral(for: idx + 1) + ".")
                        .font(DS.caption2.monospaced())
                        .foregroundStyle(DS.giltMuted)
                        .frame(width: 22, alignment: .leading)
                        .padding(.top, 2)
                    TextField("Hook", text: marginaliaHookBinding(at: idx), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(DS.caption)
                        .foregroundStyle(focusText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func marginaliaHookBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.state.hooks.indices.contains(index) else { return "" }
                return viewModel.state.hooks[index]
            },
            set: { newValue in
                guard viewModel.state.hooks.indices.contains(index) else { return }
                viewModel.state.hooks[index] = newValue
                viewModel.state.lastModified = Date()
                viewModel.state.save()
            }
        )
    }

    private func updateDraftHeadingOutline(from document: RichDocument) {
        draftHeadingOutline = RichDocumentHeadings.outline(in: document)
    }

    private func navigateToDraftHeading(_ entry: RichHeadingOutlineEntry) {
        draftNavigationTargetID = nil
        DispatchQueue.main.async {
            draftNavigationTargetID = entry.id
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
        return VStack(alignment: .center, spacing: 2) {
            HStack(spacing: DS.space8) {
                Text("\(words)")
                    .font(DS.footnote.monospaced())
                    .foregroundStyle(focusTextMuted)
                Text(words == 1 ? "word" : "words")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(focusTextMuted.opacity(0.7))
                Text("·")
                    .font(DS.footnote)
                    .foregroundStyle(DS.sepiaSubtle)
                Text("\(chars)")
                    .font(DS.footnote.monospaced())
                    .foregroundStyle(focusTextMuted)
                Text(chars == 1 ? "char" : "chars")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(focusTextMuted.opacity(0.7))
            }
            if isSelection {
                Text("selection")
                    .font(DS.caption2)
                    .foregroundStyle(DS.gilt.opacity(0.6))
                    .transition(.opacity)
            }
        }
        // Centered under the manuscript (iA-style) — clear of both margins.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, DS.space20)
        .opacity(localDraftContent.isEmpty ? 0 : 1)
        .allowsHitTesting(false)
        .animation(ProMotionSprings.snappy, value: isSelection)
    }

    private func writingAICardOverlay(in size: CGSize) -> some View {
        WritingAICardView(
            isPresented: $showWritingAICard,
            assistant: writingAIAssistant,
            contextTitle: writingAIContextTitle,
            baseContextChips: writingAIBaseChips,
            hasSelection: !selectedText.isEmpty,
            isPolishMode: isPolishModeActive,
            onSubmitPrompt: { prompt in submitWritingAI(prompt: prompt, action: nil) },
            onQuickAction: { action in submitWritingAI(action: action) },
            onReplaceSelection: { replacement in applyWritingAIReplacement(replacement) },
            onInsertBelow: { text in insertWritingAITextBelow(text) },
            onOpenReference: { reference in openWritingAIReference(reference) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, DS.space8)
        .padding(.trailing, zenMode ? DS.space24 : max(DS.space24, (size.width - 1_244) / 2 + DS.space24))
    }

    private var writingAIContextTitle: String {
        let client = clientProfileAtom?.metadataValue(as: ClientProfileMetadata.self)?.clientName
            ?? clientProfileAtom?.title
            ?? "No client"
        return "\(client) · \(WritingContentFormat.detect(from: atom).displayName) · \(viewModel.state.currentStep.label)"
    }

    private var writingAIBaseChips: [WritingAIReferenceSource] {
        var chips: [WritingAIReferenceSource] = [.currentDraft]
        if !selectedText.isEmpty { chips.append(.currentDraft) }
        if clientProfileAtom != nil { chips.append(.clientProfile) }
        if !matchedSwipeAtoms.isEmpty { chips.append(.bestPosts) }
        if sourceIdeaAtom != nil { chips.append(.source) }
        if inheritedFramework != nil { chips.append(.blueprint) }
        return chips
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
                        updateDraftHeadingOutline(from: richDoc)
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
        schedulePolishAnalysis(debounce: false)
    }

    private func debouncedPolishUpdate() {
        schedulePolishAnalysis(debounce: true)
    }

    private func schedulePolishAnalysis(debounce: Bool) {
        polishDebounceTask?.cancel()

        let text = localDraftContent
        let requestID = UUID()
        polishAnalysisRequestID = requestID

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            polishAnalysis = nil
            return
        }

        polishDebounceTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard !Task.isCancelled else { return }

            let nextAnalysis = await Task.detached(priority: .utility) {
                WritingAnalyzer.shared.analyze(text: text)
            }.value

            await MainActor.run {
                guard polishAnalysisRequestID == requestID,
                      viewModel.state.currentStep.enablesPolishHighlights,
                      !Task.isCancelled else {
                    return
                }
                polishAnalysis = nextAnalysis
            }
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
                    .foregroundStyle(focusText)
                Spacer()
                Button(action: { dismissInlineAI() }) {
                    Image(systemName: "xmark")
                        .font(DS.caption2)
                        .foregroundStyle(focusTextMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(focusBorder).frame(height: 1)

            // Body
            if inlineAssistant.isProcessing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(DS.accent)
                    Text("Generating...")
                        .font(DS.footnote)
                        .foregroundStyle(focusTextSecondary)
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
                        .foregroundStyle(focusTextSecondary)
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
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: DS.radiusMedium)
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
                .background(RoundedRectangle(cornerRadius: 6).fill(focusBorder))
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
                .background(RoundedRectangle(cornerRadius: 6).fill(focusBorder))
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
                    .foregroundStyle(focusTextSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(focusBorder))
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
        updateFocusBand()
        scheduleTypewriterScroll()
    }

    private func openWritingAI() {
        withAnimation(ProMotionSprings.snappy) {
            showWritingAICard = true
        }
    }

    private func submitWritingAI(action: WritingAIQuickAction) {
        submitWritingAI(prompt: action.prompt, action: action)
    }

    private func submitWritingAI(prompt: String, action: WritingAIQuickAction?) {
        openWritingAI()
        let request = makeWritingAIRequest(prompt: prompt, action: action)
        Task {
            await writingAIAssistant.submit(request)
        }
    }

    private func makeWritingAIRequest(prompt: String, action: WritingAIQuickAction?) -> WritingAIRequest {
        WritingAIRequest(
            prompt: prompt,
            action: action,
            selectedText: selectedText,
            selectionContext: surroundingContext() ?? "",
            draftText: localDraftContent,
            contentTitle: editableTitle,
            contentDescription: viewModel.state.contentDescription,
            contentFormat: WritingContentFormat.detect(from: atom),
            currentStep: viewModel.state.currentStep,
            clientProfileAtom: clientProfileAtom,
            sourceIdeaAtom: sourceIdeaAtom,
            matchedSwipeAtoms: matchedSwipeAtoms,
            framework: inheritedFramework,
            outline: viewModel.state.outline,
            hooks: viewModel.state.hooks
        )
    }

    private func applyWritingAIReplacement(_ replacement: String) {
        guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draftDocument = draftDocumentByReplacingSelection(with: replacement, originalText: selectedText)
        localDraftContent = draftDocument.plainText
        viewModel.state.richDraftDocument = draftDocument
        updateDraftHeadingOutline(from: draftDocument)
        draftEditedLocally = true
        triggerAutoSave()
        withAnimation(ProMotionSprings.snappy) {
            writingAIAssistant.reset()
        }
    }

    private func insertWritingAITextBelow(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draftDocument = draftDocumentByInsertingTextBelowSelection(text)
        localDraftContent = draftDocument.plainText
        viewModel.state.richDraftDocument = draftDocument
        updateDraftHeadingOutline(from: draftDocument)
        draftEditedLocally = true
        triggerAutoSave()
    }

    private func openWritingAIReference(_ reference: WritingAIReference) {
        if let atomUUID = reference.atomUUID {
            openAtomInPane(atomUUID)
            return
        }
        if let urlString = reference.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func markTypingActive() {
        guard !zenMode else { return }
        isActivelyTyping = true
        typingActivityTask?.cancel()
        typingActivityTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(ProMotionSprings.gentle) {
                    isActivelyTyping = false
                }
            }
        }
    }

    private func updateFocusBand() {
        guard focusBandMode != .off else {
            focusBandRange = nil
            return
        }
        let range = selectionInfo.range
        guard range.location != NSNotFound else {
            focusBandRange = nil
            return
        }
        focusBandRange = focusBandRange(for: range, mode: focusBandMode, in: localDraftContent)
    }

    private func focusBandRange(for range: NSRange, mode: WritingFocusBandMode, in text: String) -> NSRange? {
        let nsString = text as NSString
        guard nsString.length > 0 else { return nil }
        let safeLocation = min(max(0, range.location), max(0, nsString.length - 1))
        let safeLength = min(max(0, range.length), nsString.length - safeLocation)
        let safeRange = NSRange(location: safeLocation, length: safeLength)

        switch mode {
        case .off:
            return nil
        case .paragraph:
            return nsString.paragraphRange(for: safeRange)
        case .sentence:
            return sentenceRange(containing: safeLocation, in: nsString)
        case .block:
            return blockRange(containing: safeLocation, in: nsString)
        }
    }

    private func sentenceRange(containing location: Int, in text: NSString) -> NSRange {
        let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
        var start = paragraph.location
        var end = paragraph.location + paragraph.length

        if location > paragraph.location {
            for idx in stride(from: location - 1, through: paragraph.location, by: -1) {
                let char = text.substring(with: NSRange(location: idx, length: 1))
                if ".!?\n".contains(char) {
                    start = min(idx + 1, text.length)
                    break
                }
            }
        }

        if location < text.length {
            for idx in location..<min(text.length, paragraph.location + paragraph.length) {
                let char = text.substring(with: NSRange(location: idx, length: 1))
                if ".!?\n".contains(char) {
                    end = min(idx + 1, text.length)
                    break
                }
            }
        }

        while start < end,
              let scalar = UnicodeScalar(UInt32(text.character(at: start))),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            start += 1
        }
        return NSRange(location: start, length: max(1, end - start))
    }

    private func blockRange(containing location: Int, in text: NSString) -> NSRange {
        let full = text as String
        let stringIndex = String.Index(utf16Offset: min(location, full.utf16.count), in: full)

        let before = full[..<stringIndex]
        let after = full[stringIndex...]
        let blockStart = before.range(of: "\n\n", options: .backwards)?.upperBound ?? full.startIndex
        let blockEnd = after.range(of: "\n\n")?.lowerBound ?? full.endIndex
        let start = blockStart.utf16Offset(in: full)
        let end = blockEnd.utf16Offset(in: full)
        return NSRange(location: start, length: max(1, end - start))
    }

    private func scheduleTypewriterScroll() {
        guard zenMode || typewriterMode else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            scrollCursorToTypewriterBand()
        }
    }

    private func scrollCursorToTypewriterBand() {
        guard let scrollView = manuscriptScrollView,
              let textView = focusedEditorTextView(in: scrollView),
              let cursorRect = cursorRectInManuscript(for: textView, scrollView: scrollView) else { return }

        let visibleRect = scrollView.documentVisibleRect
        let visibleHeight = visibleRect.height
        let targetY = visibleRect.minY + visibleHeight * 0.44
        let delta = cursorRect.midY - targetY
        guard abs(delta) > 10 else { return }

        let documentHeight = scrollView.documentView?.bounds.height ?? visibleHeight
        let maxY = max(0, documentHeight - visibleHeight)
        let targetOriginY = min(max(0, visibleRect.minY + delta), maxY)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: visibleRect.minX, y: targetOriginY))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func focusedEditorTextView(in scrollView: NSScrollView) -> NSTextView? {
        guard let documentView = scrollView.documentView else { return nil }
        if let textView = scrollView.window?.firstResponder as? NSTextView,
           textView.isDescendant(of: documentView) {
            return textView
        }
        return nil
    }

    private func cursorRectInManuscript(for textView: NSTextView, scrollView: NSScrollView) -> CGRect? {
        guard !textView.string.isEmpty,
              let documentView = scrollView.documentView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }

        layoutManager.ensureLayout(for: textContainer)
        let textLength = textView.string.utf16.count
        let selectedRange = textView.selectedRange()
        let characterLocation = min(max(selectedRange.location, 0), textLength)

        let nsText = textView.string as NSString
        var usesExtraLineFragment = false
        var cursorRect: CGRect
        if characterLocation == textLength,
           textLength > 0,
           nsText.substring(with: NSRange(location: textLength - 1, length: 1)) == "\n",
           !layoutManager.extraLineFragmentRect.isEmpty {
            usesExtraLineFragment = true
            cursorRect = layoutManager.extraLineFragmentRect
        } else {
            let measuredLocation = min(characterLocation, max(textLength - 1, 0))
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: measuredLocation, length: 1),
                actualCharacterRange: nil
            )
            cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        }

        if cursorRect.isEmpty {
            cursorRect = CGRect(x: 0, y: 0, width: 1, height: textView.font?.pointSize ?? 17)
        } else if characterLocation >= textLength, !usesExtraLineFragment {
            cursorRect.origin.x = cursorRect.maxX
            cursorRect.size.width = 1
        } else {
            cursorRect.size.width = max(cursorRect.width, 1)
        }
        cursorRect.size.height = max(cursorRect.height, textView.font?.pointSize ?? 17)

        let textContainerOrigin = textView.textContainerOrigin
        let rectInTextView = cursorRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return textView.convert(rectInTextView, to: documentView)
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
        updateDraftHeadingOutline(from: draftDocument)

        triggerAutoSave()
        dismissInlineAI()
    }

    private func applyInlineAssistantDraftEdit(
        _ operation: CosmoAssistantProposalOperation
    ) async throws -> CosmoEditableOperationResult {
        guard operation.targetID == ContentContextProvider.targetID(for: atom.uuid) else {
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Target changed")
        }

        switch operation.kind {
        case .textReplacement, .structuredFieldReplacement, .textInsertion:
            guard let placement = CosmoInlineTextEditResolver.placement(for: operation, in: localDraftContent) else {
                return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Original text not found")
            }
            draftDocument = draftDocumentByReplacing(
                range: placement.range,
                in: localDraftContent,
                with: placement.replacementText
            )
            localDraftContent = draftDocument.plainText

        case .canvasPlan:
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Canvas edits need a canvas provider")
        }

        viewModel.state.draftContent = localDraftContent
        viewModel.state.richDraftDocument = draftDocument
        updateDraftHeadingOutline(from: draftDocument)
        triggerAutoSave()

        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    private func acceptInlineAssistantDraftReview(operationID: UUID) async {
        await CosmoInlineAssistantStore.shared.accept(
            operationID: operationID,
            provider: inlineAssistantContentProvider()
        )
        refreshInlineAssistantDraftReview()
    }

    private func rejectInlineAssistantDraftReview(operationID: UUID) async {
        await CosmoInlineAssistantStore.shared.reject(operationID: operationID)
        refreshInlineAssistantDraftReview()
    }

    private func refreshInlineAssistantDraftReview() {
        draftReviewProposal = CosmoInlineAssistantStore.shared.pendingProposal(
            forSurfaceID: inlineAssistantContentSurfaceID,
            targetID: inlineAssistantContentTargetID,
            activeAtomUUID: atom.uuid
        )
    }

    private var inlineAssistantContentSurfaceID: String {
        "content:\(atom.uuid)"
    }

    private var inlineAssistantContentTargetID: String {
        ContentContextProvider.targetID(for: atom.uuid)
    }

    private func inlineAssistantContentProvider() -> ContentContextProvider {
        ContentContextProvider(
            atom: atom,
            stateRef: { [viewModel] in viewModel.state },
            phaseRef: { [viewModel] in viewModel.displayPhase },
            draftTextRef: { [self] in self.localDraftContent },
            applyDraftEdit: { [self] operation in
                try await self.applyInlineAssistantDraftEdit(operation)
            }
        )
    }

    private func draftDocumentByReplacingSelection(with replacement: String, originalText: String) -> RichDocument {
        let currentPlainText = localDraftContent as NSString
        var replacementRange = selectionInfo.range

        if replacementRange.location == NSNotFound || replacementRange.location + replacementRange.length > currentPlainText.length {
            replacementRange = currentPlainText.range(of: originalText)
        } else if currentPlainText.substring(with: replacementRange) != originalText {
            replacementRange = currentPlainText.range(of: originalText)
        }

        guard replacementRange.location != NSNotFound else {
            return RichDocument.migrateLegacy(localDraftContent.replacingOccurrences(of: originalText, with: replacement))
        }

        let attributed = NSMutableAttributedString(
            attributedString: RichDocumentSerializer.attributedString(from: draftDocument, fontSize: 16, darkMode: DS.usesImmersiveFocusAppearance)
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
                    .foregroundColor: NSColor(focusText)
                ]
            )
        )
        return RichDocumentSerializer.document(from: attributed)
    }

    /// Replaces a located range (from `CosmoInlineDiffLocator`) in the rich draft while
    /// preserving surrounding formatting. Used by reviewed inline-assistant edits, which
    /// are anchored by text content rather than the live editor selection.
    private func draftDocumentByReplacing(
        range: Range<String.Index>,
        in plainText: String,
        with replacement: String
    ) -> RichDocument {
        let nsRange = NSRange(range, in: plainText)
        let attributed = NSMutableAttributedString(
            attributedString: RichDocumentSerializer.attributedString(from: draftDocument, fontSize: 16, darkMode: DS.usesImmersiveFocusAppearance)
        )
        let attributedPlainText = attributed.string as NSString

        guard nsRange.location != NSNotFound,
              nsRange.location + nsRange.length <= attributedPlainText.length else {
            let updated = (plainText as NSString).replacingCharacters(in: nsRange, with: replacement)
            return RichDocument.migrateLegacy(updated)
        }

        attributed.replaceCharacters(
            in: nsRange,
            with: NSAttributedString(
                string: replacement,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16),
                    .foregroundColor: NSColor(focusText)
                ]
            )
        )
        return RichDocumentSerializer.document(from: attributed)
    }

    private func draftDocumentByInsertingTextBelowSelection(_ text: String) -> RichDocument {
        let currentPlainText = localDraftContent as NSString
        let selectedRange = selectionInfo.range
        let insertionLocation: Int
        if selectedRange.location != NSNotFound,
           selectedRange.location + selectedRange.length <= currentPlainText.length {
            insertionLocation = selectedRange.location + selectedRange.length
        } else {
            insertionLocation = currentPlainText.length
        }

        let insertion = (insertionLocation == 0 ? "" : "\n\n") + text
        let attributed = NSMutableAttributedString(
            attributedString: RichDocumentSerializer.attributedString(from: draftDocument, fontSize: 16, darkMode: DS.usesImmersiveFocusAppearance)
        )
        let safeLocation = min(insertionLocation, attributed.length)
        attributed.replaceCharacters(
            in: NSRange(location: safeLocation, length: 0),
            with: NSAttributedString(
                string: insertion,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16),
                    .foregroundColor: NSColor(focusText)
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
        await MainActor.run {
            sourceIdeaAtom = nil
            matchedSwipeAtoms = []
            inheritedFramework = nil
            clientProfileAtom = nil
        }

        let currentAtom = (try? await AtomRepository.shared.fetch(uuid: atom.uuid)) ?? atom
        guard let metadata = currentAtom.metadataValue(as: ContentAtomMetadata.self) else { return }

        // Source idea
        if let ideaUUID = metadata.sourceIdeaUUID,
           let idea = try? await AtomRepository.shared.fetch(uuid: ideaUUID) {
            await MainActor.run { self.sourceIdeaAtom = idea }
        }

        // Matched swipes — keep every inherited reference visible in the margins.
        if let swipeUUIDs = metadata.inheritedSwipeUUIDs {
            var loaded: [Atom] = []
            for uuid in swipeUUIDs {
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

    private func handleDraftPlainTextChange(_ plainText: String) {
        guard plainText != localDraftContent else { return }
        print("[FOCUS-CONTENT] onPlainTextChange(draft) — len=\(plainText.count) preview=\"\(String(plainText.prefix(60)))\" uuid=\(atom.uuid)")
        localDraftContent = plainText
        draftEditedLocally = true
        markTypingActive()
        updateFocusBand()
        scheduleTypewriterScroll()
        triggerAutoSave()
        if isPolishModeActive { debouncedPolishUpdate() }
    }

    private func persistCurrentEditorSnapshot(reason: String) {
        autoSaveTask?.cancel()

        // Snapshot current state. CosmoDocumentEditor sends plain text on every
        // keystroke, while rich-document serialization is debounced; if they
        // diverge at close/quit time, plain text is authoritative for data safety.
        if draftDocument.plainText != localDraftContent {
            print("[FOCUS-CONTENT] \(reason) — rebuilding stale draftDocument from localDraftContent (docLen=\(draftDocument.plainText.count) vs localLen=\(localDraftContent.count))")
            draftDocument = RichDocument.migrateLegacy(localDraftContent)
            updateDraftHeadingOutline(from: draftDocument)
        }

        viewModel.state.draftContent = localDraftContent
        viewModel.state.richDraftDocument = draftDocument
        viewModel.state.lastModified = Date()

        if !cosmoWindowEnabled {
            viewModel.state.conversationHistory = writingEngine.messages
            viewModel.state.conversationSummary = writingEngine.conversationSummary
        }

        extractLessonsIfEdited()
        viewModel.saveOnClose()
    }

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

private struct ManuscriptScrollMetrics: Equatable {
    var progress: CGFloat = 0
    var thumbFraction: CGFloat = 1
    var isScrollable: Bool = false
}

private struct PremiumManuscriptScrollbar: View {
    let metrics: ManuscriptScrollMetrics

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = proxy.size.height
            let thumbHeight = max(32, trackHeight * metrics.thumbFraction)
            let travel = max(0, trackHeight - thumbHeight)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(DS.focusImmersiveTextMuted.opacity(0.10))
                    .frame(width: 2)

                Capsule()
                    .fill(DS.focusImmersiveTextMuted.opacity(0.62))
                    .frame(width: 2.5, height: thumbHeight)
                    .offset(y: travel * metrics.progress)
            }
            .frame(width: 8, height: trackHeight)
            .opacity(metrics.isScrollable ? 1 : 0)
            .animation(ProMotionSprings.gentle, value: metrics)
            .allowsHitTesting(false)
        }
        .frame(width: 8)
    }
}

private struct ScrollViewIntrospector: NSViewRepresentable {
    var onResolve: (NSScrollView) -> Void
    var onMetricsChange: (ManuscriptScrollMetrics) -> Void = { _ in }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                context.coordinator.attach(to: scrollView)
                onResolve(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onResolve = onResolve
        context.coordinator.onMetricsChange = onMetricsChange
        DispatchQueue.main.async {
            if let scrollView = nsView.enclosingScrollView {
                context.coordinator.attach(to: scrollView)
                onResolve(scrollView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onResolve: onResolve, onMetricsChange: onMetricsChange)
    }

    final class Coordinator {
        var onResolve: (NSScrollView) -> Void
        var onMetricsChange: (ManuscriptScrollMetrics) -> Void
        private weak var scrollView: NSScrollView?
        private var observers: [NSObjectProtocol] = []
        private var lastMetrics = ManuscriptScrollMetrics()

        init(
            onResolve: @escaping (NSScrollView) -> Void,
            onMetricsChange: @escaping (ManuscriptScrollMetrics) -> Void
        ) {
            self.onResolve = onResolve
            self.onMetricsChange = onMetricsChange
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func attach(to scrollView: NSScrollView) {
            if self.scrollView === scrollView {
                configure(scrollView)
                publishMetrics(for: scrollView)
                return
            }

            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            self.scrollView = scrollView
            configure(scrollView)

            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            scrollView.postsFrameChangedNotifications = true

            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let scrollView else { return }
                    self?.publishMetrics(for: scrollView)
                }
            )
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let scrollView else { return }
                    self?.publishMetrics(for: scrollView)
                }
            )

            publishMetrics(for: scrollView)
        }

        private func configure(_ scrollView: NSScrollView) {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.drawsBackground = false
        }

        private func publishMetrics(for scrollView: NSScrollView) {
            let visibleHeight = max(scrollView.documentVisibleRect.height, 1)
            let documentHeight = max(scrollView.documentView?.bounds.height ?? visibleHeight, visibleHeight)
            let scrollableDistance = max(documentHeight - visibleHeight, 0)
            let rawProgress = scrollableDistance > 0 ? scrollView.documentVisibleRect.minY / scrollableDistance : 0
            let metrics = ManuscriptScrollMetrics(
                progress: min(max(rawProgress, 0), 1),
                thumbFraction: min(max(visibleHeight / documentHeight, 0.08), 1),
                isScrollable: scrollableDistance > 1
            )
            guard metrics != lastMetrics else { return }
            lastMetrics = metrics
            onMetricsChange(metrics)
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
                self.flushTitleUpdateSync()
                self.writeToAtomSync()
            }
    }

    private var phaseChangeCancellable: AnyCancellable?

    deinit {
        autoSaveTask?.cancel()
        titleUpdateTask?.cancel()
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
                let targetUUID = notification.userInfo?["contentUUID"] as? String
                    ?? notification.userInfo?["uuid"] as? String
                if let targetUUID, targetUUID != self.atom.uuid { return }
                // Convert carousel/thread JSON to readable slide format for display.
                // New tool paths already persist rendered content; this keeps older
                // notifications safe if they still contain structured JSON.
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
                    guard ContentFocusWritePolicy.allowsWrite(
                        existingMetadata: existingMetadata,
                        snapshotLastModified: stateCopy.lastModified
                    ) else {
                        print("[FOCUS-CONTENT-VM] writeToAtom() SKIPPED stale metadata — uuid=\(atomUUID) seq=\(mySequence)")
                        return
                    }

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
                            ISO8601.string(from: Date()),
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
                guard ContentFocusWritePolicy.allowsWrite(
                    existingMetadata: existingMetadata,
                    snapshotLastModified: stateCopy.lastModified
                ) else {
                    print("[FOCUS-CONTENT-VM] writeToAtomSync() SKIPPED stale metadata — uuid=\(atomUUID)")
                    return
                }

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
                        ISO8601.string(from: Date()),
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
        flushTitleUpdateSync()
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
                            ISO8601.string(from: Date()),
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
            return ISO8601.date(from: dateStr)
        }
        return nil
    }

    var currentInheritedSwipeUUIDs: [String] {
        atom.metadataValue(as: ContentAtomMetadata.self)?.inheritedSwipeUUIDs ?? []
    }

    var currentBlueprintSwipeUUID: String? {
        atom.metadataValue(as: ContentAtomMetadata.self)?.blueprintSwipeUUID ?? currentInheritedSwipeUUIDs.first
    }

    func saveSwipeAttachments(swipeUUIDs: [String], blueprintUUID: String?) async {
        guard var freshAtom = try? await AtomRepository.shared.fetch(uuid: atom.uuid) else { return }

        var metadata = metadataDictionary(from: freshAtom.metadata)
        let orderedSwipeUUIDs = normalizedSwipeUUIDs(swipeUUIDs, blueprintUUID: blueprintUUID)
        let normalizedBlueprintUUID = orderedSwipeUUIDs.first

        metadata["inheritedSwipeUUIDs"] = orderedSwipeUUIDs.isEmpty ? nil : orderedSwipeUUIDs
        metadata["blueprintSwipeUUID"] = normalizedBlueprintUUID

        if let updatedMetadata = metadataJSONString(from: metadata) {
            freshAtom.metadata = updatedMetadata
        }

        do {
            atom = try await AtomRepository.shared.update(freshAtom)
        } catch {
            print("Content focus: saveSwipeAttachments failed: \(error)")
        }
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

    private func metadataDictionary(from metadataString: String?) -> [String: Any] {
        guard let metadataString,
              let data = metadataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private func metadataJSONString(from metadata: [String: Any]) -> String? {
        let filtered = metadata.compactMapValues { value -> Any? in
            if value is NSNull { return nil }
            return value
        }
        guard JSONSerialization.isValidJSONObject(filtered),
              let data = try? JSONSerialization.data(withJSONObject: filtered, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func normalizedSwipeUUIDs(_ swipeUUIDs: [String], blueprintUUID: String?) -> [String] {
        var ordered: [String] = []
        for uuid in swipeUUIDs where !uuid.isEmpty && !ordered.contains(uuid) {
            ordered.append(uuid)
        }

        if let blueprintUUID,
           let existingIndex = ordered.firstIndex(of: blueprintUUID) {
            ordered.remove(at: existingIndex)
            ordered.insert(blueprintUUID, at: 0)
        }

        return ordered
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
    private var pendingTitleDocument: RichDocument?
    private var pendingTitlePlainText: String?

    func updateTitle(_ newTitle: String) {
        updateTitleDocument(RichDocument.migrateLegacy(newTitle), plainTitle: newTitle)
    }

    func updateTitleDocument(_ document: RichDocument, plainTitle: String) {
        titleUpdateTask?.cancel()
        let titleDocument = RichDocumentPersistence.normalizedTitleDocument(
            document.isEmpty ? RichDocument.migrateLegacy(plainTitle) : document
        )
        let trimmed = RichDocumentPersistence.titlePlainText(from: titleDocument)
        pendingTitleDocument = titleDocument
        pendingTitlePlainText = trimmed

        titleUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s debounce
            guard !Task.isCancelled else { return }
            await persistTitleUpdate(titleDocument: titleDocument, trimmed: trimmed)
        }
    }

    private func persistTitleUpdate(titleDocument: RichDocument, trimmed: String) async {
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
                    arguments: [RichDocumentPersistence.nilIfEmpty(trimmed), fields.metadata, ISO8601.string(from: Date()), uuid]
                )
            }
            if pendingTitleDocument == titleDocument {
                pendingTitleDocument = nil
                pendingTitlePlainText = nil
            }
        } catch {
            print("❌ Content focus: title update failed: \(error)")
        }
    }

    private func flushTitleUpdateSync() {
        titleUpdateTask?.cancel()
        guard let titleDocument = pendingTitleDocument else { return }

        let trimmed = pendingTitlePlainText ?? RichDocumentPersistence.titlePlainText(from: titleDocument)
        let uuid = atom.uuid
        do {
            try CosmoDatabase.shared.write { db in
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
                    arguments: [RichDocumentPersistence.nilIfEmpty(trimmed), fields.metadata, ISO8601.string(from: Date()), uuid]
                )
            }
            pendingTitleDocument = nil
            pendingTitlePlainText = nil
        } catch {
            print("❌ Content focus: title flush failed: \(error)")
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

// MARK: - Swipe Attachment Editor

struct ContentSwipeAttachmentEditor: View {
    let currentSwipeUUIDs: [String]
    let currentBlueprintUUID: String?
    let onSave: ([String], String?) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var allSwipes: [Atom] = []
    @State private var selectedSwipeUUIDs: Set<String>
    @State private var selectedBlueprintUUID: String?
    @State private var isLoading = true
    @State private var isSaving = false

    init(
        currentSwipeUUIDs: [String],
        currentBlueprintUUID: String?,
        onSave: @escaping ([String], String?) async -> Void
    ) {
        self.currentSwipeUUIDs = currentSwipeUUIDs
        self.currentBlueprintUUID = currentBlueprintUUID
        self.onSave = onSave
        _selectedSwipeUUIDs = State(initialValue: Set(currentSwipeUUIDs))
        _selectedBlueprintUUID = State(initialValue: currentBlueprintUUID ?? currentSwipeUUIDs.first)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(DS.focusImmersiveBorder)
            searchField
            Divider().background(DS.focusImmersiveBorder)
            swipeList
            Divider().background(DS.focusImmersiveBorder)
            footer
        }
        .frame(width: 760, height: 620)
        .background(DS.focusImmersiveBackground)
        .task { await loadAllSwipes() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc.fill")
                .font(DS.navTitle.weight(.regular))
                .foregroundStyle(DS.entitySwipe)

            VStack(alignment: .leading, spacing: 2) {
                Text("Swipe References")
                    .font(DS.headline)
                    .foregroundStyle(DS.focusImmersiveText)
                Text("Choose supporting swipes and the primary blueprint.")
                    .font(DS.footnote)
                    .foregroundStyle(DS.focusImmersiveTextMuted)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(DS.buttonText.weight(.semibold))
                    .foregroundStyle(DS.focusImmersiveTextSecondary)
                    .padding(8)
                    .background(DS.focusImmersiveBorder, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(DS.callout)
                .foregroundStyle(DS.focusImmersiveTextMuted)

            TextField("Search swipes by hook, topic, creator...", text: $searchText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.focusImmersiveText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DS.focusImmersiveBorder)
    }

    private var swipeList: some View {
        ScrollView {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading swipe library...")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.focusImmersiveTextMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
            } else if filteredSwipes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(DS.pageTitle.weight(.regular))
                        .foregroundStyle(DS.focusImmersiveTextMuted)
                    Text(searchText.isEmpty ? "No swipes found" : "No swipes match '\(searchText)'")
                        .font(DS.callout)
                        .foregroundStyle(DS.focusImmersiveTextMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredSwipes, id: \.uuid) { swipe in
                        swipeRow(swipe)
                    }
                }
                .padding(12)
            }
        }
    }

    private var filteredSwipes: [Atom] {
        let search = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        return allSwipes.filter { swipe in
            guard !search.isEmpty else { return true }
            let title = (swipe.title ?? "").lowercased()
            let body = (swipe.body ?? "").lowercased()
            let hook = (swipe.researchMetadata?.hook ?? swipe.swipeAnalysis?.hookText ?? "").lowercased()
            return title.contains(search) || body.contains(search) || hook.contains(search)
        }
        .sorted { lhs, rhs in
            let lhsSelected = selectedSwipeUUIDs.contains(lhs.uuid)
            let rhsSelected = selectedSwipeUUIDs.contains(rhs.uuid)
            if lhsSelected != rhsSelected { return lhsSelected }
            let lhsIndex = currentSwipeUUIDs.firstIndex(of: lhs.uuid) ?? Int.max
            let rhsIndex = currentSwipeUUIDs.firstIndex(of: rhs.uuid) ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func swipeRow(_ swipe: Atom) -> some View {
        let isSelected = selectedSwipeUUIDs.contains(swipe.uuid)
        let isBlueprint = selectedBlueprintUUID == swipe.uuid
        let hookText = swipe.researchMetadata?.hook ?? swipe.swipeAnalysis?.hookText ?? ""

        return HStack(spacing: 12) {
            Button {
                toggleSelection(for: swipe.uuid)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(DS.title2.weight(.regular))
                    .foregroundStyle(isSelected ? DS.entityContent : DS.focusImmersiveTextMuted)
            }
            .buttonStyle(.plain)

            thumbnailView(for: swipe)

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    openAtomInPane(swipe.uuid)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(swipe.title ?? "Untitled Swipe")
                            .font(DS.buttonText)
                            .foregroundStyle(DS.focusImmersiveText)
                            .lineLimit(1)

                        if !hookText.isEmpty {
                            Text(String(hookText.prefix(100)))
                                .font(DS.footnote)
                                .foregroundStyle(DS.focusImmersiveTextSecondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let hookType = swipe.swipeAnalysis?.hookType {
                    Text(hookType.displayName)
                        .font(DS.microBadge)
                        .foregroundStyle(DS.entitySwipe)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.entitySwipe.opacity(0.12), in: Capsule())
                }
            }

            Spacer()

            Button {
                if !isSelected {
                    selectedSwipeUUIDs.insert(swipe.uuid)
                }
                selectedBlueprintUUID = swipe.uuid
            } label: {
                Text(isBlueprint ? "Blueprint" : "Set Blueprint")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(isBlueprint ? DS.textOnAccent : DS.entityContent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        isBlueprint ? DS.entityContent : DS.entityContent.opacity(0.12),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isSelected && !isBlueprint)
            .opacity(!isSelected && !isBlueprint ? 0.45 : 1)
        }
        .padding(10)
        .background(DS.focusImmersiveSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isBlueprint ? DS.entityContent.opacity(0.35) : DS.focusImmersiveBorder, lineWidth: 1)
        )
    }

    private func thumbnailView(for swipe: Atom) -> some View {
        let thumbUrl = swipe.researchMetadata?.thumbnailUrl

        return Group {
            if let urlStr = thumbUrl, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url, stableKey: swipe.uuid) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DS.focusImmersiveBorder)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.focusImmersiveBorder)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(DS.navTitle.weight(.regular))
                            .foregroundStyle(DS.focusImmersiveTextMuted)
                    )
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(.rect(cornerRadius: 6))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(selectedSwipeUUIDs.count) selected")
                .font(DS.footnote)
                .foregroundStyle(DS.focusImmersiveTextMuted)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.focusImmersiveTextSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DS.focusImmersiveBorder, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    isSaving = true
                    let orderedUUIDs = orderedSelection()
                    let blueprintUUID = orderedUUIDs.isEmpty ? nil : (selectedBlueprintUUID ?? orderedUUIDs.first)
                    await onSave(orderedUUIDs, blueprintUUID)
                    isSaving = false
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DS.textOnAccent)
                    }
                    Text("Save References")
                        .font(DS.buttonText.weight(.semibold))
                        .foregroundStyle(DS.textOnAccent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DS.entityContent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func loadAllSwipes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let research = try await AtomRepository.shared.fetchAll(type: .research)
            allSwipes = research.filter { $0.isSwipeFileAtom }
        } catch {
            print("ContentSwipeAttachmentEditor: failed to load swipes: \(error)")
        }
    }

    private func toggleSelection(for uuid: String) {
        if selectedSwipeUUIDs.contains(uuid) {
            selectedSwipeUUIDs.remove(uuid)
            if selectedBlueprintUUID == uuid {
                selectedBlueprintUUID = selectedSwipeUUIDs.first
            }
        } else {
            selectedSwipeUUIDs.insert(uuid)
            if selectedBlueprintUUID == nil {
                selectedBlueprintUUID = uuid
            }
        }
    }

    private func orderedSelection() -> [String] {
        let currentOrder = currentSwipeUUIDs + allSwipes.map(\.uuid)
        let ordered = currentOrder.reduce(into: [String]()) { result, uuid in
            guard selectedSwipeUUIDs.contains(uuid), !result.contains(uuid) else { return }
            result.append(uuid)
        }

        let blueprintUUID = selectedBlueprintUUID ?? ordered.first
        guard let blueprintUUID, ordered.contains(blueprintUUID) else { return ordered }
        return [blueprintUUID] + ordered.filter { $0 != blueprintUUID }
    }

    private func openAtomInPane(_ uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid, "asPane": true]
        )
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
class ContentContextProvider: CosmoContextProvider, CosmoEditableSurfaceProvider {
    private let atom: Atom
    private let stateRef: () -> ContentFocusModeState
    private let phaseRef: () -> ContentPhase
    private let draftTextRef: (() -> String)?
    private let applyDraftEdit: ((CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult)?

    init(
        atom: Atom,
        stateRef: @escaping () -> ContentFocusModeState,
        phaseRef: @escaping () -> ContentPhase,
        draftTextRef: (() -> String)? = nil,
        applyDraftEdit: ((CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult)? = nil
    ) {
        self.atom = atom
        self.stateRef = stateRef
        self.phaseRef = phaseRef
        self.draftTextRef = draftTextRef
        self.applyDraftEdit = applyDraftEdit
    }

    var contextType: CosmoContextType { .contentFocusMode }

    var surfaceID: String {
        "content:\(atom.uuid)"
    }

    static func targetID(for atomUUID: String) -> String {
        "content:\(atomUUID):draft"
    }

    var contextSummary: String {
        let phase = phaseRef()
        return "Content: \(atom.title ?? "Untitled") — \(phase.displayName)"
    }

    var contextData: CosmoContextData {
        let state = stateRef()
        let phase = phaseRef()
        let draftText = currentDraftText(state: state)
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
        if !draftText.isEmpty {
            viewData["draftWordCount"] = "\(draftText.split(separator: " ").count)"
            viewData["draftExcerpt"] = String(draftText.prefix(500))
        }

        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "content",
            currentAtomTitle: atom.title,
            activeClientUUID: state.clientProfileUUID,
            viewSpecificData: viewData
        )
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        let state = stateRef()
        let draftText = currentDraftText(state: state)
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: Self.targetID(for: atom.uuid),
            kind: .text,
            title: atom.title ?? "Untitled content",
            text: draftText,
            sourceHash: CosmoEditableSurfaceHasher.hash(draftText),
            anchors: [
                .init(id: "draft", label: "Draft", utf16Start: 0, utf16Length: draftText.utf16.count)
            ]
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard let applyDraftEdit else {
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Content editor is unavailable")
        }
        return try await applyDraftEdit(operation)
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }

    private func currentDraftText(state: ContentFocusModeState) -> String {
        draftTextRef?() ?? state.draftContent
    }

    var availableActions: [CosmoWindowAction] {
        [
            CosmoWindowAction(
                id: "content-insert-draft",
                name: "Insert into Draft",
                description: "Insert into the current draft editor at the cursor.",
                modelTier: .balanced
            ) { prompt in
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Nothing inserted." }
                await EditorCommandBus.shared.insertText(trimmed, at: .cursor, allowInactive: true)
                return "Inserted into the draft."
            },
            CosmoWindowAction(
                id: "content-append-draft",
                name: "Append to Draft",
                description: "Append a new paragraph to the draft.",
                modelTier: .balanced
            ) { prompt in
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Nothing appended." }
                await EditorCommandBus.shared.insertText(trimmed, at: .newParagraph, allowInactive: true)
                return "Appended to the draft."
            }
        ]
    }
}

// MARK: - Preference Key for draft editor position tracking

private struct DraftEditorFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
