// CosmoOS/UI/CommandK/CortexActionsMenu.swift
// The Raycast-style "Actions" affordance for the action bar. The actual action
// list lives in CommandKActionPanel so actions are searchable and keyboard-native.

import SwiftUI

struct CortexActionsMenu: View {
    let isEnabled: Bool
    let onShowActions: () -> Void

    var body: some View {
        Button(action: onShowActions) {
            HStack(spacing: DS.space6) {
                Text("Actions")
                    .font(DS.caption)
                    .foregroundStyle(isEnabled ? DS.textSecondary : DS.textMuted)
                CortexKeycap(symbol: "command")
                CortexKeycap(symbol: "K", isLetter: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("k", modifiers: .command)
        .fixedSize()
        .disabled(!isEnabled)
        .accessibilityLabel("Show actions")
    }
}

/// Small keycap glyph shared by the action bar and actions menu.
struct CortexKeycap: View {
    let symbol: String
    var isLetter: Bool = false

    var body: some View {
        Group {
            if isLetter {
                Text(symbol.uppercased())
                    .font(DS.keycap)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .medium))
            }
        }
        // Secondary, not muted: keycap ink sits on the darker vellum fill,
        // where the muted rung drops below AA (shared spec with the ledger's
        // shortcut bar — ONE keycap dialect).
        .foregroundStyle(DS.commandCenterSecondaryText)
        .frame(width: 18, height: 18)
        .background(DS.commandChromeControlFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(DS.commandChromeControlBorder, lineWidth: 0.5)
        )
    }
}
