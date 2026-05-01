// Canvas/CommandCenter/CommandCenterMasthead.swift
// Native macOS-style page masthead for Command Center smart lists
// April 2026

import SwiftUI

struct CommandCenterMasthead: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space12) {
                Text(viewModel.viewMode.label)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(DS.inkWash)

                Spacer(minLength: DS.space16)

                Text(dateContext)
                    .font(DS.callout)
                    .foregroundStyle(DS.inkFaded)
            }

            HStack(spacing: DS.space8) {
                Image(systemName: viewModel.viewMode.icon)
                    .font(DS.caption)
                    .foregroundStyle(DS.giltMuted)

                Text(summaryText)
                    .font(DS.callout)
                    .foregroundStyle(DS.inkFaded)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(height: 0.5)
                .padding(.top, DS.space4)
        }
    }

    private var dateContext: String {
        switch viewModel.viewMode {
        case .upcoming:
            return upcomingWeekText
        case .logbook:
            return "Completed"
        case .anytime:
            return "Available"
        case .someday:
            return "Parked"
        default:
            return viewModel.dateText
        }
    }

    private var summaryText: String {
        switch viewModel.viewMode {
        case .today:
            return [
                countText(viewModel.todayActiveCount, singular: "open task", plural: "open tasks"),
                countText(viewModel.scheduledTasks.count, singular: "scheduled", plural: "scheduled"),
                countText(viewModel.unscheduledTasks.count, singular: "unscheduled", plural: "unscheduled"),
                "\(formattedTodayTotal) tracked"
            ].joined(separator: " · ")
        case .upcoming:
            return [
                countText(viewModel.upcomingTotalCount, singular: "scheduled task", plural: "scheduled tasks"),
                "\(formattedTodayTotal) tracked today"
            ].joined(separator: " · ")
        case .anytime:
            return countText(viewModel.anytimeTasks.count, singular: "available task", plural: "available tasks")
        case .someday:
            return countText(viewModel.somedayTasks.count, singular: "parked task", plural: "parked tasks")
        case .logbook:
            return countText(viewModel.completedTodayTasks.count, singular: "completed today", plural: "completed today")
        case .project, .area:
            return countText(viewModel.currentVisibleTasks.count, singular: "task", plural: "tasks")
        }
    }

    private var upcomingWeekText: String {
        viewModel.upcomingRangeText
    }

    private var formattedTodayTotal: String {
        let total = viewModel.todayTrackedMinutes
        let hours = total / 60
        let mins = total % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private func countText(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
