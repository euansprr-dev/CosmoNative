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
    @StateObject private var coDevEngine = ConnectionCoDevEngine()

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneActive) private var isPaneActive

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._editableTitle = State(initialValue: atom.title ?? "New Connection")
        self._titleDocument = State(initialValue: RichDocumentPersistence.loadAtomDocument(
            field: .title,
            metadata: atom.metadata,
            fallbackPlainText: atom.title ?? "New Connection"
        ))
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
        .overlay(alignment: .topLeading) {
            UniversalFocusSidebar(
                title: "Connection",
                icon: "link",
                accentColor: CosmoColors.blockConnection,
                isVisible: $sidebarVisible,
                isLocked: $sidebarLocked
            ) {
                ConnectionSidebarView(
                    atom: atom,
                    viewModel: viewModel,
                    isVisible: true,
                    onDropSource: { source in
                        dropSourceOnCanvas(source)
                    }
                )
            }
            .padding(.leading, 8)
            .padding(.top, 56)
        }
        .overlay(alignment: .topTrailing) {
            if isPaneContext {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 28, height: 28)
                        .background(DS.border, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.top, 16)
            }
        }
        .onAppear {
            loadState()
            listenForAtomPicker()
            setupRightClickMonitor()
            Task {
                await viewModel.generateGhostSuggestions()
            }
            // Register context provider for global Cosmo window
            let provider = ConnectionContextProvider(atom: atom, viewModel: viewModel)
            if !isPaneContext || isPaneActive {
                CosmoWindowViewModel.shared.updateContext(provider: provider)
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
            viewModel.flushTitleSave(editableTitle)
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
        VStack(spacing: 16) {
            // Floating title header (no background container)
            connectionTitleHeader
                .frame(width: 420)
                .padding(.bottom, 8)

            // Section cards - each is its own card directly on canvas
            ForEach($viewModel.state.sections) { $section in
                ConnectionSectionView(
                    section: $section,
                    onAddItem: { document, plainText in
                        viewModel.addItem(document: document, plainText: plainText, toSection: section.type)
                    },
                    onEditItem: { item in
                        viewModel.editItem(item, inSection: section.type)
                    },
                    onDeleteItem: { id in
                        viewModel.deleteItem(id, fromSection: section.type)
                    },
                    onSourceTap: { sourceUUID in
                        openSourceAsPanel(sourceUUID)
                    },
                    onAcceptGhost: { ghost in
                        viewModel.acceptGhost(ghost, inSection: section.type)
                    },
                    onDismissGhost: { id in
                        viewModel.dismissGhost(id, inSection: section.type)
                    }
                )
                .frame(width: 420)
            }

            // Connected sources (if any)
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
            // Title (centered)
            CosmoDocumentEditor(
                document: $titleDocument,
                fontSize: 22,
                compact: true,
                placeholder: "New Connection",
                allowSlashCommands: false,
                allowMentions: true,
                allowSelectionMenu: false,
                allowImages: false,
                singleLine: true,
                baseFontWeight: .semibold,
                textAlignment: .center,
                onDocumentChange: { document, _ in
                    editableTitle = RichDocumentPersistence.titlePlainText(from: document)
                    viewModel.updateTitleDocument(document, plainTitle: editableTitle)
                }
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 44)

            // Stats (centered)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("\(viewModel.state.totalItemCount)")
                        .font(.system(size: 13, weight: .medium))
                    Text("items")
                        .font(.system(size: 12))
                }
                .foregroundColor(DS.textSecondary)

                Text("·")
                    .foregroundColor(DS.textMuted)

                HStack(spacing: 4) {
                    Text("\(viewModel.state.completedSectionCount)/8")
                        .font(.system(size: 13, weight: .medium))
                    Text("sections")
                        .font(.system(size: 12))
                }
                .foregroundColor(DS.textSecondary)
            }

            // Ghost suggestions indicator
            if viewModel.state.isGeneratingGhosts {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(CosmoColors.blockConnection)

                    Text("Finding suggestions...")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textSecondary)
                }
                .padding(.top, 4)
            } else if viewModel.state.totalGhostCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("\(viewModel.state.totalGhostCount) suggestions available")
                        .font(.system(size: 11))
                }
                .foregroundColor(CosmoColors.blockConnection.opacity(0.7))
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            // Back button (hidden in pane mode — X button handles close)
            if !isPaneContext {
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
                    .background(DS.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Type badge (right next to back button)
            HStack(spacing: 4) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 10))
                Text("CONNECTION")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundColor(CosmoColors.blockConnection)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CosmoColors.blockConnection.opacity(0.15), in: Capsule())

            Spacer()

            // Sidebar toggle (pane mode)
            if isPaneContext {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        sidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13))
                        .foregroundStyle(sidebarVisible ? DS.entityConnection : DS.textSecondary)
                        .padding(8)
                        .background(
                            sidebarVisible ? DS.entityConnection.opacity(0.15) : DS.border,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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

    // MARK: - Connected Sources Section

    private var connectedSourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CONNECTED SOURCES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DS.textMuted)
                    .tracking(1)

                Spacer()

                Text("\(viewModel.state.connectedSources.count) sources")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
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
        .padding(16)
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
        HStack(spacing: 10) {
            Image(systemName: sourceIconName(state.sourceAtom.type))
                .font(.system(size: 12))
                .foregroundColor(sourceColor(state.sourceAtom.type))

            VStack(alignment: .leading, spacing: 2) {
                Text(state.sourceAtom.title ?? "Untitled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Text(sourceTypeLabel(state.sourceAtom.type))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(sourceColor(state.sourceAtom.type))
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .padding(6)
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
            VStack(spacing: 4) {
                Image(systemName: sectionType.icon)
                    .font(.system(size: 11))

                Text(sectionType.displayName)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(isHighlighted ? sectionType.accentColor : DS.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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

        // Cancel previous debounced save
        titleSaveTask?.cancel()
        titleSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            do {
                try await CosmoDatabase.shared.asyncWrite { db in
                    var existingMetadata: String?
                    if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]) {
                        existingMetadata = row["metadata"]
                    }
                    let titleDocument = document.isEmpty ? RichDocument.migrateLegacy(plainTitle) : document
                    let fields = RichDocumentPersistence.writeAtomDocuments(
                        existingMetadata: existingMetadata,
                        titleDocument: titleDocument
                    )
                    try db.execute(
                        sql: "UPDATE atoms SET title = ?, metadata = ?, updated_at = ?, _local_version = _local_version + 1 WHERE uuid = ?",
                        arguments: [fields.title, fields.metadata, ISO8601DateFormatter().string(from: Date()), atomUUID]
                    )
                }
                print("✅ Connection title saved")
            } catch {
                print("❌ Connection title save failed: \(error)")
            }
        }
    }

    /// Force immediate synchronous title save (called on view disappear) — blocks until DB write completes.
    func flushTitleSave(_ title: String) {
        titleSaveTask?.cancel()
        let titleDocument = RichDocument.migrateLegacy(title)
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
                    sql: "UPDATE atoms SET title = ?, metadata = ?, updated_at = ?, _local_version = _local_version + 1 WHERE uuid = ?",
                    arguments: [fields.title, fields.metadata, ISO8601DateFormatter().string(from: Date()), atomUUID]
                )
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
        let structuredData = ConnectionStructuredData(sections: state.sections)
        if let json = structuredData.toJSON() {
            var updatedAtom = atom
            updatedAtom.structured = json
            updatedAtom.body = state.flattenedBodyText
            _ = try? AtomRepository.shared.updateSync(updatedAtom)
        }
    }

    // MARK: - Item Management

    func addItem(document: RichDocument, plainText: String, toSection type: ConnectionSectionType) {
        let item = ConnectionItem(content: plainText, document: document, plainText: plainText)
        state.addItem(item, toSection: type)
        saveState()
    }

    func editItem(_ item: ConnectionItem, inSection type: ConnectionSectionType) {
        state.updateItem(item, inSection: type)
        saveState()
    }

    func deleteItem(_ id: UUID, fromSection type: ConnectionSectionType) {
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
            HStack(spacing: 8) {
                // Type icon
                Image(systemName: iconForType(source.atomType))
                    .font(.system(size: 11))
                    .foregroundColor(colorForType(source.atomType))

                // Title
                Text(source.atomTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                // Connection strength
                if source.connectionStrength > 1 {
                    Text("×\(source.connectionStrength)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
        case .journalEntry: return Color(hex: "#EC4899")
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
