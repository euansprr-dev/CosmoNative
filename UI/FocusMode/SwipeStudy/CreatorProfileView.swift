// CosmoOS/UI/FocusMode/SwipeStudy/CreatorProfileView.swift
// Full creator profile — stats, swipe grid, AI pattern analysis, editing
// Premium floating overlay with canonical swipe cards
// February 2026

import SwiftUI

// MARK: - SwipeSortOption

enum SwipeSortOption: String, CaseIterable {
    case recent = "Recent"
    case mostLikes = "Most Likes"
    case mostViews = "Most Views"
    case mostComments = "Most Comments"

    var icon: String {
        switch self {
        case .recent: return "clock"
        case .mostLikes: return "heart.fill"
        case .mostViews: return "play.fill"
        case .mostComments: return "bubble.left.fill"
        }
    }
}

// MARK: - CatalogViewMode

private enum CatalogViewMode: String, CaseIterable {
    case catalog = "Catalog"
    case saved = "Saved"
}

// MARK: - CreatorProfileView

struct CreatorProfileView: View {

    let creatorAtom: Atom
    let onClose: () -> Void
    let onCompare: (Atom) -> Void
    let onOpenSwipe: (Int64) -> Void

    @State private var creator: Atom
    @State private var meta: CreatorMetadata
    @State private var swipes: [Atom] = []
    @State private var isLoadingSwipes = true
    @State private var isEditing = false
    @State private var showingImport = false
    @State private var hasAppeared = false

    // Edit fields
    @State private var editHandle: String = ""
    @State private var editNiche: String = ""
    @State private var editFollowerCount: String = ""
    @State private var editNotes: String = ""
    @State private var editIsActive: Bool = true

    // Swipe filters & sort
    @State private var narrativeFilter: NarrativeStyle?
    @State private var formatFilter: ContentFormat?
    @State private var swipeSortOption: SwipeSortOption = .recent

    // Catalog state
    @State private var catalogPosts: [ImportedPost] = []
    @State private var catalogExistingShortcodes: Set<String> = []
    @State private var catalogSelectedPostIds: Set<String> = []
    @State private var catalogSortOption: ImportSortOption = .bestPerformers
    @State private var catalogTypeFilter: InstagramContentType? = nil
    @State private var catalogSavedFilter: SavedFilter = .all
    @State private var catalogViewMode: CatalogViewMode = .catalog
    @State private var isSavingFromCatalog = false

    // Cached derived data (avoid recomputing on every body eval)
    @State private var cachedAvgScore: Double?
    @State private var cachedTopNarrative: NarrativeStyle?
    @State private var cachedTopFramework: SwipeFrameworkType?
    @State private var cachedFilteredSwipes: [Atom] = []

    private let gold = DS.entitySwipe

    init(creatorAtom: Atom, onClose: @escaping () -> Void, onCompare: @escaping (Atom) -> Void, onOpenSwipe: @escaping (Int64) -> Void) {
        self.creatorAtom = creatorAtom
        self.onClose = onClose
        self.onCompare = onCompare
        self.onOpenSwipe = onOpenSwipe
        let m = creatorAtom.metadataValue(as: CreatorMetadata.self) ?? CreatorMetadata()
        _creator = State(initialValue: creatorAtom)
        _meta = State(initialValue: m)
    }

    var body: some View {
        mainContent
            .onAppear {
                loadSwipes()
                loadCatalog()
                withAnimation(ProMotionSprings.snappy) { hasAppeared = true }
            }
            .onChange(of: narrativeFilter) { recomputeFilteredSwipes() }
            .onChange(of: formatFilter) { recomputeFilteredSwipes() }
            .onChange(of: swipeSortOption) { recomputeFilteredSwipes() }
            .onChange(of: showingImport) { _, newValue in
                if !newValue {
                    loadCatalog()
                    loadSwipes()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.SwipeFile.creatorDataChanged)) { notification in
                if let uuid = notification.userInfo?["creatorUUID"] as? String,
                   uuid == creator.uuid {
                    loadCatalog()
                    loadSwipes()
                }
            }
            .overlay {
                if isEditing {
                    editOverlay
                }
            }
            .overlay {
                if showingImport {
                    ZStack {
                        FloatingOverlayBackdrop {
                            withAnimation(ProMotionSprings.snappy) { showingImport = false }
                        }
                        CreatorImportSheet(onClose: {
                            withAnimation(ProMotionSprings.snappy) { showingImport = false }
                        }, creatorUUID: creator.uuid)
                        .frame(maxWidth: 800, maxHeight: .infinity)
                        .floatingOverlayPanel()
                        .padding(24)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(ProMotionSprings.snappy, value: showingImport)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(DS.borderActive)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    headerSection
                    creatorStatsSection
                    gridSection
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                catalogSelectionToolbar
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 8)
    }

    // MARK: - Edit Overlay

    private var editOverlay: some View {
        ZStack {
            FloatingOverlayBackdrop { isEditing = false }
            editSheet
                .frame(maxWidth: 440)
                .floatingOverlayPanel()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            backButton
            titleLabel
            Spacer()
            compareButton
            importButton
            editButton
            closeButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var backButton: some View {
        Button {
            onClose()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(DS.buttonText)
                Text("Back")
                    .font(DS.callout)
            }
            .foregroundStyle(DS.textSecondary)
        }
        .buttonStyle(.plain)
        .commandKToolbarChip()
    }

    private var titleLabel: some View {
        Text(creator.title ?? "Creator")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(DS.text)
            .lineLimit(1)
    }

    @ViewBuilder
    private var compareButton: some View {
        Button {
            onCompare(creator)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(DS.footnote)
                Text("Compare")
                    .font(DS.buttonText)
            }
            .foregroundStyle(gold)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(gold.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(gold.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var hasCatalog: Bool {
        meta.catalogPostCount != nil && meta.catalogPostCount! > 0
    }

    @ViewBuilder
    private var importButton: some View {
        Button { showingImport = true } label: {
            HStack(spacing: 4) {
                Image(systemName: !catalogPosts.isEmpty ? "arrow.clockwise" : "arrow.down.circle.fill")
                    .font(DS.footnote)
                Text(!catalogPosts.isEmpty ? "Refresh Catalog" : "Import Posts")
                    .font(DS.buttonText)
            }
            .foregroundStyle(!catalogPosts.isEmpty ? gold : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(!catalogPosts.isEmpty ? gold.opacity(0.12) : gold, in: Capsule())
            .overlay(!catalogPosts.isEmpty ? Capsule().strokeBorder(gold.opacity(0.3), lineWidth: 1) : nil)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var editButton: some View {
        Button {
            prepareEditFields()
            isEditing = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "pencil")
                    .font(DS.footnote)
                Text("Edit")
                    .font(DS.buttonText)
            }
            .foregroundStyle(DS.textSecondary)
        }
        .buttonStyle(.plain)
        .commandKToolbarChip()
    }

    private var closeButton: some View {
        FloatingOverlayCloseButton(action: onClose)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 0) {
            // Accent bar
            gold.opacity(0.2)
                .frame(height: 3)

            headerContent
                .padding(16)
        }
        .clipShape(.rect(cornerRadius: CommandKMetrics.sectionCornerRadius, style: .continuous))
        .commandKSectionChrome()
    }

    private var headerContent: some View {
        HStack(spacing: 16) {
            headerAvatar
            headerInfo
            Spacer()
            headerFollowerCount
        }
    }

    private var headerAvatar: some View {
        ZStack {
            Circle()
                .fill(DS.entitySwipe.opacity(0.15))
                .frame(width: 64, height: 64)
            Text(initialsFor(creator.title))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(gold)
        }
    }

    private var headerInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(creator.title ?? "Unknown Creator")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.text)

            if let handle = meta.handle {
                Text(handle)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.textSecondary)
            }

            headerBadges
        }
    }

    private var headerBadges: some View {
        HStack(spacing: 8) {
            if let platform = meta.platform {
                platformBadge(platform)
            }
            if let niche = meta.niche, !niche.isEmpty {
                nicheBadge(niche)
            }
            if meta.isActive == true {
                trackedBadge
            }
        }
    }

    @ViewBuilder
    private var headerFollowerCount: some View {
        if let followers = meta.followerCount, followers > 0 {
            VStack(spacing: 2) {
                Text(formatFollowers(followers))
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(DS.text)
                Text("Followers")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    // MARK: - Unified Stats Section

    private var creatorStatsSection: some View {
        VStack(spacing: 0) {
            // Analysis row
            HStack(spacing: 0) {
                inlineStat(
                    icon: "bolt.fill",
                    value: "\(swipes.count)",
                    label: "Studied",
                    color: gold
                )
                inlineStatDivider
                inlineStat(
                    icon: "chart.bar.fill",
                    value: cachedAvgScore.map { String(format: "%.1f", $0) } ?? "--",
                    label: "Hook Score",
                    color: hookScoreColor(cachedAvgScore)
                )
                if let n = cachedTopNarrative {
                    inlineStatDivider
                    inlineStat(icon: n.icon, value: n.displayName, label: "Narrative", color: n.color)
                }
                if let f = cachedTopFramework {
                    inlineStatDivider
                    inlineStat(icon: "rectangle.3.group", value: f.displayName, label: "Framework", color: f.color)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)

            // Engagement row (only if data exists)
            if meta.averageLikes != nil || meta.averageViews != nil {
                DS.border.frame(height: 1).padding(.horizontal, 12)

                HStack(spacing: 0) {
                    if let avgLikes = meta.averageLikes {
                        inlineStat(icon: "heart.fill", value: formatMetricCount(avgLikes), label: "Avg Likes", color: DS.red)
                    }
                    if let avgViews = meta.averageViews {
                        inlineStatDivider
                        inlineStat(icon: "play.fill", value: formatMetricCount(avgViews), label: "Avg Views", color: DS.entityConnection)
                    }
                    if let avgComments = meta.averageComments {
                        inlineStatDivider
                        inlineStat(icon: "bubble.left.fill", value: formatMetricCount(avgComments), label: "Avg Comments", color: DS.info)
                    }
                    if let rate = meta.medianEngagementRate {
                        inlineStatDivider
                        inlineStat(icon: "chart.line.uptrend.xyaxis", value: String(format: "%.1f%%", rate), label: "Eng. Rate", color: gold)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }
        }
        .commandKSectionChrome()
    }

    private func inlineStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var inlineStatDivider: some View {
        DS.border.frame(width: 1, height: 28)
    }

    private func formatMetricCount(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    // MARK: - Cached Stats (recomputed when swipes change)

    private func recomputeStats() {
        let scores = swipes.compactMap { $0.swipeAnalysis?.hookScore }
        cachedAvgScore = scores.isEmpty ? meta.averageHookScore : scores.reduce(0, +) / Double(scores.count)

        let narratives = swipes.compactMap { $0.swipeAnalysis?.primaryNarrative }
        let nCounts = Dictionary(narratives.map { ($0, 1) }, uniquingKeysWith: +)
        cachedTopNarrative = nCounts.max(by: { $0.value < $1.value })?.key

        let frameworks = swipes.compactMap { $0.swipeAnalysis?.frameworkType }
        let fCounts = Dictionary(frameworks.map { ($0, 1) }, uniquingKeysWith: +)
        cachedTopFramework = fCounts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Grid Section (Catalog + Saved)

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            gridSectionHeader
            if !catalogPosts.isEmpty && catalogViewMode == .catalog {
                catalogSortFilterBar
                catalogGridBody
            } else {
                savedSwipeGridBody
            }
        }
    }

    @ViewBuilder
    private var gridSectionHeader: some View {
        if !catalogPosts.isEmpty {
            HStack {
                catalogSegmentPicker
                Spacer()
                if catalogViewMode == .saved {
                    swipeFilterMenus
                }
            }
        } else {
            HStack {
                Text("SWIPES (\(cachedFilteredSwipes.count))")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(DS.textMuted)
                Spacer()
                swipeFilterMenus
            }
        }
    }

    @ViewBuilder
    private var catalogSegmentPicker: some View {
        HStack(spacing: 0) {
            catalogSegmentButton(.catalog, label: "Catalog (\(catalogPosts.count))")
            catalogSegmentButton(.saved, label: "Saved (\(swipes.count))")
        }
        .background(DS.surface, in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func catalogSegmentButton(_ mode: CatalogViewMode, label: String) -> some View {
        let isActive = catalogViewMode == mode
        Button {
            withAnimation(ProMotionSprings.snappy) { catalogViewMode = mode }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.textOnAccent : DS.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isActive ? gold : Color.clear, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Catalog Sort & Filter Bar

    @ViewBuilder
    private var catalogSortFilterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                catalogSortChips
                Spacer()
            }
            HStack(spacing: 8) {
                catalogTypeFilterChips
                Divider().frame(height: 16)
                catalogSavedFilterChips
                Spacer()
                if catalogTypeFilter != nil || catalogSavedFilter != .all {
                    catalogFilteredCountLabel
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .commandKToolbarGroup()
    }

    @ViewBuilder
    private var catalogSortChips: some View {
        ForEach(ImportSortOption.allCases, id: \.self) { option in
            catalogSortChipButton(option)
        }
    }

    @ViewBuilder
    private func catalogSortChipButton(_ option: ImportSortOption) -> some View {
        let isActive = catalogSortOption == option
        Button {
            withAnimation(ProMotionSprings.snappy) { catalogSortOption = option }
        } label: {
            Text(option.rawValue)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.textOnAccent : DS.text)
                .commandKToolbarChip(
                    isActive: isActive,
                    activeFill: gold,
                    activeBorder: gold
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var catalogTypeFilterChips: some View {
        catalogTypeFilterChipButton(nil, label: "All")
        catalogTypeFilterChipButton(.reel, label: "Reels")
        catalogTypeFilterChipButton(.carousel, label: "Carousels")
        catalogTypeFilterChipButton(.image, label: "Images")
    }

    @ViewBuilder
    private func catalogTypeFilterChipButton(_ type: InstagramContentType?, label: String) -> some View {
        let isActive = catalogTypeFilter == type
        Button {
            withAnimation(ProMotionSprings.snappy) { catalogTypeFilter = type }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.textOnAccent : DS.textSecondary)
                .commandKToolbarChip(
                    isActive: isActive,
                    activeFill: DS.accent,
                    activeBorder: DS.accent
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var catalogSavedFilterChips: some View {
        ForEach(SavedFilter.allCases, id: \.self) { filter in
            catalogSavedFilterChipButton(filter)
        }
    }

    @ViewBuilder
    private func catalogSavedFilterChipButton(_ filter: SavedFilter) -> some View {
        let isActive = catalogSavedFilter == filter
        Button {
            withAnimation(ProMotionSprings.snappy) { catalogSavedFilter = filter }
        } label: {
            Text(filter.rawValue)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.textOnAccent : DS.textSecondary)
                .commandKToolbarChip(
                    isActive: isActive,
                    activeFill: DS.accent,
                    activeBorder: DS.accent
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var catalogFilteredCountLabel: some View {
        Text("\(sortedCatalogPosts.count) shown")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(DS.textMuted)
    }

    // MARK: - Catalog Grid

    private var sortedCatalogPosts: [ImportedPost] {
        var filtered = catalogPosts
        if let typeFilter = catalogTypeFilter {
            filtered = filtered.filter { $0.contentType == typeFilter }
        }
        switch catalogSavedFilter {
        case .all: break
        case .unsaved:
            filtered = filtered.filter { !catalogExistingShortcodes.contains($0.shortcode) }
        case .saved:
            filtered = filtered.filter { catalogExistingShortcodes.contains($0.shortcode) }
        }
        return catalogSortOption.sort(filtered)
    }

    @ViewBuilder
    private var catalogGridBody: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let columnCount = max(2, Int(width / (236 + CommandKMetrics.cardSpacing)))
            let totalSpacing = CGFloat(columnCount - 1) * CommandKMetrics.cardSpacing
            let cardW = (width - totalSpacing) / CGFloat(columnCount)
            let columns = distributeCatalogColumns(columnCount: columnCount, cardWidth: cardW)

            HStack(alignment: .top, spacing: CommandKMetrics.cardSpacing) {
                ForEach(0..<columnCount, id: \.self) { col in
                    LazyVStack(spacing: CommandKMetrics.cardSpacing) {
                        ForEach(col < columns.count ? columns[col] : []) { post in
                            ImportedPostCard(
                                post: post,
                                isSelected: catalogSelectedPostIds.contains(post.id),
                                isDuplicate: false,
                                onToggle: { toggleCatalogSelection(post.id) },
                                cardWidth: cardW
                            )
                            .overlay(alignment: .topTrailing) {
                                catalogSavedBadge(for: post)
                            }
                        }
                    }
                    .frame(width: cardW)
                }
            }
        }
        .frame(minHeight: estimateCatalogGridHeight())
    }

    private func distributeCatalogColumns(columnCount: Int, cardWidth: CGFloat) -> [[ImportedPost]] {
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)
        var columns: [[ImportedPost]] = Array(repeating: [], count: columnCount)

        for post in sortedCatalogPosts {
            let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[shortest].append(post)
            columnHeights[shortest] += ImportedPostCard.estimatedHeight(for: post, cardWidth: cardWidth) + CommandKMetrics.cardSpacing
        }
        return columns
    }

    private func estimateCatalogGridHeight() -> CGFloat {
        let posts = sortedCatalogPosts
        guard !posts.isEmpty else { return 200 }
        let avgHeight = posts.prefix(20).reduce(CGFloat(0)) { sum, post in
            sum + ImportedPostCard.estimatedHeight(for: post, cardWidth: 220)
        } / CGFloat(min(posts.count, 20))
        let estimatedRows = CGFloat(posts.count) / 4.0
        return estimatedRows * (avgHeight + CommandKMetrics.cardSpacing)
    }

    @ViewBuilder
    private func catalogSavedBadge(for post: ImportedPost) -> some View {
        if catalogExistingShortcodes.contains(post.shortcode) {
            Text("Saved")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DS.accent.opacity(0.85), in: Capsule())
                .padding(6)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Catalog Selection Toolbar

    @ViewBuilder
    private var catalogSelectionToolbar: some View {
        if !catalogPosts.isEmpty && catalogViewMode == .catalog {
            VStack(spacing: 0) {
                DS.borderSubtle.frame(height: 1)
                catalogSelectionToolbarContent
            }
            .background(DS.surfaceElevated)
        }
    }

    @ViewBuilder
    private var catalogSelectionToolbarContent: some View {
        HStack(spacing: 8) {
            catalogQuickSelectChip("Select All") { catalogSelectAll() }
            catalogQuickSelectChip("Top 10") { catalogSelectTopN(10) }
            catalogQuickSelectChip("Top 25") { catalogSelectTopN(25) }
            catalogQuickSelectChip("All Reels") { catalogSelectAllReels() }
            if !catalogSelectedPostIds.isEmpty {
                catalogQuickSelectChip("Clear") { catalogSelectedPostIds.removeAll() }
            }
            Spacer()
            catalogSaveCTA
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func catalogQuickSelectChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .commandKToolbarChip()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var catalogSaveCTA: some View {
        if !catalogSelectedPostIds.isEmpty {
            Button {
                Task { await saveCatalogSelections() }
            } label: {
                HStack(spacing: 5) {
                    if isSavingFromCatalog {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(DS.textOnAccent)
                    } else {
                        Image(systemName: "square.and.arrow.down.fill")
                    }
                    Text("Save \(catalogSelectedPostIds.count) Selected")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(DS.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSavingFromCatalog)
        }
    }

    // MARK: - Saved Swipe Grid (existing)

    @ViewBuilder
    private var savedSwipeGridBody: some View {
        if isLoadingSwipes {
            HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                .padding(.vertical, 40)
        } else if cachedFilteredSwipes.isEmpty {
            Text("No swipes match current filters")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
        } else {
            MasonrySwipeGrid(swipes: cachedFilteredSwipes) { swipe in
                swipeCard(swipe)
            }
        }
    }

    @ViewBuilder
    private var swipeFilterMenus: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(SwipeSortOption.allCases, id: \.rawValue) { opt in
                    Button {
                        swipeSortOption = opt
                    } label: {
                        HStack {
                            Label(opt.rawValue, systemImage: opt.icon)
                            if swipeSortOption == opt {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                sortMenuLabel
            }
            .menuStyle(.borderlessButton)

            Menu {
                Button("All Narratives") { narrativeFilter = nil }
                Divider()
                ForEach(NarrativeStyle.allCases, id: \.rawValue) { style in
                    Button(style.displayName) {
                        narrativeFilter = narrativeFilter == style ? nil : style
                    }
                }
            } label: {
                narrativeFilterLabel
            }
            .menuStyle(.borderlessButton)

            Menu {
                Button("All Formats") { formatFilter = nil }
                Divider()
                ForEach(ContentFormat.allCases, id: \.rawValue) { fmt in
                    Button(fmt.displayName) {
                        formatFilter = formatFilter == fmt ? nil : fmt
                    }
                }
            } label: {
                formatFilterLabel
            }
            .menuStyle(.borderlessButton)
        }
    }

    @ViewBuilder
    private var sortMenuLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: swipeSortOption.icon)
                .font(.system(size: 9, weight: .bold))
            Text(swipeSortOption.rawValue)
                .font(DS.caption)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(swipeSortOption != .recent ? DS.text : DS.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(swipeSortOption != .recent ? gold.opacity(0.2) : DS.border)
        )
    }

    @ViewBuilder
    private var narrativeFilterLabel: some View {
        HStack(spacing: 3) {
            Text(narrativeFilter?.displayName ?? "Narrative")
                .font(DS.caption)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(narrativeFilter != nil ? DS.text : DS.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(narrativeFilter != nil ? gold.opacity(0.2) : DS.border)
        )
    }

    @ViewBuilder
    private var formatFilterLabel: some View {
        HStack(spacing: 3) {
            Text(formatFilter?.displayName ?? "Format")
                .font(DS.caption)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(formatFilter != nil ? DS.text : DS.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(formatFilter != nil ? gold.opacity(0.2) : DS.border)
        )
    }

    private func recomputeFilteredSwipes() {
        var items = swipes
        if let nf = narrativeFilter {
            items = items.filter { $0.swipeAnalysis?.primaryNarrative == nf }
        }
        if let ff = formatFilter {
            items = items.filter { $0.swipeAnalysis?.swipeContentFormat == ff }
        }
        switch swipeSortOption {
        case .recent:
            items.sort { $0.createdAt > $1.createdAt }
        case .mostLikes:
            items.sort { ($0.swipeAnalysis?.likesCount ?? 0) > ($1.swipeAnalysis?.likesCount ?? 0) }
        case .mostViews:
            items.sort { ($0.swipeAnalysis?.viewsCount ?? 0) > ($1.swipeAnalysis?.viewsCount ?? 0) }
        case .mostComments:
            items.sort { ($0.swipeAnalysis?.commentsCount ?? 0) > ($1.swipeAnalysis?.commentsCount ?? 0) }
        }
        cachedFilteredSwipes = items
    }

    // MARK: - Swipe Card (Canonical)

    @ViewBuilder
    private func swipeCard(_ swipe: Atom) -> some View {
        if let galleryItem = swipe.toSwipeGalleryItem() {
            SwipeGalleryCardView(item: galleryItem, cardWidth: 180)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let entityId = swipe.id {
                        onOpenSwipe(entityId)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    NotificationCenter.default.post(
                        name: Notification.Name("addSwipeToCanvas"),
                        object: nil,
                        userInfo: ["atomUUID": swipe.uuid]
                    )
                }
                .contextMenu {
                    swipeContextMenu(swipe)
                }
        }
    }

    @ViewBuilder
    private func swipeContextMenu(_ swipe: Atom) -> some View {
        Button {
            if let entityId = swipe.id {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": EntityType.research, "id": entityId]
                )
            }
        } label: {
            Label("Open in Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Button {
            NotificationCenter.default.post(
                name: Notification.Name("addSwipeToCanvas"),
                object: nil,
                userInfo: ["atomUUID": swipe.uuid]
            )
        } label: {
            Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
        }

        Divider()

        Button(role: .destructive) {
            Task {
                try? await SwipeFileEngine.shared.deleteSwipe(atomUUID: swipe.uuid)
                loadSwipes()
            }
        } label: {
            Label("Delete Swipe", systemImage: "trash")
        }
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        VStack(spacing: 16) {
            editSheetHeader
            editSheetFields
            editSheetFooter
        }
        .padding(20)
    }

    private var editSheetHeader: some View {
        HStack {
            Text("Edit Creator")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.text)
            Spacer()
            Button("Cancel") { isEditing = false }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var editSheetFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            editField("Handle", text: $editHandle)
            editField("Niche", text: $editNiche)
            editField("Follower Count", text: $editFollowerCount)

            Toggle(isOn: $editIsActive) {
                Text("Actively Tracked")
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
            }
            .toggleStyle(.switch)
            .tint(gold)

            editNotesField
        }
    }

    private var editNotesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
            TextEditor(text: $editNotes)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .scrollContentBackground(.hidden)
                .frame(height: 100)
                .padding(8)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.border, lineWidth: 1)
                )
        }
    }

    private var editSheetFooter: some View {
        HStack {
            Spacer()
            Button {
                saveEdit()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.subheadline)
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(gold, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func editField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .padding(8)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Data Loading

    private func loadSwipes() {
        Task {
            isLoadingSwipes = true
            let all = try? await AtomRepository.shared.fetchSwipesByTaxonomy(creatorUUID: creator.uuid)
            swipes = all ?? []
            recomputeStats()
            recomputeFilteredSwipes()
            isLoadingSwipes = false

            await recalculateCreatorStats()
        }
    }

    private func loadCatalog() {
        guard let posts = CatalogStore.load(creatorUUID: creator.uuid), !posts.isEmpty else {
            // No catalog — default to saved view
            catalogPosts = []
            catalogViewMode = .saved
            return
        }
        catalogPosts = posts
        Task {
            let shortcodes = posts.map(\.shortcode)
            catalogExistingShortcodes = (try? await AtomRepository.shared.findExistingShortcodes(shortcodes)) ?? []
        }
    }

    // MARK: - Catalog Selection

    private func toggleCatalogSelection(_ postId: String) {
        if catalogSelectedPostIds.contains(postId) {
            catalogSelectedPostIds.remove(postId)
        } else {
            // Only allow selecting non-saved posts
            if let post = catalogPosts.first(where: { $0.id == postId }),
               !catalogExistingShortcodes.contains(post.shortcode) {
                catalogSelectedPostIds.insert(postId)
            }
        }
    }

    private func catalogSelectAll() {
        let selectable = catalogPosts.filter { !catalogExistingShortcodes.contains($0.shortcode) }
        catalogSelectedPostIds = Set(selectable.map(\.id))
    }

    private func catalogSelectTopN(_ n: Int) {
        let sorted = catalogSortOption.sort(catalogPosts)
        let selectable = sorted.filter { !catalogExistingShortcodes.contains($0.shortcode) }
        catalogSelectedPostIds = Set(selectable.prefix(n).map(\.id))
    }

    private func catalogSelectAllReels() {
        let reels = catalogPosts.filter {
            $0.contentType == .reel && !catalogExistingShortcodes.contains($0.shortcode)
        }
        catalogSelectedPostIds = Set(reels.map(\.id))
    }

    private func saveCatalogSelections() async {
        isSavingFromCatalog = true

        let engine = CreatorImportEngine()
        await engine.loadCachedCatalog(creatorUUID: creator.uuid)
        for id in catalogSelectedPostIds {
            engine.toggleSelection(id)
        }
        _ = await engine.saveSelectedPosts()

        // Update local state
        let savedShortcodes = catalogSelectedPostIds.compactMap { id in
            catalogPosts.first { $0.id == id }?.shortcode
        }
        catalogExistingShortcodes.formUnion(savedShortcodes)
        catalogSelectedPostIds.removeAll()
        loadSwipes()
        isSavingFromCatalog = false
    }

    private func recalculateCreatorStats() async {
        let scores = swipes.compactMap { $0.swipeAnalysis?.hookScore }
        let avgScore = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)

        let narrativeCounts = Dictionary(
            swipes.compactMap { $0.swipeAnalysis?.primaryNarrative }.map { ($0.rawValue, 1) },
            uniquingKeysWith: +
        )
        let topNarratives = narrativeCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        let formatCounts = Dictionary(
            swipes.compactMap { $0.swipeAnalysis?.swipeContentFormat }.map { ($0.rawValue, 1) },
            uniquingKeysWith: +
        )
        let topFormats = formatCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        var updatedMeta = meta
        updatedMeta.swipeCount = swipes.count
        updatedMeta.averageHookScore = avgScore
        updatedMeta.topNarratives = topNarratives.isEmpty ? nil : Array(topNarratives)
        updatedMeta.topFormats = topFormats.isEmpty ? nil : Array(topFormats)

        meta = updatedMeta
        let updatedCreator = creator.withMetadata(updatedMeta)
        try? await AtomRepository.shared.update(updatedCreator)
        creator = updatedCreator
    }

    // MARK: - Edit Helpers

    private func prepareEditFields() {
        editHandle = meta.handle ?? ""
        editNiche = meta.niche ?? ""
        editFollowerCount = meta.followerCount.map { "\($0)" } ?? ""
        editNotes = meta.notes ?? ""
        editIsActive = meta.isActive ?? true
    }

    private func saveEdit() {
        var updatedMeta = meta
        updatedMeta.handle = editHandle.isEmpty ? nil : editHandle
        updatedMeta.niche = editNiche.isEmpty ? nil : editNiche
        updatedMeta.followerCount = Int(editFollowerCount)
        updatedMeta.notes = editNotes.isEmpty ? nil : editNotes
        updatedMeta.isActive = editIsActive

        meta = updatedMeta
        let updatedCreator = creator.withMetadata(updatedMeta)

        Task {
            try? await AtomRepository.shared.update(updatedCreator)
            creator = updatedCreator
        }

        isEditing = false
    }

    // MARK: - Badge Subviews

    private func platformBadge(_ platform: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: platformIconFor(platform))
                .font(DS.caption2)
            Text(platformNameFor(platform))
                .font(DS.caption)
        }
        .foregroundStyle(DS.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.border, in: Capsule())
    }

    private func nicheBadge(_ niche: String) -> some View {
        Text(niche)
            .font(DS.buttonText)
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.border, in: Capsule())
    }

    private var trackedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.fill")
                .font(.system(size: 9))
            Text("Tracked")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(gold)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(gold.opacity(0.12), in: Capsule())
    }

    // MARK: - Helpers

    private func initialsFor(_ name: String?) -> String {
        guard let name = name, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func hookScoreColor(_ score: Double?) -> Color {
        guard let score = score else { return DS.textMuted }
        if score >= 8.0 { return DS.green }
        if score >= 5.0 { return DS.info }
        return DS.textMuted
    }

    private func formatFollowers(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func platformIconFor(_ raw: String) -> String {
        switch raw {
        case "youtube": return "play.rectangle.fill"
        case "instagram": return "camera.fill"
        case "x", "twitter": return "bubble.left.fill"
        case "threads": return "at"
        case "tiktok": return "music.note"
        default: return "globe"
        }
    }

    private func platformNameFor(_ raw: String) -> String {
        switch raw {
        case "youtube": return "YouTube"
        case "instagram": return "Instagram"
        case "x", "twitter": return "X"
        case "threads": return "Threads"
        case "tiktok": return "TikTok"
        default: return raw.capitalized
        }
    }
}

// MARK: - Masonry Grid

/// Three-column waterfall layout that packs cards by shortest column
private struct MasonrySwipeGrid<Content: View>: View {
    let swipes: [Atom]
    @ViewBuilder let cardContent: (Atom) -> Content

    @State private var columnHeights: [String: CGFloat] = [:]
    @State private var cachedColumns: [[Atom]] = [[], [], []]

    private let columnCount = 3
    private let spacing: CGFloat = 12

    private func recomputeColumns() {
        var cols: [[Atom]] = Array(repeating: [], count: columnCount)
        var heights: [CGFloat] = Array(repeating: 0, count: columnCount)

        for swipe in swipes {
            let h = columnHeights[swipe.uuid] ?? 200
            let shortest = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            cols[shortest].append(swipe)
            heights[shortest] += h + spacing
        }
        cachedColumns = cols
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columnCount, id: \.self) { col in
                LazyVStack(spacing: spacing) {
                    ForEach(col < cachedColumns.count ? cachedColumns[col] : [], id: \.uuid) { swipe in
                        cardContent(swipe)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: MasonryHeightPreference.self,
                                        value: [swipe.uuid: geo.size.height]
                                    )
                                }
                            )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onPreferenceChange(MasonryHeightPreference.self) { heights in
            var changed = false
            for (key, value) in heights {
                if let existing = columnHeights[key], abs(existing - value) < 2 { continue }
                changed = true
                break
            }
            if changed {
                columnHeights.merge(heights) { _, new in new }
            }
        }
        .onAppear { recomputeColumns() }
        .onChange(of: swipes.count) { recomputeColumns() }
    }
}

private struct MasonryHeightPreference: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
