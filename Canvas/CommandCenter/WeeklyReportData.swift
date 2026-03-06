// Canvas/CommandCenter/WeeklyReportData.swift
// Data models for weekly analytics/reports
// March 2026

import Foundation

struct WeeklyReportData {
    let days: [DayReportEntry]
    let totalMinutes: Int
    let avgFocusScore: Double
    let tasksCompleted: Int
    let totalSessions: Int
    let intentDistribution: [TaskIntent: Int]
    let previousWeekMinutes: Int

    var trendPercent: Int {
        guard previousWeekMinutes > 0 else { return 0 }
        return Int(Double(totalMinutes - previousWeekMinutes) / Double(previousWeekMinutes) * 100)
    }

    var avgSessionMinutes: Int {
        guard totalSessions > 0 else { return 0 }
        return totalMinutes / totalSessions
    }

    static let empty = WeeklyReportData(
        days: [], totalMinutes: 0, avgFocusScore: 0,
        tasksCompleted: 0, totalSessions: 0,
        intentDistribution: [:], previousWeekMinutes: 0
    )
}

struct DayReportEntry: Identifiable {
    let id: String
    let date: Date
    let trackedMinutes: Int
    let focusScore: Double
    let tasksCompleted: Int
    let sessionCount: Int
    let dominantIntent: TaskIntent?

    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}
