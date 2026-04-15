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

/// Applies the Akashic floating panel chrome: vellum surface,
/// 24px continuous corners, warm sepia border, and premium floating shadow.
private struct FloatingOverlayPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous)
                    .fill(DS.vellum)
            )
            .clipShape(RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous)
                    .stroke(DS.sepiaBorder, lineWidth: 0.5)
            )
            .dsFloatingShadow()
    }
}

extension View {
    /// Apply the standard floating overlay panel chrome (white bg, 24px corners, border, shadow).
    func floatingOverlayPanel() -> some View {
        modifier(FloatingOverlayPanelModifier())
    }

    /// Apply Cortex glass panel chrome — frosted material with clean outline border.
    func cortexGlassPanel() -> some View {
        modifier(CortexGlassPanelModifier())
    }

    /// Apply Cortex inspector panel chrome — ultraThinMaterial, top-down light,
    /// hairline white border, floating shadow. Used by block/cluster detail menus.
    func cortexInspectorPanel(cornerRadius: CGFloat = 24) -> some View {
        modifier(CortexInspectorPanelModifier(cornerRadius: cornerRadius))
    }

    /// Wrap a section in an inner glass sub-pane (glassCardFill + hairline border).
    func cortexSectionPane(cornerRadius: CGFloat = 16, padding: CGFloat = 14) -> some View {
        modifier(CortexSectionPaneModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Cortex Glass Panel

/// Frosted glass panel for the Cortex Command-K overlay.
/// Uses .ultraThinMaterial for translucent depth, with a clean
/// 1px border and floating shadow — inspired by macOS Spotlight.
private struct CortexGlassPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .dsFloatingShadow()
    }
}

// MARK: - Cortex Inspector Panel

/// Frosted glass inspector panel with a top-down light gradient —
/// the visual language used by block & cluster detail menus. Family member
/// of the Cortex glass system; matches Spotlight's material but adds a
/// subtle luminance bloom along the top edge to feel like a lens, not a card.
private struct CortexInspectorPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .dsFloatingShadow()
    }
}

// MARK: - Cortex Section Pane

/// Inner sub-pane for grouping content inside a Cortex inspector panel.
/// Uses DS.glassCardFill + hairline DS.glassBorder for layered depth.
private struct CortexSectionPaneModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
    }
}

// MARK: - Cortex Chip Button Style

/// Capsule button style for Cortex inspector action chips.
/// glassInputFill background, hairline border, hover brightens + lifts 1pt,
/// press springs to 0.97. Use with `.buttonStyle(CortexChipStyle())`.
struct CortexChipStyle: ButtonStyle {
    var isDestructive: Bool = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        CortexChipBody(
            configuration: configuration,
            isDestructive: isDestructive
        )
    }
}

private struct CortexChipBody: View {
    let configuration: ButtonStyle.Configuration
    let isDestructive: Bool
    @State private var isHovered = false

    var body: some View {
        let baseFill: Color = isHovered ? DS.glassInputFillFocused : DS.glassInputFill
        let strokeColor: Color = {
            if isDestructive && isHovered { return DS.red.opacity(0.55) }
            return isHovered ? DS.glassBorderFocused : DS.glassBorder
        }()
        let textColor: Color = {
            if isDestructive { return isHovered ? DS.red : DS.red.opacity(0.85) }
            return isHovered ? DS.text : DS.textSecondary
        }()

        return configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .background(
                Capsule(style: .continuous).fill(baseFill)
            )
            .overlay(
                Capsule(style: .continuous).strokeBorder(strokeColor, lineWidth: 0.5)
            )
            .offset(y: isHovered ? -1 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) { isHovered = hovering }
            }
            .contentShape(Capsule())
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
                .foregroundStyle(DS.inkFaded)
                .frame(width: 28, height: 28)
                .background(DS.vellumDeep, in: Circle())
                .overlay(Circle().stroke(DS.sepiaBorder, lineWidth: 0.5))
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
