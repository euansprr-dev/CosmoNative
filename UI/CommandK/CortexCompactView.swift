// CosmoOS/UI/CommandK/CortexCompactView.swift
// Compact mode: domain bubbles + recents grid + keyboard hints

import SwiftUI

struct CortexCompactView: View {
    @ObservedObject var viewModel: CommandKViewModel
    var namespace: Namespace.ID

    var body: some View {
        VStack(spacing: DS.space20) {
            domainBubblesRow
            if !viewModel.recentItems.isEmpty {
                recentsSection
            }
            keyboardHintBar
        }
        .padding(DS.space24)
    }

    // MARK: - Domain Bubbles

    private var domainBubblesRow: some View {
        HStack(spacing: DS.space32) {
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
        .padding(.top, DS.space4)
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
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
    }

    private var recentsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: CommandKMetrics.recentCardMinWidth, maximum: 180), spacing: DS.space12)],
            spacing: DS.space12
        ) {
            ForEach(Array(viewModel.recentItems.enumerated()), id: \.element.id) { index, item in
                CortexRecentCard(item: item) {
                    viewModel.openRecent(item)
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
                .animation(ProMotionSprings.staggered(index: index), value: viewModel.recentItems.count)
            }
        }
    }

    // MARK: - Keyboard Hints

    private var keyboardHintBar: some View {
        HStack(spacing: DS.space16) {
            keyHint(keys: "↑↓", label: "Navigate")
            keyHint(keys: "↵", label: "Open")
            keyHint(keys: "⎋", label: "Close")
            Spacer()
        }
        .padding(.top, DS.space4)
    }

    private func keyHint(keys: String, label: String) -> some View {
        HStack(spacing: DS.space4) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(DS.vellumDeep, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(DS.sepiaSubtle, lineWidth: 0.5)
                )

            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }
}
