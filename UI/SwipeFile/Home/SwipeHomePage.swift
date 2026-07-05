import SwiftUI

// MARK: - Quick look target

private enum SwipeHomeQuickLookTarget: Equatable {
    case library(String)
    case post(String)

    var itemID: String {
        switch self {
        case .library(let id), .post(let id): return id
        }
    }
}

// MARK: - Home (the magazine)

/// The swipe context's landing page: one hero (Up Next), then shelves — New This
/// Week, Study Queue, Boards, Outliers. Browsing and deciding happens here; the
/// complete searchable catalog is the Library.
struct SwipeHomePage: View {
    @Bindable var viewModel: SwipeLibraryViewModel
    @Bindable var discoverModel: SwipeDiscoverModel
    let onNavigate: (SidebarDestination) -> Void

    @State private var frameStore = SwipeFrameStore()
    @State private var quickLook: SwipeHomeQuickLookTarget?
    @State private var quickLookExpanded = false
    @State private var quickLookSource: CGRect?
    @State private var studyHero: SwipeStudyHero?
    @State private var studyHeroExpanded = false
    @State private var contextPillVisible = false
    @State private var scrollPosition = ScrollPosition()
    @State private var pageSize: CGSize = .zero
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipePageBackground()
            scrollContent
            quickLookLayer
            if let studyHero {
                SwipeStudyHeroOverlay(hero: studyHero, expanded: studyHeroExpanded).zIndex(4)
            }
        }
        .coordinateSpace(name: "swipePage")
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { pageSize = $0 }
        .task {
            await SwipeBoardStore.shared.loadIfNeeded()
            await viewModel.loadIfNeeded(section: .home)
            viewModel.setSection(.home)
            await discoverModel.loadIfNeeded()
        }
        .onExitCommand(perform: handleEscape)
        .overlay(alignment: .bottom) { SwipeSaveToast(message: $viewModel.boardMessage) }
        .overlay(alignment: .bottom) { SwipeSaveToast(message: $discoverModel.saveMessage) }
    }

    // MARK: - Content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                masthead
                if viewModel.isLoading && viewModel.allItems.isEmpty {
                    SwipeSkeletonGrid()
                } else if viewModel.allItems.isEmpty {
                    SwipeLibraryEmptyState(scope: .home, hasActiveFilters: false, onClearFilters: {})
                } else {
                    editorial
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
                onPreview: { openQuickLook(.library(item.id)) },
                frameStore: frameStore
            ) {
                openStudy(item: item, model: model)
            }
        }
        if !newThisWeek.isEmpty {
            librarySwipeShelf(label: "NEW THIS WEEK", models: newThisWeek) {
                onNavigate(.swipeFile(section: .all))
            }
        }
        if !studyQueue.isEmpty {
            librarySwipeShelf(label: "STUDY QUEUE", count: viewModel.summary.unstudiedCount, models: studyQueue) {
                onNavigate(.swipeFile(section: .unstudied))
            }
        }
        boardsShelf
        outliersShelf
    }

    private var masthead: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            SwipeMasthead(title: "Swipes", detail: mastheadDetail)
            Spacer(minLength: DS.space16)
            SwipeLibrarySearchField(text: $viewModel.query, isFocused: $searchFocused)
                .onChange(of: viewModel.query) { _, new in
                    // Search is the catalog's job — the first keystroke lands there.
                    if !new.isEmpty {
                        onNavigate(.swipeFile(section: .all))
                    }
                }
        }
    }

    private var mastheadDetail: String {
        var parts = ["\(viewModel.summary.totalCount) saved"]
        if viewModel.summary.unstudiedCount > 0 {
            parts.append("\(viewModel.summary.unstudiedCount) to study")
        }
        return parts.joined(separator: " · ")
    }

    private var contextPill: some View {
        SwipeContextPill(
            title: "Swipes",
            detail: "\(viewModel.summary.unstudiedCount) to study",
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

    private var newThisWeek: [SwipeCardModel] {
        Array(
            SwipeLibraryDateBucket.lastWeekModels(items: viewModel.visibleItems, models: viewModel.visibleCardModels)
                .filter { $0.id != heroPick?.1.id }
                .prefix(12)
        )
        .map { $0.poster() }
    }

    /// Oldest-first — the backlog clears from the back.
    private var studyQueue: [SwipeCardModel] {
        Array(
            zip(viewModel.visibleItems, viewModel.visibleCardModels)
                .filter { !$0.0.isStudied && $0.1.id != heroPick?.1.id }
                .map(\.1)
                .reversed()
                .prefix(12)
        )
        .map { $0.poster() }
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

    private func librarySwipeShelf(
        label: String,
        count: Int? = nil,
        models: [SwipeCardModel],
        onSeeAll: @escaping () -> Void
    ) -> some View {
        SwipeShelf(
            label: label,
            count: count,
            onSeeAll: onSeeAll,
            models: models,
            hiddenItemID: quickLook?.itemID,
            frameStore: frameStore
        ) { model in
            SwipeCardActions(
                onOpen: { openQuickLook(.library(model.id)) },
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
                hiddenItemID: quickLook?.itemID,
                frameStore: frameStore
            ) { model in
                SwipeCardActions(
                    onOpen: { openQuickLook(.post(model.id)) },
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

    // MARK: - Quick look

    @ViewBuilder
    private var quickLookLayer: some View {
        if let quickLook {
            switch quickLook {
            case .library(let id):
                if let index = viewModel.visibleItems.firstIndex(where: { $0.id == id }) {
                    libraryQuickLook(viewModel.visibleItems[index]).zIndex(3)
                }
            case .post(let id):
                if let post = discoverModel.visiblePosts.first(where: { $0.id == id }) {
                    postQuickLook(post).zIndex(3)
                }
            }
        }
    }

    private func libraryQuickLook(_ item: SwipeGalleryItem) -> some View {
        let model = viewModel.cardModelsByID[item.id] ?? SwipeCardModel(item: item)
        return SwipeQuickLook(
            expanded: $quickLookExpanded,
            sourceFrame: quickLookSource,
            heroModel: model,
            onRequestClose: closeQuickLook
        ) {
            SwipeQuickLookLibraryContent(
                item: item,
                model: model,
                onStudy: { openStudy(item: item, model: model) },
                onAddToCanvas: { viewModel.addToCanvas(item) },
                onPrevious: {},
                onNext: {},
                onClose: closeQuickLook
            )
        }
    }

    private func postQuickLook(_ post: SocialPostSnapshot) -> some View {
        SwipeQuickLook(
            expanded: $quickLookExpanded,
            sourceFrame: quickLookSource,
            heroModel: SwipeCardModel(post: post),
            onRequestClose: closeQuickLook
        ) {
            SwipeQuickLookDiscoverContent(
                post: post,
                model: SwipeCardModel(post: post),
                onSave: { boardID in save(postID: post.id, boardID: boardID) },
                onTranscript: { transcript(postID: post.id) },
                onPrevious: {},
                onNext: {},
                onClose: closeQuickLook
            )
        }
    }

    private func openQuickLook(_ target: SwipeHomeQuickLookTarget) {
        guard quickLook == nil else { return }
        quickLookSource = frameStore.frames[target.itemID]
        quickLookExpanded = false
        quickLook = target
    }

    private func closeQuickLook() {
        guard quickLook != nil else { return }
        if let id = quickLook?.itemID, let frame = frameStore.frames[id] {
            quickLookSource = frame
        }
        guard !reduceMotion else {
            quickLookExpanded = false
            quickLook = nil
            return
        }
        withAnimation(ProMotionSprings.modal, completionCriteria: .logicallyComplete) {
            quickLookExpanded = false
        } completion: {
            quickLook = nil
        }
    }

    private func handleEscape() {
        if quickLook != nil {
            closeQuickLook()
        } else if searchFocused {
            searchFocused = false
        }
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
            quickLook = nil
            quickLookExpanded = false
            viewModel.openStudy(item)
            return
        }

        let source: CGRect? = quickLook != nil
            ? SwipeQuickLookGeometry.panelFrame(in: pageSize)
            : frameStore.frames[item.id]

        quickLook = nil
        quickLookExpanded = false
        studyHero = SwipeStudyHero(model: model, sourceFrame: source)

        Task { @MainActor in
            withAnimation(ProMotionSprings.focusTransition) { studyHeroExpanded = true }
            try? await Task.sleep(for: .milliseconds(80))
            viewModel.openStudy(item)
            try? await Task.sleep(for: .milliseconds(520))
            studyHeroExpanded = false
            studyHero = nil
        }
    }

    private func save(postID: String, boardID: String?) {
        guard let post = discoverModel.visiblePosts.first(where: { $0.id == postID }) else { return }
        discoverModel.save(post, boardID: boardID)
    }

    private func transcript(postID: String) {
        guard let post = discoverModel.visiblePosts.first(where: { $0.id == postID }) else { return }
        quickLook = nil
        quickLookExpanded = false
        Task { await discoverModel.saveAndOpenForTranscription(post) }
    }
}

// MARK: - Board tile (shelf size)

private struct SwipeHomeBoardTile: View {
    let board: SwipeBoard
    let coverItems: [SwipeCardModel]
    let count: Int
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                SwipeBoardMosaic(coverItems: coverItems, icon: board.icon, height: 116)
                HStack(spacing: 6) {
                    Image(systemName: board.icon)
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                    Text(board.name)
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
        .accessibilityLabel("\(board.name), \(count) swipes")
        .accessibilityAddTraits(.isButton)
    }
}
