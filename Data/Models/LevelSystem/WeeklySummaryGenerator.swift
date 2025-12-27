import Foundation
import GRDB

// MARK: - Weekly Summary Metadata

/// Metadata structure for weekly summary atoms
public struct WeeklySummaryMetadata: Codable, Sendable {
    // Week info
    public let weekStart: Date
    public let weekEnd: Date
    public let weekNumber: Int
    public let generatedAt: Date

    // XP Summary
    public let totalXPGained: Int
    public let dailyXPBreakdown: [Date: Int]
    public let dimensionXPTotals: [String: Int]
    public let avgDailyXP: Int
    public let bestDay: DaySummary
    public let worstDay: DaySummary

    // Level Progress
    public let levelStart: Int
    public let levelEnd: Int
    public let levelsGained: Int
    public let xpToNextLevel: Int
    public let weeklyProgress: Double

    // NELO Movement
    public let neloStart: Int
    public let neloEnd: Int
    public let neloChange: Int
    public let neloTrend: WeeklyTrendDirection
    public let dimensionNELOChanges: [String: Int]

    // Activity Totals
    public let tasksCompleted: Int
    public let deepWorkMinutes: Int
    public let avgDeepWorkPerDay: Int
    public let wordsWritten: Int
    public let avgWordsPerDay: Int
    public let journalEntries: Int
    public let ideasCaptured: Int

    // Health Averages
    public let avgHRV: Double?
    public let avgSleepHours: Double?
    public let avgSleepQuality: Double?
    public let avgReadiness: Double?
    public let workoutsCompleted: Int
    public let healthTrend: WeeklyTrendDirection

    // Streaks
    public let longestStreakMaintained: Int
    public let streaksBroken: Int
    public let streaksStarted: Int
    public let currentStreaks: [String: Int]

    // Badges
    public let badgesUnlocked: [BadgeUnlockSummary]
    public let totalBadgesEarned: Int

    // Quests
    public let questsCompleted: Int
    public let totalQuests: Int
    public let questCompletionRate: Double
    public let questXPEarned: Int

    // Comparison to Previous Week
    public let previousWeekXP: Int?
    public let xpChangePercent: Double?
    public let previousWeekDeepWork: Int?
    public let deepWorkChangePercent: Double?

    // AI Insights
    public let weeklyInsights: [WeeklyInsight]
    public let topAchievement: String?
    public let areaForImprovement: String?
    public let nextWeekFocus: String?

    public init(
        weekStart: Date,
        weekEnd: Date,
        weekNumber: Int,
        generatedAt: Date = Date(),
        totalXPGained: Int,
        dailyXPBreakdown: [Date: Int],
        dimensionXPTotals: [String: Int],
        avgDailyXP: Int,
        bestDay: DaySummary,
        worstDay: DaySummary,
        levelStart: Int,
        levelEnd: Int,
        levelsGained: Int,
        xpToNextLevel: Int,
        weeklyProgress: Double,
        neloStart: Int,
        neloEnd: Int,
        neloChange: Int,
        neloTrend: WeeklyTrendDirection,
        dimensionNELOChanges: [String: Int],
        tasksCompleted: Int,
        deepWorkMinutes: Int,
        avgDeepWorkPerDay: Int,
        wordsWritten: Int,
        avgWordsPerDay: Int,
        journalEntries: Int,
        ideasCaptured: Int,
        avgHRV: Double?,
        avgSleepHours: Double?,
        avgSleepQuality: Double?,
        avgReadiness: Double?,
        workoutsCompleted: Int,
        healthTrend: WeeklyTrendDirection,
        longestStreakMaintained: Int,
        streaksBroken: Int,
        streaksStarted: Int,
        currentStreaks: [String: Int],
        badgesUnlocked: [BadgeUnlockSummary],
        totalBadgesEarned: Int,
        questsCompleted: Int,
        totalQuests: Int,
        questCompletionRate: Double,
        questXPEarned: Int,
        previousWeekXP: Int?,
        xpChangePercent: Double?,
        previousWeekDeepWork: Int?,
        deepWorkChangePercent: Double?,
        weeklyInsights: [WeeklyInsight],
        topAchievement: String?,
        areaForImprovement: String?,
        nextWeekFocus: String?
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.weekNumber = weekNumber
        self.generatedAt = generatedAt
        self.totalXPGained = totalXPGained
        self.dailyXPBreakdown = dailyXPBreakdown
        self.dimensionXPTotals = dimensionXPTotals
        self.avgDailyXP = avgDailyXP
        self.bestDay = bestDay
        self.worstDay = worstDay
        self.levelStart = levelStart
        self.levelEnd = levelEnd
        self.levelsGained = levelsGained
        self.xpToNextLevel = xpToNextLevel
        self.weeklyProgress = weeklyProgress
        self.neloStart = neloStart
        self.neloEnd = neloEnd
        self.neloChange = neloChange
        self.neloTrend = neloTrend
        self.dimensionNELOChanges = dimensionNELOChanges
        self.tasksCompleted = tasksCompleted
        self.deepWorkMinutes = deepWorkMinutes
        self.avgDeepWorkPerDay = avgDeepWorkPerDay
        self.wordsWritten = wordsWritten
        self.avgWordsPerDay = avgWordsPerDay
        self.journalEntries = journalEntries
        self.ideasCaptured = ideasCaptured
        self.avgHRV = avgHRV
        self.avgSleepHours = avgSleepHours
        self.avgSleepQuality = avgSleepQuality
        self.avgReadiness = avgReadiness
        self.workoutsCompleted = workoutsCompleted
        self.healthTrend = healthTrend
        self.longestStreakMaintained = longestStreakMaintained
        self.streaksBroken = streaksBroken
        self.streaksStarted = streaksStarted
        self.currentStreaks = currentStreaks
        self.badgesUnlocked = badgesUnlocked
        self.totalBadgesEarned = totalBadgesEarned
        self.questsCompleted = questsCompleted
        self.totalQuests = totalQuests
        self.questCompletionRate = questCompletionRate
        self.questXPEarned = questXPEarned
        self.previousWeekXP = previousWeekXP
        self.xpChangePercent = xpChangePercent
        self.previousWeekDeepWork = previousWeekDeepWork
        self.deepWorkChangePercent = deepWorkChangePercent
        self.weeklyInsights = weeklyInsights
        self.topAchievement = topAchievement
        self.areaForImprovement = areaForImprovement
        self.nextWeekFocus = nextWeekFocus
    }
}

// MARK: - Supporting Types

public struct DaySummary: Codable, Sendable {
    public let date: Date
    public let xp: Int
    public let highlight: String

    public init(date: Date, xp: Int, highlight: String) {
        self.date = date
        self.xp = xp
        self.highlight = highlight
    }
}

public enum WeeklyTrendDirection: String, Codable, Sendable {
    case up
    case down
    case stable
}

public struct WeeklyInsight: Codable, Sendable {
    public let category: InsightCategory
    public let title: String
    public let description: String
    public let metric: String?
    public let change: Double?

    public enum InsightCategory: String, Codable, Sendable {
        case achievement
        case pattern
        case growth
        case health
        case consistency
        case improvement
    }

    public init(
        category: InsightCategory,
        title: String,
        description: String,
        metric: String? = nil,
        change: Double? = nil
    ) {
        self.category = category
        self.title = title
        self.description = description
        self.metric = metric
        self.change = change
    }
}

// MARK: - Weekly Summary Generator

/// Generates comprehensive weekly summary atoms
public actor WeeklySummaryGenerator {

    private let xpEngine: XPCalculationEngine

    public init(xpEngine: XPCalculationEngine = XPCalculationEngine()) {
        self.xpEngine = xpEngine
    }

    // MARK: - Generate Weekly Summary

    /// Generate a weekly summary for the specified week
    public func generateWeeklySummary(
        db: Database,
        weekOf date: Date
    ) throws -> Atom {
        let calendar = Calendar.current

        // Calculate week boundaries (Sunday to Saturday)
        let weekday = calendar.component(.weekday, from: date)
        let daysToSubtract = weekday - 1  // Days since Sunday
        guard let weekStart = calendar.date(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: date)),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            throw WeeklySummaryError.invalidDate
        }

        let weekNumber = calendar.component(.weekOfYear, from: date)

        // Fetch daily summaries for the week
        let dailySummaries = try fetchDailySummaries(db: db, from: weekStart, to: weekEnd)

        // Aggregate XP data
        let xpData = aggregateXPData(dailySummaries: dailySummaries)

        // Aggregate activity data
        let activityData = try aggregateActivityData(db: db, from: weekStart, to: weekEnd)

        // Aggregate health data
        let healthData = try aggregateHealthData(db: db, from: weekStart, to: weekEnd)

        // Get level state comparison
        let levelData = try getLevelComparison(db: db, weekStart: weekStart, weekEnd: weekEnd)

        // Get streak data
        let streakData = try getStreakData(db: db, from: weekStart, to: weekEnd)

        // Get badge data
        let badgeData = try getBadgeData(db: db, from: weekStart, to: weekEnd)

        // Get quest data
        let questData = try getQuestData(db: db, from: weekStart, to: weekEnd)

        // Get previous week comparison
        let comparison = try getPreviousWeekComparison(db: db, weekStart: weekStart)

        // Generate insights
        let insights = generateInsights(
            xpData: xpData,
            activityData: activityData,
            healthData: healthData,
            streakData: streakData,
            comparison: comparison
        )

        // Create metadata
        let metadata = WeeklySummaryMetadata(
            weekStart: weekStart,
            weekEnd: weekEnd,
            weekNumber: weekNumber,
            totalXPGained: xpData.total,
            dailyXPBreakdown: xpData.dailyBreakdown,
            dimensionXPTotals: xpData.dimensionTotals,
            avgDailyXP: xpData.dailyAverage,
            bestDay: xpData.bestDay,
            worstDay: xpData.worstDay,
            levelStart: levelData.startLevel,
            levelEnd: levelData.endLevel,
            levelsGained: levelData.levelsGained,
            xpToNextLevel: levelData.xpToNext,
            weeklyProgress: levelData.weeklyProgress,
            neloStart: levelData.neloStart,
            neloEnd: levelData.neloEnd,
            neloChange: levelData.neloChange,
            neloTrend: levelData.neloTrend,
            dimensionNELOChanges: levelData.dimensionNELOChanges,
            tasksCompleted: activityData.tasks,
            deepWorkMinutes: activityData.deepWorkMinutes,
            avgDeepWorkPerDay: activityData.avgDeepWorkPerDay,
            wordsWritten: activityData.words,
            avgWordsPerDay: activityData.avgWordsPerDay,
            journalEntries: activityData.journals,
            ideasCaptured: activityData.ideas,
            avgHRV: healthData.avgHRV,
            avgSleepHours: healthData.avgSleep,
            avgSleepQuality: healthData.avgSleepQuality,
            avgReadiness: healthData.avgReadiness,
            workoutsCompleted: healthData.workouts,
            healthTrend: healthData.trend,
            longestStreakMaintained: streakData.longest,
            streaksBroken: streakData.broken,
            streaksStarted: streakData.started,
            currentStreaks: streakData.current,
            badgesUnlocked: badgeData.unlocked,
            totalBadgesEarned: badgeData.total,
            questsCompleted: questData.completed,
            totalQuests: questData.total,
            questCompletionRate: questData.completionRate,
            questXPEarned: questData.xp,
            previousWeekXP: comparison.previousXP,
            xpChangePercent: comparison.xpChange,
            previousWeekDeepWork: comparison.previousDeepWork,
            deepWorkChangePercent: comparison.deepWorkChange,
            weeklyInsights: insights.list,
            topAchievement: insights.topAchievement,
            areaForImprovement: insights.improvement,
            nextWeekFocus: insights.nextFocus
        )

        // Create the atom
        let title = formatWeeklyTitle(weekNumber: weekNumber, xp: xpData.total)
        let body = formatWeeklyBody(metadata: metadata)

        let metadataJSON = try JSONEncoder().encode(metadata)
        let metadataString = String(data: metadataJSON, encoding: .utf8)

        return Atom(
            id: nil,
            uuid: UUID().uuidString,
            type: .weeklySummary,
            title: title,
            body: body,
            structured: nil,
            metadata: metadataString,
            links: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            isDeleted: false,
            localVersion: 1,
            serverVersion: 0,
            syncVersion: 0
        )
    }

    // MARK: - Data Aggregation

    private struct XPAggregation {
        let total: Int
        let dailyBreakdown: [Date: Int]
        let dimensionTotals: [String: Int]
        let dailyAverage: Int
        let bestDay: DaySummary
        let worstDay: DaySummary
    }

    private func fetchDailySummaries(db: Database, from start: Date, to end: Date) throws -> [DailySummaryMetadata] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT metadata FROM atoms
            WHERE type = 'daily_summary'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
            ORDER BY createdAt ASC
        """, arguments: [start, end])

        var summaries: [DailySummaryMetadata] = []
        for row in rows {
            if let metadataString = row["metadata"] as? String,
               let data = metadataString.data(using: .utf8),
               let summary = try? JSONDecoder().decode(DailySummaryMetadata.self, from: data) {
                summaries.append(summary)
            }
        }
        return summaries
    }

    private func aggregateXPData(dailySummaries: [DailySummaryMetadata]) -> XPAggregation {
        var total = 0
        var dailyBreakdown: [Date: Int] = [:]
        var dimensionTotals: [String: Int] = [
            "cognitive": 0,
            "creative": 0,
            "physiological": 0,
            "behavioral": 0,
            "knowledge": 0,
            "reflection": 0
        ]

        var bestDay = DaySummary(date: Date(), xp: 0, highlight: "")
        var worstDay = DaySummary(date: Date(), xp: Int.max, highlight: "")

        for summary in dailySummaries {
            total += summary.totalXPGained
            dailyBreakdown[summary.summaryDate] = summary.totalXPGained

            for (dim, xp) in summary.dimensionXP {
                dimensionTotals[dim, default: 0] += xp
            }

            if summary.totalXPGained > bestDay.xp {
                bestDay = DaySummary(
                    date: summary.summaryDate,
                    xp: summary.totalXPGained,
                    highlight: summary.insights.first?.title ?? "Great day!"
                )
            }

            if summary.totalXPGained < worstDay.xp {
                worstDay = DaySummary(
                    date: summary.summaryDate,
                    xp: summary.totalXPGained,
                    highlight: "Rest day"
                )
            }
        }

        let daysCount = max(1, dailySummaries.count)
        let dailyAverage = total / daysCount

        // Handle case with no summaries
        if dailySummaries.isEmpty {
            bestDay = DaySummary(date: Date(), xp: 0, highlight: "No data")
            worstDay = DaySummary(date: Date(), xp: 0, highlight: "No data")
        }

        return XPAggregation(
            total: total,
            dailyBreakdown: dailyBreakdown,
            dimensionTotals: dimensionTotals,
            dailyAverage: dailyAverage,
            bestDay: bestDay,
            worstDay: worstDay
        )
    }

    private struct ActivityAggregation {
        let tasks: Int
        let deepWorkMinutes: Int
        let avgDeepWorkPerDay: Int
        let words: Int
        let avgWordsPerDay: Int
        let journals: Int
        let ideas: Int
    }

    private func aggregateActivityData(db: Database, from start: Date, to end: Date) throws -> ActivityAggregation {
        let tasks = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'task'
            AND metadata LIKE '%"isCompleted":true%'
            AND updatedAt >= ? AND updatedAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        let deepWork = try Int.fetchOne(db, sql: """
            SELECT COALESCE(SUM(CAST(json_extract(metadata, '$.durationMinutes') AS INTEGER)), 0)
            FROM atoms
            WHERE type IN ('focus_session', 'deep_work_block')
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        let words = try Int.fetchOne(db, sql: """
            SELECT COALESCE(SUM(CAST(json_extract(metadata, '$.wordCount') AS INTEGER)), 0)
            FROM atoms
            WHERE type = 'writing_session'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        let journals = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'journal_entry'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        let ideas = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'idea'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        return ActivityAggregation(
            tasks: tasks,
            deepWorkMinutes: deepWork,
            avgDeepWorkPerDay: deepWork / 7,
            words: words,
            avgWordsPerDay: words / 7,
            journals: journals,
            ideas: ideas
        )
    }

    private struct HealthAggregation {
        let avgHRV: Double?
        let avgSleep: Double?
        let avgSleepQuality: Double?
        let avgReadiness: Double?
        let workouts: Int
        let trend: WeeklyTrendDirection
    }

    private func aggregateHealthData(db: Database, from start: Date, to end: Date) throws -> HealthAggregation {
        let avgHRV = try Double.fetchOne(db, sql: """
            SELECT AVG(CAST(json_extract(metadata, '$.hrvMs') AS REAL))
            FROM atoms
            WHERE type = 'hrv_reading'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end])

        let avgSleep = try Double.fetchOne(db, sql: """
            SELECT AVG(CAST(json_extract(metadata, '$.totalHours') AS REAL))
            FROM atoms
            WHERE type = 'sleep_record'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end])

        let avgSleepQuality = try Double.fetchOne(db, sql: """
            SELECT AVG(CAST(json_extract(metadata, '$.efficiency') AS REAL))
            FROM atoms
            WHERE type = 'sleep_record'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end])

        let avgReadiness = try Double.fetchOne(db, sql: """
            SELECT AVG(CAST(json_extract(metadata, '$.overallScore') AS REAL))
            FROM atoms
            WHERE type = 'readiness_score'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end])

        let workouts = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'workout'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        // Determine trend based on week halves
        let trend: WeeklyTrendDirection = .stable  // Simplified for now

        return HealthAggregation(
            avgHRV: avgHRV,
            avgSleep: avgSleep,
            avgSleepQuality: avgSleepQuality,
            avgReadiness: avgReadiness,
            workouts: workouts,
            trend: trend
        )
    }

    private struct LevelComparison {
        let startLevel: Int
        let endLevel: Int
        let levelsGained: Int
        let xpToNext: Int
        let weeklyProgress: Double
        let neloStart: Int
        let neloEnd: Int
        let neloChange: Int
        let neloTrend: WeeklyTrendDirection
        let dimensionNELOChanges: [String: Int]
    }

    private func getLevelComparison(db: Database, weekStart: Date, weekEnd: Date) throws -> LevelComparison {
        // Get current level state
        guard let currentState = try CosmoLevelState.fetchOne(db) else {
            return LevelComparison(
                startLevel: 1, endLevel: 1, levelsGained: 0, xpToNext: 1000,
                weeklyProgress: 0, neloStart: 1000, neloEnd: 1000, neloChange: 0,
                neloTrend: .stable, dimensionNELOChanges: [:]
            )
        }

        // For start of week, we'd need historical snapshots
        // Simplified: assume small progress
        let startLevel = currentState.cosmoIndex
        let endLevel = currentState.cosmoIndex

        let neloChange = 0  // Would calculate from dimension snapshots
        let neloTrend: WeeklyTrendDirection = .stable  // Will update when dimension snapshots are implemented

        return LevelComparison(
            startLevel: startLevel,
            endLevel: endLevel,
            levelsGained: endLevel - startLevel,
            xpToNext: XPCalculationEngine.xpToNextLevel(totalXP: currentState.totalXPEarned),
            weeklyProgress: XPCalculationEngine.progressInLevel(totalXP: currentState.totalXPEarned),
            neloStart: currentState.overallNelo,
            neloEnd: currentState.overallNelo,
            neloChange: neloChange,
            neloTrend: neloTrend,
            dimensionNELOChanges: [:]
        )
    }

    private struct StreakAggregation {
        let longest: Int
        let broken: Int
        let started: Int
        let current: [String: Int]
    }

    private func getStreakData(db: Database, from start: Date, to end: Date) throws -> StreakAggregation {
        let broken = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'streak_event'
            AND metadata LIKE '%"eventType":"broken"%'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        // Get current streaks
        var current: [String: Int] = [:]
        let dimensions = ["cognitive", "creative", "physiological", "behavioral", "knowledge", "reflection"]
        for dim in dimensions {
            let streak = try Int.fetchOne(db, sql: """
                SELECT CAST(json_extract(metadata, '$.currentStreak') AS INTEGER)
                FROM atoms
                WHERE type = 'streak_event'
                AND metadata LIKE ?
                AND isDeleted = 0
                ORDER BY createdAt DESC
                LIMIT 1
            """, arguments: ["%\"\(dim)\"%"]) ?? 0
            current[dim] = streak
        }

        let longest = current.values.max() ?? 0

        return StreakAggregation(
            longest: longest,
            broken: broken,
            started: 0,  // Would need to track new streaks
            current: current
        )
    }

    private struct BadgeAggregation {
        let unlocked: [BadgeUnlockSummary]
        let total: Int
    }

    private func getBadgeData(db: Database, from start: Date, to end: Date) throws -> BadgeAggregation {
        let rows = try Row.fetchAll(db, sql: """
            SELECT metadata FROM atoms
            WHERE type = 'badge_unlocked'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end])

        var unlocked: [BadgeUnlockSummary] = []
        for row in rows {
            if let metadataString = row["metadata"] as? String,
               let data = metadataString.data(using: .utf8),
               let meta = try? JSONDecoder().decode(BadgeUnlockMeta.self, from: data) {
                unlocked.append(BadgeUnlockSummary(
                    badgeId: meta.badgeId,
                    name: meta.badgeName,
                    tier: meta.badgeTier,
                    xpReward: meta.xpReward
                ))
            }
        }

        return BadgeAggregation(unlocked: unlocked, total: unlocked.count)
    }

    private struct BadgeUnlockMeta: Codable {
        let badgeId: String
        let badgeName: String
        let badgeTier: String
        let xpReward: Int
    }

    private struct QuestAggregation {
        let completed: Int
        let total: Int
        let completionRate: Double
        let xp: Int
    }

    private func getQuestData(db: Database, from start: Date, to end: Date) throws -> QuestAggregation {
        let completed = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'daily_quest'
            AND metadata LIKE '%"isComplete":true%'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        let total = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'daily_quest'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        let xp = try Int.fetchOne(db, sql: """
            SELECT COALESCE(SUM(CAST(json_extract(metadata, '$.xpReward') AS INTEGER)), 0)
            FROM atoms
            WHERE type = 'daily_quest'
            AND metadata LIKE '%"isComplete":true%'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        let rate = total > 0 ? Double(completed) / Double(total) : 0

        return QuestAggregation(completed: completed, total: total, completionRate: rate, xp: xp)
    }

    private struct WeekComparison {
        let previousXP: Int?
        let xpChange: Double?
        let previousDeepWork: Int?
        let deepWorkChange: Double?
    }

    private func getPreviousWeekComparison(db: Database, weekStart: Date) throws -> WeekComparison {
        let calendar = Calendar.current
        guard let prevWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart),
              let prevWeekEnd = calendar.date(byAdding: .day, value: 7, to: prevWeekStart) else {
            return WeekComparison(previousXP: nil, xpChange: nil, previousDeepWork: nil, deepWorkChange: nil)
        }

        // Get previous week's summary if it exists
        let row = try Row.fetchOne(db, sql: """
            SELECT metadata FROM atoms
            WHERE type = 'weekly_summary'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
            LIMIT 1
        """, arguments: [prevWeekStart, prevWeekEnd])

        if let row = row,
           let metadataString = row["metadata"] as? String,
           let data = metadataString.data(using: .utf8),
           let prevSummary = try? JSONDecoder().decode(WeeklySummaryMetadata.self, from: data) {
            return WeekComparison(
                previousXP: prevSummary.totalXPGained,
                xpChange: nil,  // Would calculate
                previousDeepWork: prevSummary.deepWorkMinutes,
                deepWorkChange: nil
            )
        }

        return WeekComparison(previousXP: nil, xpChange: nil, previousDeepWork: nil, deepWorkChange: nil)
    }

    // MARK: - Insight Generation

    private struct InsightsResult {
        let list: [WeeklyInsight]
        let topAchievement: String?
        let improvement: String?
        let nextFocus: String?
    }

    private func generateInsights(
        xpData: XPAggregation,
        activityData: ActivityAggregation,
        healthData: HealthAggregation,
        streakData: StreakAggregation,
        comparison: WeekComparison
    ) -> InsightsResult {
        var insights: [WeeklyInsight] = []
        var topAchievement: String?
        var improvement: String?

        // XP achievements
        if xpData.total >= 5000 {
            let insight = WeeklyInsight(
                category: .achievement,
                title: "Outstanding Week",
                description: "You earned \(xpData.total) XP this week - exceptional performance!",
                metric: "\(xpData.total) XP"
            )
            insights.append(insight)
            topAchievement = "Earned \(xpData.total) XP this week"
        }

        // Deep work pattern
        if activityData.deepWorkMinutes >= 1200 {  // 20+ hours
            insights.append(WeeklyInsight(
                category: .pattern,
                title: "Deep Work Master",
                description: "You completed \(activityData.deepWorkMinutes / 60) hours of deep work - Cal Newport approved!",
                metric: "\(activityData.deepWorkMinutes / 60)h"
            ))
        } else if activityData.deepWorkMinutes < 300 {  // Less than 5 hours
            improvement = "Increase deep work time to boost cognitive dimension"
        }

        // Streak consistency
        if streakData.longest >= 30 {
            insights.append(WeeklyInsight(
                category: .consistency,
                title: "Streak Champion",
                description: "Maintaining a \(streakData.longest)-day streak - consistency is your superpower!",
                metric: "\(streakData.longest) days"
            ))
        }

        // Health insight
        if let avgReadiness = healthData.avgReadiness, avgReadiness >= 80 {
            insights.append(WeeklyInsight(
                category: .health,
                title: "Peak Recovery",
                description: "Average readiness of \(Int(avgReadiness))% - your body is well-recovered.",
                metric: "\(Int(avgReadiness))%"
            ))
        }

        // Week over week growth
        if let prevXP = comparison.previousXP, xpData.total > prevXP {
            let growthPercent = Double(xpData.total - prevXP) / Double(prevXP) * 100
            insights.append(WeeklyInsight(
                category: .growth,
                title: "Week-over-Week Growth",
                description: "You earned \(Int(growthPercent))% more XP than last week.",
                metric: "+\(Int(growthPercent))%",
                change: growthPercent
            ))
        }

        // Next week focus
        var nextFocus: String?
        if streakData.broken > 0 {
            nextFocus = "Rebuild broken streaks with daily consistency"
        } else if activityData.journals < 3 {
            nextFocus = "Add more reflection through journaling"
        } else {
            nextFocus = "Maintain momentum and push for new personal records"
        }

        if topAchievement == nil && !insights.isEmpty {
            topAchievement = insights.first?.title
        }

        return InsightsResult(
            list: insights,
            topAchievement: topAchievement,
            improvement: improvement,
            nextFocus: nextFocus
        )
    }

    // MARK: - Formatting

    private func formatWeeklyTitle(weekNumber: Int, xp: Int) -> String {
        "Week \(weekNumber) Summary • +\(xp) XP"
    }

    private func formatWeeklyBody(metadata: WeeklySummaryMetadata) -> String {
        var lines: [String] = []

        lines.append("## Weekly Summary")
        lines.append("")
        lines.append("**Total XP:** +\(metadata.totalXPGained)")
        lines.append("**Daily Average:** \(metadata.avgDailyXP) XP")
        lines.append("")

        lines.append("### Activity")
        lines.append("- Tasks: \(metadata.tasksCompleted)")
        lines.append("- Deep Work: \(metadata.deepWorkMinutes / 60)h \(metadata.deepWorkMinutes % 60)m")
        lines.append("- Words: \(metadata.wordsWritten)")
        lines.append("- Ideas: \(metadata.ideasCaptured)")
        lines.append("")

        if let topAchievement = metadata.topAchievement {
            lines.append("### Top Achievement")
            lines.append(topAchievement)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Errors

enum WeeklySummaryError: Error {
    case invalidDate
    case noDataAvailable
}

// Note: AtomType.weeklySummary already exists as a case in the enum
