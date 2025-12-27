// CosmoOS/UI/Sanctuary/SanctuaryInsightStream.swift
// Insight Stream - Horizontal scrolling carousel of typed insight cards
// Phase 2: Following SANCTUARY_UI_SPEC_V2.md section 2.5

import SwiftUI

// MARK: - Insight Card Type

/// Types of insight cards displayed in the stream
public enum InsightCardType: String, CaseIterable {
    case prediction
    case correlation
    case achievement
    case warning
    case insight

    var icon: String {
        switch self {
        case .prediction: return "sparkles"
        case .correlation: return "arrow.left.arrow.right"
        case .achievement: return "star.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .insight: return "lightbulb.fill"
        }
    }

    var color: Color {
        switch self {
        case .prediction: return SanctuaryColors.Dimensions.creative  // Amber
        case .correlation: return SanctuaryColors.Dimensions.behavioral  // Blue
        case .achievement: return SanctuaryColors.Semantic.success  // Green
        case .warning: return SanctuaryColors.Semantic.error  // Red
        case .insight: return SanctuaryColors.Dimensions.knowledge  // Purple
        }
    }

    var label: String {
        rawValue.uppercased()
    }
}

// MARK: - Insight Card Model

/// Model for insight cards in the stream
public struct InsightCardModel: Identifiable {
    public let id: String
    public let type: InsightCardType
    public let title: String
    public let detail: String?
    public let xpReward: Int?
    public let confidence: Double?
    public let actionLabel: String?

    public init(
        id: String = UUID().uuidString,
        type: InsightCardType,
        title: String,
        detail: String? = nil,
        xpReward: Int? = nil,
        confidence: Double? = nil,
        actionLabel: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.xpReward = xpReward
        self.confidence = confidence
        self.actionLabel = actionLabel
    }

    /// Convert from CorrelationInsight
    public static func from(_ insight: CorrelationInsight) -> InsightCardModel {
        // Use human description, or format metric names as fallback
        let title = insight.humanDescription.isEmpty
            ? formatCorrelation(source: insight.sourceMetric, target: insight.targetMetric)
            : insight.humanDescription

        // Show actionable recommendation instead of raw statistical data
        let detail = insight.actionableAdvice

        return InsightCardModel(
            id: insight.uuid,
            type: .correlation,
            title: title,
            detail: detail,
            confidence: insight.statisticalConfidence,
            actionLabel: insight.strength.rawValue.capitalized  // e.g., "Strong"
        )
    }

    /// Format variable names into human-readable correlation title
    private static func formatCorrelation(source: String, target: String) -> String {
        let formatted = { (name: String) -> String in
            name.replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
        return "\(formatted(source)) → \(formatted(target))"
    }

    /// Convert from LivingInsight (with lifecycle awareness)
    public static func fromLiving(_ insight: LivingInsight) -> InsightCardModel {
        // Map insight type to card type
        let cardType: InsightCardType = {
            switch insight.type {
            case .correlation: return .correlation
            case .prediction: return .prediction
            case .warning: return .warning
            case .achievement: return .achievement
            case .pattern, .recommendation: return .insight
            }
        }()

        // Use action or mechanism as detail (human-readable recommendation)
        // NOT raw statistical data like "r = 0.73 • effect: 0.15"
        let detail: String? = insight.action ?? insight.mechanism

        // Add lifecycle badge to actionLabel instead of detail
        let actionLabel: String = {
            switch insight.lifecycleState {
            case .fresh: return "NEW"
            case .established: return "Proven"
            case .stale: return "May be outdated"
            default: return ""
            }
        }()

        return InsightCardModel(
            id: insight.id,
            type: cardType,
            title: insight.title.isEmpty ? insight.description : insight.title,
            detail: detail,
            confidence: insight.confidenceScore,
            actionLabel: actionLabel
        )
    }
}

// MARK: - Sanctuary Insight Stream

/// Horizontal scrolling carousel of insight cards
public struct SanctuaryInsightStream: View {

    // MARK: - Properties

    let insights: [InsightCardModel]
    let onCardTap: ((InsightCardModel) -> Void)?

    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isVisible: Bool = false

    // MARK: - Layout Constants

    private enum Layout {
        static let cardWidth: CGFloat = 320
        static let cardHeight: CGFloat = 100  // Increased from 88 to fit content better
        static let cardGap: CGFloat = 16
        static let peekAmount: CGFloat = 24
        static let bottomPadding: CGFloat = 48
    }

    // MARK: - Initialization

    public init(
        insights: [InsightCardModel],
        onCardTap: ((InsightCardModel) -> Void)? = nil
    ) {
        self.insights = insights
        self.onCardTap = onCardTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Section header (left-aligned)
            Text("INSIGHT STREAM")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)
                .padding(.horizontal, SanctuaryLayout.Spacing.xxl)

            // Page indicator dots - centered, above the cards
            if insights.count > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<min(insights.count, 5), id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }

                    if insights.count > 5 {
                        Text("+\(insights.count - 5)")
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)  // Centers the dots
            }

            // Carousel
            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                let cardOffset = (totalWidth - Layout.cardWidth) / 2

                HStack(spacing: Layout.cardGap) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        InsightStreamCard(
                            model: insight,
                            isActive: index == currentIndex,
                            onTap: { onCardTap?(insight) }
                        )
                        .frame(width: Layout.cardWidth, height: Layout.cardHeight)
                    }
                }
                .offset(x: cardOffset - CGFloat(currentIndex) * (Layout.cardWidth + Layout.cardGap) + dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 50
                            let velocity = value.predictedEndTranslation.width - value.translation.width

                            withAnimation(SanctuarySprings.snappy) {
                                if value.translation.width < -threshold || velocity < -100 {
                                    currentIndex = min(currentIndex + 1, insights.count - 1)
                                } else if value.translation.width > threshold || velocity > 100 {
                                    currentIndex = max(currentIndex - 1, 0)
                                }
                                dragOffset = 0
                            }
                        }
                )
                .animation(SanctuarySprings.snappy, value: currentIndex)
            }
            .frame(height: Layout.cardHeight)

            // Scroll hint arrows
            HStack {
                if currentIndex > 0 {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }

                Spacer()

                // Progress bar
                ProgressView(value: Double(currentIndex + 1), total: Double(max(insights.count, 1)))
                    .progressViewStyle(InsightStreamProgressStyle())
                    .frame(maxWidth: 200)

                Spacer()

                if currentIndex < insights.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }
            .padding(.horizontal, SanctuaryLayout.Spacing.xxl)
        }
        .padding(.bottom, Layout.bottomPadding)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: SanctuaryDurations.medium).delay(0.3)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Insight Stream Card

/// Individual card in the insight stream
struct InsightStreamCard: View {

    let model: InsightCardModel
    let isActive: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            // Type badge
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.xs) {
                    Image(systemName: model.type.icon)
                        .font(.system(size: 10))
                    Text(model.type.label)
                        .font(SanctuaryTypography.label)
                }
                .foregroundColor(model.type.color)

                Spacer()

                // Confidence or XP reward
                if let confidence = model.confidence {
                    Text("Confidence: \(Int(confidence * 100))%")
                        .font(SanctuaryTypography.label)
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            // Title
            Text(model.title)
                .font(SanctuaryTypography.body)
                .foregroundColor(SanctuaryColors.Text.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Separator and footer
            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Footer with detail/action
            HStack {
                if let detail = model.detail {
                    Text(detail)
                        .font(SanctuaryTypography.label)
                        .foregroundColor(SanctuaryColors.Text.secondary)
                        .lineLimit(1)  // Prevent overflow
                }

                Spacer()

                if let xp = model.xpReward {
                    Text("+\(xp) XP")
                        .font(SanctuaryTypography.metric)
                        .foregroundColor(SanctuaryColors.XP.primary)
                }

                if let action = model.actionLabel, !action.isEmpty {
                    Text(action)
                        .font(SanctuaryTypography.label)
                        .foregroundColor(model.type.color)
                        .lineLimit(1)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(
                            isActive ? model.type.color.opacity(0.5) : SanctuaryColors.Glass.border,
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        )
        .scaleEffect(isActive ? 1.0 : 0.95)
        .opacity(isActive ? 1.0 : 0.7)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(
            color: isActive ? model.type.color.opacity(0.2) : Color.clear,
            radius: 16, x: 0, y: 8
        )
        .animation(SanctuarySprings.hover, value: isHovered)
        .animation(SanctuarySprings.snappy, value: isActive)
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Progress Style

/// Custom progress bar style for the insight stream
struct InsightStreamProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(SanctuaryColors.Glass.border)
                    .frame(height: 4)

                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(SanctuaryColors.Text.tertiary)
                    .frame(
                        width: geometry.size.width * CGFloat(configuration.fractionCompleted ?? 0),
                        height: 4
                    )
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Preview Helpers

extension SanctuaryInsightStream {
    /// Create from CorrelationInsights
    public static func from(insights: [CorrelationInsight]) -> SanctuaryInsightStream {
        SanctuaryInsightStream(
            insights: insights.map { InsightCardModel.from($0) }
        )
    }
}

// MARK: - Preview

#if DEBUG
struct SanctuaryInsightStream_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                Spacer()

                SanctuaryInsightStream(
                    insights: [
                        InsightCardModel(
                            type: .prediction,
                            title: "Sleep before 11pm to boost Cognitive +13% tomorrow",
                            xpReward: 340,
                            confidence: 0.87
                        ),
                        InsightCardModel(
                            type: .correlation,
                            title: "HRV ↔ Deep Work",
                            detail: "r = 0.73 (Strong)",
                            actionLabel: "Tap to explore →"
                        ),
                        InsightCardModel(
                            type: .achievement,
                            title: "7-Day Deep Work Streak Unlocked!",
                            xpReward: 500,
                            actionLabel: "New Badge"
                        ),
                        InsightCardModel(
                            type: .warning,
                            title: "Sleep consistency declining for 3 days",
                            detail: "Physiological -8%"
                        ),
                        InsightCardModel(
                            type: .insight,
                            title: "Your best writing hours are 9-11am",
                            confidence: 0.92
                        )
                    ]
                ) { card in
                    print("Tapped: \(card.title)")
                }
            }
        }
    }
}
#endif
