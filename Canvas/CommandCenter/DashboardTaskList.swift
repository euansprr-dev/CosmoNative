// Canvas/CommandCenter/DashboardTaskList.swift
// Todoist-style sectioned task list with priority bars, due chips, and inline play
// March 2026

import SwiftUI

struct DashboardTaskList: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State var expandedTaskId: String?
    @State private var selectedTaskUUIDs: Set<String> = []
    @State private var completionStates: [String: CommandCenterTaskCompletionState] = [:]
    @State private var showOverdueRescheduleMenu = false
    @State private var activeTaskMenuUUID: String?
    @State private var hoveredTaskUUID: String?
    @State private var draggedTaskUUID: String?
    @State private var dropTargetTaskUUID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                switch viewModel.viewMode {
                case .today:
                    todayView
                case .upcoming:
                    upcomingView
                case .completed:
                    completedView
                }
            }
        }
    }

    // MARK: - Today View

    @ViewBuilder
    private var todayView: some View {
        // Batch action bar
        if !selectedTaskUUIDs.isEmpty {
            batchActionBar
        }

        // Overdue section
        if !viewModel.overdueTasks.isEmpty {
            taskSection(
                title: "Overdue",
                tasks: viewModel.overdueTasks,
                headerColor: PlannerumColors.overdue,
                showReschedule: true,
                section: .overdue
            )
        }

        // Scheduled section
        if !viewModel.scheduledTasks.isEmpty {
            taskSection(
                title: "Scheduled",
                tasks: viewModel.scheduledTasks,
                headerColor: DS.textSecondary,
                section: .scheduled
            )
        }

        // Unscheduled section
        taskSection(
            title: viewModel.overdueTasks.isEmpty && viewModel.scheduledTasks.isEmpty
                ? "Tasks" : "Unscheduled",
            tasks: viewModel.unscheduledTasks,
            headerColor: DS.textSecondary,
            showAddRow: true,
            section: .unscheduled
        )

        // Empty state
        if viewModel.overdueTasks.isEmpty && viewModel.scheduledTasks.isEmpty
            && viewModel.unscheduledTasks.isEmpty
        {
            emptyState(message: "All clear for today", icon: "checkmark.circle")
        }
    }

    // MARK: - Upcoming View

    @ViewBuilder
    private var upcomingView: some View {
        UpcomingBoardView(viewModel: viewModel)
    }

    // MARK: - Completed View

    @ViewBuilder
    private var completedView: some View {
        if viewModel.completedTasksByDay.isEmpty {
            emptyState(message: "No completed tasks yet", icon: "checkmark.circle")
        } else {
            ForEach(viewModel.completedTasksByDay, id: \.date) { dayGroup in
                sectionHeader(
                    title: completedDayLabel(dayGroup.date),
                    color: Calendar.current.isDateInToday(dayGroup.date) ? DS.green : DS.textSecondary,
                    trailing: "\(dayGroup.tasks.count)"
                )

                ForEach(dayGroup.tasks) { task in
                    taskRow(task)
                }
            }
        }
    }

    private func completedDayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "EEEE, MMM d"
        } else {
            formatter.dateFormat = "EEEE, MMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    // MARK: - Section Component

    @ViewBuilder
    private func taskSection(
        title: String,
        tasks: [TaskViewModel],
        headerColor: Color,
        showReschedule: Bool = false,
        showAddRow: Bool = false,
        section: CommandCenterDashboardViewModel.TaskSection? = nil
    ) -> some View {
        sectionHeader(
            title: title,
            color: headerColor,
            trailing: tasks.isEmpty ? nil : "\(tasks.count)",
            showReschedule: showReschedule
        )

        ForEach(tasks) { task in
            taskRow(task)
                .draggable(task.uuid) {
                    // Drag preview
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(task.priority.color)
                            .frame(width: 4, height: 20)
                        Text(task.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .onAppear { draggedTaskUUID = task.uuid }
                }
                .dropDestination(for: String.self) { droppedItems, _ in
                    guard let droppedUUID = droppedItems.first,
                          let targetSection = section,
                          droppedUUID != task.uuid else { return false }

                    var sectionTasks: [TaskViewModel]
                    switch targetSection {
                    case .overdue: sectionTasks = viewModel.overdueTasks
                    case .scheduled: sectionTasks = viewModel.scheduledTasks
                    case .unscheduled: sectionTasks = viewModel.unscheduledTasks
                    }

                    guard let fromIndex = sectionTasks.firstIndex(where: { $0.uuid == droppedUUID }),
                          let toIndex = sectionTasks.firstIndex(where: { $0.uuid == task.uuid })
                    else { return false }

                    let offset = toIndex > fromIndex ? toIndex + 1 : toIndex
                    viewModel.reorderTasks(
                        section: targetSection,
                        fromOffsets: IndexSet(integer: fromIndex),
                        toOffset: offset
                    )
                    draggedTaskUUID = nil
                    dropTargetTaskUUID = nil
                    return true
                } isTargeted: { targeted in
                    dropTargetTaskUUID = targeted ? task.uuid : (dropTargetTaskUUID == task.uuid ? nil : dropTargetTaskUUID)
                }
                .overlay(alignment: .top) {
                    if dropTargetTaskUUID == task.uuid && draggedTaskUUID != task.uuid {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(DS.accent)
                            .frame(height: 2)
                            .padding(.horizontal, 8)
                            .transition(.opacity)
                    }
                }

            if expandedTaskId == task.uuid && completionStates[task.uuid] == nil {
                TaskDetailInlineEditor(
                    viewModel: viewModel,
                    task: task,
                    onDismiss: { expandedTaskId = nil }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }

        if showAddRow {
            addTaskField
        }

        Spacer().frame(height: 16)
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(
        title: String,
        color: Color,
        trailing: String? = nil,
        showReschedule: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(color)

            if let trailing = trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color.opacity(0.7))
            }

            Spacer()

            if showReschedule {
                Button {
                    showOverdueRescheduleMenu.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Reschedule")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(PlannerumColors.overdue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(PlannerumColors.overdue.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(PlannerumColors.overdue.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showOverdueRescheduleMenu, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    CommandCenterReschedulePanel(title: "Reschedule overdue tasks") { date in
                        showOverdueRescheduleMenu = false
                        Task {
                            await viewModel.rescheduleTasks(
                                uuids: viewModel.overdueTasks.map(\.uuid),
                                toDate: date
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Upcoming Day Section

    @ViewBuilder
    private func upcomingDaySection(_ day: UpcomingDayViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(upcomingDayLabel(day))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(day.isToday ? DS.accent : DS.textSecondary)

                Text("\(day.taskCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.textMuted)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(day.tasks) { task in
                taskRow(task)
            }

            addTaskFieldForDate(day.date)
        }
    }

    private func upcomingDayLabel(_ day: UpcomingDayViewModel) -> String {
        if day.isToday { return "TODAY" }
        if day.isTomorrow { return "TOMORROW" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: day.date).uppercased()
    }

    // MARK: - Single Task Row

    @ViewBuilder
    private func taskRow(_ task: TaskViewModel) -> some View {
        let isActiveSession = viewModel.sessionEngine.activeSession?.taskUUID == task.uuid
            && viewModel.sessionEngine.isTimerRunning
        let isKeyboardSelected: Bool = {
            guard let idx = viewModel.selectedTaskIndex,
                  viewModel.currentVisibleTasks.indices.contains(idx) else { return false }
            return viewModel.currentVisibleTasks[idx].uuid == task.uuid
        }()
        let isMultiSelected = selectedTaskUUIDs.contains(task.uuid)
        let completionState = completionStates[task.uuid]
        let isAnimatingCompletion = completionState != nil

        let isHovered = hoveredTaskUUID == task.uuid && !isAnimatingCompletion

        HStack(spacing: 0) {
            // Priority color bar — widens on hover
            RoundedRectangle(cornerRadius: 2)
                .fill(task.priority.color.opacity(isHovered ? 1.0 : 0.85))
                .frame(width: isHovered ? 5 : 4)
                .padding(.vertical, 4)

            HStack(spacing: 10) {
                // Checkbox
                checkboxButton(task, completionState: completionState)

                // Title + meta
                taskContent(task, completionState: completionState)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isAnimatingCompletion else { return }
                        if NSEvent.modifierFlags.contains(.shift) {
                            if selectedTaskUUIDs.contains(task.uuid) {
                                selectedTaskUUIDs.remove(task.uuid)
                            } else {
                                selectedTaskUUIDs.insert(task.uuid)
                            }
                        } else {
                            selectedTaskUUIDs.removeAll()
                            withAnimation(ProMotionSprings.snappy) {
                                expandedTaskId = expandedTaskId == task.uuid ? nil : task.uuid
                            }
                        }
                    }

                Spacer(minLength: 4)

                // Due date chip
                if let dueInfo = task.dueInfo, !task.isCompleted {
                    dueDateChip(dueInfo, isOverdue: task.isOverdue)
                }

                // Play button
                if !task.isCompleted && !isAnimatingCompletion {
                    playButton(task, isActive: isActiveSession)
                }

                if !isAnimatingCompletion {
                    taskActionButton(task)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
        }
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isActiveSession ? DS.accent.opacity(0.06)
                        : isMultiSelected ? DS.accent.opacity(0.06)
                        : isKeyboardSelected ? DS.accentSoft
                        : isHovered ? DS.surfaceHover
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isActiveSession ? DS.accent.opacity(0.3)
                        : isMultiSelected ? DS.accent.opacity(0.4)
                        : isKeyboardSelected ? DS.accent.opacity(0.2)
                        : Color.clear,
                    lineWidth: isMultiSelected ? 2 : 1
                )
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .scaleEffect(completionState?.rowScale ?? 1)
        .opacity(completionState?.rowOpacity ?? 1)
        .offset(y: completionState?.rowOffsetY ?? 0)
        .blur(radius: completionState?.blurRadius ?? 0)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredTaskUUID = hovering ? task.uuid : (hoveredTaskUUID == task.uuid ? nil : hoveredTaskUUID)
        }
        .contextMenu {
            Button {
                handleTaskCompletionTap(task)
            } label: {
                Label(task.isCompleted ? "Mark Incomplete" : "Complete", systemImage: task.isCompleted ? "circle" : "checkmark.circle")
            }

            Divider()

            Button(role: .destructive) {
                if selectedTaskUUIDs.contains(task.uuid) {
                    let toDelete = selectedTaskUUIDs
                    selectedTaskUUIDs.removeAll()
                    Task { await viewModel.deleteMultipleTasks(uuids: toDelete) }
                } else {
                    Task { await viewModel.deleteTask(uuid: task.uuid) }
                }
            } label: {
                if selectedTaskUUIDs.contains(task.uuid) && selectedTaskUUIDs.count > 1 {
                    Label("Delete \(selectedTaskUUIDs.count) Tasks", systemImage: "trash")
                } else {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Batch Action Bar

    private var batchActionBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedTaskUUIDs.count) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.text)

            Spacer()

            Button {
                let toDelete = selectedTaskUUIDs
                selectedTaskUUIDs.removeAll()
                Task { await viewModel.deleteMultipleTasks(uuids: toDelete) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("Delete")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(PlannerumColors.overdue)
            }
            .buttonStyle(.plain)

            Button {
                selectedTaskUUIDs.removeAll()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.accent.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Checkbox

    @ViewBuilder
    private func checkboxButton(_ task: TaskViewModel, completionState: CommandCenterTaskCompletionState?) -> some View {
        Button {
            handleTaskCompletionTap(task)
        } label: {
            CommandCenterAnimatedCheckbox(
                priorityColor: task.priority.color,
                isCompleted: task.isCompleted,
                completionState: completionState,
                size: 18
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Task Content

    @ViewBuilder
    private func taskContent(_ task: TaskViewModel, completionState: CommandCenterTaskCompletionState?) -> some View {
        let resolvedHabit = viewModel.resolvedHabit(for: task)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if task.intent != .general {
                    Image(systemName: task.intent.iconName)
                        .font(.system(size: 9))
                        .foregroundColor(task.intent.color.opacity(0.7))
                }

                CommandCenterAnimatedTaskTitle(
                    title: task.title,
                    isCompleted: task.isCompleted,
                    completionState: completionState,
                    font: .system(size: 13, weight: task.isCompleted ? .regular : .medium),
                    activeColor: DS.text,
                    completedColor: DS.textMuted
                )
                .lineLimit(1)
            }

            HStack(spacing: 6) {
                if let timeInfo = task.timeInfo {
                    Label(timeInfo, systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                }

                if task.isRecurring {
                    Label("Repeats", systemImage: "repeat")
                        .font(.system(size: 10))
                        .foregroundColor(DS.accent.opacity(0.85))
                }

                if let resolvedHabit {
                    Label(resolvedHabit.title, systemImage: resolvedHabit.icon)
                        .font(.system(size: 10))
                        .foregroundColor(resolvedHabit.accent.opacity(0.9))
                }

                if let projectName = task.projectName {
                    Text(projectName)
                        .font(.system(size: 10))
                        .foregroundColor(task.projectColor)
                }

                if task.sessionCount > 0 {
                    Label("\(task.totalFocusMinutes)m tracked", systemImage: "timer")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                }
            }
        }
    }

    // MARK: - Due Date Chip

    private func dueDateChip(_ text: String, isOverdue: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isOverdue ? PlannerumColors.overdue : DS.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(isOverdue ? PlannerumColors.overdue.opacity(0.1) : DS.surface)
            )
    }

    // MARK: - Play Button

    @ViewBuilder
    private func playButton(_ task: TaskViewModel, isActive: Bool) -> some View {
        Button {
            if isActive {
                viewModel.sessionEngine.pauseSession()
            } else {
                viewModel.startFocusSession(for: task)
            }
        } label: {
            Image(systemName: isActive ? "pause.fill" : "play.fill")
                .font(.system(size: 10))
                .foregroundColor(isActive ? DS.accent : DS.textMuted)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isActive ? DS.accentSoft : DS.surface)
                )
        }
        .buttonStyle(.plain)
    }

    private func taskActionButton(_ task: TaskViewModel) -> some View {
        Button {
            activeTaskMenuUUID = task.uuid
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(activeTaskMenuUUID == task.uuid ? DS.text : DS.textMuted)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(activeTaskMenuUUID == task.uuid ? DS.accentSoft : DS.surface)
                )
                .overlay(
                    Circle()
                        .stroke(activeTaskMenuUUID == task.uuid ? DS.accent.opacity(0.22) : DS.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { activeTaskMenuUUID == task.uuid },
                set: { if !$0 { activeTaskMenuUUID = nil } }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            CommandCenterTaskActionPopover(
                task: task,
                currentHabit: viewModel.resolvedHabit(for: task),
                availableHabits: viewModel.availableHabitDefinitions,
                loadRecurrenceRule: { await viewModel.recurrenceRule(for: task) },
                onToggleCompletion: { handleTaskCompletionTap(task) },
                onReschedule: { date in
                    Task { await viewModel.rescheduleTask(uuid: task.uuid, toDate: date) }
                },
                onApplyHabit: { habitUUID in
                    Task { await viewModel.applyHabit(habitUUID, to: task.uuid) }
                },
                onApplyRecurrence: { rule in
                    Task { await viewModel.setTaskRecurrence(uuid: task.uuid, rule: rule) }
                },
                onDelete: {
                    Task { await viewModel.deleteTask(uuid: task.uuid) }
                },
                onDismiss: {
                    activeTaskMenuUUID = nil
                }
            )
        }
    }

    // MARK: - Add Task Field

    private var addTaskField: some View {
        SmartTaskCaptureRow(viewModel: viewModel)
    }

    @ViewBuilder
    private func addTaskFieldForDate(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textMuted)

            Text("Add task")
                .font(.system(size: 13))
                .foregroundColor(DS.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            // Focus the main add field and set date context
            viewModel.pendingTaskDate = date
        }
    }

    // MARK: - Empty State

    private func emptyState(message: String, icon: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(DS.accent.opacity(0.08), lineWidth: 1)
                    .frame(width: 56, height: 56)

                Circle()
                    .fill(DS.accentSoft.opacity(0.5))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(DS.accent.opacity(0.6))
            }

            Text(message)
                .font(DS.cardMeta)
                .foregroundColor(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func handleTaskCompletionTap(_ task: TaskViewModel) {
        guard completionStates[task.uuid] == nil else { return }

        if task.isCompleted {
            Task { _ = await viewModel.uncompleteTask(uuid: task.uuid) }
            return
        }

        expandedTaskId = nil
        let timings = CommandCenterCompletionTimings(reduceMotion: reduceMotion)
        completionStates[task.uuid] = .initial

        withAnimation(.easeInOut(duration: timings.ringDuration)) {
            updateCompletionState(for: task.uuid) { state in
                state.ringProgress = 1
                state.fillScale = 1
                state.fillOpacity = 1
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: timings.checkDelay.nanoseconds)
            withAnimation(.spring(response: timings.checkResponse, dampingFraction: 0.78)) {
                updateCompletionState(for: task.uuid) { $0.checkProgress = 1 }
            }

            try? await Task.sleep(nanoseconds: (timings.strikeDelay - timings.checkDelay).nanoseconds)
            withAnimation(.easeInOut(duration: timings.strikeDuration)) {
                updateCompletionState(for: task.uuid) { $0.strikeProgress = 1 }
            }

            try? await Task.sleep(nanoseconds: (timings.fadeDelay - timings.strikeDelay).nanoseconds)
            withAnimation(.easeInOut(duration: timings.fadeDuration)) {
                updateCompletionState(for: task.uuid) { state in
                    state.rowOpacity = 0
                    state.rowScale = reduceMotion ? 0.98 : 0.95
                    state.rowOffsetY = reduceMotion ? -4 : -10
                    state.blurRadius = reduceMotion ? 0.6 : 1.8
                }
            }

            try? await Task.sleep(nanoseconds: timings.fadeDuration.nanoseconds)
            let completed = await viewModel.completeTask(uuid: task.uuid)
            completionStates.removeValue(forKey: task.uuid)

            if completed {
                viewModel.notifyCompletedTaskArrival()
            }
        }
    }

    private func updateCompletionState(for taskUUID: String, _ update: (inout CommandCenterTaskCompletionState) -> Void) {
        var state = completionStates[taskUUID] ?? .initial
        update(&state)
        completionStates[taskUUID] = state
    }
}

struct CommandCenterTaskCompletionState: Equatable {
    var ringProgress: CGFloat = 0
    var fillScale: CGFloat = 0.7
    var fillOpacity: Double = 0
    var checkProgress: CGFloat = 0
    var strikeProgress: CGFloat = 0
    var rowOpacity: Double = 1
    var rowScale: CGFloat = 1
    var rowOffsetY: CGFloat = 0
    var blurRadius: CGFloat = 0

    static let initial = CommandCenterTaskCompletionState()
}

struct CommandCenterCompletionTimings {
    let ringDuration: Double
    let checkDelay: Double
    let checkResponse: Double
    let strikeDelay: Double
    let strikeDuration: Double
    let fadeDelay: Double
    let fadeDuration: Double

    init(reduceMotion: Bool) {
        if reduceMotion {
            ringDuration = 0.14
            checkDelay = 0.05
            checkResponse = 0.18
            strikeDelay = 0.16
            strikeDuration = 0.10
            fadeDelay = 0.28
            fadeDuration = 0.16
        } else {
            ringDuration = 0.24
            checkDelay = 0.12
            checkResponse = 0.24
            strikeDelay = 0.32
            strikeDuration = 0.18
            fadeDelay = 0.54
            fadeDuration = 0.24
        }
    }
}

struct CommandCenterAnimatedCheckbox: View {
    let priorityColor: Color
    let isCompleted: Bool
    let completionState: CommandCenterTaskCompletionState?
    let size: CGFloat

    private var ringProgress: CGFloat {
        if isCompleted { return 1 }
        return completionState?.ringProgress ?? 0
    }

    private var fillScale: CGFloat {
        if isCompleted { return 1 }
        return completionState?.fillScale ?? 0.7
    }

    private var fillOpacity: Double {
        if isCompleted { return 1 }
        return completionState?.fillOpacity ?? 0
    }

    private var checkProgress: CGFloat {
        if isCompleted { return 1 }
        return completionState?.checkProgress ?? 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(priorityColor.opacity(isCompleted ? 0 : 0.4), lineWidth: 1.5)
                .frame(width: size, height: size)

            Circle()
                .fill(DS.green)
                .frame(width: size, height: size)
                .scaleEffect(fillScale)
                .opacity(fillOpacity)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(DS.green, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .opacity(isCompleted || completionState != nil ? 1 : 0)

            CommandCenterCheckmarkShape()
                .trim(from: 0, to: checkProgress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.52, height: size * 0.52)
        }
        .frame(width: size, height: size)
    }
}

struct CommandCenterAnimatedTaskTitle: View {
    let title: String
    let isCompleted: Bool
    let completionState: CommandCenterTaskCompletionState?
    let font: Font
    let activeColor: Color
    let completedColor: Color

    private var strikeProgress: CGFloat {
        if isCompleted { return 1 }
        return completionState?.strikeProgress ?? 0
    }

    var body: some View {
        Text(title)
            .font(font)
            .foregroundColor(isCompleted || completionState != nil ? completedColor : activeColor)
            .strikethrough(isCompleted, color: completedColor)
            .overlay(alignment: .leading) {
                if !isCompleted {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(completedColor)
                            .frame(width: geo.size.width * strikeProgress, height: 1.4)
                            .position(
                                x: (geo.size.width * strikeProgress) / 2,
                                y: geo.size.height * 0.54
                            )
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

private struct CommandCenterCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.56))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.18))
        return path
    }
}

private extension Double {
    var nanoseconds: UInt64 {
        UInt64((self * 1_000_000_000).rounded())
    }
}
