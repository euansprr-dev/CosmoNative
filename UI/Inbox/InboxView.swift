// CosmoOS/UI/Inbox/InboxView.swift
// Smart Triage Inbox — AI-classified captures with one-tap actions
// March 2026

import SwiftUI

struct InboxView: View {
    @StateObject private var viewModel = InboxViewModel()

    var body: some View {
        VStack(spacing: 0) {
            inboxHeader
            Divider().foregroundColor(DS.border)

            if viewModel.items.isEmpty {
                emptyState
            } else {
                itemsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
        .sheet(isPresented: $viewModel.showOverrideSheet) {
            if let item = viewModel.overrideItem {
                InboxOverrideSheet(
                    item: item,
                    viewModel: viewModel
                )
            }
        }
    }

    // MARK: - Header

    private var inboxHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Inbox")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(DS.text)

                if !viewModel.items.isEmpty {
                    Text("\(viewModel.items.count) item\(viewModel.items.count == 1 ? "" : "s") awaiting triage")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textMuted)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Items List

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.items) { item in
                    InboxItemCard(
                        item: item,
                        isProcessing: viewModel.processingItemId == item.uuid,
                        onAccept: {
                            Task { await viewModel.acceptSuggestion(for: item) }
                        },
                        onOverride: {
                            viewModel.showOverride(for: item)
                        },
                        onDismiss: {
                            Task { await viewModel.dismiss(item: item) }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .animation(ProMotionSprings.gentle, value: viewModel.items.count)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 40, weight: .thin))
                .foregroundColor(DS.textMuted.opacity(0.5))

            Text("All caught up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DS.text)

            Text("Captures from Telegram and Quick Capture appear here.\nThe AI will suggest where each one belongs.")
                .font(.system(size: 13))
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
