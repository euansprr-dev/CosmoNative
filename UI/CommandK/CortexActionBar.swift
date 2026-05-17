// CosmoOS/UI/CommandK/CortexActionBar.swift
// Persistent bottom action bar (Raycast-style): context label + primary
// "Open ↵" + the "Actions" menu (Phase 2).

import SwiftUI

struct CortexActionBar: View {
    @ObservedObject var viewModel: CommandKViewModel
    let primaryAction: CommandKContextualAction?
    let actions: [CommandKContextualAction]
    var hasSelection: Bool
    var onOpen: () -> Void
    var onShowActions: () -> Void

    var body: some View {
        HStack(spacing: DS.space12) {
            Text(contextLabel)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            Spacer(minLength: 0)

            Button(action: onOpen) {
                HStack(spacing: DS.space6) {
                    Text(primaryLabel)
                        .font(DS.caption)
                        .foregroundStyle(canOpen ? DS.text : DS.textMuted)
                    CortexKeycap(symbol: "return")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpen)
            .accessibilityLabel("Open selection")

            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(width: 0.5, height: 14)

            CortexActionsMenu(
                isEnabled: !actions.isEmpty,
                onShowActions: onShowActions
            )
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.sepiaBorder).frame(height: 0.5)
        }
    }

    private var contextLabel: String {
        if let status = viewModel.actionStatusMessage { return status }
        if case .expandedDomain(let tab) = viewModel.cortexMode { return tab.title }
        return viewModel.query.isEmpty ? "Command K" : "Results"
    }

    private var canOpen: Bool {
        if let action = viewModel.activeCommandAction {
            return action.isExecutable && !viewModel.isExecutingAction
        }
        return hasSelection && (primaryAction?.availability.isEnabled ?? true)
    }

    private var primaryLabel: String {
        if viewModel.isExecutingAction { return "Working" }
        if let action = viewModel.activeCommandAction { return action.title }
        guard let primaryAction else { return "Open" }
        if primaryAction.id == .openFocusMode { return "Open" }
        return primaryAction.title
    }
}
