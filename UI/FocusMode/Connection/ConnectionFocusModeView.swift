// CosmoOS/UI/FocusMode/Connection/ConnectionFocusModeView.swift
// Connection Focus Mode — structured 3-pane workspace host.
// June 2026 rewrite: the free-form canvas (floating blocks, radial menu,
// space-pan, collaborator dock) is replaced by ConnectionWorkspaceView
// (navigator | board/outline/manuscript | inspector). Concept development
// now happens through the inline assistant's /concept skill, which stages
// reviewed diffs against this connection's editable surface.

import SwiftUI
import Combine
import GRDB

// MARK: - Connection Focus Mode View

struct ConnectionFocusModeView: View {

    // MARK: - Properties

    /// The connection atom being displayed
    let atom: Atom

    /// Callback to close focus mode
    let onClose: () -> Void

    // MARK: - State

    @State private var viewModel: ConnectionFocusModeViewModel
    @State private var workspace = ConnectionWorkspaceModel()
    @State private var coDevEngine = ConnectionCoDevEngine()
    @State private var showCommandK = false
    @State private var wellSources: [Atom] = []
    @State private var suggestedWellSources: [Atom] = []
    @State private var isLoadingSuggestedSources = false
    @State private var isShowingSuggestedSources = false
    @State private var isRefreshingInsights = false
    /// Sibling pages of the same deep dive — powers inline mention links.
    @State private var linkTargets: ConnectionLinkTargets = .empty
    /// Pending inline-assistant proposal targeting this connection's sections.
    @State private var reviewProposal: CosmoAssistantProposal?

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPeekContext) private var isPeekContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner
    @Environment(\.atomWindowChromeContext) private var atomChrome

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._viewModel = State(initialValue: ConnectionFocusModeViewModel(atom: atom))
    }

    // MARK: - Body

    var body: some View {
        workspaceView
            .background(DS.bg.ignoresSafeArea())
            .focusImmersiveEntryTransition()
            .overlay(alignment: .topTrailing) { paneCloseButton }
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
            .onChange(of: isPaneContextOwner) { _, isOwner in
                if isOwner { registerContextProvider() }
            }
            .onReceive(CosmoInlineAssistantStore.shared.$proposals) { proposals in
                syncReviewProposal(from: proposals)
            }
            .onKeyPress(.escape) { handleEscape() }
            .onKeyPress { handleKeyCommand($0) }
            .sheet(isPresented: $showCommandK) {
                CommandKView()
                    .frame(minWidth: 900, minHeight: 600)
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.addItemToCurrentCanvas)) { notification in
                handleAtomPicked(notification)
            }
    }

    private var workspaceView: some View {
        ConnectionWorkspaceView(
            atom: atom,
            viewModel: viewModel,
            workspace: workspace,
            title: titleBinding,
            sources: workspaceSources,
            isRefreshingInsights: isRefreshingInsights,
            reviewProposal: reviewProposal,
            reviewSourceText: reviewSourceText,
            isPaneContext: isPaneContext,
            actions: workspaceActions
        )
        .environment(\.connectionLinkTargets, linkTargets)
    }

    @ViewBuilder
    private var paneCloseButton: some View {
        if isPaneContext, !isPeekContext, atomChrome == nil {
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
            .accessibilityLabel("Close connection")
        }
    }

    // MARK: - Workspace wiring

    private var titleBinding: Binding<String> {
        Binding(
            get: { viewModel.editableTitle },
            set: { viewModel.setTitle($0) }
        )
    }

    private var workspaceSources: ConnectionWorkspaceSources {
        ConnectionWorkspaceSources(
            linked: wellSources,
            suggested: suggestedWellSources,
            isLoadingSuggestions: isLoadingSuggestedSources,
            isShowingSuggestions: isShowingSuggestedSources,
            contributions: contributionsBySource
        )
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

    private var workspaceActions: ConnectionWorkspaceActions {
        ConnectionWorkspaceActions(
            onSourceTap: { openSource($0) },
            onAddSource: { showCommandK = true },
            onRequestSuggestions: { Task { await requestSuggestedSources() } },
            onLinkSuggestedSource: { source in Task { await linkSourceToConnection(source) } },
            onRefreshInsights: { refreshInsights() },
            onDismissInsight: { id in
                viewModel.state.liveInsights.removeAll { $0.id == id }
                viewModel.saveState()
            },
            onTitleCommit: { viewModel.flushTitleSave() },
            onClose: onClose
        )
    }

    /// Serialized snapshot text the in-board diff weaves changes into.
    private var reviewSourceText: String {
        ConnectionSurfaceSerializer.serialize(
            title: viewModel.editableTitle,
            conceptType: viewModel.state.conceptType,
            sections: viewModel.state.sections
        ).text
    }

    private func syncReviewProposal(from proposals: [CosmoAssistantProposal]) {
        reviewProposal = proposals.last { proposal in
            proposal.hasReviewableOperations && proposal.matches(
                surfaceID: "connection:\(atom.uuid)",
                targetID: ConnectionContextProvider.targetID(for: atom.uuid),
                activeAtomUUID: atom.uuid
            )
        }
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
        viewModel.loadState()
        workspace.viewMode = viewModel.state.viewMode
        if let pendingSection = ConnectionFocusDeepLink.consume(for: atom.uuid) {
            workspace.openSection(pendingSection)
        }
        registerContextProvider()
        Task {
            // Sections come from a FRESH DB fetch — never from the UserDefaults
            // blob or the (possibly stale) open-time atom snapshot.
            await viewModel.refreshSectionsFromDatabase()
            await viewModel.generateGhostSuggestions()
            await loadSources()
            await loadLinkTargets()
            await refreshInsightsIfStale()
        }
    }

    private func handleDisappear() {
        AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
        viewModel.state.viewMode = workspace.viewMode
        viewModel.flushTitleSave()
        viewModel.saveToAtom()
        viewModel.saveState()
    }

    private func registerContextProvider() {
        guard !isPaneContext || isPaneContextOwner else { return }
        let provider = ConnectionContextProvider(
            atom: atom,
            viewModel: viewModel,
            titleProvider: { [weak viewModel] in
                viewModel?.editableTitle ?? "Untitled Connection"
            }
        )
        CosmoWindowViewModel.shared.updateContext(provider: provider)
    }

    // MARK: - Keyboard

    private func handleEscape() -> KeyPress.Result {
        if showCommandK {
            showCommandK = false
            return .handled
        }
        if workspace.isNavigatorOverlayPresented {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.isNavigatorOverlayPresented = false
            }
            return .handled
        }
        if workspace.isInspectorOverlayPresented {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.isInspectorOverlayPresented = false
            }
            return .handled
        }
        if workspace.pushedSection != nil {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.popSection()
            }
            return .handled
        }
        if workspace.isSearching {
            workspace.searchQuery = ""
            return .handled
        }
        if workspace.viewMode == .manuscript {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.viewMode = .board
            }
            return .handled
        }
        onClose()
        return .handled
    }

    private func handleKeyCommand(_ keyPress: KeyPress) -> KeyPress.Result {
        guard keyPress.modifiers.contains(.command) else { return .ignored }

        if keyPress.modifiers.contains(.option), keyPress.key == KeyEquivalent("i") {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleInspector()
            }
            return .handled
        }

        switch keyPress.characters {
        case "1": return setViewMode(.board)
        case "2": return setViewMode(.outline)
        case "3", "m": return setViewMode(workspace.viewMode == .manuscript ? .board : .manuscript)
        case "0":
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleNavigator()
            }
            return .handled
        case "f":
            workspace.searchFocusTick += 1
            return .handled
        case "k":
            showCommandK = true
            return .handled
        default:
            return .ignored
        }
    }

    private func setViewMode(_ mode: ConnectionViewMode) -> KeyPress.Result {
        withAnimation(ProMotionSprings.focusTransition) {
            workspace.viewMode = mode
            workspace.pushedSection = nil
        }
        return .handled
    }

    // MARK: - Sources

    /// ⌘K picker selection — connections only accept source links now
    /// (floating canvas blocks are gone).
    private func handleAtomPicked(_ notification: Notification) {
        guard let uuid = notification.userInfo?["atomUUID"] as? String else { return }
        let typeRaw = notification.userInfo?["atomType"] as? String ?? AtomType.idea.rawValue
        let atomType = AtomType(rawValue: typeRaw) ?? .idea
        showCommandK = false
        guard isEligibleSourceType(atomType) else { return }
        Task {
            guard let source = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
            await linkSourceToConnection(source)
        }
    }

    private func isEligibleSourceType(_ type: AtomType) -> Bool {
        switch type {
        case .research, .idea, .content, .note, .connection:
            return true
        default:
            return false
        }
    }

    private func openSource(_ atomUUID: String) {
        Task {
            guard let sourceAtom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else { return }
            // Web-backed sources (references imported from inquiry sessions)
            // open the actual page in the browser pane instead of an atom pane.
            if let urlString = sourceAtom.researchMetadata?.url,
               let url = URL(string: urlString) {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openWebBrowserPane,
                    object: nil,
                    userInfo: ["url": url, "title": sourceAtom.title ?? urlString]
                )
                return
            }
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": atomUUID, "asPane": true]
            )
        }
    }

    /// Sibling Connection pages of the same deep dive become inline link
    /// targets — mentions of their titles in item text open them as panes.
    @MainActor
    private func loadLinkTargets() async {
        guard let deepDiveUUID = atom.linksOfType(.deepDiveConnection).first?.uuid,
              let deepDive = try? await AtomRepository.shared.fetch(uuid: deepDiveUUID),
              let siblings = try? await InquiryRepository.shared.fetchConnections(forDeepDive: deepDive) else { return }
        linkTargets = ConnectionLinkTargets(targets: siblings.compactMap { sibling in
            guard sibling.uuid != atom.uuid, let title = sibling.title, !title.isEmpty else { return nil }
            return .init(uuid: sibling.uuid, title: title)
        })
    }

    @MainActor
    private func loadSources() async {
        wellSources = await coDevEngine.findLinkedSourceMaterials(for: atom.uuid, limit: 20)
        if isShowingSuggestedSources {
            let linkedIDs = Set(wellSources.map(\.uuid))
            suggestedWellSources.removeAll { linkedIDs.contains($0.uuid) }
        }
    }

    @MainActor
    private func requestSuggestedSources() async {
        isShowingSuggestedSources = true
        isLoadingSuggestedSources = true
        let linkedIDs = Set(wellSources.map(\.uuid))
        var suggestionSeed = atom
        suggestionSeed.title = viewModel.editableTitle
        let suggestions = await coDevEngine.findSourceMaterials(for: suggestionSeed, limit: 8)
            .filter { !linkedIDs.contains($0.uuid) }
        suggestedWellSources = suggestions
        isLoadingSuggestedSources = false
    }

    @MainActor
    private func linkSourceToConnection(_ source: Atom) async {
        // Preflight both endpoints: addingLink silently no-ops on a corrupt
        // links column, so proceeding would pretend the link was created.
        guard !source.linksAreCorrupt else {
            PersistenceHealth.note(
                .decodeFailure,
                context: "ConnectionFocusMode.linkSource",
                detail: "source \(source.uuid) links column corrupt; link not created (connection \(atom.uuid))"
            )
            return
        }

        var updatedSource = source
        let hasConnectionLink = updatedSource.linksList.contains {
            $0.uuid == atom.uuid &&
            ($0.entityType == AtomType.connection.rawValue ||
             $0.type == AtomLinkType.connection.rawValue ||
             $0.type == AtomLinkType.related.rawValue)
        }

        if !hasConnectionLink {
            updatedSource = updatedSource.addingLink(.related(atom.uuid, entityType: .connection))
            do {
                try await AtomRepository.shared.update(updatedSource)
            } catch {
                PersistenceHealth.note(
                    .writeFailure,
                    context: "ConnectionFocusMode.linkSource",
                    detail: "source endpoint write failed (source \(source.uuid), connection \(atom.uuid)): \(error.localizedDescription)"
                )
                return
            }
        }

        if var updatedConnection = try? await AtomRepository.shared.fetch(uuid: atom.uuid) {
            let hasSourceLink = updatedConnection.linksList.contains { $0.uuid == source.uuid }
            if !hasSourceLink {
                if updatedConnection.linksAreCorrupt {
                    PersistenceHealth.note(
                        .decodeFailure,
                        context: "ConnectionFocusMode.linkSource",
                        detail: "connection \(atom.uuid) links column corrupt; pair half-linked (source \(source.uuid) already written)"
                    )
                } else {
                    updatedConnection = updatedConnection.addingLink(.related(source.uuid, entityType: source.type))
                    do {
                        try await AtomRepository.shared.update(updatedConnection)
                    } catch {
                        // Second endpoint failed — retry once on a fresh copy
                        // before reporting the half-linked pair.
                        do {
                            if var retryConnection = try await AtomRepository.shared.fetch(uuid: atom.uuid),
                               !retryConnection.linksAreCorrupt {
                                retryConnection = retryConnection.addingLink(.related(source.uuid, entityType: source.type))
                                try await AtomRepository.shared.update(retryConnection)
                            }
                        } catch {
                            PersistenceHealth.note(
                                .writeFailure,
                                context: "ConnectionFocusMode.linkSource",
                                detail: "second endpoint write failed; pair half-linked (source \(source.uuid), connection \(atom.uuid)): \(error.localizedDescription)"
                            )
                        }
                    }
                }
            }
        }

        suggestedWellSources.removeAll { $0.uuid == source.uuid }
        await loadSources()
        await viewModel.generateGhostSuggestions()
    }

    // MARK: - Insights

    private func refreshInsights() {
        guard !isRefreshingInsights else { return }
        isRefreshingInsights = true
        Task { @MainActor in
            let insights = await coDevEngine.generateLiveInsights(
                state: viewModel.state,
                conceptType: viewModel.state.conceptType,
                frameworkTitle: viewModel.editableTitle
            )
            if !insights.isEmpty {
                viewModel.state.setLiveInsights(insights)
                viewModel.saveState()
            }
            isRefreshingInsights = false
        }
    }

    @MainActor
    private func refreshInsightsIfStale() async {
        guard viewModel.state.liveInsights.isEmpty,
              viewModel.state.completedSectionCount >= 2 else { return }
        refreshInsights()
    }
}

// MARK: - Connection Focus Mode ViewModel

@MainActor
@Observable
final class ConnectionFocusModeViewModel {

    // MARK: - Observable state

    var state: ConnectionFocusModeState
    var editableTitle: String
    var titleDocument: RichDocument

    // MARK: - Properties

    @ObservationIgnored private let atom: Atom
    @ObservationIgnored private var terminationCancellable: AnyCancellable?
    @ObservationIgnored private var titleSaveTask: Task<Void, Never>?
    /// Tracks whether sections were actually modified in this focus mode session.
    /// Prevents saveToAtom() from overwriting DB sections with stale state
    /// when the user only viewed but didn't edit in focus mode.
    @ObservationIgnored private(set) var sectionsModifiedInFocusMode = false

    // MARK: - Initialization

    init(atom: Atom) {
        self.atom = atom
        self.state = ConnectionFocusModeState(atomUUID: atom.uuid)
        let initialTitleDocument = RichDocumentPersistence.loadAtomDocument(
            field: .title,
            metadata: atom.metadata,
            fallbackPlainText: atom.title ?? "New Connection"
        )
        self.titleDocument = initialTitleDocument
        self.editableTitle = RichDocumentPersistence.titlePlainText(from: initialTitleDocument)
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
        // The UserDefaults blob carries ONLY layout/viewport/insights/view-mode.
        // Sections are owned by the DB (atom.structured): applying the blob's
        // sections here used to clobber fresher DB sections with last session's
        // snapshot, and the next save persisted the regression (RC6).
        if let savedState = ConnectionFocusModeState.load(atomUUID: atom.uuid) {
            let liveSections = state.sections
            state = savedState
            state.sections = liveSections
        }
    }

    /// Replaces in-memory sections with a fresh decode of the atom's structured
    /// column. Called on appear so sections never come from a stale snapshot.
    @MainActor
    func refreshSectionsFromDatabase() async {
        guard let fresh = try? await AtomRepository.shared.fetch(uuid: atom.uuid) else { return }
        applySections(fromStructured: fresh.structured)
    }

    func saveState() {
        state.lastModified = Date()
        state.save()

        // Also save to atom.structured
        saveToAtom()
    }

    // MARK: - Title

    /// UI-driven title edits (navigator title field). Debounced DB write.
    func setTitle(_ newTitle: String) {
        editableTitle = newTitle
        titleDocument = RichDocument.migrateLegacy(newTitle)
        scheduleTitleSave()
    }

    /// Programmatic renames (e.g. the inline assistant's editable surface).
    /// Updates the live UI title and persists immediately.
    func updateTitle(_ newTitle: String) {
        editableTitle = newTitle
        titleDocument = RichDocument.migrateLegacy(newTitle)
        flushTitleSave()
    }

    private func scheduleTitleSave() {
        let atomUUID = atom.uuid
        let document = titleDocument
        let plainTitle = editableTitle
        titleSaveTask?.cancel()
        titleSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
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
                        arguments: [fields.title, fields.metadata, ISO8601.string(from: Date()), atomUUID]
                    )
                }
            } catch {
                print("❌ Connection title save failed: \(error)")
            }
        }
    }

    /// Force immediate synchronous title save (called on view disappear) — blocks until DB write completes.
    func flushTitleSave() {
        titleSaveTask?.cancel()
        let titleDocument = RichDocumentPersistence.normalizedTitleDocument(
            self.titleDocument.isEmpty ? RichDocument.migrateLegacy(editableTitle) : self.titleDocument
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
                    arguments: [fields.title, fields.metadata, ISO8601.string(from: Date()), atomUUID]
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

    // MARK: - Atom persistence

    private func parseAtomStructuredData() {
        applySections(fromStructured: atom.structured)
    }

    private func applySections(fromStructured structured: String?) {
        guard let structured,
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
        guard sectionsModifiedInFocusMode else { return }
        let structuredData = ConnectionStructuredData(sections: state.sections)
        let atomUUID = atom.uuid
        do {
            // Re-fetch the live row (synchronously — this also runs from the
            // app-termination sink). Saving from the immutable open-time `atom`
            // snapshot reverted title/metadata/links to open-time values.
            let fresh = try CosmoDatabase.shared.read { db in
                try Atom.filter(Column("uuid") == atomUUID).fetchOne(db)
            } ?? atom
            // Merge the sections key over existing structured so legacy
            // mental-model keys survive the round-trip.
            var updatedAtom = fresh.mergingStructuredKeys(structuredData)
            updatedAtom.body = state.flattenedBodyText
            // updateSync is versioned, merge-on-conflict, and queues the sync
            // row in the same transaction — no separate ChangeTracker call.
            _ = try AtomRepository.shared.updateSync(updatedAtom)
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "ConnectionFocusMode.saveToAtom(\(atomUUID.prefix(8)))",
                detail: error.localizedDescription
            )
        }
    }

    // MARK: - Item Management

    func addItem(document: RichDocument, plainText: String, toSection type: ConnectionSectionType) {
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

    /// Inserts an item at a specific position: directly after `afterItemID`,
    /// or at the top of the section when nil. Used by the inline assistant's
    /// editable surface so accepted diffs land exactly where they previewed.
    @discardableResult
    func insertItem(
        document: RichDocument,
        plainText: String,
        inSection type: ConnectionSectionType,
        afterItemID: UUID?
    ) -> ConnectionItem? {
        guard let sectionIndex = state.sections.firstIndex(where: { $0.type == type }) else { return nil }
        sectionsModifiedInFocusMode = true
        let item = ConnectionItem(content: plainText, document: document, plainText: plainText)
        if let afterItemID,
           let itemIndex = state.sections[sectionIndex].items.firstIndex(where: { $0.id == afterItemID }) {
            state.sections[sectionIndex].items.insert(item, at: itemIndex + 1)
        } else if afterItemID == nil {
            state.sections[sectionIndex].items.insert(item, at: 0)
        } else {
            state.sections[sectionIndex].items.append(item)
        }
        state.lastModified = Date()
        saveState()
        return item
    }

    func deleteItem(_ id: UUID, fromSection type: ConnectionSectionType) {
        sectionsModifiedInFocusMode = true
        state.removeItem(id: id, fromSection: type)
        saveState()
    }

    func updateConceptType(_ type: ConceptFrameworkType) {
        state.conceptType = type
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
        sectionsModifiedInFocusMode = true
        state.acceptGhost(ghost.id, inSection: type)
        saveState()
    }

    func dismissGhost(_ id: UUID, inSection type: ConnectionSectionType) {
        state.dismissGhost(id, inSection: type)
        saveState()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Connection Focus Mode") {
    ConnectionFocusModeView(
        atom: Atom.new(
            type: .connection,
            title: "Atomic Habits Framework",
            body: "Building lasting habits through small improvements."
        ),
        onClose: {}
    )
    .frame(width: 1280, height: 800)
}
#endif

// ConnectionContextProvider lives in ConnectionEditableSurface.swift — it
// doubles as the inline assistant's editable surface for this connection.
