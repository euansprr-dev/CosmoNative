// Canvas/CommandCenter/DashboardShortcutBar.swift
// Contextual keyboard shortcut hints bar
// March 2026

import SwiftUI

struct DashboardShortcutBar: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    var isEditing: Bool
    var isTimerRunning: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                shortcutHint("Esc", "Close")
                shortcutHint("Tab", "Next field")
            } else if isTimerRunning {
                shortcutHint("Space", "Pause")
                shortcutHint("Esc", "Stop")
                shortcutHint("N", "Add task")
            } else {
                shortcutHint("N", "Add task")
                shortcutHint("S", "Start session")
                shortcutHint("\u{2191}\u{2193}", "Navigate")
                shortcutHint("Enter", "Edit")
                shortcutHint("Space", "Play")
                shortcutHint("Tab", "Switch view")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 6)
    }

    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(DS.textMuted)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: 3))

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)
        }
    }
}
