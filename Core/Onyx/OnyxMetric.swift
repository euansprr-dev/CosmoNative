// CosmoOS/Core/Onyx/OnyxMetric.swift
// Standardized metric display — replaces ad-hoc number + progress bar patterns.
// PRD Section 6.2: "A thin '73' at 56pt feels like a precision instrument."

import SwiftUI

/// Display style for metric values.
enum OnyxMetricStyle {
    /// 56pt Ultralight — Cosmo Index, dimension hero scores
    case hero
    /// 32pt Light — secondary heroes, large card values
    case large
    /// 22pt Light — compact card metrics
    case compact
    /// 14pt Regular — inline metric within body text
    case inline
}

/// Trend direction for a metric.
enum OnyxTrend {
    case up
    case down
    case stable
}

/// Premium metric display with animated count-up, thin progress line, and trend indicator.
struct OnyxMetric: View {
    let label: String
    var value: Double
    var displayStyle: OnyxMetricStyle
    var unit: String?
    var progress: Double?
    var progressColor: Color
    var trend: OnyxTrend?
    var trendLabel: String?

    @State private var animatedValue: Double = 0
    @State private var hasAppeared = false

    init(
        label: String,
        value: Double,
        displayStyle: OnyxMetricStyle = .large,
        unit: String? = nil,
        progress: Double? = nil,
        progressColor: Color = OnyxColors.Accent.iris,
        trend: OnyxTrend? = nil,
        trendLabel: String? = nil
    ) {
        self.label = label
        self.value = value
        self.displayStyle = displayStyle
        self.unit = unit
        self.progress = progress
        self.progressColor = progressColor
        self.trend = trend
        self.trendLabel = trendLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label row (with optional trend)
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(OnyxTypography.sectionTitle)
                    .tracking(OnyxTypography.sectionTitleTracking)
                    .foregroundColor(OnyxColors.Text.secondary)

                Spacer()

                if let trend = trend {
                    trendView(trend)
                }
            }

            // Value row
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formattedValue)
                    .font(fontForStyle)
                    .foregroundColor(OnyxColors.Text.primary)
                    .contentTransition(.numericText(value: animatedValue))

                if let unit = unit {
                    Text(unit)
                        .font(OnyxTypography.label)
                        .foregroundColor(OnyxColors.Text.tertiary)
                }
            }

            // Progress line
            if let progress = progress {
                OnyxProgressLine(
                    progress: progress,
                    color: progressColor
                )
                .padding(.top, 4)
            }

            // Trend label
            if let trendLabel = trendLabel {
                Text(trendLabel)
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Text.muted)
                    .padding(.top, 2)
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            withAnimation(OnyxSpring.metricSettle) {
                animatedValue = value
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(OnyxSpring.metricSettle) {
                animatedValue = newValue
            }
        }
    }

    // MARK: - Helpers

    private var formattedValue: String {
        if animatedValue == animatedValue.rounded() && animatedValue < 10000 {
            return "\(Int(animatedValue))"
        }
        return String(format: "%.1f", animatedValue)
    }

    private var fontForStyle: Font {
        switch displayStyle {
        case .hero: return OnyxTypography.heroMetric
        case .large: return OnyxTypography.largeMetric
        case .compact: return OnyxTypography.compactMetric
        case .inline: return OnyxTypography.body
        }
    }

    @ViewBuilder
    private func trendView(_ trend: OnyxTrend) -> some View {
        HStack(spacing: 2) {
            Image(systemName: trendIcon(trend))
                .font(.system(size: 10, weight: .medium))
            if let trendLabel = trendLabel {
                Text(trendLabel)
                    .font(OnyxTypography.micro)
            }
        }
        .foregroundColor(trendColor(trend))
    }

    private func trendIcon(_ trend: OnyxTrend) -> String {
        switch trend {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    private func trendColor(_ trend: OnyxTrend) -> Color {
        switch trend {
        case .up: return OnyxColors.Accent.sage
        case .down: return OnyxColors.Accent.rose
        case .stable: return OnyxColors.Text.tertiary
        }
    }
}
