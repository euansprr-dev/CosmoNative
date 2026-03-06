// Canvas/CommandCenter/DashboardViewModeBar.swift
// Todoist-style view mode tabs: Today / Upcoming / Completed
// March 2026

import SwiftUI

enum DashboardViewMode: String, CaseIterable {
    case today
    case upcoming
    case completed

    var label: String {
        switch self {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .completed: return "Completed"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .upcoming: return "calendar"
        case .completed: return "checkmark.circle"
        }
    }
}

struct DashboardViewModeBar: View {

    @Binding var selectedMode: DashboardViewMode
    var todayCount: Int
    var upcomingCount: Int
    var completedCount: Int

    @Namespace private var tabIndicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DashboardViewMode.allCases, id: \.self) { mode in
                tabButton(mode)
            }
            Spacer()
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
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected ? DS.accent : DS.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? DS.accentSoft : DS.surface)
                        )
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

    private func badgeCount(for mode: DashboardViewMode) -> Int {
        switch mode {
        case .today: return todayCount
        case .upcoming: return upcomingCount
        case .completed: return completedCount
        }
    }
}
