// CosmoOS/UI/CommandK/SwipeGalleryTab.swift
// Swipe Gallery tab for Command-K overlay
// Masonry card grid matching Library design, with platform-based card sizing

import SwiftUI
import AVFoundation
import AppKit

// MARK: - SwipeGalleryTab

struct SwipeGalleryTab: View {

    @ObservedObject var viewModel: CommandKViewModel
    let searchQuery: String

    @State private var hasAppeared = false

    private let gold = DS.entitySwipe

    var body: some View {
        ZStack {
            DS.bg

            VStack(spacing: 0) {
                filterBar

                Divider().background(DS.borderActive)

                if filteredItems.isEmpty {
                    emptyState
                } else {
                    GeometryReader { geometry in
                        let columnCount = max(2, Int(geometry.size.width / (220 + 16)))
                        let totalSpacing = CGFloat(columnCount - 1) * 16 + 48
                        let cardWidth = (geometry.size.width - totalSpacing) / CGFloat(columnCount)

                        ScrollView {
                            SwipeMasonryLayout(columnCount: columnCount, spacing: 16) {
                                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                    SwipeGalleryCard(item: item, cardWidth: cardWidth, viewModel: viewModel)
                                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                        .animation(
                                            ProMotionSprings.cardEntrance.delay(Double(index % 12) * 0.03),
                                            value: filteredItems.count
                                        )
                                }
                            }
                            .padding(24)
                            .padding(.bottom, viewModel.isMultiSelectActive ? 60 : 0)
                        }
                    }
                }
            }

            // Floating selection bar
            if viewModel.isMultiSelectActive {
                VStack {
                    Spacer()
                    SelectionBar(viewModel: viewModel, accentColor: gold) {
                        batchDeleteSelectedSwipes()
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(ProMotionSprings.snappy, value: viewModel.isMultiSelectActive)
        .onAppear {
            if viewModel.swipeGalleryItems.isEmpty {
                Task { await viewModel.loadSwipeGallery() }
            }
            withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
            // Register context provider for global Cosmo window
            let provider = SwipeGalleryContextProvider(viewModel: viewModel, filteredCountRef: { [self] in self.filteredItems.count }, searchQuery: searchQuery)
            CosmoWindowViewModel.shared.updateContext(provider: provider)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("swipeDeleted"))) { notification in
            if let uuid = notification.userInfo?["uuid"] as? String {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.swipeGalleryItems.removeAll { $0.atomUUID == uuid }
                }
            }
        }
    }

    // MARK: - Batch Delete

    private func batchDeleteSelectedSwipes() {
        let uuids = Array(viewModel.selectedUUIDs)
        Task {
            for uuid in uuids {
                try? await SwipeFileEngine.shared.deleteSwipe(atomUUID: uuid)
            }
        }
        withAnimation(ProMotionSprings.snappy) {
            viewModel.swipeGalleryItems.removeAll { uuids.contains($0.atomUUID) }
            viewModel.clearSelection()
        }
    }

    // MARK: - Filtered Items

    private var filteredItems: [SwipeGalleryItem] {
        var items = viewModel.swipeGalleryItems

        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            items = items.filter { item in
                item.title.lowercased().contains(q) ||
                (item.hookText?.lowercased().contains(q) ?? false) ||
                (item.author?.lowercased().contains(q) ?? false) ||
                (item.niche?.lowercased().contains(q) ?? false) ||
                (item.creatorName?.lowercased().contains(q) ?? false)
            }
        }

        if let platformFilter = viewModel.swipePlatformFilter {
            items = items.filter { $0.platformName == platformFilter }
        }

        if let hookFilter = viewModel.swipeHookTypeFilter {
            items = items.filter { $0.hookType == hookFilter }
        }

        if !viewModel.swipeNarrativeFilters.isEmpty {
            items = items.filter { item in
                guard let narrative = item.primaryNarrative else { return false }
                return viewModel.swipeNarrativeFilters.contains(narrative)
            }
        }

        if !viewModel.swipeContentFormatFilters.isEmpty {
            items = items.filter { item in
                guard let format = item.swipeContentFormat else { return false }
                return viewModel.swipeContentFormatFilters.contains(format)
            }
        }

        if let nicheFilter = viewModel.swipeNicheFilter {
            items = items.filter { $0.niche == nicheFilter }
        }

        if let creatorFilter = viewModel.swipeCreatorFilter {
            items = items.filter { $0.creatorName == creatorFilter }
        }

        switch viewModel.swipeSortMode {
        case .score:
            items.sort { ($0.hookScore ?? 0) > ($1.hookScore ?? 0) }
        case .recent:
            items.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            items.sort { $0.createdAt < $1.createdAt }
        }

        return items
    }

    // MARK: - Filter Bar (Library style)

    private var filterBar: some View {
        HStack(spacing: 12) {
            statsLabel

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    platformMenu
                    hookTypeMenu
                    narrativeMenu
                    formatMenu

                    if !viewModel.availableNiches.isEmpty {
                        nicheMenu
                    }
                    if !viewModel.availableCreators.isEmpty {
                        creatorMenu
                    }

                    filterSeparator

                    sortMenu

                    if hasActiveFilters {
                        clearButton
                    }
                }
            }

            creatorsButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var filterSeparator: some View {
        Rectangle()
            .fill(DS.borderActive)
            .frame(width: 1, height: 20)
    }

    // MARK: - Stats Label

    private var statsLabel: some View {
        HStack(spacing: 6) {
            Text("\(viewModel.swipeGalleryItems.count)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundColor(DS.text)
            Text("swipes")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textSecondary)

            if let avg = averageHookScore {
                Rectangle().fill(DS.borderActive).frame(width: 1, height: 16)
                Text(String(format: "%.1f", avg))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundColor(averageScoreColor)
                Text("avg")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
            }
        }
    }

    private var averageHookScore: Double? {
        let scores = viewModel.swipeGalleryItems.compactMap(\.hookScore)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private var averageScoreColor: Color {
        guard let score = averageHookScore else { return Color(hex: "#64748B") }
        if score >= 8.0 { return Color(hex: "#10B981") }
        if score >= 5.0 { return Color(hex: "#3B82F6") }
        return Color(hex: "#64748B")
    }

    // MARK: - Dropdown Helper

    @ViewBuilder
    private func filterDropdownLabel(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
        }
        .foregroundColor(isActive ? DS.text : DS.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? gold.opacity(0.15) : DS.surfaceElevated)
        )
    }

    // MARK: - Platform Menu

    private var platformMenu: some View {
        Menu {
            Button {
                viewModel.swipePlatformFilter = nil
            } label: {
                HStack {
                    Text("All Platforms")
                    if viewModel.swipePlatformFilter == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(["YouTube", "Instagram", "X", "Threads", "Website"], id: \.self) { platform in
                Button {
                    viewModel.swipePlatformFilter = viewModel.swipePlatformFilter == platform ? nil : platform
                } label: {
                    HStack {
                        Text(platform)
                        if viewModel.swipePlatformFilter == platform {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterDropdownLabel(
                viewModel.swipePlatformFilter ?? "Platform",
                isActive: viewModel.swipePlatformFilter != nil
            )
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    // MARK: - Hook Type Menu

    private var hookTypeMenu: some View {
        Menu {
            Button {
                viewModel.swipeHookTypeFilter = nil
            } label: {
                HStack {
                    Text("All Hook Types")
                    if viewModel.swipeHookTypeFilter == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(SwipeHookType.allCases, id: \.rawValue) { hookType in
                Button {
                    viewModel.swipeHookTypeFilter = viewModel.swipeHookTypeFilter == hookType ? nil : hookType
                } label: {
                    HStack {
                        Text(hookType.displayName)
                        if viewModel.swipeHookTypeFilter == hookType {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterDropdownLabel(
                viewModel.swipeHookTypeFilter?.displayName ?? "Hook Type",
                isActive: viewModel.swipeHookTypeFilter != nil
            )
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    // MARK: - Narrative Menu (multi-select)

    private var narrativeMenu: some View {
        Menu {
            Button {
                viewModel.swipeNarrativeFilters.removeAll()
            } label: {
                HStack {
                    Text("All Narratives")
                    if viewModel.swipeNarrativeFilters.isEmpty { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(NarrativeStyle.allCases, id: \.rawValue) { style in
                Button {
                    if viewModel.swipeNarrativeFilters.contains(style) {
                        viewModel.swipeNarrativeFilters.remove(style)
                    } else {
                        viewModel.swipeNarrativeFilters.insert(style)
                    }
                } label: {
                    narrativeMenuItemLabel(style)
                }
            }
        } label: {
            narrativeDropdownLabel
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    @ViewBuilder
    private func narrativeMenuItemLabel(_ style: NarrativeStyle) -> some View {
        HStack {
            Image(systemName: style.icon)
            Text(style.displayName)
            if viewModel.swipeNarrativeFilters.contains(style) {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var narrativeDropdownLabel: some View {
        let active = !viewModel.swipeNarrativeFilters.isEmpty
        let title = active
            ? "\(viewModel.swipeNarrativeFilters.count) Narrative\(viewModel.swipeNarrativeFilters.count > 1 ? "s" : "")"
            : "Narrative"
        return filterDropdownLabel(title, isActive: active)
    }

    // MARK: - Format Menu (multi-select)

    private var formatMenu: some View {
        Menu {
            Button {
                viewModel.swipeContentFormatFilters.removeAll()
            } label: {
                HStack {
                    Text("All Formats")
                    if viewModel.swipeContentFormatFilters.isEmpty { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(ContentFormat.allCases, id: \.rawValue) { format in
                Button {
                    if viewModel.swipeContentFormatFilters.contains(format) {
                        viewModel.swipeContentFormatFilters.remove(format)
                    } else {
                        viewModel.swipeContentFormatFilters.insert(format)
                    }
                } label: {
                    formatMenuItemLabel(format)
                }
            }
        } label: {
            formatDropdownLabel
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    @ViewBuilder
    private func formatMenuItemLabel(_ format: ContentFormat) -> some View {
        HStack {
            Image(systemName: format.icon)
            Text(format.displayName)
            if viewModel.swipeContentFormatFilters.contains(format) {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var formatDropdownLabel: some View {
        let active = !viewModel.swipeContentFormatFilters.isEmpty
        let title = active
            ? "\(viewModel.swipeContentFormatFilters.count) Format\(viewModel.swipeContentFormatFilters.count > 1 ? "s" : "")"
            : "Format"
        return filterDropdownLabel(title, isActive: active)
    }

    // MARK: - Niche Menu

    private var nicheMenu: some View {
        Menu {
            Button {
                viewModel.swipeNicheFilter = nil
            } label: {
                HStack {
                    Text("All Niches")
                    if viewModel.swipeNicheFilter == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(viewModel.availableNiches, id: \.self) { niche in
                Button {
                    viewModel.swipeNicheFilter = viewModel.swipeNicheFilter == niche ? nil : niche
                } label: {
                    HStack {
                        Text(niche)
                        if viewModel.swipeNicheFilter == niche {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterDropdownLabel(
                viewModel.swipeNicheFilter ?? "Niche",
                isActive: viewModel.swipeNicheFilter != nil
            )
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    // MARK: - Creator Menu

    private var creatorMenu: some View {
        Menu {
            Button {
                viewModel.swipeCreatorFilter = nil
            } label: {
                HStack {
                    Text("All Creators")
                    if viewModel.swipeCreatorFilter == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(viewModel.availableCreators, id: \.name) { creator in
                Button {
                    viewModel.swipeCreatorFilter = viewModel.swipeCreatorFilter == creator.name ? nil : creator.name
                } label: {
                    HStack {
                        Text(creator.name)
                        if viewModel.swipeCreatorFilter == creator.name {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterDropdownLabel(
                viewModel.swipeCreatorFilter ?? "Creator",
                isActive: viewModel.swipeCreatorFilter != nil
            )
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(SwipeSortMode.allCases, id: \.self) { mode in
                Button {
                    viewModel.swipeSortMode = mode
                } label: {
                    HStack {
                        Text(mode.displayName)
                        if viewModel.swipeSortMode == mode {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.swipeSortMode.displayName)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(DS.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.surfaceElevated)
            )
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    // MARK: - Active Filters

    private var hasActiveFilters: Bool {
        viewModel.swipePlatformFilter != nil ||
        viewModel.swipeHookTypeFilter != nil ||
        !viewModel.swipeNarrativeFilters.isEmpty ||
        !viewModel.swipeContentFormatFilters.isEmpty ||
        viewModel.swipeNicheFilter != nil ||
        viewModel.swipeCreatorFilter != nil
    }

    private var clearButton: some View {
        Button {
            viewModel.swipePlatformFilter = nil
            viewModel.swipeHookTypeFilter = nil
            viewModel.swipeNarrativeFilters.removeAll()
            viewModel.swipeContentFormatFilters.removeAll()
            viewModel.swipeNicheFilter = nil
            viewModel.swipeCreatorFilter = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                Text("Clear")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(gold.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(gold.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Creators Button

    private var creatorsButton: some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("openCreatorDatabase"),
                object: nil
            )
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.closeCommandK,
                object: nil
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.crop.rectangle.fill")
                    .font(.system(size: 10))
                Text("Creators")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(gold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(gold.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(gold.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 48))
                .foregroundColor(gold.opacity(0.3))

            Text("No swipes yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DS.textSecondary)

            Text("Press \u{2318}\u{21E7}S to capture your first swipe")
                .font(.system(size: 14))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Masonry Layout (Pinterest-style waterfall)

private struct SwipeMasonryLayout: Layout {
    let columnCount: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        let columnWidth = (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        for subview in subviews {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            columnHeights[shortestColumn] += size.height + spacing
        }

        let maxHeight = columnHeights.max() ?? 0
        return CGSize(width: width, height: max(0, maxHeight - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = (bounds.width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        for subview in subviews {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let x = bounds.minX + CGFloat(shortestColumn) * (columnWidth + spacing)
            let y = bounds.minY + columnHeights[shortestColumn]

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: nil)
            )

            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            columnHeights[shortestColumn] += size.height + spacing
        }
    }
}

// MARK: - SwipeGalleryCard

private struct SwipeGalleryCard: View {

    let item: SwipeGalleryItem
    let cardWidth: CGFloat
    var viewModel: CommandKViewModel?

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var showDeleteAlert = false
    @State private var localThumbnail: NSImage?

    private var isSelected: Bool {
        viewModel?.selectedUUIDs.contains(item.atomUUID) ?? false
    }

    /// Whether this item has any displayable thumbnail (remote URL or local video fallback)
    private var hasThumbnail: Bool {
        item.thumbnailUrl != nil || localThumbnail != nil || item.instagramId != nil
    }

    /// Whether this is an Instagram reel
    private var isReel: Bool {
        switch item.platform {
        case "instagramReel", "instagram_reel", "instagram":
            return true
        default:
            return false
        }
    }

    /// Whether this is an Instagram carousel
    private var isCarousel: Bool {
        switch item.platform {
        case "instagramCarousel", "instagram_carousel":
            return true
        default:
            return false
        }
    }

    // MARK: - Platform-Based Preview Height

    /// Height of the info section below the preview (title + subtitle + badge + padding)
    private let infoSectionHeight: CGFloat = 90

    private var previewHeight: CGFloat {
        if hasThumbnail {
            switch item.platform {
            case "youtube":
                return cardWidth * 9 / 16                     // 16:9 landscape
            case "youtubeShort", "youtube_short":
                return min(cardWidth * 16 / 9, 420)           // 9:16 portrait
            case "instagramReel", "instagram_reel":
                return min(cardWidth * 16 / 9, 420)           // 9:16 portrait
            case "instagramCarousel", "instagram_carousel":
                return cardWidth * 5 / 4                      // 4:5 (native IG carousel)
            case "instagramPost", "instagram_post":
                return cardWidth * 5 / 4                      // 4:5 (native IG post)
            case "instagram":
                return cardWidth * 5 / 4                      // 4:5 (generic IG fallback)
            default:
                return cardWidth * 9 / 16                     // default landscape
            }
        } else {
            // No thumbnail — compact text card
            return 80
        }
    }

    /// Total card height — fixed to prevent masonry layout miscalculation from async image loading
    private var totalCardHeight: CGFloat {
        previewHeight + infoSectionHeight
    }

    /// Platform-specific accent color for the preview gradient
    private var platformAccentColor: Color {
        switch item.platform {
        case "youtube", "youtubeShort", "youtube_short":
            return Color(hex: "#FF4444")
        case "instagram", "instagramReel", "instagramPost", "instagramCarousel",
             "instagram_reel", "instagram_post", "instagram_carousel":
            return Color(hex: "#C13584")
        case "xPost", "twitter", "x_post":
            return Color(hex: "#1DA1F2")
        case "threads":
            return Color(hex: "#AAAAAA")
        case "website":
            return Color(hex: "#8FC7A2")
        default:
            return Color(hex: "#8FC7A2")
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preview area — platform-based height
            previewArea
                .frame(height: previewHeight)
                .clipped()

            // Info area — matches Library card structure
            VStack(alignment: .leading, spacing: 6) {
                // Title (hook text)
                Text(item.hookText ?? item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(2)

                // Subtitle (author + platform)
                subtitleLabel

                // Bottom row: hook type badge + date
                bottomRowLabel
            }
            .padding(12)
        }
        .frame(height: totalCardHeight)
        .clipped()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .cardSelectionOverlay(isSelected: isSelected, accentColor: DS.entitySwipe)
        .shadow(
            color: .black.opacity(isHovered ? 0.4 : 0.2),
            radius: isHovered ? 16 : 8,
            y: isHovered ? 8 : 4
        )
        .scaleEffect(isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .animation(ProMotionSprings.press, value: isPressed)
        .onHover { hovering in isHovered = hovering }
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.shift) {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel?.toggleSelection(item.atomUUID)
                }
            } else if viewModel?.isMultiSelectActive == true {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel?.clearSelection()
                }
            } else {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": EntityType.research, "id": item.entityId, "commandKTab": "swipeGallery"]
                )
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.closeCommandK,
                    object: nil
                )
            }
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            isPressed = pressing
        }) {
            NotificationCenter.default.post(
                name: Notification.Name("addSwipeToCanvas"),
                object: nil,
                userInfo: ["atomUUID": item.atomUUID]
            )
        }
        .contextMenu { swipeCardContextMenu }
        .alert(swipeDeleteAlertTitle, isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                batchDeleteSwipes()
            }
        } message: {
            Text(swipeDeleteAlertMessage)
        }
        .onAppear {
            // Pre-generate local thumbnail for Instagram items without a remote URL
            if item.thumbnailUrl == nil && item.instagramId != nil {
                generateLocalThumbnail()
            }
        }
    }

    // MARK: - Preview Area

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            // Gradient background (Library-style, using platform accent)
            LinearGradient(
                colors: [platformAccentColor.opacity(0.15), platformAccentColor.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            previewContent

            // Overlay badges
            VStack {
                HStack(alignment: .top) {
                    // Platform badge (top-left)
                    HStack(spacing: 4) {
                        Image(systemName: item.platformIcon)
                            .font(.system(size: 9))
                        Text(item.platformName)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(DS.text)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DS.bg.opacity(0.75)))

                    Spacer()

                    // Score badge (top-right)
                    if let score = item.hookScore {
                        Text(String(format: "%.1f", score))
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundColor(.white) // White on accent bg — exception
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(item.scoreColor.opacity(0.85)))
                    }
                }

                Spacer()

                // Duration badge (bottom-right)
                if let duration = item.duration, duration > 0 {
                    HStack {
                        Spacer()
                        Text(formatDuration(duration))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundColor(DS.text)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(DS.bg.opacity(0.75)))
                    }
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let localThumb = localThumbnail {
            // Local thumbnail generated from cached video
            Image(nsImage: localThumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)
                .clipped()
        } else if let thumbnailUrl = item.thumbnailUrl, let url = URL(string: thumbnailUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: previewHeight)
                        .clipped()
                case .failure:
                    fallbackPreview
                        .onAppear { generateLocalThumbnail() }
                case .empty:
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(DS.textMuted)
                @unknown default:
                    fallbackPreview
                        .onAppear { generateLocalThumbnail() }
                }
            }
        } else {
            fallbackPreview
                .onAppear { generateLocalThumbnail() }
        }
    }

    @ViewBuilder
    private var fallbackPreview: some View {
        VStack(spacing: 8) {
            if let hookText = item.hookText, !hookText.isEmpty {
                // Text preview (like Library's idea card)
                Text(hookText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Image(systemName: item.platformIcon)
                    .font(.system(size: 32))
                    .foregroundColor(platformAccentColor.opacity(0.5))
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Subtitle

    @ViewBuilder
    private var subtitleLabel: some View {
        let parts = [item.author, item.platformName].compactMap { $0 }.filter { !$0.isEmpty }

        if !parts.isEmpty {
            Text(parts.joined(separator: " \u{00B7} "))
                .font(.system(size: 12))
                .foregroundColor(DS.textMuted)
                .lineLimit(1)
        }
    }

    // MARK: - Bottom Row

    @ViewBuilder
    private var bottomRowLabel: some View {
        HStack {
            if let hookType = item.hookType {
                hookTypeBadgeLabel(hookType)
            } else {
                // Pending badge for unanalyzed swipes
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("Pending")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(Color(hex: "#64748B"))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: "#64748B").opacity(0.12))
                .clipShape(Capsule())
            }

            Spacer()

            Text(relativeDate)
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
        }
    }

    @ViewBuilder
    private func hookTypeBadgeLabel(_ hookType: SwipeHookType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: hookType.iconName)
                .font(.system(size: 10))
            Text(hookType.displayName)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(hookType.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(hookType.color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Selection-Aware Context Menu

    @ViewBuilder
    private var swipeCardContextMenu: some View {
        let selCount = viewModel?.selectedUUIDs.count ?? 0

        if isSelected && selCount > 1 {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete \(selCount) Swipes", systemImage: "trash")
            }
        } else {
            Button {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": EntityType.research, "id": item.entityId, "commandKTab": "swipeGallery"]
                )
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.closeCommandK,
                    object: nil
                )
            } label: {
                Label("Open in Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Button {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openAsPane, object: nil,
                    userInfo: ["type": EntityType.research, "id": item.entityId]
                )
                NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            } label: {
                Label("Open as Pane", systemImage: "rectangle.split.2x1")
            }

            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("addSwipeToCanvas"),
                    object: nil,
                    userInfo: ["atomUUID": item.atomUUID]
                )
            } label: {
                Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete Swipe", systemImage: "trash")
            }
        }
    }

    private var swipeDeleteAlertTitle: String {
        let selCount = viewModel?.selectedUUIDs.count ?? 0
        if isSelected && selCount > 1 {
            return "Delete \(selCount) Swipes?"
        }
        return "Delete Swipe?"
    }

    private var swipeDeleteAlertMessage: String {
        let selCount = viewModel?.selectedUUIDs.count ?? 0
        if isSelected && selCount > 1 {
            return "This will permanently remove \(selCount) swipe files."
        }
        return "This will permanently remove this swipe file."
    }

    private func batchDeleteSwipes() {
        let uuidsToDelete: [String]
        if isSelected, let vm = viewModel, vm.selectedUUIDs.count > 1 {
            uuidsToDelete = Array(vm.selectedUUIDs)
        } else {
            uuidsToDelete = [item.atomUUID]
        }

        Task {
            for uuid in uuidsToDelete {
                try? await SwipeFileEngine.shared.deleteSwipe(atomUUID: uuid)
            }
        }

        withAnimation(ProMotionSprings.snappy) {
            viewModel?.clearSelection()
        }
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        ZStack {
            DS.surfaceElevated
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHovered ? DS.borderActive : DS.border,
                    lineWidth: 1
                )
        }
    }

    // MARK: - Helpers

    private var relativeDate: String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = isoFormatter.date(from: item.createdAt)
                ?? ISO8601DateFormatter().date(from: item.createdAt) else {
            return item.createdAt
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Local Thumbnail Generation

    /// Try to generate a thumbnail from the local Instagram video cache
    private func generateLocalThumbnail() {
        guard localThumbnail == nil,
              let shortcode = item.instagramId, !shortcode.isEmpty else { return }

        Task.detached(priority: .utility) {
            if let image = await Self.thumbnailFromCache(shortcode: shortcode) {
                await MainActor.run { localThumbnail = image }
                return
            }
            // No cached thumb and no video — try re-extracting from Instagram
            // (fetches fresh CDN URLs and caches the first carousel/thumbnail image)
            if let image = await Self.extractAndCacheThumbnail(shortcode: shortcode) {
                await MainActor.run { localThumbnail = image }
            }
        }
    }

    /// Check disk cache, then try generating from cached video
    private static func thumbnailFromCache(shortcode: String) async -> NSImage? {
        let thumbCache = thumbnailCacheDir()
        let thumbPath = thumbCache.appendingPathComponent("thumb-\(shortcode).jpg")
        if FileManager.default.fileExists(atPath: thumbPath.path),
           let cached = NSImage(contentsOf: thumbPath) {
            return cached
        }

        // Try generating from cached video file
        guard let videoURL = InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) else {
            return nil
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try? FileManager.default.createDirectory(at: thumbCache, withIntermediateDirectories: true)
                try? jpegData.write(to: thumbPath)
            }

            return image
        } catch {
            return nil
        }
    }

    /// Re-extract media from Instagram to get fresh URLs, download first image, cache it
    private static func extractAndCacheThumbnail(shortcode: String) async -> NSImage? {
        let igURL = URL(string: "https://www.instagram.com/p/\(shortcode)/")!

        do {
            let mediaData = try await InstagramMediaCache.shared.getMedia(for: igURL)

            // Try carousel first image, then thumbnail
            let imageURL: URL?
            if let items = mediaData.carouselItems, !items.isEmpty,
               let first = items.first(where: { $0.mediaType == .image }) ?? items.first {
                imageURL = first.mediaURL
            } else {
                imageURL = mediaData.thumbnailURL
            }

            guard let downloadURL = imageURL else { return nil }
            let (data, _) = try await URLSession.shared.data(from: downloadURL)
            guard let nsImage = NSImage(data: data) else { return nil }

            // Cache to disk
            let thumbCache = thumbnailCacheDir()
            let thumbPath = thumbCache.appendingPathComponent("thumb-\(shortcode).jpg")
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try? FileManager.default.createDirectory(at: thumbCache, withIntermediateDirectories: true)
                try? jpegData.write(to: thumbPath)
            }

            return nsImage
        } catch {
            return nil
        }
    }

    private static func thumbnailCacheDir() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo/ThumbnailCache", isDirectory: true)
    }
}

// MARK: - Cosmo Context Provider

@MainActor
class SwipeGalleryContextProvider: CosmoContextProvider {
    private weak var viewModel: CommandKViewModel?
    private let filteredCountRef: () -> Int
    private let searchQuery: String

    init(viewModel: CommandKViewModel, filteredCountRef: @escaping () -> Int, searchQuery: String) {
        self.viewModel = viewModel
        self.filteredCountRef = filteredCountRef
        self.searchQuery = searchQuery
    }

    var contextType: CosmoContextType { .swipeGallery }

    var contextSummary: String {
        let total = viewModel?.swipeGalleryItems.count ?? 0
        let filtered = filteredCountRef()
        let sortLabel = viewModel?.swipeSortMode.rawValue ?? "recent"
        if filtered == total {
            return "\(total) swipes, sorted by \(sortLabel)"
        }
        return "\(filtered)/\(total) swipes (filtered), sorted by \(sortLabel)"
    }

    var contextData: CosmoContextData {
        var filters: [String] = []
        if let platform = viewModel?.swipePlatformFilter {
            filters.append("platform: \(platform)")
        }
        if let hookType = viewModel?.swipeHookTypeFilter {
            filters.append("hookType: \(hookType.rawValue)")
        }
        if let niche = viewModel?.swipeNicheFilter {
            filters.append("niche: \(niche)")
        }
        if let creator = viewModel?.swipeCreatorFilter {
            filters.append("creator: \(creator)")
        }

        return CosmoContextData(
            viewSpecificData: [
                "totalSwipes": "\(viewModel?.swipeGalleryItems.count ?? 0)",
                "sortMode": viewModel?.swipeSortMode.rawValue ?? "recent"
            ],
            visibleItemCount: filteredCountRef(),
            activeFilters: filters.isEmpty ? nil : filters
        )
    }

    var availableActions: [CosmoWindowAction] { [] }
}

// MARK: - Preview

#Preview("Swipe Gallery Tab") {
    SwipeGalleryTab(viewModel: CommandKViewModel(), searchQuery: "")
        .frame(width: 900, height: 600)
}
