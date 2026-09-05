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
                        .font(DS.subheadline.weight(.medium))
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

/// The Seedbed's one line on Today: "N ripe" when seedlings are ready for a
/// development conversation. Disappears entirely otherwise — ripeness is an
/// invitation, never a nag. Click opens the inbox (the Growing section).
struct CommandCenterRipeChip: View {
    @ObservedObject private var seedlings = SeedlingRepository.shared
    @State private var isHovered = false

    var body: some View {
        if seedlings.ripeCount > 0 {
            Button {
                NotificationCenter.default.post(name: CosmoNotification.Inbox.open, object: nil)
            } label: {
                HStack(spacing: DS.space4) {
                    Image(systemName: "leaf.fill")
                        .font(DS.caption2.weight(.semibold))
                    Text("\(seedlings.ripeCount) ripe")
                        .font(DS.subheadline.weight(.medium))
                        .monospacedDigit()
                }
                .foregroundStyle(isHovered ? DS.accent : DS.accent.opacity(0.85))
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 3)
                .background(DS.accentSoft.opacity(0.5), in: .capsule)
                .overlay(Capsule().strokeBorder(DS.accent.opacity(0.25), lineWidth: 0.5))
                .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) { isHovered = hovering }
            }
            .help("Seedlings ready to develop into Concept pages")
            .accessibilityLabel("\(seedlings.ripeCount) seedlings ripe — open inbox")
        }
    }
}

struct CommandCenterMasthead: View {

    var viewModel: CommandCenterDashboardViewModel
    @Environment(\.isPaneContext) private var isPaneContext

    var body: some View {
        Group {
            if viewModel.viewMode == .today {
                todayMasthead
            } else if viewModel.viewMode == .upcoming {
                upcomingMasthead
            } else {
                standardMasthead
            }
        }
        // The dashboard pads DS.space24 at the top; top up to the shared
        // clearance so titles sit clear of the floating trail chrome.
        // Panes have no trail chrome, so they keep the tighter spacing.
        .padding(.top, isPaneContext ? 0 : DS.navChromeClearance - DS.space24)
        // The masthead joins the page's two rails (x=12 / W−12): its title,
        // date, and rule now hang off the same lines as every band below —
        // a page rail distinct from the content rail read as three left
        // edges, not composition.
        .padding(.horizontal, DS.space12)
    }

    private var todayMasthead: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DS.space24) {
                todayTitle
                Spacer(minLength: DS.space16)
                todayUtilities
            }
            VStack(alignment: .leading, spacing: DS.space12) {
                todayTitle
                todayUtilities
            }
        }
        .padding(.bottom, DS.space8)
    }

    private var todayTitle: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(viewedDayTitle)
                .font(DS.pageTitle)
                .foregroundStyle(DS.commandCenterTitleText)
            Text(dateContext)
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
                .contentTransition(.numericText())
                .fixedSize()
        }
    }

    private var viewedDayTitle: String {
        if viewModel.isViewingToday { return "Today" }
        let calendar = Calendar.current
        if calendar.isDateInYesterday(viewModel.selectedDate) { return "Yesterday" }
        if calendar.isDateInTomorrow(viewModel.selectedDate) { return "Tomorrow" }
        return viewModel.selectedDate.formatted(.dateTime.weekday(.wide))
    }

    private var todayUtilities: some View {
        HStack(spacing: DS.space12) {
            CommandCenterInboxChip()
            CommandCenterRipeChip()
            todayDayNavigation
        }
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
                            CommandCenterRipeChip()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: DS.space6) {
                    // The date is the page's orientation anchor — it carries
                    // real ink; the chevrons beneath recede until hover. (It
                    // was the faintest thing in the masthead, under bold
                    // chevrons: the weight order was inverted.) Tabular
                    // figures so paging days never reflows the block.
                    Text(dateContext)
                        .font(DS.dateSerif)
                        .monospacedDigit()
                        .foregroundStyle(DS.textSecondary)
                        .contentTransition(.numericText())

                    if viewModel.viewMode == .today {
                        todayDayNavigation
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            .frame(minHeight: viewModel.viewMode == .today ? 68 : 46)

            // The one rule voice (anchor, then depart) — the masthead was the
            // page's last hard-terminating hairline.
            CosmoPageRule()
                .padding(.top, DS.space4)
        }
    }

    // The Today pill appears only when you've paged away (iOS parity — the
    // duplicate-word law: a page titled "Today" must not also wear a "Today"
    // chip while you're already there). Chevrons carry the paging; their
    // tooltips teach the keyboard twin.
    private var todayDayNavigation: some View {
        HStack(spacing: 0) {
            MastheadNavChevron(direction: .left, help: "Previous day (⌥⌘←)") {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftSelectedDay(by: -1)
                }
            }
            .accessibilityLabel("Previous Day")

            if !viewModel.isViewingToday {
                MastheadTodayButton(help: "Jump back to today") {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.resetSelectedDateToToday()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            MastheadNavChevron(direction: .right, help: "Next day (⌥⌘→)") {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.shiftSelectedDay(by: 1)
                }
            }
            .accessibilityLabel("Next Day")
        }
        .animation(ProMotionSprings.snappy, value: viewModel.isViewingToday)
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
                        .monospacedDigit()
                        .foregroundStyle(DS.textSecondary)
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

    /// The content calendar lives in Studio › Pipeline now (one room per
    /// stage of material). Upcoming keeps a door to it, not a second copy.
    private var upcomingScopeControl: some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openPipeline,
                object: nil,
                userInfo: ["view": PipelineView.calendar.rawValue]
            )
        } label: {
            HStack(spacing: DS.space4) {
                Text("Content calendar")
                    .font(DS.callout.weight(.medium))
                Image(systemName: "arrow.up.right")
                    .font(DS.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .frame(height: 30)
            .background(DS.glassSectionFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Open the content calendar in the Pipeline")
        .accessibilityLabel("Open content calendar")
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
        case .today where viewModel.isDayClear:
            // The day's one earned flourish — the serif line itself
            // celebrates (iOS greeting parity), no banner, no confetti.
            return viewModel.dateText + "  ·  All clear ✦"
        default:
            return viewModel.dateText
        }
    }

    private var upcomingWeekText: String {
        viewModel.upcomingRangeText
    }
}

// MARK: - Masthead nav controls (hover + tooltip manners)

struct MastheadNavChevron: View {
    enum Direction { case left, right }
    let direction: Direction
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(isHovered ? DS.text : DS.textMuted)
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

struct MastheadTodayButton: View {
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
                    in: .rect(cornerRadius: DS.radiusSmall)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                        .strokeBorder(DS.glassBorder, lineWidth: 0.5)
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
