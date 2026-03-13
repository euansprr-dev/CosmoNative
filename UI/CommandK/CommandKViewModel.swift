// CosmoOS/UI/CommandK/CommandKViewModel.swift
// ViewModel for Command-K overlay - manages search state and constellation
// Powers the NodeGraph OS Command-K interface
// Phase 4: Multi-select filters, HybridSearchEngine integration, filter counts

import SwiftUI
import Combine

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

/// A single result in the unified cross-library search
struct UnifiedSearchResult: Identifiable {
    let id: String
    let source: UnifiedSearchSource
    let title: String
    let subtitle: String?
    let snippet: String?
    let icon: String
    let accentColor: Color
    let relevance: Double
    let atomUUID: String?
    let atomType: AtomType?
    let readwiseBookId: Int?
}

// MARK: - CommandKViewModel
/// ViewModel for the Command-K overlay
/// Manages query state, results, and constellation visualization
@MainActor
public final class CommandKViewModel: ObservableObject {

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
    @Published public var swipeSortMode: SwipeSortMode = .score

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
    @Published var unifiedCardItems: [LibraryItem] = []

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

    // MARK: - Dependencies

    private let hybridSearch = HybridSearchEngine.shared
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    /// Unfiltered results for computing filter counts
    private var unfilteredResults: [RankedResult] = []

    // MARK: - Initialization

    public init() {
        setupQueryDebounce()
        setupFilterObserver()
        setupSwipeFilterPipeline()
        setupSwipeRefreshListener()
    }

    // MARK: - Query Handling

    private func setupQueryDebounce() {
        $query
            .debounce(for: .seconds(searchDebounce), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                Task {
                    await self?.performSearch(query: query)
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
            await showRecents()
            return
        }

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
            await performUnifiedSearch(query: effectiveQuery.isEmpty ? query : effectiveQuery)
            currentPhase = .instant
            return
        }

        // Perform hybrid search (BM25 + vector similarity)
        searchTask = Task {
            do {
                // Use HybridSearchEngine for semantic + keyword search
                let hybridResults = try await hybridSearch.search(
                    query: effectiveQuery.isEmpty ? query : effectiveQuery,
                    context: nil,
                    limit: maxResults * 2,  // Get more for filtering
                    entityTypes: nil  // Don't filter at search level, do it client-side for counts
                )

                // Convert HybridSearchEngine.SearchResult to RankedResult
                var rankedResults: [RankedResult] = []
                for result in hybridResults {
                    // Map EntityType to AtomType
                    let atomType = entityTypeToAtomType(result.entityType)

                    // Fetch full atom data for UUID
                    let atomUUID = await fetchAtomUUID(entityType: result.entityType, entityId: result.entityId)

                    rankedResults.append(RankedResult(
                        atomUUID: atomUUID ?? "\(result.entityType.rawValue)-\(result.entityId)",
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
                if !Task.isCancelled {
                    isAIRanked = false
                    unfilteredResults = rankedResults
                    computeFilterCounts()
                    applyFiltersToResults()
                    await performUnifiedSearch(query: effectiveQuery.isEmpty ? query : effectiveQuery)
                    currentPhase = .complete

                    // Cache unfiltered results
                    await QueryResultCache.shared.set(rankedResults, for: cacheKey)

                    // Fire AI re-ranker asynchronously (results reorder after 1-2s)
                    let queryForReRank = effectiveQuery.isEmpty ? query : effectiveQuery
                    let reRankInputs = rankedResults.prefix(25).map { r in
                        ReRankInput(
                            uuid: r.atomUUID,
                            type: r.atomType.rawValue,
                            title: r.title,
                            preview: r.snippet ?? "",
                            score: r.relevance
                        )
                    }
                    Task {
                        if let reRanked = await SearchReRanker.shared.reRank(
                            query: queryForReRank,
                            results: reRankInputs
                        ) {
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
                    }
                }
            } catch {
                if !Task.isCancelled {
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
            if let atomUUID = result.atomUUID {
                Task {
                    try? await NodeGraphEngine.shared.recordAccess(atomUUID: atomUUID, type: .view)
                }
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                    object: nil,
                    userInfo: ["atomUUID": atomUUID]
                )
                NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
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

        // Close Command-K
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
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
            selectedNodeId = result.atomUUID ?? result.id
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
            selectedNodeId = result.atomUUID ?? result.id
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
        [.idea, .task, .research, .content, .connection, .project]
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
                let q = query.lowercased()
                items = items.filter { $0.searchableText.contains(q) }
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
            case .score:
                items.sort { ($0.hookScore ?? 0) > ($1.hookScore ?? 0) }
            case .recent:
                items.sort { $0.createdAt > $1.createdAt }
            case .oldest:
                items.sort { $0.createdAt < $1.createdAt }
            }

            let sections = buildClusteredSections(from: items)

            await MainActor.run {
                self?.cachedFilteredSwipes = items
                self?.cachedClusteredSections = sections
            }
        }
    }

    /// Listen for new swipe creation to auto-refresh gallery
    private func setupSwipeRefreshListener() {
        NotificationCenter.default.publisher(for: .researchCreated)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.swipeGalleryLoaded = false
                Task { await self.loadSwipeGallery() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Idea Gallery

    /// Load all idea atoms into gallery items
    /// - Parameter forceReload: If true, reloads even if already loaded (for after quick capture)
    public func loadIdeaGallery(forceReload: Bool = false) async {
        guard !ideaGalleryLoaded || forceReload else { return }

        do {
            // Fetch all idea atoms
            let ideaAtoms = try await AtomRepository.shared.search(query: "", types: [.idea])

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

        let _ = try? await AtomRepository.shared.create(atom)

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

    // MARK: - Unified Search

    /// Ensure swipe and idea galleries are loaded for unified search
    private func ensureGalleriesLoaded() {
        if !swipeGalleryLoaded {
            Task { await loadSwipeGallery() }
        }
        if !ideaGalleryLoaded {
            Task { await loadIdeaGallery() }
        }
    }

    /// Perform unified search across all libraries
    func performUnifiedSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty, !isTaskCreationMode else {
            isUnifiedSearchActive = false
            unifiedGroupedResults = []
            unifiedFlatResults = []
            unifiedCardItems = []
            return
        }

        // If #prefix is active, don't show unified — let the existing tab filter handle it
        if activeTypePrefix != nil {
            isUnifiedSearchActive = false
            return
        }

        isUnifiedSearchActive = true
        ensureGalleriesLoaded()

        let lowerQuery = trimmed.lowercased()

        // Collect atomUUIDs already in hybrid results to avoid duplicates
        let hybridUUIDs = Set(unfilteredResults.map(\.atomUUID))

        var allResults: [UnifiedSearchResult] = []

        // 1. Atom results from HybridSearchEngine (already computed in performSearch)
        for result in unfilteredResults.prefix(15) {
            allResults.append(UnifiedSearchResult(
                id: "atom-\(result.atomUUID)",
                source: .atoms,
                title: result.title,
                subtitle: result.atomType.displayName,
                snippet: result.snippet,
                icon: iconForAtomType(result.atomType),
                accentColor: colorForAtomType(result.atomType),
                relevance: result.relevance,
                atomUUID: result.atomUUID,
                atomType: result.atomType,
                readwiseBookId: nil
            ))
        }

        // 2. Swipe gallery matches (deduplicated)
        let matchingSwipes = swipeGalleryItems.filter { item in
            guard !hybridUUIDs.contains(item.atomUUID) else { return false }
            return item.title.lowercased().contains(lowerQuery) ||
                (item.hookText?.lowercased().contains(lowerQuery) ?? false) ||
                (item.author?.lowercased().contains(lowerQuery) ?? false) ||
                (item.niche?.lowercased().contains(lowerQuery) ?? false) ||
                (item.creatorName?.lowercased().contains(lowerQuery) ?? false)
        }
        for item in matchingSwipes.prefix(8) {
            let scoreText = item.hookScore.map { "Score: \(Int($0))" }
            allResults.append(UnifiedSearchResult(
                id: "swipe-\(item.atomUUID)",
                source: .swipes,
                title: item.title,
                subtitle: [item.platformName, scoreText].compactMap { $0 }.joined(separator: " · "),
                snippet: item.hookText,
                icon: "bolt.fill",
                accentColor: DS.entitySwipe,
                relevance: (item.hookScore ?? 50) / 100.0,
                atomUUID: item.atomUUID,
                atomType: .research,
                readwiseBookId: nil
            ))
        }

        // 3. Idea gallery matches (deduplicated)
        let matchingIdeas = ideaGalleryItems.filter { item in
            guard !hybridUUIDs.contains(item.atomUUID) else { return false }
            return item.title.lowercased().contains(lowerQuery) ||
                (item.body?.lowercased().contains(lowerQuery) ?? false)
        }
        for item in matchingIdeas.prefix(8) {
            allResults.append(UnifiedSearchResult(
                id: "idea-\(item.atomUUID)",
                source: .ideas,
                title: item.title,
                subtitle: [item.status.displayName, item.contentFormat?.displayName].compactMap { $0 }.joined(separator: " · "),
                snippet: item.body?.prefix(120).description,
                icon: "lightbulb.fill",
                accentColor: DS.entityIdea,
                relevance: item.insightScore ?? 0.4,
                atomUUID: item.atomUUID,
                atomType: .idea,
                readwiseBookId: nil
            ))
        }

        // 4. Readwise book matches
        let matchingBooks = ReadwiseBookStore.shared.search(query: trimmed)
        for book in matchingBooks.prefix(8) {
            let matchingHighlight = book.highlights.first { h in
                h.text.localizedCaseInsensitiveContains(trimmed)
            }
            let snippet = matchingHighlight?.text.prefix(120).description
                ?? "\(book.numHighlights) highlight\(book.numHighlights == 1 ? "" : "s")"

            allResults.append(UnifiedSearchResult(
                id: "readwise-\(book.id)",
                source: .readwise,
                title: "\(book.title)\(book.author.map { " — \($0)" } ?? "")",
                subtitle: book.category.displayName,
                snippet: snippet,
                icon: book.category.icon,
                accentColor: DS.entityReadwise,
                relevance: matchingHighlight != nil ? 0.5 : 0.35,
                atomUUID: nil,
                atomType: nil,
                readwiseBookId: book.id
            ))
        }

        // Group by source, ordered by best relevance in each group
        var grouped: [UnifiedSearchSource: [UnifiedSearchResult]] = [:]
        for result in allResults {
            grouped[result.source, default: []].append(result)
        }

        // Sort each group by relevance
        for key in grouped.keys {
            grouped[key]?.sort { $0.relevance > $1.relevance }
        }

        // Order sections by best score
        let sortedGroups = grouped.sorted { lhs, rhs in
            let lhsBest = lhs.value.first?.relevance ?? 0
            let rhsBest = rhs.value.first?.relevance ?? 0
            return lhsBest > rhsBest
        }

        unifiedGroupedResults = sortedGroups.map { (source: $0.key, results: $0.value) }
        unifiedFlatResults = sortedGroups.flatMap(\.value)

        // Reset keyboard selection to first result
        if let first = unifiedFlatResults.first {
            selectedResultIndex = 0
            selectedNodeId = first.atomUUID ?? first.id
        }

        // Load atoms for masonry card display
        let atomUUIDs = unifiedFlatResults.compactMap(\.atomUUID)
        if !atomUUIDs.isEmpty {
            let atoms = (try? await AtomRepository.shared.fetchBatch(uuids: atomUUIDs)) ?? []
            let atomMap = Dictionary(atoms.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

            // Build card items preserving relevance order from unifiedFlatResults
            var cards: [LibraryItem] = []
            for result in unifiedFlatResults {
                if let uuid = result.atomUUID, let atom = atomMap[uuid] {
                    cards.append(LibraryItem(atom: atom))
                }
            }
            unifiedCardItems = cards
        } else {
            unifiedCardItems = []
        }
    }

    /// Helper: SF Symbol for atom type
    private func iconForAtomType(_ type: AtomType) -> String {
        switch type {
        case .idea: return "lightbulb.fill"
        case .task: return "checkmark.circle.fill"
        case .research: return "book.fill"
        case .content: return "doc.text.fill"
        case .connection: return "link"
        case .project: return "folder.fill"
        case .image: return "photo.fill"
        case .note: return "note.text"
        default: return "circle.fill"
        }
    }

    /// Helper: accent color for atom type
    private func colorForAtomType(_ type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .task: return DS.entityTask
        case .research: return DS.entityResearch
        case .content: return DS.entityContent
        case .connection: return DS.entityConnection
        default: return DS.textSecondary
        }
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
        swipeSortMode = .score
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
    case score
    case recent
    case oldest

    public var displayName: String {
        switch self {
        case .score: return "Score \u{25BC}"
        case .recent: return "Recent"
        case .oldest: return "Oldest"
        }
    }
}
