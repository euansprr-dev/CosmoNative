// CosmoOS/UI/Sanctuary/Dimensions/Physiological/PhysiologicalSleepAnalysis.swift
// Sleep Analysis - Sleep stages, efficiency, and scoring
// Phase 5: Following SANCTUARY_UI_SPEC_V2.md section 3.3

import SwiftUI

// MARK: - Sleep Analysis Panel

/// Complete sleep analysis visualization
public struct PhysiologicalSleepAnalysis: View {

    // MARK: - Properties

    let sleep: SleepSession
    let sleepDebt: TimeInterval
    let sleepTrend: [Int]

    @State private var isVisible: Bool = false
    @State private var stagesAnimated: Bool = false

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("Sleep Analysis (Last Night)")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Main content
            HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.xl) {
                // Time in bed
                timeInBedCard

                // Sleep stages bar
                sleepStagesBar
                    .frame(maxWidth: .infinity)

                // Efficiency score
                efficiencyCard
            }

            // Bottom stats
            HStack(spacing: SanctuaryLayout.Spacing.lg) {
                // Sleep score
                sleepScoreIndicator

                // Stage percentages
                stagePercentages

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
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.4)) {
                stagesAnimated = true
            }
        }
    }

    // MARK: - Time in Bed Card

    private var timeInBedCard: some View {
        VStack(alignment: .center, spacing: SanctuaryLayout.Spacing.sm) {
            Text(sleep.formattedBedTime)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)

            Image(systemName: "arrow.down")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(sleep.formattedWakeTime)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)
                .padding(.vertical, SanctuaryLayout.Spacing.xs)

            Text(sleep.formattedDuration)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("Total")
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .frame(width: 80)
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    // MARK: - Sleep Stages Bar

    private var sleepStagesBar: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("Sleep Stages")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            // Stages bar
            GeometryReader { geometry in
                let width = geometry.size.width
                let totalDuration = sleep.totalDuration

                HStack(spacing: 2) {
                    // Deep sleep
                    stageSegment(
                        stage: .deep,
                        duration: sleep.deepSleep,
                        totalDuration: totalDuration,
                        width: width
                    )

                    // Core sleep
                    stageSegment(
                        stage: .core,
                        duration: sleep.coreSleep,
                        totalDuration: totalDuration,
                        width: width
                    )

                    // REM sleep
                    stageSegment(
                        stage: .rem,
                        duration: sleep.remSleep,
                        totalDuration: totalDuration,
                        width: width
                    )
                }
            }
            .frame(height: 24)

            // Stage labels
            HStack(spacing: 0) {
                stageLabelView(.deep, duration: sleep.deepSleep)
                Spacer()
                stageLabelView(.core, duration: sleep.coreSleep)
                Spacer()
                stageLabelView(.rem, duration: sleep.remSleep)
            }
        }
    }

    private func stageSegment(stage: SleepStageType, duration: TimeInterval, totalDuration: TimeInterval, width: CGFloat) -> some View {
        let proportion = totalDuration > 0 ? duration / totalDuration : 0
        let segmentWidth = width * CGFloat(proportion) * (stagesAnimated ? 1 : 0)

        return RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: stage.color))
            .frame(width: max(0, segmentWidth - 2))
            .animation(.easeOut(duration: 0.6), value: stagesAnimated)
    }

    private func stageLabelView(_ stage: SleepStageType, duration: TimeInterval) -> some View {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        return VStack(spacing: 2) {
            Text(stage.displayName.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(hex: stage.color))

            Text("\(hours)h \(minutes)m")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.secondary)
        }
    }

    // MARK: - Efficiency Card

    private var efficiencyCard: some View {
        VStack(alignment: .center, spacing: SanctuaryLayout.Spacing.sm) {
            Text("\(Int(sleep.efficiency))%")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(efficiencyColor)

            // Progress ring
            ZStack {
                Circle()
                    .stroke(SanctuaryColors.Glass.highlight, lineWidth: 4)

                Circle()
                    .trim(from: 0, to: stagesAnimated ? sleep.efficiency / 100 : 0)
                    .stroke(
                        efficiencyColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: stagesAnimated)
            }
            .frame(width: 50, height: 50)

            Text(sleep.scoreRating)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.secondary)
        }
        .frame(width: 90)
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private var efficiencyColor: Color {
        if sleep.efficiency >= 90 { return SanctuaryColors.Semantic.success }
        if sleep.efficiency >= 80 { return SanctuaryColors.Semantic.info }
        if sleep.efficiency >= 70 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }

    // MARK: - Sleep Score Indicator

    private var sleepScoreIndicator: some View {
        HStack(spacing: SanctuaryLayout.Spacing.sm) {
            Text("SLEEP SCORE:")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text("\(sleep.score)/100")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)

            // Star rating
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < sleep.score / 20 ? "circle.fill" : "circle")
                        .font(.system(size: 6))
                        .foregroundColor(i < sleep.score / 20 ? SanctuaryColors.Dimensions.physiological : SanctuaryColors.Text.tertiary)
                }
            }
        }
    }

    // MARK: - Stage Percentages

    private var stagePercentages: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            stagePercentage(
                label: "Deep",
                value: sleep.deepSleepPercent,
                trend: true,
                color: Color(hex: SleepStageType.deep.color)
            )

            stagePercentage(
                label: "REM",
                value: sleep.remSleepPercent,
                trend: false,
                color: Color(hex: SleepStageType.rem.color)
            )

            HStack(spacing: 4) {
                Text("Disturbances:")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("\(sleep.disturbanceCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }
        }
    }

    private func stagePercentage(label: String, value: Double, trend: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text("\(Int(value))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)

            Image(systemName: trend ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(trend ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)
        }
    }
}

// MARK: - Sleep Trend Chart

/// 7-day sleep score trend
public struct SleepTrendChart: View {

    let scores: [Int]

    @State private var isVisible: Bool = false
    @State private var barsAnimated: Bool = false

    public init(scores: [Int]) {
        self.scores = scores
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("Sleep Trend (7 Days)")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Bar chart
            HStack(alignment: .bottom, spacing: SanctuaryLayout.Spacing.sm) {
                ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                    sleepBar(score: score, index: index)
                }
            }
            .frame(height: 80)

            // Day labels
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 9))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .frame(maxWidth: .infinity)
                }
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
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.5)) {
                barsAnimated = true
            }
        }
    }

    private func sleepBar(score: Int, index: Int) -> some View {
        let height = CGFloat(score) / 100 * 80
        let isToday = index == scores.count - 1

        return VStack(spacing: 4) {
            // Score label
            Text("\(score)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.secondary)
                .opacity(barsAnimated ? 1 : 0)

            // Bar
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [barColor(for: score), barColor(for: score).opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: barsAnimated ? height : 0)
                .overlay(
                    isToday ?
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(SanctuaryColors.Text.primary, lineWidth: 1)
                        : nil
                )
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.05), value: barsAnimated)
    }

    private func barColor(for score: Int) -> Color {
        if score >= 85 { return SanctuaryColors.Semantic.success }
        if score >= 75 { return SanctuaryColors.Semantic.info }
        if score >= 65 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }
}

// MARK: - Sleep Debt Indicator

/// Shows accumulated sleep debt
public struct SleepDebtIndicator: View {

    let debt: TimeInterval

    public init(debt: TimeInterval) {
        self.debt = debt
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Icon
            Image(systemName: debtIcon)
                .font(.system(size: 16))
                .foregroundColor(debtColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sleep Debt")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Text(formattedDebt)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(debtColor)
            }

            Spacer()

            // Status
            Text(debtStatus)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(debtColor)
                .padding(.horizontal, SanctuaryLayout.Spacing.sm)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(debtColor.opacity(0.15))
                )
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(debtColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var formattedDebt: String {
        let hours = Int(debt) / 3600
        let minutes = (Int(debt) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var debtColor: Color {
        let hours = debt / 3600
        if hours < 1 { return SanctuaryColors.Semantic.success }
        if hours < 3 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }

    private var debtStatus: String {
        let hours = debt / 3600
        if hours < 1 { return "Minimal" }
        if hours < 2 { return "Low" }
        if hours < 4 { return "Moderate" }
        return "High"
    }

    private var debtIcon: String {
        let hours = debt / 3600
        if hours < 1 { return "checkmark.circle.fill" }
        if hours < 3 { return "exclamationmark.triangle.fill" }
        return "xmark.circle.fill"
    }
}

// MARK: - Compact Sleep Card

/// Compact sleep summary for embedding
public struct SleepCardCompact: View {

    let sleep: SleepSession

    public init(sleep: SleepSession) {
        self.sleep = sleep
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Sleep icon
            Image(systemName: "moon.fill")
                .font(.system(size: 16))
                .foregroundColor(SanctuaryColors.Dimensions.physiological)

            // Duration
            VStack(alignment: .leading, spacing: 2) {
                Text(sleep.formattedDuration)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("\(sleep.formattedBedTime) → \(sleep.formattedWakeTime)")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Spacer()

            // Score
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(sleep.score)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor)

                Text(sleep.scoreRating)
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
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

    private var scoreColor: Color {
        if sleep.score >= 85 { return SanctuaryColors.Semantic.success }
        if sleep.score >= 70 { return SanctuaryColors.Semantic.info }
        if sleep.score >= 55 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }
}

// MARK: - Preview

#if DEBUG
struct PhysiologicalSleepAnalysis_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    PhysiologicalSleepAnalysis(
                        sleep: PhysiologicalDimensionData.preview.lastNightSleep,
                        sleepDebt: 45 * 60,
                        sleepTrend: [82, 78, 85, 91, 76, 88, 87]
                    )

                    SleepTrendChart(scores: [82, 78, 85, 91, 76, 88, 87])

                    SleepDebtIndicator(debt: 45 * 60)

                    SleepCardCompact(sleep: PhysiologicalDimensionData.preview.lastNightSleep)
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
}
#endif
