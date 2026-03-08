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
    var completedArrivalToken: Int

    @Namespace private var tabIndicator
    @State private var pulseCompletedBadge = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DashboardViewMode.allCases, id: \.self) { mode in
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
        let isCompletedBadge = mode == .completed
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
        case .completed: return completedCount
        }
    }
}
