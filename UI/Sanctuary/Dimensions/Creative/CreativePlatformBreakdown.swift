// CosmoOS/UI/Sanctuary/Dimensions/Creative/CreativePlatformBreakdown.swift
// Platform Breakdown - Distribution chart and per-platform metrics
// Phase 4: Following SANCTUARY_UI_SPEC_V2.md section 3.2

import SwiftUI

// MARK: - Platform Breakdown

/// Shows platform distribution and detailed per-platform metrics
public struct CreativePlatformBreakdown: View {

    // MARK: - Properties

    let platforms: [PlatformMetrics]
    let onPlatformTap: ((PlatformMetrics) -> Void)?

    @State private var isVisible: Bool = false
    @State private var chartAnimated: Bool = false
    @State private var selectedPlatform: ContentPlatform?

    // MARK: - Initialization

    public init(
        platforms: [PlatformMetrics],
        onPlatformTap: ((PlatformMetrics) -> Void)? = nil
    ) {
        self.platforms = platforms
        self.onPlatformTap = onPlatformTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("PLATFORM BREAKDOWN")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.xxl) {
                // Distribution chart
                distributionChart
                    .frame(width: 200, height: 200)

                // Platform cards
                platformCardsGrid
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
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.7)) {
                chartAnimated = true
            }
        }
    }

    // MARK: - Distribution Chart

    private var distributionChart: some View {
        let totalFollowers = platforms.reduce(0) { $0 + $1.followers }

        return ZStack {
            // Pie chart segments
            ForEach(Array(platforms.enumerated()), id: \.element.platform) { index, platform in
                let startAngle = startAngle(for: index)
                let endAngle = endAngle(for: index, total: totalFollowers)

                PieSegment(
                    startAngle: startAngle,
                    endAngle: chartAnimated ? endAngle : startAngle,
                    platform: platform.platform,
                    isSelected: selectedPlatform == platform.platform
                )
                .onTapGesture {
                    withAnimation(SanctuarySprings.snappy) {
                        if selectedPlatform == platform.platform {
                            selectedPlatform = nil
                        } else {
                            selectedPlatform = platform.platform
                        }
                    }
                }
            }

            // Center content
            VStack(spacing: 2) {
                Text(formatNumber(totalFollowers))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("Total Followers")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
            .frame(width: 100, height: 100)
            .background(
                Circle()
                    .fill(SanctuaryColors.Glass.background)
            )
        }
        .animation(.easeOut(duration: 0.8), value: chartAnimated)
    }

    private func startAngle(for index: Int) -> Double {
        let totalFollowers = Double(platforms.reduce(0) { $0 + $1.followers })
        guard totalFollowers > 0 else { return 0 }

        var angle: Double = -90 // Start from top
        for i in 0..<index {
            angle += (Double(platforms[i].followers) / totalFollowers) * 360
        }
        return angle
    }

    private func endAngle(for index: Int, total: Int) -> Double {
        let totalFollowers = Double(total)
        guard totalFollowers > 0 else { return 0 }

        let startAngle = self.startAngle(for: index)
        let segmentAngle = (Double(platforms[index].followers) / totalFollowers) * 360
        return startAngle + segmentAngle
    }

    // MARK: - Platform Cards Grid

    private var platformCardsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md),
                GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md)
            ],
            spacing: SanctuaryLayout.Spacing.md
        ) {
            ForEach(platforms, id: \.platform) { platform in
                PlatformMetricCard(
                    metrics: platform,
                    isSelected: selectedPlatform == platform.platform,
                    onTap: {
                        withAnimation(SanctuarySprings.snappy) {
                            selectedPlatform = platform.platform
                        }
                        onPlatformTap?(platform)
                    }
                )
            }
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

// MARK: - Pie Segment

private struct PieSegment: View {

    let startAngle: Double
    let endAngle: Double
    let platform: ContentPlatform
    let isSelected: Bool

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2 - (isSelected ? 5 : 10)
            let innerRadius = radius * 0.6

            Path { path in
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(endAngle),
                    clockwise: false
                )
                path.addArc(
                    center: center,
                    radius: innerRadius,
                    startAngle: .degrees(endAngle),
                    endAngle: .degrees(startAngle),
                    clockwise: true
                )
                path.closeSubpath()
            }
            .fill(platform.color.opacity(isSelected ? 1 : 0.8))
            .shadow(color: isSelected ? platform.color.opacity(0.4) : Color.clear, radius: 8)
        }
        .animation(SanctuarySprings.hover, value: isSelected)
    }
}

// MARK: - Platform Metric Card

/// Individual platform performance card
public struct PlatformMetricCard: View {

    // MARK: - Properties

    let metrics: PlatformMetrics
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Image(systemName: metrics.platform.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(metrics.platform.color)

                Text(metrics.platform.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Spacer()

                // Growth indicator
                growthIndicator
            }

            // Metrics
            HStack(spacing: SanctuaryLayout.Spacing.lg) {
                metricColumn(
                    label: "Followers",
                    value: formatNumber(metrics.followers)
                )

                metricColumn(
                    label: "Avg Reach",
                    value: formatNumber(metrics.averageReach)
                )

                metricColumn(
                    label: "Engagement",
                    value: String(format: "%.1f%%", metrics.engagementRate)
                )
            }

            // Retention bar
            retentionBar
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(
                            isSelected || isHovered ? metrics.platform.color.opacity(0.5) : SanctuaryColors.Glass.border,
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: isHovered ? metrics.platform.color.opacity(0.2) : Color.clear, radius: 10)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(perform: onTap)
    }

    // MARK: - Subviews

    private var growthIndicator: some View {
        HStack(spacing: 2) {
            Image(systemName: metrics.growth >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))

            Text(String(format: "%.1f%%", abs(metrics.growth)))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(metrics.growth >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)
    }

    private func metricColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }

    private var retentionBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Retention")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                Text(String(format: "%.0f%%", metrics.retentionRate))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SanctuaryColors.Glass.highlight)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [metrics.platform.color, metrics.platform.color.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * (metrics.retentionRate / 100))
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

// MARK: - Platform Comparison Chart

/// Bar chart comparing metrics across platforms
public struct PlatformComparisonChart: View {

    // MARK: - Properties

    let platforms: [PlatformMetrics]
    let metric: ComparisonMetric

    @State private var isAnimated: Bool = false

    public enum ComparisonMetric: String, CaseIterable {
        case followers = "Followers"
        case reach = "Avg Reach"
        case engagement = "Engagement"
        case growth = "Growth"

        func value(for platform: PlatformMetrics) -> Double {
            switch self {
            case .followers: return Double(platform.followers)
            case .reach: return Double(platform.averageReach)
            case .engagement: return platform.engagementRate
            case .growth: return platform.growth
            }
        }
    }

    // MARK: - Initialization

    public init(platforms: [PlatformMetrics], metric: ComparisonMetric = .engagement) {
        self.platforms = platforms
        self.metric = metric
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text(metric.rawValue.uppercased())
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            HStack(alignment: .bottom, spacing: SanctuaryLayout.Spacing.md) {
                ForEach(platforms, id: \.platform) { platform in
                    comparisonBar(for: platform)
                }
            }
            .frame(height: 120)
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
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                isAnimated = true
            }
        }
    }

    private func comparisonBar(for platform: PlatformMetrics) -> some View {
        let value = metric.value(for: platform)
        let maxValue = platforms.map { metric.value(for: $0) }.max() ?? 1
        let normalizedHeight = maxValue > 0 ? (value / maxValue) : 0

        return VStack(spacing: SanctuaryLayout.Spacing.xs) {
            // Value label
            Text(formatValue(value))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.secondary)

            // Bar
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [platform.platform.color, platform.platform.color.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: isAnimated ? 80 * normalizedHeight : 0)

            // Platform icon
            Image(systemName: platform.platform.iconName)
                .font(.system(size: 12))
                .foregroundColor(platform.platform.color)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.6), value: isAnimated)
    }

    private func formatValue(_ value: Double) -> String {
        switch metric {
        case .followers, .reach:
            if value >= 1_000_000 {
                return String(format: "%.1fM", value / 1_000_000)
            } else if value >= 1_000 {
                return String(format: "%.0fK", value / 1_000)
            }
            return String(format: "%.0f", value)
        case .engagement, .growth:
            return String(format: "%.1f%%", value)
        }
    }
}

// MARK: - Platform Growth Timeline

/// Shows growth trends over time for each platform
public struct PlatformGrowthTimeline: View {

    let platforms: [PlatformMetrics]

    @State private var isVisible: Bool = false
    @State private var selectedTimeRange: CreativeTimeRange = .month

    public init(platforms: [PlatformMetrics]) {
        self.platforms = platforms
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header with range selector
            HStack {
                Text("GROWTH TIMELINE")
                    .font(SanctuaryTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(2)

                Spacer()

                // Range selector
                HStack(spacing: 2) {
                    ForEach([CreativeTimeRange.week, .month, .quarter], id: \.self) { range in
                        Button(action: {
                            withAnimation(SanctuarySprings.snappy) {
                                selectedTimeRange = range
                            }
                        }) {
                            Text(range.displayName)
                                .font(.system(size: 10, weight: selectedTimeRange == range ? .bold : .medium))
                                .foregroundColor(selectedTimeRange == range ? SanctuaryColors.Text.primary : SanctuaryColors.Text.tertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedTimeRange == range ? SanctuaryColors.Dimensions.creative.opacity(0.2) : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(2)
                .background(SanctuaryColors.Glass.highlight)
                .clipShape(Capsule())
            }

            // Growth lines
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height

                ZStack {
                    // Grid
                    ForEach(0..<4, id: \.self) { i in
                        Path { path in
                            let y = height * CGFloat(i) / 3
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                        .stroke(SanctuaryColors.Glass.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    // Platform lines (mock data for now)
                    ForEach(platforms, id: \.platform) { platform in
                        growthLine(for: platform, width: width, height: height)
                    }
                }
            }
            .frame(height: 100)

            // Legend
            HStack(spacing: SanctuaryLayout.Spacing.lg) {
                ForEach(platforms, id: \.platform) { platform in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(platform.platform.color)
                            .frame(width: 6, height: 6)

                        Text(platform.platform.shortName)
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                }

                Spacer()
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
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.55)) {
                isVisible = true
            }
        }
    }

    private func growthLine(for platform: PlatformMetrics, width: CGFloat, height: CGFloat) -> some View {
        // Generate mock growth data based on current growth rate
        let dataPoints = 7
        let baseGrowth = platform.growth / 100

        return Path { path in
            for i in 0..<dataPoints {
                let x = width * CGFloat(i) / CGFloat(dataPoints - 1)
                // Create a slightly randomized but trending line
                let noise = Double.random(in: -0.1...0.1)
                let progress = Double(i) / Double(dataPoints - 1)
                let y = height * (0.5 - CGFloat(baseGrowth * progress + noise) * 0.3)

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(
            platform.platform.color,
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }
}

// MARK: - Compact Platform Summary

/// Compact view for embedding platform info
public struct PlatformSummaryCompact: View {

    let platforms: [PlatformMetrics]

    public init(platforms: [PlatformMetrics]) {
        self.platforms = platforms
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            ForEach(platforms.prefix(4), id: \.platform) { platform in
                VStack(spacing: 4) {
                    Image(systemName: platform.platform.iconName)
                        .font(.system(size: 14))
                        .foregroundColor(platform.platform.color)

                    Text(formatNumber(platform.followers))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    HStack(spacing: 2) {
                        Image(systemName: platform.growth >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 7, weight: .bold))

                        Text(String(format: "%.0f%%", abs(platform.growth)))
                            .font(.system(size: 8, design: .monospaced))
                    }
                    .foregroundColor(platform.growth >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)
                }
                .frame(maxWidth: .infinity)
            }
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
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

// MARK: - Preview

#if DEBUG
struct CreativePlatformBreakdown_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    CreativePlatformBreakdown(
                        platforms: CreativeDimensionData.preview.platformMetrics
                    )

                    PlatformComparisonChart(
                        platforms: CreativeDimensionData.preview.platformMetrics,
                        metric: .engagement
                    )

                    PlatformGrowthTimeline(
                        platforms: CreativeDimensionData.preview.platformMetrics
                    )

                    PlatformSummaryCompact(
                        platforms: CreativeDimensionData.preview.platformMetrics
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 800)
    }
}
#endif
