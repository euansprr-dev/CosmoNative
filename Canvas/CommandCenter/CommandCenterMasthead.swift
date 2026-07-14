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

    var viewModel: CommandCenterDashboardViewModel
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
                    // Bare title (the masthead law): counts are dashboard
                    // chrome — they live in section headers and the sidebar
                    // badges, never under the page title. The inbox chip is
                    // the one masthead companion (a chip, not a data line).
                    HStack(spacing: DS.space10) {
                        Text(viewModel.viewMode.label)
                            .font(DS.pageTitle)
                            .foregroundStyle(DS.commandCenterTitleText)

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
            MastheadNavChevron(direction: .left, help: "Previous day") {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftSelectedDay(by: -1)
                }
            }
            .accessibilityLabel("Previous Day")

            MastheadTodayButton(help: "Jump back to today") {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.resetSelectedDateToToday()
                }
            }

            MastheadNavChevron(direction: .right, help: "Next day") {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftSelectedDay(by: 1)
                }
            }
            .accessibilityLabel("Next Day")
        }
    }

    private var upcomingMasthead: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ZStack(alignment: .top) {
                Text(viewModel.viewMode.label)
                    .font(DS.pageTitle)
                    .foregroundStyle(DS.commandCenterTitleText)
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
        // The one view-mode grammar: a sliding-thumb switcher, never
        // re-filled segments (view modes are not pills). Upcoming's two
        // faces: the week schedule and the content calendar.
        CosmoSegmentedSwitcher(
            options: Array(UpcomingLens.allCases),
            label: { $0.label },
            help: { $0.help },
            selection: Binding(
                get: { viewModel.upcomingLens },
                set: { lens in
                    withAnimation(ProMotionSprings.gentle) {
                        viewModel.setUpcomingLens(lens)
                    }
                }
            )
        )
    }

    private var upcomingRangeNavigation: some View {
        HStack(spacing: 0) {
            MastheadNavChevron(direction: .left, help: "Previous \(viewModel.upcomingCalendarScope.label.lowercased())") {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftUpcomingRange(by: -1)
                }
            }
            .accessibilityLabel("Previous \(viewModel.upcomingCalendarScope.label)")

            MastheadTodayButton(help: "Jump back to today") {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.resetUpcomingToToday()
                }
            }

            MastheadNavChevron(direction: .right, help: "Next \(viewModel.upcomingCalendarScope.label.lowercased())") {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftUpcomingRange(by: 1)
                }
            }
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

    private var upcomingWeekText: String {
        viewModel.upcomingRangeText
    }
}

// MARK: - Masthead nav controls (hover + tooltip manners)

private struct MastheadNavChevron: View {
    enum Direction { case left, right }
    let direction: Direction
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(isHovered ? DS.surfaceHover.opacity(0.5) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(help)
    }
}

private struct MastheadTodayButton: View {
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("Today")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.text)
                .padding(.horizontal, DS.space12)
                .frame(height: 30)
                .background(
                    isHovered ? DS.glassInputFillFocused : DS.glassInputFill,
                    in: .rect(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DS.glassBorder, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(help)
    }
}
