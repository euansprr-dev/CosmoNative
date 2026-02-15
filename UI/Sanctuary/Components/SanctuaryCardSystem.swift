// CosmoOS/UI/Sanctuary/Components/SanctuaryCardSystem.swift
// Sanctuary Card System - Shared card components for all dimension views
// Design: Apple Health meets Bloomberg Terminal meets luxury watch face
// Restraint over spectacle - no shadows, precision typography, data breathes

import SwiftUI

// MARK: - Card Tokens

enum SanctuaryCardSize {
    case hero      // Full width, min 160pt height
    case half      // Half width, min 200pt height
    case third     // 1/3 width, fixed 140pt height
    case quarter   // 1/4 width, fixed 100pt height

    var minHeight: CGFloat? {
        switch self {
        case .hero: return 160
        case .half: return 200
        case .third: return 140
        case .quarter: return 100
        }
    }
}

// MARK: - SanctuaryCard

struct SanctuaryCard<Content: View>: View {
    let size: SanctuaryCardSize
    let title: String?
    let accentColor: Color?
    @ViewBuilder let content: () -> Content

    init(
        size: SanctuaryCardSize,
        title: String? = nil,
        accentColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.size = size
        self.title = title
        self.accentColor = accentColor
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SanctuaryColors.Card.titleText)
                    .tracking(0.88)
                    .textCase(.uppercase)
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: size.minHeight)
        .background(SanctuaryColors.Card.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SanctuaryColors.Card.border, lineWidth: 1)
        )
    }
}

// MARK: - Card Grid Layouts

struct SanctuaryCardGrid<Content: View>: View {
    let columns: Int
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        columns: Int = 2,
        spacing: CGFloat = SanctuaryLayout.Spacing.md,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.columns = columns
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: spacing),
                count: columns
            ),
            spacing: spacing
        ) {
            content()
        }
    }
}

// MARK: - Stat Display (reusable metric within cards)

struct SanctuaryStatDisplay: View {
    let label: String
    let value: String
    let unit: String?
    let accentColor: Color

    init(
        label: String,
        value: String,
        unit: String? = nil,
        accentColor: Color = SanctuaryColors.textPrimary
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.accentColor = accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SanctuaryColors.Card.titleText)
                .tracking(0.88)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(SanctuaryTypography.Metric.secondary)
                    .foregroundColor(accentColor)

                if let unit = unit {
                    Text(unit)
                        .font(SanctuaryTypography.metricUnit)
                        .foregroundColor(SanctuaryColors.textTertiary)
                }
            }
        }
    }
}

// MARK: - Hero Stat (large format metric)

struct SanctuaryHeroStat: View {
    let value: String
    let unit: String?
    let label: String
    let accentColor: Color

    init(
        value: String,
        unit: String? = nil,
        label: String,
        accentColor: Color = SanctuaryColors.textPrimary
    ) {
        self.value = value
        self.unit = unit
        self.label = label
        self.accentColor = accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(SanctuaryTypography.Metric.hero)
                    .foregroundColor(accentColor)

                if let unit = unit {
                    Text(unit)
                        .font(SanctuaryTypography.metricUnit)
                        .foregroundColor(SanctuaryColors.textTertiary)
                }
            }

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SanctuaryColors.Card.titleText)
                .tracking(0.88)
                .textCase(.uppercase)
        }
    }
}

// MARK: - Empty State Card

struct SanctuaryEmptyCard: View {
    let size: SanctuaryCardSize
    let title: String
    let message: String
    let icon: String
    let accentColor: Color

    var body: some View {
        SanctuaryCard(size: size, title: title, accentColor: accentColor) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(accentColor.opacity(0.4))

                Text(message)
                    .font(SanctuaryTypography.bodySmall)
                    .foregroundColor(SanctuaryColors.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SanctuaryCardSystem_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 16) {
                SanctuaryCard(size: .hero, title: "HERO CARD", accentColor: SanctuaryColors.cognitive) {
                    SanctuaryHeroStat(
                        value: "87",
                        unit: "%",
                        label: "Focus Score",
                        accentColor: SanctuaryColors.cognitive
                    )
                }

                SanctuaryCardGrid(columns: 2) {
                    SanctuaryCard(size: .half, title: "METRIC A", accentColor: SanctuaryColors.creative) {
                        SanctuaryStatDisplay(
                            label: "Words Today",
                            value: "2,340",
                            accentColor: SanctuaryColors.creative
                        )
                    }

                    SanctuaryCard(size: .half, title: "METRIC B", accentColor: SanctuaryColors.physiological) {
                        SanctuaryStatDisplay(
                            label: "HRV",
                            value: "48",
                            unit: "ms",
                            accentColor: SanctuaryColors.physiological
                        )
                    }
                }

                SanctuaryCardGrid(columns: 3) {
                    ForEach(0..<3) { i in
                        SanctuaryCard(size: .third, title: "THIRD \(i + 1)") {
                            Text("Content")
                                .foregroundColor(.white)
                        }
                    }
                }

                SanctuaryEmptyCard(
                    size: .half,
                    title: "NO DATA",
                    message: "Connect a data source in Settings to see metrics here.",
                    icon: "chart.line.uptrend.xyaxis",
                    accentColor: SanctuaryColors.behavioral
                )
            }
            .padding(24)
        }
        .background(Color(hex: "141422"))
        .preferredColorScheme(.dark)
    }
}
#endif
