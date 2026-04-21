// Canvas/CommandCenter/CommandCenterDashboard.swift
// Things 3-inspired 3-column dashboard: Sidebar + Smart Lists + Context Panel
// Left: Navigation Sidebar | Center: Tasks + Timer | Right: Context Panel
// March 2026

import SwiftUI

struct CommandCenterDashboard: View {

    @StateObject private var viewModel = CommandCenterDashboardViewModel()
    @State private var composer = CommandCenterComposerController()
    @State private var isEditing = false
    @State private var selectedTaskForDetail: TaskViewModel?

    var body: some View {
        ZStack(alignment: .topLeading) {
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

            CommandCenterComposerHost(viewModel: viewModel, composer: composer)
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
                DashboardTaskList(viewModel: viewModel, composer: composer) { task in
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
            // Context-sensitive tab bar — no container, bottom indicator
            HStack(spacing: 0) {
                if selectedTaskForDetail != nil {
                    rightColumnTab("Details", icon: "info.circle", isActive: showingDetailTab == .details)
                }
                rightColumnTab("Habits", icon: "checkmark.circle", isActive: showingDetailTab == .habits)
                rightColumnTab("Reports", icon: "chart.bar", isActive: showingDetailTab == .reports)
            }

            // Content
            switch showingDetailTab {
            case .details:
                if let task = resolvedSelectedTask {
                    TaskDetailPanel(task: task, viewModel: viewModel, composer: composer)
                        .id(task.uuid)
                }
            case .reports:
                ScrollView(.vertical) {
                    DashboardReportsPanel(viewModel: viewModel)
                }
                .scrollIndicators(.hidden)
            case .habits:
                DashboardHabitPanel(viewModel: viewModel, composer: composer)
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

    private var resolvedSelectedTask: TaskViewModel? {
        guard let selectedTaskForDetail else { return nil }
        return viewModel.currentVisibleTasks.first(where: { $0.uuid == selectedTaskForDetail.uuid }) ?? selectedTaskForDetail
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
                    break
                default:
                    break
                }
            }
        } label: {
            VStack(spacing: DS.space4) {
                HStack(spacing: DS.space4) {
                    Image(systemName: icon)
                        .font(DS.caption2)
                    Text(title)
                        .font(DS.caption)
                }
                .foregroundStyle(isActive ? DS.accent : DS.inkFaded)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.space6)

                // Bottom indicator line
                Rectangle()
                    .fill(isActive ? DS.accent : Color.clear)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: isActive ? 0.6 : 0, anchor: .center)
                    .clipShape(.rect(cornerRadius: 1))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gradient Divider

    private var gradientDivider: some View {
        AkashicSectionDivider()
            .padding(.horizontal, -16) // edge-to-edge in center column
    }

    // MARK: - Greeting

    @State private var isEditingName = false
    @State private var editingNameText = ""
    @FocusState private var nameFieldFocused: Bool

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            greetingTextView

            OrnamentalRule(color: DS.gilt)
                .padding(.vertical, 2)

            Text(viewModel.dateText)
                .font(DS.dateSerif)
                .foregroundStyle(DS.inkFaded)
        }
    }

    @ViewBuilder
    private var greetingTextView: some View {
        if isEditingName {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(viewModel.greetingPrefix), ")
                    .font(DS.displaySerif)
                    .tracking(-0.5)
                    .foregroundStyle(DS.inkWash)

                TextField("your name", text: $editingNameText)
                    .textFieldStyle(.plain)
                    .font(DS.displaySerif)
                    .tracking(-0.5)
                    .foregroundStyle(DS.accent)
                    .frame(maxWidth: 200)
                    .focused($nameFieldFocused)
                    .onSubmit { saveName() }
            }
        } else {
            Text(viewModel.greetingText)
                .font(DS.displaySerif)
                .tracking(-0.5)
                .foregroundStyle(DS.inkWash)
                .onTapGesture {
                    let current = UserDefaults.standard.string(forKey: "userName") ?? ""
                    editingNameText = current == "there" ? "" : current
                    isEditingName = true
                    nameFieldFocused = true
                }
        }
    }

    private func saveName() {
        let trimmed = editingNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: "userName")
        }
        isEditingName = false
    }

    // MARK: - Quick Stats

    private var quickStats: some View {
        HStack(spacing: DS.space16) {
            statPill(
                icon: "star.fill",
                value: "Lv.\(viewModel.xpProgress.level)",
                detail: "\(viewModel.xpProgress.currentXP) XP",
                color: DS.gilt
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
                .font(DS.smallCaps)
                .foregroundStyle(DS.inkWash)

            Text(detail)
                .font(DS.smallCaps)
                .foregroundStyle(DS.inkFaded)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space4)
        .background(DS.vellum, in: .rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
    }
}
