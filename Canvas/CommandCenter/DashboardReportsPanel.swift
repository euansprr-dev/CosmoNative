// Canvas/CommandCenter/DashboardReportsPanel.swift
// Weekly analytics panel: bar chart, stats, intent breakdown
// March 2026

import SwiftUI

struct DashboardReportsPanel: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader

            if let report = viewModel.weeklyReportData {
                weeklyBarChart(report)
                statsGrid(report)
                intentBreakdown(report)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.textMuted)

            Text("THIS WEEK")
                .dsSectionLabel()
        }
    }

    // MARK: - Weekly Bar Chart

    @ViewBuilder
    private func weeklyBarChart(_ report: WeeklyReportData) -> some View {
        let maxMinutes = max(report.days.map { $0.trackedMinutes }.max() ?? 1, 1)

        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(report.days) { day in
                    VStack(spacing: 3) {
                        // Hours label
                        if day.trackedMinutes > 0 {
                            Text(formatHours(day.trackedMinutes))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(DS.textMuted)
                        }

                        // Bar
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day.dominantIntent?.color ?? DS.accent)
                            .frame(
                                height: max(CGFloat(day.trackedMinutes) / CGFloat(maxMinutes) * 80, day.trackedMinutes > 0 ? 8 : 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(day.isToday ? DS.accent : Color.clear, lineWidth: 1.5)
                            )

                        // Day label
                        Text(day.dayLabel)
                            .font(.system(size: 8, weight: day.isToday ? .bold : .medium))
                            .foregroundColor(day.isToday ? DS.accent : DS.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
        }
        .padding(10)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private func statsGrid(_ report: WeeklyReportData) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            statCard(
                title: "Total Time",
                value: formatHours(report.totalMinutes),
                detail: trendText(report.trendPercent),
                color: DS.accent
            )

            statCard(
                title: "Avg Focus",
                value: "\(Int(report.avgFocusScore))%",
                detail: nil,
                color: focusColor(report.avgFocusScore)
            )

            statCard(
                title: "Tasks Done",
                value: "\(report.tasksCompleted)",
                detail: nil,
                color: DS.green
            )

            statCard(
                title: "Sessions",
                value: "\(report.totalSessions)",
                detail: report.avgSessionMinutes > 0 ? "avg \(report.avgSessionMinutes)m" : nil,
                color: DS.info
            )
        }
    }

    private func statCard(title: String, value: String, detail: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.textMuted)

            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.text)
            }

            if let detail = detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(DS.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Intent Breakdown

    @ViewBuilder
    private func intentBreakdown(_ report: WeeklyReportData) -> some View {
        if !report.intentDistribution.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                // Stacked bar
                GeometryReader { geo in
                    let total = max(report.totalMinutes, 1)
                    HStack(spacing: 1) {
                        ForEach(sortedIntents(report), id: \.key) { entry in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(entry.key.color)
                                .frame(width: max(CGFloat(entry.value) / CGFloat(total) * geo.size.width - 1, 4))
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Legend
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(sortedIntents(report).prefix(5), id: \.key) { entry in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(entry.key.color)
                                .frame(width: 6, height: 6)

                            Text(entry.key.displayName)
                                .font(.system(size: 9))
                                .foregroundColor(DS.textSecondary)

                            Spacer()

                            Text(formatHours(entry.value))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(DS.text)

                            Text("(\(percent(entry.value, of: report.totalMinutes))%)")
                                .font(.system(size: 8))
                                .foregroundColor(DS.textMuted)
                        }
                    }
                }
            }
            .padding(10)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(DS.textMuted)

            Text("Start tracking to see reports")
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func trendText(_ percent: Int) -> String? {
        if percent == 0 { return nil }
        let arrow = percent > 0 ? "\u{2191}" : "\u{2193}"
        return "\(arrow) \(abs(percent))% vs last week"
    }

    private func focusColor(_ score: Double) -> Color {
        if score >= 80 { return DS.green }
        if score >= 50 { return DS.orange }
        return PlannerumColors.overdue
    }

    private func sortedIntents(_ report: WeeklyReportData) -> [(key: TaskIntent, value: Int)] {
        report.intentDistribution.sorted { $0.value > $1.value }
    }

    private func percent(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int(Double(value) / Double(total) * 100)
    }
}
