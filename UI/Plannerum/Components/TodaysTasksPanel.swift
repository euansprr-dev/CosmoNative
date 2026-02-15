//
//  TodaysTasksPanel.swift
//  CosmoOS
//
//  Panel displaying today's tasks with checkboxes, priority indicators,
//  due times, and quick-add functionality.
//

import SwiftUI

// MARK: - TodaysTasksPanel

/// Panel showing today's tasks with completion controls
public struct TodaysTasksPanel: View {

    // MARK: - Properties

    let tasks: [TaskViewModel]
    let onTaskComplete: (String) -> Void
    let onTaskTap: (TaskViewModel) -> Void
    let onAddTask: () -> Void

    @State private var isExpanded = true
    @State private var showQuickAdd = false
    @State private var quickAddText = ""
    @FocusState private var isQuickAddFocused: Bool

    // MARK: - Computed

    private var overdueTasks: [TaskViewModel] {
        tasks.filter { $0.isOverdue && !$0.isCompleted }
    }

    private var dueTodayTasks: [TaskViewModel] {
        tasks.filter { $0.isDueToday && !$0.isOverdue && !$0.isCompleted }
    }

    private var scheduledTasks: [TaskViewModel] {
        tasks.filter { !$0.isDueToday && !$0.isOverdue && !$0.isCompleted }
    }

    private var completedTasks: [TaskViewModel] {
        tasks.filter { $0.isCompleted }
    }

    private var pendingCount: Int {
        tasks.filter { !$0.isCompleted }.count
    }

    private var completedCount: Int {
        completedTasks.count
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            panelHeader

            if isExpanded {
                // Task sections
                ScrollView {
                    VStack(spacing: NowViewTokens.rowSpacing) {
                        // Overdue section
                        if !overdueTasks.isEmpty {
                            taskSection(title: "OVERDUE", tasks: overdueTasks, style: .overdue)
                        }

                        // Due today section
                        if !dueTodayTasks.isEmpty {
                            taskSection(title: "DUE TODAY", tasks: dueTodayTasks, style: .dueToday)
                        }

                        // Scheduled section
                        if !scheduledTasks.isEmpty {
                            taskSection(title: "SCHEDULED", tasks: scheduledTasks, style: .normal)
                        }

                        // Completed section (collapsed by default)
                        if !completedTasks.isEmpty {
                            completedSection
                        }

                        // Quick add
                        quickAddSection
                    }
                    .padding(.horizontal, NowViewTokens.rowPadding)
                    .padding(.bottom, NowViewTokens.rowPadding)
                }

                // Empty state
                if tasks.isEmpty {
                    emptyState
                }
            }
        }
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: NowViewTokens.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NowViewTokens.cornerRadius, style: .continuous)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var panelHeader: some View {
        Button(action: { withAnimation(PlannerumSprings.expand) { isExpanded.toggle() } }) {
            HStack(spacing: 8) {
                // Icon
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PlannerumColors.tasksInbox)

                // Title
                Text("TODAY'S TASKS")
                    .font(NowViewTokens.sectionHeaderFont)
                    .tracking(PlannerumTypography.trackingWide)
                    .foregroundColor(PlannerumColors.textSecondary)

                Spacer()

                // Count badges
                HStack(spacing: 8) {
                    // Pending count
                    Text("\(pendingCount) pending")
                        .font(NowViewTokens.countFont)
                        .foregroundColor(PlannerumColors.textTertiary)

                    // Completed count
                    if completedCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(completedCount)")
                        }
                        .font(NowViewTokens.countFont)
                        .foregroundColor(NowViewTokens.checkboxChecked)
                    }
                }

                // Add button
                Button(action: {
                    showQuickAdd = true
                    isQuickAddFocused = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(PlannerumColors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Expand/collapse chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .padding(NowViewTokens.rowPadding)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Task Section

    enum SectionStyle {
        case overdue
        case dueToday
        case normal
    }

    private func taskSection(title: String, tasks: [TaskViewModel], style: SectionStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section header
            HStack(spacing: 6) {
                if style == .overdue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(NowViewTokens.priorityCritical)
                }

                Text(title)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(style == .overdue ? NowViewTokens.priorityCritical : PlannerumColors.textMuted)
            }
            .padding(.leading, 4)

            // Task rows
            ForEach(tasks) { task in
                TaskRow(
                    task: task,
                    style: style,
                    onComplete: { onTaskComplete(task.id) },
                    onTap: { onTaskTap(task) }
                )
            }
        }
    }

    // MARK: - Completed Section

    @State private var showCompleted = false

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Collapsible header
            Button(action: { withAnimation(PlannerumSprings.expand) { showCompleted.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlannerumColors.textMuted)

                    Text("COMPLETED")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .foregroundColor(PlannerumColors.textMuted)

                    Text("(\(completedTasks.count))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PlannerumColors.textMuted)

                    Spacer()
                }
                .padding(.leading, 4)
            }
            .buttonStyle(.plain)

            if showCompleted {
                ForEach(completedTasks) { task in
                    TaskRow(
                        task: task,
                        style: .normal,
                        isCompleted: true,
                        onComplete: { onTaskComplete(task.id) },
                        onTap: { onTaskTap(task) }
                    )
                }
            }
        }
    }

    // MARK: - Quick Add

    private var quickAddSection: some View {
        VStack(spacing: 0) {
            if showQuickAdd {
                HStack(spacing: 8) {
                    // Checkbox placeholder
                    Circle()
                        .strokeBorder(NowViewTokens.checkboxBorder, lineWidth: 1.5)
                        .frame(width: NowViewTokens.checkboxSize, height: NowViewTokens.checkboxSize)

                    // Text field
                    TextField("Add a task...", text: $quickAddText)
                        .textFieldStyle(.plain)
                        .font(NowViewTokens.taskTitleFont)
                        .foregroundColor(PlannerumColors.textPrimary)
                        .focused($isQuickAddFocused)
                        .onSubmit {
                            submitQuickAdd()
                        }

                    // Cancel button
                    Button(action: cancelQuickAdd) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(PlannerumColors.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, NowViewTokens.rowPadding)
                .background(NowViewTokens.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                // Add task button
                Button(action: {
                    showQuickAdd = true
                    isQuickAddFocused = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(PlannerumColors.primary.opacity(0.6))

                        Text("Add task")
                            .font(NowViewTokens.taskTitleFont)
                            .foregroundColor(PlannerumColors.textTertiary)

                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, NowViewTokens.rowPadding)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func submitQuickAdd() {
        guard !quickAddText.trimmingCharacters(in: .whitespaces).isEmpty else {
            cancelQuickAdd()
            return
        }

        onAddTask()
        quickAddText = ""
        showQuickAdd = false
    }

    private func cancelQuickAdd() {
        quickAddText = ""
        showQuickAdd = false
        isQuickAddFocused = false
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(PlannerumColors.primary.opacity(0.4))

            VStack(spacing: 6) {
                Text("Your day is clear")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PlannerumColors.textSecondary)

                Text("Create a task or let Plannerum suggest what to work on.")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }

            HStack(spacing: 12) {
                Button(action: {
                    showQuickAdd = true
                    isQuickAddFocused = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add Task")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(PlannerumColors.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: {
                    NotificationCenter.default.post(
                        name: .suggestTasks,
                        object: nil
                    )
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11))
                        Text("Suggest Tasks")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(PlannerumColors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - TaskRow

/// Individual task row with checkbox and metadata
struct TaskRow: View {

    let task: TaskViewModel
    let style: TodaysTasksPanel.SectionStyle
    var isCompleted: Bool = false
    let onComplete: () -> Void
    let onTap: () -> Void

    @State private var isHovering = false
    @State private var isChecked = false
    @State private var checkboxScale: CGFloat = 1.0
    @State private var showXPFloat = false
    @State private var xpFloatOffset: CGFloat = 0
    @State private var xpFloatOpacity: Double = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    // Priority indicator
                    Rectangle()
                        .fill(priorityColor)
                        .frame(width: NowViewTokens.priorityIndicatorWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 2))

                    // Checkbox
                    checkboxButton

                    // Task content
                    VStack(alignment: .leading, spacing: 2) {
                        // Title
                        HStack(spacing: 4) {
                            if task.isRecurring {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(PlannerumColors.textTertiary)
                            }

                            Text(task.title)
                                .font(isCompleted ? NowViewTokens.taskTitleCompletedFont : NowViewTokens.taskTitleFont)
                                .foregroundColor(isCompleted ? PlannerumColors.textMuted : PlannerumColors.textPrimary)
                                .strikethrough(isCompleted)
                                .lineLimit(1)
                        }

                        // Metadata row
                        HStack(spacing: 8) {
                            // Project tag
                            if let projectName = task.projectName {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(task.projectColor)
                                        .frame(width: 6, height: 6)
                                    Text(projectName)
                                        .font(NowViewTokens.projectTagFont)
                                }
                                .foregroundColor(PlannerumColors.textTertiary)
                            }

                            // Time
                            if let timeInfo = task.timeInfo {
                                HStack(spacing: 2) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 9))
                                    Text(timeInfo)
                                        .font(NowViewTokens.dueTimeFont)
                                }
                                .foregroundColor(PlannerumColors.textTertiary)
                            }

                            // Due indicator
                            if let dueInfo = task.dueInfo, !isCompleted {
                                HStack(spacing: 2) {
                                    Image(systemName: task.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                                        .font(.system(size: 9))
                                    Text(dueInfo)
                                        .font(NowViewTokens.dueTimeFont)
                                }
                                .foregroundColor(task.isOverdue ? NowViewTokens.priorityCritical : NowViewTokens.priorityHigh)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(task.isOverdue ? NowViewTokens.overdueBackground : NowViewTokens.dueTodayBackground)
                                .clipShape(RoundedRectangle(cornerRadius: NowViewTokens.dueBadgeRadius))
                            }
                        }
                    }

                    Spacer()

                    // XP badge
                    if !isCompleted {
                        HStack(spacing: 2) {
                            Text("+\(task.estimatedXP)")
                                .font(NowViewTokens.xpFont)
                            Text("XP")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(PlannerumColors.xpGold.opacity(0.7))
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, NowViewTokens.rowPadding)
                .frame(height: NowViewTokens.taskRowHeight)
                .background(rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(isCompleted ? NowViewTokens.completedOpacity : 1.0)
            }
            .buttonStyle(.plain)

            // XP float animation overlay
            if showXPFloat {
                Text("+\(task.estimatedXP) XP")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(PlannerumColors.xpGold)
                    .opacity(xpFloatOpacity)
                    .offset(y: xpFloatOffset)
                    .padding(.trailing, 16)
                    .allowsHitTesting(false)
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            if task.isRecurring && task.recurrenceParentUUID != nil {
                Button {
                    onTap()
                } label: {
                    Label("Edit This Task Only", systemImage: "pencil")
                }

                Button {
                    // Post notification to edit the template
                    NotificationCenter.default.post(
                        name: .editRecurringTemplate,
                        object: nil,
                        userInfo: ["templateUUID": task.recurrenceParentUUID ?? ""]
                    )
                } label: {
                    Label("Edit All Future Tasks", systemImage: "arrow.triangle.2.circlepath")
                }

                Divider()
            }

            Button {
                onComplete()
            } label: {
                Label(isCompleted ? "Mark Incomplete" : "Mark Complete", systemImage: isCompleted ? "circle" : "checkmark.circle")
            }
        }
        .onAppear {
            isChecked = task.isCompleted
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .critical: return NowViewTokens.priorityCritical
        case .high: return NowViewTokens.priorityHigh
        case .medium: return NowViewTokens.priorityMedium
        case .low: return NowViewTokens.priorityLow
        }
    }

    private var checkboxButton: some View {
        Button(action: {
            withAnimation(NowViewTokens.checkAnimation) {
                isChecked.toggle()
            }

            // Scale bounce: 1.0 -> 1.1 -> 1.0
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                checkboxScale = 1.15
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                    checkboxScale = 1.0
                }
            }

            // XP float animation on check (not uncheck)
            if !isChecked == false {
                showXPFloat = true
                xpFloatOffset = 0
                xpFloatOpacity = 0

                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    xpFloatOpacity = 1.0
                }
                withAnimation(.easeOut(duration: 0.8).delay(0.05)) {
                    xpFloatOffset = -30
                }
                withAnimation(.easeOut(duration: 0.25).delay(0.6)) {
                    xpFloatOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    showXPFloat = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onComplete()
            }
        }) {
            ZStack {
                if isChecked || isCompleted {
                    Circle()
                        .fill(NowViewTokens.checkboxChecked)
                        .frame(width: NowViewTokens.checkboxSize, height: NowViewTokens.checkboxSize)

                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .strokeBorder(NowViewTokens.checkboxBorder, lineWidth: 1.5)
                        .frame(width: NowViewTokens.checkboxSize, height: NowViewTokens.checkboxSize)
                }
            }
            .scaleEffect(checkboxScale)
        }
        .buttonStyle(.plain)
    }

    private var rowBackground: some View {
        Group {
            if style == .overdue {
                NowViewTokens.overdueBackground
            } else if isHovering {
                NowViewTokens.rowBackgroundHover
            } else {
                NowViewTokens.rowBackground
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TodaysTasksPanel_Previews: PreviewProvider {
    static var sampleTasks: [TaskViewModel] {
        [
            TaskViewModel(
                uuid: "1",
                title: "Review quarterly metrics dashboard",
                projectName: "Analytics",
                projectColor: .blue,
                dueDate: Calendar.current.date(byAdding: .hour, value: -2, to: Date()),
                scheduledTime: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()),
                estimatedMinutes: 45,
                priority: .critical
            ),
            TaskViewModel(
                uuid: "2",
                title: "Send project update email",
                projectName: "Communications",
                projectColor: .orange,
                dueDate: Calendar.current.date(byAdding: .hour, value: 4, to: Date()),
                estimatedMinutes: 15,
                priority: .high
            ),
            TaskViewModel(
                uuid: "3",
                title: "Prepare presentation slides",
                projectName: "Strategy",
                projectColor: .purple,
                scheduledDate: Date(),
                estimatedMinutes: 60,
                priority: .medium
            ),
            TaskViewModel(
                uuid: "4",
                title: "Completed task example",
                estimatedMinutes: 30,
                priority: .low,
                isCompleted: true,
                completedAt: Date()
            )
        ]
    }

    static var previews: some View {
        ZStack {
            PlannerumColors.voidPrimary.ignoresSafeArea()

            TodaysTasksPanel(
                tasks: sampleTasks,
                onTaskComplete: { _ in },
                onTaskTap: { _ in },
                onAddTask: {}
            )
            .frame(maxWidth: 500)
            .padding(24)
        }
        .frame(width: 600, height: 600)
    }
}
#endif
