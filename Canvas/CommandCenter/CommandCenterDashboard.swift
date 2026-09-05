// Canvas/CommandCenter/CommandCenterDashboard.swift
// Things 3-inspired 3-column dashboard: Sidebar + Smart Lists + Context Panel
// Left: Navigation Sidebar | Center: Tasks + Timer | Right: Context Panel
// March 2026

import SwiftUI

struct CommandCenterDashboard: View {

    @State private var viewModel: CommandCenterDashboardViewModel
    @State private var contextProvider: CommandCenterContextProvider
    @State private var composer = CommandCenterComposerController()
    @State private var selectedTaskForDetail: TaskViewModel?
    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner
    private let showsInternalSidebar: Bool

    /// First-load arrival choreography — lives on the VM so the cascade plays
    /// once per app session, not on every destination revisit (the VM persists
    /// in MainView; a view-local flag reset on every remount and re-ran the
    /// whole entrance).
    private var hasAppeared: Bool { viewModel.hasPlayedArrivalCascade }

    init(
        viewModel: CommandCenterDashboardViewModel? = nil,
        showsInternalSidebar: Bool = true
    ) {
        let dashboardViewModel = viewModel ?? CommandCenterDashboardViewModel()
        _viewModel = State(initialValue: dashboardViewModel)
        _contextProvider = State(initialValue: CommandCenterContextProvider(viewModel: dashboardViewModel))
        self.showsInternalSidebar = showsInternalSidebar
    }

    var body: some View {
        GeometryReader { geometry in
            // Resolved in-pass, the Idea-bench law: routing width through
            // `.onChange` -> state seats columns against the width from
            // BEFORE a resize and clips for a pass. Below its full measure
            // (~1111pt) this page used to keep every column mounted and
            // simply clip at the trailing edge whenever a pane deck or a
            // narrow window squeezed the slot.
            let seats = DashboardLayoutMetrics.seats(
                width: geometry.size.width,
                wantsInternalSidebar: showsInternalSidebar
            )
            dashboardBody(seats: seats)
        }
    }

    private func dashboardBody(seats: DashboardColumnSeats) -> some View {
        ZStack(alignment: .topLeading) {
            // The rail runs full-bleed to the pane's top/bottom/trailing
            // edges (an integrated sidebar meets its window, never floats
            // inset); only the working region keeps the page margin.
            HStack(alignment: .top, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    if seats.internalSidebar {
                        leftColumn
                    }
                    centerColumn(seats: seats)
                }
                .padding(DS.space24)

                if !viewModel.viewMode.isFullPlanningPage, seats.rail {
                    rightColumn
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The one space every drag-aware surface measures in: the ledger's
            // rows, the sidebar's smart lists and project rows, and the Day
            // Spine's blocks and time slots all speak these points, so a lifted
            // task row can be carried between them.
            .coordinateSpace(name: CommandCenterDragSpace.name)
            .overlay(alignment: .topLeading) { TaskDragTravelCard() }
            .overlay(alignment: .bottom) {
                SwipeSaveToast(message: Binding(
                    get: { viewModel.dropToastMessage },
                    set: { viewModel.dropToastMessage = $0 }
                ))
            }
            .task {
                // First visit: migrations + refreshAll (moved out of the VM's
                // init so app launch no longer pays them); revisits hit the
                // loadIfNeeded guards and render the warm data instantly.
                await viewModel.startInitialLoadIfNeeded()
                await viewModel.loadAreasIfNeeded()
                await viewModel.loadAnytimeTasksIfNeeded()
                await viewModel.loadSomedayTasksIfNeeded()
                publishCommandCenterContext()
                if !viewModel.hasPlayedArrivalCascade {
                    // One frame at rest, then the cascade — flipped in the
                    // same update, sections would mount already-visible.
                    try? await Task.sleep(for: .milliseconds(16))
                    guard !Task.isCancelled else { return }
                    viewModel.hasPlayedArrivalCascade = true
                }
                // Warm the sound graph so the first completion of the session
                // is as tight as the tenth — but AFTER the entrance settles:
                // prewarm() decodes 33 CAF files and starts AVAudioEngine on
                // the main actor, which used to land inside the destination
                // crossfade on the very first Today open. Sound call sites
                // already startIfNeeded() lazily, so a completion inside this
                // window still plays.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                SoundEngine.shared.prewarm()
            }
            .onAppear(perform: publishCommandCenterContext)
            .onChange(of: isPaneContextOwner) { _, _ in publishCommandCenterContext() }
            .onChange(of: viewModel.viewMode) { _, mode in
                // The context provider pulls from the VM lazily, so a republish
                // on mode change (plus appear/pane-owner) replaces the old
                // per-objectWillChange republish that fired on every VM change.
                publishCommandCenterContext()
                guard mode.isFullPlanningPage else { return }
                selectedTaskForDetail = nil
                composer.dismiss()
            }
            // Lives on the root, not the rail: the rail sheds below its
            // seat width and a shed rail must not stop the deleted-task
            // detail/composer cleanup from firing.
            .onChange(of: visibleTaskUUIDs) { _, taskUUIDs in
                clearDeletedTaskState(visibleTaskUUIDs: taskUUIDs)
            }

            CommandCenterComposerHost(viewModel: viewModel, composer: composer)
        }
        // (No cancelled-drag net needed any more: the task lift is a real
        // gesture with a real onEnded — TaskDragPilot — instead of a system drag
        // session whose lifetime had to be inferred from a preview view's
        // onAppear/onDisappear and un-stuck by the next hover.)
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
    }

    // MARK: - Center Column — Timer + Content (Smart List or Project)

    private func centerColumn(seats: DashboardColumnSeats) -> some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Group {
                centerContent(seats: seats)
            }
            .id(centerContentTransitionID)
            .transition(.opacity)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.space16)
        .animation(ProMotionSprings.gentle, value: centerContentTransitionID)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.cosmo.commandCenter.keyboardAction"))) { notification in
            guard viewModel.viewMode.showsTaskList else { return }
            handleKeyboardAction(notification)
        }
    }

    @ViewBuilder
    private func centerContent(seats: DashboardColumnSeats) -> some View {
        switch viewModel.viewMode {
        case .habits:
            HabitsSectionView(viewModel: viewModel, composer: composer)
        case .reports:
            ReportsSectionView(viewModel: viewModel)
        case .queue:
            // Retired — the VM redirects to Upcoming's Content lens on the
            // next tick; render nothing for the transient frame.
            Color.clear
        case .today, .upcoming, .anytime, .someday, .logbook, .project, .area:
            existingTaskOrProjectContent(seats: seats)
        }
    }

    @ViewBuilder
    private func existingTaskOrProjectContent(seats: DashboardColumnSeats) -> some View {
        if viewModel.viewMode == .project, let projectUUID = viewModel.selectedProjectUUID,
           let project = viewModel.projects.first(where: { $0.uuid == projectUUID }) {
            ProjectDetailView(project: project, viewModel: viewModel)
        } else if viewModel.viewMode == .upcoming {
            CommandCenterMasthead(viewModel: viewModel)

            // The content calendar moved to Studio › Pipeline (one room per
            // stage of material); Upcoming is the time board only.
            UpcomingBoardView(viewModel: viewModel, composer: composer)
                .frame(maxHeight: .infinity)
        } else {
            // ONE composed group: masthead, brief, gauge, divider, and the
            // two working columns share a single bounded width — defined by
            // the columns themselves (list + gap + timeline) — centered in
            // the pane, so hairlines stop at the group's edges and the
            // margins balance instead of pooling on one side.
            VStack(alignment: .leading, spacing: DS.space16) {
                CommandCenterMasthead(viewModel: viewModel)

                if viewModel.viewMode == .today {
                    // On the content rail like every sibling band — the brief
                    // was the page's only element still at x=0.
                    DailyBriefCard()
                        .padding(.horizontal, DS.space12)
                        .cascadeIn(hasAppeared, index: 0)

                    // The deep-work gauge is Today's hero — Anytime/Someday/
                    // Logbook are ledgers, not the day's cockpit.
                    DashboardTimeTracker(viewModel: viewModel)
                        .cascadeIn(hasAppeared, index: 1)

                    // Divider only where the gauge sits above the list — the
                    // ledger lists already end their masthead with a hairline.
                    gradientDivider

                    HStack(alignment: .top, spacing: DS.space24) {
                        selectingTaskList
                            .cascadeIn(hasAppeared, index: 2)

                        // The day timeline is the first column to shed:
                        // below its seat width Today collapses to the ONE
                        // ledger column (the LAW: collapse, never shrink
                        // the two columns into each other).
                        if seats.timeline {
                            DashboardDayTimeline(viewModel: viewModel) { task in
                                selectTaskForDetail(task)
                            }
                            .frame(width: DashboardLayoutMetrics.timelineWidth)
                            .cascadeIn(hasAppeared, index: 3)
                        }
                    }
                    // The page's ONE trailing rail (x = W−12): the schedule
                    // rule now terminates on the same line as the masthead
                    // date and the Start-focus pill above it.
                    .padding(.trailing, DS.space12)
                    .frame(maxHeight: .infinity)
                } else {
                    selectingTaskList
                        .cascadeIn(hasAppeared, index: 2)
                }
            }
            .frame(maxWidth: Self.ledgerGroupWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// The composition fills the pane — small gutters, never a floating
    /// island (deep margins on three sides read as "a window in the top
    /// half"). The cap only guards ultrawide displays; on normal windows
    /// the group breathes out to the pane's edges and the list column takes
    /// the flexible remainder beside the fixed timeline.
    private static var ledgerGroupWidth: CGFloat { 1500 }

    private var selectingTaskList: some View {
        DashboardTaskList(viewModel: viewModel, composer: composer) { task in
            selectTaskForDetail(task)
        }
    }

    private func selectTaskForDetail(_ task: TaskViewModel) {
        withAnimation(ProMotionSprings.snappy) {
            selectedTaskForDetail = task
            viewModel.showReports = false
        }
    }

    // showReports must NOT be part of this ID — the habits/reports toggle
    // lives in the right rail; folding it in remounted the whole center
    // column (gauge, timer, masthead) on every rail tab switch.
    private var centerContentTransitionID: String {
        [
            viewModel.viewMode.rawValue,
            viewModel.viewMode == .upcoming ? viewModel.upcomingLens.rawValue : "no-lens",
            viewModel.selectedProjectUUID ?? "no-project",
            viewModel.selectedAreaUUID ?? "no-area"
        ].joined(separator: ":")
    }

    // MARK: - Keyboard Handling

    private func handleKeyboardAction(_ notification: Notification) {
        guard let keyCode = notification.userInfo?["keyCode"] as? UInt16 else { return }

        // ⌥⌘←/→ — page the viewed day (the masthead chevrons' keyboard twin).
        let modifiersRaw = notification.userInfo?["modifiers"] as? UInt ?? 0
        if (modifiersRaw & (1 << 20)) != 0, (modifiersRaw & (1 << 19)) != 0,
           keyCode == 123 || keyCode == 124 {
            guard viewModel.viewMode == .today else { return }
            withAnimation(ProMotionSprings.snappy) {
                viewModel.shiftSelectedDay(by: keyCode == 123 ? -1 : 1)
            }
            return
        }

        let tasks = viewModel.currentVisibleTasks

        // ⌥⌘↑/↓ — move the selected task one slot inside its band: the drag's
        // keyboard twin, so reordering has a path that never needs a mouse.
        if (modifiersRaw & (1 << 20)) != 0, (modifiersRaw & (1 << 19)) != 0,
           keyCode == 125 || keyCode == 126 {
            guard let idx = viewModel.selectedTaskIndex, tasks.indices.contains(idx) else { return }
            let moved = withAnimation(ProMotionSprings.release) {
                viewModel.nudgeTask(rowID: tasks[idx].id, by: keyCode == 126 ? -1 : 1)
            }
            if moved {
                Sound.dragDrop()
                // The cursor follows the row it moved, not the slot it left.
                viewModel.selectedTaskIndex = viewModel.currentVisibleTasks
                    .firstIndex(where: { $0.id == tasks[idx].id }) ?? idx
            }
            return
        }

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
                    Sound.focusPause()
                    viewModel.sessionEngine.pauseSession()
                } else {
                    Sound.focusResume()
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

        case 17: // T — move selected task to Today
            if let idx = viewModel.selectedTaskIndex, tasks.indices.contains(idx) {
                let task = tasks[idx]
                // Occurrence-aware: an occurrence row moves via a per-day
                // override, never a template rewrite.
                Task { await viewModel.rescheduleTask(task, toDate: Date()) }
            }

        case 14: // E — set selected task to This Evening
            if let idx = viewModel.selectedTaskIndex, tasks.indices.contains(idx) {
                let task = tasks[idx]
                Task {
                    await viewModel.rescheduleTask(task, toDate: Date())
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

    /// Upcoming offers a Shelf — the ideas you drag onto the week board to
    /// book writing sessions. It's a TAB, not a takeover: habits, reports
    /// and task details stay one click away.
    private var offersWorkShelf: Bool {
        viewModel.viewMode == .upcoming
    }

    private var showsWorkShelf: Bool {
        offersWorkShelf && viewModel.upcomingRailFace == .shelf
    }

    private var rightColumn: some View {
        CommandCenterRail {
            VStack(alignment: .leading, spacing: DS.space16) {
                rightColumnTabs
                if showsWorkShelf {
                    IdeaWorkShelfRail(viewModel: viewModel)
                } else {
                    rightColumnContent
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: DashboardLayoutMetrics.railWidth)
        .animation(ProMotionSprings.gentle, value: showsWorkShelf)
    }

    private var rightColumnTabs: some View {
        HStack(spacing: 0) {
            if offersWorkShelf {
                rightColumnTab(.shelf, label: "Shelf", icon: "tray.full")
            }
            if selectedTaskForDetail != nil {
                rightColumnTab(.details, label: "Details", icon: "info.circle")
            }
            rightColumnTab(.habits, label: "Habits", icon: "checkmark.circle")
            rightColumnTab(.reports, label: "Reports", icon: "chart.bar")
        }
    }

    @ViewBuilder
    private var rightColumnContent: some View {
        switch showingDetailTab {
        case .shelf:
            // Unreachable — the shelf renders in place of this whole branch.
            EmptyView()
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
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        case .reports:
            ScrollView(.vertical) {
                DashboardReportsPanel(viewModel: viewModel)
            }
            .scrollIndicators(.never)
        case .habits:
            DashboardHabitPanel(viewModel: viewModel, composer: composer)
        }
    }

    private enum RightColumnTab {
        case shelf, details, habits, reports
    }

    private var showingDetailTab: RightColumnTab {
        // The shelf is a stored face, so it outranks the derived trio — those
        // three have no selection of their own, they're inferred from state.
        if showsWorkShelf {
            return .shelf
        } else if selectedTaskForDetail != nil && !viewModel.showReports {
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

    private func rightColumnTab(_ tab: RightColumnTab, label: String, icon: String) -> some View {
        let isActive = showingDetailTab == tab
        return Button {
            withAnimation(ProMotionSprings.snappy) {
                // Any tab other than Shelf means "show me the inspector", and
                // that choice is remembered across launches.
                if offersWorkShelf {
                    viewModel.upcomingRailFace = (tab == .shelf) ? .shelf : .inspector
                }
                switch tab {
                case .shelf:
                    break
                case .reports:
                    viewModel.showReports = true
                    selectedTaskForDetail = nil
                case .habits:
                    viewModel.showReports = false
                    selectedTaskForDetail = nil
                case .details:
                    viewModel.showReports = false
                }
            }
        } label: {
            VStack(spacing: DS.space4) {
                HStack(spacing: DS.space4) {
                    Image(systemName: icon)
                        .font(DS.caption2)
                    // Constant weight — a semibold swap re-layouts the tab row.
                    Text(label)
                        .font(DS.subheadline.weight(.medium))
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Gradient Divider

    // The one rule voice at the page's most structural seam — the doubled
    // Akashic hairline was a third rule dialect inside 200 vertical points
    // (the premium ornament register spent on a plain divider).
    private var gradientDivider: some View {
        CosmoPageRule()
            .padding(.horizontal, DS.space12)
    }

}

@MainActor
@Observable
final class CommandCenterContextProvider: CosmoContextProvider {
    @ObservationIgnored private weak var viewModel: CommandCenterDashboardViewModel?

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

}

// MARK: - Width classes (derive-never-type)

/// Which optional columns the dashboard can seat at a given width. Resolved
/// in-pass from the root GeometryReader — routing width through `.onChange`
/// -> state seats columns one pass late and clips during resizes (the
/// Idea-bench law).
struct DashboardColumnSeats: Equatable {
    var internalSidebar: Bool
    var rail: Bool
    var timeline: Bool
}

/// The dashboard's column arithmetic, derived from the columns the layout
/// actually mounts — never a typed magic threshold. Shedding order as width
/// shrinks: the day timeline first (Today collapses to the one ledger
/// column, the mac-Today LAW — collapse, never shrink), then the
/// habits/reports rail, then the internal navigation sidebar (navigation
/// outlives the inspector — the Things grammar). The flexible ledger never
/// drops below `minimumLedgerMeasure`. Before this, the page's full measure
/// was ~1111pt and every narrower slot (open pane deck, narrow window)
/// clipped at the trailing edge (Aug 2026 audit).
enum DashboardLayoutMetrics {
    /// The working region's page padding (`.padding(DS.space24)`, horizontal share).
    static let pagePadding: CGFloat = DS.space24 * 2
    /// The center column's own horizontal padding.
    static let centerPadding: CGFloat = DS.space16 * 2
    /// Navigation sidebar column plus its trailing gap.
    static let internalSidebarSpan: CGFloat = 240 + DS.space24
    static let railWidth: CGFloat = 280
    static let timelineWidth: CGFloat = 302
    /// Timeline column plus its leading gap and the page's trailing rail inset.
    static var timelineSpan: CGFloat { timelineWidth + DS.space24 + DS.space12 }
    /// The flexible ledger's floor beside seated columns.
    static let minimumLedgerMeasure: CGFloat = 460

    /// Seating priority when width is scarce: internal sidebar, then rail,
    /// then timeline — the inverse of the shedding order above. The order is
    /// what keeps seating MONOTONIC in width: a lower-priority column only
    /// spends budget the higher ones left behind, so growing the window can
    /// never swap one seated column for another.
    static func seats(width: CGFloat, wantsInternalSidebar: Bool) -> DashboardColumnSeats {
        var budget = width - pagePadding - centerPadding
        var seats = DashboardColumnSeats(internalSidebar: false, rail: false, timeline: false)
        if wantsInternalSidebar, budget - internalSidebarSpan >= minimumLedgerMeasure {
            seats.internalSidebar = true
            budget -= internalSidebarSpan
        }
        if budget - railWidth >= minimumLedgerMeasure {
            seats.rail = true
            budget -= railWidth
        }
        if budget - timelineSpan >= minimumLedgerMeasure {
            seats.timeline = true
        }
        return seats
    }
}
