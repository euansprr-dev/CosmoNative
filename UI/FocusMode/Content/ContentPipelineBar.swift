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
    let onPhaseSelected: (ContentPhase) -> Void

    /// The furthest phase the content has reached in the pipeline
    private var maxPhase: ContentPhase { reachedPhase ?? currentPhase }

    // Colors
    private let completedColor = Color(hex: "#22C55E")
    private let accentColor = CosmoMentionColors.content  // Blue

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ContentPhase.allCases.enumerated()), id: \.element) { index, phase in
                if index > 0 {
                    // Connecting line
                    Rectangle()
                        .fill(lineColor(beforePhase: phase))
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
    }

    // MARK: - Phase Content

    @ViewBuilder
    private func phaseContent(_ phase: ContentPhase) -> some View {
        VStack(spacing: 3) {
            phaseDot(for: phase)

            Text(phase.displayName)
                .font(.system(size: 8, weight: phase == currentPhase ? .semibold : .regular))
                .foregroundColor(phaseLabelColor(phase))

            // Duration badge for current phase
            if phase == currentPhase, let enteredAt = phaseEnteredAt {
                Text(durationString(from: enteredAt))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(accentColor.opacity(0.7))
            }
        }
    }

    private func phaseLabelColor(_ phase: ContentPhase) -> Color {
        if phase == currentPhase { return .white }
        if phaseIndex(phase) <= phaseIndex(maxPhase) { return completedColor.opacity(0.7) }
        return .white.opacity(0.35)
    }

    // MARK: - Phase Dot

    @ViewBuilder
    private func phaseDot(for phase: ContentPhase) -> some View {
        if phase == currentPhase {
            // Currently displayed: filled accent with icon + glow
            ZStack {
                Circle()
                    .fill(accentColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: accentColor.opacity(0.5), radius: 4)
                Image(systemName: phase.iconName)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
            }
        } else if phaseIndex(phase) <= phaseIndex(maxPhase) {
            // Reached but not currently displayed: green checkmark
            ZStack {
                Circle().fill(completedColor).frame(width: 12, height: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
            }
        } else {
            // Future: icon in stroke circle — uniform style for all phases
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    .frame(width: 12, height: 12)
                Image(systemName: phase.iconName)
                    .font(.system(size: 6))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
    }

    // MARK: - Helpers

    /// All phases up to the max reached phase are clickable
    private func isClickable(_ phase: ContentPhase) -> Bool {
        phaseIndex(phase) <= phaseIndex(maxPhase)
    }

    private func lineColor(beforePhase phase: ContentPhase) -> Color {
        if phaseIndex(phase) <= phaseIndex(maxPhase) {
            return completedColor.opacity(0.5)
        }
        return Color.white.opacity(0.08)
    }

    private func phaseIndex(_ phase: ContentPhase) -> Int {
        ContentPhase.allCases.firstIndex(of: phase) ?? 0
    }

    private func durationString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
