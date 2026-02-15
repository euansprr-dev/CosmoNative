// CosmoOS/UI/CommandK/SwipeGalleryTab.swift
// Swipe Gallery tab for Command-K overlay
// Gold-accented gallery of captured swipe files with cards, grouping, and filters

import SwiftUI

// MARK: - SwipeGalleryTab

/// Main gallery view shown when the Swipe Gallery tab is active in Command-K
struct SwipeGalleryTab: View {

    @ObservedObject var viewModel: CommandKViewModel
    let searchQuery: String

    // Stagger animation trigger
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            // Void background
            Color(hex: "#0A0A0F")

            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Collection stats
                        if !viewModel.swipeGalleryItems.isEmpty {
                            collectionStatsRow
                                .padding(.top, 4)
                        }

                        // Swipe-specific filter chips
                        swipeFilterChips
                            .padding(.top, 8)

                        // Content: grouped or flat
                        if viewModel.swipeGrouping == .recent || viewModel.swipeGrouping == .score {
                            // Flat list as horizontal scroll
                            flatGallerySection
                        } else {
                            // Grouped sections
                            ForEach(Array(groupedItems.enumerated()), id: \.element.name) { groupIndex, group in
                                SwipeGroupSection(title: group.name, count: group.items.count) {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(spacing: 16) {
                                            ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, item in
                                                SwipeGalleryCard(
                                                    item: item,
                                                    appearDelay: Double(groupIndex * 4 + itemIndex) * 0.04,
                                                    hasAppeared: hasAppeared
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 24)
                                    }
                                    .frame(height: 260)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear {
            if viewModel.swipeGalleryItems.isEmpty {
                Task {
                    await viewModel.loadSwipeGallery()
                }
            }
            withAnimation(ProMotionSprings.gentle) {
                hasAppeared = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("swipeDeleted"))) { notification in
            if let uuid = notification.userInfo?["uuid"] as? String {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.swipeGalleryItems.removeAll { $0.atomUUID == uuid }
                }
            }
        }
    }

    // MARK: - Filtered Items

    private var filteredItems: [SwipeGalleryItem] {
        var items = viewModel.swipeGalleryItems

        // Apply search filter
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

        // Apply platform filter
        if let platformFilter = viewModel.swipePlatformFilter {
            items = items.filter { $0.platformName == platformFilter }
        }

        // Apply hook type filter
        if let hookFilter = viewModel.swipeHookTypeFilter {
            items = items.filter { $0.hookType == hookFilter }
        }

        // Apply narrative style filter (multi-select intersection)
        if !viewModel.swipeNarrativeFilters.isEmpty {
            items = items.filter { item in
                guard let narrative = item.primaryNarrative else { return false }
                return viewModel.swipeNarrativeFilters.contains(narrative)
            }
        }

        // Apply content format filter (multi-select intersection)
        if !viewModel.swipeContentFormatFilters.isEmpty {
            items = items.filter { item in
                guard let format = item.swipeContentFormat else { return false }
                return viewModel.swipeContentFormatFilters.contains(format)
            }
        }

        // Apply niche filter
        if let nicheFilter = viewModel.swipeNicheFilter {
            items = items.filter { $0.niche == nicheFilter }
        }

        // Apply creator filter
        if let creatorFilter = viewModel.swipeCreatorFilter {
            items = items.filter { $0.creatorName == creatorFilter }
        }

        // Apply sort
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

    // MARK: - Collection Stats

    private var totalSwipeCount: Int {
        viewModel.swipeGalleryItems.count
    }

    private var averageHookScore: Double? {
        let scores = viewModel.swipeGalleryItems.compactMap(\.hookScore)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private var topHookType: SwipeHookType? {
        let types = viewModel.swipeGalleryItems.compactMap(\.hookType)
        let counts = Dictionary(types.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private var blindSpotHookType: SwipeHookType? {
        let presentTypes = Set(viewModel.swipeGalleryItems.compactMap(\.hookType))
        return SwipeHookType.allCases.first { !presentTypes.contains($0) }
    }

    private var averageScoreColor: Color {
        guard let score = averageHookScore else { return Color(hex: "#64748B") }
        if score >= 8.0 { return Color(hex: "#10B981") }  // Green
        if score >= 5.0 { return Color(hex: "#3B82F6") }  // Blue
        return Color(hex: "#64748B")                        // Slate
    }

    private var collectionStatsRow: some View {
        HStack(spacing: 16) {
            // Total count
            HStack(spacing: 4) {
                Text("\(totalSwipeCount)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))
                Text("swipes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 20)

            // Average score
            if let avg = averageHookScore {
                HStack(spacing: 4) {
                    Text("Avg")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Text(String(format: "%.1f", avg))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(averageScoreColor)
                }

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 20)
            }

            // Top hook type
            if let topHook = topHookType {
                HStack(spacing: 5) {
                    Image(systemName: topHook.iconName)
                        .font(.system(size: 10))
                    Text(topHook.displayName)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(topHook.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(topHook.color.opacity(0.15))
                )

                // Divider (only if blind spot follows)
                if blindSpotHookType != nil {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 20)
                }
            }

            // Blind spot
            if let blindSpot = blindSpotHookType {
                HStack(spacing: 4) {
                    Text("Gap:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#FFD700").opacity(0.5))
                    Text(blindSpot.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#FFD700").opacity(0.5))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .strokeBorder(
                            Color(hex: "#FFD700").opacity(0.3),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
            }

            Spacer()

            // Creators button
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
                creatorsButtonLabel
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(height: 44)
        .background(Color(hex: "#0A0A0F"))
    }

    @ViewBuilder
    private var creatorsButtonLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "person.crop.rectangle.fill")
                .font(.system(size: 10))
            Text("Creators")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(Color(hex: "#FFD700"))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(hex: "#FFD700").opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(Color(hex: "#FFD700").opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Grouped Items

    private var groupedItems: [(name: String, items: [SwipeGalleryItem])] {
        let items = filteredItems

        switch viewModel.swipeGrouping {
        case .narrativeStyle:
            var groups: [NarrativeStyle: [SwipeGalleryItem]] = [:]
            var ungrouped: [SwipeGalleryItem] = []
            for item in items {
                if let narrative = item.primaryNarrative {
                    groups[narrative, default: []].append(item)
                } else {
                    ungrouped.append(item)
                }
            }
            var result = groups.map { (name: $0.key.displayName, items: $0.value) }
            result.sort { $0.items.count > $1.items.count }
            if !ungrouped.isEmpty {
                result.append((name: "Unclassified", items: ungrouped))
            }
            return result

        case .contentType:
            var groups: [ContentFormat: [SwipeGalleryItem]] = [:]
            var ungrouped: [SwipeGalleryItem] = []
            for item in items {
                if let format = item.swipeContentFormat {
                    groups[format, default: []].append(item)
                } else {
                    ungrouped.append(item)
                }
            }
            var result = groups.map { (name: $0.key.displayName, items: $0.value) }
            result.sort { $0.items.count > $1.items.count }
            if !ungrouped.isEmpty {
                result.append((name: "Unclassified", items: ungrouped))
            }
            return result

        case .hookType:
            var groups: [SwipeHookType: [SwipeGalleryItem]] = [:]
            var ungrouped: [SwipeGalleryItem] = []
            for item in items {
                if let hookType = item.hookType {
                    groups[hookType, default: []].append(item)
                } else {
                    ungrouped.append(item)
                }
            }
            var result = groups.map { (name: $0.key.displayName, items: $0.value) }
            result.sort { $0.items.count > $1.items.count }
            if !ungrouped.isEmpty {
                result.append((name: "Uncategorized", items: ungrouped))
            }
            return result

        case .platform:
            var groups: [String: [SwipeGalleryItem]] = [:]
            for item in items {
                let key = item.platformName
                groups[key, default: []].append(item)
            }
            var result = groups.map { (name: $0.key, items: $0.value) }
            result.sort { $0.items.count > $1.items.count }
            return result

        case .creator:
            var groups: [String: [SwipeGalleryItem]] = [:]
            var ungrouped: [SwipeGalleryItem] = []
            for item in items {
                if let name = item.creatorName, !name.isEmpty {
                    groups[name, default: []].append(item)
                } else {
                    ungrouped.append(item)
                }
            }
            var result = groups.map { (name: $0.key, items: $0.value) }
            result.sort { $0.items.count > $1.items.count }
            if !ungrouped.isEmpty {
                result.append((name: "Unknown Creator", items: ungrouped))
            }
            return result

        case .niche:
            var groups: [String: [SwipeGalleryItem]] = [:]
            var ungrouped: [SwipeGalleryItem] = []
            for item in items {
                if let niche = item.niche, !niche.isEmpty {
                    groups[niche, default: []].append(item)
                } else {
                    ungrouped.append(item)
                }
            }
            var result = groups.map { (name: $0.key, items: $0.value) }
            result.sort { $0.items.count > $1.items.count }
            if !ungrouped.isEmpty {
                result.append((name: "No Niche", items: ungrouped))
            }
            return result

        case .recent, .score:
            return [(name: "All Swipes", items: items)]
        }
    }

    // MARK: - Flat Gallery Section

    private var flatGallerySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                    SwipeGalleryCard(
                        item: item,
                        appearDelay: Double(index) * 0.04,
                        hasAppeared: hasAppeared
                    )
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 260)
    }

    // MARK: - Swipe Filter Chips

    private var swipeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Platform filters
                swipeChip(title: "All", isSelected: viewModel.swipePlatformFilter == nil) {
                    viewModel.swipePlatformFilter = nil
                }

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 24)

                swipeChip(title: "YouTube", isSelected: viewModel.swipePlatformFilter == "YouTube") {
                    viewModel.swipePlatformFilter = viewModel.swipePlatformFilter == "YouTube" ? nil : "YouTube"
                }
                swipeChip(title: "Instagram", isSelected: viewModel.swipePlatformFilter == "Instagram") {
                    viewModel.swipePlatformFilter = viewModel.swipePlatformFilter == "Instagram" ? nil : "Instagram"
                }
                swipeChip(title: "X", isSelected: viewModel.swipePlatformFilter == "X") {
                    viewModel.swipePlatformFilter = viewModel.swipePlatformFilter == "X" ? nil : "X"
                }
                swipeChip(title: "Threads", isSelected: viewModel.swipePlatformFilter == "Threads") {
                    viewModel.swipePlatformFilter = viewModel.swipePlatformFilter == "Threads" ? nil : "Threads"
                }
                swipeChip(title: "Website", isSelected: viewModel.swipePlatformFilter == "Website") {
                    viewModel.swipePlatformFilter = viewModel.swipePlatformFilter == "Website" ? nil : "Website"
                }

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 24)

                // Hook type dropdown
                hookTypeMenu

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 24)

                // Sort mode
                sortMenu

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 24)

                // Grouping
                groupingMenu

                // Narrative filter (if any narratives exist)
                if !viewModel.swipeGalleryItems.compactMap(\.primaryNarrative).isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 24)

                    narrativeFilterMenu
                }

                // Content format filter
                if !viewModel.swipeGalleryItems.compactMap(\.swipeContentFormat).isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 24)

                    contentFormatFilterMenu
                }

                // Niche filter
                if !viewModel.availableNiches.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 24)

                    nicheFilterMenu
                }

                // Creator filter
                if !viewModel.availableCreators.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 24)

                    creatorFilterMenu
                }

                // Active filter count / clear
                if hasActiveFilters {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 24)

                    clearFiltersButton
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 52)
    }

    private var hasActiveFilters: Bool {
        !viewModel.swipeNarrativeFilters.isEmpty ||
        !viewModel.swipeContentFormatFilters.isEmpty ||
        viewModel.swipeNicheFilter != nil ||
        viewModel.swipeCreatorFilter != nil ||
        viewModel.swipePlatformFilter != nil ||
        viewModel.swipeHookTypeFilter != nil
    }

    private var clearFiltersButton: some View {
        Button {
            viewModel.swipeNarrativeFilters.removeAll()
            viewModel.swipeContentFormatFilters.removeAll()
            viewModel.swipeNicheFilter = nil
            viewModel.swipeCreatorFilter = nil
            viewModel.swipePlatformFilter = nil
            viewModel.swipeHookTypeFilter = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                Text("Clear")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Color(hex: "#FFD700").opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "#FFD700").opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private var narrativeFilterMenu: some View {
        Menu {
            ForEach(NarrativeStyle.allCases, id: \.rawValue) { style in
                Button {
                    toggleNarrativeFilter(style)
                } label: {
                    narrativeMenuLabel(style)
                }
            }
        } label: {
            narrativeFilterMenuLabel
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private func narrativeMenuLabel(_ style: NarrativeStyle) -> some View {
        let isSelected = viewModel.swipeNarrativeFilters.contains(style)
        HStack {
            Image(systemName: style.icon)
            Text(style.displayName)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var narrativeFilterMenuLabel: some View {
        let active = !viewModel.swipeNarrativeFilters.isEmpty
        return HStack(spacing: 4) {
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 10))
            Text(active ? "\(viewModel.swipeNarrativeFilters.count) Narrative\(viewModel.swipeNarrativeFilters.count > 1 ? "s" : "")" : "Narrative")
                .font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(active ? .white : .white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(active ? Color(hex: "#FFD700").opacity(0.25) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            active ? Color(hex: "#FFD700").opacity(0.6) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        )
    }

    private func toggleNarrativeFilter(_ style: NarrativeStyle) {
        if viewModel.swipeNarrativeFilters.contains(style) {
            viewModel.swipeNarrativeFilters.remove(style)
        } else {
            viewModel.swipeNarrativeFilters.insert(style)
        }
    }

    private var contentFormatFilterMenu: some View {
        Menu {
            ForEach(ContentFormat.allCases, id: \.rawValue) { format in
                Button {
                    toggleContentFormatFilter(format)
                } label: {
                    formatMenuLabel(format)
                }
            }
        } label: {
            contentFormatFilterMenuLabel
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private func formatMenuLabel(_ format: ContentFormat) -> some View {
        let isSelected = viewModel.swipeContentFormatFilters.contains(format)
        HStack {
            Image(systemName: format.icon)
            Text(format.displayName)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var contentFormatFilterMenuLabel: some View {
        let active = !viewModel.swipeContentFormatFilters.isEmpty
        return HStack(spacing: 4) {
            Image(systemName: "rectangle.split.3x1.fill")
                .font(.system(size: 10))
            Text(active ? "\(viewModel.swipeContentFormatFilters.count) Format\(viewModel.swipeContentFormatFilters.count > 1 ? "s" : "")" : "Format")
                .font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(active ? .white : .white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(active ? Color(hex: "#FFD700").opacity(0.25) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            active ? Color(hex: "#FFD700").opacity(0.6) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        )
    }

    private func toggleContentFormatFilter(_ format: ContentFormat) {
        if viewModel.swipeContentFormatFilters.contains(format) {
            viewModel.swipeContentFormatFilters.remove(format)
        } else {
            viewModel.swipeContentFormatFilters.insert(format)
        }
    }

    private var nicheFilterMenu: some View {
        Menu {
            Button("All Niches") {
                viewModel.swipeNicheFilter = nil
            }
            Divider()
            ForEach(viewModel.availableNiches, id: \.self) { niche in
                Button(niche) {
                    viewModel.swipeNicheFilter = viewModel.swipeNicheFilter == niche ? nil : niche
                }
            }
        } label: {
            nicheFilterMenuLabel
        }
        .menuStyle(.borderlessButton)
    }

    private var nicheFilterMenuLabel: some View {
        let active = viewModel.swipeNicheFilter != nil
        return HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.system(size: 10))
            Text(viewModel.swipeNicheFilter ?? "Niche")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(active ? .white : .white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(active ? Color(hex: "#FFD700").opacity(0.25) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            active ? Color(hex: "#FFD700").opacity(0.6) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        )
    }

    private var creatorFilterMenu: some View {
        Menu {
            Button("All Creators") {
                viewModel.swipeCreatorFilter = nil
            }
            Divider()
            ForEach(viewModel.availableCreators, id: \.name) { creator in
                Button(creator.name) {
                    viewModel.swipeCreatorFilter = viewModel.swipeCreatorFilter == creator.name ? nil : creator.name
                }
            }
        } label: {
            creatorFilterMenuLabel
        }
        .menuStyle(.borderlessButton)
    }

    private var creatorFilterMenuLabel: some View {
        let active = viewModel.swipeCreatorFilter != nil
        return HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.system(size: 10))
            Text(viewModel.swipeCreatorFilter ?? "Creator")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(active ? .white : .white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(active ? Color(hex: "#FFD700").opacity(0.25) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            active ? Color(hex: "#FFD700").opacity(0.6) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        )
    }

    private func swipeChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color(hex: "#FFD700").opacity(0.25) : Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isSelected ? Color(hex: "#FFD700").opacity(0.6) : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var hookTypeMenu: some View {
        Menu {
            Button("All Hook Types") {
                viewModel.swipeHookTypeFilter = nil
            }
            Divider()
            ForEach(SwipeHookType.allCases, id: \.rawValue) { hookType in
                Button(hookType.displayName) {
                    viewModel.swipeHookTypeFilter = viewModel.swipeHookTypeFilter == hookType ? nil : hookType
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                Text(viewModel.swipeHookTypeFilter?.displayName ?? "Hook Type")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(viewModel.swipeHookTypeFilter != nil ? .white : .white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(viewModel.swipeHookTypeFilter != nil ? Color(hex: "#FFD700").opacity(0.25) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                viewModel.swipeHookTypeFilter != nil ? Color(hex: "#FFD700").opacity(0.6) : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SwipeSortMode.allCases, id: \.self) { mode in
                Button(mode.displayName) {
                    viewModel.swipeSortMode = mode
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.swipeSortMode.displayName)
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
        .menuStyle(.borderlessButton)
    }

    private var groupingMenu: some View {
        Menu {
            ForEach(SwipeGrouping.allCases, id: \.self) { mode in
                Button(mode.displayName) {
                    viewModel.swipeGrouping = mode
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 10))
                Text(viewModel.swipeGrouping.displayName)
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
        .menuStyle(.borderlessButton)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: "#FFD700").opacity(0.3))

            Text("No swipes yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            Text("Press \u{2318}\u{21E7}S to capture your first swipe")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
        }
    }
}

// MARK: - SwipeGalleryCard

private struct SwipeGalleryCard: View {

    let item: SwipeGalleryItem
    let appearDelay: Double
    let hasAppeared: Bool

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var showDeleteAlert = false

    private let cardWidth: CGFloat = 170
    private let cardHeight: CGFloat = 250
    private let gold = Color(hex: "#FFD700")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail area (60% height)
            thumbnailSection
                .frame(height: cardHeight * 0.6)
                .clipped()

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                // Hook text
                Text(item.hookText ?? item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Author + platform
                HStack(spacing: 4) {
                    if let author = item.author {
                        Text("@\(author)")
                    }
                    if item.author != nil {
                        Text("\u{00B7}")
                    }
                    Text(item.platformName)
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
            }

            // Bottom row: hook type pill + score
            HStack(spacing: 6) {
                if let hookType = item.hookType {
                    hookTypePill(hookType)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 2)

                if let score = item.hookScore {
                    scoreCircle(score)
                }
            }
            .frame(width: cardWidth - 20)

            // Taxonomy badges row
            taxonomyBadgesRow
        }
        .padding(10)
        .frame(width: cardWidth, height: cardHeight)
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
            color: isHovered ? gold.opacity(0.15) : .clear,
            radius: isHovered ? 12 : 0,
            y: isHovered ? 4 : 0
        )
        .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.03 : 1.0))
        .opacity(hasAppeared ? 1.0 : 0.0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(
            ProMotionSprings.snappy.delay(appearDelay),
            value: hasAppeared
        )
        .animation(ProMotionSprings.hover, value: isHovered)
        .animation(ProMotionSprings.press, value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            // Open in focus mode
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.research, "id": item.entityId]
            )
            // Close Command-K
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.closeCommandK,
                object: nil
            )
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            isPressed = pressing
        }) {
            // Add to canvas
            NotificationCenter.default.post(
                name: Notification.Name("addSwipeToCanvas"),
                object: nil,
                userInfo: ["atomUUID": item.atomUUID]
            )
        }
        .contextMenu {
            Button {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": EntityType.research, "id": item.entityId]
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
        .alert("Delete Swipe?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    try? await SwipeFileEngine.shared.deleteSwipe(atomUUID: item.atomUUID)
                }
            }
        } message: {
            Text("This will permanently remove this swipe file.")
        }
    }

    // MARK: - Thumbnail

    private var thumbnailSection: some View {
        ZStack {
            // Background gradient placeholder
            LinearGradient(
                colors: [Color(hex: "#1A1A25"), Color(hex: "#12121A")],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Thumbnail image or platform icon
            if let thumbnailUrl = item.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cardWidth - 20, height: cardHeight * 0.6)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .transition(.opacity.animation(ProMotionSprings.gentle))
                    default:
                        platformIconPlaceholder
                    }
                }
            } else {
                platformIconPlaceholder
            }

            // Platform badge (top-left)
            VStack {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: item.platformIcon)
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                    )

                    Spacer()
                }
                Spacer()

                // Duration badge (bottom-right)
                if let duration = item.duration, duration > 0 {
                    HStack {
                        Spacer()
                        Text(formatDuration(duration))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                    }
                }
            }
            .padding(6)
        }
        .frame(width: cardWidth - 20, height: cardHeight * 0.6)
        .clipped()
    }

    private var platformIconPlaceholder: some View {
        Image(systemName: item.platformIcon)
            .font(.system(size: 28))
            .foregroundColor(.white.opacity(0.15))
    }

    // MARK: - Hook Type Pill

    private func hookTypePill(_ hookType: SwipeHookType) -> some View {
        HStack(spacing: 3) {
            Image(systemName: hookType.iconName)
                .font(.system(size: 8))
            Text(hookType.displayName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(hookType.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(hookType.color.opacity(0.2))
        )
        .lineLimit(1)
    }

    // MARK: - Score Circle

    private func scoreCircle(_ score: Double) -> some View {
        ZStack {
            Circle()
                .strokeBorder(item.scoreColor, lineWidth: 2)
                .frame(width: 24, height: 24)

            Text(String(format: "%.1f", score))
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundColor(item.scoreColor)
        }
    }

    // MARK: - Taxonomy Badges

    @ViewBuilder
    private var taxonomyBadgesRow: some View {
        let hasAnyTaxonomy = item.primaryNarrative != nil ||
            item.swipeContentFormat != nil ||
            item.creatorName != nil ||
            item.niche != nil

        if hasAnyTaxonomy {
            HStack(spacing: 4) {
                if let narrative = item.primaryNarrative {
                    taxonomyBadge(narrative.displayName, color: narrative.color)
                }
                if let format = item.swipeContentFormat {
                    taxonomyBadge(format.displayName, color: format.color)
                }
                Spacer(minLength: 0)
            }
            .frame(width: cardWidth - 20)

            if item.creatorName != nil || item.niche != nil {
                HStack(spacing: 4) {
                    if let creator = item.creatorName {
                        Text(creator)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    if let niche = item.niche {
                        Text(niche)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(gold.opacity(0.5))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: cardWidth - 20)
            }
        }
    }

    private func taxonomyBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .lineLimit(1)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - SwipeGroupSection

private struct SwipeGroupSection<Content: View>: View {

    let title: String
    let count: Int
    let content: () -> Content

    init(title: String, count: Int, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))

                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#FFD700").opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(hex: "#FFD700").opacity(0.15))
                    )

                Spacer()
            }
            .padding(.horizontal, 24)

            // Content
            content()
        }
    }
}
