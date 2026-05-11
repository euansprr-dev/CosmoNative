// CosmoOS/UI/CommandK/CortexCompactView.swift
// Compact mode: domain bubbles + recents grid + keyboard hints

import SwiftUI

struct CortexCompactView: View {
    @ObservedObject var viewModel: CommandKViewModel
    var namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            header
            domainCardsRow
            Divider()
                .foregroundStyle(DS.glassBorder.opacity(0.58))
            if !viewModel.recentItems.isEmpty {
                recentsSection
            }
        }
        .padding(.horizontal, DS.space32)
        .padding(.vertical, DS.space24)
    }

    private var header: some View {
        HStack {
            Text("Open a space")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(DS.text)

            Spacer()

            Image(systemName: "square.grid.2x2")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 36, height: 36)
                .background(DS.glassCardFill.opacity(0.56), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(DS.glassBorder.opacity(0.62), lineWidth: 0.5)
                )
                .accessibilityHidden(true)
        }
    }

    // MARK: - Domain Bubbles

    private var domainCardsRow: some View {
        HStack(spacing: DS.space20) {
            ForEach(CommandKTab.allCases, id: \.rawValue) { tab in
                CortexDomainBubble(
                    tab: tab,
                    count: viewModel.domainCounts[tab] ?? 0,
                    namespace: namespace
                ) {
                    withAnimation(ProMotionSprings.modal) {
                        viewModel.transitionToExpanded(tab)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Recents Section

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            recentsHeader
            recentsGrid
        }
    }

    private var recentsHeader: some View {
        HStack {
            Text("Recents")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(DS.text)
            Spacer()
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
                .transition(.opacity.combined(with: .offset(y: 6)))
                .animation(ProMotionSprings.staggered(index: index), value: viewModel.recentItems.count)
            }
        }
    }
}
