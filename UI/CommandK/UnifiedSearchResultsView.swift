// CosmoOS/UI/CommandK/UnifiedSearchResultsView.swift
// Unified cross-library search results view for Command-K
// Pinterest-style masonry grid using actual library cards

import SwiftUI

// MARK: - UnifiedSearchResultsView

struct UnifiedSearchResultsView: View {

    @ObservedObject var viewModel: CommandKViewModel

    private let minCardWidth: CGFloat = 248
    private let cardSpacing: CGFloat = CommandKMetrics.cardSpacing

    var body: some View {
        if viewModel.unifiedFlatResults.isEmpty && viewModel.currentPhase != .searching {
            emptyState
        } else {
            GeometryReader { geometry in
                let columnCount = max(2, Int(geometry.size.width / (minCardWidth + cardSpacing)))
                let totalSpacing = CGFloat(columnCount - 1) * cardSpacing + (CommandKMetrics.contentPadding * 2)
                let cardWidth = (geometry.size.width - totalSpacing) / CGFloat(columnCount)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            toolbarRow
                                .padding(.horizontal, CommandKMetrics.contentPadding)

                            MasonryLayout(columnCount: columnCount, spacing: cardSpacing) {
                                ForEach(Array(viewModel.unifiedCardItems.enumerated()), id: \.element.id) { index, item in
                                    let isSelected = viewModel.selectedNodeId == item.uuid

                                    LibraryCardView(
                                        item: item,
                                        cardWidth: cardWidth,
                                        isSelected: isSelected
                                    )
                                    .id(item.uuid)
                                    .onTapGesture {
                                        openItem(item)
                                    }
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                    .animation(
                                        ProMotionSprings.cardEntrance.delay(Double(index % 16) * 0.03),
                                        value: viewModel.unifiedCardItems.count
                                    )
                                }

                                ForEach(readwiseResults) { result in
                                    readwiseCard(result, cardWidth: cardWidth)
                                        .id(result.id)
                                }
                            }
                            .padding(.horizontal, CommandKMetrics.contentPadding)
                        }
                        .padding(.vertical, 16)
                    }
                    .onChange(of: viewModel.selectedResultIndex) { _, _ in
                        if viewModel.selectedResultIndex >= 0,
                           viewModel.selectedResultIndex < viewModel.unifiedFlatResults.count {
                            let result = viewModel.unifiedFlatResults[viewModel.selectedResultIndex]
                            let scrollId = result.atomUUID ?? result.id
                            withAnimation(ProMotionSprings.snappy) {
                                proxy.scrollTo(scrollId, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Readwise Card

    private var readwiseResults: [UnifiedSearchResult] {
        viewModel.unifiedFlatResults.filter { $0.source == .readwise }
    }

    @ViewBuilder
    private func readwiseCard(_ result: UnifiedSearchResult, cardWidth: CGFloat) -> some View {
        let isSelected = viewModel.selectedNodeId == result.id
        let cornerRadius = CommandKMetrics.cardCornerRadius

        Button {
            if let bookId = result.readwiseBookId {
                viewModel.selectedReadwiseBookId = bookId
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    DS.entityReadwise.opacity(0.08)

                    Image(systemName: result.icon)
                        .font(.system(size: 30))
                        .foregroundColor(DS.entityReadwise.opacity(0.6))
                }
                .frame(height: 100)

                Rectangle()
                    .fill(DS.entityReadwise.opacity(0.18))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text(result.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.text)
                        .lineLimit(2)

                    if let snippet = result.snippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.system(size: 12))
                            .foregroundColor(DS.textMuted)
                            .lineLimit(2)
                    }

                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 10))
                            Text("Readwise")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(DS.entityReadwise)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DS.entityReadwise.opacity(0.10))
                        .clipShape(Capsule())

                        Spacer()

                        if let subtitle = result.subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(DS.textMuted)
                        }
                    }
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .commandKGalleryCardChrome(
                isHovered: false,
                isSelected: isSelected,
                accentColor: DS.entityReadwise,
                cornerRadius: cornerRadius
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            let total = viewModel.unifiedFlatResults.count
            Text("\(total) result\(total == 1 ? "" : "s") across all libraries")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textSecondary)

            if viewModel.isAIRanked {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                    Text("AI ranked")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(DS.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.accentSoft)
                .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(DS.textMuted)

            Text("No results found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.textSecondary)

            VStack(spacing: 6) {
                Text("Try different keywords or use prefixes:")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textMuted)

                HStack(spacing: 8) {
                    prefixHint("#idea")
                    prefixHint("#swipe")
                    prefixHint("#content")
                    prefixHint("task:")
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func prefixHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(DS.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
    }

    // MARK: - Helpers

    private func openItem(_ item: LibraryItem) {
        Task {
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: item.uuid, type: .view)
        }
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil,
            userInfo: ["atomUUID": item.uuid]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }
}
