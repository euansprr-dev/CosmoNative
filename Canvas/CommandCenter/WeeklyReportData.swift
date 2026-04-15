// Canvas/CommandCenter/WeeklyReportData.swift
// Data models for analytics reports (weekly, monthly, habit tracking)
// March 2026

import Foundation

// MARK: - Time Range

enum ReportTimeRange: String, CaseIterable {
    case week
    case month
}

enum ReportTab: String, CaseIterable {
    case week
    case month
    case habits
}

// MARK: - Report Data

struct ReportData {
    let timeRange: ReportTimeRange
    let startDate: Date
    let endDate: Date
    let days: [DayReportEntry]
    let totalMinutes: Int
    let avgFocusScore: Double
    let tasksCompleted: Int
    let totalSessions: Int
    let intentDistribution: [TaskIntent: Int]
    let previousPeriodMinutes: Int

    var trendPercent: Int {
        guard previousPeriodMinutes > 0 else { return 0 }
        return Int(Double(totalMinutes - previousPeriodMinutes) / Double(previousPeriodMinutes) * 100)
    }

    var avgSessionMinutes: Int {
        guard totalSessions > 0 else { return 0 }
        return totalMinutes / totalSessions
    }

    static let empty = ReportData(
        timeRange: .week,
        startDate: Date(),
        endDate: Date(),
        days: [], totalMinutes: 0, avgFocusScore: 0,
        tasksCompleted: 0, totalSessions: 0,
        intentDistribution: [:], previousPeriodMinutes: 0
    )
}

/// Backward compatibility alias
typealias WeeklyReportData = ReportData

// MARK: - Day Entry

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

    var shortDayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(1))
    }

    var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var isFuture: Bool {
        date > Date()
    }
}

// MARK: - Habit Report Data

struct HabitReportData {
    let timeRange: ReportTimeRange
    let startDate: Date
    let endDate: Date
    let habitEntries: [HabitReportEntry]
    let overallCompletionRate: Double
    let totalCompletions: Int
    let totalPossible: Int

    var bestStreak: (habitTitle: String, days: Int)? {
        guard let best = habitEntries.max(by: { $0.bestStreak < $1.bestStreak }),
              best.bestStreak > 0 else { return nil }
        return (best.habitDefinition.title, best.bestStreak)
    }

    var mostConsistent: (habitTitle: String, rate: Double)? {
        guard let best = habitEntries.filter({ $0.totalDays > 0 }).max(by: { $0.completionRate < $1.completionRate }),
              best.completionRate > 0 else { return nil }
        return (best.habitDefinition.title, best.completionRate)
    }

    var needsWork: (habitTitle: String, rate: Double)? {
        guard let worst = habitEntries.filter({ $0.totalDays > 0 }).min(by: { $0.completionRate < $1.completionRate }),
              worst.completionRate < 1.0 else { return nil }
        return (worst.habitDefinition.title, worst.completionRate)
    }

    static let empty = HabitReportData(
        timeRange: .week,
        startDate: Date(),
        endDate: Date(),
        habitEntries: [],
        overallCompletionRate: 0,
        totalCompletions: 0,
        totalPossible: 0
    )
}

struct HabitReportEntry: Identifiable {
    var id: String { habitDefinition.id }
    let habitDefinition: HabitDefinition
    let dayResults: [Date: Bool]
    let completionRate: Double
    let completedDays: Int
    let totalDays: Int
    let currentStreak: Int
    let bestStreak: Int
    let createdDate: Date?

    /// Sorted day results for display (earliest first)
    var sortedDays: [(date: Date, completed: Bool)] {
        dayResults.sorted { $0.key < $1.key }.map { (date: $0.key, completed: $0.value) }
    }
}
