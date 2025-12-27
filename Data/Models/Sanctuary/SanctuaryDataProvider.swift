// CosmoOS/Data/Models/Sanctuary/SanctuaryDataProvider.swift
// Sanctuary Data Provider - Unified data access for the Sanctuary dashboard
// Provides cached, live-updating data for all Sanctuary visualizations

import Foundation
import GRDB
import Combine

// MARK: - Sanctuary State

/// Complete state for the Sanctuary dashboard
public struct SanctuaryState: Sendable {
    public let timestamp: Date
    public let cosmoIndex: CosmoIndexState
    public let dimensions: [SanctuaryDimensionState]
    public let topInsights: [CorrelationInsight]
    public let liveMetrics: LiveMetrics
    public let trends: TrendData

    /// Overall health score (0-100)
    public var overallHealth: Double {
        let avgNelo = dimensions.map { Double($0.nelo) }.reduce(0, +) / Double(dimensions.count)
        return min(100, avgNelo / 20)  // NELO ~2000 = 100% health
    }
}

/// Current Cosmo Index state
public struct CosmoIndexState: Codable, Sendable {
    public let level: Int
    public let currentXP: Int64
    public let xpToNextLevel: Int64
    public let xpProgress: Double  // 0-1
    public let totalXP: Int64
    public let rank: String        // "Novice", "Adept", etc.
}

/// State for a single dimension (for Sanctuary UI display)
public struct SanctuaryDimensionState: Codable, Sendable, Identifiable {
    public let dimension: LevelDimension
    public let level: Int
    public let nelo: Int
    public let currentXP: Int64
    public let xpToNextLevel: Int64
    public let xpProgress: Double
    public let streak: Int
    public let lastActivity: Date?
    public let trend: Trend         // up, down, stable
    public let isActive: Bool       // Activity in last 24h

    public var id: String { dimension.rawValue }

    public init(
        dimension: LevelDimension,
        level: Int,
        nelo: Int,
        currentXP: Int64,
        xpToNextLevel: Int64,
        xpProgress: Double,
        streak: Int,
        lastActivity: Date?,
        trend: Trend,
        isActive: Bool
    ) {
        self.dimension = dimension
        self.level = level
        self.nelo = nelo
        self.currentXP = currentXP
        self.xpToNextLevel = xpToNextLevel
        self.xpProgress = xpProgress
        self.streak = streak
        self.lastActivity = lastActivity
        self.trend = trend
        self.isActive = isActive
    }
}

// Note: Trend enum is defined in LevelingMetadata.swift

/// Live metrics from real-time data
public struct LiveMetrics: Codable, Sendable {
    public let currentHRV: Double?
    public let lastHRVTime: Date?
    public let todayXP: Int64
    public let activeStreak: Int
    public let todayFocusMinutes: Int
    public let todayWordCount: Int
}

/// Trend data over time
public struct TrendData: Codable, Sendable {
    public let weeklyXPHistory: [Int64]   // Last 7 days
    public let weeklyNeloHistory: [[String: Int]]  // dimension -> NELO per day
    public let improvingDimensions: [LevelDimension]
    public let decliningDimensions: [LevelDimension]
}

// MARK: - Cache Configuration

/// Cache timing configuration
public struct SanctuaryCacheConfig {
    public static let dimensionLevelsTTL: TimeInterval = 5 * 60      // 5 minutes
    public static let correlationInsightsTTL: TimeInterval = 24 * 60 * 60  // 24 hours
    public static let liveMetricsTTL: TimeInterval = 30              // 30 seconds
    public static let trendsTTL: TimeInterval = 60 * 60              // 1 hour
}

// MARK: - Sanctuary Data Provider

/// Main data provider for the Sanctuary dashboard.
///
/// Integrates with:
/// - LivingIntelligenceEngine: For lifecycle-managed insights that evolve over time
/// - CausalityEngine: For statistical correlation analysis
/// - Database: For dimension states, live metrics, and trends
///
/// The Living Intelligence integration makes Sanctuary feel "alive" - insights
/// strengthen when validated by new data, or decay when no longer relevant.
@MainActor
public final class SanctuaryDataProvider: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var state: SanctuaryState?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: Error?

    /// Living insights from the intelligence engine (with lifecycle states)
    @Published public private(set) var livingInsights: [LivingInsight] = []

    /// Whether new insights are available (from last sync)
    @Published public private(set) var hasNewInsights: Bool = false

    // MARK: - Dependencies

    private let database: any DatabaseWriter
    private let causalityEngine: CausalityEngine
    private let livingIntelligence: LivingIntelligenceEngine
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?

    // MARK: - Cache

    private var cachedDimensionLevels: (data: [SanctuaryDimensionState], timestamp: Date)?
    private var cachedInsights: (data: [CorrelationInsight], timestamp: Date)?
    private var cachedTrends: (data: TrendData, timestamp: Date)?

    // MARK: - Initialization

    @MainActor
    public init(
        database: (any DatabaseWriter)? = nil,
        causalityEngine: CausalityEngine? = nil,
        livingIntelligence: LivingIntelligenceEngine? = nil
    ) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
        self.causalityEngine = causalityEngine ?? CausalityEngine()
        self.livingIntelligence = livingIntelligence ?? LivingIntelligenceEngine.shared

        // Subscribe to living intelligence updates
        setupLivingIntelligenceSubscription()
    }

    private func setupLivingIntelligenceSubscription() {
        // Subscribe to insight updates from LivingIntelligenceEngine
        livingIntelligence.$insights
            .receive(on: DispatchQueue.main)
            .assign(to: &$livingInsights)

        livingIntelligence.$hasNewInsights
            .receive(on: DispatchQueue.main)
            .assign(to: &$hasNewInsights)
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Loading

    /// Load complete Sanctuary state
    public func loadState() async {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil

        do {
            async let cosmoIndex = loadCosmoIndex()
            async let dimensions = loadDimensionStates()
            async let insights = loadTopInsights()
            async let liveMetrics = loadLiveMetrics()
            async let trends = loadTrends()

            let state = SanctuaryState(
                timestamp: Date(),
                cosmoIndex: try await cosmoIndex,
                dimensions: try await dimensions,
                topInsights: try await insights,
                liveMetrics: try await liveMetrics,
                trends: try await trends
            )

            self.state = state
        } catch {
            lastError = error
        }

        isLoading = false
    }

    /// Start live updates
    public func startLiveUpdates() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await loadState()
                try? await Task.sleep(nanoseconds: UInt64(SanctuaryCacheConfig.liveMetricsTTL * 1_000_000_000))
            }
        }
    }

    /// Stop live updates
    public func stopLiveUpdates() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Start the Living Intelligence engine for telepathic insights
    public func startLivingIntelligence() async {
        await livingIntelligence.start()
    }

    /// Stop the Living Intelligence engine
    public func stopLivingIntelligence() {
        livingIntelligence.stop()
    }

    /// Force a sync of the Living Intelligence engine
    public func forceLivingIntelligenceSync() async {
        await livingIntelligence.runSync(force: true)
    }

    // MARK: - Living Insight Access

    /// Get top living insights for display (with lifecycle states)
    public func getTopLivingInsights(limit: Int = 5) -> [LivingInsight] {
        livingIntelligence.getTopInsights(limit: limit)
    }

    /// Get living insights for a specific dimension
    public func getLivingInsights(for dimension: LevelDimension) -> [LivingInsight] {
        livingIntelligence.getInsights(for: dimension)
    }

    /// Get only fresh (new) insights
    public func getFreshInsights() -> [LivingInsight] {
        livingIntelligence.getFreshInsights()
    }

    /// Get actionable insights
    public func getActionableInsights() -> [LivingInsight] {
        livingIntelligence.getActionableInsights()
    }

    /// Pin an insight (prevents auto-removal)
    public func pinInsight(_ id: String) async {
        await livingIntelligence.pinInsight(id)
    }

    /// Dismiss an insight
    public func dismissInsight(_ id: String) async {
        await livingIntelligence.dismissInsight(id)
    }

    /// Mark an insight as viewed
    public func markInsightViewed(_ id: String) async {
        await livingIntelligence.markViewed(id)
    }

    /// Get the last sync state
    public var lastSyncState: IntelligenceSyncState? {
        livingIntelligence.lastSyncState
    }

    /// Whether the intelligence engine is currently syncing
    public var isIntelligenceSyncing: Bool {
        livingIntelligence.isSyncing
    }

    // MARK: - Cosmo Index

    private func loadCosmoIndex() async throws -> CosmoIndexState {
        try await database.read { db in
            guard let levelState = try CosmoLevelState.fetchOne(db) else {
                return CosmoIndexState(
                    level: 1,
                    currentXP: 0,
                    xpToNextLevel: 100,
                    xpProgress: 0,
                    totalXP: 0,
                    rank: "Novice"
                )
            }

            let xpForNextLevel = self.xpForLevel(levelState.cosmoIndex + 1)
            let xpForCurrentLevel = self.xpForLevel(levelState.cosmoIndex)
            let currentLevelXP = levelState.totalXPEarned - xpForCurrentLevel
            let xpNeeded = xpForNextLevel - xpForCurrentLevel

            return CosmoIndexState(
                level: levelState.cosmoIndex,
                currentXP: Int64(currentLevelXP),
                xpToNextLevel: Int64(xpNeeded),
                xpProgress: Double(currentLevelXP) / Double(max(xpNeeded, 1)),
                totalXP: Int64(levelState.totalXPEarned),
                rank: self.rankForLevel(levelState.cosmoIndex)
            )
        }
    }

    // MARK: - Dimension States

    private func loadDimensionStates() async throws -> [SanctuaryDimensionState] {
        // Check cache
        if let cached = cachedDimensionLevels,
           Date().timeIntervalSince(cached.timestamp) < SanctuaryCacheConfig.dimensionLevelsTTL {
            return cached.data
        }

        let states = try await database.read { db -> [SanctuaryDimensionState] in
            guard let levelState = try CosmoLevelState.fetchOne(db) else {
                return LevelDimension.allCases.map { dimension in
                    SanctuaryDimensionState(
                        dimension: dimension,
                        level: 1,
                        nelo: 1000,
                        currentXP: 0,
                        xpToNextLevel: 100,
                        xpProgress: 0,
                        streak: 0,
                        lastActivity: nil,
                        trend: .stable,
                        isActive: false
                    )
                }
            }

            return LevelDimension.allCases.map { dimension in
                let (level, xp, nelo) = self.extractDimensionData(from: levelState, dimension: dimension)

                let xpForNext = self.xpForLevel(level + 1)
                let xpForCurrent = self.xpForLevel(level)
                let currentLevelXP = xp - xpForCurrent
                let xpNeeded = xpForNext - xpForCurrent

                // Check for activity in last 24 hours
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
                let hasRecentActivity = (try? self.hasActivityForDimension(db: db, dimension: dimension, since: yesterday)) ?? false

                return SanctuaryDimensionState(
                    dimension: dimension,
                    level: level,
                    nelo: nelo,
                    currentXP: Int64(currentLevelXP),
                    xpToNextLevel: Int64(xpNeeded),
                    xpProgress: Double(currentLevelXP) / Double(max(xpNeeded, 1)),
                    streak: 0,           // Streak is tracked separately by StreakTrackingEngine
                    lastActivity: nil,   // Would need to query
                    trend: .stable,      // Would calculate from history
                    isActive: hasRecentActivity
                )
            }
        }

        cachedDimensionLevels = (states, Date())
        return states
    }

    nonisolated private func extractDimensionData(
        from state: CosmoLevelState,
        dimension: LevelDimension
    ) -> (level: Int, xp: Int, nelo: Int) {
        switch dimension {
        case .cognitive:
            return (state.cognitiveLevel, state.cognitiveCI, state.cognitiveNELO)
        case .creative:
            return (state.creativeLevel, state.creativeCI, state.creativeNELO)
        case .physiological:
            return (state.physiologicalLevel, state.physiologicalCI, state.physiologicalNELO)
        case .behavioral:
            return (state.behavioralLevel, state.behavioralCI, state.behavioralNELO)
        case .knowledge:
            return (state.knowledgeLevel, state.knowledgeCI, state.knowledgeNELO)
        case .reflection:
            return (state.reflectionLevel, state.reflectionCI, state.reflectionNELO)
        }
    }

    nonisolated private func hasActivityForDimension(db: Database, dimension: LevelDimension, since: Date) throws -> Bool {
        let types = atomTypesForDimension(dimension)
        let typesSQL = types.map { "'\($0.rawValue)'" }.joined(separator: ", ")

        let count = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type IN (\(typesSQL))
            AND created_at >= ?
            AND is_deleted = 0
        """, arguments: [since.ISO8601Format()]) ?? 0

        return count > 0
    }

    nonisolated private func atomTypesForDimension(_ dimension: LevelDimension) -> [AtomType] {
        switch dimension {
        case .cognitive:
            return [.task, .deepWorkBlock, .focusScore, .writingSession]
        case .creative:
            return [.content, .contentDraft, .contentPerformance, .idea]
        case .physiological:
            return [.hrvMeasurement, .sleepCycle, .workoutSession, .readinessScore]
        case .behavioral:
            return [.scheduleBlock, .routineDefinition, .task]
        case .knowledge:
            return [.research, .connection, .semanticCluster]
        case .reflection:
            return [.journalEntry, .emotionalState, .clarityScore]
        }
    }

    // MARK: - Insights

    private func loadTopInsights() async throws -> [CorrelationInsight] {
        // Check cache
        if let cached = cachedInsights,
           Date().timeIntervalSince(cached.timestamp) < SanctuaryCacheConfig.correlationInsightsTTL {
            return cached.data
        }

        let insights = try await causalityEngine.getTopInsights(limit: 5)
        cachedInsights = (insights, Date())
        return insights
    }

    /// Get insights for a specific dimension
    public func insightsForDimension(_ dimension: LevelDimension) async throws -> [CorrelationInsight] {
        try await causalityEngine.getInsights(for: dimension)
    }

    // MARK: - Live Metrics

    private func loadLiveMetrics() async throws -> LiveMetrics {
        try await database.read { db in
            let today = Calendar.current.startOfDay(for: Date())

            // Get latest HRV
            let latestHRV = try Atom
                .filter(Column("type") == AtomType.hrvMeasurement.rawValue)
                .filter(Column("is_deleted") == false)
                .order(Column("created_at").desc)
                .fetchOne(db)

            var currentHRV: Double?
            var lastHRVTime: Date?

            if let hrvAtom = latestHRV,
               let metadata = hrvAtom.metadataDict,
               let hrv = metadata["hrv"] as? Double {
                currentHRV = hrv
                lastHRVTime = ISO8601DateFormatter().date(from: hrvAtom.createdAt)
            }

            // Get today's XP
            let todayXP = try Int64.fetchOne(db, sql: """
                SELECT COALESCE(SUM(json_extract(metadata, '$.xpAmount')), 0) FROM atoms
                WHERE type = ?
                AND created_at >= ?
                AND is_deleted = 0
            """, arguments: [AtomType.xpEvent.rawValue, today.ISO8601Format()]) ?? 0

            // Get active streak - streaks are tracked separately by StreakTrackingEngine
            // Using longestStreakEver from CosmoLevelState as a fallback
            let levelState = try CosmoLevelState.fetchOne(db)
            let activeStreak = levelState?.longestStreakEver ?? 0

            // Get today's focus minutes
            let todayFocus = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(json_extract(metadata, '$.durationMinutes')), 0) FROM atoms
                WHERE type = ?
                AND created_at >= ?
                AND is_deleted = 0
            """, arguments: [AtomType.deepWorkBlock.rawValue, today.ISO8601Format()]) ?? 0

            // Get today's word count
            let todayWords = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(json_extract(metadata, '$.wordCount')), 0) FROM atoms
                WHERE type IN (?, ?)
                AND created_at >= ?
                AND is_deleted = 0
            """, arguments: [AtomType.writingSession.rawValue, AtomType.wordCountEntry.rawValue, today.ISO8601Format()]) ?? 0

            return LiveMetrics(
                currentHRV: currentHRV,
                lastHRVTime: lastHRVTime,
                todayXP: todayXP,
                activeStreak: activeStreak,
                todayFocusMinutes: todayFocus,
                todayWordCount: todayWords
            )
        }
    }

    // MARK: - Trends

    private func loadTrends() async throws -> TrendData {
        // Check cache
        if let cached = cachedTrends,
           Date().timeIntervalSince(cached.timestamp) < SanctuaryCacheConfig.trendsTTL {
            return cached.data
        }

        let trends = try await database.read { db in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            // Get weekly XP history
            var weeklyXP: [Int64] = []
            for dayOffset in (0..<7).reversed() {
                guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: today),
                      let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                    weeklyXP.append(0)
                    continue
                }

                let dayXP = try Int64.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(json_extract(metadata, '$.xpAmount')), 0) FROM atoms
                    WHERE type = ?
                    AND created_at >= ? AND created_at < ?
                    AND is_deleted = 0
                """, arguments: [AtomType.xpEvent.rawValue, dayStart.ISO8601Format(), dayEnd.ISO8601Format()]) ?? 0

                weeklyXP.append(dayXP)
            }

            // Simplified trend calculation
            let improving: [LevelDimension] = []
            let declining: [LevelDimension] = []

            return TrendData(
                weeklyXPHistory: weeklyXP,
                weeklyNeloHistory: [],
                improvingDimensions: improving,
                decliningDimensions: declining
            )
        }

        cachedTrends = (trends, Date())
        return trends
    }

    // MARK: - Helpers

    nonisolated private func xpForLevel(_ level: Int) -> Int {
        // Quadratic XP curve: level^2 * 50
        return level * level * 50
    }

    nonisolated private func rankForLevel(_ level: Int) -> String {
        switch level {
        case 1...5: return "Novice"
        case 6...10: return "Apprentice"
        case 11...20: return "Adept"
        case 21...35: return "Expert"
        case 36...50: return "Master"
        case 51...75: return "Grandmaster"
        case 76...99: return "Legend"
        default: return "Transcendent"
        }
    }

    // MARK: - Cache Invalidation

    /// Invalidate all caches
    public func invalidateCache() {
        cachedDimensionLevels = nil
        cachedInsights = nil
        cachedTrends = nil
    }

    /// Invalidate dimension cache only
    public func invalidateDimensionCache() {
        cachedDimensionLevels = nil
    }

    /// Invalidate insights cache only
    public func invalidateInsightsCache() {
        cachedInsights = nil
    }
}

// MARK: - Dimension State Stream

/// Provides a Combine stream for dimension state updates
@MainActor
public final class DimensionStateStream: ObservableObject {

    @Published public private(set) var dimensions: [SanctuaryDimensionState] = []

    private let provider: SanctuaryDataProvider
    private var cancellables = Set<AnyCancellable>()

    public init(provider: SanctuaryDataProvider) {
        self.provider = provider

        // Subscribe to provider updates
        provider.$state
            .compactMap { $0?.dimensions }
            .receive(on: DispatchQueue.main)
            .assign(to: &$dimensions)
    }

    /// Get state for a specific dimension
    public func state(for dimension: LevelDimension) -> SanctuaryDimensionState? {
        dimensions.first { $0.dimension == dimension }
    }
}

// MARK: - Insight Stream

/// Provides a Combine stream for insight updates
@MainActor
public final class InsightStream: ObservableObject {

    @Published public private(set) var insights: [CorrelationInsight] = []
    @Published public private(set) var featuredInsight: CorrelationInsight?

    private let provider: SanctuaryDataProvider
    private var cancellables = Set<AnyCancellable>()

    public init(provider: SanctuaryDataProvider) {
        self.provider = provider

        // Subscribe to provider updates
        provider.$state
            .compactMap { $0?.topInsights }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] insights in
                self?.insights = insights
                self?.featuredInsight = insights.first
            }
            .store(in: &cancellables)
    }

    /// Cycle to the next featured insight
    public func nextFeaturedInsight() {
        guard insights.count > 1 else { return }

        if let current = featuredInsight,
           let index = insights.firstIndex(where: { $0.uuid == current.uuid }) {
            let nextIndex = (index + 1) % insights.count
            featuredInsight = insights[nextIndex]
        } else {
            featuredInsight = insights.first
        }
    }
}

// MARK: - Living Insight Stream

/// Provides a Combine stream for living insight updates with lifecycle states.
/// This is the "telepathic" version of InsightStream that makes Sanctuary feel alive.
@MainActor
public final class LivingInsightStream: ObservableObject {

    @Published public private(set) var insights: [LivingInsight] = []
    @Published public private(set) var featuredInsight: LivingInsight?
    @Published public private(set) var hasNewInsights: Bool = false
    @Published public private(set) var newInsightCount: Int = 0

    private let provider: SanctuaryDataProvider
    private var cancellables = Set<AnyCancellable>()

    public init(provider: SanctuaryDataProvider) {
        self.provider = provider

        // Subscribe to living insights
        provider.$livingInsights
            .receive(on: DispatchQueue.main)
            .sink { [weak self] insights in
                self?.insights = insights
                self?.featuredInsight = insights.first
            }
            .store(in: &cancellables)

        // Subscribe to new insight notifications
        provider.$hasNewInsights
            .receive(on: DispatchQueue.main)
            .assign(to: &$hasNewInsights)
    }

    /// Get fresh (newly discovered) insights
    public var freshInsights: [LivingInsight] {
        insights.filter { $0.lifecycleState == .fresh }
    }

    /// Get established (high-confidence) insights
    public var establishedInsights: [LivingInsight] {
        insights.filter { $0.lifecycleState == .established }
    }

    /// Get stale or decaying insights
    public var decayingInsights: [LivingInsight] {
        insights.filter { $0.lifecycleState == .stale || $0.lifecycleState == .decaying }
    }

    /// Get insights for a specific dimension
    public func insights(for dimension: LevelDimension) -> [LivingInsight] {
        insights.filter { $0.dimensions.contains(dimension) }
    }

    /// Get cross-dimensional insights (span 2+ dimensions)
    public var crossDimensionalInsights: [LivingInsight] {
        insights.filter { $0.dimensions.count >= 2 }
    }

    /// Cycle to the next featured insight
    public func nextFeaturedInsight() {
        guard insights.count > 1 else { return }

        if let current = featuredInsight,
           let index = insights.firstIndex(where: { $0.id == current.id }) {
            let nextIndex = (index + 1) % insights.count
            featuredInsight = insights[nextIndex]
        } else {
            featuredInsight = insights.first
        }
    }

    /// Pin the currently featured insight
    public func pinFeatured() async {
        guard let featured = featuredInsight else { return }
        await provider.pinInsight(featured.id)
    }

    /// Dismiss the currently featured insight
    public func dismissFeatured() async {
        guard let featured = featuredInsight else { return }
        await provider.dismissInsight(featured.id)
        nextFeaturedInsight()
    }

    /// Mark the currently featured insight as viewed
    public func markFeaturedViewed() async {
        guard let featured = featuredInsight else { return }
        await provider.markInsightViewed(featured.id)
    }
}

// MARK: - Unified Sanctuary Streams

/// Provides all Sanctuary data streams in one place for convenience
@MainActor
public final class SanctuaryStreams: ObservableObject {

    public let dimensionStream: DimensionStateStream
    public let insightStream: InsightStream
    public let livingInsightStream: LivingInsightStream

    private let provider: SanctuaryDataProvider

    public init(provider: SanctuaryDataProvider) {
        self.provider = provider
        self.dimensionStream = DimensionStateStream(provider: provider)
        self.insightStream = InsightStream(provider: provider)
        self.livingInsightStream = LivingInsightStream(provider: provider)
    }

    /// Start all live data feeds
    public func startAll() async {
        provider.startLiveUpdates()
        await provider.startLivingIntelligence()
    }

    /// Stop all live data feeds
    public func stopAll() {
        provider.stopLiveUpdates()
        provider.stopLivingIntelligence()
    }

    /// Force a full refresh of all data
    public func refreshAll() async {
        await provider.loadState()
        await provider.forceLivingIntelligenceSync()
    }
}
