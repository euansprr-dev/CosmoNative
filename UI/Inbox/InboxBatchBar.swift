// CosmoOS/UI/Inbox/InboxBatchBar.swift
// Floating batch action bar for multi-select operations
// March 2026

import SwiftUI

struct InboxBatchBar: View {
    @Bindable var viewModel: InboxViewModel
    @State private var showBulkDismissConfirm = false

    var body: some View {
        HStack(spacing: DS.space12) {
            selectionCount
            Spacer()
            swipeAllButton
            acceptAllButton
            dismissAllButton
            deselectButton
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
        .padding(.horizontal, DS.space24)
        .padding(.bottom, DS.space16)
        .confirmationDialog(
            "Dismiss \(viewModel.selectedItemIds.count) captures?",
            isPresented: $showBulkDismissConfirm,
            titleVisibility: .visible
        ) {
            Button("Dismiss All", role: .destructive) {
                Task { await viewModel.dismissAllSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Dismissed captures move to History, where they can be restored.")
        }
    }

    private var selectionCount: some View {
        HStack(spacing: DS.space6) {
            Text("\(viewModel.selectedItemIds.count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.textOnAccent)
                .frame(minWidth: 20, minHeight: 20)
                .background(DS.accent, in: Circle())
                .contentTransition(.numericText())

            Text("selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.textSecondary)
        }
    }

    /// Batch-file a selection of links and screenshots into the Swipe File.
    /// Renders only when EVERY selected capture can become one — a partial
    /// batch would silently skip rows, and a silent skip in a bulk action is
    /// how captures get lost.
    @ViewBuilder
    private var swipeAllButton: some View {
        if viewModel.selectionCanAllBecomeSwipes {
            Button {
                Task { await viewModel.swipeAllSelected() }
            } label: {
                HStack(spacing: DS.space4) {
                    Image(systemName: SwipeKind.post.iconName)
                        .font(.system(size: 10, weight: .bold))
                    Text("Swipe All")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(DS.entitySwipe)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .background(
                    DS.entitySwipe.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .help("File every selected capture into the Swipe File")
            .accessibilityLabel("Swipe all selected captures")
        }
    }

    private var acceptAllButton: some View {
        Button {
            Task { await viewModel.acceptAllSelected() }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text("Accept All")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space8)
            .background(DS.accent, in: RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var dismissAllButton: some View {
        Button {
            // Wiping more than a handful of captures at once needs explicit
            // confirmation — ⌘A + Dismiss All used to clear the queue silently.
            if viewModel.selectedItemIds.count > 5 {
                showBulkDismissConfirm = true
            } else {
                Task { await viewModel.dismissAllSelected() }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                Text("Dismiss All")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(DS.red)
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space8)
            .background(DS.redSoft, in: RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                    .stroke(DS.red.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var deselectButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.deselectAll()
            }
        } label: {
            Image(systemName: "xmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(DS.textMuted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Deselect all")
    }
}
