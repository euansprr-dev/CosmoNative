// Canvas/CommandCenter/DashboardTaskList.swift
// Todoist-style sectioned task list with priority bars, due chips, and inline play
// March 2026

import SwiftUI

struct DashboardTaskList: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State var expandedTaskId: String?

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
        // Overdue section
        if !viewModel.overdueTasks.isEmpty {
            taskSection(
                title: "Overdue",
                tasks: viewModel.overdueTasks,
                headerColor: PlannerumColors.overdue,
                showReschedule: true
            )
        }

        // Scheduled section
        if !viewModel.scheduledTasks.isEmpty {
            taskSection(
                title: "Scheduled",
                tasks: viewModel.scheduledTasks,
                headerColor: DS.textSecondary
            )
        }

        // Unscheduled section
        taskSection(
            title: viewModel.overdueTasks.isEmpty && viewModel.scheduledTasks.isEmpty
                ? "Tasks" : "Unscheduled",
            tasks: viewModel.unscheduledTasks,
            headerColor: DS.textSecondary,
            showAddRow: true
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
        if viewModel.completedTodayTasks.isEmpty {
            emptyState(message: "No tasks completed today", icon: "checkmark.circle")
        } else {
            sectionHeader(title: "Completed Today", color: DS.green, trailing: "\(viewModel.completedTodayTasks.count)")

            ForEach(viewModel.completedTodayTasks) { task in
                taskRow(task)
            }
        }
    }

    // MARK: - Section Component

    @ViewBuilder
    private func taskSection(
        title: String,
        tasks: [TaskViewModel],
        headerColor: Color,
        showReschedule: Bool = false,
        showAddRow: Bool = false
    ) -> some View {
        sectionHeader(
            title: title,
            color: headerColor,
            trailing: tasks.isEmpty ? nil : "\(tasks.count)",
            showReschedule: showReschedule
        )

        ForEach(tasks) { task in
            taskRow(task)

            if expandedTaskId == task.uuid {
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
                    // TODO: batch reschedule overdue tasks
                } label: {
                    Text("Reschedule")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PlannerumColors.overdue)
                }
                .buttonStyle(.plain)
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
        let isSelected = viewModel.selectedTaskIndex != nil
            && viewModel.currentVisibleTasks.indices.contains(viewModel.selectedTaskIndex!)
            && viewModel.currentVisibleTasks[viewModel.selectedTaskIndex!].uuid == task.uuid

        HStack(spacing: 0) {
            // Priority color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(task.priority.color)
                .frame(width: 4)
                .padding(.vertical, 4)

            HStack(spacing: 10) {
                // Checkbox
                checkboxButton(task)

                // Title + meta
                taskContent(task)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(ProMotionSprings.snappy) {
                            expandedTaskId = expandedTaskId == task.uuid ? nil : task.uuid
                        }
                    }

                Spacer(minLength: 4)

                // Due date chip
                if let dueInfo = task.dueInfo, !task.isCompleted {
                    dueDateChip(dueInfo, isOverdue: task.isOverdue)
                }

                // Duration pill
                if !task.isCompleted && task.estimatedMinutes > 0 {
                    durationPill(task)
                }

                // Play button
                if !task.isCompleted {
                    playButton(task, isActive: isActiveSession)
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
                        : isSelected ? DS.accentSoft
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isActiveSession ? DS.accent.opacity(0.3)
                        : isSelected ? DS.accent.opacity(0.2)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
    }

    // MARK: - Checkbox

    @ViewBuilder
    private func checkboxButton(_ task: TaskViewModel) -> some View {
        Button {
            Task { await viewModel.toggleTaskCompletion(task) }
        } label: {
            ZStack {
                Circle()
                    .stroke(
                        task.isCompleted ? DS.accent : task.priority.color.opacity(0.5),
                        lineWidth: 1.5
                    )
                    .frame(width: 18, height: 18)

                if task.isCompleted {
                    Circle()
                        .fill(DS.accent)
                        .frame(width: 18, height: 18)

                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Task Content

    @ViewBuilder
    private func taskContent(_ task: TaskViewModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if task.intent != .general {
                    Image(systemName: task.intent.iconName)
                        .font(.system(size: 9))
                        .foregroundColor(task.intent.color.opacity(0.7))
                }

                Text(task.title)
                    .font(.system(size: 13, weight: task.isCompleted ? .regular : .medium))
                    .foregroundColor(task.isCompleted ? DS.textMuted : DS.text)
                    .strikethrough(task.isCompleted, color: DS.textMuted)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if let timeInfo = task.timeInfo {
                    Label(timeInfo, systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
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

    // MARK: - Duration Pill

    private func durationPill(_ task: TaskViewModel) -> some View {
        Text("\(task.estimatedMinutes)m")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(DS.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DS.surface, in: Capsule())
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
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(DS.textMuted)

            Text(message)
                .font(DS.cardMeta)
                .foregroundColor(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
