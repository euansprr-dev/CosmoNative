import SwiftUI

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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? tint : DS.textMuted)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                isSelected ? tint.opacity(DS.palette.isDark ? 0.18 : 0.12) : DS.surface.opacity(0.74),
                in: Capsule()
            )
            .overlay(Capsule().stroke(isSelected ? tint.opacity(0.38) : DS.borderSubtle, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }
}

private struct SwipeMenuLabel: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(isSelected ? DS.accentSoft : DS.surface.opacity(0.74), in: Capsule())
        .overlay(Capsule().stroke(isSelected ? DS.accent.opacity(0.28) : DS.borderSubtle, lineWidth: 0.75))
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
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 58, height: 58)
                .background(DS.surface, in: Circle())

            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DS.text)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

struct SwipeFileDiscoverView: View {
    let section: SwipeDiscoverySectionSelection
    @ObservedObject var swipeLibraryViewModel: SwipeLibraryViewModel

    @StateObject private var viewModel = SwipeFileDiscoverViewModel()
    @State private var showingFilters = false
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
                            onSave: viewModel.save
                        )
                    } else {
                        SwipeDiscoverCreatorDirectory(
                            viewModel: viewModel,
                            onSelectCreator: { selectedCreatorID = $0.id }
                        )
                    }
                } else {
                    SwipeDiscoverFeed(
                        section: section,
                        viewModel: viewModel
                    )
                }
            }
            .padding(36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SwipeFileBackground())
        .task {
            await viewModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.SwipeFile.creatorDataChanged)) { _ in
            Task { await viewModel.reload() }
        }
        .onChange(of: section) { _ in
            selectedCreatorID = nil
        }
    }
}

@MainActor
private final class SwipeFileDiscoverViewModel: ObservableObject {
    @Published var query = SocialDiscoveryQuery()
    @Published var creatorSearchText = ""
    @Published var creatorSortMode: SocialDiscoverySort = .highestOutlier
    @Published private(set) var posts: [SocialPostSnapshot] = []
    @Published private(set) var creators: [SwipeDiscoverCreatorRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isAddingCreator = false
    @Published var errorMessage: String?
    @Published var saveMessage: String?
    @Published var creatorImportMessage: String?
    @Published var creatorImportError: String?

    private var hasLoaded = false
    private let remoteStore = SocialDiscoveryRemoteStore()

    var visiblePosts: [SocialPostSnapshot] {
        SocialDiscoveryStore(query: query, posts: posts).visiblePosts
    }

    var highPerformingPosts: [SocialPostSnapshot] {
        var highQuery = query
        highQuery.minimumOutlierMultiplier = max(query.minimumOutlierMultiplier ?? 10, 10)
        highQuery.sort = .highestOutlier
        return SocialDiscoveryStore(query: highQuery, posts: posts).visiblePosts
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
        isLoading = true
        errorMessage = nil

        do {
            if remoteStore.isConfigured {
                var remoteQuery = query
                remoteQuery.searchText = ""
                remoteQuery.platforms = []
                remoteQuery.minimumOutlierMultiplier = nil
                remoteQuery.postedWindow = .allTime
                remoteQuery.limit = 1_000

                let remoteCreators = try await remoteStore.fetchCreators()
                creators = remoteCreatorRecords(creators: remoteCreators, posts: posts)
                hasLoaded = true

                do {
                    let remotePosts = try await remoteStore.fetchPosts(query: remoteQuery, creators: remoteCreators)
                    posts = remotePosts
                    creators = remoteCreatorRecords(creators: remoteCreators, posts: remotePosts)
                } catch {
                    errorMessage = "Cloud posts are still loading: \(error.localizedDescription)"
                }

                isLoading = false
                return
            }

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

    func refreshDiscovery() async {
        guard remoteStore.isConfigured else {
            await reload()
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await remoteStore.refreshDue(limit: 25, force: true)
            saveMessage = "Discovery refreshed"
        } catch {
            errorMessage = "Cloud refresh failed: \(error.localizedDescription). Showing cached results."
        }

        await reload()
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

                hasLoaded = false
                await reload()
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

        _ = try await AtomRepository.shared.create(atom)
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.creatorDataChanged, object: nil)
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(DS.text)
                    Text(section.subtitle)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                }

                Spacer(minLength: 16)

                Button {
                    isShowingFilters.toggle()
                } label: {
                    Label(SwipeDiscoveryFilterPresentation.summary(for: query), systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingFilters, arrowEdge: .top) {
                    SwipeDiscoverFilterPanel(query: $query)
                        .frame(width: 360)
                        .padding(14)
                }

                Button("Reload", systemImage: "arrow.clockwise", action: onRefresh)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(DS.borderSubtle, lineWidth: 0.75))
                    .buttonStyle(.plain)
                    .help("Reload discovery")
            }

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(searchFocused ? DS.accent : DS.textMuted)

                    TextField(searchPlaceholder, text: activeSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.text)
                        .focused($searchFocused)
                        .onSubmit {
                            if section == .creators {
                                onAddCreator()
                            }
                        }

                    if !activeSearchText.wrappedValue.isEmpty {
                        Button("Clear", systemImage: "xmark.circle.fill") {
                            activeSearchText.wrappedValue = ""
                        }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(searchFocused ? DS.borderActive : DS.borderSubtle, lineWidth: 1)
                )

                if section == .creators {
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAddCreator)
                }
            }
        }
    }
}

private struct SwipeDiscoverPillarStrip: View {
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                DiscoverSignalCard(title: "Productivity", systemImage: "bolt", tint: Color(hex: "#34D399"))
                DiscoverSignalCard(title: "Self-improvement", systemImage: "sparkles", tint: Color(hex: "#818CF8"))
                DiscoverSignalCard(title: "Business", systemImage: "briefcase", tint: Color(hex: "#F59E0B"))
                DiscoverSignalCard(title: "Psychology", systemImage: "brain.head.profile", tint: Color(hex: "#38BDF8"))
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
    let section: SwipeDiscoverySectionSelection
    @ObservedObject var viewModel: SwipeFileDiscoverViewModel

    private var posts: [SocialPostSnapshot] {
        section == .highPerformers ? viewModel.highPerformingPosts : viewModel.visiblePosts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(section == .highPerformers ? "High-Performing Matches" : "All Matches")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(DS.text)
                Text("\(posts.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textMuted)
                    .monospacedDigit()
            }

            if viewModel.isLoading {
                SwipeDiscoverSkeletonGrid()
            } else if posts.isEmpty {
                if let error = viewModel.errorMessage {
                    SwipeFileEmptyState(title: "Discovery unavailable", subtitle: error, systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    SwipeFileEmptyState(
                        title: "No discovered posts yet",
                        subtitle: "Import creator catalogs to populate the cross-platform feed.",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            } else if let error = viewModel.errorMessage {
                SwipeDiscoverCreatorImportNotice(message: error, systemImage: "exclamationmark.triangle", tint: .orange)
                SwipeDiscoverMasonryGrid(posts: posts, onSave: viewModel.save)
            } else {
                SwipeDiscoverMasonryGrid(posts: posts, onSave: viewModel.save)
            }
        }
    }
}

private struct SwipeDiscoverMasonryGrid: View {
    let posts: [SocialPostSnapshot]
    let onSave: (SocialPostSnapshot, String?) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 16, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(posts) { post in
                SwipeDiscoverPostCard(post: post, onSave: onSave)
            }
        }
    }
}

private struct SwipeDiscoverPostCard: View {
    let post: SocialPostSnapshot
    let onSave: (SocialPostSnapshot, String?) -> Void

    @State private var isHovered = false

    private var thumbnailURL: URL? {
        post.media.first(where: { $0.kind == .thumbnail || $0.kind == .image })?.url
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
        switch previewAspect {
        case .wide: return 16.0 / 9.0
        case .portrait: return 1.0
        case .vertical: return 9.0 / 16.0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mediaHeader
            VStack(alignment: .leading, spacing: 12) {
                authorRow
                Text(post.body ?? post.title ?? post.canonicalURL.absoluteString)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(6)
                metricRow
                footerRow
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(DS.surface.opacity(0.74), in: cardShape)
        .overlay(
            cardShape
                .stroke(isHovered ? DS.accent.opacity(0.32) : DS.borderSubtle, lineWidth: 0.85)
        )
        .clipShape(cardShape)
        .contentShape(cardShape)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mediaHeader: some View {
        if let thumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderMedia
                case .empty:
                    placeholderMedia.redacted(reason: .placeholder)
                @unknown default:
                    placeholderMedia
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(mediaAspectRatio, contentMode: .fill)
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .aspectRatio(post.format == .text ? 4.0 / 3.0 : mediaAspectRatio, contentMode: .fit)
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
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
            }
    }

    private var authorRow: some View {
        HStack(spacing: 8) {
            Text(post.author.displayName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
            Text("@\(post.author.handle)")
                .font(.system(size: 12, weight: .medium))
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
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(DS.textMuted)
    }

    private var footerRow: some View {
        HStack {
            if let date = post.publishedAt {
                Text(date, style: .relative)
                    .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.text)
                    .frame(width: 30, height: 30)
                    .background(DS.surfaceElevated, in: Circle())
                    .overlay(Circle().stroke(DS.borderSubtle, lineWidth: 0.75))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .help("Add to board")
        }
    }

    private var platformBadge: some View {
        Label(post.platform.displayName, systemImage: post.platform.iconName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(DS.text)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(.regularMaterial, in: Capsule())
    }

    private var outlierBadge: some View {
        Text(post.derived.outlierMultiplier.map { "\(Int($0.rounded()))x" } ?? "new")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(post.derived.outlierMultiplier == nil ? DS.textMuted : DS.accent)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(DS.surfaceElevated, in: Capsule())
    }

    private func metric(_ systemImage: String, _ value: Int?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(value.map(formatCount) ?? "-")
        }
    }
}

private struct SwipeDiscoverCreatorDirectory: View {
    @ObservedObject var viewModel: SwipeFileDiscoverViewModel
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
                SwipeDiscoverMasonryGrid(posts: sortedPosts, onSave: onSave)
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

private struct SwipeDiscoverFilterPanel: View {
    @Binding var query: SocialDiscoveryQuery

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            filterSection("Platforms") {
                ForEach(SwipeDiscoveryFilterPresentation.primaryPlatforms, id: \.rawValue) { platform in
                    Toggle(isOn: platformBinding(platform)) {
                        Label(platform.displayName, systemImage: platform.iconName)
                    }
                }
            }

            filterSection("Posted") {
                Picker("Posted", selection: $query.postedWindow) {
                    ForEach(SocialPostedWindow.allCases, id: \.rawValue) { window in
                        Text(window.displayName).tag(window)
                    }
                }
                .pickerStyle(.segmented)
            }

            filterSection("Min Outlier Score") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(SwipeDiscoveryFilterPresentation.minimumOutlierOptions.indices, id: \.self) { index in
                        let option = SwipeDiscoveryFilterPresentation.minimumOutlierOptions[index]
                        Button {
                            query.minimumOutlierMultiplier = option
                        } label: {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text(option.map { "\(Int($0))x or more" } ?? "Any")
                                Spacer()
                                if query.minimumOutlierMultiplier == option {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            filterSection("Followers") {
                HStack {
                    followerButton("Any", range: .any)
                    followerButton("1K-20K", range: .range(min: 1_000, max: 20_000))
                    followerButton("20K-100K", range: .range(min: 20_000, max: 100_000))
                    followerButton("100K-1M", range: .range(min: 100_000, max: 1_000_000))
                    followerButton("1M+", range: .range(min: 1_000_000, max: nil))
                }
            }
        }
    }

    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
            content()
        }
    }

    private func platformBinding(_ platform: SocialPlatform) -> Binding<Bool> {
        Binding {
            query.platforms.contains(platform)
        } set: { isOn in
            if isOn {
                query.platforms.insert(platform)
            } else {
                query.platforms.remove(platform)
            }
        }
    }

    private func followerButton(_ title: String, range: SocialFollowerRange) -> some View {
        Button(title) {
            query.followerRange = range
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(query.followerRange == range ? DS.accent : DS.textSecondary)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(query.followerRange == range ? DS.accentSoft : DS.surface, in: Capsule())
        .buttonStyle(.plain)
    }
}

private struct SwipeDiscoverSkeletonGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(DS.surface)
                    .frame(height: 260)
                    .redacted(reason: .placeholder)
            }
        }
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

private struct DiscoverSignalCard: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 0.75)
        )
    }
}

private struct SwipeFileBackground: View {
    var body: some View {
        DS.swipeLibraryBackground
            .ignoresSafeArea()
    }
}
