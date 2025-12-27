// CosmoOS/UI/Sanctuary/Dimensions/Cognitive/CognitiveCorrelationMap.swift
// Correlation Map - Horizontal scrolling carousel of correlation cards
// Phase 3: Following SANCTUARY_UI_SPEC_V2.md section 3.1

import SwiftUI

// MARK: - Correlation Map

/// Horizontal scrolling carousel of correlation cards with sparklines
public struct CognitiveCorrelationMap: View {

    // MARK: - Properties

    let correlations: [CognitiveCorrelation]
    let onCorrelationTap: ((CognitiveCorrelation) -> Void)?

    @State private var isVisible: Bool = false
    @State private var selectedCorrelation: UUID?

    // MARK: - Initialization

    public init(
        correlations: [CognitiveCorrelation],
        onCorrelationTap: ((CognitiveCorrelation) -> Void)? = nil
    ) {
        self.correlations = correlations
        self.onCorrelationTap = onCorrelationTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            header

            // Carousel - with vertical padding to allow hover scale animation
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SanctuaryLayout.Spacing.md) {
                    ForEach(Array(correlations.enumerated()), id: \.element.id) { index, correlation in
                        CorrelationCard(
                            correlation: correlation,
                            isSelected: selectedCorrelation == correlation.id,
                            animationDelay: Double(index) * 0.1
                        )
                        .onTapGesture {
                            withAnimation(SanctuarySprings.snappy) {
                                if selectedCorrelation == correlation.id {
                                    selectedCorrelation = nil
                                } else {
                                    selectedCorrelation = correlation.id
                                    onCorrelationTap?(correlation)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, SanctuaryLayout.Spacing.lg)
                .padding(.vertical, SanctuaryLayout.Spacing.sm)  // Allow hover scale without clipping
            }
            .clipShape(Rectangle())  // Clip only horizontally, not vertically

            // Footer hint
            footer
        }
        .padding(.vertical, SanctuaryLayout.Spacing.lg)
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
            withAnimation(.easeOut(duration: 0.4).delay(0.6)) {
                isVisible = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("CORRELATION MAP")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            Spacer()

            // Count indicator
            Text("\(correlations.count) correlations")
                .font(.system(size: 11))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .padding(.horizontal, SanctuaryLayout.Spacing.lg)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text("Tap any correlation to see full causal analysis")
                .font(.system(size: 11))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .padding(.horizontal, SanctuaryLayout.Spacing.lg)
        .padding(.top, SanctuaryLayout.Spacing.sm)  // Add spacing above footer
    }
}

// MARK: - Correlation Card

/// Individual correlation card with sparkline
fileprivate struct CorrelationCard: View {

    // MARK: - Properties

    let correlation: CognitiveCorrelation
    let isSelected: Bool
    let animationDelay: Double

    @State private var isVisible: Bool = false
    @State private var isHovered: Bool = false
    @State private var sparklineAnimated: Bool = false

    // MARK: - Layout Constants

    private enum Layout {
        static let cardWidth: CGFloat = 170
        static let cardHeight: CGFloat = 165  // Increased to fit content
        static let sparklineHeight: CGFloat = 45
    }

    // MARK: - Initialization

    init(
        correlation: CognitiveCorrelation,
        isSelected: Bool = false,
        animationDelay: Double = 0
    ) {
        self.correlation = correlation
        self.isSelected = isSelected
        self.animationDelay = animationDelay
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            // Title
            Text(correlation.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SanctuaryColors.Text.primary)
                .lineLimit(1)

            // Sparkline
            SparklineView(
                data: correlation.sparklineData,
                color: strengthColor,
                isAnimated: sparklineAnimated
            )
            .frame(height: Layout.sparklineHeight)

            // Coefficient
            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                Text(correlation.formattedCoefficient)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                // Trend indicator
                trendIndicator
            }

            // Strength badge
            HStack(spacing: 4) {
                Circle()
                    .fill(strengthColor)
                    .frame(width: 6, height: 6)

                Text(correlation.strength.rawValue.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(strengthColor)

                if correlation.trend != .stable {
                    Image(systemName: correlation.trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(correlation.trend == .up ?
                            SanctuaryColors.Semantic.success :
                            SanctuaryColors.Semantic.error)
                }
            }

            Divider()
                .background(SanctuaryColors.Glass.border)

            // Action insight
            Text(correlation.actionInsight)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .frame(width: Layout.cardWidth, height: Layout.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(
                            isSelected ? strengthColor.opacity(0.7) : SanctuaryColors.Glass.border,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.03 : (isSelected ? 1.02 : 1.0))
        .shadow(
            color: isSelected ? strengthColor.opacity(0.25) : Color.clear,
            radius: 12, x: 0, y: 6
        )
        .opacity(isVisible ? (isSelected ? 1.0 : (selectedSibling ? 0.5 : 1.0)) : 0)
        .offset(y: isVisible ? 0 : 15)
        .animation(SanctuarySprings.hover, value: isHovered)
        .animation(SanctuarySprings.snappy, value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.6 + animationDelay)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.8 + animationDelay)) {
                sparklineAnimated = true
            }
        }
    }

    // MARK: - Computed Properties

    private var strengthColor: Color {
        switch correlation.strength {
        case .strong, .veryStrong: return SanctuaryColors.Semantic.success
        case .moderate: return SanctuaryColors.Semantic.warning
        case .weak: return SanctuaryColors.Text.tertiary
        }
    }

    private var selectedSibling: Bool {
        // This would need parent context to know if another card is selected
        // For now, return false
        false
    }

    private var trendIndicator: some View {
        Group {
            if correlation.trend != .stable {
                Image(systemName: correlation.trend == .up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(correlation.trend == .up ?
                        SanctuaryColors.Semantic.success :
                        SanctuaryColors.Semantic.error)
            }
        }
    }
}

// MARK: - Sparkline View

/// Animated sparkline graph for correlation data
public struct SparklineView: View {

    let data: [Double]
    let color: Color
    let isAnimated: Bool

    public init(data: [Double], color: Color, isAnimated: Bool = true) {
        self.data = data
        self.color = color
        self.isAnimated = isAnimated
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Fill gradient
                sparklinePath(width: width, height: height, closed: true)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask(
                        Rectangle()
                            .scaleEffect(x: isAnimated ? 1 : 0, anchor: .leading)
                            .animation(.easeOut(duration: 0.8), value: isAnimated)
                    )

                // Line stroke
                sparklinePath(width: width, height: height, closed: false)
                    .trim(from: 0, to: isAnimated ? 1 : 0)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .animation(.easeOut(duration: 0.8), value: isAnimated)

                // Data points
                ForEach(0..<data.count, id: \.self) { index in
                    let point = dataPoint(index: index, width: width, height: height)

                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                        .position(point)
                        .opacity(isAnimated ? 1 : 0)
                        .scaleEffect(isAnimated ? 1 : 0)
                        .animation(.spring(response: 0.3).delay(Double(index) * 0.05), value: isAnimated)
                }
            }
        }
    }

    private func sparklinePath(width: CGFloat, height: CGFloat, closed: Bool) -> Path {
        guard data.count > 1 else { return Path() }

        let minValue = data.min() ?? 0
        let maxValue = data.max() ?? 1
        let range = maxValue - minValue
        let normalizedRange = range > 0 ? range : 1

        let stepX = width / CGFloat(data.count - 1)
        let paddingY: CGFloat = 4

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
                    // Smooth curve using quadratic bezier
                    let previousX = CGFloat(index - 1) * stepX
                    let previousValue = (data[index - 1] - minValue) / normalizedRange
                    let previousY = (height - paddingY * 2) * (1 - CGFloat(previousValue)) + paddingY

                    let controlX = (previousX + x) / 2
                    path.addQuadCurve(
                        to: CGPoint(x: x, y: y),
                        control: CGPoint(x: controlX, y: (previousY + y) / 2)
                    )
                }
            }

            if closed {
                path.addLine(to: CGPoint(x: width, y: height))
                path.closeSubpath()
            }
        }
    }

    private func dataPoint(index: Int, width: CGFloat, height: CGFloat) -> CGPoint {
        guard data.count > 1 else { return .zero }

        let minValue = data.min() ?? 0
        let maxValue = data.max() ?? 1
        let range = maxValue - minValue
        let normalizedRange = range > 0 ? range : 1

        let stepX = width / CGFloat(data.count - 1)
        let paddingY: CGFloat = 4

        let x = CGFloat(index) * stepX
        let normalizedValue = (data[index] - minValue) / normalizedRange
        let y = (height - paddingY * 2) * (1 - CGFloat(normalizedValue)) + paddingY

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Correlation Detail Overlay

/// Detailed view for a correlation with causal analysis
public struct CorrelationDetailView: View {

    let correlation: CognitiveCorrelation
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(correlation.title)
                        .font(SanctuaryTypography.title)
                        .foregroundColor(SanctuaryColors.Text.primary)

                    HStack(spacing: SanctuaryLayout.Spacing.sm) {
                        Text(correlation.formattedCoefficient)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(strengthColor)

                        Text("(\(correlation.strength.rawValue.capitalized))")
                            .font(.system(size: 12))
                            .foregroundColor(strengthColor)

                        Text("\(correlation.sampleSize) samples")
                            .font(.system(size: 11))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            // Large sparkline
            SparklineView(
                data: correlation.sparklineData,
                color: strengthColor,
                isAnimated: isVisible
            )
            .frame(height: 80)

            Divider()
                .background(SanctuaryColors.Glass.border)

            // Causal analysis
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                Text("CAUSAL ANALYSIS")
                    .font(SanctuaryTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(correlation.actionInsight)
                    .font(SanctuaryTypography.body)
                    .foregroundColor(SanctuaryColors.Text.primary)

                // Source and target metrics
                HStack(spacing: SanctuaryLayout.Spacing.xl) {
                    metricBadge(
                        label: "Source",
                        value: formatMetricName(correlation.sourceMetric),
                        color: SanctuaryColors.Dimensions.cognitive
                    )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    metricBadge(
                        label: "Target",
                        value: formatMetricName(correlation.targetMetric),
                        color: strengthColor
                    )
                }
            }

            // Trend analysis
            if correlation.trend != .stable {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: correlation.trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(correlation.trend == .up ?
                            SanctuaryColors.Semantic.success :
                            SanctuaryColors.Semantic.error)

                    Text("Trend: \(correlation.trend == .up ? "Strengthening" : "Weakening")")
                        .font(.system(size: 12))
                        .foregroundColor(correlation.trend == .up ?
                            SanctuaryColors.Semantic.success :
                            SanctuaryColors.Semantic.error)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(strengthColor.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.95)
        .onAppear {
            withAnimation(.spring(response: 0.3)) {
                isVisible = true
            }
        }
    }

    private var strengthColor: Color {
        switch correlation.strength {
        case .strong, .veryStrong: return SanctuaryColors.Semantic.success
        case .moderate: return SanctuaryColors.Semantic.warning
        case .weak: return SanctuaryColors.Text.tertiary
        }
    }

    private func metricBadge(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private func formatMetricName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Preview

#if DEBUG
struct CognitiveCorrelationMap_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                CognitiveCorrelationMap(
                    correlations: CognitiveDimensionData.preview.topCorrelations
                ) { correlation in
                    print("Tapped: \(correlation.title)")
                }

                CorrelationDetailView(
                    correlation: CognitiveDimensionData.preview.topCorrelations.first!,
                    onDismiss: {}
                )
                .frame(maxWidth: 400)
            }
            .padding()
        }
    }
}
#endif
