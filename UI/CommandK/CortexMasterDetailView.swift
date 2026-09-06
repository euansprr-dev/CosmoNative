// CosmoOS/UI/CommandK/CortexMasterDetailView.swift
// Raycast-style Command-K shell: one two-pane glass surface for recents,
// search results, and expanded domain scopes.

import SwiftUI

struct CortexMasterDetailView: View {
    var viewModel: CommandKViewModel
    var isDomainHydrated = true

    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var bookStore = ReadwiseBookStore.shared
    @State private var isLoadingDomain = false
    @State private var actionSearchQuery = ""
    @State private var actionErrorMessage: String?
    @State private var cachedDetailSubject: CortexDetailSubject = .empty
    /// Domain rail rows, cached — the filter used to re-run for EVERY body
    /// evaluation (selection moves included); now it recomputes only when
    /// `domainItemsKey` changes. Every input that key folds in MUST be
    /// observation-tracked, or a change to it never reaches `onChange` and
    /// the rail silently serves stale rows (see `domainFilterQuery`).
    @State private var cachedDomainItems: [CommandKDomainRailItem] = []

    var body: some View {
        let subject = visibleDetailSubject

        VStack(spacing: 0) {
            if viewModel.isSelectionPicker { CommandKPickerHeader(viewModel: viewModel) }
            HStack(spacing: 0) {
                CortexResultRail(
                    viewModel: viewModel,
                    domainItems: domainItems,
                    isDomainLoading: isLoadingDomain || (isExpandedDomain && !isDomainHydrated),
                    onSelectDomainItem: selectDomainItem,
                    onOpenDomainItem: openDomainItem
                )
                    .frame(width: CommandKMetrics.railWidth)

                Rectangle()
                    .fill(DS.commandChromeSeparatorStrong)
                    .frame(width: 0.5)

                CortexDetailPane(subject: subject, viewModel: viewModel)
                    .frame(maxWidth: .infinity)
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
            }
            .frame(maxHeight: .infinity)
            // ONE ground for the whole body (the Raycast anatomy): results
            // and previews are content, so they sit on near-opaque paper —
            // the inner white cards and fills existed only because text on
            // lensed glass was illegible. Chrome (search pill, panel edge,
            // action bar) stays glass.
            .background(DS.bg.opacity(0.96))

            if viewModel.isSelectionPicker {
                CommandKPickerFooter(viewModel: viewModel)
            } else { CortexActionBar(
                viewModel: viewModel,
                primaryAction: primaryAction,
                actions: contextualActions,
                hasSelection: hasSelection,
                onOpen: { viewModel.openSelected() },
                onShowActions: showActionPanel
            ) }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.isActionPanelPresented {
                actionPanel
                    .padding(.trailing, DS.space20)
                    .padding(.bottom, 58)
                    .transition(.scale(scale: 0.98, anchor: .bottomTrailing).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(ProMotionSprings.snappy, value: viewModel.isActionPanelPresented)
        .onAppear { syncCachedDetailSubject() }
        .onChange(of: detailSubject.renderSignature) { _, _ in syncCachedDetailSubject() }
        .onChange(of: viewModel.selectedNodeId) { _, _ in syncCachedDetailSubject() }
        .task(id: domainLoadKey) { await loadDomainDataIfNeeded() }
        .task(id: visibleDetailSubject.selectionIdentity) {
            await viewModel.hydrateSpaceSelection(visibleDetailSubject.atomUUID)
        }
        .onChange(of: viewModel.spaceDestinationPicker?.root?.spaceID) { _, _ in actionSearchQuery = "" }
        .onChange(of: viewModel.isActionPanelPresented) { _, presented in
            actionSearchQuery = ""
            if !presented { viewModel.dismissSpaceDestinationPicker() }
        }
        .onChange(of: domainItemsKey) { _, _ in refreshDomainItems() }
        .onChange(of: domainSelectionIDs) { _, _ in syncDomainNavigation() }
        .onChange(of: viewModel.cortexMode) { _, _ in syncDomainNavigation() }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            showActionPanel()
        }
    }

    private var actionPanel: some View {
        CommandKActionPanel(
            title: viewModel.spaceDestinationPicker == nil ? "Command K Actions" : viewModel.spaceDestinationPickerTitle,
            groups: viewModel.spaceDestinationPicker == nil ? actionGroups : viewModel.spaceDestinationActions,
            errorMessage: viewModel.actionStatusMessage ?? actionErrorMessage,
            emptyMessage: viewModel.spaceDestinationPicker?.isLoading == true ? "Loading destinations…" : "No matching destinations",
            execute: executeContextualAction,
            dismiss: { viewModel.dismissSpaceDestinationPicker() },
            searchQuery: $actionSearchQuery
        )
    }

    /// Resolve the current selection (driven by keyboard nav + row taps) into
    /// a uniform preview subject without the panes knowing the source.
    private var detailSubject: CortexDetailSubject {
        guard let id = viewModel.selectedNodeId else { return .empty }
        if let action = viewModel.primaryAction, action.id == id {
            return .action(action)
        } else if let secondary = viewModel.secondaryAction, secondary.id == id {
            return .action(secondary)
        } else if let row = viewModel.userCommandRows.first(where: { $0.id == id }) {
            return .action(row.action)
        } else if let domainItem = selectedDomainItem(for: id) {
            return domainItem.detailSubject
        } else if viewModel.query.isEmpty {
            if let item = viewModel.recentItems.first(where: { $0.id == id }) {
                if let swipe = swipeItem(atomUUID: item.id) { return .swipe(swipe) }
                if let idea = ideaItem(atomUUID: item.id) { return .idea(idea) }
                return .recent(item)
            }
        } else if let result = viewModel.unifiedFlatResults.first(where: { $0.selectionID == id }) {
            if let atomUUID = result.atomUUID, let swipe = swipeItem(atomUUID: atomUUID) { return .swipe(swipe) }
            if let atomUUID = result.atomUUID, let idea = ideaItem(atomUUID: atomUUID) { return .idea(idea) }
            if let bookID = result.readwiseBookId, let book = readwiseBook(id: bookID) { return .readwise(book) }
            return .result(result)
        }
        return .empty
    }

    private var hasSelection: Bool {
        !visibleDetailSubject.isEmpty
    }

    private var actionContext: CommandKActionContext {
        CommandKActionContext(
            query: viewModel.query,
            subject: visibleDetailSubject,
            hydratedAtom: viewModel.selectedSpaceAtom.flatMap { $0.uuid == visibleDetailSubject.atomUUID ? $0 : nil },
            mode: viewModel.cortexMode,
            activeInquirySessionUUID: nil,
            activeContentDraftUUID: nil,
            spaceContext: viewModel.spaceContext,
            selectedSpaceInfo: selectedSubjectSpaceInfo,
            selectedUUIDs: viewModel.selectedUUIDs
        )
    }

    private var selectedSubjectSpaceInfo: CommandKSpaceSearchInfo? {
        if case .result(let result) = visibleDetailSubject, let info = result.spaceInfo { return info }
        return viewModel.selectedSpaceAtom?.uuid == visibleDetailSubject.atomUUID ? viewModel.selectedSpaceInfo : nil
    }

    private var contextualActions: [CommandKContextualAction] {
        viewModel.isSelectionPicker ? [] : CommandKActionRegistry().actions(for: actionContext)
    }

    private var actionGroups: [(category: CommandKActionCategory, actions: [CommandKContextualAction])] {
        viewModel.isSelectionPicker ? [] : CommandKActionRegistry().groupedActions(for: actionContext)
    }

    private var primaryAction: CommandKContextualAction? {
        contextualActions.first { $0.category == .primary }
    }

    private var visibleDetailSubject: CortexDetailSubject {
        let current = detailSubject
        guard current.isEmpty,
              let selectedID = viewModel.selectedNodeId,
              cachedDetailSubject.selectionIdentity == selectedID else {
            return current
        }
        return cachedDetailSubject
    }

    private func syncCachedDetailSubject() {
        let current = detailSubject
        if current.isEmpty {
            if viewModel.selectedNodeId == nil {
                cachedDetailSubject = .empty
            }
        } else {
            cachedDetailSubject = current
        }
    }

    private var isExpandedDomain: Bool {
        if case .expandedDomain = viewModel.cortexMode { return true }
        return false
    }

    private var domainItems: [CommandKDomainRailItem] { cachedDomainItems }

    private func refreshDomainItems() {
        cachedDomainItems = computeDomainItems()
    }

    private func computeDomainItems() -> [CommandKDomainRailItem] {
        guard case .expandedDomain(let tab) = viewModel.cortexMode, isDomainHydrated else { return [] }
        if let picker = viewModel.selectionPicker {
            let originals = libraryVM.allItems.map(CommandKDomainRailItem.library)
            var seen = Set<String>()
            return originals.filter { item in
                guard let uuid = item.atomUUID, let type = item.atomType,
                      ![AtomType.thinkspace, .deepDive, .inquirySession].contains(type),
                      seen.insert(uuid).inserted else { return false }
                return picker.includesInScope(uuid)
            }
        }
        return CommandKDomainRailDataSource.items(
            for: tab,
            query: viewModel.domainFilterQuery,
            databaseItems: visibleDatabaseItems,
            swipeItems: viewModel.swipeGalleryItems,
            ideaItems: viewModel.ideaGalleryItems,
            readwiseBooks: bookStore.books
        )
    }

    private var visibleDatabaseItems: [LibraryItem] {
        CommandKDatabaseBrowserDataSource.visibleItems(
            allItems: libraryVM.allItems,
            displayItems: libraryVM.displayItems,
            recentlyDeletedItems: libraryVM.recentlyDeletedItems,
            isAtHome: libraryVM.isAtHome,
            showingRecentlyDeleted: libraryVM.showingRecentlyDeleted
        )
    }

    private var domainSelectionIDs: [String] {
        domainItems.map(\.selectionID)
    }

    private var domainLoadKey: String {
        guard case .expandedDomain(let tab) = viewModel.cortexMode else { return "none" }
        return "\(tab.rawValue)-\(isDomainHydrated)"
    }

    /// Everything `computeDomainItems` reads, folded into one change key:
    /// tab + hydration (domainLoadKey), the query, and the source-array
    /// counts (loads/refreshes only ever swap whole arrays). Raw library
    /// counts + flags stand in for `visibleDatabaseItems` — evaluating the
    /// key must stay cheaper than the compute it gates.
    ///
    /// The query arrives as `domainFilterQuery` (tracked), NOT `query`
    /// (`@ObservationIgnored`): this view is built from just the view model
    /// and a Bool, so a keystroke leaves its view value identical and SwiftUI
    /// skips the body — the key is never re-evaluated and the `onChange`
    /// never fires. Only an observed read gets typing back into this key.
    private var domainItemsKey: String {
        guard case .expandedDomain = viewModel.cortexMode else { return "none" }
        return [
            domainLoadKey,
            "\(viewModel.selectionPicker?.request.id.uuidString ?? "regular")-\(viewModel.selectionPicker?.scope.rawValue ?? "")-\(viewModel.selectionPicker?.isLoading == true)",
            viewModel.domainFilterQuery,
            "\(libraryVM.allItems.count)-\(libraryVM.displayItems.count)-\(libraryVM.recentlyDeletedItems.count)",
            "\(libraryVM.isAtHome)-\(libraryVM.showingRecentlyDeleted)",
            "\(viewModel.swipeGalleryItems.count)",
            "\(viewModel.ideaGalleryItems.count)",
            "\(bookStore.books.count)"
        ].joined(separator: "|")
    }

    private func selectedDomainItem(for id: String) -> CommandKDomainRailItem? {
        guard isExpandedDomain else { return nil }
        return domainItems.first { $0.selectionID == id }
    }

    private func swipeItem(atomUUID: String) -> SwipeGalleryItem? {
        viewModel.swipeGalleryItems.first { $0.atomUUID == atomUUID }
    }

    private func ideaItem(atomUUID: String) -> IdeaGalleryItem? {
        viewModel.ideaGalleryItems.first { $0.atomUUID == atomUUID }
    }

    private func readwiseBook(id: Int) -> ReadwiseLibraryBook? {
        bookStore.books.first { $0.id == id }
    }

    @MainActor
    private func loadDomainDataIfNeeded() async {
        guard case .expandedDomain(let tab) = viewModel.cortexMode, isDomainHydrated else {
            refreshDomainItems()
            syncDomainNavigation()
            return
        }

        isLoadingDomain = true
        switch tab {
        case .database:
            await libraryVM.loadLibrary(includingAllOriginals: viewModel.isSelectionPicker)
        case .swipeGallery:
            await viewModel.loadSwipeGallery()
        case .ideas:
            await viewModel.loadIdeaGallery()
        case .readwise:
            if bookStore.books.isEmpty { await bookStore.loadBooks() }
        case .inquiry:
            break
        }
        isLoadingDomain = false
        // The loads above may not change any count (already-loaded arrays), so
        // the key-driven onChange can't be relied on here — refresh directly.
        refreshDomainItems()
        syncDomainNavigation()
    }

    private func syncDomainNavigation() {
        if isExpandedDomain {
            viewModel.updateExpandedDomainNavigation(items: domainItems)
        } else {
            viewModel.updateExpandedDomainNavigation(items: [])
        }
    }

    private func selectDomainItem(_ item: CommandKDomainRailItem) {
        viewModel.selectedNodeId = item.selectionID
        viewModel.selectedResultIndex = domainItems.firstIndex { $0.selectionID == item.selectionID } ?? -1
    }

    private func openDomainItem(_ item: CommandKDomainRailItem) {
        selectDomainItem(item)
        if !viewModel.isSelectionPicker { viewModel.openSelected() }
    }

    private func showActionPanel() {
        guard !contextualActions.isEmpty else { return }
        actionErrorMessage = nil
        actionSearchQuery = ""
        viewModel.spaceDestinationPicker = nil
        viewModel.isActionPanelPresented = true
    }

    private func executeContextualAction(_ action: CommandKContextualAction) {
        guard action.availability.isEnabled else { return }
        actionErrorMessage = nil
        actionSearchQuery = ""
        viewModel.executeSpaceAction(action.intent)
    }
}
