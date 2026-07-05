import SwiftUI

/// Creators: a card directory (not a settings list) with an in-page profile push.
struct SwipeCreatorsPage: View {
    @Bindable var model: SwipeDiscoverModel

    @State private var selectedCreatorID: String?
    @State private var contextPillVisible = false
    @State private var scrollPosition = ScrollPosition()
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipePageBackground()
            if let creator = selectedCreatorID.flatMap({ model.creator(id: $0) }) {
                SwipeCreatorProfilePane(
                    creator: creator,
                    model: model,
                    onBack: { withAnimation(ProMotionSprings.focusTransition) { selectedCreatorID = nil } }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                directory
                    .transition(.opacity)
            }
        }
        .coordinateSpace(name: "swipePage")
        .task { await model.loadIfNeeded() }
        .overlay(alignment: .bottom) {
            SwipeSaveToast(message: $model.saveMessage)
        }
    }

    // MARK: - Directory

    private var directory: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                masthead
                importNotices
                if model.isLoading && model.creators.isEmpty {
                    SwipeSkeletonGrid(targetColumnWidth: 248)
                } else if model.filteredCreators.isEmpty {
                    emptyState
                } else {
                    creatorGrid
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
        .overlay(alignment: .top) {
            SwipeContextPill(
                title: "Creators",
                detail: "\(model.filteredCreators.count) profiles",
                visible: contextPillVisible
            ) {
                withAnimation(ProMotionSprings.gentle) {
                    scrollPosition.scrollTo(edge: .top)
                }
            }
            .padding(.top, DS.space12)
        }
    }

    private var masthead: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            SwipeMasthead(title: "Creators", detail: "\(model.filteredCreators.count) profiles to study")
            Spacer(minLength: DS.space16)
            HStack(spacing: 8) {
                sortMenu
                SwipeLibrarySearchField(
                    text: $model.creatorSearchText,
                    isFocused: $searchFocused,
                    placeholder: "Search or paste profile URL"
                )
                addButton
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SocialDiscoverySort.allCases, id: \.rawValue) { sort in
                Button {
                    model.creatorSortMode = sort
                } label: {
                    if model.creatorSortMode == sort {
                        Label(sort.displayName, systemImage: "checkmark")
                    } else {
                        Text(sort.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(DS.caption.weight(.semibold))
                Text(model.creatorSortMode.displayName)
                    .font(DS.subheadline.weight(.medium))
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(DS.glassInputFill))
            .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Sort creators")
        .accessibilityLabel("Sort: \(model.creatorSortMode.displayName)")
    }

    private var addButton: some View {
        Button {
            model.addCreatorFromSearch()
        } label: {
            HStack(spacing: 6) {
                if model.isAddingCreator {
                    Image(systemName: "hourglass")
                        .font(DS.caption.weight(.semibold))
                } else {
                    Image(systemName: "plus")
                        .font(DS.caption.weight(.bold))
                }
                Text("Add creator")
                    .font(DS.subheadline.weight(.semibold))
            }
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(DS.accent, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isAddingCreator)
        .help("Add the pasted URL or platform:handle to the discovery graph")
        .accessibilityLabel("Add creator")
    }

    @ViewBuilder
    private var importNotices: some View {
        if let message = model.creatorImportMessage {
            SwipeDiscoverNotice(text: message)
        }
        if let error = model.creatorImportError {
            SwipeDiscoverNotice(text: error, isError: true)
        }
    }

    private var emptyState: some View {
        SwipeLibraryErrorState(
            message: model.creatorSearchText.isEmpty
                ? "Paste a profile URL above — like youtube:aliabdaal — to start the discovery graph."
                : "No creators match. Press Add creator to import this profile.",
            onRetry: { Task { await model.reload() } }
        )
    }

    private var creatorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
            ForEach(model.filteredCreators) { creator in
                SwipeCreatorCard(creator: creator) {
                    withAnimation(ProMotionSprings.focusTransition) { selectedCreatorID = creator.id }
                }
            }
        }
    }
}

// MARK: - Creator card

private struct SwipeCreatorCard: View {
    let creator: SwipeCreatorRecord
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identityRow
            outlierStrip
            Text(meta)
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.textMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .swipeCardSurface(isHovered: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(creator.name), \(creator.handle)")
        .accessibilityAddTraits(.isButton)
    }

    private var identityRow: some View {
        HStack(spacing: 10) {
            SwipeCreatorAvatar(url: creator.avatarURL, name: creator.name, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(creator.name)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text(handleLine)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: creator.platform.iconName)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
        }
    }

    private var handleLine: String {
        var parts = [creator.handle]
        if let followers = creator.followerCount {
            parts.append("\(SwipeFormatting.count(followers)) followers")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var outlierStrip: some View {
        if creator.topPosts.isEmpty {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.glassSectionFill)
                .frame(height: 56)
                .overlay {
                    Text("No posts imported yet")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
        } else {
            HStack(spacing: 6) {
                ForEach(creator.topPosts.prefix(3), id: \.id) { post in
                    SwipeCreatorTopThumb(post: post)
                }
            }
        }
    }

    private var meta: String {
        var parts = ["\(creator.postCount) posts"]
        if let top = creator.topOutlierMultiplier, top >= 2 {
            parts.append("top \(Int(top.rounded()))×")
        }
        if creator.totalViews > 0 {
            parts.append("\(SwipeFormatting.count(creator.totalViews)) views")
        }
        return parts.joined(separator: " · ")
    }
}

private struct SwipeCreatorTopThumb: View {
    let post: SocialPostSnapshot

    private var thumbnailURL: URL? {
        post.media.first(where: { $0.kind == .thumbnail || $0.kind == .image })?.url
    }

    var body: some View {
        CachedAsyncImage(
            url: thumbnailURL,
            stableKey: post.providerPostID.isEmpty ? nil : "\(post.platform.rawValue)-\(post.providerPostID)"
        ) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty, .failure:
                Rectangle().fill(DS.glassSectionFill)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let multiplier = post.derived.outlierMultiplier, multiplier >= 2 {
                Text("\(Int(multiplier.rounded()))×")
                    .font(DS.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 14)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(4)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Avatar

struct SwipeCreatorAvatar: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        CachedAsyncImage(url: url, stableKey: url.map { "avatar-\($0.absoluteString.hashValue)" }) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty, .failure:
                Circle()
                    .fill(DS.glassSectionFill)
                    .overlay {
                        Text(String(name.prefix(1)).uppercased())
                            .font(size > 56 ? DS.title2 : DS.subheadline.weight(.semibold))
                            .foregroundStyle(DS.textMuted)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Profile

struct SwipeCreatorProfilePane: View {
    let creator: SwipeCreatorRecord
    @Bindable var model: SwipeDiscoverModel
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                backButton
                profileMasthead
                SwipeDiscoverPostGrid(posts: sortedPosts, model: model)
            }
            .padding(.horizontal, 48)
            .padding(.top, 28)
            .padding(.bottom, 72)
            .swipeContentMeasure()
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onExitCommand(perform: onBack)
    }

    private var sortedPosts: [SocialPostSnapshot] {
        model.posts(for: creator).sorted { ($0.derived.outlierMultiplier ?? 0) > ($1.derived.outlierMultiplier ?? 0) }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(DS.caption.weight(.semibold))
                Text("Creators")
                    .font(DS.subheadline.weight(.medium))
            }
            .foregroundStyle(DS.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("[", modifiers: .command)
        .help("Back to creators (Esc)")
    }

    private var profileMasthead: some View {
        HStack(alignment: .center, spacing: DS.space16) {
            SwipeCreatorAvatar(url: creator.avatarURL, name: creator.name, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(creator.name)
                    .font(DS.pageTitle)
                    .foregroundStyle(DS.text)
                Text(metaLine)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textMuted)
                if let bio = creator.bio, !bio.isEmpty {
                    Text(bio)
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: 560, alignment: .leading)
                }
            }
            Spacer(minLength: DS.space16)
            stats
        }
    }

    private var metaLine: String {
        var parts = [creator.handle]
        if let followers = creator.followerCount {
            parts.append("\(SwipeFormatting.count(followers)) followers")
        }
        parts.append(creator.platform.displayName)
        return parts.joined(separator: " · ")
    }

    private var stats: some View {
        HStack(spacing: DS.space20) {
            stat(value: "\(creator.postCount)", label: "posts")
            stat(value: SwipeFormatting.count(creator.totalViews), label: "views")
            if let top = creator.topOutlierMultiplier {
                stat(value: "\(Int(top.rounded()))×", label: "top outlier")
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.title2.monospacedDigit())
                .foregroundStyle(DS.text)
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }
}
