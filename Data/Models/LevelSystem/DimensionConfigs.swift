// CosmoOS/Data/Models/LevelSystem/DimensionConfigs.swift
// Scientific thresholds for all 6 dimensions
// Based on MIT/Stanford productivity research, WHOOP data, and cognitive science

import Foundation

// MARK: - Dimension Configuration Protocol

/// Protocol for dimension-specific configurations
protocol DimensionConfig {
    static var dimension: LevelDimension { get }
    static var displayName: String { get }
    static var description: String { get }

    /// Get level for a given metric value
    static func levelFor(metricValue: Double, metric: String) -> Int

    /// Get target value for a given level and metric
    static func targetFor(level: Int, metric: String) -> Double
}

// MARK: - Cognitive Dimension

/// Cognitive dimension: Writing, deep work, task completion
/// Research: MIT productivity studies, Cal Newport's deep work research
struct CognitiveDimensionConfig: DimensionConfig {
    static let dimension = LevelDimension.cognitive
    static let displayName = "Cognitive Output"
    static let description = "Writing productivity, deep work, and task completion"

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Words per day thresholds
    // Based on professional writer output research
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let wordsPerDayThresholds: [(level: Int, value: Int)] = [
        (1, 100),       // Basic output
        (10, 400),      // Regular writer
        (20, 800),      // Consistent professional
        (30, 1200),     // High performer
        (40, 1500),     // Top 10%
        (50, 2000),     // Elite
        (60, 2500),     // Top 1%
        (70, 3500),     // Professional author pace
        (80, 5000),     // Stephen King territory
        (90, 7500),     // Extreme outlier
        (100, 10000),   // Maximum (humanly achievable)
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Deep work hours per day
    // Based on Cal Newport's research
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let deepWorkHoursThresholds: [(level: Int, value: Double)] = [
        (1, 0.5),       // Beginner
        (25, 2.0),      // Developing habit
        (50, 4.0),      // Newport's elite threshold
        (75, 5.0),      // Very high performer
        (100, 6.0),     // Theoretical max for sustained periods
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Tasks completed per week
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let tasksPerWeekThresholds: [(level: Int, value: Int)] = [
        (1, 5),         // Minimal
        (25, 20),       // Average worker
        (50, 40),       // High performer
        (75, 70),       // Very productive
        (100, 100),     // Elite execution
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Focus score average (0-100)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let focusScoreThresholds: [(level: Int, value: Int)] = [
        (1, 30),        // Easily distracted
        (25, 50),       // Average focus
        (50, 65),       // Good focus
        (75, 80),       // Excellent focus
        (100, 95),      // Near-perfect focus
    ]

    static func levelFor(metricValue: Double, metric: String) -> Int {
        switch metric {
        case "wordsPerDay":
            return interpolateLevel(value: metricValue, thresholds: wordsPerDayThresholds.map { ($0.level, Double($0.value)) })
        case "deepWorkHours":
            return interpolateLevel(value: metricValue, thresholds: deepWorkHoursThresholds)
        case "tasksPerWeek":
            return interpolateLevel(value: metricValue, thresholds: tasksPerWeekThresholds.map { ($0.level, Double($0.value)) })
        case "focusScore":
            return interpolateLevel(value: metricValue, thresholds: focusScoreThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 1
        }
    }

    static func targetFor(level: Int, metric: String) -> Double {
        switch metric {
        case "wordsPerDay":
            return interpolateTarget(level: level, thresholds: wordsPerDayThresholds.map { ($0.level, Double($0.value)) })
        case "deepWorkHours":
            return interpolateTarget(level: level, thresholds: deepWorkHoursThresholds)
        case "tasksPerWeek":
            return interpolateTarget(level: level, thresholds: tasksPerWeekThresholds.map { ($0.level, Double($0.value)) })
        case "focusScore":
            return interpolateTarget(level: level, thresholds: focusScoreThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 0
        }
    }
}

// MARK: - Creative Dimension

/// Creative dimension: Content performance, reach, virality
/// Research: Social media analytics, creator economy benchmarks
struct CreativeDimensionConfig: DimensionConfig {
    static let dimension = LevelDimension.creative
    static let displayName = "Creative Performance"
    static let description = "Content reach, engagement, and viral potential"

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Weekly reach thresholds (platform-agnostic)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let weeklyReachThresholds: [(level: Int, value: Int)] = [
        (1, 1_000),
        (10, 10_000),
        (20, 50_000),
        (30, 100_000),
        (40, 250_000),
        (50, 500_000),
        (60, 1_000_000),
        (70, 2_500_000),
        (80, 10_000_000),
        (90, 50_000_000),
        (100, 100_000_000),   // 100M+ weekly reach
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Viral posts per month (>10x normal engagement)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let viralPostsPerMonthThresholds: [(level: Int, value: Int)] = [
        (1, 0),
        (25, 1),
        (50, 3),
        (75, 8),
        (100, 20),
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Engagement rate percentage
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let engagementRateThresholds: [(level: Int, value: Double)] = [
        (1, 0.5),       // Low engagement
        (25, 1.5),      // Average
        (50, 3.0),      // Good
        (75, 5.0),      // Very good
        (100, 10.0),    // Exceptional
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Content pieces published per month
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let publishedPerMonthThresholds: [(level: Int, value: Int)] = [
        (1, 1),
        (25, 8),        // Twice a week
        (50, 20),       // Daily-ish
        (75, 40),       // Multiple per day
        (100, 100),     // Very high volume
    ]

    static func levelFor(metricValue: Double, metric: String) -> Int {
        switch metric {
        case "weeklyReach":
            return interpolateLevel(value: metricValue, thresholds: weeklyReachThresholds.map { ($0.level, Double($0.value)) })
        case "viralPosts":
            return interpolateLevel(value: metricValue, thresholds: viralPostsPerMonthThresholds.map { ($0.level, Double($0.value)) })
        case "engagementRate":
            return interpolateLevel(value: metricValue, thresholds: engagementRateThresholds)
        case "publishedPerMonth":
            return interpolateLevel(value: metricValue, thresholds: publishedPerMonthThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 1
        }
    }

    static func targetFor(level: Int, metric: String) -> Double {
        switch metric {
        case "weeklyReach":
            return interpolateTarget(level: level, thresholds: weeklyReachThresholds.map { ($0.level, Double($0.value)) })
        case "viralPosts":
            return interpolateTarget(level: level, thresholds: viralPostsPerMonthThresholds.map { ($0.level, Double($0.value)) })
        case "engagementRate":
            return interpolateTarget(level: level, thresholds: engagementRateThresholds)
        case "publishedPerMonth":
            return interpolateTarget(level: level, thresholds: publishedPerMonthThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 0
        }
    }
}

// MARK: - Physiological Dimension

/// Physiological dimension: HRV, sleep, recovery
/// Research: WHOOP data, Oura research, Stanford sleep studies
struct PhysiologicalDimensionConfig: DimensionConfig {
    static let dimension = LevelDimension.physiological
    static let displayName = "Physiological Health"
    static let description = "HRV, sleep quality, and physical recovery"

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // HRV baseline (SDNN in ms)
    // Based on WHOOP population data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let hrvBaselineThresholds: [(level: Int, value: Int)] = [
        (1, 25),        // Low HRV
        (25, 45),       // Below average
        (50, 65),       // Average
        (75, 85),       // Above average
        (100, 120),     // Elite HRV
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Sleep consistency score (0-100)
    // Based on sleep research
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let sleepConsistencyThresholds: [(level: Int, value: Int)] = [
        (1, 40),        // Inconsistent
        (25, 60),       // Developing routine
        (50, 75),       // Good consistency
        (75, 85),       // Very consistent
        (100, 95),      // Near-perfect
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Deep sleep percentage
    // Target: 15-25% is healthy
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let deepSleepPercentThresholds: [(level: Int, value: Int)] = [
        (1, 8),         // Low deep sleep
        (25, 12),       // Below average
        (50, 18),       // Average
        (75, 22),       // Good
        (100, 28),      // Excellent
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Weekly workout hours
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let weeklyWorkoutHoursThresholds: [(level: Int, value: Double)] = [
        (1, 0.5),       // Minimal activity
        (25, 2.5),      // Light exercise
        (50, 5.0),      // Regular exerciser
        (75, 8.0),      // Very active
        (100, 12.0),    // Athlete level
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Readiness score (0-100)
    // Based on WHOOP/Oura style scoring
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let readinessScoreThresholds: [(level: Int, value: Int)] = [
        (1, 33),        // Low readiness
        (25, 50),       // Below average
        (50, 67),       // Average
        (75, 80),       // Good
        (100, 90),      // Peak readiness
    ]

    static func levelFor(metricValue: Double, metric: String) -> Int {
        switch metric {
        case "hrvBaseline":
            return interpolateLevel(value: metricValue, thresholds: hrvBaselineThresholds.map { ($0.level, Double($0.value)) })
        case "sleepConsistency":
            return interpolateLevel(value: metricValue, thresholds: sleepConsistencyThresholds.map { ($0.level, Double($0.value)) })
        case "deepSleepPercent":
            return interpolateLevel(value: metricValue, thresholds: deepSleepPercentThresholds.map { ($0.level, Double($0.value)) })
        case "weeklyWorkoutHours":
            return interpolateLevel(value: metricValue, thresholds: weeklyWorkoutHoursThresholds)
        case "readinessScore":
            return interpolateLevel(value: metricValue, thresholds: readinessScoreThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 1
        }
    }

    static func targetFor(level: Int, metric: String) -> Double {
        switch metric {
        case "hrvBaseline":
            return interpolateTarget(level: level, thresholds: hrvBaselineThresholds.map { ($0.level, Double($0.value)) })
        case "sleepConsistency":
            return interpolateTarget(level: level, thresholds: sleepConsistencyThresholds.map { ($0.level, Double($0.value)) })
        case "deepSleepPercent":
            return interpolateTarget(level: level, thresholds: deepSleepPercentThresholds.map { ($0.level, Double($0.value)) })
        case "weeklyWorkoutHours":
            return interpolateTarget(level: level, thresholds: weeklyWorkoutHoursThresholds)
        case "readinessScore":
            return interpolateTarget(level: level, thresholds: readinessScoreThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 0
        }
    }
}

// MARK: - Behavioral Dimension

/// Behavioral dimension: Consistency, routine adherence, habits
/// Research: Habit formation studies, behavioral psychology
struct BehavioralDimensionConfig: DimensionConfig {
    static let dimension = LevelDimension.behavioral
    static let displayName = "Behavioral Consistency"
    static let description = "Routine adherence, habit strength, and consistency"

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Routine adherence percentage
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let routineAdherenceThresholds: [(level: Int, value: Int)] = [
        (1, 30),        // Low adherence
        (25, 50),       // Developing
        (50, 70),       // Good
        (75, 85),       // Very consistent
        (100, 95),      // Near-perfect
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Deep work blocks per week
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let deepWorkBlocksPerWeekThresholds: [(level: Int, value: Int)] = [
        (1, 2),         // Minimal
        (25, 7),        // Daily
        (50, 14),       // Twice daily
        (75, 21),       // Three per day
        (100, 30),      // Multiple focused blocks
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Task completion streak (days)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let taskStreakThresholds: [(level: Int, value: Int)] = [
        (1, 1),
        (25, 14),       // Two weeks
        (50, 30),       // Month
        (75, 90),       // Quarter
        (100, 365),     // Year
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Morning routine completion rate
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let morningRoutineRateThresholds: [(level: Int, value: Int)] = [
        (1, 20),
        (25, 50),
        (50, 70),
        (75, 85),
        (100, 95),
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Distraction-free deep work percentage
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let distractionFreeRateThresholds: [(level: Int, value: Int)] = [
        (1, 40),
        (25, 60),
        (50, 75),
        (75, 88),
        (100, 98),
    ]

    static func levelFor(metricValue: Double, metric: String) -> Int {
        switch metric {
        case "routineAdherence":
            return interpolateLevel(value: metricValue, thresholds: routineAdherenceThresholds.map { ($0.level, Double($0.value)) })
        case "deepWorkBlocksPerWeek":
            return interpolateLevel(value: metricValue, thresholds: deepWorkBlocksPerWeekThresholds.map { ($0.level, Double($0.value)) })
        case "taskStreak":
            return interpolateLevel(value: metricValue, thresholds: taskStreakThresholds.map { ($0.level, Double($0.value)) })
        case "morningRoutineRate":
            return interpolateLevel(value: metricValue, thresholds: morningRoutineRateThresholds.map { ($0.level, Double($0.value)) })
        case "distractionFreeRate":
            return interpolateLevel(value: metricValue, thresholds: distractionFreeRateThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 1
        }
    }

    static func targetFor(level: Int, metric: String) -> Double {
        switch metric {
        case "routineAdherence":
            return interpolateTarget(level: level, thresholds: routineAdherenceThresholds.map { ($0.level, Double($0.value)) })
        case "deepWorkBlocksPerWeek":
            return interpolateTarget(level: level, thresholds: deepWorkBlocksPerWeekThresholds.map { ($0.level, Double($0.value)) })
        case "taskStreak":
            return interpolateTarget(level: level, thresholds: taskStreakThresholds.map { ($0.level, Double($0.value)) })
        case "morningRoutineRate":
            return interpolateTarget(level: level, thresholds: morningRoutineRateThresholds.map { ($0.level, Double($0.value)) })
        case "distractionFreeRate":
            return interpolateTarget(level: level, thresholds: distractionFreeRateThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 0
        }
    }
}

// MARK: - Knowledge Dimension

/// Knowledge dimension: Research, connections, semantic density
/// Research: PKM (Personal Knowledge Management) metrics
struct KnowledgeDimensionConfig: DimensionConfig {
    static let dimension = LevelDimension.knowledge
    static let displayName = "Knowledge Graph"
    static let description = "Research quality, connection density, and semantic richness"

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Total connections (mental models)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let totalConnectionsThresholds: [(level: Int, value: Int)] = [
        (1, 5),
        (25, 50),
        (50, 200),
        (75, 500),
        (100, 1000),
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Semantic cluster count
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let semanticClustersThresholds: [(level: Int, value: Int)] = [
        (1, 1),
        (25, 10),
        (50, 30),
        (75, 75),
        (100, 200),
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Average links per idea
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let linksPerIdeaThresholds: [(level: Int, value: Double)] = [
        (1, 0.5),
        (25, 2.0),
        (50, 4.0),
        (75, 7.0),
        (100, 12.0),
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Research items
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let totalResearchThresholds: [(level: Int, value: Int)] = [
        (1, 10),
        (25, 100),
        (50, 400),
        (75, 1000),
        (100, 3000),
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Insight extraction rate (insights per 100 items)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let insightRateThresholds: [(level: Int, value: Int)] = [
        (1, 5),
        (25, 15),
        (50, 30),
        (75, 50),
        (100, 80),
    ]

    static func levelFor(metricValue: Double, metric: String) -> Int {
        switch metric {
        case "totalConnections":
            return interpolateLevel(value: metricValue, thresholds: totalConnectionsThresholds.map { ($0.level, Double($0.value)) })
        case "semanticClusters":
            return interpolateLevel(value: metricValue, thresholds: semanticClustersThresholds.map { ($0.level, Double($0.value)) })
        case "linksPerIdea":
            return interpolateLevel(value: metricValue, thresholds: linksPerIdeaThresholds)
        case "totalResearch":
            return interpolateLevel(value: metricValue, thresholds: totalResearchThresholds.map { ($0.level, Double($0.value)) })
        case "insightRate":
            return interpolateLevel(value: metricValue, thresholds: insightRateThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 1
        }
    }

    static func targetFor(level: Int, metric: String) -> Double {
        switch metric {
        case "totalConnections":
            return interpolateTarget(level: level, thresholds: totalConnectionsThresholds.map { ($0.level, Double($0.value)) })
        case "semanticClusters":
            return interpolateTarget(level: level, thresholds: semanticClustersThresholds.map { ($0.level, Double($0.value)) })
        case "linksPerIdea":
            return interpolateTarget(level: level, thresholds: linksPerIdeaThresholds)
        case "totalResearch":
            return interpolateTarget(level: level, thresholds: totalResearchThresholds.map { ($0.level, Double($0.value)) })
        case "insightRate":
            return interpolateTarget(level: level, thresholds: insightRateThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 0
        }
    }
}

// MARK: - Reflection Dimension

/// Reflection dimension: Journaling, insights, self-awareness
/// Research: Journaling studies, mindfulness research
struct ReflectionDimensionConfig: DimensionConfig {
    static let dimension = LevelDimension.reflection
    static let displayName = "Self-Reflection"
    static let description = "Journaling quality, insight generation, and self-awareness"

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Journal entries per week
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let journalEntriesPerWeekThresholds: [(level: Int, value: Int)] = [
        (1, 1),
        (25, 3),
        (50, 5),        // Daily-ish
        (75, 7),        // Daily
        (100, 14),      // Twice daily
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Average clarity score (0-100)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let avgClarityScoreThresholds: [(level: Int, value: Int)] = [
        (1, 40),
        (25, 55),
        (50, 70),
        (75, 82),
        (100, 92),
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Insights generated per week
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let insightsPerWeekThresholds: [(level: Int, value: Int)] = [
        (1, 1),
        (25, 5),
        (50, 12),
        (75, 25),
        (100, 50),
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Emotional state tracking rate (% of days)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let emotionalTrackingRateThresholds: [(level: Int, value: Int)] = [
        (1, 10),
        (25, 30),
        (50, 60),
        (75, 80),
        (100, 95),
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Reflection streak (days)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    static let reflectionStreakThresholds: [(level: Int, value: Int)] = [
        (1, 1),
        (25, 14),
        (50, 30),
        (75, 90),
        (100, 365),
    ]

    static func levelFor(metricValue: Double, metric: String) -> Int {
        switch metric {
        case "journalEntriesPerWeek":
            return interpolateLevel(value: metricValue, thresholds: journalEntriesPerWeekThresholds.map { ($0.level, Double($0.value)) })
        case "avgClarityScore":
            return interpolateLevel(value: metricValue, thresholds: avgClarityScoreThresholds.map { ($0.level, Double($0.value)) })
        case "insightsPerWeek":
            return interpolateLevel(value: metricValue, thresholds: insightsPerWeekThresholds.map { ($0.level, Double($0.value)) })
        case "emotionalTrackingRate":
            return interpolateLevel(value: metricValue, thresholds: emotionalTrackingRateThresholds.map { ($0.level, Double($0.value)) })
        case "reflectionStreak":
            return interpolateLevel(value: metricValue, thresholds: reflectionStreakThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 1
        }
    }

    static func targetFor(level: Int, metric: String) -> Double {
        switch metric {
        case "journalEntriesPerWeek":
            return interpolateTarget(level: level, thresholds: journalEntriesPerWeekThresholds.map { ($0.level, Double($0.value)) })
        case "avgClarityScore":
            return interpolateTarget(level: level, thresholds: avgClarityScoreThresholds.map { ($0.level, Double($0.value)) })
        case "insightsPerWeek":
            return interpolateTarget(level: level, thresholds: insightsPerWeekThresholds.map { ($0.level, Double($0.value)) })
        case "emotionalTrackingRate":
            return interpolateTarget(level: level, thresholds: emotionalTrackingRateThresholds.map { ($0.level, Double($0.value)) })
        case "reflectionStreak":
            return interpolateTarget(level: level, thresholds: reflectionStreakThresholds.map { ($0.level, Double($0.value)) })
        default:
            return 0
        }
    }
}

// MARK: - Interpolation Helpers

/// Interpolate level from value using thresholds
private func interpolateLevel(value: Double, thresholds: [(level: Int, value: Double)]) -> Int {
    // Below minimum
    if let first = thresholds.first, value < first.value {
        return 1
    }

    // Above maximum
    if let last = thresholds.last, value >= last.value {
        return last.level
    }

    // Find the bracket and interpolate
    for i in 0..<(thresholds.count - 1) {
        let lower = thresholds[i]
        let upper = thresholds[i + 1]

        if value >= lower.value && value < upper.value {
            let valueRange = upper.value - lower.value
            let levelRange = upper.level - lower.level
            let progress = (value - lower.value) / valueRange
            return lower.level + Int(progress * Double(levelRange))
        }
    }

    return 1
}

/// Interpolate target value from level using thresholds
private func interpolateTarget(level: Int, thresholds: [(level: Int, value: Double)]) -> Double {
    // Below minimum level
    if let first = thresholds.first, level <= first.level {
        return first.value
    }

    // Above maximum level
    if let last = thresholds.last, level >= last.level {
        return last.value
    }

    // Find the bracket and interpolate
    for i in 0..<(thresholds.count - 1) {
        let lower = thresholds[i]
        let upper = thresholds[i + 1]

        if level >= lower.level && level < upper.level {
            let levelRange = Double(upper.level - lower.level)
            let valueRange = upper.value - lower.value
            let progress = Double(level - lower.level) / levelRange
            return lower.value + progress * valueRange
        }
    }

    return 0
}

// MARK: - Dimension Config Factory

/// Factory for accessing dimension configs
enum DimensionConfigFactory {
    static func config(for dimension: LevelDimension) -> any DimensionConfig.Type {
        switch dimension {
        case .cognitive: return CognitiveDimensionConfig.self
        case .creative: return CreativeDimensionConfig.self
        case .physiological: return PhysiologicalDimensionConfig.self
        case .behavioral: return BehavioralDimensionConfig.self
        case .knowledge: return KnowledgeDimensionConfig.self
        case .reflection: return ReflectionDimensionConfig.self
        }
    }

    /// Get all primary metrics for a dimension
    static func primaryMetrics(for dimension: LevelDimension) -> [String] {
        switch dimension {
        case .cognitive:
            return ["wordsPerDay", "deepWorkHours", "tasksPerWeek", "focusScore"]
        case .creative:
            return ["weeklyReach", "engagementRate", "publishedPerMonth", "viralPosts"]
        case .physiological:
            return ["hrvBaseline", "sleepConsistency", "readinessScore", "weeklyWorkoutHours"]
        case .behavioral:
            return ["routineAdherence", "deepWorkBlocksPerWeek", "taskStreak", "distractionFreeRate"]
        case .knowledge:
            return ["totalConnections", "linksPerIdea", "semanticClusters", "insightRate"]
        case .reflection:
            return ["journalEntriesPerWeek", "avgClarityScore", "insightsPerWeek", "reflectionStreak"]
        }
    }
}
