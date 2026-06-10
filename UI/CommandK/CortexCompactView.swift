// CosmoOS/UI/CommandK/CortexCompactView.swift
// Compact mode: space plates + recents grid, Atelier language.

import SwiftUI

struct CortexCompactView: View {
    var viewModel: CommandKViewModel
    var namespace: Namespace.ID
    var openDomain: (CommandKTab) -> Void

    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            CommandKSectionLabel(label: "SPACES")
                .atelierStaggerIn(delay: 0.10, appeared: hasAppeared)
            domainCardsRow
            if !viewModel.recentItems.isEmpty {
                recentsSection
            }
        }
        .padding(.horizontal, DS.space32)
        .padding(.vertical, DS.space24)
        .onAppear { hasAppeared = true }
    }

    // MARK: - Space Plates

    private var domainCardsRow: some View {
        HStack(spacing: DS.space20) {
            ForEach(Array(CommandKTab.allCases.enumerated()), id: \.element.rawValue) { index, tab in
                CortexDomainBubble(
                    tab: tab,
                    count: viewModel.domainCounts[tab] ?? 0,
                    namespace: namespace
                ) {
                    openDomain(tab)
                }
                .atelierStaggerIn(delay: 0.16 + Double(index) * 0.06, appeared: hasAppeared)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Recents Section

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CommandKSectionLabel(label: "RECENTS")
                .atelierStaggerIn(delay: 0.42, appeared: hasAppeared)
            recentsGrid
        }
    }

    private var recentsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: CommandKMetrics.recentCardMinWidth, maximum: 214), spacing: DS.space12)],
            spacing: DS.space12
        ) {
            ForEach(Array(viewModel.recentItems.enumerated()), id: \.element.id) { index, item in
                CortexRecentCard(item: item) {
                    viewModel.openRecent(item)
                } onDelete: {
                    viewModel.deleteRecent(item)
                }
                .atelierStaggerIn(delay: 0.48 + Double(index) * 0.03, appeared: hasAppeared)
            }
        }
    }
}
