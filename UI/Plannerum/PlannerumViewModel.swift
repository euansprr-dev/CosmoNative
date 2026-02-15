//
//  PlannerumViewModel.swift
//  CosmoOS
//
//  Main ViewModel for the redesigned Plannerum task-centric view.
//  Orchestrates task recommendations, daily quests, and health-aware prioritization.
//

import Foundation
import SwiftUI
import Combine

// MARK: - PlannerumViewModel

/// Main view model for Plannerum's task-centric redesign
/// Integrates TaskRecommendationEngine, DailyQuestEngine, and health data
@MainActor
public final class PlannerumViewModel: ObservableObject {

    // MARK: - Singleton

    public static let shared = PlannerumViewModel()

    // MARK: - Published State

    /// Current Focus Now recommendation
    @Published public private(set) var focusNowTask: TaskRecommendation?

    /// Alternative task recommendations
    @Published public private(set) var alternativeTasks: [TaskRecommendation] = []

    /// All tasks for today (scheduled or due)
    @Published public private(set) var todayTasks: [TaskViewModel] = []

    /// Daily quests state
    @Published public private(set) var dailyQuests: DailyQuests?

    /// Upcoming days with their tasks
    @Published public private(set) var upcomingDays: [UpcomingDayViewModel] = []

    /// Current user energy level (0-100)
    @Published public private(set) var currentEnergy: Int = 50

    /// Current user focus level (0-100)
    @Published public private(set) var currentFocus: Int = 50

    /// Context message based on current state
    @Published public private(set) var contextMessage: String = TaskRecommendationEngine.defaultContextMessage

    /// XP progress state
    @Published public private(set) var xpProgress: XPProgressState = XPProgressState()

    /// Loading states
    @Published public private(set) var isLoadingTasks: Bool = false
    @Published public private(set) var isLoadingQuests: Bool = false

    /// Error state
    @Published public private(set) var lastError: Error?

    /// Time of next scheduled commitment (for time-fit recommendations)
    @Published public var nextCommitmentAt: Date?

    // MARK: - Quest Engine (real data-driven)

    /// Quest completion engine — evaluates quests against real atom data
    let liveQuestEngine: QuestEngine = QuestEngine()

    // MARK: - Dependencies

    private let atomRepository: AtomRepository
    private let recommendationEngine: TaskRecommendationEngine
    private let questEngine: DailyQuestEngine
    private let recurrenceEngine: TaskRecurrenceEngine
    private let sanctuaryProvider: SanctuaryDataProvider?

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        atomRepository: AtomRepository? = nil,
        recommendationEngine: TaskRecommendationEngine? = nil,
        questEngine: DailyQuestEngine = DailyQuestEngine(),
        recurrenceEngine: TaskRecurrenceEngine? = nil,
        sanctuaryProvider: SanctuaryDataProvider? = nil
    ) {
        self.atomRepository = atomRepository ?? AtomRepository.shared
        self.recommendationEngine = recommendationEngine ?? TaskRecommendationEngine.shared
        self.questEngine = questEngine
        self.recurrenceEngine = recurrenceEngine ?? TaskRecurrenceEngine.shared
        self.sanctuaryProvider = sanctuaryProvider

        setupSubscriptions()

        // Start live quest evaluation
        liveQuestEngine.startEvaluation()
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Setup

    private func setupSubscriptions() {
        // Subscribe to atom changes for live updates
        atomRepository.$atoms
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadTodayTasks()
                    await self?.generateRecommendation()
                }
            }
            .store(in: &cancellables)

        // Subscribe to sanctuary health updates if available
        sanctuaryProvider?.$state
            .compactMap { $0?.liveMetrics }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.updateHealthMetrics(from: metrics)
            }
            .store(in: &cancellables)

        // Listen for task completion events
        NotificationCenter.default.publisher(for: .taskCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let taskId = notification.userInfo?["taskId"] as? String {
                    self?.handleTaskCompleted(taskId: taskId)
                }
            }
            .store(in: &cancellables)

        // Listen for quest progress events
        NotificationCenter.default.publisher(for: .questProgressUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadQuests()
                }
            }
            .store(in: &cancellables)
    }

    private func updateHealthMetrics(from metrics: LiveMetrics) {
        // Calculate focus percentage (target: 240 minutes of focus per day)
        let focusPercentage = min(100, (metrics.todayFocusMinutes * 100) / 240)
        currentFocus = focusPercentage

        // Calculate energy from HRV if available
        if let hrv = metrics.currentHRV {
            // HRV-based energy: normalize to 0-100
            currentEnergy = min(100, Int(hrv))
        }

        // Update context message
        contextMessage = TaskRecommendationEngine.contextMessage(
            focus: currentFocus,
            energy: currentEnergy
        )
    }

    // MARK: - Main API

    /// Full refresh of all Plannerum data
    public func refresh() async {
        // Generate recurring task instances before loading tasks
        try? await recurrenceEngine.generateTodayInstances()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadTodayTasks() }
            group.addTask { await self.loadQuests() }
            group.addTask { await self.loadUpcomingDays() }
            group.addTask { await self.loadXPProgress() }
        }

        await generateRecommendation()
    }

    /// Start live updates
    public func startLiveUpdates() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // Refresh every minute
            }
        }

        // Schedule midnight recurrence generation
        recurrenceEngine.scheduleMidnightRefresh()
    }

    /// Stop live updates
    public func stopLiveUpdates() {
        refreshTask?.cancel()
        refreshTask = nil
        recurrenceEngine.stopMidnightRefresh()
    }

    // MARK: - Task Operations

    /// Load today's tasks
    public func loadTodayTasks() async {
        isLoadingTasks = true
        defer { isLoadingTasks = false }

        do {
            let allTasks = try await atomRepository.fetchAll(type: .task)
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

            todayTasks = allTasks.compactMap { atom -> TaskViewModel? in
                guard let viewModel = TaskViewModel.from(atom: atom) else { return nil }

                // Exclude recurring templates -- only show generated instances
                if viewModel.isRecurring && viewModel.recurrenceParentUUID == nil {
                    return nil
                }

                // Include if:
                // 1. Scheduled for today
                // 2. Due today or overdue
                // 3. Not completed

                if viewModel.isCompleted { return nil }

                let isDueToday = viewModel.dueDate.map { $0 >= today && $0 < tomorrow } ?? false
                let isOverdue = viewModel.isOverdue
                let isScheduledToday = viewModel.scheduledDate.map { $0 >= today && $0 < tomorrow } ?? false

                if isDueToday || isOverdue || isScheduledToday {
                    return viewModel
                }

                return nil
            }
            .sorted { task1, task2 in
                // Sort by: overdue first, then by scheduled time, then by priority
                if task1.isOverdue != task2.isOverdue {
                    return task1.isOverdue
                }
                if let time1 = task1.scheduledTime, let time2 = task2.scheduledTime {
                    return time1 < time2
                }
                return task1.priority.sortOrder < task2.priority.sortOrder
            }

        } catch {
            lastError = error
        }
    }

    /// Generate task recommendation based on current state
    public func generateRecommendation() async {
        do {
            let (primary, alternatives) = try await recommendationEngine.getRecommendations(
                currentEnergy: currentEnergy,
                currentFocus: currentFocus,
                nextCommitmentAt: nextCommitmentAt,
                limit: 5
            )

            focusNowTask = primary
            alternativeTasks = alternatives

            // Update context message
            if primary != nil {
                contextMessage = TaskRecommendationEngine.contextMessage(
                    focus: currentFocus,
                    energy: currentEnergy
                )
            } else {
                contextMessage = "All caught up! Time to capture new ideas."
            }

        } catch {
            lastError = error
        }
    }

    /// Skip the current Focus Now recommendation
    public func skipFocusNow() async {
        guard let current = focusNowTask else { return }

        // Move to next alternative
        if let next = alternativeTasks.first {
            focusNowTask = next
            alternativeTasks = Array(alternativeTasks.dropFirst())
        } else {
            focusNowTask = nil
        }

        // Record skip for adaptive learning
        await recordTaskSkip(taskId: current.task.id)
    }

    /// Complete a task
    public func completeTask(taskId: String) async {
        do {
            guard var atom = try await atomRepository.fetch(uuid: taskId) else { return }

            // Update metadata
            var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            metadata.isCompleted = true
            metadata.completedAt = ISO8601DateFormatter().string(from: Date())

            if let data = try? JSONEncoder().encode(metadata),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }

            // Update in database
            try await atomRepository.update(atom)

            // Post notification for other systems (XP, quests, etc.)
            NotificationCenter.default.post(
                name: .taskCompleted,
                object: nil,
                userInfo: ["taskId": taskId]
            )

            // Update quest progress
            if var quests = dailyQuests {
                let completions = questEngine.updateQuestProgress(
                    quests: &quests,
                    action: .taskComplete,
                    value: 1
                )
                dailyQuests = quests

                // Handle any quest completions
                for completion in completions {
                    await handleQuestCompletion(completion)
                }
            }

            // Refresh recommendations
            await loadTodayTasks()
            await generateRecommendation()

        } catch {
            lastError = error
        }
    }

    private func handleTaskCompleted(taskId: String) {
        // Remove from today's tasks
        todayTasks.removeAll { $0.id == taskId }

        // If this was the focus task, move to next
        if focusNowTask?.task.id == taskId {
            Task {
                await generateRecommendation()
            }
        }
    }

    private func recordTaskSkip(taskId: String) async {
        // Record skip in task metadata for adaptive recommendations
        do {
            guard var atom = try await atomRepository.fetch(uuid: taskId) else { return }

            var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            metadata.skipCount = (metadata.skipCount ?? 0) + 1
            metadata.lastScheduledAt = ISO8601DateFormatter().string(from: Date())

            if let data = try? JSONEncoder().encode(metadata),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
                try await atomRepository.update(atom)
            }
        } catch {
            // Skip tracking is non-critical
        }
    }

    // MARK: - Quest Operations

    /// Load daily quests
    public func loadQuests() async {
        isLoadingQuests = true
        defer { isLoadingQuests = false }

        // Generate or load today's quests
        let today = Date()

        // Get user level and dimension data from existing systems
        let userLevel = xpProgress.level
        let dimensionLevels: [String: Int] = [:] // Would load from CosmoLevelState
        let recentPerformance: [String: Double] = [:] // Would calculate from recent activity

        dailyQuests = questEngine.generateDailyQuests(
            for: today,
            userLevel: userLevel,
            dimensionLevels: dimensionLevels,
            recentPerformance: recentPerformance,
            currentStreak: xpProgress.streak
        )
    }

    private func handleQuestCompletion(_ event: QuestCompletionEvent) async {
        // Post XP award notification
        NotificationCenter.default.post(
            name: .xpAwarded,
            object: nil,
            userInfo: [
                "amount": event.xpAwarded,
                "source": "quest",
                "questId": event.quest.id
            ]
        )

        // Refresh XP progress
        await loadXPProgress()
    }

    // MARK: - Upcoming Days

    /// Load upcoming days with their tasks
    public func loadUpcomingDays() async {
        do {
            let allTasks = try await atomRepository.fetchAll(type: .task)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            // Get tasks for next 7 days
            var dayViewModels: [UpcomingDayViewModel] = []

            for dayOffset in 1...7 {
                guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                    continue
                }

                let dayStart = calendar.startOfDay(for: dayDate)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

                let dayTasks = allTasks.compactMap { atom -> TaskViewModel? in
                    guard let viewModel = TaskViewModel.from(atom: atom) else { return nil }
                    if viewModel.isCompleted { return nil }

                    // Check if scheduled or due on this day
                    let isScheduled = viewModel.scheduledDate.map { $0 >= dayStart && $0 < dayEnd } ?? false
                    let isDue = viewModel.dueDate.map { $0 >= dayStart && $0 < dayEnd } ?? false

                    return (isScheduled || isDue) ? viewModel : nil
                }
                .sorted { $0.priority.sortOrder < $1.priority.sortOrder }

                dayViewModels.append(UpcomingDayViewModel(date: dayDate, tasks: dayTasks))
            }

            upcomingDays = dayViewModels

        } catch {
            lastError = error
        }
    }

    // MARK: - XP Progress

    /// Load XP and level progress
    public func loadXPProgress() async {
        // This would integrate with CosmoLevelSystem
        // For now, use placeholder values
        xpProgress = XPProgressState(
            level: 1,
            currentXP: 0,
            xpToNextLevel: 100,
            progress: 0,
            streak: 0,
            rank: "Novice"
        )
    }

    // MARK: - Focus Session

    /// Start a focus session for the current Focus Now task
    public func startFocusSession() async -> FocusSessionRequest? {
        guard let task = focusNowTask?.task else { return nil }

        return FocusSessionRequest(
            taskId: task.id,
            taskTitle: task.title,
            estimatedMinutes: task.estimatedMinutes,
            taskType: task.taskType,
            energyLevel: task.energyLevel,
            cognitiveLoad: task.cognitiveLoad
        )
    }

    // MARK: - Intent-Based Session Routing

    /// Start a session for a task, routing to the appropriate workspace based on intent.
    ///
    /// For `.writeContent`:
    /// - If `linkedContentUUID` is set, navigates directly to content focus mode
    /// - If `linkedIdeaUUID` is set, navigates to idea detail for activation
    /// - If neither, opens Ideas inbox (optionally filtered by project)
    public func startSession(for task: TaskViewModel) {
        var userInfo: [AnyHashable: Any] = ["taskId": task.id, "taskTitle": task.title]

        switch task.intent {
        case .writeContent:
            if let contentUUID = task.linkedContentUUID {
                userInfo["linkedContentUUID"] = contentUUID
                userInfo["route"] = "contentFocusMode"
            } else if let ideaUUID = task.linkedIdeaUUID {
                userInfo["linkedIdeaUUID"] = ideaUUID
                userInfo["route"] = "ideaDetail"
            } else {
                if let projectUUID = task.projectUuid {
                    userInfo["projectFilter"] = projectUUID
                }
                userInfo["route"] = "ideasInbox"
            }
            NotificationCenter.default.post(name: Notification.Name.navigateToContentWorkflow, object: nil, userInfo: userInfo)

        case .research:
            userInfo["context"] = task.title
            if let atomUUID = task.linkedAtomUUID {
                userInfo["linkedAtomUUID"] = atomUUID
            }
            NotificationCenter.default.post(name: Notification.Name.navigateToResearch, object: nil, userInfo: userInfo)

        case .studySwipes:
            NotificationCenter.default.post(name: Notification.Name.navigateToSwipeGallery, object: nil, userInfo: userInfo)

        case .deepThink:
            if let atomUUID = task.linkedAtomUUID {
                userInfo["linkedAtomUUID"] = atomUUID
            }
            NotificationCenter.default.post(name: Notification.Name.navigateToConnection, object: nil, userInfo: userInfo)

        case .review:
            if let contentUUID = task.linkedContentUUID {
                userInfo["linkedContentUUID"] = contentUUID
            }
            if let atomUUID = task.linkedAtomUUID {
                userInfo["linkedAtomUUID"] = atomUUID
            }
            NotificationCenter.default.post(name: Notification.Name.navigateToAtom, object: nil, userInfo: userInfo)

        case .general, .custom:
            NotificationCenter.default.post(name: Notification.Name.startTimerOnlySession, object: nil, userInfo: userInfo)
        }
    }

    /// Update linkedIdeaUUID on a task (e.g. after user selects an idea during writeContent session start)
    public func updateTaskLink(taskId: String, linkedIdeaUUID: String?, linkedContentUUID: String?) async {
        do {
            guard var atom = try await atomRepository.fetch(uuid: taskId) else { return }

            var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            metadata.linkedIdeaUUID = linkedIdeaUUID
            metadata.linkedContentUUID = linkedContentUUID

            if let data = try? JSONEncoder().encode(metadata),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
                try await atomRepository.update(atom)
            }
        } catch {
            lastError = error
        }
    }

    // MARK: - Task Creation

    /// Quick add a task for today
    public func quickAddTask(
        title: String,
        priority: TaskPriority = .medium,
        intent: TaskIntent = .general,
        linkedIdeaUUID: String? = nil,
        linkedContentUUID: String? = nil,
        linkedAtomUUID: String? = nil,
        recurrenceJSON: String? = nil
    ) async {
        var metadata = TaskMetadata(
            priority: priority.rawValue,
            isCompleted: false,
            focusDate: ISO8601DateFormatter().string(from: Date())
        )
        metadata.intent = intent.rawValue
        metadata.linkedIdeaUUID = linkedIdeaUUID
        metadata.linkedContentUUID = linkedContentUUID
        metadata.linkedAtomUUID = linkedAtomUUID
        metadata.recurrence = recurrenceJSON

        var metadataString: String?
        if let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataString = json
        }

        let atom = Atom.new(
            type: .task,
            title: title,
            body: nil,
            metadata: metadataString
        )

        do {
            try await atomRepository.create(atom)
            await loadTodayTasks()
            await generateRecommendation()
        } catch {
            lastError = error
        }
    }
}

// MARK: - Supporting Types

/// XP and level progress state
public struct XPProgressState: Equatable, Sendable {
    public let level: Int
    public let currentXP: Int
    public let xpToNextLevel: Int
    public let progress: Double
    public let streak: Int
    public let rank: String

    public init(
        level: Int = 1,
        currentXP: Int = 0,
        xpToNextLevel: Int = 100,
        progress: Double = 0,
        streak: Int = 0,
        rank: String = "Novice"
    ) {
        self.level = level
        self.currentXP = currentXP
        self.xpToNextLevel = xpToNextLevel
        self.progress = progress
        self.streak = streak
        self.rank = rank
    }
}

/// Request to start a focus session
public struct FocusSessionRequest: Equatable, Sendable {
    public let taskId: String
    public let taskTitle: String
    public let estimatedMinutes: Int
    public let taskType: TaskCategoryType?
    public let energyLevel: EnergyLevel?
    public let cognitiveLoad: CognitiveLoad?

    public init(
        taskId: String,
        taskTitle: String,
        estimatedMinutes: Int,
        taskType: TaskCategoryType?,
        energyLevel: EnergyLevel?,
        cognitiveLoad: CognitiveLoad?
    ) {
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.estimatedMinutes = estimatedMinutes
        self.taskType = taskType
        self.energyLevel = energyLevel
        self.cognitiveLoad = cognitiveLoad
    }
}

// MARK: - Notification Names
// Note: xpAwarded is defined in XPTracerView.swift
// Note: focusSessionStarted/Ended are defined in ActiveFocusBar.swift

public extension Notification.Name {
    static let taskCompleted = Notification.Name("com.cosmo.taskCompleted")
    static let questProgressUpdated = Notification.Name("com.cosmo.questProgressUpdated")

    // Intent-based session routing notifications
    static let navigateToContentWorkflow = Notification.Name("com.cosmo.plannerum.navigateToContentWorkflow")
    static let navigateToResearch = Notification.Name("com.cosmo.plannerum.navigateToResearch")
    static let navigateToSwipeGallery = Notification.Name("com.cosmo.plannerum.navigateToSwipeGallery")
    static let navigateToConnection = Notification.Name("com.cosmo.plannerum.navigateToConnection")
    static let navigateToAtom = Notification.Name("com.cosmo.plannerum.navigateToAtom")
    static let startTimerOnlySession = Notification.Name("com.cosmo.plannerum.startTimerOnlySession")
    static let editRecurringTemplate = Notification.Name("com.cosmo.plannerum.editRecurringTemplate")
    static let suggestTasks = Notification.Name("com.cosmo.plannerum.suggestTasks")
}

// MARK: - TaskMetadata Extension

/// Extended TaskMetadata for PlannerumViewModel use
/// Note: Primary definition is in Atom.swift
extension TaskMetadata {
    init(
        priority: String? = nil,
        isCompleted: Bool = false,
        completedAt: String? = nil,
        dueDate: String? = nil,
        focusDate: String? = nil,
        startTime: String? = nil,
        durationMinutes: Int? = nil
    ) {
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.focusDate = focusDate
        self.startTime = startTime
        self.durationMinutes = durationMinutes
    }
}
