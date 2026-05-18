// CosmoOS/UI/FocusMode/Connection/ConnectionFocusModeView.swift
// Main Connection Focus Mode view - canvas with structured concept card
// 11 sections with items, ghost suggestions, and connected sources
// December 2025 - Complete rewrite following PRD spec

import SwiftUI
import Combine
import GRDB

// MARK: - Connection Focus Mode View

@MainActor
final class ConnectionCollaboratorPreviewStore: ObservableObject {
    @Published private(set) var streamingDraft: ConnectionDraftProposal?
    @Published private(set) var sourceMessageID: UUID?
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var nextChunkIndex: Int = 0

    func begin(draft: ConnectionDraftProposal, sourceMessageID: UUID?) {
        streamingDraft = draft
        self.sourceMessageID = sourceMessageID
        isPaused = false
        isStreaming = true
        nextChunkIndex = 0
    }

    func updateVisibleText(_ text: String, nextChunkIndex: Int) {
        guard var draft = streamingDraft else { return }
        draft.visibleText = text
        draft.status = .streaming
        streamingDraft = draft
        self.nextChunkIndex = nextChunkIndex
        isStreaming = true
        isPaused = false
    }

    func pause() {
        guard var draft = streamingDraft else { return }
        draft.status = .pending
        streamingDraft = draft
        isStreaming = false
        isPaused = true
    }

    func clear() {
        streamingDraft = nil
        sourceMessageID = nil
        isPaused = false
        isStreaming = false
        nextChunkIndex = 0
    }
}

/// Main view for Connection Focus Mode.
/// Displays an infinite canvas with an anchored structured concept card,
/// floating panels from the database, and ghost suggestions from AI.
struct ConnectionFocusModeView: View {
    private enum CommandKIntent {
        case floatingBlock
        case wellSource
    }

    // MARK: - Properties

    /// The connection atom being displayed
    let atom: Atom

    /// Callback to close focus mode
    let onClose: () -> Void

    // MARK: - State

    @StateObject private var viewModel: ConnectionFocusModeViewModel
    @StateObject private var panelManager: FloatingPanelManager
    @StateObject private var focusConnectManager = FocusConnectManager()
    @StateObject private var floatingBlocksManager: FocusFloatingBlocksManager
    @State private var viewportState = CanvasViewportState()
    @State private var showCommandK = false
    @State private var activeRelationArea: RelationAreaState?
    @State private var rightClickMonitor: Any?
    @State private var viewFrameInWindow: CGRect = .zero
    @State private var editableTitle: String
    @State private var titleDocument: RichDocument = .empty
    @StateObject private var coDevEngine = ConnectionCoDevEngine()

    // MARK: - V2 "The Crucible" state

    @State private var collaboratorEngine = ConceptCollaboratorEngine()
    @State private var wellSources: [Atom] = []
    @State private var suggestedWellSources: [Atom] = []
    @State private var isLoadingSuggestedSources: Bool = false
    @State private var isShowingSuggestedSources: Bool = false
    @State private var isRefreshingInsights: Bool = false
    @State private var draftStreamingTask: Task<Void, Never>?
    @StateObject private var collaboratorPreview = ConnectionCollaboratorPreviewStore()
    @State private var commandKIntent: CommandKIntent = .floatingBlock
    // V2 mode overlays — Manuscript (⌘M), Chalkboard (⌘B), Station Mode (double-click station).
    @State private var manuscriptActive: Bool = false
    @State private var chalkboardActive: Bool = false
    @State private var stationModeType: ConnectionSectionType?
    /// V3: id of the currently-selected block on the Connection canvas.
    /// Format: `"atom:<floatingBlockId>"` for user-added atoms; intrinsic
    /// panels adopted in Phase 1b. Nil = no selection.
    @State private var selectedBlockId: String?
    /// V3: atom UUIDs created via the radial menu on this canvas. On ⌫ these
    /// are soft-deleted (not just unlinked). Pre-existing atoms dragged onto
    /// the canvas are NOT in this set — ⌫ just unlinks them.
    @State private var canvasCreatedAtomUUIDs: Set<String> = []
    /// V3 Phase 3: space-hold pan mode. When true, block drag is suppressed so
    /// drags flow to `InfiniteCanvasView`'s pan gesture. Tracked via an
    /// NSEvent local monitor on `.flagsChanged` + keyDown/keyUp.
    @State private var isSpacePanHeld: Bool = false
    @State private var spaceMonitor: Any?

    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        let initialTitleDocument = RichDocumentPersistence.loadAtomDocument(
            field: .title,
            metadata: atom.metadata,
            fallbackPlainText: atom.title ?? "New Connection"
        )
        self._editableTitle = State(initialValue: RichDocumentPersistence.titlePlainText(from: initialTitleDocument))
        self._titleDocument = State(initialValue: initialTitleDocument)
        self._viewModel = StateObject(wrappedValue: ConnectionFocusModeViewModel(atom: atom))
        self._panelManager = StateObject(wrappedValue: FloatingPanelManager(focusAtomUUID: atom.uuid))
        self._floatingBlocksManager = StateObject(wrappedValue: FocusFloatingBlocksManager(ownerAtomUUID: atom.uuid))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Main canvas area
            ZStack {
                // Infinite canvas with dotted grid background
                InfiniteCanvasView(
                    viewportState: $viewportState,
                    showGrid: true,
                    anchoredContent: {
                        anchoredConnectionCard
                    },
                    floatingContent: {
                        floatingPanelsLayer
                    }
                )

                // Focus connection lines layer (universal linking)
                FocusConnectionLinesLayer(
                    connectManager: focusConnectManager,
                    focusAtomUUID: atom.uuid
                )

                // Relation area overlay for dropped blocks
                if let relationState = activeRelationArea {
                    RelationAreaOverlayCard(
                        state: relationState,
                        onDismiss: {
                            withAnimation(ProMotionSprings.snappy) {
                                activeRelationArea = nil
                            }
                        },
                        onChipTap: { sectionType in
                            handleChipTap(sectionType, state: relationState)
                        }
                    )
                }

                // Top bar overlay
                VStack {
                    topBar
                    Spacer()
                }

                // Radial menu (on right-click)
                if let menuPosition = viewModel.radialMenuPosition {
                    RadialMenuView(
                        position: menuPosition,
                        onSelect: handleRadialAction,
                        onDismiss: {
                            viewModel.radialMenuPosition = nil
                        }
                    )
                }
            }
            .focusBlockContextMenu(
                manager: floatingBlocksManager,
                ownerAtomUUID: atom.uuid
            )
        }
        .focusBlockInspector(manager: floatingBlocksManager)
        // The governed workspace is anchored; user-added atom blocks still
        // float on the canvas around it.
        .overlay(alignment: .topTrailing) {
            if isPaneContext {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(DS.buttonText)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 28, height: 28)
                        .background(DS.border, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, DS.space16)
                .padding(.top, DS.space16)
            }
        }
        // V2 mode overlays — Chalkboard mood, Manuscript reading, Station Mode zoom.
        .overlay {
            ChalkboardModeOverlay(isActive: chalkboardActive) {
                withAnimation(ProMotionSprings.focusTransition) { chalkboardActive = false }
            }
        }
        .overlay {
            if manuscriptActive {
                ManuscriptModeView(
                    title: editableTitle,
                    conceptType: viewModel.state.conceptType,
                    sections: viewModel.state.sections,
                    onDismiss: {
                        withAnimation(ProMotionSprings.focusTransition) { manuscriptActive = false }
                    }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if let type = stationModeType, let binding = stationBinding(for: type) {
                StationModeOverlay(
                    section: binding,
                    onAddItem: { doc, text in
                        pauseActiveDraftIfNeeded(for: type)
                        viewModel.addItem(document: doc, plainText: text, toSection: type)
                    },
                    onEditItem: { item in
                        pauseActiveDraftIfNeeded(for: type)
                        viewModel.editItem(item, inSection: type)
                    },
                    onDeleteItem: { id in
                        pauseActiveDraftIfNeeded(for: type)
                        viewModel.deleteItem(id, fromSection: type)
                    },
                    onSourceTap: { uuid in openSourceAsPanel(uuid) },
                    onAcceptGhost: { ghost in viewModel.acceptGhost(ghost, inSection: type) },
                    onDismissGhost: { id in viewModel.dismissGhost(id, inSection: type) },
                    onDismiss: {
                        withAnimation(ProMotionSprings.focusTransition) { stationModeType = nil }
                    }
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
            loadState()
            viewModel.normalizeCollaboratorState()
            listenForAtomPicker()
            setupRightClickMonitor()
            setupSpaceMonitor()
            Task {
                await viewModel.generateGhostSuggestions()
                await loadAtelierData()
                await bootstrapCollaboratorIfNeeded()
            }
            // Register context provider for global Cosmo window
            let provider = ConnectionContextProvider(atom: atom, viewModel: viewModel)
            if !isPaneContext || isPaneContextOwner {
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onChange(of: viewModel.state.completedSectionCount) { oldValue, newValue in
            if oldValue == 0,
               newValue > 0,
               viewModel.state.collaboratorMessages.isEmpty,
               !viewModel.state.collaboratorSession.hasBootstrapped {
                Task { await bootstrapCollaboratorIfNeeded() }
            }
        }
        .onChange(of: isPaneContextOwner) { _, isOwner in
            if isOwner {
                let provider = ConnectionContextProvider(atom: atom, viewModel: viewModel)
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateViewFrameInWindow(geo.frame(in: .global)) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        updateViewFrameInWindow(newFrame)
                    }
            }
        )
        .onDisappear {
            print("[FOCUS-CONN] onDisappear — uuid=\(atom.uuid) title=\"\(String(editableTitle.prefix(60)))\" sectionsCount=\(viewModel.state.sections.count)")
            draftStreamingTask?.cancel()
            collaboratorPreview.clear()
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
            viewModel.flushTitleSave(titleDocument, plainTitle: editableTitle)
            viewModel.saveToAtom()
            saveState()
            floatingBlocksManager.saveImmediately()
            draftStreamingTask?.cancel()
            removeRightClickMonitor()
            removeSpaceMonitor()
        }
        // Deselect panels on background click
        .onTapGesture(count: 1) {
            panelManager.deselectAll()
            selectedBlockId = nil
            if activeRelationArea != nil {
                // Dismiss relation area on background tap
                withAnimation(ProMotionSprings.snappy) {
                    activeRelationArea = nil
                }
            }
        }
        // V3: route selection into the floating blocks manager so the
        // underlying block views (StickyNoteBlockView, NoteBlockView, etc.)
        // pick up the highlight via their CanvasBlock.isSelected binding.
        .onChange(of: selectedBlockId) { _, newValue in
            let atomBlockId: String?
            if let value = newValue, value.hasPrefix("atom:") {
                atomBlockId = String(value.dropFirst("atom:".count))
            } else {
                atomBlockId = nil
            }
            floatingBlocksManager.setSelected(atomBlockId)
        }
        // Keyboard shortcuts
        .onKeyPress(.escape) {
            // V3: clear selection first if something is selected.
            if selectedBlockId != nil {
                selectedBlockId = nil
                return .handled
            }
            // V2 mode overlays dismiss first — a sequence of nested exits.
            if stationModeType != nil {
                withAnimation(ProMotionSprings.focusTransition) { stationModeType = nil }
                return .handled
            }
            if manuscriptActive {
                withAnimation(ProMotionSprings.focusTransition) { manuscriptActive = false }
                return .handled
            }
            if chalkboardActive {
                withAnimation(ProMotionSprings.focusTransition) { chalkboardActive = false }
                return .handled
            }
            if activeRelationArea != nil {
                activeRelationArea = nil
                return .handled
            }
            if viewModel.radialMenuPosition != nil {
                viewModel.radialMenuPosition = nil
                return .handled
            }
            if showCommandK {
                showCommandK = false
                return .handled
            }
            onClose()
            return .handled
        }
        .onKeyPress { keyPress in
            if keyPress.characters == "k" && keyPress.modifiers.contains(.command) {
                showCommandK = true
                return .handled
            }
            // V3: ⌫ / delete deletes the currently-selected canvas block.
            if keyPress.key == .delete || keyPress.key == .deleteForward {
                if deleteSelectedBlock() { return .handled }
            }
            // V2 mode shortcuts — ⌘M Manuscript, ⌘B Chalkboard, ⌘F Forge (reset).
            if keyPress.modifiers.contains(.command) {
                switch keyPress.characters {
                case "m":
                    withAnimation(ProMotionSprings.focusTransition) {
                        manuscriptActive.toggle()
                        if manuscriptActive { chalkboardActive = false; stationModeType = nil }
                    }
                    return .handled
                case "b":
                    withAnimation(ProMotionSprings.focusTransition) {
                        chalkboardActive.toggle()
                    }
                    return .handled
                case "f":
                    withAnimation(ProMotionSprings.focusTransition) {
                        manuscriptActive = false
                        chalkboardActive = false
                        stationModeType = nil
                    }
                    return .handled
                case "r" where keyPress.modifiers.contains(.shift):
                    // V3: ⌘⇧R — Restore Crucible Arrangement.
                    // Clears free-placement station positions and V3 canvas positions
                    // so blocks snap back to their default layout.
                    withAnimation(ProMotionSprings.focusTransition) {
                        viewModel.state.clearStationPositions()
                        viewModel.state.clearCanvasPositions()
                    }
                    return .handled
                default: break
                }
            }
            return .ignored
        }
        .sheet(isPresented: $showCommandK) {
            CommandKView()
                .frame(minWidth: 900, minHeight: 600)
        }
        // Cmd+K single-click: add as floating block
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.addItemToCurrentCanvas)) { notification in
            guard let uuid = notification.userInfo?["atomUUID"] as? String else { return }
            let title = notification.userInfo?["title"] as? String ?? "Untitled"
            let typeRaw = notification.userInfo?["atomType"] as? String ?? AtomType.idea.rawValue
            let atomType = AtomType(rawValue: typeRaw) ?? .idea
            showCommandK = false
            handleCommandKSelection(atomUUID: uuid, title: title, atomType: atomType)
        }
    }

    // MARK: - Anchored Connection Content

    private var anchoredConnectionCard: some View {
        ConnectionStructuredWorkspaceView(
            title: Binding(
                get: { editableTitle },
                set: { newValue in
                    editableTitle = newValue
                    titleDocument = RichDocument.migrateLegacy(newValue)
                    viewModel.updateTitleDocument(titleDocument, plainTitle: newValue)
                }
            ),
            conceptType: $viewModel.state.conceptType,
            state: Binding(
                get: { viewModel.state },
                set: { viewModel.state = $0 }
            ),
            collaboratorMessages: Binding(
                get: { viewModel.state.collaboratorMessages },
                set: { viewModel.state.collaboratorMessages = $0 }
            ),
            activeDraftProposal: Binding(
                get: { viewModel.state.activeDraftProposal },
                set: { viewModel.state.activeDraftProposal = $0 }
            ),
            previewStore: collaboratorPreview,
            frameworkTitle: editableTitle,
            isCollaboratorThinking: collaboratorEngine.isThinking,
            insights: viewModel.state.liveInsights,
            isRefreshingInsights: isRefreshingInsights,
            sourceCount: wellSources.count,
            linkedSourceCount: wellSources.count,
            maturityLabel: maturityThresholdLabel,
            sources: wellSources,
            suggestedSources: suggestedWellSources,
            whispersBySource: whispersBySource,
            contributionsBySource: contributionsBySource,
            isShowingSuggestions: isShowingSuggestedSources,
            isLoadingSuggestions: isLoadingSuggestedSources,
            onAddItem: { document, plainText, type in
                pauseActiveDraftIfNeeded(for: type)
                viewModel.addItem(document: document, plainText: plainText, toSection: type)
            },
            onEditItem: { item, type in
                pauseActiveDraftIfNeeded(for: type)
                viewModel.editItem(item, inSection: type)
            },
            onDeleteItem: { id, type in
                pauseActiveDraftIfNeeded(for: type)
                viewModel.deleteItem(id, fromSection: type)
            },
            onSourceTap: { openSourceAsPanel($0) },
            onAcceptGhost: { ghost, type in
                viewModel.acceptGhost(ghost, inSection: type)
            },
            onDismissGhost: { id, type in
                viewModel.dismissGhost(id, inSection: type)
            },
            onEnterStationMode: { type in
                withAnimation(ProMotionSprings.focusTransition) {
                    stationModeType = type
                }
            },
            onTitleCommit: { _ in
                viewModel.flushTitleSave(titleDocument, plainTitle: editableTitle)
            },
            onSendMessage: { text in Task { await handleCollaboratorSend(text) } },
            onCrystallizeMessage: { message in handleCollaboratorCrystallize(message) },
            onInsertDraft: { draft in acceptDraftProposal(draft) },
            onReviseDraft: { draft in Task { await reviseDraftProposal(draft) } },
            onMoveDraft: { draft, section in moveDraftProposal(draft, to: section) },
            onDismissDraft: { draft in dismissDraftProposal(draft) },
            onResumeDraft: { draft in resumeDraftProposal(draft) },
            onUseLinkedSources: { Task { await askCollaboratorToUseLinkedSources() } },
            onRefreshInsights: { },
            onDismissInsight: { id in
                viewModel.state.liveInsights.removeAll { $0.id == id }
            },
            onAddSource: { handleAddSource() },
            onRequestSuggestions: { Task { await loadSuggestedWellSources() } },
            onLinkSuggestedSource: { source in
                Task { await linkSourceToConnection(source) }
            },
            onRefreshWhispers: { sourceUUID in
                Task { await regenerateWhispers(forSource: sourceUUID) }
            },
            onAcceptWhisper: { ghost in
                viewModel.acceptGhost(ghost, inSection: ghost.targetSectionType)
            },
            onDismissWhisper: { id in
                for section in viewModel.state.sections {
                    if section.ghostSuggestions.contains(where: { $0.id == id }) {
                        viewModel.dismissGhost(id, inSection: section.type)
                    }
                }
            },
            onHoverSource: { _ in }
        )
        .environment(\.connectionSpacePanActive, isSpacePanHeld)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
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
                    HStack(spacing: DS.space6) {
                        Image(systemName: "chevron.left")
                            .font(DS.buttonText)
                        Text("Back")
                            .font(DS.callout)
                    }
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space8)
                    .background(DS.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Type badge (right next to back button)
            HStack(spacing: DS.space4) {
                Image(systemName: "link.circle.fill")
                    .font(DS.caption2)
                Text("Connection")
                    .font(DS.smallCaps)
            }
            .foregroundStyle(DS.entityConnection)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(DS.entityConnection.opacity(DS.opacitySubtle), in: Capsule())

            Spacer()
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
        .background(
            LinearGradient(
                colors: [
                    DS.bg.opacity(0.95),
                    DS.bg.opacity(0.8),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Well/Atelier computed data

    private var whispersBySource: [String: [GhostSuggestion]] {
        var out: [String: [GhostSuggestion]] = [:]
        for section in viewModel.state.sections {
            for ghost in section.ghostSuggestions {
                out[ghost.sourceAtomUUID, default: []].append(ghost)
            }
        }
        return out
    }

    private var contributionsBySource: [String: Set<ConnectionSectionType>] {
        var out: [String: Set<ConnectionSectionType>] = [:]
        for section in viewModel.state.sections {
            for item in section.items {
                if let uuid = item.sourceAtomUUID {
                    out[uuid, default: []].insert(section.type)
                }
            }
        }
        return out
    }

    private var maturityThresholdLabel: String {
        switch viewModel.state.completedSectionCount {
        case 0...2: return "SEED"
        case 3...4: return "SAPLING"
        case 5...7: return "MATURE"
        default: return "PROVEN"
        }
    }

    // MARK: - Well/Atelier handlers

    private func handleAddSource() {
        commandKIntent = .wellSource
        showCommandK = true
    }

    private func handleCommandKSelection(atomUUID: String, title: String, atomType: AtomType) {
        defer { commandKIntent = .floatingBlock }

        if commandKIntent == .wellSource, isEligibleWellSourceType(atomType) {
            Task {
                guard let source = try? await AtomRepository.shared.fetch(uuid: atomUUID) else { return }
                await linkSourceToConnection(source)
            }
            return
        }

        floatingBlocksManager.addBlock(
            linkedAtomUUID: atomUUID,
            linkedAtomType: atomType,
            title: title,
            position: CGPoint(x: 200, y: 200)
        )
    }

    private func isEligibleWellSourceType(_ type: AtomType) -> Bool {
        switch type {
        case .research, .idea, .content, .note, .connection:
            return true
        default:
            return false
        }
    }

    private func regenerateWhispers(forSource _: String) async {
        // Per-source whisper regeneration — Phase 2 currently falls back to the
        // full-graph refresh. GhostSuggestionEngine.generateWhispers(forSource:)
        // is the Phase 3 entry point when we add the specialized API.
        await viewModel.generateGhostSuggestions()
    }

    @MainActor
    private func loadSuggestedWellSources() async {
        isShowingSuggestedSources = true
        isLoadingSuggestedSources = true
        let linkedIDs = Set(wellSources.map(\.uuid))
        var suggestionSeed = atom
        suggestionSeed.title = editableTitle
        let suggestions = await coDevEngine.findSourceMaterials(for: suggestionSeed, limit: 8)
            .filter { !linkedIDs.contains($0.uuid) }
        suggestedWellSources = suggestions
        isLoadingSuggestedSources = false
    }

    @MainActor
    private func linkSourceToConnection(_ source: Atom) async {
        var updatedSource = source
        let hasConnectionLink = updatedSource.linksList.contains {
            $0.uuid == atom.uuid &&
            ($0.entityType == AtomType.connection.rawValue ||
             $0.type == AtomLinkType.connection.rawValue ||
             $0.type == AtomLinkType.related.rawValue)
        }

        if !hasConnectionLink {
            updatedSource = updatedSource.addingLink(.related(atom.uuid, entityType: .connection))
            try? await AtomRepository.shared.update(updatedSource)
        }

        if var updatedConnection = try? await AtomRepository.shared.fetch(uuid: atom.uuid) {
            let hasSourceLink = updatedConnection.linksList.contains { $0.uuid == source.uuid }
            if !hasSourceLink {
                updatedConnection = updatedConnection.addingLink(.related(source.uuid, entityType: source.type))
                try? await AtomRepository.shared.update(updatedConnection)
            }
        }

        suggestedWellSources.removeAll { $0.uuid == source.uuid }
        await loadAtelierData()
        await viewModel.generateGhostSuggestions()
    }

    @MainActor
    private func loadAtelierData() async {
        wellSources = await coDevEngine.findLinkedSourceMaterials(for: atom.uuid, limit: 20)
        if isShowingSuggestedSources {
            let linkedIDs = Set(wellSources.map(\.uuid))
            suggestedWellSources.removeAll { linkedIDs.contains($0.uuid) }
        }
    }

    @MainActor
    private func bootstrapCollaboratorIfNeeded() async {
        guard !viewModel.state.collaboratorSession.hasBootstrapped else { return }
        if !viewModel.state.collaboratorMessages.isEmpty {
            viewModel.state.collaboratorSession.presetID = "deepen.connection"
            viewModel.state.collaboratorSession.hasBootstrapped = true
            viewModel.state.collaboratorSession.lastBootstrapAt = viewModel.state.collaboratorSession.lastBootstrapAt ?? Date()
            return
        }

        guard viewModel.state.completedSectionCount > 0 else { return }

        let bootstrapPrompt = """
        Read what is already written in this connection and the linked sources. Start from that material. Ask one sharp follow-up question or stage one additive draft for the most useful next section.
        """

        let reply = await collaboratorEngine.ask(
            prompt: bootstrapPrompt,
            frameworkTitle: editableTitle,
            conceptType: viewModel.state.conceptType,
            state: viewModel.state,
            linkedSources: wellSources,
            history: viewModel.state.collaboratorMessages,
            isBootstrap: true
        )
        viewModel.state.markCollaboratorBootstrapped()
        appendCollaboratorReply(reply, persistState: false)
    }

    @MainActor
    private func handleCollaboratorSend(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        viewModel.state.markCollaboratorBootstrapped()
        let userMessage = CollaboratorMessage(role: .user, text: trimmed)
        viewModel.state.appendCollaboratorMessage(userMessage)
        viewModel.saveState()

        let reply = await collaboratorEngine.ask(
            prompt: trimmed,
            frameworkTitle: editableTitle,
            conceptType: viewModel.state.conceptType,
            state: viewModel.state,
            linkedSources: wellSources,
            history: viewModel.state.collaboratorMessages
        )
        appendCollaboratorReply(reply)
    }

    @MainActor
    private func askCollaboratorToUseLinkedSources() async {
        guard !wellSources.isEmpty else { return }
        await handleCollaboratorSend("Use the linked sources to help me develop this connection.")
    }

    /// Binding into a specific section by type — for Station Mode overlay.
    private func stationBinding(for type: ConnectionSectionType) -> Binding<ConnectionSection>? {
        guard viewModel.state.sections.firstIndex(where: { $0.type == type }) != nil else { return nil }
        return Binding(
            get: {
                viewModel.state.sections.first(where: { $0.type == type })
                    ?? ConnectionSection(type: type)
            },
            set: { newValue in
                if let idx = viewModel.state.sections.firstIndex(where: { $0.type == type }) {
                    viewModel.state.sections[idx] = newValue
                }
            }
        )
    }

    private func handleCollaboratorCrystallize(_ message: CollaboratorMessage) {
        if let draft = message.draftProposal {
            acceptDraftProposal(draft)
        }
    }

    private func persistedCollaboratorReply(_ reply: CollaboratorMessage) -> CollaboratorMessage {
        guard reply.draftProposal != nil else { return reply }
        return CollaboratorMessage(
            id: reply.id,
            role: reply.role,
            text: reply.text,
            observationKind: reply.observationKind,
            questionSuggestion: reply.questionSuggestion,
            recommendedAction: reply.recommendedAction,
            draftProposal: nil,
            createdAt: reply.createdAt
        )
    }

    private func appendCollaboratorReply(_ reply: CollaboratorMessage, persistState: Bool = true) {
        let storedReply = persistedCollaboratorReply(reply)
        viewModel.state.appendCollaboratorMessage(storedReply)
        guard reply.draftProposal != nil else {
            if persistState {
                viewModel.saveState()
            }
            return
        }
        stageDraftIfNeeded(from: reply, sourceMessageID: storedReply.id, persistState: persistState)
    }

    private func sourceMessageID(for draft: ConnectionDraftProposal) -> UUID? {
        if collaboratorPreview.streamingDraft?.id == draft.id {
            return collaboratorPreview.sourceMessageID
        }
        return viewModel.state.collaboratorMessages.first(where: { $0.draftProposal?.id == draft.id })?.id
    }

    private func persistDraft(
        _ draft: ConnectionDraftProposal,
        sourceMessageID: UUID?,
        setActive: Bool
    ) {
        if let sourceMessageID {
            viewModel.state.setCollaboratorDraft(draft, forMessageID: sourceMessageID)
        } else {
            viewModel.state.updateCollaboratorDraft(draft)
        }
        viewModel.state.setActiveDraftProposal(setActive ? draft : nil)
    }

    private func draftChunks(for text: String, wordsPerChunk: Int = 3) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        var chunks: [String] = []
        var cumulative: [String] = []
        for start in stride(from: 0, to: words.count, by: wordsPerChunk) {
            let end = min(start + wordsPerChunk, words.count)
            cumulative.append(contentsOf: words[start..<end])
            chunks.append(cumulative.joined(separator: " "))
        }
        return chunks
    }

    private func stageDraftIfNeeded(from message: CollaboratorMessage, sourceMessageID: UUID?, persistState: Bool) {
        guard let draft = message.draftProposal else {
            collaboratorPreview.clear()
            return
        }
        draftStreamingTask?.cancel()

        if let existingPreview = collaboratorPreview.streamingDraft,
           existingPreview.id != draft.id {
            collaboratorPreview.clear()
        }

        if let existingDraft = viewModel.state.activeDraftProposal,
           existingDraft.id != draft.id,
           existingDraft.status != .accepted,
           existingDraft.status != .dismissed {
            var dismissed = existingDraft
            dismissed.status = .dismissed
            dismissed.visibleText = dismissed.draftText
            viewModel.state.updateCollaboratorDraft(dismissed)
            viewModel.state.setActiveDraftProposal(nil)
        }

        var previewDraft = draft
        previewDraft.visibleText = ""
        previewDraft.status = .streaming
        collaboratorPreview.begin(draft: previewDraft, sourceMessageID: sourceMessageID)
        streamDraftPreview(previewDraft, sourceMessageID: sourceMessageID, startingAt: 0, persistState: persistState)
    }

    private func streamDraftPreview(
        _ draft: ConnectionDraftProposal,
        sourceMessageID: UUID?,
        startingAt startIndex: Int,
        persistState: Bool
    ) {
        let chunks = draftChunks(for: draft.draftText)
        draftStreamingTask = Task { @MainActor in
            if chunks.isEmpty {
                var finalized = draft
                finalized.visibleText = finalized.draftText
                finalized.status = .pending
                collaboratorPreview.clear()
                persistDraft(finalized, sourceMessageID: sourceMessageID, setActive: true)
                if persistState {
                    viewModel.saveState()
                }
                return
            }

            for index in startIndex..<chunks.count {
                guard !Task.isCancelled else { return }
                collaboratorPreview.updateVisibleText(chunks[index], nextChunkIndex: index + 1)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            var finalized = draft
            finalized.visibleText = finalized.draftText
            finalized.status = .pending
            collaboratorPreview.clear()
            persistDraft(finalized, sourceMessageID: sourceMessageID, setActive: true)
            if persistState {
                viewModel.saveState()
            }
        }
    }

    private func acceptDraftProposal(_ draft: ConnectionDraftProposal) {
        draftStreamingTask?.cancel()
        let sourceMessageID = sourceMessageID(for: draft)
        if collaboratorPreview.streamingDraft?.id == draft.id {
            collaboratorPreview.clear()
        }
        var accepted = draft
        accepted.visibleText = accepted.draftText
        accepted.status = .accepted
        accepted.insertedAt = Date()
        persistDraft(accepted, sourceMessageID: sourceMessageID, setActive: false)

        let document = RichDocument.migrateLegacy(accepted.draftText)
        viewModel.addItem(document: document, plainText: accepted.draftText, toSection: accepted.targetSection)
        viewModel.saveState()
    }

    @MainActor
    private func reviseDraftProposal(_ draft: ConnectionDraftProposal) async {
        draftStreamingTask?.cancel()
        let sourceMessageID = sourceMessageID(for: draft)
        if collaboratorPreview.streamingDraft?.id == draft.id {
            collaboratorPreview.clear()
        }
        var pending = draft
        pending.visibleText = pending.draftText
        pending.status = .pending
        persistDraft(pending, sourceMessageID: sourceMessageID, setActive: true)
        viewModel.saveState()

        let prompt = """
        Revise the current draft for the \(draft.targetSection.displayName) section. Keep the core idea, make it sharper, and stay additive.

        Current draft:
        \(draft.draftText)
        """

        let reply = await collaboratorEngine.ask(
            prompt: prompt,
            frameworkTitle: editableTitle,
            conceptType: viewModel.state.conceptType,
            state: viewModel.state,
            linkedSources: wellSources,
            history: viewModel.state.collaboratorMessages
        )
        appendCollaboratorReply(reply)
    }

    private func moveDraftProposal(_ draft: ConnectionDraftProposal, to section: ConnectionSectionType) {
        draftStreamingTask?.cancel()
        let sourceMessageID = sourceMessageID(for: draft)
        if collaboratorPreview.streamingDraft?.id == draft.id {
            collaboratorPreview.clear()
        }
        var moved = draft
        moved.targetSection = section
        moved.visibleText = moved.draftText
        moved.status = .pending
        persistDraft(moved, sourceMessageID: sourceMessageID, setActive: true)
        viewModel.saveState()
    }

    private func dismissDraftProposal(_ draft: ConnectionDraftProposal) {
        draftStreamingTask?.cancel()
        let sourceMessageID = sourceMessageID(for: draft)
        if collaboratorPreview.streamingDraft?.id == draft.id {
            collaboratorPreview.clear()
        }
        var dismissed = draft
        dismissed.visibleText = dismissed.draftText
        dismissed.status = .dismissed
        persistDraft(dismissed, sourceMessageID: sourceMessageID, setActive: false)
        viewModel.saveState()
    }

    private func pauseActiveDraftIfNeeded(for section: ConnectionSectionType) {
        if let previewDraft = collaboratorPreview.streamingDraft,
           previewDraft.targetSection == section,
           collaboratorPreview.isStreaming {
            draftStreamingTask?.cancel()
            collaboratorPreview.pause()
            return
        }

        guard var activeDraft = viewModel.state.activeDraftProposal,
              activeDraft.targetSection == section,
              activeDraft.status == .streaming else { return }
        draftStreamingTask?.cancel()
        activeDraft.status = .pending
        activeDraft.visibleText = activeDraft.draftText
        viewModel.state.updateCollaboratorDraft(activeDraft)
        viewModel.state.setActiveDraftProposal(activeDraft)
    }

    private func resumeDraftProposal(_ draft: ConnectionDraftProposal) {
        guard collaboratorPreview.isPaused,
              collaboratorPreview.streamingDraft?.id == draft.id else { return }
        draftStreamingTask?.cancel()
        streamDraftPreview(
            draft,
            sourceMessageID: collaboratorPreview.sourceMessageID,
            startingAt: collaboratorPreview.nextChunkIndex,
            persistState: true
        )
    }

    // MARK: - Floating Panels Layer

    private var floatingPanelsLayer: some View {
        ZStack {
        // Persistent floating blocks (stored in atom metadata)
        FocusFloatingBlocksLayer(
            manager: floatingBlocksManager,
            onSelect: { blockId in
                selectedBlockId = "atom:\(blockId)"
            }
        )

        ForEach(panelManager.panels) { panel in
            if let binding = panelManager.binding(for: panel.id) {
                FloatingPanelView(
                    panel: binding,
                    content: panelManager.content(for: panel.id),
                    onDoubleTap: {
                        NotificationCenter.default.post(
                            name: CosmoNotification.Navigation.openBlockInFocusMode,
                            object: nil,
                            userInfo: ["atomUUID": panel.atomUUID]
                        )
                    },
                    onRemove: {
                        panelManager.removePanel(id: panel.id)
                    },
                    onDelete: {
                        Task {
                            try? await AtomRepository.shared.delete(uuid: panel.atomUUID)
                            panelManager.removePanel(id: panel.id)
                        }
                    },
                    onPositionChange: { newPosition in
                        panelManager.updatePosition(panel.id, position: newPosition)
                    }
                )
            }
        }
        } // ZStack
        // V3 Phase 3: suppress Thinkspace's blockSelected notification for any
        // block wrapper inside this layer — avoids the pane-mode selection race.
        .environment(\.canvasBlockSelectionSuppressed, true)
    }

    // MARK: - Right-Click Monitor

    private func updateViewFrameInWindow(_ newFrame: CGRect) {
        let oldFrame = viewFrameInWindow
        let changedEnough = oldFrame == .zero
            || abs(oldFrame.minX - newFrame.minX) > 0.5
            || abs(oldFrame.minY - newFrame.minY) > 0.5
            || abs(oldFrame.width - newFrame.width) > 0.5
            || abs(oldFrame.height - newFrame.height) > 0.5

        guard changedEnough else { return }
        viewFrameInWindow = newFrame
    }

    private func setupRightClickMonitor() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard let window = event.window else { return event }

            let windowPoint = event.locationInWindow
            let windowHeight = window.frame.height

            // Convert to SwiftUI coordinates (flip Y, origin top-left)
            let screenPoint = CGPoint(
                x: windowPoint.x,
                y: windowHeight - windowPoint.y
            )

            // Only handle clicks within this view's frame
            guard viewFrameInWindow.contains(screenPoint) else { return event }

            // Convert to view-local coordinates
            let localPoint = CGPoint(
                x: screenPoint.x - viewFrameInWindow.minX,
                y: screenPoint.y - viewFrameInWindow.minY
            )

            // Convert local coordinates to canvas coordinates
            let canvasPoint = CGPoint(
                x: (localPoint.x - viewportState.offset.x) / viewportState.zoomScale,
                y: (localPoint.y - viewportState.offset.y) / viewportState.zoomScale
            )

            viewModel.lastTapPosition = canvasPoint
            viewModel.radialMenuPosition = localPoint

            return nil // Consume the event
        }
    }

    private func removeRightClickMonitor() {
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickMonitor = nil
        }
    }

    // MARK: - Space-Hold Pan Monitor

    /// Global keyDown/keyUp monitor for space. While held, blocks stop
    /// absorbing drag gestures and the canvas pans instead (Figma pattern).
    private func setupSpaceMonitor() {
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            // Skip when the user is typing — no editor should lose its input.
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            // 49 = keyCode for space.
            guard event.keyCode == 49 else { return event }
            if event.type == .keyDown && !event.isARepeat {
                if !isSpacePanHeld { isSpacePanHeld = true }
                return nil
            } else if event.type == .keyUp {
                if isSpacePanHeld { isSpacePanHeld = false }
                return nil
            }
            return event
        }
    }

    private func removeSpaceMonitor() {
        if let monitor = spaceMonitor {
            NSEvent.removeMonitor(monitor)
            spaceMonitor = nil
        }
        isSpacePanHeld = false
    }

    // MARK: - Helpers

    private func handleRadialAction(_ action: RadialAction) {
        viewModel.radialMenuPosition = nil

        switch action.type {
        case .createNote:
            Task {
                if let noteAtom = await viewModel.createNote() {
                    canvasCreatedAtomUUIDs.insert(noteAtom.uuid)
                    addPanelForAtom(noteAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createIdea, .createTask:
            // Not used in Connection focus mode
            break

        case .createContent:
            Task {
                if let contentAtom = await viewModel.createContent() {
                    canvasCreatedAtomUUIDs.insert(contentAtom.uuid)
                    addPanelForAtom(contentAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createResearch:
            Task {
                if let researchAtom = await viewModel.createResearch() {
                    canvasCreatedAtomUUIDs.insert(researchAtom.uuid)
                    addPanelForAtom(researchAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createConnection:
            Task {
                if let connectionAtom = await viewModel.createConnection() {
                    canvasCreatedAtomUUIDs.insert(connectionAtom.uuid)
                    addPanelForAtom(connectionAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createStickyNote:
            Task {
                let stickyAtom = Atom.new(type: .stickyNote, title: "", body: "")
                if let created = try? await AtomRepository.shared.create(stickyAtom) {
                    canvasCreatedAtomUUIDs.insert(created.uuid)
                    addPanelForAtom(created, at: viewModel.lastTapPosition)
                }
            }

        case .createDeepDive:
            Task {
                if let deepDiveAtom = try? await InquiryRepository.shared.createDeepDive(title: "New Deep Dive") {
                    canvasCreatedAtomUUIDs.insert(deepDiveAtom.uuid)
                    addPanelForAtom(deepDiveAtom, at: viewModel.lastTapPosition)
                }
            }

        case .researchAgent:
            break

        case .fromDatabase:
            showCommandK = true

        case .createTemplate:
            break // Templates not supported in focus mode
        }
    }

    private func addPanelForAtom(_ atom: Atom, at position: CGPoint) {
        // Add as persistent floating block (stored in atom metadata)
        floatingBlocksManager.addBlock(
            linkedAtomUUID: atom.uuid,
            linkedAtomType: atom.type,
            title: atom.title ?? "Untitled",
            position: position
        )
    }

    /// V3: delete the currently-selected canvas block.
    /// - For `"atom:<id>"` selection: remove from canvas, and if the atom was
    ///   created on this canvas (tracked in `canvasCreatedAtomUUIDs`), also
    ///   soft-delete the atom itself. Pre-existing atoms are just unlinked.
    /// - Returns true if a delete was performed (caller should return `.handled`).
    @discardableResult
    private func deleteSelectedBlock() -> Bool {
        guard let selected = selectedBlockId else { return false }

        if selected.hasPrefix("atom:") {
            let blockId = String(selected.dropFirst("atom:".count))
            guard let block = floatingBlocksManager.block(id: blockId) else {
                selectedBlockId = nil
                return true
            }
            let atomUUID = block.linkedAtomUUID
            let wasCreatedOnCanvas = canvasCreatedAtomUUIDs.contains(atomUUID)
            floatingBlocksManager.removeBlock(id: blockId)
            canvasCreatedAtomUUIDs.remove(atomUUID)
            selectedBlockId = nil
            if wasCreatedOnCanvas {
                Task {
                    try? await AtomRepository.shared.delete(uuid: atomUUID)
                }
            }
            return true
        }

        // Intrinsic panels (Phase 1b) are not deletable — swallow the key.
        return true
    }

    /// Listen for atom picker notifications to add existing atoms as floating blocks
    private func listenForAtomPicker() {
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.FocusMode.addAtomAsFloatingBlock,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let atomUUID = userInfo["atomUUID"] as? String,
                  let atomTypeRaw = userInfo["atomType"] as? String,
                  let atomType = AtomType(rawValue: atomTypeRaw),
                  let title = userInfo["title"] as? String else { return }

            Task { @MainActor in
                guard !isPaneContext || isPaneContextOwner else { return }

                let position = CGPoint(
                    x: 500 + CGFloat.random(in: -60...60),
                    y: 300 + CGFloat.random(in: -60...60)
                )

                floatingBlocksManager.addBlock(
                    linkedAtomUUID: atomUUID,
                    linkedAtomType: atomType,
                    title: title,
                    position: position
                )
            }
        }
    }

    private func openSourceAsPanel(_ atomUUID: String) {
        // Position panel to the right of the connection card
        let position = CGPoint(x: 700, y: 300)
        Task {
            if let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                panelManager.addPanel(
                    atomUUID: atomUUID,
                    atomType: atom.type,
                    position: position
                )
            }
        }
    }

    private func loadState() {
        // Load viewport state
        let persistence = CanvasViewportPersistence()
        viewportState = persistence.load(forAtomUUID: atom.uuid)

        // ViewModel loads its own state
        viewModel.loadState()
    }

    private func saveState() {
        // Save viewport state
        let persistence = CanvasViewportPersistence()
        persistence.save(viewportState, forAtomUUID: atom.uuid)

        // Save focus mode state
        viewModel.saveState()
    }

    // MARK: - Source Drop + Relation Area

    private func dropSourceOnCanvas(_ source: Atom) {
        // Add as floating block
        let position = CGPoint(
            x: 500 + CGFloat.random(in: -60...60),
            y: 300 + CGFloat.random(in: -60...60)
        )

        floatingBlocksManager.addBlock(
            linkedAtomUUID: source.uuid,
            linkedAtomType: source.type,
            title: source.title ?? "Untitled",
            position: position
        )

        // Show relation area and trigger AI suggestion
        let state = RelationAreaState(
            sourceAtom: source,
            position: position
        )
        withAnimation(ProMotionSprings.snappy) {
            activeRelationArea = state
        }

        // AI pre-suggestion
        Task {
            do {
                let suggestion = try await coDevEngine.suggestRelation(
                    sourceMaterial: source,
                    connection: atom
                )
                withAnimation(ProMotionSprings.snappy) {
                    activeRelationArea?.applySuggestion(suggestion)
                }
            } catch {
                // Fallback: no pre-suggestion
            }
        }
    }

    private func handleChipTap(_ sectionType: ConnectionSectionType, state: RelationAreaState) {
        Task {
            let itemText = await coDevEngine.generateSectionItem(
                sourceMaterial: state.sourceAtom,
                targetSection: sectionType,
                relationNote: state.relationNote,
                connection: atom
            )

            let item = ConnectionItem(
                content: itemText,
                sourceAtomUUID: state.sourceAtom.uuid,
                sourceSnippet: state.sourceAtom.title
            )

            viewModel.state.addItem(item, toSection: sectionType)
            viewModel.saveState()

            withAnimation(ProMotionSprings.snappy) {
                activeRelationArea = nil
            }
        }
    }

    private func sourceIconName(_ type: AtomType) -> String {
        switch type {
        case .research: return "magnifyingglass"
        case .idea: return "lightbulb.fill"
        case .connection: return "link.circle.fill"
        default: return "doc.fill"
        }
    }

    private func sourceColor(_ type: AtomType) -> Color {
        switch type {
        case .research: return CosmoColors.blockResearch
        case .idea: return CosmoColors.lavender
        case .connection: return CosmoColors.blockConnection
        default: return CosmoColors.slate
        }
    }

    private func sourceTypeLabel(_ type: AtomType) -> String {
        switch type {
        case .research: return "Research"
        case .idea: return "Insight"
        case .connection: return "Connection"
        default: return type.rawValue.capitalized
        }
    }
}

// MARK: - Relation Area State

private struct RelationAreaOverlayCard: View {
    @ObservedObject var state: RelationAreaState
    let onDismiss: () -> Void
    let onChipTap: (ConnectionSectionType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            relationAreaHeader
            relationNoteField
            relationChips
        }
        .padding(16)
        .frame(width: 400)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
        .position(x: state.position.x, y: state.position.y + 220)
    }

    private var relationAreaHeader: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: sourceIconName(state.sourceAtom.type))
                .font(DS.subheadline)
                .foregroundStyle(sourceColor(state.sourceAtom.type))

            VStack(alignment: .leading, spacing: DS.space2) {
                Text(state.sourceAtom.title ?? "Untitled")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Text(sourceTypeLabel(state.sourceAtom.type))
                    .font(DS.smallCaps)
                    .foregroundStyle(sourceColor(state.sourceAtom.type))
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .padding(DS.space6)
                    .background(DS.glassCardFill, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var relationNoteField: some View {
        CosmoDocumentEditor(
            document: $state.relationNoteDocument,
            fontSize: 12,
            compact: true,
            placeholder: "How does this relate?",
            allowSlashCommands: false,
            allowMentions: true,
            allowSelectionMenu: false,
            allowImages: false,
            onDocumentChange: { document, _ in
                state.updateRelationNoteDocument(document)
            }
        )
        .frame(minHeight: 44, maxHeight: 88)
        .padding(10)
        .dsGlassInput(cornerRadius: 8)
    }

    private var relationChips: some View {
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(ConnectionSectionType.allCases, id: \.rawValue) { sectionType in
                relationChipButton(sectionType)
            }
        }
    }

    private func relationChipButton(_ sectionType: ConnectionSectionType) -> some View {
        let isHighlighted = state.highlightedSections.contains(sectionType)

        return Button {
            onChipTap(sectionType)
        } label: {
            VStack(spacing: DS.space4) {
                Image(systemName: sectionType.icon)
                    .font(DS.footnote)

                Text(sectionType.displayName)
                    .font(DS.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isHighlighted ? sectionType.accentColor : DS.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHighlighted ? sectionType.accentColor.opacity(0.15) : DS.glassCardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isHighlighted ? sectionType.accentColor.opacity(0.4) : DS.glassBorder,
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func sourceIconName(_ type: AtomType) -> String {
        switch type {
        case .research: return "magnifyingglass"
        case .idea: return "lightbulb.fill"
        case .connection: return "link.circle.fill"
        default: return "doc.fill"
        }
    }

    private func sourceColor(_ type: AtomType) -> Color {
        switch type {
        case .research: return CosmoColors.blockResearch
        case .idea: return CosmoColors.lavender
        case .connection: return CosmoColors.blockConnection
        default: return CosmoColors.slate
        }
    }

    private func sourceTypeLabel(_ type: AtomType) -> String {
        switch type {
        case .research: return "Research"
        case .idea: return "Insight"
        case .connection: return "Connection"
        default: return type.rawValue.capitalized
        }
    }
}

@MainActor
class RelationAreaState: ObservableObject {
    let sourceAtom: Atom
    let position: CGPoint
    @Published var relationNoteDocument: RichDocument
    @Published var highlightedSections: [ConnectionSectionType]
    @Published var suggestion: RelationSuggestion?

    init(
        sourceAtom: Atom,
        position: CGPoint,
        relationNote: String = "",
        highlightedSections: [ConnectionSectionType] = []
    ) {
        self.sourceAtom = sourceAtom
        self.position = position
        self.relationNoteDocument = RichDocument.migrateLegacy(relationNote)
        self.highlightedSections = highlightedSections
    }

    var relationNote: String {
        relationNoteDocument.plainText
    }

    func updateRelationNoteDocument(_ document: RichDocument) {
        relationNoteDocument = document
    }

    func applySuggestion(_ suggestion: RelationSuggestion) {
        self.suggestion = suggestion
        self.highlightedSections = suggestion.suggestedSections
        if !suggestion.relationNote.isEmpty {
            self.relationNoteDocument = RichDocument.migrateLegacy(suggestion.relationNote)
        }
    }
}

// MARK: - Connection Focus Mode ViewModel

@MainActor
class ConnectionFocusModeViewModel: ObservableObject {
    // MARK: - Published State

    @Published var state: ConnectionFocusModeState
    @Published var radialMenuPosition: CGPoint?
    @Published var lastTapPosition: CGPoint = CGPoint(x: 400, y: 300)

    // MARK: - Properties

    private let atom: Atom
    private var terminationCancellable: AnyCancellable?
    /// Tracks whether sections were actually modified in this focus mode session.
    /// Prevents saveToAtom() from overwriting DB sections with stale state
    /// when the user only viewed but didn't edit in focus mode.
    private(set) var sectionsModifiedInFocusMode = false

    // MARK: - Initialization

    init(atom: Atom) {
        self.atom = atom
        self.state = ConnectionFocusModeState(atomUUID: atom.uuid)
        parseAtomStructuredData()

        // Flush pending saves synchronously when the app is about to terminate
        terminationCancellable = NotificationCenter.default
            .publisher(for: .cosmoAppWillTerminate)
            .sink { [weak self] _ in
                self?.saveToAtom()
            }
    }

    deinit {
        MainActor.assumeIsolated {
            terminationCancellable?.cancel()
        }
    }

    // MARK: - State Management

    func loadState() {
        if let savedState = ConnectionFocusModeState.load(atomUUID: atom.uuid) {
            state = savedState
        }
    }

    func normalizeCollaboratorState() {
        state.normalizeCollaboratorStateAfterLoad()
    }

    func saveState() {
        print("[FOCUS-CONN-VM] saveState() — uuid=\(atom.uuid) sectionsCount=\(state.sections.count) totalItems=\(state.sections.flatMap(\.items).count)")
        state.lastModified = Date()
        state.save()

        // Also save to atom.structured
        saveToAtom()
    }

    private var titleSaveTask: Task<Void, Never>?

    func updateTitle(_ newTitle: String) {
        updateTitleDocument(RichDocument.migrateLegacy(newTitle), plainTitle: newTitle)
    }

    func updateTitleDocument(_ document: RichDocument, plainTitle: String) {
        let atomUUID = atom.uuid
        print("[FOCUS-CONN-VM] updateTitleDocument() — uuid=\(atomUUID) title=\"\(String(plainTitle.prefix(60)))\" 0.5s debounce starting")

        // Cancel previous debounced save
        titleSaveTask?.cancel()
        titleSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { print("[FOCUS-CONN-VM] updateTitleDocument() CANCELLED uuid=\(atomUUID)"); return }
            do {
                let titleDocument = RichDocumentPersistence.normalizedTitleDocument(
                    document.isEmpty ? RichDocument.migrateLegacy(plainTitle) : document
                )
                try await CosmoDatabase.shared.asyncWrite { db in
                    var existingMetadata: String?
                    if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]) {
                        existingMetadata = row["metadata"]
                    }
                    let fields = RichDocumentPersistence.writeAtomDocuments(
                        existingMetadata: existingMetadata,
                        titleDocument: titleDocument
                    )
                    try db.execute(
                        sql: "UPDATE atoms SET title = ?, metadata = ?, updated_at = ?, _local_version = _local_version + 1 WHERE uuid = ?",
                        arguments: [fields.title, fields.metadata, ISO8601DateFormatter().string(from: Date()), atomUUID]
                    )
                }
                print("[FOCUS-CONN-VM] updateTitleDocument() DB write DONE — uuid=\(atomUUID)")
            } catch {
                print("[FOCUS-CONN-VM] updateTitleDocument() DB write FAILED — uuid=\(atomUUID) error=\(error)")
            }
        }
    }

    /// Force immediate synchronous title save (called on view disappear) — blocks until DB write completes.
    func flushTitleSave(_ document: RichDocument, plainTitle: String) {
        print("[FOCUS-CONN-VM] flushTitleSave() — uuid=\(atom.uuid) title=\"\(String(plainTitle.prefix(60)))\"")
        titleSaveTask?.cancel()
        let titleDocument = RichDocumentPersistence.normalizedTitleDocument(
            document.isEmpty ? RichDocument.migrateLegacy(plainTitle) : document
        )
        let atomUUID = atom.uuid
        do {
            try CosmoDatabase.shared.write { db in
                var existingMetadata: String?
                if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]) {
                    existingMetadata = row["metadata"]
                }
                let fields = RichDocumentPersistence.writeAtomDocuments(
                    existingMetadata: existingMetadata,
                    titleDocument: titleDocument
                )
                try db.execute(
                    sql: "UPDATE atoms SET title = ?, metadata = ?, updated_at = ?, _local_version = _local_version + 1, _local_pending = 1 WHERE uuid = ?",
                    arguments: [fields.title, fields.metadata, ISO8601DateFormatter().string(from: Date()), atomUUID]
                )
            }
            // Sync: queue for Supabase push
            Task {
                if let updatedAtom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                    // skipVersionIncrement: raw SQL already did _local_version + 1
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                }
            }
        } catch {
            print("❌ Connection title flush failed: \(error)")
        }
    }

    private func parseAtomStructuredData() {
        guard let structured = atom.structured,
              let data = ConnectionStructuredData.fromJSON(structured) else {
            return
        }

        // Merge saved sections with default sections
        for savedSection in data.sections {
            if let index = state.sections.firstIndex(where: { $0.type == savedSection.type }) {
                state.sections[index] = savedSection
            }
        }
    }

    func saveToAtom() {
        // Only write structured/body to atom if sections were actually modified
        // in this focus mode session. Otherwise, skip to avoid overwriting
        // sections that were edited in the canvas block view.
        guard sectionsModifiedInFocusMode else {
            print("[FOCUS-CONN-VM] saveToAtom() SKIPPED — sections not modified in focus mode uuid=\(atom.uuid)")
            return
        }
        let structuredData = ConnectionStructuredData(sections: state.sections)
        if let json = structuredData.toJSON() {
            var updatedAtom = atom
            updatedAtom.structured = json
            updatedAtom.body = state.flattenedBodyText
            print("[FOCUS-CONN-VM] saveToAtom() — uuid=\(atom.uuid) bodyLen=\(state.flattenedBodyText.count) structuredLen=\(json.count) bodyPreview=\"\(String(state.flattenedBodyText.prefix(80)))\"")
            if let saved = try? AtomRepository.shared.updateSync(updatedAtom) {
                print("[FOCUS-CONN-VM] saveToAtom() DONE — uuid=\(atom.uuid) newVersion=\(saved.localVersion)")
                // Sync: queue for Supabase push
                Task {
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: saved)
                }
            } else {
                print("[FOCUS-CONN-VM] saveToAtom() FAILED — updateSync threw uuid=\(atom.uuid)")
            }
        } else {
            print("[FOCUS-CONN-VM] saveToAtom() SKIPPED — JSON serialization failed uuid=\(atom.uuid)")
        }
    }

    // MARK: - Item Management

    func addItem(document: RichDocument, plainText: String, toSection type: ConnectionSectionType) {
        print("[FOCUS-CONN-VM] addItem() — section=\(type.rawValue) textLen=\(plainText.count) preview=\"\(String(plainText.prefix(60)))\" uuid=\(atom.uuid)")
        sectionsModifiedInFocusMode = true
        let item = ConnectionItem(content: plainText, document: document, plainText: plainText)
        state.addItem(item, toSection: type)
        saveState()
    }

    func editItem(_ item: ConnectionItem, inSection type: ConnectionSectionType) {
        sectionsModifiedInFocusMode = true
        state.updateItem(item, inSection: type)
        saveState()
    }

    func deleteItem(_ id: UUID, fromSection type: ConnectionSectionType) {
        sectionsModifiedInFocusMode = true
        state.removeItem(id: id, fromSection: type)
        saveState()
    }

    // MARK: - Ghost Suggestions

    func generateGhostSuggestions() async {
        state.isGeneratingGhosts = true

        // Get related atoms
        let relatedUUIDs = await getRelatedAtomUUIDs()

        // Gather existing items to avoid duplicates
        let existingItems = state.sections.flatMap { $0.items }

        // Generate suggestions
        let suggestions = await GhostSuggestionEngine.shared.generateSuggestions(
            connectionTitle: atom.title ?? "",
            existingItems: existingItems,
            relatedAtomUUIDs: relatedUUIDs
        )

        // Apply suggestions to sections
        for (sectionType, sectionSuggestions) in suggestions {
            state.setGhostSuggestions(sectionSuggestions, forSection: sectionType)
        }

        state.isGeneratingGhosts = false
        saveState()
    }

    private func getRelatedAtomUUIDs() async -> [String] {
        do {
            let queryEngine = GraphQueryEngine()
            let neighbors = try await queryEngine.getNeighbors(of: atom.uuid, direction: .both, limit: 20)
            return neighbors.map { $0.node.atomUUID }
        } catch {
            return []
        }
    }

    func acceptGhost(_ ghost: GhostSuggestion, inSection type: ConnectionSectionType) {
        state.acceptGhost(ghost.id, inSection: type)
        saveState()
    }

    func dismissGhost(_ id: UUID, inSection type: ConnectionSectionType) {
        state.dismissGhost(id, inSection: type)
        saveState()
    }

    // MARK: - Atom Creation

    func createNote() async -> Atom? {
        // Create note with link to this connection
        let note = Atom.new(
            type: .note,
            title: "New Note",
            body: "",
            links: [AtomLink.related(atom.uuid, entityType: .connection)]
        )

        guard let created = try? await AtomRepository.shared.create(note) else {
            return nil
        }

        // Also add reverse link to the connection
        var updatedAtom = atom
        updatedAtom = updatedAtom.addingLink(AtomLink.related(created.uuid, entityType: .note))
        _ = try? await AtomRepository.shared.update(updatedAtom)

        return created
    }

    func createContent() async -> Atom? {
        let content = Atom.new(
            type: .content,
            title: "New Content",
            body: "",
            links: [AtomLink.related(atom.uuid, entityType: .connection)]
        )

        guard let created = try? await AtomRepository.shared.create(content) else {
            return nil
        }

        var updatedAtom = atom
        updatedAtom = updatedAtom.addingLink(AtomLink.related(created.uuid, entityType: .content))
        _ = try? await AtomRepository.shared.update(updatedAtom)

        return created
    }

    func createResearch() async -> Atom? {
        let research = Atom.new(
            type: .research,
            title: "New Research",
            body: "",
            links: [AtomLink.related(atom.uuid, entityType: .connection)]
        )

        guard let created = try? await AtomRepository.shared.create(research) else {
            return nil
        }

        var updatedAtom = atom
        updatedAtom = updatedAtom.addingLink(AtomLink.related(created.uuid, entityType: .research))
        _ = try? await AtomRepository.shared.update(updatedAtom)

        return created
    }

    func createConnection() async -> Atom? {
        let connection = Atom.new(
            type: .connection,
            title: "New Connection",
            body: "",
            links: [AtomLink.related(atom.uuid, entityType: .connection)]
        )

        guard let created = try? await AtomRepository.shared.create(connection) else {
            return nil
        }

        var updatedAtom = atom
        updatedAtom = updatedAtom.addingLink(AtomLink.related(created.uuid, entityType: .connection))
        _ = try? await AtomRepository.shared.update(updatedAtom)

        return created
    }
}

// MARK: - Connected Source Chip

struct ConnectedSourceChip: View {
    let source: ConnectedSource
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.space8) {
                // Type icon
                Image(systemName: iconForType(source.atomType))
                    .font(DS.footnote)
                    .foregroundStyle(colorForType(source.atomType))

                // Title
                Text(source.atomTitle)
                    .font(DS.buttonText)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                // Connection strength
                if source.connectionStrength > 1 {
                    Text("×\(source.connectionStrength)")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? DS.glassInputFillFocused : DS.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHovered ? colorForType(source.atomType).opacity(0.5) : DS.glassBorder,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    private func iconForType(_ type: AtomType) -> String {
        switch type {
        case .research: return "magnifyingglass"
        case .idea: return "lightbulb.fill"
        case .journalEntry: return "book.fill"
        case .content: return "doc.text.fill"
        case .connection: return "link.circle.fill"
        default: return "circle.fill"
        }
    }

    private func colorForType(_ type: AtomType) -> Color {
        switch type {
        case .research: return CosmoColors.blockResearch
        case .idea: return CosmoColors.lavender
        case .journalEntry: return DS.entityNote
        case .content: return CosmoColors.blockContent
        case .connection: return CosmoColors.blockConnection
        default: return CosmoColors.slate
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ConnectionFocusModeView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionFocusModeView(
            atom: Atom.new(
                type: .connection,
                title: "Atomic Habits Framework",
                body: "Building lasting habits through small improvements."
            ),
            onClose: { print("Close") }
        )
        .frame(width: 1200, height: 800)
    }
}
#endif

// MARK: - Cosmo Context Provider

@MainActor
class ConnectionContextProvider: CosmoContextProvider {
    private let atom: Atom
    private weak var viewModel: ConnectionFocusModeViewModel?

    init(atom: Atom, viewModel: ConnectionFocusModeViewModel) {
        self.atom = atom
        self.viewModel = viewModel
    }

    var contextType: CosmoContextType { .connectionFocusMode }

    var contextSummary: String {
        "Connection: \(atom.title ?? "Untitled")"
    }

    var contextData: CosmoContextData {
        var viewData: [String: String] = [:]

        if let vm = viewModel {
            let sections = vm.state.sections
            let totalItems = sections.reduce(0) { $0 + $1.items.count }
            let filledSections = sections.filter { !$0.items.isEmpty }.count
            viewData["sectionCount"] = "\(sections.count)"
            viewData["filledSections"] = "\(filledSections)"
            viewData["totalItems"] = "\(totalItems)"
        }

        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "connection",
            currentAtomTitle: atom.title,
            viewSpecificData: viewData
        )
    }

    var availableActions: [CosmoWindowAction] {
        guard let viewModel else { return [] }

        func action(
            id: String,
            name: String,
            section: ConnectionSectionType
        ) -> CosmoWindowAction {
            CosmoWindowAction(
                id: id,
                name: name,
                description: "Add a new item to \(section.displayName).",
                modelTier: .balanced
            ) { prompt in
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Nothing added." }
                let document = RichDocument.migrateLegacy(trimmed)
                await MainActor.run {
                    viewModel.addItem(document: document, plainText: trimmed, toSection: section)
                }
                return "Added to \(section.displayName.lowercased())."
            }
        }

        return [
            action(id: "connection-goal", name: "Insert into Goal", section: .goal),
            action(id: "connection-problems", name: "Insert into Problems", section: .problems),
            action(id: "connection-process", name: "Insert into Process", section: .process)
        ]
    }
}
