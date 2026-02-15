// CosmoOS/UI/Sanctuary/SanctuaryHeaderView.swift
// Sanctuary Header - Top navigation with tier, progress, and live metrics
// Onyx Design System: sentence case, thin progress line, Roman numeral tiers

import SwiftUI

// MARK: - Sanctuary Header View

/// Top header zone for Sanctuary - displays tier (Roman numeral), rank, progress, and live metrics
public struct SanctuaryHeaderView: View {

    // MARK: - Properties

    let cosmoIndex: CosmoIndexState?
    let liveMetrics: LiveMetrics?
    let showBackButton: Bool
    let onBack: (() -> Void)?

    @State private var xpBarAnimationProgress: CGFloat = 0
    @State private var isHoveringBack: Bool = false

    // MARK: - Roman Numeral Conversion

    static func romanNumeral(for number: Int) -> String {
        let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        let symbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
        var result = ""
        var remaining = max(1, number)
        for (i, value) in values.enumerated() {
            while remaining >= value {
                result += symbols[i]
                remaining -= value
            }
        }
        return result
    }

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
            // Left side - Title and tier info
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                // Back button + Title row
                HStack(spacing: SanctuaryLayout.Spacing.md) {
                    if showBackButton {
                        backButton
                    }

                    Text("Sanctuary")
                        .font(OnyxTypography.viewTitle)
                        .foregroundColor(OnyxColors.Text.primary)
                        .tracking(OnyxTypography.viewTitleTracking)
                }

                // Tier badge and progress
                if let state = cosmoIndex {
                    tierBadge(state: state)
                    progressLine(state: state)
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
            animateProgressBar()
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button(action: { onBack?() }) {
            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))

                Text("Back")
                    .font(OnyxTypography.body)
            }
            .foregroundColor(OnyxColors.Text.secondary)
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
            withAnimation(OnyxSpring.hover) {
                isHoveringBack = hovering
            }
        }
    }

    // MARK: - Tier Badge

    private func tierBadge(state: CosmoIndexState) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.sm) {
            Text("Tier \(Self.romanNumeral(for: state.level))")
                .font(OnyxTypography.label)
                .tracking(OnyxTypography.labelTracking)
                .foregroundColor(OnyxColors.Text.primary)

            Text("\u{00B7} \(state.rank)")
                .font(OnyxTypography.label)
                .tracking(OnyxTypography.labelTracking)
                .foregroundColor(OnyxColors.Text.secondary)
        }
    }

    // MARK: - Progress Line (thin 2pt OnyxProgressLine)

    private func progressLine(state: CosmoIndexState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            OnyxProgressLine(
                progress: xpBarAnimationProgress * state.xpProgress,
                color: OnyxColors.Accent.iris
            )
            .frame(maxWidth: 400)

            // Progress text — no "XP:" prefix, no percentage
            let xpRemaining = max(0, Int(state.xpToNextLevel) - Int(state.currentXP))
            Text("\(formatNumber(xpRemaining)) to Tier \(Self.romanNumeral(for: state.level + 1))")
                .font(OnyxTypography.micro)
                .foregroundColor(OnyxColors.Text.muted)
                .frame(maxWidth: 400, alignment: .leading)
        }
    }

    // MARK: - Animation

    private func animateProgressBar() {
        withAnimation(.easeOut(duration: SanctuaryDurations.slow)) {
            xpBarAnimationProgress = 1.0
        }
    }

    // MARK: - Helpers

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
                    .fill(OnyxColors.Accent.sage)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .stroke(OnyxColors.Accent.sage.opacity(0.5), lineWidth: 1.5)
                            .scaleEffect(livePulse ? 2.0 : 1.0)
                            .opacity(livePulse ? 0 : 0.5)
                    )

                Text("Live")
                    .font(OnyxTypography.label)
                    .tracking(OnyxTypography.labelTracking)
                    .foregroundColor(OnyxColors.Accent.sage)
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
