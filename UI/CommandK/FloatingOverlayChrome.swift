// CosmoOS/UI/CommandK/FloatingOverlayChrome.swift
// Shared floating overlay infrastructure — unified backdrop + panel chrome
// Matches the Command-K aesthetic across all floating panels in the app.

import SwiftUI

// MARK: - FloatingOverlayBackdrop

/// Full-screen blurred backdrop for floating overlay panels.
/// Matches the Command-K overlay's visual treatment exactly:
/// ultraThinMaterial + warm parchment tint + tap-to-close.
struct FloatingOverlayBackdrop: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).opacity(0.75)
            DS.bg.opacity(0.15)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
    }
}

// MARK: - Floating Overlay Panel Modifier

/// Applies the canonical floating panel chrome: white elevated surface,
/// 24px continuous corners, subtle border, and premium floating shadow.
private struct FloatingOverlayPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous)
                    .fill(DS.surfaceElevated)
            )
            .clipShape(RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous)
                    .stroke(DS.border, lineWidth: 1)
            )
            .dsFloatingShadow()
    }
}

extension View {
    /// Apply the standard floating overlay panel chrome (white bg, 24px corners, border, shadow).
    func floatingOverlayPanel() -> some View {
        modifier(FloatingOverlayPanelModifier())
    }
}

// MARK: - Standardized Close Button

/// The canonical close button used across all floating overlays.
/// 28x28 circle with surface background, subtle border, and xmark icon.
struct FloatingOverlayCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(DS.surface, in: Circle())
                .overlay(Circle().stroke(DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Phase Step Indicator

/// Horizontal progress dots showing the current phase in a multi-step flow.
/// Used in import wizards, creation flows, etc.
struct FloatingOverlayPhaseIndicator: View {
    let phases: [String]
    let currentPhase: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                phaseStep(index: index, label: phase)
            }
        }
    }

    @ViewBuilder
    private func phaseStep(index: Int, label: String) -> some View {
        HStack(spacing: 4) {
            stepDot(index: index)
            if index == currentPhase {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.entitySwipe)
            }
        }
    }

    @ViewBuilder
    private func stepDot(index: Int) -> some View {
        ZStack {
            Circle()
                .fill(dotFill(for: index))
                .frame(width: 8, height: 8)

            if index < currentPhase {
                Image(systemName: "checkmark")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundStyle(DS.textOnAccent)
            }
        }
    }

    private func dotFill(for index: Int) -> Color {
        if index < currentPhase {
            return DS.entitySwipe
        } else if index == currentPhase {
            return DS.entitySwipe
        } else {
            return DS.borderSubtle
        }
    }
}
