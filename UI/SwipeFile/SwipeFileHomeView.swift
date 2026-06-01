import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct SwipeFileHomeView: View {
    @ObservedObject var viewModel: SwipeLibraryViewModel
    let section: SwipeLibrarySectionSelection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : ProMotionSprings.snappy
    }

    var body: some View {
        GeometryReader { geometry in
            let showsInspector = geometry.size.width >= 1180

            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        SwipeFileMasthead(
                            section: section,
                            summary: viewModel.summary,
                            query: $viewModel.query,
                            displayMode: $viewModel.displayMode,
                            sortMode: $viewModel.sortMode,
                            onReload: { Task { await viewModel.reload() } }
                        )

                        SwipeSmartPresetStrip(viewModel: viewModel)
                        SwipeFilterBar(viewModel: viewModel)

                        if viewModel.isLoading && viewModel.visibleItems.isEmpty {
                            SwipeFileLoadingState()
                                .frame(maxWidth: .infinity, minHeight: 360)
                        } else if let error = viewModel.errorMessage {
                            SwipeFileEmptyState(
                                title: "Swipe File unavailable",
                                subtitle: error,
                                systemImage: "exclamationmark.triangle"
                            )
                            .frame(maxWidth: .infinity, minHeight: 360)
                        } else if viewModel.visibleItems.isEmpty {
                            SwipeFileEmptyState(
                                title: "No matching swipes",
                                subtitle: "Clear a filter or search another style.",
                                systemImage: "rectangle.stack.badge.minus"
                            )
                            .frame(maxWidth: .infinity, minHeight: 360)
                        } else {
                            if section != .all {
                                SwipeShelfStack(
                                    shelves: viewModel.shelves,
                                    selectedItem: viewModel.selectedItem,
                                    onSelect: { viewModel.selectedItem = $0 },
                                    onOpen: viewModel.openStudy
                                )
                            }

                            SwipeLibraryResultsSection(
                                mode: viewModel.displayMode,
                                items: viewModel.visibleItems,
                                selectedItem: viewModel.selectedItem,
                                onSelect: { viewModel.selectedItem = $0 },
                                onOpen: viewModel.openStudy,
                                onAddToCanvas: viewModel.addToCanvas
                            )
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 30)
                    .padding(.bottom, 48)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsInspector {
                    ZStack(alignment: .top) {
                        SwipeFileDetailPreview(
                            item: viewModel.selectedItem,
                            onOpen: viewModel.openStudy,
                            onAddToCanvas: viewModel.addToCanvas
                        )
                        .frame(width: 304)
                        .padding(.top, 28)
                        .padding(.bottom, 28)
                        .padding(.trailing, 24)
                    }
                    .frame(width: 340)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .trailing)))
                }
            }
            .background(SwipeFileBackground())
            .animation(motion, value: viewModel.displayMode)
            .animation(motion, value: viewModel.visibleItems.map(\.id))
            .task(id: section) {
                await viewModel.loadIfNeeded(section: section)
            }
            .onChange(of: section) { _, newSection in
                viewModel.setSection(newSection)
            }
        }
    }
}

private struct SwipeFileMasthead: View {
    let section: SwipeLibrarySectionSelection
    let summary: SwipeLibraryFacetSummary
    @Binding var query: String
    @Binding var displayMode: SwipeLibraryMode
    @Binding var sortMode: SwipeSortMode
    var onReload: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Swipe File")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(section.title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 18)

                HStack(spacing: 10) {
                    SwipeLibraryModePicker(selection: $displayMode)

                    Menu {
                        ForEach(SwipeSortMode.allCases, id: \.rawValue) { mode in
                            Button {
                                sortMode = mode
                            } label: {
                                Label(mode.displayName, systemImage: sortMode == mode ? "checkmark" : "arrow.up.arrow.down")
                            }
                        }
                    } label: {
                        Label(sortMode.displayName, systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .menuStyle(.button)

                    Button("Reload", systemImage: "arrow.clockwise", action: onReload)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(DS.borderSubtle, lineWidth: 0.75))
                        .buttonStyle(.plain)
                        .help("Reload Swipe File")
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(searchFocused ? DS.accent : DS.textMuted)

                    TextField("Search hooks, creators, formats, niches...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.text)
                        .focused($searchFocused)

                    if !query.isEmpty {
                        Button("Clear", systemImage: "xmark.circle.fill") {
                            query = ""
                        }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(searchFocused ? DS.borderActive : DS.borderSubtle, lineWidth: 1)
                )

                SwipeMetricTile(title: "Visible", value: "\(summary.filteredCount)", systemImage: "square.grid.2x2")
                SwipeMetricTile(title: "High", value: "\(summary.highScoreCount)", systemImage: "chart.line.uptrend.xyaxis")
                SwipeMetricTile(title: "Unstudied", value: "\(summary.unstudiedCount)", systemImage: "circle.dotted")
                SwipeMetricTile(
                    title: "Avg",
                    value: summary.averageHookScore.map { String(format: "%.1f", $0) } ?? "-",
                    systemImage: "gauge.with.dots.needle.67percent"
                )
            }
        }
    }
}

private struct SwipeLibraryModePicker: View {
    @Binding var selection: SwipeLibraryMode

    var body: some View {
        HStack(spacing: 3) {
            ForEach(SwipeLibraryMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == mode ? DS.accent : DS.textMuted)
                        .frame(width: 30, height: 30)
                        .background(selection == mode ? DS.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(mode.title)
            }
        }
        .padding(2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 0.75))
    }
}

private struct SwipeMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 24, height: 24)
                .background(DS.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.text)
                    .monospacedDigit()
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .textCase(.uppercase)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 0.75)
        )
    }
}

private struct SwipeSmartPresetStrip: View {
    @ObservedObject var viewModel: SwipeLibraryViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SwipeLibrarySmartPreset.allCases) { preset in
                    SwipeFilterChip(
                        title: preset.title,
                        systemImage: preset.systemImage,
                        isSelected: viewModel.filterState.smartPreset == preset
                    ) {
                        viewModel.applySmartPreset(preset)
                    }
                }

                if viewModel.filterState.hasActiveFilters || !viewModel.query.isEmpty {
                    Button {
                        viewModel.resetFilters()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.textMuted)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(DS.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
    }
}

private struct SwipeFilterBar: View {
    @ObservedObject var viewModel: SwipeLibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(viewModel.availablePlatforms, id: \.self) { platform in
                        SwipeFilterChip(
                            title: viewModel.platformName(platform),
                            systemImage: platformIcon(platform),
                            isSelected: viewModel.filterState.platforms.contains(platform)
                        ) {
                            viewModel.togglePlatform(platform)
                        }
                    }

                    Menu {
                        Button("Any Creator") { viewModel.setCreator(nil) }
                        Divider()
                        ForEach(viewModel.availableCreators, id: \.self) { creator in
                            Button {
                                viewModel.setCreator(creator)
                            } label: {
                                Label(creator, systemImage: viewModel.filterState.creator == creator ? "checkmark" : "person")
                            }
                        }
                    } label: {
                        SwipeMenuLabel(
                            title: viewModel.filterState.creator ?? "Creator",
                            systemImage: "person.crop.circle",
                            isSelected: viewModel.filterState.creator != nil
                        )
                    }
                    .buttonStyle(.plain)
                    .menuStyle(.button)

                    Menu {
                        Button("Any Niche") { viewModel.setNiche(nil) }
                        Divider()
                        ForEach(viewModel.availableNiches, id: \.self) { niche in
                            Button {
                                viewModel.setNiche(niche)
                            } label: {
                                Label(niche, systemImage: viewModel.filterState.niche == niche ? "checkmark" : "tag")
                            }
                        }
                    } label: {
                        SwipeMenuLabel(
                            title: viewModel.filterState.niche ?? "Niche",
                            systemImage: "tag",
                            isSelected: viewModel.filterState.niche != nil
                        )
                    }
                    .buttonStyle(.plain)
                    .menuStyle(.button)
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(SwipeHookType.allCases, id: \.rawValue) { hookType in
                        SwipeFilterChip(
                            title: hookType.displayName,
                            systemImage: hookType.iconName,
                            isSelected: viewModel.filterState.hookTypes.contains(hookType),
                            tint: hookType.color
                        ) {
                            viewModel.toggleHookType(hookType)
                        }
                    }

                    Divider().frame(height: 18)

                    ForEach(NarrativeStyle.allCases, id: \.rawValue) { narrative in
                        SwipeFilterChip(
                            title: narrative.displayName,
                            systemImage: narrative.icon,
                            isSelected: viewModel.filterState.narratives.contains(narrative),
                            tint: narrative.color
                        ) {
                            viewModel.toggleNarrative(narrative)
                        }
                    }

                    Divider().frame(height: 18)

                    ForEach(ContentFormat.allCases, id: \.rawValue) { format in
                        SwipeFilterChip(
                            title: format.displayName,
                            systemImage: format.icon,
                            isSelected: viewModel.filterState.formats.contains(format),
                            tint: format.color
                        ) {
                            viewModel.toggleFormat(format)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
        }
    }

    private func platformIcon(_ platform: String) -> String {
        switch platform {
        case "youtube", "youtubeShort", "youtube_short": return "play.rectangle.fill"
        case "instagram", "instagramPost", "instagram_post", "instagramReel", "instagram_reel": return "camera.fill"
        case "instagramCarousel", "instagram_carousel": return "square.stack.fill"
        case "xPost", "x_post", "twitter": return "bubble.left.fill"
        case "threads": return "at"
        default: return "globe"
        }
    }
}

private struct SwipeFilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var tint: Color = DS.accent
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(DS.footnote.weight(.semibold))
                Text(title)
                    .font(DS.subheadline.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? tint : (isHovered ? DS.textSecondary : DS.textMuted))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(chipFill, in: Capsule())
            .overlay(Capsule().strokeBorder(chipStroke, lineWidth: isSelected ? 1 : 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.snappy, value: isSelected)
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var chipFill: Color {
        if isSelected { return tint.opacity(DS.palette.isDark ? 0.22 : 0.14) }
        return isHovered ? DS.glassInputFillFocused : DS.glassInputFill
    }

    private var chipStroke: Color {
        if isSelected { return tint.opacity(0.42) }
        return isHovered ? DS.glassBorderFocused : DS.glassBorder
    }
}

private struct SwipeMenuLabel: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(DS.footnote.weight(.semibold))
            Text(title)
                .font(DS.subheadline.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(DS.caption2.weight(.bold))
        }
        .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(isSelected ? DS.accentSoft : DS.glassInputFill, in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: isSelected ? 1 : 0.5))
    }
}

private struct SwipeShelfStack: View {
    let shelves: [SwipeLibraryShelf]
    let selectedItem: SwipeGalleryItem?
    var onSelect: (SwipeGalleryItem) -> Void
    var onOpen: (SwipeGalleryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(shelves) { shelf in
                if !shelf.items.isEmpty {
                    SwipeShelfSection(
                        shelf: shelf,
                        selectedItem: selectedItem,
                        onSelect: onSelect,
                        onOpen: onOpen
                    )
                }
            }
        }
    }
}

private struct SwipeShelfSection: View {
    let shelf: SwipeLibraryShelf
    let selectedItem: SwipeGalleryItem?
    var onSelect: (SwipeGalleryItem) -> Void
    var onOpen: (SwipeGalleryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shelf.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(DS.text)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(shelf.items) { item in
                        SwipeGalleryCardView(
                            item: item,
                            cardWidth: 214,
                            isSelected: selectedItem?.id == item.id
                        )
                        .frame(width: 214)
                        .onTapGesture { onSelect(item) }
                        .onTapGesture(count: 2) { onOpen(item) }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
    }
}

private struct SwipeLibraryResultsSection: View {
    let mode: SwipeLibraryMode
    let items: [SwipeGalleryItem]
    let selectedItem: SwipeGalleryItem?
    var onSelect: (SwipeGalleryItem) -> Void
    var onOpen: (SwipeGalleryItem) -> Void
    var onAddToCanvas: (SwipeGalleryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("All Matches")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(DS.text)

            switch mode {
            case .grid:
                SwipeMasonryGrid(
                    items: items,
                    selectedItem: selectedItem,
                    onSelect: onSelect,
                    onOpen: onOpen
                )
            case .clusters:
                SwipeClusteredView(
                    items: items,
                    selectedItem: selectedItem,
                    onSelect: onSelect,
                    onOpen: onOpen
                )
            case .compact:
                SwipeCompactList(
                    items: items,
                    selectedItem: selectedItem,
                    onSelect: onSelect,
                    onOpen: onOpen,
                    onAddToCanvas: onAddToCanvas
                )
            }
        }
    }
}

private struct SwipeMasonryGrid: View {
    let items: [SwipeGalleryItem]
    let selectedItem: SwipeGalleryItem?
    var onSelect: (SwipeGalleryItem) -> Void
    var onOpen: (SwipeGalleryItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            let columnCount = Self.columnCount(for: proxy.size.width)
            let spacing: CGFloat = 16
            let cardWidth = Self.cardWidth(
                containerWidth: proxy.size.width,
                columnCount: columnCount,
                spacing: spacing
            )
            let columns = distribute(items: items, columnCount: columnCount, cardWidth: cardWidth)

            HStack(alignment: .top, spacing: spacing) {
                ForEach(columns.indices, id: \.self) { columnIndex in
                    LazyVStack(spacing: spacing) {
                        ForEach(columns[columnIndex]) { item in
                            SwipeGalleryCardView(
                                item: item,
                                cardWidth: cardWidth,
                                isSelected: selectedItem?.id == item.id
                            )
                            .frame(width: cardWidth)
                            .contextMenu {
                                Button("Open Study", systemImage: "rectangle.expand.vertical") { onOpen(item) }
                            }
                            .onTapGesture { onSelect(item) }
                            .onTapGesture(count: 2) { onOpen(item) }
                        }
                    }
                }
            }
        }
        .frame(minHeight: estimatedHeight(items: items, width: 980))
    }

    private static func columnCount(for width: CGFloat) -> Int {
        guard width > 0 else { return 2 }
        let idealCardWidth: CGFloat = 236
        let spacing: CGFloat = 16
        return max(2, min(6, Int((width + spacing) / (idealCardWidth + spacing))))
    }

    private static func cardWidth(containerWidth: CGFloat, columnCount: Int, spacing: CGFloat) -> CGFloat {
        let rawWidth = (containerWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        return min(272, max(212, rawWidth))
    }

    private func distribute(items: [SwipeGalleryItem], columnCount: Int, cardWidth: CGFloat) -> [[SwipeGalleryItem]] {
        var columns = Array(repeating: [SwipeGalleryItem](), count: columnCount)
        var heights = Array(repeating: CGFloat.zero, count: columnCount)

        for item in items {
            let target = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[target].append(item)
            heights[target] += SwipeGalleryCardView.estimatedHeight(for: item, cardWidth: cardWidth) + 16
        }

        return columns
    }

    private func estimatedHeight(items: [SwipeGalleryItem], width: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 220 }
        let columnCount = max(2, min(5, Int(width / 260)))
        return CGFloat(items.count / columnCount + 2) * 330
    }
}

private struct SwipeClusteredView: View {
    let items: [SwipeGalleryItem]
    let selectedItem: SwipeGalleryItem?
    var onSelect: (SwipeGalleryItem) -> Void
    var onOpen: (SwipeGalleryItem) -> Void

    private var grouped: [FormatGroup: [SwipeGalleryItem]] {
        Dictionary(grouping: items) { FormatGroup.group(for: $0.swipeContentFormat) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(FormatGroup.allCases) { group in
                if let groupItems = grouped[group], !groupItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: group.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(group.color)
                            Text(group.displayName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(DS.text)
                            Text("\(groupItems.count)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.textMuted)
                                .monospacedDigit()
                        }

                        SwipeMasonryGrid(
                            items: groupItems,
                            selectedItem: selectedItem,
                            onSelect: onSelect,
                            onOpen: onOpen
                        )
                    }
                }
            }
        }
    }
}

private struct SwipeCompactList: View {
    let items: [SwipeGalleryItem]
    let selectedItem: SwipeGalleryItem?
    var onSelect: (SwipeGalleryItem) -> Void
    var onOpen: (SwipeGalleryItem) -> Void
    var onAddToCanvas: (SwipeGalleryItem) -> Void

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DS.entitySwipe.opacity(0.12))
                            .frame(width: 54, height: 54)
                            .overlay {
                                Image(systemName: item.platformIcon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(DS.entitySwipe)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.hookText ?? item.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DS.text)
                                .lineLimit(2)
                            Text([item.creatorName ?? item.author, item.platformName, item.niche].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DS.textMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        if let score = item.hookScore {
                            Text(String(format: "%.1f", score))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(item.scoreColor)
                                .monospacedDigit()
                        }

                        Button("Add to Canvas", systemImage: "plus.square.on.square") {
                            onAddToCanvas(item)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.textMuted)
                        .help("Add to Canvas")
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                    .background(
                        selectedItem?.id == item.id ? DS.accentSoft : DS.surface.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selectedItem?.id == item.id ? DS.accent.opacity(0.28) : DS.borderSubtle, lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
                .onTapGesture(count: 2) { onOpen(item) }
            }
        }
    }
}

private struct SwipeFileDetailPreview: View {
    let item: SwipeGalleryItem?
    var onOpen: (SwipeGalleryItem) -> Void
    var onAddToCanvas: (SwipeGalleryItem) -> Void

    var body: some View {
        CosmoGlassPanel(cornerRadius: 24) {
            Group {
                if let item {
                    selectedContent(item)
                } else {
                    SwipeFileEmptyState(
                        title: "Select a swipe",
                        subtitle: "Preview details here.",
                        systemImage: "sidebar.right"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func selectedContent(_ item: SwipeGalleryItem) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                SwipeGalleryCardView(item: item, cardWidth: 268, isSelected: true)
                    .frame(width: 268)
                    .accessibilityLabel("Selected swipe preview")

                VStack(alignment: .leading, spacing: 14) {
                    Text(item.hookText ?? item.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(DS.text)
                        .lineLimit(5)

                    VStack(alignment: .leading, spacing: 9) {
                        metadataRow("Creator", value: item.creatorName ?? item.author ?? "Unknown")
                        metadataRow("Platform", value: item.platformName)
                        if let niche = item.niche { metadataRow("Niche", value: niche) }
                        if let hookType = item.hookType { metadataRow("Hook", value: hookType.displayName) }
                        if let narrative = item.primaryNarrative { metadataRow("Narrative", value: narrative.displayName) }
                        if let score = item.hookScore { metadataRow("Hook Score", value: String(format: "%.1f", score)) }
                    }
                    .padding(12)
                    .background(DS.commandChromePanelFill, in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.commandChromeBorder, lineWidth: 0.5)
                    }
                }

                HStack(spacing: 8) {
                    Button("Open Study", systemImage: "rectangle.expand.vertical") {
                        onOpen(item)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Canvas", systemImage: "plus.square.on.square") {
                        onAddToCanvas(item)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Add to Canvas")
                    .accessibilityLabel("Add to Canvas")
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
        }
    }
}

private struct SwipeFileLoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading Swipe File")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
        }
    }
}

private struct SwipeFileEmptyState: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(DS.pageTitle)
                .foregroundStyle(DS.textMuted)
                .frame(width: 58, height: 58)
                .background(DS.glassInputFill, in: Circle())
                .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))

            Text(title)
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Text(subtitle)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

struct SwipeFileDiscoverView: View {
    let section: SwipeDiscoverySectionSelection
    @ObservedObject var swipeLibraryViewModel: SwipeLibraryViewModel

    @State private var viewModel = SwipeFileDiscoverViewModel()
    @State private var showingFilters = false
    @State private var filterAnchor: CGRect = .zero
    @State private var detailPost: SocialPostSnapshot?

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipeFileDiscoverContent(
                section: section,
                viewModel: viewModel,
                showingFilters: $showingFilters,
                onOpenPost: { post in
                    withAnimation(ProMotionSprings.gentle) { detailPost = post }
                }
            )

            if showingFilters {
                SwipeDiscoverFilterDropdown(
                    query: $viewModel.query,
                    anchor: filterAnchor,
                    onDismiss: { withAnimation(ProMotionSprings.bouncy) { showingFilters = false } }
                )
                .zIndex(10)
            }

            if let detailPost {
                SwipeDiscoverPostDetailOverlay(
                    post: detailPost,
                    onSave: viewModel.save,
                    onTranscript: { post in
                        Task {
                            await viewModel.saveAndOpenForTranscription(post)
                            withAnimation(ProMotionSprings.gentle) { self.detailPost = nil }
                        }
                    },
                    onClose: { withAnimation(ProMotionSprings.gentle) { self.detailPost = nil } }
                )
                .zIndex(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SwipeFileBackground())
        .coordinateSpace(name: "swipeDiscoverFilterRoot")
        .onPreferenceChange(FilterAnchorKey.self) { filterAnchor = $0 }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.SwipeFile.creatorDataChanged)) { _ in
            Task { await viewModel.reload() }
        }
    }
}

private struct SwipeFileDiscoverContent: View {
    let section: SwipeDiscoverySectionSelection
    @Bindable var viewModel: SwipeFileDiscoverViewModel
    @Binding var showingFilters: Bool
    let onOpenPost: (SocialPostSnapshot) -> Void

    @State private var selectedCreatorID: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                SwipeDiscoverHeader(
                    section: section,
                    query: $viewModel.query,
                    creatorSearchText: $viewModel.creatorSearchText,
                    isAddingCreator: viewModel.isAddingCreator,
                    isShowingFilters: $showingFilters,
                    onAddCreator: viewModel.addCreatorFromSearch,
                    onRefresh: { Task { await viewModel.refreshDiscovery() } }
                )

                SwipeDiscoverPillarStrip()
                SwipeDiscoverPlatformStrip(query: $viewModel.query)

                if section == .creators {
                    if let selectedCreatorID,
                       let creator = viewModel.creator(id: selectedCreatorID) {
                        SwipeDiscoverCreatorProfile(
                            creator: creator,
                            posts: viewModel.posts(for: creator),
                            onBack: { self.selectedCreatorID = nil },
                            onSave: viewModel.save,
                            onOpen: onOpenPost
                        )
                    } else {
                        SwipeDiscoverCreatorDirectory(
                            viewModel: viewModel,
                            onSelectCreator: { selectedCreatorID = $0.id }
                        )
                    }
                } else {
                    SwipeDiscoverFeed(viewModel: viewModel, onOpen: onOpenPost)
                }
            }
            .padding(36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: section) { _, _ in
            selectedCreatorID = nil
        }
    }
}

@MainActor
@Observable
private final class SwipeFileDiscoverViewModel {
    var query = SocialDiscoveryQuery()
    var creatorSearchText = ""
    var creatorSortMode: SocialDiscoverySort = .highestOutlier
    private(set) var posts: [SocialPostSnapshot] = []
    private(set) var creators: [SwipeDiscoverCreatorRecord] = []
    private(set) var isLoading = false
    private(set) var isAddingCreator = false
    var errorMessage: String?
    var saveMessage: String?
    var creatorImportMessage: String?
    var creatorImportError: String?

    private var hasLoaded = false
    private let remoteStore = SocialDiscoveryRemoteStore()
    private let localCache = SocialDiscoveryLocalCache()

    init() {
        restoreCachedDiscoveryIfAvailable()
    }

    var visiblePosts: [SocialPostSnapshot] {
        SocialDiscoveryStore(query: query, posts: posts).visiblePosts
    }

    var filteredCreators: [SwipeDiscoverCreatorRecord] {
        let trimmedQuery = creatorSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var filtered = creators
        if !trimmedQuery.isEmpty {
            filtered = filtered.filter {
                $0.name.lowercased().contains(trimmedQuery) ||
                $0.handle.lowercased().contains(trimmedQuery) ||
                ($0.niche?.lowercased().contains(trimmedQuery) ?? false)
            }
        }

        switch creatorSortMode {
        case .highestOutlier:
            filtered.sort { ($0.topOutlierMultiplier ?? 0) > ($1.topOutlierMultiplier ?? 0) }
        case .mostViewed:
            filtered.sort { $0.totalViews > $1.totalViews }
        case .mostLiked:
            filtered.sort { $0.totalLikes > $1.totalLikes }
        case .mostCommented:
            filtered.sort { $0.totalComments > $1.totalComments }
        case .mostShared:
            filtered.sort { $0.postCount > $1.postCount }
        case .newest:
            filtered.sort { ($0.latestPostDate ?? .distantPast) > ($1.latestPostDate ?? .distantPast) }
        }
        return filtered
    }

    func creator(id: String) -> SwipeDiscoverCreatorRecord? {
        creators.first { $0.id == id }
    }

    func posts(for creator: SwipeDiscoverCreatorRecord) -> [SocialPostSnapshot] {
        posts.filter { $0.author.platformID == creator.id || "@\($0.author.handle)" == creator.handle }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        errorMessage = nil

        do {
            if remoteStore.isConfigured {
                if let cached = localCache.load() {
                    applyCachedDiscovery(cached)
                    isLoading = false
                    return
                }

                await loadRemoteDiscovery(showLoading: true)
                return
            }

            isLoading = true
            let loaded = try await loadLocalCatalog()
            creators = loaded.records
            posts = loaded.posts
            hasLoaded = true
        } catch {
            do {
                let loaded = try await loadLocalCatalog()
                creators = loaded.records
                posts = loaded.posts
                errorMessage = "Cloud discovery failed: \(error.localizedDescription). Showing local imports."
                hasLoaded = true
            } catch {
                errorMessage = "Could not load discovery data: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    private func restoreCachedDiscoveryIfAvailable() {
        guard remoteStore.isConfigured, let cached = localCache.load() else { return }
        applyCachedDiscovery(cached)
        isLoading = false
    }

    private func applyCachedDiscovery(_ cached: SocialDiscoveryLocalCache.Payload) {
        posts = cached.posts
        creators = remoteCreatorRecords(creators: cached.creators, posts: cached.posts)
        hasLoaded = true
    }

    private func loadRemoteDiscovery(showLoading: Bool) async {
        if showLoading {
            isLoading = true
        }
        errorMessage = nil

        var remoteQuery = query
        remoteQuery.searchText = ""
        remoteQuery.platforms = []
        remoteQuery.minimumOutlierMultiplier = nil
        remoteQuery.postedWindow = .allTime
        remoteQuery.limit = 1_000

        do {
            let remoteCreators = try await remoteStore.fetchCreators()
            if posts.isEmpty {
                creators = remoteCreatorRecords(creators: remoteCreators, posts: posts)
                hasLoaded = true
            }

            do {
                let remotePosts = try await remoteStore.fetchPosts(query: remoteQuery, creators: remoteCreators)
                posts = remotePosts
                creators = remoteCreatorRecords(creators: remoteCreators, posts: remotePosts)
                try? localCache.save(posts: remotePosts, creators: remoteCreators)
            } catch {
                errorMessage = "Cloud posts are still loading: \(error.localizedDescription)"
            }

            hasLoaded = true
        } catch {
            if posts.isEmpty {
                do {
                    let loaded = try await loadLocalCatalog()
                    creators = loaded.records
                    posts = loaded.posts
                    errorMessage = "Cloud discovery failed: \(error.localizedDescription). Showing local imports."
                    hasLoaded = true
                } catch {
                    errorMessage = "Could not load discovery data: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "Cloud discovery failed: \(error.localizedDescription). Showing cached results."
            }
        }

        if showLoading {
            isLoading = false
        }
    }

    func refreshDiscovery() async {
        guard remoteStore.isConfigured else {
            await reload()
            return
        }

        isLoading = true
        errorMessage = nil

        await loadRemoteDiscovery(showLoading: false)
        saveMessage = "Discovery reloaded"
        isLoading = false
    }

    func save(_ post: SocialPostSnapshot, boardID: String? = nil) {
        Task {
            do {
                try await savePost(post, boardID: boardID)
                saveMessage = boardID == nil ? "Saved to All Swipes" : "Saved to board"
            } catch {
                saveMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    func addCreatorFromSearch() {
        let rawInput = creatorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }
        guard remoteStore.isConfigured else {
            creatorImportError = "Discovery API is not configured. Add the Discovery API Base URL and Discovery API Key in Settings."
            return
        }
        guard let identity = SocialPlatformResolver.resolve(input: rawInput) else {
            creatorImportError = "Paste a profile URL or use platform:handle, like youtube:aliabdaal."
            return
        }
        guard !isAddingCreator else { return }

        isAddingCreator = true
        creatorImportError = nil
        creatorImportMessage = "Adding \(identity.handle) to the discovery graph..."
        creatorSearchText = ""

        Task {
            defer { isAddingCreator = false }

            do {
                let sourceID = try await remoteStore.addCreator(identity: identity)
                creatorImportMessage = "Creator added. Loading profile..."
                hasLoaded = false
                await reload()
                creatorImportMessage = "Creator added. Importing posts from Apify. This can take a few minutes..."

                do {
                    let result = try await remoteStore.refreshSource(sourceID: sourceID)
                    creatorImportMessage = "Import finished. \(result.upserted) posts added from \(result.provider). Reloading creators..."
                } catch {
                    creatorImportError = "Creator was added, but the import did not finish: \(error.localizedDescription)"
                }

                await loadRemoteDiscovery(showLoading: false)
                if creatorImportError == nil {
                    creatorImportMessage = "Creator imported"
                    saveMessage = "Creator imported"
                }
            } catch {
                creatorImportError = "Could not add creator: \(error.localizedDescription)"
                creatorImportMessage = nil
            }
        }
    }

    private func loadLocalCatalog() async throws -> (posts: [SocialPostSnapshot], records: [SwipeDiscoverCreatorRecord]) {
        let creatorAtoms = try await AtomRepository.shared.fetchCreators()
        return loadCatalogSnapshots(from: creatorAtoms)
    }

    private func remoteCreatorRecords(
        creators remoteCreators: [SocialDiscoveryRemoteCreator],
        posts: [SocialPostSnapshot]
    ) -> [SwipeDiscoverCreatorRecord] {
        let postsByCreator = Dictionary(grouping: posts, by: { $0.author.platformID })

        let records = remoteCreators.map { creator in
            let creatorPosts = postsByCreator[creator.uuid] ?? []
            return SwipeDiscoverCreatorRecord(
                id: creator.uuid,
                name: creator.displayName ?? creator.handle,
                handle: "@\(creator.handle)",
                platform: creator.platform,
                avatarURL: creator.avatarURL,
                followerCount: creator.followerCount,
                niche: nil,
                bio: creator.bio,
                postCount: creatorPosts.count,
                totalViews: creatorPosts.compactMap(\.metrics.views).reduce(0, +),
                totalLikes: creatorPosts.compactMap(\.metrics.likes).reduce(0, +),
                totalComments: creatorPosts.compactMap(\.metrics.comments).reduce(0, +),
                topOutlierMultiplier: creatorPosts.compactMap(\.derived.outlierMultiplier).max(),
                latestPostDate: creatorPosts.compactMap(\.publishedAt).max(),
                topPosts: Array(creatorPosts.sorted { ($0.derived.outlierMultiplier ?? 0) > ($1.derived.outlierMultiplier ?? 0) }.prefix(3))
            )
        }

        if !records.isEmpty {
            return records
        }

        return postsByCreator.map { creatorID, creatorPosts in
            let firstPost = creatorPosts[0]
            return SwipeDiscoverCreatorRecord(
                id: creatorID,
                name: firstPost.author.displayName,
                handle: "@\(firstPost.author.handle)",
                platform: firstPost.platform,
                avatarURL: firstPost.author.avatarURL,
                followerCount: firstPost.author.followerCount,
                niche: nil,
                bio: nil,
                postCount: creatorPosts.count,
                totalViews: creatorPosts.compactMap(\.metrics.views).reduce(0, +),
                totalLikes: creatorPosts.compactMap(\.metrics.likes).reduce(0, +),
                totalComments: creatorPosts.compactMap(\.metrics.comments).reduce(0, +),
                topOutlierMultiplier: creatorPosts.compactMap(\.derived.outlierMultiplier).max(),
                latestPostDate: creatorPosts.compactMap(\.publishedAt).max(),
                topPosts: Array(creatorPosts.sorted { ($0.derived.outlierMultiplier ?? 0) > ($1.derived.outlierMultiplier ?? 0) }.prefix(3))
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func loadCatalogSnapshots(from creatorAtoms: [Atom]) -> (posts: [SocialPostSnapshot], records: [SwipeDiscoverCreatorRecord]) {
        var allPosts: [SocialPostSnapshot] = []
        var records: [SwipeDiscoverCreatorRecord] = []

        for creator in creatorAtoms {
            guard let metadata = creator.metadataValue(as: CreatorMetadata.self),
                  let catalogPosts = CatalogStore.load(creatorUUID: creator.uuid),
                  !catalogPosts.isEmpty else {
                continue
            }

            let handle = (metadata.handle ?? creator.title ?? "unknown")
                .replacingOccurrences(of: "@", with: "")
            let profile = ImportedCreatorProfile(
                username: handle,
                fullName: creator.title,
                biography: metadata.bio,
                followerCount: metadata.followerCount ?? 0,
                followingCount: metadata.followingCount ?? 0,
                postsCount: metadata.postsCount ?? catalogPosts.count,
                profilePicUrl: metadata.thumbnailUrl,
                isPrivate: false,
                isVerified: false
            )

            let basePosts = catalogPosts.map {
                SocialInstagramMapper.snapshot(post: $0, profile: profile)
            }
            let scoredPosts = score(posts: basePosts)
            allPosts.append(contentsOf: scoredPosts)

            records.append(
                SwipeDiscoverCreatorRecord(
                    id: creator.uuid,
                    name: creator.title ?? profile.fullName ?? handle,
                    handle: "@\(handle)",
                    platform: .instagram,
                    avatarURL: metadata.thumbnailUrl.flatMap(URL.init(string:)),
                    followerCount: metadata.followerCount,
                    niche: metadata.niche,
                    bio: metadata.bio,
                    postCount: scoredPosts.count,
                    totalViews: scoredPosts.compactMap(\.metrics.views).reduce(0, +),
                    totalLikes: scoredPosts.compactMap(\.metrics.likes).reduce(0, +),
                    totalComments: scoredPosts.compactMap(\.metrics.comments).reduce(0, +),
                    topOutlierMultiplier: scoredPosts.compactMap(\.derived.outlierMultiplier).max(),
                    latestPostDate: scoredPosts.compactMap(\.publishedAt).max(),
                    topPosts: Array(scoredPosts.sorted { ($0.derived.outlierMultiplier ?? 0) > ($1.derived.outlierMultiplier ?? 0) }.prefix(3))
                )
            )
        }

        return (allPosts, records)
    }

    private func score(posts: [SocialPostSnapshot]) -> [SocialPostSnapshot] {
        posts.map { post in
            let score = SocialOutlierScorer.score(post: post, creatorPosts: posts)
            let derived = SocialDerivedMetrics(
                outlierMultiplier: score.multiplier,
                outlierGrade: score.grade,
                engagementRate: engagementRate(for: post)
            )
            return post.replacing(derived: derived)
        }
    }

    private func engagementRate(for post: SocialPostSnapshot) -> Double? {
        guard let followerCount = post.author.followerCount, followerCount > 0 else { return nil }
        let engagements = (post.metrics.likes ?? 0)
            + (post.metrics.comments ?? 0)
            + (post.metrics.shares ?? 0)
            + (post.metrics.reposts ?? 0)
        return Double(engagements) / Double(followerCount)
    }

    private func savePost(_ post: SocialPostSnapshot, boardID: String?) async throws {
        if post.provider == "cloud-discovery", remoteStore.isConfigured {
            try await remoteStore.savePost(postID: post.id, boardID: boardID)
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.creatorDataChanged, object: nil)
            return
        }

        _ = try await createLocalSwipeAtom(from: post, boardID: boardID)
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.creatorDataChanged, object: nil)
    }

    /// Creates a local Swipe File atom from a discovered post and returns it (with its row id).
    /// Used both by the board-save flow and the Transcript launch flow, where we need the
    /// atom's id immediately to open the swipe teardown focus mode.
    @discardableResult
    private func createLocalSwipeAtom(from post: SocialPostSnapshot, boardID: String?) async throws -> Atom {
        let hook = post.title ?? post.body?.components(separatedBy: .newlines).first
        var atom = Research.newSwipeFile(
            url: post.canonicalURL.absoluteString,
            hook: hook,
            sourceType: sourceType(for: post),
            contentSource: .import_
        )
        atom.title = hook ?? post.author.displayName
        atom.body = post.body
        atom.thumbnailUrl = post.media.first(where: { $0.kind == .thumbnail || $0.kind == .image })?.url.absoluteString
        atom.contentSource = "creator_import"
        atom.swipeBoardIDs = boardID.map { [$0] }

        // Instagram swipes must enter the SAME background pipeline the clipboard/Telegram
        // capture path uses (see CommandKInstantSwipeCapture.capture + shouldProcessInBackground):
        // mark "pending" here and kick off processing at SAVE time, below. Previously the
        // Discovery save path created the atom with only a thumbnail and never triggered
        // processing — so a saved reel had no downloaded video and SwipeStudy was forced into
        // a cold, flaky live extraction on every open (it only "worked the next day" once the
        // launch/foreground scanner happened to process it). Starting processing at save makes
        // the video download + transcribe in the background, ready to load from the store on open.
        let needsBackgroundProcessing = post.platform == .instagram
        if needsBackgroundProcessing {
            atom.processingStatus = "pending"
        }

        var analysis = SwipeAnalysis(
            analysisVersion: 1,
            isFullyAnalyzed: false,
            likesCount: post.metrics.likes,
            viewsCount: post.metrics.views,
            commentsCount: post.metrics.comments,
            sharesCount: post.metrics.shares,
            engagementRate: post.derived.engagementRate,
            publishedAt: post.publishedAt,
            postShortcode: post.providerPostID
        )
        analysis.hookText = hook
        atom = atom.withSwipeAnalysis(analysis)

        let saved = try await AtomRepository.shared.create(atom)

        if needsBackgroundProcessing {
            SwipeProcessingService.shared.processSwipeInBackground(uuid: saved.uuid)
        }

        return saved
    }

    /// Transcript-button flow: save the post into "All Swipes" locally, then open the swipe
    /// teardown focus mode. `SwipeStudyFocusModeView` auto-starts transcription on appear when
    /// the atom has no transcript yet, so this single hop covers save + teardown + transcription.
    func saveAndOpenForTranscription(_ post: SocialPostSnapshot) async {
        do {
            let atom = try await createLocalSwipeAtom(from: post, boardID: nil)
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.creatorDataChanged, object: nil)
            saveMessage = "Saved to All Swipes — transcribing…"
            guard let id = atom.id else { return }
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.research, "id": id]
            )
        } catch {
            saveMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func sourceType(for post: SocialPostSnapshot) -> ResearchRichContent.SourceType {
        switch post.platform {
        case .instagram:
            switch post.format {
            case .shortVideo: return .instagramReel
            case .carousel: return .instagramCarousel
            default: return .instagramPost
            }
        case .youtube: return post.format == .shortVideo ? .youtubeShort : .youtube
        case .tiktok: return .tiktok
        case .threads: return .threads
        case .x, .twitter: return .xPost
        default: return .website
        }
    }
}

private struct SwipeDiscoverCreatorRecord: Identifiable, Equatable {
    let id: String
    let name: String
    let handle: String
    let platform: SocialPlatform
    let avatarURL: URL?
    let followerCount: Int?
    let niche: String?
    let bio: String?
    let postCount: Int
    let totalViews: Int
    let totalLikes: Int
    let totalComments: Int
    let topOutlierMultiplier: Double?
    let latestPostDate: Date?
    let topPosts: [SocialPostSnapshot]
}

private struct SwipeDiscoverHeader: View {
    let section: SwipeDiscoverySectionSelection
    @Binding var query: SocialDiscoveryQuery
    @Binding var creatorSearchText: String
    let isAddingCreator: Bool
    @Binding var isShowingFilters: Bool
    var onAddCreator: () -> Void
    var onRefresh: () -> Void

    @FocusState private var searchFocused: Bool

    private var activeSearchText: Binding<String> {
        section == .creators ? $creatorSearchText : $query.searchText
    }

    private var searchPlaceholder: String {
        section == .creators
            ? "Search creators or paste a profile URL..."
            : "Search for a handle, keyword, or profile URL..."
    }

    private var canAddCreator: Bool {
        !creatorSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAddingCreator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                titleBlock
                Spacer(minLength: 16)
                filterButton
                reloadButton
            }
            searchRow
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)
            Text(section.subtitle)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var filterButton: some View {
        Button {
            withAnimation(ProMotionSprings.bouncy) { isShowingFilters.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(DS.subheadline.weight(.semibold))
                Text(SwipeDiscoveryFilterPresentation.summary(for: query))
                    .font(DS.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(DS.caption2.weight(.bold))
                    .rotationEffect(.degrees(isShowingFilters ? 180 : 0))
            }
            .foregroundStyle(isShowingFilters ? DS.text : DS.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .dsGlassInput(isFocused: isShowingFilters, cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FilterAnchorKey.self,
                    value: proxy.frame(in: .named("swipeDiscoverFilterRoot"))
                )
            }
        )
        .help("Filter discovery")
        .accessibilityLabel("Filter discovery")
    }

    private var reloadButton: some View {
        Button(action: onRefresh) {
            Image(systemName: "arrow.clockwise")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 36, height: 36)
                .dsGlassInput(cornerRadius: 18)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .help("Reload discovery")
        .accessibilityLabel("Reload discovery")
    }

    private var searchRow: some View {
        HStack(spacing: 12) {
            searchField
            if section == .creators {
                addCreatorButton
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(DS.body.weight(.medium))
                .foregroundStyle(searchFocused ? DS.accent : DS.textMuted)

            TextField(searchPlaceholder, text: activeSearchText)
                .textFieldStyle(.plain)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .focused($searchFocused)
                .onSubmit {
                    if section == .creators { onAddCreator() }
                }

            if !activeSearchText.wrappedValue.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    activeSearchText.wrappedValue = ""
                }
                .labelStyle(.iconOnly)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.textMuted)
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .dsGlassInput(isFocused: searchFocused, cornerRadius: 14)
        .animation(ProMotionSprings.gentle, value: searchFocused)
    }

    private var addCreatorButton: some View {
        Button(action: onAddCreator) {
            HStack(spacing: 7) {
                if isAddingCreator {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: "plus")
                }
                Text(isAddingCreator ? "Adding" : "Add")
            }
            .font(DS.callout.weight(.semibold))
            .foregroundStyle(canAddCreator ? DS.accent : DS.textMuted)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(Capsule().fill(canAddCreator ? DS.accentSoft : DS.glassInputFill))
            .overlay(
                Capsule().strokeBorder(
                    canAddCreator ? DS.accent.opacity(0.4) : DS.glassBorder,
                    lineWidth: canAddCreator ? 1 : 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canAddCreator)
        .accessibilityLabel("Add creator")
    }
}

private struct SwipeDiscoverPillarStrip: View {
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                DiscoverSignalCard(title: "Productivity", systemImage: "bolt", tint: DS.entityResearch)
                DiscoverSignalCard(title: "Self-improvement", systemImage: "sparkles", tint: DS.entityIdea)
                DiscoverSignalCard(title: "Business", systemImage: "briefcase", tint: DS.entityContent)
                DiscoverSignalCard(title: "Psychology", systemImage: "brain.head.profile", tint: DS.entityConnection)
                DiscoverSignalCard(title: "Content creation", systemImage: "camera", tint: DS.entitySwipe)
            }
        }
        .scrollIndicators(.never)
    }
}

private struct SwipeDiscoverPlatformStrip: View {
    @Binding var query: SocialDiscoveryQuery

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                SwipeFilterChip(
                    title: "All",
                    systemImage: "square.grid.2x2",
                    isSelected: query.platforms.isEmpty
                ) {
                    query.platforms = []
                }

                ForEach(SwipeDiscoveryFilterPresentation.primaryPlatforms, id: \.rawValue) { platform in
                    SwipeFilterChip(
                        title: platform.displayName,
                        systemImage: platform.iconName,
                        isSelected: query.platforms.contains(platform)
                    ) {
                        if query.platforms.contains(platform) {
                            query.platforms.remove(platform)
                        } else {
                            query.platforms.insert(platform)
                        }
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
    }
}

private struct SwipeDiscoverFeed: View {
    let viewModel: SwipeFileDiscoverViewModel
    let onOpen: (SocialPostSnapshot) -> Void

    private var posts: [SocialPostSnapshot] {
        viewModel.visiblePosts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Matches")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)
                Text("\(posts.count)")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(DS.glassInputFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
            }

            if viewModel.isLoading {
                SwipeDiscoverSkeletonGrid()
            } else if posts.isEmpty {
                if let error = viewModel.errorMessage {
                    SwipeFileEmptyState(title: "Discovery unavailable", subtitle: error, systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    SwipeFileEmptyState(
                        title: "No matches yet",
                        subtitle: "Import a creator's catalog to start the cross-platform feed.",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            } else if let error = viewModel.errorMessage {
                SwipeDiscoverCreatorImportNotice(message: error, systemImage: "exclamationmark.triangle", tint: .orange)
                SwipeDiscoverMasonryGrid(posts: posts, onSave: viewModel.save, onOpen: onOpen)
            } else {
                SwipeDiscoverMasonryGrid(posts: posts, onSave: viewModel.save, onOpen: onOpen)
            }
        }
    }
}

private struct SwipeDiscoverMasonryGrid: View {
    let posts: [SocialPostSnapshot]
    let onSave: (SocialPostSnapshot, String?) -> Void
    let onOpen: (SocialPostSnapshot) -> Void

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 16
            let columnCount = Self.columnCount(for: proxy.size.width)
            let cardWidth = Self.cardWidth(
                containerWidth: proxy.size.width,
                columnCount: columnCount,
                spacing: spacing
            )
            let columns = distribute(posts: posts, columnCount: columnCount, cardWidth: cardWidth, spacing: spacing)

            HStack(alignment: .top, spacing: spacing) {
                ForEach(columns.indices, id: \.self) { columnIndex in
                    LazyVStack(spacing: spacing) {
                        ForEach(Array(columns[columnIndex].enumerated()), id: \.element.id) { index, post in
                            SwipeDiscoverPostCard(
                                post: post,
                                cardWidth: cardWidth,
                                appearIndex: index,
                                onSave: onSave,
                                onOpen: onOpen
                            )
                            .frame(width: cardWidth)
                        }
                    }
                }
            }
        }
        .frame(minHeight: estimatedGridHeight(posts: posts, width: 980))
    }

    private static func columnCount(for width: CGFloat) -> Int {
        guard width > 0 else { return 2 }
        let idealCardWidth: CGFloat = 330
        let spacing: CGFloat = 16
        return max(2, min(4, Int((width + spacing) / (idealCardWidth + spacing))))
    }

    private static func cardWidth(containerWidth: CGFloat, columnCount: Int, spacing: CGFloat) -> CGFloat {
        let rawWidth = (containerWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        return max(260, rawWidth)
    }

    private func distribute(
        posts: [SocialPostSnapshot],
        columnCount: Int,
        cardWidth: CGFloat,
        spacing: CGFloat
    ) -> [[SocialPostSnapshot]] {
        var columns = Array(repeating: [SocialPostSnapshot](), count: columnCount)
        var heights = Array(repeating: CGFloat.zero, count: columnCount)

        for post in posts {
            let target = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[target].append(post)
            heights[target] += SwipeDiscoverPostCard.estimatedHeight(for: post, cardWidth: cardWidth) + spacing
        }

        return columns
    }

    private func estimatedGridHeight(posts: [SocialPostSnapshot], width: CGFloat) -> CGFloat {
        guard !posts.isEmpty else { return 260 }
        let spacing: CGFloat = 16
        let columnCount = Self.columnCount(for: width)
        let cardWidth = Self.cardWidth(containerWidth: width, columnCount: columnCount, spacing: spacing)
        let columns = distribute(posts: posts, columnCount: columnCount, cardWidth: cardWidth, spacing: spacing)
        return max(420, columns.map { column in
            column.reduce(CGFloat.zero) { partial, post in
                partial + SwipeDiscoverPostCard.estimatedHeight(for: post, cardWidth: cardWidth) + spacing
            }
        }.max() ?? 420)
    }
}

private struct SwipeDiscoverPostCard: View {
    let post: SocialPostSnapshot
    let cardWidth: CGFloat
    var appearIndex: Int = 0
    let onSave: (SocialPostSnapshot, String?) -> Void
    let onOpen: (SocialPostSnapshot) -> Void

    @State private var isHovered = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let infoSectionHeight: CGFloat = 196

    private var thumbnailURL: URL? {
        post.media.first(where: { $0.kind == .thumbnail || $0.kind == .image })?.url
    }

    /// Restart-safe cache key so thumbnails survive CDN URL rotation (Instagram
    /// especially). Nil when the provider ID is absent, letting the cache hash the URL.
    private var thumbnailStableKey: String? {
        guard !post.providerPostID.isEmpty else { return nil }
        return "\(post.platform.rawValue)-\(post.providerPostID)"
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private enum PreviewAspect {
        case wide
        case portrait
        case vertical
    }

    private var previewAspect: PreviewAspect {
        switch post.platform {
        case .youtube:
            return post.format == .shortVideo ? .vertical : .wide
        case .instagram:
            if post.format == .shortVideo {
                return .vertical
            }
            return .portrait
        case .tiktok:
            return .vertical
        default:
            return post.format == .shortVideo ? .vertical : .wide
        }
    }

    private var mediaAspectRatio: CGFloat {
        Self.mediaAspectRatio(for: post)
    }

    private var mediaHeight: CGFloat {
        Self.mediaHeight(for: post, cardWidth: cardWidth)
    }

    static func estimatedHeight(for post: SocialPostSnapshot, cardWidth: CGFloat) -> CGFloat {
        mediaHeight(for: post, cardWidth: cardWidth) + infoSectionHeight
    }

    private static func mediaAspectRatio(for post: SocialPostSnapshot) -> CGFloat {
        switch previewAspect(for: post) {
        case .wide: return 16.0 / 9.0
        case .portrait: return 1.0
        case .vertical: return 9.0 / 16.0
        }
    }

    private static func mediaHeight(for post: SocialPostSnapshot, cardWidth: CGFloat) -> CGFloat {
        switch previewAspect(for: post) {
        case .wide:
            return cardWidth * 9.0 / 16.0
        case .portrait:
            return cardWidth
        case .vertical:
            return min(cardWidth * 16.0 / 9.0, 620)
        }
    }

    private static func previewAspect(for post: SocialPostSnapshot) -> PreviewAspect {
        switch post.platform {
        case .youtube:
            return post.format == .shortVideo ? .vertical : .wide
        case .instagram:
            return post.format == .shortVideo ? .vertical : .portrait
        case .tiktok:
            return .vertical
        default:
            return post.format == .shortVideo ? .vertical : .wide
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mediaHeader
            infoSection
        }
        .frame(height: Self.estimatedHeight(for: post, cardWidth: cardWidth), alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .swipeGlassCard(isHovered: isHovered, tint: post.platform.discoveryBadgeColor)
        .contentShape(cardShape)
        .modifier(SwipeCardShadow(isHovered: isHovered))
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .opacity(hasAppeared || reduceMotion ? 1 : 0)
        .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
        .onHover { isHovered = $0 }
        .onTapGesture { onOpen(post) }
        .onAppear(perform: animateEntrance)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Open post details")
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            authorRow
            Text(post.body ?? post.title ?? post.canonicalURL.absoluteString)
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(4)
            Spacer(minLength: 0)
            metricRow
            footerRow
        }
        .padding(14)
        .frame(height: Self.infoSectionHeight, alignment: .topLeading)
    }

    private func animateEntrance() {
        guard !reduceMotion else { hasAppeared = true; return }
        guard !hasAppeared else { return }
        withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) {
            hasAppeared = true
        }
    }

    @ViewBuilder
    private var mediaHeader: some View {
        if let thumbnailURL {
            CachedAsyncImage(url: thumbnailURL, stableKey: thumbnailStableKey) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderMedia
                case .empty:
                    placeholderMedia.redacted(reason: .placeholder)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(mediaAspectRatio, contentMode: .fill)
            .frame(height: mediaHeight)
            .clipped()
            .overlay(alignment: .topLeading) {
                platformBadge
                    .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                outlierBadge
                    .padding(10)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                platformBadge
                Text(post.body ?? post.title ?? "")
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .frame(height: mediaHeight)
            .background(DS.commandChromePanelFill)
            .overlay(alignment: .topTrailing) {
                outlierBadge
                    .padding(10)
            }
        }
    }

    private var placeholderMedia: some View {
        Rectangle()
            .fill(DS.commandChromePanelFill)
            .overlay {
                Image(systemName: post.platform.iconName)
                    .font(DS.pageTitle)
                    .foregroundStyle(DS.textMuted)
            }
    }

    private var authorRow: some View {
        HStack(spacing: 8) {
            Text(post.author.displayName)
                .font(DS.callout.weight(.bold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
            Text("@\(post.author.handle)")
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
    }

    private var metricRow: some View {
        HStack(spacing: 12) {
            metric("eye", post.metrics.views)
            metric("heart", post.metrics.likes)
            metric("bubble.left", post.metrics.comments)
            metric("arrow.2.squarepath", post.metrics.shares ?? post.metrics.reposts)
        }
        .font(DS.subheadline.weight(.semibold))
        .foregroundStyle(DS.textMuted)
    }

    private var footerRow: some View {
        HStack {
            if let date = post.publishedAt {
                Text(date, style: .relative)
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            Menu {
                Button("All Swipes", systemImage: "rectangle.stack.badge.plus") {
                    onSave(post, nil)
                }
                Divider()
                Button("Thread Hooks", systemImage: "text.alignleft") {
                    onSave(post, "thread-hooks")
                }
                Button("Reel Ideas", systemImage: "play.rectangle") {
                    onSave(post, "reel-ideas")
                }
                Button("Client Proof", systemImage: "checkmark.seal") {
                    onSave(post, "client-proof")
                }
            } label: {
                Image(systemName: "plus")
                    .font(DS.callout.weight(.bold))
                    .foregroundStyle(DS.text)
                    .frame(width: 32, height: 32)
                    .background(DS.surfaceElevated, in: Circle())
                    .overlay(Circle().strokeBorder(DS.borderSubtle, lineWidth: 0.75))
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .help("Add to board")
            .accessibilityLabel("Add to board")
        }
    }

    private var platformBadge: some View {
        Image(systemName: post.platform.iconName)
            .font(DS.caption.weight(.bold))
            .foregroundStyle(DS.textOnAccent)
            .frame(width: 20, height: 20)
            .background(post.platform.discoveryBadgeColor, in: Circle())
            .overlay(Circle().strokeBorder(DS.textOnAccent.opacity(0.3), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
            .accessibilityLabel("\(post.platform.displayName) post")
    }

    private var outlierBadge: some View {
        Text(post.derived.outlierMultiplier.map { "\(Int($0.rounded()))x" } ?? "new")
            .font(DS.caption.weight(.bold))
            .foregroundStyle(post.derived.outlierMultiplier == nil ? DS.textMuted : DS.accent)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(DS.surfaceElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
    }

    private func metric(_ systemImage: String, _ value: Int?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(value.map(formatCount) ?? "-")
        }
    }
}

// MARK: - Swipe Glass Card Chrome

/// The reusable "Greenhouse Glass" surface for the SwipeFile tab: a warm glass fill,
/// a low-intensity platform/entity tint wash, and a focus-aware hairline border.
/// Motion (shadow lift, hover scale, entrance) is applied by the caller so this stays
/// usable for static contexts (skeletons, previews) and other SwipeFile screens later.
private struct SwipeGlassCardModifier: ViewModifier {
    var isHovered: Bool = false
    var tint: Color = DS.accent
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(tint.opacity(isHovered ? 0.10 : 0.06), in: shape)
            .background(DS.glassCardFill, in: shape)
            .overlay(
                shape.strokeBorder(
                    isHovered ? DS.glassBorderFocused : DS.glassBorder,
                    lineWidth: isHovered ? 1 : 0.5
                )
            )
            .clipShape(shape)
    }
}

/// Resting → hover shadow lift. Applies a fixed pair of `.shadow` modifiers whose
/// parameters interpolate on `isHovered` — never an `if/else` branch. A structural
/// branch here would swap `content` between `_ConditionalContent` cases on every
/// hover, destroying and rebuilding the wrapped subtree (reloading the AsyncImage
/// and breaking hover tracking). Keeping the structure constant preserves identity
/// and lets the lift animate via the caller's `.animation(_:value:)`.
private struct SwipeCardShadow: ViewModifier {
    let isHovered: Bool

    func body(content: Content) -> some View {
        let isDark = DS.palette.isDark
        return content
            .shadow(
                color: .black.opacity(isHovered ? (isDark ? 0.4 : 0.06) : (isDark ? 0.3 : 0.04)),
                radius: isHovered ? (isDark ? 8 : 16) : (isDark ? 4 : 8),
                x: 0,
                y: isHovered ? (isDark ? 2 : 4) : (isDark ? 1 : 2)
            )
            .shadow(
                color: .black.opacity(isHovered ? (isDark ? 0.25 : 0.03) : (isDark ? 0.2 : 0.02)),
                radius: isHovered ? (isDark ? 2 : 4) : (isDark ? 1 : 2),
                x: 0,
                y: isHovered ? (isDark ? 1 : 2) : (isDark ? 0 : 1)
            )
    }
}

extension View {
    /// Apply the shared SwipeFile glass card chrome (fill + tint wash + hairline border + clip).
    func swipeGlassCard(isHovered: Bool = false, tint: Color = DS.accent, cornerRadius: CGFloat = 14) -> some View {
        modifier(SwipeGlassCardModifier(isHovered: isHovered, tint: tint, cornerRadius: cornerRadius))
    }
}

// MARK: - Platform Badge Color

private extension SocialPlatform {
    /// Brand color for the tiny Discovery platform badge — the single sanctioned place
    /// the SwipeFile redesign uses non-DS hex. These are external platform brand
    /// identities that can't map to Greenhouse tokens; all other chrome uses warm DS.
    var discoveryBadgeColor: Color {
        switch self {
        case .instagram: return Color(hex: "#E1306C")
        case .youtube: return Color(hex: "#E0322B")
        case .linkedin: return Color(hex: "#0A66C2")
        case .facebook: return Color(hex: "#1877F2")
        case .substack: return Color(hex: "#E06A38")
        case .tiktok, .x, .twitter, .threads, .medium: return Color(hex: "#1C1C20")
        case .other: return DS.textMuted
        }
    }
}

// MARK: - Discovery Post Detail Modal

/// Dimmed scrim + centered glass panel. The scrim fades; the panel scales in, so hitting
/// Transcript reads as the post "lifting" out of the feed and into the teardown studio.
private struct SwipeDiscoverPostDetailOverlay: View {
    let post: SocialPostSnapshot
    let onSave: (SocialPostSnapshot, String?) -> Void
    let onTranscript: (SocialPostSnapshot) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .transition(.opacity)

            GeometryReader { proxy in
                SwipeDiscoverPostDetail(
                    post: post,
                    maxHeight: min(proxy.size.height * 0.88, 760),
                    onSave: onSave,
                    onTranscript: onTranscript,
                    onClose: onClose
                )
                .frame(width: min(720, max(360, proxy.size.width - 80)))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }
}

private struct SwipeDiscoverPostDetail: View {
    let post: SocialPostSnapshot
    let maxHeight: CGFloat
    let onSave: (SocialPostSnapshot, String?) -> Void
    let onTranscript: (SocialPostSnapshot) -> Void
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var isLaunching = false
    @State private var didCopy = false

    private var thumbnailURL: URL? {
        post.media.first(where: { $0.kind == .thumbnail || $0.kind == .image })?.url
    }

    private var hashtags: [String] { extractHashtags(from: post.body ?? "") }

    private var outlierText: String {
        post.derived.outlierMultiplier.map { "\(Int($0.rounded()))×" } ?? "New"
    }

    private var engagementText: String {
        post.derived.engagementRate.map(formatEngagementRate) ?? "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.borderSubtle)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    mediaHero
                    authorRow
                    metricsStrip
                    captionSection
                    transcriptSection
                    if !hashtags.isEmpty { hashtagSection }
                }
                .padding(20)
            }
        }
        .frame(maxHeight: maxHeight)
        .cortexInspectorPanel(cornerRadius: 20)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Label(post.platform.displayName, systemImage: post.platform.iconName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.textSecondary)
            Spacer(minLength: 8)
            boardMenu
            circleButton("arrow.up.right.square", help: "Open original") {
                openURL(post.canonicalURL)
            }
            circleButton("xmark", help: "Close", action: onClose)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var boardMenu: some View {
        Menu {
            Button("All Swipes", systemImage: "rectangle.stack.badge.plus") { onSave(post, nil) }
            Divider()
            Button("Thread Hooks", systemImage: "text.alignleft") { onSave(post, "thread-hooks") }
            Button("Reel Ideas", systemImage: "play.rectangle") { onSave(post, "reel-ideas") }
            Button("Client Proof", systemImage: "checkmark.seal") { onSave(post, "client-proof") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.textOnAccent)
                .frame(width: 34, height: 34)
                .background(DS.accent, in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Add to board")
    }

    private func circleButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 34, height: 34)
                .background(DS.surfaceElevated, in: Circle())
                .overlay(Circle().stroke(DS.borderSubtle, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Media

    private var mediaHero: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            mediaPlaceholder
                        }
                    }
                } else {
                    mediaPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(Color.black.opacity(0.92))
            .clipShape(.rect(cornerRadius: 16))

            outlierBadge.padding(12)
        }
    }

    private var mediaPlaceholder: some View {
        ZStack {
            Color.black.opacity(0.92)
            Image(systemName: post.platform.iconName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(DS.textMuted)
        }
    }

    private var outlierBadge: some View {
        let hasOutlier = post.derived.outlierMultiplier != nil
        return Text(outlierText)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(hasOutlier ? DS.textOnAccent : DS.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(hasOutlier ? AnyShapeStyle(DS.accent) : AnyShapeStyle(.regularMaterial), in: Capsule())
    }

    // MARK: Author

    private var authorRow: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(post.author.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("@\(post.author.handle)")
                    if let date = post.publishedAt {
                        Text("·")
                        Text(date, style: .relative)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let followers = post.author.followerCount {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatCount(followers))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.text)
                        .monospacedDigit()
                    Text("followers")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
    }

    private var avatar: some View {
        AsyncImage(url: post.author.avatarURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(DS.surfaceElevated)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(DS.textMuted))
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .overlay(Circle().stroke(DS.borderSubtle, lineWidth: 0.75))
    }

    // MARK: Metrics

    private var metricsStrip: some View {
        HStack(spacing: 10) {
            metricTile("Outlier", outlierText, accent: true)
            metricTile("Views", post.metrics.views.map(formatCount) ?? "—")
            metricTile("Likes", post.metrics.likes.map(formatCount) ?? "—")
            metricTile("Comments", post.metrics.comments.map(formatCount) ?? "—")
            metricTile("Eng. rate", engagementText)
        }
    }

    private func metricTile(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(accent ? DS.accent : DS.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.textMuted)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            accent ? DS.accentSoft : DS.surfaceElevated.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent ? DS.accent.opacity(0.25) : DS.borderSubtle, lineWidth: 0.75)
        )
    }

    // MARK: Caption

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Caption")
                Spacer()
                Button(action: copyCaption) {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(didCopy ? DS.accent : DS.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Text(post.body ?? post.title ?? "No caption available.")
                .font(.system(size: 14))
                .foregroundStyle(DS.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Transcript")
            if case let .available(text) = post.transcriptState, !text.isEmpty {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                transcriptCTA
            }
        }
    }

    private var transcriptCTA: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: launchTranscript) {
                HStack(spacing: 8) {
                    Image(systemName: isLaunching ? "checkmark.circle.fill" : "text.viewfinder")
                    Text(isLaunching ? "Opening teardown…" : "Transcript")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.textOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(DS.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(isLaunching ? 0.97 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isLaunching)

            Text("Transcribing adds this post to your Swipe File and opens it for teardown.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textMuted)
        }
        .animation(ProMotionSprings.bouncy, value: isLaunching)
    }

    // MARK: Hashtags

    private var hashtagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Hashtags")
            CodexFlowLayout(spacing: 6) {
                ForEach(hashtags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DS.accentSoft, in: Capsule())
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(DS.textMuted)
            .tracking(0.8)
    }

    // MARK: Actions

    private func launchTranscript() {
        guard !isLaunching else { return }
        withAnimation(ProMotionSprings.bouncy) { isLaunching = true }
        Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            onTranscript(post)
        }
    }

    private func copyCaption() {
        let text = post.body ?? post.title ?? ""
        guard !text.isEmpty else { return }
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation(ProMotionSprings.snappy) { didCopy = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(ProMotionSprings.snappy) { didCopy = false }
        }
    }
}

private struct SwipeDiscoverCreatorDirectory: View {
    let viewModel: SwipeFileDiscoverViewModel
    let onSelectCreator: (SwipeDiscoverCreatorRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Creator Library")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.text)
                Text("\(viewModel.filteredCreators.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textMuted)
                    .monospacedDigit()

                Spacer(minLength: 12)

                Menu {
                    ForEach(SocialDiscoverySort.allCases, id: \.rawValue) { sort in
                        Button(sort.displayName) {
                            viewModel.creatorSortMode = sort
                        }
                    }
                } label: {
                    SwipeMenuLabel(title: viewModel.creatorSortMode.displayName, systemImage: "arrow.up.arrow.down", isSelected: true)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }

            if let error = viewModel.creatorImportError {
                SwipeDiscoverCreatorImportNotice(message: error, systemImage: "exclamationmark.triangle", tint: .orange)
            } else if let message = viewModel.creatorImportMessage {
                SwipeDiscoverCreatorImportNotice(
                    message: message,
                    systemImage: viewModel.isAddingCreator ? "arrow.triangle.2.circlepath" : "checkmark.circle",
                    tint: viewModel.isAddingCreator ? DS.accent : .green
                )
            }

            if viewModel.isLoading && viewModel.creators.isEmpty {
                SwipeDiscoverSkeletonGrid()
            } else if viewModel.filteredCreators.isEmpty {
                SwipeFileEmptyState(
                    title: "No creators imported yet",
                    subtitle: "Import a creator catalog to study their best posts here.",
                    systemImage: "person.2"
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredCreators) { creator in
                        SwipeDiscoverCreatorRow(creator: creator) {
                            onSelectCreator(creator)
                        }
                    }
                }
            }
        }
    }
}

private struct SwipeDiscoverCreatorImportNotice: View {
    let message: String
    let systemImage: String
    let tint: Color
    private var isInProgress: Bool { systemImage == "arrow.triangle.2.circlepath" }

    var body: some View {
        HStack(spacing: 8) {
            if isInProgress {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 16)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if isInProgress {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 260)
                        .tint(tint)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DS.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 0.75)
        )
    }
}

private struct SwipeDiscoverCreatorRow: View {
    let creator: SwipeDiscoverCreatorRecord
    let onSelect: () -> Void

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    AsyncImage(url: creator.avatarURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Circle()
                                .fill(DS.accentSoft)
                                .overlay {
                                    Text(String(creator.name.prefix(1)).uppercased())
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(DS.textSecondary)
                                }
                        }
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(creator.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.text)
                        Text([creator.handle, creator.niche].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.textMuted)
                    }

                    Spacer()

                    creatorMetric("Followers", creator.followerCount)
                    creatorMetric("Posts", creator.postCount)
                    creatorMetric("Top", creator.topOutlierMultiplier.map { Int($0.rounded()) }, suffix: "x")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.textMuted)
                }

                if !creator.topPosts.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(creator.topPosts.prefix(3)) { post in
                            Text(post.body ?? post.title ?? post.canonicalURL.absoluteString)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(3)
                                .padding(10)
                                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                                .background(DS.commandChromePanelFill, in: .rect(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(14)
            .background(DS.surface.opacity(0.72), in: rowShape)
            .overlay(rowShape.stroke(DS.borderSubtle, lineWidth: 0.75))
            .contentShape(rowShape)
        }
        .buttonStyle(.plain)
    }

    private func creatorMetric(_ title: String, _ value: Int?, suffix: String = "") -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value.map { formatCount($0) + suffix } ?? "-")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DS.text)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
        }
    }
}

private struct SwipeDiscoverCreatorProfile: View {
    let creator: SwipeDiscoverCreatorRecord
    let posts: [SocialPostSnapshot]
    let onBack: () -> Void
    let onSave: (SocialPostSnapshot, String?) -> Void
    let onOpen: (SocialPostSnapshot) -> Void

    @State private var sortMode: SocialDiscoverySort = .highestOutlier

    private var sortedPosts: [SocialPostSnapshot] {
        let query = SocialDiscoveryQuery(
            minimumOutlierMultiplier: nil,
            postedWindow: .allTime,
            sort: sortMode,
            limit: 1_000
        )
        return SocialDiscoveryStore(query: query, posts: posts).visiblePosts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: onBack) {
                Label("Creators", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    AsyncImage(url: creator.avatarURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Circle()
                                .fill(DS.accentSoft)
                                .overlay {
                                    Text(String(creator.name.prefix(1)).uppercased())
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(DS.textSecondary)
                                }
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        Text(creator.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(DS.text)
                        Text(creator.handle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.textMuted)
                        if let bio = creator.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(3)
                        }
                    }

                    Spacer()

                    creatorMetric("Followers", creator.followerCount)
                    creatorMetric("Posts", creator.postCount)
                    creatorMetric("Top", creator.topOutlierMultiplier.map { Int($0.rounded()) }, suffix: "x")
                }
            }
            .padding(16)
            .background(DS.surface.opacity(0.72), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.borderSubtle, lineWidth: 0.75))

            HStack(spacing: 8) {
                ForEach([SocialDiscoverySort.highestOutlier, .mostViewed, .mostLiked, .newest], id: \.rawValue) { sort in
                    Button(sort.displayName) {
                        sortMode = sort
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(sortMode == sort ? DS.text : DS.textMuted)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(sortMode == sort ? DS.surfaceElevated : DS.surface.opacity(0.72), in: Capsule())
                    .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 0.75))
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(sortedPosts.count) posts")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textMuted)
                    .monospacedDigit()
            }

            if sortedPosts.isEmpty {
                SwipeFileEmptyState(
                    title: "No posts cached yet",
                    subtitle: "This creator is in the graph. Their posts will appear here after the import finishes.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                SwipeDiscoverMasonryGrid(posts: sortedPosts, onSave: onSave, onOpen: onOpen)
            }
        }
    }

    private func creatorMetric(_ title: String, _ value: Int?, suffix: String = "") -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value.map { formatCount($0) + suffix } ?? "-")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.text)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
        }
    }
}

// MARK: - Discovery Filter Panel

private enum DiscoverPlatformStyle {
    /// Brand-tinted SF Symbol color per platform; falls back to ink for monochrome marks.
    static func tint(_ platform: SocialPlatform) -> Color {
        switch platform {
        case .youtube: return Color(hex: "#FF0000")
        case .substack: return Color(hex: "#FF6719")
        case .instagram: return Color(hex: "#E1306C")
        case .linkedin: return Color(hex: "#0A66C2")
        default: return DS.text
        }
    }
}

private struct FilterSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(DS.textMuted)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

private struct FilterCheckbox: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isOn ? DS.accent : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isOn ? DS.accent : DS.glassBorder, lineWidth: 1.5)
            )
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.textOnAccent)
                    .opacity(isOn ? 1 : 0)
            )
            .frame(width: 22, height: 22)
    }
}

private struct FilterRadio: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle().stroke(isOn ? DS.accent : DS.glassBorder, lineWidth: 1.5)
            Circle()
                .fill(DS.accent)
                .frame(width: 11, height: 11)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 22, height: 22)
    }
}

private struct FilterSegmentChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(isSelected ? DS.surfaceElevated : Color.clear))
                .overlay(Capsule().stroke(isSelected ? DS.border : DS.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct FilterCheckRow: View {
    let platform: SocialPlatform
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                FilterCheckbox(isOn: isOn)
                Image(systemName: platform.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DiscoverPlatformStyle.tint(platform))
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(SwipeDiscoveryFilterPresentation.platformLabel(platform))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? DS.glassInputFill : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(ProMotionSprings.hover) { self.hovering = hovering } }
        .accessibilityLabel(SwipeDiscoveryFilterPresentation.platformLabel(platform))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct FilterRadioRow: View {
    let title: String
    let systemImage: String
    let iconTint: Color
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? iconTint : DS.textMuted)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? DS.text : DS.textSecondary)
                Spacer(minLength: 8)
                FilterRadio(isOn: isOn)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? DS.glassInputFill : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(ProMotionSprings.hover) { self.hovering = hovering } }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct FilterFormatRow<Filter: CaseIterable & Hashable>: View {
    let platform: SocialPlatform
    @Binding var selection: Filter
    let label: (Filter) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: platform.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DiscoverPlatformStyle.tint(platform))
                    .accessibilityHidden(true)
                Text(SwipeDiscoveryFilterPresentation.platformLabel(platform))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            CodexFlowLayout(spacing: 7) {
                ForEach(Array(Filter.allCases), id: \.self) { option in
                    FilterSegmentChip(label: label(option), isSelected: option == selection) {
                        withAnimation(ProMotionSprings.snappy) { selection = option }
                    }
                }
            }
        }
    }
}

private struct FollowerBoundField: View {
    let title: String
    let value: Int?
    let onCommit: (Int?) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
            TextField("Any", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.text)
                .focused($isFocused)
                .onSubmit(commit)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.glassInputFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(isFocused ? DS.glassBorderFocused : DS.glassBorder, lineWidth: 1)
                )
        }
        .onAppear(perform: syncFromValue)
        .onChange(of: value) { _, _ in
            if !isFocused { syncFromValue() }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func syncFromValue() {
        text = value.map(String.init) ?? ""
    }

    private func commit() {
        onCommit(SocialFollowerRange.parseFollowerInput(text))
    }
}

private struct FilterPlatformsSection: View {
    @Binding var query: SocialDiscoveryQuery

    private let platforms = SwipeDiscoveryFilterPresentation.primaryPlatforms

    // Store semantics: an empty set means "all platforms".
    private var resolved: Set<SocialPlatform> {
        query.platforms.isEmpty ? Set(platforms) : query.platforms
    }

    private var selectedCount: Int { resolved.intersection(Set(platforms)).count }
    private var allSelected: Bool { selectedCount == platforms.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                FilterSectionHeader(title: "Platforms")
                Spacer()
                Button("Select all") { query.platforms = [] }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(allSelected ? DS.textMuted : DS.accent)
                    .disabled(allSelected)
            }
            Text("\(selectedCount) of \(platforms.count) selected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .padding(.bottom, 2)
            ForEach(platforms, id: \.rawValue) { platform in
                FilterCheckRow(platform: platform, isOn: resolved.contains(platform)) {
                    toggle(platform)
                }
            }
        }
    }

    private func toggle(_ platform: SocialPlatform) {
        var set = resolved
        if set.contains(platform) {
            set.remove(platform)
        } else {
            set.insert(platform)
        }
        // Collapse a full or empty selection back to "all" so the summary reads "All".
        query.platforms = (set.isEmpty || set == Set(platforms)) ? [] : set
    }
}

private struct FilterFormatSection: View {
    @Binding var query: SocialDiscoveryQuery

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FilterSectionHeader(title: "Format")
            FilterFormatRow(platform: .youtube, selection: $query.youtubeFormat) { $0.label }
            FilterFormatRow(platform: .substack, selection: $query.substackFormat) { $0.label }
            FilterFormatRow(platform: .instagram, selection: $query.instagramFormat) { $0.label }
            Text("Format lenses apply only to their own platform's posts.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FilterFollowersSection: View {
    @Binding var query: SocialDiscoveryQuery

    private let presets = SwipeDiscoveryFilterPresentation.followerPresets

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FilterSectionHeader(title: "Followers")
            CodexFlowLayout(spacing: 7) {
                ForEach(presets) { preset in
                    FilterSegmentChip(label: preset.label, isSelected: query.followerRange == preset.range) {
                        withAnimation(ProMotionSprings.snappy) { query.followerRange = preset.range }
                    }
                }
            }
            HStack(spacing: 10) {
                FollowerBoundField(title: "Min", value: query.followerRange.minValue) { newMin in
                    query.followerRange = .bounded(min: newMin, max: query.followerRange.maxValue)
                }
                FollowerBoundField(title: "Max", value: query.followerRange.maxValue) { newMax in
                    query.followerRange = .bounded(min: query.followerRange.minValue, max: newMax)
                }
            }
            Text("Tip: type values like 20k or 1.5m.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textMuted)
        }
    }
}

private struct FilterOutlierSection: View {
    @Binding var query: SocialDiscoveryQuery

    private let options = SwipeDiscoveryFilterPresentation.minimumOutlierOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FilterSectionHeader(title: "Min Outlier Score")
                .padding(.bottom, 4)
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                FilterRadioRow(
                    title: option.map { "\(Int($0))× or more" } ?? "Any score",
                    systemImage: "bolt.fill",
                    iconTint: DS.orange,
                    isOn: query.minimumOutlierMultiplier == option
                ) {
                    withAnimation(ProMotionSprings.snappy) { query.minimumOutlierMultiplier = option }
                }
            }
        }
    }
}

private struct FilterPostedSection: View {
    @Binding var query: SocialDiscoveryQuery

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FilterSectionHeader(title: "Posted Within")
                .padding(.bottom, 4)
            ForEach(SocialPostedWindow.allCases, id: \.rawValue) { window in
                FilterRadioRow(
                    title: window.displayName,
                    systemImage: "calendar",
                    iconTint: DS.info,
                    isOn: query.postedWindow == window
                ) {
                    withAnimation(ProMotionSprings.snappy) { query.postedWindow = window }
                }
            }
        }
    }
}

private struct SwipeDiscoverFilterPanel: View {
    @Binding var query: SocialDiscoveryQuery
    var maxHeight: CGFloat = 580

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FilterPlatformsSection(query: $query)
                sectionDivider
                FilterFormatSection(query: $query)
                sectionDivider
                FilterFollowersSection(query: $query)
                sectionDivider
                FilterOutlierSection(query: $query)
                sectionDivider
                FilterPostedSection(query: $query)
                if hasActiveFilters {
                    resetButton
                }
            }
            .padding(18)
        }
        .scrollIndicators(.never)
        .frame(width: 360)
        .frame(maxHeight: maxHeight)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(DS.glassBorder)
            .frame(height: 1)
            .opacity(0.7)
    }

    private var hasActiveFilters: Bool {
        !query.platforms.isEmpty ||
        !query.usesDefaultFormats ||
        query.followerRange != .any ||
        query.minimumOutlierMultiplier != nil ||
        query.postedWindow != .lastThreeMonths
    }

    private var resetButton: some View {
        Button(action: reset) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                Text("Reset filters")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DS.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.glassInputFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func reset() {
        withAnimation(ProMotionSprings.snappy) {
            query.platforms = []
            query.youtubeFormat = .all
            query.substackFormat = .all
            query.instagramFormat = .all
            query.followerRange = .any
            query.minimumOutlierMultiplier = nil
            query.postedWindow = .lastThreeMonths
        }
    }
}

private struct FilterAnchorKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct SwipeDiscoverFilterDropdown: View {
    @Binding var query: SocialDiscoveryQuery
    let anchor: CGRect
    let onDismiss: () -> Void

    private let panelWidth: CGFloat = 360

    var body: some View {
        GeometryReader { proxy in
            let topInset = anchor.maxY + 8
            let panelHeight = min(620, max(280, proxy.size.height - topInset - 24))
            let leadingX = min(
                max(16, anchor.maxX - panelWidth),
                max(16, proxy.size.width - panelWidth - 16)
            )

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                SwipeDiscoverFilterPanel(query: $query, maxHeight: panelHeight)
                    .cortexInspectorPanel(cornerRadius: 22)
                    .offset(x: leadingX, y: topInset)
                    .transition(
                        .scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity)
                    )
            }
        }
    }
}

private struct SwipeDiscoverSkeletonGrid: View {
    private let heights: [CGFloat] = [300, 240, 280, 260, 320, 250, 290, 244]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                SwipeSkeletonCard(height: height)
            }
        }
    }
}

private struct SwipeSkeletonCard: View {
    let height: CGFloat

    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.glassSectionFill)
                .frame(height: height * 0.52)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DS.glassSectionFill)
                .frame(maxWidth: .infinity)
                .frame(height: 12)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DS.glassSectionFill)
                .frame(width: 120, height: 12)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .swipeGlassCard(cornerRadius: 14)
        .dsRestingShadow()
        .opacity(reduceMotion ? 1 : (shimmer ? 0.55 : 1))
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
        .accessibilityHidden(true)
    }
}

private extension SocialPostSnapshot {
    func replacing(derived: SocialDerivedMetrics) -> SocialPostSnapshot {
        SocialPostSnapshot(
            id: id,
            platform: platform,
            provider: provider,
            providerPostID: providerPostID,
            canonicalURL: canonicalURL,
            title: title,
            body: body,
            media: media,
            author: author,
            publishedAt: publishedAt,
            detectedLanguage: detectedLanguage,
            format: format,
            metrics: metrics,
            derived: derived,
            transcriptState: transcriptState,
            saveState: saveState,
            rawProviderPayload: rawProviderPayload
        )
    }
}

private func formatCount(_ value: Int) -> String {
    let absValue = abs(value)
    if absValue >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if absValue >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
}

/// Formats a discovery engagement rate as a percentage. The discovery API and `SwipeAnalysis`
/// store this already multiplied by 100 (e.g. 6.4 → "6.4%"); values below 1 are treated as a
/// raw fraction (e.g. 0.064 → "6.4%") so both provider conventions render correctly.
private func formatEngagementRate(_ rate: Double) -> String {
    let pct = rate < 1 ? rate * 100 : rate
    return String(format: "%.1f%%", pct)
}

/// Extracts unique, display-ready hashtags ("#tag") from caption text, in order of appearance.
private func extractHashtags(from text: String) -> [String] {
    guard text.contains("#") else { return [] }
    let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
    var result: [String] = []
    var seen = Set<String>()
    let trimSet = CharacterSet(charactersIn: "#.,!?:;)(\"'“”’]}[{")
    for token in tokens where token.hasPrefix("#") && token.count > 1 {
        let cleaned = token.trimmingCharacters(in: trimSet)
        guard !cleaned.isEmpty else { continue }
        let tag = "#\(cleaned)"
        if seen.insert(tag.lowercased()).inserted {
            result.append(tag)
        }
    }
    return Array(result.prefix(30))
}

private struct DiscoverSignalCard: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(DS.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.15), in: Circle())
            Text(title)
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .swipeGlassCard(tint: tint, cornerRadius: 14)
        .dsRestingShadow()
    }
}

private struct SwipeFileBackground: View {
    var body: some View {
        DS.swipeLibraryBackground
            .ignoresSafeArea()
    }
}
