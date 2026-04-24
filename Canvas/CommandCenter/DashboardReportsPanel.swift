// Canvas/CommandCenter/DashboardReportsPanel.swift
// Analytics panel: Week / Month / Habits tabs with navigation
// March 2026

import SwiftUI

struct DashboardReportsPanel: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State private var chartAnimated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            reportTabBar
            reportNavigator

            switch viewModel.selectedReportTab {
            case .week:
                weekContent
            case .month:
                monthContent
            case .habits:
                habitsContent
            }
        }
        .task { await loadCurrentTab() }
        .onChange(of: viewModel.selectedReportTab) { _, _ in
            chartAnimated = false
            Task { await loadCurrentTab() }
        }
    }

    // MARK: - Tab Bar

    private var reportTabBar: some View {
        HStack(spacing: 0) {
            ForEach(ReportTab.allCases, id: \.self) { tab in
                reportTabButton(tab)
            }
        }
    }

    private func reportTabButton(_ tab: ReportTab) -> some View {
        let isActive = viewModel.selectedReportTab == tab
        return Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.selectedReportTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Text(tab.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isActive ? DS.accent : DS.inkFaded)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)

                Rectangle()
                    .fill(isActive ? DS.accent : Color.clear)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: isActive ? 0.6 : 0, anchor: .center)
                    .clipShape(.rect(cornerRadius: 1))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigator (prev/next arrows + date label)

    private var reportNavigator: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.navigateReport(direction: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.inkFaded)
                    .frame(width: 24, height: 24)
                    .background(DS.vellum, in: Circle())
                    .overlay(Circle().stroke(DS.sepiaBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Text(viewModel.reportDateLabel)
                .font(DS.callout)
                .foregroundStyle(DS.inkFaded)
                .frame(maxWidth: .infinity)

            Button {
                Task { await viewModel.navigateReport(direction: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isAtPresent ? DS.inkFaded.opacity(0.3) : DS.inkFaded)
                    .frame(width: 24, height: 24)
                    .background(DS.vellum, in: Circle())
                    .overlay(Circle().stroke(DS.sepiaBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(isAtPresent)
        }
    }

    private var isAtPresent: Bool {
        switch viewModel.selectedReportTab {
        case .week: return viewModel.reportWeekOffset >= 0
        case .month: return viewModel.reportMonthOffset >= 0
        case .habits: return viewModel.reportWeekOffset >= 0
        }
    }

    // MARK: - Week Content

    @ViewBuilder
    private var weekContent: some View {
        if let report = viewModel.weeklyReportData {
            weeklyBarChart(report)
            statsGrid(report)
            intentBreakdown(report)
        } else {
            emptyState
        }
    }

    // MARK: - Month Content

    @ViewBuilder
    private var monthContent: some View {
        if let report = viewModel.weeklyReportData {
            monthlyHeatmap(report)
            statsGrid(report)
            intentBreakdown(report)
        } else {
            emptyState
        }
    }

    // MARK: - Habits Content

    @ViewBuilder
    private var habitsContent: some View {
        if let habitReport = viewModel.habitReportData, !habitReport.habitEntries.isEmpty {
            habitCompletionList(habitReport)
            overallConsistency(habitReport)
            habitInsights(habitReport)
        } else {
            emptyState
        }
    }

    // MARK: - Weekly Bar Chart

    @ViewBuilder
    private func weeklyBarChart(_ report: ReportData) -> some View {
        let maxMinutes = max(report.days.map(\.trackedMinutes).max() ?? 1, 1)

        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(report.days.enumerated()), id: \.element.id) { index, day in
                    weekBarColumn(day: day, index: index, maxMinutes: maxMinutes)
                }
            }
            .frame(height: 110)
        }
        .padding(10)
        .dsVellumInset(cornerRadius: 10)
        .onAppear { triggerChartAnimation() }
    }

    @ViewBuilder
    private func weekBarColumn(day: DayReportEntry, index: Int, maxMinutes: Int) -> some View {
        let targetHeight = max(CGFloat(day.trackedMinutes) / CGFloat(maxMinutes) * 88, day.trackedMinutes > 0 ? 10 : 3)

        VStack(spacing: 3) {
            if day.trackedMinutes > 0 {
                Text(formatHours(day.trackedMinutes))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .opacity(chartAnimated ? 1 : 0)
            }

            RoundedRectangle(cornerRadius: 4)
                .fill(day.dominantIntent?.accent ?? DS.accent)
                .frame(height: chartAnimated ? targetHeight : 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(day.isToday ? DS.accent : Color.clear, lineWidth: 1.5)
                )
                .animation(
                    reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.05),
                    value: chartAnimated
                )

            Text(day.dayLabel)
                .font(.system(size: 8, weight: day.isToday ? .bold : .medium))
                .foregroundStyle(day.isToday ? DS.accent : DS.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Monthly Heatmap

    @ViewBuilder
    private func monthlyHeatmap(_ report: ReportData) -> some View {
        let calendar = Calendar.current
        let weeks = organizeIntoWeeks(days: report.days, calendar: calendar)
        let maxTracked = max(report.days.map(\.trackedMinutes).max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 3) {
            // Weekday labels + grid
            HStack(alignment: .top, spacing: 3) {
                // Row labels
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(DS.textMuted)
                            .frame(width: 14, height: heatmapCellSize(weekCount: weeks.count))
                    }
                }

                // Grid columns (weeks)
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 3) {
                        ForEach(week, id: \.id) { day in
                            heatmapCell(day: day, maxTracked: maxTracked)
                        }
                        // Pad short weeks
                        ForEach(0..<(7 - week.count), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.clear)
                                .frame(width: heatmapCellSize(weekCount: weeks.count), height: heatmapCellSize(weekCount: weeks.count))
                        }
                    }
                }
            }

            // Legend
            heatmapLegend
        }
        .padding(10)
        .dsVellumInset(cornerRadius: 10)
    }

    @ViewBuilder
    private func heatmapCell(day: DayReportEntry, maxTracked: Int) -> some View {
        let size = heatmapCellSize(weekCount: 5)
        let cellColor = heatmapColor(minutes: day.trackedMinutes)

        RoundedRectangle(cornerRadius: 3)
            .fill(day.isFuture ? Color.clear : cellColor)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        day.isToday ? DS.gilt.opacity(0.8) :
                        (day.isFuture ? DS.sepiaSubtle.opacity(0.3) :
                        (day.trackedMinutes == 0 ? DS.sepiaSubtle.opacity(0.4) : Color.clear)),
                        lineWidth: day.isToday ? 1.5 : 0.5
                    )
            )
            .help(day.isFuture ? "" : "\(day.dayLabel): \(formatHours(day.trackedMinutes)), \(day.tasksCompleted) tasks")
    }

    private func heatmapCellSize(weekCount: Int) -> CGFloat {
        // Fit cells within ~240px (280 - padding - labels)
        let available: CGFloat = 230
        let spacing: CGFloat = CGFloat(weekCount - 1) * 3
        return max(16, (available - spacing) / CGFloat(weekCount))
    }

    /// Cartographic terrain-map coloring: parchment → gold → forest green
    private func heatmapColor(minutes: Int) -> Color {
        if minutes == 0 { return DS.vellumDeep }
        if minutes < 30 { return DS.giltSoft }
        if minutes < 120 { return DS.gilt.opacity(0.35) }
        return DS.accent.opacity(0.65)
    }

    private var heatmapLegend: some View {
        HStack(spacing: 6) {
            Spacer()
            Text("Less")
                .font(DS.smallCaps)
                .foregroundStyle(DS.inkFaded)
            ForEach(Array([0, 15, 60, 180].enumerated()), id: \.offset) { _, mins in
                RoundedRectangle(cornerRadius: 2)
                    .fill(heatmapColor(minutes: mins))
                    .frame(width: 10, height: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(mins == 0 ? DS.sepiaSubtle.opacity(0.5) : Color.clear, lineWidth: 0.5)
                    )
            }
            Text("More")
                .font(DS.smallCaps)
                .foregroundStyle(DS.inkFaded)
        }
    }

    private func organizeIntoWeeks(days: [DayReportEntry], calendar: Calendar) -> [[DayReportEntry]] {
        var weeks: [[DayReportEntry]] = []
        var currentWeek: [DayReportEntry] = []

        for day in days {
            let weekday = calendar.component(.weekday, from: day.date)
            // Monday = 2 in Calendar. Start new week on Monday.
            let isoWeekday = weekday == 1 ? 7 : weekday - 1 // Convert to Mon=1..Sun=7

            if isoWeekday == 1 && !currentWeek.isEmpty {
                weeks.append(currentWeek)
                currentWeek = []
            }
            currentWeek.append(day)
        }
        if !currentWeek.isEmpty {
            weeks.append(currentWeek)
        }
        return weeks
    }

    // MARK: - Habit Completion List

    @ViewBuilder
    private func habitCompletionList(_ report: HabitReportData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Completion Rates")
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)
                .padding(.bottom, 2)

            ForEach(report.habitEntries) { entry in
                habitCompletionRow(entry, timeRange: report.timeRange)
            }
        }
    }

    @ViewBuilder
    private func habitCompletionRow(_ entry: HabitReportEntry, timeRange: ReportTimeRange) -> some View {
        let accent = Color(hex: entry.habitDefinition.accentColor)
        let rateText = entry.totalDays > 0 ? "\(Int(entry.completionRate * 100))%" : "New"

        HStack(spacing: 8) {
            // Mini icon
            Image(systemName: entry.habitDefinition.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
                .background(accent.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.habitDefinition.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    Spacer()

                    Text(rateText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(rateColor(entry.completionRate))
                }

                // Dot strip
                habitDotStrip(entry: entry, accent: accent)

                if entry.totalDays > 0 {
                    Text("\(entry.completedDays)/\(entry.totalDays) days")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.sepiaBorder.opacity(0.4), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func habitDotStrip(entry: HabitReportEntry, accent: Color) -> some View {
        let sorted = entry.sortedDays

        if sorted.count <= 7 {
            // Weekly: individual dots
            HStack(spacing: 3) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, day in
                    Circle()
                        .fill(day.completed ? accent : DS.borderSubtle.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
        } else {
            // Monthly: continuous strip
            GeometryReader { proxy in
                let cellWidth = max(3, (proxy.size.width - CGFloat(sorted.count - 1)) / CGFloat(sorted.count))
                HStack(spacing: 1) {
                    ForEach(Array(sorted.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(day.completed ? accent.opacity(0.75) : DS.borderSubtle.opacity(0.3))
                            .frame(width: cellWidth, height: 6)
                    }
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Overall Consistency

    @ViewBuilder
    private func overallConsistency(_ report: HabitReportData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Overall")
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)

            HStack(spacing: 8) {
                // Progress bar
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.borderSubtle)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.accent.opacity(0.7))
                            .frame(width: proxy.size.width * report.overallCompletionRate, height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(Int(report.overallCompletionRate * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .frame(width: 34, alignment: .trailing)
            }

            Text("\(report.totalCompletions)/\(report.totalPossible) completions")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.textMuted)
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.sepiaBorder.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Habit Insights

    @ViewBuilder
    private func habitInsights(_ report: HabitReportData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let best = report.bestStreak {
                insightRow(icon: "flame.fill", color: DS.orange, text: "\(best.days)-day streak", detail: best.habitTitle)
            }
            if let consistent = report.mostConsistent {
                insightRow(icon: "star.fill", color: DS.green, text: "\(Int(consistent.rate * 100))% rate", detail: consistent.habitTitle)
            }
            if let needs = report.needsWork, needs.rate < 0.5 {
                insightRow(icon: "exclamationmark.triangle.fill", color: DS.orange, text: "\(Int(needs.rate * 100))% rate", detail: needs.habitTitle)
            }
        }
    }

    private func insightRow(icon: String, color: Color, text: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)

            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.text)

            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private func statsGrid(_ report: ReportData) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ], spacing: 6) {
            statCard(
                value: formatHours(report.totalMinutes),
                label: "total time",
                detail: trendText(report.trendPercent),
                color: DS.accent
            )
            statCard(
                value: "\(Int(report.avgFocusScore))%",
                label: "avg focus",
                detail: nil,
                color: focusColor(report.avgFocusScore)
            )
            statCard(
                value: "\(report.tasksCompleted)",
                label: "tasks done",
                detail: nil,
                color: DS.green
            )
            statCard(
                value: "\(report.totalSessions)",
                label: "sessions",
                detail: report.avgSessionMinutes > 0 ? "avg \(report.avgSessionMinutes)m" : nil,
                color: DS.info
            )
        }
    }

    private func statCard(value: String, label: String, detail: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.title3)
                .foregroundStyle(DS.inkWash)

            Text(label)
                .font(DS.smallCaps)
                .foregroundStyle(DS.inkFaded)

            if let detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(DS.inkFaded)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.sepiaBorder.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Intent Breakdown

    @ViewBuilder
    private func intentBreakdown(_ report: ReportData) -> some View {
        if !report.intentDistribution.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    let total = max(report.totalMinutes, 1)
                    HStack(spacing: 1) {
                        ForEach(sortedIntents(report), id: \.key.id) { entry in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(entry.key.accent)
                                .frame(width: max(CGFloat(entry.value) / CGFloat(total) * geo.size.width - 1, 4))
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(sortedIntents(report).prefix(5), id: \.key.id) { entry in
                        intentLegendRow(entry: entry, total: report.totalMinutes)
                    }
                }
            }
            .padding(10)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func intentLegendRow(entry: (key: IntentSummary, value: Int), total: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(entry.key.accent)
                .frame(width: 6, height: 6)
            Text(entry.key.title)
                .font(.system(size: 9))
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text(formatHours(entry.value))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.text)
            Text("(\(percent(entry.value, of: total))%)")
                .font(.system(size: 8))
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(DS.textMuted)
            Text("No data for this period")
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private func loadCurrentTab() async {
        switch viewModel.selectedReportTab {
        case .week:
            await viewModel.loadWeeklyReport()
        case .month:
            await viewModel.loadMonthReport()
        case .habits:
            await viewModel.loadHabitReport()
        }
        if !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                chartAnimated = true
            }
        } else {
            chartAnimated = true
        }
    }

    private func triggerChartAnimation() {
        guard !chartAnimated else { return }
        if reduceMotion {
            chartAnimated = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                chartAnimated = true
            }
        }
    }

    private func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func trendText(_ percent: Int) -> String? {
        if percent == 0 { return nil }
        let arrow = percent > 0 ? "\u{2191}" : "\u{2193}"
        return "\(arrow) \(abs(percent))%"
    }

    private func focusColor(_ score: Double) -> Color {
        if score >= 80 { return DS.green }
        if score >= 50 { return DS.orange }
        return DS.red
    }

    private func rateColor(_ rate: Double) -> Color {
        if rate >= 0.8 { return DS.green }
        if rate >= 0.5 { return DS.orange }
        return DS.red
    }

    private func sortedIntents(_ report: ReportData) -> [(key: IntentSummary, value: Int)] {
        report.intentDistribution.map { ($0, $0.minutes) }.sorted { $0.value > $1.value }
    }

    private func percent(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int(Double(value) / Double(total) * 100)
    }
}

// MARK: - ReportTab Display Name

extension ReportTab {
    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .habits: return "Habits"
        }
    }
}
