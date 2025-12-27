import Foundation
import GRDB

// MARK: - Streak Dimension

/// Dimension categories for streak tracking
public enum StreakDimension: String, Codable, CaseIterable, Sendable {
    case cognitive
    case creative
    case physiological
    case behavioral
    case knowledge
    case reflection
    case overall       // All dimensions combined

    public var displayName: String {
        switch self {
        case .cognitive: return "Cognitive"
        case .creative: return "Creative"
        case .physiological: return "Physiological"
        case .behavioral: return "Behavioral"
        case .knowledge: return "Knowledge"
        case .reflection: return "Reflection"
        case .overall: return "Overall"
        }
    }

    /// Atom types that count toward this dimension's streak
    public var qualifyingAtomTypes: Set<String> {
        switch self {
        case .cognitive:
            return ["focus_session", "focus_event", "cognitive_snapshot", "word_count_event"]
        case .creative:
            return ["idea", "ideaNote", "project", "creative_session"]
        case .physiological:
            return ["sleep_record", "hrv_reading", "workout", "recovery_score", "activity_ring"]
        case .behavioral:
            return ["task", "habit_completion", "routine_completed", "time_block"]
        case .knowledge:
            return ["book", "note", "article", "learning_session", "bookmark"]
        case .reflection:
            return ["journal_entry", "insight", "emotional_state", "reflection_session"]
        case .overall:
            // Overall includes all dimension-specific types
            return Set(StreakDimension.allCases.filter { $0 != .overall }.flatMap { $0.qualifyingAtomTypes })
        }
    }

    /// Minimum qualifying actions per day to count as active
    public var minimumDailyActions: Int {
        switch self {
        case .cognitive: return 1    // 1 focus session
        case .creative: return 1     // 1 idea or creative action
        case .physiological: return 1 // 1 health data point
        case .behavioral: return 1   // 1 task or habit
        case .knowledge: return 1    // 1 note or reading
        case .reflection: return 1   // 1 journal entry
        case .overall: return 3      // Activity in 3+ dimensions
        }
    }
}

// MARK: - Streak State

/// Current state of a streak
public struct StreakState: Codable, Sendable, Equatable {
    public let dimension: StreakDimension
    public let currentStreak: Int
    public let longestStreak: Int
    public let lastActiveDate: Date?
    public let streakStartDate: Date?
    public let totalActiveDays: Int
    public let currentMultiplier: Double
    public let freezesAvailable: Int
    public let freezesUsed: Int

    public init(
        dimension: StreakDimension,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        lastActiveDate: Date? = nil,
        streakStartDate: Date? = nil,
        totalActiveDays: Int = 0,
        currentMultiplier: Double = 1.0,
        freezesAvailable: Int = 0,
        freezesUsed: Int = 0
    ) {
        self.dimension = dimension
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastActiveDate = lastActiveDate
        self.streakStartDate = streakStartDate
        self.totalActiveDays = totalActiveDays
        self.currentMultiplier = currentMultiplier
        self.freezesAvailable = freezesAvailable
        self.freezesUsed = freezesUsed
    }

    public var isActive: Bool {
        currentStreak > 0
    }

    /// Check if streak is at risk (no activity today and last active was yesterday)
    public func isAtRisk(on date: Date = Date()) -> Bool {
        guard let lastActive = lastActiveDate else { return false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let lastActiveDay = calendar.startOfDay(for: lastActive)

        guard lastActiveDay != today else { return false }  // Already active today

        let daysDifference = calendar.dateComponents([.day], from: lastActiveDay, to: today).day ?? 0
        return daysDifference == 1  // Last active was yesterday
    }
}

// MARK: - Streak Event

/// Event that affects streak state
public struct StreakEvent: Codable, Sendable {
    public enum EventType: String, Codable, Sendable {
        case dayCompleted       // Day marked as active
        case streakIncremented  // Streak count increased
        case streakBroken       // Streak reset to 0
        case freezeUsed         // Freeze protection used
        case freezeEarned       // New freeze earned
        case milestoneReached   // Streak milestone reached
        case longestUpdated     // New longest streak record
    }

    public let id: String
    public let dimension: StreakDimension
    public let eventType: EventType
    public let timestamp: Date
    public let previousStreak: Int
    public let newStreak: Int
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        dimension: StreakDimension,
        eventType: EventType,
        timestamp: Date = Date(),
        previousStreak: Int,
        newStreak: Int,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.dimension = dimension
        self.eventType = eventType
        self.timestamp = timestamp
        self.previousStreak = previousStreak
        self.newStreak = newStreak
        self.metadata = metadata
    }
}

// MARK: - Streak Multiplier Tiers

/// XP multiplier tiers based on streak length
/// Based on habit formation research: 7 days (habit start), 21 days (habit forming),
/// 66 days (habit automatic), 365 days (lifestyle)
public struct StreakMultiplierTiers: Sendable {
    public static let tiers: [(days: Int, multiplier: Double, name: String)] = [
        (0, 1.0, "Starting"),
        (7, 1.1, "Week Warrior"),
        (14, 1.2, "Two-Week Titan"),
        (21, 1.3, "Habit Former"),
        (30, 1.4, "Monthly Master"),
        (60, 1.6, "Double Down"),
        (66, 1.7, "Habit Locked"),
        (90, 1.8, "Quarter Champion"),
        (180, 2.0, "Half-Year Hero"),
        (365, 2.5, "Year Legend"),
        (730, 2.75, "Two-Year Titan"),
        (1000, 3.0, "Millennium Mind")
    ]

    public static func multiplier(for days: Int) -> Double {
        for tier in tiers.reversed() {
            if days >= tier.days {
                return tier.multiplier
            }
        }
        return 1.0
    }

    public static func tierName(for days: Int) -> String {
        for tier in tiers.reversed() {
            if days >= tier.days {
                return tier.name
            }
        }
        return "Starting"
    }

    public static func nextTier(for days: Int) -> (days: Int, multiplier: Double, name: String)? {
        for tier in tiers {
            if days < tier.days {
                return tier
            }
        }
        return nil
    }

    public static func daysToNextTier(currentDays: Int) -> Int? {
        if let next = nextTier(for: currentDays) {
            return next.days - currentDays
        }
        return nil
    }
}

// MARK: - Streak Freeze System

/// Streak freeze protection system
/// Users can earn freezes through various achievements
public struct StreakFreezeSystem: Sendable {
    /// Maximum freezes that can be accumulated
    public static let maxFreezes: Int = 5

    /// How freezes are earned
    public enum FreezeSource: String, Codable, Sendable {
        case weekStreak       // Earned at 7-day streak
        case monthStreak      // Earned at 30-day streak
        case quarterStreak    // Earned at 90-day streak
        case perfectWeek      // 100% completion all dimensions
        case badgeEarned      // Certain badge tiers
        case purchase         // Future: in-app purchase
    }

    /// Freeze earning rules
    public static func freezesEarnedAt(streakDays: Int) -> Int {
        switch streakDays {
        case 7: return 1
        case 30: return 1
        case 90: return 2
        case 180: return 2
        case 365: return 3
        default: return 0
        }
    }
}

// MARK: - Streak Tracking Engine

/// Engine for tracking and managing streaks across all dimensions
public final class StreakTrackingEngine: Sendable {

    public init() {}

    // MARK: - Streak Calculation

    /// Calculate streak state for a dimension from database
    public func calculateStreakState(
        db: Database,
        dimension: StreakDimension,
        asOf date: Date = Date()
    ) throws -> StreakState {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        // Get all active dates for this dimension
        let activeDates = try getActiveDates(db: db, dimension: dimension)

        guard !activeDates.isEmpty else {
            return StreakState(dimension: dimension)
        }

        // Calculate current streak
        var currentStreak = 0
        var checkDate = today
        var streakStartDate: Date?
        var lastActiveDate: Date?

        // Check today and backwards
        while activeDates.contains(checkDate) || (currentStreak == 0 && activeDates.contains(calendar.date(byAdding: .day, value: -1, to: checkDate)!)) {
            if activeDates.contains(checkDate) {
                currentStreak += 1
                streakStartDate = checkDate
                if lastActiveDate == nil {
                    lastActiveDate = checkDate
                }
            }
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previousDay
        }

        // Calculate longest streak
        let longestStreak = calculateLongestStreak(activeDates: activeDates, calendar: calendar)

        // Get freeze data from cache
        let (freezesAvailable, freezesUsed) = try getFreezeData(db: db, dimension: dimension)

        // Calculate multiplier
        let multiplier = StreakMultiplierTiers.multiplier(for: currentStreak)

        return StreakState(
            dimension: dimension,
            currentStreak: currentStreak,
            longestStreak: max(longestStreak, currentStreak),
            lastActiveDate: lastActiveDate,
            streakStartDate: streakStartDate,
            totalActiveDays: activeDates.count,
            currentMultiplier: multiplier,
            freezesAvailable: freezesAvailable,
            freezesUsed: freezesUsed
        )
    }

    /// Get all dates with qualifying activity for a dimension
    private func getActiveDates(db: Database, dimension: StreakDimension) throws -> Set<Date> {
        let calendar = Calendar.current
        let atomTypes = dimension.qualifyingAtomTypes

        if dimension == .overall {
            // For overall, need activity in multiple dimensions per day
            return try getOverallActiveDates(db: db, calendar: calendar)
        }

        let placeholders = atomTypes.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT DISTINCT date(createdAt) as activeDate
            FROM atoms
            WHERE type IN (\(placeholders))
            AND isDeleted = 0
        """

        let dateStrings = try String.fetchAll(db, sql: sql, arguments: StatementArguments(Array(atomTypes)))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var dates: Set<Date> = []
        for dateString in dateStrings {
            if let date = dateFormatter.date(from: dateString) {
                dates.insert(calendar.startOfDay(for: date))
            }
        }

        return dates
    }

    /// Get dates with activity across multiple dimensions (for overall streak)
    private func getOverallActiveDates(db: Database, calendar: Calendar) throws -> Set<Date> {
        var dimensionActiveDates: [StreakDimension: Set<Date>] = [:]

        for dimension in StreakDimension.allCases where dimension != .overall {
            dimensionActiveDates[dimension] = try getActiveDates(db: db, dimension: dimension)
        }

        // Find dates with activity in 3+ dimensions
        var overallDates: Set<Date> = []
        let allDates = dimensionActiveDates.values.flatMap { $0 }
        let uniqueDates = Set(allDates)

        for date in uniqueDates {
            var activeCount = 0
            for (_, dates) in dimensionActiveDates {
                if dates.contains(date) {
                    activeCount += 1
                }
            }
            if activeCount >= 3 {
                overallDates.insert(date)
            }
        }

        return overallDates
    }

    /// Calculate longest streak from a set of active dates
    private func calculateLongestStreak(activeDates: Set<Date>, calendar: Calendar) -> Int {
        guard !activeDates.isEmpty else { return 0 }

        let sortedDates = activeDates.sorted()
        var longestStreak = 1
        var currentStreak = 1

        for i in 1..<sortedDates.count {
            let previousDate = sortedDates[i - 1]
            let currentDate = sortedDates[i]

            if let expectedNext = calendar.date(byAdding: .day, value: 1, to: previousDate),
               calendar.isDate(currentDate, inSameDayAs: expectedNext) {
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else {
                currentStreak = 1
            }
        }

        return longestStreak
    }

    /// Get freeze data from streak cache
    private func getFreezeData(db: Database, dimension: StreakDimension) throws -> (available: Int, used: Int) {
        let sql = """
            SELECT freezesAvailable, freezesUsed
            FROM cosmo_streak_cache
            WHERE dimension = ?
        """

        if let row = try Row.fetchOne(db, sql: sql, arguments: [dimension.rawValue]) {
            let available = row["freezesAvailable"] as? Int ?? 0
            let used = row["freezesUsed"] as? Int ?? 0
            return (available, used)
        }

        return (0, 0)
    }

    // MARK: - Streak Updates

    /// Record activity for a dimension (called when qualifying atom is created)
    public func recordActivity(
        db: Database,
        dimension: StreakDimension,
        atomId: String,
        date: Date = Date()
    ) throws -> StreakEvent? {
        let previousState = try calculateStreakState(db: db, dimension: dimension, asOf: date)
        let calendar = Calendar.current
        let activityDate = calendar.startOfDay(for: date)

        // Check if this is a new day of activity
        guard previousState.lastActiveDate == nil ||
              !calendar.isDate(previousState.lastActiveDate!, inSameDayAs: activityDate) else {
            // Already recorded activity for today
            return nil
        }

        // Check if this continues the streak or starts a new one
        let isConsecutive: Bool
        if let lastActive = previousState.lastActiveDate {
            let daysDifference = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastActive), to: activityDate).day ?? 0
            isConsecutive = daysDifference == 1
        } else {
            isConsecutive = false
        }

        let newStreak: Int
        let eventType: StreakEvent.EventType

        if isConsecutive {
            newStreak = previousState.currentStreak + 1
            eventType = .streakIncremented
        } else if previousState.currentStreak == 0 {
            newStreak = 1
            eventType = .dayCompleted
        } else {
            // Streak would have been broken - check for freeze
            if previousState.freezesAvailable > 0 {
                // Use freeze to maintain streak
                newStreak = previousState.currentStreak + 1
                eventType = .freezeUsed
                try useFreezeInCache(db: db, dimension: dimension)
            } else {
                // Streak broken, start new
                newStreak = 1
                eventType = .streakBroken
            }
        }

        // Update streak cache
        try updateStreakCache(
            db: db,
            dimension: dimension,
            currentStreak: newStreak,
            longestStreak: max(previousState.longestStreak, newStreak),
            lastActiveDate: activityDate
        )

        // Check for freeze earnings
        let freezesEarned = StreakFreezeSystem.freezesEarnedAt(streakDays: newStreak)
        if freezesEarned > 0 {
            try addFreezesToCache(db: db, dimension: dimension, count: freezesEarned)
        }

        var metadata: [String: String] = ["atomId": atomId]
        if eventType == .freezeUsed {
            metadata["freezeUsed"] = "true"
        }
        if newStreak > previousState.longestStreak {
            metadata["newRecord"] = "true"
        }

        return StreakEvent(
            dimension: dimension,
            eventType: eventType,
            previousStreak: previousState.currentStreak,
            newStreak: newStreak,
            metadata: metadata
        )
    }

    /// Check and break streaks that have expired (called daily by cron)
    public func checkExpiredStreaks(db: Database, asOf date: Date = Date()) throws -> [StreakEvent] {
        var events: [StreakEvent] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        for dimension in StreakDimension.allCases {
            let state = try calculateStreakState(db: db, dimension: dimension, asOf: date)

            guard state.currentStreak > 0, let lastActive = state.lastActiveDate else { continue }

            let lastActiveDay = calendar.startOfDay(for: lastActive)
            let daysDifference = calendar.dateComponents([.day], from: lastActiveDay, to: today).day ?? 0

            // If more than 1 day has passed without activity
            if daysDifference > 1 {
                // Check for freeze
                if state.freezesAvailable > 0 && daysDifference == 2 {
                    // Auto-use freeze for yesterday
                    try useFreezeInCache(db: db, dimension: dimension)

                    events.append(StreakEvent(
                        dimension: dimension,
                        eventType: .freezeUsed,
                        previousStreak: state.currentStreak,
                        newStreak: state.currentStreak,
                        metadata: ["autoUsed": "true"]
                    ))
                } else {
                    // Break the streak
                    try updateStreakCache(
                        db: db,
                        dimension: dimension,
                        currentStreak: 0,
                        longestStreak: state.longestStreak,
                        lastActiveDate: state.lastActiveDate
                    )

                    events.append(StreakEvent(
                        dimension: dimension,
                        eventType: .streakBroken,
                        previousStreak: state.currentStreak,
                        newStreak: 0,
                        metadata: ["daysMissed": String(daysDifference)]
                    ))
                }
            }
        }

        return events
    }

    // MARK: - Cache Management

    /// Update streak cache in database
    private func updateStreakCache(
        db: Database,
        dimension: StreakDimension,
        currentStreak: Int,
        longestStreak: Int,
        lastActiveDate: Date?
    ) throws {
        let sql = """
            INSERT INTO cosmo_streak_cache (dimension, currentStreak, longestStreak, lastActiveDate, updatedAt)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(dimension) DO UPDATE SET
                currentStreak = excluded.currentStreak,
                longestStreak = excluded.longestStreak,
                lastActiveDate = excluded.lastActiveDate,
                updatedAt = excluded.updatedAt
        """

        try db.execute(
            sql: sql,
            arguments: [dimension.rawValue, currentStreak, longestStreak, lastActiveDate, Date()]
        )
    }

    /// Use a freeze from cache
    private func useFreezeInCache(db: Database, dimension: StreakDimension) throws {
        let sql = """
            UPDATE cosmo_streak_cache
            SET freezesAvailable = freezesAvailable - 1,
                freezesUsed = freezesUsed + 1,
                updatedAt = ?
            WHERE dimension = ? AND freezesAvailable > 0
        """

        try db.execute(sql: sql, arguments: [Date(), dimension.rawValue])
    }

    /// Add freezes to cache
    private func addFreezesToCache(db: Database, dimension: StreakDimension, count: Int) throws {
        let sql = """
            UPDATE cosmo_streak_cache
            SET freezesAvailable = MIN(freezesAvailable + ?, ?),
                updatedAt = ?
            WHERE dimension = ?
        """

        try db.execute(sql: sql, arguments: [count, StreakFreezeSystem.maxFreezes, Date(), dimension.rawValue])
    }

    /// Initialize streak cache for a dimension if not exists
    public func initializeStreakCache(db: Database, dimension: StreakDimension) throws {
        let sql = """
            INSERT OR IGNORE INTO cosmo_streak_cache
            (dimension, currentStreak, longestStreak, freezesAvailable, freezesUsed, updatedAt)
            VALUES (?, 0, 0, 0, 0, ?)
        """

        try db.execute(sql: sql, arguments: [dimension.rawValue, Date()])
    }

    // MARK: - Streak Analytics

    /// Get streak states for all dimensions
    public func getAllStreakStates(db: Database, asOf date: Date = Date()) throws -> [StreakState] {
        try StreakDimension.allCases.map { dimension in
            try calculateStreakState(db: db, dimension: dimension, asOf: date)
        }
    }

    /// Get combined streak summary
    public func getStreakSummary(db: Database, asOf date: Date = Date()) throws -> StreakSummary {
        let states = try getAllStreakStates(db: db, asOf: date)

        let totalCurrentStreak = states.filter { $0.dimension != .overall }.map { $0.currentStreak }.reduce(0, +)
        let averageStreak = Double(totalCurrentStreak) / Double(StreakDimension.allCases.count - 1)
        let longestAnyStreak = states.map { $0.longestStreak }.max() ?? 0
        let dimensionsWithStreak = states.filter { $0.dimension != .overall && $0.currentStreak > 0 }.count
        let dimensionsAtRisk = states.filter { $0.isAtRisk(on: date) }.count

        let overallState = states.first { $0.dimension == .overall }
        let combinedMultiplier = calculateCombinedMultiplier(states: states)

        return StreakSummary(
            dimensionStates: states.filter { $0.dimension != .overall },
            overallState: overallState ?? StreakState(dimension: .overall),
            averageStreak: averageStreak,
            longestAnyStreak: longestAnyStreak,
            dimensionsWithStreak: dimensionsWithStreak,
            dimensionsAtRisk: dimensionsAtRisk,
            combinedMultiplier: combinedMultiplier
        )
    }

    /// Calculate combined XP multiplier from all streaks
    private func calculateCombinedMultiplier(states: [StreakState]) -> Double {
        // Use average of all dimension multipliers
        let multipliers = states.filter { $0.dimension != .overall }.map { $0.currentMultiplier }
        guard !multipliers.isEmpty else { return 1.0 }

        let average = multipliers.reduce(0.0, +) / Double(multipliers.count)
        return average
    }
}

// MARK: - Streak Summary

/// Summary of all streak states
public struct StreakSummary: Codable, Sendable {
    public let dimensionStates: [StreakState]
    public let overallState: StreakState
    public let averageStreak: Double
    public let longestAnyStreak: Int
    public let dimensionsWithStreak: Int
    public let dimensionsAtRisk: Int
    public let combinedMultiplier: Double

    public init(
        dimensionStates: [StreakState],
        overallState: StreakState,
        averageStreak: Double,
        longestAnyStreak: Int,
        dimensionsWithStreak: Int,
        dimensionsAtRisk: Int,
        combinedMultiplier: Double
    ) {
        self.dimensionStates = dimensionStates
        self.overallState = overallState
        self.averageStreak = averageStreak
        self.longestAnyStreak = longestAnyStreak
        self.dimensionsWithStreak = dimensionsWithStreak
        self.dimensionsAtRisk = dimensionsAtRisk
        self.combinedMultiplier = combinedMultiplier
    }

    /// User-facing streak message
    public var statusMessage: String {
        if overallState.currentStreak >= 365 {
            return "Legendary! \(overallState.currentStreak) day streak!"
        } else if overallState.currentStreak >= 100 {
            return "Incredible! \(overallState.currentStreak) days and counting!"
        } else if overallState.currentStreak >= 30 {
            return "\(overallState.currentStreak) day streak! Keep it going!"
        } else if overallState.currentStreak >= 7 {
            return "\(overallState.currentStreak) day streak!"
        } else if overallState.currentStreak > 0 {
            return "\(overallState.currentStreak) day streak started"
        } else if dimensionsAtRisk > 0 {
            return "\(dimensionsAtRisk) streak(s) at risk!"
        } else {
            return "Start your streak today!"
        }
    }
}

// MARK: - Streak Milestone

/// Milestones reached during streak progression
public struct StreakMilestone: Codable, Sendable {
    public let days: Int
    public let name: String
    public let dimension: StreakDimension
    public let reachedAt: Date
    public let xpBonus: Int
    public let freezesEarned: Int

    public static let milestones: [Int] = [7, 14, 21, 30, 60, 66, 90, 180, 365, 500, 730, 1000]

    public static func milestone(for days: Int, dimension: StreakDimension, date: Date = Date()) -> StreakMilestone? {
        guard milestones.contains(days) else { return nil }

        let name = StreakMultiplierTiers.tierName(for: days)
        let xpBonus: Int

        switch days {
        case 7: xpBonus = 100
        case 14: xpBonus = 200
        case 21: xpBonus = 300
        case 30: xpBonus = 500
        case 60: xpBonus = 750
        case 66: xpBonus = 1000
        case 90: xpBonus = 1500
        case 180: xpBonus = 3000
        case 365: xpBonus = 10000
        case 500: xpBonus = 15000
        case 730: xpBonus = 25000
        case 1000: xpBonus = 50000
        default: xpBonus = 0
        }

        let freezesEarned = StreakFreezeSystem.freezesEarnedAt(streakDays: days)

        return StreakMilestone(
            days: days,
            name: name,
            dimension: dimension,
            reachedAt: date,
            xpBonus: xpBonus,
            freezesEarned: freezesEarned
        )
    }
}
