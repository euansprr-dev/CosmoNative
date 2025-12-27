// CosmoOS/UI/Sanctuary/SanctuaryHeroOrb.swift
// Enhanced Hero Orb - Central visualization with energy rings and live metrics orbit
// Phase 2: Following SANCTUARY_UI_SPEC_V2.md section 2.2

import SwiftUI

// MARK: - Sanctuary Hero Orb

/// The central Hero Core Orb - represents unified Cosmo Index
/// Features: Outer halo, 3 energy rings, core sphere, level display, live metrics orbit
public struct SanctuaryHeroOrb: View {

    // MARK: - Properties

    let state: CosmoIndexState?
    let liveMetrics: LiveMetrics?
    let breathingScale: CGFloat
    let isActive: Bool

    @State private var ring1Rotation: Double = 0
    @State private var ring2Rotation: Double = 0
    @State private var ring3Rotation: Double = 0
    @State private var haloScale: CGFloat = 1.0
    @State private var metricsOrbitAngle: Double = 0
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    @State private var surfaceNoisePhase: Double = 0

    // MARK: - Layout Constants

    private enum Layout {
        static let coreSize: CGFloat = SanctuaryLayout.Sizing.heroOrb  // 160pt
        static let haloSize: CGFloat = 280
        static let ring1Radius: CGFloat = 90
        static let ring2Radius: CGFloat = 100
        static let ring3Radius: CGFloat = 110
        static let metricsOrbitRadius: CGFloat = 85
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Layer 1: Outer Halo
            outerHalo

            // Layer 2: Energy Rings (3 concentric)
            energyRings

            // Layer 3: Core Sphere
            coreSphere

            // Layer 4: Level Display
            levelDisplay

            // Layer 5: Live Metrics Orbit
            if liveMetrics != nil {
                liveMetricsOrbit
            }
        }
        .frame(width: Layout.haloSize, height: Layout.haloSize)
        .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.05 : 1.0))
        .animation(SanctuarySprings.press, value: isPressed)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Layer 1: Outer Halo

    private var outerHalo: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        dimensionBlendColor.opacity(0.4),
                        dimensionBlendColor.opacity(0.1),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: Layout.haloSize / 2
                )
            )
            .frame(width: Layout.haloSize, height: Layout.haloSize)
            .blur(radius: 60)
            .opacity(0.3)
            .scaleEffect(haloScale * breathingScale)
    }

    // MARK: - Layer 2: Energy Rings

    private var energyRings: some View {
        ZStack {
            // Ring 1: r=90pt, 2px stroke, rotating CW @ 20s
            energyRing(
                radius: Layout.ring1Radius,
                strokeWidth: 2,
                rotation: ring1Rotation,
                gapCount: 3,
                color: SanctuaryColors.HeroOrb.primary
            )

            // Ring 2: r=100pt, 1.5px stroke, rotating CCW @ 30s
            energyRing(
                radius: Layout.ring2Radius,
                strokeWidth: 1.5,
                rotation: -ring2Rotation,
                gapCount: 4,
                color: SanctuaryColors.HeroOrb.secondary
            )

            // Ring 3: r=110pt, 1px stroke, rotating CW @ 45s
            energyRing(
                radius: Layout.ring3Radius,
                strokeWidth: 1,
                rotation: ring3Rotation,
                gapCount: 5,
                color: SanctuaryColors.HeroOrb.tertiary
            )
        }
        .scaleEffect(breathingScale)
    }

    private func energyRing(
        radius: CGFloat,
        strokeWidth: CGFloat,
        rotation: Double,
        gapCount: Int,
        color: Color
    ) -> some View {
        Circle()
            .stroke(
                AngularGradient(
                    stops: angularGradientStops(gapCount: gapCount, color: color),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                lineWidth: strokeWidth
            )
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(rotation))
            .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 0)
    }

    private func angularGradientStops(gapCount: Int, color: Color) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        let segmentAngle = 1.0 / Double(gapCount)
        let gapSize = 0.1 // 10% of each segment is a gap

        for i in 0..<gapCount {
            let start = Double(i) * segmentAngle
            let gapStart = start + segmentAngle * (1 - gapSize)
            let end = start + segmentAngle

            stops.append(Gradient.Stop(color: color, location: start))
            stops.append(Gradient.Stop(color: color, location: gapStart - 0.01))
            stops.append(Gradient.Stop(color: color.opacity(0), location: gapStart))
            stops.append(Gradient.Stop(color: color.opacity(0), location: end - 0.01))
        }

        return stops
    }

    // MARK: - Layer 3: Core Sphere

    private var coreSphere: some View {
        ZStack {
            // Base radial gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            SanctuaryColors.HeroOrb.primary.opacity(0.8),
                            SanctuaryColors.HeroOrb.secondary.opacity(0.9)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: Layout.coreSize
                    )
                )

            // Inner glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: Layout.coreSize * 0.3
                    )
                )

            // Animated surface noise texture (simulated)
            surfaceNoiseOverlay

            // Highlight arc
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(
                    Color.white.opacity(0.2),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-45))
                .blur(radius: 2)
        }
        .frame(width: Layout.coreSize - 40, height: Layout.coreSize - 40) // 120pt
        .scaleEffect(breathingScale)
        .shadow(color: Color.black.opacity(0.4), radius: 30, x: 0, y: 20)
        .shadow(color: SanctuaryColors.HeroOrb.glow.opacity(0.5), radius: 30, x: 0, y: 0)
    }

    private var surfaceNoiseOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate

            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.1),
                            Color.clear,
                            Color.white.opacity(0.05),
                            Color.clear,
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startAngle: .degrees(phase.truncatingRemainder(dividingBy: 360) * 10),
                        endAngle: .degrees(phase.truncatingRemainder(dividingBy: 360) * 10 + 360)
                    )
                )
                .rotationEffect(.degrees(phase.truncatingRemainder(dividingBy: 360) * 5))
        }
    }

    // MARK: - Layer 4: Level Display

    private var levelDisplay: some View {
        VStack(spacing: SanctuaryLayout.Spacing.xs) {
            Text("CI")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.secondary)

            if let state = state {
                Text("\(state.level)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
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
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    // MARK: - Layer 5: Live Metrics Orbit

    private var liveMetricsOrbit: some View {
        ZStack {
            // HRV indicator
            if let hrv = liveMetrics?.currentHRV {
                orbitingMetric(
                    value: "\(Int(hrv))",
                    icon: "heart.fill",
                    color: .red,
                    angleOffset: 0
                )
            }

            // Focus indicator
            orbitingMetric(
                value: "\(focusScore)%",
                icon: "brain.head.profile",
                color: SanctuaryColors.Dimensions.cognitive,
                angleOffset: 120
            )

            // Energy indicator
            orbitingMetric(
                value: "\(energyLevel)%",
                icon: "bolt.fill",
                color: SanctuaryColors.XP.primary,
                angleOffset: 240
            )
        }
        .rotationEffect(.degrees(metricsOrbitAngle))
    }

    private func orbitingMetric(
        value: String,
        icon: String,
        color: Color,
        angleOffset: Double
    ) -> some View {
        let angle = (angleOffset * .pi / 180)
        let x = cos(angle) * Layout.metricsOrbitRadius
        let y = sin(angle) * Layout.metricsOrbitRadius

        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(SanctuaryColors.Glass.background)
        .clipShape(Capsule())
        .offset(x: x, y: y)
        .rotationEffect(.degrees(-metricsOrbitAngle)) // Counter-rotate to keep text upright
    }

    // MARK: - Computed Properties

    private var dimensionBlendColor: Color {
        // Blend of all dimension colors for the halo
        SanctuaryColors.HeroOrb.primary
    }

    private var focusScore: Int {
        guard let metrics = liveMetrics else { return 0 }
        return min(100, (metrics.todayFocusMinutes * 100) / 240)
    }

    private var energyLevel: Int {
        guard let metrics = liveMetrics, let hrv = metrics.currentHRV else { return 50 }
        return min(100, Int((hrv / 100) * 100))
    }

    // MARK: - Animation

    private func startAnimations() {
        // Halo pulse (4s cycle)
        withAnimation(
            .easeInOut(duration: 4)
            .repeatForever(autoreverses: true)
        ) {
            haloScale = 1.05
        }

        // Ring 1: CW @ 20s
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            ring1Rotation = 360
        }

        // Ring 2: CCW @ 30s
        withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
            ring2Rotation = 360
        }

        // Ring 3: CW @ 45s
        withAnimation(.linear(duration: 45).repeatForever(autoreverses: false)) {
            ring3Rotation = 360
        }

        // Metrics orbit (slow rotation)
        withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
            metricsOrbitAngle = 360
        }
    }
}

// MARK: - Hover & Press State Modifiers

extension SanctuaryHeroOrb {

    /// Apply hover state effects per spec
    func applyHoverState(_ isHovering: Bool) -> some View {
        self
            .scaleEffect(isHovering ? 1.05 : 1.0)
    }

    /// Apply press state effects per spec
    func applyPressState(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Preview

#if DEBUG
struct SanctuaryHeroOrb_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SanctuaryHeroOrb(
                state: CosmoIndexState(
                    level: 24,
                    currentXP: 12847,
                    xpToNextLevel: 16000,
                    xpProgress: 0.784,
                    totalXP: 125000,
                    rank: "Pathfinder"
                ),
                liveMetrics: LiveMetrics(
                    currentHRV: 48,
                    lastHRVTime: Date(),
                    todayXP: 340,
                    activeStreak: 7,
                    todayFocusMinutes: 197,
                    todayWordCount: 2300
                ),
                breathingScale: 1.0,
                isActive: true
            )
        }
    }
}
#endif
