// Canvas/CommandCenter/CommandCenterDashboardViewModel.swift
// Unified state coordinator for the Command Center Dashboard
// March 2026

import SwiftUI
import Combine

// MARK: - Stub Types (Plannerum directory deleted)

/// Minimal stub for XP progress display (Plannerum deleted)
struct XPProgressState {
    var level: Int = 1
    var currentXP: Int = 0
    var nextLevelXP: Int = 100
    var progress: Double { Double(currentXP) / Double(max(1, nextLevelXP)) }
}

/// Minimal stub for PlannerumViewModel (Plannerum deleted)
/// Provides today-task loading, completion, and quick-add that the dashboard depends on.
@MainActor
class PlannerumViewModel: ObservableObject {
    static let shared = PlannerumViewModel()

    @Published var todayTasks: [TaskViewModel] = []
    @Published var xpProgress: XPProgressState = XPProgressState()

    let liveQuestEngine = QuestEngine()

    func loadTodayTasks() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)
            let calendar = Calendar.current
            todayTasks = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                if vm.isCompleted { return nil }
                if vm.isRecurring && vm.recurrenceParentUUID == nil { return nil }
                if vm.calendarStart.map({ calendar.isDateInToday($0) }) == true { return vm }
                return nil
            }
        } catch {
            print("[PlannerumViewModel stub] Failed to load today tasks: \(error)")
        }
    }

    func completeTask(taskId: String) async {
        do {
            _ = try await AtomRepository.shared.update(uuid: taskId) { atom in
                var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                metadata.isCompleted = true
                metadata.completedAt = ISO8601DateFormatter().string(from: Date())
                atom = atom.withMetadata(metadata)
            }
            await loadTodayTasks()
        } catch {
            print("[PlannerumViewModel stub] Failed to complete task: \(error)")
        }
    }

    func quickAddTask(title: String) async {
        let atom = Atom.new(type: .task, title: title)
        _ = try? await AtomRepository.shared.create(atom)
        await loadTodayTasks()
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
    var sourceBreakdown: HabitSourceBreakdown
    var isBuiltIn: Bool
    var isEditable: Bool
    var linkedIntentSummary: String?
}

private enum DashboardRefreshDomain: Hashable {
    case tasks
    case habits
    case timeData
    case sessions
    case weeklyReport
}

enum RecurringTaskTitleEditScope: String, CaseIterable, Sendable {
    case currentOnly
    case currentAndFuture
}

private struct DashboardAtomSubsetSignature: Equatable {
    let count: Int
    let fingerprint: Int

    init(atoms: [Atom], matching types: Set<AtomType>) {
        var count = 0
        var hasher = Hasher()

        for atom in atoms where types.contains(atom.type) {
            count += 1
            hasher.combine(atom.uuid)
            hasher.combine(atom.localVersion)
            hasher.combine(atom.updatedAt)
        }

        self.count = count
        self.fingerprint = hasher.finalize()
    }
}

private struct DashboardAtomRefreshSignature: Equatable {
    let tasks: DashboardAtomSubsetSignature
    let deepWork: DashboardAtomSubsetSignature

    init(atoms: [Atom]) {
        self.tasks = DashboardAtomSubsetSignature(atoms: atoms, matching: [.task])
        self.deepWork = DashboardAtomSubsetSignature(atoms: atoms, matching: [.deepWorkBlock])
    }
}

struct CommandCenterTodayTaskSections: Equatable {
    var overdue: [TaskViewModel]
    var scheduled: [TaskViewModel]
    var unscheduled: [TaskViewModel]
}

enum CommandCenterTodayTaskSectioning {
    static func sectionTasks(
        _ tasks: [TaskViewModel],
        selectedDate: Date,
        calendar: Calendar = .current
    ) -> CommandCenterTodayTaskSections {
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

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
                } else if calendarStart < dayStart,
                          !isSuppressedRecurringOverdue(task, repeatedTodayParents: recurrenceParentsWithSelectedDayInstance) {
                    overdue.append(task)
                }
                continue
            }

            guard let plannedDate = plannedDate(for: task) else { continue }
            let plannedDay = calendar.startOfDay(for: plannedDate)

            if plannedDay < dayStart,
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

    private static func overdueSort(calendar: Calendar) -> (TaskViewModel, TaskViewModel) -> Bool {
        { lhs, rhs in
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

    private static func clearCalendarTime(from metadata: inout TaskMetadata) {
        metadata.startTime = nil
        metadata.endTime = nil
        metadata.scheduledStart = nil
        metadata.scheduledEnd = nil
        metadata.durationMinutes = nil
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
class CommandCenterDashboardViewModel: ObservableObject {

    // MARK: - View Mode

    @Published var viewMode: DashboardViewMode = .today

    // MARK: - Date Selection

    @Published var selectedDate: Date = Date()

    // MARK: - Sectioned Tasks (Today view)

    @Published var overdueTasks: [TaskViewModel] = []
    @Published var scheduledTasks: [TaskViewModel] = []
    @Published var unscheduledTasks: [TaskViewModel] = []
    @Published var completedTodayTasks: [TaskViewModel] = []
    @Published var completedTasksByDay: [(date: Date, tasks: [TaskViewModel])] = []

    // MARK: - Upcoming (Upcoming view)

    @Published var upcomingDayGroups: [UpcomingDayViewModel] = []
    @Published var upcomingWeekOffset: Int = 0
    @Published var upcomingCalendarEvents: [String: [CalendarEvent]] = [:]  // keyed by date string
    @Published var upcomingCalendarScope: UpcomingCalendarScope = .week
    @Published var upcomingAnchorDate: Date = Calendar.current.startOfDay(for: Date())

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
        let dates = upcomingVisibleDates
        guard let first = dates.first, let last = dates.last else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        switch upcomingCalendarScope {
        case .day:
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE, MMM d"
            return dayFormatter.string(from: upcomingAnchorDate)
        case .week:
            return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
        case .month:
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM yyyy"
            return monthFormatter.string(from: upcomingAnchorDate)
        }
    }

    // MARK: - Things 3 Smart Lists

    @Published var anytimeTasks: [TaskViewModel] = []
    @Published var somedayTasks: [TaskViewModel] = []
    @Published var logbookTasks: [TaskViewModel] = []

    // MARK: - Areas & Projects (Sidebar)

    @Published var areas: [Atom] = []
    @Published var projects: [Atom] = []
    @Published var selectedProjectUUID: String?
    @Published var selectedAreaUUID: String?
    @Published var projectTasks: [TaskViewModel] = []
    @Published var projectHeadings: [ProjectHeading] = []

    // MARK: - Timeline Sessions

    @Published var todaySessions: [SessionTimelineEntry] = []

    // MARK: - Keyboard Selection

    @Published var selectedTaskIndex: Int?

    // MARK: - Habits

    @Published var habits: [HabitState] = []

    // MARK: - Objectives

    @Published var objectives: [ObjectiveState] = []

    // MARK: - Calendar Events

    @Published var todayEvents: [CalendarEvent] = []

    // MARK: - Quick Stats

    @Published var xpProgress: XPProgressState = XPProgressState()
    @Published var currentStreak: Int = 0

    // MARK: - Reports

    @Published var weeklyReportData: WeeklyReportData?
    @Published var showReports: Bool = false
    @Published var selectedReportTab: ReportTab = .week
    @Published var reportWeekOffset: Int = 0
    @Published var reportMonthOffset: Int = 0
    @Published var habitReportData: HabitReportData?

    // MARK: - Time Tracking

    @Published var todayTrackedMinutes: Int = 0
    @Published var todayIntentSummaries: [IntentSummary] = []
    @Published var completedArrivalToken: Int = 0

    // MARK: - Task Add

    @Published var newTaskTitle: String = ""
    var pendingTaskDate: Date?

    // MARK: - Dependencies

    private let plannerum = PlannerumViewModel.shared
    let sessionEngine = DeepWorkSessionEngine.shared
    private let objectiveEngine = ObjectiveEngine()
    private let calendarService = CalendarSyncService.shared
    private let habitEngine = CommandCenterHabitEngine.shared
    private let intentEngine = CommandCenterIntentEngine.shared
    private var cancellables = Set<AnyCancellable>()
    private var inFlightRefreshes: [DashboardRefreshDomain: Task<Void, Never>] = [:]
    private var queuedRefreshDomains = Set<DashboardRefreshDomain>()
    private var lastAtomRefreshSignature: DashboardAtomRefreshSignature?

    // MARK: - Computed

    /// Flat list of currently visible tasks for keyboard navigation
    var currentVisibleTasks: [TaskViewModel] {
        switch viewMode {
        case .today:
            return overdueTasks + scheduledTasks + unscheduledTasks
        case .upcoming:
            return upcomingDayGroups.flatMap { $0.tasks }
        case .logbook:
            return completedTasksByDay.flatMap { $0.tasks }
        case .anytime:
            return anytimeTasks
        case .someday:
            return somedayTasks
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
        Task {
            await refreshAll()
        }
    }

    // MARK: - Bindings

    private func setupBindings() {
        // React to date changes
        $selectedDate
            .removeDuplicates { Calendar.current.isDate($0, inSameDayAs: $1) }
            .sink { [weak self] _ in
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
                }
            }
            .store(in: &cancellables)

        // React to view mode changes
        $viewMode
            .removeDuplicates()
            .sink { [weak self] mode in
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
            .store(in: &cancellables)

        // React to plannerum task changes (debounced to prevent cascading fetches)
        plannerum.$todayTasks
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleRefresh(.tasks, delayNanoseconds: 150_000_000)
            }
            .store(in: &cancellables)

        AtomRepository.shared.$atoms
            .map(DashboardAtomRefreshSignature.init)
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { [weak self] signature in
                self?.handleAtomRefreshSignature(signature)
            }
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
            }
        }
        .store(in: &cancellables)

        // React to objective changes
        objectiveEngine.$objectives
            .sink { [weak self] objectives in
                self?.objectives = objectives
            }
            .store(in: &cancellables)

        // React to XP changes
        plannerum.$xpProgress
            .sink { [weak self] xp in
                self?.xpProgress = xp
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
        await intentEngine.refreshDefinitions()
        await habitEngine.refreshDefinitions()
        await refreshTasks()
        refreshCalendarEvents()
        await loadHabits()
        await loadTodayTimeData()
        await loadTodaySessions()
        await loadWeeklyReport()
        objectiveEngine.startTracking()
        xpProgress = plannerum.xpProgress
        currentStreak = plannerum.liveQuestEngine.streaks.values.max() ?? 0
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
            await refreshTasks()
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

    // MARK: - Task Loading (Today view — sectioned)

    func refreshTasks() async {
        var activeTasks: [TaskViewModel] = []

        do {
            try? await TaskRecurrenceEngine.shared.generateTodayInstances()

            let atoms = try await AtomRepository.shared.fetchAll(type: .task)

            activeTasks = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                if vm.isCompleted { return nil }
                if vm.isRecurring && vm.recurrenceParentUUID == nil { return nil }
                return vm
            }
        } catch {
            print("❌ Dashboard: Failed to load today tasks for date: \(error)")
        }

        let sections = CommandCenterTodayTaskSectioning.sectionTasks(
            activeTasks,
            selectedDate: selectedDate,
            calendar: Calendar.current
        )

        assignIfChanged(\.overdueTasks, to: sections.overdue)
        assignIfChanged(\.scheduledTasks, to: sections.scheduled)
        assignIfChanged(\.unscheduledTasks, to: sections.unscheduled)

        // Load completed tasks independently (todayTasks excludes completed)
        await loadCompletedTasks()
    }

    // MARK: - Upcoming Tasks

    func loadUpcomingTasks() async {
        do {
            try? await TaskRecurrenceEngine.shared.generateInstances(in: upcomingVisibleInterval)

            let atoms = try await AtomRepository.shared.fetchAll(type: .task)
            let calendar = Calendar.current
            let visibleDates = upcomingVisibleDates

            var dayGroups: [UpcomingDayViewModel] = []

            for dayStart in visibleDates {
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

                let dayTasks = atoms.compactMap { atom -> TaskViewModel? in
                    guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                    if vm.isCompleted { return nil }
                    if vm.isRecurring && vm.recurrenceParentUUID == nil { return nil }

                    guard let calendarDisplayDate = vm.calendarDisplayDate else { return nil }
                    return calendarDisplayDate >= dayStart && calendarDisplayDate < dayEnd ? vm : nil
                }
                .sorted {
                    let lhsStart = $0.calendarDisplayDate
                    let rhsStart = $1.calendarDisplayDate
                    if lhsStart != rhsStart {
                        return (lhsStart ?? .distantFuture) < (rhsStart ?? .distantFuture)
                    }
                    if $0.priority.sortOrder != $1.priority.sortOrder {
                        return $0.priority.sortOrder < $1.priority.sortOrder
                    }
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }

                dayGroups.append(UpcomingDayViewModel(date: dayStart, tasks: dayTasks))
            }

            assignIfChanged(\.overdueTasks, to: [])

            assignIfChanged(\.upcomingDayGroups, to: dayGroups)
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

    enum TaskSection { case overdue, scheduled, unscheduled }

    func reorderTasks(section: TaskSection, fromOffsets: IndexSet, toOffset: Int) {
        switch section {
        case .overdue:
            overdueTasks.move(fromOffsets: fromOffsets, toOffset: toOffset)
            persistSortOrder(for: overdueTasks)
        case .scheduled:
            scheduledTasks.move(fromOffsets: fromOffsets, toOffset: toOffset)
            persistSortOrder(for: scheduledTasks)
        case .unscheduled:
            unscheduledTasks.move(fromOffsets: fromOffsets, toOffset: toOffset)
            persistSortOrder(for: unscheduledTasks)
        }
    }

    func moveTask(uuid: String, toSection section: TaskSection, atIndex index: Int) {
        // Remove from current section
        overdueTasks.removeAll { $0.uuid == uuid }
        scheduledTasks.removeAll { $0.uuid == uuid }
        unscheduledTasks.removeAll { $0.uuid == uuid }

        // Find the task from any previous section
        guard let task = (overdueTasks + scheduledTasks + unscheduledTasks).first(where: { $0.uuid == uuid })
            ?? [uuid].compactMap({ id in overdueTasks.first { $0.uuid == id } }).first
        else { return }

        // Insert into target section
        switch section {
        case .overdue:
            overdueTasks.insert(task, at: min(index, overdueTasks.count))
            persistSortOrder(for: overdueTasks)
        case .scheduled:
            scheduledTasks.insert(task, at: min(index, scheduledTasks.count))
            persistSortOrder(for: scheduledTasks)
        case .unscheduled:
            unscheduledTasks.insert(task, at: min(index, unscheduledTasks.count))
            persistSortOrder(for: unscheduledTasks)
        }
    }

    private func persistSortOrder(for tasks: [TaskViewModel]) {
        Task {
            for (index, task) in tasks.enumerated() {
                do {
                    _ = try await AtomRepository.shared.update(uuid: task.uuid) { atom in
                        var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                        metadata.manualSortOrder = index
                        atom = atom.withMetadata(metadata)
                    }
                } catch {
                    print("❌ Dashboard: Failed to persist sort order: \(error)")
                }
            }
        }
    }

    func rescheduleTask(uuid: String, toDate: Date?) async {
        do {
            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                CommandCenterTaskScheduling.reschedule(&metadata, toDate: toDate)
                atom = atom.withMetadata(metadata)
            }
            await refreshTaskCollectionsAfterMutation()
        } catch {
            print("❌ Dashboard: Failed to reschedule task: \(error)")
        }
    }

    func rescheduleTasks(uuids: [String], toDate: Date?) async {
        for uuid in uuids {
            do {
                _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                    var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                    CommandCenterTaskScheduling.reschedule(&metadata, toDate: toDate)
                    atom = atom.withMetadata(metadata)
                }
            } catch {
                print("❌ Dashboard: Failed to reschedule task: \(error)")
            }
        }
        await refreshTaskCollectionsAfterMutation()
    }

    func shiftUpcomingWeek(by offset: Int) {
        shiftUpcomingRange(by: offset)
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
        upcomingCalendarScope = .week

        upcomingAnchorDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: offset * 7, to: upcomingAnchorDate) ?? upcomingAnchorDate
        )
        selectedDate = upcomingAnchorDate
        syncUpcomingWeekOffset()
        Task { await loadUpcomingTasks() }
    }

    private func syncUpcomingWeekOffset() {
        let calendar = Calendar.current
        let today = CommandCenterCalendarLayout.mondayStartingWeek(containing: Date(), calendar: calendar)
        let selected = CommandCenterCalendarLayout.mondayStartingWeek(containing: upcomingAnchorDate, calendar: calendar)
        let daysDiff = calendar.dateComponents([.day], from: today, to: selected).day ?? 0
        upcomingWeekOffset = daysDiff / 7
    }

    // MARK: - Completed Tasks

    func loadCompletedTasks() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: Date())

            // Collect ALL completed tasks
            let allCompleted = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                guard vm.isCompleted else { return nil }
                guard vm.completedAt != nil else { return nil }
                return vm
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

    func loadAnytimeTasks() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)
            let anytimeCandidates = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                guard !vm.isCompleted else { return nil }
                // Anytime owns unscheduled work: explicit anytime, no scheduling bucket, or a day-only plan without a calendar time.
                let meta = atom.metadataValue(as: TaskMetadata.self)
                let state = meta?.schedulingState
                if state == "someday" { return nil }
                if meta?.recurrence != nil, meta?.recurrenceParentUUID == nil { return nil }
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

    func loadSomedayTasks() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)
            let nextSomedayTasks = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                guard !vm.isCompleted else { return nil }
                let meta = atom.metadataValue(as: TaskMetadata.self)
                guard meta?.schedulingState == "someday" else { return nil }
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
            let nextAreas = try await AtomRepository.shared.fetchAll(type: .area)
                .filter { !$0.isDeleted }
                .sorted {
                    let a = $0.metadataValue(as: AreaMetadata.self)?.sortOrder ?? Int.max
                    let b = $1.metadataValue(as: AreaMetadata.self)?.sortOrder ?? Int.max
                    return a < b
                }
            assignIfChanged(\.areas, to: nextAreas)
        } catch {
            print("❌ Dashboard: Failed to load areas: \(error)")
        }
    }

    func loadProjects() async {
        assignIfChanged(\.projects, to: [])
    }

    // MARK: - Things 3 Scheduling Operations

    func setWhenDate(taskUUID: String, date: Date?) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            if let date = date {
                let day = Calendar.current.startOfDay(for: date)
                let dateString = PlannerumFormatters.iso8601.string(from: day)
                let deadline = meta.dueDate
                CommandCenterTaskScheduling.moveCalendarTime(in: &meta, toDate: day)
                meta.whenDate = dateString
                meta.focusDate = dateString  // Keep backward compat
                meta.dueDate = deadline
                meta.schedulingState = nil  // Scheduled tasks have no scheduling state
            } else {
                meta.whenDate = nil
                meta.focusDate = nil
            }
            atom = atom.withMetadata(meta)
            try await AtomRepository.shared.update(atom)
            await refreshTasks()
        } catch {
            print("❌ Dashboard: Failed to set when date: \(error)")
        }
    }

    func setDeadline(taskUUID: String, date: Date?) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            meta.dueDate = date.map { PlannerumFormatters.iso8601.string(from: $0) }
            atom = atom.withMetadata(meta)
            try await AtomRepository.shared.update(atom)
            await refreshTasks()
        } catch {
            print("❌ Dashboard: Failed to set deadline: \(error)")
        }
    }

    func setTimeOfDay(taskUUID: String, value: String?) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            meta.timeOfDay = value
            atom = atom.withMetadata(meta)
            try await AtomRepository.shared.update(atom)
            await refreshTasks()
        } catch {
            print("❌ Dashboard: Failed to set time of day: \(error)")
        }
    }

    func setSchedulingState(taskUUID: String, state: String?) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            meta.schedulingState = state
            if state != nil {
                // Moving to anytime/someday clears the when date
                meta.whenDate = nil
                meta.focusDate = nil
            }
            atom = atom.withMetadata(meta)
            try await AtomRepository.shared.update(atom)
            await refreshTasks()
        } catch {
            print("❌ Dashboard: Failed to set scheduling state: \(error)")
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
            var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            meta.headingUUID = nil
            atom = atom.withMetadata(meta)
            try await AtomRepository.shared.update(atom)
            await refreshTasks()
        } catch {
            print("❌ Dashboard: Failed to move task to project: \(error)")
        }
    }

    func moveTaskToHeading(taskUUID: String, headingUUID: String?) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            meta.headingUUID = headingUUID
            atom = atom.withMetadata(meta)
            try await AtomRepository.shared.update(atom)
            if let projectUUID = selectedProjectUUID {
                await loadProjectTasks(projectUUID: projectUUID)
            }
        } catch {
            print("❌ Dashboard: Failed to move task to heading: \(error)")
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
            headings.removeAll { $0.id == headingUUID }

            // Save back
            let encoded = try JSONEncoder().encode(headings)
            meta.headings = String(data: encoded, encoding: .utf8)
            projectAtom = projectAtom.withMetadata(meta)
            try await AtomRepository.shared.update(projectAtom)

            projectHeadings = headings

            // Clear headingUUID from tasks that referenced this heading
            let tasks = try await AtomRepository.shared.fetchAll(type: .task)
            for var task in tasks {
                let taskMeta = task.metadataValue(as: TaskMetadata.self)
                if taskMeta?.headingUUID == headingUUID {
                    var updatedMeta = taskMeta ?? TaskMetadata()
                    updatedMeta.headingUUID = nil
                    task = task.withMetadata(updatedMeta)
                    try await AtomRepository.shared.update(task)
                }
            }

            await loadProjectTasks(projectUUID: projectUUID)
        } catch {
            print("❌ Dashboard: Failed to delete heading: \(error)")
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
                sourceBreakdown: state.sourceBreakdown,
                isBuiltIn: state.isBuiltIn,
                isEditable: state.isEditable,
                linkedIntentSummary: state.linkedIntentSummary
            )
        }
        assignIfChanged(\.habits, to: nextHabits)
        assignIfChanged(\.currentStreak, to: plannerum.liveQuestEngine.streaks.values.max() ?? 0)
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

    func toggleTaskCompletion(_ task: TaskViewModel) async {
        if task.isCompleted {
            _ = await uncompleteTask(uuid: task.uuid)
        } else {
            _ = await completeTask(uuid: task.uuid)
        }
    }

    func completeTask(uuid: String) async -> Bool {
        // Check if this is a recurring task before completing it
        var isRecurringInstance = false
        var templateUUID: String?
        if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
            let meta = atom.metadataValue(as: TaskMetadata.self)
            if let parentUUID = meta?.recurrenceParentUUID {
                isRecurringInstance = true
                templateUUID = parentUUID
            }
        }

        await plannerum.completeTask(taskId: uuid)
        await habitEngine.recordTaskCompletion(taskUUID: uuid)

        // For recurring tasks: generate next instance immediately
        if isRecurringInstance, let parentUUID = templateUUID {
            await generateNextRecurringInstance(templateUUID: parentUUID)
        }

        await refreshTaskCollectionsAfterMutation()
        await loadHabits()
        return true
    }

    /// Generate the next instance for a recurring template after completion
    private func generateNextRecurringInstance(templateUUID: String) async {
        do {
            guard let template = try await AtomRepository.shared.fetch(uuid: templateUUID),
                  let metadata = template.metadataValue(as: TaskMetadata.self),
                  let recurrenceJSON = metadata.recurrence,
                  let rule = RecurrenceRule.fromJSON(recurrenceJSON) else { return }

            // One-active-instance invariant: bail if another incomplete
            // instance of this template already exists.
            let activeTemplates = try await TaskRecurrenceEngine.shared.batchTemplatesWithActiveInstance()
            if activeTemplates.contains(templateUUID) { return }

            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!

            // Find the next valid occurrence starting from tomorrow
            var candidate = tomorrow
            var attempts = 0
            while attempts < 365 {
                if isValidOccurrence(rule: rule, date: candidate) {
                    let exists = try await TaskRecurrenceEngine.shared.instanceExists(
                        templateUUID: templateUUID, date: candidate
                    )
                    if !exists { break }
                }
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
                attempts += 1
            }

            guard attempts < 365 else { return }

            // Build instance metadata — copy from template + reset completion state
            var instanceMetadata = TaskMetadata()
            instanceMetadata.status = metadata.status ?? "todo"
            instanceMetadata.priority = metadata.priority
            instanceMetadata.color = metadata.color
            instanceMetadata.durationMinutes = metadata.durationMinutes
            instanceMetadata.focusDate = PlannerumFormatters.iso8601.string(from: candidate)
            instanceMetadata.dueDate = PlannerumFormatters.iso8601.string(from: candidate)
            instanceMetadata.whenDate = PlannerumFormatters.iso8601.string(from: candidate)
            instanceMetadata.isCompleted = false
            instanceMetadata.recurrenceParentUUID = templateUUID
            instanceMetadata.description = metadata.description
            instanceMetadata.intent = metadata.intent
            instanceMetadata.intentUUID = metadata.intentUUID
            instanceMetadata.habitUUID = metadata.habitUUID
            instanceMetadata.habitAssignmentSource = metadata.habitAssignmentSource
            instanceMetadata.linkedAtomUUID = metadata.linkedAtomUUID
            instanceMetadata.startTime = metadata.startTime
            instanceMetadata.energyLevel = metadata.energyLevel
            instanceMetadata.cognitiveLoad = metadata.cognitiveLoad
            instanceMetadata.taskType = metadata.taskType
            instanceMetadata.estimatedFocusMinutes = metadata.estimatedFocusMinutes
            instanceMetadata.headingUUID = metadata.headingUUID
            instanceMetadata.titleMentions = metadata.titleMentions
            copyCalendarTime(from: metadata, to: &instanceMetadata, on: candidate)

            // Copy checklist from template with all items unchecked
            if let checklistJSON = metadata.checklist,
               let data = checklistJSON.data(using: .utf8),
               var items = try? JSONDecoder().decode([ChecklistItem].self, from: data) {
                items = items.map { item in
                    ChecklistItem(id: UUID().uuidString, title: item.title, isCompleted: false, sortOrder: item.sortOrder)
                }
                if let encoded = try? JSONEncoder().encode(items),
                   let json = String(data: encoded, encoding: .utf8) {
                    instanceMetadata.checklist = json
                }
            }

            guard let metaData = try? JSONEncoder().encode(instanceMetadata),
                  let metaString = String(data: metaData, encoding: .utf8) else { return }

            let templateLinks = template.linksList.filter { $0.type == "project" }
            let instance = Atom.new(
                type: .task,
                title: template.title,
                body: template.body,
                metadata: metaString,
                links: templateLinks.isEmpty ? nil : templateLinks
            )
            try await AtomRepository.shared.create(instance)
        } catch {
            print("❌ Dashboard: Failed to generate next recurring instance: \(error)")
        }
    }

    private func isValidOccurrence(rule: RecurrenceRule, date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        switch rule.frequency {
        case .daily: return true
        case .weekdays: return weekday >= 2 && weekday <= 6
        case .weekly, .biweekly, .custom:
            if let days = rule.daysOfWeek, !days.isEmpty {
                return days.contains { $0.rawValue == weekday }
            }
            return true
        case .monthly:
            if let day = rule.dayOfMonth {
                return calendar.component(.day, from: date) == day
            }
            return true
        case .yearly: return true
        }
    }

    func uncompleteTask(uuid: String) async -> Bool {
        do {
            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                metadata.isCompleted = false
                metadata.completedAt = nil
                atom = atom.withMetadata(metadata)
            }
            await habitEngine.reverseTaskCompletion(taskUUID: uuid)
            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
            return true
        } catch {
            print("❌ Dashboard: Failed to uncomplete task: \(error)")
            return false
        }
    }

    func addTask() async {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newTaskTitle = ""
        // Parse and create with metadata
        let parsed = TaskInputParser.parse(title)
        await smartAddTask(parsed)
    }

    func smartAddTask(_ parsed: ParsedTaskInput) async {
        let title = parsed.title.isEmpty ? "Untitled Task" : parsed.title
        await plannerum.quickAddTask(title: title)

        // Apply parsed metadata to the newly created task
        // Find the most recently created task with this title
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)
            let recent = atoms
                .filter { $0.title == title }
                .sorted { $0.createdAt > $1.createdAt }
                .first

            if let atom = recent {
                _ = try await AtomRepository.shared.update(uuid: atom.uuid) { a in
                    var metadata = a.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()

                    if let priority = parsed.priority {
                        metadata.priority = priority.rawValue
                    }
                    if let dueDate = parsed.dueDate ?? pendingTaskDate {
                        let dateStr = PlannerumFormatters.iso8601.string(from: dueDate)
                        metadata.dueDate = dateStr
                        metadata.focusDate = dateStr  // Keep focusDate in sync so task appears on the correct day
                    } else if viewMode == .today {
                        metadata.schedulingState = "anytime"
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
                        metadata.dueDate = PlannerumFormatters.iso8601.string(from: deadline)
                    }

                    // Set whenDate from dueDate if we have one (new semantic)
                    if metadata.schedulingState == nil, let focusDate = metadata.focusDate {
                        metadata.whenDate = focusDate
                    }

                    a = a.withMetadata(metadata)

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

                    // Heading assignment from context
                    if let headingUUID = parsed.contextHeadingUUID {
                        metadata.headingUUID = headingUUID
                        a = a.withMetadata(metadata)
                    }

                    // Title mentions from @ picker
                    if !parsed.mentions.isEmpty {
                        if let encoded = try? JSONEncoder().encode(parsed.mentions),
                           let json = String(data: encoded, encoding: .utf8) {
                            metadata.titleMentions = json
                            a = a.withMetadata(metadata)
                        }
                    }
                }

                if let recurrenceRule = parsed.recurrenceRule {
                    await setTaskRecurrence(uuid: atom.uuid, rule: recurrenceRule)
                }
            }
        } catch {
            print("❌ Dashboard: Failed to enrich new task: \(error)")
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
    }

    func updateTask(
        uuid: String,
        title: String? = nil,
        priority: TaskPriority? = nil,
        dueDate: Date? = nil,
        scheduledTime: Date? = nil,
        intent: TaskIntent? = nil,
        intentUUID: String? = nil,
        body: String? = nil
    ) async {
        do {
            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                let previousAssignmentSource = HabitAssignmentSource(rawValue: metadata.habitAssignmentSource ?? "")

                if let title = title { atom.title = title }
                if let body = body { atom.body = body }
                if let priority = priority { metadata.priority = priority.rawValue }
                if let dueDate = dueDate {
                    let dateString = PlannerumFormatters.iso8601.string(from: dueDate)
                    metadata.dueDate = dateString
                    metadata.focusDate = dateString
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

                atom = atom.withMetadata(metadata)
            }
            await refreshTasks()
            await loadHabits()
        } catch {
            print("❌ Dashboard: Failed to update task: \(error)")
        }
    }

    func updateRecurringTaskTitle(
        uuid: String,
        title: String,
        scope: RecurringTaskTitleEditScope
    ) async {
        do {
            guard let current = try await AtomRepository.shared.fetch(uuid: uuid) else { return }
            let currentMetadata = current.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()

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
                    var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                    applyRecurringTitle(title, to: &atom, metadata: &metadata)
                    atom = atom.withMetadata(metadata)
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

            if calendarService.hasCalendarAccess,
               let eventId = try? await calendarService.createCosmoEvent(
                title: title.isEmpty ? "New Event" : title,
                start: normalized.start,
                end: normalized.end
               ) {
                metadata.calendarEventId = eventId
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
                var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                applyCalendarTimeRange(start: normalized.start, end: normalized.end, to: &metadata)

                if let title { atom.title = title.isEmpty ? "New Event" : title }
                if let body { atom.body = body.isEmpty ? nil : body }
                calendarEventId = metadata.calendarEventId
                atom = atom.withMetadata(metadata)
            }

            if calendarService.hasCalendarAccess {
                let resolvedTitle: String
                if let title, !title.isEmpty {
                    resolvedTitle = title
                } else {
                    resolvedTitle = try await AtomRepository.shared.fetch(uuid: uuid)?.title ?? "New Event"
                }

                if let calendarEventId {
                    try? await calendarService.updateCosmoEvent(
                        eventId: calendarEventId,
                        title: resolvedTitle,
                        start: normalized.start,
                        end: normalized.end
                    )
                } else if let newEventId = try? await calendarService.createCosmoEvent(
                    title: resolvedTitle,
                    start: normalized.start,
                    end: normalized.end
                ) {
                    _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                        var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                        metadata.calendarEventId = newEventId
                        atom = atom.withMetadata(metadata)
                    }
                }
            }

            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
        } catch {
            print("❌ Dashboard: Failed to update calendar time block: \(error)")
        }
    }

    func updateAllDayTask(uuid: String, title: String? = nil, body: String? = nil, date: Date) async {
        do {
            let day = Calendar.current.startOfDay(for: date)
            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
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

                if let title { atom.title = title.isEmpty ? "New Event" : title }
                if let body { atom.body = body.isEmpty ? nil : body }
                atom = atom.withMetadata(metadata)
            }
            await refreshTaskCollectionsAfterMutation()
            await loadHabits()
        } catch {
            print("❌ Dashboard: Failed to update all-day task: \(error)")
        }
    }

    func clearCalendarTimeBlock(uuid: String) async {
        do {
            var calendarEventId: String?
            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                calendarEventId = metadata.calendarEventId
                metadata.startTime = nil
                metadata.endTime = nil
                metadata.durationMinutes = nil
                metadata.scheduledStart = nil
                metadata.scheduledEnd = nil
                metadata.calendarEventId = nil
                atom = atom.withMetadata(metadata)
            }

            if calendarService.hasCalendarAccess, let calendarEventId {
                try? await calendarService.deleteCosmoEvent(eventId: calendarEventId)
            }

            await refreshTaskCollectionsAfterMutation()
        } catch {
            print("❌ Dashboard: Failed to clear calendar time block: \(error)")
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

    private func copyCalendarTime(from source: TaskMetadata, to destination: inout TaskMetadata, on date: Date) {
        let startSource = source.scheduledStart ?? source.startTime
        guard let startSource, let sourceStart = PlannerumFormatters.iso8601.date(from: startSource) else { return }

        let endSource = source.scheduledEnd ?? source.endTime
        let sourceEnd = endSource.flatMap { PlannerumFormatters.iso8601.date(from: $0) }
        let duration = sourceEnd.map { max(15, Int($0.timeIntervalSince(sourceStart) / 60)) }
            ?? source.durationMinutes
            ?? source.estimatedFocusMinutes
            ?? 30

        let start = merge(date: date, time: sourceStart)
        let end = Calendar.current.date(byAdding: .minute, value: duration, to: start)
            ?? start.addingTimeInterval(TimeInterval(duration * 60))
        applyCalendarTimeRange(start: start, end: end, to: &destination)
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
                        var parentMetadata = parent.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                        parentMetadata.recurrence = recurrenceJSON
                        parent = parent.withMetadata(parentMetadata)
                    }
                } else {
                    try await AtomRepository.shared.delete(uuid: parentUUID)
                    _ = try await AtomRepository.shared.update(uuid: uuid) { current in
                        var currentMetadata = current.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                        currentMetadata.recurrenceParentUUID = nil
                        current = current.withMetadata(currentMetadata)
                    }
                }
            } else if metadata.recurrence != nil {
                _ = try await AtomRepository.shared.update(uuid: uuid) { current in
                    var currentMetadata = current.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                    currentMetadata.recurrence = recurrenceJSON
                    current = current.withMetadata(currentMetadata)
                }
            } else if let recurrenceJSON {
                let template = try await createRecurringTemplate(from: atom, recurrenceJSON: recurrenceJSON)
                _ = try await AtomRepository.shared.update(uuid: uuid) { current in
                    var currentMetadata = current.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                    currentMetadata.recurrence = nil
                    currentMetadata.recurrenceParentUUID = template.uuid
                    current = current.withMetadata(currentMetadata)
                }
            }

            await refreshTaskCollectionsAfterMutation()
        } catch {
            print("❌ Dashboard: Failed to update recurrence: \(error)")
        }
    }

    private func createRecurringTemplate(from atom: Atom, recurrenceJSON: String) async throws -> Atom {
        var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
        metadata.recurrence = recurrenceJSON
        metadata.recurrenceParentUUID = nil
        metadata.isCompleted = false
        metadata.completedAt = nil

        if metadata.dueDate == nil {
            let today = PlannerumFormatters.iso8601.string(from: Date())
            metadata.dueDate = today
            metadata.focusDate = today
        }

        let template = Atom.new(
            type: .task,
            title: atom.title,
            body: atom.body,
            metadata: atom.withMetadata(metadata).metadata,
            links: atom.linksList.isEmpty ? nil : atom.linksList
        )

        return try await AtomRepository.shared.create(template)
    }

    func deleteTask(uuid: String) async {
        do {
            let calendarEventId = try await AtomRepository.shared.fetch(uuid: uuid)?
                .metadataValue(as: TaskMetadata.self)?
                .calendarEventId
            try await AtomRepository.shared.delete(uuid: uuid)
            if calendarService.hasCalendarAccess, let calendarEventId {
                try? await calendarService.deleteCosmoEvent(eventId: calendarEventId)
            }
            await refreshTaskCollectionsAfterMutation()
        } catch {
            print("❌ Dashboard: Failed to delete task: \(error)")
        }
    }

    func deleteMultipleTasks(uuids: Set<String>) async {
        for uuid in uuids {
            do {
                try await AtomRepository.shared.delete(uuid: uuid)
            } catch {
                print("❌ Dashboard: Failed to delete task \(uuid): \(error)")
            }
        }
        await refreshTaskCollectionsAfterMutation()
    }

    func startFocusSession(for task: TaskViewModel) {
        let habit = resolvedHabit(for: task)
        let intentPresentation = resolvedIntentPresentation(for: task)
        sessionEngine.startSession(
            taskUUID: task.uuid,
            taskTitle: task.title,
            intent: behaviorIntent(for: task),
            intentUUID: intentPresentation.definitionID,
            intentTitleSnapshot: intentPresentation.isUnassigned ? nil : intentPresentation.title,
            habitUUID: habit?.id,
            habitTitleSnapshot: habit?.title,
            plannedMinutes: task.estimatedMinutes
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
                guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                      let startedStr = Optional(metadata.startedAt),
                      let startedDate = PlannerumFormatters.iso8601.date(from: startedStr),
                      startedDate >= todayStart else { continue }

                let minutes = metadata.actualMinutes ?? metadata.plannedMinutes
                totalMinutes += minutes

                let summary = intentSummary(intentUUID: metadata.intentUUID, legacyIntentRaw: metadata.intent, minutes: 0)
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
                guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                      let startedDate = PlannerumFormatters.iso8601.date(from: metadata.startedAt),
                      startedDate >= todayStart else { return nil }

                let actualMinutes = metadata.actualMinutes ?? metadata.plannedMinutes
                let endDate = metadata.endedAt.flatMap { PlannerumFormatters.iso8601.date(from: $0) }
                    ?? startedDate.addingTimeInterval(TimeInterval(actualMinutes * 60))

                let intent = resolvedIntentPresentation(intentUUID: metadata.intentUUID, legacyIntentRaw: metadata.intent)

                return SessionTimelineEntry(
                    id: atom.uuid,
                    title: atom.title ?? "Focus Session",
                    intent: intent,
                    habitTitle: metadata.habitTitleSnapshot,
                    startTime: startedDate,
                    endTime: endDate,
                    focusScore: metadata.focusScore ?? 100,
                    taskUUID: metadata.taskUUID
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
                guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                      let startedDate = PlannerumFormatters.iso8601.date(from: metadata.startedAt) else { continue }

                let minutes = metadata.actualMinutes ?? metadata.plannedMinutes
                let dayStart = calendar.startOfDay(for: startedDate)

                if startedDate >= weekStart {
                    thisWeekMinutes += minutes

                    if var bucket = dayBuckets[dayStart] {
                        bucket.minutes += minutes
                        if let score = metadata.focusScore { bucket.focusScores.append(Double(score)) }
                        bucket.sessions += 1
                        let summary = intentSummary(intentUUID: metadata.intentUUID, legacyIntentRaw: metadata.intent)
                        var updated = bucket.intents[summary.id] ?? summary
                        updated.minutes += minutes
                        bucket.intents[summary.id] = updated
                        dayBuckets[dayStart] = bucket
                    }
                } else if startedDate >= previousWeekStart {
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
                guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                      let startedDate = PlannerumFormatters.iso8601.date(from: metadata.startedAt) else { continue }

                let minutes = metadata.actualMinutes ?? metadata.plannedMinutes
                let dayStart = calendar.startOfDay(for: startedDate)

                if startedDate >= monthStart && startedDate <= monthEnd.addingTimeInterval(86400) {
                    thisMonthMinutes += minutes
                    if var bucket = dayBuckets[dayStart] {
                        bucket.minutes += minutes
                        if let score = metadata.focusScore { bucket.focusScores.append(Double(score)) }
                        bucket.sessions += 1
                        let summary = intentSummary(intentUUID: metadata.intentUUID, legacyIntentRaw: metadata.intent)
                        var updated = bucket.intents[summary.id] ?? summary
                        updated.minutes += minutes
                        bucket.intents[summary.id] = updated
                        dayBuckets[dayStart] = bucket
                    }
                } else if startedDate >= prevMonthStart && startedDate < monthStart {
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
        let formatter = DateFormatter()

        switch selectedReportTab {
        case .week:
            let today = calendar.startOfDay(for: Date())
            let weekStart = calendar.date(byAdding: .day, value: reportWeekOffset * 7 - 6, to: today)!
            let weekEnd = calendar.date(byAdding: .day, value: reportWeekOffset * 7, to: today)!
            formatter.dateFormat = "MMM d"
            let start = formatter.string(from: weekStart)
            let end = formatter.string(from: weekEnd)
            formatter.dateFormat = ", yyyy"
            let year = formatter.string(from: weekEnd)
            return "\(start) – \(end)\(year)"
        case .month:
            guard let targetMonth = calendar.date(byAdding: .month, value: reportMonthOffset, to: Date()) else { return "" }
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: targetMonth)
        case .habits:
            if reportWeekOffset == 0 { return "This Week" }
            let today = calendar.startOfDay(for: Date())
            let weekStart = calendar.date(byAdding: .day, value: reportWeekOffset * 7 - 6, to: today)!
            let weekEnd = calendar.date(byAdding: .day, value: reportWeekOffset * 7, to: today)!
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: weekStart)) – \(formatter.string(from: weekEnd))"
        }
    }

    func notifyCompletedTaskArrival() {
        completedArrivalToken += 1
    }

    private func refreshTaskCollectionsAfterMutation() async {
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
        case .someday:
            await loadSomedayTasks()
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
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMMM d"
        return formatter.string(from: selectedDate)
    }

    var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var activeTaskCount: Int {
        todayActiveCount
    }

    // Legacy compatibility
    var filteredTasks: [TaskViewModel] {
        currentVisibleTasks
    }
}
