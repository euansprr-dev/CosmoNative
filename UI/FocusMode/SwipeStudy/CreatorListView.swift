// CosmoOS/UI/FocusMode/SwipeStudy/CreatorListView.swift
// Creator Database — card grid of all .creator atoms
// February 2026

import SwiftUI

// MARK: - Sort / Filter Enums

enum CreatorSortMode: String, CaseIterable {
    case name, swipeCount, hookScore

    var displayName: String {
        switch self {
        case .name: return "Name"
        case .swipeCount: return "Post Count"
        case .hookScore: return "Avg Hook Score"
        }
    }
}

// MARK: - CreatorListView

struct CreatorListView: View {

    let onSelectCreator: (Atom) -> Void
    let onCompare: ([Atom]) -> Void
    let onClose: () -> Void

    @State private var creators: [Atom] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var sortMode: CreatorSortMode = .swipeCount
    @State private var platformFilter: String?
    @State private var nicheFilter: String?
    @State private var hasAppeared = false
    @State private var showingImport = false
    @State private var cachedFilteredCreators: [Atom] = []
    @State private var allPlatforms: [String] = []
    @State private var allNiches: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(DS.borderSubtle)
            filterRow
            Divider().background(DS.borderSubtle)

            if isLoading {
                Spacer()
                ProgressView().tint(DS.textSecondary)
                Spacer()
            } else if cachedFilteredCreators.isEmpty {
                emptyState
            } else {
                creatorGrid
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
                    })
                    .frame(maxWidth: 800, maxHeight: .infinity)
                    .floatingOverlayPanel()
                    .padding(24)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(ProMotionSprings.snappy, value: showingImport)
        .onAppear {
            loadCreators()
            withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
        }
        .onChange(of: creators) { _, _ in recomputeDerivedState() }
        .onChange(of: searchText) { recomputeFilteredCreators() }
        .onChange(of: sortMode) { recomputeFilteredCreators() }
        .onChange(of: platformFilter) { recomputeFilteredCreators() }
        .onChange(of: nicheFilter) { recomputeFilteredCreators() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            headerBackButton
            headerTitle
            Spacer()
            headerSearchField
            headerImportButton
            headerCompareButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var headerBackButton: some View {
        Button {
            onClose()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Back")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(DS.textSecondary)
            .commandKToolbarChip()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var headerTitle: some View {
        Image(systemName: "person.crop.rectangle.fill")
            .font(.system(size: 14))
            .foregroundStyle(DS.entitySwipe)

        Text("Creators")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(DS.text)

        Text("\(creators.count)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DS.entitySwipe.opacity(0.8))
            .commandKToolbarChip(
                isActive: true,
                activeFill: DS.entitySwipe.opacity(0.15),
                activeBorder: DS.entitySwipe.opacity(0.3)
            )
    }

    private var headerSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
            TextField("Search creators...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.text)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 240, height: 48)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DS.borderSubtle, lineWidth: 1)
        )
    }

    private var headerImportButton: some View {
        Button { showingImport = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11))
                Text("Import")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.entitySwipe, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var headerCompareButton: some View {
        Button {
            onCompare(creators)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11))
                Text("Compare")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.surfaceElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter Row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                sortMenuView

                Rectangle()
                    .fill(DS.border)
                    .frame(width: 1, height: 24)

                filterChip(title: "All Platforms", isSelected: platformFilter == nil) {
                    platformFilter = nil
                }
                ForEach(allPlatforms, id: \.self) { platform in
                    filterChip(
                        title: platformDisplayName(platform),
                        icon: platformIcon(platform),
                        isSelected: platformFilter == platform
                    ) {
                        platformFilter = platformFilter == platform ? nil : platform
                    }
                }

                if !allNiches.isEmpty {
                    Rectangle()
                        .fill(DS.border)
                        .frame(width: 1, height: 24)

                    nicheMenuView
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .frame(height: 52)
        .background(DS.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.borderSubtle, lineWidth: 0.5)
                .padding(.horizontal, 12)
        )
    }

    private var sortMenuView: some View {
        Menu {
            ForEach(CreatorSortMode.allCases, id: \.self) { mode in
                Button(mode.displayName) {
                    sortMode = mode
                }
            }
        } label: {
            sortMenuLabel
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var sortMenuLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 10))
            Text(sortMode.displayName)
                .font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(DS.textSecondary)
        .commandKToolbarChip()
    }

    private var nicheMenuView: some View {
        Menu {
            Button("All Niches") { nicheFilter = nil }
            Divider()
            ForEach(allNiches, id: \.self) { niche in
                Button(niche) {
                    nicheFilter = nicheFilter == niche ? nil : niche
                }
            }
        } label: {
            nicheMenuLabel
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var nicheMenuLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.system(size: 10))
            Text(nicheFilter ?? "Niche")
                .font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(nicheFilter != nil ? DS.text : DS.textSecondary)
        .commandKToolbarChip(
            isActive: nicheFilter != nil,
            activeFill: DS.entitySwipe.opacity(0.15),
            activeBorder: DS.entitySwipe.opacity(0.5)
        )
    }

    private func filterChip(title: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            filterChipLabel(title: title, icon: icon, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func filterChipLabel(title: String, icon: String?, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
        .commandKToolbarChip(
            isActive: isSelected,
            activeFill: DS.entitySwipe.opacity(0.15),
            activeBorder: DS.entitySwipe.opacity(0.5)
        )
    }

    // MARK: - Filtered + Sorted Creators

    /// Recompute both filter chips and filtered list when creators change
    private func recomputeDerivedState() {
        allPlatforms = Array(Set(creators.compactMap { $0.metadataValue(as: CreatorMetadata.self)?.platform })).sorted()
        allNiches = Array(Set(creators.compactMap { $0.metadataValue(as: CreatorMetadata.self)?.niche })).sorted()
        recomputeFilteredCreators()
    }

    private func recomputeFilteredCreators() {
        var items = creators

        // Search filter
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            items = items.filter { atom in
                (atom.title?.lowercased().contains(q) ?? false) ||
                (atom.metadataValue(as: CreatorMetadata.self)?.handle?.lowercased().contains(q) ?? false)
            }
        }

        // Platform filter
        if let pf = platformFilter {
            items = items.filter { atom in
                atom.metadataValue(as: CreatorMetadata.self)?.platform == pf
            }
        }

        // Niche filter
        if let nf = nicheFilter {
            items = items.filter { atom in
                atom.metadataValue(as: CreatorMetadata.self)?.niche == nf
            }
        }

        // Sort — pre-extract metadata to avoid N*log(N) JSON deserialization
        switch sortMode {
        case .name:
            items.sort { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
        case .swipeCount:
            let metaCache = Dictionary(uniqueKeysWithValues: items.map { ($0.uuid, $0.metadataValue(as: CreatorMetadata.self)) })
            items.sort { (metaCache[$0.uuid]??.swipeCount ?? 0) > (metaCache[$1.uuid]??.swipeCount ?? 0) }
        case .hookScore:
            let metaCache = Dictionary(uniqueKeysWithValues: items.map { ($0.uuid, $0.metadataValue(as: CreatorMetadata.self)) })
            items.sort { (metaCache[$0.uuid]??.averageHookScore ?? 0) > (metaCache[$1.uuid]??.averageHookScore ?? 0) }
        }

        cachedFilteredCreators = items
    }

    // MARK: - Creator Grid

    private var creatorGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)],
                spacing: 16
            ) {
                ForEach(Array(cachedFilteredCreators.enumerated()), id: \.element.uuid) { index, atom in
                    CreatorCard(
                        atom: atom,
                        appearDelay: Double(min(index, 12)) * 0.04,
                        hasAppeared: hasAppeared,
                        onTap: { onSelectCreator(atom) }
                    )
                }
            }
            .padding(20)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.3")
                .font(.system(size: 36))
                .foregroundStyle(DS.textMuted)
            Text("No creators yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.text)
            Text("Import your first creator to start tracking")
                .font(.system(size: 13))
                .foregroundStyle(DS.textSecondary)
            Spacer()
        }
    }

    // MARK: - Data Loading

    private func loadCreators() {
        Task {
            isLoading = true
            let fetched = try? await AtomRepository.shared.fetchCreators()
            creators = fetched ?? []
            recomputeDerivedState()
            isLoading = false
        }
    }

    // MARK: - Helpers

    private func platformDisplayName(_ raw: String) -> String {
        switch raw {
        case "youtube": return "YouTube"
        case "instagram": return "Instagram"
        case "x", "twitter": return "X"
        case "threads": return "Threads"
        case "tiktok": return "TikTok"
        case "linkedin": return "LinkedIn"
        default: return raw.capitalized
        }
    }

    private func platformIcon(_ raw: String) -> String {
        switch raw {
        case "youtube": return "play.rectangle.fill"
        case "instagram": return "camera.fill"
        case "x", "twitter": return "bubble.left.fill"
        case "threads": return "at"
        case "tiktok": return "music.note"
        case "linkedin": return "briefcase.fill"
        default: return "globe"
        }
    }
}

// MARK: - Creator Card

private struct CreatorCard: View {

    let atom: Atom
    let appearDelay: Double
    let hasAppeared: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    private var meta: CreatorMetadata? {
        atom.metadataValue(as: CreatorMetadata.self)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            avatarNameRow
            platformNicheRow
            Divider().background(DS.borderSubtle)
            statsRow
            if let narratives = meta?.topNarratives, !narratives.isEmpty {
                narrativeBadges(narratives)
            }
        }
        .padding(14)
        .commandKGalleryCardChrome(
            isHovered: isHovered,
            isSelected: false,
            accentColor: DS.entitySwipe
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .opacity(hasAppeared ? 1.0 : 0.0)
        .offset(y: hasAppeared ? 0 : 16)
        .animation(ProMotionSprings.snappy.delay(appearDelay), value: hasAppeared)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }

    // MARK: - Subviews

    private var avatarNameRow: some View {
        HStack(spacing: 12) {
            avatarCircle
            VStack(alignment: .leading, spacing: 2) {
                Text(atom.title ?? "Unknown")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                if let handle = meta?.handle {
                    Text(handle)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if meta?.isActive == true {
                competitorBadge
            }
        }
    }

    private var platformNicheRow: some View {
        HStack(spacing: 8) {
            if let platform = meta?.platform {
                platformBadge(platform)
            }
            if let niche = meta?.niche, !niche.isEmpty {
                Text(niche)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statItem(value: "\(meta?.totalPostsImported ?? meta?.swipeCount ?? 0)", label: "Posts")
            statItem(
                value: meta?.averageHookScore.map { String(format: "%.1f", $0) } ?? "--",
                label: "Avg Score",
                valueColor: hookScoreColor(meta?.averageHookScore)
            )
            if let followers = meta?.followerCount, followers > 0 {
                statItem(value: formatFollowers(followers), label: "Followers")
            }
            Spacer()
        }
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(DS.entitySwipe.opacity(0.15))
                .frame(width: 40, height: 40)
            Text(initialsFor(atom.title))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.entitySwipe)
        }
    }

    private var competitorBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.fill")
                .font(.system(size: 8))
            Text("Tracked")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(DS.entitySwipe)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(DS.entitySwipe.opacity(0.12), in: Capsule())
    }

    private func platformBadge(_ platform: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: platformIconFor(platform))
                .font(.system(size: 9))
            Text(platformNameFor(platform))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(DS.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.surfaceHover, in: Capsule())
    }

    private func statItem(value: String, label: String, valueColor: Color = DS.text) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(DS.textMuted)
        }
    }

    @ViewBuilder
    private func narrativeBadges(_ narratives: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(narratives.prefix(3), id: \.self) { raw in
                if let style = NarrativeStyle(rawValue: raw) {
                    Text(style.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(style.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(style.color.opacity(0.15), in: Capsule())
                }
            }
        }
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
        if count >= 1_000_000 { return "\(count / 1_000_000)M" }
        if count >= 1_000 { return "\(count / 1_000)K" }
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
