import SwiftUI

/// Discover: one masthead, one functional topic row, one Filters popover, and the
/// masonry. The pillar chips now actually scope the feed.
struct SwipeDiscoverPage: View {
    @Bindable var model: SwipeDiscoverModel

    @State private var showFilters = false
    @State private var filterAnchor: CGRect = .zero
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipePageBackground()
            scrollContent
            if showFilters {
                filterDropdown.zIndex(2)
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

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                masthead
                SwipeDiscoverTopicRow(model: model)
                if let error = model.errorMessage {
                    SwipeDiscoverNotice(text: error, isError: true)
                }
                results
            }
            .padding(.horizontal, 48)
            .padding(.top, 36)
            .padding(.bottom, 72)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    @ViewBuilder
    private var results: some View {
        if model.isLoading && model.posts.isEmpty {
            SwipeSkeletonGrid(targetColumnWidth: 300)
        } else if model.visiblePosts.isEmpty {
            SwipeLibraryErrorState(
                message: model.posts.isEmpty
                    ? "Add a creator in Creators, or widen the posted window in Filters."
                    : "No posts match. Clear a topic or widen the filters.",
                onRetry: { Task { await model.refreshDiscovery() } }
            )
        } else {
            SwipeDiscoverPostGrid(posts: model.visiblePosts, model: model)
        }
    }

    private var masthead: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Discover")
                    .font(DS.pageTitle)
                    .foregroundStyle(DS.text)
                Text(subtitle)
                    .font(DS.subheadline.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
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
        } else if searchFocused {
            searchFocused = false
        } else if !model.query.searchText.isEmpty {
            model.query.searchText = ""
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
