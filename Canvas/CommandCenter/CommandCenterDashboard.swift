// Canvas/CommandCenter/CommandCenterDashboard.swift
// Unified 3-column dashboard: Todoist + Timery hybrid
// Left: Calendar + Timeline | Center: Tasks + Timer | Right: Habits/Reports + Stats
// March 2026

import SwiftUI

struct CommandCenterDashboard: View {

    @StateObject private var viewModel = CommandCenterDashboardViewModel()
    @State private var isEditing = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftColumn
            centerColumn
            rightColumn
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Left Column (260px) — Calendar + Timeline

    private var leftColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                DashboardMonthCalendar(viewModel: viewModel)

                Divider()
                    .foregroundColor(DS.borderSubtle)

                DashboardScheduleStrip(viewModel: viewModel)
            }
        }
        .frame(width: 280)
        .padding(.trailing, 24)
    }

    // MARK: - Center Column — Timer + Tabs + Tasks

    private var centerColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Greeting
            greetingSection

            // Time tracking panel (timer + summary + presets)
            DashboardTimeTracker(viewModel: viewModel)

            Divider()
                .foregroundColor(DS.borderSubtle)

            // View mode tabs
            DashboardViewModeBar(
                selectedMode: $viewModel.viewMode,
                todayCount: viewModel.todayActiveCount,
                upcomingCount: viewModel.upcomingTotalCount,
                completedCount: viewModel.completedTodayTasks.count
            )

            // Task list (scrollable)
            DashboardTaskList(viewModel: viewModel)

            Spacer(minLength: 0)

            // Objectives bar (pinned at bottom)
            DashboardObjectivesBar(viewModel: viewModel)

            // Keyboard shortcut hints
            DashboardShortcutBar(
                viewModel: viewModel,
                isEditing: isEditing,
                isTimerRunning: viewModel.sessionEngine.isTimerRunning
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.cosmo.commandCenter.keyboardAction"))) { notification in
            handleKeyboardAction(notification)
        }
    }

    // MARK: - Keyboard Handling

    private func handleKeyboardAction(_ notification: Notification) {
        guard let keyCode = notification.userInfo?["keyCode"] as? UInt16 else { return }

        let tasks = viewModel.currentVisibleTasks

        switch keyCode {
        case 125: // Arrow Down
            withAnimation(ProMotionSprings.snappy) {
                if let idx = viewModel.selectedTaskIndex {
                    viewModel.selectedTaskIndex = min(idx + 1, tasks.count - 1)
                } else {
                    viewModel.selectedTaskIndex = 0
                }
            }

        case 126: // Arrow Up
            withAnimation(ProMotionSprings.snappy) {
                if let idx = viewModel.selectedTaskIndex {
                    viewModel.selectedTaskIndex = max(idx - 1, 0)
                } else {
                    viewModel.selectedTaskIndex = tasks.count - 1
                }
            }

        case 36: // Enter — toggle inline editor
            // Will be handled by DashboardTaskList (expandedTaskId)
            break

        case 49: // Space — play/pause timer
            if viewModel.sessionEngine.activeSession != nil {
                if viewModel.sessionEngine.isTimerRunning {
                    viewModel.sessionEngine.pauseSession()
                } else {
                    viewModel.sessionEngine.resumeSession()
                }
            } else if let idx = viewModel.selectedTaskIndex, tasks.indices.contains(idx) {
                let task = tasks[idx]
                if !task.isCompleted {
                    viewModel.startFocusSession(for: task)
                }
            }

        case 48: // Tab — cycle view modes
            withAnimation(ProMotionSprings.snappy) {
                switch viewModel.viewMode {
                case .today: viewModel.viewMode = .upcoming
                case .upcoming: viewModel.viewMode = .completed
                case .completed: viewModel.viewMode = .today
                }
            }

        case 51: // Delete/Backspace — complete selected task
            if let idx = viewModel.selectedTaskIndex, tasks.indices.contains(idx) {
                let task = tasks[idx]
                Task { await viewModel.toggleTaskCompletion(task) }
            }

        default:
            break
        }
    }

    // MARK: - Right Column (260px) — Habits + Stats

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Toggle header
            HStack(spacing: 0) {
                rightColumnTab("Habits", icon: "checkmark.circle", isActive: !viewModel.showReports)
                rightColumnTab("Reports", icon: "chart.bar", isActive: viewModel.showReports)
            }
            .padding(2)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))

            if viewModel.showReports {
                ScrollView(.vertical, showsIndicators: false) {
                    DashboardReportsPanel(viewModel: viewModel)
                }
            } else {
                DashboardHabitPanel(viewModel: viewModel)
            }

            Spacer(minLength: 0)

            quickStats
        }
        .frame(width: 280)
        .padding(.leading, 24)
    }

    private func rightColumnTab(_ title: String, icon: String, isActive: Bool) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.showReports = (title == "Reports")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isActive ? DS.text : DS.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isActive ? DS.bg : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.greetingText)
                .font(DS.pageTitle)
                .foregroundColor(DS.text)

            Text(viewModel.dateText)
                .font(DS.cardMeta)
                .foregroundColor(DS.textSecondary)
        }
    }

    // MARK: - Quick Stats

    private var quickStats: some View {
        HStack(spacing: 16) {
            statPill(
                icon: "star.fill",
                value: "Lv.\(viewModel.xpProgress.level)",
                detail: "\(viewModel.xpProgress.currentXP) XP",
                color: Color(hex: "D97706")
            )

            if viewModel.currentStreak > 0 {
                statPill(
                    icon: "flame.fill",
                    value: "\(viewModel.currentStreak)d",
                    detail: "streak",
                    color: DS.orange
                )
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func statPill(icon: String, value: String, detail: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.text)

            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(DS.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DS.surface, in: Capsule())
    }
}
