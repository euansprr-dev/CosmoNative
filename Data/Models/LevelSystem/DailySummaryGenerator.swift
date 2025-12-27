import Foundation
import GRDB

// MARK: - Daily Summary Metadata

/// Metadata structure for daily summary atoms
public struct DailySummaryMetadata: Codable, Sendable {
    // Date info
    public let summaryDate: Date
    public let generatedAt: Date

    // XP Summary
    public let totalXPGained: Int
    public let dimensionXP: [String: Int]
    public let bonusXPGained: Int
    public let bonusReason: String?
    public let streakMultiplier: Double

    // Level Changes
    public let previousCosmoIndex: Int
    public let newCosmoIndex: Int
    public let cosmoIndexProgress: Double
    public let xpToNextLevel: Int
    public let levelUps: [LevelUpSummary]

    // NELO Changes
    public let previousNELO: Int
    public let newNELO: Int
    public let neloChange: Int
    public let neloTrend: String  // "up", "down", "stable"
    public let dimensionNELOChanges: [String: Int]

    // Activity Summary
    public let tasksCompleted: Int
    public let deepWorkMinutes: Int
    public let wordsWritten: Int
    public let journalEntries: Int
    public let researchItems: Int
    public let ideasCaptured: Int

    // Health Summary
    public let avgHRV: Double?
    public let sleepHours: Double?
    public let sleepQuality: Double?
    public let readinessScore: Double?
    public let workoutsCompleted: Int

    // Streaks
    public let currentOverallStreak: Int
    public let streaksExtended: [String]
    public let streaksBroken: [String]
    public let streaksAtRisk: [StreakAtRiskSummary]

    // Badges
    public let badgesUnlocked: [BadgeUnlockSummary]
    public let nearestBadges: [NearBadgeSummary]

    // Quests
    public let questsCompleted: Int
    public let totalQuests: Int
    public let questXPEarned: Int

    // AI Insights
    public let insights: [DailyInsight]
    public let tomorrowFocus: String?
    public let motivationalNote: String?

    public init(
        summaryDate: Date,
        generatedAt: Date = Date(),
        totalXPGained: Int,
        dimensionXP: [String: Int],
        bonusXPGained: Int,
        bonusReason: String?,
        streakMultiplier: Double,
        previousCosmoIndex: Int,
        newCosmoIndex: Int,
        cosmoIndexProgress: Double,
        xpToNextLevel: Int,
        levelUps: [LevelUpSummary],
        previousNELO: Int,
        newNELO: Int,
        neloChange: Int,
        neloTrend: String,
        dimensionNELOChanges: [String: Int],
        tasksCompleted: Int,
        deepWorkMinutes: Int,
        wordsWritten: Int,
        journalEntries: Int,
        researchItems: Int,
        ideasCaptured: Int,
        avgHRV: Double?,
        sleepHours: Double?,
        sleepQuality: Double?,
        readinessScore: Double?,
        workoutsCompleted: Int,
        currentOverallStreak: Int,
        streaksExtended: [String],
        streaksBroken: [String],
        streaksAtRisk: [StreakAtRiskSummary],
        badgesUnlocked: [BadgeUnlockSummary],
        nearestBadges: [NearBadgeSummary],
        questsCompleted: Int,
        totalQuests: Int,
        questXPEarned: Int,
        insights: [DailyInsight],
        tomorrowFocus: String?,
        motivationalNote: String?
    ) {
        self.summaryDate = summaryDate
        self.generatedAt = generatedAt
        self.totalXPGained = totalXPGained
        self.dimensionXP = dimensionXP
        self.bonusXPGained = bonusXPGained
        self.bonusReason = bonusReason
        self.streakMultiplier = streakMultiplier
        self.previousCosmoIndex = previousCosmoIndex
        self.newCosmoIndex = newCosmoIndex
        self.cosmoIndexProgress = cosmoIndexProgress
        self.xpToNextLevel = xpToNextLevel
        self.levelUps = levelUps
        self.previousNELO = previousNELO
        self.newNELO = newNELO
        self.neloChange = neloChange
        self.neloTrend = neloTrend
        self.dimensionNELOChanges = dimensionNELOChanges
        self.tasksCompleted = tasksCompleted
        self.deepWorkMinutes = deepWorkMinutes
        self.wordsWritten = wordsWritten
        self.journalEntries = journalEntries
        self.researchItems = researchItems
        self.ideasCaptured = ideasCaptured
        self.avgHRV = avgHRV
        self.sleepHours = sleepHours
        self.sleepQuality = sleepQuality
        self.readinessScore = readinessScore
        self.workoutsCompleted = workoutsCompleted
        self.currentOverallStreak = currentOverallStreak
        self.streaksExtended = streaksExtended
        self.streaksBroken = streaksBroken
        self.streaksAtRisk = streaksAtRisk
        self.badgesUnlocked = badgesUnlocked
        self.nearestBadges = nearestBadges
        self.questsCompleted = questsCompleted
        self.totalQuests = totalQuests
        self.questXPEarned = questXPEarned
        self.insights = insights
        self.tomorrowFocus = tomorrowFocus
        self.motivationalNote = motivationalNote
    }
}

// MARK: - Supporting Types

public struct LevelUpSummary: Codable, Sendable {
    public let dimension: String  // "overall" for CI, or dimension name
    public let previousLevel: Int
    public let newLevel: Int
    public let title: String?  // e.g., "Practitioner"

    public init(dimension: String, previousLevel: Int, newLevel: Int, title: String?) {
        self.dimension = dimension
        self.previousLevel = previousLevel
        self.newLevel = newLevel
        self.title = title
    }
}

public struct StreakAtRiskSummary: Codable, Sendable {
    public let dimension: String
    public let currentStreak: Int
    public let hoursRemaining: Int
    public let action: String

    public init(dimension: String, currentStreak: Int, hoursRemaining: Int, action: String) {
        self.dimension = dimension
        self.currentStreak = currentStreak
        self.hoursRemaining = hoursRemaining
        self.action = action
    }
}

public struct BadgeUnlockSummary: Codable, Sendable {
    public let badgeId: String
    public let name: String
    public let tier: String
    public let xpReward: Int

    public init(badgeId: String, name: String, tier: String, xpReward: Int) {
        self.badgeId = badgeId
        self.name = name
        self.tier = tier
        self.xpReward = xpReward
    }
}

public struct NearBadgeSummary: Codable, Sendable {
    public let badgeId: String
    public let name: String
    public let progress: Double
    public let remainingDescription: String

    public init(badgeId: String, name: String, progress: Double, remainingDescription: String) {
        self.badgeId = badgeId
        self.name = name
        self.progress = progress
        self.remainingDescription = remainingDescription
    }
}

public struct DailyInsight: Codable, Sendable {
    public let type: InsightType
    public let title: String
    public let description: String
    public let actionable: Bool

    public enum InsightType: String, Codable, Sendable {
        case achievement
        case pattern
        case suggestion
        case warning
        case celebration
    }

    public init(type: InsightType, title: String, description: String, actionable: Bool) {
        self.type = type
        self.title = title
        self.description = description
        self.actionable = actionable
    }
}

// MARK: - Daily Summary Generator

/// Generates comprehensive daily summary atoms
public final class DailySummaryGenerator: @unchecked Sendable {

    private let xpEngine: XPCalculationEngine
    private let badgeTracker: BadgeProgressTracker

    public init(
        xpEngine: XPCalculationEngine = XPCalculationEngine(),
        badgeTracker: BadgeProgressTracker = BadgeProgressTracker()
    ) {
        self.xpEngine = xpEngine
        self.badgeTracker = badgeTracker
    }

    // MARK: - Generate Daily Summary

    /// Generate a complete daily summary for the specified date
    public func generateDailySummary(
        db: Database,
        for date: Date,
        previousLevelState: CosmoLevelState,
        currentLevelState: CosmoLevelState,
        cronReport: DailyCronReport?
    ) throws -> Atom {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw SummaryError.invalidDate
        }

        // Gather XP events for the day
        let xpBreakdown = try gatherXPBreakdown(db: db, start: startOfDay, end: endOfDay)

        // Gather activity metrics
        let activities = try gatherActivityMetrics(db: db, start: startOfDay, end: endOfDay)

        // Gather health metrics
        let health = try gatherHealthMetrics(db: db, start: startOfDay, end: endOfDay)

        // Gather streak info
        let streaks = try gatherStreakInfo(db: db, date: date, cronReport: cronReport)

        // Gather badge info
        let badges = try gatherBadgeInfo(db: db, date: date, levelState: currentLevelState)

        // Gather quest completion
        let quests = try gatherQuestInfo(db: db, start: startOfDay, end: endOfDay)

        // Calculate level changes
        let levelChanges = calculateLevelChanges(
            previous: previousLevelState,
            current: currentLevelState
        )

        // Calculate NELO changes
        let neloChanges = calculateNELOChanges(
            previous: previousLevelState,
            current: currentLevelState
        )

        // Generate AI insights
        let insights = generateInsights(
            activities: activities,
            health: health,
            streaks: streaks,
            xpBreakdown: xpBreakdown
        )

        // Generate tomorrow's focus
        let tomorrowFocus = generateTomorrowFocus(
            streaks: streaks,
            activities: activities,
            health: health
        )

        // Generate motivational note
        let motivationalNote = generateMotivationalNote(
            xp: xpBreakdown.total,
            levelUps: levelChanges.levelUps,
            badges: badges.unlocked
        )

        // Create metadata
        let metadata = DailySummaryMetadata(
            summaryDate: date,
            totalXPGained: xpBreakdown.total,
            dimensionXP: xpBreakdown.byDimension,
            bonusXPGained: xpBreakdown.bonus,
            bonusReason: xpBreakdown.bonusReason,
            streakMultiplier: xpBreakdown.multiplier,
            previousCosmoIndex: previousLevelState.cosmoIndex,
            newCosmoIndex: currentLevelState.cosmoIndex,
            cosmoIndexProgress: levelChanges.progress,
            xpToNextLevel: levelChanges.xpToNext,
            levelUps: levelChanges.levelUps,
            previousNELO: previousLevelState.overallNelo,
            newNELO: currentLevelState.overallNelo,
            neloChange: neloChanges.overall,
            neloTrend: neloChanges.trend,
            dimensionNELOChanges: neloChanges.byDimension,
            tasksCompleted: activities.tasksCompleted,
            deepWorkMinutes: activities.deepWorkMinutes,
            wordsWritten: activities.wordsWritten,
            journalEntries: activities.journalEntries,
            researchItems: activities.researchItems,
            ideasCaptured: activities.ideasCaptured,
            avgHRV: health.avgHRV,
            sleepHours: health.sleepHours,
            sleepQuality: health.sleepQuality,
            readinessScore: health.readinessScore,
            workoutsCompleted: health.workoutsCompleted,
            currentOverallStreak: streaks.overallStreak,
            streaksExtended: streaks.extended,
            streaksBroken: streaks.broken,
            streaksAtRisk: streaks.atRisk,
            badgesUnlocked: badges.unlocked,
            nearestBadges: badges.nearest,
            questsCompleted: quests.completed,
            totalQuests: quests.total,
            questXPEarned: quests.xpEarned,
            insights: insights,
            tomorrowFocus: tomorrowFocus,
            motivationalNote: motivationalNote
        )

        // Create summary atom
        let title = formatSummaryTitle(date: date, xp: xpBreakdown.total)
        let body = formatSummaryBody(metadata: metadata)

        let metadataJSON = try JSONEncoder().encode(metadata)
        let metadataString = String(data: metadataJSON, encoding: .utf8)

        return Atom(
            id: nil,
            uuid: UUID().uuidString,
            type: .dailySummary,
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

    // MARK: - Data Gathering

    private struct XPBreakdown {
        let total: Int
        let byDimension: [String: Int]
        let bonus: Int
        let bonusReason: String?
        let multiplier: Double
    }

    private func gatherXPBreakdown(db: Database, start: Date, end: Date) throws -> XPBreakdown {
        // Fetch XP events from the day
        let xpEvents = try Row.fetchAll(db, sql: """
            SELECT metadata FROM atoms
            WHERE type = 'xp_event'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end])

        var total = 0
        var byDimension: [String: Int] = [
            "cognitive": 0,
            "creative": 0,
            "physiological": 0,
            "behavioral": 0,
            "knowledge": 0,
            "reflection": 0
        ]
        var bonus = 0
        var bonusReason: String?
        var multiplier: Double = 1.0

        for row in xpEvents {
            if let metadataString = row["metadata"] as? String,
               let data = metadataString.data(using: .utf8),
               let meta = try? JSONDecoder().decode(XPEventMetadata.self, from: data) {
                total += meta.amount
                let dimension = meta.dimension
                byDimension[dimension, default: 0] += meta.amount

                if let mult = meta.multiplier, mult > multiplier {
                    multiplier = mult
                }

                if let bonusAmt = meta.bonusAmount, bonusAmt > 0 {
                    bonus += bonusAmt
                    bonusReason = meta.bonusReason
                }
            }
        }

        return XPBreakdown(
            total: total,
            byDimension: byDimension,
            bonus: bonus,
            bonusReason: bonusReason,
            multiplier: multiplier
        )
    }

    private struct XPEventMetadata: Codable {
        let amount: Int
        let dimension: String
        let multiplier: Double?
        let bonusAmount: Int?
        let bonusReason: String?
    }

    private struct ActivityMetrics {
        let tasksCompleted: Int
        let deepWorkMinutes: Int
        let wordsWritten: Int
        let journalEntries: Int
        let researchItems: Int
        let ideasCaptured: Int
    }

    private func gatherActivityMetrics(db: Database, start: Date, end: Date) throws -> ActivityMetrics {
        // Tasks completed
        let tasks = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'task'
            AND metadata LIKE '%"isCompleted":true%'
            AND updatedAt >= ? AND updatedAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        // Deep work minutes (from focus sessions)
        let deepWorkMinutes = try Int.fetchOne(db, sql: """
            SELECT COALESCE(SUM(
                CAST(json_extract(metadata, '$.durationMinutes') AS INTEGER)
            ), 0) FROM atoms
            WHERE type IN ('focus_session', 'deep_work_block')
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        // Words written
        let wordsWritten = try Int.fetchOne(db, sql: """
            SELECT COALESCE(SUM(
                CAST(json_extract(metadata, '$.wordCount') AS INTEGER)
            ), 0) FROM atoms
            WHERE type = 'writing_session'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        // Journal entries
        let journals = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'journal_entry'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        // Research items
        let research = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'research'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        // Ideas captured
        let ideas = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'idea'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        return ActivityMetrics(
            tasksCompleted: tasks,
            deepWorkMinutes: deepWorkMinutes,
            wordsWritten: wordsWritten,
            journalEntries: journals,
            researchItems: research,
            ideasCaptured: ideas
        )
    }

    private struct HealthMetrics {
        let avgHRV: Double?
        let sleepHours: Double?
        let sleepQuality: Double?
        let readinessScore: Double?
        let workoutsCompleted: Int
    }

    private func gatherHealthMetrics(db: Database, start: Date, end: Date) throws -> HealthMetrics {
        // Average HRV
        let avgHRV = try Double.fetchOne(db, sql: """
            SELECT AVG(CAST(json_extract(metadata, '$.hrvMs') AS REAL)) FROM atoms
            WHERE type = 'hrv_reading'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end])

        // Sleep data (from most recent sleep record)
        let sleepRow = try Row.fetchOne(db, sql: """
            SELECT metadata FROM atoms
            WHERE type = 'sleep_record'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
            ORDER BY createdAt DESC
            LIMIT 1
        """, arguments: [start, end])

        var sleepHours: Double?
        var sleepQuality: Double?

        if let row = sleepRow,
           let metadataString = row["metadata"] as? String,
           let data = metadataString.data(using: .utf8),
           let meta = try? JSONDecoder().decode(SleepMetadata.self, from: data) {
            sleepHours = meta.totalHours
            sleepQuality = meta.efficiency
        }

        // Readiness score
        let readinessScore = try Double.fetchOne(db, sql: """
            SELECT CAST(json_extract(metadata, '$.overallScore') AS REAL) FROM atoms
            WHERE type = 'readiness_score'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
            ORDER BY createdAt DESC
            LIMIT 1
        """, arguments: [start, end])

        // Workouts
        let workouts = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'workout'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        return HealthMetrics(
            avgHRV: avgHRV,
            sleepHours: sleepHours,
            sleepQuality: sleepQuality,
            readinessScore: readinessScore,
            workoutsCompleted: workouts
        )
    }

    private struct SleepMetadata: Codable {
        let totalHours: Double
        let efficiency: Double?
    }

    private struct StreakInfo {
        let overallStreak: Int
        let extended: [String]
        let broken: [String]
        let atRisk: [StreakAtRiskSummary]
    }

    private func gatherStreakInfo(db: Database, date: Date, cronReport: DailyCronReport?) throws -> StreakInfo {
        // Get current streak state
        let overallStreak = try Int.fetchOne(db, sql: """
            SELECT COALESCE(MAX(CAST(json_extract(metadata, '$.currentStreak') AS INTEGER)), 0)
            FROM atoms
            WHERE type = 'streak_event'
            AND isDeleted = 0
        """) ?? 0

        var extended: [String] = []
        var broken: [String] = []

        // Check cron report for streak changes
        if let report = cronReport {
            for result in report.jobResults where result.jobType == .streakCheck {
                for change in result.changes {
                    if change.changeType == "streak_broken",
                       let dimension = change.dimension {
                        broken.append(dimension)
                    } else if change.changeType == "streak_extended",
                              let dimension = change.dimension {
                        extended.append(dimension)
                    }
                }
            }
        }

        // Identify at-risk streaks (streaks that need action today)
        var atRisk: [StreakAtRiskSummary] = []
        let dimensions = ["cognitive", "creative", "physiological", "behavioral", "knowledge", "reflection"]

        for dimension in dimensions {
            // Check if this dimension had activity today
            let hadActivity = try checkDimensionActivity(db: db, dimension: dimension, date: date)
            if !hadActivity {
                // Get current streak for this dimension
                let streak = try Int.fetchOne(db, sql: """
                    SELECT CAST(json_extract(metadata, '$.currentStreak') AS INTEGER)
                    FROM atoms
                    WHERE type = 'streak_event'
                    AND metadata LIKE ?
                    AND isDeleted = 0
                    ORDER BY createdAt DESC
                    LIMIT 1
                """, arguments: ["%\"\(dimension)\"%"]) ?? 0

                if streak > 0 {
                    let hoursRemaining = hoursUntilMidnight()
                    atRisk.append(StreakAtRiskSummary(
                        dimension: dimension,
                        currentStreak: streak,
                        hoursRemaining: hoursRemaining,
                        action: actionForDimension(dimension)
                    ))
                }
            }
        }

        return StreakInfo(
            overallStreak: overallStreak,
            extended: extended,
            broken: broken,
            atRisk: atRisk
        )
    }

    private func checkDimensionActivity(db: Database, dimension: String, date: Date) throws -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return false
        }

        let types: [String]
        switch dimension {
        case "cognitive": types = ["focus_session", "deep_work_block", "task"]
        case "creative": types = ["idea", "content"]
        case "physiological": types = ["hrv_reading", "workout", "sleep_record"]
        case "behavioral": types = ["task", "habit_completion"]
        case "knowledge": types = ["research", "connection"]
        case "reflection": types = ["journal_entry"]
        default: types = []
        }

        let typeList = types.map { "'\($0)'" }.joined(separator: ", ")
        let count = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type IN (\(typeList))
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        return count > 0
    }

    private func hoursUntilMidnight() -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
            return 24
        }
        let midnight = calendar.startOfDay(for: tomorrow)
        let seconds = midnight.timeIntervalSince(now)
        return max(0, Int(seconds / 3600))
    }

    private func actionForDimension(_ dimension: String) -> String {
        switch dimension {
        case "cognitive": return "Complete a deep work block"
        case "creative": return "Create or refine content"
        case "physiological": return "Check your readiness or log workout"
        case "behavioral": return "Complete a task"
        case "knowledge": return "Add research or make connections"
        case "reflection": return "Write a journal entry"
        default: return "Complete related activity"
        }
    }

    private struct BadgeInfo {
        let unlocked: [BadgeUnlockSummary]
        let nearest: [NearBadgeSummary]
    }

    private func gatherBadgeInfo(db: Database, date: Date, levelState: CosmoLevelState) throws -> BadgeInfo {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return BadgeInfo(unlocked: [], nearest: [])
        }

        // Recently unlocked badges
        let badgeRows = try Row.fetchAll(db, sql: """
            SELECT metadata FROM atoms
            WHERE type = 'badge_unlocked'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end])

        var unlocked: [BadgeUnlockSummary] = []
        for row in badgeRows {
            if let metadataString = row["metadata"] as? String,
               let data = metadataString.data(using: .utf8),
               let meta = try? JSONDecoder().decode(BadgeUnlockMetadata.self, from: data) {
                unlocked.append(BadgeUnlockSummary(
                    badgeId: meta.badgeId,
                    name: meta.badgeName,
                    tier: meta.badgeTier,
                    xpReward: meta.xpReward
                ))
            }
        }

        // Nearest badges (from badge tracker)
        let context = try badgeTracker.buildContext(db: db, levelState: levelState)
        let nearestBadges = badgeTracker.nextAchievableBadges(context: context, limit: 3)

        let nearest = nearestBadges.map { badge in
            NearBadgeSummary(
                badgeId: badge.badgeId,
                name: badge.badgeName,
                progress: badge.overallProgress,
                remainingDescription: formatRemainingRequirements(badge.requirements)
            )
        }

        return BadgeInfo(unlocked: unlocked, nearest: nearest)
    }

    private func formatRemainingRequirements(_ requirements: [RequirementProgress]) -> String {
        let incomplete = requirements.filter { $0.progress < 1.0 }
        guard !incomplete.isEmpty else { return "Almost there!" }

        let descriptions = incomplete.prefix(2).map { req in
            let remaining = max(0, Int(req.targetValue - req.currentValue))
            return "\(remaining) more \(req.description)"
        }
        return descriptions.joined(separator: ", ")
    }

    private struct BadgeUnlockMetadata: Codable {
        let badgeId: String
        let badgeName: String
        let badgeTier: String
        let xpReward: Int
    }

    private struct QuestInfo {
        let completed: Int
        let total: Int
        let xpEarned: Int
    }

    private func gatherQuestInfo(db: Database, start: Date, end: Date) throws -> QuestInfo {
        // Count completed quests
        let completed = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'daily_quest'
            AND metadata LIKE '%"isComplete":true%'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        // Total quests for the day
        let total = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type = 'daily_quest'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        // XP earned from quests
        let xp = try Int.fetchOne(db, sql: """
            SELECT COALESCE(SUM(CAST(json_extract(metadata, '$.xpReward') AS INTEGER)), 0)
            FROM atoms
            WHERE type = 'daily_quest'
            AND metadata LIKE '%"isComplete":true%'
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [start, end]) ?? 0

        return QuestInfo(completed: completed, total: total, xpEarned: xp)
    }

    // MARK: - Calculations

    private struct LevelChanges {
        let levelUps: [LevelUpSummary]
        let progress: Double
        let xpToNext: Int
    }

    private func calculateLevelChanges(
        previous: CosmoLevelState,
        current: CosmoLevelState
    ) -> LevelChanges {
        var levelUps: [LevelUpSummary] = []

        // Check overall CI level up
        if current.cosmoIndex > previous.cosmoIndex {
            levelUps.append(LevelUpSummary(
                dimension: "overall",
                previousLevel: previous.cosmoIndex,
                newLevel: current.cosmoIndex,
                title: titleForLevel(current.cosmoIndex)
            ))
        }

        // Check dimension level ups
        let dimensionPairs: [(String, Int, Int)] = [
            ("cognitive", previous.cognitiveLevel, current.cognitiveLevel),
            ("creative", previous.creativeLevel, current.creativeLevel),
            ("physiological", previous.physiologicalLevel, current.physiologicalLevel),
            ("behavioral", previous.behavioralLevel, current.behavioralLevel),
            ("knowledge", previous.knowledgeLevel, current.knowledgeLevel),
            ("reflection", previous.reflectionLevel, current.reflectionLevel)
        ]

        for (name, prev, curr) in dimensionPairs {
            if curr > prev {
                levelUps.append(LevelUpSummary(
                    dimension: name,
                    previousLevel: prev,
                    newLevel: curr,
                    title: nil
                ))
            }
        }

        let progress = XPCalculationEngine.progressInLevel(totalXP: current.totalXPEarned)
        let xpToNext = XPCalculationEngine.xpToNextLevel(totalXP: current.totalXPEarned)

        return LevelChanges(levelUps: levelUps, progress: progress, xpToNext: xpToNext)
    }

    private func titleForLevel(_ level: Int) -> String? {
        switch level {
        case 1..<10: return "Novice"
        case 10..<25: return "Apprentice"
        case 25..<50: return "Practitioner"
        case 50..<75: return "Expert"
        case 75..<100: return "Master"
        case 100...: return "Grandmaster"
        default: return nil
        }
    }

    private struct NELOChanges {
        let overall: Int
        let trend: String
        let byDimension: [String: Int]
    }

    private func calculateNELOChanges(
        previous: CosmoLevelState,
        current: CosmoLevelState
    ) -> NELOChanges {
        // Calculate overall NELO as average of all dimensions
        let currentOverall = (current.cognitiveNELO + current.creativeNELO + current.physiologicalNELO +
                              current.behavioralNELO + current.knowledgeNELO + current.reflectionNELO) / 6
        let previousOverall = (previous.cognitiveNELO + previous.creativeNELO + previous.physiologicalNELO +
                               previous.behavioralNELO + previous.knowledgeNELO + previous.reflectionNELO) / 6
        let overall = currentOverall - previousOverall

        let trend: String
        if overall > 10 {
            trend = "up"
        } else if overall < -10 {
            trend = "down"
        } else {
            trend = "stable"
        }

        let byDimension: [String: Int] = [
            "cognitive": current.cognitiveNELO - previous.cognitiveNELO,
            "creative": current.creativeNELO - previous.creativeNELO,
            "physiological": current.physiologicalNELO - previous.physiologicalNELO,
            "behavioral": current.behavioralNELO - previous.behavioralNELO,
            "knowledge": current.knowledgeNELO - previous.knowledgeNELO,
            "reflection": current.reflectionNELO - previous.reflectionNELO
        ]

        return NELOChanges(overall: overall, trend: trend, byDimension: byDimension)
    }

    // MARK: - Insight Generation

    private func generateInsights(
        activities: ActivityMetrics,
        health: HealthMetrics,
        streaks: StreakInfo,
        xpBreakdown: XPBreakdown
    ) -> [DailyInsight] {
        var insights: [DailyInsight] = []

        // Deep work achievement
        if activities.deepWorkMinutes >= 240 {
            insights.append(DailyInsight(
                type: .achievement,
                title: "Deep Work Champion",
                description: "You completed \(activities.deepWorkMinutes / 60)+ hours of deep work today!",
                actionable: false
            ))
        } else if activities.deepWorkMinutes >= 120 {
            insights.append(DailyInsight(
                type: .achievement,
                title: "Focused Day",
                description: "Great focus with \(activities.deepWorkMinutes) minutes of deep work.",
                actionable: false
            ))
        }

        // Writing milestone
        if activities.wordsWritten >= 2000 {
            insights.append(DailyInsight(
                type: .celebration,
                title: "Prolific Writer",
                description: "\(activities.wordsWritten) words written - Stephen King pace!",
                actionable: false
            ))
        }

        // HRV insight
        if let hrv = health.avgHRV {
            if hrv >= 100 {
                insights.append(DailyInsight(
                    type: .achievement,
                    title: "Elite HRV",
                    description: "Your \(Int(hrv))ms HRV indicates excellent recovery.",
                    actionable: false
                ))
            } else if hrv < 40 {
                insights.append(DailyInsight(
                    type: .warning,
                    title: "Recovery Needed",
                    description: "Low HRV (\(Int(hrv))ms) suggests focusing on rest.",
                    actionable: true
                ))
            }
        }

        // Streak warnings
        if !streaks.atRisk.isEmpty {
            let atRiskNames = streaks.atRisk.map { $0.dimension }.joined(separator: ", ")
            insights.append(DailyInsight(
                type: .warning,
                title: "Streaks at Risk",
                description: "\(atRiskNames) streaks need activity to continue.",
                actionable: true
            ))
        }

        // Pattern detection
        if xpBreakdown.byDimension["reflection"] == 0 && activities.journalEntries == 0 {
            insights.append(DailyInsight(
                type: .suggestion,
                title: "Missing Reflection",
                description: "Consider adding journaling to close the day mindfully.",
                actionable: true
            ))
        }

        return insights
    }

    private func generateTomorrowFocus(
        streaks: StreakInfo,
        activities: ActivityMetrics,
        health: HealthMetrics
    ) -> String? {
        // If there are at-risk streaks, focus on those
        if let firstAtRisk = streaks.atRisk.first {
            return "Protect your \(firstAtRisk.currentStreak)-day \(firstAtRisk.dimension) streak"
        }

        // If low deep work, suggest focus
        if activities.deepWorkMinutes < 60 {
            return "Aim for at least 60 minutes of deep work"
        }

        // If readiness is high, suggest intense work
        if let readiness = health.readinessScore, readiness >= 85 {
            return "High readiness - tackle your hardest task"
        }

        // Default
        return "Maintain your momentum with consistent progress"
    }

    private func generateMotivationalNote(
        xp: Int,
        levelUps: [LevelUpSummary],
        badges: [BadgeUnlockSummary]
    ) -> String? {
        if !levelUps.isEmpty {
            return "Congratulations on leveling up! Your consistency is paying off."
        }

        if !badges.isEmpty {
            return "New badge unlocked! Each achievement marks your growth."
        }

        if xp >= 500 {
            return "Outstanding day! You're building powerful momentum."
        }

        if xp >= 200 {
            return "Solid progress today. Keep showing up."
        }

        return "Every day you show up matters. Progress compounds."
    }

    // MARK: - Formatting

    private func formatSummaryTitle(date: Date, xp: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return "\(formatter.string(from: date)) • +\(xp) XP"
    }

    private func formatSummaryBody(metadata: DailySummaryMetadata) -> String {
        var lines: [String] = []

        lines.append("## Daily Summary")
        lines.append("")
        lines.append("**XP Earned:** +\(metadata.totalXPGained)")
        if metadata.streakMultiplier > 1.0 {
            lines.append("**Streak Multiplier:** \(String(format: "%.2fx", metadata.streakMultiplier))")
        }
        lines.append("")

        lines.append("### Activity")
        lines.append("- Tasks: \(metadata.tasksCompleted)")
        lines.append("- Deep Work: \(metadata.deepWorkMinutes) min")
        lines.append("- Words: \(metadata.wordsWritten)")
        lines.append("")

        if metadata.avgHRV != nil || metadata.sleepHours != nil {
            lines.append("### Health")
            if let hrv = metadata.avgHRV {
                lines.append("- HRV: \(Int(hrv))ms")
            }
            if let sleep = metadata.sleepHours {
                lines.append("- Sleep: \(String(format: "%.1f", sleep))h")
            }
            if let readiness = metadata.readinessScore {
                lines.append("- Readiness: \(Int(readiness))%")
            }
            lines.append("")
        }

        if !metadata.levelUps.isEmpty {
            lines.append("### Level Ups")
            for levelUp in metadata.levelUps {
                lines.append("- \(levelUp.dimension.capitalized): \(levelUp.previousLevel) → \(levelUp.newLevel)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Errors

enum SummaryError: Error {
    case invalidDate
    case missingLevelState
}

// Note: AtomType.dailySummary already exists as a case in the enum
