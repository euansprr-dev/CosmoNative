// CosmoOS/UI/Sanctuary/Dimensions/Physiological/PhysiologicalCorrelationMap.swift
// Correlation Map - Health metric correlations and predictions
// Phase 5: Following SANCTUARY_UI_SPEC_V2.md section 3.3

import SwiftUI

// MARK: - Correlation Map

/// Shows correlations between health metrics
public struct PhysiologicalCorrelationMap: View {

    // MARK: - Properties

    let correlations: [PhysiologicalCorrelation]
    let predictions: [HealthPrediction]

    @State private var isVisible: Bool = false

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("CORRELATION MAP")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Correlation cards grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md),
                    GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md)
                ],
                spacing: SanctuaryLayout.Spacing.md
            ) {
                ForEach(correlations) { correlation in
                    CorrelationCard(correlation: correlation)
                }
            }

            // Prediction section
            if let prediction = predictions.first {
                HealthPredictionCard(prediction: prediction)
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
            withAnimation(.easeOut(duration: 0.4).delay(0.45)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Correlation Card

/// Individual correlation card showing relationship between metrics
fileprivate struct CorrelationCard: View {

    let correlation: PhysiologicalCorrelation

    @State private var isHovered: Bool = false
    @State private var lineAnimated: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Source → Target header
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Text(correlation.sourceMetric)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(correlation.targetMetric)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Correlation coefficient
            HStack {
                Text("r = \(String(format: "%.2f", correlation.correlationCoefficient))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                Text(correlation.strengthLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(strengthColor)
            }

            // Visual connection line
            connectionLine

            // Impact
            HStack {
                Text(correlation.targetMetric)
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                HStack(spacing: 2) {
                    Text(correlation.impactPercent >= 0 ? "+" : "")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(impactColor)

                    Text("\(Int(correlation.impactPercent))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(impactColor)
                }

                Text(correlation.timeframe)
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? strengthColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                lineAnimated = true
            }
        }
    }

    private var connectionLine: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // Background line
                Rectangle()
                    .fill(SanctuaryColors.Glass.border)
                    .frame(height: 2)

                // Animated progress line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [strengthColor, strengthColor.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: lineAnimated ? width : 0, height: 2)
                    .animation(.easeOut(duration: 0.6), value: lineAnimated)

                // Dots at ends
                HStack {
                    Circle()
                        .fill(strengthColor)
                        .frame(width: 6, height: 6)

                    Spacer()

                    Circle()
                        .fill(strengthColor)
                        .frame(width: 6, height: 6)
                        .opacity(lineAnimated ? 1 : 0)
                }
            }
        }
        .frame(height: 8)
    }

    private var strengthColor: Color {
        let absR = abs(correlation.correlationCoefficient)
        if absR >= 0.7 {
            return correlation.isPositive ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error
        } else if absR >= 0.4 {
            return SanctuaryColors.Semantic.warning
        }
        return SanctuaryColors.Text.tertiary
    }

    private var impactColor: Color {
        correlation.impactPercent >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error
    }
}

// MARK: - Prediction Card

/// AI-generated health prediction card
public struct HealthPredictionCard: View {

    let prediction: HealthPrediction

    @State private var isExpanded: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("PREDICTION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SanctuaryColors.XP.primary)
                        .tracking(1)
                }

                Spacer()

                // Confidence badge
                Text("CONFIDENCE: \(Int(prediction.confidence * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Condition (IF)
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                Text("IF:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(prediction.condition)
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Prediction (THEN)
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                Text("THEN:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(prediction.prediction)
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Based on
            if isExpanded {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    Text("Based on:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    ForEach(prediction.basedOn, id: \.self) { basis in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(SanctuaryColors.Text.tertiary)
                                .frame(width: 3, height: 3)

                            Text(basis)
                                .font(.system(size: 10))
                                .foregroundColor(SanctuaryColors.Text.secondary)
                        }
                    }
                }
            }

            // Action buttons
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                ForEach(prediction.actions, id: \.self) { action in
                    actionButton(action)
                }

                Spacer()

                // Expand/collapse button
                Button(action: {
                    withAnimation(SanctuarySprings.snappy) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.XP.primary.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func actionButton(_ action: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 4) {
                Image(systemName: iconForAction(action))
                    .font(.system(size: 10))

                Text(action)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(SanctuaryColors.Dimensions.physiological)
            .padding(.horizontal, SanctuaryLayout.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(SanctuaryColors.Dimensions.physiological.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                            .stroke(SanctuaryColors.Dimensions.physiological.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func iconForAction(_ action: String) -> String {
        if action.lowercased().contains("schedule") { return "calendar" }
        if action.lowercased().contains("analysis") { return "chart.bar" }
        if action.lowercased().contains("remind") { return "bell" }
        return "arrow.right"
    }
}

// MARK: - Mini Correlation Badge

/// Small correlation indicator for compact views
public struct CorrelationBadge: View {

    let source: String
    let target: String
    let correlation: Double

    public init(source: String, target: String, correlation: Double) {
        self.source = source
        self.target = target
        self.correlation = correlation
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(source)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.secondary)

            Image(systemName: correlation >= 0 ? "arrow.right" : "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(badgeColor)

            Text(target)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.secondary)

            Text("(\(String(format: "%.2f", correlation)))")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, SanctuaryLayout.Spacing.sm)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.1))
        )
    }

    private var badgeColor: Color {
        if abs(correlation) >= 0.7 {
            return correlation >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error
        }
        return SanctuaryColors.Semantic.warning
    }
}

// MARK: - Health Insight Card

/// Insight card for discovered health patterns
public struct HealthInsightCard: View {

    let title: String
    let insight: String
    let confidence: Double
    let action: String?

    @State private var isHovered: Bool = false

    public init(
        title: String,
        insight: String,
        confidence: Double,
        action: String? = nil
    ) {
        self.title = title
        self.insight = insight
        self.confidence = confidence
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Title
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.XP.primary)

                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Spacer()

                Text("\(Int(confidence * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Insight text
            Text(insight)
                .font(.system(size: 12))
                .foregroundColor(SanctuaryColors.Text.secondary)
                .lineLimit(3)

            // Action
            if let action = action {
                Button(action: {}) {
                    Text(action)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SanctuaryColors.Dimensions.physiological)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? SanctuaryColors.XP.primary.opacity(0.3) : SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PhysiologicalCorrelationMap_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    PhysiologicalCorrelationMap(
                        correlations: PhysiologicalDimensionData.preview.correlations,
                        predictions: PhysiologicalDimensionData.preview.predictions
                    )

                    HStack(spacing: 8) {
                        CorrelationBadge(source: "HRV", target: "Focus", correlation: 0.72)
                        CorrelationBadge(source: "Sleep", target: "Recovery", correlation: 0.84)
                        CorrelationBadge(source: "Stress", target: "Sleep", correlation: -0.67)
                    }

                    HealthInsightCard(
                        title: "Sleep Pattern Detected",
                        insight: "Your deep sleep increases by 18% when you stop screen time 1 hour before bed.",
                        confidence: 0.85,
                        action: "Set reminder"
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 700)
    }
}
#endif
