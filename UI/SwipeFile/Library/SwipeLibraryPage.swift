import SwiftUI

/// The shared catalog surface: Library and board detail are the same page with
/// different scopes — searchable, filterable, complete, inside a measure with
/// uniform rows. Loop: scroll → click (preview rail) → Return (study) → Esc → next.
struct SwipeLibraryPage: View {
    @Bindable var viewModel: SwipeLibraryViewModel
    let section: SwipeLibrarySectionSelection

    @State private var showFilters = false
    @State private var filterAnchor: CGRect = .zero
    @State private var isPreviewOpen = false
    @State private var hero: SwipeStudyHero?
    @State private var heroExpanded = false
    @State private var heroStudyArrived = false
    @State private var frameStore = SwipeFrameStore()
    @State private var scrollMetrics = SwipeScrollMetrics()
    @State private var scrollPosition = ScrollPosition()
    @State private var revealDate = Date()
    @State private var pageSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0
    @State private var resultsTop: CGFloat = 0
    @State private var contextPillVisible = false
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Preview is a trailing rail (the Command Center grammar), not an
        // overlay — the catalog keeps working beside it, and arrow keys
        // retarget it in place.
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                SwipePageBackground()
                scrollContent
                if showFilters {
                    filterDropdown.zIndex(2)
                }
                if let hero {
                    SwipeStudyHeroOverlay(hero: hero, expanded: heroExpanded).zIndex(4)
                }
            }
            .coordinateSpace(name: "swipePage")
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { pageSize = $0 }

            if isPreviewOpen, let item = viewModel.selectedItem {
                preview(item)
                    .frame(width: SwipePreviewSidebar.width(forContainerWidth: containerWidth))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { containerWidth = $0 }
        .onPreferenceChange(SwipeFilterAnchorKey.self) { filterAnchor = $0 }
        .task(id: section) {
            await SwipeBoardStore.shared.loadIfNeeded()
            await viewModel.loadIfNeeded(section: section)
            // Each room opens in its native view (Copy/Scripts read as a
            // list); the shared catalog scopes keep the user's last choice.
            viewModel.applyRoomDefaultDisplayMode(for: section)
        }
        .onAppear { viewModel.surfaceDidAppear() }
        .onDisappear { viewModel.surfaceDidDisappear() }
        .onChange(of: viewModel.visibleItemsIdentity) { revealDate = Date() }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.swipeStudyDidAppear)) { _ in
            relieveHeroAfterStudyAppears()
        }
        .onExitCommand(perform: handleEscape)
        .background(keyboardLayer)
        .animation(ProMotionSprings.bouncy, value: showFilters)
        .overlay(alignment: .bottom) {
            SwipeSaveToast(message: $viewModel.boardMessage)
        }
        // The recording pill rides every surface that can capture — this page
        // is a drop target, so a forgotten recording session must stay visible.
        .overlay(alignment: .topTrailing) {
            SwipeFlowRecordingPill()
                .padding(.trailing, DS.space24)
                .padding(.top, DS.space16)
        }
        .swipeLibraryDropTarget()
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
                if section == .genre(.funnel) {
                    SwipeFunnelRecordCTA()
                }
                SwipeLibraryResults(
                    viewModel: viewModel,
                    frameStore: frameStore,
                    revealDate: revealDate,
                    hiddenItemID: nil,
                    onOpen: { openPreview(itemID: $0) },
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

    private func preview(_ item: SwipeGalleryItem) -> some View {
        // Arrow keys retarget the preview through the grid — the page-level
        // keyboard layer owns that; the rail stays chrome-free.
        SwipePreviewSidebar(
            item: item,
            model: viewModel.cardModelsByID[item.id] ?? SwipeCardModel(item: item),
            onStudy: { openStudy(itemID: item.id) },
            onAddToCanvas: { viewModel.addToCanvas(item) },
            onClose: closePreview
        )
    }

    // MARK: - Preview rail

    private func openPreview(itemID: String) {
        guard let item = viewModel.visibleItems.first(where: { $0.id == itemID }) else { return }
        viewModel.selectedItem = item
        guard !isPreviewOpen else { return }
        withAnimation(reduceMotion ? nil : ProMotionSprings.focusTransition) {
            isPreviewOpen = true
        }
    }

    private func closePreview() {
        guard isPreviewOpen else { return }
        withAnimation(reduceMotion ? nil : ProMotionSprings.focusTransition) {
            isPreviewOpen = false
        }
    }

    // MARK: - Open study (zoom-through hero)

    private func openStudy(itemID: String) {
        guard let item = viewModel.visibleItems.first(where: { $0.id == itemID }) else { return }
        guard hero == nil else { return }
        guard !reduceMotion else {
            viewModel.openStudy(item)
            return
        }

        // The preview rail stays open — the card is still visible in the
        // grid, so the hero flies from it and the rail is there on return.
        let model = viewModel.cardModelsByID[item.id] ?? SwipeCardModel(item: item)
        let source: CGRect? = frameStore.frames[item.id]

        heroStudyArrived = false
        hero = SwipeStudyHero(model: model, sourceFrame: source)

        Task { @MainActor in
            withAnimation(ProMotionSprings.focusTransition) { heroExpanded = true }
            try? await Task.sleep(for: .milliseconds(80))
            viewModel.openStudy(item)
            // Teardown rides the study's did-appear signal (see onReceive in
            // the body); this is only the failure fallback — if the study
            // never mounts, retreat the card to the grid instead of vanishing.
            try? await Task.sleep(for: .seconds(2))
            guard hero != nil, !heroStudyArrived else { return }
            withAnimation(ProMotionSprings.modal) { heroExpanded = false }
            try? await Task.sleep(for: .milliseconds(350))
            if !heroStudyArrived { hero = nil }
        }
    }

    /// The study is on screen — hold the hero one spring longer so the focus
    /// layer is opaque before the card beneath it unmounts.
    private func relieveHeroAfterStudyAppears() {
        guard hero != nil, !heroStudyArrived else { return }
        heroStudyArrived = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            heroExpanded = false
            hero = nil
            heroStudyArrived = false
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
                Button("") { togglePreview() }.keyboardShortcut(.space, modifiers: [])
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
        // Arrow browsing should never wait on media — warm the neighbors so
        // the next retarget (preview rail or Study) lands on full caches.
        for neighbor in [target - 1, target + 1] where items.indices.contains(neighbor) {
            SwipeStudyPrewarmer.shared.prewarm(uuid: items[neighbor].id, includeHeavyMedia: true)
        }
    }

    private func togglePreview() {
        guard !searchFocused else { return }
        if isPreviewOpen {
            closePreview()
        } else if let selected = viewModel.selectedItem {
            openPreview(itemID: selected.id)
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
        } else if isPreviewOpen {
            closePreview()
        } else if searchFocused {
            searchFocused = false
        } else if !viewModel.query.isEmpty {
            viewModel.query = ""
        }
    }

    /// Keeps the keyboard selection on-screen. Skipped for bucketed scopes whose
    /// layout doesn't match the single-grid math.
    private func scrollToSelection(index: Int) {
        guard viewModel.dateSections.isEmpty,
              viewModel.displayMode == .grid else { return }
        // Poster models — the grid renders posters, so the height math must too.
        let models = viewModel.visiblePosterModels
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

// MARK: - Funnels room CTA

/// "Record a funnel" — the Funnels room's one live affordance. Starting a
/// session flips the global recording pill on; while recording this row
/// yields (the pill IS the state, and two records reads as two systems).
private struct SwipeFunnelRecordCTA: View {
    @State private var recorder = SwipeFlowRecorder.shared
    @State private var isHovered = false

    var body: some View {
        if recorder.session == nil {
            Button {
                Task { _ = await SwipeFlowRecorder.shared.start(named: SwipeFlowRecorder.defaultName()) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.accent)
                        .accessibilityHidden(true)
                    Text("Record a funnel")
                        .font(DS.subheadline.weight(.semibold))
                        .foregroundStyle(DS.text)
                    Text("every page you swipe becomes a step")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textMuted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    isHovered ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(DS.glassSectionFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(ProMotionSprings.hover, value: isHovered)
            .help("Start a recording session — captures append as steps")
            .accessibilityLabel("Record a funnel")
        }
    }
}
