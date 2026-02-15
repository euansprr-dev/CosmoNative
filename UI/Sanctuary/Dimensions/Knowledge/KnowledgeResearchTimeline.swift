// CosmoOS/UI/Sanctuary/Dimensions/Knowledge/KnowledgeResearchTimeline.swift
// Research Timeline - Research activity timeline and weekly breakdown
// Phase 7: Following SANCTUARY_UI_SPEC_V2.md section 3.5

import SwiftUI

// MARK: - Research Timeline Panel

/// Panel showing research activity timeline
public struct KnowledgeResearchTimeline: View {

    // MARK: - Properties

    let timeline: [HourlyResearch]
    let peakHour: Int
    let peakMinutes: Int
    let totalToday: Int
    let weeklyData: [DailyResearch]
    let weeklyTotal: Int

    @State private var isVisible: Bool = false

    // MARK: - Initialization

    public init(
        timeline: [HourlyResearch],
        peakHour: Int,
        peakMinutes: Int,
        totalToday: Int,
        weeklyData: [DailyResearch],
        weeklyTotal: Int
    ) {
        self.timeline = timeline
        self.peakHour = peakHour
        self.peakMinutes = peakMinutes
        self.totalToday = totalToday
        self.weeklyData = weeklyData
        self.weeklyTotal = weeklyTotal
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("Research Timeline")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Hour heatmap
            hourlyHeatmap

            // Peak info
            peakInfo

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Weekly breakdown
            weeklyBreakdown
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
        }
    }

    // MARK: - Hourly Heatmap

    private var hourlyHeatmap: some View {
        VStack(spacing: SanctuaryLayout.Spacing.sm) {
            // Hour bars
            GeometryReader { geometry in
                let barWidth = (geometry.size.width - CGFloat(timeline.count - 1) * 2) / CGFloat(timeline.count)

                HStack(spacing: 2) {
                    ForEach(timeline) { hour in
                        VStack(spacing: 0) {
                            Spacer()

                            RoundedRectangle(cornerRadius: 2)
                                .fill(barColor(for: hour))
                                .frame(
                                    width: barWidth,
                                    height: max(4, CGFloat(hour.intensity) * 50)
                                )
                                .opacity(isVisible ? 1 : 0)
                                .animation(.easeOut(duration: 0.3).delay(Double(hour.hour) * 0.02), value: isVisible)
                        }
                    }
                }
            }
            .frame(height: 60)

            // Hour labels
            HStack {
                ForEach([0, 6, 12, 18, 23], id: \.self) { hour in
                    Text("\(hour == 0 ? "12am" : hour == 12 ? "12pm" : hour < 12 ? "\(hour)am" : "\(hour - 12)pm")")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    if hour != 23 { Spacer() }
                }
            }
        }
    }

    private func barColor(for hour: HourlyResearch) -> Color {
        if hour.isActive {
            return SanctuaryColors.Dimensions.knowledge
        }
        if hour.intensity > 0.5 {
            return SanctuaryColors.Dimensions.knowledge.opacity(0.7)
        }
        if hour.intensity > 0 {
            return SanctuaryColors.Dimensions.knowledge.opacity(0.4)
        }
        return SanctuaryColors.Glass.border
    }

    // MARK: - Peak Info

    private var peakInfo: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Peak: \(peakHour)pm-\(peakHour + 2)pm (\(peakMinutes) min focused)")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.secondary)

                Text("Total Today: \(formattedTime(totalToday))")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            Spacer()

            // Average comparison
            let avgMinutes = weeklyTotal / max(1, weeklyData.count)
            let diff = totalToday - avgMinutes
            let diffPercent = avgMinutes > 0 ? Int((Double(diff) / Double(avgMinutes)) * 100) : 0

            HStack(spacing: 4) {
                Text("vs Avg:")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("\(diff >= 0 ? "+" : "")\(diffPercent)%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(diff >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)
            }
        }
    }

    // MARK: - Weekly Breakdown

    private var weeklyBreakdown: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("THIS WEEK:")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            HStack(spacing: SanctuaryLayout.Spacing.md) {
                ForEach(weeklyData) { day in
                    VStack(spacing: 4) {
                        Text(day.dayOfWeek)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(SanctuaryColors.Text.tertiary)

                        Text(day.formattedTime)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(SanctuaryColors.Text.primary)
                    }
                    .frame(maxWidth: .infinity)

                    if day.id != weeklyData.last?.id {
                        Text("|")
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Glass.border)
                    }
                }
            }

            HStack {
                Spacer()

                Text("Total: \(formattedTime(weeklyTotal))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SanctuaryColors.Dimensions.knowledge)
            }
        }
    }

    private func formattedTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }
}

// MARK: - Research Timeline Compact

/// Compact timeline for embedding
public struct ResearchTimelineCompact: View {

    let timeline: [HourlyResearch]
    let totalToday: Int

    public init(timeline: [HourlyResearch], totalToday: Int) {
        self.timeline = timeline
        self.totalToday = totalToday
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            HStack {
                Text("Research")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Text(formattedTime(totalToday))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Dimensions.knowledge)
            }

            // Mini heatmap
            HStack(spacing: 1) {
                ForEach(timeline.filter { $0.hour >= 6 && $0.hour <= 22 }) { hour in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(hour.intensity > 0 ? SanctuaryColors.Dimensions.knowledge.opacity(hour.intensity) : SanctuaryColors.Glass.border)
                        .frame(height: 20)
                }
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

    private func formattedTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }
}

// MARK: - Weekly Research Chart

/// Weekly research bar chart
public struct WeeklyResearchChart: View {

    let weeklyData: [DailyResearch]

    @State private var isVisible: Bool = false

    public init(weeklyData: [DailyResearch]) {
        self.weeklyData = weeklyData
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("Weekly Research")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            GeometryReader { geometry in
                let maxMinutes = weeklyData.map { $0.totalMinutes }.max() ?? 1
                let barWidth = (geometry.size.width - CGFloat(weeklyData.count - 1) * 8) / CGFloat(weeklyData.count)

                HStack(spacing: 8) {
                    ForEach(Array(weeklyData.enumerated()), id: \.element.id) { index, day in
                        VStack(spacing: 4) {
                            Spacer()

                            RoundedRectangle(cornerRadius: 4)
                                .fill(SanctuaryColors.Dimensions.knowledge)
                                .frame(
                                    width: barWidth,
                                    height: isVisible ? CGFloat(day.totalMinutes) / CGFloat(maxMinutes) * (geometry.size.height - 30) : 0
                                )
                                .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.05), value: isVisible)

                            Text(day.dayOfWeek)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(SanctuaryColors.Text.tertiary)
                        }
                    }
                }
            }
            .frame(height: 100)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct KnowledgeResearchTimeline_Previews: PreviewProvider {
    static var previews: some View {
        let data = KnowledgeDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    KnowledgeResearchTimeline(
                        timeline: data.researchTimeline,
                        peakHour: data.peakResearchHour,
                        peakMinutes: data.peakResearchMinutes,
                        totalToday: data.totalResearchToday,
                        weeklyData: data.weeklyResearchData,
                        weeklyTotal: data.weeklyTotalMinutes
                    )

                    ResearchTimelineCompact(
                        timeline: data.researchTimeline,
                        totalToday: data.totalResearchToday
                    )

                    WeeklyResearchChart(weeklyData: data.weeklyResearchData)
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
}
#endif
