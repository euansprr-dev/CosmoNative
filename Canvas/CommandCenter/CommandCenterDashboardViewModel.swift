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
                let isDue = vm.dueDate.map { calendar.isDateInToday($0) } ?? false
                let isScheduled = vm.scheduledDate.map { calendar.isDateInToday($0) } ?? false
                let isWhen = vm.whenDate.map { calendar.isDateInToday($0) } ?? false
                if isDue || isScheduled || isWhen || vm.isOverdue { return vm }
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

    var upcomingWeekStart: Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: upcomingWeekOffset * 7, to: today) ?? today
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

    // MARK: - Time Tracking

    @Published var todayTrackedMinutes: Int = 0
    @Published var todaySessionsByIntent: [TaskIntent: Int] = [:]
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
    private var cancellables = Set<AnyCancellable>()

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

    init() {
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
                        // Navigate the board to the week containing selected date
                        let calendar = Calendar.current
                        let today = calendar.startOfDay(for: Date())
                        let selected = calendar.startOfDay(for: self.selectedDate)
                        let daysDiff = calendar.dateComponents([.day], from: today, to: selected).day ?? 0
                        self.upcomingWeekOffset = daysDiff / 7
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
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshTasks()
                    if self?.viewMode == .logbook {
                        await self?.loadCompletedTasks()
                    }
                }
            }
            .store(in: &cancellables)

        AtomRepository.shared.$atoms
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadHabits()
                    await self?.loadWeeklyReport()
                    await self?.loadTodaySessions()
                    await self?.loadTodayTimeData()
                }
            }
            .store(in: &cancellables)

        habitEngine.$definitions
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadHabits()
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
            }
            .store(in: &cancellables)
    }

    // MARK: - Refresh

    func refreshAll() async {
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

    // MARK: - Task Loading (Today view — sectioned)

    func refreshTasks() async {
        let isToday = Calendar.current.isDateInToday(selectedDate)
        var allTasks: [TaskViewModel] = []

        if isToday {
            await plannerum.loadTodayTasks()
            allTasks = plannerum.todayTasks
        } else {
            do {
                let atoms = try await AtomRepository.shared.fetchAll(type: .task)
                let dayStart = Calendar.current.startOfDay(for: selectedDate)
                let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

                allTasks = atoms.compactMap { atom -> TaskViewModel? in
                    guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                    if vm.isRecurring && vm.recurrenceParentUUID == nil { return nil }

                    let isDue = vm.dueDate.map { $0 >= dayStart && $0 < dayEnd } ?? false
                    let isScheduled = vm.scheduledDate.map { $0 >= dayStart && $0 < dayEnd } ?? false

                    // Only show tasks actually due/scheduled on this date (no overdue spillover for future dates)
                    if isDue || isScheduled { return vm }
                    return nil
                }
            } catch {
                print("❌ Dashboard: Failed to load tasks for date: \(error)")
            }
        }

        // Partition into sections
        let active = allTasks.filter { !$0.isCompleted }

        overdueTasks = active
            .filter { $0.isOverdue }
            .sorted { lhs, rhs in
                if let lo = lhs.manualSortOrder, let ro = rhs.manualSortOrder { return lo < ro }
                if lhs.manualSortOrder != nil { return true }
                if rhs.manualSortOrder != nil { return false }
                return lhs.priority.sortOrder < rhs.priority.sortOrder
            }

        scheduledTasks = active
            .filter { !$0.isOverdue && $0.hasSpecificTime }
            .sorted { lhs, rhs in
                if let lo = lhs.manualSortOrder, let ro = rhs.manualSortOrder { return lo < ro }
                if lhs.manualSortOrder != nil { return true }
                if rhs.manualSortOrder != nil { return false }
                return (lhs.scheduledTime ?? .distantFuture) < (rhs.scheduledTime ?? .distantFuture)
            }

        unscheduledTasks = active
            .filter { !$0.isOverdue && !$0.hasSpecificTime }
            .sorted { lhs, rhs in
                if let lo = lhs.manualSortOrder, let ro = rhs.manualSortOrder { return lo < ro }
                if lhs.manualSortOrder != nil { return true }
                if rhs.manualSortOrder != nil { return false }
                return lhs.priority.sortOrder < rhs.priority.sortOrder
            }

        // Load completed tasks independently (todayTasks excludes completed)
        await loadCompletedTasks()
    }

    // MARK: - Upcoming Tasks

    func loadUpcomingTasks() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let weekStart = upcomingWeekStart

            // Build day groups for 7 days from weekStart
            var dayGroups: [UpcomingDayViewModel] = []

            for dayOffset in 0..<7 {
                let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

                let dayTasks = atoms.compactMap { atom -> TaskViewModel? in
                    guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                    if vm.isCompleted { return nil }
                    if vm.isRecurring && vm.recurrenceParentUUID == nil { return nil }

                    // Exclude overdue tasks from day columns — they appear in the overdue column
                    if vm.isOverdue { return nil }

                    let isDue = vm.dueDate.map { $0 >= dayStart && $0 < dayEnd } ?? false
                    let isScheduled = vm.scheduledDate.map { $0 >= dayStart && $0 < dayEnd } ?? false

                    if isDue || isScheduled { return vm }
                    return nil
                }
                .sorted {
                    if $0.priority.sortOrder != $1.priority.sortOrder {
                        return $0.priority.sortOrder < $1.priority.sortOrder
                    }
                    return ($0.scheduledTime ?? .distantFuture) < ($1.scheduledTime ?? .distantFuture)
                }

                dayGroups.append(UpcomingDayViewModel(date: dayStart, tasks: dayTasks))
            }

            // Collect overdue tasks (only when viewing current week)
            if upcomingWeekOffset == 0 {
                let overdue = atoms.compactMap { atom -> TaskViewModel? in
                    guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                    if vm.isCompleted { return nil }
                    if vm.isRecurring && vm.recurrenceParentUUID == nil { return nil }
                    guard let due = vm.dueDate, due < today else { return nil }
                    return vm
                }
                .sorted { $0.priority.sortOrder < $1.priority.sortOrder }

                overdueTasks = overdue
            } else {
                overdueTasks = []
            }

            upcomingDayGroups = dayGroups
            loadUpcomingCalendarEvents()
        } catch {
            print("❌ Dashboard: Failed to load upcoming tasks: \(error)")
        }
    }

    private func loadUpcomingCalendarEvents() {
        let calendar = Calendar.current
        let weekStart = upcomingWeekStart
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        let events = calendarService.externalEvents
            .filter { $0.startDate >= weekStart && $0.startDate < weekEnd }

        var grouped: [String: [CalendarEvent]] = [:]
        for event in events {
            let key = calendar.startOfDay(for: event.startDate).formatted(.iso8601.year().month().day())
            grouped[key, default: []].append(event)
        }
        // Sort events within each day
        for key in grouped.keys {
            grouped[key]?.sort { $0.startDate < $1.startDate }
        }
        upcomingCalendarEvents = grouped
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
                let dateString = toDate.map { PlannerumFormatters.iso8601.string(from: $0) }
                metadata.dueDate = dateString
                metadata.focusDate = dateString
                metadata.whenDate = dateString
                metadata.schedulingState = nil
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
                    let dateString = toDate.map { PlannerumFormatters.iso8601.string(from: $0) }
                    metadata.dueDate = dateString
                    metadata.focusDate = dateString
                    metadata.whenDate = dateString
                    metadata.schedulingState = nil
                    atom = atom.withMetadata(metadata)
                }
            } catch {
                print("❌ Dashboard: Failed to reschedule task: \(error)")
            }
        }
        await refreshTaskCollectionsAfterMutation()
    }

    func shiftUpcomingWeek(by offset: Int) {
        upcomingWeekOffset += offset
        Task { await loadUpcomingTasks() }
    }

    func resetUpcomingToToday() {
        upcomingWeekOffset = 0
        Task { await loadUpcomingTasks() }
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
            completedTodayTasks = allCompleted
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
            completedTasksByDay = grouped
                .map { (date: $0.key, tasks: $0.value.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) }
                .sorted { $0.date > $1.date }
        } catch {
            print("❌ Dashboard: Failed to load completed tasks: \(error)")
        }
    }

    // MARK: - Anytime Tasks

    func loadAnytimeTasks() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)
            anytimeTasks = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                guard !vm.isCompleted else { return nil }
                // Anytime: schedulingState == "anytime" OR (no whenDate and no schedulingState)
                let meta = atom.metadataValue(as: TaskMetadata.self)
                let state = meta?.schedulingState
                let when = meta?.whenDate
                if state == "anytime" || (state == nil && when == nil && meta?.focusDate == nil) {
                    return vm
                }
                return nil
            }
            .sorted { ($0.manualSortOrder ?? Int.max) < ($1.manualSortOrder ?? Int.max) }
        } catch {
            print("❌ Dashboard: Failed to load anytime tasks: \(error)")
        }
    }

    // MARK: - Someday Tasks

    func loadSomedayTasks() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .task)
            somedayTasks = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                guard !vm.isCompleted else { return nil }
                let meta = atom.metadataValue(as: TaskMetadata.self)
                guard meta?.schedulingState == "someday" else { return nil }
                return vm
            }
            .sorted { ($0.manualSortOrder ?? Int.max) < ($1.manualSortOrder ?? Int.max) }
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
            projectTasks = atoms.compactMap { atom -> TaskViewModel? in
                guard let vm = TaskViewModel.from(atom: atom) else { return nil }
                // Check if task is linked to this project via AtomLinks
                let links = atom.linksList
                let isLinked = links.contains { $0.type == "project" && $0.uuid == projectUUID }
                guard isLinked else { return nil }
                return vm
            }
            .sorted { ($0.manualSortOrder ?? Int.max) < ($1.manualSortOrder ?? Int.max) }
        } catch {
            print("❌ Dashboard: Failed to load project tasks: \(error)")
        }
    }

    // MARK: - Areas & Projects Loading

    func loadAreas() async {
        do {
            areas = try await AtomRepository.shared.fetchAll(type: .area)
                .filter { !$0.isDeleted }
                .sorted {
                    let a = $0.metadataValue(as: AreaMetadata.self)?.sortOrder ?? Int.max
                    let b = $1.metadataValue(as: AreaMetadata.self)?.sortOrder ?? Int.max
                    return a < b
                }
        } catch {
            print("❌ Dashboard: Failed to load areas: \(error)")
        }
    }

    func loadProjects() async {
        do {
            projects = try await AtomRepository.shared.fetchAll(type: .project)
                .filter { !$0.isDeleted }
                .filter { ($0.metadataValue(as: ProjectMetadata.self)?.isCompleted ?? false) == false }
        } catch {
            print("❌ Dashboard: Failed to load projects: \(error)")
        }
    }

    // MARK: - Things 3 Scheduling Operations

    func setWhenDate(taskUUID: String, date: Date?) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: taskUUID) else { return }
            var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            if let date = date {
                meta.whenDate = PlannerumFormatters.iso8601.string(from: date)
                meta.focusDate = meta.whenDate  // Keep backward compat
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

        todayEvents = calendarService.externalEvents
            .filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Habits

    func loadHabits() async {
        let progressStates = await habitEngine.loadProgressStates()
        habits = progressStates.map { state in
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
        currentStreak = plannerum.liveQuestEngine.streaks.values.max() ?? 0
    }

    var availableHabitDefinitions: [HabitDefinition] {
        habitEngine.activeDefinitions
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
        allowManualCompletion: Bool
    ) async {
        await habitEngine.createHabit(
            title: title,
            icon: icon,
            accentColor: accentColor,
            dailyTargetCount: dailyTargetCount,
            keywordTriggers: keywordTriggers,
            mappedIntents: mappedIntents,
            allowManualCompletion: allowManualCompletion
        )
        await loadHabits()
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
                        // Default to today when adding from the Today tab with no explicit date
                        metadata.dueDate = PlannerumFormatters.iso8601.string(from: Date())
                    }
                    if let time = parsed.scheduledTime {
                        metadata.startTime = PlannerumFormatters.iso8601.string(from: time)
                    }
                    if let intent = parsed.intent {
                        metadata.intent = intent.rawValue
                    }
                    if let habitUUID = parsed.habitUUID {
                        metadata.habitUUID = habitUUID
                        metadata.habitAssignmentSource = parsed.habitAssignmentSource?.rawValue
                    } else if let derived = habitEngine.resolveHabit(title: title, intent: parsed.intent) {
                        metadata.habitUUID = derived.definition.id
                        metadata.habitAssignmentSource = derived.source.rawValue
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
        await loadHabits()
    }

    func updateTask(
        uuid: String,
        title: String? = nil,
        priority: TaskPriority? = nil,
        dueDate: Date? = nil,
        scheduledTime: Date? = nil,
        intent: TaskIntent? = nil,
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

                if previousAssignmentSource != .manual {
                    let resolvedTitle = title ?? atom.title ?? ""
                    let resolvedIntent = intent ?? metadata.intent.flatMap(TaskIntent.init(rawValue:))
                    if let derived = habitEngine.resolveHabit(title: resolvedTitle, intent: resolvedIntent) {
                        metadata.habitUUID = derived.definition.id
                        metadata.habitAssignmentSource = derived.source.rawValue
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

            await refreshTasks()
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
            try await AtomRepository.shared.delete(uuid: uuid)
            await refreshTasks()
            if viewMode == .upcoming {
                await loadUpcomingTasks()
            }
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
        await refreshTasks()
        if viewMode == .upcoming {
            await loadUpcomingTasks()
        }
        if viewMode == .logbook {
            await loadCompletedTasks()
        }
    }

    func startFocusSession(for task: TaskViewModel) {
        let habit = resolvedHabit(for: task)
        sessionEngine.startSession(
            taskUUID: task.uuid,
            taskTitle: task.title,
            intent: task.intent,
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
                        "intent": task.intent.rawValue,
                        "paneAtomUUIDs": panes.map(\.atomUUID),
                        "paneAtomTypes": panes.map(\.atomType)
                    ] as [String: Any]
                )
            }
        } else {
            // Legacy fallback — use old single-UUID fields
            switch task.intent {
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
            var intentMinutes: [TaskIntent: Int] = [:]

            for atom in atoms {
                guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                      let startedStr = Optional(metadata.startedAt),
                      let startedDate = PlannerumFormatters.iso8601.date(from: startedStr),
                      startedDate >= todayStart else { continue }

                let minutes = metadata.actualMinutes ?? metadata.plannedMinutes
                totalMinutes += minutes

                let intent = metadata.intent.flatMap { TaskIntent(rawValue: $0) } ?? .general
                intentMinutes[intent, default: 0] += minutes
            }

            todayTrackedMinutes = totalMinutes
            todaySessionsByIntent = intentMinutes
        } catch {
            print("❌ Dashboard: Failed to load time data: \(error)")
        }
    }

    func loadTodaySessions() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .deepWorkBlock)
            let todayStart = Calendar.current.startOfDay(for: Date())

            todaySessions = atoms.compactMap { atom -> SessionTimelineEntry? in
                guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                      let startedDate = PlannerumFormatters.iso8601.date(from: metadata.startedAt),
                      startedDate >= todayStart else { return nil }

                let actualMinutes = metadata.actualMinutes ?? metadata.plannedMinutes
                let endDate = metadata.endedAt.flatMap { PlannerumFormatters.iso8601.date(from: $0) }
                    ?? startedDate.addingTimeInterval(TimeInterval(actualMinutes * 60))

                let intent = metadata.intent.flatMap { TaskIntent(rawValue: $0) } ?? .general

                return SessionTimelineEntry(
                    id: atom.uuid,
                    title: atom.title ?? "Focus Session",
                    intent: intent,
                    startTime: startedDate,
                    endTime: endDate,
                    focusScore: metadata.focusScore ?? 100,
                    taskUUID: metadata.taskUUID
                )
            }
            .sorted { $0.startTime < $1.startTime }
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

            // Build 7-day window (Mon-Sun or today-6..today)
            let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart)!
            let previousWeekStart = calendar.date(byAdding: .day, value: -13, to: todayStart)!

            // Collect sessions for this week and previous week
            var thisWeekMinutes = 0
            var previousWeekMinutes = 0
            var dayBuckets: [Date: (minutes: Int, focusScores: [Double], tasks: Int, sessions: Int, intents: [TaskIntent: Int])] = [:]

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
                        let intent = metadata.intent.flatMap { TaskIntent(rawValue: $0) } ?? .general
                        bucket.intents[intent, default: 0] += minutes
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
            var intentDistribution: [TaskIntent: Int] = [:]

            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
                let dayStart = calendar.startOfDay(for: day)
                let bucket = dayBuckets[dayStart] ?? (0, [], 0, 0, [:])

                let avgFocus = bucket.focusScores.isEmpty ? 0.0 : bucket.focusScores.reduce(0, +) / Double(bucket.focusScores.count)
                let dominantIntent = bucket.intents.max(by: { $0.value < $1.value })?.key

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
                for (intent, mins) in bucket.intents {
                    intentDistribution[intent, default: 0] += mins
                }
            }

            let avgFocus = totalFocusScores.isEmpty ? 0.0 : totalFocusScores.reduce(0, +) / Double(totalFocusScores.count)

            weeklyReportData = WeeklyReportData(
                days: days,
                totalMinutes: thisWeekMinutes,
                avgFocusScore: avgFocus,
                tasksCompleted: totalTasksCompleted,
                totalSessions: totalSessions,
                intentDistribution: intentDistribution,
                previousWeekMinutes: previousWeekMinutes
            )
        } catch {
            print("❌ Dashboard: Failed to load weekly report: \(error)")
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

    var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        if hour < 12 {
            timeOfDay = "Good morning"
        } else if hour < 17 {
            timeOfDay = "Good afternoon"
        } else {
            timeOfDay = "Good evening"
        }
        let name = UserDefaults.standard.string(forKey: "userName") ?? "there"
        return "\(timeOfDay), \(name)"
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
