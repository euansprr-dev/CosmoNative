import Foundation
import GRDB

// MARK: - Badge Progress

/// Tracks progress toward a specific badge
public struct BadgeProgress: Codable, Sendable {
    public let badgeId: String
    public let badgeName: String
    public let tier: BadgeTier
    public let category: BadgeCategory
    public let requirements: [RequirementProgress]
    public let requireAll: Bool
    public let isComplete: Bool
    public let isSecret: Bool
    public let prerequisitesMet: Bool

    public var overallProgress: Double {
        guard !requirements.isEmpty else { return 0 }

        if requireAll {
            // AND logic: minimum of all requirements
            return requirements.map { $0.progress }.min() ?? 0
        } else {
            // OR logic: maximum of all requirements
            return requirements.map { $0.progress }.max() ?? 0
        }
    }

    public init(
        badgeId: String,
        badgeName: String,
        tier: BadgeTier,
        category: BadgeCategory,
        requirements: [RequirementProgress],
        requireAll: Bool,
        isComplete: Bool,
        isSecret: Bool,
        prerequisitesMet: Bool
    ) {
        self.badgeId = badgeId
        self.badgeName = badgeName
        self.tier = tier
        self.category = category
        self.requirements = requirements
        self.requireAll = requireAll
        self.isComplete = isComplete
        self.isSecret = isSecret
        self.prerequisitesMet = prerequisitesMet
    }
}

/// Progress toward a single requirement
public struct RequirementProgress: Codable, Sendable {
    public let type: BadgeRequirementType
    public let currentValue: Double
    public let targetValue: Double
    public let description: String

    public var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(1.0, currentValue / targetValue)
    }

    public var isComplete: Bool {
        currentValue >= targetValue
    }

    public init(
        type: BadgeRequirementType,
        currentValue: Double,
        targetValue: Double,
        description: String
    ) {
        self.type = type
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.description = description
    }
}

// MARK: - Badge Evaluation Context

/// Context for evaluating badge requirements
public struct BadgeEvaluationContext: Sendable {
    // Atom counts by type
    public let atomCounts: [String: Int]

    // Streak data
    public let currentStreaks: [BadgeCategory: Int]
    public let maxStreaks: [BadgeCategory: Int]
    public let overallStreak: Int

    // NELO ratings by dimension
    public let neloRatings: [BadgeCategory: Int]

    // CI levels by dimension
    public let ciLevels: [BadgeCategory: Int]
    public let overallLevel: Int

    // Time metrics
    public let totalMinutes: [BadgeCategory: Int]
    public let uniqueDays: [BadgeCategory: Int]
    public let overallUniqueDays: Int

    // Quality metrics
    public let averageQuality: [String: Double]
    public let perfectScores: Int
    public let consistencyRates: [BadgeCategory: Double]

    // Earned badges
    public let earnedBadgeIds: Set<String>

    // Dimension counts for meta badges
    public let dimensionsWithBadges: Int
    public let dimensionsAtNelo: [Int: Int]  // NELO threshold -> count of dimensions meeting it

    public init(
        atomCounts: [String: Int] = [:],
        currentStreaks: [BadgeCategory: Int] = [:],
        maxStreaks: [BadgeCategory: Int] = [:],
        overallStreak: Int = 0,
        neloRatings: [BadgeCategory: Int] = [:],
        ciLevels: [BadgeCategory: Int] = [:],
        overallLevel: Int = 1,
        totalMinutes: [BadgeCategory: Int] = [:],
        uniqueDays: [BadgeCategory: Int] = [:],
        overallUniqueDays: Int = 0,
        averageQuality: [String: Double] = [:],
        perfectScores: Int = 0,
        consistencyRates: [BadgeCategory: Double] = [:],
        earnedBadgeIds: Set<String> = [],
        dimensionsWithBadges: Int = 0,
        dimensionsAtNelo: [Int: Int] = [:]
    ) {
        self.atomCounts = atomCounts
        self.currentStreaks = currentStreaks
        self.maxStreaks = maxStreaks
        self.overallStreak = overallStreak
        self.neloRatings = neloRatings
        self.ciLevels = ciLevels
        self.overallLevel = overallLevel
        self.totalMinutes = totalMinutes
        self.uniqueDays = uniqueDays
        self.overallUniqueDays = overallUniqueDays
        self.averageQuality = averageQuality
        self.perfectScores = perfectScores
        self.consistencyRates = consistencyRates
        self.earnedBadgeIds = earnedBadgeIds
        self.dimensionsWithBadges = dimensionsWithBadges
        self.dimensionsAtNelo = dimensionsAtNelo
    }
}

// MARK: - Badge Progress Tracker

/// Tracks and evaluates badge progress
/// Uses atoms as source of truth, with caching for performance
public final class BadgeProgressTracker: Sendable {

    private let badgeSystem: BadgeDefinitionSystem

    public init(badgeSystem: BadgeDefinitionSystem = .shared) {
        self.badgeSystem = badgeSystem
    }

    // MARK: - Progress Calculation

    /// Calculate progress for all badges
    public func calculateAllProgress(context: BadgeEvaluationContext) -> [BadgeProgress] {
        badgeSystem.allBadges.map { badge in
            calculateProgress(for: badge, context: context)
        }
    }

    /// Calculate progress for a specific badge
    public func calculateProgress(for badge: BadgeDefinition, context: BadgeEvaluationContext) -> BadgeProgress {
        // Check if already earned
        let alreadyEarned = context.earnedBadgeIds.contains(badge.id)

        // Check prerequisites
        let prerequisitesMet = badge.prerequisiteBadges.allSatisfy { prereqId in
            context.earnedBadgeIds.contains(prereqId)
        }

        // Check time constraints
        let now = Date()
        let timeValid = (badge.unlocksAt == nil || badge.unlocksAt! <= now) &&
                       (badge.expiresAt == nil || badge.expiresAt! > now)

        // Calculate requirement progress
        let requirementProgresses = badge.requirements.map { req in
            evaluateRequirement(req, context: context)
        }

        // Determine completion
        let isComplete: Bool
        if alreadyEarned {
            isComplete = true
        } else if !prerequisitesMet || !timeValid {
            isComplete = false
        } else if badge.requireAll {
            isComplete = requirementProgresses.allSatisfy { $0.isComplete }
        } else {
            isComplete = requirementProgresses.contains { $0.isComplete }
        }

        return BadgeProgress(
            badgeId: badge.id,
            badgeName: badge.name,
            tier: badge.tier,
            category: badge.category,
            requirements: requirementProgresses,
            requireAll: badge.requireAll,
            isComplete: isComplete,
            isSecret: badge.isSecret && !alreadyEarned,
            prerequisitesMet: prerequisitesMet
        )
    }

    /// Evaluate a single requirement against context
    private func evaluateRequirement(_ req: BadgeRequirement, context: BadgeEvaluationContext) -> RequirementProgress {
        let currentValue: Double
        let description: String

        switch req.type {
        case .atomCount:
            let key = req.atomType ?? "total"
            currentValue = Double(context.atomCounts[key] ?? 0)
            description = "Atoms: \(Int(currentValue))/\(Int(req.threshold))"

        case .actionCount:
            let key = req.atomType ?? "actions"
            currentValue = Double(context.atomCounts[key] ?? 0)
            description = "Actions: \(Int(currentValue))/\(Int(req.threshold))"

        case .uniqueDays:
            if let dimension = req.dimension {
                currentValue = Double(context.uniqueDays[dimension] ?? 0)
                description = "Days active in \(dimension.rawValue): \(Int(currentValue))/\(Int(req.threshold))"
            } else {
                currentValue = Double(context.overallUniqueDays)
                description = "Total days active: \(Int(currentValue))/\(Int(req.threshold))"
            }

        case .currentStreak:
            if let dimension = req.dimension {
                currentValue = Double(context.currentStreaks[dimension] ?? 0)
                description = "\(dimension.rawValue) streak: \(Int(currentValue))/\(Int(req.threshold)) days"
            } else {
                currentValue = Double(context.overallStreak)
                description = "Overall streak: \(Int(currentValue))/\(Int(req.threshold)) days"
            }

        case .maxStreak:
            if let dimension = req.dimension {
                currentValue = Double(context.maxStreaks[dimension] ?? 0)
                description = "Best \(dimension.rawValue) streak: \(Int(currentValue))/\(Int(req.threshold)) days"
            } else {
                let maxAny = context.maxStreaks.values.max() ?? 0
                currentValue = Double(maxAny)
                description = "Best streak: \(Int(currentValue))/\(Int(req.threshold)) days"
            }

        case .streakMilestone:
            if let dimension = req.dimension {
                currentValue = Double(context.maxStreaks[dimension] ?? 0)
            } else {
                currentValue = Double(context.maxStreaks.values.max() ?? 0)
            }
            description = "Streak milestone: \(Int(currentValue))/\(Int(req.threshold)) days"

        case .neloRating:
            if let dimension = req.dimension {
                currentValue = Double(context.neloRatings[dimension] ?? 1000)
                description = "\(dimension.rawValue) NELO: \(Int(currentValue))/\(Int(req.threshold))"
            } else {
                let avgNelo = context.neloRatings.values.reduce(0, +) / max(1, context.neloRatings.count)
                currentValue = Double(avgNelo)
                description = "Average NELO: \(Int(currentValue))/\(Int(req.threshold))"
            }

        case .ciLevel:
            if let dimension = req.dimension {
                currentValue = Double(context.ciLevels[dimension] ?? 1)
                description = "\(dimension.rawValue) level: \(Int(currentValue))/\(Int(req.threshold))"
            } else {
                currentValue = Double(context.overallLevel)
                description = "Cosmo level: \(Int(currentValue))/\(Int(req.threshold))"
            }

        case .overallLevel:
            currentValue = Double(context.overallLevel)
            description = "Cosmo level: \(Int(currentValue))/\(Int(req.threshold))"

        case .averageQuality:
            let key = req.metadata["metric"] ?? "overall"
            currentValue = context.averageQuality[key] ?? 0
            description = "Quality: \(String(format: "%.1f%%", currentValue * 100))/\(String(format: "%.1f%%", req.threshold * 100))"

        case .perfectScore:
            currentValue = Double(context.perfectScores)
            description = "Perfect scores: \(Int(currentValue))/\(Int(req.threshold))"

        case .consistencyRate:
            if let dimension = req.dimension {
                currentValue = context.consistencyRates[dimension] ?? 0
                description = "\(dimension.rawValue) consistency: \(String(format: "%.1f%%", currentValue * 100))/\(String(format: "%.1f%%", req.threshold * 100))"
            } else {
                let avgConsistency = context.consistencyRates.values.reduce(0, +) / Double(max(1, context.consistencyRates.count))
                currentValue = avgConsistency
                description = "Overall consistency: \(String(format: "%.1f%%", currentValue * 100))/\(String(format: "%.1f%%", req.threshold * 100))"
            }

        case .totalMinutes:
            if let dimension = req.dimension {
                currentValue = Double(context.totalMinutes[dimension] ?? 0)
                description = "\(dimension.rawValue) time: \(Int(currentValue))/\(Int(req.threshold)) min"
            } else {
                currentValue = Double(context.totalMinutes.values.reduce(0, +))
                description = "Total time: \(Int(currentValue))/\(Int(req.threshold)) min"
            }

        case .sessionMinutes:
            // Would need session data
            currentValue = 0
            description = "Session length: 0/\(Int(req.threshold)) min"

        case .dailyMinutes:
            // Would need daily max data
            currentValue = 0
            description = "Daily max: 0/\(Int(req.threshold)) min"

        case .multiDimension:
            // Parse metadata for multi-dimension requirements
            let metaType = req.metadata["type"] ?? ""
            switch metaType {
            case "badge_count":
                currentValue = Double(context.dimensionsWithBadges)
                description = "Dimensions with badges: \(Int(currentValue))/\(Int(req.threshold))"

            case "nelo_min":
                let minNelo = Int(req.metadata["min"] ?? "1000") ?? 1000
                currentValue = Double(context.dimensionsAtNelo[minNelo] ?? 0)
                description = "Dimensions at \(minNelo) NELO: \(Int(currentValue))/\(Int(req.threshold))"

            default:
                currentValue = 0
                description = "Multi-dimension requirement"
            }

        case .conditional:
            // Complex conditional requirements would be evaluated separately
            currentValue = 0
            description = "Conditional requirement"
        }

        return RequirementProgress(
            type: req.type,
            currentValue: currentValue,
            targetValue: req.threshold,
            description: description
        )
    }

    // MARK: - Badge Checking

    /// Check for newly earned badges and return them
    public func checkForNewBadges(context: BadgeEvaluationContext) -> [BadgeDefinition] {
        badgeSystem.allBadges.compactMap { badge in
            guard !context.earnedBadgeIds.contains(badge.id) else { return nil }

            let progress = calculateProgress(for: badge, context: context)
            return progress.isComplete ? badge : nil
        }
    }

    /// Get badges close to being earned (>75% progress)
    public func nearlyEarnedBadges(context: BadgeEvaluationContext, threshold: Double = 0.75) -> [BadgeProgress] {
        calculateAllProgress(context: context).filter { progress in
            !progress.isComplete &&
            progress.prerequisitesMet &&
            progress.overallProgress >= threshold
        }.sorted { $0.overallProgress > $1.overallProgress }
    }

    /// Get next achievable badges (prerequisites met, not yet started significantly)
    public func nextAchievableBadges(context: BadgeEvaluationContext, limit: Int = 5) -> [BadgeProgress] {
        calculateAllProgress(context: context)
            .filter { !$0.isComplete && $0.prerequisitesMet && !$0.isSecret }
            .sorted { lhs, rhs in
                // Prioritize badges with some progress over those with none
                if lhs.overallProgress > 0 && rhs.overallProgress == 0 { return true }
                if lhs.overallProgress == 0 && rhs.overallProgress > 0 { return false }
                // Then by tier (lower tiers first for achievability)
                if lhs.tier != rhs.tier { return lhs.tier.rawValue < rhs.tier.rawValue }
                // Then by progress
                return lhs.overallProgress > rhs.overallProgress
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Context Building from Database

    /// Build evaluation context from database
    public func buildContext(db: Database, levelState: CosmoLevelState) throws -> BadgeEvaluationContext {
        // Get atom counts by type
        let atomCounts = try buildAtomCounts(db: db)

        // Get streak data
        let (currentStreaks, maxStreaks, overallStreak) = try buildStreakData(db: db)

        // Get earned badges
        let earnedBadgeIds = try buildEarnedBadges(db: db)

        // Get unique days
        let (uniqueDays, overallUniqueDays) = try buildUniqueDays(db: db)

        // Get total minutes by dimension
        let totalMinutes = try buildTotalMinutes(db: db)

        // Build NELO and CI from level state
        let neloRatings: [BadgeCategory: Int] = [
            .cognitive: levelState.cognitiveNELO,
            .creative: levelState.creativeNELO,
            .physiological: levelState.physiologicalNELO,
            .behavioral: levelState.behavioralNELO,
            .knowledge: levelState.knowledgeNELO,
            .reflection: levelState.reflectionNELO
        ]

        let ciLevels: [BadgeCategory: Int] = [
            .cognitive: levelState.cognitiveLevel,
            .creative: levelState.creativeLevel,
            .physiological: levelState.physiologicalLevel,
            .behavioral: levelState.behavioralLevel,
            .knowledge: levelState.knowledgeLevel,
            .reflection: levelState.reflectionLevel
        ]

        // Calculate dimensions at NELO thresholds
        let dimensionsAtNelo = calculateDimensionsAtNelo(neloRatings)

        // Calculate dimensions with badges
        let dimensionsWithBadges = calculateDimensionsWithBadges(earnedBadgeIds: earnedBadgeIds)

        return BadgeEvaluationContext(
            atomCounts: atomCounts,
            currentStreaks: currentStreaks,
            maxStreaks: maxStreaks,
            overallStreak: overallStreak,
            neloRatings: neloRatings,
            ciLevels: ciLevels,
            overallLevel: levelState.cosmoIndex,
            totalMinutes: totalMinutes,
            uniqueDays: uniqueDays,
            overallUniqueDays: overallUniqueDays,
            earnedBadgeIds: earnedBadgeIds,
            dimensionsWithBadges: dimensionsWithBadges,
            dimensionsAtNelo: dimensionsAtNelo
        )
    }

    private func buildAtomCounts(db: Database) throws -> [String: Int] {
        var counts: [String: Int] = [:]

        // Count by atom type
        let typeCountsSQL = """
            SELECT type, COUNT(*) as count
            FROM atoms
            WHERE isDeleted = 0
            GROUP BY type
        """

        let typeCounts = try Row.fetchAll(db, sql: typeCountsSQL)
        for row in typeCounts {
            if let type = row["type"] as? String, let count = row["count"] as? Int {
                counts[type] = count
            }
        }

        // Word count aggregate
        let wordCountSQL = """
            SELECT COALESCE(SUM(json_extract(metadata, '$.wordCount')), 0) as total
            FROM atoms
            WHERE type IN ('journal_entry', 'note', 'ideaNote', 'projectNote')
            AND isDeleted = 0
        """

        if let total = try Int.fetchOne(db, sql: wordCountSQL) {
            counts["word_count"] = total
        }

        return counts
    }

    private func buildStreakData(db: Database) throws -> (current: [BadgeCategory: Int], max: [BadgeCategory: Int], overall: Int) {
        var currentStreaks: [BadgeCategory: Int] = [:]
        var maxStreaks: [BadgeCategory: Int] = [:]

        // Get from streak cache
        let sql = """
            SELECT dimension, currentStreak, longestStreak
            FROM cosmo_streak_cache
        """

        let rows = try Row.fetchAll(db, sql: sql)
        for row in rows {
            if let dimStr = row["dimension"] as? String,
               let dimension = BadgeCategory(rawValue: dimStr),
               let current = row["currentStreak"] as? Int,
               let longest = row["longestStreak"] as? Int {
                currentStreaks[dimension] = current
                maxStreaks[dimension] = longest
            }
        }

        let overallStreak = currentStreaks.values.min() ?? 0

        return (currentStreaks, maxStreaks, overallStreak)
    }

    private func buildEarnedBadges(db: Database) throws -> Set<String> {
        let sql = """
            SELECT json_extract(metadata, '$.badgeId') as badgeId
            FROM atoms
            WHERE type = 'badge'
            AND isDeleted = 0
        """

        let badgeIds = try String.fetchAll(db, sql: sql)
        return Set(badgeIds)
    }

    private func buildUniqueDays(db: Database) throws -> (byDimension: [BadgeCategory: Int], overall: Int) {
        var uniqueDays: [BadgeCategory: Int] = [:]

        // This would need dimension mapping from atom types
        // For now, use a simplified approach
        let dimensionMapping: [String: BadgeCategory] = [
            "focus_session": .cognitive,
            "journal_entry": .reflection,
            "workout": .physiological,
            "task": .behavioral,
            "idea": .creative,
            "note": .knowledge
        ]

        for (atomType, dimension) in dimensionMapping {
            let sql = """
                SELECT COUNT(DISTINCT date(createdAt)) as days
                FROM atoms
                WHERE type = ?
                AND isDeleted = 0
            """

            if let days = try Int.fetchOne(db, sql: sql, arguments: [atomType]) {
                uniqueDays[dimension] = max(uniqueDays[dimension] ?? 0, days)
            }
        }

        // Overall unique days
        let overallSQL = """
            SELECT COUNT(DISTINCT date(createdAt)) as days
            FROM atoms
            WHERE isDeleted = 0
        """

        let overallUniqueDays = try Int.fetchOne(db, sql: overallSQL) ?? 0

        return (uniqueDays, overallUniqueDays)
    }

    private func buildTotalMinutes(db: Database) throws -> [BadgeCategory: Int] {
        var totalMinutes: [BadgeCategory: Int] = [:]

        // Get focus session minutes for cognitive
        let cognitiveSQL = """
            SELECT COALESCE(SUM(json_extract(metadata, '$.durationMinutes')), 0) as total
            FROM atoms
            WHERE type = 'focus_session'
            AND isDeleted = 0
        """

        if let total = try Int.fetchOne(db, sql: cognitiveSQL) {
            totalMinutes[.cognitive] = total
        }

        // Get workout minutes for physiological
        let physioSQL = """
            SELECT COALESCE(SUM(json_extract(metadata, '$.durationMinutes')), 0) as total
            FROM atoms
            WHERE type = 'workout'
            AND isDeleted = 0
        """

        if let total = try Int.fetchOne(db, sql: physioSQL) {
            totalMinutes[.physiological] = total
        }

        return totalMinutes
    }

    private func calculateDimensionsAtNelo(_ neloRatings: [BadgeCategory: Int]) -> [Int: Int] {
        let thresholds = [1200, 1400, 1600, 1800, 2000, 2200, 2400]
        var result: [Int: Int] = [:]

        for threshold in thresholds {
            result[threshold] = neloRatings.values.filter { $0 >= threshold }.count
        }

        return result
    }

    private func calculateDimensionsWithBadges(earnedBadgeIds: Set<String>) -> Int {
        let dimensions: Set<BadgeCategory> = [.cognitive, .creative, .physiological, .behavioral, .knowledge, .reflection]
        var dimensionsWithBadges = 0

        for dimension in dimensions {
            let hasBadge = badgeSystem.badges(in: dimension).contains { badge in
                earnedBadgeIds.contains(badge.id)
            }
            if hasBadge {
                dimensionsWithBadges += 1
            }
        }

        return dimensionsWithBadges
    }

    // MARK: - Badge Award Creation

    /// Create a badge atom for an earned badge
    public func createBadgeAtom(
        badge: BadgeDefinition,
        triggeringActionId: String?,
        progressSnapshot: [String: Double]
    ) -> Atom {
        let metadata = BadgeEarnedMetadata(
            badgeId: badge.id,
            badgeName: badge.name,
            tier: badge.tier,
            category: badge.category,
            earnedAt: Date(),
            xpAwarded: badge.xpReward,
            neloBonus: badge.tier.neloBonus,
            triggeringActionId: triggeringActionId,
            progressSnapshot: progressSnapshot
        )

        let metadataJSON: String
        if let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        return Atom.new(
            type: .badge,
            title: badge.name,
            body: badge.description,
            metadata: metadataJSON
        )
    }
}

// MARK: - Badge Notification

/// Notification data for badge earned events
public struct BadgeEarnedNotification: Sendable {
    public let badge: BadgeDefinition
    public let atom: Atom
    public let xpAwarded: Int
    public let neloBonus: Int
    public let newBadgesUnlocked: [String]  // Badge IDs now available due to prerequisites

    public init(
        badge: BadgeDefinition,
        atom: Atom,
        xpAwarded: Int,
        neloBonus: Int,
        newBadgesUnlocked: [String]
    ) {
        self.badge = badge
        self.atom = atom
        self.xpAwarded = xpAwarded
        self.neloBonus = neloBonus
        self.newBadgesUnlocked = newBadgesUnlocked
    }
}
