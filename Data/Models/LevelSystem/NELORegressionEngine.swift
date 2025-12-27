// CosmoOS/Data/Models/LevelSystem/NELORegressionEngine.swift
// NELO Regression Engine - Dynamic performance rating that can rise and fall
// Based on ELO rating system with domain-specific regression rules

import Foundation

// MARK: - NELO Regression Engine

/// Engine for calculating NELO (Neuro-ELO) rating changes
/// NELO is a dynamic performance metric that reflects recent activity and can regress
public final class NELORegressionEngine {

    // MARK: - Initialization

    public init() {}

    // MARK: - Regression Rules

    /// Per-dimension regression thresholds and rules
    /// Based on cognitive science research for optimal performance tracking
    struct RegressionRules {
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // COGNITIVE: 3-day rolling average drops >40%
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        static let cognitiveDropThreshold = 0.4      // 40% drop triggers regression
        static let cognitiveWindow = 3               // 3-day rolling average
        static let cognitiveInactivityDays = 3       // Days before inactivity penalty
        static let cognitiveInactivityRate = 0.05   // 5% NELO loss per day inactive

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // CREATIVE: 30-day reach < 60-day baseline
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        static let creativeRecentWindow = 30         // Recent 30 days
        static let creativeBaselineWindow = 60       // Baseline 60 days
        static let creativeDropThreshold = 0.5       // 50% drop triggers regression
        static let creativeInactivityDays = 7        // Days before inactivity penalty
        static let creativeInactivityRate = 0.03    // 3% NELO loss per day inactive

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // PHYSIOLOGICAL: HRV drops vs 7-day baseline
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        static let physiologicalHRVDropThreshold = 0.15  // 15% HRV drop
        static let physiologicalWindow = 7           // 7-day baseline
        static let physiologicalInactivityDays = 2   // Days before inactivity penalty
        static let physiologicalInactivityRate = 0.04 // 4% NELO loss per day

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // BEHAVIORAL: Deep work drops OR destructive habits increase
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        static let behavioralDeepWorkDropThreshold = 0.3  // 30% drop
        static let behavioralWindow = 7              // 7-day window
        static let behavioralInactivityDays = 2      // Days before inactivity penalty
        static let behavioralInactivityRate = 0.06  // 6% NELO loss per day

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // KNOWLEDGE: Minimal regression (knowledge persists)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        static let knowledgeInactivityDays = 30      // Long grace period
        static let knowledgeInactivityRate = 0.01   // 1% NELO loss per day
        static let knowledgeDecayRate = 0.0          // No natural decay

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // REFLECTION: Minimal if journaling stops
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        static let reflectionInactivityDays = 7      // Days before inactivity penalty
        static let reflectionInactivityRate = 0.02  // 2% NELO loss per week inactive
    }

    // MARK: - K-Factor Calculation

    /// K-factor determines NELO rating volatility (chess-style)
    /// Higher K = more volatile, lower K = more stable
    static func kFactor(forNELO nelo: Int) -> Double {
        switch nelo {
        case ..<1000:
            return 40   // High volatility for beginners (fast learning)
        case 1000..<1200:
            return 32   // Still learning
        case 1200..<1400:
            return 24   // Competent
        case 1400..<1600:
            return 20   // Proficient
        case 1600..<1800:
            return 16   // Expert
        case 1800..<2000:
            return 12   // Master
        case 2000..<2200:
            return 10   // Grandmaster
        default:
            return 8    // Legend: very slow, stable changes
        }
    }

    // MARK: - NELO Change Calculations

    /// Calculate NELO change for a dimension based on recent performance
    func calculateNELOChange(
        dimension: LevelDimension,
        currentNELO: Int,
        metrics: DimensionMetrics
    ) -> NELOChange {
        let k = Self.kFactor(forNELO: currentNELO)

        switch dimension {
        case .cognitive:
            return calculateCognitiveNELOChange(currentNELO: currentNELO, k: k, metrics: metrics)
        case .creative:
            return calculateCreativeNELOChange(currentNELO: currentNELO, k: k, metrics: metrics)
        case .physiological:
            return calculatePhysiologicalNELOChange(currentNELO: currentNELO, k: k, metrics: metrics)
        case .behavioral:
            return calculateBehavioralNELOChange(currentNELO: currentNELO, k: k, metrics: metrics)
        case .knowledge:
            return calculateKnowledgeNELOChange(currentNELO: currentNELO, k: k, metrics: metrics)
        case .reflection:
            return calculateReflectionNELOChange(currentNELO: currentNELO, k: k, metrics: metrics)
        }
    }

    // MARK: - Per-Dimension Calculations

    /// Cognitive NELO change (words written, tasks, deep work)
    private func calculateCognitiveNELOChange(
        currentNELO: Int,
        k: Double,
        metrics: DimensionMetrics
    ) -> NELOChange {
        var change = 0.0
        var reasons: [String] = []

        // Performance vs rolling average
        if let recentOutput = metrics.recentAverage,
           let baselineOutput = metrics.baselineAverage {
            let ratio = recentOutput / max(baselineOutput, 1)

            if ratio >= 1.2 {
                // 20%+ improvement
                change += k * 0.5
                reasons.append("Output +\(Int((ratio - 1) * 100))% vs baseline")
            } else if ratio < (1.0 - RegressionRules.cognitiveDropThreshold) {
                // Significant drop
                change -= k * 0.4
                reasons.append("Output dropped \(Int((1 - ratio) * 100))%")
            } else if ratio >= 1.0 {
                // Maintaining or slight improvement
                change += k * 0.1
                reasons.append("Maintaining output")
            }
        }

        // Inactivity penalty
        if metrics.daysSinceActive >= RegressionRules.cognitiveInactivityDays {
            let penaltyDays = metrics.daysSinceActive - RegressionRules.cognitiveInactivityDays
            let penalty = Double(currentNELO) * RegressionRules.cognitiveInactivityRate * Double(penaltyDays)
            change -= penalty
            reasons.append("Inactive for \(metrics.daysSinceActive) days")
        }

        // Deep work bonus
        if let deepWorkHours = metrics.additionalMetrics["deepWorkHours"],
           deepWorkHours >= 4.0 {
            change += k * 0.3
            reasons.append("Deep work: \(String(format: "%.1f", deepWorkHours))h")
        }

        return NELOChange(
            change: Int(change),
            reasons: reasons,
            dimension: .cognitive
        )
    }

    /// Creative NELO change (content performance, reach, engagement)
    private func calculateCreativeNELOChange(
        currentNELO: Int,
        k: Double,
        metrics: DimensionMetrics
    ) -> NELOChange {
        var change = 0.0
        var reasons: [String] = []

        // Reach comparison (30-day vs 60-day baseline)
        if let recentReach = metrics.recentAverage,
           let baselineReach = metrics.baselineAverage,
           baselineReach > 0 {
            let ratio = recentReach / baselineReach

            if ratio >= 1.5 {
                // Significant growth
                change += k * 0.6
                reasons.append("Reach +\(Int((ratio - 1) * 100))%")
            } else if ratio >= 1.2 {
                // Good growth
                change += k * 0.3
                reasons.append("Reach improving")
            } else if ratio < (1.0 - RegressionRules.creativeDropThreshold) {
                // Significant drop
                change -= k * 0.5
                reasons.append("Reach dropped \(Int((1 - ratio) * 100))%")
            }
        }

        // Viral content bonus
        if let viralCount = metrics.additionalMetrics["viralPosts"],
           viralCount > 0 {
            change += k * viralCount * 0.5
            reasons.append("\(Int(viralCount)) viral post(s)")
        }

        // Engagement rate bonus
        if let engagementRate = metrics.additionalMetrics["engagementRate"],
           engagementRate > 3.0 { // >3% is good
            change += k * 0.2
            reasons.append("High engagement: \(String(format: "%.1f", engagementRate))%")
        }

        // Inactivity penalty
        if metrics.daysSinceActive >= RegressionRules.creativeInactivityDays {
            let penaltyDays = metrics.daysSinceActive - RegressionRules.creativeInactivityDays
            let penalty = Double(currentNELO) * RegressionRules.creativeInactivityRate * Double(penaltyDays)
            change -= penalty
            reasons.append("No content for \(metrics.daysSinceActive) days")
        }

        return NELOChange(
            change: Int(change),
            reasons: reasons,
            dimension: .creative
        )
    }

    /// Physiological NELO change (HRV, sleep, readiness)
    private func calculatePhysiologicalNELOChange(
        currentNELO: Int,
        k: Double,
        metrics: DimensionMetrics
    ) -> NELOChange {
        var change = 0.0
        var reasons: [String] = []

        // HRV comparison
        if let recentHRV = metrics.recentAverage,
           let baselineHRV = metrics.baselineAverage,
           baselineHRV > 0 {
            let ratio = recentHRV / baselineHRV

            if ratio >= 1.1 {
                // HRV improvement
                change += k * 0.4
                reasons.append("HRV +\(Int((ratio - 1) * 100))% vs baseline")
            } else if ratio < (1.0 - RegressionRules.physiologicalHRVDropThreshold) {
                // HRV drop
                change -= k * 0.4
                reasons.append("HRV dropped \(Int((1 - ratio) * 100))%")
            }
        }

        // Sleep consistency bonus
        if let sleepConsistency = metrics.additionalMetrics["sleepConsistency"],
           sleepConsistency >= 80 {
            change += k * 0.3
            reasons.append("Sleep consistency: \(Int(sleepConsistency))%")
        }

        // Readiness score
        if let readiness = metrics.additionalMetrics["readinessScore"] {
            if readiness >= 80 {
                change += k * 0.2
                reasons.append("Optimal readiness: \(Int(readiness))")
            } else if readiness < 50 {
                change -= k * 0.2
                reasons.append("Low readiness: \(Int(readiness))")
            }
        }

        // Workout bonus
        if let workouts = metrics.additionalMetrics["weeklyWorkouts"],
           workouts >= 3 {
            change += k * 0.2
            reasons.append("\(Int(workouts)) workouts this week")
        }

        // Inactivity penalty
        if metrics.daysSinceActive >= RegressionRules.physiologicalInactivityDays {
            let penaltyDays = metrics.daysSinceActive - RegressionRules.physiologicalInactivityDays
            let penalty = Double(currentNELO) * RegressionRules.physiologicalInactivityRate * Double(penaltyDays)
            change -= penalty
            reasons.append("No health data for \(metrics.daysSinceActive) days")
        }

        return NELOChange(
            change: Int(change),
            reasons: reasons,
            dimension: .physiological
        )
    }

    /// Behavioral NELO change (deep work, routines, consistency)
    private func calculateBehavioralNELOChange(
        currentNELO: Int,
        k: Double,
        metrics: DimensionMetrics
    ) -> NELOChange {
        var change = 0.0
        var reasons: [String] = []

        // Deep work hours vs baseline
        if let recentDeepWork = metrics.recentAverage,
           let baselineDeepWork = metrics.baselineAverage,
           baselineDeepWork > 0 {
            let ratio = recentDeepWork / baselineDeepWork

            if ratio >= 1.2 {
                change += k * 0.4
                reasons.append("Deep work +\(Int((ratio - 1) * 100))%")
            } else if ratio < (1.0 - RegressionRules.behavioralDeepWorkDropThreshold) {
                change -= k * 0.5
                reasons.append("Deep work dropped \(Int((1 - ratio) * 100))%")
            }
        }

        // Routine adherence
        if let routineAdherence = metrics.additionalMetrics["routineAdherence"] {
            if routineAdherence >= 80 {
                change += k * 0.3
                reasons.append("Routine adherence: \(Int(routineAdherence))%")
            } else if routineAdherence < 50 {
                change -= k * 0.2
                reasons.append("Low routine adherence: \(Int(routineAdherence))%")
            }
        }

        // Distraction events penalty
        if let distractionRate = metrics.additionalMetrics["distractionRate"],
           distractionRate > 0.3 { // >30% distraction
            change -= k * 0.3
            reasons.append("High distraction rate: \(Int(distractionRate * 100))%")
        }

        // Streak bonus
        if let streakDays = metrics.additionalMetrics["taskCompletionStreak"],
           streakDays >= 7 {
            change += k * 0.2
            reasons.append("\(Int(streakDays))-day task streak")
        }

        // Inactivity penalty
        if metrics.daysSinceActive >= RegressionRules.behavioralInactivityDays {
            let penaltyDays = metrics.daysSinceActive - RegressionRules.behavioralInactivityDays
            let penalty = Double(currentNELO) * RegressionRules.behavioralInactivityRate * Double(penaltyDays)
            change -= penalty
            reasons.append("Inactive for \(metrics.daysSinceActive) days")
        }

        return NELOChange(
            change: Int(change),
            reasons: reasons,
            dimension: .behavioral
        )
    }

    /// Knowledge NELO change (research, connections, semantic density)
    private func calculateKnowledgeNELOChange(
        currentNELO: Int,
        k: Double,
        metrics: DimensionMetrics
    ) -> NELOChange {
        var change = 0.0
        var reasons: [String] = []

        // Knowledge graph growth
        if let recentConnections = metrics.recentAverage,
           let baselineConnections = metrics.baselineAverage,
           baselineConnections > 0 {
            let ratio = recentConnections / baselineConnections

            if ratio >= 1.1 {
                change += k * 0.3
                reasons.append("Knowledge graph +\(Int((ratio - 1) * 100))%")
            }
        }

        // New connections bonus
        if let newConnections = metrics.additionalMetrics["newConnections"],
           newConnections > 0 {
            change += k * 0.1 * min(newConnections, 10) // Cap at 10
            reasons.append("\(Int(newConnections)) new connections")
        }

        // Semantic clusters
        if let clusters = metrics.additionalMetrics["semanticClusters"],
           clusters > 0 {
            change += k * 0.2
            reasons.append("\(Int(clusters)) semantic clusters formed")
        }

        // Research added
        if let research = metrics.additionalMetrics["researchAdded"],
           research > 0 {
            change += k * 0.1 * min(research, 5) // Cap at 5
            reasons.append("\(Int(research)) research items added")
        }

        // Knowledge doesn't decay quickly
        if metrics.daysSinceActive >= RegressionRules.knowledgeInactivityDays {
            let penaltyDays = metrics.daysSinceActive - RegressionRules.knowledgeInactivityDays
            let penalty = Double(currentNELO) * RegressionRules.knowledgeInactivityRate * Double(penaltyDays)
            change -= penalty
            reasons.append("No knowledge activity for \(metrics.daysSinceActive) days")
        }

        return NELOChange(
            change: Int(change),
            reasons: reasons,
            dimension: .knowledge
        )
    }

    /// Reflection NELO change (journaling, insights, self-awareness)
    private func calculateReflectionNELOChange(
        currentNELO: Int,
        k: Double,
        metrics: DimensionMetrics
    ) -> NELOChange {
        var change = 0.0
        var reasons: [String] = []

        // Journaling consistency
        if let journalDays = metrics.additionalMetrics["journalDaysThisWeek"] {
            if journalDays >= 5 {
                change += k * 0.4
                reasons.append("Consistent journaling (\(Int(journalDays)) days)")
            } else if journalDays >= 3 {
                change += k * 0.2
                reasons.append("Regular journaling (\(Int(journalDays)) days)")
            }
        }

        // Insight generation
        if let insights = metrics.additionalMetrics["insightsGenerated"],
           insights > 0 {
            change += k * 0.1 * min(insights, 10)
            reasons.append("\(Int(insights)) insights generated")
        }

        // Clarity score
        if let avgClarity = metrics.additionalMetrics["avgClarityScore"] {
            if avgClarity >= 80 {
                change += k * 0.3
                reasons.append("High clarity: \(Int(avgClarity))")
            } else if avgClarity >= 70 {
                change += k * 0.1
                reasons.append("Good clarity: \(Int(avgClarity))")
            }
        }

        // Emotional awareness
        if let emotionalLogs = metrics.additionalMetrics["emotionalStateLogs"],
           emotionalLogs > 0 {
            change += k * 0.15
            reasons.append("Tracking emotional state")
        }

        // Inactivity penalty
        if metrics.daysSinceActive >= RegressionRules.reflectionInactivityDays {
            let penaltyWeeks = Double(metrics.daysSinceActive - RegressionRules.reflectionInactivityDays) / 7.0
            let penalty = Double(currentNELO) * RegressionRules.reflectionInactivityRate * penaltyWeeks
            change -= penalty
            reasons.append("No reflection for \(metrics.daysSinceActive) days")
        }

        return NELOChange(
            change: Int(change),
            reasons: reasons,
            dimension: .reflection
        )
    }

    // MARK: - Daily Regression Check

    /// Calculate daily regression for all dimensions
    /// Called by the daily cron engine
    func calculateDailyRegression(
        dimensions: [LevelDimension: DimensionProgress]
    ) -> [LevelDimension: NELOChange] {
        var changes: [LevelDimension: NELOChange] = [:]

        for (dimension, progress) in dimensions {
            // Only apply regression if inactive past threshold
            let threshold = inactivityThreshold(for: dimension)
            if progress.daysSinceActive > threshold {
                let penaltyRate = inactivityRate(for: dimension)
                let daysOverThreshold = progress.daysSinceActive - threshold
                let penalty = Int(Double(progress.nelo) * penaltyRate * Double(daysOverThreshold))

                changes[dimension] = NELOChange(
                    change: -penalty,
                    reasons: ["Inactivity regression (\(progress.daysSinceActive) days)"],
                    dimension: dimension
                )
            }
        }

        return changes
    }

    private func inactivityThreshold(for dimension: LevelDimension) -> Int {
        switch dimension {
        case .cognitive: return RegressionRules.cognitiveInactivityDays
        case .creative: return RegressionRules.creativeInactivityDays
        case .physiological: return RegressionRules.physiologicalInactivityDays
        case .behavioral: return RegressionRules.behavioralInactivityDays
        case .knowledge: return RegressionRules.knowledgeInactivityDays
        case .reflection: return RegressionRules.reflectionInactivityDays
        }
    }

    private func inactivityRate(for dimension: LevelDimension) -> Double {
        switch dimension {
        case .cognitive: return RegressionRules.cognitiveInactivityRate
        case .creative: return RegressionRules.creativeInactivityRate
        case .physiological: return RegressionRules.physiologicalInactivityRate
        case .behavioral: return RegressionRules.behavioralInactivityRate
        case .knowledge: return RegressionRules.knowledgeInactivityRate
        case .reflection: return RegressionRules.reflectionInactivityRate
        }
    }
}

// MARK: - Supporting Types

/// Result of a NELO calculation
struct NELOChange: Sendable {
    let change: Int
    let reasons: [String]
    let dimension: LevelDimension

    var isPositive: Bool { change > 0 }
    var isNegative: Bool { change < 0 }
    var isNeutral: Bool { change == 0 }

    /// Formatted description
    var description: String {
        let sign = change >= 0 ? "+" : ""
        let reasonText = reasons.joined(separator: ", ")
        return "\(sign)\(change) NELO (\(reasonText))"
    }
}

/// Metrics for calculating dimension NELO
struct DimensionMetrics: Sendable {
    /// Recent average (3-30 days depending on dimension)
    let recentAverage: Double?

    /// Baseline average (7-60 days depending on dimension)
    let baselineAverage: Double?

    /// Days since last activity in this dimension
    let daysSinceActive: Int

    /// Additional dimension-specific metrics
    let additionalMetrics: [String: Double]

    init(
        recentAverage: Double? = nil,
        baselineAverage: Double? = nil,
        daysSinceActive: Int = 0,
        additionalMetrics: [String: Double] = [:]
    ) {
        self.recentAverage = recentAverage
        self.baselineAverage = baselineAverage
        self.daysSinceActive = daysSinceActive
        self.additionalMetrics = additionalMetrics
    }
}

// MARK: - NELO Range Constants

extension NELORegressionEngine {
    /// Minimum possible NELO (prevents going below this)
    static let minimumNELO = 800

    /// Maximum possible NELO (theoretical ceiling)
    static let maximumNELO = 2400

    /// Starting NELO for new users
    static let startingNELO = 1200

    /// Clamp NELO to valid range
    static func clampNELO(_ nelo: Int) -> Int {
        max(minimumNELO, min(maximumNELO, nelo))
    }
}
