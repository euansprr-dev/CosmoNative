// CosmoOS/UI/CommandK/CortexResultRail.swift
// Raycast-style left rail. Decision 1C: no SPACES section — the rail is
// purely Recents (empty query) or live grouped results (query active).
// Decision 2B: single tap selects + previews, double tap / Enter opens.

import SwiftUI

enum CommandKDomainOpenTarget: Equatable {
    case atom(String)
    case thinkspace(String)
    case readwiseBook(Int)
}

enum CommandKDomainRailItem: Identifiable {
    case library(LibraryItem)
    case swipe(SwipeGalleryItem)
    case idea(IdeaGalleryItem)
    case readwise(ReadwiseLibraryBook)

    var id: String { selectionID }

    var selectionID: String {
        switch self {
        case .library(let item): return item.uuid
        case .swipe(let item): return item.atomUUID
        case .idea(let item): return item.atomUUID
        case .readwise(let book): return "readwise-\(book.id)"
        }
    }

    var title: String {
        switch self {
        case .library(let item): return item.title
        case .swipe(let item): return item.title
        case .idea(let item): return item.title
        case .readwise(let book): return book.title
        }
    }

    var subtitle: String {
        switch self {
        case .library(let item):
            return [item.typeName, item.provenanceSummary ?? item.relativeDate]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        case .swipe(let item):
            let score = item.hookScore.map { "Score \(Int($0))" }
            return [item.platformName, score].compactMap { $0 }.joined(separator: " · ")
        case .idea(let item):
            return [item.status.displayName, item.clientName].compactMap { $0 }.joined(separator: " · ")
        case .readwise(let book):
            return [book.author, book.category.displayName].compactMap { $0 }.joined(separator: " · ")
        }
    }

    var accent: Color {
        switch self {
        case .library(let item): return item.color
        case .swipe: return DS.entitySwipe
        case .idea: return DS.entityIdea
        case .readwise: return DS.entityReadwise
        }
    }

    var thumbnailURL: String? {
        switch self {
        case .library(let item): return item.thumbnailURL
        case .swipe(let item): return item.thumbnailUrl
        case .idea: return nil
        case .readwise(let book): return book.coverImageUrl
        }
    }

    var previewText: String? {
        switch self {
        case .library(let item): return item.preview
        case .swipe(let item): return item.hookText
        case .idea(let item): return item.context ?? item.body ?? item.hooks.first
        case .readwise(let book): return book.highlights.first?.text ?? "\(book.numHighlights) saved highlights"
        }
    }

    var atomUUID: String? {
        switch self {
        case .library(let item): return item.kind == .thinkspace ? nil : item.uuid
        case .swipe(let item): return item.atomUUID
        case .idea(let item): return item.atomUUID
        case .readwise: return nil
        }
    }

    var atomType: AtomType? {
        switch self {
        case .library(let item): return item.atomType
        case .swipe: return .research
        case .idea: return .idea
        case .readwise: return nil
        }
    }

    var entityId: Int64 {
        switch self {
        case .library(let item): return item.entityId
        case .swipe(let item): return item.entityId
        case .idea(let item): return item.entityId
        case .readwise: return 0
        }
    }

    var isConnection: Bool {
        if case .library(let item) = self { return item.atomType == .connection }
        return false
    }

    var isThinkspace: Bool {
        if case .library(let item) = self { return item.kind == .thinkspace }
        return false
    }

    var openTarget: CommandKDomainOpenTarget {
        switch self {
        case .library(let item):
            return item.kind == .thinkspace ? .thinkspace(item.uuid) : .atom(item.uuid)
        case .swipe(let item):
            return .atom(item.atomUUID)
        case .idea(let item):
            return .atom(item.atomUUID)
        case .readwise(let book):
            return .readwiseBook(book.id)
        }
    }

    var detailSubject: CortexDetailSubject {
        switch self {
        case .library(let item): return .library(item)
        case .swipe(let item): return .swipe(item)
        case .idea(let item): return .idea(item)
        case .readwise(let book): return .readwise(book)
        }
    }
}

enum CommandKDomainRailDataSource {
    static func items(
        for tab: CommandKTab,
        query: String,
        databaseItems: [LibraryItem],
        swipeItems: [SwipeGalleryItem],
        ideaItems: [IdeaGalleryItem],
        readwiseBooks: [ReadwiseLibraryBook]
    ) -> [CommandKDomainRailItem] {
        let allItems = unfilteredItems(
            for: tab,
            databaseItems: databaseItems,
            swipeItems: swipeItems,
            ideaItems: ideaItems,
            readwiseBooks: readwiseBooks
        )
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allItems }
        return allItems.filter { matches($0, query: trimmed) }
    }

    private static func unfilteredItems(
        for tab: CommandKTab,
        databaseItems: [LibraryItem],
        swipeItems: [SwipeGalleryItem],
        ideaItems: [IdeaGalleryItem],
        readwiseBooks: [ReadwiseLibraryBook]
    ) -> [CommandKDomainRailItem] {
        switch tab {
        case .database:
            return databaseItems.map(CommandKDomainRailItem.library)
        case .swipeGallery:
            return swipeItems.map(CommandKDomainRailItem.swipe)
        case .ideas:
            return ideaItems.map(CommandKDomainRailItem.idea)
        case .readwise:
            return readwiseBooks.map(CommandKDomainRailItem.readwise)
        case .inquiry:
            return []
        }
    }

    private static func matches(_ item: CommandKDomainRailItem, query: String) -> Bool {
        switch item {
        case .library(let libraryItem):
            return LibraryTab.matchesSearch(libraryItem, query: query)
        case .swipe(let swipeItem):
            return CommandKViewModel.matchesSwipeGallerySearch(swipeItem, query: query)
        case .idea(let ideaItem):
            return IdeasTab.matchesSearch(ideaItem, query: query)
        case .readwise(let book):
            return ReadwiseBookStore.matchesSearch(book, query: query)
        }
    }
}

struct CortexResultRail: View {
    @ObservedObject var viewModel: CommandKViewModel
    var domainItems: [CommandKDomainRailItem] = []
    var isDomainLoading = false
    var onSelectDomainItem: (CommandKDomainRailItem) -> Void = { _ in }
    var onOpenDomainItem: (CommandKDomainRailItem) -> Void = { _ in }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space6) {
                    railContent
                }
                .padding(DS.space16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.selectedResultIndex) { _, _ in
                guard let id = viewModel.selectedNodeId else { return }
                withAnimation(ProMotionSprings.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private var railContent: some View {
        switch viewModel.cortexMode {
        case .expandedDomain(let tab):
            domainSection(tab)
        case .compact, .searchResults:
            if viewModel.query.isEmpty {
                recentsSection
            } else {
                resultsSections
            }
        }
    }

    // MARK: Recents (empty query)

    @ViewBuilder
    private var recentsSection: some View {
        if viewModel.recentItems.isEmpty {
            railHint("Search your mind, or pick a recent thread.")
        } else {
            AtelierOrnamentalSectionLabel(label: "RECENTS")
            ForEach(viewModel.recentItems) { item in
                CortexRailRow(
                    title: item.title,
                    subtitle: "\(item.type.displayName) · \(item.relativeDate)",
                    accent: cortexEntityAccent(item.type),
                    thumbnailURL: item.thumbnailURL,
                    previewText: item.preview,
                    isConnection: item.type == .connection,
                    isSelected: viewModel.selectedNodeId == item.id,
                    onSelect: {
                        viewModel.selectedNodeId = item.id
                        viewModel.selectedResultIndex =
                            viewModel.recentItems.firstIndex { $0.id == item.id } ?? -1
                    },
                    onOpen: { viewModel.openRecent(item) }
                )
                .id(item.id)
                .commandKCardContextMenu(atomUUID: item.id, entityId: item.entityId, atomType: item.type)
            }
        }
    }

    // MARK: Results (active query)

    @ViewBuilder
    private var resultsSections: some View {
        let groups = viewModel.unifiedGroupedResults.filter { !$0.results.isEmpty }
        if viewModel.primaryAction == nil && groups.isEmpty {
            railHint(viewModel.currentPhase == .searching ? "Searching…" : "No matches yet.")
        } else {
            if let action = viewModel.primaryAction {
                AtelierOrnamentalSectionLabel(label: "COMMAND")
                CortexRailRow(
                    title: action.title,
                    subtitle: action.subtitle ?? "Press return to run",
                    accent: DS.accent,
                    thumbnailURL: nil,
                    previewText: action.subtitle ?? action.payload.rawText,
                    isConnection: false,
                    isSelected: viewModel.selectedNodeId == action.id,
                    onSelect: {
                        viewModel.selectedNodeId = action.id
                        viewModel.selectedResultIndex = 0
                    },
                    onOpen: {
                        viewModel.selectedNodeId = action.id
                        viewModel.selectedResultIndex = 0
                        viewModel.performPrimaryAction()
                    }
                )
                .id(action.id)
            }

            if !viewModel.userCommandRows.isEmpty {
                AtelierOrnamentalSectionLabel(label: "QUICKLINKS")
                ForEach(viewModel.userCommandRows) { row in
                    CortexRailRow(
                        title: row.title,
                        subtitle: row.subtitle,
                        accent: DS.gilt,
                        thumbnailURL: nil,
                        previewText: row.action.subtitle,
                        isConnection: false,
                        isSelected: viewModel.selectedNodeId == row.id,
                        onSelect: {
                            viewModel.selectedNodeId = row.id
                            viewModel.selectedResultIndex =
                                viewModel.userCommandRows.firstIndex { $0.id == row.id } ?? -1
                        },
                        onOpen: {
                            viewModel.selectedNodeId = row.id
                            viewModel.selectedResultIndex =
                                viewModel.userCommandRows.firstIndex { $0.id == row.id } ?? -1
                            viewModel.openSelected()
                        }
                    )
                    .id(row.id)
                }
            }

            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                AtelierOrnamentalSectionLabel(label: group.source.displayName.uppercased())
                ForEach(group.results) { result in
                    CortexRailRow(
                        title: result.title,
                        subtitle: result.subtitle ?? result.snippet ?? "",
                        accent: result.accentColor,
                        thumbnailURL: nil,
                        previewText: result.snippet ?? result.subtitle,
                        isConnection: result.atomType == .connection,
                        isSelected: viewModel.selectedNodeId == result.selectionID,
                        onSelect: { select(result) },
                        onOpen: { select(result); viewModel.openSelected() }
                    )
                    .id(result.selectionID)
                    .commandKSearchResultContextMenu(result: result)
                }
            }
        }
    }

    private func select(_ result: UnifiedSearchResult) {
        viewModel.selectedNodeId = result.selectionID
        viewModel.selectedResultIndex =
            viewModel.unifiedFlatResults.firstIndex { $0.selectionID == result.selectionID } ?? -1
    }

    // MARK: Domain Items (expanded scope)

    @ViewBuilder
    private func domainSection(_ tab: CommandKTab) -> some View {
        if isDomainLoading && domainItems.isEmpty {
            railHint("Gathering \(tab.title.lowercased())…")
        } else if domainItems.isEmpty {
            railHint(viewModel.query.isEmpty ? "Nothing in \(tab.title) yet." : "No \(tab.title.lowercased()) matches.")
        } else {
            AtelierOrnamentalSectionLabel(label: tab.title.uppercased())
            ForEach(domainItems) { item in
                domainRow(item)
            }
        }
    }

    @ViewBuilder
    private func domainRow(_ item: CommandKDomainRailItem) -> some View {
        let row = CortexRailRow(
            title: item.title,
            subtitle: item.subtitle,
            accent: item.accent,
            thumbnailURL: item.thumbnailURL,
            previewText: item.previewText,
            isConnection: item.isConnection,
            isSelected: viewModel.selectedNodeId == item.selectionID,
            onSelect: { onSelectDomainItem(item) },
            onOpen: {
                onSelectDomainItem(item)
                onOpenDomainItem(item)
            }
        )
        .id(item.selectionID)

        if let atomUUID = item.atomUUID, let atomType = item.atomType {
            row.commandKCardContextMenu(
                atomUUID: atomUUID,
                entityId: item.entityId,
                atomType: atomType,
                isThinkspace: false,
                allowsSpatialGoToObject: true
            )
        } else if item.isThinkspace, let atomType = item.atomType {
            row.commandKCardContextMenu(
                atomUUID: item.selectionID,
                entityId: item.entityId,
                atomType: atomType,
                isThinkspace: true,
                allowsSpatialGoToObject: false
            )
        } else {
            row
        }
    }

    private func railHint(_ text: String) -> some View {
        Text(text)
            .font(DS.dateSerif)
            .italic()
            .foregroundStyle(DS.inkFaded)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.space24)
    }
}

private struct CortexRailRow: View {
    let title: String
    let subtitle: String
    let accent: Color
    let thumbnailURL: String?
    let previewText: String?
    let isConnection: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space12) {
            thumbnail
                .frame(width: 38, height: 50)
                .clipShape(.rect(cornerRadius: DS.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                        .strokeBorder(DS.sepiaSubtle, lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: DS.space2) {
                Text(title)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.caption2)
                        .foregroundStyle(DS.inkFaded)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.space8)
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(.rect(cornerRadius: DS.radiusMedium))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint("Double-tap or press return to open")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = thumbnailURL, !url.isEmpty {
            SpotlightImageContent(urlString: url)
        } else if isConnection {
            SpotlightConnectionPreview(preview: previewText, accentColor: accent)
        } else if let text = previewText, !text.isEmpty {
            SpotlightPageContent(text: text, accentColor: accent)
        } else {
            SpotlightFauxPage(accentColor: accent)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .fill(isSelected ? accent.opacity(0.10) : (isHovered ? DS.vellum : Color.clear))
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .strokeBorder(
                isSelected ? accent.opacity(0.45) : (isHovered ? DS.sepiaSubtle : Color.clear),
                lineWidth: isSelected ? 1 : 0.5
            )
    }
}
