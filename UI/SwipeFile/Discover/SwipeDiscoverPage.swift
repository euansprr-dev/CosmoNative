import SwiftUI

/// Discover, the editorial feed: a top-outlier hero, one shelf per pillar with
/// enough posts, then the complete browse grid. Searching or scoping to a pillar
/// collapses the page to catalog mode — finding beats rhythm.
struct SwipeDiscoverPage: View {
    @Bindable var model: SwipeDiscoverModel

    @State private var showFilters = false
    @State private var filterAnchor: CGRect = .zero
    @State private var contextPillVisible = false
    @State private var scrollPosition = ScrollPosition()
    @State private var shelfFrameStore = SwipeFrameStore()
    @State private var shelfQuickLookID: String?
    @State private var shelfQuickLookExpanded = false
    @State private var shelfQuickLookSource: CGRect?
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipePageBackground()
            scrollContent
            if showFilters {
                filterDropdown.zIndex(2)
            }
            if let post = shelfQuickLookPost {
                shelfQuickLook(post).zIndex(3)
            }
        }
        .coordinateSpace(name: "swipePage")
        .onPreferenceChange(SwipeFilterAnchorKey.self) { filterAnchor = $0 }
        .task { await model.loadIfNeeded() }
        .onExitCommand(perform: handleEscape)
        .animation(ProMotionSprings.bouncy, value: showFilters)
        .overlay(alignment: .bottom) {
            SwipeSaveToast(message: $model.saveMessage)
        }
    }

    /// Catalog mode: the user is finding, not browsing — shelves and hero yield
    /// to the flat grid plus the narrowing chip row.
    private var isCatalogMode: Bool {
        !model.query.searchText.isEmpty || model.activePillar != nil
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                masthead
                if let error = model.errorMessage {
                    SwipeDiscoverNotice(text: error, isError: true)
                }
                results
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
        .overlay(alignment: .top) {
            SwipeContextPill(
                title: "Discover",
                detail: model.activePillar?.title ?? "\(model.visiblePosts.count) posts",
                visible: contextPillVisible
            ) {
                withAnimation(ProMotionSprings.gentle) {
                    scrollPosition.scrollTo(edge: .top)
                }
            }
            .padding(.top, DS.space12)
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.isLoading && model.posts.isEmpty {
            SwipeSkeletonGrid(targetColumnWidth: 248)
        } else if model.visiblePosts.isEmpty {
            SwipeLibraryErrorState(
                message: model.posts.isEmpty
                    ? "Add a creator in Creators, or widen the posted window in Filters."
                    : "No posts match. Clear a topic or widen the filters.",
                onRetry: { Task { await model.refreshDiscovery() } }
            )
        } else if isCatalogMode {
            VStack(alignment: .leading, spacing: DS.space16) {
                SwipeDiscoverTopicRow(model: model)
                SwipeDiscoverPostGrid(posts: model.visiblePosts, model: model)
            }
        } else {
            editorial
        }
    }

    // MARK: - Editorial

    @ViewBuilder
    private var editorial: some View {
        if let post = model.topOutlierPost {
            heroCard(post)
        }
        ForEach(pillarShelves, id: \.pillar) { shelf in
            pillarShelf(shelf.pillar, posts: shelf.posts)
        }
        VStack(alignment: .leading, spacing: DS.space12) {
            SwipeSectionHeader(label: "EVERYTHING", count: model.visiblePosts.count)
            SwipeDiscoverPostGrid(posts: model.visiblePosts, model: model)
        }
    }

    private var pillarShelves: [(pillar: SwipeDiscoverPillar, posts: [SocialPostSnapshot])] {
        SwipeDiscoverPillar.allCases.compactMap { pillar in
            let posts = model.posts(for: pillar)
            return posts.count >= 4 ? (pillar, Array(posts.prefix(12))) : nil
        }
    }

    private func heroCard(_ post: SocialPostSnapshot) -> some View {
        let cardModel = SwipeCardModel(post: post)
        let kicker = cardModel.outlierLabel.map { "TOP OUTLIER · \($0)" } ?? "TOP OUTLIER"
        return SwipeHeroCard(
            kicker: kicker,
            model: cardModel,
            ctaLabel: "Save",
            ctaIcon: "bookmark.fill",
            onPreview: { openShelfQuickLook(postID: post.id) },
            frameStore: shelfFrameStore
        ) {
            model.save(post, boardID: nil)
        }
    }

    private func pillarShelf(_ pillar: SwipeDiscoverPillar, posts: [SocialPostSnapshot]) -> some View {
        SwipeShelf(
            label: pillar.title.uppercased(),
            count: model.posts(for: pillar).count,
            onSeeAll: {
                withAnimation(ProMotionSprings.snappy) { model.activePillar = pillar }
            },
            models: posts.map { SwipeCardModel(post: $0).poster() },
            hiddenItemID: shelfQuickLookID,
            frameStore: shelfFrameStore
        ) { cardModel in
            SwipeCardActions(
                onOpen: { openShelfQuickLook(postID: cardModel.id) },
                onStudy: { transcript(postID: cardModel.id) },
                onBookmark: { savePost(cardModel.id, boardID: nil) }
            )
        }
    }

    // MARK: - Shelf quick look

    private var shelfQuickLookPost: SocialPostSnapshot? {
        guard let shelfQuickLookID else { return nil }
        return model.visiblePosts.first { $0.id == shelfQuickLookID }
    }

    private func shelfQuickLook(_ post: SocialPostSnapshot) -> some View {
        SwipeQuickLook(
            expanded: $shelfQuickLookExpanded,
            sourceFrame: shelfQuickLookSource,
            heroModel: SwipeCardModel(post: post),
            onRequestClose: closeShelfQuickLook
        ) {
            SwipeQuickLookDiscoverContent(
                post: post,
                model: SwipeCardModel(post: post),
                onSave: { boardID in savePost(post.id, boardID: boardID) },
                onTranscript: { transcript(postID: post.id) },
                onPrevious: {},
                onNext: {},
                onClose: closeShelfQuickLook
            )
        }
    }

    private func openShelfQuickLook(postID: String) {
        guard shelfQuickLookID == nil else { return }
        shelfQuickLookSource = shelfFrameStore.frames[postID]
        shelfQuickLookExpanded = false
        shelfQuickLookID = postID
    }

    private func closeShelfQuickLook() {
        guard shelfQuickLookID != nil else { return }
        if let id = shelfQuickLookID, let frame = shelfFrameStore.frames[id] {
            shelfQuickLookSource = frame
        }
        guard !reduceMotion else {
            shelfQuickLookExpanded = false
            shelfQuickLookID = nil
            return
        }
        withAnimation(ProMotionSprings.modal, completionCriteria: .logicallyComplete) {
            shelfQuickLookExpanded = false
        } completion: {
            shelfQuickLookID = nil
        }
    }

    private func savePost(_ postID: String, boardID: String?) {
        guard let post = model.visiblePosts.first(where: { $0.id == postID }) else { return }
        model.save(post, boardID: boardID)
    }

    private func transcript(postID: String) {
        guard let post = model.visiblePosts.first(where: { $0.id == postID }) else { return }
        shelfQuickLookID = nil
        shelfQuickLookExpanded = false
        Task { await model.saveAndOpenForTranscription(post) }
    }

    private var masthead: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            SwipeMasthead(title: "Discover", detail: subtitle)
            Spacer(minLength: DS.space16)
            HStack(spacing: 8) {
                SwipeLibrarySearchField(
                    text: $model.query.searchText,
                    isFocused: $searchFocused,
                    placeholder: "Search posts, hooks, creators"
                )
                filtersButton
                reloadButton
            }
        }
    }

    private var subtitle: String {
        let count = model.visiblePosts.count
        return count > 0
            ? "\(count) high-performing posts"
            : "High-performing posts across platforms"
    }

    private var filtersButton: some View {
        SwipeLibraryFiltersButton(activeCount: activeFilterCount, isOpen: $showFilters)
            .help(SwipeDiscoveryFilterPresentation.summary(for: model.query))
    }

    private var activeFilterCount: Int {
        var count = 0
        if !model.query.platforms.isEmpty { count += 1 }
        if !model.query.usesDefaultFormats { count += 1 }
        if model.query.followerRange != .any { count += 1 }
        if model.query.minimumOutlierMultiplier != nil { count += 1 }
        if model.query.postedWindow != .lastThreeMonths { count += 1 }
        return count
    }

    private var reloadButton: some View {
        Button {
            Task { await model.refreshDiscovery() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(DS.glassInputFill))
                .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .help("Reload discovery (⌘R)")
        .accessibilityLabel("Reload discovery")
    }

    private var filterDropdown: some View {
        SwipeAnchoredFilterDropdown(
            anchor: filterAnchor,
            onDismiss: { withAnimation(ProMotionSprings.bouncy) { showFilters = false } }
        ) { maxHeight in
            SwipeDiscoveryFilterPanel(model: model, maxHeight: maxHeight)
        }
    }

    private func handleEscape() {
        if showFilters {
            withAnimation(ProMotionSprings.bouncy) { showFilters = false }
        } else if shelfQuickLookID != nil {
            closeShelfQuickLook()
        } else if searchFocused {
            searchFocused = false
        } else if !model.query.searchText.isEmpty {
            model.query.searchText = ""
        } else if model.activePillar != nil {
            withAnimation(ProMotionSprings.snappy) { model.activePillar = nil }
        }
    }
}

// MARK: - Topic scope row

struct SwipeDiscoverTopicRow: View {
    @Bindable var model: SwipeDiscoverModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SwipeDiscoverPillar.allCases) { pillar in
                SwipeDiscoverTopicChip(
                    pillar: pillar,
                    isSelected: model.activePillar == pillar
                ) {
                    withAnimation(ProMotionSprings.snappy) { model.togglePillar(pillar) }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SwipeDiscoverTopicChip: View {
    let pillar: SwipeDiscoverPillar
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: pillar.systemImage)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? pillar.tint : DS.textMuted)
                    .accessibilityHidden(true)
                Text(pillar.title)
                    .font(DS.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? DS.text : (hovering ? DS.textSecondary : DS.textMuted))
            }
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(Capsule().fill(isSelected ? pillar.tint.opacity(0.12) : (hovering ? DS.glassInputFill : Color.clear)))
            .overlay(Capsule().strokeBorder(isSelected ? pillar.tint.opacity(0.45) : DS.glassBorder, lineWidth: isSelected ? 1 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(ProMotionSprings.hover) { hovering = value } }
        .help("Scope the feed to \(pillar.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Quiet notice

struct SwipeDiscoverNotice: View {
    let text: String
    var isError = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle" : "info.circle")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text(text)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Save toast

/// 1.2s confirmation capsule — the page's single delight moment.
struct SwipeSaveToast: View {
    @Binding var message: String?

    var body: some View {
        Group {
            if let message {
                Text(message)
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .task {
                        try? await Task.sleep(for: .milliseconds(1600))
                        withAnimation(ProMotionSprings.gentle) { self.message = nil }
                    }
            }
        }
        .padding(.bottom, 24)
        .animation(ProMotionSprings.bouncy, value: message)
        .allowsHitTesting(false)
    }
}
