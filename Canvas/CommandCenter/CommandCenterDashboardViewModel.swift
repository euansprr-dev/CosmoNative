// Canvas/CommandCenter/CommandCenterDashboardViewModel.swift
// Unified state coordinator for the Command Center Dashboard
// March 2026

import SwiftUI
import Combine
import GRDB

/// Shared wording for the delete-series confirmations (task list, menus, detail
/// panel, inline editor) — deleting a series keeps its completion history now,
/// and every surface should say so the same way.
enum SeriesDeleteCopy {
    static func message(completionCount: Int) -> String {
        switch completionCount {
        case 0:
            return "This removes the repeating task."
        case 1:
            return "This removes the current occurrence and all future ones. Your 1 logged completion stays in your history."
        default:
            return "This removes the current occurrence and all future ones. Your \(completionCount) logged completions stay in your history."
        }
    }
}

// MARK: - Task writes

/// Persistence only. The dashboard's database observation owns freshness;
/// keeping a second Today mirror here added a full-table read and another
/// delayed refresh after each creation and completion.
@MainActor
private enum DashboardTaskPersistence {
    /// Returns false when the completion did NOT persist (missing atom, corrupt metadata,
    /// or write failure) so callers can reverse optimistic UI and withhold habit/XP credit.
    @discardableResult
    static func completeTask(taskId: String, completedAt: Date = Date()) async -> Bool {
        do {
            var applied = false
            let result = try await AtomRepository.shared.update(uuid: taskId) { atom in
                guard var metadata = taskMetadataForWrite(atom, context: "DashboardTaskPersistence.completeTask(\(taskId.prefix(8)))") else { return }
                metadata.isCompleted = true
                metadata.completedAt = ISO8601.string(from: completedAt)
                guard let merged = atom.mergingTaskMetadata(metadata, context: "DashboardTaskPersistence.completeTask(\(taskId.prefix(8)))") else { return }
                atom = merged
                applied = true
            }
            guard applied, result != nil else { return false }
            return true
        } catch {
            PersistenceHealth.note(.writeFailure, context: "DashboardTaskPersistence.completeTask(\(taskId.prefix(8)))", detail: error.localizedDescription)
            return false
        }
    }

    /// Returns the created atom, or nil when creation failed — callers must surface the
    /// failure instead of pretending the task exists.
    @discardableResult
    static func quickAddTask(title: String) async -> Atom? {
        do {
            let atom = Atom.new(type: .task, title: title)
            let created = try await AtomRepository.shared.create(atom)
            return created
        } catch {
            PersistenceHealth.note(.writeFailure, context: "DashboardTaskPersistence.quickAddTask", detail: error.localizedDescription)
            return nil
        }
    }
}

// MARK: - Task Metadata Write Guard

/// Decode-state guard for every task write: absent → fresh metadata, corrupt → nil
/// (reported via PersistenceHealth). Callers MUST bail out of the write when this
/// returns nil so a corrupt column is never overwritten by a default-derived re-encode
/// (the "one completion tap erases the recurrence rule + completion log" failure mode).
private func taskMetadataForWrite(_ atom: Atom, context: String) -> TaskMetadata? {
    switch atom.decodedMetadata(as: TaskMetadata.self) {
    case .absent:
        return TaskMetadata()
    case .value(let metadata):
        return metadata
    case .corrupt(let error):
        PersistenceHealth.note(.decodeFailure, context: context, detail: "task metadata undecodable; refusing write (\(error.localizedDescription))")
        return nil
    }
}

// MARK: - Habit State

struct HabitState: Identifiable, Equatable {
    let id: String
    let title: String
    let iconName: String
    let accentColor: Color
    var todayProgress: Double
    var isTodayComplete: Bool
    var last7Days: [Bool]
    var consistencyCount: Int
    var allowManualComplete: Bool
    var targetCount: Int
    var todayCount: Int
    var trackedMinutesToday: Int
    var isTimeBased: Bool
    var targetMinutes: Int?
    var sourceBreakdown: HabitSourceBreakdown
    var isBuiltIn: Bool
    var isEditable: Bool
    var linkedIntentSummary: String?

    /// "2/3 today" for count habits, "42/60m today" for time-based habits.
    var todayProgressLabel: String {
        if isTimeBased, let targetMinutes, targetMinutes > 0 {
            return "\(min(trackedMinutesToday, targetMinutes))/\(targetMinutes)m today"
        }
        return "\(todayCount)/\(max(targetCount, 1)) today"
    }
}

private enum DashboardRefreshDomain: Hashable {
    case tasks
    case habits
    case timeData
    case sessions
    case weeklyReport
    case scheduleBlocks
}

enum RecurringTaskTitleEditScope: String, CaseIterable, Sendable {
    case currentOnly
    case currentAndFuture
}

private struct DashboardAtomSubsetSignature: Equatable {
    let count: Int
    let versionSum: Int64
    let latestUpdatedAt: String

    /// SQL-aggregate signature: any insert/update/delete in the subset moves
    /// count, the _local_version sum, or MAX(updated_at). Replaces hashing a
    /// full decoded atoms array (the old AtomRepository.$atoms mirror decoded
    /// every atom in the database on every write, app-wide).
    static func fetch(_ db: Database, types: [AtomType]) throws -> DashboardAtomSubsetSignature {
        let typeList = types.map { "'\($0.rawValue)'" }.joined(separator: ",")
        let row = try Row.fetchOne(db, sql: """
            SELECT COUNT(*) AS c,
                   COALESCE(SUM(_local_version), 0) AS v,
                   COALESCE(MAX(updated_at), '') AS u
            FROM atoms
            WHERE is_deleted = 0 AND type IN (\(typeList))
            """)
        return DashboardAtomSubsetSignature(
            count: row?["c"] ?? 0,
            versionSum: row?["v"] ?? 0,
            latestUpdatedAt: row?["u"] ?? ""
        )
    }
}

private struct DashboardAtomRefreshSignature: Equatable {
    let tasks: DashboardAtomSubsetSignature
    let deepWork: DashboardAtomSubsetSignature
    let scheduleBlocks: DashboardAtomSubsetSignature

    static func fetch(_ db: Database) throws -> DashboardAtomRefreshSignature {
        DashboardAtomRefreshSignature(
            tasks: try DashboardAtomSubsetSignature.fetch(db, types: [.task]),
            deepWork: try DashboardAtomSubsetSignature.fetch(db, types: [.deepWorkBlock]),
            scheduleBlocks: try DashboardAtomSubsetSignature.fetch(db, types: [.scheduleBlock])
        )
    }
}

struct CommandCenterTodayTaskSections: Equatable {
    var overdue: [TaskViewModel]
    var scheduled: [TaskViewModel]
    var unscheduled: [TaskViewModel]
}

enum CommandCenterTodayTaskSectioning {
    /// Sections tasks for a single day page. Overdue is anchored to the *actual*
    /// today (`today`), never the viewed day: tasks planned before today ride
    /// along as Overdue only on today's page (matching iOS TodayEngine's
    /// grammar). Any other day — past or future — shows only its own tasks, so
    /// browsing ahead never brands today's still-live tasks as overdue.
    static func sectionTasks(
        _ tasks: [TaskViewModel],
        selectedDate: Date,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> CommandCenterTodayTaskSections {
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let isViewingToday = calendar.isDate(selectedDate, inSameDayAs: today)

        var overdue: [TaskViewModel] = []
        var scheduled: [TaskViewModel] = []
        var unscheduled: [TaskViewModel] = []
        let recurrenceParentsWithSelectedDayInstance = Set(
            tasks.compactMap { task -> String? in
                guard let parentUUID = task.recurrenceParentUUID,
                      isPlannedOnSelectedDay(task, dayStart: dayStart, dayEnd: dayEnd, calendar: calendar) else {
                    return nil
                }
                return parentUUID
            }
        )

        for task in tasks {
            if let calendarStart = task.calendarStart(using: calendar) {
                if calendarStart >= dayStart && calendarStart < dayEnd {
                    scheduled.append(task)
                } else if isViewingToday, calendarStart < dayStart,
                          !isSuppressedRecurringOverdue(task, repeatedTodayParents: recurrenceParentsWithSelectedDayInstance) {
                    overdue.append(task)
                }
                continue
            }

            guard let plannedDate = plannedDate(for: task) else { continue }
            let plannedDay = calendar.startOfDay(for: plannedDate)

            if isViewingToday, plannedDay < dayStart,
               !isSuppressedRecurringOverdue(task, repeatedTodayParents: recurrenceParentsWithSelectedDayInstance) {
                overdue.append(task)
            } else if plannedDay >= dayStart && plannedDay < dayEnd {
                unscheduled.append(task)
            }
        }

        return CommandCenterTodayTaskSections(
            overdue: overdue.sorted(by: overdueSort(calendar: calendar)),
            scheduled: scheduled.sorted(by: scheduledSort(calendar: calendar)),
            unscheduled: unscheduled.sorted(by: unscheduledSort)
        )
    }

    private static func plannedDate(for task: TaskViewModel) -> Date? {
        task.whenDate ?? task.scheduledDate ?? task.dueDate
    }

    private static func isPlannedOnSelectedDay(
        _ task: TaskViewModel,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> Bool {
        if let calendarStart = task.calendarStart(using: calendar) {
            return calendarStart >= dayStart && calendarStart < dayEnd
        }

        guard let plannedDate = plannedDate(for: task) else { return false }
        let plannedDay = calendar.startOfDay(for: plannedDate)
        return plannedDay >= dayStart && plannedDay < dayEnd
    }

    private static func isSuppressedRecurringOverdue(
        _ task: TaskViewModel,
        repeatedTodayParents: Set<String>
    ) -> Bool {
        guard let parentUUID = task.recurrenceParentUUID else { return false }
        return repeatedTodayParents.contains(parentUUID)
    }

    /// Overdue reads oldest-debt-first until a hand touches it — then the hand
    /// wins (iOS `TodayEngine`: "hand-placed order wins within a band"). Before
    /// any drag every row's `manualSortOrder` is nil, so the day comparison
    /// decides; a single reorder stamps the whole band, and from then on the
    /// arrangement is the user's. Without this promotion the band shuffled under
    /// the pointer and reverted on the next load.
    private static func overdueSort(calendar: Calendar) -> (TaskViewModel, TaskViewModel) -> Bool {
        { lhs, rhs in
            if lhs.manualSortOrder != rhs.manualSortOrder {
                return (lhs.manualSortOrder ?? Int.max) < (rhs.manualSortOrder ?? Int.max)
            }
            let lhsDay = plannedDate(for: lhs).map { calendar.startOfDay(for: $0) } ?? lhs.calendarStart(using: calendar) ?? .distantPast
            let rhsDay = plannedDate(for: rhs).map { calendar.startOfDay(for: $0) } ?? rhs.calendarStart(using: calendar) ?? .distantPast
            if lhsDay != rhsDay { return lhsDay < rhsDay }
            return fallbackSort(lhs, rhs)
        }
    }

    private static func scheduledSort(calendar: Calendar) -> (TaskViewModel, TaskViewModel) -> Bool {
        { lhs, rhs in
            let lhsStart = lhs.calendarStart(using: calendar) ?? .distantFuture
            let rhsStart = rhs.calendarStart(using: calendar) ?? .distantFuture
            if lhsStart != rhsStart { return lhsStart < rhsStart }
            return fallbackSort(lhs, rhs)
        }
    }

    private static func unscheduledSort(_ lhs: TaskViewModel, _ rhs: TaskViewModel) -> Bool {
        if lhs.manualSortOrder != rhs.manualSortOrder {
            return (lhs.manualSortOrder ?? Int.max) < (rhs.manualSortOrder ?? Int.max)
        }
        if lhs.priority.sortOrder != rhs.priority.sortOrder {
            return lhs.priority.sortOrder < rhs.priority.sortOrder
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func fallbackSort(_ lhs: TaskViewModel, _ rhs: TaskViewModel) -> Bool {
        if lhs.manualSortOrder != rhs.manualSortOrder {
            return (lhs.manualSortOrder ?? Int.max) < (rhs.manualSortOrder ?? Int.max)
        }
        if lhs.priority.sortOrder != rhs.priority.sortOrder {
            return lhs.priority.sortOrder < rhs.priority.sortOrder
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

enum CommandCenterDateSelection {
    static func dateForCurrentDayChange(
        selectedDate: Date,
        previousToday: Date,
        newToday: Date,
        calendar: Calendar = .current
    ) -> Date {
        if calendar.isDate(selectedDate, inSameDayAs: previousToday) {
            return calendar.startOfDay(for: newToday)
        }
        return selectedDate
    }
}

enum CommandCenterTaskScheduling {
    @discardableResult
    static func moveCalendarTime(
        in metadata: inout TaskMetadata,
        toDate date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard let currentStart = calendarTimeStart(in: metadata),
              let rescheduledStart = merged(date: day, time: currentStart, calendar: calendar) else {
            return false
        }

        let duration = calendarTimeDurationMinutes(in: metadata, start: currentStart)
        let rescheduledEnd = calendar.date(byAdding: .minute, value: duration, to: rescheduledStart)
            ?? rescheduledStart.addingTimeInterval(TimeInterval(duration * 60))
        applyCalendarTimeRange(start: rescheduledStart, end: rescheduledEnd, to: &metadata, calendar: calendar)
        return true
    }

    /// Place a task at an ABSOLUTE time range. The sibling of `reschedule` for
    /// callers that are *setting* a time rather than *moving* one — dropping an
    /// idea onto the week board's hour grid, chiefly.
    ///
    /// Why this exists rather than seeding the time and calling `reschedule`:
    /// `reschedule` routes through `moveCalendarTime` → `merged(date:time:)`,
    /// which rebuilds the start from date+time COMPONENTS and returns nil for a
    /// wall-clock time that doesn't exist (the spring-forward gap). On nil,
    /// `reschedule` silently falls back to `applyPlannedDate` and the task
    /// renders all-day — a downgrade with no error and no toast. Taking an
    /// absolute `Date` and never re-deriving it sidesteps that entirely.
    ///
    /// `schedulingState` is cleared here for parity with `reschedule` — a row
    /// holding a time block AND an anytime/someday bucket makes
    /// `unifiedPinCorrection` bail out and paints in both places at once.
    static func schedule(
        _ metadata: inout TaskMetadata,
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) {
        let floor = calendar.date(byAdding: .minute, value: CommandCenterCalendarLayout.snapMinutes, to: start)
            ?? start.addingTimeInterval(TimeInterval(CommandCenterCalendarLayout.snapMinutes * 60))
        applyCalendarTimeRange(start: start, end: max(end, floor), to: &metadata, calendar: calendar)
        metadata.schedulingState = nil
    }

    /// Strip a task's time block, leaving its day pins alone. Public so the
    /// all-day lane can land a session that previously had a time: `reschedule`
    /// alone would CARRY the old wall-clock time onto the new day and the entry
    /// would reappear in the hour grid at a time nobody picked.
    static func clearCalendarTime(from metadata: inout TaskMetadata) {
        metadata.startTime = nil
        metadata.endTime = nil
        metadata.scheduledStart = nil
        metadata.scheduledEnd = nil
        metadata.durationMinutes = nil
    }

    static func reschedule(
        _ metadata: inout TaskMetadata,
        toDate date: Date?,
        calendar: Calendar = .current
    ) {
        guard let date else {
            clearPlannedDate(from: &metadata)
            clearCalendarTime(from: &metadata)
            metadata.schedulingState = nil
            return
        }

        let day = calendar.startOfDay(for: date)
        if !moveCalendarTime(in: &metadata, toDate: day, calendar: calendar) {
            applyPlannedDate(day, to: &metadata)
        }

        metadata.schedulingState = nil
    }

    /// Detects the cross-device reschedule lag TaskDayPinRepair heals: a client
    /// moved dueDate+focusDate to a new day but left whenDate stranded behind
    /// (the pre-fix iOS reschedule wrote only due/focus). Every legitimate Mac
    /// writer moves the three pins together, and the deliberate split shape
    /// (deadline ≠ planned day) has focusDate on the whenDate side — so
    /// "focus == due, whenDate strictly earlier" only arises from the lag.
    /// Returns the corrected whenDate string, or nil when the shape is healthy.
    static func laggingWhenDateCorrection(
        in metadata: TaskMetadata,
        calendar: Calendar = .current
    ) -> String? {
        guard metadata.recurrence == nil, metadata.recurrenceParentUUID == nil,
              let due = metadata.dueDate.flatMap({ PlannerumFormatters.iso8601.date(from: $0) }),
              let focus = metadata.focusDate.flatMap({ PlannerumFormatters.iso8601.date(from: $0) }),
              let when = metadata.whenDate.flatMap({ PlannerumFormatters.iso8601.date(from: $0) })
        else { return nil }
        let dueDay = calendar.startOfDay(for: due)
        guard calendar.isDate(focus, inSameDayAs: due),
              calendar.startOfDay(for: when) < dueDay else { return nil }
        return PlannerumFormatters.iso8601.string(from: dueDay)
    }

    /// One-date unification (July 2026): a task has a single day, so the three
    /// storage pins must agree. Returns the ISO day every pin should hold —
    /// the task's planned day, whenDate ?? focusDate ?? dueDate — or nil when
    /// the pins already agree (or none is set). Recurring templates and
    /// occurrences are excluded: their anchor semantics live in
    /// seriesAnchorDay and must not be rewritten by a bulk repair.
    static func unifiedPinCorrection(
        in metadata: TaskMetadata,
        calendar: Calendar = .current
    ) -> String? {
        guard metadata.recurrence == nil, metadata.recurrenceParentUUID == nil else { return nil }
        // Anytime/Someday rows may carry a residual dueDate from the old
        // deadline model — stamping the other pins would make them MORE
        // dated, not less. Leave bucketed tasks alone.
        guard metadata.schedulingState == nil else { return nil }
        let pins = [metadata.whenDate, metadata.focusDate, metadata.dueDate]
        let parsed = pins.map { $0.flatMap { PlannerumFormatters.iso8601.date(from: $0) } }
        guard let planned = parsed.compactMap({ $0 }).first else { return nil }
        let plannedDay = calendar.startOfDay(for: planned)
        let unified = parsed.allSatisfy { date in
            guard let date else { return false }
            return calendar.isDate(date, inSameDayAs: plannedDay)
        }
        return unified ? nil : PlannerumFormatters.iso8601.string(from: plannedDay)
    }

    private static func applyPlannedDate(_ day: Date, to metadata: inout TaskMetadata) {
        let dateString = PlannerumFormatters.iso8601.string(from: day)
        metadata.dueDate = dateString
        metadata.focusDate = dateString
        metadata.whenDate = dateString
    }

    private static func clearPlannedDate(from metadata: inout TaskMetadata) {
        metadata.dueDate = nil
        metadata.focusDate = nil
        metadata.whenDate = nil
    }

    private static func applyCalendarTimeRange(
        start: Date,
        end: Date,
        to metadata: inout TaskMetadata,
        calendar: Calendar
    ) {
        let day = calendar.startOfDay(for: start)
        applyPlannedDate(day, to: &metadata)
        metadata.startTime = PlannerumFormatters.iso8601.string(from: start)
        metadata.endTime = PlannerumFormatters.iso8601.string(from: end)
        metadata.scheduledStart = metadata.startTime
        metadata.scheduledEnd = metadata.endTime
        metadata.durationMinutes = max(15, Int(end.timeIntervalSince(start) / 60))
    }

    private static func calendarTimeStart(in metadata: TaskMetadata) -> Date? {
        for candidate in [metadata.scheduledStart, metadata.startTime] {
            if let candidate, let date = PlannerumFormatters.iso8601.date(from: candidate) {
                return date
            }
        }
        return nil
    }

    private static func calendarTimeEnd(in metadata: TaskMetadata) -> Date? {
        for candidate in [metadata.scheduledEnd, metadata.endTime] {
            if let candidate, let date = PlannerumFormatters.iso8601.date(from: candidate) {
                return date
            }
        }
        return nil
    }

    private static func calendarTimeDurationMinutes(in metadata: TaskMetadata, start: Date) -> Int {
        if let end = calendarTimeEnd(in: metadata), end > start {
            return max(15, Int(end.timeIntervalSince(start) / 60))
        }
        return max(15, metadata.durationMinutes ?? metadata.estimatedFocusMinutes ?? 30)
    }

    private static func merged(date: Date, time: Date, calendar: Calendar) -> Date? {
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var merged = DateComponents()
        merged.calendar = calendar
        merged.timeZone = calendar.timeZone
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second ?? 0
        return calendar.date(from: merged)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class CommandCenterDashboardViewModel {

    // MARK: - View Mode

    var viewMode: DashboardViewMode = .today {
        didSet {
            guard oldValue != viewMode else { return }
            handleViewModeChange(viewMode)
        }
    }

    // MARK: - Date Selection

    var selectedDate: Date = Date() {
        didSet {
            guard !Calendar.current.isDate(oldValue, inSameDayAs: selectedDate) else { return }
            handleSelectedDateChange()
        }
    }

    // MARK: - Sectioned Tasks (Today view)

    var overdueTasks: [TaskViewModel] = []
    var scheduledTasks: [TaskViewModel] = []
    var unscheduledTasks: [TaskViewModel] = []
    var completedTodayTasks: [TaskViewModel] = []
    var completedTasksByDay: [(date: Date, tasks: [TaskViewModel])] = []

    // MARK: - Upcoming (Upcoming view)

    var upcomingDayGroups: [UpcomingDayViewModel] = []
    /// Schedule blocks per visible day — the Upcoming board draws them as
    /// display-only calendar cards (editing lives on the Today timeline).
    var upcomingScheduleBlocksByDay: [Date: [ScheduleBlockEntry]] = [:]
    /// True while a task row is being dragged anywhere in the ledger — the
    /// timeline reads it to wake its drop targets (continuous feedback: the
    /// invitation appears the moment the pickup happens, not at the drop).
    var isTaskDragInFlight = false
    var upcomingWeekOffset: Int = 0
    var upcomingCalendarEvents: [String: [CalendarEvent]] = [:]  // keyed by date string
    var upcomingCalendarScope: UpcomingCalendarScope = .week
    var upcomingAnchorDate: Date = Calendar.current.startOfDay(for: Date())

    /// Which face Upcoming wears: the week schedule or the content calendar.
    /// Persisted so the planning surface reopens where you left it.
    var upcomingLens: UpcomingLens = {
        // A persisted `.content` (the retired lens) reopens as the schedule.
        let stored = UpcomingLens(
            rawValue: UserDefaults.standard.string(forKey: CommandCenterDashboardViewModel.upcomingLensDefaultsKey) ?? ""
        ) ?? .schedule
        return stored == .content ? .schedule : stored
    }() {
        didSet {
            guard oldValue != upcomingLens else { return }
            UserDefaults.standard.set(upcomingLens.rawValue, forKey: Self.upcomingLensDefaultsKey)
        }
    }

    private static let upcomingLensDefaultsKey = "commandCenter.upcomingLens"

    /// Which face the right rail wears on Upcoming's schedule lens: the
    /// habits/reports/details inspector, or the Shelf you drag ideas from.
    /// Defaults to `.shelf` so the capability is discoverable; persisted so a
    /// deliberate flip to the inspector sticks.
    var upcomingRailFace: UpcomingRailFace = UpcomingRailFace(
        rawValue: UserDefaults.standard.string(forKey: CommandCenterDashboardViewModel.upcomingRailFaceDefaultsKey) ?? ""
    ) ?? .shelf {
        didSet {
            guard oldValue != upcomingRailFace else { return }
            UserDefaults.standard.set(upcomingRailFace.rawValue, forKey: Self.upcomingRailFaceDefaultsKey)
        }
    }

    private static let upcomingRailFaceDefaultsKey = "commandCenter.upcomingRailFace"

    var upcomingWeekStart: Date {
        CommandCenterCalendarLayout.mondayStartingWeek(containing: upcomingAnchorDate)
    }

    var upcomingVisibleDates: [Date] {
        CommandCenterCalendarLayout.visibleDates(
            anchor: upcomingAnchorDate,
            scope: upcomingCalendarScope,
            calendar: Calendar.current
        )
    }

    var upcomingVisibleInterval: DateInterval {
        CommandCenterCalendarLayout.visibleInterval(
            anchor: upcomingAnchorDate,
            scope: upcomingCalendarScope,
            calendar: Calendar.current
        )
    }

    var upcomingRangeText: String {
        // The content lens is always a month at a glance.
        if upcomingLens == .content {
            return CosmoDateFormatters.monthYear.string(from: upcomingAnchorDate)
        }

        let dates = upcomingVisibleDates
        guard let first = dates.first, let last = dates.last else { return "" }

        switch upcomingCalendarScope {
        case .day:
            return CosmoDateFormatters.abbreviatedWeekdayMonthDay.string(from: upcomingAnchorDate)
        case .week:
            return "\(CosmoDateFormatters.abbreviatedMonthDay.string(from: first)) - \(CosmoDateFormatters.abbreviatedMonthDay.string(from: last))"
        case .month:
            return CosmoDateFormatters.monthYear.string(from: upcomingAnchorDate)
        }
    }

    // MARK: - Things 3 Smart Lists

    var anytimeTasks: [TaskViewModel] = []
    var somedayTasks: [TaskViewModel] = []
    var logbookTasks: [TaskViewModel] = []

    // MARK: - Areas & Projects (Sidebar)

    var areas: [Atom] = []
    var projects: [Atom] = []
    var selectedProjectUUID: String?
    var selectedAreaUUID: String?
    var projectTasks: [TaskViewModel] = []
    var projectHeadings: [ProjectHeading] = []

    // MARK: - Timeline Sessions

    var todaySessions: [SessionTimelineEntry] = []

    // MARK: - Keyboard Selection

    var selectedTaskIndex: Int?

    // MARK: - Habits

    var habits: [HabitState] = []


    // MARK: - Calendar Events

    var todayEvents: [CalendarEvent] = []

    // MARK: - Schedule Blocks (pure time blocking — iOS planner parity)

    /// The viewed day's schedule blocks, recurring templates already
    /// projected (ScheduleBlockEngine mirrors the iOS contract).
    var todayScheduleBlocks: [ScheduleBlockEntry] = []

    // MARK: - Quick Stats


    // MARK: - Reports

    var weeklyReportData: WeeklyReportData?
    var showReports: Bool = false
    var selectedReportTab: ReportTab = .week
    var reportWeekOffset: Int = 0
    var reportMonthOffset: Int = 0
    var habitReportData: HabitReportData?

    // MARK: - Time Tracking

    var todayTrackedMinutes: Int = 0
    var todayIntentSummaries: [IntentSummary] = []
    var completedArrivalToken: Int = 0

    // MARK: - Task Add

    var newTaskTitle: String = ""
    var pendingTaskDate: Date?

    // MARK: - Dependencies

    let sessionEngine = DeepWorkSessionEngine.shared
    private let calendarService = CalendarSyncService.shared
    private let habitEngine = CommandCenterHabitEngine.shared
    private let intentEngine = CommandCenterIntentEngine.shared
    private var cancellables = Set<AnyCancellable>()
    private var inFlightRefreshes: [DashboardRefreshDomain: Task<Void, Never>] = [:]
    private var queuedRefreshDomains = Set<DashboardRefreshDomain>()
    private var lastAtomRefreshSignature: DashboardAtomRefreshSignature?
    private var lastObservedTodayStart = Calendar.current.startOfDay(for: Date())

    // MARK: - Computed

    /// Tasks completed on the viewed day — the receding "Completed" section at the
    /// bottom of Today (iOS parity: finished work stays in place, dimmed, instead of
    /// vanishing straight to the Logbook). Derived from the already-grouped completed
    /// set so it stays correct as you navigate days; sorted completedAt-descending.
    var completedTasksForSelectedDay: [TaskViewModel] {
        let calendar = Calendar.current
        return completedTasksByDay
            .first { calendar.isDate($0.date, inSameDayAs: selectedDate) }?
            .tasks ?? []
    }

    /// Flat list of currently visible tasks for keyboard navigation
    var currentVisibleTasks: [TaskViewModel] {
        switch viewMode {
        case .today:
            return overdueTasks + scheduledTasks + unscheduledTasks + completedTasksForSelectedDay
        case .upcoming:
            return upcomingDayGroups.flatMap { $0.tasks }
        case .logbook:
            return completedTasksByDay.flatMap { $0.tasks }
        case .anytime:
            return anytimeTasks
        case .someday:
            return somedayTasks
        case .habits, .reports, .queue:
            return []
        case .project:
            return projectTasks
        case .area:
            return []  // Area view aggregates from projects
        }
    }

    var todayActiveCount: Int {
        overdueTasks.count + scheduledTasks.count + unscheduledTasks.count
    }

    var upcomingTotalCount: Int {
        upcomingDayGroups.reduce(0) { $0 + $1.taskCount }
    }

    // MARK: - Init

    init(startsRefreshing: Bool = true) {
        guard startsRefreshing else { return }

        setupBindings()
    }

    // MARK: - Initial Load (deferred to the dashboard's first appearance)

    /// One-time migrations + first full refresh. Lives here instead of init so
    /// creating the VM at app launch (MainView owns it) costs nothing; the
    /// dashboard's `.task` runs this on first visit.
    @ObservationIgnored private var hasPerformedInitialLoad = false
    /// Arrival cascade plays once per app session (view-local state reset on
    /// every remount and re-ran the entrance on each revisit).
    var hasPlayedArrivalCascade = false

    /// The habit rail's ring sweep is an ARRIVAL, and you only arrive once —
    /// @State on the panel reset every time the Habits/Reports tab switch
    /// remounted it, replaying all five rings (a decorative loop).
    var hasPlayedHabitRingSweep = false
    @ObservationIgnored private var hasLoadedAreas = false
    @ObservationIgnored private var hasLoadedAnytime = false
    @ObservationIgnored private var hasLoadedSomeday = false

    func startInitialLoadIfNeeded() async {
        guard !hasPerformedInitialLoad else { return }
        hasPerformedInitialLoad = true
        await RecurringSeriesEngine.shared.runCleanSlateMigrationIfNeeded()
        await TaskDayPinRepair.runIfNeeded()
        await refreshAll()
    }

    /// Revisit-guards: the VM persists across destination switches, so these
    /// warm loads run once — mode switches and the change-signature refresh
    /// keep the data fresh afterwards.
    func loadAreasIfNeeded() async {
        guard !hasLoadedAreas else { return }
        hasLoadedAreas = true
        await loadAreas()
    }

    func loadAnytimeTasksIfNeeded() async {
        guard !hasLoadedAnytime else { return }
        hasLoadedAnytime = true
        await loadAnytimeTasks()
    }

    func loadSomedayTasksIfNeeded() async {
        guard !hasLoadedSomeday else { return }
        hasLoadedSomeday = true
        await loadSomedayTasks()
    }

    private var hasLoadedHabits = false

    func loadHabitsIfNeeded() async {
        guard !hasLoadedHabits else { return }
        hasLoadedHabits = true
        await loadHabits()
    }

    // MARK: - Property-change handlers (were Combine $-sinks pre-@Observable)

    private func handleSelectedDateChange() {
        Task { [weak self] in
            guard let self else { return }
            if self.viewMode == .upcoming {
                self.upcomingAnchorDate = Calendar.current.startOfDay(for: self.selectedDate)
                self.syncUpcomingWeekOffset()
                await self.loadUpcomingTasks()
            } else {
                await self.refreshTasks()
            }
            self.refreshCalendarEvents()
            await self.refreshScheduleBlocks()
        }
    }

    private func handleViewModeChange(_ mode: DashboardViewMode) {
        Task { [weak self] in
            switch mode {
            case .today:
                await self?.refreshTasks()
            case .upcoming:
                await self?.loadUpcomingTasks()
            case .logbook:
                await self?.loadCompletedTasks()
            case .anytime:
                await self?.loadAnytimeTasks()
            case .someday:
                await self?.loadSomedayTasks()
            case .habits:
                await self?.loadHabits()
                await self?.loadHabitReport()
                await self?.loadTodayTimeData()
            case .reports:
                await self?.loadTodayTimeData()
                await self?.loadTodaySessions()
                await self?.loadWeeklyReport()
                await self?.loadHabitReport()
            case .queue:
                // Retired page — old jump targets land on the Pipeline's
                // calendar (the queue's successor, twice removed).
                self?.viewMode = .upcoming
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openPipeline,
                    object: nil,
                    userInfo: ["view": PipelineView.calendar.rawValue]
                )
            case .project:
                if let uuid = self?.selectedProjectUUID {
                    await self?.loadProjectTasks(projectUUID: uuid)
                }
            case .area:
                break
            }
            self?.selectedTaskIndex = nil
        }
    }

    // MARK: - Bindings

    private func setupBindings() {
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .sink { [weak self] _ in
                self?.handleCurrentDayChange()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
            .sink { [weak self] _ in
                self?.handleCurrentDayChange()
            }
            .store(in: &cancellables)

        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.handleCurrentDayChange(now: now)
            }
            .store(in: &cancellables)

        // Atom-change signal via a cheap SQL aggregate observation — fires on
        // any atoms write but never decodes rows (the old full-table
        // AtomRepository.$atoms mirror re-decoded every atom per write).
        CosmoDatabase.shared.observe { db in
            try DashboardAtomRefreshSignature.fetch(db)
        }
        .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
        .sink(
            receiveCompletion: { _ in },
            receiveValue: { [weak self] signature in
                self?.handleAtomRefreshSignature(signature)
            }
        )
        .store(in: &cancellables)

        habitEngine.$definitions
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleRefresh(.habits, delayNanoseconds: 100_000_000)
            }
            .store(in: &cancellables)

        Publishers.MergeMany([
            NotificationCenter.default.publisher(for: .deepWorkSessionStarted).map { _ in Notification.Name.deepWorkSessionStarted },
            NotificationCenter.default.publisher(for: .deepWorkSessionPaused).map { _ in Notification.Name.deepWorkSessionPaused },
            NotificationCenter.default.publisher(for: .deepWorkSessionResumed).map { _ in Notification.Name.deepWorkSessionResumed },
            NotificationCenter.default.publisher(for: .deepWorkSessionExtended).map { _ in Notification.Name.deepWorkSessionExtended },
            NotificationCenter.default.publisher(for: .deepWorkSessionEnded).map { _ in Notification.Name.deepWorkSessionEnded }
        ])
        .sink { [weak self] name in
            self?.scheduleRefresh(.timeData, delayNanoseconds: 100_000_000)
            self?.scheduleRefresh(.sessions, delayNanoseconds: 100_000_000)
            if name == .deepWorkSessionEnded {
                self?.scheduleRefresh(.weeklyReport, delayNanoseconds: 150_000_000)
                self?.scheduleRefresh(.habits, delayNanoseconds: 150_000_000)
                // Timed-goal sessions can auto-complete their task on end
                self?.scheduleRefresh(.tasks, delayNanoseconds: 150_000_000)
            }
        }
        .store(in: &cancellables)

        // Timed goal completions (prompt "Mark complete" or session-end auto-complete)
        // change task + habit state outside the dashboard's own mutation paths.
        NotificationCenter.default.publisher(for: .timedGoalTaskCompleted)
            .sink { [weak self] _ in
                self?.scheduleRefresh(.tasks, delayNanoseconds: 100_000_000)
                self?.scheduleRefresh(.habits, delayNanoseconds: 150_000_000)
            }
            .store(in: &cancellables)

        // Calendar events (debounced — CalendarSyncService publishes on refresh)
        calendarService.$externalEvents
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCalendarEvents()
                Task { [weak self] in
                    await self?.loadUpcomingCalendarEvents()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Refresh

    func refreshAll() async {
        // Definition refreshes feed the loaders below — they run first.
        async let intentDefs: Void = intentEngine.refreshDefinitions()
        async let habitDefs: Void = habitEngine.refreshDefinitions()
        _ = await (intentDefs, habitDefs)

        // Independent loads write disjoint state — one concurrent wave
        // instead of the nine sequential awaits this used to be (the first
        // dashboard paint waited on the full chain).
        refreshCalendarEvents()
        async let tasks: Void = refreshInitialTaskCollections()
        async let schedule: Void = refreshScheduleBlocks()
        async let habitStates: Void = loadHabits()
        async let timeData: Void = loadTodayTimeData()
        async let sessions: Void = loadTodaySessions()
        async let weekly: Void = loadWeeklyReport()
        _ = await (tasks, schedule, habitStates, timeData, sessions, weekly)
    }

    private func refreshInitialTaskCollections() async {
        guard let atoms = try? await loadTaskAtoms(nil) else { return }
        await refreshTasks(from: atoms)
        await loadAnytimeTasks(from: atoms)
        await loadSomedayTasks(from: atoms)
        hasLoadedAnytime = true
        hasLoadedSomeday = true
    }

    private func scheduleRefresh(_ domain: DashboardRefreshDomain, delayNanoseconds: UInt64 = 0) {
        if inFlightRefreshes[domain] != nil {
            queuedRefreshDomains.insert(domain)
            return
        }

        inFlightRefreshes[domain] = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self else { return }
            await self.performRefresh(domain)
            self.finishRefresh(domain)
        }
    }

    private func performRefresh(_ domain: DashboardRefreshDomain) async {
        switch domain {
        case .tasks:
            guard let atoms = try? await loadTaskAtoms(nil) else { return }
            await refreshTasks(from: atoms)
            // The signature fires for EVERY task-table write, including sync
            // pulls from the iPhone. Today always repaints above; the list the
            // user is actually looking at must repaint too, or a phone-side
            // reschedule sits stale on Upcoming/Anytime/Someday/Project until
            // the next interaction.
            switch viewMode {
            case .upcoming:
                await loadUpcomingTasks(from: atoms)
            case .logbook:
                break
            case .anytime:
                await loadAnytimeTasks(from: atoms)
            case .someday:
                await loadSomedayTasks(from: atoms)
            case .project:
                if let uuid = selectedProjectUUID {
                    await loadProjectTasks(projectUUID: uuid)
                }
            case .today, .habits, .reports, .queue, .area:
                break
            }
        case .habits:
            await loadHabits()
        case .timeData:
            await loadTodayTimeData()
        case .sessions:
            await loadTodaySessions()
        case .weeklyReport:
            switch selectedReportTab {
            case .week:
                await loadWeeklyReport()
            case .month:
                await loadMonthReport()
            case .habits:
                await loadHabitReport()
            }
        case .scheduleBlocks:
            await refreshScheduleBlocks()
        }
    }

    private func finishRefresh(_ domain: DashboardRefreshDomain) {
        inFlightRefreshes[domain] = nil
        if queuedRefreshDomains.remove(domain) != nil {
            scheduleRefresh(domain)
        }
    }

    private func handleAtomRefreshSignature(_ signature: DashboardAtomRefreshSignature) {
        guard let previous = lastAtomRefreshSignature else {
            lastAtomRefreshSignature = signature
            return
        }

        if previous.tasks != signature.tasks {
            scheduleRefresh(.tasks, delayNanoseconds: 200_000_000)
            scheduleRefresh(.habits, delayNanoseconds: 200_000_000)
            scheduleRefresh(.weeklyReport, delayNanoseconds: 250_000_000)
        }

        if previous.deepWork != signature.deepWork {
            scheduleRefresh(.timeData, delayNanoseconds: 150_000_000)
            scheduleRefresh(.sessions, delayNanoseconds: 150_000_000)
            scheduleRefresh(.habits, delayNanoseconds: 200_000_000)
            scheduleRefresh(.weeklyReport, delayNanoseconds: 250_000_000)
        }

        // Blocks made on the iPhone planner land here through sync.
        if previous.scheduleBlocks != signature.scheduleBlocks {
            scheduleRefresh(.scheduleBlocks, delayNanoseconds: 200_000_000)
        }

        lastAtomRefreshSignature = signature
    }

    private func assignIfChanged<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<CommandCenterDashboardViewModel, T>,
        to newValue: T
    ) {
        guard self[keyPath: keyPath] != newValue else { return }
        self[keyPath: keyPath] = newValue
    }

    private func assignCompletedTasksIfChanged(_ groupedTasks: [(date: Date, tasks: [TaskViewModel])]) {
        guard completedTasksByDay.count == groupedTasks.count else {
            completedTasksByDay = groupedTasks
            return
        }

        for (lhs, rhs) in zip(completedTasksByDay, groupedTasks) {
            if lhs.date != rhs.date || lhs.tasks != rhs.tasks {
                completedTasksByDay = groupedTasks
                return
            }
        }
    }

    /// Explicit refresh-wave input, never a time-based cache: a committed
    /// mutation always fetches a fresh snapshot, then shares it with its lists.
    private func loadTaskAtoms(_ snapshot: [Atom]?) async throws -> [Atom] {
        if let snapshot { return snapshot }
        return try await AtomRepository.shared.fetchAll(type: .task)
    }

    // MARK: - Task Loading (Today view — sectioned)

    @ObservationIgnored private var todayRefreshGeneration = 0
    @ObservationIgnored private var upcomingRefreshGeneration = 0
    @ObservationIgnored private var completedRefreshGeneration = 0

    func refreshTasks(from taskSnapshot: [Atom]? = nil) async {
        todayRefreshGeneration += 1
        let generation = todayRefreshGeneration
        let requestedDate = selectedDate
        var activeTasks: [TaskViewModel] = []
        var loadedAtoms: [Atom]?

        do {
            let atoms = try await loadTaskAtoms(taskSnapshot)
            loadedAtoms = atoms
            let calendar = Calendar.current
            let today = Date()
            let selectedDay = calendar.startOfDay(for: requestedDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
            let isToday = calendar.isDateInToday(requestedDate)

            // 1) Plain (non-recurring) incomplete tasks. Recurring templates AND any stale
            //    materialized instances are excluded here — recurrence is projected below.
            let plain = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                if vm.isCompleted { return nil }
                if vm.isRecurring { return nil }
                return vm
            }

            // 2) Recurring series → virtual occurrences for the selected-day frame.
            //    Today shows the single live occurrence per series (collapse-and-jump); a
            //    navigated day shows that day's occurrence(s).
            var occurrences: [TaskViewModel] = []
            for atom in atoms {
                guard let snapshot = RecurringSeriesEngine.makeSnapshot(from: atom, calendar: calendar),
                      let templateVM = TaskViewModel.from(atom: atom) else { continue }

                if isToday {
                    if let live = RecurringSeriesEngine.liveOccurrence(for: snapshot, asOf: today, calendar: calendar) {
                        occurrences.append(templateVM.makingOccurrence(live))
                    }
                } else {
                    let projected = RecurringSeriesEngine.occurrences(
                        for: snapshot,
                        in: DateInterval(start: selectedDay, end: dayEnd),
                        asOf: today,
                        calendar: calendar
                    )
                    for occ in projected where occ.status != .completed && occ.status != .missed {
                        occurrences.append(templateVM.makingOccurrence(occ))
                    }
                }
            }

            activeTasks = plain + occurrences
        } catch {
            print("❌ Dashboard: Failed to load today tasks for date: \(error)")
        }

        // Resolve schedule-block links for display against the shown day —
        // block title/color for the badge, occurrence range for "live now".
        activeTasks = await ScheduleBlockEngine.resolveLinks(in: activeTasks, on: requestedDate)
        guard generation == todayRefreshGeneration, requestedDate == selectedDate else { return }

        let sections = CommandCenterTodayTaskSectioning.sectionTasks(
            activeTasks,
            selectedDate: selectedDate,
            today: Date(),
            calendar: Calendar.current
        )

        assignIfChanged(\.overdueTasks, to: sections.overdue)
        assignIfChanged(\.scheduledTasks, to: sections.scheduled)
        assignIfChanged(\.unscheduledTasks, to: sections.unscheduled)

        // Load completed tasks independently (todayTasks excludes completed)
        await loadCompletedTasks(from: loadedAtoms)
    }

    // MARK: - Upcoming Tasks

    // MARK: - Idea → writing session (the week board's drop)

    /// Toast for a completed drop. Rendered by the dashboard.
    var dropToastMessage: String?

    /// Ideas with a drop already in flight. `resolveDrop` reads then writes
    /// across a suspension point, so two fast drops on the same idea could both
    /// see "no open session" and both create one. @MainActor only rules out
    /// true parallelism, not interleaving at awaits — this closes it.
    private var ideaDropsInFlight: Set<String> = []

    /// Book (or move) a writing session from a shelf idea dropped on the board.
    /// Owns the write, the undo registration AND the refresh, because
    /// `.atomsDidChange` has no observer anywhere in the Command Center — a drop
    /// that only posted it would leave the board stale until the view mode changed.
    func bookIdeaSession(target: UpcomingDropActions.Target) async {
        let ideaUUID: String
        let day: Date
        let start: Date?
        switch target {
        case .timed(let uuid, let at):
            ideaUUID = uuid
            start = at
            day = Calendar.current.startOfDay(for: at)
        case .allDay(let uuid, let on):
            ideaUUID = uuid
            start = nil
            day = on
        }

        guard !ideaDropsInFlight.contains(ideaUUID) else { return }
        ideaDropsInFlight.insert(ideaUUID)
        defer { ideaDropsInFlight.remove(ideaUUID) }

        // Re-fetch rather than trusting the drag payload: the shelf snapshot can
        // outlive the atom, and a session built against a deleted idea leaves a
        // mention pill that resolves to nothing.
        guard let idea = try? await AtomRepository.shared.fetch(uuid: ideaUUID), idea.type == .idea else {
            return
        }

        let resolution = (try? await IdeaTaskLinkService.resolveDrop(for: ideaUUID)) ?? .create
        var moved = false
        var siblings = 0

        switch resolution {
        case .move(let taskUUID, let siblingCount):
            guard let before = try? await IdeaTaskLinkService.move(
                taskUUID: taskUUID,
                to: day,
                at: start
            ) else { return }
            moved = true
            siblings = siblingCount
            registerIdeaSessionUndo(
                description: "Move Writing Session",
                undo: { try? await IdeaTaskLinkService.restorePins(taskUUID: taskUUID, to: before) },
                redo: { _ = try? await IdeaTaskLinkService.move(taskUUID: taskUUID, to: day, at: start) }
            )

        case .create:
            guard let task = try? await IdeaTaskLinkService.createScheduledTask(
                for: idea,
                on: day,
                at: start
            ) else { return }
            let taskUUID = task.uuid
            // Delete/restore, never delete/re-create: re-creating mints a NEW
            // uuid that the captured undo closure doesn't know about, so every
            // redo would strand another orphan task. The service verbs are the
            // symmetric pair and post `.atomsDidChange` for the surfaces outside
            // the Command Center (the Thinkspace sidebar, ⌘K).
            registerIdeaSessionUndo(
                description: "Book Writing Session",
                undo: { try? await IdeaTaskLinkService.removeScheduledTask(taskUUID: taskUUID) },
                redo: { try? await IdeaTaskLinkService.restoreScheduledTask(taskUUID: taskUUID) }
            )
        }

        await refreshAfterIdeaSessionDrop()
        withAnimation(ProMotionSprings.gentle) {
            dropToastMessage = UpcomingDropActions.toast(moved: moved, siblings: siblings, target: target)
        }
    }

    private func registerIdeaSessionUndo(
        description: String,
        undo: @escaping @MainActor () async -> Void,
        redo: @escaping @MainActor () async -> Void
    ) {
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: description,
            undo: { [weak self] in
                await undo()
                await self?.refreshAfterIdeaSessionDrop()
            },
            redo: { [weak self] in
                await redo()
                await self?.refreshAfterIdeaSessionDrop()
            }
        ))
    }

    /// Everything that must be told a session moved. The board reloads itself,
    /// the shelf listens only to `.contentCalendarNeedsReload`, and the drag
    /// session must end or day cells stay tinted.
    private func refreshAfterIdeaSessionDrop() async {
        await refreshTaskCollectionsAfterMutation()
        ShelfDragSession.shared.end()
        NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
    }

    func loadUpcomingTasks(from taskSnapshot: [Atom]? = nil) async {
        upcomingRefreshGeneration += 1
        let generation = upcomingRefreshGeneration
        let visibleDates = upcomingVisibleDates
        let interval = upcomingVisibleInterval
        do {
            let atoms = try await loadTaskAtoms(taskSnapshot)
            let calendar = Calendar.current
            let today = Date()

            // Recurring series → virtual occurrences across the whole visible window, every
            // status. Completed renders done, missed renders dim — Upcoming doubles as history.
            var occurrenceVMs: [TaskViewModel] = []
            for atom in atoms {
                guard let snapshot = RecurringSeriesEngine.makeSnapshot(from: atom, calendar: calendar),
                      let templateVM = TaskViewModel.from(atom: atom) else { continue }
                for occ in RecurringSeriesEngine.occurrences(for: snapshot, in: interval, asOf: today, calendar: calendar) {
                    occurrenceVMs.append(templateVM.makingOccurrence(occ))
                }
            }

            // Plain (non-recurring) tasks, INCLUDING completed so finished work stays visible
            // on its scheduled day instead of vanishing.
            let plainVMs = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                if vm.isRecurring { return nil }
                return vm
            }

            var dayGroups: [UpcomingDayViewModel] = []
            for dayStart in visibleDates {
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

                let dayOccurrences = occurrenceVMs.filter { vm in
                    guard let occDay = vm.occurrenceDay else { return false }
                    return occDay >= dayStart && occDay < dayEnd
                }

                let dayPlain = plainVMs.filter { vm in
                    guard let display = vm.calendarDisplayDate else { return false }
                    return display >= dayStart && display < dayEnd
                }

                let dayTasks = (dayOccurrences + dayPlain).sorted {
                    let lhs = $0.calendarDisplayDate ?? .distantFuture
                    let rhs = $1.calendarDisplayDate ?? .distantFuture
                    if lhs != rhs { return lhs < rhs }
                    if $0.priority.sortOrder != $1.priority.sortOrder {
                        return $0.priority.sortOrder < $1.priority.sortOrder
                    }
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }

                dayGroups.append(UpcomingDayViewModel(date: dayStart, tasks: dayTasks))
            }

            guard generation == upcomingRefreshGeneration, interval == upcomingVisibleInterval else { return }
            assignIfChanged(\.overdueTasks, to: [])
            assignIfChanged(\.upcomingDayGroups, to: dayGroups)

            // The week's blocks, day by day (recurring templates project) —
            // without them the board shows a plan with its scaffolding missing.
            let blocksByDay = await ScheduleBlockEngine.blocks(on: visibleDates)
            guard generation == upcomingRefreshGeneration, interval == upcomingVisibleInterval else { return }
            assignIfChanged(\.upcomingScheduleBlocksByDay, to: blocksByDay)

            await loadUpcomingCalendarEvents()
        } catch {
            print("❌ Dashboard: Failed to load upcoming tasks: \(error)")
        }
    }

    func loadUpcomingCalendarEvents() async {
        let calendar = Calendar.current
        let interval = upcomingVisibleInterval

        if calendarService.hasCalendarAccess {
            await calendarService.fetchExternalEvents(for: interval)
        }

        let events = calendarService.externalEvents
            .filter { $0.startDate < interval.end && $0.endDate > interval.start }

        var grouped: [String: [CalendarEvent]] = [:]
        for event in events {
            let eventStart = calendar.startOfDay(for: max(event.startDate, interval.start))
            let inclusiveEnd = min(event.endDate.addingTimeInterval(-1), interval.end.addingTimeInterval(-1))
            let eventEnd = calendar.startOfDay(for: max(eventStart, inclusiveEnd))
            var cursor = eventStart

            while cursor <= eventEnd && cursor < interval.end {
                let key = cursor.formatted(.iso8601.year().month().day())
                grouped[key, default: []].append(event)
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
            }
        }

        for key in grouped.keys {
            grouped[key]?.sort { $0.startDate < $1.startDate }
        }
        assignIfChanged(\.upcomingCalendarEvents, to: grouped)
    }

    func moveTask(uuid: String, toDate: Date) async {
        await rescheduleTask(uuid: uuid, toDate: toDate)
    }

    // MARK: - Task Reordering

    /// The bands a hand can arrange. Today's *Scheduled* band is deliberately
    /// absent: the clock owns its order (`scheduledSort`), so a manual index
    /// there would be overwritten by the next load — a promise the UI must not
    /// make. See `TaskBandOrdering.clock`.
    enum ManualOrderBand: Equatable {
        case overdue
        case unscheduled
        case anytime
        case someday
        case project
    }

    /// Commit a hand-arranged order, named by ROW ID rather than by index.
    ///
    /// Ids, because a band on screen is not always the whole array behind it:
    /// the project page draws one heading's rows and hides completed ones, so an
    /// index handed over from the view would address a different task than the
    /// one the hand moved. Row ids can't drift.
    ///
    /// The arrangement is stamped into `manualSortOrder` and syncs like any other
    /// edit (iOS `TodayEngine.setManualOrder` is the twin).
    func applyManualOrder(band: ManualOrderBand, orderedRowIDs: [String]) {
        guard orderedRowIDs.count > 1 else { return }
        switch band {
        case .overdue:
            overdueTasks = TaskReorderGeometry.permuted(overdueTasks, to: orderedRowIDs)
            persistSortOrder(for: overdueTasks)
        case .unscheduled:
            unscheduledTasks = TaskReorderGeometry.permuted(unscheduledTasks, to: orderedRowIDs)
            persistSortOrder(for: unscheduledTasks)
        case .anytime:
            anytimeTasks = TaskReorderGeometry.permuted(anytimeTasks, to: orderedRowIDs)
            persistSortOrder(for: anytimeTasks)
        case .someday:
            somedayTasks = TaskReorderGeometry.permuted(somedayTasks, to: orderedRowIDs)
            persistSortOrder(for: somedayTasks)
        case .project:
            projectTasks = TaskReorderGeometry.permuted(projectTasks, to: orderedRowIDs)
            persistSortOrder(for: projectTasks)
        }
    }

    /// The drag's keyboard twin (⌥⌘↑/↓): nudge a row one slot inside its own
    /// band. Returns false when there is nowhere to go — a clock-ordered band,
    /// or already at the end — so the caller can stay silent instead of
    /// pretending something moved.
    @discardableResult
    func nudgeTask(rowID: String, by delta: Int) -> Bool {
        guard let (band, rows) = manualBand(containing: rowID) else { return false }
        guard let from = rows.firstIndex(where: { $0.id == rowID }) else { return false }
        let to = from + delta
        guard rows.indices.contains(to) else { return false }
        applyManualOrder(
            band: band,
            orderedRowIDs: TaskReorderGeometry.reordered(rows, from: from, to: to).map(\.id)
        )
        return true
    }

    /// Which hand-arranged band a row belongs to on the page being looked at.
    /// Mode-scoped on purpose: the same task can satisfy both Today's "To do"
    /// and Anytime (a day-planned task with no clock time is in both arrays),
    /// and the answer must be the band the user can actually see.
    private func manualBand(containing rowID: String) -> (ManualOrderBand, [TaskViewModel])? {
        switch viewMode {
        case .today:
            if overdueTasks.contains(where: { $0.id == rowID }) { return (.overdue, overdueTasks) }
            if unscheduledTasks.contains(where: { $0.id == rowID }) { return (.unscheduled, unscheduledTasks) }
            return nil
        case .anytime:
            return (.anytime, anytimeTasks)
        case .someday:
            return (.someday, somedayTasks)
        case .project:
            // A project's rows are drawn grouped by heading, so the keyboard's
            // band is the row's own heading — never the whole project.
            guard let task = projectTasks.first(where: { $0.id == rowID }) else { return nil }
            return (.project, projectTasks.filter { $0.headingUUID == task.headingUUID })
        case .upcoming, .logbook, .habits, .reports, .queue, .area:
            return nil
        }
    }

    /// Stamps positions into `manualSortOrder`, skipping rows already carrying
    /// the index they need. Skipping matters: the shorter the write window, the
    /// smaller the chance a refresh lands mid-persist and reads a half-arranged
    /// ladder back onto the screen.
    private func persistSortOrder(for tasks: [TaskViewModel]) {
        let pending = tasks.enumerated().filter { $0.element.manualSortOrder != $0.offset }
        guard !pending.isEmpty else { return }
        Task {
            for (index, task) in pending {
                do {
                    _ = try await AtomRepository.shared.update(uuid: task.uuid) { atom in
                        guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.persistSortOrder(\(task.uuid.prefix(8)))") else { return }
                        metadata.manualSortOrder = index
                        guard let merged = atom.mergingTaskMetadata(metadata, context: "Dashboard.persistSortOrder(\(task.uuid.prefix(8)))") else { return }
                        atom = merged
                    }
                } catch {
                    PersistenceHealth.note(.writeFailure, context: "Dashboard.persistSortOrder(\(task.uuid.prefix(8)))", detail: error.localizedDescription)
                }
            }
        }
    }

    /// Split a row id of the form "templateUUID#yyyy-MM-dd" (a virtual recurring
    /// occurrence) into its components. Returns nil for plain task uuids.
    static func occurrenceComponents(ofRowID id: String) -> (templateUUID: String, dayKey: String)? {
        guard let hash = id.firstIndex(of: "#") else { return nil }
        let uuid = String(id[..<hash])
        let dayKey = String(id[id.index(after: hash)...])
        guard !uuid.isEmpty, !dayKey.isEmpty else { return nil }
        return (uuid, dayKey)
    }

    /// Reschedule entry point that understands recurring occurrences. Occurrence rows are
    /// rescheduled via a per-day override; only plain tasks (and deliberate template moves)
    /// rewrite atom dates.
    func rescheduleTask(_ task: TaskViewModel, toDate: Date?) async {
        if let occurrenceDay = task.occurrenceDay {
            guard let toDate else {
                // Clearing the date of a single occurrence has no occurrence-level meaning;
                // falling through would clear the TEMPLATE anchor and orphan the series.
                PersistenceHealth.note(.writeFailure, context: "Dashboard.rescheduleTask", detail: "ignored clear-date on recurring occurrence \(task.id)")
                return
            }
            await rescheduleOccurrence(templateUUID: task.uuid, dayKey: RecurringSeriesEngine.dayKey(for: occurrenceDay), toDate: toDate)
            return
        }
        await rescheduleTask(uuid: task.uuid, toDate: toDate)
    }

    /// Row-id variant for batch surfaces that only carry ids ("uuid" or "uuid#day").
    func rescheduleTaskRow(id: String, toDate: Date?) async {
        if let occurrence = Self.occurrenceComponents(ofRowID: id) {
            guard let toDate else {
                PersistenceHealth.note(.writeFailure, context: "Dashboard.rescheduleTaskRow", detail: "ignored clear-date on recurring occurrence \(id)")
                return
            }
            await rescheduleOccurrence(templateUUID: occurrence.templateUUID, dayKey: occurrence.dayKey, toDate: toDate)
            return
        }
        await rescheduleTask(uuid: id, toDate: toDate)
    }

    private func rescheduleOccurrence(templateUUID: String, dayKey: String, toDate: Date) async {
        do {
            try await RecurringSeriesEngine.shared.rescheduleOccurrence(
                templateUUID: templateUUID,
                dayKey: dayKey,
                to: toDate
            )
            await refreshTaskCollectionsAfterMutation()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.rescheduleOccurrence(\(templateUUID.prefix(8))#\(dayKey))", detail: error.localizedDescription)
        }
    }

    func rescheduleTask(uuid: String, toDate: Date?) async {
        do {
            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.rescheduleTask(\(uuid.prefix(8)))") else { return }

                let isSeriesTemplate = metadata.recurrence != nil && metadata.recurrenceParentUUID == nil
                if toDate == nil, isSeriesTemplate {
                    // Clearing the anchor date of a recurring template makes the entire
                    // series — and its completion history — unprojectable. Refuse.
                    PersistenceHealth.note(.writeFailure, context: "Dashboard.rescheduleTask(\(uuid.prefix(8)))", detail: "blocked clearing the anchor date of a recurring series")
                    return
                }

                CommandCenterTaskScheduling.reschedule(&metadata, toDate: toDate)
                if let toDate, isSeriesTemplate {
                    metadata.seriesAnchorDay = RecurringSeriesEngine.dayKey(for: toDate)
                }
                guard let merged = atom.mergingTaskMetadata(metadata, context: "Dashboard.rescheduleTask(\(uuid.prefix(8)))") else { return }
                atom = merged
            }
            await refreshTaskCollectionsAfterMutation()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.rescheduleTask(\(uuid.prefix(8)))", detail: error.localizedDescription)
        }
    }

    func rescheduleTasks(uuids: [String], toDate: Date?) async {
        for uuid in uuids {
            await rescheduleTaskRow(id: uuid, toDate: toDate)
        }
        await refreshTaskCollectionsAfterMutation()
    }

    func shiftUpcomingWeek(by offset: Int) {
        shiftUpcomingRange(by: offset)
    }

    func shiftSelectedDay(by offset: Int) {
        let calendar = Calendar.current
        selectedDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: offset, to: selectedDate) ?? selectedDate
        )
    }

    func resetSelectedDateToToday() {
        selectedDate = Calendar.current.startOfDay(for: Date())
    }

    func resetUpcomingToToday() {
        upcomingCalendarScope = .week
        upcomingAnchorDate = Calendar.current.startOfDay(for: Date())
        upcomingWeekOffset = 0
        Task { await loadUpcomingTasks() }
    }

    func setUpcomingCalendarScope(_ scope: UpcomingCalendarScope) {
        let normalizedScope: UpcomingCalendarScope = .week
        guard upcomingCalendarScope != normalizedScope || scope != normalizedScope else { return }
        upcomingCalendarScope = normalizedScope
        syncUpcomingWeekOffset()
        Task { await loadUpcomingTasks() }
    }

    func setUpcomingAnchorDate(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        guard !Calendar.current.isDate(day, inSameDayAs: upcomingAnchorDate) else { return }
        upcomingCalendarScope = .week
        upcomingAnchorDate = day
        selectedDate = day
        syncUpcomingWeekOffset()
        Task { await loadUpcomingTasks() }
    }

    func shiftUpcomingRange(by offset: Int) {
        let calendar = Calendar.current

        // Content lens pages by month; the schedule pages by week.
        if upcomingLens == .content {
            upcomingAnchorDate = calendar.startOfDay(
                for: calendar.date(byAdding: .month, value: offset, to: upcomingAnchorDate) ?? upcomingAnchorDate
            )
            return
        }

        upcomingCalendarScope = .week
        upcomingAnchorDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: offset * 7, to: upcomingAnchorDate) ?? upcomingAnchorDate
        )
        selectedDate = upcomingAnchorDate
        syncUpcomingWeekOffset()
        Task { await loadUpcomingTasks() }
    }

    func setUpcomingLens(_ lens: UpcomingLens) {
        // `.content` is retired (the calendar lives in the Pipeline); the
        // case survives for persisted rawValues and old jump targets.
        if lens == .content {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openPipeline,
                object: nil,
                userInfo: ["view": PipelineView.calendar.rawValue]
            )
            return
        }
        guard upcomingLens != lens else { return }
        upcomingLens = lens
        // Re-anchor to today when switching faces — arriving on a stale
        // month (or week) reads as a broken calendar.
        upcomingAnchorDate = Calendar.current.startOfDay(for: Date())
        if lens == .schedule {
            syncUpcomingWeekOffset()
            Task { await loadUpcomingTasks() }
        }
    }

    private func syncUpcomingWeekOffset() {
        let calendar = Calendar.current
        let today = CommandCenterCalendarLayout.mondayStartingWeek(containing: Date(), calendar: calendar)
        let selected = CommandCenterCalendarLayout.mondayStartingWeek(containing: upcomingAnchorDate, calendar: calendar)
        let daysDiff = calendar.dateComponents([.day], from: today, to: selected).day ?? 0
        upcomingWeekOffset = daysDiff / 7
    }

    private func handleCurrentDayChange(now: Date = Date()) {
        let calendar = Calendar.current
        let newToday = calendar.startOfDay(for: now)
        guard !calendar.isDate(newToday, inSameDayAs: lastObservedTodayStart) else { return }

        let previousToday = lastObservedTodayStart
        lastObservedTodayStart = newToday
        let adjustedSelectedDate = CommandCenterDateSelection.dateForCurrentDayChange(
            selectedDate: selectedDate,
            previousToday: previousToday,
            newToday: newToday,
            calendar: calendar
        )

        if !calendar.isDate(adjustedSelectedDate, inSameDayAs: selectedDate) {
            selectedDate = adjustedSelectedDate
        }

        if viewMode == .upcoming {
            syncUpcomingWeekOffset()
        }

        Task {
            await refreshDateSensitiveCollectionsAfterDayChange()
        }
    }

    private func refreshDateSensitiveCollectionsAfterDayChange() async {
        switch viewMode {
        case .today:
            await refreshTasks()
        case .upcoming:
            await loadUpcomingTasks()
            await loadCompletedTasks()
        case .logbook:
            await loadCompletedTasks()
        case .anytime:
            await loadAnytimeTasks()
            await loadCompletedTasks()
        case .someday:
            await loadSomedayTasks()
            await loadCompletedTasks()
        case .habits, .reports, .queue:
            await loadCompletedTasks()
        case .project:
            if let uuid = selectedProjectUUID {
                await loadProjectTasks(projectUUID: uuid)
            }
            await loadCompletedTasks()
        case .area:
            await loadCompletedTasks()
        }

        refreshCalendarEvents()
        await refreshScheduleBlocks()
        await loadHabits()
        await loadTodayTimeData()
        await loadTodaySessions()
        await loadWeeklyReport()
    }

    // MARK: - Completed Tasks

    func loadCompletedTasks(from taskSnapshot: [Atom]? = nil) async {
        completedRefreshGeneration += 1
        let generation = completedRefreshGeneration
        do {
            let atoms = try await loadTaskAtoms(taskSnapshot)
            guard generation == completedRefreshGeneration else { return }
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: Date())

            // Plain completed tasks
            var allCompleted = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                guard vm.isCompleted else { return nil }
                guard vm.completedAt != nil else { return nil }
                return vm
            }

            // Recurring series → project the completion log into the Logbook. Each logged
            // occurrence becomes a completed row on the day it was checked off.
            for atom in atoms {
                guard let meta = atom.metadataValue(as: TaskMetadata.self),
                      meta.recurrence != nil,
                      meta.recurrenceParentUUID == nil,
                      let entries = meta.completedOccurrences, !entries.isEmpty,
                      let templateVM = TaskViewModel.from(atom: atom) else { continue }

                for entry in entries {
                    guard let occurrenceDay = RecurringSeriesEngine.day(fromKey: entry.day, calendar: calendar) else { continue }
                    let completedAt = PlannerumFormatters.iso8601.date(from: entry.completedAt) ?? occurrenceDay
                    let override = meta.occurrenceOverrides?[entry.day]
                    let occurrence = RecurringSeriesEngine.VirtualOccurrence(
                        templateUUID: atom.uuid,
                        title: override?.title ?? templateVM.title,
                        day: occurrenceDay,
                        start: nil,
                        end: nil,
                        status: .completed
                    )
                    allCompleted.append(templateVM.makingOccurrence(occurrence, completedAt: completedAt))
                }
            }

            // Today's completed (for badge count)
            let nextCompletedToday = allCompleted
                .filter { ($0.completedAt ?? .distantPast) >= todayStart }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

            // Group by completion day
            var grouped: [Date: [TaskViewModel]] = [:]
            for task in allCompleted {
                guard let completedAt = task.completedAt else { continue }
                let dayKey = calendar.startOfDay(for: completedAt)
                grouped[dayKey, default: []].append(task)
            }

            // Sort each day's tasks by completedAt descending, then sort days descending
            let groupedByDay = grouped
                .map { (date: $0.key, tasks: $0.value.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) }
                .sorted { $0.date > $1.date }

            assignIfChanged(\.completedTodayTasks, to: nextCompletedToday)
            assignCompletedTasksIfChanged(groupedByDay)
        } catch {
            print("❌ Dashboard: Failed to load completed tasks: \(error)")
        }
    }

    // MARK: - Anytime Tasks

    func loadAnytimeTasks(from taskSnapshot: [Atom]? = nil) async {
        do {
            let atoms = try await loadTaskAtoms(taskSnapshot)
            let anytimeCandidates = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                guard !vm.isCompleted else { return nil }
                // Anytime owns unscheduled work: explicit anytime, no scheduling bucket, or a day-only plan without a calendar time.
                let state = vm.schedulingState
                if state == "someday" { return nil }
                if vm.isRecurring && vm.recurrenceParentUUID == nil { return nil }
                if state == "anytime" || !vm.hasCalendarTime {
                    return vm
                }
                return nil
            }
            .sorted { ($0.manualSortOrder ?? Int.max) < ($1.manualSortOrder ?? Int.max) }

            var seenRecurringParents = Set<String>()
            let nextAnytimeTasks = anytimeCandidates.filter { task in
                guard let parent = task.recurrenceParentUUID else { return true }
                return seenRecurringParents.insert(parent).inserted
            }
            assignIfChanged(\.anytimeTasks, to: nextAnytimeTasks)
        } catch {
            print("❌ Dashboard: Failed to load anytime tasks: \(error)")
        }
    }

    // MARK: - Someday Tasks

    func loadSomedayTasks(from taskSnapshot: [Atom]? = nil) async {
        do {
            let atoms = try await loadTaskAtoms(taskSnapshot)
            let nextSomedayTasks = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                guard !vm.isCompleted else { return nil }
                guard vm.schedulingState == "someday" else { return nil }
                return vm
            }
            .sorted { ($0.manualSortOrder ?? Int.max) < ($1.manualSortOrder ?? Int.max) }
            assignIfChanged(\.somedayTasks, to: nextSomedayTasks)
        } catch {
            print("❌ Dashboard: Failed to load someday tasks: \(error)")
        }
    }

    // MARK: - Project Tasks (drill-in view)

    func loadProjectTasks(projectUUID: String) async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)

            // Load project metadata for headings
            if let projectAtom = try await AtomRepository.shared.fetch(uuid: projectUUID) {
                let meta = projectAtom.metadataValue(as: ProjectMetadata.self)
                if let headingsJSON = meta?.headings,
                   let data = headingsJSON.data(using: .utf8) {
                    projectHeadings = (try? JSONDecoder().decode([ProjectHeading].self, from: data)) ?? []
                } else {
                    projectHeadings = []
                }
            }

            // Filter tasks linked to this project
            let nextProjectTasks = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                // Check if task is linked to this project via AtomLinks
                let links = atom.linksList
                let isLinked = links.contains { $0.type == "project" && $0.uuid == projectUUID }
                guard isLinked else { return nil }
                return vm
            }
            .sorted { ($0.manualSortOrder ?? Int.max) < ($1.manualSortOrder ?? Int.max) }
            assignIfChanged(\.projectTasks, to: nextProjectTasks)
        } catch {
            print("❌ Dashboard: Failed to load project tasks: \(error)")
        }
    }

    // MARK: - Areas & Projects Loading

    func loadAreas() async {
        do {
            let areasWithSortOrder = try await AtomRepository.shared.fetchAll(type: .area)
                .filter { !$0.isDeleted }
                .map { area in
                    (area: area, sortOrder: area.metadataValue(as: AreaMetadata.self)?.sortOrder ?? Int.max)
                }
            let nextAreas = areasWithSortOrder.sorted { $0.sortOrder < $1.sortOrder }.map(\.area)
            assignIfChanged(\.areas, to: nextAreas)
        } catch {
            print("❌ Dashboard: Failed to load areas: \(error)")
        }
    }

    func loadProjects() async {
        assignIfChanged(\.projects, to: [])
    }

    // MARK: - Scheduling Operations

    /// Set a task's ONE date. There is no separate when/deadline anymore —
    /// a task has a single day, and all three storage pins
    /// (dueDate/focusDate/whenDate) move together so every reader on every
    /// device lands on the same day. Delegates to the canonical reschedule
    /// contract, which also carries any time block onto the new day.
    func setWhenDate(taskUUID: String, date: Date?) async {
        do {
            guard let atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            guard var meta = taskMetadataForWrite(atom, context: "Dashboard.setWhenDate(\(taskUUID.prefix(8)))") else { return }
            if date == nil, meta.recurrence != nil, meta.recurrenceParentUUID == nil {
                // Clearing the date of a recurring template can orphan the series.
                PersistenceHealth.note(.writeFailure, context: "Dashboard.setWhenDate(\(taskUUID.prefix(8)))", detail: "blocked clearing the date of a recurring series")
                return
            }
            CommandCenterTaskScheduling.reschedule(&meta, toDate: date)
            if let date, meta.recurrence != nil, meta.recurrenceParentUUID == nil {
                meta.seriesAnchorDay = RecurringSeriesEngine.dayKey(for: date)
            }
            guard let merged = atom.mergingTaskMetadata(meta, context: "Dashboard.setWhenDate(\(taskUUID.prefix(8)))") else { return }
            try await AtomRepository.shared.update(merged)
            await refreshTasks()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.setWhenDate(\(taskUUID.prefix(8)))", detail: error.localizedDescription)
        }
    }

    func setTimeOfDay(taskUUID: String, value: String?) async {
        do {
            guard let atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            guard var meta = taskMetadataForWrite(atom, context: "Dashboard.setTimeOfDay(\(taskUUID.prefix(8)))") else { return }
            meta.timeOfDay = value
            guard let merged = atom.mergingTaskMetadata(meta, context: "Dashboard.setTimeOfDay(\(taskUUID.prefix(8)))") else { return }
            try await AtomRepository.shared.update(merged)
            await refreshTasks()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.setTimeOfDay(\(taskUUID.prefix(8)))", detail: error.localizedDescription)
        }
    }

    func setSchedulingState(taskUUID: String, state: String?) async {
        do {
            guard let atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            guard var meta = taskMetadataForWrite(atom, context: "Dashboard.setSchedulingState(\(taskUUID.prefix(8)))") else { return }
            meta.schedulingState = state
            if state != nil {
                if meta.recurrence != nil, meta.recurrenceParentUUID == nil {
                    // Anytime/someday clears the when date — for a recurring template that
                    // can orphan the series and its history.
                    PersistenceHealth.note(.writeFailure, context: "Dashboard.setSchedulingState(\(taskUUID.prefix(8)))", detail: "blocked moving a recurring series to \(state ?? "")")
                    return
                }
                // Moving to anytime/someday clears the date — all three pins
                // (one-date model; a surviving dueDate would keep the task
                // haunting its old day on every surface).
                meta.whenDate = nil
                meta.focusDate = nil
                meta.dueDate = nil
            }
            guard let merged = atom.mergingTaskMetadata(meta, context: "Dashboard.setSchedulingState(\(taskUUID.prefix(8)))") else { return }
            try await AtomRepository.shared.update(merged)
            await refreshTasks()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.setSchedulingState(\(taskUUID.prefix(8)))", detail: error.localizedDescription)
        }
    }

    func moveTaskToProject(taskUUID: String, projectUUID: String) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            // Remove existing project links
            atom = atom.removingLinks(ofType: .project)
            // Add new project link
            atom = atom.addingLink(.project(projectUUID))
            // Clear heading (headings are project-specific)
            guard var meta = taskMetadataForWrite(atom, context: "Dashboard.moveTaskToProject(\(taskUUID.prefix(8)))") else { return }
            meta.headingUUID = nil
            guard let merged = atom.mergingTaskMetadata(meta, context: "Dashboard.moveTaskToProject(\(taskUUID.prefix(8)))") else { return }
            try await AtomRepository.shared.update(merged)
            await refreshTasks()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.moveTaskToProject(\(taskUUID.prefix(8)))", detail: error.localizedDescription)
        }
    }

    func moveTaskToHeading(taskUUID: String, headingUUID: String?) async {
        do {
            guard let atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            guard var meta = taskMetadataForWrite(atom, context: "Dashboard.moveTaskToHeading(\(taskUUID.prefix(8)))") else { return }
            meta.headingUUID = headingUUID
            guard let merged = atom.mergingTaskMetadata(meta, context: "Dashboard.moveTaskToHeading(\(taskUUID.prefix(8)))") else { return }
            try await AtomRepository.shared.update(merged)
            if let projectUUID = selectedProjectUUID {
                await loadProjectTasks(projectUUID: projectUUID)
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.moveTaskToHeading(\(taskUUID.prefix(8)))", detail: error.localizedDescription)
        }
    }

    func createArea(title: String, icon: String? = nil, color: String? = nil) async {
        do {
            let meta = AreaMetadata(icon: icon ?? "square.stack.fill", color: color, sortOrder: areas.count, isCollapsed: false)
            let metaJSON = try? JSONEncoder().encode(meta)
            let metaString = metaJSON.flatMap { String(data: $0, encoding: .utf8) }
            let atom = Atom.new(type: .area, title: title, metadata: metaString)
            _ = try await AtomRepository.shared.create(atom)
            await loadAreas()
        } catch {
            print("❌ Dashboard: Failed to create area: \(error)")
        }
    }

    func createProject(title: String, color: String = "#8B5CF6", isTemporary: Bool = false) async {
        do {
            if isTemporary {
                var meta = ProjectMetadata(color: color, status: "active", priority: "Medium")
                meta.isTemporary = true
                let metaJSON = try JSONEncoder().encode(meta)
                let metaString = String(data: metaJSON, encoding: .utf8)
                let atom = Atom.new(type: .project, title: title, metadata: metaString)
                _ = try await AtomRepository.shared.create(atom)
            } else {
                _ = try await AtomRepository.shared.createProject(title: title, color: color)
            }
            await loadProjects()
        } catch {
            print("❌ Dashboard: Failed to create project: \(error)")
        }
    }

    func createHeading(projectUUID: String, title: String) async {
        do {
            guard var projectAtom = try await AtomRepository.shared.fetch(uuid: projectUUID) else { return }
            var meta = projectAtom.metadataValue(as: ProjectMetadata.self) ?? ProjectMetadata()

            // Parse existing headings
            var headings: [ProjectHeading] = []
            if let headingsJSON = meta.headings, let data = headingsJSON.data(using: .utf8) {
                headings = (try? JSONDecoder().decode([ProjectHeading].self, from: data)) ?? []
            }

            // Add new heading
            let newHeading = ProjectHeading(title: title, sortOrder: headings.count)
            headings.append(newHeading)

            // Save back
            let encoded = try JSONEncoder().encode(headings)
            meta.headings = String(data: encoded, encoding: .utf8)
            projectAtom = projectAtom.withMetadata(meta)
            try await AtomRepository.shared.update(projectAtom)

            projectHeadings = headings
        } catch {
            print("❌ Dashboard: Failed to create heading: \(error)")
        }
    }

    func deleteHeading(projectUUID: String, headingUUID: String) async {
        do {
            guard var projectAtom = try await AtomRepository.shared.fetch(uuid: projectUUID) else { return }
            var meta = projectAtom.metadataValue(as: ProjectMetadata.self) ?? ProjectMetadata()

            // Parse and remove heading
            var headings: [ProjectHeading] = []
            if let headingsJSON = meta.headings, let data = headingsJSON.data(using: .utf8) {
                headings = (try? JSONDecoder().decode([ProjectHeading].self, from: data)) ?? []
            }
            let previousHeadings = headings
            headings.removeAll { $0.id == headingUUID }

            // Save back
            let encoded = try JSONEncoder().encode(headings)
            meta.headings = String(data: encoded, encoding: .utf8)
            projectAtom = projectAtom.withMetadata(meta)
            try await AtomRepository.shared.update(projectAtom)

            projectHeadings = headings

            // Clear headingUUID from tasks that referenced this heading
            let tasks = try await AtomRepository.shared.fetchAll(type: .task)
            var unstampedTaskUUIDs: [String] = []
            for task in tasks {
                guard var updatedMeta = taskMetadataForWrite(task, context: "Dashboard.deleteHeading(\(task.uuid.prefix(8)))"),
                      updatedMeta.headingUUID == headingUUID else { continue }
                updatedMeta.headingUUID = nil
                guard let merged = task.mergingTaskMetadata(updatedMeta, context: "Dashboard.deleteHeading(\(task.uuid.prefix(8)))") else { continue }
                try await AtomRepository.shared.update(merged)
                unstampedTaskUUIDs.append(task.uuid)
            }

            await loadProjectTasks(projectUUID: projectUUID)

            registerHeadingDeletionUndo(
                projectUUID: projectUUID,
                headingUUID: headingUUID,
                previousHeadings: previousHeadings,
                newHeadings: headings,
                unstampedTaskUUIDs: unstampedTaskUUIDs
            )
        } catch {
            print("❌ Dashboard: Failed to delete heading: \(error)")
        }
    }

    /// ⌘Z contract for heading deletion: write the previous headings JSON back
    /// onto the project and re-stamp `headingUUID` on the tasks that were
    /// unfiled by the delete.
    private func registerHeadingDeletionUndo(
        projectUUID: String,
        headingUUID: String,
        previousHeadings: [ProjectHeading],
        newHeadings: [ProjectHeading],
        unstampedTaskUUIDs: [String]
    ) {
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: "Delete Heading",
            undo: { [weak self] in
                await self?.applyHeadingsState(
                    projectUUID: projectUUID,
                    headings: previousHeadings,
                    unstampedTaskUUIDs: unstampedTaskUUIDs,
                    taskHeadingUUID: headingUUID
                )
            },
            redo: { [weak self] in
                await self?.applyHeadingsState(
                    projectUUID: projectUUID,
                    headings: newHeadings,
                    unstampedTaskUUIDs: unstampedTaskUUIDs,
                    taskHeadingUUID: nil
                )
            }
        ))
    }

    private func applyHeadingsState(
        projectUUID: String,
        headings: [ProjectHeading],
        unstampedTaskUUIDs: [String],
        taskHeadingUUID: String?
    ) async {
        do {
            guard var projectAtom = try await AtomRepository.shared.fetch(uuid: projectUUID) else { return }
            var meta = projectAtom.metadataValue(as: ProjectMetadata.self) ?? ProjectMetadata()
            let encoded = try JSONEncoder().encode(headings)
            meta.headings = String(data: encoded, encoding: .utf8)
            projectAtom = projectAtom.withMetadata(meta)
            try await AtomRepository.shared.update(projectAtom)
            projectHeadings = headings

            for uuid in unstampedTaskUUIDs {
                guard let task = try await AtomRepository.shared.fetch(uuid: uuid),
                      var taskMeta = taskMetadataForWrite(task, context: "Dashboard.undoDeleteHeading(\(uuid.prefix(8)))") else { continue }
                taskMeta.headingUUID = taskHeadingUUID
                guard let merged = task.mergingTaskMetadata(taskMeta, context: "Dashboard.undoDeleteHeading(\(uuid.prefix(8)))") else { continue }
                try await AtomRepository.shared.update(merged)
            }
            await loadProjectTasks(projectUUID: projectUUID)
        } catch {
            print("❌ Dashboard: heading undo/redo write failed: \(error)")
        }
    }

    // MARK: - Calendar Events

    private func refreshCalendarEvents() {
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let nextEvents = calendarService.externalEvents
            .filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
            .sorted { $0.startDate < $1.startDate }
        assignIfChanged(\.todayEvents, to: nextEvents)
    }

    // MARK: - Schedule blocks

    func refreshScheduleBlocks() async {
        let blocks = await ScheduleBlockEngine.blocks(on: selectedDate)
        assignIfChanged(\.todayScheduleBlocks, to: blocks)
    }

    /// The Mac block palette — iOS `ScheduleEngine.blockPalette`, hex for hex
    /// (tokens move in pairs).
    static let blockPalette: [String] = [
        "#8B5CF6", // violet (default)
        "#818CF8", // indigo
        "#38BDF8", // sky
        "#34D399", // emerald
        "#FBBF24", // amber
        "#F97316", // orange
        "#EF4444", // red
        "#6B7280", // slate
    ]

    /// Draw a block onto the day (the timeline's drag-create). Snapping to
    /// the 15-minute grain is the caller's job; this persists and refreshes.
    @discardableResult
    func createScheduleBlock(title: String, start: Date, end: Date, colorHex: String? = nil) async -> String? {
        var meta = ScheduleBlockMetadata()
        meta.startTime = ISO8601.string(from: start)
        meta.endTime = ISO8601.string(from: end)
        meta.color = colorHex ?? Self.blockPalette[0]
        var atom = Atom.new(type: .scheduleBlock, title: title)
        atom.metadata = Atom.mergedJSONObjectString(existing: nil, overlay: meta, context: "Dashboard.createScheduleBlock")
        guard let created = try? await AtomRepository.shared.create(atom) else { return nil }
        await refreshScheduleBlocks()
        return created.uuid
    }

    /// Move or resize a one-off block. Recurring templates are series-
    /// anchored (whole-series time semantics) — the timeline disables their
    /// drag rather than silently rewriting every occurrence.
    func updateScheduleBlockTimes(uuid: String, start: Date, end: Date) async {
        _ = try? await AtomRepository.shared.update(uuid: uuid) { atom in
            var meta = atom.metadataValue(as: ScheduleBlockMetadata.self) ?? ScheduleBlockMetadata()
            meta.startTime = ISO8601.string(from: start)
            meta.endTime = ISO8601.string(from: end)
            atom.metadata = Atom.mergedJSONObjectString(existing: atom.metadata, overlay: meta, context: "Dashboard.updateScheduleBlockTimes")
        }
        await refreshScheduleBlocks()
    }

    func renameScheduleBlock(uuid: String, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? await AtomRepository.shared.update(uuid: uuid) { atom in
            atom.title = trimmed
        }
        await refreshScheduleBlocks()
    }

    /// The one door from a block into the task world: the new task inherits
    /// the slot (and any repeat becomes a task series); the block retires.
    func convertScheduleBlockToTask(_ block: ScheduleBlockEntry) {
        Task {
            _ = try? await ScheduleBlockEngine.convertToTask(scheduleBlockUUID: block.id)
            await refreshScheduleBlocks()
            await refreshTasks()
        }
    }

    /// Deletes the block atom (a repeating block's whole series).
    func deleteScheduleBlock(_ block: ScheduleBlockEntry) {
        Task {
            try? await AtomRepository.shared.delete(uuid: block.id)
            await refreshScheduleBlocks()
            CosmoUndoManager.shared.register(InlineUndoAction(
                actionDescription: "Delete Schedule Block",
                undo: { [weak self] in
                    try? await AtomRepository.shared.restore(uuid: block.id)
                    await self?.refreshScheduleBlocks()
                },
                redo: { [weak self] in
                    try? await AtomRepository.shared.delete(uuid: block.id)
                    await self?.refreshScheduleBlocks()
                }
            ))
        }
    }

    // MARK: - Task ↔ block links (iOS contract)

    /// Nest a task inside a schedule block, or unlink with nil. The block
    /// owns the time — this never time-boxes the task. Key-level merge;
    /// `mergingTaskMetadata` honors the nil so unlinking removes the key.
    func setScheduleBlock(taskUUID: String, blockUUID: String?) async {
        do {
            guard let atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            guard var meta = taskMetadataForWrite(atom, context: "Dashboard.setScheduleBlock(\(taskUUID.prefix(8)))") else { return }
            meta.scheduleBlockUUID = blockUUID
            guard let merged = atom.mergingTaskMetadata(meta, context: "Dashboard.setScheduleBlock(\(taskUUID.prefix(8)))") else { return }
            try await AtomRepository.shared.update(merged)
            await refreshTasks()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.setScheduleBlock(\(taskUUID.prefix(8)))", detail: error.localizedDescription)
        }
    }

    /// The viewed day's tasks nested in `blockID` — open first (overdue,
    /// then scheduled/unscheduled in their section order), completed after.
    /// Drives the timeline card nesting and the block context menu.
    func tasksLinked(toBlock blockID: String) -> [TaskViewModel] {
        let open = (overdueTasks + scheduledTasks + unscheduledTasks)
            .filter { $0.scheduleBlockUUID == blockID }
        let calendar = Calendar.current
        let completed = completedTasksByDay
            .first { calendar.isDate($0.date, inSameDayAs: selectedDate) }?
            .tasks.filter { $0.scheduleBlockUUID == blockID } ?? []
        return open + completed
    }

    /// The viewed day's open tasks not yet nested in any block — the
    /// candidates a block's "Add Task" menu offers.
    var blockLinkCandidates: [TaskViewModel] {
        (overdueTasks + scheduledTasks + unscheduledTasks)
            .filter { $0.scheduleBlockUUID == nil }
    }

    // MARK: - Habits

    func loadHabits() async {
        let progressStates = await habitEngine.loadProgressStates()
        let nextHabits = progressStates.map { state in
            HabitState(
                id: state.definition.id,
                title: state.definition.title,
                iconName: state.definition.icon,
                accentColor: state.definition.accent,
                todayProgress: state.todayProgress,
                isTodayComplete: state.isTodayComplete,
                last7Days: state.last7Days,
                consistencyCount: state.consistencyCount,
                allowManualComplete: state.definition.allowManualCompletion,
                targetCount: state.targetCount,
                todayCount: state.todayCount,
                trackedMinutesToday: state.trackedMinutesToday,
                isTimeBased: state.definition.isTimeBased,
                targetMinutes: state.definition.dailyTargetMinutes,
                sourceBreakdown: state.sourceBreakdown,
                isBuiltIn: state.isBuiltIn,
                isEditable: state.isEditable,
                linkedIntentSummary: state.linkedIntentSummary
            )
        }
        assignIfChanged(\.habits, to: nextHabits)
    }

    var availableHabitDefinitions: [HabitDefinition] {
        habitEngine.activeDefinitions
    }

    var availableIntentDefinitions: [IntentDefinition] {
        intentEngine.activeDefinitions
    }

    func resolvedIntentPresentation(intentUUID: String?, legacyIntent: TaskIntent) -> ResolvedIntentPresentation {
        intentEngine.resolvedPresentation(intentUUID: intentUUID, legacyIntentRaw: legacyIntent.rawValue)
    }

    func resolvedIntentPresentation(for task: TaskViewModel) -> ResolvedIntentPresentation {
        resolvedIntentPresentation(intentUUID: task.intentUUID, legacyIntent: task.intent)
    }

    func resolvedIntentPresentation(intentUUID: String?, legacyIntentRaw: String?) -> ResolvedIntentPresentation {
        intentEngine.resolvedPresentation(intentUUID: intentUUID, legacyIntentRaw: legacyIntentRaw)
    }

    func behaviorIntent(for task: TaskViewModel) -> TaskIntent {
        intentEngine.behaviorTemplate(intentUUID: task.intentUUID, legacyIntentRaw: task.intent.rawValue)?.taskIntent ?? .general
    }

    func intentDefinition(for id: String?) -> IntentDefinition? {
        intentEngine.definition(for: id)
    }

    private func intentSummary(intentUUID: String?, legacyIntentRaw: String?, minutes: Int = 0) -> IntentSummary {
        let presentation = resolvedIntentPresentation(intentUUID: intentUUID, legacyIntentRaw: legacyIntentRaw)
        return IntentSummary(
            id: presentation.id,
            title: presentation.title,
            icon: presentation.icon,
            accentColorHex: presentation.accentColorHex,
            minutes: minutes
        )
    }

    /// Both-axes attribution: bucket tracked time by **habit** when the work belongs to one,
    /// falling back to the intent, then "Unassigned". Keeps the time strip + reports grouped the
    /// way work is actually organized (the habits panel) rather than landing in "Unassigned".
    private func attributionSummary(habitUUID: String?, intentUUID: String?, legacyIntentRaw: String?, minutes: Int = 0) -> IntentSummary {
        if let habitUUID, let habit = habitDefinition(for: habitUUID) {
            return IntentSummary(
                id: "habit:\(habit.id)",
                title: habit.title,
                icon: habit.icon,
                accentColorHex: habit.accentColor,
                minutes: minutes
            )
        }
        return intentSummary(intentUUID: intentUUID, legacyIntentRaw: legacyIntentRaw, minutes: minutes)
    }

    func habitDefinition(for id: String?) -> HabitDefinition? {
        habitEngine.definition(for: id)
    }

    func resolvedHabit(for task: TaskViewModel) -> HabitDefinition? {
        habitEngine.resolvedHabit(for: task)?.definition
    }

    func createHabit(
        title: String,
        icon: String,
        accentColor: String,
        dailyTargetCount: Int,
        goalType: String? = nil,
        dailyTargetMinutes: Int? = nil,
        keywordTriggers: [String],
        mappedIntents: [TaskIntent],
        defaultIntentUUID: String?,
        allowManualCompletion: Bool
    ) async {
        await habitEngine.createHabit(
            title: title,
            icon: icon,
            accentColor: accentColor,
            dailyTargetCount: dailyTargetCount,
            goalType: goalType,
            dailyTargetMinutes: dailyTargetMinutes,
            keywordTriggers: keywordTriggers,
            mappedIntents: mappedIntents,
            defaultIntentUUID: defaultIntentUUID,
            allowManualCompletion: allowManualCompletion
        )
        await loadHabits()
    }

    func createIntent(title: String, icon: String, accentColor: String, behaviorTemplate: IntentBehaviorTemplate?) async {
        await intentEngine.createIntent(title: title, icon: icon, accentColor: accentColor, behaviorTemplate: behaviorTemplate)
        await refreshTasks()
        await loadTodayTimeData()
        await loadTodaySessions()
    }

    func updateIntent(_ definition: IntentDefinition) async {
        await intentEngine.updateIntent(definition)
        await refreshTasks()
        await loadTodayTimeData()
        await loadTodaySessions()
    }

    func archiveIntent(id: String) async {
        await intentEngine.archiveIntent(id: id)
        await refreshTasks()
        await loadTodayTimeData()
        await loadTodaySessions()
    }

    func moveIntent(id: String, direction: Int) async {
        await intentEngine.moveIntent(id: id, direction: direction)
        await refreshTasks()
    }

    func updateHabit(_ definition: HabitDefinition) async {
        await habitEngine.updateHabit(definition)
        await loadHabits()
    }

    func archiveHabit(uuid: String) async {
        await habitEngine.archiveHabit(uuid: uuid)
        await loadHabits()
    }

    func moveHabit(uuid: String, direction: Int) async {
        await habitEngine.moveHabit(uuid: uuid, direction: direction)
        await loadHabits()
    }

    func recordManualHabitCompletion(habitUUID: String) async {
        await habitEngine.recordManualCompletion(habitUUID: habitUUID)
        await loadHabits()
    }

    var builtInHabitToggles: [(definition: HabitDefinition, isEnabled: Bool)] {
        habitEngine.allBuiltInDefinitions.map { def in
            (def, habitEngine.isBuiltInHabitEnabled(def.id))
        }
    }

    func setBuiltInHabitEnabled(id: String, enabled: Bool) async {
        await habitEngine.setBuiltInHabitEnabled(id: id, enabled: enabled)
        await loadHabits()
    }

    func applyHabit(_ habitUUID: String?, to taskUUID: String) async {
        await habitEngine.assignHabit(taskUUID: taskUUID, habitUUID: habitUUID, source: .manual)
        await refreshTasks()
        await loadHabits()
    }

    // MARK: - Task Actions

    /// The instant a completion made from the Today surface is stamped with:
    /// wall-clock now on today's page, else midday of the viewed day — so the
    /// task's `completedAt` and any habit credit it triggers land on the day
    /// you're looking at, not on wall-clock today (back-filling a day you
    /// forgot to tick).
    private var completionDate: Date {
        let calendar = Calendar.current
        guard !calendar.isDateInToday(selectedDate) else { return Date() }
        let start = calendar.startOfDay(for: selectedDate)
        return calendar.date(byAdding: .hour, value: 12, to: start) ?? start
    }

    func toggleTaskCompletion(_ task: TaskViewModel) async {
        if task.isOccurrence {
            if task.occurrenceStatus == .completed {
                _ = await uncompleteTask(task)
            } else {
                _ = await completeTask(task)
            }
        } else if task.isCompleted {
            _ = await uncompleteTask(uuid: task.uuid)
        } else {
            _ = await completeTask(uuid: task.uuid)
        }
    }

    /// Completion entry point that understands recurring occurrences. Prefer this over the
    /// uuid-only variants on any surface that can show recurring tasks (Today, Upcoming).
    @discardableResult
    func completeTask(_ task: TaskViewModel) async -> Bool {
        guard let occurrenceDay = task.occurrenceDay else {
            return await completeTask(uuid: task.uuid)
        }
        do {
            try await RecurringSeriesEngine.shared.complete(
                templateUUID: task.uuid,
                occurrenceDay: occurrenceDay,
                on: completionDate,
                trackedMinutes: nil
            )
            await habitEngine.recordTaskCompletion(taskUUID: task.uuid, on: completionDate)
            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
            return true
        } catch {
            print("❌ Dashboard: Failed to complete recurring occurrence: \(error)")
            return false
        }
    }

    @discardableResult
    func uncompleteTask(_ task: TaskViewModel) async -> Bool {
        guard let occurrenceDay = task.occurrenceDay else {
            return await uncompleteTask(uuid: task.uuid)
        }
        do {
            try await RecurringSeriesEngine.shared.uncomplete(
                templateUUID: task.uuid,
                occurrenceDay: occurrenceDay
            )
            await habitEngine.reverseTaskCompletion(taskUUID: task.uuid, on: completionDate)
            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
            return true
        } catch {
            print("❌ Dashboard: Failed to uncomplete recurring occurrence: \(error)")
            return false
        }
    }

    func completeTask(uuid: String) async -> Bool {
        // Legacy materialized instances (recurrenceParentUUID set) just complete as plain
        // atoms now — occurrences are projected by RecurringSeriesEngine, so spawning a
        // "next instance" atom would re-introduce the mixed-model duplicate mess.
        let persisted = await DashboardTaskPersistence.completeTask(taskId: uuid, completedAt: completionDate)
        guard persisted else { return false }

        // Habit credit only after the completion actually persisted.
        await habitEngine.recordTaskCompletion(taskUUID: uuid, on: completionDate)
        await refreshTaskCollectionsAfterMutation()
        await loadHabits()
        return true
    }

    func uncompleteTask(uuid: String) async -> Bool {
        do {
            var applied = false
            let result = try await AtomRepository.shared.update(uuid: uuid) { atom in
                guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.uncompleteTask(\(uuid.prefix(8)))") else { return }
                metadata.isCompleted = false
                metadata.completedAt = nil
                guard let merged = atom.mergingTaskMetadata(metadata, context: "Dashboard.uncompleteTask(\(uuid.prefix(8)))") else { return }
                atom = merged
                applied = true
            }
            guard applied, result != nil else { return false }
            await habitEngine.reverseTaskCompletion(taskUUID: uuid, on: completionDate)
            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
            return true
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.uncompleteTask(\(uuid.prefix(8)))", detail: error.localizedDescription)
            return false
        }
    }

    func addTask() async {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newTaskTitle = ""
        // Parse and create with metadata (seed implicit dates from the viewed day)
        let parsed = TaskInputParser.parse(title, referenceDate: selectedDate)
        let created = await smartAddTask(parsed)
        if !created {
            // Creation failed — restore the input so the capture isn't silently lost.
            newTaskTitle = title
        }
    }

    /// Returns false when task creation failed. On failure the capture text is restored to
    /// `newTaskTitle` so the user's input is never silently discarded; PersistenceHealth
    /// surfaces the failure.
    @discardableResult
    func smartAddTask(_ parsed: ParsedTaskInput) async -> Bool {
        let title = parsed.title.isEmpty ? "Untitled Task" : parsed.title
        guard let createdAtom = await DashboardTaskPersistence.quickAddTask(title: title) else {
            if newTaskTitle.isEmpty, !parsed.title.isEmpty {
                newTaskTitle = parsed.title
            }
            PersistenceHealth.note(.writeFailure, context: "Dashboard.smartAddTask", detail: "task creation failed for \"\(title)\"")
            return false
        }

        // Enrich the created task by its returned UUID — never by title re-find, which can
        // grab an unrelated task with the same title.
        let atom = createdAtom
        do {
            _ = try await AtomRepository.shared.update(uuid: atom.uuid) { a in
                guard var metadata = taskMetadataForWrite(a, context: "Dashboard.smartAddTask(\(atom.uuid.prefix(8)))") else { return }

                if let priority = parsed.priority {
                    metadata.priority = priority.rawValue
                }
                if let dueDate = parsed.dueDate ?? pendingTaskDate {
                    let dateStr = PlannerumFormatters.iso8601.string(from: dueDate)
                    metadata.dueDate = dateStr
                    metadata.focusDate = dateStr  // Keep focusDate in sync so task appears on the correct day
                } else {
                    // No explicit date typed. Where the task lands is decided by WHICH list
                    // you're capturing from — you only get "anytime"/"someday" by actually
                    // being in those lists. On the Today page a plain task pins to the day
                    // you're LOOKING at (today, tomorrow, or any paged day via selectedDate),
                    // never the real "today" and never the anytime bucket.
                    switch viewMode {
                    case .today, .upcoming:
                        let day = Calendar.current.startOfDay(for: selectedDate)
                        let dateStr = PlannerumFormatters.iso8601.string(from: day)
                        metadata.dueDate = dateStr
                        metadata.focusDate = dateStr
                    case .anytime:
                        metadata.schedulingState = "anytime"
                    case .someday:
                        metadata.schedulingState = "someday"
                    default:
                        break
                    }
                }
                if let time = parsed.scheduledTime {
                    let date = parsed.dueDate ?? pendingTaskDate ?? Date()
                    let scheduledStart = merge(date: date, time: time)
                    let scheduledEnd = Calendar.current.date(
                        byAdding: .minute,
                        value: metadata.durationMinutes ?? metadata.estimatedFocusMinutes ?? 30,
                        to: scheduledStart
                    ) ?? scheduledStart.addingTimeInterval(1_800)
                    applyCalendarTimeRange(start: scheduledStart, end: scheduledEnd, to: &metadata)
                }
                if let intent = parsed.intent {
                    metadata.intent = intent.rawValue
                }
                if let intentUUID = parsed.intentUUID {
                    metadata.intentUUID = intentUUID
                }
                if let habitUUID = parsed.habitUUID {
                    metadata.habitUUID = habitUUID
                    metadata.habitAssignmentSource = parsed.habitAssignmentSource?.rawValue
                } else if let derived = habitEngine.resolveHabit(title: title, intent: parsed.intent) {
                    metadata.habitUUID = derived.definition.id
                    metadata.habitAssignmentSource = derived.source.rawValue
                    if metadata.intentUUID == nil {
                        metadata.intentUUID = derived.definition.defaultIntentUUID
                    }
                }

                // Things 3 scheduling fields
                if let timeOfDay = parsed.timeOfDay {
                    metadata.timeOfDay = timeOfDay
                }
                if let schedulingState = parsed.schedulingState {
                    metadata.schedulingState = schedulingState
                    // Someday/Anytime tasks don't get a date
                    metadata.dueDate = nil
                    metadata.focusDate = nil
                    metadata.whenDate = nil
                }
                if let deadline = parsed.deadline {
                    // "deadline: friday" is legacy grammar for the task's one
                    // date — all three pins move together, never due alone.
                    let dateStr = PlannerumFormatters.iso8601.string(from: Calendar.current.startOfDay(for: deadline))
                    metadata.dueDate = dateStr
                    metadata.focusDate = dateStr
                    metadata.whenDate = dateStr
                    metadata.schedulingState = nil
                }

                // Set whenDate from dueDate if we have one (new semantic)
                if metadata.schedulingState == nil, let focusDate = metadata.focusDate {
                    metadata.whenDate = focusDate
                }

                // Heading assignment from context
                if let headingUUID = parsed.contextHeadingUUID {
                    metadata.headingUUID = headingUUID
                }

                // Title mentions from @ picker
                if !parsed.mentions.isEmpty,
                   let encoded = try? JSONEncoder().encode(parsed.mentions),
                   let json = String(data: encoded, encoding: .utf8) {
                    metadata.titleMentions = json
                }

                guard let merged = a.mergingTaskMetadata(metadata, context: "Dashboard.smartAddTask(\(atom.uuid.prefix(8)))") else { return }
                a = merged

                // Project assignment — context (from project view) or #tag (from parser)
                if let contextProject = parsed.contextProjectUUID {
                    a = a.addingLink(.project(contextProject))
                } else if let projectName = parsed.projectName {
                    let matchingProject = projects.first { ($0.title ?? "").lowercased() == projectName.lowercased() }
                    if let project = matchingProject {
                        a = a.addingLink(.project(project.uuid))
                    }
                } else if viewMode == .project, let selectedProject = selectedProjectUUID {
                    // Auto-link when in project view with no explicit project
                    a = a.addingLink(.project(selectedProject))
                }
            }

            if let recurrenceRule = parsed.recurrenceRule {
                await setTaskRecurrence(uuid: atom.uuid, rule: recurrenceRule)
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.smartAddTask(\(atom.uuid.prefix(8)))", detail: "task created but enrichment failed: \(error.localizedDescription)")
        }

        pendingTaskDate = nil

        // Reload appropriate view
        if viewMode == .project, let uuid = selectedProjectUUID {
            await loadProjectTasks(projectUUID: uuid)
        }
        await refreshTasks()
        if viewMode == .today {
            await loadAnytimeTasks()
        }
        await loadHabits()
        return true
    }

    func updateTask(
        uuid: String,
        title: String? = nil,
        priority: TaskPriority? = nil,
        dueDate: Date? = nil,
        scheduledTime: Date? = nil,
        intent: TaskIntent? = nil,
        intentUUID: String? = nil,
        body: String? = nil,
        timeGoalMinutes: Int?? = nil
    ) async {
        do {
            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.updateTask(\(uuid.prefix(8)))") else { return }
                let previousAssignmentSource = HabitAssignmentSource(rawValue: metadata.habitAssignmentSource ?? "")

                if let title = title { atom.title = title }
                if let body = body { atom.body = body }
                if let priority = priority { metadata.priority = priority.rawValue }
                if let goalUpdate = timeGoalMinutes {
                    // Outer nil = unchanged; inner nil (or 0) clears the goal
                    metadata.timeGoalMinutes = goalUpdate.flatMap { $0 > 0 ? $0 : nil }
                }
                if let dueDate = dueDate {
                    let dateString = PlannerumFormatters.iso8601.string(from: dueDate)
                    metadata.dueDate = dateString
                    metadata.focusDate = dateString
                    // Day pins move together — a stranded whenDate keeps the
                    // task on its old day everywhere that plans by whenDate first.
                    metadata.whenDate = dateString
                    if metadata.recurrence != nil, metadata.recurrenceParentUUID == nil {
                        metadata.seriesAnchorDay = RecurringSeriesEngine.dayKey(for: dueDate)
                    }
                }
                if let time = scheduledTime {
                    metadata.startTime = PlannerumFormatters.iso8601.string(from: time)
                }
                if let intent = intent {
                    metadata.intent = intent.rawValue
                }
                if let intentUUID {
                    metadata.intentUUID = intentUUID
                    metadata.intent = intentEngine.behaviorTemplate(intentUUID: intentUUID, legacyIntentRaw: metadata.intent)?.taskIntent.rawValue
                }

                if previousAssignmentSource != .manual {
                    let resolvedTitle = title ?? atom.title ?? ""
                    let resolvedIntent = intent ?? metadata.intent.flatMap(TaskIntent.init(rawValue:))
                    if let derived = habitEngine.resolveHabit(title: resolvedTitle, intent: resolvedIntent) {
                        metadata.habitUUID = derived.definition.id
                        metadata.habitAssignmentSource = derived.source.rawValue
                        if metadata.intentUUID == nil {
                            metadata.intentUUID = derived.definition.defaultIntentUUID
                        }
                    } else {
                        metadata.habitUUID = nil
                        metadata.habitAssignmentSource = nil
                    }
                }

                guard let merged = atom.mergingTaskMetadata(metadata, context: "Dashboard.updateTask(\(uuid.prefix(8)))") else { return }
                atom = merged
            }
            await refreshTasks()
            await loadHabits()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.updateTask(\(uuid.prefix(8)))", detail: error.localizedDescription)
        }
    }

    func updateRecurringTaskTitle(
        uuid: String,
        title: String,
        scope: RecurringTaskTitleEditScope,
        occurrenceDay: Date? = nil
    ) async {
        do {
            guard let current = try await AtomRepository.shared.fetch(uuid: uuid) else { return }
            let currentMetadata = current.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()

            // Virtual-occurrence series: occurrence rows carry the TEMPLATE uuid.
            // "This occurrence only" writes a per-day title override; "current and
            // future" renames the series (projection derives every occurrence's
            // title from the template + overrides).
            if currentMetadata.recurrence != nil, currentMetadata.recurrenceParentUUID == nil {
                if scope == .currentOnly, let occurrenceDay {
                    try await RecurringSeriesEngine.shared.overrideOccurrenceTitle(
                        templateUUID: uuid,
                        dayKey: RecurringSeriesEngine.dayKey(for: occurrenceDay),
                        title: title
                    )
                    await refreshTaskCollectionsAfterMutation()
                    await loadHabits()
                    return
                }
                await updateTask(uuid: uuid, title: title)
                return
            }

            guard scope == .currentAndFuture,
                  let parentUUID = currentMetadata.recurrenceParentUUID,
                  let parent = try await AtomRepository.shared.fetch(uuid: parentUUID) else {
                await updateTask(uuid: uuid, title: title)
                return
            }

            let calendar = Calendar.current
            let referenceDay = calendar.startOfDay(for: recurrenceOccurrenceDate(from: currentMetadata) ?? Date())
            let matchingTitles = Set([current.title, parent.title].compactMap { $0 })
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)

            for candidate in atoms where shouldUpdateRecurringTitleTarget(
                candidate,
                parentUUID: parentUUID,
                currentUUID: uuid,
                matchingTitles: matchingTitles,
                referenceDay: referenceDay,
                calendar: calendar
            ) {
                _ = try await AtomRepository.shared.update(uuid: candidate.uuid) { atom in
                    guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.updateRecurringTaskTitle(\(candidate.uuid.prefix(8)))") else { return }
                    applyRecurringTitle(title, to: &atom, metadata: &metadata)
                    guard let merged = atom.mergingTaskMetadata(metadata, context: "Dashboard.updateRecurringTaskTitle(\(candidate.uuid.prefix(8)))") else { return }
                    atom = merged
                }
            }

            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
        } catch {
            print("❌ Dashboard: Failed to update recurring task title: \(error)")
        }
    }

    private func shouldUpdateRecurringTitleTarget(
        _ atom: Atom,
        parentUUID: String,
        currentUUID: String,
        matchingTitles: Set<String>,
        referenceDay: Date,
        calendar: Calendar
    ) -> Bool {
        if atom.uuid == parentUUID || atom.uuid == currentUUID {
            return true
        }

        guard !atom.isDeleted,
              let metadata = atom.metadataValue(as: TaskMetadata.self),
              metadata.recurrenceParentUUID == parentUUID,
              metadata.isCompleted != true,
              let occurrenceDate = recurrenceOccurrenceDate(from: metadata),
              calendar.startOfDay(for: occurrenceDate) >= referenceDay else {
            return false
        }

        guard !matchingTitles.isEmpty else {
            return true
        }

        return atom.title.map { matchingTitles.contains($0) } ?? false
    }

    private func applyRecurringTitle(_ title: String, to atom: inout Atom, metadata: inout TaskMetadata) {
        let previousAssignmentSource = HabitAssignmentSource(rawValue: metadata.habitAssignmentSource ?? "")
        atom.title = title

        guard previousAssignmentSource != .manual else { return }

        let resolvedIntent = metadata.intent.flatMap(TaskIntent.init(rawValue:))
        if let derived = habitEngine.resolveHabit(title: title, intent: resolvedIntent) {
            metadata.habitUUID = derived.definition.id
            metadata.habitAssignmentSource = derived.source.rawValue
            if metadata.intentUUID == nil {
                metadata.intentUUID = derived.definition.defaultIntentUUID
            }
        } else {
            metadata.habitUUID = nil
            metadata.habitAssignmentSource = nil
        }
    }

    private func recurrenceOccurrenceDate(from metadata: TaskMetadata) -> Date? {
        let candidates = [
            metadata.focusDate,
            metadata.scheduledStart,
            metadata.startTime,
            metadata.whenDate,
            metadata.dueDate
        ]

        for candidate in candidates {
            if let candidate, let date = PlannerumFormatters.iso8601.date(from: candidate) {
                return date
            }
        }

        return nil
    }

    @discardableResult
    func createCalendarTimeBlock(
        title: String,
        start: Date,
        end: Date,
        body: String? = nil
    ) async -> TaskViewModel? {
        do {
            let normalized = normalizedTimeBlockRange(start: start, end: end)
            var metadata = TaskMetadata()
            applyCalendarTimeRange(start: normalized.start, end: normalized.end, to: &metadata)

            if calendarService.hasCalendarAccess {
                do {
                    metadata.calendarEventId = try await calendarService.createCosmoEvent(
                        title: title.isEmpty ? "New Event" : title,
                        start: normalized.start,
                        end: normalized.end
                    )
                } catch {
                    PersistenceHealth.note(.syncFailure, context: "Dashboard.createCalendarTimeBlock", detail: "EK event creation failed: \(error.localizedDescription)")
                }
            }

            let metadataString = encodeTaskMetadata(metadata)
            let atom = Atom.new(
                type: .task,
                title: title.isEmpty ? "New Event" : title,
                body: body?.isEmpty == true ? nil : body,
                metadata: metadataString
            )
            let created = try await AtomRepository.shared.create(atom)
            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
            return TaskViewModel.from(atom: created)
        } catch {
            print("❌ Dashboard: Failed to create calendar time block: \(error)")
            return nil
        }
    }

    @discardableResult
    func createAllDayTask(title: String, date: Date, body: String? = nil) async -> TaskViewModel? {
        do {
            let day = Calendar.current.startOfDay(for: date)
            var metadata = TaskMetadata()
            let dateString = PlannerumFormatters.iso8601.string(from: day)
            metadata.dueDate = dateString
            metadata.focusDate = dateString
            metadata.whenDate = dateString
            metadata.schedulingState = nil

            let atom = Atom.new(
                type: .task,
                title: title.isEmpty ? "New Event" : title,
                body: body?.isEmpty == true ? nil : body,
                metadata: encodeTaskMetadata(metadata)
            )
            let created = try await AtomRepository.shared.create(atom)
            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
            return TaskViewModel.from(atom: created)
        } catch {
            print("❌ Dashboard: Failed to create all-day task: \(error)")
            return nil
        }
    }

    func updateCalendarTimeBlock(
        uuid: String,
        title: String? = nil,
        body: String? = nil,
        start: Date,
        end: Date
    ) async {
        do {
            let normalized = normalizedTimeBlockRange(start: start, end: end)
            var calendarEventId: String?

            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.updateCalendarTimeBlock(\(uuid.prefix(8)))") else { return }
                applyCalendarTimeRange(start: normalized.start, end: normalized.end, to: &metadata)

                if let title { atom.title = title.isEmpty ? "New Event" : title }
                if let body { atom.body = body.isEmpty ? nil : body }
                calendarEventId = metadata.calendarEventId
                guard let merged = atom.mergingTaskMetadata(metadata, context: "Dashboard.updateCalendarTimeBlock(\(uuid.prefix(8)))") else { return }
                atom = merged
            }

            if calendarService.hasCalendarAccess {
                let resolvedTitle: String
                if let title, !title.isEmpty {
                    resolvedTitle = title
                } else {
                    resolvedTitle = try await AtomRepository.shared.fetch(uuid: uuid)?.title ?? "New Event"
                }

                do {
                    if let calendarEventId {
                        try await calendarService.updateCosmoEvent(
                            eventId: calendarEventId,
                            title: resolvedTitle,
                            start: normalized.start,
                            end: normalized.end
                        )
                    } else {
                        let newEventId = try await calendarService.createCosmoEvent(
                            title: resolvedTitle,
                            start: normalized.start,
                            end: normalized.end
                        )
                        _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                            guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.updateCalendarTimeBlock(\(uuid.prefix(8)))") else { return }
                            metadata.calendarEventId = newEventId
                            guard let merged = atom.mergingTaskMetadata(metadata, context: "Dashboard.updateCalendarTimeBlock(\(uuid.prefix(8)))") else { return }
                            atom = merged
                        }
                    }
                } catch {
                    PersistenceHealth.note(.syncFailure, context: "Dashboard.updateCalendarTimeBlock(\(uuid.prefix(8)))", detail: "EK event sync failed: \(error.localizedDescription)")
                }
            }

            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.updateCalendarTimeBlock(\(uuid.prefix(8)))", detail: error.localizedDescription)
        }
    }

    func updateAllDayTask(uuid: String, title: String? = nil, body: String? = nil, date: Date) async {
        do {
            let day = Calendar.current.startOfDay(for: date)
            var staleCalendarEventId: String?
            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.updateAllDayTask(\(uuid.prefix(8)))") else { return }
                let dateString = PlannerumFormatters.iso8601.string(from: day)
                metadata.dueDate = dateString
                metadata.focusDate = dateString
                metadata.whenDate = dateString
                metadata.startTime = nil
                metadata.endTime = nil
                metadata.durationMinutes = nil
                metadata.scheduledStart = nil
                metadata.scheduledEnd = nil
                metadata.schedulingState = nil
                // Becoming all-day removes the time block — take the linked EK event with it
                // instead of leaving a stale event on the old time slot.
                staleCalendarEventId = metadata.calendarEventId
                metadata.calendarEventId = nil
                if metadata.recurrence != nil, metadata.recurrenceParentUUID == nil {
                    metadata.seriesAnchorDay = RecurringSeriesEngine.dayKey(for: day)
                }

                if let title { atom.title = title.isEmpty ? "New Event" : title }
                if let body { atom.body = body.isEmpty ? nil : body }
                guard let merged = atom.mergingTaskMetadata(metadata, context: "Dashboard.updateAllDayTask(\(uuid.prefix(8)))") else { return }
                atom = merged
            }

            if calendarService.hasCalendarAccess, let staleCalendarEventId {
                do {
                    try await calendarService.deleteCosmoEvent(eventId: staleCalendarEventId)
                } catch {
                    PersistenceHealth.note(.syncFailure, context: "Dashboard.updateAllDayTask(\(uuid.prefix(8)))", detail: "stale EK event removal failed: \(error.localizedDescription)")
                }
            }

            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.updateAllDayTask(\(uuid.prefix(8)))", detail: error.localizedDescription)
        }
    }

    func clearCalendarTimeBlock(uuid: String) async {
        do {
            var calendarEventId: String?
            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.clearCalendarTimeBlock(\(uuid.prefix(8)))") else { return }
                calendarEventId = metadata.calendarEventId
                metadata.startTime = nil
                metadata.endTime = nil
                metadata.durationMinutes = nil
                metadata.scheduledStart = nil
                metadata.scheduledEnd = nil
                metadata.calendarEventId = nil
                guard let merged = atom.mergingTaskMetadata(metadata, context: "Dashboard.clearCalendarTimeBlock(\(uuid.prefix(8)))") else { return }
                atom = merged
            }

            if calendarService.hasCalendarAccess, let calendarEventId {
                do {
                    try await calendarService.deleteCosmoEvent(eventId: calendarEventId)
                } catch {
                    PersistenceHealth.note(.syncFailure, context: "Dashboard.clearCalendarTimeBlock(\(uuid.prefix(8)))", detail: "EK event removal failed: \(error.localizedDescription)")
                }
            }

            await refreshTaskCollectionsAfterMutation()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.clearCalendarTimeBlock(\(uuid.prefix(8)))", detail: error.localizedDescription)
        }
    }

    private func normalizedTimeBlockRange(start: Date, end: Date) -> (start: Date, end: Date) {
        let snappedStart = CommandCenterCalendarLayout.snappedDate(for: start, calendar: Calendar.current)
        let snappedEnd = CommandCenterCalendarLayout.snappedDate(for: end, calendar: Calendar.current)
        let minEnd = Calendar.current.date(byAdding: .minute, value: 15, to: snappedStart) ?? snappedStart.addingTimeInterval(900)
        return (snappedStart, max(snappedEnd, minEnd))
    }

    private func merge(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second ?? 0
        return calendar.date(from: merged) ?? date
    }

    private func applyCalendarTimeRange(start: Date, end: Date, to metadata: inout TaskMetadata) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: start)
        let dateString = PlannerumFormatters.iso8601.string(from: day)
        metadata.dueDate = dateString
        metadata.focusDate = dateString
        metadata.whenDate = dateString
        metadata.startTime = PlannerumFormatters.iso8601.string(from: start)
        metadata.endTime = PlannerumFormatters.iso8601.string(from: end)
        metadata.scheduledStart = PlannerumFormatters.iso8601.string(from: start)
        metadata.scheduledEnd = PlannerumFormatters.iso8601.string(from: end)
        metadata.durationMinutes = max(15, Int(end.timeIntervalSince(start) / 60))
        metadata.schedulingState = nil
    }

    private func encodeTaskMetadata(_ metadata: TaskMetadata) -> String? {
        guard let data = try? JSONEncoder().encode(metadata) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func recurrenceRule(for task: TaskViewModel) async -> RecurrenceRule? {
        do {
            guard let atom = try await AtomRepository.shared.fetch(uuid: task.uuid) else {
                return nil
            }

            if let metadata = atom.metadataValue(as: TaskMetadata.self) {
                if let recurrenceJSON = metadata.recurrence {
                    return RecurrenceRule.fromJSON(recurrenceJSON)
                }

                if let parentUUID = metadata.recurrenceParentUUID,
                   let parent = try await AtomRepository.shared.fetch(uuid: parentUUID),
                   let parentMetadata = parent.metadataValue(as: TaskMetadata.self),
                   let recurrenceJSON = parentMetadata.recurrence {
                    return RecurrenceRule.fromJSON(recurrenceJSON)
                }
            }
        } catch {
            print("❌ Dashboard: Failed to load recurrence rule: \(error)")
        }

        return nil
    }

    func setTaskRecurrence(uuid: String, rule: RecurrenceRule?) async {
        do {
            guard let atom = try await AtomRepository.shared.fetch(uuid: uuid) else { return }
            let recurrenceJSON = rule?.toJSON()
            let metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()

            if let parentUUID = metadata.recurrenceParentUUID {
                if let recurrenceJSON {
                    _ = try await AtomRepository.shared.update(uuid: parentUUID) { parent in
                        guard var parentMetadata = taskMetadataForWrite(parent, context: "Dashboard.setTaskRecurrence(\(parentUUID.prefix(8)))") else { return }
                        parentMetadata.recurrence = recurrenceJSON
                        guard let merged = parent.mergingTaskMetadata(parentMetadata, context: "Dashboard.setTaskRecurrence(\(parentUUID.prefix(8)))") else { return }
                        parent = merged
                    }
                } else {
                    try await AtomRepository.shared.delete(uuid: parentUUID)
                    _ = try await AtomRepository.shared.update(uuid: uuid) { current in
                        guard var currentMetadata = taskMetadataForWrite(current, context: "Dashboard.setTaskRecurrence(\(uuid.prefix(8)))") else { return }
                        currentMetadata.recurrenceParentUUID = nil
                        guard let merged = current.mergingTaskMetadata(currentMetadata, context: "Dashboard.setTaskRecurrence(\(uuid.prefix(8)))") else { return }
                        current = merged
                    }
                }
            } else if metadata.recurrence != nil {
                _ = try await AtomRepository.shared.update(uuid: uuid) { current in
                    guard var currentMetadata = taskMetadataForWrite(current, context: "Dashboard.setTaskRecurrence(\(uuid.prefix(8)))") else { return }
                    currentMetadata.recurrence = recurrenceJSON
                    guard let merged = current.mergingTaskMetadata(currentMetadata, context: "Dashboard.setTaskRecurrence(\(uuid.prefix(8)))") else { return }
                    current = merged
                }
            } else if let recurrenceJSON {
                let template = try await createRecurringTemplate(from: atom, recurrenceJSON: recurrenceJSON)
                _ = try await AtomRepository.shared.update(uuid: uuid) { current in
                    guard var currentMetadata = taskMetadataForWrite(current, context: "Dashboard.setTaskRecurrence(\(uuid.prefix(8)))") else { return }
                    currentMetadata.recurrence = nil
                    currentMetadata.recurrenceParentUUID = template.uuid
                    guard let merged = current.mergingTaskMetadata(currentMetadata, context: "Dashboard.setTaskRecurrence(\(uuid.prefix(8)))") else { return }
                    current = merged
                }
            }

            await refreshTaskCollectionsAfterMutation()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.setTaskRecurrence(\(uuid.prefix(8)))", detail: error.localizedDescription)
        }
    }

    private func createRecurringTemplate(from atom: Atom, recurrenceJSON: String) async throws -> Atom {
        guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.createRecurringTemplate(\(atom.uuid.prefix(8)))") else {
            throw AtomRepositoryError.notFound(atom.uuid)
        }
        metadata.recurrence = recurrenceJSON
        metadata.recurrenceParentUUID = nil
        metadata.isCompleted = false
        metadata.completedAt = nil

        if metadata.dueDate == nil {
            let today = PlannerumFormatters.iso8601.string(from: Date())
            metadata.dueDate = today
            metadata.focusDate = today
            metadata.whenDate = today
        }

        // Timezone-safe anchor day, derived from the anchor date being persisted.
        let anchorDate = metadata.dueDate.flatMap { PlannerumFormatters.iso8601.date(from: $0) } ?? Date()
        metadata.seriesAnchorDay = RecurringSeriesEngine.dayKey(for: anchorDate)

        let template = Atom.new(
            type: .task,
            title: atom.title,
            body: atom.body,
            metadata: (atom.mergingTaskMetadata(metadata, context: "Dashboard.createRecurringTemplate(\(atom.uuid.prefix(8)))") ?? atom.withMetadata(metadata)).metadata,
            links: atom.linksList.isEmpty ? nil : atom.linksList
        )

        return try await AtomRepository.shared.create(template)
    }

    /// Cancel a single recurring occurrence — the default "delete" for occurrence rows.
    /// Writes a per-day override on the template; the series, its rule, and its completion
    /// history are untouched.
    @discardableResult
    func cancelOccurrence(_ task: TaskViewModel) async -> Bool {
        guard let occurrenceDay = task.occurrenceDay else { return false }
        do {
            try await RecurringSeriesEngine.shared.cancelOccurrence(
                templateUUID: task.uuid,
                dayKey: RecurringSeriesEngine.dayKey(for: occurrenceDay)
            )
            await refreshTaskCollectionsAfterMutation()
            return true
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.cancelOccurrence(\(task.id))", detail: error.localizedDescription)
            return false
        }
    }

    /// Number of logged completions on a recurring series template — surfaced by the
    /// delete-series confirmation message.
    func seriesCompletionCount(templateUUID: String) async -> Int {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: templateUUID),
              let meta = atom.metadataValue(as: TaskMetadata.self) else { return 0 }
        return meta.completedOccurrences?.count ?? 0
    }

    func deleteTask(
        uuid: String,
        recurrenceScope: RecurringTaskTitleEditScope = .currentAndFuture
    ) async {
        do {
            guard let current = try await AtomRepository.shared.fetch(uuid: uuid) else { return }
            // Virtual series template with logged history: deleting the atom would take the
            // completion log with it. End the series in place instead — past occurrences
            // (and their completions) stay; the current and future ones vanish.
            if let meta = current.metadataValue(as: TaskMetadata.self),
               meta.recurrenceParentUUID == nil,
               meta.recurrence != nil,
               RecurringSeriesEngine.hasLoggedHistory(meta) {
                try await RecurringSeriesEngine.shared.endSeriesPreservingHistory(templateUUID: uuid)
                await removeCalendarEvent(for: current)
                await refreshTaskCollectionsAfterMutation()
                return
            }
            try await truncateRecurringTemplateIfNeeded(
                for: current,
                scope: recurrenceScope
            )
            let targets = try await recurringDeleteTargets(
                for: current,
                scope: recurrenceScope
            )
            try await deleteTasksAndCalendarEvents(targets)
            await refreshTaskCollectionsAfterMutation()
            registerTaskDeletionUndo(
                uuids: targets.map(\.uuid),
                actionDescription: targets.count > 1 ? "Delete Tasks" : "Delete Task"
            )
        } catch {
            PersistenceHealth.note(.writeFailure, context: "Dashboard.deleteTask(\(uuid.prefix(8)))", detail: error.localizedDescription)
        }
    }

    /// ⌘Z contract for task deletions: restore the tombstoned atoms and
    /// refresh every list. Calendar events removed alongside the delete are
    /// not resurrected — the task returns, its EK mirror is re-created on the
    /// next calendar sync touch.
    private func registerTaskDeletionUndo(uuids: [String], actionDescription: String) {
        guard !uuids.isEmpty else { return }
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: actionDescription,
            undo: { [weak self] in
                for uuid in uuids {
                    try? await AtomRepository.shared.restore(uuid: uuid)
                }
                await self?.refreshTaskCollectionsAfterMutation()
            },
            redo: { [weak self] in
                for uuid in uuids {
                    try? await AtomRepository.shared.delete(uuid: uuid)
                }
                await self?.refreshTaskCollectionsAfterMutation()
            }
        ))
    }

    private func recurringDeleteTargets(
        for current: Atom,
        scope: RecurringTaskTitleEditScope
    ) async throws -> [Atom] {
        guard scope == .currentAndFuture,
              let currentMetadata = current.metadataValue(as: TaskMetadata.self) else {
            return [current]
        }

        if let parentUUID = currentMetadata.recurrenceParentUUID {
            let calendar = Calendar.current
            let referenceDay = calendar.startOfDay(for: recurrenceOccurrenceDate(from: currentMetadata) ?? Date())
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)
            var targetsByUUID: [String: Atom] = [current.uuid: current]

            for atom in atoms {
                guard let metadata = atom.metadataValue(as: TaskMetadata.self),
                      metadata.recurrenceParentUUID == parentUUID,
                      let occurrenceDate = recurrenceOccurrenceDate(from: metadata),
                      calendar.startOfDay(for: occurrenceDate) >= referenceDay else {
                    continue
                }

                targetsByUUID[atom.uuid] = atom
            }

            return Array(targetsByUUID.values)
        }

        guard currentMetadata.recurrence != nil else {
            return [current]
        }

        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: recurrenceOccurrenceDate(from: currentMetadata) ?? Date())
        let atoms = try await AtomRepository.shared.fetchAll(type: .task)
        var targetsByUUID: [String: Atom] = [current.uuid: current]

        for atom in atoms {
            guard let metadata = atom.metadataValue(as: TaskMetadata.self),
                  metadata.recurrenceParentUUID == current.uuid,
                  let occurrenceDate = recurrenceOccurrenceDate(from: metadata),
                  calendar.startOfDay(for: occurrenceDate) >= referenceDay else {
                continue
            }

            targetsByUUID[atom.uuid] = atom
        }

        return Array(targetsByUUID.values)
    }

    private func truncateRecurringTemplateIfNeeded(
        for current: Atom,
        scope: RecurringTaskTitleEditScope
    ) async throws {
        guard scope == .currentAndFuture,
              let currentMetadata = current.metadataValue(as: TaskMetadata.self),
              let parentUUID = currentMetadata.recurrenceParentUUID,
              let occurrenceDate = recurrenceOccurrenceDate(from: currentMetadata),
              let parent = try await AtomRepository.shared.fetch(uuid: parentUUID),
              let parentMetadata = parent.metadataValue(as: TaskMetadata.self),
              let recurrenceJSON = parentMetadata.recurrence,
              let rule = RecurrenceRule.fromJSON(recurrenceJSON) else {
            return
        }

        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: occurrenceDate)
        let endDate = calendar.date(byAdding: .day, value: -1, to: referenceDay)
            ?? referenceDay.addingTimeInterval(-86_400)
        let truncatedRule = RecurrenceRule(
            frequency: rule.frequency,
            interval: rule.interval,
            daysOfWeek: rule.daysOfWeek,
            dayOfMonth: rule.dayOfMonth,
            monthOfYear: rule.monthOfYear,
            endCondition: .onDate(endDate)
        )

        _ = try await AtomRepository.shared.update(uuid: parentUUID) { atom in
            guard var metadata = taskMetadataForWrite(atom, context: "Dashboard.truncateRecurringTemplate(\(parentUUID.prefix(8)))") else { return }
            metadata.recurrence = truncatedRule.toJSON()
            guard let merged = atom.mergingTaskMetadata(metadata, context: "Dashboard.truncateRecurringTemplate(\(parentUUID.prefix(8)))") else { return }
            atom = merged
        }
    }

    private func deleteTasksAndCalendarEvents(_ atoms: [Atom]) async throws {
        for atom in atoms {
            try await AtomRepository.shared.delete(uuid: atom.uuid)
            await removeCalendarEvent(for: atom)
        }
    }

    private func removeCalendarEvent(for atom: Atom) async {
        guard calendarService.hasCalendarAccess,
              let calendarEventId = atom.metadataValue(as: TaskMetadata.self)?.calendarEventId else { return }
        do {
            try await calendarService.deleteCosmoEvent(eventId: calendarEventId)
        } catch {
            PersistenceHealth.note(.syncFailure, context: "Dashboard.deleteTasksAndCalendarEvents(\(atom.uuid.prefix(8)))", detail: "EK event removal failed: \(error.localizedDescription)")
        }
    }

    func deleteMultipleTasks(uuids: Set<String>) async {
        for uuid in uuids {
            do {
                try await AtomRepository.shared.delete(uuid: uuid)
            } catch {
                PersistenceHealth.note(.writeFailure, context: "Dashboard.deleteMultipleTasks(\(uuid.prefix(8)))", detail: error.localizedDescription)
            }
        }
        await refreshTaskCollectionsAfterMutation()
        registerTaskDeletionUndo(
            uuids: Array(uuids),
            actionDescription: uuids.count > 1 ? "Delete Tasks" : "Delete Task"
        )
    }

    func startFocusSession(for task: TaskViewModel) {
        // The one choke point for starting a sitting (gauge button, row play,
        // Space) — the cue lives with the action, not the surfaces.
        Sound.focusStart()
        let habit = resolvedHabit(for: task)
        var intentPresentation = resolvedIntentPresentation(for: task)
        // Both-axes attribution: when the task carries no explicit intent, inherit the habit's
        // default intent so behavior routing + dimension XP never fall back to "Unassigned".
        if intentPresentation.isUnassigned, let habitIntentUUID = habit?.defaultIntentUUID {
            intentPresentation = resolvedIntentPresentation(intentUUID: habitIntentUUID, legacyIntentRaw: nil)
        }
        // Timed tasks: aim the session at the remaining goal time, not the estimate.
        // (Recurring per-day progress is resolved async by the engine's goal context;
        // the session length here is just the visible countdown.)
        let plannedMinutes: Int
        if let goal = task.timeGoalMinutes {
            plannedMinutes = max(1, goal - (task.isRecurring ? 0 : task.totalFocusMinutes))
        } else {
            plannedMinutes = task.estimatedMinutes
        }
        sessionEngine.startSession(
            taskUUID: task.uuid,
            taskTitle: task.title,
            intent: behaviorIntent(for: task),
            intentUUID: intentPresentation.definitionID,
            intentTitleSnapshot: intentPresentation.isUnassigned ? nil : intentPresentation.title,
            habitUUID: habit?.id,
            habitTitleSnapshot: habit?.title,
            plannedMinutes: plannedMinutes
        )

        // Route to focus mode — use linkedAtoms (primary = main, others = panes)
        let allLinked = task.linkedAtoms
        if !allLinked.isEmpty {
            let primary = allLinked.first(where: \.isPrimary) ?? allLinked.first
            let panes = allLinked.filter { $0.id != primary?.id }

            if let primary {
                NotificationCenter.default.post(
                    name: .init("com.cosmo.navigateToAtom"),
                    object: nil,
                    userInfo: [
                        "uuid": primary.atomUUID,
                        "atomType": primary.atomType,
                        "intent": behaviorIntent(for: task).rawValue,
                        "paneAtomUUIDs": panes.map(\.atomUUID),
                        "paneAtomTypes": panes.map(\.atomType)
                    ] as [String: Any]
                )
            }
        } else {
            // Legacy fallback — use old single-UUID fields
            switch behaviorIntent(for: task) {
            case .writeContent:
                if let uuid = task.linkedContentUUID ?? task.linkedIdeaUUID {
                    NotificationCenter.default.post(
                        name: .init("com.cosmo.navigateToAtom"),
                        object: nil,
                        userInfo: ["uuid": uuid, "intent": "writeContent"]
                    )
                }
            case .research:
                if let uuid = task.linkedAtomUUID {
                    NotificationCenter.default.post(
                        name: .init("com.cosmo.navigateToAtom"),
                        object: nil,
                        userInfo: ["uuid": uuid, "intent": "research"]
                    )
                }
            case .studySwipes:
                NotificationCenter.default.post(
                    name: .init("com.cosmo.navigateToSwipeStudy"),
                    object: nil
                )
            case .deepThink:
                if let uuid = task.linkedAtomUUID {
                    NotificationCenter.default.post(
                        name: .init("com.cosmo.navigateToAtom"),
                        object: nil,
                        userInfo: ["uuid": uuid, "intent": "deepThink"]
                    )
                }
            case .review:
                if let uuid = task.linkedAtomUUID ?? task.linkedContentUUID {
                    NotificationCenter.default.post(
                        name: .init("com.cosmo.navigateToAtom"),
                        object: nil,
                        userInfo: ["uuid": uuid, "intent": "review"]
                    )
                }
            case .general, .custom:
                break
            }
        }
    }

    // MARK: - Time Tracking Data

    func loadTodayTimeData() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .deepWorkBlock)
            let todayStart = Calendar.current.startOfDay(for: Date())

            var totalMinutes = 0
            var intentMinutes: [String: IntentSummary] = [:]

            for atom in atoms {
                guard let session = CommandCenterHabitPersistence.deepWorkSession(from: atom),
                      session.startedAt >= todayStart else { continue }

                let minutes = session.minutes
                totalMinutes += minutes

                let summary = attributionSummary(habitUUID: session.habitUUID, intentUUID: session.intentUUID, legacyIntentRaw: session.intent, minutes: 0)
                var updated = intentMinutes[summary.id] ?? summary
                updated.minutes += minutes
                intentMinutes[summary.id] = updated
            }

            assignIfChanged(\.todayTrackedMinutes, to: totalMinutes)
            assignIfChanged(\.todayIntentSummaries, to: intentMinutes.values.sorted { $0.minutes > $1.minutes })
        } catch {
            print("❌ Dashboard: Failed to load time data: \(error)")
        }
    }

    func loadTodaySessions() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .deepWorkBlock)
            let todayStart = Calendar.current.startOfDay(for: Date())

            let nextSessions = atoms.compactMap { atom -> SessionTimelineEntry? in
                guard let session = CommandCenterHabitPersistence.deepWorkSession(from: atom),
                      session.startedAt >= todayStart else { return nil }

                let actualMinutes = session.minutes
                let endDate = session.endedAt
                    ?? session.startedAt.addingTimeInterval(TimeInterval(actualMinutes * 60))

                let intent = resolvedIntentPresentation(intentUUID: session.intentUUID, legacyIntentRaw: session.intent)

                return SessionTimelineEntry(
                    id: atom.uuid,
                    title: atom.title ?? "Focus Session",
                    intent: intent,
                    habitTitle: session.habitTitleSnapshot,
                    startTime: session.startedAt,
                    endTime: endDate,
                    focusScore: session.focusScore ?? 100,
                    taskUUID: session.taskUUID
                )
            }
            .sorted { $0.startTime < $1.startTime }
            assignIfChanged(\.todaySessions, to: nextSessions)
        } catch {
            print("❌ Dashboard: Failed to load today sessions: \(error)")
        }
    }

    // MARK: - Weekly Report

    func loadWeeklyReport() async {
        do {
            let sessionAtoms = try await AtomRepository.shared.fetchAll(type: .deepWorkBlock)
            let taskAtoms = try await AtomRepository.shared.fetchAll(type: .task)

            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: Date())

            // Build 7-day window with offset support
            let weekEnd = calendar.date(byAdding: .day, value: reportWeekOffset * 7, to: todayStart)!
            let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd)!
            let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!

            // Collect sessions for this week and previous week
            var thisWeekMinutes = 0
            var previousWeekMinutes = 0
            var dayBuckets: [Date: (minutes: Int, focusScores: [Double], tasks: Int, sessions: Int, intents: [String: IntentSummary])] = [:]

            // Initialize buckets for each of the 7 days
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
                dayBuckets[calendar.startOfDay(for: day)] = (0, [], 0, 0, [:])
            }

            // Aggregate session data
            for atom in sessionAtoms {
                guard let session = CommandCenterHabitPersistence.deepWorkSession(from: atom) else { continue }

                let minutes = session.minutes
                let dayStart = calendar.startOfDay(for: session.startedAt)

                if session.startedAt >= weekStart {
                    thisWeekMinutes += minutes

                    if var bucket = dayBuckets[dayStart] {
                        bucket.minutes += minutes
                        if let score = session.focusScore { bucket.focusScores.append(Double(score)) }
                        bucket.sessions += 1
                        let summary = attributionSummary(habitUUID: session.habitUUID, intentUUID: session.intentUUID, legacyIntentRaw: session.intent)
                        var updated = bucket.intents[summary.id] ?? summary
                        updated.minutes += minutes
                        bucket.intents[summary.id] = updated
                        dayBuckets[dayStart] = bucket
                    }
                } else if session.startedAt >= previousWeekStart {
                    previousWeekMinutes += minutes
                }
            }

            // Count completed tasks per day
            for atom in taskAtoms {
                guard let vm = TaskViewModel.from(atom: atom),
                      vm.isCompleted,
                      let completedAt = vm.completedAt else { continue }

                let dayStart = calendar.startOfDay(for: completedAt)
                if var bucket = dayBuckets[dayStart] {
                    bucket.tasks += 1
                    dayBuckets[dayStart] = bucket
                }
            }

            // Build DayReportEntry array
            var days: [DayReportEntry] = []
            var totalFocusScores: [Double] = []
            var totalTasksCompleted = 0
            var totalSessions = 0
            var intentDistribution: [String: IntentSummary] = [:]

            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
                let dayStart = calendar.startOfDay(for: day)
                let bucket = dayBuckets[dayStart] ?? (0, [], 0, 0, [:])

                let avgFocus = bucket.focusScores.isEmpty ? 0.0 : bucket.focusScores.reduce(0, +) / Double(bucket.focusScores.count)
                let dominantIntent = bucket.intents.values.max(by: { $0.minutes < $1.minutes })

                days.append(DayReportEntry(
                    id: "\(offset)",
                    date: day,
                    trackedMinutes: bucket.minutes,
                    focusScore: avgFocus,
                    tasksCompleted: bucket.tasks,
                    sessionCount: bucket.sessions,
                    dominantIntent: dominantIntent
                ))

                totalFocusScores.append(contentsOf: bucket.focusScores)
                totalTasksCompleted += bucket.tasks
                totalSessions += bucket.sessions
                for summary in bucket.intents.values {
                    var updated = intentDistribution[summary.id] ?? intentSummary(intentUUID: summary.id == "unassigned" ? nil : summary.id, legacyIntentRaw: nil)
                    updated = summary
                    if let existing = intentDistribution[summary.id] {
                        updated.minutes = existing.minutes + summary.minutes
                    }
                    intentDistribution[summary.id] = updated
                }
            }

            let avgFocus = totalFocusScores.isEmpty ? 0.0 : totalFocusScores.reduce(0, +) / Double(totalFocusScores.count)

            let nextReport = ReportData(
                timeRange: .week,
                startDate: weekStart,
                endDate: weekEnd,
                days: days,
                totalMinutes: thisWeekMinutes,
                avgFocusScore: avgFocus,
                tasksCompleted: totalTasksCompleted,
                totalSessions: totalSessions,
                intentDistribution: intentDistribution.values.sorted { $0.minutes > $1.minutes },
                previousPeriodMinutes: previousWeekMinutes
            )
            assignIfChanged(\.weeklyReportData, to: nextReport)
        } catch {
            print("❌ Dashboard: Failed to load weekly report: \(error)")
        }
    }

    // MARK: - Month Report

    func loadMonthReport() async {
        do {
            let sessionAtoms = try await AtomRepository.shared.fetchAll(type: .deepWorkBlock)
            let taskAtoms = try await AtomRepository.shared.fetchAll(type: .task)

            let calendar = Calendar.current
            let today = Date()

            // Calculate month start/end based on offset
            guard let targetMonth = calendar.date(byAdding: .month, value: reportMonthOffset, to: today) else { return }
            guard let monthRange = calendar.range(of: .day, in: .month, for: targetMonth) else { return }
            let comps = calendar.dateComponents([.year, .month], from: targetMonth)
            guard let monthStart = calendar.date(from: comps) else { return }
            guard let monthEnd = calendar.date(byAdding: .day, value: monthRange.count - 1, to: monthStart) else { return }

            // Previous month for trend
            guard let prevMonth = calendar.date(byAdding: .month, value: -1, to: monthStart) else { return }
            let prevComps = calendar.dateComponents([.year, .month], from: prevMonth)
            guard let prevMonthStart = calendar.date(from: prevComps) else { return }

            var thisMonthMinutes = 0
            var prevMonthMinutes = 0
            var dayBuckets: [Date: (minutes: Int, focusScores: [Double], tasks: Int, sessions: Int, intents: [String: IntentSummary])] = [:]

            for offset in 0..<monthRange.count {
                guard let day = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
                dayBuckets[calendar.startOfDay(for: day)] = (0, [], 0, 0, [:])
            }

            for atom in sessionAtoms {
                guard let session = CommandCenterHabitPersistence.deepWorkSession(from: atom) else { continue }

                let minutes = session.minutes
                let dayStart = calendar.startOfDay(for: session.startedAt)

                if session.startedAt >= monthStart && session.startedAt <= monthEnd.addingTimeInterval(86400) {
                    thisMonthMinutes += minutes
                    if var bucket = dayBuckets[dayStart] {
                        bucket.minutes += minutes
                        if let score = session.focusScore { bucket.focusScores.append(Double(score)) }
                        bucket.sessions += 1
                        let summary = attributionSummary(habitUUID: session.habitUUID, intentUUID: session.intentUUID, legacyIntentRaw: session.intent)
                        var updated = bucket.intents[summary.id] ?? summary
                        updated.minutes += minutes
                        bucket.intents[summary.id] = updated
                        dayBuckets[dayStart] = bucket
                    }
                } else if session.startedAt >= prevMonthStart && session.startedAt < monthStart {
                    prevMonthMinutes += minutes
                }
            }

            for atom in taskAtoms {
                guard let vm = TaskViewModel.from(atom: atom),
                      vm.isCompleted,
                      let completedAt = vm.completedAt else { continue }
                let dayStart = calendar.startOfDay(for: completedAt)
                if var bucket = dayBuckets[dayStart] {
                    bucket.tasks += 1
                    dayBuckets[dayStart] = bucket
                }
            }

            var days: [DayReportEntry] = []
            var totalFocusScores: [Double] = []
            var totalTasksCompleted = 0
            var totalSessions = 0
            var intentDistribution: [String: IntentSummary] = [:]

            for offset in 0..<monthRange.count {
                guard let day = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
                let dayStart = calendar.startOfDay(for: day)
                let bucket = dayBuckets[dayStart] ?? (0, [], 0, 0, [:])
                let avgFocus = bucket.focusScores.isEmpty ? 0.0 : bucket.focusScores.reduce(0, +) / Double(bucket.focusScores.count)
                let dominantIntent = bucket.intents.values.max(by: { $0.minutes < $1.minutes })

                days.append(DayReportEntry(
                    id: "\(offset)",
                    date: day,
                    trackedMinutes: bucket.minutes,
                    focusScore: avgFocus,
                    tasksCompleted: bucket.tasks,
                    sessionCount: bucket.sessions,
                    dominantIntent: dominantIntent
                ))

                totalFocusScores.append(contentsOf: bucket.focusScores)
                totalTasksCompleted += bucket.tasks
                totalSessions += bucket.sessions
                for summary in bucket.intents.values {
                    var updated = intentDistribution[summary.id] ?? intentSummary(intentUUID: summary.id == "unassigned" ? nil : summary.id, legacyIntentRaw: nil)
                    updated = summary
                    if let existing = intentDistribution[summary.id] {
                        updated.minutes = existing.minutes + summary.minutes
                    }
                    intentDistribution[summary.id] = updated
                }
            }

            let avgFocus = totalFocusScores.isEmpty ? 0.0 : totalFocusScores.reduce(0, +) / Double(totalFocusScores.count)

            let nextReport = ReportData(
                timeRange: .month,
                startDate: monthStart,
                endDate: monthEnd,
                days: days,
                totalMinutes: thisMonthMinutes,
                avgFocusScore: avgFocus,
                tasksCompleted: totalTasksCompleted,
                totalSessions: totalSessions,
                intentDistribution: intentDistribution.values.sorted { $0.minutes > $1.minutes },
                previousPeriodMinutes: prevMonthMinutes
            )
            assignIfChanged(\.weeklyReportData, to: nextReport)
        } catch {
            print("❌ Dashboard: Failed to load month report: \(error)")
        }
    }

    // MARK: - Habit Report

    func loadHabitReport() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate: Date
        let endDate: Date

        switch selectedReportTab {
        case .week, .habits:
            let weekStart = calendar.date(byAdding: .day, value: reportWeekOffset * 7 - 6, to: today)!
            let weekEnd = calendar.date(byAdding: .day, value: reportWeekOffset * 7, to: today)!
            startDate = weekStart
            endDate = weekEnd
        case .month:
            guard let targetMonth = calendar.date(byAdding: .month, value: reportMonthOffset, to: today) else { return }
            let comps = calendar.dateComponents([.year, .month], from: targetMonth)
            guard let monthStart = calendar.date(from: comps),
                  let monthRange = calendar.range(of: .day, in: .month, for: targetMonth),
                  let monthEnd = calendar.date(byAdding: .day, value: monthRange.count - 1, to: monthStart) else { return }
            startDate = monthStart
            endDate = monthEnd
        }

        let entries = await habitEngine.loadHabitReport(startDate: startDate, endDate: endDate)
        let totalCompletions = entries.reduce(0) { $0 + $1.completedDays }
        let totalPossible = entries.reduce(0) { $0 + $1.totalDays }
        let rate = totalPossible > 0 ? Double(totalCompletions) / Double(totalPossible) : 0

        let nextReport = HabitReportData(
            timeRange: selectedReportTab == .month ? .month : .week,
            startDate: startDate,
            endDate: endDate,
            habitEntries: entries,
            overallCompletionRate: rate,
            totalCompletions: totalCompletions,
            totalPossible: totalPossible
        )
        assignIfChanged(\.habitReportData, to: nextReport)
    }

    // MARK: - Report Navigation

    func navigateReport(direction: Int) async {
        switch selectedReportTab {
        case .week:
            reportWeekOffset += direction
            await loadWeeklyReport()
        case .month:
            reportMonthOffset += direction
            await loadMonthReport()
        case .habits:
            reportWeekOffset += direction
            await loadHabitReport()
        }
    }

    var reportDateLabel: String {
        let calendar = Calendar.current

        switch selectedReportTab {
        case .week:
            let today = calendar.startOfDay(for: Date())
            let weekStart = calendar.date(byAdding: .day, value: reportWeekOffset * 7 - 6, to: today)!
            let weekEnd = calendar.date(byAdding: .day, value: reportWeekOffset * 7, to: today)!
            let start = CosmoDateFormatters.abbreviatedMonthDay.string(from: weekStart)
            let end = CosmoDateFormatters.abbreviatedMonthDay.string(from: weekEnd)
            let year = CosmoDateFormatters.commaYearSuffix.string(from: weekEnd)
            return "\(start) – \(end)\(year)"
        case .month:
            guard let targetMonth = calendar.date(byAdding: .month, value: reportMonthOffset, to: Date()) else { return "" }
            return CosmoDateFormatters.monthYear.string(from: targetMonth)
        case .habits:
            if reportWeekOffset == 0 { return "This Week" }
            let today = calendar.startOfDay(for: Date())
            let weekStart = calendar.date(byAdding: .day, value: reportWeekOffset * 7 - 6, to: today)!
            let weekEnd = calendar.date(byAdding: .day, value: reportWeekOffset * 7, to: today)!
            return "\(CosmoDateFormatters.abbreviatedMonthDay.string(from: weekStart)) – \(CosmoDateFormatters.abbreviatedMonthDay.string(from: weekEnd))"
        }
    }

    func notifyCompletedTaskArrival() {
        completedArrivalToken += 1
    }

    private func refreshTaskCollectionsAfterMutation() async {
        guard let atoms = try? await loadTaskAtoms(nil) else { return }
        switch viewMode {
        case .today:
            await refreshTasks(from: atoms)
        case .upcoming:
            await loadUpcomingTasks(from: atoms)
            await loadCompletedTasks(from: atoms)
        case .logbook:
            await loadCompletedTasks(from: atoms)
        case .anytime:
            await loadAnytimeTasks(from: atoms)
        case .someday:
            await loadSomedayTasks(from: atoms)
        case .habits, .reports, .queue:
            break
        case .project:
            if let uuid = selectedProjectUUID {
                await loadProjectTasks(projectUUID: uuid)
            }
        case .area:
            break
        }
        await loadTodayTimeData()
        await loadTodaySessions()
    }

    // MARK: - Greeting

    var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    var greetingText: String {
        let name = UserDefaults.standard.string(forKey: "userName") ?? "there"
        return "\(greetingPrefix), \(name)"
    }

    var dateText: String {
        CosmoDateFormatters.abbreviatedWeekdayFullMonthDay.string(from: selectedDate)
    }

    var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Every open band cleared with at least one completion on the viewed
    /// day — the once-a-day earned moment (the masthead's "All clear ✦" and
    /// the day-clear chime both read this).
    var isDayClear: Bool {
        isViewingToday
            && overdueTasks.isEmpty
            && scheduledTasks.isEmpty
            && unscheduledTasks.isEmpty
            && !completedTasksForSelectedDay.isEmpty
    }

    /// The evening register: today after 17:00 — or any moment the day
    /// stands cleared — invites planning tomorrow.
    var isEveningRegister: Bool {
        guard isViewingToday else { return false }
        if isDayClear { return true }
        return Calendar.current.component(.hour, from: Date()) >= 17
    }

    /// Open work already waiting on `day` — the Plan-Tomorrow row's glance
    /// count. One day's window over the same projection rules
    /// loadUpcomingTasks uses (series occurrences + plain display dates).
    func plannedOpenCount(for day: Date) async -> Int {
        guard let atoms = try? await AtomRepository.shared.fetchAll(type: .task) else { return 0 }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        let interval = DateInterval(start: dayStart, end: dayEnd)

        var count = 0
        for atom in atoms {
            if let snapshot = RecurringSeriesEngine.makeSnapshot(from: atom, calendar: calendar),
               let templateVM = TaskViewModel.from(atom: atom) {
                for occ in RecurringSeriesEngine.occurrences(for: snapshot, in: interval, asOf: Date(), calendar: calendar) {
                    let vm = templateVM.makingOccurrence(occ)
                    if !vm.isCompleted { count += 1 }
                }
            } else if let vm = TaskViewModel.from(atom: atom), !vm.isRecurring, !vm.isCompleted,
                      let display = vm.calendarDisplayDate,
                      display >= dayStart, display < dayEnd {
                count += 1
            }
        }
        return count
    }

    var activeTaskCount: Int {
        todayActiveCount
    }

    // Legacy compatibility
    var filteredTasks: [TaskViewModel] {
        currentVisibleTasks
    }
}
