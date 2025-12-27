// CosmoOS/Scheduler/Shared/ScheduleBlock.swift
// Unified schedule item model - the single source of truth for all scheduled content
// Replaces fragmented CalendarEvent + CosmoTask scheduling logic
//
// Design Philosophy:
// - One model for tasks, time blocks, events, and focus sessions
// - Rich semantic linking to ideas, research, and swipe file
// - Optimized for both Plan Mode (visual) and Today Mode (action list)
// - Full offline-first sync capability

import Foundation
import GRDB

// MARK: - Schedule Block Type

/// The fundamental type of a schedule block determines its behavior and rendering
public enum ScheduleBlockType: String, Codable, CaseIterable, Sendable {
    /// Completable item with checkbox - shown in task lists
    case task

    /// Scheduled work session without completion state - "Deep Work 2-4pm"
    case timeBlock

    /// External calendar event (imported from CalDAV, etc.)
    case event

    /// Focus session with Pomodoro-style tracking and progress
    case focus

    /// Quick reminder without duration
    case reminder

    // MARK: - Display Properties

    var displayName: String {
        switch self {
        case .task: return "Task"
        case .timeBlock: return "Time Block"
        case .event: return "Event"
        case .focus: return "Focus Session"
        case .reminder: return "Reminder"
        }
    }

    var systemImage: String {
        switch self {
        case .task: return "checkmark.circle"
        case .timeBlock: return "rectangle.stack"
        case .event: return "calendar"
        case .focus: return "brain.head.profile"
        case .reminder: return "bell"
        }
    }

    /// Whether this block type supports completion state
    var supportsCompletion: Bool {
        switch self {
        case .task, .focus, .reminder: return true
        case .timeBlock, .event: return false
        }
    }

    /// Whether this block type has fixed timing (vs flexible/unscheduled)
    var requiresTiming: Bool {
        switch self {
        case .event: return true
        case .task, .timeBlock, .focus, .reminder: return false
        }
    }
}

// MARK: - Task Status

/// Progression state for completable blocks
public enum ScheduleBlockStatus: String, Codable, CaseIterable, Sendable {
    case todo
    case inProgress = "in_progress"
    case done
    case cancelled
    case deferred

    var displayName: String {
        switch self {
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        case .deferred: return "Deferred"
        }
    }

    var isTerminal: Bool {
        self == .done || self == .cancelled
    }
}

// MARK: - Priority

/// Priority levels with semantic meaning
public enum ScheduleBlockPriority: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case urgent

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }

    var accentOpacity: Double {
        switch self {
        case .urgent: return 1.0
        case .high: return 0.85
        case .medium: return 0.6
        case .low: return 0.4
        }
    }
}

// MARK: - Origin Type

/// Tracks how this block was created for context and undo
public enum ScheduleBlockOrigin: String, Codable, Sendable {
    case idea           // Promoted from an idea
    case voice          // Created via voice command
    case manual         // User-created directly in scheduler
    case recurring      // Generated from recurrence rule
    case imported       // External calendar sync
    case quickCapture   // Created from command hub
    case template       // Created from a template
}

// MARK: - Focus Session Data

/// Tracking data for focus/deep work blocks
public struct FocusSessionData: Codable, Sendable, Equatable {
    /// Target duration in minutes
    var targetMinutes: Int

    /// Actual elapsed minutes (updated during/after session)
    var actualMinutes: Int?

    /// Break intervals taken
    var breaks: [FocusBreak]?

    /// AI-calculated focus quality score (0-100)
    var focusScore: Double?

    /// Whether session was completed vs abandoned
    var wasCompleted: Bool?

    /// Distractions logged during session
    var distractionCount: Int?

    struct FocusBreak: Codable, Sendable, Equatable {
        var startedAt: Date
        var durationSeconds: Int
        var wasPlanned: Bool
    }

    init(targetMinutes: Int = 25) {
        self.targetMinutes = targetMinutes
    }
}

// MARK: - Checklist Item

/// Sub-task within a schedule block
public struct ScheduleChecklistItem: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    var title: String
    var isCompleted: Bool
    var completedAt: Date?
    var sortOrder: Int

    init(title: String, sortOrder: Int = 0) {
        self.id = UUID().uuidString
        self.title = title
        self.isCompleted = false
        self.sortOrder = sortOrder
    }
}

// MARK: - Semantic Links

/// Rich linking to other Cosmo entities
public struct ScheduleSemanticLinks: Codable, Sendable, Equatable {
    /// Linked idea UUIDs
    var ideas: [String]?

    /// Linked research item UUIDs
    var research: [String]?

    /// Linked swipe file item UUIDs
    var swipeItems: [String]?

    /// Linked connection UUIDs
    var connections: [String]?

    /// AI-suggested template IDs
    var suggestedTemplates: [String]?

    /// Whether links were auto-discovered vs manual
    var autoDiscovered: Bool?

    var isEmpty: Bool {
        (ideas?.isEmpty ?? true) &&
        (research?.isEmpty ?? true) &&
        (swipeItems?.isEmpty ?? true) &&
        (connections?.isEmpty ?? true)
    }

    var totalLinkCount: Int {
        let ideasCount = ideas?.count ?? 0
        let researchCount = research?.count ?? 0
        let swipeCount = swipeItems?.count ?? 0
        let connectionsCount = connections?.count ?? 0
        return ideasCount + researchCount + swipeCount + connectionsCount
    }

    init() {}
}

// MARK: - Schedule Block Model

/// The unified schedule block model - single source of truth for all scheduled items
public struct ScheduleBlock: Codable, Sendable, Equatable {
    // MARK: - Identity

    /// Database row ID (for GRDB) - use `uuid` for stable identification
    var databaseId: Int64?
    var uuid: String
    var userId: String?

    // MARK: - Core Content

    var title: String
    var blockDescription: String?
    var blockType: ScheduleBlockType

    // MARK: - Timing

    /// Start time - nil means unscheduled
    var startTime: Date?

    /// End time - nil means use duration or point-in-time
    var endTime: Date?

    /// Explicit duration in minutes (used when endTime is nil)
    var durationMinutes: Int?

    /// Whether this spans entire day(s)
    var isAllDay: Bool

    // MARK: - Status (for completable types)

    var status: ScheduleBlockStatus?
    var isCompleted: Bool
    var completedAt: Date?

    // MARK: - Organization

    var projectId: Int64?
    var projectUuid: String?
    var priority: ScheduleBlockPriority
    var color: String?
    var tags: [String]?

    // MARK: - Origin Tracking

    var originType: ScheduleBlockOrigin?
    var originEntityId: Int64?
    var originEntityUuid: String?

    // MARK: - Semantic Links

    var semanticLinks: ScheduleSemanticLinks?

    // MARK: - Recurrence

    var recurrence: RecurrenceRule?
    var recurrenceParentId: Int64?
    var recurrenceParentUuid: String?

    // MARK: - Additional Data

    var checklist: [ScheduleChecklistItem]?
    var reminderMinutes: Int?
    var location: String?
    var focusSession: FocusSessionData?
    var notes: String?

    // MARK: - Sync Metadata

    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var isDeleted: Bool
    var localVersion: Int64
    var serverVersion: Int64
    var syncVersion: Int64

    // MARK: - Initialization

    init(
        databaseId: Int64? = nil,
        uuid: String = UUID().uuidString,
        userId: String? = nil,
        title: String,
        blockDescription: String? = nil,
        blockType: ScheduleBlockType = .task,
        startTime: Date? = nil,
        endTime: Date? = nil,
        durationMinutes: Int? = nil,
        isAllDay: Bool = false,
        status: ScheduleBlockStatus? = .todo,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        projectId: Int64? = nil,
        projectUuid: String? = nil,
        priority: ScheduleBlockPriority = .medium,
        color: String? = nil,
        tags: [String]? = nil,
        originType: ScheduleBlockOrigin? = nil,
        originEntityId: Int64? = nil,
        originEntityUuid: String? = nil,
        semanticLinks: ScheduleSemanticLinks? = nil,
        recurrence: RecurrenceRule? = nil,
        recurrenceParentId: Int64? = nil,
        recurrenceParentUuid: String? = nil,
        checklist: [ScheduleChecklistItem]? = nil,
        reminderMinutes: Int? = nil,
        location: String? = nil,
        focusSession: FocusSessionData? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncedAt: Date? = nil,
        isDeleted: Bool = false,
        localVersion: Int64 = 1,
        serverVersion: Int64 = 0,
        syncVersion: Int64 = 0
    ) {
        self.databaseId = databaseId
        self.uuid = uuid
        self.userId = userId
        self.title = title
        self.blockDescription = blockDescription
        self.blockType = blockType
        self.startTime = startTime
        self.endTime = endTime
        self.durationMinutes = durationMinutes
        self.isAllDay = isAllDay
        self.status = blockType.supportsCompletion ? (status ?? .todo) : nil
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.projectId = projectId
        self.projectUuid = projectUuid
        self.priority = priority
        self.color = color
        self.tags = tags
        self.originType = originType
        self.originEntityId = originEntityId
        self.originEntityUuid = originEntityUuid
        self.semanticLinks = semanticLinks
        self.recurrence = recurrence
        self.recurrenceParentId = recurrenceParentId
        self.recurrenceParentUuid = recurrenceParentUuid
        self.checklist = checklist
        self.reminderMinutes = reminderMinutes
        self.location = location
        self.focusSession = focusSession
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
        self.isDeleted = isDeleted
        self.localVersion = localVersion
        self.serverVersion = serverVersion
        self.syncVersion = syncVersion
    }

    // MARK: - Computed Properties

    /// Whether this block is currently scheduled (has a start time)
    var isScheduled: Bool {
        startTime != nil
    }

    /// Calculated duration in minutes
    var effectiveDurationMinutes: Int {
        if let duration = durationMinutes {
            return duration
        }
        if let start = startTime, let end = endTime {
            return Int(end.timeIntervalSince(start) / 60)
        }
        return 30 // Default 30 minutes
    }

    /// Calculated end time
    var effectiveEndTime: Date? {
        if let end = endTime {
            return end
        }
        if let start = startTime {
            return start.addingTimeInterval(TimeInterval(effectiveDurationMinutes * 60))
        }
        return nil
    }

    /// Whether this block is overdue
    var isOverdue: Bool {
        guard blockType.supportsCompletion, !isCompleted else { return false }

        if let end = effectiveEndTime {
            return end < Date()
        }
        return false
    }

    /// Whether this block is happening now
    var isActive: Bool {
        guard let start = startTime else { return false }
        let now = Date()
        let end = effectiveEndTime ?? start.addingTimeInterval(3600)
        return now >= start && now <= end
    }

    /// Checklist completion percentage (0-1)
    var checklistProgress: Double {
        guard let items = checklist, !items.isEmpty else { return 0 }
        let completed = items.filter { $0.isCompleted }.count
        return Double(completed) / Double(items.count)
    }

    /// Whether all checklist items are complete
    var isChecklistComplete: Bool {
        guard let items = checklist, !items.isEmpty else { return true }
        return items.allSatisfy { $0.isCompleted }
    }

    // MARK: - Factory Methods

    /// Create a new task block
    static func task(
        title: String,
        startTime: Date? = nil,
        durationMinutes: Int = 30,
        priority: ScheduleBlockPriority = .medium,
        projectUuid: String? = nil
    ) -> ScheduleBlock {
        ScheduleBlock(
            title: title,
            blockType: .task,
            startTime: startTime,
            durationMinutes: durationMinutes,
            status: .todo,
            projectUuid: projectUuid,
            priority: priority,
            originType: .manual
        )
    }

    /// Create a new time block (scheduled work session)
    static func timeBlock(
        title: String,
        startTime: Date,
        endTime: Date,
        color: String? = nil
    ) -> ScheduleBlock {
        ScheduleBlock(
            title: title,
            blockType: .timeBlock,
            startTime: startTime,
            endTime: endTime,
            color: color ?? "lavender",
            originType: .manual
        )
    }

    /// Create a new focus session
    static func focusSession(
        title: String,
        startTime: Date,
        targetMinutes: Int = 25
    ) -> ScheduleBlock {
        ScheduleBlock(
            title: title,
            blockType: .focus,
            startTime: startTime,
            durationMinutes: targetMinutes,
            status: .todo,
            color: "lavender",
            originType: .manual,
            focusSession: FocusSessionData(targetMinutes: targetMinutes)
        )
    }

    /// Create from an existing idea (promotion)
    static func fromIdea(
        ideaUuid: String,
        title: String,
        startTime: Date? = nil
    ) -> ScheduleBlock {
        var block = ScheduleBlock.task(title: title, startTime: startTime)
        block.originType = .idea
        block.originEntityUuid = ideaUuid
        block.semanticLinks = ScheduleSemanticLinks()
        block.semanticLinks?.ideas = [ideaUuid]
        return block
    }

    // MARK: - Mutation Helpers

    /// Mark as completed with timestamp
    mutating func markCompleted() {
        guard blockType.supportsCompletion else { return }
        isCompleted = true
        completedAt = Date()
        status = .done
        updatedAt = Date()
        localVersion += 1
    }

    /// Mark as incomplete
    mutating func markIncomplete() {
        guard blockType.supportsCompletion else { return }
        isCompleted = false
        completedAt = nil
        status = .todo
        updatedAt = Date()
        localVersion += 1
    }

    /// Toggle completion state
    mutating func toggleCompletion() {
        if isCompleted {
            markIncomplete()
        } else {
            markCompleted()
        }
    }

    /// Reschedule to new time
    mutating func reschedule(to newStart: Date, duration: Int? = nil) {
        startTime = newStart
        if let duration = duration {
            durationMinutes = duration
            endTime = newStart.addingTimeInterval(TimeInterval(duration * 60))
        } else if let existingDuration = durationMinutes {
            endTime = newStart.addingTimeInterval(TimeInterval(existingDuration * 60))
        }
        updatedAt = Date()
        localVersion += 1
    }

    /// Update duration (resize)
    mutating func resize(to newDurationMinutes: Int) {
        durationMinutes = newDurationMinutes
        if let start = startTime {
            endTime = start.addingTimeInterval(TimeInterval(newDurationMinutes * 60))
        }
        updatedAt = Date()
        localVersion += 1
    }

    /// Add semantic link
    mutating func addLink(ideaUuid: String? = nil, researchUuid: String? = nil, connectionUuid: String? = nil) {
        if semanticLinks == nil {
            semanticLinks = ScheduleSemanticLinks()
        }

        if let ideaUuid = ideaUuid {
            if semanticLinks?.ideas == nil { semanticLinks?.ideas = [] }
            if !(semanticLinks?.ideas?.contains(ideaUuid) ?? false) {
                semanticLinks?.ideas?.append(ideaUuid)
            }
        }

        if let researchUuid = researchUuid {
            if semanticLinks?.research == nil { semanticLinks?.research = [] }
            if !(semanticLinks?.research?.contains(researchUuid) ?? false) {
                semanticLinks?.research?.append(researchUuid)
            }
        }

        if let connectionUuid = connectionUuid {
            if semanticLinks?.connections == nil { semanticLinks?.connections = [] }
            if !(semanticLinks?.connections?.contains(connectionUuid) ?? false) {
                semanticLinks?.connections?.append(connectionUuid)
            }
        }

        updatedAt = Date()
        localVersion += 1
    }

    /// Toggle checklist item
    mutating func toggleChecklistItem(id: String) {
        guard var items = checklist,
              let index = items.firstIndex(where: { $0.id == id }) else { return }

        items[index].isCompleted.toggle()
        items[index].completedAt = items[index].isCompleted ? Date() : nil
        checklist = items
        updatedAt = Date()
        localVersion += 1
    }

    /// Add checklist item
    mutating func addChecklistItem(title: String) {
        if checklist == nil { checklist = [] }
        let sortOrder = checklist?.count ?? 0
        checklist?.append(ScheduleChecklistItem(title: title, sortOrder: sortOrder))
        updatedAt = Date()
        localVersion += 1
    }

    /// Soft delete
    mutating func softDelete() {
        isDeleted = true
        updatedAt = Date()
        localVersion += 1
    }
}

// MARK: - GRDB Conformance

extension ScheduleBlock: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "schedule_blocks"

    // Custom column mapping to match database schema
    enum CodingKeys: String, CodingKey, ColumnExpression {
        case databaseId = "id"
        case uuid
        case userId = "user_id"
        case title
        case blockDescription = "description"
        case blockType = "block_type"
        case startTime = "start_time"
        case endTime = "end_time"
        case durationMinutes = "duration_minutes"
        case isAllDay = "is_all_day"
        case status
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case projectId = "project_id"
        case projectUuid = "project_uuid"
        case priority
        case color
        case tags
        case originType = "origin_type"
        case originEntityId = "origin_entity_id"
        case originEntityUuid = "origin_entity_uuid"
        case semanticLinks = "semantic_links"
        case recurrence
        case recurrenceParentId = "recurrence_parent_id"
        case recurrenceParentUuid = "recurrence_parent_uuid"
        case checklist
        case reminderMinutes = "reminder_minutes"
        case location
        case focusSession = "focus_session"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
        case isDeleted = "is_deleted"
        case localVersion = "_local_version"
        case serverVersion = "_server_version"
        case syncVersion = "_sync_version"
    }
}

// MARK: - Syncable Conformance

extension ScheduleBlock: Syncable {
    /// Database row ID for Syncable protocol (maps to databaseId)
    var id: Int64? { databaseId }

    // Provide explicit getUUID() since our uuid is non-optional String
    func getUUID() -> String? { uuid }
}

// MARK: - SwiftUI Identification
// Note: Use ForEach(blocks, id: \.uuid) for stable iteration
// Syncable protocol provides id: Int64? for database operations

// MARK: - Hashable

extension ScheduleBlock: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}

// MARK: - Time Formatting Helpers

extension ScheduleBlock {
    /// Formatted time range string
    var formattedTimeRange: String {
        guard let start = startTime else { return "Unscheduled" }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let startString = formatter.string(from: start)

        if isAllDay {
            return "All Day"
        }

        if let end = effectiveEndTime {
            let endString = formatter.string(from: end)
            return "\(startString) – \(endString)"
        }

        return startString
    }

    /// Short time string (just start time)
    var formattedStartTime: String {
        guard let start = startTime else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: start)
    }

    /// Duration string
    var formattedDuration: String {
        let minutes = effectiveDurationMinutes
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    /// Day of week for this block's start time
    var dayOfWeek: Int? {
        guard let start = startTime else { return nil }
        return Calendar.current.component(.weekday, from: start)
    }

    /// Hour of day (0-23) for this block's start time
    var hourOfDay: Int? {
        guard let start = startTime else { return nil }
        return Calendar.current.component(.hour, from: start)
    }

    /// Minute of hour for this block's start time
    var minuteOfHour: Int? {
        guard let start = startTime else { return nil }
        return Calendar.current.component(.minute, from: start)
    }
}

// MARK: - Sorting

extension ScheduleBlock {
    /// Sort blocks by time, then priority
    static func sortForDisplay(_ blocks: [ScheduleBlock]) -> [ScheduleBlock] {
        blocks.sorted { a, b in
            // Scheduled items first
            if a.isScheduled != b.isScheduled {
                return a.isScheduled
            }

            // Then by start time
            if let aStart = a.startTime, let bStart = b.startTime {
                if aStart != bStart {
                    return aStart < bStart
                }
            }

            // Then by priority
            if a.priority.sortOrder != b.priority.sortOrder {
                return a.priority.sortOrder < b.priority.sortOrder
            }

            // Finally by title
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
}
