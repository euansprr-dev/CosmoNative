// Canvas/CommandCenter/CommandCenterMasthead.swift
// Native macOS-style page masthead for Command Center smart lists
// April 2026

import SwiftUI

/// Quiet "Inbox · N to triage" chip on the Today masthead — the morning-ritual
/// seam between capture and triage. Disappears entirely at inbox zero, so it
/// never nags. Click navigates to the inbox queue.
struct CommandCenterInboxChip: View {
    @ObservedObject private var inboxRepo = InboxRepository.shared
    @State private var isHovered = false

    var body: some View {
        if !inboxRepo.items.isEmpty {
            Button {
                NotificationCenter.default.post(name: CosmoNotification.Inbox.open, object: nil)
            } label: {
                HStack(spacing: DS.space4) {
                    Image(systemName: "tray")
                        .font(DS.caption2.weight(.semibold))
                    Text("\(inboxRepo.items.count) to triage")
                        .font(DS.caption.weight(.medium))
                        .monospacedDigit()
                }
                .foregroundStyle(isHovered ? DS.text : DS.commandCenterSecondaryText)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 3)
                .background(DS.glassSectionFill, in: .capsule)
                .overlay(Capsule().strokeBorder(DS.borderSubtle, lineWidth: 0.5))
                .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) { isHovered = hovering }
            }
            .help("Open the inbox queue")
            .accessibilityLabel("\(inboxRepo.items.count) captures to triage — open inbox")
        }
    }
}

struct CommandCenterMasthead: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @Environment(\.isPaneContext) private var isPaneContext

    var body: some View {
        Group {
            if viewModel.viewMode == .upcoming {
                upcomingMasthead
            } else {
                standardMasthead
            }
        }
        // The dashboard pads DS.space24 at the top; top up to the shared
        // clearance so titles sit clear of the floating trail chrome.
        // Panes have no trail chrome, so they keep the tighter spacing.
        .padding(.top, isPaneContext ? 0 : DS.navChromeClearance - DS.space24)
    }

    private var standardMasthead: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text(viewModel.viewMode.label)
                        .font(DS.pageTitle)
                        .foregroundStyle(DS.commandCenterTitleText)

                    HStack(spacing: DS.space8) {
                        // The editorial marginalia voice — the phone's serif
                        // date line; counts tick instead of re-laying out.
                        Text(summaryText)
                            .font(DS.dateSerif)
                            .foregroundStyle(DS.giltMuted)
                            .lineLimit(1)
                            .contentTransition(.numericText())

                        if viewModel.viewMode == .today {
                            CommandCenterInboxChip()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: DS.space6) {
                    Text(dateContext)
                        .font(DS.dateSerif)
                        .foregroundStyle(DS.giltMuted)

                    if viewModel.viewMode == .today {
                        todayDayNavigation
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            .frame(minHeight: viewModel.viewMode == .today ? 68 : 46)

            Rectangle()
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
                .padding(.top, DS.space4)
        }
    }

    private var todayDayNavigation: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftSelectedDay(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(DS.subheadline).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous Day")

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.resetSelectedDateToToday()
                }
            } label: {
                Text("Today")
                    .font(DS.subheadline).fontWeight(.semibold)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, DS.space12)
                    .frame(height: 30)
                    .background(DS.glassInputFill, in: .rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DS.glassBorder, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftSelectedDay(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(DS.subheadline).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next Day")
        }
    }

    private var upcomingMasthead: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text(viewModel.viewMode.label)
                        .font(DS.pageTitle)
                        .foregroundStyle(DS.commandCenterTitleText)

                    HStack(spacing: DS.space8) {
                        Text(summaryText)
                            .font(DS.dateSerif)
                            .foregroundStyle(DS.giltMuted)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                upcomingScopeControl
                    .padding(.top, DS.space32)

                VStack(alignment: .trailing, spacing: DS.space6) {
                    Text(dateContext)
                        .font(DS.dateSerif)
                        .foregroundStyle(DS.giltMuted)
                        .contentTransition(.numericText())

                    upcomingRangeNavigation
                }
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            .frame(minHeight: 68)

            Rectangle()
                .fill(DS.commandCenterSeparator)
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
                    // Selection is a soft accent wash + hairline (the pill
                    // law) — never a gray fill.
                    let isSelected = viewModel.upcomingCalendarScope == scope
                    Text(scope.label)
                        .font(DS.subheadline).fontWeight(isSelected ? .semibold : .medium)
                        .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                        .frame(width: 56, height: 28)
                        .background(
                            isSelected ? DS.accent.opacity(0.12) : Color.clear,
                            in: .rect(cornerRadius: 8)
                        )
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(DS.accent.opacity(0.3), lineWidth: 1)
                            }
                        }
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
                    .font(DS.subheadline).fontWeight(.semibold)
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
                    .font(DS.subheadline).fontWeight(.semibold)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, DS.space12)
                    .frame(height: 30)
                    .background(DS.glassInputFill, in: .rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DS.glassBorder, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftUpcomingRange(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(DS.subheadline).fontWeight(.semibold)
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
        case .habits:
            return "Practice"
        case .reports:
            return "Review"
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
        case .habits:
            let complete = viewModel.habits.filter(\.isTodayComplete).count
            return "\(complete)/\(viewModel.habits.count) complete today"
        case .reports:
            return "\(formattedTodayTotal) tracked today"
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
