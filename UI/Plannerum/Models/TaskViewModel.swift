//
//  TaskViewModel.swift
//  CosmoOS
//
//  Created for Plannerum Redesign
//

import Foundation
import SwiftUI

// MARK: - TaskViewModel

/// View model representing a task for display in Plannerum
/// Converts from Atom to a UI-friendly representation with computed properties
public struct TaskViewModel: Identifiable, Equatable, Sendable {

    // MARK: - Identity

    public let id: String
    public let uuid: String

    // MARK: - Core Properties

    public let title: String
    public let body: String?
    public let projectUuid: String?
    public let projectName: String?
    public let projectColor: Color

    // MARK: - Scheduling

    public let dueDate: Date?
    public let scheduledDate: Date?
    public let scheduledTime: Date?
    public let estimatedMinutes: Int

    // MARK: - Status

    public let priority: TaskPriority
    public let isCompleted: Bool
    public let completedAt: Date?

    // MARK: - Smart Task Intent (WP1)

    public let intent: TaskIntent
    public let linkedIdeaUUID: String?
    public let linkedContentUUID: String?
    public let linkedAtomUUID: String?

    // MARK: - Session Tracking (WP2)

    public let totalFocusMinutes: Int
    public let sessionCount: Int

    // MARK: - Recurrence (WP4)

    public let recurrenceParentUUID: String?
    public let isRecurring: Bool

    // MARK: - Time Blocking (WP3)

    public let scheduledStart: Date?
    public let scheduledEnd: Date?

    // MARK: - Recommendation Engine

    public let taskType: TaskCategoryType?
    public let energyLevel: EnergyLevel?
    public let cognitiveLoad: CognitiveLoad?
    public let recommendationScore: Double
    public let recommendationReason: String?

    // MARK: - Metadata

    public let createdAt: Date
    public let updatedAt: Date

    // MARK: - Computed Properties

    /// Whether the task is due today
    public var isDueToday: Bool {
        guard let due = dueDate else { return false }
        return Calendar.current.isDateInToday(due)
    }

    /// Whether the task is overdue
    public var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return due < Date()
    }

    /// Whether the task is due tomorrow
    public var isDueTomorrow: Bool {
        guard let due = dueDate else { return false }
        return Calendar.current.isDateInTomorrow(due)
    }

    /// Human-readable due date info
    public var dueInfo: String? {
        guard let due = dueDate else { return nil }
        if isOverdue { return "Overdue" }
        if Calendar.current.isDateInToday(due) { return "Due today" }
        if Calendar.current.isDateInTomorrow(due) { return "Due tomorrow" }
        return "Due \(due.formatted(.dateTime.month().day()))"
    }

    /// Human-readable scheduled time info
    public var timeInfo: String? {
        guard let time = scheduledTime else { return nil }
        return time.formatted(.dateTime.hour().minute())
    }

    /// Whether the task has a specific scheduled time
    public var hasSpecificTime: Bool {
        scheduledTime != nil
    }

    /// Estimated XP for completing this task
    public var estimatedXP: Int {
        let baseXP = 10
        let durationBonus = min(estimatedMinutes / 15, 4) * 5  // 5 XP per 15 min, max 20
        let priorityBonus: Int
        switch priority {
        case .critical: priorityBonus = 15
        case .high: priorityBonus = 10
        case .medium: priorityBonus = 5
        case .low: priorityBonus = 0
        }
        return baseXP + durationBonus + priorityBonus
    }

    /// Hours until due (negative if overdue)
    public var hoursUntilDue: Double? {
        guard let due = dueDate else { return nil }
        return due.timeIntervalSinceNow / 3600
    }

    // MARK: - Initialization

    public init(
        id: String = UUID().uuidString,
        uuid: String,
        title: String,
        body: String? = nil,
        projectUuid: String? = nil,
        projectName: String? = nil,
        projectColor: Color = .blue,
        dueDate: Date? = nil,
        scheduledDate: Date? = nil,
        scheduledTime: Date? = nil,
        estimatedMinutes: Int = 30,
        priority: TaskPriority = .medium,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        intent: TaskIntent = .general,
        linkedIdeaUUID: String? = nil,
        linkedContentUUID: String? = nil,
        linkedAtomUUID: String? = nil,
        totalFocusMinutes: Int = 0,
        sessionCount: Int = 0,
        recurrenceParentUUID: String? = nil,
        isRecurring: Bool = false,
        scheduledStart: Date? = nil,
        scheduledEnd: Date? = nil,
        taskType: TaskCategoryType? = nil,
        energyLevel: EnergyLevel? = nil,
        cognitiveLoad: CognitiveLoad? = nil,
        recommendationScore: Double = 0.0,
        recommendationReason: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.uuid = uuid
        self.title = title
        self.body = body
        self.projectUuid = projectUuid
        self.projectName = projectName
        self.projectColor = projectColor
        self.dueDate = dueDate
        self.scheduledDate = scheduledDate
        self.scheduledTime = scheduledTime
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.intent = intent
        self.linkedIdeaUUID = linkedIdeaUUID
        self.linkedContentUUID = linkedContentUUID
        self.linkedAtomUUID = linkedAtomUUID
        self.totalFocusMinutes = totalFocusMinutes
        self.sessionCount = sessionCount
        self.recurrenceParentUUID = recurrenceParentUUID
        self.isRecurring = isRecurring
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.taskType = taskType
        self.energyLevel = energyLevel
        self.cognitiveLoad = cognitiveLoad
        self.recommendationScore = recommendationScore
        self.recommendationReason = recommendationReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - TaskPriority

/// Task priority levels
public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    public var color: Color {
        switch self {
        case .low: return .secondary
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }

    public var iconName: String {
        switch self {
        case .low: return "arrow.down"
        case .medium: return "minus"
        case .high: return "arrow.up"
        case .critical: return "exclamationmark.2"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }

    /// Initialize from string (with fallback)
    public init(from string: String?) {
        guard let string = string else {
            self = .medium
            return
        }
        self = TaskPriority(rawValue: string.lowercased()) ?? .medium
    }
}

// MARK: - EnergyMatch

/// How well a task matches the user's current energy level
public enum EnergyMatch: String, CaseIterable, Sendable {
    case excellent
    case good
    case neutral
    case poor

    public var color: Color {
        switch self {
        case .excellent: return Color(red: 34/255, green: 197/255, blue: 94/255)  // Green
        case .good: return Color(red: 245/255, green: 158/255, blue: 11/255)      // Amber
        case .neutral: return Color(red: 100/255, green: 116/255, blue: 139/255)  // Slate
        case .poor: return Color(red: 239/255, green: 68/255, blue: 68/255)       // Red
        }
    }

    public var displayName: String {
        switch self {
        case .excellent: return "Perfect match"
        case .good: return "Good match"
        case .neutral: return "Neutral"
        case .poor: return "Energy mismatch"
        }
    }

    public var iconName: String {
        switch self {
        case .excellent: return "bolt.fill"
        case .good: return "bolt"
        case .neutral: return "minus"
        case .poor: return "bolt.slash"
        }
    }

    /// Calculate energy match from current energy and task requirements
    public static func calculate(currentEnergy: Int, taskType: TaskCategoryType?) -> EnergyMatch {
        guard let taskType = taskType else { return .neutral }

        let idealRange = taskType.idealEnergyRange
        let idealMidpoint = (idealRange.lowerBound + idealRange.upperBound) / 2

        let difference = abs(currentEnergy - idealMidpoint)

        if idealRange.contains(currentEnergy) {
            return difference <= 10 ? .excellent : .good
        } else if difference <= 20 {
            return .neutral
        } else {
            return .poor
        }
    }
}

// MARK: - TaskViewModel + Atom Conversion

extension TaskViewModel {

    /// Create a TaskViewModel from an Atom
    public static func from(
        atom: Atom,
        projectName: String? = nil,
        projectColor: Color = .blue,
        recommendationScore: Double = 0.0,
        recommendationReason: String? = nil
    ) -> TaskViewModel? {
        guard atom.type == .task else { return nil }

        // Parse metadata
        let metadata = atom.metadataValue(as: TaskMetadata.self)

        // Parse dates
        let dueDate = metadata?.dueDate.flatMap { PlannerumFormatters.iso8601.date(from: $0) }
        let scheduledDate = metadata?.focusDate.flatMap { PlannerumFormatters.iso8601.date(from: $0) }
        let scheduledTime = metadata?.startTime.flatMap { PlannerumFormatters.iso8601.date(from: $0) }
        let completedAt = metadata?.completedAt.flatMap { PlannerumFormatters.iso8601.date(from: $0) }

        // Parse enums
        let taskType = metadata?.taskType.flatMap { TaskCategoryType(rawValue: $0) }
        let energyLevel = metadata?.energyLevel.flatMap { EnergyLevel(rawValue: $0) }
        let cognitiveLoad = metadata?.cognitiveLoad.flatMap { CognitiveLoad(rawValue: $0) }
        let intent = metadata?.intent.flatMap { TaskIntent(rawValue: $0) } ?? .general

        // Parse time block dates
        let scheduledStart = metadata?.scheduledStart.flatMap { PlannerumFormatters.iso8601.date(from: $0) }
        let scheduledEnd = metadata?.scheduledEnd.flatMap { PlannerumFormatters.iso8601.date(from: $0) }

        return TaskViewModel(
            id: atom.uuid,
            uuid: atom.uuid,
            title: atom.title ?? "Untitled Task",
            body: atom.body,
            projectUuid: nil,  // Would need to resolve from links
            projectName: projectName,
            projectColor: projectColor,
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            scheduledTime: scheduledTime,
            estimatedMinutes: metadata?.durationMinutes ?? metadata?.estimatedFocusMinutes ?? 30,
            priority: TaskPriority(from: metadata?.priority),
            isCompleted: metadata?.isCompleted ?? false,
            completedAt: completedAt,
            intent: intent,
            linkedIdeaUUID: metadata?.linkedIdeaUUID,
            linkedContentUUID: metadata?.linkedContentUUID,
            linkedAtomUUID: metadata?.linkedAtomUUID,
            totalFocusMinutes: metadata?.totalFocusMinutes ?? 0,
            sessionCount: metadata?.sessionCount ?? 0,
            recurrenceParentUUID: metadata?.recurrenceParentUUID,
            isRecurring: metadata?.recurrence != nil || metadata?.recurrenceParentUUID != nil,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd,
            taskType: taskType,
            energyLevel: energyLevel,
            cognitiveLoad: cognitiveLoad,
            recommendationScore: recommendationScore,
            recommendationReason: recommendationReason,
            createdAt: PlannerumFormatters.iso8601.date(from: atom.createdAt) ?? Date(),
            updatedAt: PlannerumFormatters.iso8601.date(from: atom.updatedAt) ?? Date()
        )
    }
}

// MARK: - TaskRecommendation

/// A recommended task with scoring details
public struct TaskRecommendation: Identifiable, Equatable, Sendable {
    public let id: String
    public let task: TaskViewModel
    public let score: Double
    public let reason: RecommendationReason

    public init(task: TaskViewModel, score: Double, reason: RecommendationReason) {
        self.id = task.id
        self.task = task
        self.score = score
        self.reason = reason
    }
}

/// Reason why a task was recommended
public enum RecommendationReason: Equatable, Sendable {
    case deadlinePressure(hoursUntilDue: Double)
    case energyMatch(currentEnergy: Int, requiredEnergy: EnergyLevel)
    case focusMatch(currentFocus: Int, requiredFocus: CognitiveLoad)
    case timeAvailable(availableMinutes: Int)
    case streakContinuation(questType: String)
    case userPrioritized
    case projectFocus(projectName: String)

    public var displayMessage: String {
        switch self {
        case .deadlinePressure(let hours):
            if hours < 0 { return "Overdue - needs attention" }
            if hours < 4 { return "Due very soon" }
            if hours < 24 { return "Due today" }
            if hours < 48 { return "Due tomorrow" }
            return "Upcoming deadline"
        case .energyMatch(let current, _):
            if current >= 70 { return "Perfect for your high energy" }
            if current >= 40 { return "Matches your current energy" }
            return "Light task for low energy"
        case .focusMatch(let focus, _):
            if focus >= 70 { return "Great for deep focus" }
            return "Suitable for your focus level"
        case .timeAvailable(let minutes):
            return "Fits in your available \(minutes)min"
        case .streakContinuation(let quest):
            return "Contributes to \(quest) streak"
        case .userPrioritized:
            return "High priority task"
        case .projectFocus(let project):
            return "Focus on \(project)"
        }
    }
}

// MARK: - UpcomingDayViewModel

/// View model for a day in the upcoming section
public struct UpcomingDayViewModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let tasks: [TaskViewModel]

    public var dayName: String {
        date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    public var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    public var taskCount: Int {
        tasks.count
    }

    public var topPriorityTask: String? {
        tasks.first?.title
    }

    public var hasDeadlines: Bool {
        tasks.contains { $0.dueDate != nil }
    }

    public var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    public var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(date)
    }

    public var isWeekend: Bool {
        Calendar.current.isDateInWeekend(date)
    }

    public init(date: Date, tasks: [TaskViewModel] = []) {
        self.id = date.formatted(.iso8601.year().month().day())
        self.date = date
        self.tasks = tasks
    }
}

// Note: PlannerumFormatters is defined in PlannerumTokens.swift
