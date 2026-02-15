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
        case .swipeCount: return "Swipe Count"
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

    // Derived unique values for filter chips
    private var allPlatforms: [String] {
        let values = creators.compactMap { $0.metadataValue(as: CreatorMetadata.self)?.platform }
        return Array(Set(values)).sorted()
    }

    private var allNiches: [String] {
        let values = creators.compactMap { $0.metadataValue(as: CreatorMetadata.self)?.niche }
        return Array(Set(values)).sorted()
    }

    private let gold = Color(hex: "#FFD700")

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0F").ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                Divider().background(Color.white.opacity(0.1))
                filterRow
                Divider().background(Color.white.opacity(0.1))

                if isLoading {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else if filteredCreators.isEmpty {
                    emptyState
                } else {
                    creatorGrid
                }
            }
        }
        .onAppear {
            loadCreators()
            withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            Image(systemName: "person.crop.rectangle.fill")
                .font(.system(size: 14))
                .foregroundColor(gold)

            Text("Creators")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Text("\(creators.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(gold.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(gold.opacity(0.15), in: Capsule())

            Spacer()

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                TextField("Search creators...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 240)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )

            // Compare button
            Button {
                onCompare(filteredCreators)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11))
                    Text("Compare")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(gold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(gold.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(gold.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Filter Row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Sort menu
                sortMenuView

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 24)

                // Platform filters
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
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 24)

                    // Niche filters
                    nicheMenuView
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 52)
        .background(Color(hex: "#0A0A0F"))
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
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
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
        .foregroundColor(nicheFilter != nil ? .white : .white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(nicheFilter != nil ? gold.opacity(0.25) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            nicheFilter != nil ? gold.opacity(0.6) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        )
    }

    private func filterChip(title: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? gold.opacity(0.25) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? gold.opacity(0.6) : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered + Sorted Creators

    private var filteredCreators: [Atom] {
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

        // Sort
        switch sortMode {
        case .name:
            items.sort { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
        case .swipeCount:
            items.sort {
                ($0.metadataValue(as: CreatorMetadata.self)?.swipeCount ?? 0)
                > ($1.metadataValue(as: CreatorMetadata.self)?.swipeCount ?? 0)
            }
        case .hookScore:
            items.sort {
                ($0.metadataValue(as: CreatorMetadata.self)?.averageHookScore ?? 0)
                > ($1.metadataValue(as: CreatorMetadata.self)?.averageHookScore ?? 0)
            }
        }

        return items
    }

    // MARK: - Creator Grid

    private var creatorGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)],
                spacing: 16
            ) {
                ForEach(Array(filteredCreators.enumerated()), id: \.element.uuid) { index, atom in
                    CreatorCard(
                        atom: atom,
                        appearDelay: Double(index) * 0.04,
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
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.rectangle.fill")
                .font(.system(size: 48))
                .foregroundColor(gold.opacity(0.3))
            Text(searchText.isEmpty ? "No creators yet" : "No matching creators")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("Creators are auto-detected when you save swipe files")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
        }
    }

    // MARK: - Data Loading

    private func loadCreators() {
        Task {
            isLoading = true
            let fetched = try? await AtomRepository.shared.fetchCreators()
            creators = fetched ?? []
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

    private let gold = Color(hex: "#FFD700")
    private let cardWidth: CGFloat = 260

    private var meta: CreatorMetadata? {
        atom.metadataValue(as: CreatorMetadata.self)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Avatar + name row
            HStack(spacing: 12) {
                avatarCircle
                VStack(alignment: .leading, spacing: 2) {
                    Text(atom.title ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let handle = meta?.handle {
                        Text(handle)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer()
                if meta?.isActive == true {
                    competitorBadge
                }
            }

            // Platform + niche row
            HStack(spacing: 8) {
                if let platform = meta?.platform {
                    platformBadge(platform)
                }
                if let niche = meta?.niche, !niche.isEmpty {
                    Text(niche)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
            }

            Divider().background(Color.white.opacity(0.08))

            // Stats row
            HStack(spacing: 12) {
                statItem(value: "\(meta?.swipeCount ?? 0)", label: "Swipes")
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

            // Top narratives
            if let narratives = meta?.topNarratives, !narratives.isEmpty {
                narrativeBadges(narratives)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "#1A1A25"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHovered ? gold.opacity(0.3) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isHovered ? gold.opacity(0.12) : .clear,
            radius: isHovered ? 10 : 0,
            y: isHovered ? 3 : 0
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

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(gold.opacity(0.15))
                .frame(width: 40, height: 40)
            Text(initialsFor(atom.title))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(gold)
        }
    }

    private var competitorBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.fill")
                .font(.system(size: 8))
            Text("Tracked")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(gold)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(gold.opacity(0.12), in: Capsule())
    }

    private func platformBadge(_ platform: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: platformIconFor(platform))
                .font(.system(size: 9))
            Text(platformNameFor(platform))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func statItem(value: String, label: String, valueColor: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundColor(valueColor)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    @ViewBuilder
    private func narrativeBadges(_ narratives: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(narratives.prefix(3), id: \.self) { raw in
                if let style = NarrativeStyle(rawValue: raw) {
                    Text(style.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(style.color)
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
        guard let score = score else { return Color(hex: "#64748B") }
        if score >= 8.0 { return Color(hex: "#10B981") }
        if score >= 5.0 { return Color(hex: "#3B82F6") }
        return Color(hex: "#64748B")
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
