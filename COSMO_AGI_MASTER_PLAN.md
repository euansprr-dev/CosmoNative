# COSMO AGI MASTER PLAN
## The World's First Cognitive OS for Knowledge Workers

**Target Hardware:**
- Current: MacBook Pro M4, 16GB RAM
- Future: Mac Studio M3 Ultra, 512GB RAM
- Companion: Apple Watch Ultra 3

**Architecture Principle:** Everything is an Atom. No exceptions.

---

# PART 1: FOUNDATIONAL ARCHITECTURE

## 1.1 The Unified Atom System (Extended)

The existing Atom model is solid. We extend it to support the full cognitive OS:

### New Atom Types to Add

```swift
enum AtomType: String, Codable, CaseIterable {
    // Existing
    case idea, task, project, content, research, connection
    case journalEntry, calendarEvent, scheduleBlock, uncommittedItem

    // NEW: Leveling & Gamification
    case xpEvent              // Every XP gain is an atom
    case levelUpdate          // CI or NELO level changes
    case streakEvent          // Streak milestones
    case badgeUnlocked        // Achievement unlocks
    case dimensionSnapshot    // Daily dimension scores

    // NEW: Physiology (Apple Watch Ultra 3)
    case hrvMeasurement       // Heart Rate Variability readings
    case restingHR            // Resting heart rate
    case sleepCycle           // Sleep stage data
    case sleepConsistency     // Sleep schedule adherence
    case readinessScore       // Daily readiness composite
    case workoutSession       // Exercise data
    case mealLog              // Nutrition tracking
    case breathingSession     // Mindfulness/breathing
    case bloodOxygen          // SpO2 measurements
    case bodyTemperature      // Wrist temperature deviation

    // NEW: Cognitive Output
    case deepWorkBlock        // Focused work sessions
    case writingSession       // Words written in session
    case wordCountEntry       // Daily word aggregates
    case focusScore           // Attention quality metrics
    case distractionEvent     // Context switches tracked

    // NEW: Content Pipeline
    case contentDraft         // Draft versions
    case contentPhase         // Phase transitions
    case contentPerformance   // Analytics data
    case contentPublish       // Publish events
    case clientProfile        // Ghostwriting clients

    // NEW: Knowledge Graph
    case semanticCluster      // Auto-grouped concepts
    case connectionLink       // Explicit atom relationships
    case autoLinkSuggestion   // AI-suggested links
    case insightExtraction    // AI-extracted insights

    // NEW: Reflection
    case journalInsight       // Extracted from journals
    case analysisChunk        // LLM analysis segments
    case emotionalState       // Sentiment snapshots
    case clarityScore         // Journal quality metrics

    // NEW: System
    case dailySummary         // End-of-day rollup
    case weeklySummary        // Weekly analysis
    case syncEvent            // Sync operations
    case systemEvent          // App lifecycle events
    case userPreference       // Settings as atoms
    case routineDefinition    // Behavioral patterns
}
```

### Extended Atom Metadata Structures

```swift
// MARK: - Leveling Metadata

struct XPEventMetadata: Codable {
    let dimension: LevelDimension
    let xpAmount: Int
    let source: String           // What triggered this XP
    let sourceAtomUUID: String?  // Related atom
    let multiplier: Double       // Streak/bonus multipliers
    let timestamp: Date
}

struct LevelUpdateMetadata: Codable {
    let dimension: LevelDimension
    let previousLevel: Int
    let newLevel: Int
    let levelType: LevelType     // .ci or .nelo
    let triggeringXP: Int
}

struct StreakEventMetadata: Codable {
    let streakType: StreakType
    let currentStreak: Int
    let previousStreak: Int
    let isNewRecord: Bool
    let multiplierUnlocked: Double?
}

struct BadgeUnlockedMetadata: Codable {
    let badgeId: String
    let badgeCategory: BadgeCategory
    let badgeTier: BadgeTier
    let unlockedAt: Date
    let triggerMetric: String
    let triggerValue: Double
}

struct DimensionSnapshotMetadata: Codable {
    let date: Date
    let cognitive: DimensionState
    let creative: DimensionState
    let physiological: DimensionState
    let behavioral: DimensionState
    let knowledge: DimensionState
    let reflection: DimensionState
    let overallCI: Int
    let overallNELO: Int
}

struct DimensionState: Codable {
    let level: Int
    let xp: Int
    let xpToNextLevel: Int
    let nelo: Int
    let neloChange: Int      // +/- from previous day
    let trend: Trend         // .improving, .stable, .declining
}

// MARK: - Physiology Metadata (Apple Watch Ultra 3)

struct HRVMeasurementMetadata: Codable {
    let hrvMs: Double                    // SDNN in milliseconds
    let measurementType: HRVType         // .nighttime, .resting, .recovery
    let confidence: Double               // 0-1 measurement quality
    let context: String?                 // "post-workout", "morning", etc.
    let deviceId: String                 // Watch identifier
    let percentileRank: Double?          // vs. population
}

struct SleepCycleMetadata: Codable {
    let sleepStart: Date
    let sleepEnd: Date
    let totalDuration: TimeInterval
    let deepSleepMinutes: Int
    let remSleepMinutes: Int
    let coreSleepMinutes: Int
    let awakeMinutes: Int
    let sleepEfficiency: Double          // 0-1
    let respiratoryRate: Double?         // breaths/min
    let heartRateDuringSleep: HeartRateRange
}

struct SleepConsistencyMetadata: Codable {
    let date: Date
    let targetBedtime: Date
    let actualBedtime: Date
    let targetWakeTime: Date
    let actualWakeTime: Date
    let deviationMinutes: Int
    let consistencyScore: Double         // 0-100
    let streak: Int                      // Days of consistency
}

struct ReadinessScoreMetadata: Codable {
    let date: Date
    let overallScore: Double             // 0-100
    let hrvContribution: Double
    let sleepContribution: Double
    let recoveryContribution: Double
    let strainBalance: Double            // Recovery vs strain
    let recommendation: ReadinessRecommendation
}

struct WorkoutSessionMetadata: Codable {
    let workoutType: WorkoutType
    let duration: TimeInterval
    let activeCalories: Double
    let avgHeartRate: Int
    let maxHeartRate: Int
    let hrvRecovery: Double?             // Post-workout HRV
    let strainScore: Double              // 0-21 scale (WHOOP-style)
    let elevationGain: Double?
    let distance: Double?
    let zones: [HeartRateZone]
}

// MARK: - Cognitive Output Metadata

struct DeepWorkBlockMetadata: Codable {
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let focusScore: Double               // 0-100 based on interruptions
    let contextSwitches: Int
    let projectUUID: String?
    let wordsWritten: Int
    let tasksCompleted: Int
    let qualityRating: Int?              // User self-rating 1-5
}

struct WritingSessionMetadata: Codable {
    let startTime: Date
    let endTime: Date
    let wordCount: Int
    let netWordCount: Int                // Accounting for deletions
    let charactersTyped: Int
    let averageWPM: Double
    let peakWPM: Double
    let contentAtomUUID: String?
    let sessionType: WritingSessionType  // .drafting, .editing, .research
}

struct FocusScoreMetadata: Codable {
    let timestamp: Date
    let score: Double                    // 0-100
    let activeAppBundleId: String
    let screenTimeMinutes: Int
    let productiveMinutes: Int
    let distractedMinutes: Int
    let topDistractions: [String]
}

// MARK: - Content Pipeline Metadata

struct ContentPerformanceMetadata: Codable {
    let platform: SocialPlatform
    let postId: String
    let publishedAt: Date
    let impressions: Int
    let reach: Int
    let engagement: Int
    let likes: Int
    let comments: Int
    let shares: Int
    let saves: Int
    let profileVisits: Int?
    let followsGained: Int?
    let engagementRate: Double
    let viralityScore: Double?           // Calculated metric
    let isViral: Bool                    // Exceeds threshold
    let lastUpdated: Date
}

struct ClientProfileMetadata: Codable {
    let clientId: String
    let clientName: String
    let platforms: [SocialPlatform]
    let totalReach: Int
    let avgEngagementRate: Double
    let contentCount: Int
    let activeStatus: Bool
}

// MARK: - Reflection Metadata

struct JournalInsightMetadata: Codable {
    let journalAtomUUID: String
    let insightType: InsightType         // .goal, .fear, .belief, .pattern
    let extractedText: String
    let confidence: Double
    let suggestedAction: String?
    let linkedAtomUUIDs: [String]
    let emotionalValence: Double         // -1 to 1
}

struct EmotionalStateMetadata: Codable {
    let timestamp: Date
    let primaryEmotion: Emotion
    let secondaryEmotions: [Emotion]
    let valence: Double                  // -1 to 1
    let arousal: Double                  // 0 to 1
    let dominance: Double                // 0 to 1
    let source: EmotionalStateSource     // .journal, .voice, .inferred
    let contextNotes: String?
}

struct ClarityScoreMetadata: Codable {
    let journalAtomUUID: String
    let overallClarity: Double           // 0-100
    let structureScore: Double           // Coherent thought progression
    let specificityScore: Double         // Concrete vs vague
    let actionabilityScore: Double       // Leads to clear actions
    let emotionalAccuracy: Double        // Self-awareness quality
    let insightDensity: Double           // Insights per 100 words
}
```

### Atom Links System (Extended)

```swift
struct AtomLink: Codable, Hashable {
    let type: AtomLinkType
    let targetUUID: String
    let strength: Double?        // 0-1 for semantic similarity
    let createdAt: Date
    let metadata: [String: String]?

    enum AtomLinkType: String, Codable {
        // Hierarchical
        case parent              // Parent-child relationship
        case child
        case project             // Belongs to project

        // Temporal
        case previous            // Sequential ordering
        case next
        case recurrenceParent    // Recurring item source
        case recurrenceInstance

        // Semantic
        case related             // General relationship
        case semantic            // AI-detected similarity
        case contradicts         // Opposing ideas
        case supports            // Supporting evidence
        case refines             // More specific version
        case generalizes         // More abstract version

        // Causal
        case causedBy            // Effect of another atom
        case causes              // Leads to another atom
        case blockedBy           // Dependency
        case enables             // Unlocks another

        // Knowledge
        case cites               // References source
        case citedBy             // Is referenced
        case elaborates          // Expands on
        case summarizes          // Condenses

        // XP/Leveling
        case triggered           // Caused XP event
        case achievementSource   // Led to badge unlock
        case streakMember        // Part of streak
    }
}
```

---

## 1.2 The Two-Tier Level Architecture

### Core Level System

```swift
// MARK: - Level System Core

struct CosmoLevelSystem: Codable {
    // Permanent identity-level progress (never decreases)
    var cosmoIndex: Int                  // CI: 1-100+
    var cosmoIndexXP: Int                // Total XP towards CI

    // Dynamic performance metric (can rise and fall)
    var neuroELO: Int                    // NELO: ~800-2400 scale

    // Per-dimension tracking
    var dimensions: [LevelDimension: DimensionProgress]

    // Streaks
    var streaks: StreakTracker

    // Badges
    var unlockedBadges: Set<String>
    var badgeProgress: [String: BadgeProgress]
}

enum LevelDimension: String, Codable, CaseIterable {
    case cognitive         // Writing, deep work, task completion
    case creative          // Content performance, reach, virality
    case physiological     // HRV, sleep, recovery
    case behavioral        // Consistency, routine adherence
    case knowledge         // Research, connections, semantic density
    case reflection        // Journaling, insights, self-awareness
}

struct DimensionProgress: Codable {
    let dimension: LevelDimension
    var level: Int                       // 1-100
    var xp: Int                          // Current XP in level
    var totalXP: Int                     // Lifetime XP
    var nelo: Int                        // Dimension-specific NELO
    var neloHistory: [NELODataPoint]     // Last 30 days

    // Regression tracking
    var lastActiveDate: Date
    var daysSinceActive: Int
    var regressionWarning: Bool
}

struct NELODataPoint: Codable {
    let date: Date
    let nelo: Int
    let change: Int
    let triggeredBy: String              // Description of cause
}
```

### XP Calculation Engine

```swift
// MARK: - XP Engine

class XPCalculationEngine {

    // Base XP values (before multipliers)
    struct BaseXP {
        // Cognitive
        static let wordsWritten = 1          // Per 100 words
        static let taskCompleted = 10
        static let deepWorkHour = 25
        static let contentPieceCreated = 50

        // Creative
        static let contentPublished = 20
        static let impressionsPer10K = 5
        static let viralPost = 500
        static let engagementRateBonusPer1Pct = 10

        // Physiological
        static let hrvMeasurement = 5
        static let sleepLogged = 10
        static let sleepConsistencyBonus = 15   // Per day streak
        static let workoutCompleted = 20
        static let hrvImprovement = 25          // Per 5ms improvement

        // Behavioral
        static let deepWorkBlockCompleted = 15
        static let routineAdherence = 10        // Per block followed
        static let taskCompletionStreak = 5     // Per day
        static let morningRoutineComplete = 30

        // Knowledge
        static let researchAdded = 10
        static let connectionCreated = 25
        static let semanticLinkDiscovered = 15
        static let insightExtracted = 20

        // Reflection
        static let journalEntry = 15
        static let journalInsightGenerated = 10
        static let clarityScoreBonus = 1        // Per point above 70
        static let emotionalAwarenessLog = 5
    }

    // Streak multipliers
    struct StreakMultipliers {
        static func forStreak(_ days: Int) -> Double {
            switch days {
            case 0...6: return 1.0
            case 7...13: return 1.1
            case 14...29: return 1.2
            case 30...59: return 1.35
            case 60...89: return 1.5
            case 90...179: return 1.75
            case 180...364: return 2.0
            case 365...999: return 2.5
            default: return 3.0              // 1000+ days
            }
        }
    }

    // Level thresholds (exponential curve)
    static func xpRequiredForLevel(_ level: Int) -> Int {
        // L1: 100, L10: 1000, L25: 6250, L50: 25000, L100: 100000
        return Int(100 * pow(Double(level), 1.5))
    }
}
```

### NELO Regression System

```swift
// MARK: - NELO Regression

class NELORegressionEngine {

    struct RegressionRules {
        // Cognitive: 3-day rolling average drops >40%
        static let cognitiveThreshold = 0.4
        static let cognitiveWindow = 3

        // Physiological: HRV drops vs 7-day baseline
        static let physiologicalHRVDropThreshold = 0.15
        static let physiologicalWindow = 7

        // Behavioral: Deep work drops OR destructive habits increase
        static let behavioralDeepWorkDropThreshold = 0.3
        static let behavioralWindow = 7

        // Creative: 30-day reach < 60-day baseline
        static let creativeReachDropWindow = 30
        static let creativeBaselineWindow = 60

        // Knowledge: Minimal regression (knowledge persists)
        static let knowledgeRegressionRate = 0.0  // No regression

        // Reflection: Minimal if journaling stops
        static let reflectionInactivityDays = 7
        static let reflectionRegressionRate = 0.02  // 2% per week inactive
    }

    func calculateNELOChange(
        dimension: LevelDimension,
        currentNELO: Int,
        recentAtoms: [Atom],
        baselineAtoms: [Atom]
    ) -> Int {
        // Returns positive or negative change
        // Implementation varies by dimension
    }

    // K-factor for NELO changes (chess-style)
    static func kFactor(forNELO nelo: Int) -> Double {
        switch nelo {
        case ..<1200: return 40   // High volatility for beginners
        case 1200..<1600: return 32
        case 1600..<2000: return 24
        case 2000..<2400: return 16
        default: return 10        // Elite: slow, stable changes
        }
    }
}
```

---

## 1.3 The Six Dimensions (Scientific Thresholds)

### Dimension 1: Cognitive Output

```swift
struct CognitiveDimensionConfig {
    // Data-anchored thresholds (MIT/Stanford productivity research)
    static let levelThresholds: [(level: Int, wordsPerDay: Int)] = [
        (1, 100),      // Basic output
        (10, 400),     // Regular writer
        (20, 800),     // Consistent professional
        (30, 1200),    // High performer
        (40, 1500),    // Top 10%
        (50, 2000),    // Elite
        (60, 2500),    // Top 1%
        (70, 3500),    // Professional author pace
        (80, 5000),    // Stephen King territory
        (90, 7500),    // Extreme outlier
        (100, 10000),  // Maximum (humanly achievable)
    ]

    // Deep work thresholds (Cal Newport research)
    static let deepWorkThresholds: [(level: Int, hoursPerDay: Double)] = [
        (1, 0.5),
        (25, 2.0),
        (50, 4.0),     // Newport's elite threshold
        (75, 5.0),
        (100, 6.0),    // Theoretical max for sustained periods
    ]

    // Task completion velocity
    static let taskThresholds: [(level: Int, tasksPerWeek: Int)] = [
        (1, 5),
        (25, 20),
        (50, 40),
        (75, 70),
        (100, 100),
    ]
}
```

### Dimension 2: Creative Performance

```swift
struct CreativeDimensionConfig {
    // Platform-agnostic virality thresholds
    static let reachThresholds: [(level: Int, weeklyReach: Int)] = [
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

    // Viral content thresholds (30-day window)
    static let viralThresholds: [(level: Int, viralPosts: Int)] = [
        (25, 1),
        (50, 5),
        (75, 15),
        (100, 30),            // Nearly daily virality
    ]

    // Client aggregation for ghostwriters
    struct ClientAggregation {
        static func normalizedReach(
            clients: [ClientProfile],
            window: DateInterval
        ) -> Int {
            // Sum all client reach, weighted by post count
            // Prevents gaming by having many inactive clients
        }
    }
}
```

### Dimension 3: Physiological Mastery

```swift
struct PhysiologicalDimensionConfig {
    // HRV thresholds (real science: WHOOP, Oura, academic research)
    // Note: Age-adjusted in practice
    static let hrvThresholds: [(level: Int, hrvMs: Double)] = [
        (1, 40),       // Below average
        (10, 55),      // Average
        (20, 65),      // Good
        (30, 75),      // Very good
        (40, 85),      // Excellent
        (50, 100),     // Elite
        (60, 115),     // Top 5%
        (70, 130),     // Top 1%
        (80, 145),     // Top 0.5%
        (90, 160),     // Elite athlete
        (100, 180),    // Maximum observed
    ]

    // Resting heart rate (lower is better)
    static let restingHRThresholds: [(level: Int, bpm: Int)] = [
        (1, 80),
        (25, 65),
        (50, 55),
        (75, 48),
        (100, 40),     // Elite athlete
    ]

    // Sleep consistency (variance in minutes)
    static let sleepConsistencyThresholds: [(level: Int, varianceMinutes: Int)] = [
        (1, 90),       // High variance
        (25, 60),
        (50, 30),
        (75, 15),      // Elite consistency
        (100, 10),     // Near-perfect
    ]

    // Deep sleep percentage
    static let deepSleepThresholds: [(level: Int, percentage: Double)] = [
        (1, 10),
        (25, 15),
        (50, 20),
        (75, 25),
        (100, 30),     // Exceptional
    ]

    // Combined readiness score
    static func calculateReadinessLevel(
        hrv: Double,
        restingHR: Int,
        sleepQuality: Double,
        recoveryStatus: Double
    ) -> Int {
        // Weighted composite
    }
}
```

### Dimension 4: Behavioral Consistency

```swift
struct BehavioralDimensionConfig {
    // Deep work blocks per day
    static let deepWorkBlockThresholds: [(level: Int, blocksPerDay: Int, streak: Int)] = [
        (1, 1, 1),
        (20, 2, 10),
        (50, 3, 30),
        (75, 4, 60),
        (100, 4, 90),  // 90 days of 4 blocks/day
    ]

    // Routine adherence
    static let routineAdherenceThresholds: [(level: Int, percentage: Double)] = [
        (1, 30),
        (25, 50),
        (50, 70),
        (75, 85),
        (100, 95),
    ]

    // Wake/sleep consistency
    static let circadianConsistencyThresholds: [(level: Int, varianceMinutes: Int, streak: Int)] = [
        (1, 60, 1),
        (25, 45, 7),
        (50, 30, 14),
        (75, 20, 30),
        (100, 15, 60),
    ]

    // Distraction resistance (context switches per hour during deep work)
    static let focusThresholds: [(level: Int, switchesPerHour: Double)] = [
        (1, 12),       // Every 5 min
        (25, 6),       // Every 10 min
        (50, 3),       // Every 20 min
        (75, 1.5),     // Every 40 min
        (100, 0.5),    // Near-zero distraction
    ]
}
```

### Dimension 5: Knowledge Expansion

```swift
struct KnowledgeDimensionConfig {
    // Semantic connections (meaningful links between atoms)
    static let connectionThresholds: [(level: Int, connections: Int)] = [
        (1, 10),
        (10, 50),
        (20, 150),
        (30, 300),
        (40, 600),
        (50, 1_000),
        (60, 2_500),
        (70, 5_000),
        (80, 10_000),
        (90, 20_000),
        (100, 30_000),     // True polymath brain
    ]

    // Semantic density (unique concepts per 1000 atoms)
    static let semanticDensityThresholds: [(level: Int, density: Double)] = [
        (1, 10),
        (25, 25),
        (50, 50),
        (75, 100),
        (100, 200),
    ]

    // Cross-domain linkage ratio
    static let crossDomainThresholds: [(level: Int, ratio: Double)] = [
        (1, 0.05),     // 5% cross-domain links
        (25, 0.15),
        (50, 0.30),
        (75, 0.45),
        (100, 0.60),   // 60% of links cross domains
    ]

    // Note: Knowledge doesn't regress (NELO stays stable)
}
```

### Dimension 6: Self-Reflection Depth

```swift
struct ReflectionDimensionConfig {
    // Journal frequency
    static let journalThresholds: [(level: Int, entries: Int)] = [
        (1, 3),
        (10, 20),
        (25, 50),
        (50, 200),
        (75, 500),
        (100, 1000),
    ]

    // Clarity score (LLM-analyzed)
    static let clarityThresholds: [(level: Int, avgScore: Double)] = [
        (1, 30),
        (25, 50),
        (50, 65),
        (75, 80),
        (100, 90),
    ]

    // Insight density (insights per journal entry)
    static let insightDensityThresholds: [(level: Int, insightsPerEntry: Double)] = [
        (1, 0.5),
        (25, 1.0),
        (50, 2.0),
        (75, 3.5),
        (100, 5.0),
    ]

    // Emotional accuracy (self-report vs detected alignment)
    static let emotionalAccuracyThresholds: [(level: Int, alignment: Double)] = [
        (1, 0.3),
        (25, 0.5),
        (50, 0.7),
        (75, 0.85),
        (100, 0.95),
    ]
}
```

---

## 1.4 Badge System Architecture

### Badge Categories & Tiers

```swift
// MARK: - Badge System

enum BadgeCategory: String, Codable, CaseIterable {
    case consistency        // Streak-based
    case health             // Physiological achievements
    case writingOutput      // Words written
    case performance        // Content virality
    case research           // Knowledge accumulation
    case connections        // Linking mastery
    case progression        // Level milestones
    case transformation     // Major life wins
}

enum BadgeTier: String, Codable, CaseIterable {
    case bronze             // Entry level
    case silver             // Intermediate
    case gold               // Advanced
    case platinum           // Expert
    case diamond            // Elite
    case obsidian           // Legendary (hidden until unlocked)
}

struct Badge: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let category: BadgeCategory
    let tier: BadgeTier
    let iconName: String
    let requirement: BadgeRequirement
    let xpReward: Int
    let isSecret: Bool
    let unlockedMessage: String
}

struct BadgeRequirement: Codable {
    let metric: String
    let threshold: Double
    let window: DateWindow?        // nil = lifetime
    let additionalConditions: [String: Any]?
}
```

### Complete Badge Catalog

```swift
struct BadgeCatalog {

    // CONSISTENCY SERIES
    static let consistency: [Badge] = [
        Badge(id: "streak_7", name: "7-Day Operator",
              description: "Complete core routine 7 days straight",
              category: .consistency, tier: .bronze,
              requirement: .init(metric: "routine_streak", threshold: 7),
              xpReward: 100),

        Badge(id: "streak_30", name: "30-Day Flowwalker",
              description: "30 consecutive days of deep work",
              category: .consistency, tier: .silver,
              requirement: .init(metric: "deep_work_streak", threshold: 30),
              xpReward: 500),

        Badge(id: "streak_90", name: "90-Day Relentless",
              description: "Quarter of unbroken commitment",
              category: .consistency, tier: .gold,
              requirement: .init(metric: "routine_streak", threshold: 90),
              xpReward: 1500),

        Badge(id: "streak_180", name: "180-Day Vanguard",
              description: "Half year of consistency",
              category: .consistency, tier: .platinum,
              requirement: .init(metric: "routine_streak", threshold: 180),
              xpReward: 3500),

        Badge(id: "streak_365", name: "365-Day Endurer",
              description: "One year unbroken",
              category: .consistency, tier: .diamond,
              requirement: .init(metric: "routine_streak", threshold: 365),
              xpReward: 10000),

        Badge(id: "streak_1000", name: "1000-Day Unbroken",
              description: "The holy grail of consistency",
              category: .consistency, tier: .obsidian, isSecret: true,
              requirement: .init(metric: "routine_streak", threshold: 1000),
              xpReward: 50000),
    ]

    // WRITING OUTPUT SERIES
    static let writing: [Badge] = [
        Badge(id: "words_100k", name: "100K Words",
              description: "First hundred thousand words",
              category: .writingOutput, tier: .bronze,
              requirement: .init(metric: "lifetime_words", threshold: 100_000),
              xpReward: 250),

        Badge(id: "words_500k", name: "500K Words",
              description: "Half million words written",
              category: .writingOutput, tier: .silver,
              requirement: .init(metric: "lifetime_words", threshold: 500_000),
              xpReward: 1000),

        Badge(id: "words_1m", name: "Millionaire",
              description: "One million words",
              category: .writingOutput, tier: .gold,
              requirement: .init(metric: "lifetime_words", threshold: 1_000_000),
              xpReward: 3000),

        Badge(id: "words_5m", name: "Prolific",
              description: "Five million words",
              category: .writingOutput, tier: .platinum,
              requirement: .init(metric: "lifetime_words", threshold: 5_000_000),
              xpReward: 10000),

        Badge(id: "words_10m", name: "Titan of Text",
              description: "Ten million words - published author territory",
              category: .writingOutput, tier: .diamond,
              requirement: .init(metric: "lifetime_words", threshold: 10_000_000),
              xpReward: 25000),
    ]

    // HEALTH SERIES
    static let health: [Badge] = [
        Badge(id: "hrv_improved_10", name: "HRV Rising",
              description: "HRV improved 10 days straight",
              category: .health, tier: .bronze,
              requirement: .init(metric: "hrv_improvement_streak", threshold: 10),
              xpReward: 150),

        Badge(id: "hrv_100", name: "HRV Century",
              description: "Achieve 100ms+ HRV",
              category: .health, tier: .gold,
              requirement: .init(metric: "hrv_max", threshold: 100),
              xpReward: 1000),

        Badge(id: "sleep_consistency_90", name: "Sleep Master",
              description: "90% sleep consistency for 30 days",
              category: .health, tier: .gold,
              requirement: .init(metric: "sleep_consistency", threshold: 90,
                               window: .days(30)),
              xpReward: 1500),

        Badge(id: "readiness_elite_7", name: "Morning Readiness Elite",
              description: "7-day streak of elite readiness",
              category: .health, tier: .platinum,
              requirement: .init(metric: "readiness_streak", threshold: 7),
              xpReward: 2000),

        Badge(id: "hrv_160", name: "Elite Physiology",
              description: "Achieve 160ms+ HRV (top 0.1%)",
              category: .health, tier: .obsidian, isSecret: true,
              requirement: .init(metric: "hrv_max", threshold: 160),
              xpReward: 5000),
    ]

    // PERFORMANCE SERIES
    static let performance: [Badge] = [
        Badge(id: "viral_1", name: "First Viral",
              description: "Your first viral post",
              category: .performance, tier: .bronze,
              requirement: .init(metric: "viral_posts", threshold: 1),
              xpReward: 500),

        Badge(id: "viral_10", name: "Viral Veteran",
              description: "10 viral posts",
              category: .performance, tier: .silver,
              requirement: .init(metric: "viral_posts", threshold: 10),
              xpReward: 2000),

        Badge(id: "viral_100", name: "Viral Virtuoso",
              description: "100 viral posts",
              category: .performance, tier: .gold,
              requirement: .init(metric: "viral_posts", threshold: 100),
              xpReward: 10000),

        Badge(id: "views_1b", name: "Billion Views",
              description: "1 billion collective views",
              category: .performance, tier: .platinum,
              requirement: .init(metric: "lifetime_views", threshold: 1_000_000_000),
              xpReward: 25000),

        Badge(id: "views_10b", name: "Decabillion",
              description: "10 billion collective views",
              category: .performance, tier: .obsidian, isSecret: true,
              requirement: .init(metric: "lifetime_views", threshold: 10_000_000_000),
              xpReward: 100000),
    ]

    // PROGRESSION SERIES
    static let progression: [Badge] = [
        Badge(id: "ci_10", name: "Initiate",
              description: "Reach Cosmo Index 10",
              category: .progression, tier: .bronze,
              requirement: .init(metric: "cosmo_index", threshold: 10),
              xpReward: 100),

        Badge(id: "ci_25", name: "Apprentice",
              description: "Reach Cosmo Index 25",
              category: .progression, tier: .silver,
              requirement: .init(metric: "cosmo_index", threshold: 25),
              xpReward: 500),

        Badge(id: "ci_50", name: "Practitioner",
              description: "Reach Cosmo Index 50",
              category: .progression, tier: .gold,
              requirement: .init(metric: "cosmo_index", threshold: 50),
              xpReward: 2500),

        Badge(id: "ci_75", name: "Expert",
              description: "Reach Cosmo Index 75",
              category: .progression, tier: .platinum,
              requirement: .init(metric: "cosmo_index", threshold: 75),
              xpReward: 7500),

        Badge(id: "ci_100", name: "Master",
              description: "Reach Cosmo Index 100",
              category: .progression, tier: .diamond,
              requirement: .init(metric: "cosmo_index", threshold: 100),
              xpReward: 25000),

        Badge(id: "nelo_2400", name: "Grandmaster",
              description: "Achieve 2400 NELO rating",
              category: .progression, tier: .obsidian, isSecret: true,
              requirement: .init(metric: "peak_nelo", threshold: 2400),
              xpReward: 50000),
    ]

    // TRANSFORMATION SERIES (Rare, meaningful achievements)
    static let transformation: [Badge] = [
        Badge(id: "first_deep_work_week", name: "Week of Depth",
              description: "First week of consistent deep work",
              category: .transformation, tier: .bronze,
              requirement: .init(metric: "deep_work_week_streak", threshold: 1),
              xpReward: 200),

        Badge(id: "knowledge_graph_100", name: "Connected Mind",
              description: "100+ connections in knowledge graph",
              category: .transformation, tier: .silver,
              requirement: .init(metric: "knowledge_connections", threshold: 100),
              xpReward: 750),

        Badge(id: "complete_dimension_50", name: "Renaissance",
              description: "All 6 dimensions at level 50+",
              category: .transformation, tier: .diamond,
              requirement: .init(metric: "min_dimension_level", threshold: 50),
              xpReward: 15000),

        Badge(id: "perfect_day", name: "Perfect Day",
              description: "Complete all planned tasks, deep work, AND elite readiness",
              category: .transformation, tier: .gold, isSecret: true,
              requirement: .init(metric: "perfect_day_score", threshold: 100),
              xpReward: 1000),
    ]
}
```

---

# PART 2: APPLE WATCH ULTRA 3 INTEGRATION

## 2.1 HealthKit Data Pipeline

### HealthKit Data Types to Collect

```swift
// MARK: - HealthKit Integration

struct HealthKitConfiguration {

    // Read permissions required
    static let readTypes: Set<HKObjectType> = [
        // Heart
        HKQuantityType(.heartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.walkingHeartRateAverage),
        HKQuantityType(.heartRateRecoveryOneMinute),

        // Blood Oxygen (Apple Watch Ultra 3)
        HKQuantityType(.oxygenSaturation),

        // Temperature (Apple Watch Ultra 3)
        HKQuantityType(.appleSleepingWristTemperature),

        // Respiratory
        HKQuantityType(.respiratoryRate),

        // Sleep
        HKCategoryType(.sleepAnalysis),

        // Activity
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.appleStandTime),
        HKQuantityType(.appleMoveTime),
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.distanceSwimming),
        HKQuantityType(.flightsClimbed),

        // Workouts
        HKWorkoutType.workoutType(),

        // Mindfulness
        HKCategoryType(.mindfulSession),

        // Water intake
        HKQuantityType(.dietaryWater),
    ]

    // Background delivery for real-time atoms
    static let backgroundDeliveryTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRateVariabilitySDNN),
        HKCategoryType(.sleepAnalysis),
        HKWorkoutType.workoutType(),
    ]
}
```

### HealthKit to Atom Converter

```swift
// MARK: - HealthKit Atom Factory

actor HealthKitAtomFactory {

    private let atomRepository: AtomRepository
    private let healthStore: HKHealthStore

    func convertHRVSample(_ sample: HKQuantitySample) async -> Atom {
        let hrvMs = sample.quantity.doubleValue(for: .init(from: "ms"))

        let metadata = HRVMeasurementMetadata(
            hrvMs: hrvMs,
            measurementType: classifyHRVType(sample),
            confidence: calculateConfidence(sample),
            context: inferContext(sample),
            deviceId: sample.device?.localIdentifier ?? "unknown",
            percentileRank: calculatePercentile(hrvMs)
        )

        return Atom(
            uuid: UUID().uuidString,
            type: .hrvMeasurement,
            title: "HRV: \(Int(hrvMs))ms",
            body: nil,
            metadata: try? JSONEncoder().encode(metadata),
            createdAt: sample.startDate
        )
    }

    func convertSleepAnalysis(_ samples: [HKCategorySample]) async -> Atom {
        let analysis = analyzeSleepSamples(samples)

        let metadata = SleepCycleMetadata(
            sleepStart: analysis.startTime,
            sleepEnd: analysis.endTime,
            totalDuration: analysis.duration,
            deepSleepMinutes: analysis.deepMinutes,
            remSleepMinutes: analysis.remMinutes,
            coreSleepMinutes: analysis.coreMinutes,
            awakeMinutes: analysis.awakeMinutes,
            sleepEfficiency: analysis.efficiency,
            respiratoryRate: analysis.avgRespiratoryRate,
            heartRateDuringSleep: analysis.heartRateRange
        )

        return Atom(
            uuid: UUID().uuidString,
            type: .sleepCycle,
            title: "Sleep: \(formatDuration(analysis.duration))",
            body: generateSleepSummary(analysis),
            metadata: try? JSONEncoder().encode(metadata)
        )
    }

    func convertWorkout(_ workout: HKWorkout) async -> Atom {
        let metadata = WorkoutSessionMetadata(
            workoutType: mapWorkoutType(workout.workoutActivityType),
            duration: workout.duration,
            activeCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
            avgHeartRate: await fetchAvgHeartRate(during: workout),
            maxHeartRate: await fetchMaxHeartRate(during: workout),
            hrvRecovery: await fetchPostWorkoutHRV(workout),
            strainScore: calculateStrainScore(workout),
            elevationGain: workout.totalFlightsClimbed?.doubleValue(for: .count()),
            distance: workout.totalDistance?.doubleValue(for: .meter()),
            zones: await calculateHeartRateZones(during: workout)
        )

        return Atom(
            uuid: UUID().uuidString,
            type: .workoutSession,
            title: "\(workout.workoutActivityType.name) - \(formatDuration(workout.duration))",
            body: generateWorkoutSummary(workout, metadata),
            metadata: try? JSONEncoder().encode(metadata)
        )
    }
}
```

### Readiness Score Calculator

```swift
// MARK: - Readiness Calculator

class ReadinessCalculator {

    struct ReadinessInputs {
        let recentHRV: [Double]              // Last 7 days
        let baselineHRV: Double              // 30-day average
        let lastNightSleep: SleepCycleMetadata?
        let sleepConsistency: Double         // 0-100
        let recentWorkouts: [WorkoutSessionMetadata]
        let restingHR: Double
        let baselineRestingHR: Double
    }

    func calculateReadiness(_ inputs: ReadinessInputs) -> ReadinessScoreMetadata {
        // HRV contribution (40% weight)
        let hrvTrend = calculateHRVTrend(inputs.recentHRV, baseline: inputs.baselineHRV)
        let hrvScore = mapToScore(hrvTrend, range: -0.3...0.3)

        // Sleep contribution (30% weight)
        let sleepScore = calculateSleepScore(
            lastNight: inputs.lastNightSleep,
            consistency: inputs.sleepConsistency
        )

        // Recovery contribution (20% weight)
        let recoveryScore = calculateRecoveryScore(
            restingHR: inputs.restingHR,
            baseline: inputs.baselineRestingHR,
            recentStrain: inputs.recentWorkouts.map(\.strainScore)
        )

        // Strain balance (10% weight)
        let strainBalance = calculateStrainBalance(inputs.recentWorkouts)

        let overallScore = (
            hrvScore * 0.4 +
            sleepScore * 0.3 +
            recoveryScore * 0.2 +
            strainBalance * 0.1
        )

        return ReadinessScoreMetadata(
            date: Date(),
            overallScore: overallScore,
            hrvContribution: hrvScore,
            sleepContribution: sleepScore,
            recoveryContribution: recoveryScore,
            strainBalance: strainBalance,
            recommendation: generateRecommendation(overallScore)
        )
    }

    private func generateRecommendation(_ score: Double) -> ReadinessRecommendation {
        switch score {
        case 85...100:
            return .peakPerformance("You're primed for peak performance. Push hard today.")
        case 70..<85:
            return .goodToGo("Solid recovery. Normal training recommended.")
        case 50..<70:
            return .moderate("Recovery in progress. Light activity only.")
        case 30..<50:
            return .restRecommended("Your body needs rest. Focus on recovery.")
        default:
            return .restRequired("Critical recovery needed. Rest completely.")
        }
    }
}
```

---

# PART 3: GAMIFICATION ENGINE

## 3.1 Dopamine-Optimized Feedback Systems

### Psychology-Based XP Delivery

```swift
// MARK: - Gamification Psychology

/// Based on: Variable Ratio Reinforcement, Flow State Theory,
/// Self-Determination Theory, and Video Game Addiction Research

class GamificationEngine {

    // MARK: - Variable Ratio Rewards (Slot Machine Psychology)

    struct VariableRewardSystem {
        /// Randomly boost XP to create unpredictable rewards
        /// This is the most addictive reinforcement schedule
        static func applyVariableMultiplier(baseXP: Int) -> (xp: Int, bonusType: BonusType?) {
            let roll = Double.random(in: 0...1)

            switch roll {
            case 0..<0.70:    // 70% - Normal
                return (baseXP, nil)
            case 0.70..<0.85: // 15% - Small bonus
                return (Int(Double(baseXP) * 1.25), .luckyBonus)
            case 0.85..<0.95: // 10% - Medium bonus
                return (Int(Double(baseXP) * 1.5), .superBonus)
            case 0.95..<0.99: // 4% - Large bonus
                return (Int(Double(baseXP) * 2.0), .megaBonus)
            default:          // 1% - Jackpot
                return (baseXP * 3, .jackpot)
            }
        }

        enum BonusType: String {
            case luckyBonus = "Lucky Bonus!"
            case superBonus = "Super Bonus!"
            case megaBonus = "MEGA BONUS!"
            case jackpot = "JACKPOT!"
        }
    }

    // MARK: - Flow State Preservation

    struct FlowStateManager {
        /// Delays notifications during deep work to preserve flow
        /// Based on Csikszentmihalyi's Flow research

        static func shouldDeliverNotification(
            currentActivity: ActivityState,
            notificationType: NotificationType
        ) -> DeliveryDecision {

            switch currentActivity {
            case .deepWork(let minutesIn):
                if minutesIn < 45 {
                    // Never interrupt first 45 minutes
                    return .defer(until: .deepWorkEnd)
                } else {
                    // Only critical after 45 min
                    return notificationType.isCritical ? .deliver : .defer(until: .deepWorkEnd)
                }

            case .writing(let wordsSinceLast):
                if wordsSinceLast < 200 {
                    return .defer(until: .naturalPause)
                }
                return .deliver

            case .idle:
                return .deliver
            }
        }
    }

    // MARK: - Competence Building (Self-Determination Theory)

    struct CompetenceSystem {
        /// Ensures users feel growing mastery
        /// Difficulty scaling based on current level

        static func calibrateChallenges(
            dimension: LevelDimension,
            currentLevel: Int,
            recentPerformance: [Double]
        ) -> ChallengeSettings {

            let avgPerformance = recentPerformance.reduce(0, +) / Double(recentPerformance.count)

            // Optimal challenge: 80-85% success rate
            let targetDifficulty: Double
            if avgPerformance > 0.90 {
                targetDifficulty = 1.15  // Increase challenge
            } else if avgPerformance < 0.75 {
                targetDifficulty = 0.85  // Decrease challenge
            } else {
                targetDifficulty = 1.0   // Maintain
            }

            return ChallengeSettings(
                difficultyMultiplier: targetDifficulty,
                suggestedGoals: generateGoals(dimension, level: currentLevel, difficulty: targetDifficulty)
            )
        }
    }

    // MARK: - Loss Aversion Mechanics

    struct LossAversionEngine {
        /// NELO regression creates urgency without being punitive
        /// Based on Kahneman's Prospect Theory (losses hurt 2x more than equivalent gains)

        static func calculateRegressionImpact(
            currentNELO: Int,
            potentialLoss: Int,
            streakAtRisk: Int
        ) -> RegressionWarning {

            // Show warning when streak or NELO at risk
            let urgencyLevel: UrgencyLevel

            if streakAtRisk >= 30 {
                urgencyLevel = .critical  // Major streak at risk
            } else if potentialLoss > 50 {
                urgencyLevel = .high      // Significant NELO drop
            } else if streakAtRisk >= 7 {
                urgencyLevel = .moderate  // Week streak at risk
            } else {
                urgencyLevel = .low
            }

            return RegressionWarning(
                urgency: urgencyLevel,
                message: generateWarningMessage(urgencyLevel, streakAtRisk, potentialLoss),
                suggestedAction: generateSuggestedAction(urgencyLevel)
            )
        }
    }

    // MARK: - Social Proof (Future: Leaderboards)

    struct SocialProofSystem {
        /// Percentile rankings create competition without toxicity

        static func calculatePercentile(
            metric: String,
            value: Double,
            population: PercentileData
        ) -> PercentileRank {
            // Compare against anonymized population data
            // Future: opt-in leaderboards
        }
    }

    // MARK: - Milestone Celebrations

    struct CelebrationEngine {
        /// Creates memorable moments for achievements
        /// Based on peak-end rule (Kahneman)

        static func triggerCelebration(
            achievement: Achievement,
            context: CelebrationContext
        ) {
            switch achievement.tier {
            case .bronze:
                // Subtle haptic + small animation
                CosmicHaptics.impact(.light)
                // Small confetti burst

            case .silver:
                // Medium haptic + sound + animation
                CosmicHaptics.impact(.medium)
                // Moderate celebration animation

            case .gold:
                // Full celebration sequence
                CosmicHaptics.notification(.success)
                // Full confetti + particle effects
                // 3-second takeover animation

            case .platinum, .diamond:
                // Epic celebration
                CosmicHaptics.impactSequence([.heavy, .light, .heavy])
                // Full-screen takeover
                // Custom animation sequence
                // Optional: save celebration as memory atom

            case .obsidian:
                // Legendary - secret unlocked
                // Special "legendary" animation
                // Permanent profile flair unlocked
            }
        }
    }
}
```

### Daily Quest System

```swift
// MARK: - Daily Quests

class DailyQuestEngine {

    struct DailyQuests {
        let date: Date
        var mainQuest: Quest           // Primary focus
        var sideQuests: [Quest]        // 3-5 additional
        var bonusQuest: Quest?         // Hidden until unlocked
    }

    struct Quest: Identifiable, Codable {
        let id: String
        let title: String
        let description: String
        let dimension: LevelDimension
        let requirement: QuestRequirement
        let xpReward: Int
        let bonusXP: Int?              // For exceeding target
        var progress: Double           // 0-1
        var isComplete: Bool
    }

    enum QuestRequirement: Codable {
        case deepWorkMinutes(target: Int)
        case wordsWritten(target: Int)
        case tasksCompleted(target: Int)
        case journalEntry
        case hrvMeasurement
        case sleepTargetMet
        case workoutCompleted(minutes: Int)
        case researchAdded(count: Int)
        case connectionsCreated(count: Int)
        case routineBlocks(count: Int)
    }

    func generateDailyQuests(
        for user: UserProfile,
        levels: CosmoLevelSystem,
        recentPerformance: PerformanceSnapshot
    ) -> DailyQuests {

        // Main quest: Focus on weakest dimension or user's priority
        let weakestDimension = levels.dimensions.min { $0.value.level < $1.value.level }?.key
        let mainQuest = generateMainQuest(dimension: weakestDimension, level: levels)

        // Side quests: Mix of dimensions, calibrated to level
        let sideQuests = generateSideQuests(levels: levels, performance: recentPerformance)

        // Bonus quest: Hidden, unlocked by completing all others
        let bonusQuest = Quest(
            id: "bonus_\(Date().formatted(.iso8601))",
            title: "Overachiever",
            description: "Complete all daily quests to unlock",
            dimension: .cognitive,
            requirement: .deepWorkMinutes(target: 30),  // Extra challenge
            xpReward: 200,
            bonusXP: nil,
            progress: 0,
            isComplete: false
        )

        return DailyQuests(
            date: Date(),
            mainQuest: mainQuest,
            sideQuests: sideQuests,
            bonusQuest: bonusQuest
        )
    }
}
```

---

# PART 4: VOICE COMMAND INTEGRATION

## 4.1 Level System Voice Commands

Extend the existing VoiceCommandPipeline to support leveling:

```swift
// MARK: - Level System Voice Commands

extension PatternMatcher {

    static let levelPatterns: [VoicePattern] = [
        // Status queries
        VoicePattern(
            regex: #"(?:what('s| is) my|show me my|check my) (level|xp|score|progress)"#,
            action: .showLevelStatus
        ),
        VoicePattern(
            regex: #"(?:what('s| is) my|show) (cosmo index|ci|nelo|rating)"#,
            action: .showCosmoIndex
        ),
        VoicePattern(
            regex: #"how am I doing (?:in |on |with )?(cognitive|creative|health|behavioral|knowledge|reflection)?"#,
            action: .showDimensionStatus(dimension: .fromCapture)
        ),

        // Streak queries
        VoicePattern(
            regex: #"(?:what('s| is) my|show me my|check my) streak"#,
            action: .showStreak
        ),
        VoicePattern(
            regex: #"how long (?:is |have I )?(?:been |kept )?(?:my )?streak"#,
            action: .showStreak
        ),

        // Badge queries
        VoicePattern(
            regex: #"(?:show me my|what are my|list my) badges"#,
            action: .showBadges
        ),
        VoicePattern(
            regex: #"what badges (?:can I|do I need to) unlock"#,
            action: .showNextBadges
        ),

        // XP queries
        VoicePattern(
            regex: #"how much xp (?:did I|have I) (?:earn|gain|get)(?:ed)? today"#,
            action: .showDailyXP
        ),
        VoicePattern(
            regex: #"(?:what|how much) xp (?:do I need |until |to )(?:level up|next level)"#,
            action: .showXPToNextLevel
        ),

        // Deep work commands (XP-generating)
        VoicePattern(
            regex: #"start(?:ing)? (?:a )?deep work(?: block| session)?"#,
            action: .startDeepWork
        ),
        VoicePattern(
            regex: #"(?:end|finish|stop|complete) deep work"#,
            action: .endDeepWork
        ),

        // Health logging
        VoicePattern(
            regex: #"log(?:ging)? (?:my )?workout"#,
            action: .logWorkout
        ),
        VoicePattern(
            regex: #"(?:check|show|what('s| is)) my readiness"#,
            action: .showReadiness
        ),
        VoicePattern(
            regex: #"(?:check|show|what('s| is)) my hrv"#,
            action: .showHRV
        ),

        // Daily summary
        VoicePattern(
            regex: #"(?:give me|show me|what's) (?:my )?daily (?:summary|report|review)"#,
            action: .showDailySummary
        ),
        VoicePattern(
            regex: #"how (?:did|was) my day"#,
            action: .showDailySummary
        ),
    ]
}
```

---

# PART 5: DAILY CRON ENGINE

## 5.1 Midnight Processing Pipeline

```swift
// MARK: - Daily Cron Engine

actor DailyCronEngine {

    private let atomRepository: AtomRepository
    private let levelEngine: LevelCalculationEngine
    private let healthKit: HealthKitAtomFactory
    private let notificationService: ProactiveNotificationService

    /// Runs at midnight local time
    func executeDailyCron() async throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let dateRange = Calendar.current.startOfDay(for: yesterday)...Calendar.current.startOfDay(for: Date())

        // 1. Pull all atoms from last 24 hours
        let dailyAtoms = try await atomRepository.fetchAtoms(in: dateRange)

        // 2. Pull health data from HealthKit
        let healthAtoms = try await healthKit.fetchAndConvertDailyHealth(for: yesterday)
        await atomRepository.saveAtoms(healthAtoms)

        // 3. Calculate metrics for each dimension
        let dimensionMetrics = await calculateDimensionMetrics(
            atoms: dailyAtoms + healthAtoms,
            date: yesterday
        )

        // 4. Calculate XP for each dimension
        let xpEvents = await calculateDailyXP(metrics: dimensionMetrics)
        await atomRepository.saveAtoms(xpEvents)

        // 5. Update Cosmo Index (CI)
        let ciUpdates = await updateCosmoIndex(xpEvents: xpEvents)
        if !ciUpdates.isEmpty {
            await atomRepository.saveAtoms(ciUpdates)
        }

        // 6. Update Neuro-ELO (NELO) with regression checks
        let neloUpdates = await updateNELO(metrics: dimensionMetrics, date: yesterday)
        await atomRepository.saveAtoms(neloUpdates)

        // 7. Check for regressions and trigger warnings
        let regressionWarnings = await checkRegressions(neloUpdates: neloUpdates)

        // 8. Create dimension snapshot atom
        let snapshot = await createDimensionSnapshot(date: yesterday, metrics: dimensionMetrics)
        await atomRepository.saveAtom(snapshot)

        // 9. Update streaks
        let streakUpdates = await updateStreaks(atoms: dailyAtoms)
        await atomRepository.saveAtoms(streakUpdates)

        // 10. Check badge unlocks
        let badgeUnlocks = await checkBadgeUnlocks()
        await atomRepository.saveAtoms(badgeUnlocks)

        // 11. Create daily summary atom
        let summary = await createDailySummary(
            date: yesterday,
            atoms: dailyAtoms,
            xpEvents: xpEvents,
            streakUpdates: streakUpdates,
            badgeUnlocks: badgeUnlocks
        )
        await atomRepository.saveAtom(summary)

        // 12. Schedule morning notification with summary
        await notificationService.scheduleMorningSummary(summary)

        // 13. Generate daily quests for today
        await generateTodaysQuests()
    }

    private func calculateDimensionMetrics(atoms: [Atom], date: Date) async -> [LevelDimension: DimensionDailyMetrics] {
        var metrics: [LevelDimension: DimensionDailyMetrics] = [:]

        // Cognitive
        metrics[.cognitive] = DimensionDailyMetrics(
            wordsWritten: atoms.filter { $0.type == .writingSession }
                .compactMap { try? JSONDecoder().decode(WritingSessionMetadata.self, from: $0.metadata!) }
                .reduce(0) { $0 + $1.wordCount },
            tasksCompleted: atoms.filter { $0.type == .task && $0.isCompleted }.count,
            deepWorkMinutes: atoms.filter { $0.type == .deepWorkBlock }
                .compactMap { try? JSONDecoder().decode(DeepWorkBlockMetadata.self, from: $0.metadata!) }
                .reduce(0) { $0 + Int($1.duration / 60) },
            contentPiecesCreated: atoms.filter { $0.type == .content && wasCreatedToday($0, date) }.count
        )

        // Similar calculations for other dimensions...

        return metrics
    }
}
```

---

# PART 6: JOURNALING PIPELINE

## 6.1 Voice-First Journal Capture

```swift
// MARK: - Journal Router

class JournalRouter {

    enum InputClassification {
        case command(ParsedAction)      // Quick action
        case capture(CaptureType)       // Brief note to store
        case journal(JournalType)       // Reflective entry
    }

    struct ClassificationSignals {
        let length: Int
        let sentenceCount: Int
        let hasReflectiveLanguage: Bool     // "I feel", "I think", "here's what"
        let hasCommandLanguage: Bool        // "create", "add", "schedule"
        let pausePatterns: [TimeInterval]   // Pauses during speech
        let emotionalIntensity: Double      // Sentiment analysis
        let timeOfDay: TimeOfDay
    }

    func classify(_ transcript: String, signals: ClassificationSignals) -> InputClassification {
        // Rule-based classification with ML fallback

        // Quick command check (highest priority)
        if signals.hasCommandLanguage && signals.length < 50 {
            return .command(parseCommand(transcript))
        }

        // Journal indicators
        let journalIndicators = [
            signals.hasReflectiveLanguage,
            signals.sentenceCount >= 3,
            signals.length > 200,
            signals.pausePatterns.contains { $0 > 2.0 },  // Thoughtful pauses
            signals.emotionalIntensity > 0.5,
        ]

        let journalScore = Double(journalIndicators.filter { $0 }.count) / Double(journalIndicators.count)

        if journalScore >= 0.6 {
            return .journal(classifyJournalType(transcript, signals))
        }

        // Default to capture
        return .capture(classifyCaptureType(transcript))
    }
}
```

### Journal Processing Pipeline

```swift
// MARK: - Journal Processor

actor JournalProcessor {

    private let llm: LocalLLM
    private let atomRepository: AtomRepository

    struct ProcessedJournal {
        let originalAtom: Atom
        let segments: [JournalSegment]
        let extractedInsights: [JournalInsight]
        let suggestedActions: [SuggestedAction]
        let emotionalAnalysis: EmotionalAnalysis
        let clarityScore: ClarityScoreMetadata
    }

    struct JournalSegment: Codable {
        let text: String
        let type: SegmentType
        let startIndex: Int
        let endIndex: Int
        let suggestedDestination: AtomType?
    }

    enum SegmentType: String, Codable {
        case reflection         // Pure reflection, stays in journal
        case task               // Could become task atom
        case idea               // Could become idea atom
        case goal               // Could become project/arc
        case insight            // Extract as insight atom
        case gratitude          // Tag for gratitude tracking
        case worry              // Tag for worry pattern tracking
    }

    func processJournal(_ journalAtom: Atom) async -> ProcessedJournal {
        let text = journalAtom.body ?? ""

        // 1. Segment the journal using LLM
        let segments = await segmentJournal(text)

        // 2. Extract insights
        let insights = await extractInsights(text, segments: segments)

        // 3. Analyze emotional content
        let emotions = await analyzeEmotions(text)

        // 4. Calculate clarity score
        let clarityScore = await calculateClarity(text, segments: segments)

        // 5. Generate suggested actions (non-automatic)
        let suggestions = await generateSuggestions(segments, insights: insights)

        return ProcessedJournal(
            originalAtom: journalAtom,
            segments: segments,
            extractedInsights: insights,
            suggestedActions: suggestions,
            emotionalAnalysis: emotions,
            clarityScore: clarityScore
        )
    }

    /// User must approve before atoms are created from journal
    func executeApprovedSuggestions(
        _ suggestions: [SuggestedAction],
        from processed: ProcessedJournal
    ) async {
        for suggestion in suggestions where suggestion.isApproved {
            switch suggestion.action {
            case .createTask(let title, let details):
                let taskAtom = Atom.createTask(
                    title: title,
                    body: details,
                    links: [.init(type: .causedBy, targetUUID: processed.originalAtom.uuid)]
                )
                await atomRepository.saveAtom(taskAtom)

            case .createIdea(let title, let content):
                let ideaAtom = Atom.createIdea(
                    title: title,
                    body: content,
                    links: [.init(type: .causedBy, targetUUID: processed.originalAtom.uuid)]
                )
                await atomRepository.saveAtom(ideaAtom)

            case .linkToExisting(let targetUUID, let linkType):
                await atomRepository.addLink(
                    from: processed.originalAtom.uuid,
                    to: targetUUID,
                    type: linkType
                )
            }
        }
    }
}
```

---

# PART 7: CONTENT PIPELINE

## 7.1 Content Lifecycle Tracking

```swift
// MARK: - Content Pipeline

class ContentPipelineEngine {

    enum ContentPhase: String, Codable, CaseIterable {
        case ideation       // Initial concept
        case outline        // Structure defined
        case draft          // First draft
        case polish         // Editing/refining
        case scheduled      // Ready for publish
        case published      // Live
        case analyzing      // Gathering performance data
        case archived       // Historical
    }

    struct ContentItem {
        let contentAtom: Atom
        var currentPhase: ContentPhase
        var phaseHistory: [PhaseTransition]
        var performanceData: ContentPerformanceMetadata?
        var linkedAtoms: [AtomLink]        // Research, ideas used
        var clientProfile: ClientProfile?  // For ghostwriting
    }

    struct PhaseTransition: Codable {
        let from: ContentPhase
        let to: ContentPhase
        let timestamp: Date
        let wordCount: Int
        let timeSpentSeconds: Int
    }

    // MARK: - Performance Matching

    /// Matches published content to Cosmo-tracked drafts
    func matchPublishedContent(
        publishedPost: SocialMediaPost,
        candidates: [ContentItem]
    ) -> ContentItem? {
        // Matching criteria:
        // 1. Timestamp ±24 hours of draft completion
        // 2. Content similarity via embeddings (>0.85 threshold)
        // 3. Client ID match (if applicable)
        // 4. Media type match

        for candidate in candidates {
            let timeDelta = abs(publishedPost.publishedAt.timeIntervalSince(candidate.lastPhaseTransition.timestamp))
            guard timeDelta < 86400 else { continue }  // 24 hours

            let similarity = calculateEmbeddingSimilarity(
                candidate.contentAtom.body ?? "",
                publishedPost.text
            )
            guard similarity > 0.85 else { continue }

            if let clientId = candidate.clientProfile?.clientId,
               clientId == publishedPost.accountId {
                return candidate
            }

            // No client or client matched
            return candidate
        }

        return nil
    }

    // MARK: - Performance Tracking

    func updatePerformanceMetrics(
        for contentItem: inout ContentItem,
        with post: SocialMediaPost
    ) {
        let metrics = ContentPerformanceMetadata(
            platform: post.platform,
            postId: post.id,
            publishedAt: post.publishedAt,
            impressions: post.impressions,
            reach: post.reach,
            engagement: post.totalEngagement,
            likes: post.likes,
            comments: post.comments,
            shares: post.shares,
            saves: post.saves,
            profileVisits: post.profileVisits,
            followsGained: post.followsGained,
            engagementRate: post.engagementRate,
            viralityScore: calculateViralityScore(post),
            isViral: isViral(post),
            lastUpdated: Date()
        )

        contentItem.performanceData = metrics

        // Create performance atom linked to content
        let perfAtom = Atom(
            uuid: UUID().uuidString,
            type: .contentPerformance,
            title: "Performance: \(contentItem.contentAtom.title ?? "Untitled")",
            metadata: try? JSONEncoder().encode(metrics),
            links: [.init(type: .parent, targetUUID: contentItem.contentAtom.uuid)]
        )

        Task {
            await atomRepository.saveAtom(perfAtom)
        }
    }

    private func isViral(_ post: SocialMediaPost) -> Bool {
        // Platform-specific virality thresholds
        switch post.platform {
        case .twitter:
            return post.impressions > 100_000 || post.engagementRate > 0.05
        case .linkedin:
            return post.impressions > 50_000 || post.engagementRate > 0.03
        case .instagram:
            return post.reach > 10 * post.followerCount || post.saves > 500
        case .tiktok:
            return post.views > 100_000 || post.shares > 1000
        default:
            return false
        }
    }
}
```

---

# PART 8: LOCAL MODEL ARCHITECTURE

## 8.1 Current Hardware Configuration (M4 16GB)

```swift
// MARK: - Model Configuration

struct LocalModelConfiguration {

    // CURRENT: M4 MacBook Pro 16GB
    struct Current {
        // Voice Processing
        static let whisperModel = "whisper-large-v3-turbo"  // ~1.5GB
        static let streamingASR = "qwen3-asr-flash"         // ~500MB

        // Intent Classification
        static let intentModel = "qwen2.5-0.5b-ft"          // ~300MB (fine-tuned)

        // Main LLM (via XPC Daemon)
        static let primaryLLM = "hermes-3-llama-3.2-3b-q4"  // ~2GB

        // Embeddings
        static let embeddingModel = "nomic-embed-text-v1.5" // ~300MB

        // Total VRAM: ~4.5GB (leaves headroom for system)

        // Fallback for complex tasks
        static let cloudFallback = "anthropic/claude-sonnet" // Via OpenRouter
    }

    // FUTURE: M3 Ultra 512GB
    struct Future {
        // Voice Processing
        static let whisperModel = "whisper-large-v3"        // ~3GB
        static let streamingASR = "qwen3-asr-large"         // ~2GB

        // Main LLMs (Mixture of Experts)
        static let routerModel = "mixtral-8x7b-router"      // Router
        static let expertModels = [
            "llama-3.3-70b-q4",      // ~40GB - General reasoning
            "deepseek-coder-33b",    // ~20GB - Code
            "qwen2.5-72b-instruct",  // ~45GB - Instructions
            "phi-4-14b",             // ~10GB - Fast reasoning
        ]

        // Embeddings
        static let embeddingModel = "nomic-embed-text-v2"   // Full precision

        // Vision
        static let visionModel = "llava-1.6-34b"            // ~20GB

        // Total VRAM usage: ~140GB (leaves 370GB for context/batch)
    }
}
```

## 8.2 Model Routing Strategy

```swift
// MARK: - Intelligent Model Router

class ModelRouter {

    enum TaskComplexity {
        case trivial        // Pattern matching, simple lookups
        case simple         // Single-step reasoning
        case moderate       // Multi-step, needs context
        case complex        // Synthesis, analysis
        case generative     // Long-form creation
    }

    func routeTask(
        _ task: AITask,
        complexity: TaskComplexity,
        latencyRequirement: LatencyRequirement,
        hardware: HardwareProfile
    ) -> ModelSelection {

        switch (complexity, latencyRequirement, hardware.isUltra) {
        // Current Hardware (M4 16GB)
        case (.trivial, _, false):
            return .pattern  // No model needed

        case (.simple, .realtime, false):
            return .local(model: "qwen2.5-0.5b")

        case (.moderate, _, false):
            return .local(model: "hermes-3-llama-3.2-3b")

        case (.complex, _, false), (.generative, _, false):
            return .cloud(model: "claude-sonnet", via: .openRouter)

        // Future Hardware (M3 Ultra 512GB)
        case (.trivial, _, true):
            return .pattern

        case (.simple, .realtime, true):
            return .local(model: "phi-4-14b")

        case (.moderate, _, true):
            return .local(model: "llama-3.3-70b")

        case (.complex, _, true):
            return .moe(router: "mixtral-router", experts: ["llama-70b", "qwen-72b"])

        case (.generative, _, true):
            return .local(model: "qwen2.5-72b-instruct")
        }
    }
}
```

---

# PART 9: THE SANCTUARY - NEURAL INTERFACE DASHBOARD

The Sanctuary is not a dashboard. It's a **neural interface visualization of your Atom graph** - a living, breathing representation of your entire life system. Every pixel is data. Every animation is feedback. Every correlation is a truth extracted from your own patterns.

## 9.1 Core Interaction Model

### Entry Animation (Clicking the Level Orb)

When the user clicks the top-left Level Orb:

- **DO NOT** open a new page
- **DO NOT** slide in a sidebar
- **Instead:** Sanctuary materializes from behind reality

```
ENTRY SEQUENCE (0.4s total):
├── 0.00s: Canvas fades (opacity 1.0 → 0.3)
├── 0.00s: Canvas z-translates (0 → -100pt)
├── 0.00s: Canvas blur begins (0 → 15pt Gaussian)
├── 0.08s: Sanctuary container fades in
├── 0.12s: Hero Orb scales up (0.8 → 1.0, spring damping: 0.7)
├── 0.18s: Dimension orbs stagger in (40ms each)
├── 0.35s: Particle field activates
└── 0.40s: Causality lines draw in

EXIT SEQUENCE (0.3s total):
├── 0.00s: Causality lines fade
├── 0.05s: Dimension orbs scale down (reverse stagger)
├── 0.10s: Hero Orb exits
├── 0.15s: Sanctuary container fades
├── 0.20s: Canvas blur clears
└── 0.30s: Canvas fully restored
```

### Core Layout

```
┌─────────────────────────────────────────────────────────────────┐
│                     SANCTUARY OVERLAY                            │
│                                                                  │
│                        ○ Reflection                              │
│                   ○                    ○                         │
│               Knowledge            Cognitive                     │
│                                                                  │
│                         ┌───────┐                                │
│                         │ HERO  │                                │
│                         │  ORB  │                                │
│                         │ L.42  │                                │
│                         └───────┘                                │
│                                                                  │
│                Behavioral           Creative                     │
│                   ○                    ○                         │
│                        ○ Physiological                           │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Live: HRV 78ms ↑ │ Today: +342 XP │ Streak: 47 days    │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## 9.2 The Causality Engine

### Core Architecture

The Causality Engine is the brain of Sanctuary. It discovers patterns across ALL Atom types using a **90-day rolling window**.

```swift
actor CausalityComputeEngine {

    // CRITICAL: Uses 90-day rolling window, NOT 24 hours
    static let correlationWindow: Int = 90  // days

    // Triggered by: MidnightCron (daily batch processing)
    // NOT triggered by: Opening Sanctuary, minor data updates

    func computeDailyCorrelations() async throws {
        // 1. Fetch ALL Atoms from last 90 days
        let window = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let allAtoms = try await atomRepository.fetchAtoms(since: window)

        // 2. Aggregate into structured metrics (see Data Volume section)
        let metrics = aggregateToCorrelationMetrics(allAtoms)

        // 3. Run correlation analysis (local or cloud)
        let correlations = try await analyzeCorrelations(metrics)

        // 4. Generate/update causalityInsight Atoms
        let insights = generateInsights(from: correlations)

        // 5. Store as Atoms (cached until next daily run)
        try await storeInsightAtoms(insights)
    }
}
```

### New Atom Types for Causality

```swift
enum AtomType {
    // ... existing types ...

    // NEW: Causality System
    case causalityInsight      // Discovered correlation between dimensions
    case correlationSnapshot   // Point-in-time correlation matrix
    case liveMetricCache       // Cached computed metrics for instant load
    case dimensionRelationship // Tracked cause-effect pairs
}

struct CausalityInsightMetadata: Codable {
    let sourceDimension: LevelDimension
    let targetDimension: LevelDimension
    let sourceMetric: String
    let targetMetric: String
    let relationship: RelationshipType  // .positive, .negative, .threshold
    let lagDays: Int                     // 0-7 day delay effect
    let confidenceScore: Double          // 0.0 - 1.0 (must be > 0.70)
    let occurrenceCount: Int             // Must be >= 5
    let effectSize: Double               // Percentage change (must be > 10%)
    let humanReadableInsight: String
    let lastValidated: Date
    let contradictionCount: Int          // Decay if > 5
}
```

### Smart Caching Strategy

| Data Type | Cache Duration | Invalidation Trigger |
|-----------|---------------|---------------------|
| Dimension levels | 5 minutes | New XP event |
| Correlation insights | 24 hours | MidnightCron recompute |
| HRV/Health metrics | Real-time stream | N/A (always live) |
| Historical graphs | 1 hour | New data in range |
| Causality relationships | Until contradicted | Pattern break detected |

### Insight Lifecycle

```
1. RAW DATA → Atoms created (HRV, posts, deep work, journals, etc.)
2. AGGREGATION → MidnightCron aggregates 90-day window
3. DETECTION → CausalityEngine scans for statistical patterns
4. VALIDATION → Pattern must appear 5+ times with >70% consistency
5. STORAGE → causalityInsight Atom created with confidence score
6. DISPLAY → Sanctuary shows insight with "strength" indicator
7. MONITORING → Each new day validates or contradicts pattern
8. DECAY → If contradicted 5+ times, confidence decreases
9. REMOVAL → Insight removed when confidence < 0.50
```

## 9.3 Complete Correlation Matrix

### Every Extractable Metric from Every Atom Type

The Causality Engine analyzes ALL of these metrics across the 90-day window:

#### Physiology Atoms (HealthKit)

| Atom Type | Metrics Extracted |
|-----------|------------------|
| `hrvMeasurement` | hrvMs, time of day, day of week, vs personal baseline |
| `restingHR` | bpm, trend (rising/falling), vs baseline |
| `sleepCycle` | total duration, deep sleep %, REM %, efficiency, latency, wake count |
| `sleepConsistency` | bedtime variance, wake time variance |
| `readinessScore` | overall (0-100), HRV component, sleep component |
| `workoutSession` | type, duration, calories, avg HR, max HR, strain, time of day |
| `bloodOxygen` | SpO2 %, deviation from baseline |
| `bodyTemperature` | deviation from baseline |

#### Cognitive Atoms

| Atom Type | Metrics Extracted |
|-----------|------------------|
| `deepWorkBlock` | duration, focus score, time of day, interrupted (yes/no) |
| `writingSession` | word count, net words, WPM, duration, time of day |
| `focusScore` | score (0-100), session context |
| `distractionEvent` | count per session, type |
| `task` | completed (yes/no), time to complete, priority, overdue |

#### Content Pipeline Atoms

| Atom Type | Metrics Extracted |
|-----------|------------------|
| `content` | phase, word count, time in each phase |
| `contentDraft` | version count, words added per version |
| `contentPublish` | platform, time of day, day of week |
| `contentPerformance` | impressions, engagement, viral score, vs personal avg |

#### Reflection Atoms (Including Semantic Analysis)

| Atom Type | Metrics Extracted |
|-----------|------------------|
| `journalEntry` | word count, time of day, **semantic content** (see below) |
| `journalInsight` | insight type (goal/fear/belief/pattern/gratitude/lesson) |
| `emotionalState` | valence (-1 to +1), arousal, specific emotion labels |
| `clarityScore` | clarity (0-100), coherence, actionability |

#### Knowledge Atoms

| Atom Type | Metrics Extracted |
|-----------|------------------|
| `idea` | word count, connection count, time of day created |
| `research` | source type, topic cluster, consumption time |
| `semanticCluster` | cluster size, growth rate |
| `connectionLink` | cross-cluster (yes/no) |

#### Behavioral Atoms

| Atom Type | Metrics Extracted |
|-----------|------------------|
| `streakEvent` | streak type, current length, broken (yes/no) |
| `xpEvent` | amount, source dimension, time of day |
| `routineDefinition` | adherence %, which steps skipped |

### Journal Semantic Extraction

Journals aren't just "did they write" - it's WHAT they wrote:

```swift
struct JournalSemanticAnalysis: Codable {
    // Topic Detection
    let topicsMentioned: [JournalTopic]  // work, family, health, money, creativity...

    // Emotional Content
    let emotionalValence: Double         // -1 (negative) to +1 (positive)
    let dominantEmotions: [String]       // anxious, grateful, excited, frustrated...

    // Named Entities (anonymized for correlation)
    let peopleMentioned: [String]        // "Mom", "boss", "partner"

    // Goal/Fear Detection
    let goalsExpressed: [String]
    let fearsExpressed: [String]
    let gratitudeExpressions: Int

    // Cognitive Patterns
    let futureOriented: Bool
    let problemSolving: Bool
    let venting: Bool
    let planning: Bool

    // Recurring Themes (tracked over time)
    let recurringTheme: String?
}

enum JournalTopic: String, Codable, CaseIterable {
    case work, career
    case family, relationships
    case health, fitness
    case money, finances
    case creativity, projects
    case spirituality, meaning
    case stress, anxiety
    case gratitude, positivity
}
```

### Correlation Categories

#### Category 1: Health ↔ Everything

```
HRV correlations:
├── HRV ↔ Deep work duration (same day, +1d, +2d, +3d)
├── HRV ↔ Journal emotional valence
├── HRV ↔ Workout intensity (recovery effect)
├── HRV ↔ Sleep duration & deep %
├── HRV ↔ Content performance (stress indicator)
├── HRV ↔ Task completion rate
├── HRV ↔ Journal topics (does writing about stress lower HRV?)
├── HRV ↔ Gratitude expressions (does gratitude improve HRV?)
└── HRV ↔ People mentioned (do certain relationships affect HRV?)

Sleep correlations:
├── Sleep duration ↔ Next-day word count
├── Sleep quality ↔ Next-day focus score
├── Deep sleep % ↔ Creative output (ideas generated)
├── Sleep latency ↔ Evening screen time / late publishing
├── Sleep consistency ↔ Week-over-week productivity trend
└── Sleep ↔ Workout timing (morning vs evening)
```

#### Category 2: Productivity ↔ Everything

```
Deep work correlations:
├── Duration ↔ Word quality (engagement on resulting content)
├── Time of day ↔ Output quality
├── Interrupted vs uninterrupted ↔ Completion rate
├── Pre-deep-work activity ↔ Focus score
├── Post-deep-work HRV ↔ Session intensity
└── Deep work + research ↔ Idea quality

Writing correlations:
├── Words per day ↔ Content performance
├── Writing time ↔ Engagement rate
├── Draft iterations ↔ Virality
├── Research before writing ↔ Post depth
└── Journaling before writing ↔ Clarity
```

#### Category 3: Content ↔ Everything

```
Content performance correlations:
├── Publish time of day ↔ Engagement
├── Publish day of week ↔ Reach
├── HRV on publish day ↔ Content quality
├── Sleep before publish ↔ Performance
├── Deep work hours before content ↔ Engagement
├── Research consumed ↔ Post depth/shares
├── Emotional state when writing ↔ Audience response
└── Thread vs single ↔ Virality rate
```

#### Category 4: Reflection ↔ Everything

```
Journal correlations:
├── Journaling ↔ Next-day HRV
├── Journal emotional valence ↔ Week performance
├── Gratitude count ↔ HRV trend
├── Problem-solving journals ↔ Task completion
├── Morning vs evening journal ↔ Day outcomes
└── Journal topics ↔ Life outcomes
    ├── Writing about goals ↔ Goal achievement rate
    ├── Writing about fears ↔ Anxiety resolution
    └── Writing about relationships ↔ Emotional stability
```

### Multi-Factor Correlations (The Mind-Blowing Ones)

```
1. "The Compound Day"
   Sleep 7+ hrs + Morning workout + Journal + Deep work > 2hrs
   → What happens to content performance 2 days later?

2. "The Burnout Predictor"
   Deep work > 4hrs for 3+ days + No workout + Declining HRV
   → Predict productivity crash before it happens

3. "The Viral Formula"
   Research 2 days before + Morning publish + High HRV + Thread format
   → 3x engagement on content

4. "The Creativity Catalyst"
   Run + Shower + Journal + Research → Idea explosion?

5. "The Relationship Effect"
   When journaling about [person X], what happens to:
   Sleep quality, HRV, productivity next 3 days?

6. "The Gratitude Multiplier"
   3+ gratitude expressions in journal →
   Next 7 days: HRV, productivity, content performance

7. "Your Personal Peak Performance State"
   What specific combination predicts your best days?
```

## 9.4 Data Volume & Cloud Model Integration

### 90-Day Data Volume

| Category | Metrics | Data Points |
|----------|---------|-------------|
| Physiology | 12 metrics | ~1,080 |
| Cognitive | 8 metrics | ~720 |
| Content | 10 metrics | ~300 |
| Reflection | 15+ semantic features | ~900 |
| Knowledge | 5 metrics | ~450 |
| Behavioral | 6 metrics | ~540 |
| **Total** | | **~4,000 data points** |

**Serialized size: ~30-50KB** — Trivial for cloud models.

### Cloud Model Correlation Prompt

```swift
func buildComprehensiveAnalysisPrompt(data: UserLifeData) -> String {
    """
    You are analyzing 90 days of comprehensive life data for pattern recognition.
    Find correlations that a human would NEVER notice themselves.

    == PHYSIOLOGICAL DATA ==
    Daily HRV (90 days): \(data.hrvTimeline)
    Daily resting HR: \(data.restingHRTimeline)
    Sleep (duration, deep%, efficiency): \(data.sleepTimeline)
    Workouts (type, duration, intensity): \(data.workoutTimeline)

    == COGNITIVE DATA ==
    Deep work (duration, focus score, time): \(data.deepWorkTimeline)
    Writing (words, duration, time): \(data.writingTimeline)
    Tasks (completed, overdue): \(data.taskTimeline)

    == CONTENT DATA ==
    Posts (platform, time, type): \(data.publishTimeline)
    Performance (impressions, engagement, virality): \(data.performanceTimeline)

    == REFLECTION DATA ==
    Journal entries with semantic analysis:
    \(data.journalSemanticTimeline)
    // Includes: topics, emotions, gratitude count, goals, fears, people mentioned

    == KNOWLEDGE DATA ==
    Research consumed: \(data.researchTimeline)
    Ideas generated: \(data.ideaTimeline)

    == BEHAVIORAL DATA ==
    Streaks: \(data.streakTimeline)
    Routine adherence: \(data.routineTimeline)

    == ANALYSIS REQUIREMENTS ==

    1. Find LAG correlations (X today → Y in 1-7 days)
    2. Find COMPOUND patterns (A + B + C → exceptional outcome)
    3. Find PERSONAL BASELINES (what's normal for THIS user)
    4. Find INFLECTION POINTS (what causes sudden changes)
    5. Find RECURRING THEMES in journals that predict outcomes
    6. Find the user's PEAK PERFORMANCE prerequisites
    7. Find EARLY WARNING signals for burnout/low periods
    8. Find which SPECIFIC ACTIONS have highest ROI

    Only report patterns with:
    - 5+ occurrences
    - 70%+ consistency
    - >10% effect size
    - Clear actionability

    Format as JSON with:
    - insight_text (human readable)
    - source_metrics (what was analyzed)
    - target_outcome (what was predicted)
    - lag_days (time delay if any)
    - confidence (0-1)
    - occurrence_count
    - effect_size (% change)
    - actionable_recommendation
    """
}
```

### Example Generated Insights

```
"When you journal about your family AND sleep 7+ hours,
your content engagement is 2.4x higher for the next 3 days."
Confidence: 84% | Occurrences: 17

"Your HRV peaks exactly 48 hours after completing a 90+ minute
deep work block. Shorter sessions don't have this effect."
Confidence: 91% | Occurrences: 34

"Posts published between 8-9am on days you worked out
outperform your average by 67%."
Confidence: 78% | Occurrences: 12

"Whenever you journal about [recurring fear X], your task
completion drops 40% for 2 days. Consider addressing this."
Confidence: 82% | Occurrences: 8

"Your most viral content follows this exact pattern:
Research → 2 day gap → Morning journal → Write → Publish next day"
Confidence: 76% | Occurrences: 6

"Writing about gratitude in your journal predicts
your HRV being 12% above baseline the next day."
Confidence: 86% | Occurrences: 28
```

## 9.5 Sanctuary UI Components

### Hero Orb (Center)

```
Size: 180pt diameter
Position: Center of Sanctuary
Content:
  - Level number (large, SF Rounded Bold)
  - "Cosmo Index" label (small, secondary)
  - XP progress ring (outer edge, 4pt stroke)
  - Pulsing glow (synced to HRV if available, else 1Hz)

Orbiting Elements:
  - 3-5 small particles = recent achievements
  - Orbit radius: 100pt, period: 8s
```

### Dimension Orbs (Surrounding)

```
Size: 64pt diameter
Position: Circle, radius 160pt from center
Distribution: 60° apart (6 orbs)

Order (clockwise from top):
  1. Cognitive (top)
  2. Creative (top-right)
  3. Physiological (bottom-right)
  4. Behavioral (bottom)
  5. Knowledge (bottom-left)
  6. Reflection (top-left)

Each orb contains:
  - Progress ring (Apple Fitness style)
  - Dimension icon (SF Symbol)
  - Glow intensity = today's progress %
  - Subtle pulse when receiving new data
```

### Dimension Detail View (On Tap)

```
┌─────────────────────────────────────────────────────────────┐
│  [← Back]                 DIMENSION NAME              [⚙️]  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              TIMELINE GRAPH (Primary)                │   │
│  │  Shows: Main metric over 90 days                     │   │
│  │  Overlay: Correlation highlights from other dims     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │  TODAY STAT  │ │  WEEK AVG    │ │  TREND       │        │
│  └──────────────┘ └──────────────┘ └──────────────┘        │
│                                                             │
│  ─────────────── CAUSALITY INSIGHTS ───────────────        │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 💡 "Your HRV peaks 2 days after completing deep     │   │
│  │    work blocks of 90+ minutes"                       │   │
│  │    Confidence: 87% • Based on 23 occurrences        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Live Metric Badges (Floating)

```
Position: Bottom of Sanctuary, corner-anchored
Updates: Real-time (where applicable)

Content:
├── Live HRV (if Watch connected)
├── Today's XP counter (increments on events)
├── Active streak count
└── Current activity (if in deep work/writing)
```

## 9.6 Metal Shader Requirements

### Required Shaders

| Shader | Purpose |
|--------|---------|
| `OrbSurface.metal` | Iridescent glass surface, internal glow based on score, touch ripples |
| `ParticleField.metal` | Floating particles color-coded by dimension, drift toward origin orb |
| `CausalityLine.metal` | Lines connecting correlated dimensions, pulse on correlation strength |
| `DepthBlur.metal` | Canvas fade-back effect, variable blur by z-position |

### Animation Micro-Interactions

| Gesture | Response |
|---------|----------|
| Hover on orb | Scale 1.02x, glow intensifies |
| Press on orb | Ripple from touch point, haptic tap |
| Drag on timeline | Smooth scrubbing, tooltips appear |
| Pinch on graph | Zoom time range (7 days ↔ 90 days) |
| Long press insight | Expand to show raw data sources |
| Swipe down in detail | Dismiss with velocity-based spring |

## 9.7 Edge Cases

### No Data Yet (New User)

```
Hero Orb: Level 1, empty XP ring
Dimension Orbs: All dim (10% glow)
Causality Lines: None
Insights: None

Message: "Your Sanctuary will come alive as you use CosmoOS.
          Start by completing a deep work session or logging a journal entry."
```

### Low Data Day

```
Orbs: Lower glow intensity
Particles: Sparse field
Insights: Show "Not enough data today" or fallback to weekly insights
```

### Heavy Data Day

```
Orbs: Maximum glow, faster pulse
Particles: Dense (capped at 50 for performance)
Insights: Prioritize by confidence, show top 3 with "See more"
```

### Stale Data

```
If HealthKit > 4 hours old:
  - Show "Last updated X hours ago" badge
  - HRV shows "--" instead of stale number

If no atoms in 24 hours:
  - Show "Check in" prompt
  - Orbs enter "sleeping" state (0.2Hz pulse)
```

---

# PART 10: iOS APP SYNC ARCHITECTURE

## 10.1 CloudKit Sync Protocol

```swift
// MARK: - iOS Sync Architecture

/// Sync Flow:
/// iPhone/Watch → CloudKit → Mac Daemon → Atom Created → Sync Back → iOS Notification

struct SyncArchitecture {

    // MARK: - Data Flow

    enum SyncDirection {
        case phoneToMac     // Captures from mobile
        case macToPhone     // Results back to mobile
        case watchToMac     // Health data from watch
        case macToWatch     // Complications, summaries
    }

    // MARK: - CloudKit Record Types

    struct CloudKitSchema {
        static let atomRecord = "Atom"
        static let syncMetadata = "SyncMetadata"
        static let userProfile = "UserProfile"
        static let levelState = "LevelState"
    }

    // MARK: - Real-time Notifications

    struct SyncNotifications {
        /// Sent to iOS when capture is processed
        static func captureProcessed(
            originalCapture: String,
            createdAtoms: [AtomPreview]
        ) -> PushNotification {
            return PushNotification(
                title: "Capture processed",
                body: "Created: \(createdAtoms.map(\.title).joined(separator: ", "))",
                category: .captureResult,
                data: ["atoms": createdAtoms.map(\.uuid)]
            )
        }

        /// Sent when journal generates insights
        static func journalInsights(
            journalTitle: String,
            insightCount: Int
        ) -> PushNotification {
            return PushNotification(
                title: "Journal analyzed",
                body: "\(insightCount) insights extracted",
                category: .journalResult,
                data: ["journalId": journalTitle]
            )
        }

        /// Daily summary push
        static func dailySummary(_ summary: DailySummaryCard) -> PushNotification {
            return PushNotification(
                title: "Daily Summary",
                body: "+\(summary.xpGained) XP • \(summary.tasksCompleted) tasks • \(summary.deepWorkMinutes)min deep work",
                category: .dailySummary
            )
        }

        /// Badge unlock celebration
        static func badgeUnlocked(_ badge: Badge) -> PushNotification {
            return PushNotification(
                title: "Badge Unlocked!",
                body: badge.name,
                category: .achievement,
                sound: .achievement
            )
        }
    }
}
```

## 10.2 Apple Watch Companion App

```swift
// MARK: - Watch App Architecture

struct WatchAppArchitecture {

    // MARK: - Complications

    enum Complication {
        case cosmoIndex         // Shows CI level
        case neuroELO           // Shows NELO rating
        case streak             // Current streak count
        case readiness          // Today's readiness score
        case deepWorkTimer      // Active session timer
        case dailyXP            // XP earned today
        case nextQuest          // Current quest progress
    }

    // MARK: - Quick Actions

    enum WatchQuickAction {
        case startDeepWork
        case endDeepWork
        case quickCapture       // Voice note
        case logMood
        case checkStats
    }

    // MARK: - Glances

    struct WatchGlances {
        let miniDashboard: MiniDashboard
        let healthSnapshot: HealthSnapshot
        let todayProgress: TodayProgress
    }

    struct MiniDashboard {
        let ci: Int
        let nelo: Int
        let streak: Int
        let todayXP: Int
    }

    struct HealthSnapshot {
        let readiness: Double
        let hrv: Double
        let sleepQuality: Double
    }

    struct TodayProgress {
        let questsComplete: Int
        let questsTotal: Int
        let deepWorkMinutes: Int
        let deepWorkTarget: Int
    }
}
```

---

# PART 11: IMPLEMENTATION PHASES

## Phase 1: Foundation (Weeks 1-4)

### 1.1 Extended Atom Model
- [ ] Add all new AtomType cases
- [ ] Implement all metadata structures
- [ ] Extend AtomLink system
- [ ] Update AtomRepository for new types
- [ ] Create database migrations

### 1.2 Core Level System
- [ ] Implement CosmoLevelSystem data model
- [ ] Create XPCalculationEngine
- [ ] Implement NELORegressionEngine
- [ ] Build LevelProgressTracker
- [ ] Add level system to user profile

### 1.3 Dimension Tracking
- [ ] Implement all 6 dimension configs
- [ ] Create DimensionMetricsCalculator
- [ ] Build dimension snapshot generator
- [ ] Add dimension-specific XP rules

---

## Phase 2: Health Integration (Weeks 5-8)

### 2.1 HealthKit Setup
- [ ] Request HealthKit permissions
- [ ] Implement HealthKitConfiguration
- [ ] Set up background delivery
- [ ] Build HealthKitAtomFactory

### 2.2 Health Atom Processing
- [ ] HRV measurement processing
- [ ] Sleep cycle analysis
- [ ] Workout session tracking
- [ ] Readiness score calculation

### 2.3 Health-Level Integration
- [ ] Connect health data to Physiological dimension
- [ ] Implement health-based XP calculation
- [ ] Add health-based NELO regression

---

## Phase 3: Gamification (Weeks 9-12)

### 3.1 Badge System
- [ ] Implement Badge data model
- [ ] Create BadgeCatalog with all badges
- [ ] Build BadgeUnlockEngine
- [ ] Add badge progress tracking

### 3.2 Quest System
- [ ] Implement DailyQuestEngine
- [ ] Create quest generation logic
- [ ] Build quest progress tracking
- [ ] Add quest completion rewards

### 3.3 Celebration Engine
- [ ] Implement CelebrationEngine
- [ ] Create celebration animations
- [ ] Add haptic feedback patterns
- [ ] Build XP summary overlay

---

## Phase 4: Daily Cron & Summaries (Weeks 13-16)

### 4.1 Cron Engine
- [ ] Implement DailyCronEngine
- [ ] Create midnight trigger system
- [ ] Build daily metrics aggregation
- [ ] Implement streak updates

### 4.2 Summary Generation
- [ ] Create daily summary atom type
- [ ] Build summary generation logic
- [ ] Implement weekly summary
- [ ] Add AI insights generation

### 4.3 Notifications
- [ ] Morning summary notification
- [ ] Streak warning notifications
- [ ] Badge unlock notifications
- [ ] Quest reminder notifications

---

## Phase 5: Voice Integration (Weeks 17-20)

### 5.1 Level Voice Commands
- [ ] Add level status voice patterns
- [ ] Implement streak query commands
- [ ] Add badge query commands
- [ ] Build XP query commands

### 5.2 Health Voice Commands
- [ ] Add readiness query command
- [ ] Implement HRV query command
- [ ] Build workout logging command
- [ ] Add deep work start/stop

### 5.3 Journal Voice Pipeline
- [ ] Implement JournalRouter
- [ ] Build journal classification
- [ ] Create journal processor
- [ ] Add insight extraction

---

## Phase 6: Content Pipeline (Weeks 21-24)

### 6.1 Content Tracking
- [ ] Implement ContentPipelineEngine
- [ ] Create phase tracking system
- [ ] Build content atom workflow
- [ ] Add draft versioning

### 6.2 Performance Matching
- [ ] Implement content matching algorithm
- [ ] Build social media API integrations
- [ ] Create performance atom generation
- [ ] Add virality detection

### 6.3 Creative Dimension
- [ ] Connect content performance to Creative dimension
- [ ] Implement client aggregation
- [ ] Add reach-based XP calculation
- [ ] Build viral post detection

---

## Phase 7: The Sanctuary (Weeks 25-32)

The Sanctuary is the neural interface dashboard - a living visualization of the entire Atom graph with causality-based insights. This is the most complex UI phase.

### 7.1 Causality Engine (Foundation - Must Complete First)

#### 7.1.1 New Atom Types
- [ ] Add `causalityInsight` Atom type
- [ ] Add `correlationSnapshot` Atom type
- [ ] Add `liveMetricCache` Atom type
- [ ] Add `dimensionRelationship` Atom type
- [ ] Create metadata structs for all causality types
- [ ] Add database migrations

#### 7.1.2 Correlation Compute Engine
- [ ] Implement `CausalityComputeEngine` actor
- [ ] Build 90-day rolling window aggregation
- [ ] Implement metric extraction from ALL Atom types:
  - [ ] Physiology: HRV, sleep, workouts, readiness
  - [ ] Cognitive: deep work, writing, focus, tasks
  - [ ] Content: performance, reach, virality
  - [ ] Reflection: journal semantic analysis
  - [ ] Knowledge: ideas, research, connections
  - [ ] Behavioral: streaks, routines
- [ ] Create lag correlation detection (0-7 day effects)
- [ ] Build compound pattern detection (A + B + C → outcome)
- [ ] Implement statistical significance filtering (p < 0.05 or >70% consistency)

#### 7.1.3 Journal Semantic Analysis
- [ ] Implement `JournalSemanticAnalysis` model
- [ ] Build topic detection (work, family, health, money, etc.)
- [ ] Add emotional valence extraction (-1 to +1)
- [ ] Create goal/fear/gratitude detection
- [ ] Implement recurring theme tracking
- [ ] Build named entity extraction (people mentioned)

#### 7.1.4 Cloud Model Integration
- [ ] Build `buildComprehensiveAnalysisPrompt()` for Gemini/Claude
- [ ] Implement 90-day data serialization (~30-50KB)
- [ ] Create JSON response parser for insights
- [ ] Add fallback to local statistical analysis
- [ ] Implement insight validation and storage

#### 7.1.5 Insight Lifecycle Management
- [ ] Build insight creation from correlations
- [ ] Implement confidence scoring (0-1)
- [ ] Add occurrence counting (minimum 5)
- [ ] Create effect size calculation (minimum 10%)
- [ ] Build insight decay on contradiction
- [ ] Implement insight removal when confidence < 0.50

#### 7.1.6 Smart Caching System
- [ ] Implement `CachedInsightProvider`
- [ ] Build dimension level cache (5 min TTL)
- [ ] Create correlation insight cache (24 hour TTL)
- [ ] Add historical graph cache (1 hour TTL)
- [ ] Implement invalidation triggers

### 7.2 Sanctuary Data Layer

#### 7.2.1 Data Provider
- [ ] Implement `SanctuaryDataProvider` @MainActor class
- [ ] Build live data streams (HRV, active timers, today XP)
- [ ] Create cached insight provider integration
- [ ] Implement on-demand dimension detail loading
- [ ] Add parallel data loading for <100ms entry

#### 7.2.2 Live Data Streams
- [ ] Implement `LiveDataStreamManager`
- [ ] Connect to HealthKit observer for real-time HRV
- [ ] Build today XP counter (event-driven updates)
- [ ] Create active session tracking (deep work/writing)
- [ ] Add streak status monitoring

### 7.3 Core Sanctuary UI

#### 7.3.1 Sanctuary Container
- [ ] Implement `SanctuaryView` root container
- [ ] Build entry animation sequence (0.4s choreography)
- [ ] Create exit animation sequence (0.3s choreography)
- [ ] Implement canvas fade/blur effect
- [ ] Add gesture handling for dismiss

#### 7.3.2 Background Layer
- [ ] Implement `SanctuaryBackgroundView`
- [ ] Build frosted glass material effect
- [ ] Create floating particle field
- [ ] Add gradient animation based on dimension balance

#### 7.3.3 Hero Orb
- [ ] Implement `HeroOrbView` (180pt diameter)
- [ ] Build level display with XP progress ring
- [ ] Create pulsing glow (synced to HRV or 1Hz fallback)
- [ ] Implement orbiting achievement particles
- [ ] Add touch interaction effects

#### 7.3.4 Dimension Orb Ring
- [ ] Implement `DimensionOrbRing` layout
- [ ] Build `DimensionOrbView` component (64pt diameter)
- [ ] Create Apple Fitness-style progress rings
- [ ] Implement glow intensity based on today's progress
- [ ] Add staggered entrance animation (40ms intervals)
- [ ] Build selection/expansion animation

#### 7.3.5 Causality Lines
- [ ] Implement `CausalityLinesView`
- [ ] Build lines connecting correlated dimensions
- [ ] Create pulse animation on correlation strength
- [ ] Add thickness based on confidence score

### 7.4 Metal Shaders

- [ ] Create `OrbSurface.metal` shader
  - [ ] Iridescent glass surface
  - [ ] Internal glow based on dimension score
  - [ ] Touch ripple effect
- [ ] Create `ParticleField.metal` shader
  - [ ] Floating particles by dimension color
  - [ ] Drift toward origin orb
  - [ ] Density based on activity level
- [ ] Create `CausalityLine.metal` shader
  - [ ] Gradient lines with pulse animation
  - [ ] Variable thickness
- [ ] Create `DepthBlur.metal` shader
  - [ ] Variable Gaussian blur
  - [ ] Z-position based intensity

### 7.5 Dimension Detail Views

#### 7.5.1 Common Components
- [ ] Implement `DimensionDetailSheet` container
- [ ] Build `TimelineGraphView` (90-day range)
- [ ] Create `CorrelationOverlayView` for graph highlights
- [ ] Implement `InsightCardView` for causality insights
- [ ] Add `LiveMetricBadge` floating component

#### 7.5.2 Performance Mode (Creative)
- [ ] Build reach/impressions timeline
- [ ] Add engagement rate trend
- [ ] Create viral post markers
- [ ] Implement correlation overlays (deep work, sleep, etc.)
- [ ] Add "Posts after X perform Y% better" insights

#### 7.5.3 Health Mode (Physiological)
- [ ] Build HRV timeline (hero metric)
- [ ] Add sleep efficiency secondary line
- [ ] Create recovery score dots
- [ ] Implement workout markers
- [ ] Add "Your HRV peaks after X" insights

#### 7.5.4 Creativity Mode (Knowledge)
- [ ] Build idea generation timeline
- [ ] Add semantic diversity score
- [ ] Create connection density graph
- [ ] Implement research consumption overlay
- [ ] Add "Ideas spike after X" insights

#### 7.5.5 Behavior Mode (Consistency)
- [ ] Build multi-streak timeline
- [ ] Add routine adherence bars
- [ ] Create XP multiplier visualization
- [ ] Implement "Streak + X = Y" insights

#### 7.5.6 Knowledge Mode (Graph)
- [ ] Build mini knowledge graph visualization
- [ ] Add connection count timeline
- [ ] Create semantic cluster growth
- [ ] Implement cross-domain linking display

#### 7.5.7 Reflection Mode (Journal)
- [ ] Build journal frequency timeline
- [ ] Add clarity score trend
- [ ] Create emotional state distribution
- [ ] Implement "Journaling about X predicts Y" insights

### 7.6 Animation Choreography

- [ ] Implement interruptible spring animations
- [ ] Build orb selection sequence (tap → expand → detail)
- [ ] Create timeline scrubbing with tooltips
- [ ] Implement pinch-to-zoom on graphs (7 days ↔ 90 days)
- [ ] Add haptic feedback patterns
- [ ] Build mid-animation interruption handling

### 7.7 Edge Cases & Polish

- [ ] Implement empty state for new users
- [ ] Build low-data-day fallback (weekly insights)
- [ ] Create stale data indicators (>4 hours)
- [ ] Add "sleeping" orb state (no atoms in 24hrs)
- [ ] Implement heavy-data-day optimization (aggregate to hour level)
- [ ] Build background/foreground state handling

### 7.8 Integration with MidnightCron

- [ ] Add causality computation to daily cron pipeline
- [ ] Implement 90-day window aggregation
- [ ] Build cloud model API call (Gemini/Claude)
- [ ] Create insight Atom creation/update
- [ ] Add correlation snapshot Atom for history

---

## Phase 8: iOS Sync (Weeks 29-32)

### 8.1 CloudKit Setup
- [ ] Configure CloudKit container
- [ ] Implement sync record types
- [ ] Build sync engine for iOS
- [ ] Add conflict resolution

### 8.2 iOS Companion App
- [ ] Build minimal iOS app
- [ ] Implement quick capture
- [ ] Add push notification handling
- [ ] Create mini dashboard

### 8.3 Watch App
- [ ] Build watch complications
- [ ] Implement quick actions
- [ ] Create watch glances
- [ ] Add health data capture

---

## Phase 9: AI Enhancement (Weeks 33-36)

### 9.1 Model Optimization
- [ ] Fine-tune intent classifier for levels
- [ ] Optimize journal processing prompts
- [ ] Build insight extraction pipeline
- [ ] Add clarity scoring model

### 9.2 Predictive Features
- [ ] Implement proactive suggestions
- [ ] Build regression predictions
- [ ] Create optimal timing recommendations
- [ ] Add goal achievement forecasting

### 9.3 Future Hardware Prep
- [ ] Design MoE routing system
- [ ] Create model switching logic
- [ ] Build hardware detection
- [ ] Prepare 512GB configurations

---

## Phase 10: Polish & Launch (Weeks 37-40)

### 10.1 Performance
- [ ] Optimize database queries
- [ ] Profile and fix bottlenecks
- [ ] Reduce memory usage
- [ ] Improve animation performance

### 10.2 Testing
- [ ] Unit tests for level calculations
- [ ] Integration tests for sync
- [ ] UI tests for dashboard
- [ ] End-to-end flow tests

### 10.3 Documentation
- [ ] User onboarding flow
- [ ] Feature documentation
- [ ] API documentation
- [ ] Architecture documentation

---

# APPENDIX A: DATA SCIENCE REFERENCES

## Scientific Thresholds Sources

### HRV Research
- Shaffer & Ginsberg (2017) - HRV metrics overview
- WHOOP population data (2024)
- Oura Ring white papers
- Elite athlete studies (Harvard, Stanford)

### Sleep Science
- Walker, M. "Why We Sleep" (2017)
- Sleep Foundation guidelines
- Huberman Lab protocols
- WHOOP sleep research

### Productivity Research
- Newport, C. "Deep Work" (2016)
- MIT productivity studies
- Stanford attention research
- Writing productivity benchmarks (Hemingway App)

### Gamification Psychology
- Kahneman, D. "Thinking, Fast and Slow" (2011) - Loss aversion
- Csikszentmihalyi, M. "Flow" (1990) - Flow state
- Ryan & Deci - Self-Determination Theory
- Skinner, B.F. - Variable ratio reinforcement

### Video Game Addiction Mechanics
- Schell, J. "The Art of Game Design" (2008)
- Chou, Y. "Actionable Gamification" (2015)
- Zichermann, G. "Gamification by Design" (2011)

---

# APPENDIX B: TECHNICAL SPECIFICATIONS

## Database Schema Extensions

```sql
-- New indexes for level system
CREATE INDEX idx_atoms_type_created ON atoms(type, created_at);
CREATE INDEX idx_atoms_user_dimension ON atoms(user_id, type) WHERE type IN ('xp_event', 'level_update', 'nelo_update');
CREATE INDEX idx_atoms_streak ON atoms(user_id, type, created_at) WHERE type = 'streak_event';
CREATE INDEX idx_atoms_badge ON atoms(user_id, type) WHERE type = 'badge_unlocked';

-- Health data indexes
CREATE INDEX idx_atoms_health ON atoms(user_id, type, created_at) WHERE type IN ('hrv_measurement', 'sleep_cycle', 'readiness_score', 'workout_session');

-- Performance optimization
CREATE INDEX idx_atoms_links ON atoms USING GIN (links);
CREATE INDEX idx_atoms_metadata ON atoms USING GIN (metadata);
```

## Memory Budgets

### M4 16GB Configuration
- System: 6GB
- App: 2GB
- ML Models: 4GB
- Vector DB: 1GB
- Buffer: 3GB

### M3 Ultra 512GB Configuration
- System: 32GB
- App: 8GB
- ML Models: 180GB
- Vector DB: 50GB
- Context Cache: 200GB
- Buffer: 42GB

---

**End of Master Plan**

*Version: 1.1*
*Created: December 2025*
*Last Updated: December 2025*
*Author: CosmoOS Development*

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | December 2025 | Initial master plan with Phases 1-10 |
| 1.1 | December 2025 | Comprehensive Phase 7 (Sanctuary) specification: Causality Engine with 90-day rolling window, complete correlation matrix across all Atom types, journal semantic analysis, cloud model integration, Metal shader specs, insight lifecycle management |
