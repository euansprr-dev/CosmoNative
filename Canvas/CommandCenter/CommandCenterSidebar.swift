// Canvas/CommandCenter/CommandCenterSidebar.swift
// Things 3-inspired navigation sidebar: Smart Lists + Calendar
// March 2026

import SwiftUI

struct CommandCenterSidebar: View {

    var viewModel: CommandCenterDashboardViewModel
    @State private var hoveredMode: DashboardViewMode?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DS.space16) {
                smartListsSection

                gradientDivider

                compactCalendar
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Smart Lists

    private var smartListsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("SMART LISTS")

            ForEach(DashboardViewMode.smartLists, id: \.self) { mode in
                smartListRow(mode)
            }
        }
    }

    @ViewBuilder
    private func smartListRow(_ mode: DashboardViewMode) -> some View {
        let isSelected = viewModel.viewMode == mode &&
            viewModel.selectedProjectUUID == nil &&
            viewModel.selectedAreaUUID == nil &&
            !viewModel.showReports
        let isHovered = hoveredMode == mode
        let count = badgeCount(for: mode)

        Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.selectedProjectUUID = nil
                viewModel.selectedAreaUUID = nil
                viewModel.viewMode = mode
            }
        } label: {
            HStack(spacing: DS.space10) {
                // Selected indicator, replacing the old accent bar pattern.
                if isSelected {
                    Circle()
                        .fill(mode.activeTint.opacity(0.9))
                        .frame(width: 4, height: 4)
                }

                Image(systemName: mode.icon)
                    .font(DS.callout)
                    .foregroundStyle(isSelected ? mode.activeTint : DS.commandCenterMutedText)
                    .frame(width: DS.space20)

                // Constant weight — selection must never re-layout the row
                // (a headline↔callout swap shifts every label's width).
                Text(mode.label)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(isSelected ? DS.commandCenterTitleText : (isHovered ? DS.textSecondary : DS.commandCenterMutedText))

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(DS.footnote)
                        .foregroundStyle(isSelected ? mode.activeTint : DS.commandCenterMutedText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? DS.commandCenterSelectedRowFill : (isHovered ? DS.surfaceHover.opacity(0.4) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                hoveredMode = hovering ? mode : (hoveredMode == mode ? nil : hoveredMode)
            }
        }
        .help(helpText(for: mode))
        .dropDestination(for: String.self) { uuids, _ in
            handleDrop(uuids: uuids, onto: mode)
            return true
        }
    }

    private func helpText(for mode: DashboardViewMode) -> String {
        if let index = DashboardViewMode.smartLists.firstIndex(of: mode) {
            return "\(mode.label) (⌘\(index + 1))"
        }
        return mode.label
    }

    private func badgeCount(for mode: DashboardViewMode) -> Int {
        switch mode {
        case .today: return viewModel.todayActiveCount
        case .upcoming: return viewModel.upcomingTotalCount
        case .anytime: return viewModel.anytimeTasks.count
        case .someday: return viewModel.somedayTasks.count
        case .logbook: return viewModel.completedTodayTasks.count
        default: return 0
        }
    }

    // MARK: - Compact Calendar

    private var compactCalendar: some View {
        DashboardMonthCalendar(viewModel: viewModel)
    }

    // MARK: - Drag Handling

    private func handleDrop(uuids: [String], onto mode: DashboardViewMode) {
        for uuid in uuids {
            Task {
                switch mode {
                case .today:
                    await viewModel.setWhenDate(taskUUID: uuid, date: Date())
                case .someday:
                    await viewModel.setSchedulingState(taskUUID: uuid, state: "someday")
                case .anytime:
                    await viewModel.setSchedulingState(taskUUID: uuid, state: "anytime")
                default:
                    break
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(text)
                .font(DS.smallCaps)
                .foregroundStyle(DS.commandCenterOrnamentText)
                .padding(.horizontal, DS.space10)

            Rectangle()
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
                .padding(.horizontal, DS.space10)
        }
        .padding(.bottom, DS.space4)
    }

    private var gradientDivider: some View {
        AkashicSectionDivider()
    }
}
