import Foundation

struct SwipeLibraryVisibleItemsIdentity: Equatable {
    private let ids: [String]

    init(items: [SwipeGalleryItem]) {
        self.ids = items.map(\.id)
    }
}

enum SwipeLibraryFiltering {
    /// Scope-composed filtering: `scope ∧ filters ∧ query`. Scope is the structural
    /// pre-filter owned by navigation; user filters never encode it.
    ///
    /// SEARCH LIFTS GENRE SCOPE: a non-empty query widens `.home` and `.genre`
    /// to the whole library — finding beats browsing, and a search typed in
    /// the Posts room that silently missed every newsletter would read as
    /// data loss. Board scope does NOT lift: searching inside a board is an
    /// intentional narrowing the user chose.
    static func filteredItems(
        from items: [SwipeGalleryItem],
        scope: SwipeLibrarySectionSelection,
        filters: SwipeLibraryFilterState,
        query: String,
        sortMode: SwipeSortMode
    ) -> [SwipeGalleryItem] {
        let effectiveScope = effectiveScope(scope, query: query)
        let inScope: [SwipeGalleryItem]
        switch effectiveScope {
        case .all, .boards:
            inScope = items
        default:
            let predicate = scopePredicate(effectiveScope)
            inScope = items.filter(predicate)
        }
        return filteredItems(from: inScope, filters: filters, query: query, sortMode: sortMode)
    }

    /// The scope a non-empty query actually searches under.
    static func effectiveScope(
        _ scope: SwipeLibrarySectionSelection,
        query: String
    ) -> SwipeLibrarySectionSelection {
        guard !query.isEmpty else { return scope }
        switch scope {
        case .home, .genre:
            return .all
        default:
            return scope
        }
    }

    static func scopePredicate(_ scope: SwipeLibrarySectionSelection) -> (SwipeGalleryItem) -> Bool {
        switch scope {
        case .all, .boards:
            return { _ in true }
        case .home:
            // The landing page is the POSTS room — every other genre has its
            // own space, and one mixed stream is the junk drawer this whole
            // system exists to end.
            return { $0.genre == .post }
        case .genre(let genre):
            return { $0.genre == genre }
        case .highHookScore:
            return { ($0.hookScore ?? 0) >= 7.5 }
        case .unstudied:
            return { !$0.isStudied }
        case .board(let boardID):
            return { $0.boardIDs.contains(boardID) }
        }
    }

    static func filteredItems(
        from items: [SwipeGalleryItem],
        filters: SwipeLibraryFilterState,
        query: String,
        sortMode: SwipeSortMode
    ) -> [SwipeGalleryItem] {
        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
        var filtered = items.filter { item in
            matchesQuery(item, normalizedQuery: normalizedQuery) &&
            matchesSmartPreset(item, preset: filters.smartPreset) &&
            matchesExplicitFilters(item, filters: filters)
        }

        sortItems(&filtered, by: sortMode)
        return filtered
    }

    static func availableCreators(from items: [SwipeGalleryItem]) -> [String] {
        Array(Set(items.compactMap(\.creatorName).filter { !$0.isEmpty })).sorted()
    }

    static func availableNiches(from items: [SwipeGalleryItem]) -> [String] {
        Array(Set(items.compactMap(\.niche).filter { !$0.isEmpty })).sorted()
    }

    private static func matchesQuery(_ item: SwipeGalleryItem, normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }
        return CommandKSearchMatcher.matches(normalizedQuery: normalizedQuery, inNormalizedText: item.searchableText)
    }

    private static func matchesSmartPreset(_ item: SwipeGalleryItem, preset: SwipeLibrarySmartPreset) -> Bool {
        switch preset {
        case .all:
            return true
        case .fearHooks:
            return matchesFearPreset(item)
        case .curiosity:
            return item.hookType == .curiosityGap || item.dominantEmotion == .curiosity
        case .threads:
            return item.swipeContentFormat == .thread || item.platformName == "X" || item.platformName == "Threads"
        case .reels:
            return item.swipeContentFormat == .reel ||
                item.swipeContentFormat == .voiceoverReel ||
                item.swipeContentFormat == .oneSliderReel ||
                item.swipeContentFormat == .multiSliderReel ||
                item.platform == "instagram_reel" ||
                item.platform == "instagramReel"
        case .highScore:
            return (item.hookScore ?? 0) >= 7.5
        }
    }

    private static func matchesExplicitFilters(_ item: SwipeGalleryItem, filters: SwipeLibraryFilterState) -> Bool {
        if !filters.kinds.isEmpty, !filters.kinds.contains(item.kind) {
            return false
        }

        if !filters.genres.isEmpty, !filters.genres.contains(item.genre) {
            return false
        }

        if !filters.platforms.isEmpty, !filters.platforms.contains(item.platformName) {
            return false
        }

        if !filters.hookTypes.isEmpty {
            guard let hookType = item.hookType, filters.hookTypes.contains(hookType) else { return false }
        }

        if !filters.frameworks.isEmpty {
            guard let framework = item.frameworkType, filters.frameworks.contains(framework) else { return false }
        }

        if !filters.narratives.isEmpty {
            guard let narrative = item.primaryNarrative, filters.narratives.contains(narrative) else { return false }
        }

        if !filters.formats.isEmpty {
            guard let format = item.swipeContentFormat, filters.formats.contains(format) else { return false }
        }

        if let creator = filters.creator, item.creatorName != creator {
            return false
        }

        if let niche = filters.niche, item.niche != niche {
            return false
        }

        if filters.onlyStudied, !item.isStudied {
            return false
        }

        if filters.onlyUnstudied, item.isStudied {
            return false
        }

        if let minimumHookScore = filters.minimumHookScore, (item.hookScore ?? 0) < minimumHookScore {
            return false
        }

        return true
    }

    private static func matchesFearPreset(_ item: SwipeGalleryItem) -> Bool {
        if item.primaryNarrative == .fearMongering || item.dominantEmotion == .fear {
            return true
        }

        if item.hookType == .controversy || item.hookType == .contrarian || item.hookType == .boldClaim {
            return true
        }

        let normalized = CommandKSearchMatcher.normalize([item.title, item.hookText].compactMap { $0 }.joined(separator: " "))
        let warningTerms = [
            "mistake",
            "warning",
            "avoid",
            "stop",
            "danger",
            "before you",
            "costing you",
            "nobody tells you",
            "most people",
        ]
        return warningTerms.contains { normalized.contains($0) }
    }

    static func sortItems(_ items: inout [SwipeGalleryItem], by sortMode: SwipeSortMode) {
        let indexed = items.enumerated().map {
            SwipeSortRecord(index: $0.offset, item: $0.element, createdAt: $0.element.createdAtDate ?? .distantPast)
        }
        let sorted: [SwipeSortRecord]
        switch sortMode {
        case .recent:
            sorted = indexed.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.index < rhs.index
            }
        case .oldest:
            sorted = indexed.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.index < rhs.index
            }
        case .alphabetical:
            sorted = indexed.sorted { lhs, rhs in
                let comparison = lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs.index < rhs.index
            }
        case .creator:
            sorted = indexed.sorted { lhs, rhs in
                let lhsCreator = lhs.item.creatorName ?? lhs.item.author ?? ""
                let rhsCreator = rhs.item.creatorName ?? rhs.item.author ?? ""
                if lhsCreator == rhsCreator {
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                    return lhs.index < rhs.index
                }
                return lhsCreator.localizedCaseInsensitiveCompare(rhsCreator) == .orderedAscending
            }
        }
        items = sorted.map(\.item)
    }


}

private struct SwipeSortRecord {
    let index: Int
    let item: SwipeGalleryItem
    let createdAt: Date
}
