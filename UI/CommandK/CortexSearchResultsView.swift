// CosmoOS/UI/CommandK/CortexSearchResultsView.swift
// Grouped search results for Cortex search mode — sections by source with "See all" navigation

import SwiftUI

struct CortexSearchResultsView: View {
    @ObservedObject var viewModel: CommandKViewModel

    var body: some View {
        let swipeItemsByUUID = Dictionary(uniqueKeysWithValues: viewModel.swipeGalleryItems.map { ($0.atomUUID, $0) })
        let ideaItemsByUUID = Dictionary(uniqueKeysWithValues: viewModel.ideaGalleryItems.map { ($0.atomUUID, $0) })

        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: DS.space20) {
                    ForEach(Array(viewModel.unifiedGroupedResults.enumerated()), id: \.element.source) { _, group in
                        if !group.results.isEmpty {
                            CortexSearchSection(
                                source: group.source,
                                results: group.results,
                                selectedId: viewModel.selectedNodeId,
                                libraryItemsByID: viewModel.unifiedLibraryItemsByID,
                                swipeItemsByUUID: swipeItemsByUUID,
                                ideaItemsByUUID: ideaItemsByUUID,
                                onSeeAll: { seeAll(group.source) },
                                onSelect: { selectResult($0) }
                            )
                        }
                    }

                    if viewModel.currentPhase == .searching {
                        loadingState
                    } else if viewModel.unifiedGroupedResults.allSatisfy({ $0.results.isEmpty }) && viewModel.currentPhase == .complete {
                        emptyState
                    }
                }
                .padding(DS.space24)
            }
            .onChange(of: viewModel.selectedResultIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < viewModel.unifiedFlatResults.count else { return }
                let result = viewModel.unifiedFlatResults[newIndex]
                withAnimation(ProMotionSprings.snappy) {
                    proxy.scrollTo(result.selectionID, anchor: .center)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: DS.space8) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(DS.textMuted)
            Text("Searching...")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(DS.textMuted)
            Text("No results found")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }

    private func seeAll(_ source: UnifiedSearchSource) {
        let tab: CommandKTab = switch source {
        case .atoms: .database
        case .swipes: .swipeGallery
        case .ideas: .ideas
        case .readwise: .readwise
        }
        withAnimation(ProMotionSprings.modal) {
            viewModel.transitionToExpanded(tab)
        }
    }

    private func selectResult(_ result: UnifiedSearchResult) {
        viewModel.selectedNodeId = result.selectionID
        if let idx = viewModel.unifiedFlatResults.firstIndex(where: { $0.selectionID == result.selectionID }) {
            viewModel.selectedResultIndex = idx
        }
        viewModel.openSelected()
    }
}

// MARK: - Search Section

private struct CortexSearchSection: View {
    let source: UnifiedSearchSource
    let results: [UnifiedSearchResult]
    let selectedId: String?
    let libraryItemsByID: [String: LibraryItem]
    let swipeItemsByUUID: [String: SwipeGalleryItem]
    let ideaItemsByUUID: [String: IdeaGalleryItem]
    let onSeeAll: () -> Void
    let onSelect: (UnifiedSearchResult) -> Void

    private let databaseCardWidth: CGFloat = 126
    private let swipeCardWidth: CGFloat = 148

    /// Max items to show per section
    private var maxItems: Int {
        switch source {
        case .atoms: return 8
        case .swipes: return 4
        case .ideas: return 3
        case .readwise: return 3
        }
    }

    private var visibleAtomResults: [(result: UnifiedSearchResult, item: LibraryItem)] {
        results.prefix(maxItems).compactMap { result in
            guard let key = result.libraryLookupKey,
                  let item = libraryItemsByID[key] else { return nil }
            return (result, item)
        }
    }

    private var visibleSwipeResults: [(result: UnifiedSearchResult, item: SwipeGalleryItem)] {
        results.prefix(maxItems).compactMap { result in
            guard let atomUUID = result.atomUUID,
                  let item = swipeItemsByUUID[atomUUID] else { return nil }
            return (result, item)
        }
    }

    private var visibleIdeaResults: [(result: UnifiedSearchResult, item: IdeaGalleryItem)] {
        results.prefix(maxItems).compactMap { result in
            guard let atomUUID = result.atomUUID,
                  let item = ideaItemsByUUID[atomUUID] else { return nil }
            return (result, item)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionHeader
            sectionContent
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: source.icon)
                .font(DS.callout)
                .foregroundStyle(source.accentColor)

            Text(source.displayName)
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Text("\(results.count)")
                .font(DS.caption2)
                .foregroundStyle(source.accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(source.accentColor.opacity(0.12), in: Capsule())

            Spacer()

            if results.count > maxItems {
                Button(action: onSeeAll) {
                    HStack(spacing: 3) {
                        Text("See all")
                            .font(DS.caption)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(source.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch source {
        case .atoms:
            atomPreviewStrip
        case .swipes:
            swipePreviewStrip
        case .ideas:
            ideaPreviewList
        case .readwise:
            readwisePreviewStrip
        }
    }

    private var atomPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.space12) {
                ForEach(visibleAtomResults, id: \.result.id) { entry in
                    SpotlightDocCard(
                        item: entry.item,
                        onTap: { onSelect(entry.result) },
                        onDelete: {
                            Task { try? await AtomRepository.shared.delete(uuid: entry.item.uuid) }
                        }
                    )
                    .frame(width: databaseCardWidth)
                    .id(entry.result.selectionID)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private var swipePreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.space12) {
                ForEach(visibleSwipeResults, id: \.result.id) { entry in
                    CortexSwipeThumb(item: entry.item) {
                        onSelect(entry.result)
                    }
                    .frame(width: swipeCardWidth, alignment: .top)
                    .id(entry.result.selectionID)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private var ideaPreviewList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleIdeaResults.enumerated()), id: \.element.result.id) { index, entry in
                LedgerRow(item: entry.item) {
                    onSelect(entry.result)
                }
                .id(entry.result.selectionID)

                if index < visibleIdeaResults.count - 1 {
                    Rectangle()
                        .fill(DS.borderSubtle)
                        .frame(height: 0.5)
                        .padding(.leading, DS.space12)
                }
            }
        }
        .padding(DS.space12)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 16, y: 8)
    }

    private var readwisePreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space12) {
                ForEach(results.prefix(maxItems)) { result in
                    CortexSearchCard(
                        result: result,
                        isSelected: selectedId == result.selectionID,
                        onSelect: { onSelect(result) }
                    )
                    .id(result.selectionID)
                }
            }
        }
    }
}

// MARK: - Search Card (for Swipes/Readwise)

private struct CortexSearchCard: View {
    let result: UnifiedSearchResult
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: DS.space8) {
                cardPreview
                cardTitle
            }
            .frame(width: 160)
            .padding(DS.space10)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(
                color: .black.opacity(isHovered ? 0.07 : 0.03),
                radius: isHovered ? 10 : 5,
                x: 0,
                y: isHovered ? 3 : 1
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .commandKSearchResultContextMenu(result: result)
    }

    private var cardPreview: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(result.accentColor.opacity(0.08))
            .frame(height: 80)
            .overlay {
                Image(systemName: result.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(result.accentColor.opacity(0.4))
            }
    }

    private var cardTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.text)
                .lineLimit(2)

            if let subtitle = result.subtitle {
                Text(subtitle)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(DS.glassCardFill.opacity(isHovered ? 0.7 : 0.4))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(isSelected ? DS.accent.opacity(0.4) : DS.border.opacity(0.2), lineWidth: isSelected ? 1.5 : 0.5)
    }
}
