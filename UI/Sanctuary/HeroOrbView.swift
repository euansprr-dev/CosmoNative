// CosmoOS/UI/Sanctuary/HeroOrbView.swift
// Hero Orb - Central animated orb representing overall Cosmo Index
// Breathing animation synced to HRV when available
// Phase 1: Integrated with ATOM Architecture foundation

import SwiftUI

// MARK: - Hero Orb View

public struct HeroOrbView: View {

    let state: CosmoIndexState?
    let liveMetrics: LiveMetrics?
    let animationPhase: Double

    @State private var breathingScale: CGFloat = 1.0
    @State private var innerRotation: Double = 0
    @State private var outerRotation: Double = 0
    @State private var orbitalRingRotation: Double = 0
    @State private var isHovered: Bool = false
    @State private var particlePhases: [Double] = [0, 0.33, 0.66, 0.5, 0.16]  // 5 particles

    private let baseSize: CGFloat = SanctuaryLayout.Sizing.heroOrb
    private let orbitalRingRadius: CGFloat = 1.2  // 120% of base size
    private let glowColors: [Color] = [
        SanctuaryColors.HeroOrb.primary,
        SanctuaryColors.HeroOrb.secondary,
        SanctuaryColors.HeroOrb.tertiary
    ]

    public var body: some View {
        ZStack {
            // Faint orbital ring at 120% radius (hairline, 15% opacity)
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
                .frame(width: baseSize * orbitalRingRadius, height: baseSize * orbitalRingRadius)
                .rotationEffect(.degrees(orbitalRingRotation))
                .scaleEffect(breathingScale)

            // Outer glow rings
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: glowColors + [glowColors[0]],
                            center: .center,
                            startAngle: .degrees(outerRotation + Double(ring * 120)),
                            endAngle: .degrees(outerRotation + Double(ring * 120) + 360)
                        ),
                        lineWidth: 2
                    )
                    .frame(width: baseSize + CGFloat(ring * 30), height: baseSize + CGFloat(ring * 30))
                    .opacity(0.3 - Double(ring) * 0.1)
                    .scaleEffect(breathingScale + CGFloat(ring) * 0.05)
            }

            // Main orb body
            ZStack {
                // Gradient fill (using level-based colors)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                SanctuaryColors.HeroOrb.primary.opacity(0.8),
                                SanctuaryColors.HeroOrb.secondary.opacity(0.9)
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: baseSize
                        )
                    )

                // Inner glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: baseSize * 0.4
                        )
                    )

                // Subtle inner glow ring (white, 5% opacity)
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 2)
                    .frame(width: baseSize * 0.7, height: baseSize * 0.7)
                    .blur(radius: 2)

                // Micro-particle drift (3-5 particles, slow float)
                ForEach(0..<5, id: \.self) { index in
                    let phase = particlePhases[index] + animationPhase * 0.1
                    let angle = phase * .pi * 2
                    let radius = baseSize * 0.25 * (0.5 + 0.5 * sin(phase * 2 + Double(index)))
                    let x = cos(angle) * radius
                    let y = sin(angle) * radius

                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 3, height: 3)
                        .blur(radius: 1)
                        .offset(x: x, y: y)
                }

                // Surface detail (animated)
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.clear,
                                Color.white.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startAngle: .degrees(innerRotation),
                            endAngle: .degrees(innerRotation + 360)
                        ),
                        lineWidth: 3
                    )
                    .blur(radius: 2)
            }
            .frame(width: baseSize, height: baseSize)
            .scaleEffect(breathingScale * (isHovered ? 1.03 : 1.0))
            .shadow(color: SanctuaryColors.HeroOrb.glow.opacity(0.5), radius: 30, x: 0, y: 0)
            .animation(SanctuarySprings.hover, value: isHovered)

            // Level display
            VStack(spacing: SanctuaryLayout.Spacing.xs) {
                Text("CI")
                    .font(SanctuaryTypography.label)
                    .foregroundColor(SanctuaryColors.Text.secondary)

                if let state = state {
                    Text("\(state.level)")
                        .font(SanctuaryTypography.display)
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

                    // XP progress ring
                    Circle()
                        .trim(from: 0, to: CGFloat(state.xpProgress))
                        .stroke(
                            LinearGradient(
                                colors: [SanctuaryColors.XP.primary, SanctuaryColors.XP.secondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))
                }
            }

            // Live HRV indicator
            if let hrv = liveMetrics?.currentHRV {
                VStack {
                    Spacer()

                    HStack(spacing: SanctuaryLayout.Spacing.xs) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)

                        Text("\(Int(hrv))")
                            .font(SanctuaryTypography.metric)
                            .foregroundColor(SanctuaryColors.Text.secondary)
                    }
                    .padding(.horizontal, SanctuaryLayout.Spacing.sm)
                    .padding(.vertical, SanctuaryLayout.Spacing.xs)
                    .background(SanctuaryColors.Glass.background)
                    .clipShape(Capsule())
                    .offset(y: baseSize * 0.6)
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Animation

    private func startAnimations() {
        // PERFORMANCE FIX: Single breathing animation (synced to HRV when available)
        // Removed multiple competing animations - use single animation with calculated duration
        let breathingDuration: Double = liveMetrics?.currentHRV != nil
            ? 60.0 / (liveMetrics?.currentHRV ?? 60) * 4  // Sync to HRV
            : SanctuaryDurations.breathing

        withAnimation(
            .easeInOut(duration: breathingDuration)
            .repeatForever(autoreverses: true)
        ) {
            breathingScale = 1.05
        }

        // PERFORMANCE FIX: Consolidated rotation animations
        // Using single animation block with all rotations starting together
        // This reduces CATransaction overhead from 4 separate animations to 1
        let rotationDuration = SanctuaryDurations.rotation

        withAnimation(.linear(duration: rotationDuration).repeatForever(autoreverses: false)) {
            innerRotation = 360
        }

        // Stagger outer rotations slightly but start together
        withAnimation(.linear(duration: rotationDuration * 1.5).repeatForever(autoreverses: false)) {
            outerRotation = -360
        }

        withAnimation(.linear(duration: rotationDuration * 2).repeatForever(autoreverses: false)) {
            orbitalRingRotation = 360
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        HeroOrbView(
            state: CosmoIndexState(
                level: 23,
                currentXP: 450,
                xpToNextLevel: 600,
                xpProgress: 0.75,
                totalXP: 12450,
                rank: "Adept"
            ),
            liveMetrics: LiveMetrics(
                currentHRV: 65,
                lastHRVTime: Date(),
                todayXP: 350,
                activeStreak: 12,
                todayFocusMinutes: 145,
                todayWordCount: 2300
            ),
            animationPhase: 0
        )
    }
}
