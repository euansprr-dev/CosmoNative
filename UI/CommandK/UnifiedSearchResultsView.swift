// CosmoOS/UI/CommandK/UnifiedSearchResultsView.swift
// Unified cross-library search results view for Command-K
// Shows results from all sources (database, swipes, ideas, readwise) grouped by type

import SwiftUI

// MARK: - UnifiedSearchResultsView

struct UnifiedSearchResultsView: View {

    @ObservedObject var viewModel: CommandKViewModel

    var body: some View {
        if viewModel.unifiedFlatResults.isEmpty && viewModel.currentPhase != .searching {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        toolbarRow

                        ForEach(viewModel.unifiedGroupedResults, id: \.source) { group in
                            sectionView(source: group.source, results: group.results)
                        }
                    }
                    .padding(.horizontal, CommandKMetrics.contentPadding)
                    .padding(.vertical, 16)
                }
                .onChange(of: viewModel.selectedResultIndex) { _, _ in
                    if viewModel.selectedResultIndex >= 0,
                       viewModel.selectedResultIndex < viewModel.unifiedFlatResults.count {
                        let result = viewModel.unifiedFlatResults[viewModel.selectedResultIndex]
                        withAnimation(ProMotionSprings.snappy) {
                            proxy.scrollTo(result.id, anchor: .center)
                        }
                    }
                }
            }
        }
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

    // MARK: - Section

    @ViewBuilder
    private func sectionView(source: UnifiedSearchSource, results: [UnifiedSearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: source.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(source.accentColor)

                Text(source.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(DS.textSecondary)
                    .tracking(0.8)

                Text("\(results.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(source.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(source.accentColor.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Result rows
            VStack(spacing: 2) {
                ForEach(results.prefix(8)) { result in
                    resultRow(result)
                        .id(result.id)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .commandKSectionChrome()
    }

    // MARK: - Result Row

    @ViewBuilder
    private func resultRow(_ result: UnifiedSearchResult) -> some View {
        let isSelected = isResultSelected(result)

        Button {
            openResult(result)
        } label: {
            resultRowContent(result, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func resultRowContent(_ result: UnifiedSearchResult, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: result.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(result.accentColor)
                .frame(width: 28, height: 28)
                .background(result.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            // Title + snippet
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                if let snippet = result.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 11))
                        .foregroundColor(DS.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Subtitle badge
            if let subtitle = result.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(result.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(result.accentColor.opacity(0.08))
                    .clipShape(Capsule())
            }

            // Relevance indicator (for atom results with meaningful scores)
            if result.source == .atoms, result.relevance > 0.01 {
                Text("\(Int(result.relevance * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(DS.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? result.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? result.accentColor.opacity(0.25) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
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

    private func isResultSelected(_ result: UnifiedSearchResult) -> Bool {
        let selectedId = result.atomUUID ?? result.id
        return viewModel.selectedNodeId == selectedId
    }

    private func openResult(_ result: UnifiedSearchResult) {
        if let atomUUID = result.atomUUID {
            Task {
                try? await NodeGraphEngine.shared.recordAccess(atomUUID: atomUUID, type: .view)
            }
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                object: nil,
                userInfo: ["atomUUID": atomUUID]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        } else if let bookId = result.readwiseBookId {
            viewModel.selectedReadwiseBookId = bookId
        }
    }
}
