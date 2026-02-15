// CosmoOS/UI/Sanctuary/DimensionOrbView.swift
// Dimension Orb - Individual dimension visualization with NELO and level
// Animated with pulsing, glow, and activity indicators
// Phase 2: Enhanced with status ring per SANCTUARY_UI_SPEC_V2.md section 2.3

import SwiftUI

// MARK: - Dimension Orb View

public struct DimensionOrbView: View {

    let dimension: LevelDimension
    let state: SanctuaryDimensionState?
    let isSelected: Bool
    let animationPhase: Double

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.5
    @State private var isHovered: Bool = false
    @State private var statusRingProgress: CGFloat = 0

    private let baseSize: CGFloat = SanctuaryLayout.Sizing.dimensionOrb

    /// Health score derived from NELO (0-100)
    private var healthScore: Double {
        guard let state = state else { return 0 }
        // NELO ~2000 = 100% health, ~800 = 0%
        return min(100, max(0, Double(state.nelo - 800) / 12))
    }

    /// Luminosity-based orb opacity: 0.65 base + (level * 0.05), capped at 1.0
    private var luminosityOpacity: Double {
        guard let state = state else { return 0.65 }
        return min(1.0, 0.65 + Double(state.level) * 0.05)
    }

    /// Glow intensity scales with level
    private var levelGlowRadius: CGFloat {
        guard let state = state else { return 4 }
        return 4 + CGFloat(min(state.level, 20)) * 0.8
    }

    /// Desaturated dimension color (Onyx hub palette)
    private var onyxDimensionColor: Color {
        OnyxColors.Dimension.color(for: dimension)
    }

    /// Blended orb color: mix desaturated + vivid for richer appearance
    private var enrichedOrbColor: Color {
        // 60% desaturated + 40% vivid via overlay approach — we use vivid directly in gradient
        OnyxColors.DimensionVivid.color(for: dimension)
    }

    public var body: some View {
        ZStack {
            // Layer 1: Ambient Glow (luminosity-based) — rendered behind, doesn't affect layout
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            onyxDimensionColor.opacity(luminosityOpacity * 0.3),
                            onyxDimensionColor.opacity(luminosityOpacity * 0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: (baseSize + 48) / 2
                    )
                )
                .frame(width: baseSize + 80, height: baseSize + 80)
                .allowsHitTesting(false)

            // Layer 2: Status Ring (health indicator)
            statusRing

            // Activity ring (animated when active)
            if let state = state, state.isActive {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [onyxDimensionColor, onyxDimensionColor.opacity(0.3), onyxDimensionColor],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: baseSize + 10, height: baseSize + 10)
                    .rotationEffect(.degrees(animationPhase * 30))
            }

            // Layer 3: Orb Body — luminosity-based, no level number
            ZStack {
                // Base gradient (blended dimension color, opacity driven by level)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                enrichedOrbColor.opacity(luminosityOpacity * 0.5),
                                onyxDimensionColor.opacity(luminosityOpacity * 0.9),
                                onyxDimensionColor.opacity(luminosityOpacity * 0.4)
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: baseSize
                        )
                    )

                // Inner highlight (glass-like)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: baseSize * 0.4
                        )
                    )

                // Border: desaturated color at reduced opacity
                Circle()
                    .stroke(onyxDimensionColor.opacity(0.35), lineWidth: 1)

                // Icon only — no level number
                Image(systemName: SanctuaryIcons.Dimensions.icon(for: dimension))
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(OnyxColors.Text.primary)
            }
            .frame(width: baseSize, height: baseSize)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: isHovered ? 10 : 6)
            .shadow(color: onyxDimensionColor.opacity(isHovered ? 0.4 : 0.2), radius: levelGlowRadius, x: 0, y: 0)
            .scaleEffect(pulseScale * (isSelected ? 1.15 : 1.0) * (isHovered ? 1.05 : 1.0))
            .offset(y: isHovered ? -4 : 0)
            .animation(OnyxSpring.hover, value: isHovered)

            // Selection ring
            if isSelected {
                Circle()
                    .stroke(OnyxColors.Text.primary, lineWidth: 2)
                    .frame(width: baseSize + 4, height: baseSize + 4)
            }

            // Streak badge (using glass material)
            if let state = state, state.streak >= 3 {
                HStack(spacing: SanctuaryLayout.Spacing.xxs) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8))

                    Text("\(state.streak)")
                        .font(OnyxTypography.label)
                }
                .foregroundColor(OnyxColors.Accent.amber)
                .padding(.horizontal, SanctuaryLayout.Spacing.sm)
                .padding(.vertical, SanctuaryLayout.Spacing.xxs)
                .background(OnyxColors.Elevation.raised)
                .clipShape(Capsule())
                .offset(x: baseSize * 0.3, y: -baseSize * 0.35)
            }

            // Trend indicator
            if let state = state, state.trend != .stable {
                Image(systemName: state.trend == .up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(state.trend == .up ? OnyxColors.Accent.sage : OnyxColors.Accent.rose)
                    .padding(SanctuaryLayout.Spacing.xs)
                    .background(OnyxColors.Elevation.raised)
                    .clipShape(Circle())
                    .offset(x: -baseSize * 0.3, y: -baseSize * 0.35)
            }

            // Dimension label — positioned just below the orb circle, not below the glow
            Text(dimension.displayName)
                .font(.system(size: 11, design: .serif))
                .foregroundColor(OnyxColors.Text.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(OnyxColors.Elevation.void.opacity(0.85))
                )
                .shadow(color: OnyxColors.Elevation.void, radius: 4, x: 0, y: 0)
                .offset(y: baseSize / 2 + 22)
        }
        .frame(width: baseSize + 80, height: baseSize + 80)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Status Ring

    /// Circular progress ring showing dimension health (0-100%)
    private var statusRing: some View {
        ZStack {
            // Track
            Circle()
                .stroke(
                    onyxDimensionColor.opacity(0.15),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: baseSize + 16, height: baseSize + 16)

            // Progress
            Circle()
                .trim(from: 0, to: statusRingProgress * CGFloat(healthScore / 100))
                .stroke(
                    onyxDimensionColor.opacity(0.6),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: baseSize + 16, height: baseSize + 16)
                .rotationEffect(.degrees(-90))
                .shadow(color: onyxDimensionColor.opacity(0.3), radius: 3, x: 0, y: 0)
        }
    }

    // MARK: - Computed Properties

    private var dimensionColor: Color {
        SanctuaryColors.Dimensions.color(for: dimension)
    }

    // MARK: - Animation

    private func startAnimations() {
        // Animate status ring on appear (one-time, not repeating)
        withAnimation(.easeOut(duration: SanctuaryDurations.slow).delay(0.2)) {
            statusRingProgress = 1.0
        }

        // PERFORMANCE FIX: Synchronized pulse and glow animations
        // Both use the same duration to prevent visual conflicts and reduce CATransaction overhead
        // Using slow duration (3s) for subtle, ambient effect
        let ambientDuration = SanctuaryDurations.slow

        withAnimation(
            .easeInOut(duration: ambientDuration)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.03
            glowOpacity = 0.7  // Sync with pulse for unified breathing effect
        }
    }
}

// MARK: - Insight Carousel View

public struct InsightCarouselView: View {

    let insights: [CorrelationInsight]
    @Binding var selectedInsight: CorrelationInsight?

    @State private var currentIndex = 0

    public var body: some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            // Title
            HStack {
                Image(systemName: SanctuaryIcons.Actions.insight)
                    .foregroundColor(SanctuaryColors.XP.primary)

                Text("Insights")
                    .font(SanctuaryTypography.body)
                    .foregroundColor(SanctuaryColors.Text.primary)

                Spacer()

                Text("\(currentIndex + 1)/\(insights.count)")
                    .font(SanctuaryTypography.metric)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Carousel
            TabView(selection: $currentIndex) {
                ForEach(Array(insights.enumerated()), id: \.element.uuid) { index, insight in
                    InsightCardView(insight: insight)
                        .tag(index)
                        .onTapGesture {
                            selectedInsight = insight
                        }
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .frame(height: 100)
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .sanctuaryGlass(.secondary)
        .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg))
    }
}

// MARK: - Insight Card View

public struct InsightCardView: View {

    let insight: CorrelationInsight
    @State private var isHovered: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            // Confidence badge
            HStack {
                confidenceBadge

                Spacer()

                strengthBadge
            }

            // Description
            Text(insight.humanDescription)
                .font(SanctuaryTypography.body)
                .foregroundColor(SanctuaryColors.Text.primary)
                .lineLimit(2)

            // Metrics
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                metricPill(insight.sourceMetric, icon: "arrow.right")
                metricPill(insight.targetMetric, icon: "target")
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var confidenceBadge: some View {
        HStack(spacing: SanctuaryLayout.Spacing.xs) {
            Circle()
                .fill(confidenceColor)
                .frame(width: 6, height: 6)

            Text(insight.confidence.rawValue.capitalized)
                .font(SanctuaryTypography.label)
                .foregroundColor(confidenceColor)
        }
        .padding(.horizontal, SanctuaryLayout.Spacing.sm)
        .padding(.vertical, SanctuaryLayout.Spacing.xs)
        .background(confidenceColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var strengthBadge: some View {
        Text(insight.strength.rawValue.capitalized)
            .font(SanctuaryTypography.label)
            .foregroundColor(SanctuaryColors.Text.tertiary)
            .padding(.horizontal, SanctuaryLayout.Spacing.sm)
            .padding(.vertical, SanctuaryLayout.Spacing.xs)
            .background(SanctuaryColors.Glass.highlight)
            .clipShape(Capsule())
    }

    private func metricPill(_ metric: String, icon: String) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 8))

            Text(formatMetricName(metric))
                .font(SanctuaryTypography.label)
        }
        .foregroundColor(SanctuaryColors.Text.secondary)
        .padding(.horizontal, SanctuaryLayout.Spacing.sm)
        .padding(.vertical, SanctuaryLayout.Spacing.xs)
        .background(SanctuaryColors.Glass.highlight)
        .clipShape(Capsule())
    }

    private var confidenceColor: Color {
        switch insight.confidence {
        case .proven: return SanctuaryColors.Semantic.success
        case .established: return SanctuaryColors.Dimensions.behavioral
        case .developing: return SanctuaryColors.Semantic.warning
        case .emerging: return SanctuaryColors.Semantic.error
        }
    }

    private var borderColor: Color {
        insight.coefficient > 0
            ? SanctuaryColors.Semantic.success.opacity(0.3)
            : SanctuaryColors.Semantic.error.opacity(0.3)
    }

    private func formatMetricName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            DimensionOrbView(
                dimension: .cognitive,
                state: SanctuaryDimensionState(
                    dimension: .cognitive,
                    level: 15,
                    nelo: 1450,
                    currentXP: 200,
                    xpToNextLevel: 300,
                    xpProgress: 0.66,
                    streak: 7,
                    lastActivity: Date(),
                    trend: .up,
                    isActive: true
                ),
                isSelected: true,
                animationPhase: 0
            )

            DimensionOrbView(
                dimension: .physiological,
                state: SanctuaryDimensionState(
                    dimension: .physiological,
                    level: 12,
                    nelo: 1280,
                    currentXP: 150,
                    xpToNextLevel: 250,
                    xpProgress: 0.6,
                    streak: 0,
                    lastActivity: nil,
                    trend: .down,
                    isActive: false
                ),
                isSelected: false,
                animationPhase: 0
            )
        }
    }
}
