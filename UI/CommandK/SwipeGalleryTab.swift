// CosmoOS/UI/CommandK/SwipeGalleryTab.swift
// Swipe Gallery tab for Command-K overlay
// Masonry card grid matching Library design, with platform-based card sizing

import SwiftUI
import AVFoundation
import AppKit

// MARK: - SwipeGalleryTab

struct SwipeGalleryTab: View {

    var viewModel: CommandKViewModel
    let searchQuery: String

    @State private var hasAppeared = false
    @State private var cachedAvgHookScore: Double?

    private let gold = DS.entitySwipe

    var body: some View {
        ZStack {
            DS.surface

            VStack(spacing: 0) {
                filterBar

                Divider().background(DS.borderSubtle)

                let items = viewModel.cachedFilteredSwipes
                if items.isEmpty {
                    emptyState
                } else {
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let columnCount = max(2, Int(width / (236 + CommandKMetrics.cardSpacing)))
                        let totalSpacing = CGFloat(columnCount - 1) * CommandKMetrics.cardSpacing + (CommandKMetrics.contentPadding * 2)
                        let cardWidth = (width - totalSpacing) / CGFloat(columnCount)

                        let isSearching = !searchQuery.isEmpty
                        let effectiveMode: SwipeViewMode = isSearching ? .flat : viewModel.swipeViewMode

                        if effectiveMode == .clustered {
                            clusteredScrollView(columnCount: columnCount, cardWidth: cardWidth)
                        } else {
                            flatLazyMasonryView(items: items, columnCount: columnCount, cardWidth: cardWidth)
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
        .onChange(of: searchQuery) { newValue in
            viewModel.swipeSearchQuery = newValue
        }
        .onAppear {
            viewModel.swipeSearchQuery = searchQuery
            if viewModel.swipeGalleryItems.isEmpty {
                Task { await viewModel.loadSwipeGallery() }
            }
            recomputeAvgHookScore()
            withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
            // Register context provider for global Cosmo window
            let provider = SwipeGalleryContextProvider(viewModel: viewModel, filteredCountRef: { [self] in viewModel.cachedFilteredSwipes.count }, searchQuery: searchQuery)
            CosmoWindowViewModel.shared.updateContext(provider: provider)
        }
        .onChange(of: viewModel.swipeGalleryItems.count) {
            recomputeAvgHookScore()
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

    // MARK: - Flat Lazy Masonry View (Performance Fix)

    @ViewBuilder
    private func flatLazyMasonryView(items: [SwipeGalleryItem], columnCount: Int, cardWidth: CGFloat) -> some View {
        let allColumns = Self.distributeColumns(columnCount: columnCount, items: items, cardWidth: cardWidth)
        ScrollView {
            HStack(alignment: .top, spacing: CommandKMetrics.cardSpacing) {
                ForEach(0..<columnCount, id: \.self) { columnIndex in
                    LazyVStack(spacing: CommandKMetrics.cardSpacing) {
                        let colItems = columnIndex < allColumns.count ? allColumns[columnIndex] : []
                        ForEach(colItems, id: \.id) { item in
                            SwipeGalleryCard(item: item, cardWidth: cardWidth, viewModel: viewModel)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .frame(width: cardWidth)
                }
            }
            .padding(CommandKMetrics.contentPadding)
            .padding(.bottom, viewModel.isMultiSelectActive ? 60 : 0)
        }
    }

    /// Distribute items across all columns by estimated height (masonry pattern) — computed once
    private static func distributeColumns(columnCount: Int, items: [SwipeGalleryItem], cardWidth: CGFloat) -> [[SwipeGalleryItem]] {
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)
        var columns: [[SwipeGalleryItem]] = Array(repeating: [], count: columnCount)

        for item in items {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[shortestColumn].append(item)
            columnHeights[shortestColumn] += SwipeGalleryCard.estimatedHeight(for: item, cardWidth: cardWidth) + CommandKMetrics.cardSpacing
        }

        return columns
    }

    // MARK: - Clustered Scroll View

    @ViewBuilder
    private func clusteredScrollView(columnCount: Int, cardWidth: CGFloat) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(viewModel.cachedClusteredSections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        formatSectionHeader(section)

                        if viewModel.expandedFormatGroups.contains(section.id) {
                            ForEach(section.clusters) { cluster in
                                clusterRow(cluster, columnCount: columnCount, cardWidth: cardWidth)
                            }
                        }
                    }
                    .padding(16)
                    .commandKSectionChrome()
                }
            }
            .padding(CommandKMetrics.contentPadding)
            .padding(.bottom, viewModel.isMultiSelectActive ? 60 : 0)
        }
    }

    // MARK: - Format Section Header (Layer 1)

    @ViewBuilder
    private func formatSectionHeader(_ section: FormatSection) -> some View {
        let isExpanded = viewModel.expandedFormatGroups.contains(section.id)

        Button {
            withAnimation(ProMotionSprings.snappy) {
                if isExpanded {
                    viewModel.expandedFormatGroups.remove(section.id)
                } else {
                    viewModel.expandedFormatGroups.insert(section.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.formatGroup.icon)
                    .font(.system(size: 14))
                    .foregroundColor(section.formatGroup.color)

                Text(section.formatGroup.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.text)

                Text("\(section.totalItemCount)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(section.formatGroup.color)
                    .commandKToolbarChip(
                        isActive: true,
                        activeFill: section.formatGroup.color.opacity(0.10),
                        activeBorder: section.formatGroup.color.opacity(0.18),
                        cornerRadius: 8
                    )

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textMuted)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cluster Row (Layer 2)

    @ViewBuilder
    private func clusterRow(_ cluster: SwipeCluster, columnCount: Int, cardWidth: CGFloat) -> some View {
        let isExpanded = viewModel.expandedClusters.contains(cluster.id)

        VStack(alignment: .leading, spacing: 10) {
            // Cluster header
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    if isExpanded {
                        viewModel.expandedClusters.remove(cluster.id)
                    } else {
                        viewModel.expandedClusters.insert(cluster.id)
                    }
                }
            } label: {
                clusterHeaderLabel(cluster, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Expanded: show all cards in lazy masonry
                flatLazyMasonryView(items: cluster.items, columnCount: columnCount, cardWidth: cardWidth)
                    .frame(height: estimateClusterHeight(cluster, columnCount: columnCount, cardWidth: cardWidth))
            } else {
                // Collapsed: thumbnail preview strip
                clusterPreviewStrip(cluster)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func clusterHeaderLabel(_ cluster: SwipeCluster, isExpanded: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: cluster.narrativeIcon)
                .font(.system(size: 12))
                .foregroundColor(cluster.narrativeColor)

            Text(cluster.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.text)

            Text("\(cluster.itemCount)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(DS.textMuted)

            Spacer()

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    // MARK: - Cluster Preview Strip (Collapsed)

    @ViewBuilder
    private func clusterPreviewStrip(_ cluster: SwipeCluster) -> some View {
        let previewItems = Array(cluster.items.prefix(4))
        let thumbSize: CGFloat = 72

        HStack(spacing: 8) {
            ForEach(previewItems, id: \.id) { item in
                SwipeThumbnailMini(item: item, size: thumbSize)
            }

            if cluster.items.count > 4 {
                Text("+\(cluster.items.count - 4)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundColor(DS.textSecondary)
                    .frame(width: thumbSize, height: thumbSize)
                    .background(DS.glassCardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.glassBorder, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 2)
    }

    /// Estimate total height for an expanded cluster to size the embedded scroll view
    private func estimateClusterHeight(_ cluster: SwipeCluster, columnCount: Int, cardWidth: CGFloat) -> CGFloat {
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)
        for item in cluster.items {
            let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columnHeights[shortest] += SwipeGalleryCard.estimatedHeight(for: item, cardWidth: cardWidth) + CommandKMetrics.cardSpacing
        }
        return (columnHeights.max() ?? 200) + 48
    }

    // MARK: - Filter Bar (Library style)

    private var filterBar: some View {
        HStack(spacing: CommandKMetrics.toolbarSpacing) {
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

                    viewModeToggle

                    sortMenu

                    if hasActiveFilters {
                        clearButton
                    }
                }
            }

            creatorsButton
        }
        .padding(.horizontal, CommandKMetrics.contentPadding)
        .padding(.vertical, 12)
    }

    private var filterSeparator: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(width: 1, height: 22)
    }

    private var viewModeToggle: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.swipeViewMode = viewModel.swipeViewMode == .clustered ? .flat : .clustered
            }
        } label: {
            Image(systemName: viewModel.swipeViewMode == .clustered ? "folder.fill" : "square.grid.2x2.fill")
                .font(.system(size: 12))
                .foregroundColor(DS.text)
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DS.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(viewModel.swipeViewMode == .clustered ? "Switch to flat grid" : "Switch to clustered view")
    }

    // MARK: - Stats Label

    private var statsLabel: some View {
        HStack(spacing: 6) {
            Text("\(viewModel.swipeGalleryItems.count)")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundColor(DS.text)
            Text("swipes")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.textSecondary)

            if let avg = cachedAvgHookScore {
                Text(String(format: "%.1f", avg))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundColor(averageScoreColor)
                    .commandKToolbarChip(
                        isActive: true,
                        activeFill: averageScoreColor.opacity(0.10),
                        activeBorder: averageScoreColor.opacity(0.18),
                        cornerRadius: 8
                    )

                Text("avg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textMuted)
            }
        }
    }

    private func recomputeAvgHookScore() {
        let scores = viewModel.swipeGalleryItems.compactMap(\.hookScore)
        cachedAvgHookScore = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
    }

    private var averageScoreColor: Color {
        guard let score = cachedAvgHookScore else { return Color(hex: "#64748B") }
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
        .foregroundColor(DS.text)
        .commandKToolbarChip(
            isActive: isActive,
            activeFill: gold.opacity(0.12),
            activeBorder: gold.opacity(0.18)
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
            .commandKToolbarChip()
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
            .commandKToolbarChip(
                isActive: true,
                activeFill: gold.opacity(0.10),
                activeBorder: gold.opacity(0.18)
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
            .commandKToolbarChip(
                isActive: true,
                activeFill: gold.opacity(0.10),
                activeBorder: gold.opacity(0.18)
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

// MARK: - SwipeThumbnailMini

private struct SwipeThumbnailMini: View {
    let item: SwipeGalleryItem
    let size: CGFloat
    @State private var localThumbnail: NSImage?

    var body: some View {
        Group {
            if let localThumb = localThumbnail {
                Image(nsImage: localThumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let thumbnailUrl = item.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                CachedAsyncImage(url: url, stableKey: item.instagramId) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        miniPlaceholder
                            .onAppear { generateLocalThumbnail() }
                    case .empty:
                        miniPlaceholder
                    }
                }
            } else {
                miniPlaceholder
                    .onAppear { generateLocalThumbnail() }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DS.border, lineWidth: 1)
        )
    }

    private var miniPlaceholder: some View {
        ZStack {
            DS.surfaceElevated
            Text(String(item.title.prefix(2)).uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.textMuted)
        }
    }

    private func generateLocalThumbnail() {
        guard localThumbnail == nil,
              let shortcode = item.instagramId, !shortcode.isEmpty else { return }
        Task.detached(priority: .utility) {
            if let image = await SwipeGalleryCard.thumbnailFromCache(shortcode: shortcode) {
                await MainActor.run { localThumbnail = image }
                return
            }
            if let image = await SwipeGalleryCard.extractAndCacheThumbnail(shortcode: shortcode) {
                await MainActor.run { localThumbnail = image }
            }
        }
    }
}

// MARK: - SwipeGalleryCard

private struct SwipeGalleryCard: View {

    let item: SwipeGalleryItem
    let cardWidth: CGFloat
    var viewModel: CommandKViewModel?

    @State private var isPressed = false
    @State private var showDeleteAlert = false

    private var isSelected: Bool {
        viewModel?.selectedUUIDs.contains(item.atomUUID) ?? false
    }

    static func estimatedHeight(for item: SwipeGalleryItem, cardWidth: CGFloat) -> CGFloat {
        SwipeGalleryCardView.estimatedHeight(for: item, cardWidth: cardWidth)
    }

    fileprivate static func thumbnailFromCache(shortcode: String) async -> NSImage? {
        await SwipeGalleryCardView.thumbnailFromCache(shortcode: shortcode)
    }

    fileprivate static func extractAndCacheThumbnail(shortcode: String) async -> NSImage? {
        await SwipeGalleryCardView.extractAndCacheThumbnail(shortcode: shortcode)
    }

    // MARK: - Body

    var body: some View {
        SwipeGalleryCardView(
            item: item,
            cardWidth: cardWidth,
            isSelected: isSelected,
            isPressed: isPressed
        )
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
                    name: CosmoNotification.NodeGraph.hideCommandK,
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
                    name: CosmoNotification.NodeGraph.hideCommandK,
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

            if item.processingStatus == "extraction_failed" {
                Button {
                    Task {
                        if var atom = try? await AtomRepository.shared.fetch(uuid: item.atomUUID) {
                            atom.processingStatus = "pending"
                            var sa = atom.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
                            sa.extractionRetryCount = 0
                            atom = atom.withSwipeAnalysis(sa)
                            _ = try? await AtomRepository.shared.update(atom)
                            await SwipeProcessingService.shared.processSwipeInBackground(uuid: item.atomUUID)
                        }
                    }
                } label: {
                    Label("Retry Processing", systemImage: "arrow.clockwise")
                }
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
}

// SwipeGalleryCardView has been extracted to SwipeGalleryCardView.swift

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
