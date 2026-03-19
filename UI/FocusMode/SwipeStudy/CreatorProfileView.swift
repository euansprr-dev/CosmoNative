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
                withAnimation(ProMotionSprings.snappy) { hasAppeared = true }
            }
            .onChange(of: narrativeFilter) { recomputeFilteredSwipes() }
            .onChange(of: formatFilter) { recomputeFilteredSwipes() }
            .onChange(of: swipeSortOption) { recomputeFilteredSwipes() }
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
                    swipeGridSection
                }
                .padding(20)
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
                    .font(.system(size: 12, weight: .semibold))
                Text("Back")
                    .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 11))
                Text("Compare")
                    .font(.system(size: 12, weight: .medium))
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
                Image(systemName: hasCatalog ? "tray.full.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 11))
                Text(hasCatalog ? "Browse Catalog" : "Import Posts")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(gold, in: Capsule())
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
                    .font(.system(size: 11))
                Text("Edit")
                    .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 11))
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
                        inlineStat(icon: "heart.fill", value: formatMetricCount(avgLikes), label: "Avg Likes", color: Color(hex: "#FF4444"))
                    }
                    if let avgViews = meta.averageViews {
                        inlineStatDivider
                        inlineStat(icon: "play.fill", value: formatMetricCount(avgViews), label: "Avg Views", color: Color(hex: "#8B5CF6"))
                    }
                    if let avgComments = meta.averageComments {
                        inlineStatDivider
                        inlineStat(icon: "bubble.left.fill", value: formatMetricCount(avgComments), label: "Avg Comments", color: Color(hex: "#3B82F6"))
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
                .font(.system(size: 10))
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

    // MARK: - Swipe Grid Section

    private var swipeGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            swipeGridHeader
            swipeGridBody
        }
    }

    private var swipeGridHeader: some View {
        HStack {
            Text("SWIPES (\(cachedFilteredSwipes.count))")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(DS.textMuted)

            Spacer()

            swipeFilterMenus
        }
    }

    @ViewBuilder
    private var swipeGridBody: some View {
        if isLoadingSwipes {
            HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                .padding(.vertical, 40)
        } else if cachedFilteredSwipes.isEmpty {
            Text("No swipes match current filters")
                .font(.system(size: 13))
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
                .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 13))
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
                .font(.system(size: 13))
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
                        .font(.system(size: 12))
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
                .font(.system(size: 13))
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
                .font(.system(size: 10))
            Text(platformNameFor(platform))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(DS.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.border, in: Capsule())
    }

    private func nicheBadge(_ niche: String) -> some View {
        Text(niche)
            .font(.system(size: 12, weight: .medium))
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
