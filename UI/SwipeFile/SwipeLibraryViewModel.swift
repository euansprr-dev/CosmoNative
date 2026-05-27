import Foundation
import SwiftUI

@MainActor
final class SwipeLibraryViewModel: ObservableObject {
    @Published private(set) var allItems: [SwipeGalleryItem] = []
    @Published private(set) var visibleItems: [SwipeGalleryItem] = []
    @Published private(set) var shelves: [SwipeLibraryShelf] = []
    @Published private(set) var summary = SwipeLibraryFacetSummary(
        totalCount: 0,
        filteredCount: 0,
        highScoreCount: 0,
        unstudiedCount: 0,
        averageHookScore: nil
    )
    @Published private(set) var availableCreators: [String] = []
    @Published private(set) var availableNiches: [String] = []
    @Published private(set) var availablePlatforms: [String] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedItem: SwipeGalleryItem?

    @Published var query = "" {
        didSet { recomputeIfNeeded(oldValue != query) }
    }

    @Published var filterState = SwipeLibraryFilterState() {
        didSet { recomputeIfNeeded(oldValue != filterState) }
    }

    @Published var sortMode: SwipeSortMode = .recent {
        didSet { recomputeIfNeeded(oldValue != sortMode) }
    }

    @Published var displayMode: SwipeLibraryMode = .grid

    private var hasLoaded = false
    private var activeSection: SwipeLibrarySectionSelection = .all

    func loadIfNeeded(section: SwipeLibrarySectionSelection) async {
        activeSection = section
        applySection(section)

        guard !hasLoaded else { return }
        await reload()
    }

    func setSection(_ section: SwipeLibrarySectionSelection) {
        activeSection = section
        applySection(section)
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

    func addToCanvas(_ item: SwipeGalleryItem) {
        NotificationCenter.default.post(
            name: .addSwipeToCanvas,
            object: nil,
            userInfo: ["atomUUID": item.atomUUID]
        )
    }

    private func applySection(_ section: SwipeLibrarySectionSelection) {
        var next = filterState
        let sectionFilters = SwipeLibraryFiltering.sectionFilters(for: section)

        switch section {
        case .all:
            next.onlyStudied = false
            next.onlyUnstudied = false
            next.minimumHookScore = nil
        case .recentlyAdded:
            next.onlyStudied = false
            next.onlyUnstudied = false
            sortMode = .recent
        case .highHookScore:
            next.minimumHookScore = sectionFilters.minimumHookScore
        case .unstudied:
            next.onlyStudied = false
            next.onlyUnstudied = true
        case .board(let id):
            if id == "fear-hooks" {
                next.smartPreset = .fearHooks
                next.narratives = [.fearMongering]
                next.hookTypes = [.controversy, .contrarian, .boldClaim]
            } else if id == "curiosity-gaps" {
                next.smartPreset = .curiosity
                next.hookTypes = [.curiosityGap, .question, .hiddenGem]
            }
        }

        filterState = next
    }

    private func recomputeIfNeeded(_ shouldRecompute: Bool) {
        guard shouldRecompute else { return }
        recompute()
    }

    private func recompute() {
        let items = SwipeLibraryFiltering.filteredItems(
            from: allItems,
            filters: filterState,
            query: query,
            sortMode: sortMode
        )
        visibleItems = items
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
