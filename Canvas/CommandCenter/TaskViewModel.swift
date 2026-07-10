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

    /// Time goal in minutes — presence makes this a timed task (tracked focus time
    /// counts toward the goal; a prompt fires when it's reached).
    public let timeGoalMinutes: Int?

    // MARK: - Status

    public let priority: TaskPriority
    public let isCompleted: Bool
    public let completedAt: Date?

    // MARK: - Smart Task Intent (WP1)

    public let intent: TaskIntent
    public let intentUUID: String?
    public let habitUUID: String?
    public let habitAssignmentSource: String?
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

    // MARK: - Manual Sort Order

    /// Manual sort order for drag-to-reorder (lower = higher in list)
    public let manualSortOrder: Int?

    // MARK: - Recommendation Engine

    public let taskType: TaskCategoryType?
    public let energyLevel: EnergyLevel?
    public let cognitiveLoad: CognitiveLoad?
    public let recommendationScore: Double
    public let recommendationReason: String?

    // MARK: - Things 3 Scheduling

    /// "When" date — when the user plans to work on this (distinct from deadline)
    public let whenDate: Date?

    /// Hard deadline (semantic rename of dueDate for clarity)
    public let deadline: Date?

    /// Time of day preference: "morning", "evening", or nil
    public let timeOfDay: String?

    /// Scheduling bucket: "anytime", "someday", or nil
    public let schedulingState: String?

    // MARK: - Project Hierarchy

    /// UUID of heading this task belongs to within a project
    public let headingUUID: String?

    /// Parsed checklist items
    public let checklist: [ChecklistItem]

    // MARK: - Linked Atoms

    /// Atoms linked to this task (max 3)
    public let linkedAtoms: [TaskLinkedAtom]

    /// @ mentions embedded in the task title
    public let titleMentions: [RichMention]

    // MARK: - Metadata

    public let createdAt: Date
    public let updatedAt: Date

    // MARK: - Schedule Block Link (iOS contract, July 2026)

    /// UUID of the schedule_block atom this task nests inside. The block owns
    /// the time — the link never time-boxes the task. Raw pointer straight
    /// from metadata; the display fields below are resolved per shown day by
    /// `ScheduleBlockEngine.resolveLinks` and stay nil for dangling links.
    public var scheduleBlockUUID: String? = nil
    public var blockTitle: String? = nil
    public var blockColorHex: String? = nil
    /// The block's occurrence range on the SHOWN day — nil when the block
    /// doesn't occur that day (badge still shows; it just can't read "live").
    public var blockStart: Date? = nil
    public var blockEnd: Date? = nil

    /// True while `date` sits inside the block's occurrence on the shown day —
    /// the "this is what I should be doing now" signal.
    public func blockIsLive(at date: Date = Date()) -> Bool {
        guard let blockStart, let blockEnd else { return false }
        return (blockStart...blockEnd).contains(date)
    }

    // MARK: - Virtual Recurrence Occurrence

    /// When this VM represents a *computed* occurrence of a recurring series, the occurrence
    /// day (startOfDay). nil for plain tasks. Note: `uuid` stays the series template's uuid so
    /// atom-level actions (time-tracking, navigation, edits) keep working; `id` is occurrence-unique.
    public let occurrenceDay: Date?

    /// Display status of the occurrence (overdue/active/upcoming/completed/missed). nil for plain tasks.
    public let occurrenceStatus: TaskOccurrenceStatus?

    /// Whether this VM is a computed recurring occurrence (vs a stored atom).
    public var isOccurrence: Bool { occurrenceDay != nil }

    // MARK: - Computed Properties

    /// Whether the task is due today
    public var isDueToday: Bool {
        guard let due = dueDate else { return false }
        return Calendar.current.isDateInToday(due)
    }

    /// Whether the task is overdue (compares at day level — a task due today is NOT overdue)
    public var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return due < Calendar.current.startOfDay(for: Date())
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

    /// Whether the task belongs on the calendar timeline.
    public var hasCalendarTime: Bool {
        scheduledStart != nil || scheduledTime != nil
    }

    /// Canonical start used by Today and Upcoming calendar surfaces.
    public var calendarStart: Date? {
        calendarStart(using: .current)
    }

    /// Canonical end used by Today and Upcoming calendar surfaces.
    public var calendarEnd: Date? {
        calendarEnd(using: .current)
    }

    /// Date used by calendar surfaces when a task is scheduled without a specific time.
    public var calendarDisplayDate: Date? {
        calendarStart ?? plannedCalendarDate
    }

    public func calendarStart(using calendar: Calendar) -> Date? {
        guard let persistedStart = persistedCalendarStart else { return nil }
        guard let plannedDate = plannedCalendarDate else { return persistedStart }

        let plannedDay = calendar.startOfDay(for: plannedDate)
        if calendar.isDate(persistedStart, inSameDayAs: plannedDay) {
            return persistedStart
        }

        return Self.merged(date: plannedDay, time: persistedStart, calendar: calendar) ?? persistedStart
    }

    public func calendarEnd(using calendar: Calendar) -> Date? {
        guard let normalizedStart = calendarStart(using: calendar),
              let persistedStart = persistedCalendarStart,
              let persistedEnd = scheduledEnd else {
            return nil
        }

        let duration = persistedEnd.timeIntervalSince(persistedStart)
        guard duration > 0 else { return nil }
        return normalizedStart.addingTimeInterval(duration)
    }

    private var persistedCalendarStart: Date? {
        scheduledStart ?? scheduledTime
    }

    private var plannedCalendarDate: Date? {
        whenDate ?? scheduledDate ?? dueDate
    }

    private static func merged(date: Date, time: Date, calendar: Calendar) -> Date? {
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second ?? 0
        merged.timeZone = calendar.timeZone
        return calendar.date(from: merged)
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

    /// Whether the task is in the "Anytime" bucket
    public var isAnytime: Bool {
        schedulingState == "anytime"
    }

    /// Whether the task is in the "Someday" bucket
    public var isSomeday: Bool {
        schedulingState == "someday"
    }

    /// Whether the task has a hard deadline
    public var hasDeadline: Bool {
        deadline != nil
    }

    /// Checklist completion progress
    public var checklistProgress: (completed: Int, total: Int) {
        let total = checklist.count
        let completed = checklist.filter(\.isCompleted).count
        return (completed, total)
    }

    /// Whether all checklist items are completed
    public var isChecklistComplete: Bool {
        !checklist.isEmpty && checklist.allSatisfy(\.isCompleted)
    }

    /// The primary linked atom (opens as main view on play)
    public var primaryLinkedAtom: TaskLinkedAtom? {
        linkedAtoms.first(where: \.isPrimary) ?? linkedAtoms.first
    }

    /// Linked thinkspaces
    public var linkedThinkspaces: [TaskLinkedAtom] {
        linkedAtoms.filter { $0.atomType == "thinkspace" }
    }

    /// Title with colored mention spans as AttributedString
    public var attributedTitle: AttributedString {
        guard !titleMentions.isEmpty else {
            return AttributedString(title)
        }

        var result = AttributedString(title)

        for mention in titleMentions {
            let mentionText = "@\(mention.titleSnapshot)"
            if let range = result.range(of: mentionText) {
                result[range].foregroundColor = CosmoMentionColors.color(for: mention.entityType)
                result[range].font = DS.callout.weight(.semibold)
            }
        }

        return result
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
        timeGoalMinutes: Int? = nil,
        priority: TaskPriority = .medium,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        intent: TaskIntent = .general,
        intentUUID: String? = nil,
        habitUUID: String? = nil,
        habitAssignmentSource: String? = nil,
        linkedIdeaUUID: String? = nil,
        linkedContentUUID: String? = nil,
        linkedAtomUUID: String? = nil,
        totalFocusMinutes: Int = 0,
        sessionCount: Int = 0,
        recurrenceParentUUID: String? = nil,
        isRecurring: Bool = false,
        scheduledStart: Date? = nil,
        scheduledEnd: Date? = nil,
        manualSortOrder: Int? = nil,
        taskType: TaskCategoryType? = nil,
        energyLevel: EnergyLevel? = nil,
        cognitiveLoad: CognitiveLoad? = nil,
        recommendationScore: Double = 0.0,
        recommendationReason: String? = nil,
        whenDate: Date? = nil,
        deadline: Date? = nil,
        timeOfDay: String? = nil,
        schedulingState: String? = nil,
        headingUUID: String? = nil,
        checklist: [ChecklistItem] = [],
        linkedAtoms: [TaskLinkedAtom] = [],
        titleMentions: [RichMention] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        occurrenceDay: Date? = nil,
        occurrenceStatus: TaskOccurrenceStatus? = nil
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
        self.timeGoalMinutes = timeGoalMinutes
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.intent = intent
        self.intentUUID = intentUUID
        self.habitUUID = habitUUID
        self.habitAssignmentSource = habitAssignmentSource
        self.linkedIdeaUUID = linkedIdeaUUID
        self.linkedContentUUID = linkedContentUUID
        self.linkedAtomUUID = linkedAtomUUID
        self.totalFocusMinutes = totalFocusMinutes
        self.sessionCount = sessionCount
        self.recurrenceParentUUID = recurrenceParentUUID
        self.isRecurring = isRecurring
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.manualSortOrder = manualSortOrder
        self.taskType = taskType
        self.energyLevel = energyLevel
        self.cognitiveLoad = cognitiveLoad
        self.recommendationScore = recommendationScore
        self.recommendationReason = recommendationReason
        self.whenDate = whenDate
        self.deadline = deadline
        self.timeOfDay = timeOfDay
        self.schedulingState = schedulingState
        self.headingUUID = headingUUID
        self.checklist = checklist
        self.linkedAtoms = linkedAtoms
        self.titleMentions = titleMentions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.occurrenceDay = occurrenceDay
        self.occurrenceStatus = occurrenceStatus
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
        case .excellent: return DS.green
        case .good: return DS.orange
        case .neutral: return DS.textMuted
        case .poor: return DS.red
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

        // Legacy materialized recurring instances (pre-virtual-occurrence model)
        // are never rendered. Local copies were purged by the clean-slate
        // migration; any straggler arriving from the cloud (old devices, rows
        // whose tombstones never propagated) must not resurface as a task.
        if metadata?.recurrenceParentUUID != nil { return nil }

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

        // Parse Things 3 scheduling fields
        let whenDate = metadata?.whenDate.flatMap { PlannerumFormatters.iso8601.date(from: $0) }
        // dueDate doubles as deadline — also expose as `deadline` for semantic clarity
        let deadline = dueDate

        // Parse checklist from JSON
        var checklistItems: [ChecklistItem] = []
        if let checklistJSON = metadata?.checklist,
           let data = checklistJSON.data(using: .utf8) {
            checklistItems = (try? JSONDecoder().decode([ChecklistItem].self, from: data)) ?? []
        }

        // Parse linked atoms from JSON (with legacy migration)
        var parsedLinkedAtoms: [TaskLinkedAtom] = []
        if let linkedAtomsJSON = metadata?.linkedAtoms,
           let data = linkedAtomsJSON.data(using: .utf8) {
            parsedLinkedAtoms = (try? JSONDecoder().decode([TaskLinkedAtom].self, from: data)) ?? []
        } else {
            // Migrate legacy single-UUID fields
            if let ideaUUID = metadata?.linkedIdeaUUID, !ideaUUID.isEmpty {
                parsedLinkedAtoms.append(TaskLinkedAtom(atomUUID: ideaUUID, atomType: "idea", titleSnapshot: "Linked Idea", isPrimary: parsedLinkedAtoms.isEmpty))
            }
            if let contentUUID = metadata?.linkedContentUUID, !contentUUID.isEmpty {
                parsedLinkedAtoms.append(TaskLinkedAtom(atomUUID: contentUUID, atomType: "content", titleSnapshot: "Linked Content", isPrimary: parsedLinkedAtoms.isEmpty))
            }
            if let atomUUID = metadata?.linkedAtomUUID, !atomUUID.isEmpty {
                parsedLinkedAtoms.append(TaskLinkedAtom(atomUUID: atomUUID, atomType: "research", titleSnapshot: "Linked Atom", isPrimary: parsedLinkedAtoms.isEmpty))
            }
        }

        // Parse title mentions from JSON
        var parsedTitleMentions: [RichMention] = []
        if let mentionsJSON = metadata?.titleMentions,
           let data = mentionsJSON.data(using: .utf8) {
            parsedTitleMentions = (try? JSONDecoder().decode([RichMention].self, from: data)) ?? []
        }

        var vm = TaskViewModel(
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
            timeGoalMinutes: metadata?.timeGoalMinutes,
            priority: TaskPriority(from: metadata?.priority),
            isCompleted: metadata?.isCompleted ?? false,
            completedAt: completedAt,
            intent: intent,
            intentUUID: metadata?.intentUUID,
            habitUUID: metadata?.habitUUID,
            habitAssignmentSource: metadata?.habitAssignmentSource,
            linkedIdeaUUID: metadata?.linkedIdeaUUID,
            linkedContentUUID: metadata?.linkedContentUUID,
            linkedAtomUUID: metadata?.linkedAtomUUID,
            totalFocusMinutes: metadata?.totalFocusMinutes ?? 0,
            sessionCount: metadata?.sessionCount ?? 0,
            recurrenceParentUUID: metadata?.recurrenceParentUUID,
            isRecurring: metadata?.recurrence != nil || metadata?.recurrenceParentUUID != nil,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd,
            manualSortOrder: metadata?.manualSortOrder,
            taskType: taskType,
            energyLevel: energyLevel,
            cognitiveLoad: cognitiveLoad,
            recommendationScore: recommendationScore,
            recommendationReason: recommendationReason,
            whenDate: whenDate,
            deadline: deadline,
            timeOfDay: metadata?.timeOfDay,
            schedulingState: metadata?.schedulingState,
            headingUUID: metadata?.headingUUID,
            checklist: checklistItems,
            linkedAtoms: parsedLinkedAtoms,
            titleMentions: parsedTitleMentions,
            createdAt: PlannerumFormatters.iso8601.date(from: atom.createdAt) ?? Date(),
            updatedAt: PlannerumFormatters.iso8601.date(from: atom.updatedAt) ?? Date()
        )
        // Raw block pointer; display fields resolve per shown day later
        // (ScheduleBlockEngine.resolveLinks), fail-soft for dangling links.
        vm.scheduleBlockUUID = metadata?.scheduleBlockUUID
        return vm
    }
}

// MARK: - TaskViewModel + Virtual Occurrence

extension TaskViewModel {

    /// Project this *series template* VM onto a computed occurrence. Dates are shifted onto the
    /// occurrence day/time and the occurrence identity/status is stamped. `uuid` stays the
    /// template's; `id` becomes occurrence-unique so SwiftUI tracks each occurrence separately.
    /// `completedAt` carries the wall-clock completion time from the completion log (Logbook
    /// grouping/sorting); it defaults to the occurrence day for completed occurrences.
    func makingOccurrence(_ occ: RecurringSeriesEngine.VirtualOccurrence, completedAt: Date? = nil) -> TaskViewModel {
        let completed = occ.status == .completed
        var vm = TaskViewModel(
            id: occ.id,
            uuid: uuid,
            title: occ.title,
            body: body,
            projectUuid: projectUuid,
            projectName: projectName,
            projectColor: projectColor,
            dueDate: occ.start ?? occ.day,
            scheduledDate: occ.day,
            scheduledTime: occ.start,
            estimatedMinutes: estimatedMinutes,
            timeGoalMinutes: timeGoalMinutes,
            priority: priority,
            isCompleted: completed,
            completedAt: completed ? (completedAt ?? occ.day) : nil,
            intent: intent,
            intentUUID: intentUUID,
            habitUUID: habitUUID,
            habitAssignmentSource: habitAssignmentSource,
            linkedIdeaUUID: linkedIdeaUUID,
            linkedContentUUID: linkedContentUUID,
            linkedAtomUUID: linkedAtomUUID,
            totalFocusMinutes: totalFocusMinutes,
            sessionCount: sessionCount,
            recurrenceParentUUID: nil,
            isRecurring: true,
            scheduledStart: occ.start,
            scheduledEnd: occ.end,
            manualSortOrder: manualSortOrder,
            taskType: taskType,
            energyLevel: energyLevel,
            cognitiveLoad: cognitiveLoad,
            recommendationScore: recommendationScore,
            recommendationReason: recommendationReason,
            whenDate: occ.day,
            deadline: nil,
            timeOfDay: timeOfDay,
            schedulingState: schedulingState,
            headingUUID: headingUUID,
            checklist: checklist,
            linkedAtoms: linkedAtoms,
            titleMentions: titleMentions,
            createdAt: createdAt,
            updatedAt: updatedAt,
            occurrenceDay: occ.day,
            occurrenceStatus: occ.status
        )
        // The template's block link speaks for every occurrence.
        vm.scheduleBlockUUID = scheduleBlockUUID
        return vm
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

// MARK: - PlannerumFormatters (stub — original in deleted PlannerumTokens.swift)

/// Shared date formatters for Plannerum task metadata
enum PlannerumFormatters {
    static let iso8601 = LenientISO8601Formatter()
}

/// ISO 8601 formatter that writes with fractional seconds and parses both formats.
/// Fixes mismatch where some callers write without fractional seconds.
final class LenientISO8601Formatter: @unchecked Sendable {

    private let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let withoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func date(from string: String) -> Date? {
        withFractional.date(from: string) ?? withoutFractional.date(from: string)
    }

    func string(from date: Date) -> String {
        withFractional.string(from: date)
    }
}
