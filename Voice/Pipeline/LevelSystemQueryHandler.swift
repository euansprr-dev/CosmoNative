// CosmoOS/Voice/Pipeline/LevelSystemQueryHandler.swift
// Handles Level System voice queries and formats responses

import Foundation
import GRDB

// MARK: - Level System Query Handler

/// Processes Level System voice queries and returns formatted responses.
/// Queries the database for level state, streaks, badges, and health data,
/// then formats responses for both TTS and visual display.
actor LevelSystemQueryHandler {
    /// Shared singleton
    @MainActor static let shared = LevelSystemQueryHandler()

    private let database: any DatabaseWriter
    private let responseFormatter: QueryResponseFormatter
    private let streakEngine: StreakTrackingEngine

    @MainActor
    init(database: (any DatabaseWriter)? = nil) {
        // Note: When using default database, must be called on main actor
        if let db = database {
            self.database = db
        } else {
            // Use a placeholder that will be replaced - this is safe because
            // shared singleton is created at app startup on main thread
            self.database = MainActorDatabaseAccess.getDatabase()
        }
        self.responseFormatter = QueryResponseFormatter()
        self.streakEngine = StreakTrackingEngine()
    }

    // MARK: - Main Query Execution

    /// Execute a level system query and return a formatted response.
    func executeQuery(_ action: ParsedAction) async throws -> QueryResponse {
        guard let queryType = action.queryType else {
            throw QueryError.missingQueryType
        }

        switch queryType {
        // Level Queries
        case .levelStatus:
            return try await queryLevelStatus()
        case .xpToday:
            return try await queryXPToday()
        case .xpBreakdown:
            return try await queryXPBreakdown()
        case .dimensionStatus:
            return try await queryDimensionStatus(dimension: action.dimension)

        // Streak Queries
        case .streakStatus:
            return try await queryStreakStatus(streakType: action.title)
        case .allStreaks:
            return try await queryAllStreaks()
        case .streakHistory:
            return try await queryStreakHistory()

        // Badge Queries
        case .badgesEarned:
            return try await queryBadgesEarned()
        case .badgeProgress:
            return try await queryBadgeProgress(badgeName: action.title)
        case .badgeDetails:
            return try await queryBadgeDetails(badgeName: action.title ?? "")

        // Quest Queries
        case .activeQuests:
            return try await queryActiveQuests()
        case .questProgress:
            return try await queryQuestProgress()

        // Health Queries
        case .readinessScore:
            return try await queryReadinessScore()
        case .hrvStatus:
            return try await queryHRVStatus()
        case .sleepScore:
            return try await querySleepScore()
        case .todayHealth:
            return try await queryTodayHealth()

        // Summary Queries
        case .dailySummary:
            return try await queryDailySummary()
        case .weeklySummary:
            return try await queryWeeklySummary()
        case .monthProgress:
            return try await queryMonthProgress()

        // Content Performance Queries (handled by ContentVoiceCommands)
        case .contentPerformance, .totalReach, .engagementRate, .viralCount,
             .viralContent, .topContent, .pipelineStatus, .activeContent,
             .creativeDimension, .clientPerformance, .clientList:
            return QueryResponse(
                queryType: queryType,
                spokenText: "Content performance queries are handled by the content system.",
                displayTitle: "Content Query",
                displaySubtitle: "Use content commands for this query",
                metrics: []
            )
        }
    }

    // MARK: - Level Queries

    private func queryLevelStatus() async throws -> QueryResponse {
        let state = try await database.read { db in
            try CosmoLevelState.fetchOne(db)
        }

        guard let levelState = state else {
            return responseFormatter.formatNoDataResponse(for: .levelStatus)
        }

        let xpToNextLevel = levelState.xpRequiredForNextLevel - levelState.currentLevelXP
        let progressPercent = Int((Double(levelState.currentLevelXP) / Double(levelState.xpRequiredForNextLevel)) * 100)

        let spokenText = "You're at Cosmo Index level \(levelState.cosmoIndex), " +
            "with \(formatNumber(levelState.lifetimeXP)) lifetime XP. " +
            "You need \(formatNumber(xpToNextLevel)) more XP to reach level \(levelState.cosmoIndex + 1)."

        return QueryResponse(
            queryType: .levelStatus,
            spokenText: spokenText,
            displayTitle: "Level \(levelState.cosmoIndex)",
            displaySubtitle: "\(formatNumber(levelState.lifetimeXP)) Lifetime XP",
            metrics: [
                QueryMetric(label: "Cosmo Index", value: "\(levelState.cosmoIndex)", icon: "star.fill", color: "gold", trend: nil),
                QueryMetric(label: "Neuro-ELO", value: "\(levelState.neuroELO)", icon: "brain", color: "purple", trend: neloTrend(levelState)),
                QueryMetric(label: "To Next Level", value: "\(formatNumber(xpToNextLevel)) XP", icon: "arrow.up.circle", color: "blue", trend: nil),
                QueryMetric(label: "Progress", value: "\(progressPercent)%", icon: "chart.bar.fill", color: "green", trend: nil)
            ],
            action: QueryAction(title: "View Details", destination: "level_dashboard")
        )
    }

    private func queryXPToday() async throws -> QueryResponse {
        let state = try await database.read { db in
            try CosmoLevelState.fetchOne(db)
        }

        guard let levelState = state else {
            return responseFormatter.formatNoDataResponse(for: .xpToday)
        }

        let todayXP = levelState.todayXP
        let dailyGoal = 500 // Default daily goal
        let percentOfGoal = min(100, Int((Double(todayXP) / Double(dailyGoal)) * 100))

        var spokenText = "You've earned \(formatNumber(todayXP)) XP today"
        if percentOfGoal >= 100 {
            spokenText += ". That's \(percentOfGoal - 100)% above your daily goal. Great work!"
        } else {
            spokenText += ", which is \(percentOfGoal)% of your daily goal."
        }

        return QueryResponse(
            queryType: .xpToday,
            spokenText: spokenText,
            displayTitle: "\(formatNumber(todayXP)) XP Today",
            displaySubtitle: "\(percentOfGoal)% of daily goal",
            metrics: [
                QueryMetric(label: "Today", value: "+\(formatNumber(todayXP))", icon: "plus.circle.fill", color: "green", trend: nil),
                QueryMetric(label: "Daily Goal", value: "\(dailyGoal)", icon: "target", color: "blue", trend: nil),
                QueryMetric(label: "Progress", value: "\(percentOfGoal)%", icon: "percent", color: percentOfGoal >= 100 ? "gold" : "blue", trend: nil)
            ]
        )
    }

    private func queryXPBreakdown() async throws -> QueryResponse {
        let state = try await database.read { db in
            try CosmoLevelState.fetchOne(db)
        }

        guard let levelState = state else {
            return responseFormatter.formatNoDataResponse(for: .xpBreakdown)
        }

        // Get dimension XP breakdown
        let dimensions = levelState.dimensionXP
        let sortedDimensions = dimensions.sorted { $0.value > $1.value }
        let topDimension = sortedDimensions.first

        var spokenText = "Here's your XP breakdown. "
        if let top = topDimension {
            spokenText += "Your strongest dimension is \(top.key) with \(formatNumber(top.value)) XP. "
        }
        spokenText += "Total lifetime XP is \(formatNumber(levelState.lifetimeXP))."

        let metrics = sortedDimensions.prefix(6).map { dimension, xp in
            QueryMetric(
                label: dimension.capitalized,
                value: formatNumber(xp),
                icon: dimensionIcon(dimension),
                color: dimensionColor(dimension),
                trend: nil
            )
        }

        return QueryResponse(
            queryType: .xpBreakdown,
            spokenText: spokenText,
            displayTitle: "XP Breakdown",
            displaySubtitle: "\(formatNumber(levelState.lifetimeXP)) Total XP",
            metrics: metrics,
            action: QueryAction(title: "Full Breakdown", destination: "xp_details")
        )
    }

    private func queryDimensionStatus(dimension: String?) async throws -> QueryResponse {
        let dimName = dimension ?? "cognitive"
        let state = try await database.read { db in
            try CosmoLevelState.fetchOne(db)
        }

        guard let levelState = state else {
            return responseFormatter.formatNoDataResponse(for: .dimensionStatus)
        }

        let dimXP = levelState.dimensionXP[dimName] ?? 0
        let dimLevel = levelState.dimensionLevels[dimName] ?? 1

        let spokenText = "Your \(dimName) dimension is at level \(dimLevel) with \(formatNumber(dimXP)) XP."

        return QueryResponse(
            queryType: .dimensionStatus,
            spokenText: spokenText,
            displayTitle: "\(dimName.capitalized) Dimension",
            displaySubtitle: "Level \(dimLevel)",
            metrics: [
                QueryMetric(label: "Level", value: "\(dimLevel)", icon: dimensionIcon(dimName), color: dimensionColor(dimName), trend: nil),
                QueryMetric(label: "XP", value: formatNumber(dimXP), icon: "sparkles", color: "gold", trend: nil)
            ]
        )
    }

    // MARK: - Streak Queries

    private func queryStreakStatus(streakType: String?) async throws -> QueryResponse {
        let streaks = try await database.read { [streakEngine] db in
            try streakEngine.getAllStreakStates(db: db)
        }

        // If specific streak requested, find it
        if let requestedType = streakType {
            let streak = streaks.first { $0.dimension.rawValue.lowercased().contains(requestedType.lowercased()) }
            if let s = streak {
                return formatStreakResponse(s)
            }
        }

        // Return primary streak (longest active)
        if let primaryStreak = streaks.filter({ $0.isActive }).max(by: { $0.currentStreak < $1.currentStreak }) {
            return formatStreakResponse(primaryStreak)
        }

        return responseFormatter.formatNoDataResponse(for: .streakStatus)
    }

    private func queryAllStreaks() async throws -> QueryResponse {
        let allStreaks = try await database.read { [streakEngine] db in
            try streakEngine.getAllStreakStates(db: db)
        }
        let streaks = allStreaks.filter { $0.isActive }

        if streaks.isEmpty {
            return QueryResponse(
                queryType: .allStreaks,
                spokenText: "You don't have any active streaks yet. Start a daily habit to begin building one!",
                displayTitle: "No Active Streaks",
                displaySubtitle: "Start building your habits",
                metrics: []
            )
        }

        let sortedStreaks = streaks.sorted { $0.currentStreak > $1.currentStreak }
        let totalDays = sortedStreaks.reduce(0) { $0 + $1.currentStreak }

        var spokenText = "You have \(streaks.count) active streaks with a combined \(totalDays) days. "
        if let longest = sortedStreaks.first {
            spokenText += "Your longest is \(longest.dimension.displayName) at \(longest.currentStreak) days."
        }

        let metrics = sortedStreaks.prefix(4).map { streak in
            QueryMetric(
                label: streak.dimension.displayName,
                value: "\(streak.currentStreak) days",
                icon: streakIcon(streak.dimension.rawValue),
                color: streak.currentStreak >= 7 ? "gold" : "blue",
                trend: streak.isAtRisk() ? .down : .stable
            )
        }

        return QueryResponse(
            queryType: .allStreaks,
            spokenText: spokenText,
            displayTitle: "\(streaks.count) Active Streaks",
            displaySubtitle: "\(totalDays) total streak days",
            metrics: metrics,
            action: QueryAction(title: "View All", destination: "streaks")
        )
    }

    private func queryStreakHistory() async throws -> QueryResponse {
        let streaks = try await database.read { [streakEngine] db in
            try streakEngine.getAllStreakStates(db: db)
        }

        let bestStreak = streaks.max(by: { $0.longestStreak < $1.longestStreak })
        let totalStreakDays = streaks.reduce(0) { $0 + $1.totalActiveDays }

        var spokenText = "You've maintained \(totalStreakDays) total streak days across all habits. "
        if let best = bestStreak {
            spokenText += "Your all-time best is \(best.longestStreak) days for \(best.dimension.displayName)."
        }

        return QueryResponse(
            queryType: .streakHistory,
            spokenText: spokenText,
            displayTitle: "Streak History",
            displaySubtitle: "\(totalStreakDays) lifetime streak days",
            metrics: [
                QueryMetric(label: "Total Days", value: "\(totalStreakDays)", icon: "flame.fill", color: "orange", trend: nil),
                QueryMetric(label: "Best Streak", value: "\(bestStreak?.longestStreak ?? 0) days", icon: "trophy.fill", color: "gold", trend: nil),
                QueryMetric(label: "Active", value: "\(streaks.filter { $0.isActive }.count)", icon: "checkmark.circle.fill", color: "green", trend: nil)
            ]
        )
    }

    private func formatStreakResponse(_ streak: StreakState) -> QueryResponse {
        var spokenText = "Your \(streak.dimension.displayName) streak is at \(streak.currentStreak) days"
        if streak.isAtRisk() {
            spokenText += ". Warning: it's at risk! Complete your activity today to keep it going."
        } else if streak.currentStreak >= 7 {
            spokenText += ". Great job keeping it up!"
        } else {
            spokenText += "."
        }

        let multiplier = streak.currentMultiplier
        let multiplierText = multiplier > 1.0 ? "\(String(format: "%.1f", multiplier))x" : "1x"

        return QueryResponse(
            queryType: .streakStatus,
            spokenText: spokenText,
            displayTitle: "\(streak.currentStreak) Day Streak",
            displaySubtitle: streak.dimension.displayName,
            metrics: [
                QueryMetric(label: "Current", value: "\(streak.currentStreak) days", icon: "flame.fill", color: streak.isAtRisk() ? "orange" : "green", trend: streak.isAtRisk() ? .down : .stable),
                QueryMetric(label: "Best", value: "\(streak.longestStreak) days", icon: "trophy.fill", color: "gold", trend: nil),
                QueryMetric(label: "Multiplier", value: multiplierText, icon: "bolt.fill", color: "purple", trend: nil)
            ]
        )
    }

    // MARK: - Badge Queries (Badge system uses Atom-based tracking, not dedicated tables)

    private func queryBadgesEarned() async throws -> QueryResponse {
        // Badge data is stored in CosmoLevelSystem, not as separate database records
        // Return a placeholder until badge atom queries are implemented
        return QueryResponse(
            queryType: .badgesEarned,
            spokenText: "Badge tracking is integrated with the level system. Check your level dashboard for badge progress.",
            displayTitle: "Badges",
            displaySubtitle: "View in Level Dashboard",
            metrics: [],
            action: QueryAction(title: "View Dashboard", destination: "level_dashboard")
        )
    }

    private func queryBadgeProgress(badgeName: String?) async throws -> QueryResponse {
        // Badge progress is tracked through CosmoLevelSystem
        return QueryResponse(
            queryType: .badgeProgress,
            spokenText: "Badge progress is tracked in your level dashboard. Keep completing activities to unlock badges!",
            displayTitle: "Badge Progress",
            displaySubtitle: "Keep going!",
            metrics: [],
            action: QueryAction(title: "View Dashboard", destination: "level_dashboard")
        )
    }

    private func queryBadgeDetails(badgeName: String) async throws -> QueryResponse {
        // Badge definitions are in BadgeDefinitionSystem
        return QueryResponse(
            queryType: .badgeDetails,
            spokenText: "Badge details are available in your level dashboard.",
            displayTitle: "Badge Details",
            displaySubtitle: badgeName,
            metrics: [],
            action: QueryAction(title: "View Dashboard", destination: "level_dashboard")
        )
    }

    // MARK: - Quest Queries (Quest system uses DailyQuestEngine, not dedicated tables)

    private func queryActiveQuests() async throws -> QueryResponse {
        // Quests are generated and tracked by DailyQuestEngine
        return QueryResponse(
            queryType: .activeQuests,
            spokenText: "Daily quests are generated each day. Check your dashboard for today's quests!",
            displayTitle: "Daily Quests",
            displaySubtitle: "Check your dashboard",
            metrics: [],
            action: QueryAction(title: "View Quests", destination: "quests")
        )
    }

    private func queryQuestProgress() async throws -> QueryResponse {
        // Quest progress tracked by DailyQuestEngine
        return QueryResponse(
            queryType: .questProgress,
            spokenText: "Quest progress is tracked throughout the day. Complete activities to advance your quests!",
            displayTitle: "Quest Progress",
            displaySubtitle: "Keep going!",
            metrics: [],
            action: QueryAction(title: "View Quests", destination: "quests")
        )
    }

    // MARK: - Health Queries (Health data is stored as Atoms with physiological type)

    private func queryReadinessScore() async throws -> QueryResponse {
        // Health data would be queried from Atoms with type physiological
        // Currently returning placeholder until HealthKit integration is complete
        return QueryResponse(
            queryType: .readinessScore,
            spokenText: "Readiness tracking requires Apple Watch sync. Make sure your watch is connected.",
            displayTitle: "Readiness Score",
            displaySubtitle: "Sync your Apple Watch",
            metrics: []
        )
    }

    private func queryHRVStatus() async throws -> QueryResponse {
        // HRV data would come from HealthKit via Atoms
        return QueryResponse(
            queryType: .hrvStatus,
            spokenText: "HRV tracking requires Apple Watch sync. Make sure your watch is connected.",
            displayTitle: "HRV Status",
            displaySubtitle: "Sync your Apple Watch",
            metrics: []
        )
    }

    private func querySleepScore() async throws -> QueryResponse {
        // Sleep data would come from HealthKit via Atoms
        return QueryResponse(
            queryType: .sleepScore,
            spokenText: "Sleep tracking requires Apple Watch sync. Make sure you wear your watch to bed.",
            displayTitle: "Sleep Score",
            displaySubtitle: "Sync your Apple Watch",
            metrics: []
        )
    }

    private func queryTodayHealth() async throws -> QueryResponse {
        // Combined health summary - placeholder until HealthKit integration
        return QueryResponse(
            queryType: .todayHealth,
            spokenText: "Health data requires Apple Watch sync. Connect your watch to see readiness, HRV, and sleep metrics.",
            displayTitle: "Health Summary",
            displaySubtitle: "Sync your Apple Watch",
            metrics: [],
            action: QueryAction(title: "Connect Watch", destination: "health_settings")
        )
    }

    // MARK: - Summary Queries

    private func queryDailySummary() async throws -> QueryResponse {
        let state = try await database.read { db in
            try CosmoLevelState.fetchOne(db)
        }

        guard let levelState = state else {
            return responseFormatter.formatNoDataResponse(for: .dailySummary)
        }

        let xp = levelState.todayXP
        let tasksCompleted = levelState.todayTasksCompleted
        let focusMinutes = levelState.todayFocusMinutes

        let spokenText = "Here's your daily summary. You earned \(formatNumber(xp)) XP, " +
            "completed \(tasksCompleted) tasks, and logged \(focusMinutes) minutes of focus time."

        return QueryResponse(
            queryType: .dailySummary,
            spokenText: spokenText,
            displayTitle: "Today's Summary",
            displaySubtitle: Date().formatted(date: .abbreviated, time: .omitted),
            metrics: [
                QueryMetric(label: "XP Earned", value: "+\(formatNumber(xp))", icon: "sparkles", color: "gold", trend: nil),
                QueryMetric(label: "Tasks", value: "\(tasksCompleted)", icon: "checkmark.circle.fill", color: "green", trend: nil),
                QueryMetric(label: "Focus", value: "\(focusMinutes)m", icon: "brain.head.profile", color: "purple", trend: nil)
            ],
            action: QueryAction(title: "Full Summary", destination: "daily_summary")
        )
    }

    private func queryWeeklySummary() async throws -> QueryResponse {
        let state = try await database.read { db in
            try CosmoLevelState.fetchOne(db)
        }

        guard let levelState = state else {
            return responseFormatter.formatNoDataResponse(for: .weeklySummary)
        }

        let weekXP = levelState.weekXP
        let weekTasks = levelState.weekTasksCompleted
        let avgFocus = levelState.weekFocusMinutes / 7

        let spokenText = "This week you earned \(formatNumber(weekXP)) XP, " +
            "completed \(weekTasks) tasks, and averaged \(avgFocus) minutes of focus time per day."

        return QueryResponse(
            queryType: .weeklySummary,
            spokenText: spokenText,
            displayTitle: "Weekly Summary",
            displaySubtitle: "This Week",
            metrics: [
                QueryMetric(label: "Week XP", value: "+\(formatNumber(weekXP))", icon: "sparkles", color: "gold", trend: nil),
                QueryMetric(label: "Tasks", value: "\(weekTasks)", icon: "checkmark.circle.fill", color: "green", trend: nil),
                QueryMetric(label: "Avg Focus", value: "\(avgFocus)m/day", icon: "brain.head.profile", color: "purple", trend: nil)
            ],
            action: QueryAction(title: "Full Report", destination: "weekly_summary")
        )
    }

    private func queryMonthProgress() async throws -> QueryResponse {
        let state = try await database.read { db in
            try CosmoLevelState.fetchOne(db)
        }

        guard let levelState = state else {
            return responseFormatter.formatNoDataResponse(for: .monthProgress)
        }

        let monthXP = levelState.monthXP
        let levelsGained = levelState.monthLevelsGained
        let badgesEarned = levelState.monthBadgesEarned

        let spokenText = "This month you've earned \(formatNumber(monthXP)) XP, " +
            "gained \(levelsGained) levels, and earned \(badgesEarned) badges."

        return QueryResponse(
            queryType: .monthProgress,
            spokenText: spokenText,
            displayTitle: "Monthly Progress",
            displaySubtitle: Date().formatted(.dateTime.month(.wide)),
            metrics: [
                QueryMetric(label: "XP", value: formatNumber(monthXP), icon: "sparkles", color: "gold", trend: nil),
                QueryMetric(label: "Levels", value: "+\(levelsGained)", icon: "arrow.up.circle.fill", color: "green", trend: nil),
                QueryMetric(label: "Badges", value: "\(badgesEarned)", icon: "medal.fill", color: "purple", trend: nil)
            ]
        )
    }

    // MARK: - Helpers

    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            let k = Double(number) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(number)"
    }

    private func neloTrend(_ state: CosmoLevelState) -> QueryMetric.MetricTrend? {
        // Compare to yesterday's NELO
        if state.neuroELOChange > 10 { return .up }
        if state.neuroELOChange < -10 { return .down }
        return .stable
    }

    private func dimensionIcon(_ dimension: String) -> String {
        switch dimension.lowercased() {
        case "cognitive": return "brain"
        case "creative": return "paintbrush.fill"
        case "physiological": return "heart.fill"
        case "behavioral": return "figure.walk"
        case "knowledge": return "book.fill"
        case "reflection": return "sparkles"
        default: return "star.fill"
        }
    }

    private func dimensionColor(_ dimension: String) -> String {
        switch dimension.lowercased() {
        case "cognitive": return "purple"
        case "creative": return "pink"
        case "physiological": return "red"
        case "behavioral": return "green"
        case "knowledge": return "blue"
        case "reflection": return "orange"
        default: return "gray"
        }
    }

    private func streakIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "writing": return "pencil"
        case "focus", "deep_work": return "brain.head.profile"
        case "workout": return "figure.run"
        case "journal": return "book.closed.fill"
        case "reading": return "book.fill"
        default: return "flame.fill"
        }
    }

    private func badgeTierColor(_ tier: BadgeTier) -> String {
        switch tier {
        case .bronze: return "brown"
        case .silver: return "gray"
        case .gold: return "yellow"
        case .platinum: return "blue"
        case .diamond: return "cyan"
        case .cosmic: return "purple"
        }
    }

    private func readinessLevel(_ score: Int) -> (description: String, recommendation: String, color: String, icon: String) {
        switch score {
        case 80...100:
            return ("well-rested and ready", "Great day for challenging work!", "green", "checkmark.circle.fill")
        case 60..<80:
            return ("moderately ready", "Good for regular tasks.", "blue", "circle.fill")
        case 40..<60:
            return ("somewhat fatigued", "Consider lighter tasks today.", "orange", "exclamationmark.circle.fill")
        default:
            return ("fatigued", "Rest and recovery recommended.", "red", "xmark.circle.fill")
        }
    }

    private func sleepQuality(_ hours: Double) -> (description: String, summary: String, color: String) {
        switch hours {
        case 7.5...:
            return ("That's excellent recovery time!", "Excellent", "green")
        case 6.5..<7.5:
            return ("That's decent, but a bit more would help.", "Good", "blue")
        case 5..<6.5:
            return ("That's below optimal. Try for more tonight.", "Fair", "orange")
        default:
            return ("That's not enough. Prioritize rest tonight.", "Poor", "red")
        }
    }
}

// MARK: - Query Response Formatter

/// Formats query responses for consistent output
struct QueryResponseFormatter {

    func formatNoDataResponse(for queryType: ParsedAction.QueryType) -> QueryResponse {
        let messages: [ParsedAction.QueryType: (spoken: String, title: String)] = [
            .levelStatus: ("I don't have level data yet. Complete some activities to start earning XP!", "No Level Data"),
            .xpToday: ("No XP earned today yet. Get started!", "No XP Today"),
            .streakStatus: ("You don't have any active streaks. Start a daily habit!", "No Active Streaks"),
            .badgesEarned: ("You haven't earned any badges yet. Keep going!", "No Badges Yet"),
            .activeQuests: ("No active quests right now.", "No Active Quests"),
            .dailySummary: ("I don't have summary data for today yet.", "No Summary Available"),
            .weeklySummary: ("I don't have enough data for a weekly summary yet.", "No Weekly Data")
        ]

        let message = messages[queryType] ?? ("No data available.", "No Data")

        return QueryResponse(
            queryType: queryType,
            spokenText: message.spoken,
            displayTitle: message.title,
            displaySubtitle: nil,
            metrics: []
        )
    }
}

// MARK: - Main Actor Database Access Helper

private enum MainActorDatabaseAccess {
    /// Access database synchronously. This is safe because:
    /// 1. CosmoDatabase.shared is initialized at app startup on MainActor
    /// 2. dbQueue is thread-safe once initialized
    /// 3. This is only called during singleton initialization which happens at startup
    @MainActor static func getDatabase() -> any DatabaseWriter {
        CosmoDatabase.shared.dbQueue! as any DatabaseWriter
    }
}

// MARK: - Query Errors

enum QueryError: Error, LocalizedError {
    case missingQueryType
    case databaseError(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .missingQueryType:
            return "Query type not specified"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .notFound(let item):
            return "\(item) not found"
        }
    }
}
