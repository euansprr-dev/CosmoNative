// CosmoOS/Data/Models/Sanctuary/CausalityEngine.swift
// Causality Engine - 90-day rolling correlation analysis across all Atom types
// Discovers patterns that a human could never realize themselves

import Foundation
import GRDB

// MARK: - Correlation Types

/// Types of correlations the engine can detect
public enum CorrelationType: String, Codable, Sendable {
    case direct           // X and Y correlate on the same day
    case lagged           // X today correlates with Y in 1-7 days
    case compound         // Multiple factors combine to predict outcome
    case threshold        // Effect only appears when X exceeds a threshold
    case inverse          // X and Y are inversely correlated
    case periodic         // Correlation varies by day of week or time
}

/// Strength levels for correlations
public enum CorrelationStrength: String, Codable, Sendable {
    case weak             // 0.3-0.5 correlation coefficient
    case moderate         // 0.5-0.7
    case strong           // 0.7-0.85
    case veryStrong       // 0.85+

    public var minCoefficient: Double {
        switch self {
        case .weak: return 0.3
        case .moderate: return 0.5
        case .strong: return 0.7
        case .veryStrong: return 0.85
        }
    }
}

/// Confidence levels for correlation insights
public enum CorrelationConfidence: String, Codable, Sendable {
    case emerging         // 5-10 data points, needs more validation
    case developing       // 10-20 data points
    case established      // 20-50 data points
    case proven           // 50+ data points, highly reliable

    public var minOccurrences: Int {
        switch self {
        case .emerging: return 5
        case .developing: return 10
        case .established: return 20
        case .proven: return 50
        }
    }
}

// MARK: - Metric Data Point

/// A single data point for correlation analysis
public struct MetricDataPoint: Codable, Sendable {
    public let date: Date
    public let metricType: String     // e.g., "hrv", "sleep_hours", "focus_minutes"
    public let dimension: String?      // LevelDimension if applicable
    public let value: Double
    public let atomUUID: String?       // Source atom
    public let atomType: String        // AtomType raw value

    public init(
        date: Date,
        metricType: String,
        dimension: String? = nil,
        value: Double,
        atomUUID: String? = nil,
        atomType: String
    ) {
        self.date = date
        self.metricType = metricType
        self.dimension = dimension
        self.value = value
        self.atomUUID = atomUUID
        self.atomType = atomType
    }
}

/// Daily aggregated metrics for correlation
public struct DailyMetricAggregate: Codable, Sendable {
    public let date: Date
    public var metrics: [String: Double]  // metricType -> value

    public init(date: Date, metrics: [String: Double] = [:]) {
        self.date = date
        self.metrics = metrics
    }
}

// MARK: - Correlation Result

/// Result of a correlation calculation
public struct CorrelationResult: Codable, Sendable {
    public let sourceMetric: String
    public let targetMetric: String
    public let coefficient: Double      // Pearson correlation (-1 to 1)
    public let pValue: Double           // Statistical significance
    public let sampleSize: Int
    public let lagDays: Int             // 0 = same day, 1-7 = lagged
    public let correlationType: CorrelationType
    public let strength: CorrelationStrength
    public let effectSize: Double       // How much target changes per unit source

    public var isSignificant: Bool {
        pValue < 0.05 && sampleSize >= 10
    }

    public var meetsThreshold: Bool {
        abs(coefficient) >= 0.3 && isSignificant && abs(effectSize) >= 0.1
    }
}

// MARK: - Correlation Insight

/// A validated, displayable insight from correlation analysis
public struct CorrelationInsight: Codable, Sendable {
    public let uuid: String
    public let sourceMetric: String
    public let targetMetric: String
    public let correlationType: CorrelationType
    public let strength: CorrelationStrength
    public let confidence: CorrelationConfidence
    public let coefficient: Double
    public let effectSize: Double
    public let lagDays: Int
    public let occurrences: Int          // How many times pattern observed
    public let firstObserved: Date
    public let lastValidated: Date
    public let decayFactor: Double       // 1.0 = fresh, 0.0 = should be removed
    public let humanDescription: String  // "When you sleep 7+ hours, your HRV is 15% higher the next day"
    public let actionableAdvice: String? // "Try to get 7+ hours tonight"

    /// Whether this insight should be shown to the user
    public var isActive: Bool {
        occurrences >= 5 && decayFactor > 0.3 && confidence.minOccurrences <= occurrences
    }

    /// Priority for display (higher = more important)
    public var displayPriority: Double {
        let strengthWeight = abs(coefficient)
        let confidenceWeight = Double(occurrences) / 50.0
        let freshnessWeight = decayFactor
        let effectWeight = min(abs(effectSize), 0.5) * 2  // Cap at 100%

        return (strengthWeight * 0.3 + confidenceWeight * 0.25 + freshnessWeight * 0.25 + effectWeight * 0.2)
    }

    /// Statistical confidence as a Double (0.0 - 1.0)
    public var statisticalConfidence: Double {
        switch confidence {
        case .emerging: return 0.25
        case .developing: return 0.5
        case .established: return 0.75
        case .proven: return 0.95
        }
    }

    /// Trend direction based on effect size
    public var trend: TrendDirection {
        if effectSize > 0.1 { return .improving }
        if effectSize < -0.1 { return .declining }
        return .stable
    }
}

// MARK: - Insight Metadata

/// Metadata for storing CorrelationInsight as an Atom
public struct CorrelationInsightMetadata: Codable, Sendable {
    public let sourceMetric: String
    public let targetMetric: String
    public let correlationType: String
    public let strength: String
    public let confidence: String
    public let coefficient: Double
    public let effectSize: Double
    public let lagDays: Int
    public let occurrences: Int
    public let firstObserved: Date
    public let lastValidated: Date
    public let decayFactor: Double
    public let actionableAdvice: String?
    public let dimensionAffected: String?
    public let isActive: Bool

    public init(from insight: CorrelationInsight, dimensionAffected: String? = nil) {
        self.sourceMetric = insight.sourceMetric
        self.targetMetric = insight.targetMetric
        self.correlationType = insight.correlationType.rawValue
        self.strength = insight.strength.rawValue
        self.confidence = insight.confidence.rawValue
        self.coefficient = insight.coefficient
        self.effectSize = insight.effectSize
        self.lagDays = insight.lagDays
        self.occurrences = insight.occurrences
        self.firstObserved = insight.firstObserved
        self.lastValidated = insight.lastValidated
        self.decayFactor = insight.decayFactor
        self.actionableAdvice = insight.actionableAdvice
        self.dimensionAffected = dimensionAffected
        self.isActive = insight.isActive
    }
}

// MARK: - Causality Computation Metadata

/// Metadata for tracking computation runs
public struct CausalityComputationMetadata: Codable, Sendable {
    public let computedAt: Date
    public let dataWindowStart: Date
    public let dataWindowEnd: Date
    public let totalDataPoints: Int
    public let metricsAnalyzed: Int
    public let correlationsFound: Int
    public let newInsightsCreated: Int
    public let insightsValidated: Int
    public let insightsDecayed: Int
    public let insightsRemoved: Int
    public let computationDurationMs: Int
    public let usedCloudModel: Bool
    public let cloudModelProvider: String?
}

// MARK: - Causality Engine

/// Main engine for computing correlations across all Atom types
public actor CausalityEngine {

    // MARK: - Configuration

    /// Rolling window for correlation analysis (90 days)
    public static let analysisWindowDays: Int = 90

    /// Minimum occurrences for an insight to be valid
    public static let minOccurrences: Int = 5

    /// Minimum correlation coefficient for significance
    public static let minCorrelation: Double = 0.3

    /// Minimum effect size (10% change)
    public static let minEffectSize: Double = 0.10

    /// Decay rate per day without validation
    public static let dailyDecayRate: Double = 0.02

    /// Decay threshold for removal
    public static let removalDecayThreshold: Double = 0.3

    // MARK: - Dependencies

    private let database: any DatabaseWriter

    // MARK: - State

    private var cachedInsights: [CorrelationInsight] = []
    private var lastComputationDate: Date?
    private var isComputing: Bool = false

    // MARK: - Initialization

    @MainActor
    public init(database: (any DatabaseWriter)? = nil) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
    }

    // MARK: - Main Computation Entry Point

    /// Run the full causality computation (called at midnight)
    public func runDailyComputation() async throws -> CausalityComputationMetadata {
        guard !isComputing else {
            throw CausalityError.computationInProgress
        }

        isComputing = true
        defer { isComputing = false }

        let startTime = Date()
        let windowEnd = Calendar.current.startOfDay(for: Date())
        guard let windowStart = Calendar.current.date(
            byAdding: .day,
            value: -Self.analysisWindowDays,
            to: windowEnd
        ) else {
            throw CausalityError.invalidDateRange
        }

        // Step 1: Collect all metrics from the 90-day window
        let dailyAggregates = try await collectAllMetrics(from: windowStart, to: windowEnd)

        // Step 2: Calculate correlations
        let correlations = calculateCorrelations(from: dailyAggregates)

        // Step 3: Load existing insights
        var existingInsights = try await loadExistingInsights()

        // Step 4: Validate/update existing insights
        let (validated, decayed, removed) = updateExistingInsights(
            &existingInsights,
            withNewCorrelations: correlations
        )

        // Step 5: Create new insights from strong correlations
        let newInsights = createNewInsights(
            from: correlations,
            existingInsights: existingInsights
        )

        // Step 6: Save all insights to database
        try await saveInsights(existingInsights + newInsights)

        // Step 7: Create computation record
        let endTime = Date()
        let metadata = CausalityComputationMetadata(
            computedAt: endTime,
            dataWindowStart: windowStart,
            dataWindowEnd: windowEnd,
            totalDataPoints: dailyAggregates.reduce(0) { $0 + $1.metrics.count },
            metricsAnalyzed: Set(dailyAggregates.flatMap { $0.metrics.keys }).count,
            correlationsFound: correlations.count,
            newInsightsCreated: newInsights.count,
            insightsValidated: validated,
            insightsDecayed: decayed,
            insightsRemoved: removed,
            computationDurationMs: Int(endTime.timeIntervalSince(startTime) * 1000),
            usedCloudModel: false,
            cloudModelProvider: nil
        )

        // Record the computation
        try await recordComputation(metadata: metadata)

        lastComputationDate = endTime
        cachedInsights = existingInsights + newInsights

        return metadata
    }

    // MARK: - Data Collection

    /// Collect all metrics from Atoms within the date range
    private func collectAllMetrics(from startDate: Date, to endDate: Date) async throws -> [DailyMetricAggregate] {
        try await database.read { db in
            var dailyData: [String: DailyMetricAggregate] = [:]
            let calendar = Calendar.current
            let dateFormatter = ISO8601DateFormatter()

            // Initialize all days in the range
            var currentDate = startDate
            while currentDate < endDate {
                let key = self.dateKey(currentDate)
                dailyData[key] = DailyMetricAggregate(date: currentDate)
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate
            }

            // Query all relevant atom types
            let atomTypes: [AtomType] = [
                // Physiology
                .hrvMeasurement, .restingHR, .sleepCycle, .sleepConsistency,
                .readinessScore, .workoutSession, .breathingSession, .bloodOxygen,
                // Cognitive
                .deepWorkBlock, .writingSession, .wordCountEntry, .focusScore,
                // Behavioral
                .task, .scheduleBlock,
                // Content
                .contentPerformance,
                // Reflection
                .journalEntry, .emotionalState,
                // Leveling
                .xpEvent, .dimensionSnapshot
            ]

            let atomTypesSQL = atomTypes.map { "'\($0.rawValue)'" }.joined(separator: ", ")

            let atoms = try Atom
                .filter(sql: "type IN (\(atomTypesSQL))")
                .filter(Column("created_at") >= startDate.ISO8601Format())
                .filter(Column("created_at") < endDate.ISO8601Format())
                .filter(Column("is_deleted") == false)
                .fetchAll(db)

            // Extract metrics from each atom
            for atom in atoms {
                guard let createdAtString = atom.createdAt as String?,
                      let createdAt = dateFormatter.date(from: createdAtString) else {
                    continue
                }

                let key = self.dateKey(createdAt)
                guard var aggregate = dailyData[key] else { continue }

                // Extract metrics based on atom type
                let metrics = self.extractMetrics(from: atom)
                for (metricName, value) in metrics {
                    // Aggregate by averaging for the day
                    if let existing = aggregate.metrics[metricName] {
                        aggregate.metrics[metricName] = (existing + value) / 2
                    } else {
                        aggregate.metrics[metricName] = value
                    }
                }

                dailyData[key] = aggregate
            }

            return Array(dailyData.values).sorted { $0.date < $1.date }
        }
    }

    /// Extract numeric metrics from an atom
    private nonisolated func extractMetrics(from atom: Atom) -> [String: Double] {
        var metrics: [String: Double] = [:]

        switch atom.type {
        case .hrvMeasurement:
            if let meta = atom.metadataDict {
                if let hrv = meta["hrv"] as? Double {
                    metrics["hrv"] = hrv
                }
                if let rmssd = meta["rmssd"] as? Double {
                    metrics["hrv_rmssd"] = rmssd
                }
            }

        case .restingHR:
            if let meta = atom.metadataDict {
                if let bpm = meta["bpm"] as? Double {
                    metrics["resting_hr"] = bpm
                }
            }

        case .sleepCycle:
            if let meta = atom.metadataDict {
                if let duration = meta["durationHours"] as? Double {
                    metrics["sleep_hours"] = duration
                }
                if let deep = meta["deepSleepMinutes"] as? Double {
                    metrics["deep_sleep_minutes"] = deep
                }
                if let rem = meta["remSleepMinutes"] as? Double {
                    metrics["rem_sleep_minutes"] = rem
                }
                if let efficiency = meta["efficiency"] as? Double {
                    metrics["sleep_efficiency"] = efficiency
                }
            }

        case .sleepConsistency:
            if let meta = atom.metadataDict {
                if let deviation = meta["deviationMinutes"] as? Double {
                    metrics["sleep_schedule_deviation"] = deviation
                }
            }

        case .readinessScore:
            if let meta = atom.metadataDict {
                if let score = meta["score"] as? Double {
                    metrics["readiness_score"] = score
                }
            }

        case .workoutSession:
            if let meta = atom.metadataDict {
                if let duration = meta["durationMinutes"] as? Double {
                    metrics["workout_minutes"] = duration
                }
                if let calories = meta["calories"] as? Double {
                    metrics["workout_calories"] = calories
                }
                if let intensity = meta["intensity"] as? Double {
                    metrics["workout_intensity"] = intensity
                }
            }

        case .deepWorkBlock:
            if let meta = atom.metadataDict {
                if let duration = meta["durationMinutes"] as? Double {
                    metrics["deep_work_minutes"] = duration
                }
                if let quality = meta["qualityScore"] as? Double {
                    metrics["deep_work_quality"] = quality
                }
            }

        case .writingSession:
            if let meta = atom.metadataDict {
                if let words = meta["wordCount"] as? Double {
                    metrics["words_written"] = words
                }
                if let duration = meta["durationMinutes"] as? Double {
                    metrics["writing_minutes"] = duration
                }
            }

        case .wordCountEntry:
            if let meta = atom.metadataDict {
                if let words = meta["wordCount"] as? Double {
                    metrics["daily_word_count"] = words
                }
            }

        case .focusScore:
            if let meta = atom.metadataDict {
                if let score = meta["score"] as? Double {
                    metrics["focus_score"] = score
                }
            }

        case .task:
            if let meta = atom.metadataDict {
                if meta["isCompleted"] as? Bool == true {
                    metrics["tasks_completed"] = (metrics["tasks_completed"] ?? 0) + 1
                }
            }

        case .journalEntry:
            // Count journal entries and extract word count
            metrics["journal_entries"] = 1
            if let body = atom.body {
                metrics["journal_word_count"] = Double(body.split(separator: " ").count)
            }

        case .emotionalState:
            if let meta = atom.metadataDict {
                if let valence = meta["valence"] as? Double {
                    metrics["emotional_valence"] = valence  // -1 to 1
                }
                if let energy = meta["energy"] as? Double {
                    metrics["emotional_energy"] = energy
                }
            }

        case .xpEvent:
            if let meta = atom.metadataDict {
                if let xp = meta["xpAmount"] as? Double {
                    metrics["xp_earned"] = (metrics["xp_earned"] ?? 0) + xp
                }
            }

        case .contentPerformance:
            if let meta = atom.metadataDict {
                if let reach = meta["impressions"] as? Double {
                    metrics["content_reach"] = reach
                }
                if let engagement = meta["engagementRate"] as? Double {
                    metrics["content_engagement"] = engagement
                }
            }

        default:
            break
        }

        return metrics
    }

    // MARK: - Correlation Calculation

    /// Calculate all pairwise correlations between metrics
    private func calculateCorrelations(from dailyAggregates: [DailyMetricAggregate]) -> [CorrelationResult] {
        var results: [CorrelationResult] = []

        // Get all unique metric names
        let allMetrics = Set(dailyAggregates.flatMap { $0.metrics.keys })
        let metricArray = Array(allMetrics)

        // Calculate same-day correlations
        for i in 0..<metricArray.count {
            for j in (i + 1)..<metricArray.count {
                if let result = calculatePairwiseCorrelation(
                    metric1: metricArray[i],
                    metric2: metricArray[j],
                    data: dailyAggregates,
                    lagDays: 0
                ) {
                    results.append(result)
                }
            }
        }

        // Calculate lagged correlations (1-7 days)
        for lag in 1...7 {
            for sourceMetric in metricArray {
                for targetMetric in metricArray {
                    if sourceMetric != targetMetric {
                        if let result = calculatePairwiseCorrelation(
                            metric1: sourceMetric,
                            metric2: targetMetric,
                            data: dailyAggregates,
                            lagDays: lag
                        ) {
                            results.append(result)
                        }
                    }
                }
            }
        }

        // Filter to significant correlations
        return results.filter { $0.meetsThreshold }
    }

    /// Calculate Pearson correlation between two metrics
    private func calculatePairwiseCorrelation(
        metric1: String,
        metric2: String,
        data: [DailyMetricAggregate],
        lagDays: Int
    ) -> CorrelationResult? {
        var pairs: [(Double, Double)] = []

        for i in 0..<(data.count - lagDays) {
            guard let value1 = data[i].metrics[metric1],
                  let value2 = data[i + lagDays].metrics[metric2] else {
                continue
            }
            pairs.append((value1, value2))
        }

        guard pairs.count >= 10 else { return nil }

        // Calculate Pearson correlation coefficient
        let n = Double(pairs.count)
        let sumX = pairs.reduce(0) { $0 + $1.0 }
        let sumY = pairs.reduce(0) { $0 + $1.1 }
        let sumXY = pairs.reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = pairs.reduce(0) { $0 + $1.0 * $1.0 }
        let sumY2 = pairs.reduce(0) { $0 + $1.1 * $1.1 }

        let numerator = n * sumXY - sumX * sumY
        let denominator = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY))

        guard denominator > 0 else { return nil }

        let r = numerator / denominator

        // Calculate p-value (simplified t-test)
        let t = r * sqrt((n - 2) / (1 - r * r))
        let pValue = 2 * (1 - Self.tDistributionCDF(t: abs(t), df: n - 2))

        // Calculate effect size
        _ = sumX / n  // meanX calculated for potential future use
        let meanY = sumY / n
        let stdY = sqrt(sumY2 / n - meanY * meanY)
        let effectSize = stdY > 0 ? (r * stdY / max(meanY, 0.001)) : 0

        // Determine correlation type
        let corrType: CorrelationType
        if lagDays > 0 {
            corrType = .lagged
        } else if r < 0 {
            corrType = .inverse
        } else {
            corrType = .direct
        }

        // Determine strength
        let strength: CorrelationStrength
        let absR = abs(r)
        if absR >= 0.85 {
            strength = .veryStrong
        } else if absR >= 0.7 {
            strength = .strong
        } else if absR >= 0.5 {
            strength = .moderate
        } else {
            strength = .weak
        }

        return CorrelationResult(
            sourceMetric: metric1,
            targetMetric: metric2,
            coefficient: r,
            pValue: pValue,
            sampleSize: pairs.count,
            lagDays: lagDays,
            correlationType: corrType,
            strength: strength,
            effectSize: effectSize
        )
    }

    /// Simplified t-distribution CDF
    private static func tDistributionCDF(t: Double, df: Double) -> Double {
        // Use normal approximation for large df
        if df > 30 {
            return 0.5 * (1 + erf(t / sqrt(2)))
        }
        // Simplified approximation for smaller df
        let x = df / (df + t * t)
        return 1 - 0.5 * pow(x, df / 2)
    }

    // MARK: - Insight Management

    /// Load existing insights from database
    private func loadExistingInsights() async throws -> [CorrelationInsight] {
        try await database.read { db in
            let atoms = try Atom
                .filter(Column("type") == AtomType.correlationInsight.rawValue)
                .filter(Column("is_deleted") == false)
                .fetchAll(db)

            return atoms.compactMap { atom -> CorrelationInsight? in
                guard let meta = atom.metadataValue(as: CorrelationInsightMetadata.self) else {
                    return nil
                }

                return CorrelationInsight(
                    uuid: atom.uuid,
                    sourceMetric: meta.sourceMetric,
                    targetMetric: meta.targetMetric,
                    correlationType: CorrelationType(rawValue: meta.correlationType) ?? .direct,
                    strength: CorrelationStrength(rawValue: meta.strength) ?? .weak,
                    confidence: CorrelationConfidence(rawValue: meta.confidence) ?? .emerging,
                    coefficient: meta.coefficient,
                    effectSize: meta.effectSize,
                    lagDays: meta.lagDays,
                    occurrences: meta.occurrences,
                    firstObserved: meta.firstObserved,
                    lastValidated: meta.lastValidated,
                    decayFactor: meta.decayFactor,
                    humanDescription: atom.body ?? "",
                    actionableAdvice: meta.actionableAdvice
                )
            }
        }
    }

    /// Update existing insights with new correlation data
    private func updateExistingInsights(
        _ insights: inout [CorrelationInsight],
        withNewCorrelations correlations: [CorrelationResult]
    ) -> (validated: Int, decayed: Int, removed: Int) {
        var validated = 0
        var decayed = 0
        var removed = 0
        var updatedInsights: [CorrelationInsight] = []

        for insight in insights {
            // Check if this insight is validated by new data
            let matchingCorrelation = correlations.first {
                $0.sourceMetric == insight.sourceMetric &&
                $0.targetMetric == insight.targetMetric &&
                $0.lagDays == insight.lagDays
            }

            if let match = matchingCorrelation {
                // Insight is validated
                let newOccurrences = insight.occurrences + 1
                let newConfidence: CorrelationConfidence
                if newOccurrences >= 50 {
                    newConfidence = .proven
                } else if newOccurrences >= 20 {
                    newConfidence = .established
                } else if newOccurrences >= 10 {
                    newConfidence = .developing
                } else {
                    newConfidence = .emerging
                }

                let updated = CorrelationInsight(
                    uuid: insight.uuid,
                    sourceMetric: insight.sourceMetric,
                    targetMetric: insight.targetMetric,
                    correlationType: insight.correlationType,
                    strength: match.strength,
                    confidence: newConfidence,
                    coefficient: (insight.coefficient + match.coefficient) / 2,  // Running average
                    effectSize: (insight.effectSize + match.effectSize) / 2,
                    lagDays: insight.lagDays,
                    occurrences: newOccurrences,
                    firstObserved: insight.firstObserved,
                    lastValidated: Date(),
                    decayFactor: 1.0,  // Reset decay on validation
                    humanDescription: insight.humanDescription,
                    actionableAdvice: insight.actionableAdvice
                )
                updatedInsights.append(updated)
                validated += 1
            } else {
                // Insight not validated - apply decay
                let newDecay = insight.decayFactor - Self.dailyDecayRate

                if newDecay <= Self.removalDecayThreshold {
                    // Remove this insight
                    removed += 1
                } else {
                    let decayedInsight = CorrelationInsight(
                        uuid: insight.uuid,
                        sourceMetric: insight.sourceMetric,
                        targetMetric: insight.targetMetric,
                        correlationType: insight.correlationType,
                        strength: insight.strength,
                        confidence: insight.confidence,
                        coefficient: insight.coefficient,
                        effectSize: insight.effectSize,
                        lagDays: insight.lagDays,
                        occurrences: insight.occurrences,
                        firstObserved: insight.firstObserved,
                        lastValidated: insight.lastValidated,
                        decayFactor: newDecay,
                        humanDescription: insight.humanDescription,
                        actionableAdvice: insight.actionableAdvice
                    )
                    updatedInsights.append(decayedInsight)
                    decayed += 1
                }
            }
        }

        insights = updatedInsights
        return (validated, decayed, removed)
    }

    /// Create new insights from correlations not already tracked
    private func createNewInsights(
        from correlations: [CorrelationResult],
        existingInsights: [CorrelationInsight]
    ) -> [CorrelationInsight] {
        var newInsights: [CorrelationInsight] = []

        for correlation in correlations {
            // Check if this correlation is already tracked
            let isTracked = existingInsights.contains {
                $0.sourceMetric == correlation.sourceMetric &&
                $0.targetMetric == correlation.targetMetric &&
                $0.lagDays == correlation.lagDays
            }

            if !isTracked && correlation.meetsThreshold {
                let description = generateHumanDescription(for: correlation)
                let advice = generateActionableAdvice(for: correlation)

                let insight = CorrelationInsight(
                    uuid: UUID().uuidString,
                    sourceMetric: correlation.sourceMetric,
                    targetMetric: correlation.targetMetric,
                    correlationType: correlation.correlationType,
                    strength: correlation.strength,
                    confidence: .emerging,
                    coefficient: correlation.coefficient,
                    effectSize: correlation.effectSize,
                    lagDays: correlation.lagDays,
                    occurrences: 1,
                    firstObserved: Date(),
                    lastValidated: Date(),
                    decayFactor: 1.0,
                    humanDescription: description,
                    actionableAdvice: advice
                )
                newInsights.append(insight)
            }
        }

        return newInsights
    }

    /// Generate a human-readable description for a correlation
    private func generateHumanDescription(for correlation: CorrelationResult) -> String {
        let direction = correlation.coefficient > 0 ? "higher" : "lower"
        let effect = String(format: "%.0f%%", abs(correlation.effectSize * 100))

        if correlation.lagDays > 0 {
            return "When your \(formatMetricName(correlation.sourceMetric)) is high, your \(formatMetricName(correlation.targetMetric)) tends to be \(effect) \(direction) \(correlation.lagDays) day\(correlation.lagDays > 1 ? "s" : "") later."
        } else {
            return "Higher \(formatMetricName(correlation.sourceMetric)) correlates with \(effect) \(direction) \(formatMetricName(correlation.targetMetric))."
        }
    }

    /// Generate actionable advice for a correlation
    private func generateActionableAdvice(for correlation: CorrelationResult) -> String? {
        // Only generate advice for actionable metrics
        let actionableSourceMetrics = ["sleep_hours", "deep_sleep_minutes", "workout_minutes", "deep_work_minutes"]
        let positiveTargetMetrics = ["hrv", "focus_score", "readiness_score", "content_engagement"]

        if actionableSourceMetrics.contains(correlation.sourceMetric) &&
           positiveTargetMetrics.contains(correlation.targetMetric) &&
           correlation.coefficient > 0 {
            return "Try increasing your \(formatMetricName(correlation.sourceMetric)) to boost your \(formatMetricName(correlation.targetMetric))."
        }

        return nil
    }

    /// Format a metric name for display
    private func formatMetricName(_ metric: String) -> String {
        metric.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Persistence

    /// Save insights to the database
    private func saveInsights(_ insights: [CorrelationInsight]) async throws {
        try await database.write { db in
            for insight in insights {
                let metadata = CorrelationInsightMetadata(from: insight)

                // Check if this insight already exists
                if let existingAtom = try Atom
                    .filter(Column("uuid") == insight.uuid)
                    .fetchOne(db) {
                    // Update existing
                    var updated = existingAtom
                    updated.body = insight.humanDescription
                    updated.metadata = try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
                    updated.updatedAt = Date().ISO8601Format()
                    try updated.save(db)
                } else {
                    // Create new
                    var atom = Atom.new(
                        type: .correlationInsight,
                        title: "\(insight.sourceMetric) → \(insight.targetMetric)",
                        body: insight.humanDescription
                    )
                    atom.uuid = insight.uuid
                    atom.metadata = try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
                    try atom.insert(db)
                }
            }

            // Mark removed insights as deleted
            let activeUUIDs = insights.map { $0.uuid }
            if !activeUUIDs.isEmpty {
                try db.execute(sql: """
                    UPDATE atoms
                    SET is_deleted = 1, updated_at = ?
                    WHERE type = ? AND uuid NOT IN (\(activeUUIDs.map { "'\($0)'" }.joined(separator: ", ")))
                """, arguments: [Date().ISO8601Format(), AtomType.correlationInsight.rawValue])
            }
        }
    }

    /// Record the computation as an Atom
    private func recordComputation(metadata: CausalityComputationMetadata) async throws {
        try await database.write { db in
            var atom = Atom.new(
                type: .causalityComputation,
                title: "Causality Computation - \(metadata.computedAt.formatted(date: .abbreviated, time: .shortened))"
            )
            atom.metadata = try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
            try atom.insert(db)
        }
    }

    // MARK: - Public Accessors

    /// Get active insights for display
    public func getActiveInsights() async throws -> [CorrelationInsight] {
        if cachedInsights.isEmpty {
            cachedInsights = try await loadExistingInsights()
        }
        return cachedInsights.filter { $0.isActive }.sorted { $0.displayPriority > $1.displayPriority }
    }

    /// Get insights for a specific dimension
    public func getInsights(for dimension: LevelDimension) async throws -> [CorrelationInsight] {
        let all = try await getActiveInsights()
        let dimensionMetrics = metricsForDimension(dimension)
        return all.filter {
            dimensionMetrics.contains($0.sourceMetric) || dimensionMetrics.contains($0.targetMetric)
        }
    }

    /// Get top insights for Sanctuary display
    public func getTopInsights(limit: Int = 5) async throws -> [CorrelationInsight] {
        let active = try await getActiveInsights()
        return Array(active.prefix(limit))
    }

    /// Force a refresh of cached insights
    public func refreshCache() async throws {
        cachedInsights = try await loadExistingInsights()
    }

    // MARK: - Helpers

    private nonisolated func dateKey(_ date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year!)-\(components.month!)-\(components.day!)"
    }

    private func metricsForDimension(_ dimension: LevelDimension) -> Set<String> {
        switch dimension {
        case .cognitive:
            return ["deep_work_minutes", "deep_work_quality", "focus_score", "tasks_completed"]
        case .creative:
            return ["words_written", "writing_minutes", "daily_word_count", "content_reach", "content_engagement"]
        case .physiological:
            return ["hrv", "hrv_rmssd", "resting_hr", "sleep_hours", "deep_sleep_minutes", "rem_sleep_minutes", "sleep_efficiency", "readiness_score", "workout_minutes"]
        case .behavioral:
            return ["tasks_completed", "sleep_schedule_deviation"]
        case .knowledge:
            return ["xp_earned"]
        case .reflection:
            return ["journal_entries", "journal_word_count", "emotional_valence", "emotional_energy"]
        }
    }
}

// MARK: - Errors

public enum CausalityError: Error, LocalizedError {
    case computationInProgress
    case invalidDateRange
    case noDataAvailable
    case databaseError(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .computationInProgress:
            return "A causality computation is already in progress"
        case .invalidDateRange:
            return "Invalid date range for correlation analysis"
        case .noDataAvailable:
            return "Not enough data available for correlation analysis"
        case .databaseError(let underlying):
            return "Database error: \(underlying.localizedDescription)"
        }
    }
}
