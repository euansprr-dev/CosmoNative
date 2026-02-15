// CosmoOS/UI/Sanctuary/SatelliteNodeView.swift
// Satellite Node View - Reusable orb component for Plannerum & Thinkspace
// Apple-level quality with subtle animations and depth cues

import SwiftUI

/// A satellite node representing a region accessible from the Sanctuary map.
/// Used for Plannerum (planning realm) and Thinkspace (creative canvas).
///
/// Visual Design:
/// - 72pt orb (same size as dimension orbs)
/// - Recessed in z-depth with subtle blur
/// - Breathing animation (1.0 → 1.02 → 1.0)
/// - Glow halo on hover
/// - Orbital ring (hairline, slow rotation)
/// - Label below orb
public struct SatelliteNodeView: View {

    // MARK: - Properties

    let type: SanctuaryColors.SatelliteType
    let isHovered: Bool
    let animationPhase: Double
    let badgeCount: Int?
    let onTap: () -> Void
    let onHoverChanged: ((Bool) -> Void)?  // FIX: Handle hover inside view where contentShape is defined

    // Convenience init without hover callback (for backwards compatibility)
    init(
        type: SanctuaryColors.SatelliteType,
        isHovered: Bool,
        animationPhase: Double,
        badgeCount: Int?,
        onTap: @escaping () -> Void,
        onHoverChanged: ((Bool) -> Void)? = nil
    ) {
        self.type = type
        self.isHovered = isHovered
        self.animationPhase = animationPhase
        self.badgeCount = badgeCount
        self.onTap = onTap
        self.onHoverChanged = onHoverChanged
    }

    // MARK: - State

    @State private var isPressed = false
    @State private var orbRotation: Double = 0

    // MARK: - Layout Constants

    private enum Layout {
        static let orbSize: CGFloat = 56  // Reduced from 72pt per Onyx spec
        static let iconSize: CGFloat = 20
        static let labelSpacing: CGFloat = 6
        static let glowBlur: CGFloat = 10
        static let orbitalRingSize: CGFloat = orbSize * 1.3
        static let orbitalRingWidth: CGFloat = 0.5
        static let badgeSize: CGFloat = 16
    }

    // MARK: - Animation

    /// Breathing scale based on animation phase (subtle 2% oscillation)
    private var breathingScale: CGFloat {
        let base: CGFloat = 1.0
        let amplitude: CGFloat = 0.02
        return base + amplitude * CGFloat(sin(animationPhase * 0.8))
    }

    /// Hover lift offset
    private var hoverOffset: CGFloat {
        isHovered ? -4 : 0
    }

    /// Hover scale
    private var hoverScale: CGFloat {
        isHovered ? 1.05 : 1.0
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: Layout.labelSpacing) {
            // Orb with glow and orbital ring
            ZStack {
                // Background glow (visible on hover)
                Circle()
                    .fill(type.glowColor)
                    .frame(width: Layout.orbSize * 1.5, height: Layout.orbSize * 1.5)
                    .blur(radius: Layout.glowBlur)
                    .opacity(isHovered ? 0.6 : 0.2)

                // Orbital ring (hairline, slow rotation)
                Circle()
                    .stroke(
                        type.primaryColor.opacity(0.2),
                        lineWidth: Layout.orbitalRingWidth
                    )
                    .frame(width: Layout.orbitalRingSize, height: Layout.orbitalRingSize)
                    .rotationEffect(.degrees(orbRotation))

                // Main orb
                Circle()
                    .fill(SanctuaryColors.Satellite.gradient(for: type))
                    .frame(width: Layout.orbSize, height: Layout.orbSize)
                    .overlay(
                        // Inner highlight
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.15),
                                        Color.clear
                                    ],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: Layout.orbSize * 0.6
                                )
                            )
                    )
                    .overlay(
                        // Border
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: type.primaryColor.opacity(0.4),
                        radius: isHovered ? 16 : 8,
                        x: 0,
                        y: 4
                    )

                // Icon
                Image(systemName: type.icon)
                    .font(.system(size: Layout.iconSize, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                // Badge (if present)
                if let count = badgeCount, count > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: Layout.badgeSize, height: Layout.badgeSize)
                                .background(
                                    Circle()
                                        .fill(SanctuaryColors.warning)
                                )
                                .offset(x: 8, y: -8)
                        }
                        Spacer()
                    }
                    .frame(width: Layout.orbSize, height: Layout.orbSize)
                }
            }
            .scaleEffect(breathingScale * hoverScale * (isPressed ? 0.95 : 1.0))
            .offset(y: hoverOffset)

            // Label — 10pt, tertiary
            Text(type.displayName)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(
                    isHovered
                        ? OnyxColors.Text.primary
                        : OnyxColors.Text.secondary
                )
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
        // FIX: Use Circle contentShape to match orb visual + limit hover/tap to actual content
        .contentShape(Circle().scale(1.3))  // Slightly larger than orb for easier targeting
        .onHover { hovering in
            // Handle hover inside view where contentShape properly limits detection area
            onHoverChanged?(hovering)
        }
        .onTapGesture {
            withAnimation(SanctuarySprings.press) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(SanctuarySprings.snappy) {
                    isPressed = false
                }
                onTap()
            }
        }
        .onAppear {
            // Start orbital ring rotation
            withAnimation(
                .linear(duration: 30)
                .repeatForever(autoreverses: false)
            ) {
                orbRotation = 360
            }
        }
        .animation(SanctuarySprings.hover, value: isHovered)
        .animation(SanctuarySprings.smooth, value: animationPhase)
    }
}

// MARK: - Preview

#if DEBUG
struct SatelliteNodeView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            SanctuaryColors.voidPrimary
                .ignoresSafeArea()

            HStack(spacing: 200) {
                // Plannerum node
                SatelliteNodeView(
                    type: .plannerum,
                    isHovered: false,
                    animationPhase: 0,
                    badgeCount: 5,
                    onTap: {}
                )

                // Thinkspace node (hovered)
                SatelliteNodeView(
                    type: .thinkspace,
                    isHovered: true,
                    animationPhase: 0,
                    badgeCount: nil,
                    onTap: {}
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
