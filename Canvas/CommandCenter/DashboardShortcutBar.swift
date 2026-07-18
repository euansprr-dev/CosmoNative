// Canvas/CommandCenter/DashboardShortcutBar.swift
// The Raycast law: shortcuts taught in place compound into expertise. A quiet
// keycap footer under the ledger — every hint here is wired in MainView's key
// monitor or the dashboard's keyboard handler; the bar must never advertise a
// key that does nothing.
// March 2026 · re-crafted July 2026

import SwiftUI

struct DashboardShortcutBar: View {

    var viewModel: CommandCenterDashboardViewModel
    @ObservedObject private var sessionEngine = DeepWorkSessionEngine.shared

    var body: some View {
        HStack(spacing: DS.space16) {
            if sessionEngine.isTimerRunning {
                hint("Space", "Pause")
                hint("N", "Add task")
                hint("↑↓", "Navigate")
                hint("⌫", "Complete")
            } else {
                hint("N", "Add task")
                hint("S", "Session")
                hint("↑↓", "Navigate")
                hint("Space", "Focus")
                hint("⌫", "Complete")
                hint("Tab", "Lists")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.space6)
        .animation(ProMotionSprings.gentle, value: sessionEngine.isTimerRunning)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard shortcuts")
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: DS.space4) {
            Text(key)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space6)
                .padding(.vertical, 2.5)
                .background(DS.glassSectionFill, in: .rect(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(DS.borderSubtle, lineWidth: 0.5)
                )

            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }
}
