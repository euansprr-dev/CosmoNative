// CosmoOS/UI/FocusMode/Content/ContentPipelineBar.swift
// 7-phase pipeline bar for Content Focus Mode top bar
// February 2026

import SwiftUI

// MARK: - Content Pipeline Bar

/// Horizontal 7-phase pipeline indicator that replaces the old 3-step indicator.
/// Creation phases (ideation-polish) are clickable; post-creation phases are not.
struct ContentPipelineBar: View {
    let currentPhase: ContentPhase      // Currently displayed/active phase
    let reachedPhase: ContentPhase?     // Furthest pipeline phase reached (nil = same as current)
    let phaseEnteredAt: Date?
    var compact: Bool = false
    let onPhaseSelected: (ContentPhase) -> Void

    /// The furthest phase the content has reached in the pipeline
    private var maxPhase: ContentPhase { reachedPhase ?? currentPhase }

    /// Only show visible phases (Schedule/Published/Analyzing hidden for V1)
    private var displayPhases: [ContentPhase] { ContentPhase.visiblePhases }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(displayPhases.enumerated()), id: \.element) { index, phase in
                if index > 0 {
                    // Connecting line
                    connectingLine(beforePhase: phase, atIndex: index)
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                }

                // Phase dot + label
                Button {
                    if isClickable(phase) {
                        onPhaseSelected(phase)
                    }
                } label: {
                    phaseContent(phase)
                }
                .buttonStyle(.plain)
                .disabled(!isClickable(phase))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 12 : 32)
        .background(DS.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.border)
                .frame(height: 1)
        }
    }

    // MARK: - Phase Content

    @ViewBuilder
    private func phaseContent(_ phase: ContentPhase) -> some View {
        VStack(spacing: compact ? 2 : 4) {
            phaseDot(for: phase)

            if !compact {
                Text(phase.displayName)
                    .font(.system(size: 10, weight: phase == currentPhase ? .semibold : .regular))
                    .foregroundStyle(phaseLabelColor(phase))

                // Duration badge for current phase
                if phase == currentPhase, let enteredAt = phaseEnteredAt {
                    Text(durationString(from: enteredAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
    }

    private func phaseLabelColor(_ phase: ContentPhase) -> Color {
        if phase == currentPhase { return DS.text }
        if phaseIndex(phase) <= phaseIndex(maxPhase) { return DS.green.opacity(0.7) }
        return DS.textMuted
    }

    // MARK: - Phase Dot

    @ViewBuilder
    private func phaseDot(for phase: ContentPhase) -> some View {
        let activeSize: CGFloat = compact ? 18 : 22
        let inactiveSize: CGFloat = compact ? 14 : 18

        if phase == currentPhase {
            // Active phase: DS.accent fill, white icon, 12px accentGlow shadow
            ZStack {
                Circle()
                    .fill(DS.accent)
                    .frame(width: activeSize, height: activeSize)
                    .shadow(color: DS.accentGlow, radius: compact ? 6 : 12, x: 0, y: 0)
                Image(systemName: phase.iconName)
                    .font(.system(size: compact ? 8 : 10, weight: .bold))
                    .foregroundStyle(DS.textOnAccent)
            }
        } else if phaseIndex(phase) <= phaseIndex(maxPhase) {
            // Completed phase: DS.green fill, checkmark, 8px green glow
            ZStack {
                Circle()
                    .fill(DS.green)
                    .frame(width: inactiveSize, height: inactiveSize)
                    .shadow(color: DS.greenGlow, radius: compact ? 4 : 8, x: 0, y: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: compact ? 6 : 8, weight: .bold))
                    .foregroundStyle(DS.textOnAccent)
            }
        } else {
            // Inactive phase: transparent with 1px DS.textMuted border, number inside
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: inactiveSize, height: inactiveSize)
                    .overlay(
                        Circle()
                            .stroke(DS.textMuted, lineWidth: 1)
                    )
                Text("\(phaseIndex(phase) + 1)")
                    .font(.system(size: compact ? 7 : 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    // MARK: - Helpers

    /// All phases up to the max reached phase are clickable
    private func isClickable(_ phase: ContentPhase) -> Bool {
        phaseIndex(phase) <= phaseIndex(maxPhase)
    }

    /// Connecting line between phase dots, with gradient for active-to-next transition
    @ViewBuilder
    private func connectingLine(beforePhase phase: ContentPhase, atIndex index: Int) -> some View {
        let idx = phaseIndex(phase)
        let maxIdx = phaseIndex(maxPhase)
        let currentIdx = phaseIndex(currentPhase)

        if idx <= maxIdx {
            // Completed segment — solid green
            Rectangle().fill(DS.green)
        } else if idx == currentIdx + 1 {
            // Active-to-next transition — gradient from green to border
            Rectangle().fill(
                LinearGradient(
                    colors: [DS.green, DS.border],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        } else {
            // Future segment — subtle border
            Rectangle().fill(DS.borderSubtle)
        }
    }

    private func phaseIndex(_ phase: ContentPhase) -> Int {
        displayPhases.firstIndex(of: phase) ?? 0
    }

    private func durationString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
