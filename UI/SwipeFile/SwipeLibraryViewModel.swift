import Foundation
import SwiftUI
import Combine

@MainActor
@Observable
final class SwipeLibraryViewModel {
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var syncRefreshTask: Task<Void, Never>?

    init() {
        // Swipes captured on iPhone arrive via SYNC PULLS, not through any UI
        // action on this Mac — without this listener the library rendered a
        // launch-time snapshot until the next app restart (user-visible as
        // "the Mac is days behind iOS/web" even though the local DB is
        // fully up to date).
        NotificationCenter.default.publisher(for: CosmoNotification.Sync.atomsPulled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleSyncRefresh()
                }
            }
            .store(in: &cancellables)
    }

    /// Debounced: batch pulls arrive in bursts (up to 100 atoms per page) —
    /// one reload after the burst settles keeps shelves/catalog fresh without
    /// hammering the decode path. Identity-gated downstream, so a reload that
    /// changes nothing re-renders nothing.
    private func scheduleSyncRefresh() {
        guard hasLoaded else { return }
        syncRefreshTask?.cancel()
        syncRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }
    private(set) var allItems: [SwipeGalleryItem] = []
    private(set) var visibleItems: [SwipeGalleryItem] = []
    /// Card display models aligned 1:1 with `visibleItems` — adapters (date parsing,
    /// URL building) run once per recompute, never on the render path.
    private(set) var visibleCardModels: [SwipeCardModel] = []
    private(set) var cardModelsByID: [String: SwipeCardModel] = [:]
    private(set) var visibleItemsIdentity = SwipeLibraryVisibleItemsIdentity(items: [])
    /// Month-rhythm sections for the catalog — populated only when browsing the
    /// full library newest-first with no query/filters (finding beats rhythm).
    private(set) var dateSections: [SwipeLibraryDateBucket] = []
    private(set) var shelves: [SwipeLibraryShelf] = []
    private(set) var summary = SwipeLibraryFacetSummary.empty
    private(set) var availableCreators: [String] = []
    private(set) var availableNiches: [String] = []
    private(set) var availablePlatforms: [String] = []
    /// Kinds actually present in the library, in canonical order.
    /// PROGRESSIVE DISCLOSURE: the Kind facet renders only when there is more
    /// than one — a library of nothing but posts must look exactly as it did
    /// before the artifact spine shipped.
    private(set) var availableKinds: [SwipeKind] = []
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

    /// True once the first library load has landed — pages gate their
    /// editorial layout on this so a cold open shows the skeleton, never a
    /// partial page (boards shelf first, hero missing).
    private(set) var hasLoaded = false

    func loadIfNeeded(section: SwipeLibrarySectionSelection) async {
        setScope(section)
        guard !hasLoaded else { return }
        await reload()
    }

    /// Launch-time warm: the first load WITHOUT touching scope — a prewarm
    /// racing a real visit must never re-scope what the user is looking at.
    func prewarmIfNeeded() async {
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
            // Atom→item mapping decodes several JSON columns per swipe — far
            // too heavy for the main actor at library size. Atom and
            // SwipeGalleryItem are Sendable; the map runs detached and only
            // the finished array hops back.
            let items = await Task.detached(priority: .userInitiated) {
                var items: [SwipeGalleryItem] = []
                for atom in atoms where atom.isSwipeFileAtom {
                    if let item = atom.toSwipeGalleryItem() {
                        items.append(item)
                    }
                }
                SwipeLibraryFiltering.sortItems(&items, by: .recent)
                return items
            }.value

            allItems = items
            hasLoaded = true
            await refreshAvailableFacets()
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

    func toggleKind(_ kind: SwipeKind) {
        toggle(kind, in: &filterState.kinds)
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
        // Record the browsing order so Study's prev/next chevrons (⌘[ / ⌘])
        // walk the same sequence this surface was showing.
        SwipeStudySession.shared.begin(
            order: visibleItems.map(\.entityId),
            current: item.entityId
        )
        // No "commandKTab" tag: this surface is the Swipe Studio, not the ⌘K
        // palette. Tagging a ⌘K return tab makes MainView's focus-exit observer
        // re-present Command-K on close (the return tab is its restore signal),
        // which would pop ⌘K instead of landing back in the studio.
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.research,
                "id": item.entityId
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

    /// The default browse — no query, no filters, newest first. The shape a
    /// cold launch lands on, and the only one worth persisting a warm list for.
    private var isUnfilteredBrowse: Bool {
        query.isEmpty && !filterState.hasActiveFilters && sortMode == .recent
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
        let wantsDateSections = scope == .all
            && sortMode == .recent
            && query.isEmpty
            && !filterState.hasActiveFilters
        dateSections = wantsDateSections
            ? SwipeLibraryDateBucket.monthBuckets(items: items, models: visibleCardModels)
            : []
        shelves = SwipeLibraryFiltering.shelves(from: items)
        summary = SwipeLibraryFiltering.facetSummary(allItems: allItems, filteredItems: items)
        // Warm the head of whatever the user is about to be looking at — a
        // launch prewarm, a scope switch, a filter, a search keystroke. Already
        // resident keys never reach the queue, so this is nearly free. Only an
        // unfiltered browse is worth recording for next launch.
        SwipeThumbnailPrewarmer.shared.warmLibrary(
            models: visibleCardModels,
            recordAsLaunchManifest: isUnfilteredBrowse
        )

        if let selectedItem, !items.contains(where: { $0.id == selectedItem.id }) {
            self.selectedItem = items.first
        } else if selectedItem == nil {
            selectedItem = items.first
        }
    }

    private func refreshAvailableFacets() async {
        availableCreators = SwipeLibraryFiltering.availableCreators(from: allItems)
        availableNiches = await Self.nicheFacetOptions(from: allItems)
        availablePlatforms = Array(Set(allItems.compactMap(\.platform))).sorted { lhs, rhs in
            platformName(lhs) < platformName(rhs)
        }
        let present = Set(allItems.map(\.kind))
        availableKinds = SwipeKind.allCases.filter(present.contains)
    }

    /// How many swipes of a kind the library holds — the facet row's live count.
    func kindCount(_ kind: SwipeKind) -> Int {
        allItems.reduce(into: 0) { $0 += ($1.kind == kind ? 1 : 0) }
    }

    /// Niche facet options: the exact strings present in the library (the
    /// filter matches exact values), ordered by canonical registry usage so
    /// the user's core verticals lead the menu. Strings the registry doesn't
    /// know yet (pre-backfill stragglers) trail alphabetically.
    static func nicheFacetOptions(from items: [SwipeGalleryItem]) async -> [String] {
        let present = Set(items.compactMap(\.niche).filter { !$0.isEmpty })
        guard !present.isEmpty else { return [] }

        let niches = await NicheRegistry.shared.currentNiches()
        let usageByKey = Dictionary(
            niches.map { (NicheMatcher.normalizeKey($0.value), $0.usageCount) },
            uniquingKeysWith: { max($0, $1) }
        )
        return present.sorted { lhs, rhs in
            let lhsUsage = usageByKey[NicheMatcher.normalizeKey(lhs)] ?? -1
            let rhsUsage = usageByKey[NicheMatcher.normalizeKey(rhs)] ?? -1
            if lhsUsage != rhsUsage { return lhsUsage > rhsUsage }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
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
