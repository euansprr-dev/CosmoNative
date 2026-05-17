// CosmoOS/UI/CommandK/CortexActionBar.swift
// Persistent bottom action bar (Raycast-style): context label + primary
// "Open ↵" + the "Actions" menu (Phase 2).

import SwiftUI

struct CortexActionBar: View {
    @ObservedObject var viewModel: CommandKViewModel
    let selectedAtomUUID: String?
    var hasSelection: Bool
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: DS.space12) {
            Text(contextLabel)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            Spacer(minLength: 0)

            Button(action: onOpen) {
                HStack(spacing: DS.space6) {
                    Text("Open")
                        .font(DS.caption)
                        .foregroundStyle(hasSelection ? DS.text : DS.textMuted)
                    CortexKeycap(symbol: "return")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
            .accessibilityLabel("Open selection")

            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(width: 0.5, height: 14)

            CortexActionsMenu(atomUUID: selectedAtomUUID)
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.sepiaBorder).frame(height: 0.5)
        }
    }

    private var contextLabel: String {
        if case .expandedDomain(let tab) = viewModel.cortexMode { return tab.title }
        return viewModel.query.isEmpty ? "Command K" : "Results"
    }
}
