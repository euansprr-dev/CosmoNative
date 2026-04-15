// CosmoOS/UI/CommandK/CortexSwipeBrowser.swift
// Masonry thumbnail grid for swipe gallery with true aspect ratios and filters

import SwiftUI

struct CortexSwipeBrowser: View {
    @ObservedObject var viewModel: CommandKViewModel
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().foregroundStyle(DS.border.opacity(0.2))
            content
        }
        .task {
            if viewModel.swipeGalleryItems.isEmpty { await viewModel.loadSwipeGallery() }
            withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.swipeGalleryItems.isEmpty && !hasAppeared {
            skeletonGrid
        } else if viewModel.cachedFilteredSwipes.isEmpty {
            emptyState
        } else {
            thumbnailGrid
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space8) {
                Text("\(viewModel.cachedFilteredSwipes.count) swipes")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)

                if let avg = averageScore {
                    Text(String(format: "%.1f", avg))
                        .font(DS.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, DS.space6)
                        .padding(.vertical, 2)
                        .background(DS.accent.opacity(0.12), in: Capsule())
                }

                // Platform filter
                platformFilterMenu

                // Hook Type filter
                hookTypeFilterMenu

                // Sort
                sortMenu

                // Clear filters
                if hasActiveFilters {
                    Button("Clear") {
                        viewModel.swipePlatformFilter = nil
                        viewModel.swipeHookTypeFilter = nil
                    }
                    .font(DS.caption)
                    .foregroundStyle(DS.red)
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, DS.space16)
        }
        .frame(height: 32)
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
            .foregroundStyle(DS.textSecondary)
            .commandKToolbarChip()
        }
        .buttonStyle(.plain)
    }

    private var availablePlatforms: [String] {
        Array(Set(viewModel.swipeGalleryItems.compactMap(\.platform))).sorted()
    }

    private var averageScore: Double? {
        let scored = viewModel.cachedFilteredSwipes.compactMap(\.hookScore)
        guard !scored.isEmpty else { return nil }
        return scored.reduce(0, +) / Double(scored.count)
    }

    // MARK: - Masonry Grid

    private var thumbnailGrid: some View {
        ScrollView {
            CortexMasonryLayout(columns: 5, spacing: 8) {
                ForEach(Array(viewModel.cachedFilteredSwipes.enumerated()), id: \.element.id) { index, item in
                    CortexSwipeThumb(item: item) { openSwipe(item) }
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 8)
                        .animation(
                            ProMotionSprings.staggered(index: index),
                            value: hasAppeared
                        )
                }
            }
            .padding(DS.space16)
        }
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

// MARK: - Swipe Thumbnail

private struct CortexSwipeThumb: View {
    let item: SwipeGalleryItem
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
            onDelete: {
                Task {
                    try? await AtomRepository.shared.delete(uuid: item.atomUUID)
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
        if let url = item.thumbnailUrl, let nsUrl = URL(string: url) {
            CachedAsyncImage(url: nsUrl, stableKey: item.instagramId) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .empty:
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(DS.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.glassCardFill.opacity(0.5))
                case .failure:
                    placeholderView
                }
            }
            .frame(maxHeight: thumbMaxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            placeholderView
                .frame(height: thumbMaxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
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
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DS.glassCardFill.opacity(0.5))
            Image(systemName: platformIcon)
                .font(DS.callout)
                .foregroundStyle(DS.entitySwipe)
                .accessibilityHidden(true)
        }
    }

    private var thumbLabel: some View {
        Text(item.title)
            .font(DS.caption2)
            .foregroundStyle(DS.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Platform-aware max height for thumbnails
    private var thumbMaxHeight: CGFloat {
        let platform = item.platform?.lowercased() ?? ""
        if platform.contains("youtube") && !platform.contains("short") { return 55 }
        if platform.contains("carousel") || platform.contains("post") { return 110 }
        return 140  // Reels, shorts, TikTok — portrait
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
