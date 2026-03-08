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
    var todayProgress: Double      // 0.0–1.0
    var isTodayComplete: Bool
    var last7Days: [Bool]          // [6 days ago ... today], true = completed
    var consistencyCount: Int      // completed count in last 7 days
    var allowManualComplete: Bool
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
        return Calendar.current.date(byAdding: .day, value: upcomingWeekOffset * 7, to: today)!
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

        // React to quest state changes (for habits) — debounced
        plannerum.liveQuestEngine.$quests
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] quests in
                self?.updateHabits(from: quests)
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
        await refreshTasks()
        refreshCalendarEvents()
        await loadTodayTimeData()
        await loadTodaySessions()
        await loadWeeklyReport()
        updateHabits(from: plannerum.liveQuestEngine.quests)
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
                let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

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
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }

        scheduledTasks = active
            .filter { !$0.isOverdue && $0.hasSpecificTime }
            .sorted { ($0.scheduledTime ?? .distantFuture) < ($1.scheduledTime ?? .distantFuture) }

        unscheduledTasks = active
            .filter { !$0.isOverdue && !$0.hasSpecificTime }
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }

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
        await updateTask(uuid: uuid, dueDate: toDate)
        await loadUpcomingTasks()
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
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        todayEvents = calendarService.externalEvents
            .filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Habits

    private func updateHabits(from quests: [QuestState]) {
        let habitQuests = quests.filter { $0.id != "overachiever" }

        habits = habitQuests.map { quest in
            let streak = plannerum.liveQuestEngine.streaks[quest.id] ?? 0
            let last7 = buildLast7Days(streak: streak, todayComplete: quest.isComplete)

            return HabitState(
                id: quest.id,
                title: habitTitle(for: quest.id),
                iconName: quest.iconName,
                accentColor: quest.accentColor,
                todayProgress: quest.progress,
                isTodayComplete: quest.isComplete,
                last7Days: last7,
                consistencyCount: last7.filter { $0 }.count,
                allowManualComplete: quest.allowManualComplete
            )
        }

        currentStreak = plannerum.liveQuestEngine.streaks.values.max() ?? 0
    }

    private func habitTitle(for questId: String) -> String {
        switch questId {
        case "deepFocus":        return "Deep Focus"
        case "dailyReflection":  return "Journal"
        case "taskCrusher":      return "Tasks Done"
        case "creativeBurst":    return "Create"
        case "heartHealth":      return "Exercise"
        default:                 return questId.capitalized
        }
    }

    private func buildLast7Days(streak: Int, todayComplete: Bool) -> [Bool] {
        var days = [Bool](repeating: false, count: 7)
        days[6] = todayComplete
        let pastStreak = todayComplete ? max(streak - 1, 0) : streak
        for i in 0..<min(pastStreak, 6) {
            days[5 - i] = true
        }
        return days
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
        await refreshTaskCollectionsAfterMutation()
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
            await refreshTaskCollectionsAfterMutation()
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

                    a = a.withMetadata(metadata)
                }
            }
        } catch {
            print("❌ Dashboard: Failed to enrich new task: \(error)")
        }

        pendingTaskDate = nil
        await refreshTasks()
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

                if let title = title { atom.title = title }
                if let body = body { atom.body = body }
                if let priority = priority { metadata.priority = priority.rawValue }
                if let dueDate = dueDate {
                    metadata.dueDate = PlannerumFormatters.iso8601.string(from: dueDate)
                }
                if let time = scheduledTime {
                    metadata.startTime = PlannerumFormatters.iso8601.string(from: time)
                }
                if let intent = intent {
                    metadata.intent = intent.rawValue
                }

                atom = atom.withMetadata(metadata)
            }
            await refreshTasks()
        } catch {
            print("❌ Dashboard: Failed to update task: \(error)")
        }
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
        sessionEngine.startSession(
            taskUUID: task.uuid,
            taskTitle: task.title,
            intent: task.intent,
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
