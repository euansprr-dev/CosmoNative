// CosmoOS/Canvas/TaskBlockView.swift
// Premium Task block with status, priority, and progress visualization
// Coral-tinted for energy and action

import SwiftUI
import GRDB

struct TaskBlockView: View {
    let block: CanvasBlock

    @State private var task: CosmoTask?
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var isLoading = true
    @State private var checklistItems: [ChecklistItem] = []

    @EnvironmentObject private var expansionManager: BlockExpansionManager

    private let database = CosmoDatabase.shared

    // MARK: - Computed Properties

    private var isCompleted: Bool {
        task?.status.lowercased() == "done" || task?.status.lowercased() == "completed"
    }

    private var checklistProgress: Double {
        guard !checklistItems.isEmpty else { return 0 }
        let completed = checklistItems.filter { $0.completed }.count
        return Double(completed) / Double(checklistItems.count)
    }

    private var formattedDuration: String? {
        guard let minutes = task?.durationMinutes, minutes > 0 else { return nil }
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
    }

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: CosmoMentionColors.task,
            icon: isCompleted ? "checkmark.circle.fill" : "circle",
            title: task?.title ?? block.title,
            isExpanded: $isExpanded,
            onFocusMode: openFocusMode
        ) {
            contentView
        }
        .onAppear {
            loadTask()
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                loadingView
            } else if let task = task {
                taskContent(task)
            } else {
                emptyView
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Task Content

    @ViewBuilder
    private func taskContent(_ task: CosmoTask) -> some View {
        // Status and priority row
        HStack(spacing: 8) {
            TaskStatusBadge(status: task.status)
            TaskPriorityBadge(priority: task.priority)
            Spacer()

            // Duration if available
            if let duration = formattedDuration {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(duration)
                        .font(CosmoTypography.caption)
                }
                .foregroundColor(CosmoColors.textTertiary)
            }
        }

        // Description
        if let description = task.description, !description.isEmpty {
            Text(description)
                .font(CosmoTypography.bodySmall)
                .foregroundColor(CosmoColors.textSecondary)
                .lineLimit(isExpanded ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Checklist preview
        if !checklistItems.isEmpty {
            ChecklistPreview(
                items: checklistItems,
                progress: checklistProgress,
                isExpanded: isExpanded
            )
        }

        // Due date
        if let dueDate = task.dueDate {
            DueDateBadge(dateString: dueDate)
        }

        // Expanded content
        if isExpanded {
            Divider()
                .background(CosmoMentionColors.task.opacity(0.3))
                .padding(.vertical, 4)

            // Time details
            TaskTimeDetails(task: task)

            // Recurrence info
            if let recurrence = task.recurrence {
                RecurrenceBadge(recurrenceJson: recurrence)
            }

            // Metadata
            TaskMetadataView(task: task)
        }

        Spacer(minLength: 0)

        // Footer
        TaskFooter(task: task, isExpanded: isExpanded, onToggleComplete: toggleComplete)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading task...")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.badge.xmark")
                .font(.system(size: 32))
                .foregroundColor(CosmoColors.textTertiary)
            Text("Task not found")
                .font(CosmoTypography.body)
                .foregroundColor(CosmoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadTask() {
        Task {
            task = try? await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.task.rawValue)
                    .filter(Column("id") == block.entityId)
                    .fetchOne(db)
                    .map { TaskWrapper(atom: $0) }
            }

            // Parse checklist
            if let checklistJson = task?.checklist,
               let data = checklistJson.data(using: .utf8) {
                checklistItems = (try? JSONDecoder().decode([ChecklistItem].self, from: data)) ?? []
            }

            isLoading = false
        }
    }

    private func openFocusMode() {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": EntityType.task, "id": task?.id ?? block.entityId]
        )
    }

    private func toggleComplete() {
        guard let currentTask = task else { return }

        let newStatus = isCompleted ? "pending" : "done"
        let taskUUID = currentTask.uuid
        let updatedAt = ISO8601DateFormatter().string(from: Date())

        Task {
            do {
                try await database.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE tasks SET status = ?, updated_at = ? WHERE uuid = ?",
                        arguments: [newStatus, updatedAt, taskUUID]
                    )
                }

                // Force UI refresh by reloading the task
                loadTask()
            } catch {
                print("Failed to toggle task: \(error)")
            }
        }
    }
}

// MARK: - Checklist Item Model

struct ChecklistItem: Codable, Identifiable {
    let id: String
    var title: String
    var completed: Bool
}

// MARK: - Task Status Badge

struct TaskStatusBadge: View {
    let status: String

    private var statusColor: Color {
        switch status.lowercased() {
        case "done", "completed": return CosmoColors.emerald
        case "in_progress", "active": return CosmoColors.skyBlue
        case "pending", "todo": return CosmoColors.glassGrey
        case "blocked": return CosmoColors.softRed
        default: return CosmoColors.glassGrey
        }
    }

    private var statusIcon: String {
        switch status.lowercased() {
        case "done", "completed": return "checkmark.circle.fill"
        case "in_progress", "active": return "play.circle"
        case "pending", "todo": return "circle"
        case "blocked": return "exclamationmark.circle"
        default: return "circle"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 10))
            Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(CosmoTypography.caption)
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12), in: Capsule())
    }
}

// MARK: - Task Priority Badge

struct TaskPriorityBadge: View {
    let priority: String

    private var priorityColor: Color {
        switch priority.lowercased() {
        case "urgent", "critical": return CosmoColors.softRed
        case "high": return CosmoColors.coral
        case "medium", "normal": return CosmoColors.lavender
        case "low": return CosmoColors.emerald
        default: return CosmoColors.glassGrey
        }
    }

    private var priorityIcon: String {
        switch priority.lowercased() {
        case "urgent", "critical": return "exclamationmark.3"
        case "high": return "flame.fill"
        case "medium", "normal": return "circle.fill"
        case "low": return "leaf.fill"
        default: return "circle"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: priorityIcon)
                .font(.system(size: 8))
            Text(priority.capitalized)
                .font(CosmoTypography.caption)
        }
        .foregroundColor(priorityColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(priorityColor.opacity(0.1), in: Capsule())
    }
}

// MARK: - Checklist Preview

struct ChecklistPreview: View {
    let items: [ChecklistItem]
    let progress: Double
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Progress bar
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: CosmoMentionColors.task))

                Text("\(Int(progress * 100))%")
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
            }

            // Items (show more when expanded)
            let visibleItems = isExpanded ? items : Array(items.prefix(3))
            ForEach(visibleItems) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.completed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundColor(item.completed ? CosmoColors.emerald : CosmoColors.textTertiary)

                    Text(item.title)
                        .font(CosmoTypography.caption)
                        .foregroundColor(item.completed ? CosmoColors.textTertiary : CosmoColors.textSecondary)
                        .strikethrough(item.completed)
                        .lineLimit(1)
                }
            }

            // Overflow indicator
            if !isExpanded && items.count > 3 {
                Text("+\(items.count - 3) more items")
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
            }
        }
        .padding(10)
        .background(CosmoColors.mistGrey.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Due Date Badge

struct DueDateBadge: View {
    let dateString: String

    private var date: Date? {
        ISO8601DateFormatter().date(from: dateString)
    }

    private var isOverdue: Bool {
        guard let date = date else { return false }
        return date < Date()
    }

    private var isDueToday: Bool {
        guard let date = date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private var dueDateColor: Color {
        if isOverdue { return CosmoColors.softRed }
        if isDueToday { return CosmoColors.coral }
        return CosmoColors.textTertiary
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isOverdue ? "exclamationmark.triangle" : "calendar")
                .font(.system(size: 10))
            Text(formattedDate)
                .font(CosmoTypography.caption)
        }
        .foregroundColor(dueDateColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(dueDateColor.opacity(0.1), in: Capsule())
    }

    private var formattedDate: String {
        guard let date = date else { return dateString }

        if isOverdue {
            return "Overdue"
        }

        if isDueToday {
            return "Due today"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Due \(formatter.string(from: date))"
    }
}

// MARK: - Recurrence Badge

struct RecurrenceBadge: View {
    let recurrenceJson: String

    private var recurrenceText: String {
        // Parse recurrence JSON
        guard let data = recurrenceJson.data(using: .utf8),
              let recurrence = try? JSONDecoder().decode(RecurrenceData.self, from: data) else {
            return "Recurring"
        }

        switch recurrence.frequency.lowercased() {
        case "daily": return "Daily"
        case "weekly": return "Weekly"
        case "monthly": return "Monthly"
        case "yearly": return "Yearly"
        default: return "Recurring"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "repeat")
                .font(.system(size: 10))
            Text(recurrenceText)
                .font(CosmoTypography.caption)
        }
        .foregroundColor(CosmoColors.lavender)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(CosmoColors.lavender.opacity(0.1), in: Capsule())
        .transition(.opacity.combined(with: .scale))
    }
}

struct RecurrenceData: Codable {
    let frequency: String
    let interval: Int?
    let days: [String]?
}

// MARK: - Task Time Details

struct TaskTimeDetails: View {
    let task: CosmoTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)

            HStack(spacing: 16) {
                if let startTime = task.startTime {
                    TimeDetail(icon: "play", label: "Start", time: startTime)
                }

                if let endTime = task.endTime {
                    TimeDetail(icon: "stop", label: "End", time: endTime)
                }

                if let focusDate = task.focusDate {
                    TimeDetail(icon: "scope", label: "Focus", time: focusDate)
                }
            }
        }
        .padding(12)
        .background(CosmoMentionColors.task.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct TimeDetail: View {
    let icon: String
    let label: String
    let time: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(CosmoTypography.caption)
            }
            .foregroundColor(CosmoColors.textTertiary)

            Text(formatTime(time))
                .font(CosmoTypography.bodySmall)
                .foregroundColor(CosmoColors.textSecondary)
        }
    }

    private func formatTime(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Task Metadata View

struct TaskMetadataView: View {
    let task: CosmoTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                MetadataRow(icon: "calendar", label: "Created", value: formatDate(task.createdAt))
                MetadataRow(icon: "pencil", label: "Updated", value: formatDate(task.updatedAt))

                if task.isUnscheduled {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 10))
                        Text("Unscheduled")
                            .font(CosmoTypography.caption)
                    }
                    .foregroundColor(CosmoColors.textTertiary)
                }
            }
        }
        .padding(12)
        .background(CosmoColors.mistGrey.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func formatDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Task Footer

struct TaskFooter: View {
    let task: CosmoTask
    let isExpanded: Bool
    let onToggleComplete: () -> Void

    private var isCompleted: Bool {
        task.status.lowercased() == "done" || task.status.lowercased() == "completed"
    }

    var body: some View {
        HStack(spacing: 8) {
            // Last updated
            Text(timeAgo(from: task.updatedAt))
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)

            Spacer()

            // Complete/Uncomplete button
            Button(action: onToggleComplete) {
                HStack(spacing: 4) {
                    Image(systemName: isCompleted ? "arrow.uturn.backward" : "checkmark")
                        .font(.system(size: 10))
                    Text(isCompleted ? "Reopen" : "Complete")
                        .font(CosmoTypography.caption)
                }
                .foregroundColor(isCompleted ? CosmoColors.textSecondary : CosmoColors.emerald)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    (isCompleted ? CosmoColors.glassGrey : CosmoColors.emerald).opacity(0.12),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func timeAgo(from dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return ""
        }

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
