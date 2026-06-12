import Foundation
import SwiftUI

@MainActor
@Observable
final class SwipeLibraryViewModel {
    private(set) var allItems: [SwipeGalleryItem] = []
    private(set) var visibleItems: [SwipeGalleryItem] = []
    /// Card display models aligned 1:1 with `visibleItems` — adapters (date parsing,
    /// URL building) run once per recompute, never on the render path.
    private(set) var visibleCardModels: [SwipeCardModel] = []
    private(set) var cardModelsByID: [String: SwipeCardModel] = [:]
    private(set) var visibleItemsIdentity = SwipeLibraryVisibleItemsIdentity(items: [])
    /// Date-bucketed sections, populated only for the Recently Added scope.
    private(set) var recentBuckets: [SwipeLibraryDateBucket] = []
    private(set) var shelves: [SwipeLibraryShelf] = []
    private(set) var summary = SwipeLibraryFacetSummary.empty
    private(set) var availableCreators: [String] = []
    private(set) var availableNiches: [String] = []
    private(set) var availablePlatforms: [String] = []
    private(set) var isLoading = false
    var errorMessage: String?
    var selectedItem: SwipeGalleryItem?
    /// Transient toast text for board membership changes.
    var boardMessage: String?

    /// Structural pre-filter set by navigation (sidebar section / board detail).
    /// Independent of `filterState` — switching scope never touches user filters.
    private(set) var scope: SwipeLibrarySectionSelection = .all

    var query = "" {
        didSet { recomputeIfNeeded(oldValue != query) }
    }

    var filterState = SwipeLibraryFilterState() {
        didSet { recomputeIfNeeded(oldValue != filterState) }
    }

    var sortMode: SwipeSortMode = .recent {
        didSet { recomputeIfNeeded(oldValue != sortMode) }
    }

    var displayMode: SwipeLibraryMode = .grid

    private var hasLoaded = false

    func loadIfNeeded(section: SwipeLibrarySectionSelection) async {
        setScope(section)
        guard !hasLoaded else { return }
        await reload()
    }

    func setSection(_ section: SwipeLibrarySectionSelection) {
        setScope(section)
    }

    func setScope(_ newScope: SwipeLibrarySectionSelection) {
        guard scope != newScope else { return }
        scope = newScope
        recompute()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            let atoms = try await AtomRepository.shared.search(query: "", types: [.research])
            var items: [SwipeGalleryItem] = []

            for atom in atoms where atom.isSwipeFileAtom {
                if let item = atom.toSwipeGalleryItem() {
                    items.append(item)
                }
            }

            SwipeLibraryFiltering.sortItems(&items, by: .recent)

            allItems = items
            hasLoaded = true
            refreshAvailableFacets()
            recompute()
        } catch {
            errorMessage = "Could not load Swipe File: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func resetFilters() {
        filterState.reset()
        query = ""
        sortMode = .recent
    }

    func applySmartPreset(_ preset: SwipeLibrarySmartPreset) {
        var next = SwipeLibraryFilterState()
        next.smartPreset = preset
        switch preset {
        case .all:
            break
        case .fearHooks:
            next.narratives = [.fearMongering]
            next.hookTypes = [.controversy, .contrarian, .boldClaim]
        case .curiosity:
            next.hookTypes = [.curiosityGap, .question, .hiddenGem]
        case .threads:
            next.formats = [.thread, .tweet]
        case .reels:
            next.formats = [.reel, .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA]
        case .highScore:
            next.minimumHookScore = 8
        }
        filterState = next
    }

    func togglePlatform(_ platform: String) {
        toggle(platform, in: &filterState.platforms)
    }

    func toggleHookType(_ hookType: SwipeHookType) {
        toggle(hookType, in: &filterState.hookTypes)
    }

    func toggleFramework(_ framework: SwipeFrameworkType) {
        toggle(framework, in: &filterState.frameworks)
    }

    func toggleNarrative(_ narrative: NarrativeStyle) {
        toggle(narrative, in: &filterState.narratives)
    }

    func toggleFormat(_ format: ContentFormat) {
        toggle(format, in: &filterState.formats)
    }

    func setCreator(_ creator: String?) {
        filterState.creator = creator
    }

    func setNiche(_ niche: String?) {
        filterState.niche = niche
    }

    func openStudy(_ item: SwipeGalleryItem) {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.research,
                "id": item.entityId,
                "commandKTab": "swipeGallery"
            ]
        )
    }

    /// Toggles a swipe's membership in a board. Persists on the atom, reloads, and
    /// notifies every other library instance + the sidebar counts.
    func toggleBoard(_ board: SwipeBoard, itemID: String) {
        Task {
            do {
                guard var atom = try await AtomRepository.shared.fetch(uuid: itemID) else { return }
                var ids = Set(atom.swipeBoardIDs ?? [])
                let adding = !ids.contains(board.uuid)
                if adding {
                    ids.insert(board.uuid)
                } else {
                    ids.remove(board.uuid)
                }
                atom.swipeBoardIDs = Array(ids).sorted()
                _ = try await AtomRepository.shared.update(atom)
                boardMessage = adding ? "Saved to \(board.name)" : "Removed from \(board.name)"
                await reload()
                SwipeBoardStore.shared.refreshCounts(from: allItems)
                NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
            } catch {
                boardMessage = "Board update failed"
            }
        }
    }

    func addToCanvas(_ item: SwipeGalleryItem) {
        NotificationCenter.default.post(
            name: .addSwipeToCanvas,
            object: nil,
            userInfo: ["atomUUID": item.atomUUID]
        )
    }

    private func recomputeIfNeeded(_ shouldRecompute: Bool) {
        guard shouldRecompute else { return }
        recompute()
    }

    private func recompute() {
        let items = SwipeLibraryFiltering.filteredItems(
            from: allItems,
            scope: scope,
            filters: filterState,
            query: query,
            sortMode: sortMode
        )
        let nextIdentity = SwipeLibraryVisibleItemsIdentity(items: items)
        if visibleItemsIdentity != nextIdentity {
            visibleItemsIdentity = nextIdentity
        }
        visibleItems = items
        visibleCardModels = items.map(SwipeCardModel.init(item:))
        cardModelsByID = Dictionary(zip(items.map(\.id), visibleCardModels), uniquingKeysWith: { first, _ in first })
        recentBuckets = scope == .recentlyAdded
            ? SwipeLibraryDateBucket.buckets(items: items, models: visibleCardModels)
            : []
        shelves = SwipeLibraryFiltering.shelves(from: items)
        summary = SwipeLibraryFiltering.facetSummary(allItems: allItems, filteredItems: items)

        if let selectedItem, !items.contains(where: { $0.id == selectedItem.id }) {
            self.selectedItem = items.first
        } else if selectedItem == nil {
            selectedItem = items.first
        }
    }

    private func refreshAvailableFacets() {
        availableCreators = SwipeLibraryFiltering.availableCreators(from: allItems)
        availableNiches = SwipeLibraryFiltering.availableNiches(from: allItems)
        availablePlatforms = Array(Set(allItems.compactMap(\.platform))).sorted { lhs, rhs in
            platformName(lhs) < platformName(rhs)
        }
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    func platformName(_ platform: String) -> String {
        switch platform {
        case "youtube": return "YouTube"
        case "youtubeShort", "youtube_short": return "Shorts"
        case "instagram", "instagramPost", "instagram_post": return "Instagram"
        case "instagramReel", "instagram_reel": return "Reels"
        case "instagramCarousel", "instagram_carousel": return "Carousels"
        case "xPost", "x_post", "twitter": return "X"
        case "threads": return "Threads"
        default:
            return platform
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }
}
