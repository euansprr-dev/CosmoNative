// Canvas/CommandCenter/CommandCenterDashboardViewModel.swift
// Unified state coordinator for the Command Center Dashboard
// March 2026

import SwiftUI
import Combine

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
        case .completed:
            return completedTasksByDay.flatMap { $0.tasks }
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
                    case .completed:
                        await self?.loadCompletedTasks()
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
                    if self?.viewMode == .completed {
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
                atom = atom.withMetadata(metadata)
            }
            await refreshTasks()
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
                    atom = atom.withMetadata(metadata)
                }
            } catch {
                print("❌ Dashboard: Failed to reschedule task: \(error)")
            }
        }
        await refreshTasks()
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
        await plannerum.completeTask(taskId: uuid)
        await habitEngine.recordTaskCompletion(taskUUID: uuid)
        await refreshTaskCollectionsAfterMutation()
        await loadHabits()
        return true
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

                    a = a.withMetadata(metadata)
                }

                if let recurrenceRule = parsed.recurrenceRule {
                    await setTaskRecurrence(uuid: atom.uuid, rule: recurrenceRule)
                }
            }
        } catch {
            print("❌ Dashboard: Failed to enrich new task: \(error)")
        }

        pendingTaskDate = nil
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
        if viewMode == .completed {
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
            plannedMinutes: 0
        )
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
        case .completed:
            await loadCompletedTasks()
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
