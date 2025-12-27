import Foundation
import GRDB
import Combine

// MARK: - Level System Events

/// Events emitted by the level system
public enum LevelSystemEvent: Sendable {
    case xpEarned(XPAward)
    case levelUp(LevelUpEvent)
    case neloChanged(NELOChangeEvent)
    case badgeEarned(BadgeEarnedEvent)
    case streakUpdated(StreakUpdateEvent)
    case milestoneReached(MilestoneEvent)
    case dailyCronCompleted(DailyCronReport)
}

public struct LevelUpEvent: Sendable {
    public let previousLevel: Int
    public let newLevel: Int
    public let dimension: String?  // nil for overall
    public let xpAtLevelUp: Int
    public let timestamp: Date

    public init(
        previousLevel: Int,
        newLevel: Int,
        dimension: String? = nil,
        xpAtLevelUp: Int,
        timestamp: Date = Date()
    ) {
        self.previousLevel = previousLevel
        self.newLevel = newLevel
        self.dimension = dimension
        self.xpAtLevelUp = xpAtLevelUp
        self.timestamp = timestamp
    }
}

public struct NELOChangeEvent: Sendable {
    public let dimension: String
    public let previousNELO: Int
    public let newNELO: Int
    public let reason: String
    public let timestamp: Date

    public init(
        dimension: String,
        previousNELO: Int,
        newNELO: Int,
        reason: String,
        timestamp: Date = Date()
    ) {
        self.dimension = dimension
        self.previousNELO = previousNELO
        self.newNELO = newNELO
        self.reason = reason
        self.timestamp = timestamp
    }
}

public struct BadgeEarnedEvent: Sendable {
    public let badge: BadgeDefinition
    public let xpAwarded: Int
    public let timestamp: Date

    public init(badge: BadgeDefinition, xpAwarded: Int, timestamp: Date = Date()) {
        self.badge = badge
        self.xpAwarded = xpAwarded
        self.timestamp = timestamp
    }
}

public struct StreakUpdateEvent: Sendable {
    public let dimension: StreakDimension
    public let previousStreak: Int
    public let newStreak: Int
    public let isBroken: Bool
    public let freezeUsed: Bool
    public let timestamp: Date

    public init(
        dimension: StreakDimension,
        previousStreak: Int,
        newStreak: Int,
        isBroken: Bool = false,
        freezeUsed: Bool = false,
        timestamp: Date = Date()
    ) {
        self.dimension = dimension
        self.previousStreak = previousStreak
        self.newStreak = newStreak
        self.isBroken = isBroken
        self.freezeUsed = freezeUsed
        self.timestamp = timestamp
    }
}

public struct MilestoneEvent: Sendable {
    public let type: MilestoneType
    public let value: Int
    public let dimension: String?
    public let xpBonus: Int
    public let timestamp: Date

    public enum MilestoneType: String, Sendable {
        case streakDays
        case levelReached
        case neloTier
        case totalXP
        case badgeCount
    }

    public init(
        type: MilestoneType,
        value: Int,
        dimension: String? = nil,
        xpBonus: Int,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.value = value
        self.dimension = dimension
        self.xpBonus = xpBonus
        self.timestamp = timestamp
    }
}

// MARK: - Level System Snapshot

/// Complete snapshot of user's level system state
public struct LevelSystemSnapshot: Sendable {
    public let cosmoLevel: Int
    public let totalXP: Int
    public let xpToNextLevel: Int
    public let currentLevelProgress: Double  // 0-1
    public let dimensions: [DimensionSnapshot]
    public let streakSummary: StreakSummary
    public let recentBadges: [BadgeDefinition]
    public let nearestBadges: [BadgeProgress]
    public let overallNELO: Int
    public let neloTier: NELOTier
    public let timestamp: Date

    public init(
        cosmoLevel: Int,
        totalXP: Int,
        xpToNextLevel: Int,
        currentLevelProgress: Double,
        dimensions: [DimensionSnapshot],
        streakSummary: StreakSummary,
        recentBadges: [BadgeDefinition],
        nearestBadges: [BadgeProgress],
        overallNELO: Int,
        neloTier: NELOTier,
        timestamp: Date = Date()
    ) {
        self.cosmoLevel = cosmoLevel
        self.totalXP = totalXP
        self.xpToNextLevel = xpToNextLevel
        self.currentLevelProgress = currentLevelProgress
        self.dimensions = dimensions
        self.streakSummary = streakSummary
        self.recentBadges = recentBadges
        self.nearestBadges = nearestBadges
        self.overallNELO = overallNELO
        self.neloTier = neloTier
        self.timestamp = timestamp
    }
}

public struct DimensionSnapshot: Sendable {
    public let name: String
    public let displayName: String
    public let level: Int
    public let xp: Int
    public let nelo: Int
    public let neloTier: NELOTier
    public let levelProgress: Double
    public let streakDays: Int
    public let isActive: Bool

    public init(
        name: String,
        displayName: String,
        level: Int,
        xp: Int,
        nelo: Int,
        neloTier: NELOTier,
        levelProgress: Double,
        streakDays: Int,
        isActive: Bool
    ) {
        self.name = name
        self.displayName = displayName
        self.level = level
        self.xp = xp
        self.nelo = nelo
        self.neloTier = neloTier
        self.levelProgress = levelProgress
        self.streakDays = streakDays
        self.isActive = isActive
    }
}

// MARK: - Level System Service

/// Main orchestrator for the Cosmo Level System
/// Coordinates all level system components and provides a unified API
@MainActor
public final class LevelSystemService: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var currentSnapshot: LevelSystemSnapshot?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: Error?

    // MARK: - Event Stream

    private let eventSubject = PassthroughSubject<LevelSystemEvent, Never>()
    public var events: AnyPublisher<LevelSystemEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private let database: DatabaseQueue
    private let xpEngine: XPCalculationEngine
    private let neloEngine: NELORegressionEngine
    private let streakEngine: StreakTrackingEngine
    private let badgeTracker: BadgeProgressTracker
    private let cronEngine: DailyCronEngine
    private let metricsCalculator: DimensionMetricsCalculator

    // MARK: - Initialization

    public init(database: DatabaseQueue) {
        self.database = database
        self.xpEngine = XPCalculationEngine()
        self.neloEngine = NELORegressionEngine()
        self.streakEngine = StreakTrackingEngine()
        self.badgeTracker = BadgeProgressTracker()
        self.cronEngine = DailyCronEngine()
        self.metricsCalculator = DimensionMetricsCalculator(dbQueue: database)
    }

    // MARK: - Initialization & Startup

    /// Initialize the level system for first-time users or after reset
    public func initializeLevelSystem() async throws {
        isLoading = true
        defer { isLoading = false }

        try await database.write { db in
            // Create initial level state if not exists
            if try CosmoLevelState.fetchOne(db) == nil {
                let state = CosmoLevelState.initial
                try state.insert(db)
            }

            // Initialize streak caches
            for dimension in StreakDimension.allCases {
                try self.streakEngine.initializeStreakCache(db: db, dimension: dimension)
            }
        }

        // Refresh snapshot
        try await refreshSnapshot()
    }

    /// Check and run any pending daily cron jobs
    public func checkDailyCron() async throws {
        let reports = try await database.write { db in
            try self.cronEngine.catchUpMissedDays(db: db)
        }

        for report in reports {
            eventSubject.send(.dailyCronCompleted(report))
        }

        // Refresh after cron
        if !reports.isEmpty {
            try await refreshSnapshot()
        }
    }

    // MARK: - XP & Level Operations

    /// Award XP for an action
    public func awardXP(for action: XPAction, atomId: String? = nil) async throws -> XPAward {
        let award = try await database.write { db in
            guard var levelState = try CosmoLevelState.fetchOne(db) else {
                throw LevelSystemError.notInitialized
            }

            // Get current streak multiplier
            let streakSummary = try self.streakEngine.getStreakSummary(db: db)
            let streakDays = streakSummary.overallState.currentStreak

            // Calculate XP award using the proper API
            let baseXP = XPCalculationEngine.xpForAction(action)
            let dimension = XPCalculationEngine.dimensionForAction(action)
            let award = XPCalculationEngine.calculateXP(
                baseAmount: baseXP,
                streakDays: streakDays,
                dimension: dimension
            )

            // Update dimension XP and check for level ups
            let previousDimensionLevel: Int
            let _ = levelState.cosmoIndex // previousOverallLevel

            switch dimension {
            case .cognitive:
                previousDimensionLevel = levelState.cognitiveLevel
                levelState.cognitiveCI += award.finalAmount
                levelState.cognitiveLevel = XPCalculationEngine.levelForXP(levelState.cognitiveCI)
            case .creative:
                previousDimensionLevel = levelState.creativeLevel
                levelState.creativeCI += award.finalAmount
                levelState.creativeLevel = XPCalculationEngine.levelForXP(levelState.creativeCI)
            case .physiological:
                previousDimensionLevel = levelState.physiologicalLevel
                levelState.physiologicalCI += award.finalAmount
                levelState.physiologicalLevel = XPCalculationEngine.levelForXP(levelState.physiologicalCI)
            case .behavioral:
                previousDimensionLevel = levelState.behavioralLevel
                levelState.behavioralCI += award.finalAmount
                levelState.behavioralLevel = XPCalculationEngine.levelForXP(levelState.behavioralCI)
            case .knowledge:
                previousDimensionLevel = levelState.knowledgeLevel
                levelState.knowledgeCI += award.finalAmount
                levelState.knowledgeLevel = XPCalculationEngine.levelForXP(levelState.knowledgeCI)
            case .reflection:
                previousDimensionLevel = levelState.reflectionLevel
                levelState.reflectionCI += award.finalAmount
                levelState.reflectionLevel = XPCalculationEngine.levelForXP(levelState.reflectionCI)
            }
            let _ = previousDimensionLevel // suppress unused warning

            // Update total XP and overall level
            levelState.totalXPEarned += award.finalAmount
            levelState.cosmoIndex = XPCalculationEngine.levelForXP(levelState.totalXPEarned)
            levelState.updatedAt = Date()

            try levelState.update(db)

            // Record streak activity
            if let streakDim = StreakDimension(rawValue: dimension.rawValue) {
                _ = try self.streakEngine.recordActivity(
                    db: db,
                    dimension: streakDim,
                    atomId: atomId ?? UUID().uuidString
                )
            }

            return award
        }

        // Emit event
        eventSubject.send(.xpEarned(award))

        // Refresh snapshot
        try await refreshSnapshot()

        return award
    }

    /// Get current XP for a dimension
    public func getXP(for dimension: String) async throws -> Int {
        try await database.read { db in
            guard let state = try CosmoLevelState.fetchOne(db) else {
                throw LevelSystemError.notInitialized
            }

            switch dimension {
            case "cognitive": return state.cognitiveCI
            case "creative": return state.creativeCI
            case "physiological": return state.physiologicalCI
            case "behavioral": return state.behavioralCI
            case "knowledge": return state.knowledgeCI
            case "reflection": return state.reflectionCI
            case "total": return state.totalXPEarned
            default: return 0
            }
        }
    }

    // MARK: - NELO Operations

    /// Update NELO for a dimension based on performance
    public func updateNELO(
        dimension: String,
        performance: Double,  // 0-1 scale
        difficulty: Double = 0.5  // 0-1 scale
    ) async throws {
        let event = try await database.write { db -> NELOChangeEvent? in
            guard var levelState = try CosmoLevelState.fetchOne(db) else {
                throw LevelSystemError.notInitialized
            }

            let previousNELO: Int
            switch dimension {
            case "cognitive": previousNELO = levelState.cognitiveNELO
            case "creative": previousNELO = levelState.creativeNELO
            case "physiological": previousNELO = levelState.physiologicalNELO
            case "behavioral": previousNELO = levelState.behavioralNELO
            case "knowledge": previousNELO = levelState.knowledgeNELO
            case "reflection": previousNELO = levelState.reflectionNELO
            default: return nil
            }

            // Calculate NELO change using ELO-style formula
            let kFactor = NELORegressionEngine.kFactor(forNELO: previousNELO)
            let expectedScore = 1.0 / (1.0 + pow(10.0, Double(1500 - previousNELO) / 400.0))
            let actualScore = performance * difficulty + (1 - difficulty) * 0.5
            let change = Int(Double(kFactor) * (actualScore - expectedScore))

            let newNELO = max(100, min(3000, previousNELO + change))

            if newNELO == previousNELO { return nil }

            // Update state
            switch dimension {
            case "cognitive": levelState.cognitiveNELO = newNELO
            case "creative": levelState.creativeNELO = newNELO
            case "physiological": levelState.physiologicalNELO = newNELO
            case "behavioral": levelState.behavioralNELO = newNELO
            case "knowledge": levelState.knowledgeNELO = newNELO
            case "reflection": levelState.reflectionNELO = newNELO
            default: break
            }

            levelState.updatedAt = Date()
            try levelState.update(db)

            return NELOChangeEvent(
                dimension: dimension,
                previousNELO: previousNELO,
                newNELO: newNELO,
                reason: "Performance update"
            )
        }

        if let event = event {
            eventSubject.send(.neloChanged(event))
            try await refreshSnapshot()
        }
    }

    // MARK: - Badge Operations

    /// Check for newly earned badges
    public func checkBadges() async throws -> [BadgeDefinition] {
        let newBadges = try await database.write { db in
            guard let levelState = try CosmoLevelState.fetchOne(db) else {
                throw LevelSystemError.notInitialized
            }

            let context = try self.badgeTracker.buildContext(db: db, levelState: levelState)
            let newBadges = self.badgeTracker.checkForNewBadges(context: context)

            // Create badge atoms
            for badge in newBadges {
                let badgeAtom = self.badgeTracker.createBadgeAtom(
                    badge: badge,
                    triggeringActionId: nil,
                    progressSnapshot: [:]
                )
                try badgeAtom.insert(db)
            }

            return newBadges
        }

        // Emit events
        for badge in newBadges {
            eventSubject.send(.badgeEarned(BadgeEarnedEvent(
                badge: badge,
                xpAwarded: badge.xpReward
            )))
        }

        if !newBadges.isEmpty {
            try await refreshSnapshot()
        }

        return newBadges
    }

    /// Get badge progress for all badges
    public func getBadgeProgress() async throws -> [BadgeProgress] {
        try await database.read { db in
            guard let levelState = try CosmoLevelState.fetchOne(db) else {
                throw LevelSystemError.notInitialized
            }

            let context = try self.badgeTracker.buildContext(db: db, levelState: levelState)
            return self.badgeTracker.calculateAllProgress(context: context)
        }
    }

    /// Get badges nearly earned
    public func getNearlyEarnedBadges(threshold: Double = 0.75) async throws -> [BadgeProgress] {
        try await database.read { db in
            guard let levelState = try CosmoLevelState.fetchOne(db) else {
                throw LevelSystemError.notInitialized
            }

            let context = try self.badgeTracker.buildContext(db: db, levelState: levelState)
            return self.badgeTracker.nearlyEarnedBadges(context: context, threshold: threshold)
        }
    }

    // MARK: - Streak Operations

    /// Get current streak summary
    public func getStreakSummary() async throws -> StreakSummary {
        try await database.read { db in
            try self.streakEngine.getStreakSummary(db: db)
        }
    }

    /// Get streak state for a specific dimension
    public func getStreakState(for dimension: StreakDimension) async throws -> StreakState {
        try await database.read { db in
            try self.streakEngine.calculateStreakState(db: db, dimension: dimension)
        }
    }

    // MARK: - Snapshot Operations

    /// Refresh the current level system snapshot
    public func refreshSnapshot() async throws {
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await database.read { db -> LevelSystemSnapshot in
            guard let levelState = try CosmoLevelState.fetchOne(db) else {
                throw LevelSystemError.notInitialized
            }

            let streakSummary = try self.streakEngine.getStreakSummary(db: db)
            let badgeContext = try self.badgeTracker.buildContext(db: db, levelState: levelState)
            let nearestBadges = self.badgeTracker.nextAchievableBadges(context: badgeContext, limit: 5)

            // Build dimension snapshots
            let dimensions = self.buildDimensionSnapshots(state: levelState, streaks: streakSummary.dimensionStates)

            // Calculate overall NELO (average of all dimensions)
            let allNelos = [
                levelState.cognitiveNELO,
                levelState.creativeNELO,
                levelState.physiologicalNELO,
                levelState.behavioralNELO,
                levelState.knowledgeNELO,
                levelState.reflectionNELO
            ]
            let overallNELO = allNelos.reduce(0, +) / allNelos.count

            // Calculate level progress
            let currentLevelXP = XPCalculationEngine.xpRequiredForLevel(levelState.cosmoIndex)
            let nextLevelXP = XPCalculationEngine.xpRequiredForLevel(levelState.cosmoIndex + 1)
            let xpInCurrentLevel = levelState.totalXPEarned - currentLevelXP
            let xpNeededForLevel = nextLevelXP - currentLevelXP
            let levelProgress = Double(xpInCurrentLevel) / Double(max(1, xpNeededForLevel))

            // Get recent badges
            let recentBadges = try self.getRecentBadges(db: db, limit: 5)

            return LevelSystemSnapshot(
                cosmoLevel: levelState.cosmoIndex,
                totalXP: levelState.totalXPEarned,
                xpToNextLevel: nextLevelXP - levelState.totalXPEarned,
                currentLevelProgress: levelProgress,
                dimensions: dimensions,
                streakSummary: streakSummary,
                recentBadges: recentBadges,
                nearestBadges: nearestBadges,
                overallNELO: overallNELO,
                neloTier: NELOTier.from(nelo: overallNELO)
            )
        }

        self.currentSnapshot = snapshot
    }

    nonisolated private func buildDimensionSnapshots(state: CosmoLevelState, streaks: [StreakState]) -> [DimensionSnapshot] {
        let dimensionData: [(name: String, displayName: String, level: Int, xp: Int, nelo: Int)] = [
            ("cognitive", "Cognitive", state.cognitiveLevel, state.cognitiveCI, state.cognitiveNELO),
            ("creative", "Creative", state.creativeLevel, state.creativeCI, state.creativeNELO),
            ("physiological", "Physiological", state.physiologicalLevel, state.physiologicalCI, state.physiologicalNELO),
            ("behavioral", "Behavioral", state.behavioralLevel, state.behavioralCI, state.behavioralNELO),
            ("knowledge", "Knowledge", state.knowledgeLevel, state.knowledgeCI, state.knowledgeNELO),
            ("reflection", "Reflection", state.reflectionLevel, state.reflectionCI, state.reflectionNELO)
        ]

        return dimensionData.map { data in
            let streak = streaks.first { $0.dimension.rawValue == data.name }

            let currentLevelXP = XPCalculationEngine.xpRequiredForLevel(data.level)
            let nextLevelXP = XPCalculationEngine.xpRequiredForLevel(data.level + 1)
            let xpInLevel = data.xp - currentLevelXP
            let xpNeeded = nextLevelXP - currentLevelXP
            let progress = Double(xpInLevel) / Double(xpNeeded)

            return DimensionSnapshot(
                name: data.name,
                displayName: data.displayName,
                level: data.level,
                xp: data.xp,
                nelo: data.nelo,
                neloTier: NELOTier.from(nelo: data.nelo),
                levelProgress: progress,
                streakDays: streak?.currentStreak ?? 0,
                isActive: streak?.currentStreak ?? 0 > 0
            )
        }
    }

    nonisolated private func getRecentBadges(db: Database, limit: Int) throws -> [BadgeDefinition] {
        let sql = """
            SELECT json_extract(metadata, '$.badgeId') as badgeId
            FROM atoms
            WHERE type = 'badge'
            AND isDeleted = 0
            ORDER BY createdAt DESC
            LIMIT ?
        """

        let badgeIds = try String.fetchAll(db, sql: sql, arguments: [limit])

        return badgeIds.compactMap { badgeId in
            BadgeDefinitionSystem.shared.badge(withID: badgeId)
        }
    }

    // MARK: - Error Handling

    public func setError(_ error: Error?) {
        self.lastError = error
    }
}

// MARK: - Level System Error

public enum LevelSystemError: LocalizedError {
    case notInitialized
    case invalidDimension(String)
    case databaseError(Error)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Level system has not been initialized"
        case .invalidDimension(let name):
            return "Invalid dimension: \(name)"
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        }
    }
}

// Note: Use XPCalculationEngine.dimensionForAction(action) to get the dimension for an XPAction
// The dimension property is available via that static method which handles all cases correctly
