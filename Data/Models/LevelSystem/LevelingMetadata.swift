// CosmoOS/Data/Models/LevelSystem/LevelingMetadata.swift
// Metadata structures for the Cosmo Level System
// Supports XP events, level updates, streaks, badges, and dimension snapshots

import Foundation

// MARK: - Level Types

/// Type of level (Cosmo Index vs Neuro-ELO)
enum LevelType: String, Codable, Sendable {
    case cosmoIndex = "ci"    // Permanent, only increases
    case neuroELO = "nelo"    // Dynamic, can rise and fall
}

// MARK: - Trend Direction

/// Direction of progress or change
public enum Trend: String, Codable, Sendable {
    case improving
    case stable
    case declining

    // Aliases for UI compatibility
    case up = "up"
    case down = "down"

    /// Initialize from numeric change
    init(change: Double, threshold: Double = 0.05) {
        if change > threshold {
            self = .improving
        } else if change < -threshold {
            self = .declining
        } else {
            self = .stable
        }
    }

    /// Normalize to canonical form for comparison
    var normalized: Trend {
        switch self {
        case .up: return .improving
        case .down: return .declining
        default: return self
        }
    }
}

// MARK: - XP Event Metadata

/// Metadata for xpEvent atoms - tracks every XP gain
struct XPEventMetadata: Codable, Sendable {
    /// Which dimension this XP applies to
    let dimension: LevelDimension

    /// Amount of XP earned
    let xpAmount: Int

    /// Base XP before multipliers
    let baseXP: Int

    /// What action triggered this XP (e.g., "task_completed", "deep_work_block")
    let source: String

    /// UUID of the atom that caused this XP gain
    let sourceAtomUUID: String?

    /// Multiplier applied (from streaks, bonuses)
    let multiplier: Double

    /// Type of bonus applied (if any)
    let bonusType: XPBonusType?

    /// When this XP was earned
    let timestamp: Date

    init(
        dimension: LevelDimension,
        xpAmount: Int,
        baseXP: Int,
        source: String,
        sourceAtomUUID: String? = nil,
        multiplier: Double = 1.0,
        bonusType: XPBonusType? = nil,
        timestamp: Date = Date()
    ) {
        self.dimension = dimension
        self.xpAmount = xpAmount
        self.baseXP = baseXP
        self.source = source
        self.sourceAtomUUID = sourceAtomUUID
        self.multiplier = multiplier
        self.bonusType = bonusType
        self.timestamp = timestamp
    }
}

/// Types of XP bonuses (variable ratio rewards)
public enum XPBonusType: String, Codable, Sendable {
    case streakBonus = "streak"           // From maintaining streaks
    case luckyBonus = "lucky"             // 15% chance, 1.25x
    case superBonus = "super"             // 10% chance, 1.5x
    case megaBonus = "mega"               // 4% chance, 2.0x
    case jackpot = "jackpot"              // 1% chance, 3.0x
    case firstOfDay = "first_of_day"      // First action of the day
    case perfectDay = "perfect_day"       // All quests completed
    case dimensionMilestone = "milestone" // Hit a level milestone

    var displayName: String {
        switch self {
        case .streakBonus: return "Streak Bonus"
        case .luckyBonus: return "Lucky Bonus!"
        case .superBonus: return "Super Bonus!"
        case .megaBonus: return "MEGA BONUS!"
        case .jackpot: return "JACKPOT!"
        case .firstOfDay: return "First of the Day"
        case .perfectDay: return "Perfect Day"
        case .dimensionMilestone: return "Milestone"
        }
    }

    var multiplier: Double {
        switch self {
        case .streakBonus: return 1.0      // Variable based on streak
        case .luckyBonus: return 1.25
        case .superBonus: return 1.5
        case .megaBonus: return 2.0
        case .jackpot: return 3.0
        case .firstOfDay: return 1.1
        case .perfectDay: return 1.5
        case .dimensionMilestone: return 2.0
        }
    }
}

// MARK: - Level Update Metadata

/// Metadata for levelUpdate atoms - tracks CI and NELO level changes
struct LevelUpdateMetadata: Codable, Sendable {
    /// Which dimension this update applies to
    let dimension: LevelDimension

    /// Previous level
    let previousLevel: Int

    /// New level after update
    let newLevel: Int

    /// Type of level (CI or NELO)
    let levelType: LevelType

    /// XP that triggered this level change
    let triggeringXP: Int

    /// Total XP at time of level up
    let totalXP: Int

    /// XP required for the next level
    let xpToNextLevel: Int

    /// Whether this was a regression (for NELO only)
    let isRegression: Bool

    /// Timestamp of level change
    let timestamp: Date

    init(
        dimension: LevelDimension,
        previousLevel: Int,
        newLevel: Int,
        levelType: LevelType,
        triggeringXP: Int,
        totalXP: Int,
        xpToNextLevel: Int,
        timestamp: Date = Date()
    ) {
        self.dimension = dimension
        self.previousLevel = previousLevel
        self.newLevel = newLevel
        self.levelType = levelType
        self.triggeringXP = triggeringXP
        self.totalXP = totalXP
        self.xpToNextLevel = xpToNextLevel
        self.isRegression = newLevel < previousLevel
        self.timestamp = timestamp
    }
}

// MARK: - Streak Event Metadata

/// Metadata for streakEvent atoms - tracks streak milestones
struct StreakEventMetadata: Codable, Sendable {
    /// Type of streak
    let streakType: StreakType

    /// Current streak count
    let currentStreak: Int

    /// Previous streak count
    let previousStreak: Int

    /// Whether this is a new personal record
    let isNewRecord: Bool

    /// Previous record (if broken)
    let previousRecord: Int?

    /// Multiplier unlocked at this streak level
    let multiplierUnlocked: Double?

    /// Associated dimension (if any)
    let dimension: LevelDimension?

    /// Timestamp
    let timestamp: Date

    init(
        streakType: StreakType,
        currentStreak: Int,
        previousStreak: Int,
        isNewRecord: Bool = false,
        previousRecord: Int? = nil,
        multiplierUnlocked: Double? = nil,
        dimension: LevelDimension? = nil,
        timestamp: Date = Date()
    ) {
        self.streakType = streakType
        self.currentStreak = currentStreak
        self.previousStreak = previousStreak
        self.isNewRecord = isNewRecord
        self.previousRecord = previousRecord
        self.multiplierUnlocked = multiplierUnlocked
        self.dimension = dimension
        self.timestamp = timestamp
    }
}

/// Types of streaks that can be tracked
enum StreakType: String, Codable, CaseIterable, Sendable {
    // Activity-based
    case deepWork = "deep_work"                   // Daily deep work blocks
    case writing = "writing"                      // Daily writing sessions
    case taskCompletion = "task_completion"       // Daily task completion
    case journaling = "journaling"                // Daily journal entries

    // Health-based
    case sleepConsistency = "sleep_consistency"   // Consistent sleep schedule
    case workouts = "workouts"                    // Regular workouts
    case hrvImprovement = "hrv_improvement"       // HRV trending up

    // System-wide
    case routine = "routine"                      // Full routine completion
    case app = "app"                              // Daily app usage

    var displayName: String {
        switch self {
        case .deepWork: return "Deep Work"
        case .writing: return "Writing"
        case .taskCompletion: return "Task Completion"
        case .journaling: return "Journaling"
        case .sleepConsistency: return "Sleep Consistency"
        case .workouts: return "Workouts"
        case .hrvImprovement: return "HRV Improvement"
        case .routine: return "Routine"
        case .app: return "Daily Usage"
        }
    }

    var iconName: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .writing: return "pencil.line"
        case .taskCompletion: return "checkmark.circle"
        case .journaling: return "book"
        case .sleepConsistency: return "bed.double"
        case .workouts: return "figure.run"
        case .hrvImprovement: return "heart.text.square"
        case .routine: return "repeat"
        case .app: return "flame"
        }
    }

    /// Related dimension for this streak type
    var dimension: LevelDimension? {
        switch self {
        case .deepWork, .writing, .taskCompletion:
            return .cognitive
        case .journaling:
            return .reflection
        case .sleepConsistency, .workouts, .hrvImprovement:
            return .physiological
        case .routine, .app:
            return .behavioral
        }
    }
}

// MARK: - Badge System
// Note: BadgeCategory and BadgeTier are defined in BadgeDefinitionSystem.swift

/// Time window for badge requirements
enum DateWindow: Codable, Sendable {
    case days(Int)
    case weeks(Int)
    case months(Int)
    case lifetime

    var displayName: String {
        switch self {
        case .days(let n): return "\(n) day\(n == 1 ? "" : "s")"
        case .weeks(let n): return "\(n) week\(n == 1 ? "" : "s")"
        case .months(let n): return "\(n) month\(n == 1 ? "" : "s")"
        case .lifetime: return "Lifetime"
        }
    }

    /// Convert to DateInterval from now
    func toDateInterval(from date: Date = Date()) -> DateInterval? {
        let calendar = Calendar.current
        let startDate: Date?

        switch self {
        case .days(let n):
            startDate = calendar.date(byAdding: .day, value: -n, to: date)
        case .weeks(let n):
            startDate = calendar.date(byAdding: .weekOfYear, value: -n, to: date)
        case .months(let n):
            startDate = calendar.date(byAdding: .month, value: -n, to: date)
        case .lifetime:
            return nil  // No limit
        }

        guard let start = startDate else { return nil }
        return DateInterval(start: start, end: date)
    }
}

/// Metadata for badgeUnlocked atoms
struct BadgeUnlockedMetadata: Codable, Sendable {
    /// Unique badge identifier
    let badgeId: String

    /// Badge category
    let badgeCategory: BadgeCategory

    /// Badge tier/rarity
    let badgeTier: BadgeTier

    /// When the badge was unlocked
    let unlockedAt: Date

    /// Metric that triggered the unlock
    let triggerMetric: String

    /// Value that triggered the unlock
    let triggerValue: Double

    /// XP reward granted
    let xpReward: Int

    /// Whether this was a secret badge
    let wasSecret: Bool

    init(
        badgeId: String,
        badgeCategory: BadgeCategory,
        badgeTier: BadgeTier,
        unlockedAt: Date = Date(),
        triggerMetric: String,
        triggerValue: Double,
        xpReward: Int,
        wasSecret: Bool = false
    ) {
        self.badgeId = badgeId
        self.badgeCategory = badgeCategory
        self.badgeTier = badgeTier
        self.unlockedAt = unlockedAt
        self.triggerMetric = triggerMetric
        self.triggerValue = triggerValue
        self.xpReward = xpReward
        self.wasSecret = wasSecret
    }
}

// MARK: - Dimension Snapshot Metadata

/// State of a single dimension at a point in time
struct DimensionState: Codable, Sendable {
    /// Current level (1-100)
    let level: Int

    /// XP within current level
    let xp: Int

    /// XP needed for next level
    let xpToNextLevel: Int

    /// Current NELO rating
    let nelo: Int

    /// NELO change from previous snapshot
    let neloChange: Int

    /// Trend direction
    let trend: Trend

    /// Total lifetime XP in this dimension
    let totalXP: Int

    /// Days since last activity in this dimension
    let daysSinceActive: Int

    init(
        level: Int,
        xp: Int,
        xpToNextLevel: Int,
        nelo: Int,
        neloChange: Int = 0,
        trend: Trend = .stable,
        totalXP: Int = 0,
        daysSinceActive: Int = 0
    ) {
        self.level = level
        self.xp = xp
        self.xpToNextLevel = xpToNextLevel
        self.nelo = nelo
        self.neloChange = neloChange
        self.trend = trend
        self.totalXP = totalXP
        self.daysSinceActive = daysSinceActive
    }
}

/// Metadata for dimensionSnapshot atoms - daily capture of all dimension states
struct DimensionSnapshotMetadata: Codable, Sendable {
    /// Date of the snapshot
    let date: Date

    /// State of each dimension
    let cognitive: DimensionState
    let creative: DimensionState
    let physiological: DimensionState
    let behavioral: DimensionState
    let knowledge: DimensionState
    let reflection: DimensionState

    /// Overall Cosmo Index
    let overallCI: Int

    /// Overall Neuro-ELO (weighted average)
    let overallNELO: Int

    /// Total XP earned on this date
    let dailyXP: Int

    /// Badges unlocked on this date
    let badgesUnlocked: [String]

    /// Active streaks at snapshot time
    let activeStreaks: [StreakSnapshot]

    init(
        date: Date,
        cognitive: DimensionState,
        creative: DimensionState,
        physiological: DimensionState,
        behavioral: DimensionState,
        knowledge: DimensionState,
        reflection: DimensionState,
        overallCI: Int,
        overallNELO: Int,
        dailyXP: Int = 0,
        badgesUnlocked: [String] = [],
        activeStreaks: [StreakSnapshot] = []
    ) {
        self.date = date
        self.cognitive = cognitive
        self.creative = creative
        self.physiological = physiological
        self.behavioral = behavioral
        self.knowledge = knowledge
        self.reflection = reflection
        self.overallCI = overallCI
        self.overallNELO = overallNELO
        self.dailyXP = dailyXP
        self.badgesUnlocked = badgesUnlocked
        self.activeStreaks = activeStreaks
    }

    /// Get dimension state by dimension type
    func state(for dimension: LevelDimension) -> DimensionState {
        switch dimension {
        case .cognitive: return cognitive
        case .creative: return creative
        case .physiological: return physiological
        case .behavioral: return behavioral
        case .knowledge: return knowledge
        case .reflection: return reflection
        }
    }
}

/// Snapshot of a streak at a point in time
struct StreakSnapshot: Codable, Sendable {
    let streakType: StreakType
    let currentStreak: Int
    let isAtRisk: Bool       // Will break if not continued today

    init(streakType: StreakType, currentStreak: Int, isAtRisk: Bool = false) {
        self.streakType = streakType
        self.currentStreak = currentStreak
        self.isAtRisk = isAtRisk
    }
}

// MARK: - NELO Data Point

/// Historical NELO data point for tracking changes over time
struct NELODataPoint: Codable, Sendable {
    let date: Date
    let nelo: Int
    let change: Int
    let triggeredBy: String  // Description of what caused the change

    init(date: Date, nelo: Int, change: Int, triggeredBy: String) {
        self.date = date
        self.nelo = nelo
        self.change = change
        self.triggeredBy = triggeredBy
    }
}

// Note: DailySummaryMetadata is now defined in DailySummaryGenerator.swift
// Note: WeeklySummaryMetadata is now defined in WeeklySummaryGenerator.swift

// MARK: - Legacy Weekly Summary Metadata

/// Legacy metadata for weeklySummary atoms (kept for backwards compatibility)
struct LegacyWeeklySummaryMetadata: Codable, Sendable {
    /// Start date of the week
    let weekStartDate: Date

    /// End date of the week
    let weekEndDate: Date

    /// Total XP earned this week
    let totalXP: Int

    /// XP comparison to previous week
    let xpChangeFromLastWeek: Int

    /// Average daily XP
    let avgDailyXP: Double

    /// Best day (by XP)
    let bestDayDate: Date?
    let bestDayXP: Int

    /// Dimension level changes
    let dimensionChanges: [String: DimensionWeeklyChange]

    /// Overall NELO change
    let neloChange: Int

    /// Badges unlocked this week
    let badgesUnlocked: [String]

    /// Longest streak reached
    let longestStreakReached: Int
    let longestStreakType: StreakType?

    /// Insights about the week
    let weeklyInsights: [String]

    /// Goals for next week
    let nextWeekGoals: [String]

    init(
        weekStartDate: Date,
        weekEndDate: Date,
        totalXP: Int,
        xpChangeFromLastWeek: Int = 0,
        avgDailyXP: Double = 0,
        bestDayDate: Date? = nil,
        bestDayXP: Int = 0,
        dimensionChanges: [String: DimensionWeeklyChange] = [:],
        neloChange: Int = 0,
        badgesUnlocked: [String] = [],
        longestStreakReached: Int = 0,
        longestStreakType: StreakType? = nil,
        weeklyInsights: [String] = [],
        nextWeekGoals: [String] = []
    ) {
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.totalXP = totalXP
        self.xpChangeFromLastWeek = xpChangeFromLastWeek
        self.avgDailyXP = avgDailyXP
        self.bestDayDate = bestDayDate
        self.bestDayXP = bestDayXP
        self.dimensionChanges = dimensionChanges
        self.neloChange = neloChange
        self.badgesUnlocked = badgesUnlocked
        self.longestStreakReached = longestStreakReached
        self.longestStreakType = longestStreakType
        self.weeklyInsights = weeklyInsights
        self.nextWeekGoals = nextWeekGoals
    }
}

/// Weekly change summary for a dimension
struct DimensionWeeklyChange: Codable, Sendable {
    let dimension: LevelDimension
    let startLevel: Int
    let endLevel: Int
    let xpEarned: Int
    let neloChange: Int
    let trend: Trend

    var levelChange: Int {
        endLevel - startLevel
    }
}
