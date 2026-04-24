// CosmoOS/UI/Inbox/InboxView.swift
// Smart Triage Inbox — capture bar, temporal grouping, filters, batch actions,
// keyboard navigation, intelligence, and beautiful empty state
// March 2026

import SwiftUI

struct InboxView: View {
    @State private var viewModel = InboxViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContent
            batchBarOverlay
            undoToastOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
        .sheet(isPresented: $viewModel.showOverrideSheet) {
            overrideSheet
        }
        .onKeyPress(.upArrow) { viewModel.moveFocusUp(); return .handled }
        .onKeyPress(.downArrow) { viewModel.moveFocusDown(); return .handled }
        .onKeyPress(.return) { Task { await viewModel.acceptFocused() }; return .handled }
        .onKeyPress(.delete) { Task { await viewModel.dismissFocused() }; return .handled }
        .onKeyPress(.space) { viewModel.toggleFocusedSelection(); return .handled }
        .onKeyPress(.escape) { viewModel.deselectAll(); return .handled }
        .background {
            // Hidden button for Cmd+A select all
            Button("") { viewModel.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            inboxHeader
            captureBar
            if !viewModel.items.isEmpty {
                statsAndFilters
            }
            Divider().foregroundStyle(DS.border)
            itemsOrEmptyState
        }
    }

    // MARK: - Header

    private var inboxHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Inbox")
                    .font(DS.pageTitle)
                    .foregroundStyle(DS.text)

                if !viewModel.items.isEmpty {
                    Text("\(viewModel.items.count) item\(viewModel.items.count == 1 ? "" : "s") awaiting triage")
                        .font(DS.callout)
                        .foregroundStyle(DS.textMuted)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space16)
    }

    // MARK: - Capture Bar

    private var captureBar: some View {
        InboxCaptureBar(viewModel: viewModel)
            .padding(.horizontal, DS.space24)
            .padding(.bottom, DS.space12)
    }

    // MARK: - Stats & Filters

    private var statsAndFilters: some View {
        InboxStatsBar(viewModel: viewModel)
    }

    // MARK: - Items or Empty State

    @ViewBuilder
    private var itemsOrEmptyState: some View {
        if viewModel.items.isEmpty {
            emptyState
        } else {
            itemsList
        }
    }

    // MARK: - Items List (Sectioned)

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                groupSuggestions
                ForEach(viewModel.groupedItems) { section in
                    Section {
                        sectionItems(section)
                    } header: {
                        InboxSectionHeader(
                            title: section.title,
                            itemCount: section.items.count
                        )
                    }
                }
            }
            .padding(.bottom, viewModel.isMultiSelectActive ? 80 : DS.space16)
        }
        .animation(ProMotionSprings.gentle, value: viewModel.groupedItems.map(\.id))
    }

    @ViewBuilder
    private var groupSuggestions: some View {
        ForEach(viewModel.itemGroups) { group in
            InboxGroupSuggestionCard(
                group: group,
                onExecute: { Task { await viewModel.executeBatchGroup(group) } },
                onDismiss: { viewModel.dismissGroup(group) }
            )
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space4)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
        }
    }

    private func sectionItems(_ section: InboxSection) -> some View {
        ForEach(Array(section.items.enumerated()), id: \.element.uuid) { index, item in
            InboxItemCard(
                item: item,
                isProcessing: viewModel.processingItemIds.contains(item.uuid),
                isExpanded: viewModel.isExpanded(item),
                isSelected: viewModel.selectedItemIds.contains(item.uuid),
                isFocused: viewModel.focusedItemId == item.uuid,
                insight: viewModel.itemInsights[item.uuid],
                onAccept: { Task { await viewModel.acceptSuggestion(for: item) } },
                onOverride: { viewModel.showOverride(for: item) },
                onDismiss: { Task { await viewModel.dismiss(item: item) } },
                onToggleExpand: { viewModel.toggleExpanded(for: item) },
                onToggleSelect: { viewModel.toggleSelection(for: item) }
            )
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space4)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.95))
            ))
            .animation(
                ProMotionSprings.staggered(index: index),
                value: item.uuid
            )
            .onAppear { viewModel.markReadIfNeeded(item) }
            .onTapGesture(count: 1) {
                if NSEvent.modifierFlags.contains(.command) {
                    viewModel.toggleSelection(for: item)
                }
            }
        }
    }

    // MARK: - Batch Bar Overlay

    @ViewBuilder
    private var batchBarOverlay: some View {
        if viewModel.isMultiSelectActive {
            InboxBatchBar(viewModel: viewModel)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(ProMotionSprings.snappy, value: viewModel.isMultiSelectActive)
        }
    }

    @ViewBuilder
    private var undoToastOverlay: some View {
        if viewModel.showUndoToast {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.accent)

                Text(viewModel.undoToastMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button("Undo") {
                    Task { await viewModel.undoLastInboxAction() }
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)

                Button {
                    viewModel.dismissUndoToast()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .stroke(DS.border, lineWidth: 1)
            )
            .padding(.horizontal, DS.space24)
            .padding(.bottom, viewModel.isMultiSelectActive ? 92 : DS.space20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Override Sheet

    @ViewBuilder
    private var overrideSheet: some View {
        if let item = viewModel.overrideItem {
            InboxOverrideSheet(
                item: item,
                viewModel: viewModel
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: DS.space24) {
                Spacer(minLength: DS.space32)

                emptyStateIcon
                emptyStateCopy
                howToCaptureCard
                recentActivitySection
                weeklyStats

                Spacer(minLength: DS.space32)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.space40)
        }
    }

    private var emptyStateIcon: some View {
        Image(systemName: "tray")
            .font(.system(size: 40, weight: .thin))
            .foregroundStyle(DS.textMuted.opacity(0.5))
    }

    private var emptyStateCopy: some View {
        VStack(spacing: DS.space8) {
            Text("Your inbox is clear")
                .font(DS.title2)
                .foregroundStyle(DS.text)

            Text("Thoughts, ideas, and captures land here for triage.")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var howToCaptureCard: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text("How to Capture")
                .dsSmallCapsLabel()

            captureMethodRow(
                icon: "paperplane.fill",
                label: "Telegram",
                detail: "Send anything to your Cosmo bot"
            )
            captureMethodRow(
                icon: "text.cursor",
                label: "Prefix",
                detail: "inbox: your thought here"
            )
            captureMethodRow(
                icon: "plus.circle",
                label: "Capture bar",
                detail: "Type above to capture instantly"
            )
        }
        .padding(DS.space16)
        .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .frame(maxWidth: 360)
    }

    private func captureMethodRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: DS.space10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(DS.accent)
                .frame(width: 24, height: 24)
                .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)
                Text(detail)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    @ViewBuilder
    private var recentActivitySection: some View {
        if !viewModel.recentHistory.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Recent Activity")
                    .dsSmallCapsLabel()

                ForEach(viewModel.recentHistory) { item in
                    recentHistoryRow(item)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
    }

    private func recentHistoryRow(_ item: InboxItem) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: item.status == .actioned ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(item.status == .actioned ? DS.accent : DS.textMuted)

            Text(item.title ?? String(item.rawText.prefix(40)))
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)

            Spacer()

            if let actionedAt = item.actionedAt {
                Text(relativeTime(from: actionedAt))
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    @ViewBuilder
    private var weeklyStats: some View {
        if viewModel.triagedThisWeek > 0 {
            Text("This week: \(viewModel.triagedThisWeek) items triaged")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Helpers

    private func relativeTime(from dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
