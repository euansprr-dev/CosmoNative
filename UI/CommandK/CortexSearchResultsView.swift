// CosmoOS/UI/CommandK/CortexSearchResultsView.swift
// Grouped search results for Cortex search mode — sections by source with "See all" navigation

import SwiftUI

struct CortexSearchResultsView: View {
    @ObservedObject var viewModel: CommandKViewModel

    var body: some View {
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
    let onSeeAll: () -> Void
    let onSelect: (UnifiedSearchResult) -> Void

    /// Max items to show per section
    private var maxItems: Int {
        switch source {
        case .atoms: return 8
        case .swipes: return 4
        case .ideas: return 3
        case .readwise: return 3
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
            atomHorizontalCards
        case .swipes, .readwise:
            horizontalCards
        case .ideas:
            listRows
        }
    }

    private var atomHorizontalCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.space12) {
                ForEach(results.prefix(maxItems)) { result in
                    if let key = result.libraryLookupKey, let item = libraryItemsByID[key] {
                        LibraryCardView(item: item, cardWidth: 220, isSelected: selectedId == result.selectionID)
                            .frame(width: 220)
                            .id(result.selectionID)
                            .onTapGesture { onSelect(result) }
                            .commandKSearchResultContextMenu(result: result)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private var listRows: some View {
        VStack(spacing: 0) {
            ForEach(results.prefix(maxItems)) { result in
                CortexSearchRow(
                    result: result,
                    isSelected: selectedId == result.selectionID,
                    onSelect: { onSelect(result) }
                )
                .id(result.selectionID)
            }
        }
        .background(DS.glassCardFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.border.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var horizontalCards: some View {
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

// MARK: - Search Row (for Database/Ideas)

private struct CortexSearchRow: View {
    let result: UnifiedSearchResult
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DS.space12) {
                Image(systemName: result.icon)
                    .font(DS.callout)
                    .foregroundStyle(result.accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(DS.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    if let subtitle = result.subtitle ?? result.snippet {
                        Text(subtitle)
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let atomType = result.atomType {
                    Text(atomType.displayName)
                        .font(DS.caption2)
                        .foregroundStyle(result.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(result.accentColor.opacity(0.10), in: Capsule())
                }
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space10)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel(result.title)
        .commandKSearchResultContextMenu(result: result)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            DS.accent.opacity(0.12)
        } else if isHovered {
            DS.glassCardFill.opacity(0.5)
        } else {
            Color.clear
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
