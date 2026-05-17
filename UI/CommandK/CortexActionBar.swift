// CosmoOS/UI/CommandK/CortexActionBar.swift
// Persistent bottom action bar (Raycast-style). Phase 1: context label +
// primary "Open ↵". The "Actions ⌘K" menu is wired in Phase 2.

import SwiftUI

struct CortexActionBar: View {
    @ObservedObject var viewModel: CommandKViewModel
    let hasSelection: Bool

    var body: some View {
        HStack(spacing: DS.space12) {
            Text(contextLabel)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            Spacer(minLength: 0)

            Button(action: { viewModel.openSelected() }) {
                HStack(spacing: DS.space6) {
                    Text("Open")
                        .font(DS.caption)
                        .foregroundStyle(hasSelection ? DS.text : DS.textMuted)
                    keycap("return")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
            .accessibilityLabel("Open selection")

            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(width: 0.5, height: 14)

            HStack(spacing: DS.space6) {
                Text("Actions")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                keycap("command")
                keycap("k", isLetter: true)
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.sepiaBorder).frame(height: 0.5)
        }
    }

    private var contextLabel: String {
        viewModel.query.isEmpty ? "Command K" : "Results"
    }

    @ViewBuilder
    private func keycap(_ symbol: String, isLetter: Bool = false) -> some View {
        Group {
            if isLetter {
                Text(symbol.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .foregroundStyle(DS.inkFaded)
        .frame(width: 18, height: 18)
        .background(DS.vellumDeep, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(DS.sepiaBorder, lineWidth: 0.5)
        )
    }
}
