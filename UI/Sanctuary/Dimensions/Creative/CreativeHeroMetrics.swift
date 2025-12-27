// CosmoOS/UI/Sanctuary/Dimensions/Creative/CreativeHeroMetrics.swift
// Hero Metrics - Top-level performance cards with sparklines
// Phase 4: Following SANCTUARY_UI_SPEC_V2.md section 3.2

import SwiftUI

// MARK: - Hero Metrics Row

/// Row of hero metric cards showing key performance indicators
public struct CreativeHeroMetrics: View {

    // MARK: - Properties

    let data: CreativeDimensionData

    @State private var isVisible: Bool = false

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            Text("HERO METRICS")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Cards row
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                HeroMetricCard(
                    title: "TOTAL REACH",
                    value: data.formattedReach,
                    trend: data.reachTrend,
                    trendLabel: "vs last 30d",
                    sparklineData: data.reachSparkline.map { Double($0) },
                    color: SanctuaryColors.Dimensions.creative,
                    animationDelay: 0
                )

                HeroMetricCard(
                    title: "ENGAGEMENT",
                    value: String(format: "%.1f%%", data.engagementRate),
                    trend: data.engagementTrend,
                    trendLabel: "vs last 30d",
                    sparklineData: data.engagementSparkline,
                    color: SanctuaryColors.Semantic.success,
                    animationDelay: 0.05
                )

                HeroMetricCard(
                    title: "FOLLOWERS",
                    value: data.formattedFollowers,
                    trend: Double(data.followerGrowth),
                    trendLabel: "this week",
                    trendIsAbsolute: true,
                    sparklineData: data.followerSparkline.map { Double($0) },
                    color: SanctuaryColors.Dimensions.behavioral,
                    animationDelay: 0.1
                )

                HeroMetricCard(
                    title: "GROWTH RATE",
                    value: String(format: "+%.1f%%/wk", data.growthRate),
                    statusLabel: data.growthStatus.displayName,
                    statusColor: Color(hex: data.growthStatus.color),
                    sparklineData: data.followerSparkline.map { Double($0) },
                    color: Color(hex: data.growthStatus.color),
                    animationDelay: 0.15
                )
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Hero Metric Card

/// Individual hero metric card with sparkline
public struct HeroMetricCard: View {

    // MARK: - Properties

    let title: String
    let value: String
    let trend: Double?
    let trendLabel: String?
    let trendIsAbsolute: Bool
    let statusLabel: String?
    let statusColor: Color?
    let sparklineData: [Double]
    let color: Color
    let animationDelay: Double

    @State private var isVisible: Bool = false
    @State private var sparklineAnimated: Bool = false
    @State private var isHovered: Bool = false

    // MARK: - Initialization

    public init(
        title: String,
        value: String,
        trend: Double? = nil,
        trendLabel: String? = nil,
        trendIsAbsolute: Bool = false,
        statusLabel: String? = nil,
        statusColor: Color? = nil,
        sparklineData: [Double],
        color: Color,
        animationDelay: Double = 0
    ) {
        self.title = title
        self.value = value
        self.trend = trend
        self.trendLabel = trendLabel
        self.trendIsAbsolute = trendIsAbsolute
        self.statusLabel = statusLabel
        self.statusColor = statusColor
        self.sparklineData = sparklineData
        self.color = color
        self.animationDelay = animationDelay
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Title with indicator
            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3, height: 14)

                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)
            }

            // Value
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(SanctuaryColors.Text.primary)

            // Trend or status
            if let trend = trend {
                trendView(trend: trend)
            } else if let status = statusLabel, let statusColor = statusColor {
                statusView(label: status, color: statusColor)
            }

            Spacer()

            // Sparkline
            HeroSparkline(
                data: sparklineData,
                color: color,
                isAnimated: sparklineAnimated
            )
            .frame(height: 30)
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(
                            isHovered ? color.opacity(0.5) : SanctuaryColors.Glass.border,
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: isHovered ? color.opacity(0.2) : Color.clear, radius: 12)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 15)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.1 + animationDelay)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.25 + animationDelay)) {
                sparklineAnimated = true
            }
        }
    }

    // MARK: - Subviews

    private func trendView(trend: Double) -> some View {
        HStack(spacing: 4) {
            if trend > 0 {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Semantic.success)

                if trendIsAbsolute {
                    Text("+\(Int(trend))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SanctuaryColors.Semantic.success)
                } else {
                    Text("+\(String(format: "%.1f", trend))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SanctuaryColors.Semantic.success)
                }
            } else if trend < 0 {
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Semantic.error)

                if trendIsAbsolute {
                    Text("\(Int(trend))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SanctuaryColors.Semantic.error)
                } else {
                    Text("\(String(format: "%.1f", trend))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SanctuaryColors.Semantic.error)
                }
            } else {
                Text("─")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            if let label = trendLabel {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
        }
    }

    private func statusView(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)

            Text("trajectory")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }
}

// MARK: - Hero Sparkline

/// Animated sparkline for hero metrics
public struct HeroSparkline: View {

    let data: [Double]
    let color: Color
    let isAnimated: Bool

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Fill gradient
                sparklinePath(width: width, height: height, closed: true)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.4), color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask(
                        Rectangle()
                            .scaleEffect(x: isAnimated ? 1 : 0, anchor: .leading)
                    )

                // Line stroke
                sparklinePath(width: width, height: height, closed: false)
                    .trim(from: 0, to: isAnimated ? 1 : 0)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
            }
            .animation(.easeOut(duration: 0.6), value: isAnimated)
        }
    }

    private func sparklinePath(width: CGFloat, height: CGFloat, closed: Bool) -> Path {
        guard data.count > 1 else { return Path() }

        let minValue = data.min() ?? 0
        let maxValue = data.max() ?? 1
        let range = maxValue - minValue
        let normalizedRange = range > 0 ? range : 1

        let stepX = width / CGFloat(data.count - 1)
        let paddingY: CGFloat = 2

        return Path { path in
            for (index, value) in data.enumerated() {
                let x = CGFloat(index) * stepX
                let normalizedValue = (value - minValue) / normalizedRange
                let y = (height - paddingY * 2) * (1 - CGFloat(normalizedValue)) + paddingY

                if index == 0 {
                    if closed {
                        path.move(to: CGPoint(x: 0, y: height))
                        path.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        path.move(to: CGPoint(x: x, y: y))
                    }
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            if closed {
                path.addLine(to: CGPoint(x: width, y: height))
                path.closeSubpath()
            }
        }
    }
}

// MARK: - Compact Hero Metric

/// Smaller version of hero metric for compact layouts
public struct CompactHeroMetric: View {

    let title: String
    let value: String
    let trend: Double?
    let color: Color

    @State private var isHovered: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(SanctuaryColors.Text.primary)

                if let trend = trend, trend != 0 {
                    Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(trend > 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Live Status Indicator

/// Shows live posting status
public struct CreativeLiveStatus: View {

    let nextPostTime: String?
    let bestTime: String

    @State private var isPulsing: Bool = false

    public var body: some View {
        VStack(alignment: .trailing, spacing: SanctuaryLayout.Spacing.xs) {
            // Live indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0.6 : 1.0)

                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Next post
            if let nextPost = nextPostTime {
                Text("Posting in \(nextPost)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            // Best time
            Text("Best: \(bestTime)")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1)
                .repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CreativeHeroMetrics_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                CreativeHeroMetrics(data: .preview)

                HStack(spacing: 16) {
                    CompactHeroMetric(
                        title: "REACH",
                        value: "847.2K",
                        trend: 12.3,
                        color: SanctuaryColors.Dimensions.creative
                    )

                    CompactHeroMetric(
                        title: "ENGAGEMENT",
                        value: "4.7%",
                        trend: 0.3,
                        color: SanctuaryColors.Semantic.success
                    )

                    CreativeLiveStatus(
                        nextPostTime: "2h",
                        bestTime: "3:15pm"
                    )
                }
            }
            .padding()
        }
    }
}
#endif
