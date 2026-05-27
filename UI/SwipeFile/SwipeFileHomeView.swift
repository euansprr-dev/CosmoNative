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
        CommandCenterGlassRail(cornerRadius: 24) {
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

struct SwipeFileDiscoverPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Discover")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(DS.text)
                Text("High-performing posts across platforms")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }

            HStack(spacing: 12) {
                DiscoverSignalCard(title: "Productivity", systemImage: "bolt", tint: Color(hex: "#34D399"))
                DiscoverSignalCard(title: "Self-improvement", systemImage: "sparkles", tint: Color(hex: "#818CF8"))
                DiscoverSignalCard(title: "Business", systemImage: "briefcase", tint: Color(hex: "#F59E0B"))
                DiscoverSignalCard(title: "Psychology", systemImage: "brain.head.profile", tint: Color(hex: "#38BDF8"))
            }

            SwipeFileEmptyState(
                title: "Discovery engine pending",
                subtitle: "The feed shell is ready for platform imports.",
                systemImage: "chart.line.uptrend.xyaxis"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SwipeFileBackground())
    }
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
