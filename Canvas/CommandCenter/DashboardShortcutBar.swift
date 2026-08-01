// Canvas/CommandCenter/DashboardShortcutBar.swift
// The Raycast law: shortcuts taught in place compound into expertise. A quiet
// keycap footer under the ledger — every hint here is wired in MainView's key
// monitor or the dashboard's keyboard handler; the bar must never advertise a
// key that does nothing.
// March 2026 · re-crafted July 2026

import SwiftUI

struct DashboardShortcutBar: View {

    var viewModel: CommandCenterDashboardViewModel
    /// The narrow signal, not the engine: an @ObservedObject on
    /// DeepWorkSessionEngine repaints this bar once a second for a clock it
    /// never draws (see ActiveFocusSignal).
    private var focus: ActiveFocusSignal { .shared }

    // Stable slots (Raycast's footer law): starting a session must never
    // reflow the bar — Tab, ⌥⌘↑↓, ↑↓ and ⌫ all stay wired mid-session, so
    // they stay visible. Only "S" (start a session) is genuinely dead while
    // one runs, and Space relabels in place.
    var body: some View {
        HStack(spacing: DS.space16) {
            hint("N", "Add task")
            if !focus.isTimerRunning {
                hint("S", "Session")
                    .transition(.opacity)
            }
            hint("↑↓", "Navigate")
            hint("⌥⌘↑↓", "Reorder")
            hint("Space", focus.isTimerRunning ? "Pause" : "Focus")
            hint("⌫", "Complete")
            hint("Tab", "Lists")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.space6)
        .animation(ProMotionSprings.gentle, value: focus.isTimerRunning)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard shortcuts")
    }

    // ONE keycap anatomy app-wide — the ⌘K CortexKeycap spec exactly: warm
    // vellum control fill, radius 5, medium monospaced glyph, inset border,
    // FIXED 18pt height (a floor lets a tall chord grow its tile and drop
    // its bottom edge below its neighbors'), minWidth escape for chords.
    private func hint(_ key: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space4) {
            // Secondary ink, not muted: the keycap is the one site where ink
            // sits on a DARKER fill (vellum), and muted dropped below AA there.
            Text(key)
                .font(DS.keycap)
                .foregroundStyle(DS.commandCenterSecondaryText)
                .padding(.horizontal, DS.space4)
                .frame(minWidth: 18)
                .frame(height: 18)
                .background(DS.commandChromeControlFill, in: .rect(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(DS.commandChromeControlBorder, lineWidth: 0.5)
                )

            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }
}
