// Canvas/CommandCenter/CommandCenterMasthead.swift
// Native macOS-style page masthead for Command Center smart lists
// April 2026

import SwiftUI

struct CommandCenterMasthead: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        if viewModel.viewMode == .upcoming {
            upcomingMasthead
        } else {
            standardMasthead
        }
    }

    private var standardMasthead: some View {
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

    private var upcomingMasthead: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text(viewModel.viewMode.label)
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(DS.inkWash)

                    HStack(spacing: DS.space8) {
                        Image(systemName: viewModel.viewMode.icon)
                            .font(DS.caption)
                            .foregroundStyle(DS.giltMuted)

                        Text(summaryText)
                            .font(DS.callout)
                            .foregroundStyle(DS.inkFaded)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                upcomingScopeControl
                    .padding(.top, DS.space32)

                VStack(alignment: .trailing, spacing: DS.space6) {
                    Text(dateContext)
                        .font(DS.callout)
                        .foregroundStyle(DS.inkFaded)

                    upcomingRangeNavigation
                }
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            .frame(minHeight: 68)

            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(height: 0.5)
        }
    }

    private var upcomingScopeControl: some View {
        HStack(spacing: 2) {
            ForEach(UpcomingCalendarScope.allCases) { scope in
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.setUpcomingCalendarScope(scope)
                    }
                } label: {
                    Text(scope.label)
                        .font(.system(size: 12, weight: viewModel.upcomingCalendarScope == scope ? .semibold : .medium))
                        .foregroundStyle(viewModel.upcomingCalendarScope == scope ? DS.text : DS.textSecondary)
                        .frame(width: 56, height: 28)
                        .background(
                            viewModel.upcomingCalendarScope == scope ? DS.surfaceHover : Color.clear,
                            in: .rect(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(DS.surface.opacity(0.72), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.borderSubtle, lineWidth: 0.5)
        )
    }

    private var upcomingRangeNavigation: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftUpcomingRange(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous \(viewModel.upcomingCalendarScope.label)")

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.resetUpcomingToToday()
                }
            } label: {
                Text("Today")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, DS.space12)
                    .frame(height: 30)
                    .background(DS.surface, in: .rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DS.borderSubtle, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftUpcomingRange(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next \(viewModel.upcomingCalendarScope.label)")
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
                countText(viewModel.scheduledTasks.count, singular: "scheduled task", plural: "scheduled tasks"),
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
