// CosmoOS/UI/Sanctuary/Dimensions/Knowledge/KnowledgeStamina.swift
// Knowledge Stamina - Cognitive stamina tracking and factors
// Phase 7: Following SANCTUARY_UI_SPEC_V2.md section 3.5

import SwiftUI

// MARK: - Knowledge Stamina Panel

/// Panel showing knowledge stamina and contributing factors
public struct KnowledgeStaminaPanel: View {

    // MARK: - Properties

    let stamina: Double
    let optimalWindowStart: Int
    let optimalWindowEnd: Int
    let rechargeNeeded: Int
    let factors: [StaminaFactor]

    @State private var isVisible: Bool = false
    @State private var progressAnimated: Bool = false

    // MARK: - Initialization

    public init(
        stamina: Double,
        optimalWindowStart: Int,
        optimalWindowEnd: Int,
        rechargeNeeded: Int,
        factors: [StaminaFactor]
    ) {
        self.stamina = stamina
        self.optimalWindowStart = optimalWindowStart
        self.optimalWindowEnd = optimalWindowEnd
        self.rechargeNeeded = rechargeNeeded
        self.factors = factors
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("Knowledge Stamina")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Main stamina display
            staminaDisplay

            // Optimal window
            optimalWindowSection

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Stamina factors
            staminaFactorsSection
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
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                progressAnimated = true
            }
        }
    }

    // MARK: - Stamina Display

    private var staminaDisplay: some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            // Current label
            Text("CURRENT: \(Int(stamina))%")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(staminaColor)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(SanctuaryColors.Glass.border)
                        .frame(height: 12)

                    // Progress
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [staminaColor, staminaColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: progressAnimated ? geometry.size.width * CGFloat(stamina / 100) : 0,
                            height: 12
                        )

                    // Glow
                    RoundedRectangle(cornerRadius: 6)
                        .fill(staminaColor.opacity(0.4))
                        .blur(radius: 4)
                        .frame(
                            width: progressAnimated ? geometry.size.width * CGFloat(stamina / 100) : 0,
                            height: 12
                        )
                }
            }
            .frame(height: 12)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private var staminaColor: Color {
        if stamina >= 80 { return SanctuaryColors.Semantic.success }
        if stamina >= 50 { return SanctuaryColors.Semantic.info }
        if stamina >= 30 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }

    // MARK: - Optimal Window

    private var optimalWindowSection: some View {
        HStack(spacing: SanctuaryLayout.Spacing.xl) {
            // Optimal window
            VStack(alignment: .leading, spacing: 4) {
                Text("Optimal Window:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("\(optimalWindowStart)pm - \(optimalWindowEnd)pm")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Dimensions.knowledge)
            }

            // Recharge needed
            VStack(alignment: .leading, spacing: 4) {
                Text("Recharge needed:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("~\(rechargeNeeded) min break")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }
        }
    }

    // MARK: - Stamina Factors

    private var staminaFactorsSection: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("STAMINA FACTORS:")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            ForEach(factors) { factor in
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    // Indicator
                    Circle()
                        .fill(factor.isPositive ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)
                        .frame(width: 6, height: 6)

                    // Name
                    Text(factor.name)
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Spacer()

                    // Impact
                    Text(factor.impactString)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(factor.isPositive ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)
                }
            }
        }
    }
}

// MARK: - Stamina Gauge

/// Circular stamina gauge
public struct StaminaGauge: View {

    let stamina: Double

    @State private var progressAnimated: Bool = false

    public init(stamina: Double) {
        self.stamina = stamina
    }

    public var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(SanctuaryColors.Glass.border, lineWidth: 8)

            // Progress circle
            Circle()
                .trim(from: 0, to: progressAnimated ? CGFloat(stamina / 100) : 0)
                .stroke(
                    LinearGradient(
                        colors: [staminaColor, staminaColor.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: 2) {
                Text("\(Int(stamina))")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("%")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
        }
        .frame(width: 80, height: 80)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
                progressAnimated = true
            }
        }
    }

    private var staminaColor: Color {
        if stamina >= 80 { return SanctuaryColors.Semantic.success }
        if stamina >= 50 { return SanctuaryColors.Semantic.info }
        if stamina >= 30 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }
}

// MARK: - Stamina Compact

/// Compact stamina display
public struct StaminaCompact: View {

    let stamina: Double
    let optimalWindow: String

    public init(stamina: Double, optimalWindow: String) {
        self.stamina = stamina
        self.optimalWindow = optimalWindow
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            StaminaGauge(stamina: stamina)

            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                Text("Stamina")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Text(staminaLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(staminaColor)

                Text("Optimal: \(optimalWindow)")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            Spacer()
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

    private var staminaLabel: String {
        if stamina >= 80 { return "Excellent" }
        if stamina >= 50 { return "Good" }
        if stamina >= 30 { return "Low" }
        return "Depleted"
    }

    private var staminaColor: Color {
        if stamina >= 80 { return SanctuaryColors.Semantic.success }
        if stamina >= 50 { return SanctuaryColors.Semantic.info }
        if stamina >= 30 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }
}

// MARK: - Factor Impact Bar

/// Visual bar showing factor impact
public struct FactorImpactBar: View {

    let factors: [StaminaFactor]

    public init(factors: [StaminaFactor]) {
        self.factors = factors
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("Factor Impact")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            GeometryReader { geometry in
                let totalPositive = factors.filter { $0.isPositive }.map { $0.impact }.reduce(0, +)
                let totalNegative = factors.filter { !$0.isPositive }.map { $0.impact }.reduce(0, +)
                let total = totalPositive + totalNegative

                HStack(spacing: 0) {
                    // Positive factors
                    if totalPositive > 0 {
                        Rectangle()
                            .fill(SanctuaryColors.Semantic.success)
                            .frame(width: geometry.size.width * CGFloat(totalPositive / total))
                    }

                    // Negative factors
                    if totalNegative > 0 {
                        Rectangle()
                            .fill(SanctuaryColors.Semantic.error)
                            .frame(width: geometry.size.width * CGFloat(totalNegative / total))
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 8)

            // Labels
            HStack {
                Text("+\(Int(factors.filter { $0.isPositive }.map { $0.impact }.reduce(0, +)))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Semantic.success)

                Spacer()

                Text("-\(Int(factors.filter { !$0.isPositive }.map { $0.impact }.reduce(0, +)))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Semantic.error)
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct KnowledgeStamina_Previews: PreviewProvider {
    static var previews: some View {
        let data = KnowledgeDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    KnowledgeStaminaPanel(
                        stamina: data.knowledgeStamina,
                        optimalWindowStart: data.optimalWindowStart,
                        optimalWindowEnd: data.optimalWindowEnd,
                        rechargeNeeded: data.rechargeNeededMinutes,
                        factors: data.staminaFactors
                    )

                    StaminaCompact(
                        stamina: data.knowledgeStamina,
                        optimalWindow: data.optimalWindowFormatted
                    )

                    FactorImpactBar(factors: data.staminaFactors)
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}
#endif
