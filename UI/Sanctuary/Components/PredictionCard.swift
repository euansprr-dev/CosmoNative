// CosmoOS/UI/Sanctuary/Components/PredictionCard.swift
// Prediction Card - AI-powered insight card for Sanctuary dimensions
// "If you [action], your [metric] is predicted to [outcome]"
// Earned luminance - predictions only appear when data supports them

import SwiftUI

// MARK: - Prediction Card

struct PredictionCard: View {
    let prediction: String
    let confidence: Double
    let accentColor: Color
    let actions: [(label: String, action: () -> Void)]

    var body: some View {
        SanctuaryCard(size: .half, title: "AI PREDICTION", accentColor: accentColor) {
            VStack(alignment: .leading, spacing: 12) {
                // Prediction text
                Text(prediction)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(3)

                HStack {
                    // Confidence badge
                    confidenceBadge

                    Spacer()

                    // Action buttons
                    actionButtons
                }
            }
        }
    }

    // MARK: - Confidence Badge

    private var confidenceBadge: some View {
        HStack(spacing: 6) {
            // Confidence diamond icon
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundColor(confidenceColor)

            Text("\(Int(confidence * 100))% confidence")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(confidenceColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(confidenceColor.opacity(0.1))
        )
    }

    private var confidenceColor: Color {
        switch confidence {
        case 0.8...1.0: return SanctuaryColors.live
        case 0.6..<0.8: return accentColor
        case 0.4..<0.6: return SanctuaryColors.warning
        default: return SanctuaryColors.textMuted
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            ForEach(actions.indices, id: \.self) { i in
                actionButton(label: actions[i].label, action: actions[i].action)
            }
        }
    }

    private func actionButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(accentColor.opacity(0.12))
                        .overlay(
                            Capsule()
                                .strokeBorder(accentColor.opacity(0.2), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Correlation Insight Card

struct CorrelationInsightCard: View {
    let sourceMetric: String
    let targetMetric: String
    let description: String
    let coefficient: Double
    let accentColor: Color

    var body: some View {
        SanctuaryCard(size: .half, title: "CORRELATION", accentColor: accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                // Correlation description
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
                    .lineSpacing(2)

                HStack(spacing: 12) {
                    // Source metric pill
                    metricPill(sourceMetric, icon: "arrow.right")

                    // Arrow
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.textMuted)

                    // Target metric pill
                    metricPill(targetMetric, icon: "target")

                    Spacer()

                    // Coefficient badge
                    coefficientBadge
                }
            }
        }
    }

    private func metricPill(_ metric: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))

            Text(metric)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(SanctuaryColors.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    private var coefficientBadge: some View {
        let isPositive = coefficient > 0
        let color = isPositive ? SanctuaryColors.live : SanctuaryColors.danger

        return Text(String(format: "%+.2f", coefficient))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#if DEBUG
struct PredictionCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            PredictionCard(
                prediction: "If you maintain 7+ hours of sleep for 3 more days, your focus score is predicted to increase by 12%.",
                confidence: 0.82,
                accentColor: SanctuaryColors.cognitive,
                actions: [
                    (label: "Set Reminder", action: {}),
                    (label: "Dismiss", action: {})
                ]
            )

            CorrelationInsightCard(
                sourceMetric: "Sleep Quality",
                targetMetric: "Focus Score",
                description: "Your sleep quality strongly predicts next-day focus performance.",
                coefficient: 0.78,
                accentColor: SanctuaryColors.physiological
            )
        }
        .padding(24)
        .background(Color(hex: "141422"))
        .preferredColorScheme(.dark)
    }
}
#endif
