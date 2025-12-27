// CosmoOS/UI/Sanctuary/Dimensions/Reflection/ReflectionGrailInsights.swift
// Grail Insights - Breakthrough moments and cross-dimension insights
// Phase 8: Following SANCTUARY_UI_SPEC_V2.md section 3.6

import SwiftUI

// MARK: - Grail Insights Panel

/// Main panel showing breakthrough insights and their journey
public struct GrailInsightsPanel: View {

    // MARK: - Properties

    let insights: [GrailInsight]
    let patterns: [InsightPattern]
    let predictions: [ReflectionPrediction]
    let totalInsights: Int
    let onInsightTap: (GrailInsight) -> Void

    @State private var isVisible: Bool = false
    @State private var selectedInsight: GrailInsight?

    // MARK: - Initialization

    public init(
        insights: [GrailInsight],
        patterns: [InsightPattern],
        predictions: [ReflectionPrediction],
        totalInsights: Int,
        onInsightTap: @escaping (GrailInsight) -> Void
    ) {
        self.insights = insights
        self.patterns = patterns
        self.predictions = predictions
        self.totalInsights = totalInsights
        self.onInsightTap = onInsightTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            headerSection

            // Featured insight
            if let featured = insights.first {
                featuredInsightCard(featured)
            }

            // Recent insights grid
            recentInsightsGrid

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Patterns and predictions row
            HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.xl) {
                patternsSection
                predictionsSection
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
            withAnimation(.easeOut(duration: 0.5)) {
                isVisible = true
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GRAIL INSIGHTS")
                    .font(SanctuaryTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(2)

                Text("Breakthrough Moments")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            Spacer()

            // Total insights badge
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Dimensions.reflection)

                Text("\(totalInsights) discoveries")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }
            .padding(.horizontal, SanctuaryLayout.Spacing.md)
            .padding(.vertical, SanctuaryLayout.Spacing.xs)
            .background(
                Capsule()
                    .fill(SanctuaryColors.Dimensions.reflection.opacity(0.1))
            )
        }
    }

    // MARK: - Featured Insight Card

    private func featuredInsightCard(_ insight: GrailInsight) -> some View {
        Button(action: { onInsightTap(insight) }) {
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
                // Header
                HStack {
                    Text("LATEST BREAKTHROUGH")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Dimensions.reflection)
                        .tracking(1)

                    Spacer()

                    Text(formatDate(insight.discoveredAt))
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }

                // Insight content
                Text("\"\(insight.insight)\"")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .italic()
                    .lineLimit(3)

                // Journey visualization
                insightJourneyMini(insight.journey)

                // Cross-dimension links
                if !insight.dimensionLinks.isEmpty {
                    HStack(spacing: SanctuaryLayout.Spacing.sm) {
                        Text("Connected to:")
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Text.tertiary)

                        ForEach(insight.dimensionLinks) { link in
                            HStack(spacing: 2) {
                                Text(dimensionEmoji(link.dimension))
                                    .font(.system(size: 12))

                                Text(link.dimension.capitalized)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(dimensionColor(link.dimension))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(dimensionColor(link.dimension).opacity(0.1))
                            )
                        }
                    }
                }
            }
            .padding(SanctuaryLayout.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: [
                                SanctuaryColors.Dimensions.reflection.opacity(0.15),
                                SanctuaryColors.Glass.highlight
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                            .stroke(SanctuaryColors.Dimensions.reflection.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func insightJourneyMini(_ journey: [InsightJourneyStep]) -> some View {
        let items = Array(journey.prefix(5))
        let count = items.count
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                let step = items[index]
                HStack(spacing: 4) {
                    Circle()
                        .fill(stepColor(step.type))
                        .frame(width: 8, height: 8)

                    if index < min(4, count - 1) {
                        Rectangle()
                            .fill(SanctuaryColors.Glass.border)
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if journey.count > 5 {
                Text("+\(journey.count - 5)")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .padding(.leading, 4)
            }
        }
    }

    private func stepColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "observation": return SanctuaryColors.Semantic.info
        case "question": return SanctuaryColors.Dimensions.knowledge
        case "connection": return SanctuaryColors.Dimensions.creative
        case "insight": return SanctuaryColors.Dimensions.reflection
        default: return SanctuaryColors.Text.tertiary
        }
    }

    // MARK: - Recent Insights Grid

    private var recentInsightsGrid: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("RECENT DISCOVERIES")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SanctuaryLayout.Spacing.md) {
                    ForEach(Array(insights.dropFirst().prefix(4).enumerated()), id: \.element.id) { index, insight in
                        InsightMiniCard(insight: insight, onTap: { onInsightTap(insight) })
                            .opacity(isVisible ? 1 : 0)
                            .offset(x: isVisible ? 0 : 20)
                            .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.08), value: isVisible)
                    }
                }
            }
        }
    }

    // MARK: - Patterns Section

    private var patternsSection: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("INSIGHT PATTERNS")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            ForEach(Array(patterns.prefix(3))) { pattern in
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Dimensions.reflection)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pattern.description)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(SanctuaryColors.Text.primary)
                            .lineLimit(2)

                        Text("\(Int(pattern.confidence * 100))% confidence")
                            .font(.system(size: 9))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                }
                .padding(SanctuaryLayout.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(SanctuaryColors.Glass.highlight)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Predictions Section

    private var predictionsSection: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("EMERGING INSIGHTS")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            ForEach(Array(predictions.prefix(3))) { prediction in
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Semantic.info)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(prediction.prediction)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(SanctuaryColors.Text.primary)
                            .lineLimit(2)

                        HStack(spacing: 4) {
                            Text("\(Int(prediction.confidence * 100))% likely")
                                .font(.system(size: 9))
                                .foregroundColor(SanctuaryColors.Semantic.info)

                            Text("•")
                                .foregroundColor(SanctuaryColors.Text.tertiary)

                            Text(prediction.timeframe)
                                .font(.system(size: 9))
                                .foregroundColor(SanctuaryColors.Text.tertiary)
                        }
                    }
                }
                .padding(SanctuaryLayout.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(SanctuaryColors.Glass.highlight)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func dimensionEmoji(_ dimension: String) -> String {
        switch dimension.lowercased() {
        case "cognitive": return "🧠"
        case "creative": return "🎨"
        case "physiological": return "💪"
        case "behavioral": return "⚡"
        case "knowledge": return "📚"
        case "reflection": return "🪷"
        default: return "✨"
        }
    }

    private func dimensionColor(_ dimension: String) -> Color {
        switch dimension.lowercased() {
        case "cognitive": return SanctuaryColors.Dimensions.cognitive
        case "creative": return SanctuaryColors.Dimensions.creative
        case "physiological": return SanctuaryColors.Dimensions.physiological
        case "behavioral": return SanctuaryColors.Dimensions.behavioral
        case "knowledge": return SanctuaryColors.Dimensions.knowledge
        case "reflection": return SanctuaryColors.Dimensions.reflection
        default: return SanctuaryColors.Text.secondary
        }
    }
}

// MARK: - Insight Mini Card

/// Compact insight card for grid display
public struct InsightMiniCard: View {

    let insight: GrailInsight
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    public init(insight: GrailInsight, onTap: @escaping () -> Void) {
        self.insight = insight
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                // Sparkle icon
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundColor(SanctuaryColors.Dimensions.reflection)

                // Insight preview
                Text(insight.insight)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Date
                Text(formatDate(insight.discoveredAt))
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
            .padding(SanctuaryLayout.Spacing.md)
            .frame(width: 160, height: 120)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                    .fill(SanctuaryColors.Glass.highlight)
                    .overlay(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                            .stroke(
                                isHovered ? SanctuaryColors.Dimensions.reflection.opacity(0.5) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Insight Detail Panel

/// Full detail view of a grail insight
public struct InsightDetailPanel: View {

    let insight: GrailInsight
    let onDismiss: () -> Void

    public init(insight: GrailInsight, onDismiss: @escaping () -> Void) {
        self.insight = insight
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundColor(SanctuaryColors.Dimensions.reflection)

                    Text("GRAIL INSIGHT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(SanctuaryColors.Dimensions.reflection)
                        .tracking(1)
                }

                Spacer()

                Text(formatDate(insight.discoveredAt))
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Main insight
            Text("\"\(insight.insight)\"")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)
                .italic()

            // Journey section
            journeySection

            // Dimension links
            if !insight.dimensionLinks.isEmpty {
                dimensionLinksSection
            }

            // Source
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("Source: \(insight.sourceType)")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Dimensions.reflection.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var journeySection: some View {
        let journey = insight.journey
        let lastId = journey.last?.id
        return VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("INSIGHT JOURNEY")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            ForEach(journey) { step in
                journeyStepRow(step: step, isLast: step.id == lastId)
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private func journeyStepRow(step: InsightJourneyStep, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.md) {
            VStack(spacing: 0) {
                Circle()
                    .fill(stepColor(step.type))
                    .frame(width: 10, height: 10)

                if !isLast {
                    Rectangle()
                        .fill(SanctuaryColors.Glass.border)
                        .frame(width: 1, height: 30)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.type.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(stepColor(step.type))

                Text(step.content)
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text(formatDate(step.timestamp))
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
        }
    }

    private var dimensionLinksSection: some View {
        let links = insight.dimensionLinks
        return VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("CROSS-DIMENSION CONNECTIONS")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            ForEach(links) { link in
                dimensionLinkRow(link: link)
            }
        }
    }

    private func dimensionLinkRow(link: DimensionLink) -> some View {
        let color = dimensionColor(link.dimension)
        let strengthDots = Int(link.strength * 5)
        return HStack(spacing: SanctuaryLayout.Spacing.md) {
            Text(dimensionEmoji(link.dimension))
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 2) {
                Text(link.dimension.capitalized)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)

                Text(link.connection)
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            Spacer()

            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < strengthDots ? color : SanctuaryColors.Glass.border)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(color.opacity(0.1))
        )
    }

    private func stepColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "observation": return SanctuaryColors.Semantic.info
        case "question": return SanctuaryColors.Dimensions.knowledge
        case "connection": return SanctuaryColors.Dimensions.creative
        case "insight": return SanctuaryColors.Dimensions.reflection
        default: return SanctuaryColors.Text.tertiary
        }
    }

    private func dimensionEmoji(_ dimension: String) -> String {
        switch dimension.lowercased() {
        case "cognitive": return "🧠"
        case "creative": return "🎨"
        case "physiological": return "💪"
        case "behavioral": return "⚡"
        case "knowledge": return "📚"
        case "reflection": return "🪷"
        default: return "✨"
        }
    }

    private func dimensionColor(_ dimension: String) -> Color {
        switch dimension.lowercased() {
        case "cognitive": return SanctuaryColors.Dimensions.cognitive
        case "creative": return SanctuaryColors.Dimensions.creative
        case "physiological": return SanctuaryColors.Dimensions.physiological
        case "behavioral": return SanctuaryColors.Dimensions.behavioral
        case "knowledge": return SanctuaryColors.Dimensions.knowledge
        case "reflection": return SanctuaryColors.Dimensions.reflection
        default: return SanctuaryColors.Text.secondary
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Grail Insights Compact

/// Compact insights summary
public struct GrailInsightsCompact: View {

    let recentInsight: GrailInsight?
    let totalCount: Int
    let onExpand: () -> Void

    public init(recentInsight: GrailInsight?, totalCount: Int, onExpand: @escaping () -> Void) {
        self.recentInsight = recentInsight
        self.totalCount = totalCount
        self.onExpand = onExpand
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundColor(SanctuaryColors.Dimensions.reflection)

            VStack(alignment: .leading, spacing: 2) {
                Text("GRAIL INSIGHTS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                if let insight = recentInsight {
                    Text(insight.insight)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .lineLimit(1)
                } else {
                    Text("No insights yet")
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            Spacer()

            Text("\(totalCount)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Dimensions.reflection)

            Button(action: onExpand) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Dimensions.reflection)
            }
            .buttonStyle(PlainButtonStyle())
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
}

// MARK: - Preview

#if DEBUG
struct ReflectionGrailInsights_Previews: PreviewProvider {
    static var previews: some View {
        let data = ReflectionDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    GrailInsightsPanel(
                        insights: data.grailInsights,
                        patterns: data.insightPatterns,
                        predictions: data.predictions,
                        totalInsights: data.totalGrailInsights,
                        onInsightTap: { _ in }
                    )

                    if let insight = data.grailInsights.first {
                        InsightDetailPanel(
                            insight: insight,
                            onDismiss: {}
                        )
                        .frame(maxWidth: 500)
                    }

                    GrailInsightsCompact(
                        recentInsight: data.grailInsights.first,
                        totalCount: data.totalGrailInsights,
                        onExpand: {}
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 1000)
    }
}
#endif
