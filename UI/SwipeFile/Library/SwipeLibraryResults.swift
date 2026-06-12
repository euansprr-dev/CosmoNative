import SwiftUI

// MARK: - Date buckets (Recently Added)

struct SwipeLibraryDateBucket: Equatable, Identifiable {
    let title: String
    let models: [SwipeCardModel]

    var id: String { title }

    static func buckets(items: [SwipeGalleryItem], models: [SwipeCardModel]) -> [SwipeLibraryDateBucket] {
        let calendar = Calendar.current
        let now = Date()
        var today: [SwipeCardModel] = []
        var thisWeek: [SwipeCardModel] = []
        var earlier: [SwipeCardModel] = []

        for (item, model) in zip(items, models) {
            let date = ISO8601.date(from: item.createdAt) ?? .distantPast
            if calendar.isDateInToday(date) {
                today.append(model)
            } else if date > now.addingTimeInterval(-7 * 24 * 3600) {
                thisWeek.append(model)
            } else {
                earlier.append(model)
            }
        }

        return [
            SwipeLibraryDateBucket(title: "Today", models: today),
            SwipeLibraryDateBucket(title: "This Week", models: thisWeek),
            SwipeLibraryDateBucket(title: "Earlier", models: earlier)
        ].filter { !$0.models.isEmpty }
    }
}

// MARK: - Results

/// Routes between skeleton / error / empty / masonry / buckets / compact list.
struct SwipeLibraryResults: View {
    @Bindable var viewModel: SwipeLibraryViewModel
    let frameStore: SwipeFrameStore
    let revealDate: Date
    let onOpen: (String) -> Void
    let onStudy: (String) -> Void

    var body: some View {
        if viewModel.isLoading && viewModel.allItems.isEmpty {
            SwipeSkeletonGrid()
        } else if let error = viewModel.errorMessage, viewModel.allItems.isEmpty {
            SwipeLibraryErrorState(message: error) {
                Task { await viewModel.reload() }
            }
        } else if viewModel.visibleCardModels.isEmpty {
            SwipeLibraryEmptyState(
                scope: viewModel.scope,
                hasActiveFilters: viewModel.filterState.hasActiveFilters || !viewModel.query.isEmpty,
                onClearFilters: { viewModel.resetFilters() }
            )
        } else if viewModel.displayMode == .compact {
            SwipeLibraryCompactList(viewModel: viewModel, onOpen: onOpen, onStudy: onStudy)
        } else if !viewModel.recentBuckets.isEmpty {
            bucketedGrids
        } else {
            grid(models: viewModel.visibleCardModels, indexOffset: 0)
        }
    }

    private var bucketedGrids: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            ForEach(viewModel.recentBuckets) { bucket in
                VStack(alignment: .leading, spacing: DS.space12) {
                    bucketHeader(bucket)
                    grid(models: bucket.models, indexOffset: bucketOffset(for: bucket))
                }
            }
        }
    }

    private func bucketHeader(_ bucket: SwipeLibraryDateBucket) -> some View {
        HStack(spacing: 8) {
            Text(bucket.title)
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
            Text("\(bucket.models.count)")
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.textMuted)
            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 0.5)
        }
    }

    private func bucketOffset(for bucket: SwipeLibraryDateBucket) -> Int {
        var offset = 0
        for candidate in viewModel.recentBuckets {
            if candidate.id == bucket.id { break }
            offset += candidate.models.count
        }
        return offset
    }

    private func grid(models: [SwipeCardModel], indexOffset: Int) -> some View {
        SwipeWaterfallGrid(
            items: models,
            targetColumnWidth: 252,
            spacing: 16,
            itemHeight: { model, width in model.height(forWidth: width) },
            cell: { model, width, index in
                SwipeLibraryCardCell(
                    model: model,
                    width: width,
                    index: index + indexOffset,
                    isSelected: viewModel.selectedItem?.id == model.id,
                    revealDate: revealDate,
                    frameStore: frameStore,
                    boardMenu: SwipeCardBoardMenu(
                        boards: SwipeBoardStore.shared.boards,
                        memberIDs: model.boardIDs,
                        onToggle: { board in viewModel.toggleBoard(board, itemID: model.id) }
                    ),
                    onOpen: onOpen,
                    onStudy: onStudy,
                    onAddToCanvas: { id in
                        if let item = viewModel.visibleItems.first(where: { $0.id == id }) {
                            viewModel.addToCanvas(item)
                        }
                    }
                )
            }
        )
    }
}

// MARK: - Card cell (entrance + frame recording + context menu)

private struct SwipeLibraryCardCell: View {
    let model: SwipeCardModel
    let width: CGFloat
    let index: Int
    let isSelected: Bool
    let revealDate: Date
    let frameStore: SwipeFrameStore
    let boardMenu: SwipeCardBoardMenu
    let onOpen: (String) -> Void
    let onStudy: (String) -> Void
    let onAddToCanvas: (String) -> Void

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwipeCard(
            model: model,
            width: width,
            isSelected: isSelected,
            actions: SwipeCardActions(
                onOpen: { onOpen(model.id) },
                onStudy: { onStudy(model.id) },
                boardMenu: boardMenu
            )
        )
        .contextMenu { contextMenuItems }
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.96)
        .onAppear(perform: animateEntrance)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("swipePage")) }) { frame in
            frameStore.frames[model.id] = frame
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Open Study", systemImage: "play.rectangle") { onStudy(model.id) }
        Button("Quick Look", systemImage: "eye") { onOpen(model.id) }
        Divider()
        Menu("Add to Board") {
            ForEach(boardMenu.boards) { board in
                Button {
                    boardMenu.onToggle(board)
                } label: {
                    if boardMenu.memberIDs.contains(board.uuid) {
                        Label(board.name, systemImage: "checkmark")
                    } else {
                        Label(board.name, systemImage: board.icon)
                    }
                }
            }
        }
        Button("Add to Canvas", systemImage: "square.grid.2x2") { onAddToCanvas(model.id) }
    }

    /// Cascade only on dataset reveal — cells entering via scroll appear instantly.
    private func animateEntrance() {
        guard !hasAppeared else { return }
        let isRevealWindow = Date().timeIntervalSince(revealDate) < 0.8
        guard isRevealWindow, index < 12, !reduceMotion else {
            hasAppeared = true
            return
        }
        withAnimation(ProMotionSprings.cascade(index: min(index, 8))) {
            hasAppeared = true
        }
    }
}

// MARK: - Compact list

private struct SwipeLibraryCompactList: View {
    @Bindable var viewModel: SwipeLibraryViewModel
    let onOpen: (String) -> Void
    let onStudy: (String) -> Void

    var body: some View {
        LazyVStack(spacing: 6) {
            ForEach(viewModel.visibleCardModels) { model in
                SwipeLibraryCompactRow(
                    model: model,
                    isSelected: viewModel.selectedItem?.id == model.id,
                    onOpen: { onOpen(model.id) },
                    onStudy: { onStudy(model.id) }
                )
            }
        }
    }
}

private struct SwipeLibraryCompactRow: View {
    let model: SwipeCardModel
    let isSelected: Bool
    let onOpen: () -> Void
    let onStudy: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(model.hookText)
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                metaLine
            }
            Spacer(minLength: 8)
            if let score = model.scoreLabel {
                Text(score)
                    .font(DS.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(model.scoreTint ?? DS.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .swipeCardSurface(isHovered: isHovered, isSelected: isSelected, tint: model.platformColor ?? DS.entitySwipe, cornerRadius: 12)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: onStudy)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.hookText)
        .accessibilityAddTraits(.isButton)
    }

    private var thumbnail: some View {
        CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty, .failure:
                Rectangle()
                    .fill(DS.glassSectionFill)
                    .overlay {
                        Image(systemName: model.platformGlyph ?? "doc.text")
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                    }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private var metaLine: some View {
        HStack(spacing: 5) {
            if model.isUnstudied {
                Circle().fill(DS.accent).frame(width: 5, height: 5)
            }
            Text([model.creatorLine, model.ageLabel].compactMap(\.self).joined(separator: " · "))
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
    }
}
