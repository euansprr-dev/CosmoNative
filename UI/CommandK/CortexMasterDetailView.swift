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

    var body: some View {
        let subject = visibleDetailSubject

        VStack(spacing: 0) {
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

            CortexActionBar(
                viewModel: viewModel,
                primaryAction: primaryAction,
                actions: contextualActions,
                hasSelection: hasSelection,
                onOpen: { viewModel.openSelected() },
                onShowActions: showActionPanel
            )
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
        .onChange(of: domainSelectionIDs) { _, _ in syncDomainNavigation() }
        .onChange(of: viewModel.cortexMode) { _, _ in syncDomainNavigation() }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            showActionPanel()
        }
    }

    private var actionPanel: some View {
        CommandKActionPanel(
            title: "Command K Actions",
            groups: actionGroups,
            errorMessage: actionErrorMessage,
            execute: executeContextualAction,
            dismiss: { viewModel.isActionPanelPresented = false },
            searchQuery: $actionSearchQuery
        )
    }

    /// Resolve the current selection (driven by keyboard nav + row taps) into
    /// a uniform preview subject without the panes knowing the source.
    private var detailSubject: CortexDetailSubject {
        guard let id = viewModel.selectedNodeId else { return .empty }
        if let action = viewModel.primaryAction, action.id == id {
            return .action(action)
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
            hydratedAtom: nil,
            mode: viewModel.cortexMode,
            activeInquirySessionUUID: nil,
            activeContentDraftUUID: nil
        )
    }

    private var contextualActions: [CommandKContextualAction] {
        CommandKActionRegistry().actions(for: actionContext)
    }

    private var actionGroups: [(category: CommandKActionCategory, actions: [CommandKContextualAction])] {
        CommandKActionRegistry().groupedActions(for: actionContext)
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

    private var domainItems: [CommandKDomainRailItem] {
        guard case .expandedDomain(let tab) = viewModel.cortexMode, isDomainHydrated else { return [] }
        return CommandKDomainRailDataSource.items(
            for: tab,
            query: viewModel.query,
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
            syncDomainNavigation()
            return
        }

        isLoadingDomain = true
        switch tab {
        case .database:
            await libraryVM.loadLibrary()
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
        viewModel.openSelected()
    }

    private func showActionPanel() {
        guard !contextualActions.isEmpty else { return }
        actionErrorMessage = nil
        actionSearchQuery = ""
        viewModel.isActionPanelPresented = true
    }

    private func executeContextualAction(_ action: CommandKContextualAction) {
        guard action.availability.isEnabled else { return }
        actionErrorMessage = nil
        Task { @MainActor in
            do {
                try await CommandKActionExecutor().execute(action.intent)
                viewModel.isActionPanelPresented = false
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }
}
