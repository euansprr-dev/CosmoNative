// Canvas/CommandCenter/UpcomingBoardView.swift
// Todoist-style horizontal board: day columns, calendar events, drag+drop, week nav
// March 2026

import SwiftUI

struct UpcomingBoardView: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State private var addingTaskInColumn: String?
    @State private var newTaskText = ""
    @State private var dropTargetDay: String?
    @State private var selectedTaskUUIDs: Set<String> = []
    @FocusState private var addTaskFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            boardHeader

            // Batch action bar
            if !selectedTaskUUIDs.isEmpty {
                batchActionBar
            }

            boardContent
        }
    }

    // MARK: - Header

    private var boardHeader: some View {
        HStack {
            Text(monthYearLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.textSecondary)

            Spacer()

            weekNavigation
        }
    }

    private var monthYearLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: viewModel.upcomingWeekStart)
    }

    private var weekNavigation: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftUpcomingWeek(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.resetUpcomingToToday()
                }
            } label: {
                Text("Today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftUpcomingWeek(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Board Content

    private var boardContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                // Overdue column (only when on current week and has overdue tasks)
                if viewModel.upcomingWeekOffset == 0 && !viewModel.overdueTasks.isEmpty {
                    overdueColumn
                }

                // Day columns
                ForEach(viewModel.upcomingDayGroups) { day in
                    dayColumn(day)
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Overdue Column

    private var overdueColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Text("Overdue")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(PlannerumColors.overdue)

                Text("\(viewModel.overdueTasks.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PlannerumColors.overdue.opacity(0.7))

                Spacer()

                Button {
                    // Reschedule all overdue to today
                    Task {
                        for task in viewModel.overdueTasks {
                            await viewModel.moveTask(uuid: task.uuid, toDate: Date())
                        }
                    }
                } label: {
                    Text("Reschedule")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PlannerumColors.overdue)
                }
                .buttonStyle(.plain)
            }

            // Task cards
            ForEach(viewModel.overdueTasks) { task in
                boardTaskCard(task)
                    .draggable(task.uuid)
            }
        }
        .frame(width: 220)
    }

    // MARK: - Day Column

    @ViewBuilder
    private func dayColumn(_ day: UpcomingDayViewModel) -> some View {
        let dayKey = day.date.formatted(.iso8601.year().month().day())
        let isDropTarget = dropTargetDay == dayKey

        VStack(alignment: .leading, spacing: 8) {
            // Column header
            dayColumnHeader(day)

            // Calendar events card
            calendarEventsCard(for: day)

            // Task cards
            ForEach(day.tasks) { task in
                boardTaskCard(task)
                    .draggable(task.uuid)
            }

            // Add task
            addTaskButton(dayKey: dayKey, date: day.date)
        }
        .frame(width: 220)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDropTarget ? DS.accent.opacity(0.04) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDropTarget ? DS.accent.opacity(0.4) : Color.clear, lineWidth: 2)
                .animation(ProMotionSprings.snappy, value: isDropTarget)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let taskUUID = items.first else { return false }
            Task { await viewModel.moveTask(uuid: taskUUID, toDate: day.date) }
            return true
        } isTargeted: { targeted in
            withAnimation(ProMotionSprings.snappy) {
                dropTargetDay = targeted ? dayKey : nil
            }
        }
    }

    private func dayColumnHeader(_ day: UpcomingDayViewModel) -> some View {
        HStack(spacing: 6) {
            Text(dayHeaderLabel(day))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(day.isToday ? DS.text : DS.textSecondary)

            Text("\(day.taskCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textMuted)

            Spacer()
        }
    }

    private func dayHeaderLabel(_ day: UpcomingDayViewModel) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        let dateStr = formatter.string(from: day.date)

        if day.isToday { return "\(dateStr) · Today" }
        if day.isTomorrow { return "\(dateStr) · Tomorrow" }

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE"
        return "\(dateStr) · \(weekdayFormatter.string(from: day.date))"
    }

    // MARK: - Calendar Events Card

    @ViewBuilder
    private func calendarEventsCard(for day: UpcomingDayViewModel) -> some View {
        let dayKey = day.date.formatted(.iso8601.year().month().day())
        let events = viewModel.upcomingCalendarEvents[dayKey] ?? []

        if !events.isEmpty {
            CalendarEventsCard(events: events)
        }
    }

    // MARK: - Task Card (Todoist style)

    private func boardTaskCard(_ task: TaskViewModel) -> some View {
        let isSelected = selectedTaskUUIDs.contains(task.uuid)

        return HStack(alignment: .top, spacing: 10) {
            // Checkbox
            Button {
                Task { await viewModel.toggleTaskCompletion(task) }
            } label: {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(task.priority.color.opacity(0.5), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if let dueInfo = task.dueInfo {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(dueInfo)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(task.isOverdue ? PlannerumColors.overdue : DS.textMuted)
                    }

                    if task.intent != .general {
                        HStack(spacing: 3) {
                            Image(systemName: task.intent.iconName)
                                .font(.system(size: 9))
                            Text(task.intent.displayName)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(task.intent.color.opacity(0.8))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? DS.accent.opacity(0.06) : DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? DS.accent.opacity(0.4) : DS.borderSubtle, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.shift) {
                // Shift+click: toggle selection
                if selectedTaskUUIDs.contains(task.uuid) {
                    selectedTaskUUIDs.remove(task.uuid)
                } else {
                    selectedTaskUUIDs.insert(task.uuid)
                }
            } else {
                selectedTaskUUIDs.removeAll()
            }
        }
        .contextMenu {
            Button {
                Task { await viewModel.toggleTaskCompletion(task) }
            } label: {
                Label(task.isCompleted ? "Mark Incomplete" : "Complete", systemImage: task.isCompleted ? "circle" : "checkmark.circle")
            }

            Divider()

            Button(role: .destructive) {
                if selectedTaskUUIDs.contains(task.uuid) {
                    // Delete all selected
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

    // MARK: - Add Task Button

    @ViewBuilder
    private func addTaskButton(dayKey: String, date: Date) -> some View {
        if addingTaskInColumn == dayKey {
            inlineAddField(dayKey: dayKey, date: date)
        } else {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    addingTaskInColumn = dayKey
                    newTaskText = ""
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    addTaskFocused = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PlannerumColors.overdue)

                    Text("Add task")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private func inlineAddField(dayKey: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                if newTaskText.isEmpty {
                    Text("Task name")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textMuted)
                        .allowsHitTesting(false)
                }
                TextField("", text: $newTaskText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(DS.text)
                    .focused($addTaskFocused)
                    .onSubmit {
                        submitInlineTask(date: date)
                    }
                    .onExitCommand {
                        withAnimation(ProMotionSprings.snappy) {
                            addingTaskInColumn = nil
                            newTaskText = ""
                        }
                    }
            }

            HStack(spacing: 8) {
                Button {
                    submitInlineTask(date: date)
                } label: {
                    Text("Add task")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(DS.accent, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        addingTaskInColumn = nil
                        newTaskText = ""
                    }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.accent.opacity(0.3), lineWidth: 1)
        )
    }

    private func submitInlineTask(date: Date) {
        let title = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let parsed = TaskInputParser.parse(title)
        var enriched = parsed
        if enriched.dueDate == nil {
            enriched = ParsedTaskInput(
                title: parsed.title,
                priority: parsed.priority,
                dueDate: date,
                scheduledTime: parsed.scheduledTime,
                estimatedMinutes: parsed.estimatedMinutes,
                intent: parsed.intent
            )
        }

        Task {
            await viewModel.smartAddTask(enriched)
            await viewModel.loadUpcomingTasks()
        }

        withAnimation(ProMotionSprings.snappy) {
            newTaskText = ""
            addingTaskInColumn = nil
        }
    }
}

// MARK: - Calendar Events Card

private struct CalendarEventsCard: View {
    let events: [CalendarEvent]
    @State private var isExpanded = false

    private var visibleEvents: [CalendarEvent] {
        isExpanded ? events : Array(events.prefix(4))
    }

    private var hiddenCount: Int {
        max(events.count - 4, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleEvents, id: \.id) { event in
                eventRow(event)
            }

            if hiddenCount > 0 && !isExpanded {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        isExpanded = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        ForEach(0..<min(hiddenCount, 3), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(DS.textMuted)
                                .frame(width: 3, height: 10)
                        }
                        Text("\(hiddenCount) more")
                            .font(.system(size: 10))
                            .foregroundColor(DS.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            // Collapse button at top-right
            if events.count > 4 {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.textMuted)
                            .frame(width: 24, height: 20)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 6)
                .padding(.top, -4)
            }
        }
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 6) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.calendarColor))
                .frame(width: 3, height: 16)

            // Time range + title
            if let timeStr = eventTimeString(event) {
                Text(timeStr)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
            }

            Text(event.title)
                .font(.system(size: 11))
                .foregroundColor(DS.text)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func eventTimeString(_ event: CalendarEvent) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: event.startDate)

        if event.durationMinutes > 0 && event.durationMinutes < 1440 {
            let end = formatter.string(from: event.endDate)
            return "\(start)-\(end)"
        }
        return start
    }
}
