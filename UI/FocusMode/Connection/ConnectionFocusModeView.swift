// CosmoOS/UI/FocusMode/Connection/ConnectionFocusModeView.swift
// Main Connection Focus Mode view - canvas with structured concept card
// 8 sections with items, ghost suggestions, and connected sources
// December 2025 - Complete rewrite following PRD spec

import SwiftUI
import Combine

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

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: ConnectionFocusModeViewModel(atom: atom))
        self._panelManager = StateObject(wrappedValue: FloatingPanelManager(focusAtomUUID: atom.uuid))
        self._floatingBlocksManager = StateObject(wrappedValue: FocusFloatingBlocksManager(ownerAtomUUID: atom.uuid))
    }

    // MARK: - Body

    var body: some View {
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
        .onAppear {
            loadState()
            listenForAtomPicker()
            Task {
                await viewModel.generateGhostSuggestions()
            }
        }
        .onDisappear {
            saveState()
            floatingBlocksManager.saveImmediately()
        }
        // Right-click for radial menu
        .onTapGesture(count: 1) {
            panelManager.deselectAll()
        }
        .gesture(
            TapGesture(count: 1)
                .modifiers(.control)
                .onEnded { _ in
                    viewModel.radialMenuPosition = CGPoint(x: 400, y: 300)
                }
        )
        // Keyboard shortcuts
        .onKeyPress(.escape) {
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
            return .ignored
        }
        .sheet(isPresented: $showCommandK) {
            CommandKView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }

    // MARK: - Anchored Connection Content

    /// Section cards displayed directly on the canvas (no outer container)
    private var anchoredConnectionCard: some View {
        VStack(spacing: 16) {
            // Floating title header (no background container)
            connectionTitleHeader
                .padding(.bottom, 8)

            // Section cards - each is its own card directly on canvas
            ForEach($viewModel.state.sections) { $section in
                ConnectionSectionView(
                    section: $section,
                    onAddItem: { content in
                        viewModel.addItem(content, toSection: section.type)
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
            // Icon and title
            HStack(spacing: 8) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(CosmoColors.blockConnection)

                Text(atom.title ?? "New Connection")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Stats
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("\(viewModel.state.totalItemCount)")
                        .font(.system(size: 13, weight: .medium))
                    Text("items")
                        .font(.system(size: 12))
                }
                .foregroundColor(.white.opacity(0.5))

                Text("·")
                    .foregroundColor(.white.opacity(0.3))

                HStack(spacing: 4) {
                    Text("\(viewModel.state.completedSectionCount)/8")
                        .font(.system(size: 13, weight: .medium))
                    Text("sections")
                        .font(.system(size: 12))
                }
                .foregroundColor(.white.opacity(0.5))
            }

            // Ghost suggestions indicator
            if viewModel.state.isGeneratingGhosts {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(CosmoColors.blockConnection)

                    Text("Finding suggestions...")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
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
        HStack(spacing: 16) {
            // Back button
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            // Title
            Text(atom.title ?? "Connection")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            // Type badge
            HStack(spacing: 4) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 10))
                Text("CONNECTION")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundColor(CosmoColors.blockConnection)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CosmoColors.blockConnection.opacity(0.15), in: Capsule())

            Spacer()

            // Refresh suggestions button
            Button {
                Task {
                    await viewModel.generateGhostSuggestions()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("Refresh Suggestions")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.state.isGeneratingGhosts)

            // Command-K button
            Button {
                showCommandK = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                    Text("⌘K")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    CosmoColors.thinkspaceVoid.opacity(0.95),
                    CosmoColors.thinkspaceVoid.opacity(0.8),
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
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1)

                Spacer()

                Text("\(viewModel.state.connectedSources.count) sources")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
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
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
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

        case .researchAgent:
            // Connection doesn't use research agent directly
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
        ) { notification in
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

    // MARK: - Initialization

    init(atom: Atom) {
        self.atom = atom
        self.state = ConnectionFocusModeState(atomUUID: atom.uuid)
        parseAtomStructuredData()
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

    private func saveToAtom() {
        let structuredData = ConnectionStructuredData(sections: state.sections)
        if let json = structuredData.toJSON() {
            var updatedAtom = atom
            updatedAtom.structured = json
            Task {
                _ = try? await AtomRepository.shared.update(updatedAtom)
            }
        }
    }

    // MARK: - Item Management

    func addItem(_ content: String, toSection type: ConnectionSectionType) {
        let item = ConnectionItem(content: content)
        state.addItem(item, toSection: type)
        saveState()
    }

    func editItem(_ item: ConnectionItem, inSection type: ConnectionSectionType) {
        // Would open edit sheet
        print("Edit item: \(item.content)")
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
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Connection strength
                if source.connectionStrength > 1 {
                    Text("×\(source.connectionStrength)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isHovered ? 0.1 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isHovered ? colorForType(source.atomType).opacity(0.5) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
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
