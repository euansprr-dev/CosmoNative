// CosmoOS/UI/CommandK/CommandKViewModel.swift
// ViewModel for Command-K overlay - manages search state and constellation
// Powers the NodeGraph OS Command-K interface
// Phase 4: Multi-select filters, HybridSearchEngine integration, filter counts

import SwiftUI
import Combine

// MARK: - CommandKTab

/// The domain tabs available in Command-K
public enum CommandKTab: String, CaseIterable, Equatable {
    case database
    case swipeGallery
    case ideas
    case readwise
    case inquiry

    public static var allCases: [CommandKTab] {
        [.database, .swipeGallery, .ideas, .readwise]
    }

    var title: String {
        switch self {
        case .database: return "Database"
        case .swipeGallery: return "Swipe Gallery"
        case .ideas: return "Ideas"
        case .readwise: return "Readwise"
        case .inquiry: return "Inquiry"
        }
    }

    var icon: String {
        switch self {
        case .database: return "tray.full.fill"
        case .swipeGallery: return "bolt.fill"
        case .ideas: return "lightbulb.fill"
        case .readwise: return "books.vertical.fill"
        case .inquiry: return "circle.hexagongrid.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .database: return DS.accent
        case .swipeGallery: return DS.entitySwipe
        case .ideas: return DS.entityIdea
        case .readwise: return DS.entityReadwise
        case .inquiry: return CosmoMentionColors.color(for: .deepDive)
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .database: return "Search database..."
        case .swipeGallery: return "Search swipes..."
        case .ideas: return "Search ideas..."
        case .readwise: return "Search books..."
        case .inquiry: return "Search Deep Dives, questions, lexicon..."
        }
    }
}

// MARK: - CortexMode

/// The three interaction modes of the Cortex Command-K interface
public enum CortexMode: Equatable {
    /// Compact: search bar + domain bubbles + recents grid
    case compact
    /// Search results: grouped results by source
    case searchResults
    /// Expanded domain: full tab content (Database, Swipes, Ideas, Readwise)
    case expandedDomain(CommandKTab)
}

// MARK: - RecentDisplayItem

/// Lightweight model for recent items shown in compact mode
public struct RecentDisplayItem: Identifiable {
    public let id: String  // atom UUID
    let title: String
    let type: AtomType
    let entityId: Int64
    let relativeDate: String
    let thumbnailURL: String?
    let preview: String?
}

// MARK: - SearchPhase
/// Current phase of the search process
public enum SearchPhase: Sendable {
    case idle           // No search active
    case instant        // Instant (cached) results shown
    case searching      // Full search in progress
    case complete       // Search complete
}

// MARK: - SwipeViewMode

enum SwipeViewMode: String, CaseIterable {
    case clustered
    case flat

    var displayName: String {
        switch self {
        case .clustered: return "Clustered"
        case .flat: return "Grid"
        }
    }

    var icon: String {
        switch self {
        case .clustered: return "folder.fill"
        case .flat: return "square.grid.2x2.fill"
        }
    }
}

// MARK: - CommandKSearchMatcher

enum CommandKSearchMatcher {
    static func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func normalizeQuery(_ query: String) -> String {
        normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func searchableText(from values: [String?]) -> String {
        values
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return normalize(value)
            }
            .joined(separator: " ")
    }

    static func matches(_ query: String, in value: String?) -> Bool {
        matches(normalizedQuery: normalizeQuery(query), in: value)
    }

    static func matches(normalizedQuery: String, in value: String?) -> Bool {
        guard !normalizedQuery.isEmpty, let value, !value.isEmpty else { return false }
        return normalize(value).contains(normalizedQuery)
    }

    static func matches(normalizedQuery: String, inNormalizedText normalizedText: String) -> Bool {
        guard !normalizedQuery.isEmpty, !normalizedText.isEmpty else { return false }
        return normalizedText.contains(normalizedQuery)
    }

    static func matches(_ query: String, inAny values: [String?]) -> Bool {
        let normalizedQuery = normalizeQuery(query)
        guard !normalizedQuery.isEmpty else { return false }
        return values.contains { matches(normalizedQuery: normalizedQuery, in: $0) }
    }
}

// MARK: - Unified Search Types

/// Source category for unified cross-library search results
enum UnifiedSearchSource: String, CaseIterable {
    case atoms       // HybridSearchEngine results (all atom types)
    case swipes      // Swipe gallery matches
    case ideas       // Idea gallery matches
    case readwise    // ReadwiseBookStore matches

    var displayName: String {
        switch self {
        case .atoms: return "Database"
        case .swipes: return "Swipe Gallery"
        case .ideas: return "Ideas"
        case .readwise: return "Readwise"
        }
    }

    var icon: String {
        switch self {
        case .atoms: return "tray.full.fill"
        case .swipes: return "bolt.fill"
        case .ideas: return "lightbulb.fill"
        case .readwise: return "books.vertical.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .atoms: return DS.accent
        case .swipes: return DS.entitySwipe
        case .ideas: return DS.entityIdea
        case .readwise: return DS.entityReadwise
        }
    }
}

enum UnifiedSearchResultKind: String {
    case atom
    case project
    case thinkspace
    case readwise
}

/// A single result in the unified cross-library search
struct UnifiedSearchResult: Identifiable {
    let id: String
    let source: UnifiedSearchSource
    let resultKind: UnifiedSearchResultKind
    let title: String
    let subtitle: String?
    let snippet: String?
    let icon: String
    let accentColor: Color
    let relevance: Double
    let atomUUID: String?
    let atomType: AtomType?
    let thinkspaceId: String?
    let projectUUID: String?
    let projectName: String?
    let thinkspaceNames: [String]
    let readwiseBookId: Int?

    var selectionID: String {
        atomUUID ?? thinkspaceId ?? id
    }

    var libraryLookupKey: String? {
        switch resultKind {
        case .atom:
            return atomUUID
        case .project:
            return atomUUID
        case .thinkspace:
            return thinkspaceId
        case .readwise:
            return nil
        }
    }
}

enum UnifiedCardItem: Identifiable {
    case library(LibraryItem)
    case swipe(SwipeGalleryItem)
    case readwise(UnifiedSearchResult)

    var id: String {
        switch self {
        case .library(let item):
            return item.id
        case .swipe(let item):
            return item.id
        case .readwise(let result):
            return result.id
        }
    }

    var selectionID: String {
        switch self {
        case .library(let item):
            return item.uuid
        case .swipe(let item):
            return item.atomUUID
        case .readwise(let result):
            return result.id
        }
    }
}

struct UnifiedSearchOutput {
    let groupedResults: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])]
    let flatResults: [UnifiedSearchResult]
}

enum CommandKUnifiedSearchComposer {
    private static let hybridLimit = 15
    private static let swipeLimit = 8
    private static let ideaLimit = 8
    private static let readwiseLimit = 8

    static func buildOutput(
        query: String,
        hybridResults: [RankedResult],
        swipeGalleryItems: [SwipeGalleryItem],
        ideaGalleryItems: [IdeaGalleryItem],
        readwiseBooks: [ReadwiseLibraryBook]
    ) -> UnifiedSearchOutput {
        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
        guard !normalizedQuery.isEmpty else {
            return UnifiedSearchOutput(groupedResults: [], flatResults: [])
        }

        let swipeItemsByUUID = Dictionary(uniqueKeysWithValues: swipeGalleryItems.map { ($0.atomUUID, $0) })
        var includedAtomUUIDs = Set<String>()
        var allResults: [UnifiedSearchResult] = []

        for result in hybridResults.prefix(hybridLimit) {
            if result.atomType == .idea { continue }
            includedAtomUUIDs.insert(result.atomUUID)

            if result.atomType == .research, let swipeItem = swipeItemsByUUID[result.atomUUID] {
                allResults.append(swipeResult(for: swipeItem, relevance: max(result.relevance, swipeRelevance(for: swipeItem))))
            } else {
                allResults.append(atomResult(for: result))
            }
        }

        var addedSwipes = 0
        for item in swipeGalleryItems where !includedAtomUUIDs.contains(item.atomUUID) {
            guard CommandKSearchMatcher.matches(normalizedQuery: normalizedQuery, inNormalizedText: item.searchableText) else {
                continue
            }
            allResults.append(swipeResult(for: item, relevance: swipeRelevance(for: item)))
            includedAtomUUIDs.insert(item.atomUUID)
            addedSwipes += 1
            if addedSwipes >= swipeLimit { break }
        }

        var addedIdeas = 0
        for item in ideaGalleryItems where !includedAtomUUIDs.contains(item.atomUUID) {
            guard IdeasTab.matchesSearch(item, query: query) else { continue }
            allResults.append(ideaResult(for: item))
            includedAtomUUIDs.insert(item.atomUUID)
            addedIdeas += 1
            if addedIdeas >= ideaLimit { break }
        }

        var addedBooks = 0
        for book in readwiseBooks where ReadwiseBookStore.matchesSearch(book, query: query) {
            let matchingHighlight = book.highlights.first {
                ReadwiseLibraryTab.matchesSearch($0, query: query)
            }
            let snippet = matchingHighlight?.text.prefix(120).description
                ?? "\(book.numHighlights) highlight\(book.numHighlights == 1 ? "" : "s")"

            allResults.append(UnifiedSearchResult(
                id: "readwise-\(book.id)",
                source: .readwise,
                resultKind: .readwise,
                title: "\(book.title)\(book.author.map { " — \($0)" } ?? "")",
                subtitle: book.category.displayName,
                snippet: snippet,
                icon: book.category.icon,
                accentColor: DS.entityReadwise,
                relevance: matchingHighlight != nil ? 0.5 : 0.35,
                atomUUID: nil,
                atomType: nil,
                thinkspaceId: nil,
                projectUUID: nil,
                projectName: nil,
                thinkspaceNames: [],
                readwiseBookId: book.id
            ))
            addedBooks += 1
            if addedBooks >= readwiseLimit { break }
        }

        let groupedResults = groupedResults(from: allResults)
        return UnifiedSearchOutput(
            groupedResults: groupedResults,
            flatResults: groupedResults.flatMap(\.results)
        )
    }

    static func buildCardItems(
        flatResults: [UnifiedSearchResult],
        libraryItemsByID: [String: LibraryItem],
        swipeItemsByUUID: [String: SwipeGalleryItem]
    ) -> [UnifiedCardItem] {
        flatResults.compactMap { result in
            switch result.source {
            case .swipes:
                guard let uuid = result.atomUUID, let item = swipeItemsByUUID[uuid] else { return nil }
                return .swipe(item)
            case .readwise:
                return .readwise(result)
            case .atoms, .ideas:
                guard let key = result.libraryLookupKey,
                      let item = libraryItemsByID[key] else { return nil }
                return .library(item)
            }
        }
    }

    static func regroup(_ results: [UnifiedSearchResult]) -> UnifiedSearchOutput {
        let groupedResults = groupedResults(from: results)
        return UnifiedSearchOutput(
            groupedResults: groupedResults,
            flatResults: groupedResults.flatMap(\.results)
        )
    }

    private static func groupedResults(from allResults: [UnifiedSearchResult]) -> [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] {
        var grouped: [UnifiedSearchSource: [UnifiedSearchResult]] = [:]
        for result in allResults {
            grouped[result.source, default: []].append(result)
        }

        for key in grouped.keys {
            grouped[key]?.sort { $0.relevance > $1.relevance }
        }

        return grouped.sorted { lhs, rhs in
            let lhsBest = lhs.value.first?.relevance ?? 0
            let rhsBest = rhs.value.first?.relevance ?? 0
            return lhsBest > rhsBest
        }.map { (source: $0.key, results: $0.value) }
    }

    private static func atomResult(for result: RankedResult) -> UnifiedSearchResult {
        UnifiedSearchResult(
            id: "atom-\(result.atomUUID)",
            source: .atoms,
            resultKind: .atom,
            title: result.title,
            subtitle: result.atomType.displayName,
            snippet: result.snippet,
            icon: result.atomType.iconName,
            accentColor: accentColor(for: result.atomType),
            relevance: result.relevance,
            atomUUID: result.atomUUID,
            atomType: result.atomType,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    private static func swipeResult(for item: SwipeGalleryItem, relevance: Double) -> UnifiedSearchResult {
        let scoreText = item.hookScore.map { "Score: \(Int($0))" }
        return UnifiedSearchResult(
            id: "swipe-\(item.atomUUID)",
            source: .swipes,
            resultKind: .atom,
            title: item.title,
            subtitle: [item.platformName, scoreText].compactMap { $0 }.joined(separator: " · "),
            snippet: item.hookText,
            icon: "bolt.fill",
            accentColor: DS.entitySwipe,
            relevance: relevance,
            atomUUID: item.atomUUID,
            atomType: .research,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    private static func ideaResult(for item: IdeaGalleryItem) -> UnifiedSearchResult {
        UnifiedSearchResult(
            id: "idea-\(item.atomUUID)",
            source: .ideas,
            resultKind: .atom,
            title: item.title,
            subtitle: [item.status.displayName, item.contentFormat?.displayName].compactMap { $0 }.joined(separator: " · "),
            snippet: item.body?.prefix(120).description,
            icon: "lightbulb.fill",
            accentColor: DS.entityIdea,
            relevance: item.insightScore ?? 0.4,
            atomUUID: item.atomUUID,
            atomType: .idea,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    static func thinkspaceResult(for item: LibraryItem, relevance: Double) -> UnifiedSearchResult {
        UnifiedSearchResult(
            id: "thinkspace-\(item.uuid)",
            source: .atoms,
            resultKind: .thinkspace,
            title: item.title,
            subtitle: item.projectName ?? item.typeName,
            snippet: item.preview,
            icon: item.icon,
            accentColor: item.color,
            relevance: relevance,
            atomUUID: nil,
            atomType: .thinkspace,
            thinkspaceId: item.uuid,
            projectUUID: item.projectUUID,
            projectName: item.projectName,
            thinkspaceNames: item.thinkspaceNames,
            readwiseBookId: nil
        )
    }

    private static func swipeRelevance(for item: SwipeGalleryItem) -> Double {
        (item.hookScore ?? 50) / 100.0
    }
    private static func accentColor(for type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .task: return DS.entityTask
        case .research: return DS.entityResearch
        case .content: return DS.entityContent
        case .connection: return DS.entityConnection
        default: return DS.textSecondary
        }
    }
}

// MARK: - CommandKViewModel
/// ViewModel for the Command-K overlay
/// Manages query state, results, and constellation visualization
@MainActor
public final class CommandKViewModel: ObservableObject {

    // MARK: - Cortex Mode State

    /// Current interaction mode (compact → searchResults → expandedDomain)
    @Published public var cortexMode: CortexMode = .compact

    /// Recent items for compact mode display
    @Published public var recentItems: [RecentDisplayItem] = []

    /// The initial tab passed from MainView (nil = start compact)
    var initialExpandedTab: CommandKTab?

    // MARK: - Published State

    /// Current search query
    @Published public var query: String = ""

    /// Current search results
    @Published public private(set) var results: [RankedResult] = []

    /// Selected result/node UUID
    @Published public var selectedNodeId: String?

    /// Current search phase
    @Published public private(set) var currentPhase: SearchPhase = .idle

    /// Whether voice input is active
    @Published public var isVoiceActive: Bool = false

    /// Multi-select type filters
    @Published public var selectedTypeFilters: Set<AtomType> = []

    /// Filter counts by type (computed from unfiltered results)
    @Published public private(set) var filterCounts: [AtomType: Int] = [:]

    /// Error message (if any)
    @Published public var errorMessage: String?

    // MARK: - Swipe Gallery State

    /// Swipe gallery items loaded from research atoms
    @Published public var swipeGalleryItems: [SwipeGalleryItem] = []

    /// Current grouping mode for swipe gallery
    @Published public var swipeGrouping: SwipeGrouping = .narrativeStyle

    /// Current sort mode for swipe gallery
    @Published public var swipeSortMode: SwipeSortMode = .recent

    /// Platform filter for swipe gallery (nil = all)
    @Published public var swipePlatformFilter: String?

    /// Hook type filter for swipe gallery (nil = all)
    @Published public var swipeHookTypeFilter: SwipeHookType?

    /// Narrative style filters for swipe gallery (multi-select)
    @Published var swipeNarrativeFilters: Set<NarrativeStyle> = []

    /// Content format filters for swipe gallery (multi-select)
    @Published var swipeContentFormatFilters: Set<ContentFormat> = []

    /// Niche filter for swipe gallery (nil = all)
    @Published var swipeNicheFilter: String?

    /// Creator filter for swipe gallery (nil = all)
    @Published var swipeCreatorFilter: String?

    /// Available niches extracted from swipe gallery items
    @Published var availableNiches: [String] = []

    /// Available creators extracted from swipe gallery items
    @Published var availableCreators: [(name: String, uuid: String)] = []

    /// Creator search query for autocomplete
    @Published var creatorSearchQuery: String = ""

    /// Whether swipe gallery has been loaded
    private var swipeGalleryLoaded = false

    /// Cached filtered swipes — recomputed only when filter inputs change
    @Published public private(set) var cachedFilteredSwipes: [SwipeGalleryItem] = []

    /// Cached clustered sections — recomputed from cachedFilteredSwipes
    @Published public private(set) var cachedClusteredSections: [FormatSection] = []

    /// View mode for swipe gallery: clustered folders or flat grid
    @Published var swipeViewMode: SwipeViewMode = .clustered

    /// Search query passed from SwipeGalleryTab for filtering
    @Published var swipeSearchQuery: String = ""

    /// Expansion state for Layer 1 format group sections
    @Published var expandedFormatGroups: Set<String> = Set(FormatGroup.allCases.map(\.rawValue))

    /// Expansion state for Layer 2 narrative clusters (collapsed by default)
    @Published var expandedClusters: Set<String> = []

    // MARK: - Multi-Select State

    /// UUIDs of cards selected via Shift+Click across gallery tabs
    @Published var selectedUUIDs: Set<String> = []

    /// Whether multi-select mode is active (at least one card selected)
    var isMultiSelectActive: Bool { !selectedUUIDs.isEmpty }

    /// Toggle a card's selection state (Shift+Click)
    func toggleSelection(_ uuid: String) {
        if selectedUUIDs.contains(uuid) {
            selectedUUIDs.remove(uuid)
        } else {
            selectedUUIDs.insert(uuid)
        }
    }

    /// Clear all card selections
    func clearSelection() {
        selectedUUIDs.removeAll()
    }

    // MARK: - Unified Search State

    /// Whether unified cross-library search is active (query is non-empty)
    @Published var isUnifiedSearchActive: Bool = false

    /// Grouped unified results by source
    @Published var unifiedGroupedResults: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] = []

    /// Flat ordered list for keyboard navigation across all unified groups
    @Published var unifiedFlatResults: [UnifiedSearchResult] = []

    /// Selected Readwise book ID for navigation from unified results
    @Published var selectedReadwiseBookId: Int?

    /// Card items for masonry grid display of unified search results
    @Published var unifiedCardItems: [UnifiedCardItem] = []

    /// Library items keyed by lookup key — used to render Database section with real library previews
    @Published var unifiedLibraryItemsByID: [String: LibraryItem] = [:]

    // MARK: - Idea Gallery State

    /// Idea gallery items loaded from idea atoms
    @Published var ideaGalleryItems: [IdeaGalleryItem] = []

    /// Whether idea gallery has been loaded
    private var ideaGalleryLoaded = false

    // MARK: - Configuration

    /// Debounce delay for search queries
    private let searchDebounce: TimeInterval = 0.15

    /// Maximum results to display
    private let maxResults = 25

    /// Whether we're showing recents (empty query)
    @Published var isShowingRecents: Bool = false

    /// Whether AI re-ranking has been applied
    @Published var isAIRanked: Bool = false

    /// Grouped results by atom type (ordered by best score)
    @Published var groupedResults: [(type: AtomType, results: [RankedResult])] = []

    /// Flat ordered list for keyboard navigation (across groups)
    @Published var flatNavigableResults: [RankedResult] = []

    /// Currently selected index in flatNavigableResults for keyboard nav
    @Published var selectedResultIndex: Int = -1

    /// Active #type prefix filter parsed from query
    @Published var activeTypePrefix: AtomType? = nil

    /// Monotonic request token so slower unified searches cannot overwrite newer ones.
    private var unifiedSearchRequestID: Int = 0

    // MARK: - Dependencies

    private let hybridSearch = HybridSearchEngine.shared
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var ideaGalleryReloadTask: Task<Void, Never>?
    private let searchPipeline = CommandKSearchPipeline()
    private var searchIndex = CommandKSearchIndex()
    private var searchIndexLoaded = false
    private var searchIndexTask: Task<Void, Never>?
    private var isSurfaceActive = true

    /// Unfiltered results for computing filter counts
    private var unfilteredResults: [RankedResult] = []

    // MARK: - Initialization

    public init() {
        setupQueryDebounce()
        setupFilterObserver()
        setupSwipeFilterPipeline()
        setupSwipeRefreshListener()
        setupIdeaRefreshListener()
    }

    public func setSurfaceActive(_ active: Bool) {
        guard isSurfaceActive != active else { return }
        isSurfaceActive = active

        if active {
            prewarmSearchIndexIfNeeded()
        } else {
            searchTask?.cancel()
            ideaGalleryReloadTask?.cancel()
            searchIndexTask?.cancel()
            currentPhase = .idle
        }
    }

    // MARK: - Query Handling

    private func setupQueryDebounce() {
        $query
            .debounce(for: .seconds(searchDebounce), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                Task { @MainActor [weak self] in
                    guard let self, self.isSurfaceActive else { return }
                    await self.performSearch(query: query)
                }
            }
            .store(in: &cancellables)
    }

    private func setupFilterObserver() {
        $selectedTypeFilters
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyFiltersToResults()
            }
            .store(in: &cancellables)
    }

    private func prewarmSearchIndexIfNeeded(force: Bool = false) {
        guard isSurfaceActive else { return }
        guard force || !searchIndexLoaded else { return }

        searchIndexTask?.cancel()
        searchIndexTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let signpost = CommandKPerformanceInstrumentation.signposter.beginInterval("prewarm-search-index")
            defer {
                CommandKPerformanceInstrumentation.signposter.endInterval("prewarm-search-index", signpost)
            }
            do {
                let atoms = try await AtomRepository.shared.fetchRecent(limit: 10_000)
                guard !Task.isCancelled, self.isSurfaceActive else { return }
                self.searchIndex.replace(atoms: atoms)
                self.searchIndexLoaded = true
            } catch {
                CommandKPerformanceInstrumentation.logger.error("Command-K search index prewarm failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Parse #type prefix from query and return (stripped query, type filter)
    private func parseTypePrefix(_ rawQuery: String) -> (query: String, typeFilter: AtomType?) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        let prefixMap: [String: AtomType] = [
            "#idea": .idea,
            "#task": .task,
            "#swipe": .research,
            "#content": .content,
            "#research": .research,
            "#connection": .connection,
            "#project": .project,
        ]
        for (prefix, type) in prefixMap {
            if trimmed.lowercased().hasPrefix(prefix) {
                let stripped = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return (stripped, type)
            }
        }
        return (trimmed, nil)
    }

    /// Perform search with current query using HybridSearchEngine
    public func performSearch(query: String) async {
        // Cancel previous search
        searchTask?.cancel()
        guard isSurfaceActive else { return }
        let requestID = await searchPipeline.nextRequestID()
        let signpost = CommandKPerformanceInstrumentation.signposter.beginInterval("perform-search")
        defer {
            CommandKPerformanceInstrumentation.signposter.endInterval("perform-search", signpost)
        }

        // Parse #type prefix
        let parsed = parseTypePrefix(query)
        let searchQuery = parsed.query
        let prefixType = parsed.typeFilter

        // Update prefix filter state
        if let pt = prefixType {
            activeTypePrefix = pt
            if !selectedTypeFilters.contains(pt) {
                selectedTypeFilters = [pt]
            }
        } else {
            activeTypePrefix = nil
        }

        // Handle empty query - show recents
        if searchQuery.isEmpty && prefixType == nil {
            isUnifiedSearchActive = false
            unifiedGroupedResults = []
            unifiedFlatResults = []
            unifiedCardItems = []
            // Auto-return to compact when query cleared (unless in expanded domain)
            if cortexMode == .searchResults {
                cortexMode = .compact
                await loadRecentsForCompact()
            }
            await showRecents()
            return
        }

        // Auto-transition to search results when typing in compact mode
        if cortexMode == .compact {
            cortexMode = .searchResults
        }
        // Reset phase so CortexSearchResultsView shows loading, not premature "no results"
        currentPhase = .searching

        // Skip search in task creation mode
        if isTaskCreationMode {
            results = []
            isShowingRecents = false
            currentPhase = .idle
            return
        }

        isShowingRecents = false
        currentPhase = .searching

        let effectiveQuery = searchQuery.isEmpty ? "" : searchQuery
        let queryForSearch = effectiveQuery.isEmpty ? query : effectiveQuery

        let instantIndexedResults = searchIndex.search(queryForSearch, limit: maxResults)
        if !instantIndexedResults.isEmpty {
            unfilteredResults = instantIndexedResults
            computeFilterCounts()
            applyFiltersToResults()
            currentPhase = .instant
        }

        // Check cache first
        let cacheKey = QueryResultCache.cacheKey(
            query: effectiveQuery,
            contextType: FocusContextDetector.shared.currentContext.type.rawValue,
            focusAtomUUID: FocusContextDetector.shared.currentContext.focusAtomUUID,
            typeFilter: nil  // Cache unfiltered, apply filters client-side
        )

        if let cached = await QueryResultCache.shared.get(for: cacheKey) {
            unfilteredResults = cached
            computeFilterCounts()
            applyFiltersToResults()
            await performUnifiedSearch(query: queryForSearch)
            currentPhase = .instant
            return
        }

        // Perform hybrid search (BM25 + vector similarity)
        searchTask = Task { @MainActor in
            do {
                let hybridSignpost = CommandKPerformanceInstrumentation.signposter.beginInterval("hybrid-search")
                // Use HybridSearchEngine for semantic + keyword search
                let hybridResults = try await hybridSearch.search(
                    query: queryForSearch,
                    context: nil,
                    limit: maxResults * 2,  // Get more for filtering
                    entityTypes: nil  // Don't filter at search level, do it client-side for counts
                )
                CommandKPerformanceInstrumentation.signposter.endInterval("hybrid-search", hybridSignpost)

                // Convert HybridSearchEngine.SearchResult to RankedResult
                var rankedResults: [RankedResult] = []
                for result in hybridResults {
                    // Map EntityType to AtomType
                    let atomType = entityTypeToAtomType(result.entityType)

                    // Use UUID directly from atoms_fts (no legacy ID resolution needed)
                    let atomUUID = result.entityUUID ?? "\(result.entityType.rawValue)-\(result.entityId)"

                    rankedResults.append(RankedResult(
                        atomUUID: atomUUID,
                        atomType: atomType,
                        title: result.title,
                        snippet: result.preview,
                        semanticWeight: result.vectorSimilarity,
                        structuralWeight: result.bm25Score / 25.0,  // Normalize
                        recencyWeight: 0.5,  // Default
                        usageWeight: 0.5,    // Default
                        updatedAt: ISO8601DateFormatter().string(from: Date()),
                        accessCount: 0
                    ))
                }

                // Apply context boosts
                let context = FocusContextDetector.shared.currentContext
                let typeBoosts = FocusContextDetector.shared.getTypeBoosts()
                rankedResults = ContextAwareSearchAdapter.applyContextBoosts(
                    to: rankedResults,
                    context: context,
                    typeBoosts: typeBoosts
                )

                // Sort by combined score
                rankedResults.sort()

                // Update state
                if !Task.isCancelled,
                   isSurfaceActive,
                   await searchPipeline.isCurrent(requestID) {
                    isAIRanked = false
                    unfilteredResults = rankedResults
                    computeFilterCounts()
                    applyFiltersToResults()
                    await performUnifiedSearch(query: queryForSearch)
                    currentPhase = .complete

                    // Cache unfiltered results
                    await QueryResultCache.shared.set(rankedResults, for: cacheKey)

                    // Fire AI re-ranker asynchronously (results reorder after 1-2s)
                    let queryForReRank = queryForSearch
                    let reRankInputs = rankedResults.prefix(25).map { r in
                        ReRankInput(
                            uuid: r.atomUUID,
                            type: r.atomType.rawValue,
                            title: r.title,
                            preview: r.snippet ?? "",
                            score: r.relevance
                        )
                    }
                    Task { @MainActor in
                        let rerankSignpost = CommandKPerformanceInstrumentation.signposter.beginInterval("ai-rerank")
                        if let reRanked = await SearchReRanker.shared.reRank(
                            query: queryForReRank,
                            results: reRankInputs
                        ), isSurfaceActive,
                           await searchPipeline.isCurrent(requestID) {
                            // Rebuild results with AI-boosted semantic weights
                            let aiScoreMap = Dictionary(uniqueKeysWithValues: reRanked.map { ($0.uuid, $0.blendedScore) })
                            let reRankedResults = unfilteredResults.map { r in
                                if let aiScore = aiScoreMap[r.atomUUID] {
                                    return RankedResult(
                                        atomUUID: r.atomUUID,
                                        atomType: r.atomType,
                                        title: r.title,
                                        snippet: r.snippet,
                                        semanticWeight: aiScore,
                                        structuralWeight: r.structuralWeight,
                                        recencyWeight: r.recencyWeight,
                                        usageWeight: r.usageWeight,
                                        updatedAt: r.updatedAt,
                                        accessCount: r.accessCount
                                    )
                                }
                                return r
                            }
                            unfilteredResults = reRankedResults.sorted()
                            applyFiltersToResults()
                            await performUnifiedSearch(query: queryForReRank)
                            isAIRanked = true
                        }
                        CommandKPerformanceInstrumentation.signposter.endInterval("ai-rerank", rerankSignpost)
                    }
                }
            } catch {
                if !Task.isCancelled,
                   isSurfaceActive,
                   await searchPipeline.isCurrent(requestID) {
                    // Fallback to graph-based search if hybrid fails
                    await fallbackToGraphSearch(query: query)
                }
            }
        }
    }

    /// Fallback to direct atom search if HybridSearchEngine fails
    private func fallbackToGraphSearch(query: String) async {
        do {
            // Search atoms directly by title/body containing query
            let atoms = try await AtomRepository.shared.search(query: query, limit: maxResults * 2)

            var rankedResults: [RankedResult] = []
            for atom in atoms {
                rankedResults.append(RankedResult(
                    atomUUID: atom.uuid,
                    atomType: atom.type,
                    title: atom.title ?? "Untitled",
                    snippet: atom.body?.prefix(100).description,
                    semanticWeight: 0.0,
                    structuralWeight: 0.5,
                    recencyWeight: WeightCalculator.recencyWeight(fromISO8601: atom.updatedAt),
                    usageWeight: 0.5,
                    updatedAt: atom.updatedAt,
                    accessCount: 0
                ))
            }

            rankedResults.sort()
            unfilteredResults = rankedResults
            computeFilterCounts()
            applyFiltersToResults()
            currentPhase = .complete

        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            currentPhase = .idle
        }
    }

    /// Compute filter counts from unfiltered results
    private func computeFilterCounts() {
        var counts: [AtomType: Int] = [:]
        for result in unfilteredResults {
            counts[result.atomType, default: 0] += 1
        }
        filterCounts = counts
    }

    /// Apply current filters to unfiltered results
    private func applyFiltersToResults() {
        if selectedTypeFilters.isEmpty {
            results = Array(unfilteredResults.prefix(maxResults))
        } else {
            results = Array(unfilteredResults
                .filter { selectedTypeFilters.contains($0.atomType) }
                .prefix(maxResults))
        }
        buildGroupedResults()
    }

    /// Fetch atom UUID from entity type and ID
    private func fetchAtomUUID(entityType: EntityType, entityId: Int64) async -> String? {
        // Try to fetch the atom to get its UUID
        if let atom = try? await AtomRepository.shared.fetch(id: entityId) {
            return atom.uuid
        }
        return nil
    }

    /// Map EntityType to AtomType
    private func entityTypeToAtomType(_ entityType: EntityType) -> AtomType {
        switch entityType {
        case .idea: return .idea
        case .task: return .task
        case .research: return .research
        case .content: return .content
        case .connection: return .connection
        case .project: return .project
        case .journal: return .journalEntry
        case .note: return .idea  // Map notes to ideas
        default: return .idea
        }
    }


    /// Show recent atoms when query is empty
    private func showRecents() async {
        currentPhase = .searching
        isShowingRecents = true

        do {
            // Fetch 8 most recent user-facing atoms
            let recentAtoms = try await AtomRepository.shared.fetchRecent(limit: 8)

            // Build results from actual atoms
            var combinedResults: [RankedResult] = []
            for atom in recentAtoms {
                combinedResults.append(RankedResult(
                    atomUUID: atom.uuid,
                    atomType: atom.type,
                    title: atom.title ?? "Untitled",
                    snippet: atom.body?.prefix(100).description,
                    semanticWeight: 0.0,
                    structuralWeight: 0.5,
                    recencyWeight: WeightCalculator.recencyWeight(fromISO8601: atom.updatedAt),
                    usageWeight: 0.5,
                    updatedAt: atom.updatedAt,
                    accessCount: 0
                ))
            }

            combinedResults.sort()
            unfilteredResults = combinedResults
            computeFilterCounts()
            applyFiltersToResults()
            currentPhase = .complete

        } catch {
            errorMessage = "Failed to load recents: \(error.localizedDescription)"
            currentPhase = .idle
        }
    }

    /// Build grouped results from current filtered results
    private func buildGroupedResults() {
        // Group by atom type
        var groups: [AtomType: [RankedResult]] = [:]
        for result in results {
            groups[result.atomType, default: []].append(result)
        }

        // Sort each group by relevance descending (already sorted, but ensure)
        for key in groups.keys {
            groups[key]?.sort()
        }

        // Order sections by highest-scoring result in each group
        let sorted = groups.sorted { lhs, rhs in
            let lhsBest = lhs.value.first?.relevance ?? 0
            let rhsBest = rhs.value.first?.relevance ?? 0
            return lhsBest > rhsBest
        }

        groupedResults = sorted.map { (type: $0.key, results: $0.value) }

        // Build flat navigable list (for keyboard navigation across groups)
        flatNavigableResults = sorted.flatMap { $0.value }

        // Reset selection
        selectedResultIndex = flatNavigableResults.isEmpty ? -1 : 0
        if let first = flatNavigableResults.first {
            selectedNodeId = first.atomUUID
        }
    }

    /// Quick-create an atom from search query
    func quickCreate(type: AtomType) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let parsed = parseTypePrefix(trimmed)
        let name = parsed.query.isEmpty ? trimmed : parsed.query
        guard !name.isEmpty else { return }

        Task {
            let atom: Atom
            switch type {
            case .idea:
                atom = Atom.new(type: .idea, title: name, body: nil, metadata: nil)
            case .task:
                var taskMeta = TaskMetadata()
                taskMeta.intent = TaskIntent.general.rawValue
                var metadataString: String?
                if let data = try? JSONEncoder().encode(taskMeta),
                   let json = String(data: data, encoding: .utf8) {
                    metadataString = json
                }
                atom = Atom.new(type: .task, title: name, body: nil, metadata: metadataString)
            case .connection:
                atom = Atom.new(type: .connection, title: name, body: nil, metadata: nil)
            default:
                atom = Atom.new(type: type, title: name, body: nil, metadata: nil)
            }

            let _ = try? await AtomRepository.shared.create(atom)
        }

        // Clear query and close
        query = ""
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }


    // MARK: - Selection

    /// Select a result by UUID
    public func select(uuid: String) {
        selectedNodeId = uuid

        // Record access
        Task {
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: uuid, type: .view)
        }
    }

    // MARK: - Task Quick-Create

    /// Whether the current query is a "task:" creation command
    public var isTaskCreationMode: Bool {
        query.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("task:")
    }

    /// Extract task name from "task: [name]" query
    private var taskNameFromQuery: String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return "" }
        let afterColon = trimmed[trimmed.index(after: colonIndex)...]
        return afterColon.trimmingCharacters(in: .whitespaces)
    }

    /// Create a task atom from the "task:" query and close Command-K
    public func createTaskFromQuery() {
        let name = taskNameFromQuery
        guard !name.isEmpty else { return }

        Task {
            var taskMeta = TaskMetadata()
            taskMeta.intent = TaskIntent.general.rawValue

            var metadataString: String?
            if let data = try? JSONEncoder().encode(taskMeta),
               let json = String(data: data, encoding: .utf8) {
                metadataString = json
            }

            let atom = Atom.new(
                type: .task,
                title: name,
                body: nil,
                metadata: metadataString
            )

            let _ = try? await AtomRepository.shared.create(atom)
        }

        // Clear query and close
        query = ""
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }

    /// Open the selected result
    public func openSelected() {
        // Intercept task creation mode
        if isTaskCreationMode {
            createTaskFromQuery()
            return
        }

        // Unified search mode
        if isUnifiedSearchActive, selectedResultIndex >= 0,
           selectedResultIndex < unifiedFlatResults.count {
            let result = unifiedFlatResults[selectedResultIndex]
            if result.resultKind == .thinkspace, let thinkspaceId = result.thinkspaceId {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.navigateToThinkspaceById,
                    object: nil,
                    userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: thinkspaceId).userInfo
                )
                NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            } else if let atomUUID = result.atomUUID {
                Task {
                    try? await NodeGraphEngine.shared.recordAccess(atomUUID: atomUUID, type: .view)
                }
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                    object: nil,
                    userInfo: ["atomUUID": atomUUID]
                )
                NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
            } else if let bookId = result.readwiseBookId {
                selectedReadwiseBookId = bookId
            }
            return
        }

        guard let uuid = selectedNodeId else { return }

        // Record access
        Task {
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: uuid, type: .view)
        }

        // Post notification to open
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil,
            userInfo: ["atomUUID": uuid]
        )

        // Hide Command-K (keep alive behind focus mode)
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }

    // MARK: - Cortex Mode Transitions

    /// Transition to expanded domain view for a specific tab
    public func transitionToExpanded(_ tab: CommandKTab) {
        cortexMode = .expandedDomain(tab)
        selectedResultIndex = -1
        selectedNodeId = nil

        // Ensure tab data is loaded
        switch tab {
        case .swipeGallery:
            if swipeGalleryItems.isEmpty {
                Task { await loadSwipeGallery() }
            }
        case .ideas:
            if ideaGalleryItems.isEmpty {
                Task { await loadIdeaGallery() }
            }
        default:
            break
        }
    }

    /// Return to compact mode from expanded or search
    public func returnToCompact() {
        query = ""
        cortexMode = .compact
        isUnifiedSearchActive = false
        selectedResultIndex = -1
        selectedNodeId = nil
        clearSelection()
        if isSurfaceActive {
            Task { await loadRecentsForCompact() }
        }
    }

    /// Load recent atoms for compact mode display
    public func loadRecentsForCompact() async {
        guard isSurfaceActive else { return }
        do {
            let recentAtoms = try await AtomRepository.shared.fetchRecent(limit: 12)
            recentItems = recentAtoms.filter { $0.type != .task }.prefix(8).map { atom in
                let researchMeta = atom.metadata.flatMap { metaStr -> ResearchMetadata? in
                    guard let data = metaStr.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(ResearchMetadata.self, from: data)
                }
                return RecentDisplayItem(
                    id: atom.uuid,
                    title: atom.title ?? "Untitled",
                    type: atom.type,
                    entityId: atom.id ?? 0,
                    relativeDate: Self.relativeTimeString(from: atom.updatedAt),
                    thumbnailURL: researchMeta?.thumbnailUrl,
                    preview: atom.body
                )
            }
        } catch {
            recentItems = []
        }
    }

    /// Open a recent item from compact mode
    public func openRecent(_ item: RecentDisplayItem) {
        Task {
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: item.id, type: .view)
        }
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil,
            userInfo: ["atomUUID": item.id]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }

    public func deleteRecent(_ item: RecentDisplayItem) {
        Task {
            try? await AtomRepository.shared.delete(uuid: item.id)
            await MainActor.run {
                recentItems.removeAll { $0.id == item.id }
            }
        }
    }

    /// Cached total database atom count (loaded on init)
    @Published public var databaseTotalCount: Int = 0

    /// Domain item counts for bubbles
    public var domainCounts: [CommandKTab: Int] {
        [
            .database: databaseTotalCount,
            .swipeGallery: swipeGalleryItems.count,
            .ideas: ideaGalleryItems.count,
            .readwise: ReadwiseBookStore.shared.books.count,
            .inquiry: deepDiveTotalCount
        ]
    }

    @Published public var deepDiveTotalCount: Int = 0

    /// Load the total database atom count for bubble display
    private func loadDatabaseCount() async {
        guard isSurfaceActive else { return }
        do {
            let atoms = try await AtomRepository.shared.fetchRecent(limit: 500)
            databaseTotalCount = atoms.count
            deepDiveTotalCount = (try? await InquiryRepository.shared.fetchAllDeepDives().count) ?? 0
        } catch {
            databaseTotalCount = 0
            deepDiveTotalCount = 0
        }
    }

    /// Initialize cortex mode based on initial tab from MainView
    public func initializeCortexMode() {
        guard isSurfaceActive else { return }
        prewarmSearchIndexIfNeeded()
        if let tab = initialExpandedTab {
            transitionToExpanded(tab)
        } else {
            cortexMode = .compact
            Task {
                await loadRecentsForCompact()
                await loadDatabaseCount()
                // Preload gallery counts for bubble display
                if swipeGalleryItems.isEmpty { await loadSwipeGallery() }
                if ideaGalleryItems.isEmpty { await loadIdeaGallery() }
            }
        }
    }

    /// Relative time string from ISO8601
    private static func relativeTimeString(from iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(max(1, Int(interval / 60)))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
    }

    /// Navigate selection up
    public func selectPrevious() {
        if isUnifiedSearchActive {
            guard !unifiedFlatResults.isEmpty else { return }
            if selectedResultIndex > 0 {
                selectedResultIndex -= 1
            } else {
                selectedResultIndex = unifiedFlatResults.count - 1
            }
            let result = unifiedFlatResults[selectedResultIndex]
            selectedNodeId = result.selectionID
            return
        }

        guard !flatNavigableResults.isEmpty else { return }

        if selectedResultIndex > 0 {
            selectedResultIndex -= 1
        } else {
            selectedResultIndex = flatNavigableResults.count - 1
        }
        selectedNodeId = flatNavigableResults[selectedResultIndex].atomUUID
    }

    /// Navigate selection down
    public func selectNext() {
        if isUnifiedSearchActive {
            guard !unifiedFlatResults.isEmpty else { return }
            if selectedResultIndex < unifiedFlatResults.count - 1 {
                selectedResultIndex += 1
            } else {
                selectedResultIndex = 0
            }
            let result = unifiedFlatResults[selectedResultIndex]
            selectedNodeId = result.selectionID
            return
        }

        guard !flatNavigableResults.isEmpty else { return }

        if selectedResultIndex < flatNavigableResults.count - 1 {
            selectedResultIndex += 1
        } else {
            selectedResultIndex = 0
        }
        selectedNodeId = flatNavigableResults[selectedResultIndex].atomUUID
    }

    // MARK: - Filter

    /// Toggle a type filter (multi-select)
    public func toggleTypeFilter(_ type: AtomType) {
        if selectedTypeFilters.contains(type) {
            selectedTypeFilters.remove(type)
        } else {
            selectedTypeFilters.insert(type)
        }
    }

    /// Clear all type filters
    public func clearTypeFilters() {
        selectedTypeFilters.removeAll()
    }

    /// Check if a type filter is active
    public func isTypeFilterActive(_ type: AtomType) -> Bool {
        selectedTypeFilters.contains(type)
    }

    /// Available filter types with their display info
    public var filterTypes: [AtomType] {
        [.idea, .task, .research, .content, .connection, .project, .templateInstance]
    }

    /// Get count for a specific filter type
    public func countForType(_ type: AtomType) -> Int {
        filterCounts[type] ?? 0
    }

    /// Total count across all types
    public var totalCount: Int {
        unfilteredResults.count
    }

    // MARK: - Swipe Gallery

    /// Load all swipe file atoms into gallery items
    public func loadSwipeGallery() async {
        guard isSurfaceActive else { return }
        guard !swipeGalleryLoaded else { return }

        do {
            // Fetch all research atoms
            let researchAtoms = try await AtomRepository.shared.search(query: "", types: [.research])

            // Filter to swipe files and convert
            var items: [SwipeGalleryItem] = []
            for atom in researchAtoms {
                if atom.isSwipeFileAtom, let galleryItem = atom.toSwipeGalleryItem() {
                    items.append(galleryItem)
                }
            }

            // Sort by score descending
            items.sort { ($0.hookScore ?? 0) > ($1.hookScore ?? 0) }

            swipeGalleryItems = items
            swipeGalleryLoaded = true

            // Extract available niches
            let niches = Set(items.compactMap(\.niche)).sorted()
            availableNiches = niches

            // Extract available creators from gallery items
            var creatorSet: [String: String] = [:] // name -> atomUUID (deduplicate)
            for item in items {
                if let name = item.creatorName, !name.isEmpty {
                    if creatorSet[name] == nil {
                        creatorSet[name] = item.atomUUID
                    }
                }
            }
            // Also fetch from creator atoms
            if let creators = try? await AtomRepository.shared.fetchCreators() {
                for creator in creators {
                    let name = creator.title ?? "Unknown"
                    creatorSet[name] = creator.uuid
                }
            }
            availableCreators = creatorSet.map { (name: $0.key, uuid: $0.value) }.sorted { $0.name < $1.name }
        } catch {
            errorMessage = "Failed to load swipe gallery: \(error.localizedDescription)"
        }
    }

    // MARK: - Swipe Filter Pipeline

    /// Sets up Combine pipeline to memoize filtered swipes + clustered sections.
    /// Recomputes only when a filter input changes (debounced 50ms).
    private func setupSwipeFilterPipeline() {
        // Observe all filter inputs and recompute when any change
        Publishers.CombineLatest4(
            $swipeGalleryItems,
            $swipePlatformFilter,
            $swipeHookTypeFilter,
            $swipeSortMode
        )
        .combineLatest(
            Publishers.CombineLatest4(
                $swipeNarrativeFilters,
                $swipeContentFormatFilters,
                $swipeNicheFilter,
                $swipeCreatorFilter
            )
        )
        .combineLatest($swipeSearchQuery)
        .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.recomputeFilteredSwipes()
        }
        .store(in: &cancellables)
    }

    /// Recompute cached filtered swipes and clustered sections from current filter state.
    func recomputeFilteredSwipes() {
        // Capture filter state for background work
        let sourceItems = swipeGalleryItems
        let query = swipeSearchQuery
        let platformFilter = swipePlatformFilter
        let hookFilter = swipeHookTypeFilter
        let narrativeFilters = swipeNarrativeFilters
        let formatFilters = swipeContentFormatFilters
        let nicheFilter = swipeNicheFilter
        let creatorFilter = swipeCreatorFilter
        let sortMode = swipeSortMode

        Task.detached(priority: .userInitiated) { [weak self] in
            var items = sourceItems

            if !query.isEmpty {
                let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
                items = items.filter { Self.matchesSwipeGallerySearch($0, normalizedQuery: normalizedQuery) }
            }

            if let platformFilter {
                items = items.filter { $0.platformName == platformFilter }
            }

            if let hookFilter {
                items = items.filter { $0.hookType == hookFilter }
            }

            if !narrativeFilters.isEmpty {
                items = items.filter { item in
                    guard let narrative = item.primaryNarrative else { return false }
                    return narrativeFilters.contains(narrative)
                }
            }

            if !formatFilters.isEmpty {
                items = items.filter { item in
                    guard let format = item.swipeContentFormat else { return false }
                    return formatFilters.contains(format)
                }
            }

            if let nicheFilter {
                items = items.filter { $0.niche == nicheFilter }
            }

            if let creatorFilter {
                items = items.filter { $0.creatorName == creatorFilter }
            }

            switch sortMode {
            case .recent:
                items.sort { $0.createdAt > $1.createdAt }
            case .oldest:
                items.sort { $0.createdAt < $1.createdAt }
            case .alphabetical:
                items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .creator:
                items.sort {
                    let a = $0.creatorName ?? $0.author ?? ""
                    let b = $1.creatorName ?? $1.author ?? ""
                    return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }
            }

            let sections = buildClusteredSections(from: items)

            await MainActor.run {
                self?.cachedFilteredSwipes = items
                self?.cachedClusteredSections = sections
            }
        }
    }

    nonisolated static func matchesSwipeGallerySearch(_ item: SwipeGalleryItem, query: String) -> Bool {
        matchesSwipeGallerySearch(item, normalizedQuery: CommandKSearchMatcher.normalizeQuery(query))
    }

    nonisolated static func matchesSwipeGallerySearch(_ item: SwipeGalleryItem, normalizedQuery: String) -> Bool {
        CommandKSearchMatcher.matches(normalizedQuery: normalizedQuery, inNormalizedText: item.searchableText)
    }

    /// Listen for new swipe creation to auto-refresh gallery
    private func setupSwipeRefreshListener() {
        NotificationCenter.default.publisher(for: .researchCreated)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isSurfaceActive else { return }
                self.swipeGalleryLoaded = false
                Task { await self.loadSwipeGallery() }
            }
            .store(in: &cancellables)
    }

    /// Listen for idea lifecycle changes so the gallery stays in sync while Command-K is open.
    private func setupIdeaRefreshListener() {
        let entityNotifications = [
            CosmoNotification.Entity.created,
            CosmoNotification.Entity.updated,
            CosmoNotification.Entity.deleted,
        ]

        for name in entityNotifications {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self, self.isSurfaceActive, Self.notificationTargetsIdeaGallery(notification) else { return }
                    Task { @MainActor [weak self] in
                        self?.handleIdeaGalleryNotification(notification)
                    }
                }
                .store(in: &cancellables)
        }

        for name in [Self.legacyIdeaDeletedNotification, Self.legacyIdeaActivatedNotification] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self, self.isSurfaceActive else { return }
                    Task { @MainActor [weak self] in
                        self?.handleIdeaGalleryNotification(notification)
                    }
                }
                .store(in: &cancellables)
        }

        NotificationCenter.default.publisher(for: CosmoNotification.Sync.atomsPulled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.isSurfaceActive == true else { return }
                    self?.scheduleIdeaGalleryReload()
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func handleIdeaGalleryNotification(_ notification: Notification) {
        guard isSurfaceActive else { return }
        if let uuid = Self.ideaUUID(from: notification),
           Self.notificationRemovesIdeaFromGallery(notification) {
            ideaGalleryItems.removeAll { $0.atomUUID == uuid }
        }

        scheduleIdeaGalleryReload()
    }

    @MainActor
    private func scheduleIdeaGalleryReload() {
        guard isSurfaceActive else { return }
        ideaGalleryReloadTask?.cancel()
        ideaGalleryReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled, self.isSurfaceActive else { return }
            await self.loadIdeaGallery(forceReload: true)
        }
    }

    static let legacyIdeaDeletedNotification = Notification.Name("ideaDeleted")
    static let legacyIdeaActivatedNotification = Notification.Name("ideaActivated")

    static func notificationTargetsIdeaGallery(_ notification: Notification) -> Bool {
        if notification.name == legacyIdeaDeletedNotification || notification.name == legacyIdeaActivatedNotification {
            return true
        }

        if let atom = notification.userInfo?["atom"] as? Atom {
            return atom.type == .idea
        }

        if let type = notification.userInfo?["type"] as? AtomType {
            return type == .idea
        }

        if let type = notification.userInfo?["type"] as? String {
            return type == AtomType.idea.rawValue
        }

        return false
    }

    static func ideaUUID(from notification: Notification) -> String? {
        if let atom = notification.userInfo?["atom"] as? Atom {
            return atom.uuid
        }

        return notification.userInfo?["uuid"] as? String
    }

    static func notificationRemovesIdeaFromGallery(_ notification: Notification) -> Bool {
        notification.name == legacyIdeaDeletedNotification
            || notification.name == legacyIdeaActivatedNotification
            || notification.name == CosmoNotification.Entity.deleted
    }

    // MARK: - Idea Gallery

    /// Load all idea atoms into gallery items
    /// - Parameter forceReload: If true, reloads even if already loaded (for after quick capture)
    public func loadIdeaGallery(forceReload: Bool = false) async {
        guard isSurfaceActive else { return }
        guard !ideaGalleryLoaded || forceReload else { return }

        do {
            // Fetch all idea atoms (fetchAll avoids LIKE filter that can miss NULL title/body)
            let ideaAtoms = try await AtomRepository.shared.fetchAll(type: .idea)

            // Build a client name cache for display
            var clientNameCache: [String: String] = [:]
            let clientUUIDs = Set(ideaAtoms.compactMap { $0.ideaClientUUID })
            for clientUUID in clientUUIDs {
                if let clientAtom = try? await AtomRepository.shared.fetch(uuid: clientUUID) {
                    clientNameCache[clientUUID] = clientAtom.title ?? "Unknown Client"
                }
            }

            // Convert to gallery items — exclude activated ideas (they're content pieces now)
            let activatedStatuses: Set<IdeaStatus> = [.inProduction, .published, .archived]
            var items: [IdeaGalleryItem] = []
            for atom in ideaAtoms {
                let clientName = atom.ideaClientUUID.flatMap { clientNameCache[$0] }
                if let galleryItem = atom.toIdeaGalleryItem(clientName: clientName),
                   !activatedStatuses.contains(galleryItem.status) {
                    items.append(galleryItem)
                }
            }

            // Sort by updated date descending
            items.sort { $0.updatedAt > $1.updatedAt }

            ideaGalleryItems = items
            ideaGalleryLoaded = true
        } catch {
            errorMessage = "Failed to load idea gallery: \(error.localizedDescription)"
        }
    }

    // MARK: - Idea Quick Actions

    /// Quick-analyze an idea from the gallery card hover bar
    func quickAnalyzeIdea(_ item: IdeaGalleryItem) {
        Task {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: item.atomUUID) else { return }
            let ideaText = [atom.title, atom.body].compactMap { $0 }.joined(separator: "\n")
            let _ = IdeaInsightEngine.shared.quickInsight(ideaText: ideaText)
            await loadIdeaGallery(forceReload: true)
        }
    }

    /// Create an idea pre-assigned to a client profile (used by board view inline add)
    func createIdeaForClient(title: String, clientUUID: String?) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var atom = Atom.new(type: .idea, title: trimmed, body: nil, metadata: nil)

        if let clientUUID {
            atom = atom.withUpdatedIdeaMetadata { meta in
                meta.clientUUID = clientUUID
            }
            atom = atom.addingLink(.ideaToClient(clientUUID))
        }

        do {
            let created = try await AtomRepository.shared.create(atom)

            if let clientName = await clientName(for: clientUUID),
               let galleryItem = created.toIdeaGalleryItem(clientName: clientName) {
                ideaGalleryItems.insert(galleryItem, at: 0)
            } else if let galleryItem = created.toIdeaGalleryItem() {
                ideaGalleryItems.insert(galleryItem, at: 0)
            }
            ideaGalleryItems.sort { $0.updatedAt > $1.updatedAt }
            ideaGalleryLoaded = true
        } catch {
            errorMessage = "Failed to capture idea: \(error.localizedDescription)"
            return
        }

        // Add reciprocal link on client
        if let clientUUID,
           var client = try? await AtomRepository.shared.fetch(uuid: clientUUID) {
            client = client.addingLink(.clientToIdea(atom.uuid))
            client.updatedAt = ISO8601DateFormatter().string(from: Date())
            client.localVersion += 1
            _ = try? await AtomRepository.shared.update(client)
        }

        await loadIdeaGallery(forceReload: true)
    }

    private func clientName(for clientUUID: String?) async -> String? {
        guard let clientUUID else { return nil }
        guard let client = try? await AtomRepository.shared.fetch(uuid: clientUUID) else { return nil }
        return client.title
    }

    // MARK: - Unified Search

    static func preloadUnifiedSearchSupportData(
        swipeGalleryLoaded: Bool,
        ideaGalleryLoaded: Bool,
        loadSwipeGallery: @escaping () async -> Void,
        loadIdeaGallery: @escaping () async -> Void
    ) async {
        async let swipeTask: Void = {
            guard !swipeGalleryLoaded else { return }
            await loadSwipeGallery()
        }()
        async let ideaTask: Void = {
            guard !ideaGalleryLoaded else { return }
            await loadIdeaGallery()
        }()
        _ = await (swipeTask, ideaTask)
    }

    /// Ensure swipe and idea galleries are loaded before unified search composes results.
    private func preloadUnifiedSearchSupportData() async {
        await Self.preloadUnifiedSearchSupportData(
            swipeGalleryLoaded: swipeGalleryLoaded,
            ideaGalleryLoaded: ideaGalleryLoaded,
            loadSwipeGallery: { await self.loadSwipeGallery() },
            loadIdeaGallery: { await self.loadIdeaGallery() }
        )
    }

    private func nextUnifiedSearchRequestID() -> Int {
        unifiedSearchRequestID += 1
        return unifiedSearchRequestID
    }

    private func isCurrentUnifiedSearchRequest(_ requestID: Int) -> Bool {
        requestID == unifiedSearchRequestID
    }

    /// Perform unified search across all libraries
    func performUnifiedSearch(query: String) async {
        guard isSurfaceActive else { return }
        let signpost = CommandKPerformanceInstrumentation.signposter.beginInterval("unified-search")
        defer {
            CommandKPerformanceInstrumentation.signposter.endInterval("unified-search", signpost)
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let requestID = nextUnifiedSearchRequestID()

        guard !trimmed.isEmpty, !isTaskCreationMode else {
            isUnifiedSearchActive = false
            unifiedGroupedResults = []
            unifiedFlatResults = []
            unifiedCardItems = []
            selectedResultIndex = -1
            selectedNodeId = nil
            return
        }

        // If #prefix is active, don't show unified — let the existing tab filter handle it
        if activeTypePrefix != nil {
            isUnifiedSearchActive = false
            unifiedGroupedResults = []
            unifiedFlatResults = []
            unifiedCardItems = []
            selectedResultIndex = -1
            selectedNodeId = nil
            return
        }

        isUnifiedSearchActive = true
        await preloadUnifiedSearchSupportData()
        if ThinkspaceManager.shared.thinkspaces.isEmpty {
            await ThinkspaceManager.shared.loadThinkspaces()
        }
        guard isCurrentUnifiedSearchRequest(requestID) else { return }

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: trimmed,
            hybridResults: unfilteredResults,
            swipeGalleryItems: swipeGalleryItems,
            ideaGalleryItems: ideaGalleryItems,
            readwiseBooks: ReadwiseBookStore.shared.books
        )
        guard isCurrentUnifiedSearchRequest(requestID) else { return }

        let projectAtoms = (try? await AtomRepository.shared.fetchAll(type: .project)) ?? []
        let projectsByUUID = Dictionary(uniqueKeysWithValues: projectAtoms.map { ($0.uuid, $0) })
        let thinkspaceLibraryItems = ThinkspaceManager.shared.sidebarThinkspaces.map { thinkspace in
            LibraryItem(
                thinkspace: thinkspace,
                project: thinkspace.projectUuid.flatMap { projectsByUUID[$0] },
                nestedThinkspaceCount: ThinkspaceManager.shared.childThinkspaces(of: thinkspace.id).count
            )
        }
        let matchingThinkspaceResults = thinkspaceLibraryItems
            .filter { matchesUnifiedLibrarySearch($0, query: trimmed) }
            .prefix(8)
            .map { item in
                CommandKUnifiedSearchComposer.thinkspaceResult(
                    for: item,
                    relevance: thinkspaceRelevance(for: item, query: trimmed)
                )
            }

        let combinedResults = output.flatResults + matchingThinkspaceResults
        let atomUUIDs = combinedResults.compactMap { result -> String? in
            guard result.resultKind != .thinkspace,
                  result.source != .swipes else { return nil }
            return result.atomUUID
        }
        let thinkspacesByID = Dictionary(uniqueKeysWithValues: ThinkspaceManager.shared.sidebarThinkspaces.map { ($0.id, $0) })
        var libraryItemsByID = await buildUnifiedAtomLibraryItems(
            atomUUIDs: atomUUIDs,
            projectsByUUID: projectsByUUID,
            thinkspacesByID: thinkspacesByID
        )
        for item in thinkspaceLibraryItems {
            libraryItemsByID[item.uuid] = item
        }

        let enrichedResults = combinedResults.map { result in
            enrichUnifiedSearchResult(result, with: result.libraryLookupKey.flatMap { libraryItemsByID[$0] })
        }
        let regrouped = CommandKUnifiedSearchComposer.regroup(enrichedResults)
        guard isCurrentUnifiedSearchRequest(requestID) else { return }

        unifiedGroupedResults = regrouped.groupedResults
        unifiedFlatResults = regrouped.flatResults
        unifiedLibraryItemsByID = libraryItemsByID

        // Reset keyboard selection to first result
        if let first = unifiedFlatResults.first {
            selectedResultIndex = 0
            selectedNodeId = first.selectionID
        } else {
            selectedResultIndex = -1
            selectedNodeId = nil
        }

        let swipeItemsByUUID = Dictionary(uniqueKeysWithValues: swipeGalleryItems.map { ($0.atomUUID, $0) })
        unifiedCardItems = CommandKUnifiedSearchComposer.buildCardItems(
            flatResults: unifiedFlatResults,
            libraryItemsByID: libraryItemsByID,
            swipeItemsByUUID: swipeItemsByUUID
        )
    }

    private func buildUnifiedAtomLibraryItems(
        atomUUIDs: [String],
        projectsByUUID: [String: Atom],
        thinkspacesByID: [String: Thinkspace]
    ) async -> [String: LibraryItem] {
        guard !atomUUIDs.isEmpty else { return [:] }

        let atoms = (try? await AtomRepository.shared.fetchBatch(uuids: atomUUIDs)) ?? []
        let memberships = (try? await AtomRepository.shared.fetchThinkspaceMembership(for: atomUUIDs)) ?? [:]

        return atoms.reduce(into: [String: LibraryItem]()) { result, atom in
            let atomThinkspaces = (memberships[atom.uuid] ?? []).compactMap { thinkspacesByID[$0] }
            let project = resolveProject(
                for: atom,
                thinkspaces: atomThinkspaces,
                projectsByUUID: projectsByUUID
            )
            result[atom.uuid] = LibraryItem(
                atom: atom,
                project: project,
                thinkspaces: atomThinkspaces
            )
        }
    }

    private func resolveProject(
        for atom: Atom,
        thinkspaces: [Thinkspace],
        projectsByUUID: [String: Atom]
    ) -> Atom? {
        if atom.type == .project {
            return atom
        }
        if let explicitProjectUUID = atom.link(ofType: .project)?.uuid,
           let project = projectsByUUID[explicitProjectUUID] {
            return project
        }
        if let thinkspaceProjectUUID = thinkspaces.compactMap(\.projectUuid).first,
           let project = projectsByUUID[thinkspaceProjectUUID] {
            return project
        }
        return nil
    }

    private func matchesUnifiedLibrarySearch(_ item: LibraryItem, query: String) -> Bool {
        CommandKSearchMatcher.matches(query, inAny: [item.title, item.preview, item.typeName, item.provenanceSummary])
    }

    private func thinkspaceRelevance(for item: LibraryItem, query: String) -> Double {
        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
        let normalizedTitle = CommandKSearchMatcher.normalize(item.title)
        if normalizedTitle == normalizedQuery {
            return 0.98
        }
        if normalizedTitle.hasPrefix(normalizedQuery) {
            return 0.82
        }
        return 0.62
    }

    private func enrichUnifiedSearchResult(_ result: UnifiedSearchResult, with item: LibraryItem?) -> UnifiedSearchResult {
        guard let item else { return result }

        let resultKind: UnifiedSearchResultKind
        switch item.kind {
        case .atom:
            resultKind = .atom
        case .project:
            resultKind = .project
        case .thinkspace:
            resultKind = .thinkspace
        case .cluster:
            resultKind = .thinkspace
        }

        return UnifiedSearchResult(
            id: result.id,
            source: result.source,
            resultKind: resultKind,
            title: result.title,
            subtitle: result.subtitle ?? item.typeName,
            snippet: result.snippet ?? item.preview,
            icon: result.icon,
            accentColor: item.color,
            relevance: result.relevance,
            atomUUID: result.atomUUID,
            atomType: result.atomType,
            thinkspaceId: result.thinkspaceId ?? (item.kind == .thinkspace ? item.uuid : item.thinkspaceUUIDs.first),
            projectUUID: item.projectUUID,
            projectName: item.projectName,
            thinkspaceNames: item.thinkspaceNames,
            readwiseBookId: result.readwiseBookId
        )
    }

    // MARK: - Cleanup

    /// Clear search state
    public func clear() {
        query = ""
        results = []
        unfilteredResults = []
        filterCounts = [:]
        selectedNodeId = nil
        currentPhase = .idle
        errorMessage = nil
        selectedTypeFilters.removeAll()
        swipeGalleryItems = []
        swipeGalleryLoaded = false
        swipePlatformFilter = nil
        swipeHookTypeFilter = nil
        swipeNarrativeFilters = []
        swipeContentFormatFilters = []
        swipeNicheFilter = nil
        swipeCreatorFilter = nil
        swipeSortMode = .recent
        selectedUUIDs.removeAll()
        ideaGalleryItems = []
        ideaGalleryLoaded = false
        isShowingRecents = false
        groupedResults = []
        flatNavigableResults = []
        selectedResultIndex = -1
        activeTypePrefix = nil
        isUnifiedSearchActive = false
        unifiedGroupedResults = []
        unifiedFlatResults = []
        selectedReadwiseBookId = nil
    }
}

// MARK: - Swipe Gallery Enums

/// Grouping mode for the swipe gallery
public enum SwipeGrouping: String, CaseIterable {
    case narrativeStyle
    case contentType
    case hookType
    case platform
    case creator
    case niche
    case recent
    case score

    public var displayName: String {
        switch self {
        case .narrativeStyle: return "Narrative"
        case .contentType: return "Format"
        case .hookType: return "Hook Type"
        case .platform: return "Platform"
        case .creator: return "Creator"
        case .niche: return "Niche"
        case .recent: return "Recent"
        case .score: return "Score"
        }
    }
}

/// Sort mode for the swipe gallery
public enum SwipeSortMode: String, CaseIterable {
    case recent
    case oldest
    case alphabetical
    case creator

    public var displayName: String {
        switch self {
        case .recent: return "Most Recent"
        case .oldest: return "Oldest First"
        case .alphabetical: return "A–Z"
        case .creator: return "By Creator"
        }
    }
}
