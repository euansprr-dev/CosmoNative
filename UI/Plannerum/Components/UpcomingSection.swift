//
//  UpcomingSection.swift
//  CosmoOS
//
//  Horizontal scrolling section showing upcoming days with their tasks.
//  Allows quick overview of the week ahead with mini task cards.
//

import SwiftUI

// MARK: - UpcomingSection

/// Horizontal scrolling view of upcoming days with their tasks
public struct UpcomingSection: View {

    // MARK: - Properties

    let upcomingDays: [UpcomingDayViewModel]
    let onDayTap: (Date) -> Void
    let onTaskTap: (TaskViewModel) -> Void

    @State private var isExpanded = true

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            sectionHeader

            if isExpanded {
                // Horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: UpcomingSectionTokens.columnSpacing) {
                        ForEach(upcomingDays) { day in
                            DayColumn(
                                day: day,
                                onTap: { onDayTap(day.date) },
                                onTaskTap: onTaskTap
                            )
                        }
                    }
                    .padding(.horizontal, UpcomingSectionTokens.padding)
                    .padding(.bottom, UpcomingSectionTokens.padding)
                }
            }
        }
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: UpcomingSectionTokens.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UpcomingSectionTokens.cornerRadius, style: .continuous)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var sectionHeader: some View {
        Button(action: { withAnimation(PlannerumSprings.expand) { isExpanded.toggle() } }) {
            HStack(spacing: 8) {
                // Icon
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PlannerumColors.primary.opacity(0.8))

                // Title
                Text("Upcoming")
                    .font(OnyxTypography.label)
                    .tracking(OnyxTypography.labelTracking)
                    .foregroundColor(OnyxColors.Text.secondary)

                Spacer()

                // Days summary
                let totalTasks = upcomingDays.reduce(0) { $0 + $1.taskCount }
                if totalTasks > 0 {
                    Text("\(totalTasks) tasks this week")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PlannerumColors.textTertiary)
                }

                // Expand/collapse chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .padding(UpcomingSectionTokens.padding)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DayColumn

/// Column representing a single day with its tasks
struct DayColumn: View {

    let day: UpcomingDayViewModel
    let onTap: () -> Void
    let onTaskTap: (TaskViewModel) -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Day header
                dayHeader

                // Tasks
                VStack(spacing: 6) {
                    ForEach(Array(day.tasks.prefix(UpcomingSectionTokens.maxVisibleTasks))) { task in
                        MiniTaskCard(
                            task: task,
                            onTap: { onTaskTap(task) }
                        )
                    }

                    // More tasks indicator
                    if day.tasks.count > UpcomingSectionTokens.maxVisibleTasks {
                        moreTasksIndicator
                    }

                    // Empty state
                    if day.tasks.isEmpty {
                        emptyDayState
                    }
                }
                .padding(.horizontal, UpcomingSectionTokens.padding)
                .padding(.bottom, UpcomingSectionTokens.padding)

                Spacer(minLength: 0)
            }
            .frame(width: UpcomingSectionTokens.dayColumnWidth)
            .frame(minHeight: UpcomingSectionTokens.dayColumnMinHeight)
            .background(columnBackground)
            .clipShape(RoundedRectangle(cornerRadius: UpcomingSectionTokens.cornerRadius, style: .continuous))
            .overlay(columnBorder)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    // MARK: - Day Header

    private var dayHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Day name
                Text(day.dayName)
                    .font(UpcomingSectionTokens.dayNameFont)
                    .foregroundColor(UpcomingSectionTokens.dayHeaderTextSecondary)

                Spacer()

                // Today/Tomorrow badge
                if day.isToday {
                    Text("Today")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(UpcomingSectionTokens.todayBadge)
                        .clipShape(Capsule())
                } else if day.isTomorrow {
                    Text("Tomorrow")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.5)
                        .foregroundColor(OnyxColors.Text.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Day number
                Text("\(day.dayNumber)")
                    .font(UpcomingSectionTokens.dayNumberFont)
                    .foregroundColor(UpcomingSectionTokens.dayHeaderText)

                Spacer()

                // Task count & deadline indicator
                HStack(spacing: 6) {
                    if day.hasDeadlines {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(UpcomingSectionTokens.deadlineIndicator)
                    }

                    if day.taskCount > 0 {
                        Text("\(day.taskCount)")
                            .font(UpcomingSectionTokens.taskCountFont)
                            .foregroundColor(PlannerumColors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(UpcomingSectionTokens.taskCountBadge)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(UpcomingSectionTokens.padding)
        .frame(height: UpcomingSectionTokens.dayHeaderHeight)
        .background(Color.white.opacity(0.02))
    }

    // MARK: - More Tasks Indicator

    private var moreTasksIndicator: some View {
        HStack {
            Text("+\(day.tasks.count - UpcomingSectionTokens.maxVisibleTasks) more")
                .font(UpcomingSectionTokens.moreTasksFont)
                .foregroundColor(PlannerumColors.textTertiary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(PlannerumColors.textMuted)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: UpcomingSectionTokens.miniCardRadius, style: .continuous))
    }

    // MARK: - Empty State

    private var emptyDayState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(PlannerumColors.textMuted.opacity(0.5))

            Text("No tasks")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PlannerumColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Background & Border

    private var columnBackground: some View {
        Group {
            if day.isToday {
                UpcomingSectionTokens.todayHighlight
            } else if day.isTomorrow {
                UpcomingSectionTokens.tomorrowBackground
            } else if day.isWeekend {
                UpcomingSectionTokens.weekendBackground
            } else {
                UpcomingSectionTokens.columnBackground
            }
        }
    }

    private var columnBorder: some View {
        RoundedRectangle(cornerRadius: UpcomingSectionTokens.cornerRadius, style: .continuous)
            .strokeBorder(
                day.isToday ? PlannerumColors.primary.opacity(0.3) : PlannerumColors.glassBorder,
                lineWidth: day.isToday ? 1.5 : 1
            )
    }
}

// MARK: - MiniTaskCard

/// Compact task card for upcoming section
struct MiniTaskCard: View {

    let task: TaskViewModel
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Priority dot
                Circle()
                    .fill(priorityColor)
                    .frame(width: 6, height: 6)

                // Title
                Text(task.title)
                    .font(UpcomingSectionTokens.miniCardTitleFont)
                    .foregroundColor(PlannerumColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                // Time if available
                if let timeInfo = task.timeInfo {
                    Text(timeInfo)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(PlannerumColors.textTertiary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(height: UpcomingSectionTokens.miniCardHeight)
            .background(isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: UpcomingSectionTokens.miniCardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .critical: return NowViewTokens.priorityCritical
        case .high: return NowViewTokens.priorityHigh
        case .medium: return NowViewTokens.priorityMedium
        case .low: return NowViewTokens.priorityLow
        }
    }
}

// MARK: - Preview

#if DEBUG
struct UpcomingSection_Previews: PreviewProvider {
    static var sampleDays: [UpcomingDayViewModel] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (1...7).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: today)!

            let tasks: [TaskViewModel]
            switch dayOffset {
            case 1:
                tasks = [
                    TaskViewModel(uuid: "1", title: "Team standup", scheduledTime: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date), priority: .medium),
                    TaskViewModel(uuid: "2", title: "Code review", priority: .high),
                    TaskViewModel(uuid: "3", title: "Update documentation", priority: .low)
                ]
            case 2:
                tasks = [
                    TaskViewModel(uuid: "4", title: "Client presentation", dueDate: date, priority: .critical),
                    TaskViewModel(uuid: "5", title: "Prepare slides", priority: .high)
                ]
            case 3:
                tasks = []
            case 5, 6:
                tasks = [
                    TaskViewModel(uuid: "6", title: "Weekend planning", priority: .low)
                ]
            default:
                tasks = [
                    TaskViewModel(uuid: "\(dayOffset)", title: "Regular task", priority: .medium)
                ]
            }

            return UpcomingDayViewModel(date: date, tasks: tasks)
        }
    }

    static var previews: some View {
        ZStack {
            PlannerumColors.voidPrimary.ignoresSafeArea()

            UpcomingSection(
                upcomingDays: sampleDays,
                onDayTap: { _ in },
                onTaskTap: { _ in }
            )
            .padding(24)
        }
        .frame(width: 1000, height: 400)
    }
}
#endif
