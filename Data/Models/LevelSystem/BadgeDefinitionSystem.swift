import Foundation

// MARK: - Badge Tier System

/// Badge tiers following video game psychology progression
/// Each tier represents increasing mastery and commitment
public enum BadgeTier: Int, Codable, CaseIterable, Sendable {
    case bronze = 1      // Entry level - achievable in first week
    case silver = 2      // Intermediate - 2-4 weeks of consistent use
    case gold = 3        // Advanced - 1-3 months of mastery
    case platinum = 4    // Expert - 3-6 months of excellence
    case diamond = 5     // Elite - 6-12 months of peak performance
    case cosmic = 6      // Legendary - 1+ year of transcendent achievement

    public var displayName: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        case .diamond: return "Diamond"
        case .cosmic: return "Cosmic"
        }
    }

    public var xpMultiplier: Double {
        switch self {
        case .bronze: return 1.0
        case .silver: return 1.25
        case .gold: return 1.5
        case .platinum: return 2.0
        case .diamond: return 2.5
        case .cosmic: return 3.0
        }
    }

    public var neloBonus: Int {
        switch self {
        case .bronze: return 10
        case .silver: return 25
        case .gold: return 50
        case .platinum: return 100
        case .diamond: return 200
        case .cosmic: return 500
        }
    }
}

// MARK: - Badge Category

public enum BadgeCategory: String, Codable, CaseIterable, Sendable {
    case cognitive
    case creative
    case physiological
    case behavioral
    case knowledge
    case reflection
    case meta          // Cross-dimensional achievements
    case milestone     // Level/time-based achievements
    case special       // Limited-time or rare achievements
}

// MARK: - Badge Requirement Types

/// Different types of requirements for earning badges
public enum BadgeRequirementType: String, Codable, Sendable {
    // Count-based
    case atomCount              // Total atoms of a type
    case actionCount            // Total actions performed
    case uniqueDays             // Unique days with activity

    // Streak-based
    case currentStreak          // Current consecutive days
    case maxStreak              // All-time longest streak
    case streakMilestone        // Reached X-day streak at any point

    // Performance-based
    case neloRating             // Reach NELO rating in dimension
    case ciLevel                // Reach CI level in dimension
    case overallLevel           // Reach overall Cosmo level

    // Quality-based
    case averageQuality         // Average quality score
    case perfectScore           // Number of perfect scores
    case consistencyRate        // Consistency percentage over time

    // Time-based
    case totalMinutes           // Total time spent
    case sessionMinutes         // Single session duration
    case dailyMinutes           // Minutes in a single day

    // Compound
    case multiDimension         // Requirements across multiple dimensions
    case conditional            // Complex conditional requirements
}

// MARK: - Badge Requirement

public struct BadgeRequirement: Codable, Sendable, Equatable {
    public let type: BadgeRequirementType
    public let dimension: BadgeCategory?  // nil for cross-dimensional
    public let threshold: Double
    public let atomType: String?          // Optional atom type filter
    public let metadata: [String: String] // Additional requirement context

    public init(
        type: BadgeRequirementType,
        dimension: BadgeCategory? = nil,
        threshold: Double,
        atomType: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.type = type
        self.dimension = dimension
        self.threshold = threshold
        self.atomType = atomType
        self.metadata = metadata
    }

    // Convenience initializers
    public static func atomCount(_ count: Int, type: String? = nil, in dimension: BadgeCategory? = nil) -> BadgeRequirement {
        BadgeRequirement(type: .atomCount, dimension: dimension, threshold: Double(count), atomType: type)
    }

    public static func streak(_ days: Int, in dimension: BadgeCategory? = nil) -> BadgeRequirement {
        BadgeRequirement(type: .currentStreak, dimension: dimension, threshold: Double(days))
    }

    public static func neloRating(_ rating: Int, in dimension: BadgeCategory) -> BadgeRequirement {
        BadgeRequirement(type: .neloRating, dimension: dimension, threshold: Double(rating))
    }

    public static func ciLevel(_ level: Int, in dimension: BadgeCategory) -> BadgeRequirement {
        BadgeRequirement(type: .ciLevel, dimension: dimension, threshold: Double(level))
    }

    public static func totalMinutes(_ minutes: Int, in dimension: BadgeCategory? = nil) -> BadgeRequirement {
        BadgeRequirement(type: .totalMinutes, dimension: dimension, threshold: Double(minutes))
    }

    public static func uniqueDays(_ days: Int, in dimension: BadgeCategory? = nil) -> BadgeRequirement {
        BadgeRequirement(type: .uniqueDays, dimension: dimension, threshold: Double(days))
    }
}

// MARK: - Badge Definition

public struct BadgeDefinition: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let category: BadgeCategory
    public let tier: BadgeTier
    public let requirements: [BadgeRequirement]
    public let requireAll: Bool           // true = AND, false = OR
    public let iconName: String
    public let flavorText: String         // Motivational/fun description
    public let unlocksAt: Date?           // For time-gated badges
    public let expiresAt: Date?           // For limited-time badges
    public let isSecret: Bool             // Hidden until earned
    public let prerequisiteBadges: [String]  // Badge IDs required first

    public init(
        id: String,
        name: String,
        description: String,
        category: BadgeCategory,
        tier: BadgeTier,
        requirements: [BadgeRequirement],
        requireAll: Bool = true,
        iconName: String,
        flavorText: String = "",
        unlocksAt: Date? = nil,
        expiresAt: Date? = nil,
        isSecret: Bool = false,
        prerequisiteBadges: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.tier = tier
        self.requirements = requirements
        self.requireAll = requireAll
        self.iconName = iconName
        self.flavorText = flavorText
        self.unlocksAt = unlocksAt
        self.expiresAt = expiresAt
        self.isSecret = isSecret
        self.prerequisiteBadges = prerequisiteBadges
    }

    public var xpReward: Int {
        let base: Int
        switch tier {
        case .bronze: base = 100
        case .silver: base = 250
        case .gold: base = 500
        case .platinum: base = 1000
        case .diamond: base = 2500
        case .cosmic: base = 5000
        }
        return base
    }
}

// MARK: - Badge Definition System

/// Central registry for all badge definitions
/// Following game design principles: clear goals, visible progress, meaningful rewards
public final class BadgeDefinitionSystem: Sendable {

    public static let shared = BadgeDefinitionSystem()

    public let allBadges: [BadgeDefinition]
    private let badgesByID: [String: BadgeDefinition]
    private let badgesByCategory: [BadgeCategory: [BadgeDefinition]]

    private init() {
        let badges = Self.generateAllBadges()
        self.allBadges = badges
        self.badgesByID = Dictionary(uniqueKeysWithValues: badges.map { ($0.id, $0) })
        self.badgesByCategory = Dictionary(grouping: badges, by: { $0.category })
    }

    public func badge(withID id: String) -> BadgeDefinition? {
        badgesByID[id]
    }

    public func badges(in category: BadgeCategory) -> [BadgeDefinition] {
        badgesByCategory[category] ?? []
    }

    public func badges(ofTier tier: BadgeTier) -> [BadgeDefinition] {
        allBadges.filter { $0.tier == tier }
    }

    public func secretBadges() -> [BadgeDefinition] {
        allBadges.filter { $0.isSecret }
    }

    // MARK: - Badge Generation

    private static func generateAllBadges() -> [BadgeDefinition] {
        var badges: [BadgeDefinition] = []

        badges.append(contentsOf: cognitiveBadges())
        badges.append(contentsOf: creativeBadges())
        badges.append(contentsOf: physiologicalBadges())
        badges.append(contentsOf: behavioralBadges())
        badges.append(contentsOf: knowledgeBadges())
        badges.append(contentsOf: reflectionBadges())
        badges.append(contentsOf: metaBadges())
        badges.append(contentsOf: milestoneBadges())

        return badges
    }

    // MARK: - Cognitive Badges

    private static func cognitiveBadges() -> [BadgeDefinition] {
        [
            // Writing badges
            BadgeDefinition(
                id: "cognitive_writer_bronze",
                name: "Wordsmith",
                description: "Write your first 1,000 words",
                category: .cognitive,
                tier: .bronze,
                requirements: [.atomCount(1000, type: "word_count")],
                iconName: "pencil.circle.fill",
                flavorText: "Every great story starts with a single word."
            ),
            BadgeDefinition(
                id: "cognitive_writer_silver",
                name: "Prolific Pen",
                description: "Write 10,000 words total",
                category: .cognitive,
                tier: .silver,
                requirements: [.atomCount(10000, type: "word_count")],
                iconName: "pencil.circle.fill",
                flavorText: "Your thoughts flow like a river.",
                prerequisiteBadges: ["cognitive_writer_bronze"]
            ),
            BadgeDefinition(
                id: "cognitive_writer_gold",
                name: "Master Scribe",
                description: "Write 50,000 words total",
                category: .cognitive,
                tier: .gold,
                requirements: [.atomCount(50000, type: "word_count")],
                iconName: "pencil.circle.fill",
                flavorText: "A novel's worth of wisdom captured.",
                prerequisiteBadges: ["cognitive_writer_silver"]
            ),
            BadgeDefinition(
                id: "cognitive_writer_platinum",
                name: "Literary Legend",
                description: "Write 250,000 words total",
                category: .cognitive,
                tier: .platinum,
                requirements: [.atomCount(250000, type: "word_count")],
                iconName: "pencil.circle.fill",
                flavorText: "Your words could fill libraries.",
                prerequisiteBadges: ["cognitive_writer_gold"]
            ),
            BadgeDefinition(
                id: "cognitive_writer_diamond",
                name: "Cognitive Chronicler",
                description: "Write 1,000,000 words total",
                category: .cognitive,
                tier: .diamond,
                requirements: [.atomCount(1000000, type: "word_count")],
                iconName: "pencil.circle.fill",
                flavorText: "A million words, each one a step toward mastery.",
                prerequisiteBadges: ["cognitive_writer_platinum"]
            ),

            // Focus session badges
            BadgeDefinition(
                id: "cognitive_focus_bronze",
                name: "First Focus",
                description: "Complete your first deep work session",
                category: .cognitive,
                tier: .bronze,
                requirements: [.atomCount(1, type: "focus_session")],
                iconName: "brain.head.profile",
                flavorText: "The journey of a thousand miles begins with a single focus block."
            ),
            BadgeDefinition(
                id: "cognitive_focus_silver",
                name: "Flow Finder",
                description: "Complete 25 deep work sessions",
                category: .cognitive,
                tier: .silver,
                requirements: [.atomCount(25, type: "focus_session")],
                iconName: "brain.head.profile",
                flavorText: "You're learning to dance with focus.",
                prerequisiteBadges: ["cognitive_focus_bronze"]
            ),
            BadgeDefinition(
                id: "cognitive_focus_gold",
                name: "Deep Diver",
                description: "Accumulate 100 hours of deep work",
                category: .cognitive,
                tier: .gold,
                requirements: [.totalMinutes(6000, in: .cognitive)],
                iconName: "brain.head.profile",
                flavorText: "100 hours of pure cognitive immersion.",
                prerequisiteBadges: ["cognitive_focus_silver"]
            ),
            BadgeDefinition(
                id: "cognitive_focus_platinum",
                name: "Flow Master",
                description: "Accumulate 500 hours of deep work",
                category: .cognitive,
                tier: .platinum,
                requirements: [.totalMinutes(30000, in: .cognitive)],
                iconName: "brain.head.profile",
                flavorText: "Flow state is your natural habitat.",
                prerequisiteBadges: ["cognitive_focus_gold"]
            ),
            BadgeDefinition(
                id: "cognitive_focus_diamond",
                name: "Cognitive Sovereign",
                description: "Accumulate 2000 hours of deep work",
                category: .cognitive,
                tier: .diamond,
                requirements: [.totalMinutes(120000, in: .cognitive)],
                iconName: "brain.head.profile",
                flavorText: "Mastery through unwavering focus.",
                prerequisiteBadges: ["cognitive_focus_platinum"]
            ),

            // NELO mastery
            BadgeDefinition(
                id: "cognitive_nelo_silver",
                name: "Cognitive Contender",
                description: "Reach 1200 NELO in Cognitive dimension",
                category: .cognitive,
                tier: .silver,
                requirements: [.neloRating(1200, in: .cognitive)],
                iconName: "chart.line.uptrend.xyaxis",
                flavorText: "Rising through the ranks of mental mastery."
            ),
            BadgeDefinition(
                id: "cognitive_nelo_gold",
                name: "Cognitive Champion",
                description: "Reach 1600 NELO in Cognitive dimension",
                category: .cognitive,
                tier: .gold,
                requirements: [.neloRating(1600, in: .cognitive)],
                iconName: "chart.line.uptrend.xyaxis",
                flavorText: "A true cognitive athlete.",
                prerequisiteBadges: ["cognitive_nelo_silver"]
            ),
            BadgeDefinition(
                id: "cognitive_nelo_platinum",
                name: "Cognitive Grandmaster",
                description: "Reach 2000 NELO in Cognitive dimension",
                category: .cognitive,
                tier: .platinum,
                requirements: [.neloRating(2000, in: .cognitive)],
                iconName: "chart.line.uptrend.xyaxis",
                flavorText: "Elite cognitive performance unlocked.",
                prerequisiteBadges: ["cognitive_nelo_gold"]
            ),
            BadgeDefinition(
                id: "cognitive_nelo_diamond",
                name: "Cognitive Apex",
                description: "Reach 2400 NELO in Cognitive dimension",
                category: .cognitive,
                tier: .diamond,
                requirements: [.neloRating(2400, in: .cognitive)],
                iconName: "chart.line.uptrend.xyaxis",
                flavorText: "Peak human cognitive performance.",
                prerequisiteBadges: ["cognitive_nelo_platinum"]
            ),
        ]
    }

    // MARK: - Creative Badges

    private static func creativeBadges() -> [BadgeDefinition] {
        [
            BadgeDefinition(
                id: "creative_spark_bronze",
                name: "First Spark",
                description: "Capture your first idea",
                category: .creative,
                tier: .bronze,
                requirements: [.atomCount(1, type: "idea")],
                iconName: "lightbulb.fill",
                flavorText: "Every masterpiece begins as a spark."
            ),
            BadgeDefinition(
                id: "creative_spark_silver",
                name: "Idea Fountain",
                description: "Capture 50 ideas",
                category: .creative,
                tier: .silver,
                requirements: [.atomCount(50, type: "idea")],
                iconName: "lightbulb.fill",
                flavorText: "Your mind is a wellspring of innovation.",
                prerequisiteBadges: ["creative_spark_bronze"]
            ),
            BadgeDefinition(
                id: "creative_spark_gold",
                name: "Creative Catalyst",
                description: "Capture 250 ideas",
                category: .creative,
                tier: .gold,
                requirements: [.atomCount(250, type: "idea")],
                iconName: "lightbulb.fill",
                flavorText: "Ideas flow through you like electricity.",
                prerequisiteBadges: ["creative_spark_silver"]
            ),
            BadgeDefinition(
                id: "creative_spark_platinum",
                name: "Innovation Engine",
                description: "Capture 1000 ideas",
                category: .creative,
                tier: .platinum,
                requirements: [.atomCount(1000, type: "idea")],
                iconName: "lightbulb.fill",
                flavorText: "A thousand sparks, each one a potential revolution.",
                prerequisiteBadges: ["creative_spark_gold"]
            ),

            // Project completion
            BadgeDefinition(
                id: "creative_builder_bronze",
                name: "Project Pioneer",
                description: "Complete your first project",
                category: .creative,
                tier: .bronze,
                requirements: [.atomCount(1, type: "project_completed")],
                iconName: "hammer.fill",
                flavorText: "From idea to reality."
            ),
            BadgeDefinition(
                id: "creative_builder_silver",
                name: "Project Pro",
                description: "Complete 10 projects",
                category: .creative,
                tier: .silver,
                requirements: [.atomCount(10, type: "project_completed")],
                iconName: "hammer.fill",
                flavorText: "Consistently shipping greatness.",
                prerequisiteBadges: ["creative_builder_bronze"]
            ),
            BadgeDefinition(
                id: "creative_builder_gold",
                name: "Prolific Creator",
                description: "Complete 50 projects",
                category: .creative,
                tier: .gold,
                requirements: [.atomCount(50, type: "project_completed")],
                iconName: "hammer.fill",
                flavorText: "A portfolio of accomplishments.",
                prerequisiteBadges: ["creative_builder_silver"]
            ),

            // Idea-to-project conversion
            BadgeDefinition(
                id: "creative_converter_gold",
                name: "Dream Realizer",
                description: "Convert 25 ideas into completed projects",
                category: .creative,
                tier: .gold,
                requirements: [.atomCount(25, type: "idea_to_project")],
                iconName: "arrow.triangle.2.circlepath",
                flavorText: "You don't just dream, you build."
            ),

            // NELO
            BadgeDefinition(
                id: "creative_nelo_silver",
                name: "Creative Contender",
                description: "Reach 1200 NELO in Creative dimension",
                category: .creative,
                tier: .silver,
                requirements: [.neloRating(1200, in: .creative)],
                iconName: "paintpalette.fill",
                flavorText: "Your creative flame grows brighter."
            ),
            BadgeDefinition(
                id: "creative_nelo_gold",
                name: "Creative Virtuoso",
                description: "Reach 1600 NELO in Creative dimension",
                category: .creative,
                tier: .gold,
                requirements: [.neloRating(1600, in: .creative)],
                iconName: "paintpalette.fill",
                flavorText: "Artistry in everything you touch.",
                prerequisiteBadges: ["creative_nelo_silver"]
            ),
            BadgeDefinition(
                id: "creative_nelo_platinum",
                name: "Creative Visionary",
                description: "Reach 2000 NELO in Creative dimension",
                category: .creative,
                tier: .platinum,
                requirements: [.neloRating(2000, in: .creative)],
                iconName: "paintpalette.fill",
                flavorText: "You see what others cannot.",
                prerequisiteBadges: ["creative_nelo_gold"]
            ),
        ]
    }

    // MARK: - Physiological Badges

    private static func physiologicalBadges() -> [BadgeDefinition] {
        [
            // Sleep badges
            BadgeDefinition(
                id: "physio_sleep_bronze",
                name: "Rest Rookie",
                description: "Log 7 consecutive nights of sleep",
                category: .physiological,
                tier: .bronze,
                requirements: [.streak(7, in: .physiological)],
                iconName: "moon.fill",
                flavorText: "The foundation of peak performance is rest."
            ),
            BadgeDefinition(
                id: "physio_sleep_silver",
                name: "Sleep Scholar",
                description: "Maintain healthy sleep for 30 days",
                category: .physiological,
                tier: .silver,
                requirements: [.streak(30, in: .physiological)],
                iconName: "moon.fill",
                flavorText: "Your body thanks you.",
                prerequisiteBadges: ["physio_sleep_bronze"]
            ),
            BadgeDefinition(
                id: "physio_sleep_gold",
                name: "Dream Master",
                description: "Achieve 90% sleep consistency for 90 days",
                category: .physiological,
                tier: .gold,
                requirements: [
                    .streak(90, in: .physiological),
                    BadgeRequirement(type: .consistencyRate, dimension: .physiological, threshold: 0.9)
                ],
                iconName: "moon.fill",
                flavorText: "Sleep is your superpower.",
                prerequisiteBadges: ["physio_sleep_silver"]
            ),

            // HRV badges
            BadgeDefinition(
                id: "physio_hrv_bronze",
                name: "Heart Listener",
                description: "Track HRV for 7 consecutive days",
                category: .physiological,
                tier: .bronze,
                requirements: [.uniqueDays(7, in: .physiological)],
                iconName: "heart.fill",
                flavorText: "Your heart speaks, you listen."
            ),
            BadgeDefinition(
                id: "physio_hrv_silver",
                name: "Stress Sensor",
                description: "Track HRV for 30 consecutive days",
                category: .physiological,
                tier: .silver,
                requirements: [.uniqueDays(30, in: .physiological)],
                iconName: "heart.fill",
                flavorText: "Understanding your nervous system.",
                prerequisiteBadges: ["physio_hrv_bronze"]
            ),
            BadgeDefinition(
                id: "physio_hrv_gold",
                name: "Autonomic Ace",
                description: "Improve average HRV by 20% over baseline",
                category: .physiological,
                tier: .gold,
                requirements: [
                    BadgeRequirement(type: .averageQuality, dimension: .physiological, threshold: 1.2, metadata: ["metric": "hrv"])
                ],
                iconName: "heart.fill",
                flavorText: "Your nervous system is thriving.",
                prerequisiteBadges: ["physio_hrv_silver"]
            ),

            // Exercise badges
            BadgeDefinition(
                id: "physio_exercise_bronze",
                name: "Movement Initiate",
                description: "Log 10 workout sessions",
                category: .physiological,
                tier: .bronze,
                requirements: [.atomCount(10, type: "workout")],
                iconName: "figure.run",
                flavorText: "Motion is the medicine."
            ),
            BadgeDefinition(
                id: "physio_exercise_silver",
                name: "Active Athlete",
                description: "Log 100 workout sessions",
                category: .physiological,
                tier: .silver,
                requirements: [.atomCount(100, type: "workout")],
                iconName: "figure.run",
                flavorText: "Consistency builds champions.",
                prerequisiteBadges: ["physio_exercise_bronze"]
            ),
            BadgeDefinition(
                id: "physio_exercise_gold",
                name: "Iron Will",
                description: "Log 500 workout sessions",
                category: .physiological,
                tier: .gold,
                requirements: [.atomCount(500, type: "workout")],
                iconName: "figure.run",
                flavorText: "Discipline forged in sweat.",
                prerequisiteBadges: ["physio_exercise_silver"]
            ),

            // NELO
            BadgeDefinition(
                id: "physio_nelo_silver",
                name: "Body Aware",
                description: "Reach 1200 NELO in Physiological dimension",
                category: .physiological,
                tier: .silver,
                requirements: [.neloRating(1200, in: .physiological)],
                iconName: "figure.stand",
                flavorText: "Mastering the vessel."
            ),
            BadgeDefinition(
                id: "physio_nelo_gold",
                name: "Physical Peak",
                description: "Reach 1600 NELO in Physiological dimension",
                category: .physiological,
                tier: .gold,
                requirements: [.neloRating(1600, in: .physiological)],
                iconName: "figure.stand",
                flavorText: "Peak physical optimization.",
                prerequisiteBadges: ["physio_nelo_silver"]
            ),
            BadgeDefinition(
                id: "physio_nelo_platinum",
                name: "Biohacker Elite",
                description: "Reach 2000 NELO in Physiological dimension",
                category: .physiological,
                tier: .platinum,
                requirements: [.neloRating(2000, in: .physiological)],
                iconName: "figure.stand",
                flavorText: "Your body is a finely tuned instrument.",
                prerequisiteBadges: ["physio_nelo_gold"]
            ),
        ]
    }

    // MARK: - Behavioral Badges

    private static func behavioralBadges() -> [BadgeDefinition] {
        [
            // Task completion
            BadgeDefinition(
                id: "behavioral_task_bronze",
                name: "Task Tackler",
                description: "Complete 10 tasks",
                category: .behavioral,
                tier: .bronze,
                requirements: [.atomCount(10, type: "task_completed")],
                iconName: "checkmark.circle.fill",
                flavorText: "Getting things done, one task at a time."
            ),
            BadgeDefinition(
                id: "behavioral_task_silver",
                name: "Productivity Pro",
                description: "Complete 100 tasks",
                category: .behavioral,
                tier: .silver,
                requirements: [.atomCount(100, type: "task_completed")],
                iconName: "checkmark.circle.fill",
                flavorText: "Your execution is exemplary.",
                prerequisiteBadges: ["behavioral_task_bronze"]
            ),
            BadgeDefinition(
                id: "behavioral_task_gold",
                name: "Task Titan",
                description: "Complete 500 tasks",
                category: .behavioral,
                tier: .gold,
                requirements: [.atomCount(500, type: "task_completed")],
                iconName: "checkmark.circle.fill",
                flavorText: "Nothing stands in your way.",
                prerequisiteBadges: ["behavioral_task_silver"]
            ),
            BadgeDefinition(
                id: "behavioral_task_platinum",
                name: "Execution Machine",
                description: "Complete 2500 tasks",
                category: .behavioral,
                tier: .platinum,
                requirements: [.atomCount(2500, type: "task_completed")],
                iconName: "checkmark.circle.fill",
                flavorText: "Pure operational excellence.",
                prerequisiteBadges: ["behavioral_task_gold"]
            ),

            // Habit badges
            BadgeDefinition(
                id: "behavioral_habit_bronze",
                name: "Habit Beginner",
                description: "Maintain a habit for 7 days",
                category: .behavioral,
                tier: .bronze,
                requirements: [.streak(7, in: .behavioral)],
                iconName: "repeat.circle.fill",
                flavorText: "Small steps, big changes."
            ),
            BadgeDefinition(
                id: "behavioral_habit_silver",
                name: "Habit Builder",
                description: "Maintain a habit for 30 days",
                category: .behavioral,
                tier: .silver,
                requirements: [.streak(30, in: .behavioral)],
                iconName: "repeat.circle.fill",
                flavorText: "Neural pathways strengthening.",
                prerequisiteBadges: ["behavioral_habit_bronze"]
            ),
            BadgeDefinition(
                id: "behavioral_habit_gold",
                name: "Habit Master",
                description: "Maintain a habit for 66 days",
                category: .behavioral,
                tier: .gold,
                requirements: [.streak(66, in: .behavioral)],
                iconName: "repeat.circle.fill",
                flavorText: "66 days - the habit is now automatic.",
                prerequisiteBadges: ["behavioral_habit_silver"]
            ),
            BadgeDefinition(
                id: "behavioral_habit_platinum",
                name: "Lifestyle Architect",
                description: "Maintain 5 different habits for 66+ days each",
                category: .behavioral,
                tier: .platinum,
                requirements: [.atomCount(5, type: "habit_66_days")],
                iconName: "repeat.circle.fill",
                flavorText: "Your life is designed by intention.",
                prerequisiteBadges: ["behavioral_habit_gold"]
            ),

            // Routine badges
            BadgeDefinition(
                id: "behavioral_routine_bronze",
                name: "Routine Rookie",
                description: "Complete your first morning routine",
                category: .behavioral,
                tier: .bronze,
                requirements: [.atomCount(1, type: "routine_completed")],
                iconName: "sunrise.fill",
                flavorText: "Win the morning, win the day."
            ),
            BadgeDefinition(
                id: "behavioral_routine_silver",
                name: "Routine Regular",
                description: "Complete 50 routines",
                category: .behavioral,
                tier: .silver,
                requirements: [.atomCount(50, type: "routine_completed")],
                iconName: "sunrise.fill",
                flavorText: "Structure brings freedom.",
                prerequisiteBadges: ["behavioral_routine_bronze"]
            ),

            // NELO
            BadgeDefinition(
                id: "behavioral_nelo_silver",
                name: "Behavioral Apprentice",
                description: "Reach 1200 NELO in Behavioral dimension",
                category: .behavioral,
                tier: .silver,
                requirements: [.neloRating(1200, in: .behavioral)],
                iconName: "gearshape.2.fill",
                flavorText: "Mastering your actions."
            ),
            BadgeDefinition(
                id: "behavioral_nelo_gold",
                name: "Behavioral Expert",
                description: "Reach 1600 NELO in Behavioral dimension",
                category: .behavioral,
                tier: .gold,
                requirements: [.neloRating(1600, in: .behavioral)],
                iconName: "gearshape.2.fill",
                flavorText: "Your habits serve your purpose.",
                prerequisiteBadges: ["behavioral_nelo_silver"]
            ),
        ]
    }

    // MARK: - Knowledge Badges

    private static func knowledgeBadges() -> [BadgeDefinition] {
        [
            // Reading badges
            BadgeDefinition(
                id: "knowledge_reader_bronze",
                name: "Page Turner",
                description: "Add your first book to your library",
                category: .knowledge,
                tier: .bronze,
                requirements: [.atomCount(1, type: "book")],
                iconName: "book.fill",
                flavorText: "A reader lives a thousand lives."
            ),
            BadgeDefinition(
                id: "knowledge_reader_silver",
                name: "Bibliophile",
                description: "Read 12 books",
                category: .knowledge,
                tier: .silver,
                requirements: [.atomCount(12, type: "book_completed")],
                iconName: "book.fill",
                flavorText: "A book a month keeps ignorance at bay.",
                prerequisiteBadges: ["knowledge_reader_bronze"]
            ),
            BadgeDefinition(
                id: "knowledge_reader_gold",
                name: "Scholar",
                description: "Read 52 books",
                category: .knowledge,
                tier: .gold,
                requirements: [.atomCount(52, type: "book_completed")],
                iconName: "book.fill",
                flavorText: "A book a week, a mind at peak.",
                prerequisiteBadges: ["knowledge_reader_silver"]
            ),
            BadgeDefinition(
                id: "knowledge_reader_platinum",
                name: "Polymath",
                description: "Read 200 books across 10+ categories",
                category: .knowledge,
                tier: .platinum,
                requirements: [
                    .atomCount(200, type: "book_completed"),
                    BadgeRequirement(type: .atomCount, dimension: .knowledge, threshold: 10, atomType: "book_categories")
                ],
                iconName: "book.fill",
                flavorText: "Renaissance mind in the modern age.",
                prerequisiteBadges: ["knowledge_reader_gold"]
            ),

            // Note-taking badges
            BadgeDefinition(
                id: "knowledge_notes_bronze",
                name: "Note Novice",
                description: "Create 10 notes",
                category: .knowledge,
                tier: .bronze,
                requirements: [.atomCount(10, type: "note")],
                iconName: "note.text",
                flavorText: "Capture knowledge, build understanding."
            ),
            BadgeDefinition(
                id: "knowledge_notes_silver",
                name: "Knowledge Keeper",
                description: "Create 100 notes",
                category: .knowledge,
                tier: .silver,
                requirements: [.atomCount(100, type: "note")],
                iconName: "note.text",
                flavorText: "Your second brain grows.",
                prerequisiteBadges: ["knowledge_notes_bronze"]
            ),
            BadgeDefinition(
                id: "knowledge_notes_gold",
                name: "Wisdom Weaver",
                description: "Create 500 interconnected notes",
                category: .knowledge,
                tier: .gold,
                requirements: [
                    .atomCount(500, type: "note"),
                    BadgeRequirement(type: .atomCount, dimension: .knowledge, threshold: 1000, atomType: "note_links")
                ],
                iconName: "note.text",
                flavorText: "A web of knowledge, ever expanding.",
                prerequisiteBadges: ["knowledge_notes_silver"]
            ),

            // Learning badges
            BadgeDefinition(
                id: "knowledge_learn_bronze",
                name: "Curious Mind",
                description: "Complete your first learning session",
                category: .knowledge,
                tier: .bronze,
                requirements: [.atomCount(1, type: "learning_session")],
                iconName: "graduationcap.fill",
                flavorText: "The beginning of wisdom is wonder."
            ),
            BadgeDefinition(
                id: "knowledge_learn_silver",
                name: "Knowledge Seeker",
                description: "Complete 50 learning sessions",
                category: .knowledge,
                tier: .silver,
                requirements: [.atomCount(50, type: "learning_session")],
                iconName: "graduationcap.fill",
                flavorText: "The mind that opens to a new idea never returns to its original size.",
                prerequisiteBadges: ["knowledge_learn_bronze"]
            ),

            // NELO
            BadgeDefinition(
                id: "knowledge_nelo_silver",
                name: "Knowledge Adept",
                description: "Reach 1200 NELO in Knowledge dimension",
                category: .knowledge,
                tier: .silver,
                requirements: [.neloRating(1200, in: .knowledge)],
                iconName: "brain",
                flavorText: "Your knowledge compounds."
            ),
            BadgeDefinition(
                id: "knowledge_nelo_gold",
                name: "Knowledge Master",
                description: "Reach 1600 NELO in Knowledge dimension",
                category: .knowledge,
                tier: .gold,
                requirements: [.neloRating(1600, in: .knowledge)],
                iconName: "brain",
                flavorText: "Deep understanding achieved.",
                prerequisiteBadges: ["knowledge_nelo_silver"]
            ),
            BadgeDefinition(
                id: "knowledge_nelo_platinum",
                name: "Sage",
                description: "Reach 2000 NELO in Knowledge dimension",
                category: .knowledge,
                tier: .platinum,
                requirements: [.neloRating(2000, in: .knowledge)],
                iconName: "brain",
                flavorText: "Wisdom flows through you.",
                prerequisiteBadges: ["knowledge_nelo_gold"]
            ),
        ]
    }

    // MARK: - Reflection Badges

    private static func reflectionBadges() -> [BadgeDefinition] {
        [
            // Journaling badges
            BadgeDefinition(
                id: "reflection_journal_bronze",
                name: "First Reflection",
                description: "Write your first journal entry",
                category: .reflection,
                tier: .bronze,
                requirements: [.atomCount(1, type: "journal_entry")],
                iconName: "book.closed.fill",
                flavorText: "Self-awareness begins with reflection."
            ),
            BadgeDefinition(
                id: "reflection_journal_silver",
                name: "Daily Reflector",
                description: "Journal for 30 consecutive days",
                category: .reflection,
                tier: .silver,
                requirements: [.streak(30, in: .reflection)],
                iconName: "book.closed.fill",
                flavorText: "A month of introspection.",
                prerequisiteBadges: ["reflection_journal_bronze"]
            ),
            BadgeDefinition(
                id: "reflection_journal_gold",
                name: "Contemplative Master",
                description: "Journal for 100 consecutive days",
                category: .reflection,
                tier: .gold,
                requirements: [.streak(100, in: .reflection)],
                iconName: "book.closed.fill",
                flavorText: "100 days of deep self-discovery.",
                prerequisiteBadges: ["reflection_journal_silver"]
            ),
            BadgeDefinition(
                id: "reflection_journal_platinum",
                name: "Inner Sage",
                description: "Journal for 365 consecutive days",
                category: .reflection,
                tier: .platinum,
                requirements: [.streak(365, in: .reflection)],
                iconName: "book.closed.fill",
                flavorText: "A year of daily wisdom captured.",
                prerequisiteBadges: ["reflection_journal_gold"]
            ),

            // Insight badges
            BadgeDefinition(
                id: "reflection_insight_bronze",
                name: "First Insight",
                description: "Capture your first insight",
                category: .reflection,
                tier: .bronze,
                requirements: [.atomCount(1, type: "insight")],
                iconName: "sparkles",
                flavorText: "The first light of understanding."
            ),
            BadgeDefinition(
                id: "reflection_insight_silver",
                name: "Pattern Finder",
                description: "Capture 25 insights",
                category: .reflection,
                tier: .silver,
                requirements: [.atomCount(25, type: "insight")],
                iconName: "sparkles",
                flavorText: "You see the patterns others miss.",
                prerequisiteBadges: ["reflection_insight_bronze"]
            ),
            BadgeDefinition(
                id: "reflection_insight_gold",
                name: "Wisdom Collector",
                description: "Capture 100 insights",
                category: .reflection,
                tier: .gold,
                requirements: [.atomCount(100, type: "insight")],
                iconName: "sparkles",
                flavorText: "A treasure trove of personal wisdom.",
                prerequisiteBadges: ["reflection_insight_silver"]
            ),

            // Emotional awareness badges
            BadgeDefinition(
                id: "reflection_emotion_bronze",
                name: "Emotional Observer",
                description: "Log 10 emotional states",
                category: .reflection,
                tier: .bronze,
                requirements: [.atomCount(10, type: "emotional_state")],
                iconName: "heart.text.square.fill",
                flavorText: "Name it to tame it."
            ),
            BadgeDefinition(
                id: "reflection_emotion_silver",
                name: "Emotional Intelligence",
                description: "Log 100 emotional states",
                category: .reflection,
                tier: .silver,
                requirements: [.atomCount(100, type: "emotional_state")],
                iconName: "heart.text.square.fill",
                flavorText: "Deep emotional awareness.",
                prerequisiteBadges: ["reflection_emotion_bronze"]
            ),
            BadgeDefinition(
                id: "reflection_emotion_gold",
                name: "Emotional Mastery",
                description: "Track emotional patterns for 90 days",
                category: .reflection,
                tier: .gold,
                requirements: [.uniqueDays(90, in: .reflection)],
                iconName: "heart.text.square.fill",
                flavorText: "Master of your inner world.",
                prerequisiteBadges: ["reflection_emotion_silver"]
            ),

            // NELO
            BadgeDefinition(
                id: "reflection_nelo_silver",
                name: "Self-Aware",
                description: "Reach 1200 NELO in Reflection dimension",
                category: .reflection,
                tier: .silver,
                requirements: [.neloRating(1200, in: .reflection)],
                iconName: "person.fill.questionmark",
                flavorText: "The examined life."
            ),
            BadgeDefinition(
                id: "reflection_nelo_gold",
                name: "Deep Thinker",
                description: "Reach 1600 NELO in Reflection dimension",
                category: .reflection,
                tier: .gold,
                requirements: [.neloRating(1600, in: .reflection)],
                iconName: "person.fill.questionmark",
                flavorText: "Profound self-understanding.",
                prerequisiteBadges: ["reflection_nelo_silver"]
            ),
        ]
    }

    // MARK: - Meta Badges (Cross-Dimensional)

    private static func metaBadges() -> [BadgeDefinition] {
        [
            // Balance badges
            BadgeDefinition(
                id: "meta_balance_bronze",
                name: "Balanced Start",
                description: "Earn at least one badge in 3 different dimensions",
                category: .meta,
                tier: .bronze,
                requirements: [
                    BadgeRequirement(type: .multiDimension, threshold: 3, metadata: ["type": "badge_count", "min": "1"])
                ],
                iconName: "scalemass.fill",
                flavorText: "The journey to wholeness begins."
            ),
            BadgeDefinition(
                id: "meta_balance_silver",
                name: "Well-Rounded",
                description: "Reach Silver tier in all 6 dimensions",
                category: .meta,
                tier: .silver,
                requirements: [
                    BadgeRequirement(type: .multiDimension, threshold: 6, metadata: ["type": "nelo_min", "min": "1200"])
                ],
                iconName: "scalemass.fill",
                flavorText: "Excellence in all dimensions.",
                prerequisiteBadges: ["meta_balance_bronze"]
            ),
            BadgeDefinition(
                id: "meta_balance_gold",
                name: "Renaissance Mind",
                description: "Reach Gold tier (1600 NELO) in all 6 dimensions",
                category: .meta,
                tier: .gold,
                requirements: [
                    BadgeRequirement(type: .multiDimension, threshold: 6, metadata: ["type": "nelo_min", "min": "1600"])
                ],
                iconName: "scalemass.fill",
                flavorText: "True polymathic excellence.",
                prerequisiteBadges: ["meta_balance_silver"]
            ),
            BadgeDefinition(
                id: "meta_balance_platinum",
                name: "Transcendent",
                description: "Reach Platinum tier (2000 NELO) in all 6 dimensions",
                category: .meta,
                tier: .platinum,
                requirements: [
                    BadgeRequirement(type: .multiDimension, threshold: 6, metadata: ["type": "nelo_min", "min": "2000"])
                ],
                iconName: "scalemass.fill",
                flavorText: "Beyond ordinary human limits.",
                prerequisiteBadges: ["meta_balance_gold"]
            ),

            // Consistency badges
            BadgeDefinition(
                id: "meta_streak_bronze",
                name: "Week Warrior",
                description: "Use Cosmo for 7 consecutive days",
                category: .meta,
                tier: .bronze,
                requirements: [.streak(7)],
                iconName: "flame.fill",
                flavorText: "Your streak begins."
            ),
            BadgeDefinition(
                id: "meta_streak_silver",
                name: "Month Master",
                description: "Use Cosmo for 30 consecutive days",
                category: .meta,
                tier: .silver,
                requirements: [.streak(30)],
                iconName: "flame.fill",
                flavorText: "A month of dedication.",
                prerequisiteBadges: ["meta_streak_bronze"]
            ),
            BadgeDefinition(
                id: "meta_streak_gold",
                name: "Quarter Champion",
                description: "Use Cosmo for 90 consecutive days",
                category: .meta,
                tier: .gold,
                requirements: [.streak(90)],
                iconName: "flame.fill",
                flavorText: "Quarter of a year, unstoppable.",
                prerequisiteBadges: ["meta_streak_silver"]
            ),
            BadgeDefinition(
                id: "meta_streak_platinum",
                name: "Year Legend",
                description: "Use Cosmo for 365 consecutive days",
                category: .meta,
                tier: .platinum,
                requirements: [.streak(365)],
                iconName: "flame.fill",
                flavorText: "365 days. Legendary.",
                prerequisiteBadges: ["meta_streak_gold"]
            ),
            BadgeDefinition(
                id: "meta_streak_diamond",
                name: "Eternal Flame",
                description: "Use Cosmo for 1000 consecutive days",
                category: .meta,
                tier: .diamond,
                requirements: [.streak(1000)],
                iconName: "flame.fill",
                flavorText: "The flame that never dies.",
                prerequisiteBadges: ["meta_streak_platinum"]
            ),

            // Synergy badges
            BadgeDefinition(
                id: "meta_synergy_gold",
                name: "Mind-Body Link",
                description: "Reach Gold in both Cognitive and Physiological dimensions on the same day",
                category: .meta,
                tier: .gold,
                requirements: [
                    .neloRating(1600, in: .cognitive),
                    .neloRating(1600, in: .physiological)
                ],
                requireAll: true,
                iconName: "figure.mind.and.body",
                flavorText: "Peak performance requires both mind and body."
            ),
        ]
    }

    // MARK: - Milestone Badges

    private static func milestoneBadges() -> [BadgeDefinition] {
        [
            // Level milestones
            BadgeDefinition(
                id: "milestone_level_10",
                name: "Double Digits",
                description: "Reach Cosmo Level 10",
                category: .milestone,
                tier: .bronze,
                requirements: [BadgeRequirement(type: .overallLevel, threshold: 10)],
                iconName: "10.circle.fill",
                flavorText: "Your journey truly begins."
            ),
            BadgeDefinition(
                id: "milestone_level_25",
                name: "Quarter Century",
                description: "Reach Cosmo Level 25",
                category: .milestone,
                tier: .silver,
                requirements: [BadgeRequirement(type: .overallLevel, threshold: 25)],
                iconName: "25.circle.fill",
                flavorText: "25 levels of growth.",
                prerequisiteBadges: ["milestone_level_10"]
            ),
            BadgeDefinition(
                id: "milestone_level_50",
                name: "Half Century",
                description: "Reach Cosmo Level 50",
                category: .milestone,
                tier: .gold,
                requirements: [BadgeRequirement(type: .overallLevel, threshold: 50)],
                iconName: "50.circle.fill",
                flavorText: "Halfway to mastery.",
                prerequisiteBadges: ["milestone_level_25"]
            ),
            BadgeDefinition(
                id: "milestone_level_75",
                name: "Three Quarters",
                description: "Reach Cosmo Level 75",
                category: .milestone,
                tier: .platinum,
                requirements: [BadgeRequirement(type: .overallLevel, threshold: 75)],
                iconName: "75.circle.fill",
                flavorText: "The final stretch approaches.",
                prerequisiteBadges: ["milestone_level_50"]
            ),
            BadgeDefinition(
                id: "milestone_level_100",
                name: "Centurion",
                description: "Reach Cosmo Level 100",
                category: .milestone,
                tier: .diamond,
                requirements: [BadgeRequirement(type: .overallLevel, threshold: 100)],
                iconName: "100.circle.fill",
                flavorText: "The pinnacle achieved.",
                prerequisiteBadges: ["milestone_level_75"]
            ),

            // Time-based milestones
            BadgeDefinition(
                id: "milestone_onboarding",
                name: "Welcome to Cosmo",
                description: "Complete the onboarding experience",
                category: .milestone,
                tier: .bronze,
                requirements: [.atomCount(1, type: "onboarding_complete")],
                iconName: "star.fill",
                flavorText: "Your cosmic journey begins."
            ),
            BadgeDefinition(
                id: "milestone_first_week",
                name: "First Week",
                description: "Complete your first week with Cosmo",
                category: .milestone,
                tier: .bronze,
                requirements: [.uniqueDays(7)],
                iconName: "calendar",
                flavorText: "The first of many weeks."
            ),
            BadgeDefinition(
                id: "milestone_first_month",
                name: "First Month",
                description: "Complete your first month with Cosmo",
                category: .milestone,
                tier: .silver,
                requirements: [.uniqueDays(30)],
                iconName: "calendar",
                flavorText: "A month of transformation.",
                prerequisiteBadges: ["milestone_first_week"]
            ),
            BadgeDefinition(
                id: "milestone_first_quarter",
                name: "First Quarter",
                description: "Complete your first 90 days with Cosmo",
                category: .milestone,
                tier: .gold,
                requirements: [.uniqueDays(90)],
                iconName: "calendar",
                flavorText: "A quarter of transformation.",
                prerequisiteBadges: ["milestone_first_month"]
            ),
            BadgeDefinition(
                id: "milestone_first_year",
                name: "First Year",
                description: "Complete your first year with Cosmo",
                category: .milestone,
                tier: .platinum,
                requirements: [.uniqueDays(365)],
                iconName: "calendar",
                flavorText: "One year. One transformed life.",
                prerequisiteBadges: ["milestone_first_quarter"]
            ),

            // Secret badges
            BadgeDefinition(
                id: "secret_night_owl",
                name: "Night Owl",
                description: "Complete 10 deep work sessions between midnight and 4am",
                category: .milestone,
                tier: .silver,
                requirements: [.atomCount(10, type: "night_session")],
                iconName: "moon.stars.fill",
                flavorText: "The night holds secrets for those who seek.",
                isSecret: true
            ),
            BadgeDefinition(
                id: "secret_early_bird",
                name: "Early Bird",
                description: "Start 50 days before 5am",
                category: .milestone,
                tier: .gold,
                requirements: [.atomCount(50, type: "early_start")],
                iconName: "sunrise.fill",
                flavorText: "While others sleep, you rise.",
                isSecret: true
            ),
            BadgeDefinition(
                id: "secret_perfectionist",
                name: "Perfectionist",
                description: "Achieve 100% daily completion for 30 consecutive days",
                category: .milestone,
                tier: .diamond,
                requirements: [
                    BadgeRequirement(type: .perfectScore, dimension: nil, threshold: 30)
                ],
                iconName: "checkmark.seal.fill",
                flavorText: "Perfection is not attainable, but if we chase perfection we can catch excellence.",
                isSecret: true
            ),
        ]
    }
}

// MARK: - Badge Atom Metadata

/// Metadata stored with badge atoms when earned
public struct BadgeEarnedMetadata: Codable, Sendable {
    public let badgeId: String
    public let badgeName: String
    public let tier: BadgeTier
    public let category: BadgeCategory
    public let earnedAt: Date
    public let xpAwarded: Int
    public let neloBonus: Int
    public let triggeringActionId: String?
    public let progressSnapshot: [String: Double]

    public init(
        badgeId: String,
        badgeName: String,
        tier: BadgeTier,
        category: BadgeCategory,
        earnedAt: Date = Date(),
        xpAwarded: Int,
        neloBonus: Int,
        triggeringActionId: String? = nil,
        progressSnapshot: [String: Double] = [:]
    ) {
        self.badgeId = badgeId
        self.badgeName = badgeName
        self.tier = tier
        self.category = category
        self.earnedAt = earnedAt
        self.xpAwarded = xpAwarded
        self.neloBonus = neloBonus
        self.triggeringActionId = triggeringActionId
        self.progressSnapshot = progressSnapshot
    }
}
