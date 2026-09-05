// CosmoOS/UI/CommandK/CortexResultRail.swift
// Raycast-style left rail. Decision 1C: no SPACES section — the rail is
// purely Recents (empty query) or live grouped results (query active).
// Decision 2B: single tap selects + previews, double tap / Enter opens.

import SwiftUI

enum CommandKDomainOpenTarget: Equatable {
    case atom(String)
    case thinkspace(String)
    case readwiseBook(Int)
    /// Jump out of the palette to the Ideas destination (Command-K is the
    /// fast keyboard PATH to ideas — the browse lives on the surface).
    case ideasBoard(clientUUID: String?)
    /// Jump to the content Pipeline (Board / Calendar / List) — Sept 2026.
    case pipeline(view: PipelineView)
    /// Jump to the Clients index.
    case clients
}

enum CommandKDomainRailItem: Identifiable {
    case library(LibraryItem)
    case swipe(SwipeGalleryItem)
    case idea(IdeaGalleryItem)
    case readwise(ReadwiseLibraryBook)
    /// The find-and-jump row for the Ideas surface. Distinct ids for the
    /// browse and search forms so a fresh query re-lands selection on the
    /// top hit instead of sticking to the jump row.
    case ideasBoardJump(clientUUID: String?, clientName: String?, isSearch: Bool)
    /// Find-and-jump rows for the Pipeline and the Clients index — the
    /// keyboard path to the other two Studio › Create rooms.
    case pipelineJump(view: PipelineView)
    case clientsJump

    var id: String { selectionID }

    var selectionID: String {
        switch self {
        case .library(let item): return item.uuid
        case .swipe(let item): return item.atomUUID
        case .idea(let item): return item.atomUUID
        case .readwise(let book): return "readwise-\(book.id)"
        case .ideasBoardJump(_, _, let isSearch): return isSearch ? "ideas-board-jump-search" : "ideas-board-jump"
        case .pipelineJump(let view): return "pipeline-jump-\(view.rawValue)"
        case .clientsJump: return "clients-jump"
        }
    }

    var title: String {
        switch self {
        case .library(let item): return item.title
        case .swipe(let item): return item.title
        case .idea(let item): return item.title
        case .readwise(let book): return book.title
        case .ideasBoardJump(_, let clientName, _):
            return clientName.map { "Open \($0)'s board" } ?? "Open Ideas board"
        case .pipelineJump(let view):
            return "Open Pipeline · \(view.title)"
        case .clientsJump:
            return "Open Clients"
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
        case .ideasBoardJump:
            return "Jump to the Ideas surface ↵"
        case .pipelineJump:
            return "Jump to the content Pipeline ↵"
        case .clientsJump:
            return "Jump to your Clients ↵"
        }
    }

    var accent: Color {
        switch self {
        case .library(let item): return item.color
        case .swipe: return DS.entitySwipe
        // An idea with a client wears the client's color — identity over
        // the generic entity tint.
        case .idea(let item):
            return item.clientUUID.map { DS.clientColor(for: $0) } ?? DS.entityIdea
        case .readwise: return DS.entityReadwise
        case .ideasBoardJump(let clientUUID, _, _):
            return clientUUID.map { DS.clientColor(for: $0) } ?? DS.entityIdea
        case .pipelineJump, .clientsJump:
            return DS.accent
        }
    }

    var thumbnailURL: String? {
        switch self {
        case .library(let item): return item.thumbnailURL
        case .swipe(let item): return item.thumbnailUrl
        case .idea: return nil
        case .readwise(let book): return book.coverImageUrl
        case .ideasBoardJump, .pipelineJump, .clientsJump: return nil
        }
    }

    /// Host for a favicon mark — URL-backed objects carry their site's own
    /// identity (the Raycast register); nil falls through to previews/chips.
    var faviconHost: String? {
        switch self {
        case .readwise(let book):
            return book.sourceUrl.flatMap { URL(string: $0)?.host }
        default:
            return nil
        }
    }

    var previewText: String? {
        switch self {
        case .library(let item): return item.preview
        case .swipe(let item): return item.hookText
        case .idea(let item):
            return CommandKPreviewExcerpt.clampOptional(
                item.context ?? item.body ?? item.hooks.first,
                limit: CommandKPreviewExcerpt.thumbnailLimit
            )
        case .readwise(let book): return book.highlights.first?.text ?? "\(book.numHighlights) saved highlights"
        case .ideasBoardJump, .pipelineJump, .clientsJump: return nil
        }
    }

    var visualIdentity: CommandKVisualIdentity {
        switch self {
        case .library(let item):
            return item.kind == .thinkspace
                ? CommandKVisualIdentity.atom(type: .thinkspace)
                : CommandKVisualIdentity.atom(type: item.atomType)
        case .swipe:
            return CommandKVisualIdentity(
                style: .swipeFile,
                symbolName: "bolt",
                title: "Swipe File",
                subtitle: "Hook capture",
                badge: "SWIPE"
            )
        case .idea:
            return CommandKVisualIdentity.atom(type: .idea)
        case .readwise(let book):
            return CommandKVisualIdentity(
                style: .readwise,
                symbolName: book.category.icon,
                title: "Library",
                subtitle: book.category.displayName,
                badge: "BOOK"
            )
        case .ideasBoardJump:
            return CommandKVisualIdentity.atom(type: .idea)
        case .pipelineJump:
            return CommandKVisualIdentity.atom(type: .content)
        case .clientsJump:
            return CommandKVisualIdentity.atom(type: .clientProfile)
        }
    }

    var atomUUID: String? {
        switch self {
        case .library(let item): return item.kind == .thinkspace ? nil : item.uuid
        case .swipe(let item): return item.atomUUID
        case .idea(let item): return item.atomUUID
        case .readwise: return nil
        case .ideasBoardJump, .pipelineJump, .clientsJump: return nil
        }
    }

    var atomType: AtomType? {
        switch self {
        case .library(let item): return item.atomType
        case .swipe: return .research
        case .idea: return .idea
        case .readwise: return nil
        case .ideasBoardJump, .pipelineJump, .clientsJump: return nil
        }
    }

    var entityId: Int64 {
        switch self {
        case .library(let item): return item.entityId
        case .swipe(let item): return item.entityId
        case .idea(let item): return item.entityId
        case .readwise: return 0
        case .ideasBoardJump, .pipelineJump, .clientsJump: return 0
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
        case .ideasBoardJump(let clientUUID, _, _):
            return .ideasBoard(clientUUID: clientUUID)
        case .pipelineJump(let view):
            return .pipeline(view: view)
        case .clientsJump:
            return .clients
        }
    }

    var detailSubject: CortexDetailSubject {
        switch self {
        case .library(let item): return .library(item)
        case .swipe(let item): return .swipe(item)
        case .idea(let item): return .idea(item)
        case .readwise(let book): return .readwise(book)
        case .ideasBoardJump, .pipelineJump, .clientsJump: return .empty
        }
    }
}

struct CommandKIdeaRailSection: Identifiable {
    let id: String
    let title: String
    let color: Color
    let items: [IdeaGalleryItem]

    var countText: String {
        "\(items.count) idea\(items.count == 1 ? "" : "s")"
    }
}

enum CommandKIdeaRailGrouping {
    private static let unassignedSectionID = "unassigned"

    static func sections(from ideas: [IdeaGalleryItem]) -> [CommandKIdeaRailSection] {
        var groupedItems: [String: [IdeaGalleryItem]] = [:]
        var sectionTitles: [String: String] = [:]
        var colorSeeds: [String: String] = [:]
        var unassigned: [IdeaGalleryItem] = []

        for idea in ideas {
            guard let key = profileKey(for: idea) else {
                unassigned.append(idea)
                continue
            }

            groupedItems[key, default: []].append(idea)
            sectionTitles[key] = profileTitle(for: idea)
            colorSeeds[key] = idea.clientUUID ?? sectionTitles[key] ?? key
        }

        let profileSections = groupedItems.keys
            .sorted { lhs, rhs in
                let left = sectionTitles[lhs] ?? lhs
                let right = sectionTitles[rhs] ?? rhs
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
            .map { key in
                CommandKIdeaRailSection(
                    id: key,
                    title: sectionTitles[key] ?? "Profile",
                    color: DS.clientColor(for: colorSeeds[key] ?? key),
                    items: sortedIdeas(groupedItems[key] ?? [])
                )
            }

        guard !unassigned.isEmpty else { return profileSections }
        return profileSections + [
            CommandKIdeaRailSection(
                id: unassignedSectionID,
                title: "Unassigned",
                color: DS.entityIdea,
                items: sortedIdeas(unassigned)
            )
        ]
    }

    static func orderedItems(from ideas: [IdeaGalleryItem]) -> [IdeaGalleryItem] {
        sections(from: ideas).flatMap(\.items)
    }

    private static func sortedIdeas(_ ideas: [IdeaGalleryItem]) -> [IdeaGalleryItem] {
        ideas.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static func profileKey(for idea: IdeaGalleryItem) -> String? {
        if let clientUUID = idea.clientUUID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clientUUID.isEmpty {
            return "client-\(clientUUID)"
        }

        guard let clientName = idea.clientName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientName.isEmpty else {
            return nil
        }
        return "name-\(clientName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased())"
    }

    private static func profileTitle(for idea: IdeaGalleryItem) -> String {
        guard let title = idea.clientName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return "Profile"
        }
        return title
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
        // Ideas is find-and-jump now: top hits plus the board jump row —
        // the browse lives on the Ideas surface, not in the palette.
        if tab == .ideas {
            return ideasItems(query: query, ideaItems: ideaItems)
        }
        let allItems = unfilteredItems(
            for: tab,
            databaseItems: databaseItems,
            swipeItems: swipeItems,
            ideaItems: ideaItems,
            readwiseBooks: readwiseBooks
        )
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allItems }
        // Normalize ONCE — the per-item matchers used to re-normalize the
        // query for every candidate row.
        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(trimmed)
        return allItems.filter { matches($0, normalizedQuery: normalizedQuery) }
    }

    /// Empty query → the jump row leads, so ⏎ goes straight to the board.
    /// Searching → hits lead (⏎ opens the top hit), the jump row trails and
    /// names the client's board when the hits infer one.
    private static func ideasItems(query: String, ideaItems: [IdeaGalleryItem]) -> [CommandKDomainRailItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let rows = CommandKIdeaRailGrouping.orderedItems(from: ideaItems).map(CommandKDomainRailItem.idea)
            // The other two Studio › Create rooms trail the browse — reachable
            // by arrowing past the ideas, never in front of them.
            return [.ideasBoardJump(clientUUID: nil, clientName: nil, isSearch: false)] + rows
                + [.pipelineJump(view: .board), .clientsJump]
        }

        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(trimmed)
        let hits = ideaItems.filter { IdeasTab.matchesSearch($0, normalizedQuery: normalizedQuery) }
        let rows = CommandKIdeaRailGrouping.orderedItems(from: hits).map(CommandKDomainRailItem.idea)
        let sections = CommandKIdeaRailGrouping.sections(from: hits)
        let inferred = sections.count == 1 && sections[0].title != "Unassigned" ? sections[0] : nil
        return rows + [.ideasBoardJump(
            clientUUID: inferred?.items.first?.clientUUID,
            clientName: inferred?.title,
            isSearch: true
        )] + roomJumps(matching: trimmed)
    }

    /// Typing the room's name surfaces its jump row ("pipe…", "calendar",
    /// "clients"); anything else keeps the rail to idea hits.
    static func roomJumps(matching query: String) -> [CommandKDomainRailItem] {
        let q = query.lowercased()
        var rows: [CommandKDomainRailItem] = []
        if q.hasPrefix("cal") {
            rows.append(.pipelineJump(view: .calendar))
        } else if q.hasPrefix("pipe") || q.hasPrefix("board") || q.hasPrefix("content") {
            rows.append(.pipelineJump(view: .board))
        }
        if q.hasPrefix("client") {
            rows.append(.clientsJump)
        }
        return rows
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
            // Handled by ideasItems(query:ideaItems:) — never reached.
            return []
        case .readwise:
            return readwiseBooks.map(CommandKDomainRailItem.readwise)
        case .inquiry:
            return []
        }
    }

    private static func matches(_ item: CommandKDomainRailItem, normalizedQuery: String) -> Bool {
        switch item {
        case .library(let libraryItem):
            return LibraryTab.matchesSearch(libraryItem, normalizedQuery: normalizedQuery)
        case .swipe(let swipeItem):
            return CommandKViewModel.matchesSwipeGallerySearch(swipeItem, normalizedQuery: normalizedQuery)
        case .idea(let ideaItem):
            return IdeasTab.matchesSearch(ideaItem, normalizedQuery: normalizedQuery)
        case .readwise(let book):
            return ReadwiseBookStore.matchesSearch(book, normalizedQuery: normalizedQuery)
        case .ideasBoardJump, .pipelineJump, .clientsJump:
            return true
        }
    }
}

struct CortexResultRail: View {
    var viewModel: CommandKViewModel
    var domainItems: [CommandKDomainRailItem] = []
    var isDomainLoading = false
    var onSelectDomainItem: (CommandKDomainRailItem) -> Void = { _ in }
    var onOpenDomainItem: (CommandKDomainRailItem) -> Void = { _ in }

    @State private var railScrollMetrics = CortexScrollMetricsStore()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space6) {
                    railContent
                }
                .padding(DS.space16)
                .background(CortexScrollViewIntrospector { [railScrollMetrics] metrics in
                    railScrollMetrics.publish(metrics)
                })
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .cortexThinScrollbar(store: railScrollMetrics)
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
            CommandKSectionLabel(label: "RECENTS", count: viewModel.recentItems.count)
            ForEach(viewModel.recentItems) { item in
                CortexRailRow(
                    title: item.title,
                    subtitle: "\(item.type.displayName) · \(item.relativeDate)",
                    accent: cortexEntityAccent(item.type),
                    visualIdentity: CommandKVisualIdentity.atom(type: item.type),
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
                // The retrieve verb: any recent can be dragged out of the
                // palette onto the canvas (the palette ghosts mid-drag).
                .modifier(CommandKDragOutModifier(
                    uuid: item.id,
                    title: item.title,
                    subtitle: "\(item.type.displayName) · \(item.relativeDate)",
                    accent: cortexEntityAccent(item.type),
                    symbolName: CommandKVisualIdentity.atom(type: item.type).symbolName,
                    thumbnailURL: item.thumbnailURL
                ))
                .commandKCardContextMenu(atomUUID: item.id, entityId: item.entityId, atomType: item.type)
            }
        }
    }

    // MARK: Results (active query)

    @ViewBuilder
    private var resultsSections: some View {
        let groups = viewModel.unifiedGroupedResults.filter { !$0.results.isEmpty }
        if viewModel.primaryAction == nil && groups.isEmpty {
            if viewModel.searchFeedback.matches(query: viewModel.query) {
                railHint("No matches — try fewer words, or keep typing to create a task.")
            } else {
                Color.clear.frame(height: 1)
            }
        } else {
            if let action = viewModel.primaryAction, action.kind == .calculator {
                calculatorSection(action)
            } else if let action = viewModel.primaryAction {
                let commandCount = 1
                    + (viewModel.secondaryAction != nil ? 1 : 0)
                    + viewModel.userCommandRows.count
                CommandKSectionLabel(label: "COMMANDS", count: commandCount)
                CortexRailRow(
                    title: action.title,
                    subtitle: action.subtitle ?? "Press return to run",
                    accent: DS.accent,
                    visualIdentity: CommandKVisualIdentity.action(action),
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

                // The other capture verb for the same link (swipe ↔ research):
                // the URL's source type picks the default row above, never
                // the set of options.
                if let secondary = viewModel.secondaryAction {
                    CortexRailRow(
                        title: secondary.title,
                        subtitle: secondary.subtitle ?? "Press return to run",
                        accent: DS.accent,
                        visualIdentity: CommandKVisualIdentity.action(secondary),
                        thumbnailURL: nil,
                        previewText: secondary.subtitle ?? secondary.payload.rawText,
                        isConnection: false,
                        isSelected: viewModel.selectedNodeId == secondary.id,
                        onSelect: {
                            viewModel.selectedNodeId = secondary.id
                            viewModel.selectedResultIndex =
                                viewModel.searchSelectionIndex(for: secondary.id)
                        },
                        onOpen: {
                            viewModel.selectedNodeId = secondary.id
                            viewModel.selectedResultIndex =
                                viewModel.searchSelectionIndex(for: secondary.id)
                            viewModel.openSelected()
                        }
                    )
                    .id(secondary.id)
                }
            }

            if !viewModel.userCommandRows.isEmpty {
                ForEach(viewModel.userCommandRows) { row in
                    CortexRailRow(
                        title: row.title,
                        subtitle: row.subtitle,
                        accent: DS.gilt,
                        visualIdentity: CommandKVisualIdentity.action(row.action),
                        thumbnailURL: nil,
                        previewText: row.action.subtitle,
                        isConnection: false,
                        isSelected: viewModel.selectedNodeId == row.id,
                        onSelect: {
                            viewModel.selectedNodeId = row.id
                            viewModel.selectedResultIndex =
                                viewModel.searchSelectionIndex(for: row.id)
                        },
                        onOpen: {
                            viewModel.selectedNodeId = row.id
                            viewModel.selectedResultIndex =
                                viewModel.searchSelectionIndex(for: row.id)
                            viewModel.openSelected()
                        }
                    )
                    .id(row.id)
                }
            }

            ForEach(groups, id: \.source) { group in
                CommandKSectionLabel(label: group.source.displayName.uppercased(), count: group.results.count)
                ForEach(group.results) { result in
                    CortexRailRow(
                        title: result.title,
                        subtitle: result.subtitle ?? result.snippet ?? "",
                        accent: result.accentColor,
                        visualIdentity: CommandKVisualIdentity.result(result),
                        thumbnailURL: result.thumbnailURL,
                        faviconHost: Self.faviconHost(for: result),
                        previewText: result.snippet ?? result.subtitle,
                        matchedExcerptLine: excerptLine(for: result),
                        isConnection: result.atomType == .connection,
                        isSelected: viewModel.selectedNodeId == result.selectionID,
                        onSelect: { select(result) },
                        onOpen: { select(result); viewModel.openSelected() }
                    )
                    .id(result.selectionID)
                    .modifier(Self.dragOutModifier(for: result))
                    .commandKSearchResultContextMenu(result: result)
                }
            }
        }
    }

    /// The calculator claims its own section: the Raycast split card
    /// (expression | answer) instead of a command row. When quicklinks also
    /// match, they keep their COMMANDS header below.
    @ViewBuilder
    private func calculatorSection(_ action: CommandKAction) -> some View {
        CommandKSectionLabel(label: "CALCULATOR")
        CommandKCalculatorRailCard(
            expression: action.payload.expressionText ?? action.payload.rawText ?? "",
            result: action.payload.resultText ?? "",
            isSelected: viewModel.selectedNodeId == nil || viewModel.selectedNodeId == action.id,
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
        if !viewModel.userCommandRows.isEmpty {
            CommandKSectionLabel(label: "COMMANDS", count: viewModel.userCommandRows.count)
        }
    }

    /// Extracted (not inline) — the row builder sits at the type-checker's
    /// budget edge.
    private static func faviconHost(for result: UnifiedSearchResult) -> String? {
        result.faviconHost ?? result.browserURL?.host
    }

    /// Body-evidence rows show the matched sentence with the query tokens
    /// emphasized; title-tier rows keep their clean type subtitle so name
    /// searches stay quiet.
    private func excerptLine(for result: UnifiedSearchResult) -> AttributedString? {
        guard result.lexicalTier >= .phraseInBody,
              let excerpt = result.matchedExcerpt, !excerpt.isEmpty else { return nil }
        return CommandKMatchHighlighter.attributed(
            excerpt,
            query: viewModel.query,
            baseColor: DS.inkFaded,
            emphasisColor: DS.text,
            font: DS.caption2
        )
    }

    /// Extracted for the same type-checker-budget reason as faviconHost.
    private static func dragOutModifier(for result: UnifiedSearchResult) -> CommandKDragOutModifier {
        CommandKDragOutModifier(
            uuid: result.atomUUID ?? result.selectionID,
            title: result.title,
            subtitle: result.subtitle ?? result.snippet ?? "",
            accent: result.accentColor,
            symbolName: CommandKVisualIdentity.result(result).symbolName,
            thumbnailURL: result.thumbnailURL,
            faviconHost: faviconHost(for: result)
        )
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
        } else if tab == .ideas {
            ideaDomainSection(domainItems)
        } else {
            CommandKSectionLabel(label: tab.title.uppercased(), count: domainItems.count)
            ForEach(domainItems) { item in
                domainRow(item)
            }
        }
    }

    @ViewBuilder
    private func ideaDomainSection(_ items: [CommandKDomainRailItem]) -> some View {
        let ideas = items.compactMap { item -> IdeaGalleryItem? in
            if case .idea(let idea) = item { return idea }
            return nil
        }
        let jump = items.first { if case .ideasBoardJump = $0 { return true } else { return false } }
        let jumpLeads: Bool = {
            if case .ideasBoardJump = items.first { return true }
            return false
        }()
        let sections = CommandKIdeaRailGrouping.sections(from: ideas)

        if jumpLeads, let jump {
            domainRow(jump)
        }
        CommandKSectionLabel(label: "IDEAS", count: ideas.count)
        ForEach(sections) { section in
            ideaProfileHeader(section)
            ForEach(section.items, id: \.atomUUID) { idea in
                domainRow(.idea(idea))
            }
        }
        if !jumpLeads, let jump {
            domainRow(jump)
        }
    }

    private func ideaProfileHeader(_ section: CommandKIdeaRailSection) -> some View {
        HStack(spacing: DS.space8) {
            Circle()
                .fill(section.color.opacity(0.82))
                .frame(width: 6, height: 6)
            Text(section.title)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: DS.space8)
            Text(section.countText)
                .font(DS.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.space8)
        .padding(.top, DS.space10)
        .padding(.bottom, DS.space2)
    }

    @ViewBuilder
    private func domainRow(_ item: CommandKDomainRailItem) -> some View {
        let row = CortexRailRow(
            title: item.title,
            subtitle: item.subtitle,
            accent: item.accent,
            visualIdentity: item.visualIdentity,
            thumbnailURL: item.thumbnailURL,
            faviconHost: item.faviconHost,
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
            row.modifier(CommandKDragOutModifier(
                uuid: atomUUID,
                title: item.title,
                subtitle: item.subtitle,
                accent: item.accent,
                symbolName: item.visualIdentity.symbolName,
                thumbnailURL: item.thumbnailURL,
                faviconHost: item.faviconHost
            ))
                .commandKCardContextMenu(
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
    let visualIdentity: CommandKVisualIdentity?
    let thumbnailURL: String?
    var faviconHost: String? = nil
    let previewText: String?
    /// Matched-context excerpt with query tokens pre-emphasized. When
    /// present it replaces the subtitle line: a body match should show the
    /// sentence it matched, not the type name (the Omnisearch anatomy).
    var matchedExcerptLine: AttributedString? = nil
    let isConnection: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space12) {
            thumbnailSlot
            VStack(alignment: .leading, spacing: DS.space2) {
                Text(title)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                if let matchedExcerptLine {
                    Text(matchedExcerptLine)
                        .lineLimit(1)
                } else if !subtitle.isEmpty {
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

    /// The rail is Raycast's icon territory: real media thumbnails and
    /// favicons are identity and stay; everything else gets the compact
    /// identity chip. Content excerpts live in the detail pane, not the
    /// list — 38pt text micro-pages read as noise, and a command's subtitle
    /// typeset as a fake document was the worst offender.
    @ViewBuilder
    private var thumbnailSlot: some View {
        if let url = thumbnailURL, !url.isEmpty {
            framedObject { SpotlightImageContent(urlString: url) }
        } else if let host = faviconHost {
            bareMark { CommandKFavicon(host: host) { identityChip } }
        } else if visualIdentity != nil {
            bareMark { identityChip }
        } else {
            framedObject { SpotlightFauxPage(accentColor: accent) }
        }
    }

    @ViewBuilder
    private var identityChip: some View {
        if let visualIdentity {
            CosmoIdentityChip(systemName: visualIdentity.symbolName, tint: accent)
        }
    }

    /// Object previews (media, pages, miniatures) wear the object edge.
    private func framedObject<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: 38, height: 50)
            .clipShape(.rect(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                    .strokeBorder(DS.commandChromeSeparator, lineWidth: 0.5)
            )
    }

    /// Bare marks (chip, favicon) float in the slot — a stroked frame around
    /// a 22pt chip would be another container.
    private func bareMark<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: 38, height: 50)
    }

    private var rowBackground: some View {
        // Matches the sidebar row recipe so rail + sidebar rows read as one family.
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .fill(isSelected ? accent.opacity(0.10) : (isHovered ? DS.surfaceHover.opacity(0.40) : Color.clear))
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .strokeBorder(
                isSelected ? accent.opacity(0.45) : (isHovered ? DS.commandChromeSeparator : Color.clear),
                lineWidth: isSelected ? 1 : 0.5
            )
    }
}
