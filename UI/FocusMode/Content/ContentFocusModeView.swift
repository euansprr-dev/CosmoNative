// CosmoOS/UI/FocusMode/Content/ContentFocusModeView.swift
// Main Content Focus Mode container - 3-step workflow (Brainstorm → Draft → Polish)
// February 2026

import SwiftUI
import Combine
import GRDB

// MARK: - Content Focus Mode View

/// Main container for Content Focus Mode.
/// Routes between 3 workflow steps with a persistent step indicator in the top bar.
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

    // Feature flag: when true, the embedded AI Collaborator is hidden (replaced by global Cosmo window)
    @AppStorage("cosmoWindowEnabled") private var cosmoWindowEnabled = true

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

            // Main content — editor takes center stage
            VStack(spacing: 0) {
                // Top bar spacer — matches the fixed header height
                Spacer().frame(height: 72)

                // Full-width step content (no context panel)
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Unified bottom navigation bar
                unifiedBottomBar
            }

            // Top bar overlay (fixed)
            VStack {
                topBar
                Spacer()
            }
            .zIndex(10)

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
        .onAppear {
            viewModel.loadState()
            viewModel.startObservingState()
            Task {
                await viewModel.searchRelatedAtoms()
            }
            // Register context provider for global Cosmo window
            let provider = ContentContextProvider(atom: atom, stateRef: { [viewModel] in viewModel.state }, phaseRef: { [viewModel] in viewModel.displayPhase })
            CosmoWindowViewModel.shared.updateContext(provider: provider)
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

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        if ContentFocusModeState.stepForPhase(viewModel.displayPhase) != nil {
            // Creation phase -- use existing step routing
            creationStepContent
        } else {
            // Post-creation phase — main content + context sidebar
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

    @ViewBuilder
    private var creationStepContent: some View {
        switch viewModel.state.currentStep {
        case .brainstorm:
            ContentBrainstormView(
                state: $viewModel.state,
                atom: atom,
                writingEngine: cosmoWindowEnabled ? nil : writingEngine,
                onNext: {
                    viewModel.goToStep(.draft)
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

        case .draft:
            ContentDraftView(
                state: $viewModel.state,
                atom: atom,
                editableTitle: $editableTitle,
                selectedText: $selectedText,
                writingEngine: cosmoWindowEnabled ? nil : writingEngine,
                onBack: {
                    viewModel.goToStep(.brainstorm)
                },
                onNext: {
                    viewModel.goToStep(.polish)
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

        case .polish:
            ContentPolishView(
                state: $viewModel.state,
                atom: atom,
                onBack: {
                    viewModel.goToStep(.draft)
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }

    // MARK: - Unified Bottom Navigation Bar

    private var unifiedBottomBar: some View {
        HStack(spacing: 12) {
            // Left: Back button — ghost style (hidden on first phase)
            if let prevPhase = viewModel.displayPhase.previousPhase {
                Button {
                    viewModel.goToPhase(prevPhase)
                } label: {
                    backButtonLabel(prevPhase)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 120, height: 1)
            }

            Spacer()

            // Center: Phase name — 12px, DS.textMuted, 0.02em tracking
            Text(viewModel.displayPhase.displayName)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DS.textMuted)
                .tracking(0.24)

            // Word + character count — selection-aware
            if !viewModel.state.draftContent.isEmpty {
                let textToCount = selectedText.isEmpty ? viewModel.state.draftContent : selectedText
                let words = textToCount.split(whereSeparator: \.isWhitespace).count
                let chars = textToCount.count
                Text("\(words) words · \(chars) chars")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(DS.textMuted)
            }

            Spacer()

            // AI Collaborator toggle — hidden when global Cosmo window is enabled
            if !cosmoWindowEnabled {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        showAICollaborator.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                        Text("AI")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(DS.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(showAICollaborator ? DS.accent.opacity(0.15) : DS.accentSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.accent.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Right: Advance phase button — DS.accent solid, white text, glow
            if let nextPhase = viewModel.displayPhase.nextPhase {
                Button {
                    viewModel.goToPhase(nextPhase)
                } label: {
                    nextButtonLabel(nextPhase)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 120, height: 1)
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

    /// Back button — ghost style: transparent bg, 1px DS.border, DS.textSecondary text
    @ViewBuilder
    private func backButtonLabel(_ phase: ContentPhase) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left")
                .font(.system(size: 12, weight: .medium))
            Text(phase.displayName)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(DS.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    /// Advance button — DS.accent solid bg, white text, weight 500, accentGlow shadow 16px
    @ViewBuilder
    private func nextButtonLabel(_ phase: ContentPhase) -> some View {
        HStack(spacing: 6) {
            Text(phase.displayName)
                .font(.system(size: 12, weight: .medium))
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.accent)
        )
        .shadow(color: DS.accentGlow, radius: 16)
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

            // Pipeline bar
            ContentPipelineBar(
                currentPhase: viewModel.displayPhase,
                reachedPhase: viewModel.currentPhase,
                phaseEnteredAt: viewModel.phaseEnteredAt,
                onPhaseSelected: { phase in
                    viewModel.goToPhase(phase)
                }
            )

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
                guard let self else { return }
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
