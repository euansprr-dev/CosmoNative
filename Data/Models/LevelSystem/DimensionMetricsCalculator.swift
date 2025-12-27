// CosmoOS/Data/Models/LevelSystem/DimensionMetricsCalculator.swift
// Calculates dimension metrics from atoms for level and NELO calculations
// Queries the atoms table to compute real-time performance metrics

import Foundation
import GRDB

// MARK: - Dimension Metrics Calculator

/// Calculator for aggregating dimension metrics from atoms
/// Used by the Level System to track progress and calculate NELO changes
public final class DimensionMetricsCalculator {

    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Metric Calculation

    /// Calculate all metrics for a dimension
    func calculateMetrics(
        for dimension: LevelDimension,
        recentWindow: Int = 7,
        baselineWindow: Int = 30
    ) async throws -> DimensionMetrics {
        switch dimension {
        case .cognitive:
            return try await calculateCognitiveMetrics(recentWindow: recentWindow, baselineWindow: baselineWindow)
        case .creative:
            return try await calculateCreativeMetrics(recentWindow: recentWindow, baselineWindow: baselineWindow)
        case .physiological:
            return try await calculatePhysiologicalMetrics(recentWindow: recentWindow, baselineWindow: baselineWindow)
        case .behavioral:
            return try await calculateBehavioralMetrics(recentWindow: recentWindow, baselineWindow: baselineWindow)
        case .knowledge:
            return try await calculateKnowledgeMetrics(recentWindow: recentWindow, baselineWindow: baselineWindow)
        case .reflection:
            return try await calculateReflectionMetrics(recentWindow: recentWindow, baselineWindow: baselineWindow)
        }
    }

    // MARK: - Cognitive Metrics

    /// Calculate cognitive dimension metrics (writing, tasks, deep work)
    private func calculateCognitiveMetrics(
        recentWindow: Int,
        baselineWindow: Int
    ) async throws -> DimensionMetrics {
        try await dbQueue.read { db in
            let recentDate = Date().addingTimeInterval(-Double(recentWindow) * 86400)
            let baselineDate = Date().addingTimeInterval(-Double(baselineWindow) * 86400)
            let recentDateStr = ISO8601DateFormatter().string(from: recentDate)
            let baselineDateStr = ISO8601DateFormatter().string(from: baselineDate)

            // Recent word count (from writing sessions)
            let recentWords = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(
                    CAST(json_extract(metadata, '$.netWordCount') AS INTEGER)
                ), 0)
                FROM atoms
                WHERE type = 'writing_session'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Baseline word count
            let baselineWords = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(
                    CAST(json_extract(metadata, '$.netWordCount') AS INTEGER)
                ), 0)
                FROM atoms
                WHERE type = 'writing_session'
                AND is_deleted = 0
                AND created_at >= ?
                AND created_at < ?
            """, arguments: [baselineDateStr, recentDateStr]) ?? 0

            // Average per day
            let recentAvg = Double(recentWords) / Double(recentWindow)
            let baselineDays = baselineWindow - recentWindow
            let baselineAvg = baselineDays > 0 ? Double(baselineWords) / Double(baselineDays) : 0

            // Deep work hours
            let deepWorkHours = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(
                    CAST(json_extract(metadata, '$.duration') AS REAL) / 3600.0
                ), 0)
                FROM atoms
                WHERE type = 'deep_work_block'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Tasks completed
            let tasksCompleted = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'task'
                AND is_deleted = 0
                AND json_extract(metadata, '$.isCompleted') = 1
                AND json_extract(metadata, '$.completedAt') >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Average focus score
            let avgFocusScore = try Double.fetchOne(db, sql: """
                SELECT AVG(CAST(json_extract(metadata, '$.score') AS REAL))
                FROM atoms
                WHERE type = 'focus_score'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Days since last activity
            let lastActivity = try Date.fetchOne(db, sql: """
                SELECT MAX(created_at)
                FROM atoms
                WHERE type IN ('writing_session', 'deep_work_block', 'focus_score')
                AND is_deleted = 0
            """)
            let daysSinceActive = lastActivity.map {
                Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
            } ?? 999

            return DimensionMetrics(
                recentAverage: recentAvg,
                baselineAverage: baselineAvg,
                daysSinceActive: daysSinceActive,
                additionalMetrics: [
                    "deepWorkHours": deepWorkHours,
                    "tasksCompleted": Double(tasksCompleted),
                    "avgFocusScore": avgFocusScore,
                    "recentWords": Double(recentWords)
                ]
            )
        }
    }

    // MARK: - Creative Metrics

    /// Calculate creative dimension metrics (reach, engagement, virality)
    private func calculateCreativeMetrics(
        recentWindow: Int,
        baselineWindow: Int
    ) async throws -> DimensionMetrics {
        try await dbQueue.read { db in
            let recentDate = Date().addingTimeInterval(-Double(recentWindow) * 86400)
            let baselineDate = Date().addingTimeInterval(-Double(baselineWindow) * 86400)
            let recentDateStr = ISO8601DateFormatter().string(from: recentDate)
            let baselineDateStr = ISO8601DateFormatter().string(from: baselineDate)

            // Recent impressions
            let recentImpressions = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(
                    CAST(json_extract(metadata, '$.impressions') AS INTEGER)
                ), 0)
                FROM atoms
                WHERE type = 'content_performance'
                AND is_deleted = 0
                AND json_extract(metadata, '$.lastUpdated') >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Baseline impressions
            let baselineImpressions = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(
                    CAST(json_extract(metadata, '$.impressions') AS INTEGER)
                ), 0)
                FROM atoms
                WHERE type = 'content_performance'
                AND is_deleted = 0
                AND json_extract(metadata, '$.lastUpdated') >= ?
                AND json_extract(metadata, '$.lastUpdated') < ?
            """, arguments: [baselineDateStr, recentDateStr]) ?? 0

            // Viral posts count
            let viralPosts = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'content_performance'
                AND is_deleted = 0
                AND json_extract(metadata, '$.isViral') = 1
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Average engagement rate
            let avgEngagement = try Double.fetchOne(db, sql: """
                SELECT AVG(CAST(json_extract(metadata, '$.engagementRate') AS REAL))
                FROM atoms
                WHERE type = 'content_performance'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Content published
            let contentPublished = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'content_publish'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Days since last activity
            let lastActivity = try Date.fetchOne(db, sql: """
                SELECT MAX(created_at)
                FROM atoms
                WHERE type IN ('content_publish', 'content_performance')
                AND is_deleted = 0
            """)
            let daysSinceActive = lastActivity.map {
                Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
            } ?? 999

            let baselineDays = baselineWindow - recentWindow
            return DimensionMetrics(
                recentAverage: Double(recentImpressions) / Double(recentWindow),
                baselineAverage: baselineDays > 0 ? Double(baselineImpressions) / Double(baselineDays) : 0,
                daysSinceActive: daysSinceActive,
                additionalMetrics: [
                    "viralPosts": Double(viralPosts),
                    "engagementRate": avgEngagement,
                    "contentPublished": Double(contentPublished),
                    "weeklyReach": Double(recentImpressions)
                ]
            )
        }
    }

    // MARK: - Physiological Metrics

    /// Calculate physiological dimension metrics (HRV, sleep, readiness)
    private func calculatePhysiologicalMetrics(
        recentWindow: Int,
        baselineWindow: Int
    ) async throws -> DimensionMetrics {
        try await dbQueue.read { db in
            let recentDate = Date().addingTimeInterval(-Double(recentWindow) * 86400)
            let baselineDate = Date().addingTimeInterval(-Double(baselineWindow) * 86400)
            let recentDateStr = ISO8601DateFormatter().string(from: recentDate)
            let baselineDateStr = ISO8601DateFormatter().string(from: baselineDate)

            // Recent HRV average
            let recentHRV = try Double.fetchOne(db, sql: """
                SELECT AVG(CAST(json_extract(metadata, '$.hrvMs') AS REAL))
                FROM atoms
                WHERE type = 'hrv_measurement'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Baseline HRV
            let baselineHRV = try Double.fetchOne(db, sql: """
                SELECT AVG(CAST(json_extract(metadata, '$.hrvMs') AS REAL))
                FROM atoms
                WHERE type = 'hrv_measurement'
                AND is_deleted = 0
                AND created_at >= ?
                AND created_at < ?
            """, arguments: [baselineDateStr, recentDateStr]) ?? 0

            // Sleep consistency
            let sleepConsistency = try Double.fetchOne(db, sql: """
                SELECT AVG(CAST(json_extract(metadata, '$.consistencyScore') AS REAL))
                FROM atoms
                WHERE type = 'sleep_consistency'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Readiness score
            let readinessScore = try Double.fetchOne(db, sql: """
                SELECT AVG(CAST(json_extract(metadata, '$.overallScore') AS REAL))
                FROM atoms
                WHERE type = 'readiness_score'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Weekly workouts
            let workouts = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'workout_session'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Days since last activity
            let lastActivity = try Date.fetchOne(db, sql: """
                SELECT MAX(created_at)
                FROM atoms
                WHERE type IN ('hrv_measurement', 'sleep_cycle', 'readiness_score', 'workout_session')
                AND is_deleted = 0
            """)
            let daysSinceActive = lastActivity.map {
                Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
            } ?? 999

            return DimensionMetrics(
                recentAverage: recentHRV,
                baselineAverage: baselineHRV,
                daysSinceActive: daysSinceActive,
                additionalMetrics: [
                    "sleepConsistency": sleepConsistency,
                    "readinessScore": readinessScore,
                    "weeklyWorkouts": Double(workouts)
                ]
            )
        }
    }

    // MARK: - Behavioral Metrics

    /// Calculate behavioral dimension metrics (routines, consistency)
    private func calculateBehavioralMetrics(
        recentWindow: Int,
        baselineWindow: Int
    ) async throws -> DimensionMetrics {
        try await dbQueue.read { db in
            let recentDate = Date().addingTimeInterval(-Double(recentWindow) * 86400)
            let baselineDate = Date().addingTimeInterval(-Double(baselineWindow) * 86400)
            let recentDateStr = ISO8601DateFormatter().string(from: recentDate)
            let baselineDateStr = ISO8601DateFormatter().string(from: baselineDate)

            // Recent deep work blocks
            let recentBlocks = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'deep_work_block'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Baseline blocks
            let baselineBlocks = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'deep_work_block'
                AND is_deleted = 0
                AND created_at >= ?
                AND created_at < ?
            """, arguments: [baselineDateStr, recentDateStr]) ?? 0

            // Distraction rate (distractions per deep work block)
            let distractions = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'distraction_event'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0
            let distractionRate = recentBlocks > 0 ? Double(distractions) / Double(recentBlocks) : 0

            // Task completion streak
            // (This is simplified - real implementation would track consecutive days)
            let taskStreak = try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT date(created_at))
                FROM atoms
                WHERE type = 'task'
                AND is_deleted = 0
                AND json_extract(metadata, '$.isCompleted') = 1
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Days since last activity
            let lastActivity = try Date.fetchOne(db, sql: """
                SELECT MAX(created_at)
                FROM atoms
                WHERE type IN ('deep_work_block', 'distraction_event')
                AND is_deleted = 0
            """)
            let daysSinceActive = lastActivity.map {
                Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
            } ?? 999

            let baselineDays = baselineWindow - recentWindow
            return DimensionMetrics(
                recentAverage: Double(recentBlocks) / Double(recentWindow) * 7, // Per week
                baselineAverage: baselineDays > 0 ? Double(baselineBlocks) / Double(baselineDays) * 7 : 0,
                daysSinceActive: daysSinceActive,
                additionalMetrics: [
                    "distractionRate": distractionRate,
                    "taskCompletionStreak": Double(taskStreak),
                    "weeklyDeepWorkBlocks": Double(recentBlocks)
                ]
            )
        }
    }

    // MARK: - Knowledge Metrics

    /// Calculate knowledge dimension metrics (connections, clusters)
    private func calculateKnowledgeMetrics(
        recentWindow: Int,
        baselineWindow: Int
    ) async throws -> DimensionMetrics {
        try await dbQueue.read { db in
            let recentDate = Date().addingTimeInterval(-Double(recentWindow) * 86400)
            let baselineDate = Date().addingTimeInterval(-Double(baselineWindow) * 86400)
            let recentDateStr = ISO8601DateFormatter().string(from: recentDate)
            let baselineDateStr = ISO8601DateFormatter().string(from: baselineDate)

            // Recent connections created
            let recentConnections = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'connection'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Baseline connections
            let baselineConnections = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'connection'
                AND is_deleted = 0
                AND created_at >= ?
                AND created_at < ?
            """, arguments: [baselineDateStr, recentDateStr]) ?? 0

            // Total connections
            let totalConnections = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'connection'
                AND is_deleted = 0
            """) ?? 0

            // Semantic clusters
            let semanticClusters = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'semantic_cluster'
                AND is_deleted = 0
            """) ?? 0

            // Research items
            let researchAdded = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'research'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Days since last activity
            let lastActivity = try Date.fetchOne(db, sql: """
                SELECT MAX(created_at)
                FROM atoms
                WHERE type IN ('connection', 'semantic_cluster', 'research', 'insight_extraction')
                AND is_deleted = 0
            """)
            let daysSinceActive = lastActivity.map {
                Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
            } ?? 999

            return DimensionMetrics(
                recentAverage: Double(recentConnections),
                baselineAverage: Double(baselineConnections),
                daysSinceActive: daysSinceActive,
                additionalMetrics: [
                    "totalConnections": Double(totalConnections),
                    "semanticClusters": Double(semanticClusters),
                    "researchAdded": Double(researchAdded),
                    "newConnections": Double(recentConnections)
                ]
            )
        }
    }

    // MARK: - Reflection Metrics

    /// Calculate reflection dimension metrics (journaling, insights)
    private func calculateReflectionMetrics(
        recentWindow: Int,
        baselineWindow: Int
    ) async throws -> DimensionMetrics {
        try await dbQueue.read { db in
            let recentDate = Date().addingTimeInterval(-Double(recentWindow) * 86400)
            let baselineDate = Date().addingTimeInterval(-Double(baselineWindow) * 86400)
            let recentDateStr = ISO8601DateFormatter().string(from: recentDate)
            let baselineDateStr = ISO8601DateFormatter().string(from: baselineDate)

            // Recent journal entries
            let recentJournals = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'journal_entry'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Baseline journals
            let baselineJournals = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'journal_entry'
                AND is_deleted = 0
                AND created_at >= ?
                AND created_at < ?
            """, arguments: [baselineDateStr, recentDateStr]) ?? 0

            // Average clarity score
            let avgClarity = try Double.fetchOne(db, sql: """
                SELECT AVG(CAST(json_extract(metadata, '$.overallClarity') AS REAL))
                FROM atoms
                WHERE type = 'clarity_score'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Insights generated
            let insights = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'journal_insight'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Emotional state logs
            let emotionalLogs = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM atoms
                WHERE type = 'emotional_state'
                AND is_deleted = 0
                AND created_at >= ?
            """, arguments: [recentDateStr]) ?? 0

            // Days since last activity
            let lastActivity = try Date.fetchOne(db, sql: """
                SELECT MAX(created_at)
                FROM atoms
                WHERE type IN ('journal_entry', 'journal_insight', 'emotional_state', 'clarity_score')
                AND is_deleted = 0
            """)
            let daysSinceActive = lastActivity.map {
                Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
            } ?? 999

            let baselineDays = baselineWindow - recentWindow
            return DimensionMetrics(
                recentAverage: Double(recentJournals) / Double(recentWindow) * 7, // Per week
                baselineAverage: baselineDays > 0 ? Double(baselineJournals) / Double(baselineDays) * 7 : 0,
                daysSinceActive: daysSinceActive,
                additionalMetrics: [
                    "journalDaysThisWeek": Double(recentJournals),
                    "avgClarityScore": avgClarity,
                    "insightsGenerated": Double(insights),
                    "emotionalStateLogs": Double(emotionalLogs)
                ]
            )
        }
    }

    // MARK: - Summary Metrics

    /// Get a summary of all dimension metrics
    func calculateAllDimensionMetrics() async throws -> [LevelDimension: DimensionMetrics] {
        var results: [LevelDimension: DimensionMetrics] = [:]

        for dimension in LevelDimension.allCases {
            results[dimension] = try await calculateMetrics(for: dimension)
        }

        return results
    }

    /// Calculate the composite level for a dimension based on all metrics
    func calculateDimensionLevel(
        for dimension: LevelDimension,
        metrics: DimensionMetrics
    ) -> Int {
        let config = DimensionConfigFactory.config(for: dimension)
        let primaryMetrics = DimensionConfigFactory.primaryMetrics(for: dimension)

        var totalLevel = 0
        var metricCount = 0

        for metric in primaryMetrics {
            if let value = metrics.additionalMetrics[metric] {
                let level = config.levelFor(metricValue: value, metric: metric)
                totalLevel += level
                metricCount += 1
            }
        }

        // Also consider the primary average metric
        if let recent = metrics.recentAverage {
            let level = config.levelFor(metricValue: recent, metric: primaryMetrics.first ?? "")
            totalLevel += level
            metricCount += 1
        }

        return metricCount > 0 ? totalLevel / metricCount : 1
    }
}

// MARK: - Snapshot Generation

extension DimensionMetricsCalculator {
    /// Generate a daily dimension snapshot atom
    func generateDailySnapshot() async throws -> DimensionSnapshotMetadata {
        let allMetrics = try await calculateAllDimensionMetrics()

        var states: [LevelDimension: DimensionState] = [:]

        for (dimension, metrics) in allMetrics {
            let level = calculateDimensionLevel(for: dimension, metrics: metrics)
            let xpToNext = XPCalculationEngine.xpToNextLevel(totalXP: level * 100) // Rough estimate

            // Calculate trend from recent vs baseline
            let trend: Trend
            if let recent = metrics.recentAverage, let baseline = metrics.baselineAverage, baseline > 0 {
                let ratio = recent / baseline
                if ratio > 1.1 {
                    trend = .improving
                } else if ratio < 0.9 {
                    trend = .declining
                } else {
                    trend = .stable
                }
            } else {
                trend = .stable
            }

            states[dimension] = DimensionState(
                level: level,
                xp: 0, // Would need to fetch from actual state
                xpToNextLevel: xpToNext,
                nelo: 1200, // Would need to fetch from actual state
                neloChange: 0,
                trend: trend
            )
        }

        // Calculate overall CI and NELO
        let overallCI = states.values.reduce(0) { $0 + $1.level } / states.count
        let overallNELO = states.values.reduce(0) { $0 + $1.nelo } / states.count

        return DimensionSnapshotMetadata(
            date: Date(),
            cognitive: states[.cognitive] ?? DimensionState.initial(for: .cognitive),
            creative: states[.creative] ?? DimensionState.initial(for: .creative),
            physiological: states[.physiological] ?? DimensionState.initial(for: .physiological),
            behavioral: states[.behavioral] ?? DimensionState.initial(for: .behavioral),
            knowledge: states[.knowledge] ?? DimensionState.initial(for: .knowledge),
            reflection: states[.reflection] ?? DimensionState.initial(for: .reflection),
            overallCI: overallCI,
            overallNELO: overallNELO
        )
    }
}

// MARK: - DimensionState Helper

extension DimensionState {
    static func initial(for dimension: LevelDimension) -> DimensionState {
        DimensionState(
            level: 1,
            xp: 0,
            xpToNextLevel: 100,
            nelo: 1200,
            neloChange: 0,
            trend: .stable
        )
    }
}
