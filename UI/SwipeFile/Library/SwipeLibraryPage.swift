import SwiftUI

/// The shared catalog surface: Library and board detail are the same page with
/// different scopes — searchable, filterable, complete, inside a measure with
/// uniform rows. Loop: scroll → click (quick look) → Return (study) → Esc → next.
struct SwipeLibraryPage: View {
    @Bindable var viewModel: SwipeLibraryViewModel
    let section: SwipeLibrarySectionSelection

    @State private var showFilters = false
    @State private var filterAnchor: CGRect = .zero
    @State private var isQuickLookOpen = false
    @State private var quickLookExpanded = false
    @State private var quickLookSource: CGRect?
    @State private var hero: SwipeStudyHero?
    @State private var heroExpanded = false
    @State private var frameStore = SwipeFrameStore()
    @State private var scrollMetrics = SwipeScrollMetrics()
    @State private var scrollPosition = ScrollPosition()
    @State private var revealDate = Date()
    @State private var pageSize: CGSize = .zero
    @State private var resultsTop: CGFloat = 0
    @State private var contextPillVisible = false
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipePageBackground()
            scrollContent
            if showFilters {
                filterDropdown.zIndex(2)
            }
            if isQuickLookOpen, let item = viewModel.selectedItem {
                quickLook(item).zIndex(3)
            }
            if let hero {
                SwipeStudyHeroOverlay(hero: hero, expanded: heroExpanded).zIndex(4)
            }
        }
        .coordinateSpace(name: "swipePage")
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { pageSize = $0 }
        .onPreferenceChange(SwipeFilterAnchorKey.self) { filterAnchor = $0 }
        .task(id: section) {
            await SwipeBoardStore.shared.loadIfNeeded()
            await viewModel.loadIfNeeded(section: section)
        }
        .onChange(of: viewModel.visibleItemsIdentity) { revealDate = Date() }
        .onExitCommand(perform: handleEscape)
        .background(keyboardLayer)
        .animation(ProMotionSprings.bouncy, value: showFilters)
        .overlay(alignment: .bottom) {
            SwipeSaveToast(message: $viewModel.boardMessage)
        }
    }

    // MARK: - Content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                SwipeLibraryHeader(
                    viewModel: viewModel,
                    title: pageTitle,
                    searchFocused: $searchFocused,
                    showFilters: $showFilters
                )
                SwipeLibraryScopeBar(viewModel: viewModel)
                SwipeLibraryResults(
                    viewModel: viewModel,
                    frameStore: frameStore,
                    revealDate: revealDate,
                    hiddenItemID: isQuickLookOpen ? viewModel.selectedItem?.id : nil,
                    onOpen: { openQuickLook(itemID: $0) },
                    onStudy: { openStudy(itemID: $0) }
                )
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named("swipeLibraryContent")).minY }) {
                    resultsTop = $0
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 36)
            .padding(.bottom, 72)
            .coordinateSpace(name: "swipeLibraryContent")
            .swipeContentMeasure()
        }
        .scrollPosition($scrollPosition)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onScrollGeometryChange(for: CGRect.self, of: { CGRect(origin: $0.contentOffset, size: $0.containerSize) }) { _, new in
            scrollMetrics.offsetY = new.origin.y
            scrollMetrics.viewportHeight = new.size.height
            // Only the threshold crossing touches state — continuous scroll
            // never invalidates the view tree.
            let shouldShow = new.origin.y > 88
            if shouldShow != contextPillVisible {
                contextPillVisible = shouldShow
            }
        }
        .overlay(alignment: .top) {
            SwipeContextPill(
                title: pageTitle,
                detail: "\(viewModel.summary.filteredCount) swipes",
                visible: contextPillVisible
            ) {
                withAnimation(ProMotionSprings.gentle) {
                    scrollPosition.scrollTo(edge: .top)
                }
            }
            .padding(.top, DS.space12)
        }
    }

    private var pageTitle: String {
        if case .board(let id) = section {
            return SwipeBoardStore.shared.board(withID: id)?.name ?? "Board"
        }
        return section.title
    }

    private var filterDropdown: some View {
        SwipeAnchoredFilterDropdown(
            anchor: filterAnchor,
            onDismiss: { withAnimation(ProMotionSprings.bouncy) { showFilters = false } }
        ) { maxHeight in
            SwipeLibraryFilterPanel(viewModel: viewModel, maxHeight: maxHeight)
        }
    }

    private func quickLook(_ item: SwipeGalleryItem) -> some View {
        let index = viewModel.visibleItems.firstIndex { $0.id == item.id }
        return SwipeQuickLook(
            expanded: $quickLookExpanded,
            sourceFrame: quickLookSource,
            heroModel: viewModel.cardModelsByID[item.id] ?? SwipeCardModel(item: item),
            onRequestClose: closeQuickLook
        ) {
            SwipeQuickLookLibraryContent(
                item: item,
                model: viewModel.cardModelsByID[item.id] ?? SwipeCardModel(item: item),
                hasPrevious: (index ?? 0) > 0,
                hasNext: index.map { $0 < viewModel.visibleItems.count - 1 } ?? false,
                onStudy: { openStudy(itemID: item.id) },
                onAddToCanvas: { viewModel.addToCanvas(item) },
                onPrevious: { moveSelection(by: -1) },
                onNext: { moveSelection(by: 1) },
                onClose: closeQuickLook
            )
        }
    }

    // MARK: - Quick look

    private func openQuickLook(itemID: String) {
        guard let item = viewModel.visibleItems.first(where: { $0.id == itemID }) else { return }
        viewModel.selectedItem = item
        if isQuickLookOpen { return }
        // Frames are only recorded by grid cells — in compact mode the stored
        // frame is a stale grid position, so fall back to the centered fade.
        quickLookSource = viewModel.displayMode == .grid ? frameStore.frames[itemID] : nil
        isQuickLookOpen = true
    }

    private func closeQuickLook() {
        guard isQuickLookOpen else { return }
        if viewModel.displayMode == .grid,
           let id = viewModel.selectedItem?.id, let frame = frameStore.frames[id] {
            quickLookSource = frame
        } else {
            quickLookSource = nil
        }
        guard !reduceMotion else {
            quickLookExpanded = false
            isQuickLookOpen = false
            return
        }
        withAnimation(ProMotionSprings.modal, completionCriteria: .logicallyComplete) {
            quickLookExpanded = false
        } completion: {
            isQuickLookOpen = false
        }
    }

    // MARK: - Open study (zoom-through hero)

    private func openStudy(itemID: String) {
        guard let item = viewModel.visibleItems.first(where: { $0.id == itemID }) else { return }
        guard hero == nil else { return }
        guard !reduceMotion else {
            isQuickLookOpen = false
            quickLookExpanded = false
            viewModel.openStudy(item)
            return
        }

        let model = viewModel.cardModelsByID[item.id] ?? SwipeCardModel(item: item)
        let source: CGRect? = isQuickLookOpen
            ? SwipeQuickLookGeometry.panelFrame(in: pageSize)
            : frameStore.frames[item.id]

        isQuickLookOpen = false
        quickLookExpanded = false
        hero = SwipeStudyHero(model: model, sourceFrame: source)

        Task { @MainActor in
            withAnimation(ProMotionSprings.focusTransition) { heroExpanded = true }
            try? await Task.sleep(for: .milliseconds(80))
            viewModel.openStudy(item)
            try? await Task.sleep(for: .milliseconds(520))
            heroExpanded = false
            hero = nil
        }
    }

    // MARK: - Keyboard

    /// Bare-key shortcuts are structurally removed while the search field has focus —
    /// a no-op guard alone would still swallow the keystrokes before the field sees them.
    private var keyboardLayer: some View {
        Group {
            if !searchFocused {
                Button("") { moveSelection(by: 1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { moveSelection(by: -1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { moveSelection(by: columnCount) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("") { moveSelection(by: -columnCount) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { toggleQuickLook() }.keyboardShortcut(.space, modifiers: [])
                Button("") { openSelectedStudy() }.keyboardShortcut(.return, modifiers: [])
            }
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { Task { await viewModel.reload() } }.keyboardShortcut("r", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Grid width under the measure — must mirror the results grid exactly.
    private var gridAvailableWidth: CGFloat {
        max(0, min(pageSize.width, 1180) - 96)
    }

    private var columnCount: Int {
        SwipeWaterfallLayout.columnMetrics(
            availableWidth: gridAvailableWidth,
            targetColumnWidth: 208,
            spacing: 20
        ).count
    }

    private func moveSelection(by delta: Int) {
        guard !searchFocused else { return }
        let items = viewModel.visibleItems
        guard !items.isEmpty else { return }
        let current = viewModel.selectedItem.flatMap { selected in
            items.firstIndex { $0.id == selected.id }
        } ?? 0
        let target = max(0, min(items.count - 1, current + delta))
        guard target != current || viewModel.selectedItem == nil else { return }
        viewModel.selectedItem = items[target]
        scrollToSelection(index: target)
    }

    private func toggleQuickLook() {
        guard !searchFocused else { return }
        if isQuickLookOpen {
            closeQuickLook()
        } else if let selected = viewModel.selectedItem {
            openQuickLook(itemID: selected.id)
        }
    }

    private func openSelectedStudy() {
        guard !searchFocused else { return }
        guard let selected = viewModel.selectedItem else { return }
        openStudy(itemID: selected.id)
    }

    private func handleEscape() {
        if showFilters {
            withAnimation(ProMotionSprings.bouncy) { showFilters = false }
        } else if isQuickLookOpen {
            closeQuickLook()
        } else if searchFocused {
            searchFocused = false
        } else if !viewModel.query.isEmpty {
            viewModel.query = ""
        }
    }

    /// Keeps the keyboard selection on-screen. Skipped for bucketed scopes whose
    /// layout doesn't match the single-grid math.
    private func scrollToSelection(index: Int) {
        guard isQuickLookOpen == false, viewModel.dateSections.isEmpty,
              viewModel.displayMode == .grid else { return }
        // Poster models — the grid renders posters, so the height math must too.
        let models = viewModel.visibleCardModels.map { $0.poster() }
        guard index < models.count else { return }

        let metrics = SwipeWaterfallLayout.columnMetrics(
            availableWidth: gridAvailableWidth,
            targetColumnWidth: 208,
            spacing: 20
        )
        let layout = SwipeWaterfallLayout.compute(
            heights: models.map { $0.height(forWidth: metrics.width) },
            columnCount: metrics.count,
            columnWidth: metrics.width,
            spacing: 20
        )
        guard index < layout.frames.count else { return }

        let frame = layout.frames[index].offsetBy(dx: 0, dy: resultsTop)
        let visibleTop = scrollMetrics.offsetY + 80
        let visibleBottom = scrollMetrics.offsetY + scrollMetrics.viewportHeight - 40

        var targetY: CGFloat?
        if frame.minY < visibleTop {
            targetY = max(0, frame.minY - 120)
        } else if frame.maxY > visibleBottom {
            targetY = frame.maxY - scrollMetrics.viewportHeight + 60
        }
        if let targetY {
            withAnimation(ProMotionSprings.gentle) {
                scrollPosition.scrollTo(y: targetY)
            }
        }
    }
}

/// Live scroll geometry, stored outside the observation system — reads happen only
/// at keypress time, so continuous updates never invalidate the view tree.
final class SwipeScrollMetrics {
    var offsetY: CGFloat = 0
    var viewportHeight: CGFloat = 0
}
