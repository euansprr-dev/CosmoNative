import Foundation
import GRDB

// MARK: - Daily Cron Job Types

/// Types of daily cron jobs
public enum DailyCronJobType: String, Codable, CaseIterable, Sendable {
    case neloRegression           // Apply NELO regression for inactive dimensions
    case streakCheck              // Check and break expired streaks
    case dimensionSnapshot        // Create daily dimension snapshots
    case badgeCheck               // Check for newly earned badges
    case levelRecalculation       // Recalculate levels from XP
    case cacheCleanup             // Clean up old cache entries
    case analyticsAggregation     // Aggregate daily analytics
    case causalityComputation     // Run 90-day correlation analysis for Sanctuary
    case semanticExtraction       // Extract semantics from unprocessed journals
}

// MARK: - Cron Job Result

/// Result of a single cron job execution
public struct CronJobResult: Codable, Sendable {
    public let jobType: DailyCronJobType
    public let startTime: Date
    public let endTime: Date
    public let success: Bool
    public let itemsProcessed: Int
    public let changes: [CronJobChange]
    public let errorMessage: String?

    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    public init(
        jobType: DailyCronJobType,
        startTime: Date,
        endTime: Date,
        success: Bool,
        itemsProcessed: Int,
        changes: [CronJobChange],
        errorMessage: String? = nil
    ) {
        self.jobType = jobType
        self.startTime = startTime
        self.endTime = endTime
        self.success = success
        self.itemsProcessed = itemsProcessed
        self.changes = changes
        self.errorMessage = errorMessage
    }
}

/// A single change made by a cron job
public struct CronJobChange: Codable, Sendable {
    public let changeType: String
    public let dimension: String?
    public let previousValue: Double?
    public let newValue: Double?
    public let description: String

    public init(
        changeType: String,
        dimension: String? = nil,
        previousValue: Double? = nil,
        newValue: Double? = nil,
        description: String
    ) {
        self.changeType = changeType
        self.dimension = dimension
        self.previousValue = previousValue
        self.newValue = newValue
        self.description = description
    }
}

// MARK: - Daily Cron Report

/// Complete report of all daily cron jobs
public struct DailyCronReport: Codable, Sendable {
    public let date: Date
    public let jobResults: [CronJobResult]
    public let totalDuration: TimeInterval
    public let allSucceeded: Bool
    public let summary: CronReportSummary

    public init(
        date: Date,
        jobResults: [CronJobResult],
        totalDuration: TimeInterval,
        summary: CronReportSummary
    ) {
        self.date = date
        self.jobResults = jobResults
        self.totalDuration = totalDuration
        self.allSucceeded = jobResults.allSatisfy { $0.success }
        self.summary = summary
    }
}

/// Summary statistics for cron report
public struct CronReportSummary: Codable, Sendable {
    public let neloRegressionsApplied: Int
    public let streaksBroken: Int
    public let freezesUsed: Int
    public let badgesEarned: Int
    public let levelsGained: Int
    public let snapshotsCreated: Int
    public let correlationsDiscovered: Int
    public let insightsValidated: Int
    public let journalsProcessed: Int

    public init(
        neloRegressionsApplied: Int = 0,
        streaksBroken: Int = 0,
        freezesUsed: Int = 0,
        badgesEarned: Int = 0,
        levelsGained: Int = 0,
        snapshotsCreated: Int = 0,
        correlationsDiscovered: Int = 0,
        insightsValidated: Int = 0,
        journalsProcessed: Int = 0
    ) {
        self.neloRegressionsApplied = neloRegressionsApplied
        self.streaksBroken = streaksBroken
        self.freezesUsed = freezesUsed
        self.badgesEarned = badgesEarned
        self.levelsGained = levelsGained
        self.snapshotsCreated = snapshotsCreated
        self.correlationsDiscovered = correlationsDiscovered
        self.insightsValidated = insightsValidated
        self.journalsProcessed = journalsProcessed
    }
}

// MARK: - Daily Activity Metrics

/// Simple activity metrics for daily cron jobs
private struct DailyActivityMetrics {
    let dimension: String
    let activityCount: Int
    let qualityScore: Double
    let isActive: Bool
}

// MARK: - Daily Cron Engine

/// Engine that runs daily maintenance tasks for the level system
/// Should be triggered at midnight or on app launch if not run today
/// Note: @unchecked Sendable because engines are immutable after initialization
public final class DailyCronEngine: @unchecked Sendable {

    private let neloEngine: NELORegressionEngine
    private let streakEngine: StreakTrackingEngine
    private let badgeTracker: BadgeProgressTracker
    private let xpEngine: XPCalculationEngine
    private let metricsCalculator: DimensionMetricsCalculator

    @MainActor
    public init(
        dbQueue: DatabaseQueue? = nil,
        neloEngine: NELORegressionEngine = NELORegressionEngine(),
        streakEngine: StreakTrackingEngine = StreakTrackingEngine(),
        badgeTracker: BadgeProgressTracker = BadgeProgressTracker(),
        xpEngine: XPCalculationEngine = XPCalculationEngine(),
        metricsCalculator: DimensionMetricsCalculator? = nil
    ) {
        self.neloEngine = neloEngine
        self.streakEngine = streakEngine
        self.badgeTracker = badgeTracker
        self.xpEngine = xpEngine
        let queue = dbQueue ?? CosmoDatabase.shared.dbQueue!
        self.metricsCalculator = metricsCalculator ?? DimensionMetricsCalculator(dbQueue: queue)
    }

    // MARK: - Main Execution

    /// Run all daily cron jobs
    public func runDailyCron(db: Database, forDate date: Date = Date()) throws -> DailyCronReport {
        let overallStart = Date()
        var jobResults: [CronJobResult] = []
        var summary = CronReportSummary()

        // Check if already run today
        if try hasRunToday(db: db, date: date) {
            return DailyCronReport(
                date: date,
                jobResults: [],
                totalDuration: 0,
                summary: summary
            )
        }

        // Run jobs in order
        let jobOrder: [DailyCronJobType] = [
            .streakCheck,
            .neloRegression,
            .dimensionSnapshot,
            .badgeCheck,
            .levelRecalculation,
            .analyticsAggregation,
            .semanticExtraction,      // Extract journal semantics before correlation
            .causalityComputation,    // Run 90-day correlation analysis
            .cacheCleanup
        ]

        for jobType in jobOrder {
            let result = try runJob(jobType, db: db, date: date, summary: &summary)
            jobResults.append(result)
        }

        // Record that cron has run today
        try recordCronRun(db: db, date: date, report: jobResults)

        let totalDuration = Date().timeIntervalSince(overallStart)

        return DailyCronReport(
            date: date,
            jobResults: jobResults,
            totalDuration: totalDuration,
            summary: summary
        )
    }

    /// Run a specific job
    private func runJob(
        _ jobType: DailyCronJobType,
        db: Database,
        date: Date,
        summary: inout CronReportSummary
    ) throws -> CronJobResult {
        let startTime = Date()
        var changes: [CronJobChange] = []
        var itemsProcessed = 0
        var errorMessage: String?

        do {
            switch jobType {
            case .streakCheck:
                let streakChanges = try runStreakCheck(db: db, date: date)
                changes = streakChanges.changes
                itemsProcessed = streakChanges.processed
                summary = CronReportSummary(
                    neloRegressionsApplied: summary.neloRegressionsApplied,
                    streaksBroken: streakChanges.broken,
                    freezesUsed: streakChanges.freezesUsed,
                    badgesEarned: summary.badgesEarned,
                    levelsGained: summary.levelsGained,
                    snapshotsCreated: summary.snapshotsCreated
                )

            case .neloRegression:
                let neloChanges = try runNeloRegression(db: db, date: date)
                changes = neloChanges.changes
                itemsProcessed = neloChanges.processed
                summary = CronReportSummary(
                    neloRegressionsApplied: neloChanges.regressionsApplied,
                    streaksBroken: summary.streaksBroken,
                    freezesUsed: summary.freezesUsed,
                    badgesEarned: summary.badgesEarned,
                    levelsGained: summary.levelsGained,
                    snapshotsCreated: summary.snapshotsCreated
                )

            case .dimensionSnapshot:
                let snapshotCount = try runDimensionSnapshot(db: db, date: date)
                itemsProcessed = snapshotCount
                summary = CronReportSummary(
                    neloRegressionsApplied: summary.neloRegressionsApplied,
                    streaksBroken: summary.streaksBroken,
                    freezesUsed: summary.freezesUsed,
                    badgesEarned: summary.badgesEarned,
                    levelsGained: summary.levelsGained,
                    snapshotsCreated: snapshotCount
                )

            case .badgeCheck:
                let badgeCount = try runBadgeCheck(db: db, date: date)
                itemsProcessed = badgeCount
                summary = CronReportSummary(
                    neloRegressionsApplied: summary.neloRegressionsApplied,
                    streaksBroken: summary.streaksBroken,
                    freezesUsed: summary.freezesUsed,
                    badgesEarned: badgeCount,
                    levelsGained: summary.levelsGained,
                    snapshotsCreated: summary.snapshotsCreated
                )

            case .levelRecalculation:
                let levelChanges = try runLevelRecalculation(db: db)
                changes = levelChanges.changes
                itemsProcessed = levelChanges.processed

            case .analyticsAggregation:
                itemsProcessed = try runAnalyticsAggregation(db: db, date: date)

            case .semanticExtraction:
                let processed = try runSemanticExtraction(db: db, date: date)
                itemsProcessed = processed
                summary = CronReportSummary(
                    neloRegressionsApplied: summary.neloRegressionsApplied,
                    streaksBroken: summary.streaksBroken,
                    freezesUsed: summary.freezesUsed,
                    badgesEarned: summary.badgesEarned,
                    levelsGained: summary.levelsGained,
                    snapshotsCreated: summary.snapshotsCreated,
                    correlationsDiscovered: summary.correlationsDiscovered,
                    insightsValidated: summary.insightsValidated,
                    journalsProcessed: processed
                )

            case .causalityComputation:
                let causalityResult = try runCausalityComputation(db: db, date: date)
                itemsProcessed = causalityResult.metricsAnalyzed
                changes = causalityResult.changes
                summary = CronReportSummary(
                    neloRegressionsApplied: summary.neloRegressionsApplied,
                    streaksBroken: summary.streaksBroken,
                    freezesUsed: summary.freezesUsed,
                    badgesEarned: summary.badgesEarned,
                    levelsGained: summary.levelsGained,
                    snapshotsCreated: summary.snapshotsCreated,
                    correlationsDiscovered: causalityResult.newInsights,
                    insightsValidated: causalityResult.validated,
                    journalsProcessed: summary.journalsProcessed
                )

            case .cacheCleanup:
                itemsProcessed = try runCacheCleanup(db: db, date: date)
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        let endTime = Date()

        return CronJobResult(
            jobType: jobType,
            startTime: startTime,
            endTime: endTime,
            success: errorMessage == nil,
            itemsProcessed: itemsProcessed,
            changes: changes,
            errorMessage: errorMessage
        )
    }

    // MARK: - Individual Jobs

    /// Check and update streaks
    private func runStreakCheck(db: Database, date: Date) throws -> (changes: [CronJobChange], processed: Int, broken: Int, freezesUsed: Int) {
        let events = try streakEngine.checkExpiredStreaks(db: db, asOf: date)

        var changes: [CronJobChange] = []
        var broken = 0
        var freezesUsed = 0

        for event in events {
            switch event.eventType {
            case .streakBroken:
                broken += 1
                changes.append(CronJobChange(
                    changeType: "streak_broken",
                    dimension: event.dimension.rawValue,
                    previousValue: Double(event.previousStreak),
                    newValue: 0,
                    description: "\(event.dimension.displayName) streak broken after \(event.previousStreak) days"
                ))

            case .freezeUsed:
                freezesUsed += 1
                changes.append(CronJobChange(
                    changeType: "freeze_used",
                    dimension: event.dimension.rawValue,
                    description: "Freeze auto-used to protect \(event.dimension.displayName) streak"
                ))

            default:
                break
            }
        }

        return (changes, events.count, broken, freezesUsed)
    }

    /// Apply NELO regression to inactive dimensions
    private func runNeloRegression(db: Database, date: Date) throws -> (changes: [CronJobChange], processed: Int, regressionsApplied: Int) {
        // Get current level state
        guard var levelState = try CosmoLevelState.fetchOne(db) else {
            return ([], 0, 0)
        }

        // Build dimension activity from yesterday
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else {
            return ([], 0, 0)
        }

        let activityMetrics = try fetchDimensionActivityMetrics(db: db, for: yesterday)

        var changes: [CronJobChange] = []
        var regressionsApplied = 0

        // Simple NELO regression: reduce by 5% if no activity in dimension
        let regressionRate = 0.05

        let dimensionConfigs: [(name: String, getNELO: () -> Int, setNELO: (Int) -> Void)] = [
            ("cognitive", { levelState.cognitiveNELO }, { levelState.cognitiveNELO = $0 }),
            ("creative", { levelState.creativeNELO }, { levelState.creativeNELO = $0 }),
            ("physiological", { levelState.physiologicalNELO }, { levelState.physiologicalNELO = $0 }),
            ("behavioral", { levelState.behavioralNELO }, { levelState.behavioralNELO = $0 }),
            ("knowledge", { levelState.knowledgeNELO }, { levelState.knowledgeNELO = $0 }),
            ("reflection", { levelState.reflectionNELO }, { levelState.reflectionNELO = $0 })
        ]

        for (name, getNELO, setNELO) in dimensionConfigs {
            let isActive = activityMetrics[name]?.isActive ?? false
            if !isActive {
                let currentNELO = getNELO()
                let regression = Int(Double(currentNELO) * regressionRate)
                if regression > 0 {
                    let newNELO = max(0, currentNELO - regression)
                    setNELO(newNELO)
                    regressionsApplied += 1
                    changes.append(CronJobChange(
                        changeType: "nelo_regression",
                        dimension: name,
                        previousValue: Double(currentNELO),
                        newValue: Double(newNELO),
                        description: "\(name) NELO regressed by \(regression) due to inactivity"
                    ))
                }
            }
        }

        // Update level state if any regressions occurred
        if regressionsApplied > 0 {
            levelState.updatedAt = Date()
            try levelState.save(db)
        }

        return (changes, 6, regressionsApplied)  // Always check 6 dimensions
    }

    /// Fetch dimension activity metrics for a specific date
    private func fetchDimensionActivityMetrics(db: Database, for date: Date) throws -> [String: DailyActivityMetrics] {
        var metrics: [String: DailyActivityMetrics] = [:]
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return metrics
        }

        // Check cognitive activity
        let cognitiveCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type IN ('focus_session', 'focus_event')
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [startOfDay, endOfDay]) ?? 0

        metrics["cognitive"] = DailyActivityMetrics(
            dimension: "cognitive",
            activityCount: cognitiveCount,
            qualityScore: cognitiveCount > 0 ? 0.8 : 0.0,
            isActive: cognitiveCount > 0
        )

        // Check creative activity
        let creativeCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type IN ('idea', 'ideaNote', 'project')
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [startOfDay, endOfDay]) ?? 0

        metrics["creative"] = DailyActivityMetrics(
            dimension: "creative",
            activityCount: creativeCount,
            qualityScore: creativeCount > 0 ? 0.8 : 0.0,
            isActive: creativeCount > 0
        )

        // Check physiological activity
        let physioCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type IN ('sleep_record', 'hrv_reading', 'workout', 'recovery_score')
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [startOfDay, endOfDay]) ?? 0

        metrics["physiological"] = DailyActivityMetrics(
            dimension: "physiological",
            activityCount: physioCount,
            qualityScore: physioCount > 0 ? 0.8 : 0.0,
            isActive: physioCount > 0
        )

        // Check behavioral activity
        let behavioralCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type IN ('task', 'habit_completion', 'routine_completed')
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [startOfDay, endOfDay]) ?? 0

        metrics["behavioral"] = DailyActivityMetrics(
            dimension: "behavioral",
            activityCount: behavioralCount,
            qualityScore: behavioralCount > 0 ? 0.8 : 0.0,
            isActive: behavioralCount > 0
        )

        // Check knowledge activity
        let knowledgeCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type IN ('note', 'book', 'article', 'learning_session')
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [startOfDay, endOfDay]) ?? 0

        metrics["knowledge"] = DailyActivityMetrics(
            dimension: "knowledge",
            activityCount: knowledgeCount,
            qualityScore: knowledgeCount > 0 ? 0.8 : 0.0,
            isActive: knowledgeCount > 0
        )

        // Check reflection activity
        let reflectionCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM atoms
            WHERE type IN ('journal_entry', 'insight', 'emotional_state', 'reflection_session')
            AND createdAt >= ? AND createdAt < ?
            AND isDeleted = 0
        """, arguments: [startOfDay, endOfDay]) ?? 0

        metrics["reflection"] = DailyActivityMetrics(
            dimension: "reflection",
            activityCount: reflectionCount,
            qualityScore: reflectionCount > 0 ? 0.8 : 0.0,
            isActive: reflectionCount > 0
        )

        return metrics
    }

    /// Create daily dimension snapshots
    private func runDimensionSnapshot(db: Database, date: Date) throws -> Int {
        // This would call DimensionMetricsCalculator.generateDailySnapshot
        // For now, return 0 as placeholder
        return 0
    }

    /// Check for newly earned badges
    private func runBadgeCheck(db: Database, date: Date) throws -> Int {
        guard let levelState = try CosmoLevelState.fetchOne(db) else {
            return 0
        }

        let context = try badgeTracker.buildContext(db: db, levelState: levelState)
        let newBadges = badgeTracker.checkForNewBadges(context: context)

        // Create badge atoms for newly earned badges
        for badge in newBadges {
            let badgeAtom = badgeTracker.createBadgeAtom(
                badge: badge,
                triggeringActionId: nil,
                progressSnapshot: [:]
            )

            try badgeAtom.insert(db)
        }

        return newBadges.count
    }

    /// Recalculate levels from XP
    private func runLevelRecalculation(db: Database) throws -> (changes: [CronJobChange], processed: Int) {
        guard var levelState = try CosmoLevelState.fetchOne(db) else {
            return ([], 0)
        }

        var changes: [CronJobChange] = []

        // Recalculate dimension levels (use CI/XP values to recalculate levels)
        let dimensions = [
            ("cognitive", levelState.cognitiveCI, levelState.cognitiveLevel),
            ("creative", levelState.creativeCI, levelState.creativeLevel),
            ("physiological", levelState.physiologicalCI, levelState.physiologicalLevel),
            ("behavioral", levelState.behavioralCI, levelState.behavioralLevel),
            ("knowledge", levelState.knowledgeCI, levelState.knowledgeLevel),
            ("reflection", levelState.reflectionCI, levelState.reflectionLevel)
        ]

        for (name, xp, currentLevel) in dimensions {
            let expectedDimLevel = XPCalculationEngine.levelForXP(xp)
            if expectedDimLevel != currentLevel {
                changes.append(CronJobChange(
                    changeType: "dimension_level_correction",
                    dimension: name,
                    previousValue: Double(currentLevel),
                    newValue: Double(expectedDimLevel),
                    description: "\(name) level corrected from \(currentLevel) to \(expectedDimLevel)"
                ))

                switch name {
                case "cognitive": levelState.cognitiveLevel = expectedDimLevel
                case "creative": levelState.creativeLevel = expectedDimLevel
                case "physiological": levelState.physiologicalLevel = expectedDimLevel
                case "behavioral": levelState.behavioralLevel = expectedDimLevel
                case "knowledge": levelState.knowledgeLevel = expectedDimLevel
                case "reflection": levelState.reflectionLevel = expectedDimLevel
                default: break
                }
            }
        }

        if !changes.isEmpty {
            levelState.updatedAt = Date()
            try levelState.save(db)
        }

        return (changes, 7)  // 1 overall + 6 dimensions
    }

    /// Aggregate daily analytics
    private func runAnalyticsAggregation(db: Database, date: Date) throws -> Int {
        // Aggregate metrics for analytics dashboard
        // This would create summary atoms for historical tracking
        return 0
    }

    /// Clean up old cache entries
    private func runCacheCleanup(db: Database, date: Date) throws -> Int {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -90, to: date) else {
            return 0
        }

        // Clean old cron run records (keep 90 days)
        try db.execute(sql: """
            DELETE FROM cosmo_cron_history
            WHERE runDate < ?
        """, arguments: [cutoffDate])

        return db.changesCount
    }

    // MARK: - Sanctuary / Causality Jobs

    /// Result of causality computation
    private struct CausalityJobResult {
        let metricsAnalyzed: Int
        let newInsights: Int
        let validated: Int
        let changes: [CronJobChange]
    }

    /// Extract semantic content from unprocessed journal entries
    private func runSemanticExtraction(db: Database, date: Date) throws -> Int {
        // Find journal entries that don't have semantic extractions yet
        let processedUUIDs = try Atom
            .filter(Column("type") == AtomType.semanticExtraction.rawValue)
            .filter(Column("is_deleted") == false)
            .fetchAll(db)
            .compactMap { atom -> String? in
                guard let metadata = atom.metadata,
                      let data = metadata.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                return dict["sourceUUID"] as? String
            }

        // Get unprocessed journal entries from the last 7 days
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: date) else {
            return 0
        }

        var query = Atom
            .filter(Column("type") == AtomType.journalEntry.rawValue)
            .filter(Column("is_deleted") == false)
            .filter(Column("created_at") >= weekAgo.ISO8601Format())

        if !processedUUIDs.isEmpty {
            query = query.filter(!processedUUIDs.contains(Column("uuid")))
        }

        let unprocessedJournals = try query.fetchAll(db)

        // Process each journal entry (using on-device NLP for now)
        var processed = 0
        for journal in unprocessedJournals {
            guard let body = journal.body, !body.isEmpty else { continue }

            // Basic extraction using keyword matching
            let wordCount = body.split(separator: " ").count
            let sentenceCount = body.filter { ".!?".contains($0) }.count

            // Simple sentiment estimation
            let positiveWords = ["happy", "excited", "grateful", "proud", "love", "great", "amazing", "wonderful"]
            let negativeWords = ["sad", "angry", "frustrated", "anxious", "stressed", "worried", "tired", "overwhelmed"]

            let lowerBody = body.lowercased()
            let positiveCount = positiveWords.filter { lowerBody.contains($0) }.count
            let negativeCount = negativeWords.filter { lowerBody.contains($0) }.count

            let valence = Double(positiveCount - negativeCount) / max(Double(positiveCount + negativeCount), 1.0)

            // Create semantic extraction atom
            let metadata: [String: Any] = [
                "sourceUUID": journal.uuid,
                "extractedAt": Date().ISO8601Format(),
                "wordCount": wordCount,
                "sentenceCount": sentenceCount,
                "overallValence": valence > 0.3 ? "positive" : (valence < -0.3 ? "negative" : "neutral"),
                "valenceScore": valence,
                "topicCount": 0,
                "emotionCount": positiveCount + negativeCount,
                "usedCloudModel": false
            ]

            var atom = Atom.new(
                type: .semanticExtraction,
                title: "Semantic Extraction",
                body: "Extracted from journal entry"
            )

            if let metadataData = try? JSONSerialization.data(withJSONObject: metadata),
               let metadataString = String(data: metadataData, encoding: .utf8) {
                atom.metadata = metadataString
            }

            atom.links = try? String(data: JSONEncoder().encode([
                AtomLink(type: "semantic_source", uuid: journal.uuid, entityType: "journal_entry")
            ]), encoding: .utf8)

            try atom.insert(db)
            processed += 1
        }

        return processed
    }

    /// Run 90-day correlation analysis
    private func runCausalityComputation(db: Database, date: Date) throws -> CausalityJobResult {
        // This is a synchronous wrapper for the async CausalityEngine
        // In production, this would be called from an async context

        let calendar = Calendar.current
        guard let windowStart = calendar.date(byAdding: .day, value: -90, to: date) else {
            return CausalityJobResult(metricsAnalyzed: 0, newInsights: 0, validated: 0, changes: [])
        }

        // Collect all metrics for the 90-day window
        let atomTypes: [AtomType] = [
            .hrvMeasurement, .restingHR, .sleepCycle, .readinessScore,
            .workoutSession, .deepWorkBlock, .focusScore, .task,
            .journalEntry, .emotionalState, .xpEvent
        ]

        let atomTypesSQL = atomTypes.map { "'\($0.rawValue)'" }.joined(separator: ", ")

        let atoms = try Atom
            .filter(sql: "type IN (\(atomTypesSQL))")
            .filter(Column("created_at") >= windowStart.ISO8601Format())
            .filter(Column("created_at") < date.ISO8601Format())
            .filter(Column("is_deleted") == false)
            .fetchAll(db)

        // Group by date and extract metrics
        var dailyMetrics: [String: [String: [Double]]] = [:]  // date -> metric -> values
        let dateFormatter = ISO8601DateFormatter()

        for atom in atoms {
            guard let createdAt = dateFormatter.date(from: atom.createdAt) else { continue }
            let dateKey = calendar.startOfDay(for: createdAt).ISO8601Format()

            if dailyMetrics[dateKey] == nil {
                dailyMetrics[dateKey] = [:]
            }

            // Extract metrics based on type
            let extractedMetrics = extractMetricsFromAtom(atom)
            for (metric, value) in extractedMetrics {
                if dailyMetrics[dateKey]![metric] == nil {
                    dailyMetrics[dateKey]![metric] = []
                }
                dailyMetrics[dateKey]![metric]!.append(value)
            }
        }

        // Calculate daily averages
        var dailyAverages: [[String: Double]] = []
        for (_, metrics) in dailyMetrics.sorted(by: { $0.key < $1.key }) {
            var avgMetrics: [String: Double] = [:]
            for (metric, values) in metrics {
                avgMetrics[metric] = values.reduce(0, +) / Double(values.count)
            }
            dailyAverages.append(avgMetrics)
        }

        // Calculate correlations (simplified Pearson)
        var newInsights = 0
        var validated = 0
        var changes: [CronJobChange] = []

        let allMetrics = Set(dailyAverages.flatMap { $0.keys })

        for sourceMetric in allMetrics {
            for targetMetric in allMetrics where sourceMetric < targetMetric {
                let correlation = calculateSimpleCorrelation(
                    metric1: sourceMetric,
                    metric2: targetMetric,
                    data: dailyAverages
                )

                if abs(correlation) >= 0.5 {
                    // Check if this insight already exists
                    let existingInsight = try Atom
                        .filter(Column("type") == AtomType.correlationInsight.rawValue)
                        .filter(Column("title") == "\(sourceMetric) → \(targetMetric)")
                        .filter(Column("is_deleted") == false)
                        .fetchOne(db)

                    if existingInsight != nil {
                        // Validate existing insight
                        validated += 1
                    } else {
                        // Create new insight
                        let description = correlation > 0
                            ? "Higher \(sourceMetric) correlates with higher \(targetMetric)"
                            : "Higher \(sourceMetric) correlates with lower \(targetMetric)"

                        let metadata: [String: Any] = [
                            "sourceMetric": sourceMetric,
                            "targetMetric": targetMetric,
                            "correlationType": "direct",
                            "strength": abs(correlation) >= 0.7 ? "strong" : "moderate",
                            "coefficient": correlation,
                            "occurrences": 1,
                            "firstObserved": Date().ISO8601Format(),
                            "lastValidated": Date().ISO8601Format(),
                            "decayFactor": 1.0,
                            "isActive": true
                        ]

                        var atom = Atom.new(
                            type: .correlationInsight,
                            title: "\(sourceMetric) → \(targetMetric)",
                            body: description
                        )

                        if let metadataData = try? JSONSerialization.data(withJSONObject: metadata),
                           let metadataString = String(data: metadataData, encoding: .utf8) {
                            atom.metadata = metadataString
                        }

                        try atom.insert(db)
                        newInsights += 1

                        changes.append(CronJobChange(
                            changeType: "new_insight",
                            description: description
                        ))
                    }
                }
            }
        }

        // Record the computation
        let computationMetadata: [String: Any] = [
            "computedAt": Date().ISO8601Format(),
            "dataWindowStart": windowStart.ISO8601Format(),
            "dataWindowEnd": date.ISO8601Format(),
            "totalDataPoints": atoms.count,
            "metricsAnalyzed": allMetrics.count,
            "newInsightsCreated": newInsights,
            "insightsValidated": validated
        ]

        var computationAtom = Atom.new(
            type: .causalityComputation,
            title: "Causality Computation - \(date.formatted(date: .abbreviated, time: .omitted))"
        )

        if let metadataData = try? JSONSerialization.data(withJSONObject: computationMetadata),
           let metadataString = String(data: metadataData, encoding: .utf8) {
            computationAtom.metadata = metadataString
        }

        try computationAtom.insert(db)

        return CausalityJobResult(
            metricsAnalyzed: allMetrics.count,
            newInsights: newInsights,
            validated: validated,
            changes: changes
        )
    }

    /// Extract numeric metrics from an atom
    private func extractMetricsFromAtom(_ atom: Atom) -> [String: Double] {
        var metrics: [String: Double] = [:]

        guard let metadataString = atom.metadata,
              let data = metadataString.data(using: .utf8),
              let metaDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return metrics
        }

        switch atom.type {
        case .hrvMeasurement:
            if let hrv = metaDict["hrv"] as? Double {
                metrics["hrv"] = hrv
            }
        case .sleepCycle:
            if let hours = metaDict["durationHours"] as? Double {
                metrics["sleep_hours"] = hours
            }
        case .readinessScore:
            if let score = metaDict["score"] as? Double {
                metrics["readiness"] = score
            }
        case .workoutSession:
            if let duration = metaDict["durationMinutes"] as? Double {
                metrics["workout_minutes"] = duration
            }
        case .deepWorkBlock:
            if let duration = metaDict["durationMinutes"] as? Double {
                metrics["deep_work_minutes"] = duration
            }
        case .focusScore:
            if let score = metaDict["score"] as? Double {
                metrics["focus_score"] = score
            }
        case .task:
            if metaDict["isCompleted"] as? Bool == true {
                metrics["tasks_completed"] = 1
            }
        case .journalEntry:
            if let body = atom.body {
                metrics["journal_words"] = Double(body.split(separator: " ").count)
            }
        default:
            break
        }

        return metrics
    }

    /// Calculate simple Pearson correlation between two metrics
    private func calculateSimpleCorrelation(
        metric1: String,
        metric2: String,
        data: [[String: Double]]
    ) -> Double {
        var pairs: [(Double, Double)] = []

        for day in data {
            if let v1 = day[metric1], let v2 = day[metric2] {
                pairs.append((v1, v2))
            }
        }

        guard pairs.count >= 10 else { return 0 }

        let n = Double(pairs.count)
        let sumX = pairs.reduce(0) { $0 + $1.0 }
        let sumY = pairs.reduce(0) { $0 + $1.1 }
        let sumXY = pairs.reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = pairs.reduce(0) { $0 + $1.0 * $1.0 }
        let sumY2 = pairs.reduce(0) { $0 + $1.1 * $1.1 }

        let numerator = n * sumXY - sumX * sumY
        let denominator = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY))

        guard denominator > 0 else { return 0 }

        return numerator / denominator
    }

    // MARK: - Cron Run Tracking

    /// Check if cron has already run today
    private func hasRunToday(db: Database, date: Date) throws -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        let count = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM cosmo_cron_history
            WHERE runDate >= ?
        """, arguments: [startOfDay]) ?? 0

        return count > 0
    }

    /// Record that cron has run
    private func recordCronRun(db: Database, date: Date, report: [CronJobResult]) throws {
        let metadata: String
        if let data = try? JSONEncoder().encode(report),
           let json = String(data: data, encoding: .utf8) {
            metadata = json
        } else {
            metadata = "{}"
        }

        try db.execute(sql: """
            INSERT INTO cosmo_cron_history (runDate, jobResults, createdAt)
            VALUES (?, ?, ?)
        """, arguments: [date, metadata, Date()])
    }

    /// Get last cron run date
    public func lastCronRunDate(db: Database) throws -> Date? {
        try Date.fetchOne(db, sql: """
            SELECT MAX(runDate) FROM cosmo_cron_history
        """)
    }

    /// Check if cron needs to run (missed days)
    public func missedCronDays(db: Database, asOf date: Date = Date()) throws -> Int {
        guard let lastRun = try lastCronRunDate(db: db) else {
            return 1  // Never run, need to run now
        }

        let calendar = Calendar.current
        let daysDifference = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastRun), to: calendar.startOfDay(for: date)).day ?? 0

        return max(0, daysDifference)
    }

    /// Run cron for all missed days
    public func catchUpMissedDays(db: Database, asOf date: Date = Date()) throws -> [DailyCronReport] {
        var reports: [DailyCronReport] = []
        let calendar = Calendar.current

        guard let lastRun = try lastCronRunDate(db: db) else {
            // First run ever
            let report = try runDailyCron(db: db, forDate: date)
            return [report]
        }

        var checkDate = calendar.startOfDay(for: lastRun)
        let today = calendar.startOfDay(for: date)

        while checkDate < today {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate) else { break }
            checkDate = nextDay

            if checkDate <= today {
                let report = try runDailyCron(db: db, forDate: checkDate)
                reports.append(report)
            }
        }

        return reports
    }
}

// MARK: - Cron History Table Migration

/// Database migration for cron history
public struct CronHistoryMigration {
    public static let migrationSQL = """
        CREATE TABLE IF NOT EXISTS cosmo_cron_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            runDate DATETIME NOT NULL,
            jobResults TEXT,
            createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_cron_history_date ON cosmo_cron_history(runDate);
    """
}

// MARK: - Extension for Level State

extension CosmoLevelState {
    /// Get dimension NELOs as dictionary
    var dimensionNELOs: [String: Int] {
        [
            "cognitive": cognitiveNELO,
            "creative": creativeNELO,
            "physiological": physiologicalNELO,
            "behavioral": behavioralNELO,
            "knowledge": knowledgeNELO,
            "reflection": reflectionNELO
        ]
    }
}
