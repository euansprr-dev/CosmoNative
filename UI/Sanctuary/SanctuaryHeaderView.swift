// CosmoOS/UI/Sanctuary/SanctuaryHeaderView.swift
// Sanctuary Header - Top navigation with level, XP progress, and live metrics
// Phase 2: Home Sanctuary implementation following SANCTUARY_UI_SPEC_V2.md

import SwiftUI

// MARK: - Sanctuary Header View

/// Top header zone for Sanctuary - displays level, rank, XP progress, and live metrics
public struct SanctuaryHeaderView: View {

    // MARK: - Properties

    let cosmoIndex: CosmoIndexState?
    let liveMetrics: LiveMetrics?
    let showBackButton: Bool
    let onBack: (() -> Void)?

    @State private var xpBarAnimationProgress: CGFloat = 0
    @State private var shimmerOffset: CGFloat = 0
    @State private var isHoveringBack: Bool = false

    // MARK: - Initialization

    public init(
        cosmoIndex: CosmoIndexState?,
        liveMetrics: LiveMetrics?,
        showBackButton: Bool = false,
        onBack: (() -> Void)? = nil
    ) {
        self.cosmoIndex = cosmoIndex
        self.liveMetrics = liveMetrics
        self.showBackButton = showBackButton
        self.onBack = onBack
    }

    // MARK: - Body

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left side - Title and level info
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                // Back button + Title row
                HStack(spacing: SanctuaryLayout.Spacing.md) {
                    if showBackButton {
                        backButton
                    }

                    Text("SANCTUARY")
                        .font(SanctuaryTypography.displayMedium)
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .tracking(4)
                }

                // Level badge and XP progress
                if let state = cosmoIndex {
                    levelBadge(state: state)
                    xpProgressBar(state: state)
                }
            }

            Spacer()

            // Right side - Live metrics panel
            if let metrics = liveMetrics, metrics.currentHRV != nil {
                SanctuaryLiveMetricsPanel(metrics: metrics)
            }
        }
        .padding(.horizontal, SanctuaryLayout.Spacing.xxl)
        .padding(.top, SanctuaryLayout.Spacing.xl)
        .padding(.bottom, SanctuaryLayout.Spacing.lg)
        .onAppear {
            animateXPBar()
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button(action: { onBack?() }) {
            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))

                Text("Back")
                    .font(SanctuaryTypography.body)
            }
            .foregroundColor(SanctuaryColors.Text.secondary)
            .padding(.horizontal, SanctuaryLayout.Spacing.md)
            .padding(.vertical, SanctuaryLayout.Spacing.sm)
            .background(
                isHoveringBack
                    ? SanctuaryColors.Glass.highlight
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))
            .scaleEffect(isHoveringBack ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(SanctuarySprings.hover) {
                isHoveringBack = hovering
            }
        }
    }

    // MARK: - Level Badge

    private func levelBadge(state: CosmoIndexState) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.sm) {
            Text("Level \(state.level)")
                .font(SanctuaryTypography.body)
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("•")
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(state.rank)
                .font(SanctuaryTypography.body)
                .foregroundColor(rankColor(for: state.rank))
        }
    }

    // MARK: - XP Progress Bar

    private func xpProgressBar(state: CosmoIndexState) -> some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.xs)
                        .fill(SanctuaryColors.XP.track)
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.xs)
                        .fill(
                            LinearGradient(
                                colors: [SanctuaryColors.XP.primary, SanctuaryColors.XP.secondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * min(xpBarAnimationProgress * CGFloat(state.xpProgress), 1.0),
                            height: 8
                        )
                        .shadow(color: SanctuaryColors.XP.primary.opacity(0.5), radius: 4, x: 0, y: 0)

                    // Shimmer effect
                    if state.xpProgress > 0 {
                        shimmerEffect(width: geometry.size.width, progress: state.xpProgress)
                    }
                }
            }
            .frame(height: 8)
            .frame(maxWidth: 400)

            // XP text
            HStack {
                Text("XP: \(formatNumber(Int(state.currentXP))) / \(formatNumber(Int(state.xpToNextLevel))) to Level \(state.level + 1)")
                    .font(SanctuaryTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                Text("\(Int(state.xpProgress * 100))%")
                    .font(SanctuaryTypography.metric)
                    .foregroundColor(SanctuaryColors.XP.primary)
            }
            .frame(maxWidth: 400)
        }
    }

    // MARK: - Shimmer Effect

    private func shimmerEffect(width: CGFloat, progress: Double) -> some View {
        // Core Animation-driven shimmer — no TimelineView CPU overhead
        let fillWidth = width * CGFloat(progress)
        return Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 60, height: 8)
            .offset(x: -30 + (fillWidth + 60) * shimmerOffset)
            .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.xs))
            .mask(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.xs)
                    .frame(width: fillWidth, height: 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.0
                }
            }
    }

    // MARK: - Animation

    private func animateXPBar() {
        withAnimation(.easeOut(duration: SanctuaryDurations.slow)) {
            xpBarAnimationProgress = 1.0
        }
    }

    // MARK: - Helpers

    private func rankColor(for rank: String) -> Color {
        SanctuaryRanks.color(for: rank)
    }

    private static let _numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    private func formatNumber(_ number: Int) -> String {
        Self._numberFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Live Metrics Panel

/// Floating panel showing real-time metrics (HRV, Focus, Energy)
public struct SanctuaryLiveMetricsPanel: View {

    let metrics: LiveMetrics

    @State private var isExpanded: Bool = false
    @State private var livePulse: Bool = false

    public var body: some View {
        VStack(alignment: .trailing, spacing: SanctuaryLayout.Spacing.sm) {
            // Live indicator
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                // Pulsing live dot
                Circle()
                    .fill(SanctuaryColors.Semantic.success)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(SanctuaryColors.Semantic.success.opacity(0.5), lineWidth: 2)
                            .scaleEffect(livePulse ? 2.0 : 1.0)
                            .opacity(livePulse ? 0 : 0.5)
                    )

                Text("LIVE")
                    .font(SanctuaryTypography.label)
                    .foregroundColor(SanctuaryColors.Semantic.success)
            }

            // Metrics
            VStack(alignment: .trailing, spacing: SanctuaryLayout.Spacing.xs) {
                if let hrv = metrics.currentHRV {
                    metricRow(label: "HRV", value: "\(Int(hrv))ms", color: hrvColor(hrv))
                }

                metricRow(
                    label: "Focus",
                    value: "\(focusScore)%",
                    color: focusColor(focusScore)
                )

                metricRow(
                    label: "Energy",
                    value: "\(energyLevel)%",
                    color: energyColor(energyLevel)
                )
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(SanctuaryColors.Glass.background)
        .overlay(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md))
        .onAppear {
            startLivePulse()
        }
    }

    // MARK: - Metric Row

    private func metricRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            Text(label)
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(value)
                .font(SanctuaryTypography.metric)
                .foregroundColor(color)
        }
    }

    // MARK: - Computed Metrics

    private var focusScore: Int {
        // Derive focus score from focus minutes (assume 4h = 100%)
        min(100, (metrics.todayFocusMinutes * 100) / 240)
    }

    private var energyLevel: Int {
        // Derive energy from HRV and activity
        if let hrv = metrics.currentHRV {
            return min(100, Int((hrv / 100) * 100))
        }
        return 50
    }

    // MARK: - Color Helpers

    private func hrvColor(_ hrv: Double) -> Color {
        switch hrv {
        case 0..<30: return SanctuaryColors.Semantic.error
        case 30..<50: return SanctuaryColors.Semantic.warning
        case 50..<70: return SanctuaryColors.Text.primary
        default: return SanctuaryColors.Semantic.success
        }
    }

    private func focusColor(_ score: Int) -> Color {
        switch score {
        case 0..<40: return SanctuaryColors.Semantic.error
        case 40..<70: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Semantic.success
        }
    }

    private func energyColor(_ level: Int) -> Color {
        switch level {
        case 0..<30: return SanctuaryColors.Semantic.error
        case 30..<60: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Semantic.success
        }
    }

    // MARK: - Animation

    private func startLivePulse() {
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: false)
        ) {
            livePulse = true
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SanctuaryHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                SanctuaryHeaderView(
                    cosmoIndex: CosmoIndexState(
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
                        todayFocusMinutes: 145,
                        todayWordCount: 2300
                    ),
                    showBackButton: false
                )

                Spacer()
            }
        }
    }
}
#endif
