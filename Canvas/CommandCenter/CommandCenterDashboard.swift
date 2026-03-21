// Canvas/CommandCenter/CommandCenterDashboard.swift
// Things 3-inspired 3-column dashboard: Sidebar + Smart Lists + Context Panel
// Left: Navigation Sidebar | Center: Tasks + Timer | Right: Context Panel
// March 2026

import SwiftUI

struct CommandCenterDashboard: View {

    @StateObject private var viewModel = CommandCenterDashboardViewModel()
    @State private var isEditing = false
    @State private var selectedTaskForDetail: TaskViewModel?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftColumn
            centerColumn
            rightColumn
        }
        .padding(DS.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await viewModel.loadAreas()
            await viewModel.loadProjects()
            await viewModel.loadAnytimeTasks()
            await viewModel.loadSomedayTasks()
        }
    }

    // MARK: - Left Column (240px) — Things 3-style Navigation Sidebar

    private var leftColumn: some View {
        CommandCenterSidebar(viewModel: viewModel)
            .frame(width: 240)
            .padding(.trailing, DS.space24)
    }

    // MARK: - Center Column — Timer + Content (Smart List or Project)

    private var centerColumn: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            // Greeting
            greetingSection

            // Time tracking panel (timer + summary + presets)
            DashboardTimeTracker(viewModel: viewModel)

            gradientDivider

            // Content switches between smart list task view and project detail view
            if viewModel.viewMode == .project, let projectUUID = viewModel.selectedProjectUUID,
               let project = viewModel.projects.first(where: { $0.uuid == projectUUID }) {
                ProjectDetailView(project: project, viewModel: viewModel)
            } else {
                // View mode tabs (for smart lists)
                DashboardViewModeBar(
                    selectedMode: $viewModel.viewMode,
                    todayCount: viewModel.todayActiveCount,
                    upcomingCount: viewModel.upcomingTotalCount,
                    anytimeCount: viewModel.anytimeTasks.count,
                    somedayCount: viewModel.somedayTasks.count,
                    completedCount: viewModel.completedTodayTasks.count,
                    completedArrivalToken: viewModel.completedArrivalToken
                )

                // Task list (scrollable)
                DashboardTaskList(viewModel: viewModel) { task in
                    withAnimation(ProMotionSprings.snappy) {
                        selectedTaskForDetail = task
                        viewModel.showReports = false
                    }
                }
            }

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
        .padding(.horizontal, DS.space16)
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

        case 48: // Tab — cycle view modes (smart lists only)
            withAnimation(ProMotionSprings.snappy) {
                let smartLists = DashboardViewMode.smartLists
                if let idx = smartLists.firstIndex(of: viewModel.viewMode) {
                    let next = smartLists[(idx + 1) % smartLists.count]
                    viewModel.viewMode = next
                } else {
                    viewModel.viewMode = .today
                }
            }

        case 51: // Delete/Backspace — complete selected task
            if let idx = viewModel.selectedTaskIndex, tasks.indices.contains(idx) {
                let task = tasks[idx]
                Task { await viewModel.toggleTaskCompletion(task) }
            }

        case 17: // T — set selected task's whenDate to Today
            if let idx = viewModel.selectedTaskIndex, tasks.indices.contains(idx) {
                let task = tasks[idx]
                Task { await viewModel.setWhenDate(taskUUID: task.uuid, date: Date()) }
            }

        case 14: // E — set selected task to This Evening
            if let idx = viewModel.selectedTaskIndex, tasks.indices.contains(idx) {
                let task = tasks[idx]
                Task {
                    await viewModel.setWhenDate(taskUUID: task.uuid, date: Date())
                    await viewModel.setTimeOfDay(taskUUID: task.uuid, value: "evening")
                }
            }

        default:
            break
        }

        // Cmd+ shortcuts (check modifier flags)
        let modifiers = notification.userInfo?["modifiers"] as? UInt ?? 0
        let hasCmd = (modifiers & (1 << 20)) != 0  // NSEvent.ModifierFlags.command
        let hasShift = (modifiers & (1 << 17)) != 0  // NSEvent.ModifierFlags.shift

        if hasCmd {
            switch keyCode {
            case 1: // Cmd+S — Move to Someday
                if let idx = viewModel.selectedTaskIndex, tasks.indices.contains(idx) {
                    let task = tasks[idx]
                    Task { await viewModel.setSchedulingState(taskUUID: task.uuid, state: "someday") }
                }
            case 18: // Cmd+1 — Today
                withAnimation(ProMotionSprings.snappy) { viewModel.viewMode = .today }
            case 19: // Cmd+2 — Upcoming
                withAnimation(ProMotionSprings.snappy) { viewModel.viewMode = .upcoming }
            case 20: // Cmd+3 — Anytime
                withAnimation(ProMotionSprings.snappy) { viewModel.viewMode = .anytime }
            case 21: // Cmd+4 — Someday
                withAnimation(ProMotionSprings.snappy) { viewModel.viewMode = .someday }
            case 23: // Cmd+5 — Logbook
                withAnimation(ProMotionSprings.snappy) { viewModel.viewMode = .logbook }
            case 45: // Cmd+N — New task
                NotificationCenter.default.post(name: .init("com.cosmo.commandCenter.quickAddTask"), object: nil)
            case 7 where hasShift: // Cmd+Shift+N — New heading (project view)
                if viewModel.viewMode == .project, let uuid = viewModel.selectedProjectUUID {
                    Task { await viewModel.createHeading(projectUUID: uuid, title: "New Section") }
                }
            default:
                break
            }
        }
    }

    // MARK: - Right Column (280px) — Context-Sensitive Panel

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            // Context-sensitive tab bar
            HStack(spacing: 0) {
                if selectedTaskForDetail != nil {
                    rightColumnTab("Details", icon: "info.circle", isActive: showingDetailTab == .details)
                }
                rightColumnTab("Habits", icon: "checkmark.circle", isActive: showingDetailTab == .habits)
                rightColumnTab("Reports", icon: "chart.bar", isActive: showingDetailTab == .reports)
            }
            .padding(DS.space2)
            .background(DS.surface, in: .rect(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )

            // Content
            switch showingDetailTab {
            case .details:
                if let task = selectedTaskForDetail {
                    TaskDetailPanel(task: task, viewModel: viewModel)
                        .id(task.uuid)
                }
            case .reports:
                ScrollView(.vertical) {
                    DashboardReportsPanel(viewModel: viewModel)
                }
                .scrollIndicators(.hidden)
            case .habits:
                DashboardHabitPanel(viewModel: viewModel)
            }

            Spacer(minLength: 0)

            quickStats
        }
        .frame(width: 280)
        .padding(.leading, DS.space24)
    }

    private enum RightColumnTab {
        case details, habits, reports
    }

    private var showingDetailTab: RightColumnTab {
        if selectedTaskForDetail != nil && !viewModel.showReports {
            return .details
        } else if viewModel.showReports {
            return .reports
        } else {
            return .habits
        }
    }

    private func rightColumnTab(_ title: String, icon: String, isActive: Bool) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                switch title {
                case "Reports":
                    viewModel.showReports = true
                    selectedTaskForDetail = nil
                case "Habits":
                    viewModel.showReports = false
                    selectedTaskForDetail = nil
                case "Details":
                    viewModel.showReports = false
                    // selectedTaskForDetail stays as-is
                    break
                default:
                    break
                }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: icon)
                    .font(DS.caption2)
                Text(title)
                    .font(DS.caption)
            }
            .foregroundStyle(isActive ? DS.text : DS.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space6)
            .background(isActive ? DS.surfaceElevated : Color.clear, in: .rect(cornerRadius: DS.radiusSmall))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gradient Divider

    private var gradientDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [DS.borderSubtle.opacity(0), DS.borderSubtle, DS.borderSubtle.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(viewModel.greetingText)
                .font(DS.pageTitle)
                .tracking(-0.3)
                .foregroundStyle(DS.text)

            HStack(spacing: DS.space6) {
                Circle()
                    .fill(DS.accent.opacity(0.5))
                    .frame(width: DS.space4, height: DS.space4)

                Text(viewModel.dateText)
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }

    // MARK: - Quick Stats

    private var quickStats: some View {
        HStack(spacing: DS.space16) {
            statPill(
                icon: "star.fill",
                value: "Lv.\(viewModel.xpProgress.level)",
                detail: "\(viewModel.xpProgress.currentXP) XP",
                color: DS.orange
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
        .padding(.top, DS.space4)
    }

    @ViewBuilder
    private func statPill(icon: String, value: String, detail: String, color: Color) -> some View {
        HStack(spacing: DS.space6) {
            Image(systemName: icon)
                .font(DS.footnote)
                .foregroundStyle(color)

            Text(value)
                .font(DS.cardMeta)
                .foregroundStyle(DS.text)

            Text(detail)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space4)
        .background(DS.surface, in: Capsule())
    }
}
