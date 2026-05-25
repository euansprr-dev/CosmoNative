// Canvas/CommandCenter/CommandCenterDashboard.swift
// Things 3-inspired 3-column dashboard: Sidebar + Smart Lists + Context Panel
// Left: Navigation Sidebar | Center: Tasks + Timer | Right: Context Panel
// March 2026

import SwiftUI

struct CommandCenterDashboard: View {

    @StateObject private var viewModel: CommandCenterDashboardViewModel
    @StateObject private var contextProvider: CommandCenterContextProvider
    @State private var composer = CommandCenterComposerController()
    @State private var selectedTaskForDetail: TaskViewModel?
    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner
    private let showsInternalSidebar: Bool

    init(
        viewModel: CommandCenterDashboardViewModel? = nil,
        showsInternalSidebar: Bool = true
    ) {
        let dashboardViewModel = viewModel ?? CommandCenterDashboardViewModel()
        _viewModel = StateObject(wrappedValue: dashboardViewModel)
        _contextProvider = StateObject(wrappedValue: CommandCenterContextProvider(viewModel: dashboardViewModel))
        self.showsInternalSidebar = showsInternalSidebar
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                if showsInternalSidebar {
                    leftColumn
                }
                centerColumn
                rightColumn
            }
            .padding(DS.space24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task {
                await viewModel.loadAreas()
                await viewModel.loadAnytimeTasks()
                await viewModel.loadSomedayTasks()
                publishCommandCenterContext()
            }
            .onAppear(perform: publishCommandCenterContext)
            .onChange(of: isPaneContextOwner) { _, _ in publishCommandCenterContext() }
            .onReceive(viewModel.objectWillChange) { _ in
                DispatchQueue.main.async {
                    publishCommandCenterContext()
                }
            }

            CommandCenterComposerHost(viewModel: viewModel, composer: composer)
        }
    }

    private func publishCommandCenterContext() {
        guard !isPaneContext || isPaneContextOwner else { return }
        CosmoWindowViewModel.shared.updateContext(provider: contextProvider)
    }

    // MARK: - Left Column (240px) — Things 3-style Navigation Sidebar

    private var leftColumn: some View {
        CommandCenterSidebar(viewModel: viewModel)
            .frame(width: 240)
            .padding(.trailing, DS.space24)
            .cosmoGlassSceneSignal(
                id: "command-center-internal-sidebar",
                source: .commandTask,
                color: DS.entityTask,
                intensity: 0.18
            )
    }

    // MARK: - Center Column — Timer + Content (Smart List or Project)

    private var centerColumn: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Group {
                // Content switches between smart list task view and project detail view
                if viewModel.viewMode == .project, let projectUUID = viewModel.selectedProjectUUID,
                   let project = viewModel.projects.first(where: { $0.uuid == projectUUID }) {
                    ProjectDetailView(project: project, viewModel: viewModel)
                } else {
                    if viewModel.viewMode == .upcoming {
                        CommandCenterMasthead(viewModel: viewModel)

                        UpcomingBoardView(viewModel: viewModel, composer: composer)
                            .frame(maxHeight: .infinity)
                            .cosmoGlassSceneSignal(
                                id: "command-center-calendar",
                                source: .commandCalendar,
                                color: DS.info,
                                intensity: 0.16
                            )
                    } else {
                        CommandCenterMasthead(viewModel: viewModel)
                            .cosmoGlassSceneSignal(
                                id: "command-center-masthead",
                                source: .routeAccent,
                                color: DS.accent,
                                intensity: 0.22
                            )

                        DashboardTimeTracker(viewModel: viewModel)
                            .cosmoGlassSceneSignal(
                                id: "command-center-timer",
                                source: .commandTask,
                                color: DS.orange,
                                intensity: 0.22
                            )

                        gradientDivider

                        // Task list (scrollable)
                        DashboardTaskList(viewModel: viewModel, composer: composer) { task in
                            withAnimation(ProMotionSprings.snappy) {
                                selectedTaskForDetail = task
                                viewModel.showReports = false
                            }
                        }
                        .cosmoGlassSceneSignal(
                            id: "command-center-tasks-\(viewModel.viewMode.rawValue)",
                            source: .commandTask,
                            color: DS.entityTask,
                            intensity: 0.20
                        )
                    }
                }
            }
            .id(centerContentTransitionID)
            .transition(.opacity)

            Spacer(minLength: 0)

            // Objectives bar (pinned at bottom)
            if viewModel.viewMode != .upcoming {
                DashboardObjectivesBar(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.space16)
        .animation(.easeInOut(duration: 0.22), value: centerContentTransitionID)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.cosmo.commandCenter.keyboardAction"))) { notification in
            handleKeyboardAction(notification)
        }
    }

    private var centerContentTransitionID: String {
        [
            viewModel.viewMode.rawValue,
            viewModel.selectedProjectUUID ?? "no-project",
            viewModel.selectedAreaUUID ?? "no-area",
            viewModel.showReports ? "reports" : "main"
        ].joined(separator: ":")
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

    // MARK: - Right Column (280px) — Context-Sensitive Inspector

    private var rightColumn: some View {
        CommandCenterGlassRail(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: DS.space16) {
                rightColumnTabs
                rightColumnContent
                Spacer(minLength: 0)
            }
        }
        .frame(width: 280)
        .padding(.leading, DS.space20)
        .onChange(of: visibleTaskUUIDs) { _, taskUUIDs in
            clearDeletedTaskState(visibleTaskUUIDs: taskUUIDs)
        }
    }

    private var rightColumnTabs: some View {
        HStack(spacing: 0) {
            if selectedTaskForDetail != nil {
                rightColumnTab("Details", icon: "info.circle", isActive: showingDetailTab == .details)
            }
            rightColumnTab("Habits", icon: "checkmark.circle", isActive: showingDetailTab == .habits)
            rightColumnTab("Reports", icon: "chart.bar", isActive: showingDetailTab == .reports)
        }
    }

    @ViewBuilder
    private var rightColumnContent: some View {
        switch showingDetailTab {
        case .details:
            if let task = resolvedSelectedTask {
                TaskDetailPanel(
                    task: task,
                    viewModel: viewModel,
                    composer: composer,
                    onDeleted: { deletedTaskUUID in
                        handleDeletedSelectedTask(uuid: deletedTaskUUID)
                    }
                )
                .id(task.uuid)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .cosmoGlassSceneSignal(
                    id: "command-center-task-detail-\(task.uuid)",
                    source: .commandTask,
                    color: DS.entityTask,
                    intensity: 0.26
                )
            }
        case .reports:
            ScrollView(.vertical) {
                DashboardReportsPanel(viewModel: viewModel)
            }
            .scrollIndicators(.never)
            .cosmoGlassSceneSignal(
                id: "command-center-reports",
                source: .commandCalendar,
                color: DS.info,
                intensity: 0.24
            )
        case .habits:
            DashboardHabitPanel(viewModel: viewModel, composer: composer)
                .cosmoGlassSceneSignal(
                    id: "command-center-habits",
                    source: .commandHabit,
                    color: DS.green,
                    intensity: 0.28
                )
        }
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
        return viewModel.currentVisibleTasks.first(where: { $0.uuid == selectedTaskForDetail.uuid })
    }

    private var visibleTaskUUIDs: [String] {
        viewModel.currentVisibleTasks.map(\.uuid)
    }

    private func handleDeletedSelectedTask(uuid: String) {
        withAnimation(ProMotionSprings.snappy) {
            if selectedTaskForDetail?.uuid == uuid {
                selectedTaskForDetail = nil
            }
            composer.dismiss()
        }
    }

    private func clearDeletedTaskState(visibleTaskUUIDs: [String]) {
        if let selectedTaskForDetail, !visibleTaskUUIDs.contains(selectedTaskForDetail.uuid) {
            withAnimation(ProMotionSprings.snappy) {
                self.selectedTaskForDetail = nil
            }
        }

        if let activeTaskUUID = composer.route?.taskUUID, !visibleTaskUUIDs.contains(activeTaskUUID) {
            composer.dismiss()
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
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                }
                .foregroundStyle(isActive ? DS.accent : DS.commandCenterMutedText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.space8)

                // Bottom indicator line
                Rectangle()
                    .fill(isActive ? DS.accent : Color.clear)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: isActive ? 0.48 : 0, anchor: .center)
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

}

@MainActor
final class CommandCenterContextProvider: ObservableObject, CosmoContextProvider {
    private weak var viewModel: CommandCenterDashboardViewModel?

    init(viewModel: CommandCenterDashboardViewModel) {
        self.viewModel = viewModel
    }

    var contextType: CosmoContextType { .commandCenter }

    var contextSummary: String {
        guard let viewModel else { return "Command Center" }
        return [
            "Command Center",
            viewModel.viewMode.label,
            "\(viewModel.currentVisibleTasks.count) visible tasks",
            "\(viewModel.habits.count) habits"
        ].joined(separator: " · ")
    }

    var contextData: CosmoContextData {
        guard let viewModel else {
            return CosmoContextData(viewSpecificData: ["surface": "Command Center"])
        }

        let visibleTasks = viewModel.currentVisibleTasks
        return CosmoContextData(
            viewSpecificData: [
                "surface": "Command Center",
                "viewMode": viewModel.viewMode.label,
                "selectedDate": viewModel.dateText,
                "overdueTasks": "\(viewModel.overdueTasks.count)",
                "scheduledTasks": "\(viewModel.scheduledTasks.count)",
                "unscheduledTasks": "\(viewModel.unscheduledTasks.count)",
                "anytimeTasks": "\(viewModel.anytimeTasks.count)",
                "somedayTasks": "\(viewModel.somedayTasks.count)",
                "completedTodayTasks": "\(viewModel.completedTodayTasks.count)",
                "trackedToday": "\(viewModel.todayTrackedMinutes)m",
                "habits": habitSummary(for: viewModel.habits),
                "objectives": objectiveSummary(for: viewModel.objectives),
                "visibleTasks": taskSummary(for: visibleTasks)
            ],
            visibleItemCount: visibleTasks.count,
            activeFilters: activeFilters(for: viewModel)
        )
    }

    var availableActions: [CosmoWindowAction] { [] }

    private func activeFilters(for viewModel: CommandCenterDashboardViewModel) -> [String] {
        var filters = [viewModel.viewMode.label]
        if viewModel.showReports {
            filters.append("Reports: \(viewModel.selectedReportTab.displayName)")
        }
        if let project = viewModel.projects.first(where: { $0.uuid == viewModel.selectedProjectUUID }) {
            filters.append("Project: \(project.title ?? "Untitled")")
        }
        return filters
    }

    private func taskSummary(for tasks: [TaskViewModel]) -> String {
        guard !tasks.isEmpty else { return "No visible tasks" }
        return tasks.prefix(12).map { task in
            var parts = [task.title]
            if let time = task.timeInfo {
                parts.append(time)
            }
            if task.isRecurring {
                parts.append("Repeats")
            }
            if let projectName = task.projectName, !projectName.isEmpty {
                parts.append(projectName)
            }
            return parts.joined(separator: " · ")
        }.joined(separator: "\n")
    }

    private func habitSummary(for habits: [HabitState]) -> String {
        guard !habits.isEmpty else { return "No habits visible" }
        return habits.prefix(8)
            .map { "\($0.title) \($0.todayCount)/\($0.targetCount)" }
            .joined(separator: ", ")
    }

    private func objectiveSummary(for objectives: [ObjectiveState]) -> String {
        guard !objectives.isEmpty else { return "No objectives visible" }
        return objectives.prefix(5)
            .map { "\($0.title) \(Int($0.progress * 100))%" }
            .joined(separator: ", ")
    }
}
