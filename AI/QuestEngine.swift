//
//  QuestEngine.swift
//  CosmoOS
//
//  Quest Completion Engine — evaluates daily quest progress against real
//  atom data sources (deep work blocks, journal entries, tasks, content phases).
//  Runs periodic evaluation every 60 seconds and posts completion notifications.
//

import Foundation
import Combine
import SwiftUI

// MARK: - QuestState

struct QuestState: Identifiable, Equatable {
    let id: String
    var title: String
    let description: String
    var xpReward: Int
    var progress: Double       // 0.0–1.0
    var isComplete: Bool
    var completedAt: Date?
    var streak: Int            // Consecutive days completed
    let iconName: String
    let accentColor: Color     // Dimension-based
    let requirement: QuestRequirement
    var allowManualComplete: Bool

    static func == (lhs: QuestState, rhs: QuestState) -> Bool {
        lhs.id == rhs.id &&
        lhs.progress == rhs.progress &&
        lhs.isComplete == rhs.isComplete &&
        lhs.streak == rhs.streak &&
        lhs.title == rhs.title &&
        lhs.xpReward == rhs.xpReward &&
        lhs.allowManualComplete == rhs.allowManualComplete
    }
}

// MARK: - Default Quest Definitions

struct QuestDefinition {
    let id: String
    var title: String
    var description: String
    var xpReward: Int
    let requirement: QuestRequirement
    let iconName: String
    let accentColor: Color
    var allowManualComplete: Bool

    init(
        id: String,
        title: String,
        description: String,
        xpReward: Int,
        requirement: QuestRequirement,
        iconName: String,
        accentColor: Color,
        allowManualComplete: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.xpReward = xpReward
        self.requirement = requirement
        self.iconName = iconName
        self.accentColor = accentColor
        self.allowManualComplete = allowManualComplete
    }

    static let defaults: [QuestDefinition] = [
        QuestDefinition(
            id: "deepFocus",
            title: "Deep Focus",
            description: "Complete a 25+ min deep work session",
            xpReward: 50,
            requirement: .deepWorkMinutes(target: 25),
            iconName: "brain.head.profile",
            accentColor: Color(red: 0.45, green: 0.35, blue: 0.95) // Cognitive purple
        ),
        QuestDefinition(
            id: "dailyReflection",
            title: "Daily Reflection",
            description: "Write a journal entry (50+ words)",
            xpReward: 30,
            requirement: .journalEntry,
            iconName: "book.fill",
            accentColor: Color(red: 0.30, green: 0.70, blue: 0.90) // Reflection blue
        ),
        QuestDefinition(
            id: "taskCrusher",
            title: "Task Crusher",
            description: "Complete 3 tasks today",
            xpReward: 40,
            requirement: .tasksCompleted(target: 3),
            iconName: "checkmark.circle.fill",
            accentColor: Color(red: 0.35, green: 0.80, blue: 0.50) // Behavioral green
        ),
        QuestDefinition(
            id: "creativeBurst",
            title: "Creative Burst",
            description: "Advance content to next phase",
            xpReward: 45,
            requirement: .wordsWritten(target: 1),
            iconName: "paintbrush.fill",
            accentColor: Color(red: 0.95, green: 0.55, blue: 0.30) // Creative orange
        ),
        QuestDefinition(
            id: "heartHealth",
            title: "Heart Health",
            description: "Log exercise or physical activity",
            xpReward: 35,
            requirement: .workoutCompleted(minutes: 1),
            iconName: "heart.fill",
            accentColor: Color(red: 0.90, green: 0.30, blue: 0.40), // Physiology red
            allowManualComplete: true
        ),
        QuestDefinition(
            id: "overachiever",
            title: "Overachiever",
            description: "Complete all daily quests",
            xpReward: 100,
            requirement: .streakMaintained,
            iconName: "star.fill",
            accentColor: Color(red: 1.0, green: 0.84, blue: 0.0) // Gold
        ),
    ]
}

// MARK: - QuestEngine

@MainActor
class QuestEngine: ObservableObject {

    // MARK: - Published State

    @Published var quests: [QuestState] = []
    @Published var streaks: [String: Int] = [:]  // questId -> consecutive days

    // MARK: - Dependencies

    private let atomRepository: AtomRepository
    private var evaluationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// User-customized quest definitions (empty = use defaults)
    private var customDefinitions: [QuestDefinition] = []

    /// The fixed number of base quests (excluding Overachiever)
    private let baseQuestCount = 5

    // MARK: - Init

    init(atomRepository: AtomRepository? = nil) {
        self.atomRepository = atomRepository ?? AtomRepository.shared
        initializeQuests()
    }

    // MARK: - Lifecycle

    /// Start periodic evaluation (every 60 seconds)
    func startEvaluation() {
        // Evaluate immediately
        Task { await evaluate() }

        // Then every 60 seconds
        evaluationTimer?.invalidate()
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.evaluate()
            }
        }

        // Immediate re-eval on specific quest-relevant events
        let triggerNotifications: [Notification.Name] = [
            .deepWorkSessionEnded,
            .taskCompleted,
        ]
        for name in triggerNotifications {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.evaluate()
                    }
                }
                .store(in: &cancellables)
        }

        // Re-eval when atoms change (catches journal writes, content phase, workouts, etc.)
        atomRepository.$atoms
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.evaluate()
                }
            }
            .store(in: &cancellables)
    }

    func stopEvaluation() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        cancellables.removeAll()
    }

    // MARK: - Quest Initialization

    private func initializeQuests() {
        let definitions = customDefinitions.isEmpty ? QuestDefinition.defaults : customDefinitions
        quests = definitions.map { def in
            QuestState(
                id: def.id,
                title: def.title,
                description: def.description,
                xpReward: def.xpReward,
                progress: 0,
                isComplete: false,
                completedAt: nil,
                streak: streaks[def.id] ?? 0,
                iconName: def.iconName,
                accentColor: def.accentColor,
                requirement: def.requirement,
                allowManualComplete: def.allowManualComplete
            )
        }
    }

    // MARK: - Evaluation

    /// Evaluate all quest progress against real data
    func evaluate() async {
        // Load streaks first
        await loadStreaks()

        var updatedQuests: [QuestState] = []
        var newCompletions: [QuestState] = []

        for quest in quests {
            // Skip overachiever — evaluated after all others
            if quest.id == "overachiever" { continue }

            let (progress, isComplete) = await evaluateRequirement(quest.requirement)

            var updated = quest
            let wasComplete = updated.isComplete
            // If already manually completed, preserve that state
            if !wasComplete {
                updated.progress = progress
                updated.isComplete = isComplete
            }
            updated.streak = streaks[quest.id] ?? 0

            if updated.isComplete && !wasComplete {
                updated.completedAt = Date()
                newCompletions.append(updated)
            }

            updatedQuests.append(updated)
        }

        // Evaluate Overachiever — ALL base quests (non-overachiever) must be complete (strict AND)
        let baseQuests = updatedQuests.filter { $0.id != "overachiever" }
        let completedBaseCount = baseQuests.filter { $0.isComplete }.count
        let totalBaseQuests = baseQuests.count
        let allOthersComplete = totalBaseQuests > 0 && baseQuests.allSatisfy { $0.isComplete }

        let definitions = customDefinitions.isEmpty ? QuestDefinition.defaults : customDefinitions
        if let overachieverDef = definitions.first(where: { $0.id == "overachiever" }) {
            let existingOverachiever = quests.first(where: { $0.id == "overachiever" })
            let wasComplete = existingOverachiever?.isComplete ?? false

            var overachiever = QuestState(
                id: overachieverDef.id,
                title: overachieverDef.title,
                description: overachieverDef.description,
                xpReward: overachieverDef.xpReward,
                progress: totalBaseQuests > 0 ? Double(completedBaseCount) / Double(totalBaseQuests) : 0,
                isComplete: allOthersComplete,
                completedAt: allOthersComplete ? (existingOverachiever?.completedAt ?? Date()) : nil,
                streak: streaks["overachiever"] ?? 0,
                iconName: overachieverDef.iconName,
                accentColor: overachieverDef.accentColor,
                requirement: overachieverDef.requirement,
                allowManualComplete: overachieverDef.allowManualComplete
            )

            if allOthersComplete && !wasComplete {
                overachiever.completedAt = Date()
                newCompletions.append(overachiever)
            }

            updatedQuests.append(overachiever)
        }

        quests = updatedQuests

        // Handle new completions
        for completed in newCompletions {
            await handleCompletion(completed)
        }
    }

    // MARK: - Requirement Evaluation

    private func evaluateRequirement(_ requirement: QuestRequirement) async -> (progress: Double, isComplete: Bool) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        switch requirement {

        // Deep Focus: 1+ deepWorkBlock atoms today with duration >= 25 min and focusScore > 70
        case .deepWorkMinutes(let target):
            do {
                let blocks = try await atomRepository.fetchAll(type: .deepWorkBlock)
                let todayBlocks = blocks.filter { atom in
                    guard let date = ISO8601DateFormatter().date(from: atom.createdAt) else { return false }
                    return calendar.isDate(date, inSameDayAs: todayStart)
                }

                // Find the best qualifying session (duration meets target AND focusScore > 70)
                var bestMinutes: Int = 0
                var bestQualifyingMinutes: Int = 0
                for block in todayBlocks {
                    if let meta = block.metadataValue(as: DeepWorkSessionMetadata.self) {
                        let minutes = meta.actualMinutes ?? meta.plannedMinutes
                        bestMinutes = max(bestMinutes, minutes)
                        // Quality gate: focusScore > 70 (or no score recorded yet = passes)
                        let qualifies = (meta.focusScore ?? 100) > 70
                        if qualifies {
                            bestQualifyingMinutes = max(bestQualifyingMinutes, minutes)
                        }
                    }
                }

                // Progress bar shows raw duration progress; completion requires quality
                let progress = min(1.0, Double(bestMinutes) / Double(target))
                let isComplete = bestQualifyingMinutes >= target
                return (progress, isComplete)
            } catch {
                return (0, false)
            }

        // Daily Reflection: 1+ journalEntry atoms today with body >= 50 words
        case .journalEntry:
            do {
                let entries = try await atomRepository.fetchAll(type: .journalEntry)
                let todayEntries = entries.filter { atom in
                    guard let date = ISO8601DateFormatter().date(from: atom.createdAt) else { return false }
                    return calendar.isDate(date, inSameDayAs: todayStart)
                }

                let qualifyingEntry = todayEntries.first { atom in
                    let wordCount = (atom.body ?? "")
                        .split(separator: " ", omittingEmptySubsequences: true)
                        .count
                    return wordCount >= 50
                }

                if qualifyingEntry != nil {
                    return (1.0, true)
                }

                // Partial progress based on best word count
                let bestWordCount = todayEntries.map { atom in
                    (atom.body ?? "")
                        .split(separator: " ", omittingEmptySubsequences: true)
                        .count
                }.max() ?? 0

                let progress = min(1.0, Double(bestWordCount) / 50.0)
                return (progress, false)
            } catch {
                return (0, false)
            }

        // Task Crusher: 3+ tasks completed today
        case .tasksCompleted(let target):
            do {
                let tasks = try await atomRepository.fetchAll(type: .task)
                let completedToday = tasks.filter { atom in
                    guard let meta = atom.metadataValue(as: TaskMetadata.self),
                          meta.isCompleted == true else { return false }

                    // Check completedAt date
                    if let completedAtStr = meta.completedAt,
                       let completedDate = ISO8601DateFormatter().date(from: completedAtStr) {
                        return calendar.isDate(completedDate, inSameDayAs: todayStart)
                    }

                    // Fall back to updatedAt if completedAt not set
                    if let date = ISO8601DateFormatter().date(from: atom.updatedAt) {
                        return calendar.isDate(date, inSameDayAs: todayStart)
                    }

                    return false
                }

                let count = completedToday.count
                let progress = min(1.0, Double(count) / Double(target))
                return (progress, count >= target)
            } catch {
                return (0, false)
            }

        // Creative Burst: 1+ contentPhase atoms created today
        case .wordsWritten(let target):
            do {
                let phases = try await atomRepository.fetchAll(type: .contentPhase)
                let todayPhases = phases.filter { atom in
                    guard let date = ISO8601DateFormatter().date(from: atom.createdAt) else { return false }
                    return calendar.isDate(date, inSameDayAs: todayStart)
                }

                let count = todayPhases.count
                let progress = min(1.0, Double(count) / Double(target))
                return (progress, count >= target)
            } catch {
                return (0, false)
            }

        // Heart Health: 1+ workout/task atoms today marked as physical activity
        case .workoutCompleted:
            do {
                // Check workout atoms
                let workouts = try await atomRepository.fetchAll(type: .workout)
                let todayWorkouts = workouts.filter { atom in
                    guard let date = ISO8601DateFormatter().date(from: atom.createdAt) else { return false }
                    return calendar.isDate(date, inSameDayAs: todayStart)
                }

                if !todayWorkouts.isEmpty {
                    return (1.0, true)
                }

                // Also check workoutSession atoms
                let sessions = try await atomRepository.fetchAll(type: .workoutSession)
                let todaySessions = sessions.filter { atom in
                    guard let date = ISO8601DateFormatter().date(from: atom.createdAt) else { return false }
                    return calendar.isDate(date, inSameDayAs: todayStart)
                }

                if !todaySessions.isEmpty {
                    return (1.0, true)
                }

                return (0, false)
            } catch {
                return (0, false)
            }

        // Streak maintained is handled by overachiever logic
        case .streakMaintained:
            return (0, false)

        // Fallback for unhandled types — mark as 0 progress
        default:
            return (0, false)
        }
    }

    // MARK: - Completion Handling

    private func handleCompletion(_ quest: QuestState) async {
        // Post completion notification
        NotificationCenter.default.post(
            name: Notification.Name("questCompleted"),
            object: nil,
            userInfo: [
                "questId": quest.id,
                "xpReward": quest.xpReward,
                "title": quest.title
            ]
        )

        // Award XP
        NotificationCenter.default.post(
            name: .xpAwarded,
            object: nil,
            userInfo: [
                "amount": quest.xpReward,
                "source": "quest",
                "questId": quest.id
            ]
        )

        // Store completion record as dimensionSnapshot for streak tracking
        await storeCompletionRecord(quest)
    }

    private func storeCompletionRecord(_ quest: QuestState) async {
        let metadata: [String: Any] = [
            "questId": quest.id,
            "questTitle": quest.title,
            "xpReward": quest.xpReward,
            "type": "questCompletion",
            "completedAt": ISO8601DateFormatter().string(from: Date())
        ]

        guard let metadataString = try? String(
            data: JSONSerialization.data(withJSONObject: metadata),
            encoding: .utf8
        ) else { return }

        do {
            try await atomRepository.create(
                type: .dimensionSnapshot,
                title: "Quest: \(quest.title)",
                body: "Completed daily quest — +\(quest.xpReward) XP",
                metadata: metadataString
            )
        } catch {
            // Non-critical — quest still counts as complete in-memory
        }
    }

    // MARK: - Streak Tracking

    private func loadStreaks() async {
        do {
            let snapshots = try await atomRepository.fetchAll(type: .dimensionSnapshot)

            // Filter to quest completion records
            let questRecords = snapshots.filter { atom in
                guard let metaStr = atom.metadata,
                      let data = metaStr.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return false
                }
                return dict["type"] as? String == "questCompletion"
            }

            // Group by questId and date
            var questDates: [String: Set<String>] = [:]  // questId -> set of date strings
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            for record in questRecords {
                guard let metaStr = record.metadata,
                      let data = metaStr.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let questId = dict["questId"] as? String else { continue }

                // Use completedAt from metadata, or fall back to atom createdAt
                let dateString: String
                if let completedAt = dict["completedAt"] as? String,
                   let date = ISO8601DateFormatter().date(from: completedAt) {
                    dateString = dateFormatter.string(from: date)
                } else if let date = ISO8601DateFormatter().date(from: record.createdAt) {
                    dateString = dateFormatter.string(from: date)
                } else {
                    continue
                }

                questDates[questId, default: []].insert(dateString)
            }

            // Calculate consecutive day streaks ending yesterday or today
            var newStreaks: [String: Int] = [:]
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            for (questId, dates) in questDates {
                var streak = 0
                var checkDate = today

                // Count backwards from today
                while true {
                    let checkString = dateFormatter.string(from: checkDate)
                    if dates.contains(checkString) {
                        streak += 1
                        guard let prevDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                        checkDate = prevDay
                    } else if calendar.isDateInToday(checkDate) {
                        // Today not yet completed is OK — check yesterday
                        guard let prevDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                        checkDate = prevDay
                    } else {
                        break
                    }
                }

                newStreaks[questId] = streak
            }

            streaks = newStreaks
        } catch {
            // Non-critical
        }
    }

    // MARK: - Manual Completion

    /// Manually complete a quest (for quests like Heart Health where activity happens outside app)
    func manualComplete(questId: String) async {
        guard let index = quests.firstIndex(where: { $0.id == questId }),
              quests[index].allowManualComplete,
              !quests[index].isComplete else { return }

        quests[index].isComplete = true
        quests[index].progress = 1.0
        quests[index].completedAt = Date()

        await handleCompletion(quests[index])

        // Re-evaluate overachiever after manual completion
        await evaluate()
    }

    // MARK: - Quest Customization

    /// Update a quest's title and XP reward
    func updateQuest(questId: String, title: String, xpReward: Int) {
        if let index = quests.firstIndex(where: { $0.id == questId }) {
            quests[index].title = title
            quests[index].xpReward = xpReward
        }
    }

    /// Remove a quest from the active list
    func deleteQuest(questId: String) {
        quests.removeAll { $0.id == questId }
    }

    // MARK: - Convenience

    var completedCount: Int {
        quests.filter { $0.isComplete }.count
    }

    var totalCount: Int {
        quests.count
    }

    var allComplete: Bool {
        quests.allSatisfy { $0.isComplete }
    }

    var totalXPAvailable: Int {
        quests.map { $0.xpReward }.reduce(0, +)
    }

    var earnedXP: Int {
        quests.filter { $0.isComplete }.map { $0.xpReward }.reduce(0, +)
    }
}
