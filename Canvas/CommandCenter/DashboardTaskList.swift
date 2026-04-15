// Canvas/CommandCenter/DashboardTaskList.swift
// Todoist-style sectioned task list with priority bars, due chips, and inline play
// March 2026

import SwiftUI

struct DashboardTaskList: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    var onSelectTask: ((TaskViewModel) -> Void)?
    // expandedTaskId removed — task detail is now right-panel only
    @State private var selectedTaskUUIDs: Set<String> = []
    @State private var completionStates: [String: CommandCenterTaskCompletionState] = [:]
    @State private var showOverdueRescheduleMenu = false
    @State private var hoveredTaskUUID: String?
    @State private var draggedTaskUUID: String?
    @State private var dropTargetTaskUUID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                switch viewModel.viewMode {
                case .today:
                    todayView
                case .upcoming:
                    upcomingView
                case .logbook:
                    completedView
                case .anytime:
                    anytimeView
                case .someday:
                    somedayView
                case .project:
                    projectView
                case .area:
                    EmptyView()
                }
            }
        }
        .scrollIndicators(.hidden)
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
                headerColor: DS.red,
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

    // MARK: - Anytime View

    @ViewBuilder
    private var anytimeView: some View {
        if viewModel.anytimeTasks.isEmpty {
            emptyState(message: "No anytime tasks", icon: "tray.full")
        } else {
            sectionHeader(title: "Anytime", color: DS.textSecondary, trailing: "\(viewModel.anytimeTasks.count)")
            ForEach(viewModel.anytimeTasks) { task in
                taskRow(task)
            }
        }

        SmartTaskCaptureRow(viewModel: viewModel)
    }

    // MARK: - Someday View

    @ViewBuilder
    private var somedayView: some View {
        if viewModel.somedayTasks.isEmpty {
            emptyState(message: "No someday tasks — park ideas here for later", icon: "archivebox")
        } else {
            sectionHeader(title: "Someday", color: DS.textSecondary, trailing: "\(viewModel.somedayTasks.count)")
            ForEach(viewModel.somedayTasks) { task in
                taskRow(task)
            }
        }

        SmartTaskCaptureRow(viewModel: viewModel)
    }

    // MARK: - Project View

    @ViewBuilder
    private var projectView: some View {
        if viewModel.projectTasks.isEmpty && viewModel.projectHeadings.isEmpty {
            emptyState(message: "No tasks in this project yet", icon: "folder")
        } else {
            // Tasks grouped by heading
            let tasksWithNoHeading = viewModel.projectTasks.filter { $0.headingUUID == nil }
            let sortedHeadings = viewModel.projectHeadings.sorted { $0.sortOrder < $1.sortOrder }

            ForEach(sortedHeadings) { heading in
                let headingTasks = viewModel.projectTasks.filter { $0.headingUUID == heading.id }
                projectHeadingSection(heading: heading, tasks: headingTasks)
            }

            if !tasksWithNoHeading.isEmpty || sortedHeadings.isEmpty {
                if !sortedHeadings.isEmpty {
                    sectionHeader(title: "No Heading", color: DS.textMuted, trailing: "\(tasksWithNoHeading.count)")
                }
                ForEach(tasksWithNoHeading) { task in
                    taskRow(task)
                }
            }

            SmartTaskCaptureRow(
                viewModel: viewModel,
                contextProjectUUID: viewModel.selectedProjectUUID,
                placeholderText: "Add task to project..."
            )
        }
    }

    @ViewBuilder
    private func projectHeadingSection(heading: ProjectHeading, tasks: [TaskViewModel]) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: heading.isCollapsed ? "chevron.right" : "chevron.down")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .frame(width: 14)

            Text(heading.title)
                .font(DS.callout)
                .foregroundStyle(DS.accent)

            Spacer()

            if heading.isCollapsed {
                Text("\(tasks.count)")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(.vertical, DS.space8)
        .padding(.horizontal, DS.space12)
        .contentShape(Rectangle())

        if !heading.isCollapsed {
            ForEach(tasks) { task in
                taskRow(task)
            }

            // Add task row for this heading
            SmartTaskCaptureRow(
                viewModel: viewModel,
                contextProjectUUID: viewModel.selectedProjectUUID,
                contextHeadingUUID: heading.id,
                placeholderText: "Add task to \(heading.title)..."
            )
            .padding(.horizontal, 4)
        }
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
                    // Drag preview — vellum card, no accent bar
                    HStack(spacing: 8) {
                        TaskTitleWithMentions(
                            title: task.title,
                            mentions: task.titleMentions,
                            font: .system(size: 13, weight: .medium)
                        ) { mention in
                            NotificationCenter.default.post(
                                name: .init("com.cosmo.navigateToAtom"),
                                object: nil,
                                userInfo: ["uuid": mention.entityUUID, "intent": "general"]
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DS.vellum, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DS.giltMuted, lineWidth: 0.5)
                    )
                    .dsFloatingShadow()
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

            // Inline editor removed — task detail is in right panel only
        }

        if showAddRow {
            addTaskField
        }

        Spacer().frame(height: DS.space16)
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
            Text(title)
                .font(DS.smallCaps)
                .foregroundStyle(color)

            if let trailing {
                Text("(\(trailing))")
                    .font(DS.smallCaps)
                    .foregroundStyle(color.opacity(0.6))
            }

            // Anchoring line — extends to right edge like a ledger rule
            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(height: 0.5)
                .padding(.leading, DS.space8)

            Spacer(minLength: 0)

            if showReschedule {
                Button {
                    showOverdueRescheduleMenu.toggle()
                } label: {
                    HStack(spacing: DS.space4) {
                        Image(systemName: "calendar.badge.clock")
                            .font(DS.caption2)
                        Text("Reschedule")
                            .font(DS.caption)
                    }
                    .foregroundStyle(DS.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(DS.red.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(DS.red.opacity(0.2), lineWidth: 1)
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
        .padding(.horizontal, DS.space10)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space6)
    }

    // MARK: - Upcoming Day Section

    @ViewBuilder
    private func upcomingDaySection(_ day: UpcomingDayViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(upcomingDayLabel(day))
                    .font(DS.smallCaps)
                    .foregroundStyle(day.isToday ? DS.accent : DS.textSecondary)

                Text("\(day.taskCount)")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)

                Spacer()
            }
            .padding(.horizontal, DS.space10)
            .padding(.top, DS.space12)
            .padding(.bottom, DS.space6)

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

        rowBase(task, completionState: completionState, isActiveSession: isActiveSession, isAnimatingCompletion: isAnimatingCompletion)
        .background(rowBackground(isActiveSession: isActiveSession, isMultiSelected: isMultiSelected, isKeyboardSelected: isKeyboardSelected, isHovered: isHovered))
        .overlay(alignment: .bottom) { rowPriorityWash(task, isAnimatingCompletion: isAnimatingCompletion) }
        .overlay(rowBorder(isActiveSession: isActiveSession, isMultiSelected: isMultiSelected, isKeyboardSelected: isKeyboardSelected))
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .scaleEffect(completionState?.rowScale ?? 1)
        .opacity(completionState?.rowOpacity ?? 1)
        .offset(y: completionState?.rowOffsetY ?? 0)
        .blur(radius: completionState?.blurRadius ?? 0)
        .contentShape(Rectangle())
        .onTapGesture { handleRowTap(task, isAnimatingCompletion: isAnimatingCompletion) }
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
        HStack(spacing: DS.space12) {
            Text("\(selectedTaskUUIDs.count) selected")
                .font(DS.cardMeta)
                .foregroundStyle(DS.text)

            Spacer()

            Button {
                let toDelete = selectedTaskUUIDs
                selectedTaskUUIDs.removeAll()
                Task { await viewModel.deleteMultipleTasks(uuids: toDelete) }
            } label: {
                HStack(spacing: DS.space4) {
                    Image(systemName: "trash")
                        .font(DS.footnote)
                    Text("Delete")
                        .font(DS.cardMeta)
                }
                .foregroundStyle(DS.red)
            }
            .buttonStyle(.plain)

            Button {
                selectedTaskUUIDs.removeAll()
            } label: {
                Text("Cancel")
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .background(DS.surface, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
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
            HStack(spacing: DS.space4) {
                if task.intent != .general {
                    Image(systemName: task.intent.iconName)
                        .font(DS.caption2)
                        .foregroundStyle(task.intent.color.opacity(0.7))
                }

                if !task.titleMentions.isEmpty && completionState == nil && !task.isCompleted {
                    TaskTitleWithMentions(
                        title: task.title,
                        mentions: task.titleMentions,
                        font: DS.callout
                    ) { mention in
                        NotificationCenter.default.post(
                            name: .init("com.cosmo.navigateToAtom"),
                            object: nil,
                            userInfo: ["uuid": mention.entityUUID, "intent": "general"]
                        )
                    }
                } else {
                    CommandCenterAnimatedTaskTitle(
                        title: task.title,
                        isCompleted: task.isCompleted,
                        completionState: completionState,
                        font: DS.callout,
                        activeColor: DS.text,
                        completedColor: DS.textMuted
                    )
                    .lineLimit(1)
                }
            }

            HStack(spacing: DS.space6) {
                if let timeInfo = task.timeInfo {
                    Label(timeInfo, systemImage: "clock")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }

                if task.isRecurring {
                    Label("Repeats", systemImage: "repeat")
                        .font(DS.caption2)
                        .foregroundStyle(DS.accent.opacity(0.85))
                }

                if let resolvedHabit {
                    Label(resolvedHabit.title, systemImage: resolvedHabit.icon)
                        .font(DS.caption2)
                        .foregroundStyle(resolvedHabit.accent.opacity(0.9))
                }

                if let projectName = task.projectName {
                    Text(projectName)
                        .font(DS.caption2)
                        .foregroundStyle(task.projectColor)
                }

                if task.sessionCount > 0 {
                    Label("\(task.totalFocusMinutes)m tracked", systemImage: "timer")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
    }

    // MARK: - Due Date Chip

    private func dueDateChip(_ text: String, isOverdue: Bool) -> some View {
        HStack(spacing: 3) {
            if isOverdue {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(DS.red)
            }
            Text(text)
                .font(DS.caption2)
                .foregroundStyle(isOverdue ? DS.red : DS.inkFaded)
        }
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
                .font(DS.caption2)
                .foregroundStyle(isActive ? DS.accent : DS.inkFaded)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isActive ? DS.accentSoft : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rowBase(
        _ task: TaskViewModel,
        completionState: CommandCenterTaskCompletionState?,
        isActiveSession: Bool,
        isAnimatingCompletion: Bool
    ) -> some View {
        HStack(spacing: 0) {
            rowPriorityLead(task)
            rowContent(task, completionState: completionState, isActiveSession: isActiveSession, isAnimatingCompletion: isAnimatingCompletion)
                .padding(.trailing, 10)
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func rowPriorityLead(_ task: TaskViewModel) -> some View {
        if task.priority == .high || task.priority == .critical {
            Rectangle()
                .fill(task.priority.color.opacity(0.30))
                .frame(width: 4, height: 4)
                .rotationEffect(.degrees(45))
                .padding(.leading, 6)
                .padding(.trailing, 2)
        } else {
            Spacer().frame(width: 12)
        }
    }

    private func rowBackground(isActiveSession: Bool, isMultiSelected: Bool, isKeyboardSelected: Bool, isHovered: Bool) -> some View {
        let fill: Color = {
            if isActiveSession { return DS.accentSoft.opacity(0.5) }
            if isMultiSelected { return DS.accent.opacity(0.06) }
            if isKeyboardSelected { return DS.accentSoft }
            if isHovered { return DS.vellum.opacity(0.5) }
            return Color.clear
        }()
        return RoundedRectangle(cornerRadius: 6).fill(fill)
    }

    @ViewBuilder
    private func rowPriorityWash(_ task: TaskViewModel, isAnimatingCompletion: Bool) -> some View {
        if !task.isCompleted && !isAnimatingCompletion {
            LinearGradient(
                colors: [task.priority.color.opacity(0.06), Color.clear],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.4, y: 0.5)
            )
            .frame(height: 1)
            .clipShape(.rect(cornerRadius: 6))
        }
    }

    private func rowBorder(isActiveSession: Bool, isMultiSelected: Bool, isKeyboardSelected: Bool) -> some View {
        let stroke: Color = {
            if isActiveSession { return DS.accent.opacity(0.3) }
            if isMultiSelected { return DS.accent.opacity(0.4) }
            if isKeyboardSelected { return DS.accent.opacity(0.2) }
            return Color.clear
        }()
        return RoundedRectangle(cornerRadius: 6)
            .stroke(stroke, lineWidth: isMultiSelected ? 2 : 1)
    }

    @ViewBuilder
    private func rowContent(
        _ task: TaskViewModel,
        completionState: CommandCenterTaskCompletionState?,
        isActiveSession: Bool,
        isAnimatingCompletion: Bool
    ) -> some View {
        HStack(spacing: 10) {
            checkboxButton(task, completionState: completionState)

            taskContent(task, completionState: completionState)

            Spacer(minLength: 4)

            if let dueInfo = task.dueInfo, !task.isCompleted {
                dueDateChip(dueInfo, isOverdue: task.isOverdue)
            }

            if !task.isCompleted && !isAnimatingCompletion {
                playButton(task, isActive: isActiveSession)
            }
        }
    }

    private func handleRowTap(_ task: TaskViewModel, isAnimatingCompletion: Bool) {
        guard !isAnimatingCompletion else { return }
        if NSEvent.modifierFlags.contains(.shift) {
            if selectedTaskUUIDs.contains(task.uuid) {
                selectedTaskUUIDs.remove(task.uuid)
            } else {
                selectedTaskUUIDs.insert(task.uuid)
            }
        } else {
            selectedTaskUUIDs.removeAll()
            onSelectTask?(task)
        }
    }

    // MARK: - Add Task Field

    private var addTaskField: some View {
        SmartTaskCaptureRow(viewModel: viewModel)
    }

    @ViewBuilder
    private func addTaskFieldForDate(_ date: Date) -> some View {
        Button {
            viewModel.pendingTaskDate = date
        } label: {
            HStack(spacing: DS.space8) {
                Image(systemName: "plus")
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.textMuted)

                Text("Add task")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private func emptyState(message: String, icon: String) -> some View {
        VStack(spacing: DS.space10) {
            OrnamentalRule(color: DS.giltMuted)

            Text(message)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(DS.inkFaded)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }

    private func handleTaskCompletionTap(_ task: TaskViewModel) {
        guard completionStates[task.uuid] == nil else { return }

        if task.isCompleted {
            Task { _ = await viewModel.uncompleteTask(uuid: task.uuid) }
            return
        }

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
            .foregroundStyle(isCompleted || completionState != nil ? completedColor : activeColor)
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
