import Foundation
import GRDB

// MARK: - Quest System

/// Daily quest system for gamified engagement
/// Based on video game psychology: clear goals, visible progress, meaningful rewards

// MARK: - Quest Definition

public struct Quest: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let dimension: String
    public let requirement: QuestRequirement
    public let xpReward: Int
    public let bonusXP: Int?              // For exceeding target
    public var progress: Double           // 0-1
    public var isComplete: Bool
    public let difficulty: QuestDifficulty
    public let expiresAt: Date
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String,
        dimension: String,
        requirement: QuestRequirement,
        xpReward: Int,
        bonusXP: Int? = nil,
        progress: Double = 0,
        isComplete: Bool = false,
        difficulty: QuestDifficulty = .normal,
        expiresAt: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.dimension = dimension
        self.requirement = requirement
        self.xpReward = xpReward
        self.bonusXP = bonusXP
        self.progress = progress
        self.isComplete = isComplete
        self.difficulty = difficulty
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }
}

// MARK: - Quest Requirement

public enum QuestRequirement: Codable, Sendable {
    case deepWorkMinutes(target: Int)
    case wordsWritten(target: Int)
    case tasksCompleted(target: Int)
    case journalEntry
    case hrvMeasurement
    case sleepTargetMet(hours: Double)
    case workoutCompleted(minutes: Int)
    case researchAdded(count: Int)
    case connectionsCreated(count: Int)
    case routineBlocks(count: Int)
    case ideasCaptured(count: Int)
    case notesCreated(count: Int)
    case readinessCheck
    case streakMaintained
    case customMetric(metric: String, target: Double)

    public var displayName: String {
        switch self {
        case .deepWorkMinutes(let target):
            return "Complete \(target) minutes of deep work"
        case .wordsWritten(let target):
            return "Write \(target) words"
        case .tasksCompleted(let target):
            return "Complete \(target) tasks"
        case .journalEntry:
            return "Write a journal entry"
        case .hrvMeasurement:
            return "Log an HRV measurement"
        case .sleepTargetMet(let hours):
            return "Get \(Int(hours)) hours of sleep"
        case .workoutCompleted(let minutes):
            return "Complete a \(minutes)+ minute workout"
        case .researchAdded(let count):
            return "Add \(count) research items"
        case .connectionsCreated(let count):
            return "Create \(count) connections"
        case .routineBlocks(let count):
            return "Complete \(count) routine blocks"
        case .ideasCaptured(let count):
            return "Capture \(count) ideas"
        case .notesCreated(let count):
            return "Create \(count) notes"
        case .readinessCheck:
            return "Check your readiness score"
        case .streakMaintained:
            return "Maintain your streak"
        case .customMetric(let metric, let target):
            return "Achieve \(Int(target)) \(metric)"
        }
    }
}

// MARK: - Quest Difficulty

public enum QuestDifficulty: String, Codable, Sendable, CaseIterable {
    case easy
    case normal
    case challenging
    case epic

    public var xpMultiplier: Double {
        switch self {
        case .easy: return 0.75
        case .normal: return 1.0
        case .challenging: return 1.5
        case .epic: return 2.0
        }
    }

    public var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Quest Category

public enum QuestCategory: String, Codable, Sendable {
    case main       // Primary daily quest
    case side       // Secondary quests
    case bonus      // Hidden until unlocked
    case weekly     // Week-long challenges
}

// MARK: - Daily Quests Container

public struct DailyQuests: Codable, Sendable {
    public let date: Date
    public var mainQuest: Quest
    public var sideQuests: [Quest]
    public var bonusQuest: Quest?
    public var allQuestsComplete: Bool

    public init(
        date: Date,
        mainQuest: Quest,
        sideQuests: [Quest],
        bonusQuest: Quest? = nil
    ) {
        self.date = date
        self.mainQuest = mainQuest
        self.sideQuests = sideQuests
        self.bonusQuest = bonusQuest
        self.allQuestsComplete = false
    }

    public var totalXPAvailable: Int {
        var total = mainQuest.xpReward
        total += sideQuests.map { $0.xpReward }.reduce(0, +)
        if let bonus = bonusQuest {
            total += bonus.xpReward
        }
        return total
    }

    public var completedQuestCount: Int {
        var count = mainQuest.isComplete ? 1 : 0
        count += sideQuests.filter { $0.isComplete }.count
        if bonusQuest?.isComplete == true { count += 1 }
        return count
    }

    public var totalQuestCount: Int {
        return 1 + sideQuests.count + (bonusQuest != nil ? 1 : 0)
    }

    public mutating func updateAllComplete() {
        allQuestsComplete = mainQuest.isComplete && sideQuests.allSatisfy { $0.isComplete }
    }
}

// MARK: - Daily Quest Engine

/// Generates and manages daily quests
/// Uses adaptive difficulty based on user performance
public final class DailyQuestEngine: Sendable {

    // MARK: - Quest Templates

    private struct QuestTemplates {
        // Cognitive quests
        static let cognitive: [(String, String, QuestRequirement, Int)] = [
            ("Deep Focus", "Complete a deep work session", .deepWorkMinutes(target: 45), 50),
            ("Word Warrior", "Write 500 words", .wordsWritten(target: 500), 40),
            ("Task Master", "Complete 5 tasks", .tasksCompleted(target: 5), 35),
            ("Marathon Writer", "Write 1000 words", .wordsWritten(target: 1000), 75),
            ("Deep Dive", "Complete 90 minutes of deep work", .deepWorkMinutes(target: 90), 100),
        ]

        // Creative quests
        static let creative: [(String, String, QuestRequirement, Int)] = [
            ("Idea Generator", "Capture 3 ideas", .ideasCaptured(count: 3), 30),
            ("Creative Burst", "Capture 5 ideas", .ideasCaptured(count: 5), 50),
            ("Brainstorm Master", "Capture 10 ideas", .ideasCaptured(count: 10), 100),
        ]

        // Physiological quests
        static let physiological: [(String, String, QuestRequirement, Int)] = [
            ("Recovery Check", "Check your readiness score", .readinessCheck, 20),
            ("Heart Health", "Log an HRV measurement", .hrvMeasurement, 25),
            ("Move It", "Complete a 30-minute workout", .workoutCompleted(minutes: 30), 50),
            ("Rest Well", "Get 7 hours of sleep", .sleepTargetMet(hours: 7), 40),
            ("Elite Recovery", "Get 8 hours of quality sleep", .sleepTargetMet(hours: 8), 60),
        ]

        // Behavioral quests
        static let behavioral: [(String, String, QuestRequirement, Int)] = [
            ("Routine Keeper", "Complete 2 routine blocks", .routineBlocks(count: 2), 30),
            ("Task Crusher", "Complete 10 tasks", .tasksCompleted(target: 10), 60),
            ("Streak Keeper", "Maintain your streak", .streakMaintained, 50),
        ]

        // Knowledge quests
        static let knowledge: [(String, String, QuestRequirement, Int)] = [
            ("Note Taker", "Create 3 notes", .notesCreated(count: 3), 30),
            ("Researcher", "Add 2 research items", .researchAdded(count: 2), 40),
            ("Connection Maker", "Create 5 connections", .connectionsCreated(count: 5), 50),
        ]

        // Reflection quests
        static let reflection: [(String, String, QuestRequirement, Int)] = [
            ("Daily Reflection", "Write a journal entry", .journalEntry, 35),
        ]
    }

    // MARK: - Quest Generation

    /// Generate daily quests for a user
    public func generateDailyQuests(
        for date: Date,
        userLevel: Int,
        dimensionLevels: [String: Int],
        recentPerformance: [String: Double],
        currentStreak: Int
    ) -> DailyQuests {
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!

        // Find weakest dimension for main quest focus
        let weakestDimension = dimensionLevels.min { $0.value < $1.value }?.key ?? "cognitive"

        // Generate main quest targeting weakest dimension
        let mainQuest = generateMainQuest(
            dimension: weakestDimension,
            level: userLevel,
            expiresAt: endOfDay
        )

        // Generate 3-4 side quests across different dimensions
        let sideQuests = generateSideQuests(
            excludeDimension: weakestDimension,
            level: userLevel,
            performance: recentPerformance,
            expiresAt: endOfDay
        )

        // Generate bonus quest (hidden until all others complete)
        let bonusQuest = generateBonusQuest(
            level: userLevel,
            streak: currentStreak,
            expiresAt: endOfDay
        )

        return DailyQuests(
            date: date,
            mainQuest: mainQuest,
            sideQuests: sideQuests,
            bonusQuest: bonusQuest
        )
    }

    private func generateMainQuest(
        dimension: String,
        level: Int,
        expiresAt: Date
    ) -> Quest {
        let templates: [(String, String, QuestRequirement, Int)]

        switch dimension {
        case "cognitive":
            templates = QuestTemplates.cognitive
        case "creative":
            templates = QuestTemplates.creative
        case "physiological":
            templates = QuestTemplates.physiological
        case "behavioral":
            templates = QuestTemplates.behavioral
        case "knowledge":
            templates = QuestTemplates.knowledge
        case "reflection":
            templates = QuestTemplates.reflection
        default:
            templates = QuestTemplates.cognitive
        }

        // Select based on level
        let index = min(templates.count - 1, level / 25)  // Harder quests at higher levels
        let template = templates[index]

        // Scale XP with level
        let scaledXP = Int(Double(template.3) * (1.0 + Double(level) * 0.01))

        return Quest(
            title: template.0,
            description: template.1,
            dimension: dimension,
            requirement: template.2,
            xpReward: scaledXP,
            bonusXP: scaledXP / 2,  // 50% bonus for exceeding target
            difficulty: .normal,
            expiresAt: expiresAt
        )
    }

    private func generateSideQuests(
        excludeDimension: String,
        level: Int,
        performance: [String: Double],
        expiresAt: Date
    ) -> [Quest] {
        var quests: [Quest] = []
        let dimensions = ["cognitive", "creative", "physiological", "behavioral", "knowledge", "reflection"]
            .filter { $0 != excludeDimension }
            .shuffled()

        // Pick 3-4 dimensions
        let selectedDimensions = Array(dimensions.prefix(min(4, max(3, dimensions.count))))

        for dimension in selectedDimensions {
            let templates: [(String, String, QuestRequirement, Int)]

            switch dimension {
            case "cognitive": templates = QuestTemplates.cognitive
            case "creative": templates = QuestTemplates.creative
            case "physiological": templates = QuestTemplates.physiological
            case "behavioral": templates = QuestTemplates.behavioral
            case "knowledge": templates = QuestTemplates.knowledge
            case "reflection": templates = QuestTemplates.reflection
            default: continue
            }

            guard !templates.isEmpty else { continue }

            // Adaptive difficulty based on recent performance
            let perf = performance[dimension] ?? 0.5
            let difficultyIndex: Int
            if perf > 0.8 {
                difficultyIndex = min(templates.count - 1, 2)  // Harder
            } else if perf < 0.5 {
                difficultyIndex = 0  // Easier
            } else {
                difficultyIndex = min(templates.count - 1, 1)  // Normal
            }

            let template = templates[difficultyIndex]
            let scaledXP = Int(Double(template.3) * (1.0 + Double(level) * 0.005))

            quests.append(Quest(
                title: template.0,
                description: template.1,
                dimension: dimension,
                requirement: template.2,
                xpReward: scaledXP,
                difficulty: perf > 0.8 ? .challenging : .normal,
                expiresAt: expiresAt
            ))
        }

        return quests
    }

    private func generateBonusQuest(
        level: Int,
        streak: Int,
        expiresAt: Date
    ) -> Quest {
        // Bonus quest is always challenging
        let baseXP = 200 + level * 2
        let streakBonus = min(streak * 5, 100)

        return Quest(
            title: "Overachiever",
            description: "Complete all daily quests to unlock this bonus challenge",
            dimension: "meta",
            requirement: .deepWorkMinutes(target: 30),  // Extra deep work
            xpReward: baseXP + streakBonus,
            bonusXP: (baseXP + streakBonus) / 2,
            difficulty: .epic,
            expiresAt: expiresAt
        )
    }

    // MARK: - Quest Progress Tracking

    /// Update quest progress based on an action
    public func updateQuestProgress(
        quests: inout DailyQuests,
        action: QuestAction,
        value: Double
    ) -> [QuestCompletionEvent] {
        var completions: [QuestCompletionEvent] = []

        // Check main quest
        if let event = checkAndUpdateQuest(&quests.mainQuest, action: action, value: value) {
            completions.append(event)
        }

        // Check side quests
        for i in quests.sideQuests.indices {
            if let event = checkAndUpdateQuest(&quests.sideQuests[i], action: action, value: value) {
                completions.append(event)
            }
        }

        // Check if bonus quest is now unlocked
        quests.updateAllComplete()
        if quests.allQuestsComplete, var bonus = quests.bonusQuest, !bonus.isComplete {
            // Bonus quest is now active
            if let event = checkAndUpdateQuest(&bonus, action: action, value: value) {
                completions.append(event)
            }
            quests.bonusQuest = bonus
        }

        return completions
    }

    private func checkAndUpdateQuest(
        _ quest: inout Quest,
        action: QuestAction,
        value: Double
    ) -> QuestCompletionEvent? {
        guard !quest.isComplete else { return nil }

        // Check if action matches quest requirement
        let matches = doesActionMatchRequirement(action: action, requirement: quest.requirement)
        guard matches else { return nil }

        // Update progress
        let target = targetForRequirement(quest.requirement)
        quest.progress = min(1.0, value / target)

        // Check completion
        if quest.progress >= 1.0 {
            quest.isComplete = true

            // Calculate bonus for exceeding
            var totalXP = quest.xpReward
            if value > target, let bonus = quest.bonusXP {
                totalXP += bonus
            }

            return QuestCompletionEvent(
                quest: quest,
                xpAwarded: totalXP,
                exceededTarget: value > target,
                completedAt: Date()
            )
        }

        return nil
    }

    private func doesActionMatchRequirement(action: QuestAction, requirement: QuestRequirement) -> Bool {
        switch (action, requirement) {
        case (.deepWork, .deepWorkMinutes): return true
        case (.wordsWritten, .wordsWritten): return true
        case (.taskComplete, .tasksCompleted): return true
        case (.journalEntry, .journalEntry): return true
        case (.hrvLogged, .hrvMeasurement): return true
        case (.sleepLogged, .sleepTargetMet): return true
        case (.workoutComplete, .workoutCompleted): return true
        case (.researchAdded, .researchAdded): return true
        case (.connectionCreated, .connectionsCreated): return true
        case (.routineComplete, .routineBlocks): return true
        case (.ideaCaptured, .ideasCaptured): return true
        case (.noteCreated, .notesCreated): return true
        case (.readinessChecked, .readinessCheck): return true
        case (.streakMaintained, .streakMaintained): return true
        default: return false
        }
    }

    private func targetForRequirement(_ requirement: QuestRequirement) -> Double {
        switch requirement {
        case .deepWorkMinutes(let target): return Double(target)
        case .wordsWritten(let target): return Double(target)
        case .tasksCompleted(let target): return Double(target)
        case .journalEntry: return 1
        case .hrvMeasurement: return 1
        case .sleepTargetMet(let hours): return hours
        case .workoutCompleted(let minutes): return Double(minutes)
        case .researchAdded(let count): return Double(count)
        case .connectionsCreated(let count): return Double(count)
        case .routineBlocks(let count): return Double(count)
        case .ideasCaptured(let count): return Double(count)
        case .notesCreated(let count): return Double(count)
        case .readinessCheck: return 1
        case .streakMaintained: return 1
        case .customMetric(_, let target): return target
        }
    }

    // MARK: - Quest Persistence

    /// Create a quest atom for storage
    public func createQuestAtom(from quests: DailyQuests) -> Atom {
        let metadataJSON: String
        if let data = try? JSONEncoder().encode(quests),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        return Atom.new(
            type: .systemEvent,
            title: "Daily Quests - \(quests.date.formatted(date: .abbreviated, time: .omitted))",
            body: "\(quests.completedQuestCount)/\(quests.totalQuestCount) quests completed",
            metadata: metadataJSON
        )
    }
}

// MARK: - Quest Action

public enum QuestAction: String, Sendable {
    case deepWork
    case wordsWritten
    case taskComplete
    case journalEntry
    case hrvLogged
    case sleepLogged
    case workoutComplete
    case researchAdded
    case connectionCreated
    case routineComplete
    case ideaCaptured
    case noteCreated
    case readinessChecked
    case streakMaintained
}

// MARK: - Quest Completion Event

public struct QuestCompletionEvent: Sendable {
    public let quest: Quest
    public let xpAwarded: Int
    public let exceededTarget: Bool
    public let completedAt: Date

    public init(
        quest: Quest,
        xpAwarded: Int,
        exceededTarget: Bool,
        completedAt: Date
    ) {
        self.quest = quest
        self.xpAwarded = xpAwarded
        self.exceededTarget = exceededTarget
        self.completedAt = completedAt
    }
}

// MARK: - AtomType Extension

extension AtomType {
    static var dailyQuest: AtomType {
        // Would be added to the AtomType enum
        .routineDefinition  // Temporary placeholder
    }
}
