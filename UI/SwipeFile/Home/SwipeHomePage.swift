import SwiftUI

// MARK: - Swipe File (the one page)

/// The swipe file, whole, on one surface: one hero (Up Next), the date shelves
/// (New This Week / New This Month), Boards, Outliers — then the complete
/// catalog under "All" with the library's sort/view/filter tools. Searching or
/// filtering steps the editorial aside and shows just results, in place.
struct SwipeHomePage: View {
    @Bindable var viewModel: SwipeLibraryViewModel
    @Bindable var discoverModel: SwipeDiscoverModel
    let onNavigate: (SidebarDestination) -> Void

    @State private var frameStore = SwipeFrameStore()
    /// Saved swipes preview in the trailing rail; unsaved Discover posts keep
    /// the centered quick look (no transcript exists until they're saved).
    @State private var previewItemID: String?
    @State private var postQuickLookID: String?
    @State private var quickLookExpanded = false
    @State private var quickLookSource: CGRect?
    @State private var studyHero: SwipeStudyHero?
    @State private var studyHeroExpanded = false
    @State private var studyHeroArrived = false
    @State private var contextPillVisible = false
    @State private var scrollPosition = ScrollPosition()
    @State private var containerWidth: CGFloat = 0
    @State private var showFilters = false
    @State private var filterAnchor: CGRect = .zero
    @State private var revealDate = Date()
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                SwipePageBackground()
                scrollContent
                if showFilters {
                    filterDropdown.zIndex(2)
                }
                postQuickLookLayer
                if let studyHero {
                    SwipeStudyHeroOverlay(hero: studyHero, expanded: studyHeroExpanded).zIndex(4)
                }
            }
            .coordinateSpace(name: "swipePage")

            if let item = previewItem {
                previewSidebar(item)
                    .frame(width: SwipePreviewSidebar.width(forContainerWidth: containerWidth))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { containerWidth = $0 }
        .onPreferenceChange(SwipeFilterAnchorKey.self) { filterAnchor = $0 }
        .task {
            await SwipeBoardStore.shared.loadIfNeeded()
            await viewModel.loadIfNeeded(section: .home)
            viewModel.setSection(.home)
            await discoverModel.loadIfNeeded()
        }
        .onChange(of: viewModel.visibleItemsIdentity) { revealDate = Date() }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.swipeStudyDidAppear)) { _ in
            relieveHeroAfterStudyAppears()
        }
        .onExitCommand(perform: handleEscape)
        .background(keyboardLayer)
        .animation(ProMotionSprings.bouncy, value: showFilters)
        .overlay(alignment: .bottom) { SwipeSaveToast(message: $viewModel.boardMessage) }
        .overlay(alignment: .bottom) { SwipeSaveToast(message: $discoverModel.saveMessage) }
    }

    // MARK: - Content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                masthead
                // Gate on hasLoaded, not isLoading: before the load task even
                // starts, isLoading is still false — the old gate let the page
                // render its editorial with only the (already cached) boards
                // shelf at the top for the first beats of a cold open.
                if !viewModel.hasLoaded && viewModel.allItems.isEmpty {
                    SwipeSkeletonGrid()
                } else if viewModel.allItems.isEmpty {
                    SwipeLibraryEmptyState(scope: .home, hasActiveFilters: false, onClearFilters: {})
                } else if isCatalogFocused {
                    catalogSection
                } else {
                    editorial
                    catalogSection
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 36)
            .padding(.bottom, 72)
            .swipeContentMeasure()
        }
        .scrollPosition($scrollPosition)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, new in
            let shouldShow = new > 88
            if shouldShow != contextPillVisible {
                contextPillVisible = shouldShow
            }
        }
        .overlay(alignment: .top) { contextPill }
    }

    @ViewBuilder
    private var editorial: some View {
        if let (item, model) = heroPick {
            SwipeHeroCard(
                kicker: item.isStudied ? "LATEST SAVE" : "UP NEXT",
                model: model,
                ctaLabel: "Open Study",
                onPreview: { openPreview(itemID: item.id) },
                frameStore: frameStore
            ) {
                openStudy(item: item, model: model)
            }
        }
        if !newThisWeek.isEmpty {
            librarySwipeShelf(label: "NEW THIS WEEK", count: newThisWeek.count, models: newThisWeek)
        }
        if !newThisMonth.isEmpty {
            librarySwipeShelf(label: "NEW THIS MONTH", count: newThisMonth.count, models: newThisMonth)
        }
        boardsShelf
        patternsShelf
        outliersShelf
    }

    /// The complete catalog, inline — header voice + the library's tool cluster,
    /// then the uniform grid. While searching/filtering this is the whole page.
    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: 10) {
                SwipeSectionHeader(
                    label: isCatalogFocused ? "RESULTS" : "ALL",
                    count: viewModel.summary.filteredCount
                )
                Spacer(minLength: DS.space16)
                SwipeLibraryControlBar(viewModel: viewModel, showFilters: $showFilters)
            }
            SwipeLibraryResults(
                viewModel: viewModel,
                frameStore: frameStore,
                revealDate: revealDate,
                hiddenItemID: postQuickLookID,
                onOpen: { openPreview(itemID: $0) },
                onStudy: { openStudyByID($0) }
            )
        }
    }

    /// Search or filters active — the catalog takes the page.
    private var isCatalogFocused: Bool {
        !viewModel.query.isEmpty || viewModel.filterState.hasActiveFilters
    }

    private var masthead: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            SwipeMasthead(title: "Swipe File")
            Spacer(minLength: DS.space16)
            SwipeLibrarySearchField(text: $viewModel.query, isFocused: $searchFocused)
        }
    }

    private var contextPill: some View {
        SwipeContextPill(
            title: "Swipe File",
            detail: "\(viewModel.summary.totalCount) saved",
            visible: contextPillVisible
        ) {
            withAnimation(ProMotionSprings.gentle) {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .padding(.top, DS.space12)
    }

    // MARK: - Shelf data

    /// The hero is the most recent unstudied swipe — honest recency, no score
    /// ranking (all swipes are curated). Studying it promotes the next one.
    private var heroPick: (SwipeGalleryItem, SwipeCardModel)? {
        let items = viewModel.visibleItems
        let models = viewModel.visibleCardModels
        guard !items.isEmpty else { return nil }
        if let index = items.firstIndex(where: { !$0.isStudied }) {
            return (items[index], models[index])
        }
        return (items[0], models[0])
    }

    /// Every save in the window belongs on its shelf — a capped shelf silently
    /// drops the overflow into Everything and the header count lies.
    private var newThisWeek: [SwipeCardModel] {
        SwipeLibraryDateBucket.lastWeekModels(items: viewModel.visibleItems, models: viewModel.visibleCardModels)
            .filter { $0.id != heroPick?.1.id }
            .map { $0.poster().hookless() }
    }

    private var newThisMonth: [SwipeCardModel] {
        SwipeLibraryDateBucket.lastMonthModels(items: viewModel.visibleItems, models: viewModel.visibleCardModels)
            .filter { $0.id != heroPick?.1.id }
            .map { $0.poster().hookless() }
    }

    private var topOutliers: [SwipeCardModel] {
        Array(
            discoverModel.visiblePosts
                .sorted { ($0.derived.outlierMultiplier ?? 0) > ($1.derived.outlierMultiplier ?? 0) }
                .prefix(12)
        )
        .map { SwipeCardModel(post: $0).poster() }
    }

    // MARK: - Shelves

    /// Date shelves carry no "See All" — everything below them IS the all.
    private func librarySwipeShelf(
        label: String,
        count: Int? = nil,
        models: [SwipeCardModel]
    ) -> some View {
        SwipeShelf(
            label: label,
            count: count,
            onSeeAll: nil,
            models: models,
            hiddenItemID: postQuickLookID,
            frameStore: frameStore
        ) { model in
            SwipeCardActions(
                onOpen: { openPreview(itemID: model.id) },
                onStudy: { openStudyByID(model.id) },
                boardMenu: SwipeCardBoardMenu(
                    boards: SwipeBoardStore.shared.boards,
                    memberIDs: model.boardIDs,
                    onToggle: { board in viewModel.toggleBoard(board, itemID: model.id) }
                )
            )
        }
    }

    @ViewBuilder
    private var boardsShelf: some View {
        let boards = SwipeBoardStore.shared.boards
        if !boards.isEmpty {
            SwipeShelfRow(
                label: "BOARDS",
                count: boards.count,
                onSeeAll: { onNavigate(.swipeFile(section: .boards)) }
            ) {
                ForEach(boards) { board in
                    SwipeHomeBoardTile(
                        board: board,
                        coverItems: boardCoverItems(board),
                        count: SwipeBoardStore.shared.counts[board.uuid] ?? 0
                    ) {
                        onNavigate(.swipeFile(section: .board(board.uuid)))
                    }
                }
            }
        }
    }

    /// Recurring moves the PatternWeaver noticed across saved swipes. Hidden
    /// until patterns exist (the Boards grammar); opening one starts a study
    /// session that walks the pattern's members with the prev/next chevrons.
    @ViewBuilder
    private var patternsShelf: some View {
        let patterns = SwipePatternStore.shared.patterns
        if !patterns.isEmpty {
            SwipeShelfRow(
                label: "PATTERNS",
                count: patterns.count,
                onSeeAll: nil
            ) {
                ForEach(patterns.sorted { $0.members.count > $1.members.count }) { pattern in
                    SwipeHomePatternTile(
                        pattern: pattern,
                        coverItems: patternCoverItems(pattern)
                    ) {
                        openPatternStudy(pattern)
                    }
                }
            }
        }
    }

    private func patternCoverItems(_ pattern: SwipePattern) -> [SwipeCardModel] {
        Array(
            pattern.members
                .compactMap { member in
                    viewModel.allItems.first(where: { $0.id == member.swipeUUID })
                        .map { viewModel.cardModelsByID[$0.id] ?? SwipeCardModel(item: $0) }
                }
                .prefix(4)
        )
    }

    /// Study the pattern: open its most recent member with the session queue
    /// set to the pattern's members, so ⌘[/⌘] walks the move end to end.
    private func openPatternStudy(_ pattern: SwipePattern) {
        let memberIDs = pattern.members.map(\.swipeUUID)
        let items = viewModel.allItems.filter { memberIDs.contains($0.id) }
        guard let first = items.first else { return }
        SwipeStudySession.shared.begin(
            order: items.map(\.entityId),
            current: first.entityId
        )
        // No "commandKTab" tag: this surface is the Swipe Studio, not the ⌘K
        // palette. Tagging a ⌘K return tab makes MainView's focus-exit observer
        // re-present Command-K on close, which would pop ⌘K instead of landing
        // back in the studio.
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.research,
                "id": first.entityId
            ]
        )
    }

    @ViewBuilder
    private var outliersShelf: some View {
        if topOutliers.isEmpty {
            discoverTeachingRow
        } else {
            SwipeShelf(
                label: "OUTLIERS FROM YOUR CREATORS",
                count: topOutliers.count,
                onSeeAll: { onNavigate(.discover(section: .discover)) },
                models: topOutliers,
                hiddenItemID: postQuickLookID,
                frameStore: frameStore
            ) { model in
                SwipeCardActions(
                    onOpen: { openPostQuickLook(postID: model.id) },
                    onStudy: { transcript(postID: model.id) },
                    onBookmark: { save(postID: model.id, boardID: nil) }
                )
            }
        }
    }

    /// Absence teaches the fix — never a silently missing section.
    private var discoverTeachingRow: some View {
        Button {
            onNavigate(.discover(section: .creators))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                Text("Add creators to see their outlier posts here")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                Image(systemName: "chevron.right")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add creators to see their outlier posts here")
    }

    private func boardCoverItems(_ board: SwipeBoard) -> [SwipeCardModel] {
        Array(
            viewModel.allItems
                .filter { $0.boardIDs.contains(board.uuid) }
                .compactMap { viewModel.cardModelsByID[$0.id] ?? SwipeCardModel(item: $0) }
                .prefix(4)
        )
    }

    // MARK: - Preview rail (saved swipes)

    private var previewItem: SwipeGalleryItem? {
        guard let previewItemID else { return nil }
        return viewModel.visibleItems.first(where: { $0.id == previewItemID })
    }

    private func previewSidebar(_ item: SwipeGalleryItem) -> some View {
        let model = viewModel.cardModelsByID[item.id] ?? SwipeCardModel(item: item)
        return SwipePreviewSidebar(
            item: item,
            model: model,
            onStudy: { openStudy(item: item, model: model) },
            onAddToCanvas: { viewModel.addToCanvas(item) },
            onClose: closePreview
        )
    }

    private func openPreview(itemID: String) {
        guard viewModel.visibleItems.contains(where: { $0.id == itemID }) else { return }
        // The catalog grid marks the previewed swipe with its selection ring.
        viewModel.selectedItem = viewModel.visibleItems.first(where: { $0.id == itemID })
        withAnimation(reduceMotion ? nil : ProMotionSprings.focusTransition) {
            previewItemID = itemID
        }
    }

    private func closePreview() {
        guard previewItemID != nil else { return }
        withAnimation(reduceMotion ? nil : ProMotionSprings.focusTransition) {
            previewItemID = nil
        }
    }

    // MARK: - Quick look (unsaved Discover posts)

    @ViewBuilder
    private var postQuickLookLayer: some View {
        if let postQuickLookID,
           let post = discoverModel.visiblePosts.first(where: { $0.id == postQuickLookID }) {
            postQuickLook(post).zIndex(3)
        }
    }

    private func postQuickLook(_ post: SocialPostSnapshot) -> some View {
        SwipeQuickLook(
            expanded: $quickLookExpanded,
            sourceFrame: quickLookSource,
            heroModel: SwipeCardModel(post: post),
            onRequestClose: closePostQuickLook
        ) {
            SwipeQuickLookDiscoverContent(
                post: post,
                model: SwipeCardModel(post: post),
                onSave: { boardID in save(postID: post.id, boardID: boardID) },
                onTranscript: { transcript(postID: post.id) },
                onPrevious: {},
                onNext: {},
                onClose: closePostQuickLook
            )
        }
    }

    private func openPostQuickLook(postID: String) {
        guard postQuickLookID == nil else { return }
        quickLookSource = frameStore.frames[postID]
        quickLookExpanded = false
        postQuickLookID = postID
    }

    private func closePostQuickLook() {
        guard postQuickLookID != nil else { return }
        if let id = postQuickLookID, let frame = frameStore.frames[id] {
            quickLookSource = frame
        }
        guard !reduceMotion else {
            quickLookExpanded = false
            postQuickLookID = nil
            return
        }
        withAnimation(ProMotionSprings.modal, completionCriteria: .logicallyComplete) {
            quickLookExpanded = false
        } completion: {
            postQuickLookID = nil
        }
    }

    private func handleEscape() {
        if showFilters {
            withAnimation(ProMotionSprings.bouncy) { showFilters = false }
        } else if postQuickLookID != nil {
            closePostQuickLook()
        } else if previewItemID != nil {
            closePreview()
        } else if searchFocused {
            searchFocused = false
        } else if !viewModel.query.isEmpty {
            viewModel.query = ""
        }
    }

    // MARK: - Filters & keyboard

    private var filterDropdown: some View {
        SwipeAnchoredFilterDropdown(
            anchor: filterAnchor,
            onDismiss: { withAnimation(ProMotionSprings.bouncy) { showFilters = false } }
        ) { maxHeight in
            SwipeLibraryFilterPanel(viewModel: viewModel, maxHeight: maxHeight)
        }
    }

    private var keyboardLayer: some View {
        Group {
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { Task { await viewModel.reload() } }.keyboardShortcut("r", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func openStudyByID(_ id: String) {
        guard let index = viewModel.visibleItems.firstIndex(where: { $0.id == id }) else { return }
        openStudy(item: viewModel.visibleItems[index], model: viewModel.visibleCardModels[index])
    }

    /// The zoom-through into Swipe Study — same choreography as the Library page.
    private func openStudy(item: SwipeGalleryItem, model: SwipeCardModel) {
        guard studyHero == nil else { return }
        guard !reduceMotion else {
            viewModel.openStudy(item)
            return
        }

        // The preview rail stays open — the card is still visible on the
        // page, so the hero flies from it and the rail is there on return.
        let source: CGRect? = frameStore.frames[item.id]

        studyHeroArrived = false
        studyHero = SwipeStudyHero(model: model, sourceFrame: source)

        Task { @MainActor in
            withAnimation(ProMotionSprings.focusTransition) { studyHeroExpanded = true }
            try? await Task.sleep(for: .milliseconds(80))
            viewModel.openStudy(item)
            // Teardown rides the study's did-appear signal (see onReceive in
            // the body); this is only the failure fallback — if the study
            // never mounts, retreat the card to the grid instead of vanishing.
            try? await Task.sleep(for: .seconds(2))
            guard studyHero != nil, !studyHeroArrived else { return }
            withAnimation(ProMotionSprings.modal) { studyHeroExpanded = false }
            try? await Task.sleep(for: .milliseconds(350))
            if !studyHeroArrived { studyHero = nil }
        }
    }

    /// The study is on screen — hold the hero one spring longer so the focus
    /// layer is opaque before the card beneath it unmounts.
    private func relieveHeroAfterStudyAppears() {
        guard studyHero != nil, !studyHeroArrived else { return }
        studyHeroArrived = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            studyHeroExpanded = false
            studyHero = nil
            studyHeroArrived = false
        }
    }

    private func save(postID: String, boardID: String?) {
        guard let post = discoverModel.visiblePosts.first(where: { $0.id == postID }) else { return }
        discoverModel.save(post, boardID: boardID)
    }

    private func transcript(postID: String) {
        guard let post = discoverModel.visiblePosts.first(where: { $0.id == postID }) else { return }
        postQuickLookID = nil
        quickLookExpanded = false
        Task { await discoverModel.saveAndOpenForTranscription(post) }
    }
}

// MARK: - Pattern tile (shelf size)

/// A recurring move: named, defined, with a mosaic of the swipes sharing it.
private struct SwipeHomePatternTile: View {
    let pattern: SwipePattern
    let coverItems: [SwipeCardModel]
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                SwipeBoardMosaic(coverItems: coverItems, icon: "circle.hexagongrid", height: 116)
                Text(pattern.name)
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text(pattern.definition)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                    .frame(height: 26, alignment: .topLeading)
                Text("\(pattern.members.count) swipes share this move")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
            .padding(10)
            .frame(width: 208, alignment: .topLeading)
            .swipeCardSurface(isHovered: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help("Study this pattern — the chevrons walk its swipes")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pattern.name), \(pattern.members.count) swipes")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Board tile (shelf size)

private struct SwipeHomeBoardTile: View {
    let board: SwipeBoard
    let coverItems: [SwipeCardModel]
    let count: Int
    let onOpen: () -> Void

    @State private var isHovered = false

    /// Board identity, the App Store register: a typed emoji wins (and
    /// cleans the label); boards have no hand-picked mark, so the curated
    /// keyword pass runs too. SF glyph only as the last honest fallback.
    private var identity: (emoji: String?, label: String) {
        CollectionEmoji.resolve(name: board.name)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                SwipeBoardMosaic(coverItems: coverItems, icon: board.icon, height: 116)
                HStack(spacing: 6) {
                    if let emoji = identity.emoji {
                        Text(emoji)
                            .font(DS.caption)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: board.icon)
                            .font(DS.caption.weight(.semibold))
                            .foregroundStyle(DS.textMuted)
                            .accessibilityHidden(true)
                    }
                    Text(identity.label)
                        .font(DS.callout.weight(.semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                }
                Text(count == 1 ? "1 swipe" : "\(count) swipes")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
            .padding(10)
            .frame(width: 208, alignment: .topLeading)
            .swipeCardSurface(isHovered: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(identity.label), \(count) swipes")
        .accessibilityAddTraits(.isButton)
    }
}
