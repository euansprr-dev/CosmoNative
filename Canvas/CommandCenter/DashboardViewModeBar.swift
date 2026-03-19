// Canvas/CommandCenter/DashboardViewModeBar.swift
// Todoist-style view mode tabs: Today / Upcoming / Completed
// March 2026

import SwiftUI

enum DashboardViewMode: String, CaseIterable {
    case today
    case upcoming
    case anytime
    case someday
    case logbook
    case project       // Viewing a specific project
    case area          // Viewing all tasks in an area

    /// Smart list modes shown in sidebar navigation
    static var smartLists: [DashboardViewMode] {
        [.today, .upcoming, .anytime, .someday, .logbook]
    }

    var label: String {
        switch self {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .anytime: return "Anytime"
        case .someday: return "Someday"
        case .logbook: return "Logbook"
        case .project: return "Project"
        case .area: return "Area"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .upcoming: return "calendar"
        case .anytime: return "tray.full"
        case .someday: return "archivebox"
        case .logbook: return "book.closed"
        case .project: return "folder.fill"
        case .area: return "square.stack.fill"
        }
    }
}

struct DashboardViewModeBar: View {

    @Binding var selectedMode: DashboardViewMode
    var todayCount: Int
    var upcomingCount: Int
    var anytimeCount: Int
    var somedayCount: Int
    var completedCount: Int
    var completedArrivalToken: Int

    @Namespace private var tabIndicator
    @State private var pulseCompletedBadge = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DashboardViewMode.smartLists, id: \.self) { mode in
                tabButton(mode)
            }
            Spacer()
        }
        .onChange(of: completedArrivalToken) { _, _ in
            guard completedCount > 0 else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.62)) {
                pulseCompletedBadge = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.easeOut(duration: 0.18)) {
                    pulseCompletedBadge = false
                }
            }
        }
    }

    @ViewBuilder
    private func tabButton(_ mode: DashboardViewMode) -> some View {
        let isSelected = selectedMode == mode
        let count = badgeCount(for: mode)

        Button {
            withAnimation(ProMotionSprings.snappy) {
                selectedMode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10, weight: .medium))

                Text(mode.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))

                if count > 0 {
                    badge(for: mode, count: count, isSelected: isSelected)
                }
            }
            .foregroundColor(isSelected ? DS.accent : DS.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DS.surfaceElevated)
                            .matchedGeometryEffect(id: "tabBg", in: tabIndicator)
                            .dsRestingShadow()
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private func badge(for mode: DashboardViewMode, count: Int, isSelected: Bool) -> some View {
        let isCompletedBadge = mode == .logbook
        let isPulsing = isCompletedBadge && pulseCompletedBadge

        return Text("\(count)")
            .font(.system(size: 10, weight: .semibold))
            .contentTransition(.numericText(value: Double(count)))
            .foregroundColor(isSelected ? DS.accent : DS.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(isSelected ? DS.accentSoft : DS.surface)
                    .overlay(
                        Capsule()
                            .fill(DS.green.opacity(isPulsing ? 0.18 : 0))
                    )
            )
            .scaleEffect(isPulsing ? 1.12 : 1.0)
    }

    private func badgeCount(for mode: DashboardViewMode) -> Int {
        switch mode {
        case .today: return todayCount
        case .upcoming: return upcomingCount
        case .anytime: return anytimeCount
        case .someday: return somedayCount
        case .logbook: return completedCount
        case .project, .area: return 0
        }
    }
}
