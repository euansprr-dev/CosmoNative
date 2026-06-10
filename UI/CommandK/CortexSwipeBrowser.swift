// CosmoOS/UI/CommandK/CortexSwipeBrowser.swift
// Masonry thumbnail grid for swipe gallery with true aspect ratios and filters

import SwiftUI

struct CortexSwipeBrowser: View {
    var viewModel: CommandKViewModel
    @State private var hasAppeared = false
    @State private var selectedSwipeID: String?

    var body: some View {
        content
            .background(swipeBackground)
        .task {
            if viewModel.swipeGalleryItems.isEmpty { await viewModel.loadSwipeGallery() }
            if selectedSwipeID == nil {
                selectedSwipeID = visibleSwipes.first?.atomUUID
            }
            withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true }
        }
        .onChange(of: visibleSwipes.map(\.atomUUID)) { _, ids in
            if selectedSwipeID == nil || !ids.contains(selectedSwipeID ?? "") {
                selectedSwipeID = ids.first
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.swipeGalleryItems.isEmpty && !hasAppeared {
            skeletonGrid
        } else if viewModel.cachedFilteredSwipes.isEmpty {
            emptyState
        } else {
            swipeWorkbench
        }
    }

    private var visibleSwipes: [SwipeGalleryItem] {
        viewModel.cachedFilteredSwipes
    }

    private var selectedSwipe: SwipeGalleryItem? {
        if let selectedSwipeID, let item = visibleSwipes.first(where: { $0.atomUUID == selectedSwipeID }) {
            return item
        }
        return visibleSwipes.first
    }

    private var isDarkCanvas: Bool {
        DS.palette.isDark
    }

    private var swipeBackground: some View {
        Group {
            if isDarkCanvas {
                LinearGradient(
                    colors: [Color(hex: "1D1A16"), Color(hex: "11100D")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [DS.vellum.opacity(0.98), DS.vellumDeep.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var hasActiveFilters: Bool {
        viewModel.swipePlatformFilter != nil || viewModel.swipeHookTypeFilter != nil
    }

    private var platformFilterMenu: some View {
        Menu {
            Button("All Platforms") { viewModel.swipePlatformFilter = nil }
            Divider()
            ForEach(availablePlatforms, id: \.self) { platform in
                Button(platform) { viewModel.swipePlatformFilter = platform }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Text(viewModel.swipePlatformFilter ?? "Platform")
                    .font(DS.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundStyle(viewModel.swipePlatformFilter != nil ? DS.accent : DS.textSecondary)
            .commandKToolbarChip(
                isActive: viewModel.swipePlatformFilter != nil,
                activeFill: DS.accent.opacity(0.12),
                activeBorder: DS.accent.opacity(0.2)
            )
        }
        .buttonStyle(.plain)
    }

    private var hookTypeFilterMenu: some View {
        Menu {
            Button("All Hooks") { viewModel.swipeHookTypeFilter = nil }
            Divider()
            ForEach(SwipeHookType.allCases, id: \.self) { hookType in
                Button(hookType.displayName) { viewModel.swipeHookTypeFilter = hookType }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Text(viewModel.swipeHookTypeFilter?.displayName ?? "Hook Type")
                    .font(DS.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundStyle(viewModel.swipeHookTypeFilter != nil ? DS.entitySwipe : DS.textSecondary)
            .commandKToolbarChip(
                isActive: viewModel.swipeHookTypeFilter != nil,
                activeFill: DS.entitySwipe.opacity(0.12),
                activeBorder: DS.entitySwipe.opacity(0.2)
            )
        }
        .buttonStyle(.plain)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SwipeSortMode.allCases, id: \.self) { mode in
                Button(mode.displayName) { viewModel.swipeSortMode = mode }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Text(viewModel.swipeSortMode.displayName)
                    .font(DS.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
                            .foregroundStyle(Color.white.opacity(0.7))
            .commandKToolbarChip()
        }
        .buttonStyle(.plain)
    }

    private var availablePlatforms: [String] {
        Array(Set(viewModel.swipeGalleryItems.compactMap(\.platform))).sorted()
    }

    private var averageScore: Double? {
        viewModel.swipeFacetSummary.averageHookScore
    }

    // MARK: - Workbench

    private var swipeWorkbench: some View {
        HStack(spacing: 0) {
            swipeSidebar
                .frame(width: 222)

            Divider().foregroundStyle(chromeBorder)

            VStack(alignment: .leading, spacing: DS.space16) {
                narrativeBar
                swipeGrid
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().foregroundStyle(chromeBorder)

            if let selectedSwipe {
                CommandKSwipePreviewPane(
                    item: selectedSwipe,
                    isDark: isDarkCanvas,
                    onOpen: { openSwipe(selectedSwipe) }
                )
                .frame(width: 318)
            }
        }
        .frame(minHeight: 486)
    }

    private var swipeSidebar: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Text("Format")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primaryText)

            VStack(spacing: DS.space8) {
                sidebarRow(
                    title: "All",
                    icon: "rectangle.grid.1x2",
                    count: viewModel.swipeGalleryItems.count,
                    isSelected: viewModel.swipeContentFormatFilters.isEmpty
                ) {
                    viewModel.swipeContentFormatFilters = []
                }

                ForEach(viewModel.swipeFacetSummary.topContentFormats, id: \.format) { entry in
                    sidebarRow(
                        title: entry.format.displayName,
                        icon: entry.format.icon,
                        count: entry.count,
                        isSelected: viewModel.swipeContentFormatFilters.contains(entry.format)
                    ) {
                        withAnimation(ProMotionSprings.snappy) {
                            toggleContentFormat(entry.format)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space18)
    }

    private var narrativeBar: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HStack {
                Text("Narrative Style")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryText)

                Spacer()

                if let avg = averageScore {
                    Text(String(format: "%.1f", avg))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isDarkCanvas ? .white : DS.text)
                        .padding(.horizontal, DS.space8)
                        .frame(height: 26)
                        .background(DS.entitySwipe.opacity(isDarkCanvas ? 0.30 : 0.18), in: Capsule())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space8) {
                    filterPill("All", isSelected: viewModel.swipeNarrativeFilters.isEmpty) {
                        viewModel.swipeNarrativeFilters = []
                    }

                    ForEach(viewModel.swipeFacetSummary.topNarrativeStyles, id: \.style) { entry in
                        filterPill("\(entry.style.displayName)  \(entry.count)", isSelected: viewModel.swipeNarrativeFilters.contains(entry.style)) {
                            withAnimation(ProMotionSprings.snappy) {
                                toggleNarrative(entry.style)
                            }
                        }
                    }
                }
            }
        }
    }

    private var swipeGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 148, maximum: 174), spacing: DS.space12)],
                spacing: 14
            ) {
                ForEach(Array(visibleSwipes.enumerated()), id: \.element.id) { index, item in
                    CommandKSwipeMiniCard(
                        item: item,
                        isSelected: item.atomUUID == selectedSwipe?.atomUUID,
                        isDark: isDarkCanvas
                    ) {
                        withAnimation(ProMotionSprings.snappy) {
                            selectedSwipeID = item.atomUUID
                        }
                    }
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 8)
                            .animation(CommandKAnimationPolicy.entranceAnimation(index: index), value: hasAppeared)
                }
            }
            .padding(.bottom, DS.space12)
        }
    }

    private var primaryText: Color {
        isDarkCanvas ? Color.white.opacity(0.92) : DS.text
    }

    private var secondaryText: Color {
        isDarkCanvas ? Color.white.opacity(0.62) : DS.textSecondary
    }

    private var chromeBorder: Color {
        isDarkCanvas ? Color.white.opacity(0.12) : DS.glassBorder.opacity(0.68)
    }

    private func toggleContentFormat(_ format: ContentFormat) {
        if viewModel.swipeContentFormatFilters.contains(format) {
            viewModel.swipeContentFormatFilters.remove(format)
        } else {
            viewModel.swipeContentFormatFilters = [format]
        }
    }

    private func toggleNarrative(_ style: NarrativeStyle) {
        if viewModel.swipeNarrativeFilters.contains(style) {
            viewModel.swipeNarrativeFilters.remove(style)
        } else {
            viewModel.swipeNarrativeFilters = [style]
        }
    }

    private func sidebarRow(title: String, icon: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(count.formatted(.number))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? primaryText : secondaryText)
            }
            .foregroundStyle(isSelected ? primaryText : secondaryText)
            .padding(.horizontal, DS.space12)
            .frame(height: 36)
            .background(isSelected ? DS.entitySwipe.opacity(isDarkCanvas ? 0.30 : 0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func filterPill(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? (isDarkCanvas ? .white : DS.text) : secondaryText)
                .padding(.horizontal, DS.space10)
                .frame(height: 28)
                .background(isSelected ? DS.entitySwipe.opacity(isDarkCanvas ? 0.32 : 0.18) : DS.glassCardFill.opacity(isDarkCanvas ? 0.08 : 0.38), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? DS.entitySwipe.opacity(0.42) : chromeBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Skeleton

    private var skeletonGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 80, maximum: 110), spacing: DS.space8)],
            spacing: DS.space10
        ) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DS.glassCardFill.opacity(0.3))
                    .frame(height: 100)
            }
        }
        .padding(DS.space16)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 28))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("No swipes match filters")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }

    private func openSwipe(_ item: SwipeGalleryItem) {
        Task { try? await NodeGraphEngine.shared.recordAccess(atomUUID: item.atomUUID, type: .view) }
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil, userInfo: ["atomUUID": item.atomUUID]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }
}

// MARK: - Swipe Workbench Cards

private struct CommandKSwipeMiniCard: View {
    let item: SwipeGalleryItem
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: DS.space8) {
                ZStack(alignment: .topLeading) {
                    thumbnail
                    if let hookType = item.hookType {
                        Text(hookType.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(hookType.color)
                            .padding(.horizontal, DS.space6)
                            .padding(.vertical, 4)
                            .background(hookType.color.opacity(isDark ? 0.18 : 0.12), in: Capsule())
                            .padding(DS.space8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(labelText.opacity(0.86))
                        .padding(DS.space8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(labelText)
                        .lineLimit(2)
                    Text(item.platformName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(labelText.opacity(0.62))
                        .lineLimit(1)
                }
            }
            .padding(DS.space10)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? DS.entitySwipe.opacity(0.90) : borderColor, lineWidth: isSelected ? 1.2 : 0.6)
            )
            .shadow(color: Color.black.opacity(isDark ? 0.28 : 0.06), radius: isHovered ? 14 : 8, x: 0, y: isHovered ? 8 : 3)
            .scaleEffect(isHovered ? 1.008 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .commandKCardContextMenu(
            atomUUID: item.atomUUID,
            entityId: item.entityId,
            atomType: .research,
            allowsSpatialGoToObject: true,
            onDelete: {
                Task {
                    try? await SwipeFileEngine.shared.deleteSwipe(atomUUID: item.atomUUID)
                }
            }
        )
    }

    private var thumbnail: some View {
        ZStack {
            if let url = item.thumbnailUrl, let nsUrl = URL(string: url) {
                CachedAsyncImage(url: nsUrl, stableKey: item.instagramId) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView().scaleEffect(0.55).tint(labelText.opacity(0.62))
                    case .failure:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(height: 128)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [DS.entitySwipe.opacity(0.28), Color.black.opacity(isDark ? 0.46 : 0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: item.platformIcon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(labelText.opacity(0.68))
        }
    }

    private var cardFill: Color {
        isDark ? Color.white.opacity(isSelected ? 0.10 : 0.055) : DS.glassCardFill.opacity(isSelected ? 0.74 : 0.42)
    }

    private var borderColor: Color {
        isDark ? Color.white.opacity(0.16) : DS.glassBorder.opacity(0.70)
    }

    private var labelText: Color {
        isDark ? .white : DS.text
    }
}

private struct CommandKSwipePreviewPane: View {
    let item: SwipeGalleryItem
    let isDark: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: DS.space16) {
            previewImage
            actionRow
        }
        .padding(DS.space16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var previewImage: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = item.thumbnailUrl, let nsUrl = URL(string: url) {
                CachedAsyncImage(url: nsUrl, stableKey: item.instagramId) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().scaleEffect(0.7).tint(textColor.opacity(0.7))
                    case .failure:
                        previewPlaceholder
                    }
                }
            } else {
                previewPlaceholder
            }

            LinearGradient(
                colors: [Color.black.opacity(0.00), Color.black.opacity(0.62)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: DS.space8) {
                if let hookType = item.hookType {
                    Text(hookType.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hookType.color)
                        .padding(.horizontal, DS.space8)
                        .frame(height: 24)
                        .background(hookType.color.opacity(0.18), in: Capsule())
                }

                Text(item.hookText ?? item.title)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(4)

                Text([item.creatorName ?? item.author, item.platformName].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(DS.space16)
        }
        .frame(height: 286)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.18) : DS.glassBorder.opacity(0.70), lineWidth: 0.6)
        )
    }

    private var previewPlaceholder: some View {
        LinearGradient(
            colors: [DS.entitySwipe.opacity(0.34), Color.black.opacity(isDark ? 0.70 : 0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var actionRow: some View {
        HStack(spacing: DS.space10) {
            previewAction("Open", icon: "arrow.up.right.square", action: onOpen)
            previewAction("Attach", icon: "paperclip", action: {})
            previewAction("Canvas", icon: "square.grid.2x2", action: {})
        }
    }

    private func previewAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DS.space6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(isDark ? Color.white.opacity(0.08) : DS.glassCardFill.opacity(0.46), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isDark ? Color.white.opacity(0.14) : DS.glassBorder.opacity(0.64), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var textColor: Color {
        isDark ? .white : DS.text
    }
}

// MARK: - Swipe Thumbnail

struct CortexSwipeThumb: View {
    let item: SwipeGalleryItem
    var prefersDarkChrome: Bool = false
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DS.space4) {
                thumbPreview
                thumbLabel
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel(item.title)
        .commandKCardContextMenu(
            atomUUID: item.atomUUID,
            entityId: item.entityId,
            atomType: .research,
            allowsSpatialGoToObject: true,
            onDelete: {
                Task {
                    try? await SwipeFileEngine.shared.deleteSwipe(atomUUID: item.atomUUID)
                }
            }
        )
    }

    private var thumbPreview: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailImage
            scoreBadge
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isHovered ? DS.entitySwipe.opacity(0.3) : DS.border.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(
            color: .black.opacity(isHovered ? 0.08 : 0.03),
            radius: isHovered ? 8 : 4, x: 0,
            y: isHovered ? 3 : 1
        )
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        Group {
            if let url = item.thumbnailUrl, let nsUrl = URL(string: url) {
                CachedAsyncImage(url: nsUrl, stableKey: item.instagramId) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    case .empty:
                        placeholderFrame {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(DS.textMuted)
                        }
                    case .failure:
                        placeholderFrame { placeholderIcon }
                    }
                }
            } else {
                placeholderFrame { placeholderIcon }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Fallback frame with platform-derived aspect ratio, used while images load or fail.
    @ViewBuilder
    private func placeholderFrame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Color.clear
            .aspectRatio(fallbackAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(DS.glassCardFill.opacity(0.5))
            .overlay(content())
    }

    private var placeholderIcon: some View {
        Image(systemName: platformIcon)
            .font(DS.callout)
            .foregroundStyle(DS.entitySwipe)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var scoreBadge: some View {
        if let score = item.hookScore, score > 0 {
            Text(String(format: "%.0f", score))
                .font(DS.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.space4)
                .padding(.vertical, 2)
                .background(scoreColor(score), in: RoundedRectangle(cornerRadius: 3))
                .padding(3)
        }
    }

    private var placeholderView: some View {
        placeholderFrame { placeholderIcon }
    }

    private var thumbLabel: some View {
        Text(item.title)
            .font(DS.caption2)
            .foregroundStyle(prefersDarkChrome ? Color.white.opacity(0.92) : DS.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Only used as a loading/error placeholder. Real images render at their natural
    /// aspect ratio via `.aspectRatio(contentMode: .fit)`.
    private var fallbackAspectRatio: CGFloat {
        let platform = item.platform?.lowercased() ?? ""
        if platform.contains("youtube") && !platform.contains("short") { return 16.0 / 9.0 }
        if platform.contains("carousel") || (platform.contains("post") && !platform.contains("reel")) {
            return 4.0 / 5.0
        }
        if platform.contains("x") || platform.contains("twitter") || platform.contains("thread") {
            return 3.0 / 4.0
        }
        return 9.0 / 16.0
    }

    private var platformIcon: String {
        let platform = item.platform?.lowercased() ?? ""
        if platform.contains("youtube") { return "play.rectangle.fill" }
        if platform.contains("instagram") { return "camera.fill" }
        if platform.contains("tiktok") { return "music.note" }
        return "bolt.fill"
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 8.5 { return DS.green }
        if score >= 7.0 { return DS.orange }
        return DS.textMuted
    }
}
