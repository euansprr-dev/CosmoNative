// CosmoOS/UI/CommandK/CortexMasterDetailView.swift
// Raycast-style Command-K shell: one two-pane glass surface for recents,
// search results, and expanded domain scopes.

import SwiftUI

struct CortexMasterDetailView: View {
    @ObservedObject var viewModel: CommandKViewModel
    var isDomainHydrated = true

    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var bookStore = ReadwiseBookStore.shared
    @State private var isLoadingDomain = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CortexResultRail(
                    viewModel: viewModel,
                    domainItems: domainItems,
                    isDomainLoading: isLoadingDomain || (isExpandedDomain && !isDomainHydrated),
                    onSelectDomainItem: selectDomainItem,
                    onOpenDomainItem: openDomainItem
                )
                    .frame(width: 360)

                Rectangle()
                    .fill(DS.sepiaBorder)
                    .frame(width: 0.5)

                CortexDetailPane(subject: detailSubject)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            CortexActionBar(
                viewModel: viewModel,
                selectedAtomUUID: detailSubject.atomUUID,
                hasSelection: hasSelection,
                onOpen: { viewModel.openSelected() }
            )
        }
        .task(id: domainLoadKey) { await loadDomainDataIfNeeded() }
        .onChange(of: domainSelectionIDs) { _, _ in syncDomainNavigation() }
        .onChange(of: viewModel.cortexMode) { _, _ in syncDomainNavigation() }
    }

    /// Resolve the current selection (driven by keyboard nav + row taps) into
    /// a uniform preview subject without the panes knowing the source.
    private var detailSubject: CortexDetailSubject {
        guard let id = viewModel.selectedNodeId else { return .empty }
        if let domainItem = selectedDomainItem(for: id) {
            return domainItem.detailSubject
        } else if viewModel.query.isEmpty {
            if let item = viewModel.recentItems.first(where: { $0.id == id }) {
                return .recent(item)
            }
        } else if let result = viewModel.unifiedFlatResults.first(where: { $0.selectionID == id }) {
            return .result(result)
        }
        return .empty
    }

    private var hasSelection: Bool {
        if case .empty = detailSubject { return false }
        return true
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
}
