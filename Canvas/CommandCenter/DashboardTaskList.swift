// Canvas/CommandCenter/DashboardTaskList.swift
// Todoist-style sectioned task list with priority bars, due chips, and inline play
// March 2026

import SwiftUI

struct DashboardTaskList: View {

    private let rowChromeInset: CGFloat = DS.space8

    var viewModel: CommandCenterDashboardViewModel
    @ObservedObject private var sessionEngine = DeepWorkSessionEngine.shared
    let composer: CommandCenterComposerController
    var onSelectTask: ((TaskViewModel) -> Void)?
    // expandedTaskId removed — task detail is now right-panel only
    @State private var selectedTaskUUIDs: Set<String> = []
    @State private var completionStates: [String: CommandCenterTaskCompletionState] = [:]
    @State private var hoveredTaskUUID: String?
    @State private var draggedTaskUUID: String?
    @State private var dropTargetTaskUUID: String?
    @State private var seriesDeleteTarget: TaskViewModel?
    @State private var seriesDeleteCompletionCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if viewModel.viewMode == .upcoming {
                upcomingView
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        switch viewModel.viewMode {
                        case .today:
                            todayView
                        case .upcoming:
                            EmptyView()
                        case .logbook:
                            completedView
                        case .anytime:
                            anytimeView
                        case .someday:
                            somedayView
                        case .habits, .reports, .queue:
                            EmptyView()
                        case .project:
                            projectView
                        case .area:
                            EmptyView()
                        }

                        // The hints are ledger verbs (N, ↑↓, Space, ⌫ all act
                        // on this list) — they live at the column's foot as
                        // its quiet terminus, never at the window bottom
                        // where the assistant island owns the center.
                        DashboardShortcutBar(viewModel: viewModel)
                            .padding(.horizontal, DS.space10)
                            .padding(.top, DS.space16)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Rows glide to close the gap when a completed task departs
                    // (or a task is added/reordered) instead of teleporting.
                    .animation(
                        reduceMotion ? nil : ProMotionSprings.gentle,
                        value: todayListIdentity
                    )
                }
                .scrollIndicators(.never)
            }
        }
        .confirmationDialog(
            "Delete \"\(seriesDeleteTarget?.title ?? "")\"?",
            isPresented: Binding(
                get: { seriesDeleteTarget != nil },
                set: { if !$0 { seriesDeleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete series", role: .destructive) {
                guard let target = seriesDeleteTarget else { return }
                seriesDeleteTarget = nil
                Sound.deleteTuck()
                Task { await viewModel.deleteTask(uuid: target.uuid) }
            }
            Button("Cancel", role: .cancel) { seriesDeleteTarget = nil }
        } message: {
            Text(SeriesDeleteCopy.message(completionCount: seriesDeleteCompletionCount))
        }
    }

    /// Identity of the visible today sections — the animation key for row moves.
    /// Completed ids are included so a task checked off glides into the Completed
    /// section (and the gap it left closes) instead of teleporting.
    private var todayListIdentity: [String] {
        viewModel.overdueTasks.map(\.id)
            + viewModel.scheduledTasks.map(\.id)
            + viewModel.unscheduledTasks.map(\.id)
            + viewModel.completedTasksForSelectedDay.map(\.id)
    }

    // MARK: - Delete Routing

    /// Default delete for an occurrence row cancels just that occurrence; deleting the
    /// whole series goes through the confirmation dialog above.
    private func requestSeriesDelete(_ task: TaskViewModel) {
        Task {
            seriesDeleteCompletionCount = await viewModel.seriesCompletionCount(templateUUID: task.uuid)
            seriesDeleteTarget = task
        }
    }

    /// Batch delete that understands recurring occurrences: occurrence rows are canceled
    /// individually (never soft-deleting the series template they share a uuid with).
    private func deleteSelectedTasks(_ uuids: Set<String>) {
        Sound.deleteTuck()
        let visible = viewModel.currentVisibleTasks
        var plainUUIDs = Set<String>()
        var occurrenceTasks: [TaskViewModel] = []
        for uuid in uuids {
            if let match = visible.first(where: { $0.uuid == uuid }), match.isOccurrence {
                occurrenceTasks.append(match)
            } else {
                plainUUIDs.insert(uuid)
            }
        }
        Task {
            for occurrence in occurrenceTasks {
                _ = await viewModel.cancelOccurrence(occurrence)
            }
            if !plainUUIDs.isEmpty {
                await viewModel.deleteMultipleTasks(uuids: plainUUIDs)
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

        if !viewModel.overdueTasks.isEmpty {
            taskSection(
                title: "Overdue",
                tasks: viewModel.overdueTasks,
                headerColor: DS.red,
                isSemantic: true,
                showReschedule: true,
                section: .overdue
            )
        }

        if !viewModel.scheduledTasks.isEmpty {
            taskSection(
                title: "Scheduled",
                tasks: viewModel.scheduledTasks,
                headerColor: DS.textSecondary,
                section: .scheduled
            )
        }

        // "To do", not "Today" — the page title already says Today; a section
        // must never echo it (the duplicate-word law). The count speaks the
        // reward-loop language ("4 left" ticks down as rows depart), never a
        // bare tally.
        if !viewModel.unscheduledTasks.isEmpty {
            taskSection(
                title: "To do",
                tasks: viewModel.unscheduledTasks,
                headerColor: DS.textSecondary,
                countSuffix: "left",
                section: .unscheduled
            )
        }

        let hasActiveTasks = !viewModel.overdueTasks.isEmpty
            || !viewModel.scheduledTasks.isEmpty
            || !viewModel.unscheduledTasks.isEmpty

        // Only truly empty when nothing is planned AND nothing was finished today —
        // a day cleared to completion shows its Completed section, not "No tasks".
        if !hasActiveTasks && viewModel.completedTasksForSelectedDay.isEmpty {
            emptyState(message: "No tasks today", icon: "calendar")
        }

        SmartTaskCaptureRow(viewModel: viewModel)

        // The evening register: after 17:00 (or the moment the day clears)
        // the page hands you tomorrow — the "plan tomorrow today" ritual as
        // a door, not another task.
        if viewModel.isEveningRegister {
            EveningPlanRow(viewModel: viewModel)
        }

        // Finished work files itself away at the very bottom — dimmed, struck
        // through, still one tap from being reopened (iOS Today parity).
        if !viewModel.completedTasksForSelectedDay.isEmpty {
            completedTodaySection
        }
    }

    // MARK: - Completed (Today)

    /// The receding pile of today's checked-off tasks. Plain rows (no drag / no
    /// reorder — completed work isn't planned) under one quiet "Completed" header.
    @ViewBuilder
    private var completedTodaySection: some View {
        let completed = viewModel.completedTasksForSelectedDay
        sectionHeader(
            title: "Completed",
            color: DS.textSecondary,
            trailing: "\(completed.count)"
        )

        ForEach(completed) { task in
            taskRow(task)
        }

        Spacer().frame(height: DS.space16)
    }

    // MARK: - Upcoming View

    @ViewBuilder
    private var upcomingView: some View {
        UpcomingBoardView(viewModel: viewModel, composer: composer)
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
                    color: DS.green,
                    trailing: "\(dayGroup.tasks.count)",
                    isSemantic: Calendar.current.isDateInToday(dayGroup.date)
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

    // No section header on the single-section lists: a lone section must
    // never echo the page's own title ("Anytime"/"ANYTIME" — the duplicate-
    // word law), and Things shows none here. The masthead and sidebar badge
    // already carry the context.
    @ViewBuilder
    private var anytimeView: some View {
        if viewModel.anytimeTasks.isEmpty {
            emptyState(message: "No anytime tasks", icon: "tray.full")
        } else {
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
                placeholderText: "Add task to project…"
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
                placeholderText: "Add task to \(heading.title)…"
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
        isSemantic: Bool = false,
        showReschedule: Bool = false,
        showAddRow: Bool = false,
        countSuffix: String? = nil,
        section: CommandCenterDashboardViewModel.TaskSection? = nil
    ) -> some View {
        sectionHeader(
            title: title,
            color: headerColor,
            trailing: tasks.isEmpty ? nil : countSuffix.map { "\(tasks.count) \($0)" } ?? "\(tasks.count)",
            isSemantic: isSemantic,
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
                            font: DS.callout.weight(.medium)
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
                    // The drag preview's lifetime IS the drag session: appear
                    // at pickup, disappear on drop or cancel — the one place
                    // both ends of the gesture are observable.
                    .onAppear {
                        draggedTaskUUID = task.uuid
                        viewModel.isTaskDragInFlight = true
                        Sound.dragPickup()
                    }
                    .onDisappear {
                        viewModel.isTaskDragInFlight = false
                        if draggedTaskUUID == task.uuid { draggedTaskUUID = nil }
                    }
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
                    viewModel.isTaskDragInFlight = false
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

    // (The Schedule story — events + blocks — lives in the right rail's
    // Day Spine now; one home, and blocks there are live drop targets.)

    // MARK: - Section Header

    /// The one header voice (peakui): small-caps label — gilt by default,
    /// tinted for semantic sections (Overdue red) — live count, ledger rule,
    /// and section actions docked in the trailing slot.
    @ViewBuilder
    private func sectionHeader(
        title: String,
        color: Color,
        trailing: String? = nil,
        isSemantic: Bool = false,
        showReschedule: Bool = false
    ) -> some View {
        CosmoSectionHeader(
            label: title,
            detail: trailing,
            tint: isSemantic ? color : nil
        ) {
            if showReschedule {
                CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                    // Row ids ("uuid" or "uuid#day") so recurring occurrences reschedule via
                    // per-day overrides instead of rewriting their template's anchor.
                    .batchSchedule(
                        title: "Reschedule overdue tasks",
                        taskUUIDs: viewModel.overdueTasks.map(\.id),
                        anchor: anchor
                    )
                } label: {
                    Label("Reschedule", systemImage: "calendar.badge.clock")
                        .font(DS.caption)
                    .foregroundStyle(DS.red.opacity(0.85))
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, DS.space4)
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
                    .font(DS.caption).fontWeight(.semibold)
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
        if day.isToday { return "Today" }
        if day.isTomorrow { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: day.date)
    }

    // MARK: - Single Task Row

    @ViewBuilder
    private func taskRow(_ task: TaskViewModel) -> some View {
        let isActiveSession = sessionEngine.activeSession?.taskUUID == task.uuid
            && sessionEngine.isTimerRunning
        let isKeyboardSelected: Bool = {
            guard let idx = viewModel.selectedTaskIndex,
                  viewModel.currentVisibleTasks.indices.contains(idx) else { return false }
            return viewModel.currentVisibleTasks[idx].uuid == task.uuid
        }()
        let isMultiSelected = selectedTaskUUIDs.contains(task.uuid)
        let completionState = completionStates[task.uuid]
        let isAnimatingCompletion = completionState != nil

        let isHovered = hoveredTaskUUID == task.uuid && !isAnimatingCompletion

        rowBase(
            task,
            completionState: completionState,
            isActiveSession: isActiveSession,
            isAnimatingCompletion: isAnimatingCompletion,
            showsInlineActions: isHovered || isKeyboardSelected || isActiveSession || composer.isShowingTaskAction(for: task.uuid)
        )
        .background(
            rowBackground(
                task: task,
                isActiveSession: isActiveSession,
                isMultiSelected: isMultiSelected,
                isKeyboardSelected: isKeyboardSelected,
                isHovered: isHovered
            )
            .padding(.horizontal, rowChromeInset)
        )
        .overlay(alignment: .bottom) { rowPriorityWash(task, isAnimatingCompletion: isAnimatingCompletion) }
        // Completed work recedes as a group on Today — remaining tasks own
        // the list. (Logbook keeps full strength; it's a list OF completed.)
        .opacity(task.isCompleted && !isAnimatingCompletion && viewModel.viewMode == .today ? 0.7 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .animation(ProMotionSprings.hover, value: isKeyboardSelected)
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

            if selectedTaskUUIDs.contains(task.uuid) && selectedTaskUUIDs.count > 1 {
                Button(role: .destructive) {
                    let toDelete = selectedTaskUUIDs
                    selectedTaskUUIDs.removeAll()
                    deleteSelectedTasks(toDelete)
                } label: {
                    Label("Delete \(selectedTaskUUIDs.count) Tasks", systemImage: "trash")
                }
            } else if task.isOccurrence {
                // Occurrence rows share the series template's uuid — a plain delete would
                // end the whole series, not just this day.
                Button(role: .destructive) {
                    Sound.deleteTuck()
                    Task { _ = await viewModel.cancelOccurrence(task) }
                } label: {
                    Label("Remove This Occurrence", systemImage: "trash")
                }
                Button(role: .destructive) {
                    requestSeriesDelete(task)
                } label: {
                    Label("Delete Series…", systemImage: "trash.slash")
                }
            } else {
                Button(role: .destructive) {
                    Sound.deleteTuck()
                    Task { await viewModel.deleteTask(uuid: task.uuid) }
                } label: {
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
                deleteSelectedTasks(toDelete)
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

    // Rows are monochrome until interaction matters (peakui — the accent-
    // discipline law proven on iOS): intent, habit, repeat, and project meta
    // all speak muted ink at rest; color arrives only on the row whose focus
    // session is live. Identity colors live on identity surfaces, never
    // sprayed across a ledger.
    @ViewBuilder
    private func taskContent(
        _ task: TaskViewModel,
        completionState: CommandCenterTaskCompletionState?,
        isActiveSession: Bool
    ) -> some View {
        let resolvedHabit = viewModel.resolvedHabit(for: task)
        let intentPresentation = viewModel.resolvedIntentPresentation(for: task)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.space4) {
                if !intentPresentation.isUnassigned {
                    Image(systemName: intentPresentation.icon)
                        .font(DS.caption2)
                        .foregroundStyle(isActiveSession ? intentPresentation.accent : DS.textMuted)
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
                        .foregroundStyle(DS.textMuted)
                }

                if let resolvedHabit {
                    Label(resolvedHabit.title, systemImage: resolvedHabit.icon)
                        .font(DS.caption2)
                        .foregroundStyle(isActiveSession ? resolvedHabit.accent : DS.textMuted)
                }

                taskBlockBadge(task)

                if let projectName = task.projectName {
                    Text(projectName)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }

                if let goal = task.timeGoalMinutes {
                    // Timed task: progress toward the goal (recurring per-day progress
                    // is session-scoped, so template rows show the goal itself).
                    // A met goal is a live achievement — the one meta accent.
                    Label(
                        task.isRecurring
                            ? "\(Self.durationLabel(goal)) goal"
                            : "\(Self.durationLabel(min(task.totalFocusMinutes, goal))) of \(Self.durationLabel(goal))",
                        systemImage: "timer"
                    )
                    .font(DS.caption2)
                    .foregroundStyle(!task.isRecurring && task.totalFocusMinutes >= goal ? DS.accent : DS.textMuted)
                } else if task.sessionCount > 0 {
                    Label("\(Self.durationLabel(task.totalFocusMinutes)) tracked", systemImage: "timer")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
    }

    // MARK: - Block Badge (iOS parity)

    /// The block-membership badge — the same bare icon-plus-text grammar as
    /// the row's other meta labels, never a pill. Quiet by default (a small
    /// swatch in the block's color, muted text); while the block's occurrence
    /// is live the swatch becomes a play glyph and the name takes the color —
    /// "this is what I should be doing now".
    @ViewBuilder
    private func taskBlockBadge(_ task: TaskViewModel) -> some View {
        if let blockTitle = task.blockTitle {
            let tint = task.blockColorHex.map(Color.init(hex:)) ?? DS.accent
            let isLive = !task.isCompleted && task.blockIsLive()
            HStack(spacing: 3) {
                if isLive {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(tint)
                } else {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(tint)
                        .frame(width: 6, height: 6)
                }
                Text(blockTitle)
                    .font(DS.caption2)
                    .foregroundStyle(isLive ? tint : DS.textMuted)
                    .lineLimit(1)
            }
            .help(isLive ? "In block \(blockTitle) — happening now" : "In block \(blockTitle)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("In block \(blockTitle)\(isLive ? ", happening now" : "")")
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
                .foregroundStyle(isOverdue ? DS.red : DS.commandCenterMutedText)
        }
        .frame(width: 76, alignment: .trailing)
    }

    // MARK: - Play Button

    @ViewBuilder
    private func playButton(_ task: TaskViewModel, isActive: Bool) -> some View {
        Button {
            if isActive {
                Sound.focusPause()
                sessionEngine.pauseSession()
            } else {
                viewModel.startFocusSession(for: task)
            }
        } label: {
            // iOS-parity time-tracking affordance: dusty-rose task accent.
            Image(systemName: isActive ? "pause.circle.fill" : "play.circle")
                .font(.system(size: 20))
                .foregroundStyle(DS.entityTask)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isActive ? "Pause session" : "Start focus session")
    }

    @ViewBuilder
    private func rowBase(
        _ task: TaskViewModel,
        completionState: CommandCenterTaskCompletionState?,
        isActiveSession: Bool,
        isAnimatingCompletion: Bool,
        showsInlineActions: Bool
    ) -> some View {
        HStack(spacing: 0) {
            rowPriorityLead(task)
            rowContent(
                task,
                completionState: completionState,
                isActiveSession: isActiveSession,
                isAnimatingCompletion: isAnimatingCompletion,
                showsInlineActions: showsInlineActions
            )
            .padding(.trailing, DS.space8)
        }
        .padding(.vertical, DS.space6)
    }

    @ViewBuilder
    private func rowPriorityLead(_ task: TaskViewModel) -> some View {
        if task.priority == .high || task.priority == .critical {
            Rectangle()
                .fill(task.priority.color.opacity(0.36))
                .frame(width: 3.5, height: 3.5)
                .rotationEffect(.degrees(45))
                .padding(.leading, 6)
                .padding(.trailing, 2)
        } else {
            Spacer().frame(width: 12)
        }
    }

    private func rowBackground(
        task: TaskViewModel,
        isActiveSession: Bool,
        isMultiSelected: Bool,
        isKeyboardSelected: Bool,
        isHovered: Bool
    ) -> some View {
        CommandCenterRowGlass(
            isActive: isActiveSession,
            isSelected: isMultiSelected || isKeyboardSelected,
            isHovered: isHovered,
            tint: task.priority.color
        )
    }

    @ViewBuilder
    private func rowPriorityWash(_ task: TaskViewModel, isAnimatingCompletion: Bool) -> some View {
        if !task.isCompleted && !isAnimatingCompletion {
            LinearGradient(
                colors: [task.priority.color.opacity(0.035), Color.clear],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.4, y: 0.5)
            )
            .frame(height: 1)
            .clipShape(.rect(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func rowContent(
        _ task: TaskViewModel,
        completionState: CommandCenterTaskCompletionState?,
        isActiveSession: Bool,
        isAnimatingCompletion: Bool,
        showsInlineActions: Bool
    ) -> some View {
        HStack(spacing: DS.space10) {
            checkboxButton(task, completionState: completionState)

            taskContent(task, completionState: completionState, isActiveSession: isActiveSession)

            Spacer(minLength: DS.space8)

            // Inside Today, "Due today" is ambient context — every row
            // repeating it is chrome noise (Things shows nothing). Overdue
            // keeps its chip; other lists keep due dates. Overdue is judged
            // from the VIEWED day, so scrolling back to a task's due day drops
            // the "Overdue" chip — it's a normal item that day.
            let overdue = task.isOverdue(asOf: viewModel.selectedDate)
            if let dueInfo = task.dueInfo(asOf: viewModel.selectedDate), !task.isCompleted,
               viewModel.viewMode != .today || overdue {
                dueDateChip(dueInfo, isOverdue: overdue)
            } else {
                Color.clear
                    .frame(width: 76, height: 1)
            }

            if !task.isCompleted && !isAnimatingCompletion {
                HStack(spacing: DS.space4) {
                    playButton(task, isActive: isActiveSession)
                    taskActionButton(task)
                }
                .opacity(showsInlineActions ? 1 : 0)
            }
        }
    }

    private func taskActionButton(_ task: TaskViewModel) -> some View {
        CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
            .taskActions(task: task, anchor: anchor)
        } label: {
            Image(systemName: "ellipsis")
                .font(DS.caption2).fontWeight(.bold)
                .foregroundStyle(composer.isShowingTaskAction(for: task.uuid) ? DS.text : DS.textMuted)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(composer.isShowingTaskAction(for: task.uuid) ? DS.accentSoft : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(
                            composer.isShowingTaskAction(for: task.uuid) ? DS.accent.opacity(0.22) : Color.clear,
                            lineWidth: 0.8
                        )
                )
        }
    }

    private func handleRowTap(_ task: TaskViewModel, isAnimatingCompletion: Bool) {
        guard !isAnimatingCompletion else { return }
        // ⌘-click is the Mac's toggle-into-selection gesture (shift kept for
        // muscle memory until range selection lands).
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) || modifiers.contains(.shift) {
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
        let presentation = emptyStatePresentation(message: message, icon: icon)
        return CommandCenterEmptyPane(
            icon: icon,
            title: presentation.title,
            subtitle: presentation.subtitle
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space16)
    }

    private func emptyStatePresentation(message: String, icon: String) -> (title: String, subtitle: String) {
        switch icon {
        case "calendar":
            return ("Today is clear", "Add a task or drag one into Today when you are ready to schedule it.")
        case "checkmark.circle":
            return ("No completed tasks yet", "Completed tasks will collect here as you finish the day.")
        case "tray.full":
            return ("No anytime tasks", "Tasks without a date will wait here until you are ready to plan them.")
        case "archivebox":
            return ("Someday is empty", "Park ideas here when they matter, but not today.")
        case "folder":
            return ("No tasks in this project yet", "Add the next concrete step and keep the project moving.")
        default:
            return (message, "Add a task when you are ready.")
        }
    }

    private func handleTaskCompletionTap(_ task: TaskViewModel) {
        guard completionStates[task.uuid] == nil else { return }

        if task.isCompleted {
            Task { _ = await viewModel.uncompleteTask(task) }
            return
        }

        let timings = CommandCenterCompletionTimings(reduceMotion: reduceMotion)
        // The signature cue rides the animation keyframes: swish with the
        // ring, pen stroke with the check, landing note with the strike.
        Sound.taskCompletion(timings: timings)
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
                    // Settle into the receded "completed" look (0.7, matching the
                    // Completed section) and drift downward — the row files itself
                    // into the pile below instead of vanishing, so the hand-off to
                    // the Completed section reads as one continuous move.
                    state.rowOpacity = 0.7
                    state.rowOffsetY = reduceMotion ? 4 : 12
                }
            }

            try? await Task.sleep(nanoseconds: timings.fadeDuration.nanoseconds)
            let completed = await viewModel.completeTask(task)

            if completed {
                completionStates.removeValue(forKey: task.uuid)
                viewModel.notifyCompletedTaskArrival()
                // The last open task of the day fell — the one earned moment.
                // (completeTask refreshed the section arrays before returning,
                // so isDayClear speaks the post-completion truth.)
                if viewModel.viewMode == .today, viewModel.isDayClear {
                    Sound.dayClear()
                }
            } else {
                // Persistence failed — reverse the optimistic animation so the row comes
                // back instead of silently vanishing while the task stays incomplete.
                // Habit/XP credit was withheld inside completeTask.
                withAnimation(.easeOut(duration: 0.2)) {
                    updateCompletionState(for: task.uuid) { state in
                        state = .initial
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                completionStates.removeValue(forKey: task.uuid)
            }
        }
    }

    private func updateCompletionState(for taskUUID: String, _ update: (inout CommandCenterTaskCompletionState) -> Void) {
        var state = completionStates[taskUUID] ?? .initial
        update(&state)
        completionStates[taskUUID] = state
    }

    /// The one duration voice: "2h 9m", never "129m".
    static func durationLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
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

// MARK: - Evening register (Plan Tomorrow)

/// The "plan tomorrow today" ritual as a door: one click lands on tomorrow's
/// page with the capture row waiting (⌥⌘← comes back; the masthead's Today
/// pill appears on the far side). The glance line answers "how loaded is
/// tomorrow already?" before you commit the evening to it.
private struct EveningPlanRow: View {
    var viewModel: CommandCenterDashboardViewModel

    @State private var plannedCount: Int?
    @State private var isHovered = false

    private var tomorrow: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    private var metaLine: String {
        let dayName = tomorrow.formatted(.dateTime.weekday(.wide))
        guard let plannedCount else { return dayName }
        if plannedCount == 0 { return "\(dayName) · a clear slate" }
        return "\(dayName) · \(plannedCount) already waiting"
    }

    var body: some View {
        Button {
            withAnimation(ProMotionSprings.focusTransition) {
                viewModel.shiftSelectedDay(by: 1)
            }
        } label: {
            HStack(spacing: DS.space10) {
                Image(systemName: "moon.stars")
                    .font(DS.caption)
                    .foregroundStyle(DS.gilt)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Plan tomorrow")
                        .font(DS.callout.weight(.medium))
                        .foregroundStyle(DS.text)
                    Text(metaLine)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(isHovered ? DS.text : DS.textMuted)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                    .fill(isHovered ? DS.glassCardFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, DS.space8)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Open tomorrow (⌥⌘→)")
        // Re-glance when today's ledger changes — pushing a task to tomorrow
        // updates the waiting count the moment the row departs.
        .task(id: viewModel.currentVisibleTasks.count) {
            plannedCount = await viewModel.plannedOpenCount(for: tomorrow)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan tomorrow. \(metaLine). Opens tomorrow's page.")
    }
}

private extension Double {
    var nanoseconds: UInt64 {
        UInt64((self * 1_000_000_000).rounded())
    }
}
