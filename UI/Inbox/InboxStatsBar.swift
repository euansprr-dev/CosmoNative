// CosmoOS/UI/Inbox/InboxStatsBar.swift
// Stats bar with classification counts and filter chips
// March 2026

import SwiftUI

struct InboxStatsBar: View {
    @Bindable var viewModel: InboxViewModel

    var body: some View {
        VStack(spacing: DS.space8) {
            statsRow
            filterRow
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space10)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: DS.space12) {
            statBadge(
                count: viewModel.stats.mergeCount,
                label: "merge",
                color: DS.orange
            )
            statBadge(
                count: viewModel.stats.placeCount,
                label: "place",
                color: DS.accent
            )
            statBadge(
                count: viewModel.stats.newCount,
                label: "new",
                color: Color(hex: "818CF8")
            )

            if viewModel.stats.pendingCount > 0 {
                statBadge(
                    count: viewModel.stats.pendingCount,
                    label: "classifying",
                    color: DS.textMuted
                )
            }

            Spacer()

            Text("\(viewModel.stats.total) awaiting triage")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private func statBadge(count: Int, label: String, color: Color) -> some View {
        if count > 0 {
            HStack(spacing: DS.space4) {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text(label)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    // MARK: - Filter Row

    private var filterRow: some View {
        HStack(spacing: DS.space6) {
            // Source filters
            sourceFilterChip("All", source: nil)
            sourceFilterChip("Telegram", source: .telegramText)
            sourceFilterChip("Voice", source: .telegramVoice)
            sourceFilterChip("Capture", source: .quickCapture)

            Divider()
                .frame(height: 16)
                .foregroundStyle(DS.borderSubtle)

            // Classification filters
            classificationFilterChip("Merge", classification: .merge, color: DS.orange)
            classificationFilterChip("Place", classification: .place, color: DS.accent)
            classificationFilterChip("New", classification: .new, color: Color(hex: "818CF8"))

            Spacer()

            sortMenu

            if viewModel.hasActiveFilters {
                clearFiltersButton
            }
        }
    }

    // MARK: - Filter Chips

    private func sourceFilterChip(_ label: String, source: InboxSource?) -> some View {
        let isActive = viewModel.activeSourceFilter == source
        return Button {
            withAnimation(ProMotionSprings.snappy) {
                if let source {
                    viewModel.toggleSourceFilter(source)
                } else {
                    viewModel.activeSourceFilter = nil
                    viewModel.activeClassificationFilter = nil
                }
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.accent : DS.textSecondary)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space4)
                .background(
                    isActive ? DS.accentSoft : DS.surface,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? DS.accent.opacity(0.3) : DS.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func classificationFilterChip(_ label: String, classification: InboxClassification, color: Color) -> some View {
        let isActive = viewModel.activeClassificationFilter == classification
        return Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.toggleClassificationFilter(classification)
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? color : DS.textSecondary)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space4)
                .background(
                    isActive ? color.opacity(0.12) : DS.surface,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? color.opacity(0.3) : DS.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(InboxSortOrder.allCases, id: \.self) { order in
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.setSortOrder(order)
                    }
                } label: {
                    HStack {
                        Text(order.rawValue)
                        if viewModel.sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10))
                Text(viewModel.sortOrder.rawValue)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(DS.surface, in: Capsule())
            .overlay(Capsule().stroke(DS.border, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
    }

    private var clearFiltersButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.clearFilters()
            }
        } label: {
            HStack(spacing: DS.space2) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Clear")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DS.textMuted)
        }
        .buttonStyle(.plain)
    }
}
