// CosmoOS/Data/Models/LevelSystem/CosmoLevelSystem.swift
// Core Level System model - the heart of the Cosmo gamification engine
// Two-tier architecture: Cosmo Index (permanent) + Neuro-ELO (dynamic)

import Foundation
import GRDB

// MARK: - Cosmo Level System

/// The complete level system state for a user
/// Everything is stored as atoms, this is a computed view of that state
@MainActor
final class CosmoLevelSystem: ObservableObject {
    // MARK: - Cosmo Index (CI) - Permanent Progress

    /// Overall Cosmo Index level (1-100+, never decreases)
    @Published private(set) var cosmoIndex: Int = 1

    /// Total XP accumulated across all dimensions
    @Published private(set) var totalXP: Int = 0

    /// XP progress towards next CI level
    @Published private(set) var xpToNextLevel: Int = 100

    // MARK: - Neuro-ELO (NELO) - Dynamic Performance

    /// Overall NELO rating (800-2400 scale, can rise and fall)
    @Published private(set) var neuroELO: Int = 1200

    /// NELO trend direction
    @Published private(set) var neloTrend: Trend = .stable

    // MARK: - Per-Dimension Progress

    /// Progress for each of the 6 dimensions
    @Published private(set) var dimensions: [LevelDimension: DimensionProgress] = [:]

    // MARK: - Streaks

    /// Active streak tracking
    @Published private(set) var streaks: StreakTracker = StreakTracker()

    /// Current multiplier from streaks
    @Published private(set) var currentMultiplier: Double = 1.0

    // MARK: - Badges

    /// Set of unlocked badge IDs
    @Published private(set) var unlockedBadges: Set<String> = []

    /// Progress towards locked badges
    @Published private(set) var badgeProgress: [String: BadgeProgress] = [:]

    /// Total badges unlocked
    @Published private(set) var totalBadgesUnlocked: Int = 0

    // MARK: - Timestamps

    /// When XP was last earned
    @Published private(set) var lastXPAt: Date?

    /// When the last level up occurred
    @Published private(set) var lastLevelUpAt: Date?

    /// When the last badge was unlocked
    @Published private(set) var lastBadgeAt: Date?

    // MARK: - Initialization

    init() {
        // Initialize all dimensions
        for dimension in LevelDimension.allCases {
            dimensions[dimension] = DimensionProgress(dimension: dimension)
        }
    }

    /// Initialize from cached state
    init(from state: CosmoLevelState) {
        self.cosmoIndex = state.cosmoIndex
        self.neuroELO = state.overallNelo
        self.totalXP = state.totalXPEarned
        self.totalBadgesUnlocked = state.totalBadgesUnlocked
        self.lastXPAt = state.lastXPAt
        self.lastLevelUpAt = state.lastLevelUpAt
        self.lastBadgeAt = state.lastBadgeAt

        // Initialize dimensions from state
        self.dimensions = [
            .cognitive: DimensionProgress(
                dimension: .cognitive,
                level: state.cognitiveLevel,
                xp: 0,
                totalXP: state.cognitiveCI,
                nelo: state.cognitiveNELO
            ),
            .creative: DimensionProgress(
                dimension: .creative,
                level: state.creativeLevel,
                xp: 0,
                totalXP: state.creativeCI,
                nelo: state.creativeNELO
            ),
            .physiological: DimensionProgress(
                dimension: .physiological,
                level: state.physiologicalLevel,
                xp: 0,
                totalXP: state.physiologicalCI,
                nelo: state.physiologicalNELO
            ),
            .behavioral: DimensionProgress(
                dimension: .behavioral,
                level: state.behavioralLevel,
                xp: 0,
                totalXP: state.behavioralCI,
                nelo: state.behavioralNELO
            ),
            .knowledge: DimensionProgress(
                dimension: .knowledge,
                level: state.knowledgeLevel,
                xp: 0,
                totalXP: state.knowledgeCI,
                nelo: state.knowledgeNELO
            ),
            .reflection: DimensionProgress(
                dimension: .reflection,
                level: state.reflectionLevel,
                xp: 0,
                totalXP: state.reflectionCI,
                nelo: state.reflectionNELO
            )
        ]

        // Calculate XP to next level
        self.xpToNextLevel = XPCalculationEngine.xpRequiredForLevel(cosmoIndex + 1) - totalXP
    }

    // MARK: - XP Operations

    /// Award XP to a dimension
    /// - Parameters:
    ///   - amount: Base XP amount (before multipliers)
    ///   - dimension: The dimension to award XP to
    ///   - source: Description of what triggered the XP
    ///   - sourceAtomUUID: UUID of the atom that triggered this XP
    /// - Returns: The actual XP awarded (after multipliers)
    @discardableResult
    func awardXP(
        _ amount: Int,
        dimension: LevelDimension,
        source: String,
        sourceAtomUUID: String? = nil
    ) -> Int {
        // Apply streak multiplier
        let multipliedAmount = Int(Double(amount) * currentMultiplier)

        // Update dimension
        if var progress = dimensions[dimension] {
            progress.addXP(multipliedAmount)
            dimensions[dimension] = progress
        }

        // Update total XP
        totalXP += multipliedAmount

        // Check for CI level up
        let newLevel = XPCalculationEngine.levelForXP(totalXP)
        if newLevel > cosmoIndex {
            cosmoIndex = newLevel
            lastLevelUpAt = Date()
        }

        // Update XP to next level
        xpToNextLevel = XPCalculationEngine.xpRequiredForLevel(cosmoIndex + 1) - totalXP

        // Update timestamp
        lastXPAt = Date()

        return multipliedAmount
    }

    // MARK: - NELO Operations

    /// Update NELO for a dimension based on performance
    func updateNELO(
        dimension: LevelDimension,
        change: Int,
        triggeredBy: String
    ) {
        guard var progress = dimensions[dimension] else { return }

        // Apply change with K-factor adjustment
        let kFactor = NELORegressionEngine.kFactor(forNELO: progress.nelo)
        let adjustedChange = Int(Double(change) * kFactor / 32.0)

        progress.updateNELO(change: adjustedChange, triggeredBy: triggeredBy)
        dimensions[dimension] = progress

        // Recalculate overall NELO
        recalculateOverallNELO()
    }

    /// Recalculate the overall NELO from dimension NELOs
    private func recalculateOverallNELO() {
        // Weighted average of dimension NELOs
        let weights: [LevelDimension: Double] = [
            .cognitive: 0.20,
            .creative: 0.15,
            .physiological: 0.15,
            .behavioral: 0.20,
            .knowledge: 0.15,
            .reflection: 0.15
        ]

        var weightedSum = 0.0
        for (dimension, weight) in weights {
            if let progress = dimensions[dimension] {
                weightedSum += Double(progress.nelo) * weight
            }
        }

        let previousNELO = neuroELO
        neuroELO = Int(weightedSum)

        // Update trend
        let change = neuroELO - previousNELO
        if change > 10 {
            neloTrend = .improving
        } else if change < -10 {
            neloTrend = .declining
        } else {
            neloTrend = .stable
        }
    }

    // MARK: - Streak Operations

    /// Update streak for a specific type
    func updateStreak(_ type: StreakType, active: Bool) {
        if active {
            streaks.incrementStreak(type)
        } else {
            streaks.breakStreak(type)
        }

        // Recalculate multiplier
        currentMultiplier = streaks.calculateTotalMultiplier()
    }

    // MARK: - Badge Operations

    /// Unlock a badge
    func unlockBadge(_ badge: BadgeDefinition) {
        unlockedBadges.insert(badge.id)
        badgeProgress.removeValue(forKey: badge.id)
        totalBadgesUnlocked += 1
        lastBadgeAt = Date()
    }

    /// Update progress towards a badge
    func updateBadgeProgress(_ badgeId: String, current: Int, target: Int) {
        if !unlockedBadges.contains(badgeId) {
            let requirement = RequirementProgress(
                type: .actionCount,
                currentValue: Double(current),
                targetValue: Double(target),
                description: "Progress towards \(badgeId)"
            )
            badgeProgress[badgeId] = BadgeProgress(
                badgeId: badgeId,
                badgeName: badgeId,
                tier: .bronze,
                category: .milestone,
                requirements: [requirement],
                requireAll: true,
                isComplete: current >= target,
                isSecret: false,
                prerequisitesMet: true
            )
        }
    }

    // MARK: - Computed Properties

    /// Average dimension level
    var averageDimensionLevel: Double {
        let total = dimensions.values.reduce(0) { $0 + $1.level }
        return Double(total) / Double(dimensions.count)
    }

    /// Strongest dimension
    var strongestDimension: LevelDimension? {
        dimensions.max(by: { $0.value.nelo < $1.value.nelo })?.key
    }

    /// Weakest dimension
    var weakestDimension: LevelDimension? {
        dimensions.min(by: { $0.value.nelo < $1.value.nelo })?.key
    }

    /// Whether any dimension is at risk of regression
    var hasRegressionRisk: Bool {
        dimensions.values.contains { $0.regressionWarning }
    }

    /// Dimensions needing attention
    var dimensionsNeedingAttention: [LevelDimension] {
        dimensions.filter { $0.value.regressionWarning }.map { $0.key }
    }

    /// NELO tier classification
    var neloTier: NELOTier {
        NELOTier.from(nelo: neuroELO)
    }

    /// CI tier classification
    var ciTier: CITier {
        CITier.from(level: cosmoIndex)
    }
}

// MARK: - Dimension Progress

/// Progress tracking for a single dimension
struct DimensionProgress: Codable, Sendable {
    let dimension: LevelDimension

    /// Current level in this dimension (1-100)
    private(set) var level: Int

    /// XP progress within current level
    private(set) var xp: Int

    /// Total lifetime XP in this dimension
    private(set) var totalXP: Int

    /// Current NELO rating for this dimension
    private(set) var nelo: Int

    /// NELO history for trend analysis (last 30 days)
    private(set) var neloHistory: [NELODataPoint]

    /// Last active date for this dimension
    private(set) var lastActiveDate: Date

    /// Days since last activity
    var daysSinceActive: Int {
        Calendar.current.dateComponents([.day], from: lastActiveDate, to: Date()).day ?? 0
    }

    /// Whether this dimension is at risk of regression
    var regressionWarning: Bool {
        daysSinceActive >= regressionWarningThreshold
    }

    /// Threshold days before regression warning
    private var regressionWarningThreshold: Int {
        switch dimension {
        case .cognitive: return 3
        case .creative: return 7
        case .physiological: return 2
        case .behavioral: return 2
        case .knowledge: return 14 // Knowledge persists longer
        case .reflection: return 5
        }
    }

    /// XP needed to reach next level
    var xpToNextLevel: Int {
        XPCalculationEngine.xpRequiredForLevel(level + 1) - totalXP
    }

    /// Progress percentage within current level
    var levelProgress: Double {
        let currentLevelXP = XPCalculationEngine.xpRequiredForLevel(level)
        let nextLevelXP = XPCalculationEngine.xpRequiredForLevel(level + 1)
        let xpInLevel = totalXP - currentLevelXP
        let xpForLevel = nextLevelXP - currentLevelXP
        return Double(xpInLevel) / Double(xpForLevel)
    }

    /// NELO trend over last 7 days
    var neloTrend: Trend {
        guard neloHistory.count >= 2 else { return .stable }
        let recent = neloHistory.suffix(7)
        let avgChange = recent.reduce(0) { $0 + $1.change } / recent.count
        if avgChange > 5 { return .improving }
        if avgChange < -5 { return .declining }
        return .stable
    }

    init(
        dimension: LevelDimension,
        level: Int = 1,
        xp: Int = 0,
        totalXP: Int = 0,
        nelo: Int = 1200
    ) {
        self.dimension = dimension
        self.level = level
        self.xp = xp
        self.totalXP = totalXP
        self.nelo = nelo
        self.neloHistory = []
        self.lastActiveDate = Date()
    }

    /// Add XP and check for level up
    mutating func addXP(_ amount: Int) {
        totalXP += amount
        lastActiveDate = Date()

        // Check for level up
        let newLevel = XPCalculationEngine.levelForXP(totalXP)
        if newLevel > level {
            level = newLevel
        }

        // Update xp within current level
        let currentLevelXP = XPCalculationEngine.xpRequiredForLevel(level)
        xp = totalXP - currentLevelXP
    }

    /// Update NELO rating
    mutating func updateNELO(change: Int, triggeredBy: String) {
        let newNelo = max(800, min(2400, nelo + change))
        let dataPoint = NELODataPoint(
            date: Date(),
            nelo: newNelo,
            change: change,
            triggeredBy: triggeredBy
        )

        nelo = newNelo
        neloHistory.append(dataPoint)

        // Keep only last 30 days
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        neloHistory = neloHistory.filter { $0.date > thirtyDaysAgo }

        lastActiveDate = Date()
    }
}

// Note: NELODataPoint is now defined in LevelingMetadata.swift

// MARK: - Streak Tracker

/// Tracks all active streaks
struct StreakTracker: Codable, Sendable {
    /// All tracked streaks
    private(set) var streaks: [StreakType: StreakData] = [:]

    /// Total active streak count
    var activeStreakCount: Int {
        streaks.values.filter { $0.isActive }.count
    }

    /// Longest current streak
    var longestCurrentStreak: Int {
        streaks.values.map { $0.currentCount }.max() ?? 0
    }

    /// Get data for a specific streak
    func streak(_ type: StreakType) -> StreakData? {
        streaks[type]
    }

    /// Increment a streak
    mutating func incrementStreak(_ type: StreakType) {
        if var data = streaks[type] {
            data.increment()
            streaks[type] = data
        } else {
            var data = StreakData(type: type)
            data.increment()
            streaks[type] = data
        }
    }

    /// Break a streak
    mutating func breakStreak(_ type: StreakType) {
        if var data = streaks[type] {
            data.reset()
            streaks[type] = data
        }
    }

    /// Calculate total multiplier from all active streaks
    func calculateTotalMultiplier() -> Double {
        var maxMultiplier = 1.0
        for (_, data) in streaks where data.isActive {
            let streakMultiplier = StreakMultipliers.forStreak(data.currentCount)
            maxMultiplier = max(maxMultiplier, streakMultiplier)
        }
        return maxMultiplier
    }
}

/// Data for a single streak
struct StreakData: Codable, Sendable {
    let type: StreakType
    private(set) var currentCount: Int = 0
    private(set) var longestCount: Int = 0
    private(set) var lastActivityDate: Date?
    private(set) var isActive: Bool = false

    init(type: StreakType) {
        self.type = type
    }

    var currentMultiplier: Double {
        StreakMultipliers.forStreak(currentCount)
    }

    mutating func increment() {
        currentCount += 1
        if currentCount > longestCount {
            longestCount = currentCount
        }
        lastActivityDate = Date()
        isActive = true
    }

    mutating func reset() {
        currentCount = 0
        isActive = false
    }
}

// MARK: - Streak Multipliers

/// Multiplier calculations based on streak length
enum StreakMultipliers {
    static func forStreak(_ days: Int) -> Double {
        switch days {
        case 0...6: return 1.0
        case 7...13: return 1.1      // Week: +10%
        case 14...29: return 1.2     // Two weeks: +20%
        case 30...59: return 1.35    // Month: +35%
        case 60...89: return 1.5     // Two months: +50%
        case 90...179: return 1.75   // Quarter: +75%
        case 180...364: return 2.0   // Half year: +100%
        case 365...999: return 2.5   // Year: +150%
        default: return 3.0          // 1000+ days: +200%
        }
    }

    /// Description of the current multiplier tier
    static func tierName(for days: Int) -> String {
        switch days {
        case 0...6: return "Starting"
        case 7...13: return "Weekly"
        case 14...29: return "Biweekly"
        case 30...59: return "Monthly"
        case 60...89: return "Bimonthly"
        case 90...179: return "Quarterly"
        case 180...364: return "Semiannual"
        case 365...999: return "Annual"
        default: return "Legendary"
        }
    }
}

// MARK: - Badge Types
// Note: BadgeProgress is defined in BadgeProgressTracker.swift
// Note: BadgeRequirement and BadgeDefinition are defined in BadgeDefinitionSystem.swift
// Note: BadgeCategory and BadgeTier are defined in BadgeDefinitionSystem.swift

// MARK: - NELO Tier

/// Classification tiers for NELO ratings
public enum NELOTier: String, Codable, Sendable, CaseIterable {
    case beginner = "Beginner"
    case developing = "Developing"
    case competent = "Competent"
    case proficient = "Proficient"
    case expert = "Expert"
    case master = "Master"
    case grandmaster = "Grandmaster"
    case legend = "Legend"

    static func from(nelo: Int) -> NELOTier {
        switch nelo {
        case ..<1000: return .beginner
        case 1000..<1200: return .developing
        case 1200..<1400: return .competent
        case 1400..<1600: return .proficient
        case 1600..<1800: return .expert
        case 1800..<2000: return .master
        case 2000..<2200: return .grandmaster
        default: return .legend
        }
    }

    var minNELO: Int {
        switch self {
        case .beginner: return 800
        case .developing: return 1000
        case .competent: return 1200
        case .proficient: return 1400
        case .expert: return 1600
        case .master: return 1800
        case .grandmaster: return 2000
        case .legend: return 2200
        }
    }

    var colorHex: String {
        switch self {
        case .beginner: return "#9CA3AF"      // Gray
        case .developing: return "#60A5FA"    // Blue
        case .competent: return "#34D399"     // Green
        case .proficient: return "#FBBF24"    // Yellow
        case .expert: return "#F97316"        // Orange
        case .master: return "#EF4444"        // Red
        case .grandmaster: return "#A855F7"   // Purple
        case .legend: return "#FFD700"        // Gold
        }
    }
}

// MARK: - CI Tier

/// Classification tiers for Cosmo Index
enum CITier: String, Codable, Sendable, CaseIterable {
    case novice = "Novice"
    case apprentice = "Apprentice"
    case journeyman = "Journeyman"
    case adept = "Adept"
    case expert = "Expert"
    case master = "Master"
    case grandmaster = "Grandmaster"
    case sage = "Sage"
    case legend = "Legend"
    case transcendent = "Transcendent"

    static func from(level: Int) -> CITier {
        switch level {
        case 1...10: return .novice
        case 11...20: return .apprentice
        case 21...30: return .journeyman
        case 31...40: return .adept
        case 41...50: return .expert
        case 51...60: return .master
        case 61...70: return .grandmaster
        case 71...80: return .sage
        case 81...90: return .legend
        default: return .transcendent
        }
    }

    var levelRange: ClosedRange<Int> {
        switch self {
        case .novice: return 1...10
        case .apprentice: return 11...20
        case .journeyman: return 21...30
        case .adept: return 31...40
        case .expert: return 41...50
        case .master: return 51...60
        case .grandmaster: return 61...70
        case .sage: return 71...80
        case .legend: return 81...90
        case .transcendent: return 91...100
        }
    }

    var colorHex: String {
        switch self {
        case .novice: return "#9CA3AF"        // Gray
        case .apprentice: return "#60A5FA"    // Blue
        case .journeyman: return "#34D399"    // Green
        case .adept: return "#FBBF24"         // Yellow
        case .expert: return "#F97316"        // Orange
        case .master: return "#EF4444"        // Red
        case .grandmaster: return "#A855F7"   // Purple
        case .sage: return "#EC4899"          // Pink
        case .legend: return "#FFD700"        // Gold
        case .transcendent: return "#E5E4E2"  // Platinum
        }
    }
}

// MARK: - Cached State Model (for GRDB)

/// Database model for cached level state (single row)
public struct CosmoLevelState: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "cosmo_level_state"

    public let id: Int // Always 1

    // Overall
    public var cosmoIndex: Int
    public var overallNelo: Int

    // Dimension CI
    public var cognitiveCI: Int
    public var creativeCI: Int
    public var physiologicalCI: Int
    public var behavioralCI: Int
    public var knowledgeCI: Int
    public var reflectionCI: Int

    // Dimension NELO
    public var cognitiveNELO: Int
    public var creativeNELO: Int
    public var physiologicalNELO: Int
    public var behavioralNELO: Int
    public var knowledgeNELO: Int
    public var reflectionNELO: Int

    // Dimension Levels
    public var cognitiveLevel: Int
    public var creativeLevel: Int
    public var physiologicalLevel: Int
    public var behavioralLevel: Int
    public var knowledgeLevel: Int
    public var reflectionLevel: Int

    // Stats
    public var totalXPEarned: Int
    public var totalBadgesUnlocked: Int
    public var longestStreakEver: Int

    // Timestamps
    public var lastXPAt: Date?
    public var lastLevelUpAt: Date?
    public var lastBadgeAt: Date?
    public var updatedAt: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case cosmoIndex = "cosmo_index"
        case overallNelo = "overall_nelo"
        case cognitiveCI = "cognitive_ci"
        case creativeCI = "creative_ci"
        case physiologicalCI = "physiological_ci"
        case behavioralCI = "behavioral_ci"
        case knowledgeCI = "knowledge_ci"
        case reflectionCI = "reflection_ci"
        case cognitiveNELO = "cognitive_nelo"
        case creativeNELO = "creative_nelo"
        case physiologicalNELO = "physiological_nelo"
        case behavioralNELO = "behavioral_nelo"
        case knowledgeNELO = "knowledge_nelo"
        case reflectionNELO = "reflection_nelo"
        case cognitiveLevel = "cognitive_level"
        case creativeLevel = "creative_level"
        case physiologicalLevel = "physiological_level"
        case behavioralLevel = "behavioral_level"
        case knowledgeLevel = "knowledge_level"
        case reflectionLevel = "reflection_level"
        case totalXPEarned = "total_xp_earned"
        case totalBadgesUnlocked = "total_badges_unlocked"
        case longestStreakEver = "longest_streak_ever"
        case lastXPAt = "last_xp_at"
        case lastLevelUpAt = "last_level_up_at"
        case lastBadgeAt = "last_badge_at"
        case updatedAt = "updated_at"
    }

    /// Default initial state
    static var initial: CosmoLevelState {
        CosmoLevelState(
            id: 1,
            cosmoIndex: 1,
            overallNelo: 1200,
            cognitiveCI: 0,
            creativeCI: 0,
            physiologicalCI: 0,
            behavioralCI: 0,
            knowledgeCI: 0,
            reflectionCI: 0,
            cognitiveNELO: 1200,
            creativeNELO: 1200,
            physiologicalNELO: 1200,
            behavioralNELO: 1200,
            knowledgeNELO: 1200,
            reflectionNELO: 1200,
            cognitiveLevel: 1,
            creativeLevel: 1,
            physiologicalLevel: 1,
            behavioralLevel: 1,
            knowledgeLevel: 1,
            reflectionLevel: 1,
            totalXPEarned: 0,
            totalBadgesUnlocked: 0,
            longestStreakEver: 0,
            lastXPAt: nil,
            lastLevelUpAt: nil,
            lastBadgeAt: nil,
            updatedAt: Date()
        )
    }

    /// Add XP to the total and update timestamp
    public mutating func addXP(_ amount: Int, dimension: String) {
        totalXPEarned += amount
        lastXPAt = Date()
        updatedAt = Date()
    }

    // MARK: - Computed Convenience Properties (for LevelSystemQueryHandler)

    /// XP required to reach the next level
    public var xpRequiredForNextLevel: Int {
        XPCalculationEngine.xpRequiredForLevel(cosmoIndex + 1)
    }

    /// XP earned within the current level
    public var currentLevelXP: Int {
        let currentLevelStart = XPCalculationEngine.xpRequiredForLevel(cosmoIndex)
        return totalXPEarned - currentLevelStart
    }

    /// Alias for totalXPEarned for backward compatibility
    public var lifetimeXP: Int { totalXPEarned }

    /// Alias for overallNelo for backward compatibility
    public var neuroELO: Int { overallNelo }

    /// Dictionary of dimension XP values
    public var dimensionXP: [String: Int] {
        [
            "cognitive": cognitiveCI,
            "creative": creativeCI,
            "physiological": physiologicalCI,
            "behavioral": behavioralCI,
            "knowledge": knowledgeCI,
            "reflection": reflectionCI
        ]
    }

    /// Dictionary of dimension levels
    public var dimensionLevels: [String: Int] {
        [
            "cognitive": cognitiveLevel,
            "creative": creativeLevel,
            "physiological": physiologicalLevel,
            "behavioral": behavioralLevel,
            "knowledge": knowledgeLevel,
            "reflection": reflectionLevel
        ]
    }

    // MARK: - Daily/Weekly/Monthly Stats (placeholder values - real implementation would query XP events)

    /// XP earned today (requires query - returning 0 as placeholder)
    public var todayXP: Int { 0 }

    /// NELO change since yesterday (placeholder)
    public var neuroELOChange: Int { 0 }

    /// Tasks completed today (placeholder)
    public var todayTasksCompleted: Int { 0 }

    /// Focus minutes today (placeholder)
    public var todayFocusMinutes: Int { 0 }

    /// XP earned this week (placeholder)
    public var weekXP: Int { 0 }

    /// Tasks completed this week (placeholder)
    public var weekTasksCompleted: Int { 0 }

    /// Focus minutes this week (placeholder)
    public var weekFocusMinutes: Int { 0 }

    /// XP earned this month (placeholder)
    public var monthXP: Int { 0 }

    /// Levels gained this month (placeholder)
    public var monthLevelsGained: Int { 0 }

    /// Badges earned this month (placeholder)
    public var monthBadgesEarned: Int { 0 }
}
