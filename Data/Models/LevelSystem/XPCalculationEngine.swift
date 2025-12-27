// CosmoOS/Data/Models/LevelSystem/XPCalculationEngine.swift
// XP Calculation Engine - handles all XP awards, level calculations, and streak bonuses
// Based on cognitive science research and gamification best practices

import Foundation

// MARK: - XP Calculation Engine

/// Engine for calculating XP awards, level requirements, and streak multipliers
/// All values are research-based and optimized for knowledge worker engagement
public final class XPCalculationEngine {

    // MARK: - Initialization

    public init() {}

    // MARK: - Base XP Values

    /// Base XP values for all trackable actions (before multipliers)
    enum BaseXP {
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // COGNITIVE DIMENSION
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        /// XP per 100 words written
        static let wordsWritten = 1

        /// XP for completing a task
        static let taskCompleted = 10

        /// XP per hour of deep work
        static let deepWorkHour = 25

        /// XP for creating a content piece
        static let contentPieceCreated = 50

        /// XP for completing a writing session
        static let writingSessionCompleted = 15

        /// XP per focus score point above 80
        static let focusScoreBonus = 2

        /// XP for uninterrupted deep work block
        static let uninterruptedDeepWork = 20

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // CREATIVE DIMENSION
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        /// XP for publishing content
        static let contentPublished = 20

        /// XP per 10,000 impressions
        static let impressionsPer10K = 5

        /// XP for a viral post (>10x normal engagement)
        static let viralPost = 500

        /// XP per 1% engagement rate above baseline
        static let engagementRateBonusPer1Pct = 10

        /// XP for content entering new phase
        static let contentPhaseTransition = 15

        /// XP for completing content draft
        static let contentDraftCompleted = 25

        /// XP for ghostwriting client delivery
        static let clientContentDelivered = 40

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // PHYSIOLOGICAL DIMENSION
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        /// XP for logging HRV measurement
        static let hrvMeasurement = 5

        /// XP for logging sleep
        static let sleepLogged = 10

        /// XP per day of sleep consistency streak
        static let sleepConsistencyBonus = 15

        /// XP for completing a workout
        static let workoutCompleted = 20

        /// XP per 5ms HRV improvement vs baseline
        static let hrvImprovement = 25

        /// XP for achieving optimal readiness score (>80)
        static let optimalReadiness = 30

        /// XP for completing breathing session
        static let breathingSession = 10

        /// XP for hitting sleep target duration
        static let sleepTargetHit = 15

        /// XP for optimal deep sleep percentage (>20%)
        static let optimalDeepSleep = 20

        /// XP for logging meal
        static let mealLogged = 5

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // BEHAVIORAL DIMENSION
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        /// XP for completing a deep work block
        static let deepWorkBlockCompleted = 15

        /// XP per routine block followed
        static let routineAdherence = 10

        /// XP per day of task completion streak
        static let taskCompletionStreak = 5

        /// XP for completing morning routine
        static let morningRoutineComplete = 30

        /// XP for completing evening routine
        static let eveningRoutineComplete = 20

        /// XP for maintaining schedule adherence (>80%)
        static let scheduleAdherenceBonus = 25

        /// XP for avoiding distractions during focus time
        static let distractionFreeBonus = 15

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // KNOWLEDGE DIMENSION
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        /// XP for adding research
        static let researchAdded = 10

        /// XP for creating a connection (mental model)
        static let connectionCreated = 25

        /// XP for discovering semantic link
        static let semanticLinkDiscovered = 15

        /// XP for AI-extracted insight
        static let insightExtracted = 20

        /// XP for confirming auto-link suggestion
        static let autoLinkConfirmed = 10

        /// XP for semantic cluster formed
        static let semanticClusterFormed = 30

        /// XP for knowledge graph density improvement
        static let graphDensityBonus = 5

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // REFLECTION DIMENSION
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        /// XP for journal entry
        static let journalEntry = 15

        /// XP for journal insight generated
        static let journalInsightGenerated = 10

        /// XP per clarity score point above 70
        static let clarityScoreBonus = 1

        /// XP for emotional awareness log
        static let emotionalAwarenessLog = 5

        /// XP for completing reflection session
        static let reflectionSessionCompleted = 20

        /// XP for morning intention set
        static let morningIntention = 15

        /// XP for evening review completed
        static let eveningReview = 15

        /// XP for weekly reflection
        static let weeklyReflection = 50

        /// XP for monthly review
        static let monthlyReview = 100
    }

    // MARK: - Level Calculations

    /// Calculate XP required to reach a specific level
    /// Uses an exponential curve: L1=100, L10=1000, L25=6250, L50=25000, L100=100000
    static func xpRequiredForLevel(_ level: Int) -> Int {
        guard level > 0 else { return 0 }
        // Formula: 100 * level^1.5
        return Int(100 * pow(Double(level), 1.5))
    }

    /// Calculate level from total XP
    static func levelForXP(_ xp: Int) -> Int {
        guard xp > 0 else { return 1 }
        // Inverse of xpRequiredForLevel: level = (xp/100)^(2/3)
        let level = Int(pow(Double(xp) / 100.0, 2.0 / 3.0))
        return max(1, level)
    }

    /// Calculate progress percentage within current level
    static func progressInLevel(totalXP: Int) -> Double {
        let currentLevel = levelForXP(totalXP)
        let currentLevelXP = xpRequiredForLevel(currentLevel)
        let nextLevelXP = xpRequiredForLevel(currentLevel + 1)
        let xpInLevel = totalXP - currentLevelXP
        let xpForLevel = nextLevelXP - currentLevelXP
        guard xpForLevel > 0 else { return 0 }
        return Double(xpInLevel) / Double(xpForLevel)
    }

    /// Calculate XP remaining to reach next level
    static func xpToNextLevel(totalXP: Int) -> Int {
        let currentLevel = levelForXP(totalXP)
        let nextLevelXP = xpRequiredForLevel(currentLevel + 1)
        return max(0, nextLevelXP - totalXP)
    }

    // MARK: - XP Award Calculation

    /// Calculate XP award with all applicable multipliers
    static func calculateXP(
        baseAmount: Int,
        streakDays: Int = 0,
        dimension: LevelDimension,
        bonusMultipliers: [Double] = []
    ) -> XPAward {
        var multiplier = 1.0

        // Apply streak multiplier
        let streakMultiplier = StreakMultipliers.forStreak(streakDays)
        multiplier *= streakMultiplier

        // Apply dimension-specific bonuses (future: time-of-day, etc.)
        let dimensionMultiplier = dimensionBonus(for: dimension)
        multiplier *= dimensionMultiplier

        // Apply any bonus multipliers (events, achievements, etc.)
        for bonus in bonusMultipliers {
            multiplier *= bonus
        }

        let finalAmount = Int(Double(baseAmount) * multiplier)

        return XPAward(
            baseAmount: baseAmount,
            finalAmount: finalAmount,
            multiplier: multiplier,
            streakMultiplier: streakMultiplier,
            dimension: dimension
        )
    }

    /// Get dimension-specific bonus (placeholder for future features)
    private static func dimensionBonus(for dimension: LevelDimension) -> Double {
        // Could be influenced by:
        // - Time of day (creative peak hours)
        // - Day of week (weekend bonuses)
        // - Special events
        // - User preferences
        return 1.0
    }

    // MARK: - Action XP Lookups

    /// Get XP for a specific action type
    static func xpForAction(_ action: XPAction) -> Int {
        switch action {
        // Cognitive
        case .wordsWritten(let count):
            return (count / 100) * BaseXP.wordsWritten
        case .taskCompleted:
            return BaseXP.taskCompleted
        case .deepWorkHour(let hours):
            return Int(Double(BaseXP.deepWorkHour) * hours)
        case .contentPieceCreated:
            return BaseXP.contentPieceCreated
        case .writingSessionCompleted:
            return BaseXP.writingSessionCompleted
        case .focusScoreBonus(let pointsAbove80):
            return pointsAbove80 * BaseXP.focusScoreBonus
        case .uninterruptedDeepWork:
            return BaseXP.uninterruptedDeepWork

        // Creative
        case .contentPublished:
            return BaseXP.contentPublished
        case .impressions(let count):
            return (count / 10_000) * BaseXP.impressionsPer10K
        case .viralPost:
            return BaseXP.viralPost
        case .engagementRateBonus(let percentAboveBaseline):
            return Int(percentAboveBaseline) * BaseXP.engagementRateBonusPer1Pct
        case .contentPhaseTransition:
            return BaseXP.contentPhaseTransition
        case .contentDraftCompleted:
            return BaseXP.contentDraftCompleted
        case .clientContentDelivered:
            return BaseXP.clientContentDelivered

        // Physiological
        case .hrvMeasurement, .logHRV:
            return BaseXP.hrvMeasurement
        case .sleepLogged, .logSleep:
            return BaseXP.sleepLogged
        case .sleepConsistencyDay:
            return BaseXP.sleepConsistencyBonus
        case .workoutCompleted, .logWorkout:
            return BaseXP.workoutCompleted
        case .hrvImprovement(let msImprovement):
            return (msImprovement / 5) * BaseXP.hrvImprovement
        case .optimalReadiness:
            return BaseXP.optimalReadiness
        case .breathingSession:
            return BaseXP.breathingSession
        case .sleepTargetHit, .achieveSleepGoal:
            return BaseXP.sleepTargetHit
        case .optimalDeepSleep:
            return BaseXP.optimalDeepSleep
        case .mealLogged:
            return BaseXP.mealLogged

        // Behavioral
        case .deepWorkBlockCompleted:
            return BaseXP.deepWorkBlockCompleted
        case .routineAdherence:
            return BaseXP.routineAdherence
        case .taskCompletionStreakDay:
            return BaseXP.taskCompletionStreak
        case .morningRoutineComplete:
            return BaseXP.morningRoutineComplete
        case .eveningRoutineComplete:
            return BaseXP.eveningRoutineComplete
        case .scheduleAdherenceBonus:
            return BaseXP.scheduleAdherenceBonus
        case .distractionFreeBonus:
            return BaseXP.distractionFreeBonus

        // Knowledge
        case .researchAdded:
            return BaseXP.researchAdded
        case .connectionCreated:
            return BaseXP.connectionCreated
        case .semanticLinkDiscovered:
            return BaseXP.semanticLinkDiscovered
        case .insightExtracted:
            return BaseXP.insightExtracted
        case .autoLinkConfirmed:
            return BaseXP.autoLinkConfirmed
        case .semanticClusterFormed:
            return BaseXP.semanticClusterFormed
        case .graphDensityBonus:
            return BaseXP.graphDensityBonus

        // Reflection
        case .journalEntry:
            return BaseXP.journalEntry
        case .journalInsightGenerated:
            return BaseXP.journalInsightGenerated
        case .clarityScoreBonus(let pointsAbove70):
            return pointsAbove70 * BaseXP.clarityScoreBonus
        case .emotionalAwarenessLog:
            return BaseXP.emotionalAwarenessLog
        case .reflectionSessionCompleted:
            return BaseXP.reflectionSessionCompleted
        case .morningIntention:
            return BaseXP.morningIntention
        case .eveningReview:
            return BaseXP.eveningReview
        case .weeklyReflection:
            return BaseXP.weeklyReflection
        case .monthlyReview:
            return BaseXP.monthlyReview
        }
    }

    /// Get the dimension for an action
    static func dimensionForAction(_ action: XPAction) -> LevelDimension {
        switch action {
        case .wordsWritten, .taskCompleted, .deepWorkHour, .contentPieceCreated,
             .writingSessionCompleted, .focusScoreBonus, .uninterruptedDeepWork:
            return .cognitive

        case .contentPublished, .impressions, .viralPost, .engagementRateBonus,
             .contentPhaseTransition, .contentDraftCompleted, .clientContentDelivered:
            return .creative

        case .hrvMeasurement, .logHRV, .sleepLogged, .logSleep, .sleepConsistencyDay,
             .workoutCompleted, .logWorkout, .hrvImprovement, .optimalReadiness,
             .breathingSession, .sleepTargetHit, .achieveSleepGoal, .optimalDeepSleep,
             .mealLogged:
            return .physiological

        case .deepWorkBlockCompleted, .routineAdherence, .taskCompletionStreakDay,
             .morningRoutineComplete, .eveningRoutineComplete, .scheduleAdherenceBonus,
             .distractionFreeBonus:
            return .behavioral

        case .researchAdded, .connectionCreated, .semanticLinkDiscovered,
             .insightExtracted, .autoLinkConfirmed, .semanticClusterFormed,
             .graphDensityBonus:
            return .knowledge

        case .journalEntry, .journalInsightGenerated, .clarityScoreBonus,
             .emotionalAwarenessLog, .reflectionSessionCompleted, .morningIntention,
             .eveningReview, .weeklyReflection, .monthlyReview:
            return .reflection
        }
    }
}

// MARK: - XP Action Types

/// All actions that can earn XP
public enum XPAction: Sendable {
    // Cognitive
    case wordsWritten(count: Int)
    case taskCompleted
    case deepWorkHour(hours: Double)
    case contentPieceCreated
    case writingSessionCompleted
    case focusScoreBonus(pointsAbove80: Int)
    case uninterruptedDeepWork

    // Creative
    case contentPublished
    case impressions(count: Int)
    case viralPost
    case engagementRateBonus(percentAboveBaseline: Double)
    case contentPhaseTransition
    case contentDraftCompleted
    case clientContentDelivered

    // Physiological
    case hrvMeasurement
    case logHRV                            // Alias for hrvMeasurement
    case sleepLogged
    case logSleep                          // Alias for sleepLogged
    case sleepConsistencyDay
    case workoutCompleted
    case logWorkout                        // Alias for workoutCompleted
    case hrvImprovement(msImprovement: Int)
    case optimalReadiness
    case breathingSession
    case sleepTargetHit
    case achieveSleepGoal                  // Alias for sleepTargetHit
    case optimalDeepSleep
    case mealLogged

    // Behavioral
    case deepWorkBlockCompleted
    case routineAdherence
    case taskCompletionStreakDay
    case morningRoutineComplete
    case eveningRoutineComplete
    case scheduleAdherenceBonus
    case distractionFreeBonus

    // Knowledge
    case researchAdded
    case connectionCreated
    case semanticLinkDiscovered
    case insightExtracted
    case autoLinkConfirmed
    case semanticClusterFormed
    case graphDensityBonus

    // Reflection
    case journalEntry
    case journalInsightGenerated
    case clarityScoreBonus(pointsAbove70: Int)
    case emotionalAwarenessLog
    case reflectionSessionCompleted
    case morningIntention
    case eveningReview
    case weeklyReflection
    case monthlyReview
}

// MARK: - XP Award Result

/// Result of an XP calculation
public struct XPAward: Sendable {
    public let baseAmount: Int
    public let finalAmount: Int
    public let multiplier: Double
    public let streakMultiplier: Double
    public let dimension: LevelDimension

    public init(baseAmount: Int, finalAmount: Int, multiplier: Double, streakMultiplier: Double, dimension: LevelDimension) {
        self.baseAmount = baseAmount
        self.finalAmount = finalAmount
        self.multiplier = multiplier
        self.streakMultiplier = streakMultiplier
        self.dimension = dimension
    }

    /// Human-readable description of the award
    var description: String {
        if multiplier > 1.0 {
            return "+\(finalAmount) XP (\(baseAmount) × \(String(format: "%.2f", multiplier)))"
        } else {
            return "+\(finalAmount) XP"
        }
    }

    /// Whether a multiplier was applied
    var hasMultiplier: Bool {
        multiplier > 1.0
    }
}

// MARK: - Level Milestone

/// Represents a significant level milestone
struct LevelMilestone: Sendable, Identifiable {
    let id = UUID()
    let level: Int
    let name: String
    let description: String
    let xpRequired: Int
    let rewards: [MilestoneReward]

    static let milestones: [LevelMilestone] = [
        LevelMilestone(
            level: 10,
            name: "First Steps",
            description: "You've established a baseline of cognitive habits.",
            xpRequired: XPCalculationEngine.xpRequiredForLevel(10),
            rewards: [.badge("first_steps")]
        ),
        LevelMilestone(
            level: 25,
            name: "Getting Serious",
            description: "Your knowledge work practice is becoming consistent.",
            xpRequired: XPCalculationEngine.xpRequiredForLevel(25),
            rewards: [.badge("getting_serious"), .multiplierBonus(1.05)]
        ),
        LevelMilestone(
            level: 50,
            name: "Expert",
            description: "You've reached expert-level cognitive performance.",
            xpRequired: XPCalculationEngine.xpRequiredForLevel(50),
            rewards: [.badge("expert"), .multiplierBonus(1.1)]
        ),
        LevelMilestone(
            level: 75,
            name: "Master",
            description: "You operate at master-level across dimensions.",
            xpRequired: XPCalculationEngine.xpRequiredForLevel(75),
            rewards: [.badge("master"), .multiplierBonus(1.15)]
        ),
        LevelMilestone(
            level: 100,
            name: "Transcendent",
            description: "You've achieved peak cognitive performance.",
            xpRequired: XPCalculationEngine.xpRequiredForLevel(100),
            rewards: [.badge("transcendent"), .multiplierBonus(1.25)]
        )
    ]

    static func milestone(forLevel level: Int) -> LevelMilestone? {
        milestones.first { $0.level == level }
    }

    static func nextMilestone(fromLevel level: Int) -> LevelMilestone? {
        milestones.first { $0.level > level }
    }
}

/// Rewards for reaching a milestone
enum MilestoneReward: Sendable {
    case badge(String)
    case multiplierBonus(Double)
    case featureUnlock(String)
}

// MARK: - XP Event Helpers

extension XPCalculationEngine {
    /// Create XP metadata for an event atom
    static func createXPMetadata(
        action: XPAction,
        streakDays: Int,
        sourceAtomUUID: String?,
        bonusMultipliers: [Double] = []
    ) -> XPEventMetadata {
        let dimension = dimensionForAction(action)
        let award = calculateXP(
            baseAmount: xpForAction(action),
            streakDays: streakDays,
            dimension: dimension,
            bonusMultipliers: bonusMultipliers
        )

        // Determine bonus type if any
        var bonusType: XPBonusType? = nil
        if award.streakMultiplier > 1.0 {
            bonusType = .streakBonus
        } else if !bonusMultipliers.isEmpty && bonusMultipliers.contains(where: { $0 > 1.0 }) {
            bonusType = .luckyBonus
        }

        return XPEventMetadata(
            dimension: dimension,
            xpAmount: award.finalAmount,
            baseXP: award.baseAmount,
            source: String(describing: action),
            sourceAtomUUID: sourceAtomUUID,
            multiplier: award.multiplier,
            bonusType: bonusType,
            timestamp: Date()
        )
    }
}
