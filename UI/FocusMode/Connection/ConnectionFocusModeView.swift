// CosmoOS/UI/FocusMode/Connection/ConnectionFocusModeView.swift
// Main Connection Focus Mode view - canvas with structured concept card
// 8 sections with items, ghost suggestions, and connected sources
// December 2025 - Complete rewrite following PRD spec

import SwiftUI
import Combine
import GRDB

// MARK: - Connection Focus Mode View

/// Main view for Connection Focus Mode.
/// Displays an infinite canvas with an anchored structured concept card,
/// floating panels from the database, and ghost suggestions from AI.
struct ConnectionFocusModeView: View {
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
    @State private var sidebarVisible = false
    @State private var sidebarLocked = false
    @State private var showSettings = false
    @State private var activeRelationArea: RelationAreaState?
    @State private var rightClickMonitor: Any?
    @State private var viewFrameInWindow: CGRect = .zero
    @State private var editableTitle: String
    @State private var titleDocument: RichDocument = .empty
    @State private var titleEditorHeight: CGFloat = 76
    @State private var isEditingTitle = false
    @StateObject private var coDevEngine = ConnectionCoDevEngine()

    // MARK: - V2 "The Crucible" state

    @State private var collaboratorEngine = ConceptCollaboratorEngine()
    @State private var wellSources: [Atom] = []
    @State private var wellIsLoading: Bool = false
    @State private var hoveredSourceUUID: String?
    @State private var hoveredStationType: ConnectionSectionType?
    @State private var isRefreshingInsights: Bool = false
    @State private var atelierContentUsages: [AtelierContentUsage] = []
    @State private var atelierProfiles: [AtelierProfileChip] = []
    // V2 mode overlays — Manuscript (⌘M), Chalkboard (⌘B), Station Mode (double-click station).
    @State private var manuscriptActive: Bool = false
    @State private var chalkboardActive: Bool = false
    @State private var stationModeType: ConnectionSectionType?

    private let titleStyle = SharedTitleSurfaceStyle.connectionFocus

    private var titleFontSize: CGFloat { titleStyle.fontSize }

    private var titleMinHeight: CGFloat { titleStyle.minimumHeight }

    private var titlePreviewMaxHeight: CGFloat { titleStyle.previewMaxHeight }

    private var titleEditingMaxHeight: CGFloat { titleStyle.editingMaxHeight }

    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneActive) private var isPaneActive

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
        .overlay(alignment: .topLeading) {
            FocusSidebarTrigger(isVisible: $sidebarVisible)
                .frame(maxHeight: .infinity)
        }
        // V2 "The Crucible": left-docked Well
        .overlay(alignment: .leading) {
            theWellPanel
                .padding(.top, 56)
                .padding(.bottom, DS.space16)
        }
        // V2 "The Crucible": right-docked Atelier
        .overlay(alignment: .trailing) {
            theAtelierPanel
                .padding(.top, 56)
                .padding(.bottom, DS.space16)
        }
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
                    onAddItem: { doc, text in viewModel.addItem(document: doc, plainText: text, toSection: type) },
                    onEditItem: { item in viewModel.editItem(item, inSection: type) },
                    onDeleteItem: { id in viewModel.deleteItem(id, fromSection: type) },
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
            listenForAtomPicker()
            setupRightClickMonitor()
            titleEditorHeight = titleMinHeight
            Task {
                await viewModel.generateGhostSuggestions()
                await loadAtelierData()
                // Kick off an initial insights pass if the framework has enough substance.
                if viewModel.state.completedSectionCount >= 2 {
                    await refreshLiveInsights()
                }
            }
            // Register context provider for global Cosmo window
            let provider = ConnectionContextProvider(atom: atom, viewModel: viewModel)
            if !isPaneContext || isPaneActive {
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onChange(of: viewModel.state.completedSectionCount) { oldValue, newValue in
            // Threshold-crossed? Refresh insights.
            let oldBand = thresholdBand(oldValue)
            let newBand = thresholdBand(newValue)
            if newBand != oldBand && newValue >= 2 {
                Task { await refreshLiveInsights() }
            }
        }
        .onChange(of: isPaneActive) { _, isActive in
            if isActive {
                let provider = ConnectionContextProvider(atom: atom, viewModel: viewModel)
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewFrameInWindow = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in viewFrameInWindow = newFrame }
            }
        )
        .onDisappear {
            print("[FOCUS-CONN] onDisappear — uuid=\(atom.uuid) title=\"\(String(editableTitle.prefix(60)))\" sectionsCount=\(viewModel.state.sections.count)")
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
            viewModel.flushTitleSave(titleDocument, plainTitle: editableTitle)
            viewModel.saveToAtom()
            saveState()
            floatingBlocksManager.saveImmediately()
            removeRightClickMonitor()
        }
        // Deselect panels on background click
        .onTapGesture(count: 1) {
            panelManager.deselectAll()
            if activeRelationArea != nil {
                // Dismiss relation area on background tap
                withAnimation(ProMotionSprings.snappy) {
                    activeRelationArea = nil
                }
            }
        }
        // Keyboard shortcuts
        .onKeyPress(.escape) {
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
            if sidebarVisible {
                withAnimation(ProMotionSprings.snappy) {
                    sidebarVisible = false
                }
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
                default: break
                }
            }
            return .ignored
        }
        .sheet(isPresented: $showCommandK) {
            CommandKView()
                .frame(minWidth: 900, minHeight: 600)
        }
        // Settings sheet
        .sheet(isPresented: $showSettings) {
            SanctuarySettingsView()
                .frame(width: 720, height: 540)
        }
        // Cmd+K single-click: add as floating block
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.addItemToCurrentCanvas)) { notification in
            guard let uuid = notification.userInfo?["atomUUID"] as? String else { return }
            let title = notification.userInfo?["title"] as? String ?? "Untitled"
            let typeRaw = notification.userInfo?["atomType"] as? String ?? AtomType.idea.rawValue
            let atomType = AtomType(rawValue: typeRaw) ?? .idea
            showCommandK = false
            floatingBlocksManager.addBlock(
                linkedAtomUUID: uuid,
                linkedAtomType: atomType,
                title: title,
                position: CGPoint(x: 200, y: 200)
            )
        }
    }

    // MARK: - Anchored Connection Content

    /// Section cards displayed directly on the canvas (no outer container)
    private var anchoredConnectionCard: some View {
        VStack(spacing: 24) {
            // V2 "The Crucible" — Masthead + spatial Stations grid
            TheForgeView(
                title: Binding(
                    get: { editableTitle },
                    set: { newValue in
                        editableTitle = newValue
                        titleDocument = RichDocument.migrateLegacy(newValue)
                        viewModel.updateTitleDocument(titleDocument, plainTitle: newValue)
                    }
                ),
                conceptType: $viewModel.state.conceptType,
                state: $viewModel.state,
                onAddItem: { document, plainText, type in
                    viewModel.addItem(document: document, plainText: plainText, toSection: type)
                },
                onEditItem: { item, type in
                    viewModel.editItem(item, inSection: type)
                },
                onDeleteItem: { id, type in
                    viewModel.deleteItem(id, fromSection: type)
                },
                onSourceTap: { sourceUUID in
                    openSourceAsPanel(sourceUUID)
                },
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
                sourceCount: viewModel.state.connectedSources.count,
                insightCount: viewModel.state.totalGhostCount
            )
            .frame(maxWidth: CGFloat(4) * 260 + CGFloat(3) * 20)

            // Connected sources (if any) — preserved from V1 until Phase 2 replaces with TheWellView.
            if !viewModel.state.connectedSources.isEmpty {
                connectedSourcesSection
                    .frame(width: 420)
            }
        }
    }

    // MARK: - Title Header

    /// Floating title with stats - no container background
    private var connectionTitleHeader: some View {
        VStack(spacing: 8) {
            Group {
                if isEditingTitle {
                    CosmoDocumentEditor(
                        document: $titleDocument,
                        fontSize: titleFontSize,
                        compact: titleStyle.compact,
                        placeholder: "New Connection",
                        allowSlashCommands: false,
                        allowMentions: true,
                        allowSelectionMenu: false,
                        allowImages: false,
                        titleConfiguration: titleStyle.titleConfiguration,
                        baseFontWeight: titleStyle.baseFontWeight,
                        scrollsInternally: true,
                        textAlignment: titleStyle.textAlignment,
                        onContentHeightChange: { newHeight in
                            titleEditorHeight = min(titleEditingMaxHeight, max(titleMinHeight, newHeight))
                        },
                        onPlainTextChange: { plainText in
                            editableTitle = plainText
                        },
                        onStructuredDocumentChange: { document, plainText in
                            titleDocument = document
                            editableTitle = plainText
                            viewModel.updateTitleDocument(document, plainTitle: plainText)
                        },
                        onActivate: { isEditingTitle = true },
                        onDeactivate: { isEditingTitle = false },
                        onCommit: { isEditingTitle = false },
                        autoFocus: true
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: min(titleEditingMaxHeight, max(titleMinHeight, titleEditorHeight)))
                } else {
                    Text(editableTitle.isEmpty ? "New Connection" : editableTitle)
                        .font(titleStyle.swiftUIFont)
                        .foregroundStyle(editableTitle.isEmpty ? DS.textMuted : DS.text)
                        .lineLimit(titleStyle.previewLineLimit)
                        .truncationMode(.tail)
                        .multilineTextAlignment(titleStyle.swiftUITextAlignment)
                        .frame(maxWidth: .infinity, minHeight: titleMinHeight, maxHeight: titlePreviewMaxHeight, alignment: .center)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isEditingTitle = true
                        }
                }
            }

            // Stats (centered)
            HStack(spacing: DS.space12) {
                HStack(spacing: DS.space4) {
                    Text("\(viewModel.state.totalItemCount)")
                        .font(DS.callout)
                    Text("items")
                        .font(DS.subheadline)
                }
                .foregroundStyle(DS.textSecondary)

                Text("·")
                    .foregroundStyle(DS.textMuted)

                HStack(spacing: DS.space4) {
                    Text("\(viewModel.state.completedSectionCount)/8")
                        .font(DS.callout)
                    Text("sections")
                        .font(DS.subheadline)
                }
                .foregroundStyle(DS.textSecondary)
            }

            // Ghost suggestions indicator
            if viewModel.state.isGeneratingGhosts {
                HStack(spacing: DS.space6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(DS.entityConnection)

                    Text("Finding suggestions...")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.top, DS.space4)
            } else if viewModel.state.totalGhostCount > 0 {
                HStack(spacing: DS.space4) {
                    Image(systemName: "sparkles")
                        .font(DS.caption2)
                    Text("\(viewModel.state.totalGhostCount) suggestions available")
                        .font(DS.footnote)
                }
                .foregroundStyle(DS.entityConnection.opacity(0.7))
                .padding(.top, DS.space4)
            }
        }
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

            // Focus mode sidebar toggle
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    sidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(DS.callout)
                    .foregroundStyle(sidebarVisible ? DS.entityConnection : DS.textSecondary)
                    .padding(DS.space8)
                    .background(
                        sidebarVisible ? DS.entityConnection.opacity(0.15) : DS.border,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
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

    // MARK: - V2 "The Crucible" — Well & Atelier panels

    /// Left-docked sources + whispers zone.
    private var theWellPanel: some View {
        TheWellView(
            sources: wellSources,
            whispersBySource: whispersBySource,
            isLoadingSources: wellIsLoading,
            onAddSource: { handleAddSource() },
            onSourceTap: { openSourceAsPanel($0) },
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
            onHoverSource: { hoveredSourceUUID = $0 },
            contributionsBySource: contributionsBySource
        )
        .background(DS.vellum.opacity(0.95))
        .shadow(color: DS.inkWash.opacity(0.06), radius: 8, x: 2, y: 0)
    }

    /// Right-docked partner zone: collaborator, insights, crystal, usage.
    private var theAtelierPanel: some View {
        TheAtelierView(
            collaboratorMessages: Binding(
                get: { viewModel.state.collaboratorMessages },
                set: { viewModel.state.collaboratorMessages = $0 }
            ),
            isCollaboratorThinking: collaboratorEngine.isThinking,
            onSendMessage: { text in Task { await handleCollaboratorSend(text) } },
            onCrystallizeMessage: { message in handleCollaboratorCrystallize(message) },
            insights: viewModel.state.liveInsights,
            isRefreshingInsights: isRefreshingInsights,
            onRefreshInsights: { Task { await refreshLiveInsights() } },
            onDismissInsight: { id in
                viewModel.state.liveInsights.removeAll { $0.id == id }
            },
            filledSectionCount: viewModel.state.completedSectionCount,
            thresholdLabel: maturityThresholdLabel,
            maturityDetail: maturityDetailLine,
            contentUsages: atelierContentUsages,
            profiles: atelierProfiles,
            onOpenContent: { openContentAtom($0) },
            onAddProfile: { handleAddProfile() },
            onOpenProfile: { openProfileAtom($0) },
            frameworkTitle: editableTitle,
            conceptType: viewModel.state.conceptType
        )
        .background(DS.vellum.opacity(0.95))
        .shadow(color: DS.inkWash.opacity(0.06), radius: 8, x: -2, y: 0)
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

    private var maturityDetailLine: String {
        "\(viewModel.state.completedSectionCount)/8 STATIONS"
    }

    // MARK: - Well/Atelier handlers

    private func handleAddSource() {
        showCommandK = true
    }

    private func handleAddProfile() {
        // Placeholder — future work wires the profile picker.
    }

    private func openContentAtom(_ uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid]
        )
    }

    private func openProfileAtom(_ uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid]
        )
    }

    private func regenerateWhispers(forSource sourceUUID: String) async {
        // Per-source whisper regeneration — Phase 2 currently falls back to the
        // full-graph refresh. GhostSuggestionEngine.generateWhispers(forSource:)
        // is the Phase 3 entry point when we add the specialized API.
        await viewModel.generateGhostSuggestions()
    }

    @MainActor
    private func loadAtelierData() async {
        wellIsLoading = true
        wellSources = await coDevEngine.findSourceMaterials(for: atom, limit: 10)
        wellIsLoading = false

        let usages = await coDevEngine.findContentUsage(connectionUUID: atom.uuid)
        atelierContentUsages = usages.map { usage in
            AtelierContentUsage(
                id: usage.atom.uuid,
                title: usage.atom.title ?? "Untitled",
                formatGlyph: "doc.richtext"
            )
        }

        let profileIds = atom.connectionLinkedProfileIds
        var chips: [AtelierProfileChip] = []
        for id in profileIds {
            if let profile = try? await AtomRepository.shared.fetch(uuid: id) {
                let initial = String((profile.title ?? "?").prefix(1))
                chips.append(AtelierProfileChip(id: profile.uuid, initial: initial, title: profile.title ?? "Profile"))
            }
        }
        atelierProfiles = chips
    }

    @MainActor
    private func refreshLiveInsights() async {
        isRefreshingInsights = true
        let insights = await coDevEngine.generateLiveInsights(
            state: viewModel.state,
            conceptType: viewModel.state.conceptType,
            frameworkTitle: editableTitle
        )
        viewModel.state.setLiveInsights(insights)
        isRefreshingInsights = false
    }

    @MainActor
    private func handleCollaboratorSend(_ text: String) async {
        let userMessage = CollaboratorMessage(role: .user, text: text)
        viewModel.state.appendCollaboratorMessage(userMessage)

        let reply = await collaboratorEngine.ask(
            prompt: text,
            frameworkTitle: editableTitle,
            conceptType: viewModel.state.conceptType,
            state: viewModel.state,
            history: viewModel.state.collaboratorMessages
        )
        viewModel.state.appendCollaboratorMessage(reply)
    }

    private func thresholdBand(_ count: Int) -> Int {
        switch count {
        case 0...2: return 0
        case 3...4: return 1
        case 5...7: return 2
        default: return 3
        }
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
        guard let section = message.crystallizeTarget,
              let content = message.crystallizeContent, !content.isEmpty else { return }
        let document = RichDocument.migrateLegacy(content)
        viewModel.addItem(document: document, plainText: content, toSection: section)
    }

    // MARK: - Connected Sources Section

    private var connectedSourcesSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                Text("CONNECTED SOURCES")
                    .dsSectionLabel()

                Spacer()

                Text("\(viewModel.state.connectedSources.count) sources")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space10) {
                    ForEach(viewModel.state.connectedSources) { source in
                        ConnectedSourceChip(
                            source: source,
                            onTap: {
                                openSourceAsPanel(source.atomUUID)
                            }
                        )
                    }
                }
            }
        }
        .padding(DS.space16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.borderSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.border, lineWidth: 1)
                )
        )
    }

    // MARK: - Floating Panels Layer

    private var floatingPanelsLayer: some View {
        ZStack {
        // Persistent floating blocks (stored in atom metadata)
        FocusFloatingBlocksLayer(manager: floatingBlocksManager)

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
    }

    // MARK: - Right-Click Monitor

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

    // MARK: - Helpers

    private func handleRadialAction(_ action: RadialAction) {
        viewModel.radialMenuPosition = nil

        switch action.type {
        case .createNote:
            Task {
                if let noteAtom = await viewModel.createNote() {
                    addPanelForAtom(noteAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createIdea, .createTask:
            // Not used in Connection focus mode
            break

        case .createContent:
            Task {
                if let contentAtom = await viewModel.createContent() {
                    addPanelForAtom(contentAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createResearch:
            Task {
                if let researchAtom = await viewModel.createResearch() {
                    addPanelForAtom(researchAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createConnection:
            Task {
                if let connectionAtom = await viewModel.createConnection() {
                    addPanelForAtom(connectionAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createStickyNote:
            Task {
                let stickyAtom = Atom.new(type: .stickyNote, title: "", body: "")
                if let created = try? await AtomRepository.shared.create(stickyAtom) {
                    addPanelForAtom(created, at: viewModel.lastTapPosition)
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

    /// Listen for atom picker notifications to add existing atoms as floating blocks
    private func listenForAtomPicker() {
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.FocusMode.addAtomAsFloatingBlock,
            object: nil,
            queue: .main
        ) { [self] notification in
            guard !self.isPaneContext || self.isPaneActive else { return }
            guard let userInfo = notification.userInfo,
                  let atomUUID = userInfo["atomUUID"] as? String,
                  let atomTypeRaw = userInfo["atomType"] as? String,
                  let atomType = AtomType(rawValue: atomTypeRaw),
                  let title = userInfo["title"] as? String else { return }

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
        terminationCancellable?.cancel()
    }

    // MARK: - State Management

    func loadState() {
        if let savedState = ConnectionFocusModeState.load(atomUUID: atom.uuid) {
            state = savedState
        }
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

    var availableActions: [CosmoWindowAction] { [] }
}
