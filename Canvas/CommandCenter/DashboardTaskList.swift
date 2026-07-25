// Canvas/CommandCenter/DashboardTaskList.swift
// The Command Center ledger: sectioned task lists with priority leads, due
// chips, inline play — and live drag-to-reorder.
//
// Rows live inside TaskReorderBand (the drag), and each row is its own view
// (DashboardTaskRow), so hovering one row no longer rebuilds the whole ledger.
// March 2026 · live reorder July 2026

import SwiftUI

struct DashboardTaskList: View {

    var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController
    var onSelectTask: ((TaskViewModel) -> Void)?

    @State private var selectedTaskUUIDs: Set<String> = []
    @State private var seriesDeleteTarget: TaskViewModel?
    @State private var seriesDeleteCompletionCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if viewModel.viewMode == .upcoming {
                UpcomingBoardView(viewModel: viewModel, composer: composer)
            } else {
                ledger
            }
        }
        // The fence a lifted row crosses to stop being a reorder and start
        // being a delivery to the sidebar or the Day Spine.
        .taskDragLedger()
        .confirmationDialog(
            "Delete \"\(seriesDeleteTarget?.title ?? "")\"?",
            isPresented: Binding(
                get: { seriesDeleteTarget != nil },
                set: { if !$0 { seriesDeleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete series", role: .destructive) {
                guard let target = seriesDeleteTarget else { return }
                seriesDeleteTarget = nil
                Sound.deleteTuck()
                Task { await viewModel.deleteTask(uuid: target.uuid) }
            }
            Button("Cancel", role: .cancel) { seriesDeleteTarget = nil }
        } message: {
            Text(SeriesDeleteCopy.message(completionCount: seriesDeleteCompletionCount))
        }
    }

    private var ledger: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                lists

                // The hints are ledger verbs (N, ↑↓, Space, ⌫ all act on this
                // list) — they live at the column's foot as its quiet terminus,
                // never at the window bottom where the assistant island owns
                // the center.
                DashboardShortcutBar(viewModel: viewModel)
                    .padding(.horizontal, DS.space10)
                    .padding(.top, DS.space16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Hands the pilot this scroll view so a lifted row dragged to the
            // top or bottom edge scrolls the ledger under itself.
            .taskDragScrollAnchor()
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var lists: some View {
        switch viewModel.viewMode {
        case .today:
            todayView
        case .logbook:
            completedView
        case .anytime:
            anytimeView
        case .someday:
            somedayView
        case .project:
            projectView
        case .upcoming, .habits, .reports, .queue, .area:
            EmptyView()
        }
    }

    // MARK: - Delete Routing

    /// Default delete for an occurrence row cancels just that occurrence; deleting the
    /// whole series goes through the confirmation dialog above.
    private func requestSeriesDelete(_ task: TaskViewModel) {
        Task {
            seriesDeleteCompletionCount = await viewModel.seriesCompletionCount(templateUUID: task.uuid)
            seriesDeleteTarget = task
        }
    }

    /// Batch delete that understands recurring occurrences: occurrence rows are canceled
    /// individually (never soft-deleting the series template they share a uuid with).
    private func deleteSelectedTasks(_ uuids: Set<String>) {
        Sound.deleteTuck()
        let visible = viewModel.currentVisibleTasks
        var plainUUIDs = Set<String>()
        var occurrenceTasks: [TaskViewModel] = []
        for uuid in uuids {
            if let match = visible.first(where: { $0.uuid == uuid }), match.isOccurrence {
                occurrenceTasks.append(match)
            } else {
                plainUUIDs.insert(uuid)
            }
        }
        Task {
            for occurrence in occurrenceTasks {
                _ = await viewModel.cancelOccurrence(occurrence)
            }
            if !plainUUIDs.isEmpty {
                await viewModel.deleteMultipleTasks(uuids: plainUUIDs)
            }
        }
    }

    // MARK: - Today View

    @ViewBuilder
    private var todayView: some View {
        // Batch action bar
        if !selectedTaskUUIDs.isEmpty {
            batchActionBar
        }

        if !viewModel.overdueTasks.isEmpty {
            taskSection(
                title: "Overdue",
                tasks: viewModel.overdueTasks,
                headerColor: DS.red,
                isSemantic: true,
                showReschedule: true,
                ordering: .manual,
                band: .overdue
            )
        }

        if !viewModel.scheduledTasks.isEmpty {
            taskSection(
                title: "Scheduled",
                tasks: viewModel.scheduledTasks,
                headerColor: DS.textSecondary,
                // The clock arranges this band, so a drag inside it carries the
                // row out (to a block, to a list) but never pretends to reorder.
                ordering: .clock,
                band: nil
            )
        }

        // "To do", not "Today" — the page title already says Today; a section
        // must never echo it (the duplicate-word law). The count speaks the
        // reward-loop language ("4 left" ticks down as rows depart), never a
        // bare tally.
        if !viewModel.unscheduledTasks.isEmpty {
            taskSection(
                title: "To do",
                tasks: viewModel.unscheduledTasks,
                headerColor: DS.textSecondary,
                countSuffix: "left",
                ordering: .manual,
                band: .unscheduled
            )
        }

        let hasActiveTasks = !viewModel.overdueTasks.isEmpty
            || !viewModel.scheduledTasks.isEmpty
            || !viewModel.unscheduledTasks.isEmpty

        // Only truly empty when nothing is planned AND nothing was finished today —
        // a day cleared to completion shows its Completed section, not "No tasks".
        if !hasActiveTasks && viewModel.completedTasksForSelectedDay.isEmpty {
            emptyState(message: "No tasks today", icon: "calendar")
        }

        SmartTaskCaptureRow(viewModel: viewModel)

        // The evening register: after 17:00 (or the moment the day clears)
        // the page hands you tomorrow — the "plan tomorrow today" ritual as
        // a door, not another task.
        if viewModel.isEveningRegister {
            EveningPlanRow(viewModel: viewModel)
        }

        // Finished work files itself away at the very bottom — dimmed, struck
        // through, still one tap from being reopened (iOS Today parity).
        if !viewModel.completedTasksForSelectedDay.isEmpty {
            completedTodaySection
        }
    }

    // MARK: - Completed (Today)

    /// The receding pile of today's checked-off tasks under one quiet "Completed"
    /// header. `.fixed` ordering: completed work is a record, not a plan — it
    /// never lifts.
    @ViewBuilder
    private var completedTodaySection: some View {
        let completed = viewModel.completedTasksForSelectedDay
        sectionHeader(
            title: "Completed",
            color: DS.textSecondary,
            trailing: "\(completed.count)"
        )

        band(tasks: completed, ordering: .fixed, band: nil)

        Spacer().frame(height: DS.space16)
    }

    // MARK: - Completed View

    @ViewBuilder
    private var completedView: some View {
        if viewModel.completedTasksByDay.isEmpty {
            emptyState(message: "No completed tasks yet", icon: "checkmark.circle")
        } else {
            ForEach(viewModel.completedTasksByDay, id: \.date) { dayGroup in
                sectionHeader(
                    title: completedDayLabel(dayGroup.date),
                    color: DS.green,
                    trailing: "\(dayGroup.tasks.count)",
                    isSemantic: Calendar.current.isDateInToday(dayGroup.date)
                )

                band(
                    tasks: dayGroup.tasks,
                    ordering: .fixed,
                    band: nil
                )
            }
        }
    }

    private func completedDayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "EEEE, MMM d"
        } else {
            formatter.dateFormat = "EEEE, MMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    // MARK: - Anytime View

    // No section header on the single-section lists: a lone section must
    // never echo the page's own title ("Anytime"/"ANYTIME" — the duplicate-
    // word law), and Things shows none here. The masthead and sidebar badge
    // already carry the context.
    @ViewBuilder
    private var anytimeView: some View {
        if viewModel.anytimeTasks.isEmpty {
            emptyState(message: "No anytime tasks", icon: "tray.full")
        } else {
            band(tasks: viewModel.anytimeTasks, ordering: .manual, band: .anytime)
        }

        SmartTaskCaptureRow(viewModel: viewModel)
    }

    // MARK: - Someday View

    @ViewBuilder
    private var somedayView: some View {
        if viewModel.somedayTasks.isEmpty {
            emptyState(message: "No someday tasks — park ideas here for later", icon: "archivebox")
        } else {
            band(tasks: viewModel.somedayTasks, ordering: .manual, band: .someday)
        }

        SmartTaskCaptureRow(viewModel: viewModel)
    }

    // MARK: - Project View

    @ViewBuilder
    private var projectView: some View {
        if viewModel.projectTasks.isEmpty && viewModel.projectHeadings.isEmpty {
            emptyState(message: "No tasks in this project yet", icon: "folder")
        } else {
            let tasksWithNoHeading = viewModel.projectTasks.filter { $0.headingUUID == nil }
            let sortedHeadings = viewModel.projectHeadings.sorted { $0.sortOrder < $1.sortOrder }

            ForEach(sortedHeadings) { heading in
                let headingTasks = viewModel.projectTasks.filter { $0.headingUUID == heading.id }
                projectHeadingSection(heading: heading, tasks: headingTasks)
            }

            if !tasksWithNoHeading.isEmpty || sortedHeadings.isEmpty {
                if !sortedHeadings.isEmpty {
                    sectionHeader(title: "No Heading", color: DS.textMuted, trailing: "\(tasksWithNoHeading.count)")
                }
                band(
                    tasks: tasksWithNoHeading,
                    ordering: .manual,
                    band: .project
                )
            }

            SmartTaskCaptureRow(
                viewModel: viewModel,
                contextProjectUUID: viewModel.selectedProjectUUID,
                placeholderText: "Add task to project…"
            )
        }
    }

    @ViewBuilder
    private func projectHeadingSection(heading: ProjectHeading, tasks: [TaskViewModel]) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: heading.isCollapsed ? "chevron.right" : "chevron.down")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .frame(width: 14)

            Text(heading.title)
                .font(DS.callout)
                .foregroundStyle(DS.accent)

            Spacer()

            if heading.isCollapsed {
                Text("\(tasks.count)")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(.vertical, DS.space8)
        .padding(.horizontal, DS.space12)
        .contentShape(Rectangle())

        if !heading.isCollapsed {
            band(
                tasks: tasks,
                ordering: .manual,
                band: .project
            )

            // Add task row for this heading
            SmartTaskCaptureRow(
                viewModel: viewModel,
                contextProjectUUID: viewModel.selectedProjectUUID,
                contextHeadingUUID: heading.id,
                placeholderText: "Add task to \(heading.title)…"
            )
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Section Component

    @ViewBuilder
    private func taskSection(
        title: String,
        tasks: [TaskViewModel],
        headerColor: Color,
        isSemantic: Bool = false,
        showReschedule: Bool = false,
        countSuffix: String? = nil,
        ordering: TaskBandOrdering,
        band orderBand: CommandCenterDashboardViewModel.ManualOrderBand?
    ) -> some View {
        sectionHeader(
            title: title,
            color: headerColor,
            trailing: tasks.isEmpty ? nil : countSuffix.map { "\(tasks.count) \($0)" } ?? "\(tasks.count)",
            isSemantic: isSemantic,
            showReschedule: showReschedule
        )

        band(tasks: tasks, ordering: ordering, band: orderBand)

        Spacer().frame(height: DS.space16)
    }

    /// One band of rows: the drag lives here, the row chrome lives in
    /// DashboardTaskRow, and neither knows about the other.
    private func band(
        tasks: [TaskViewModel],
        ordering: TaskBandOrdering,
        band orderBand: CommandCenterDashboardViewModel.ManualOrderBand?
    ) -> some View {
        // A band with nowhere to persist to must never look reorderable — it
        // would shuffle under the hand and revert on the next load.
        let resolved: TaskBandOrdering = (ordering == .manual && orderBand == nil) ? .clock : ordering
        // Resolved once per band, never per row: `currentVisibleTasks`
        // concatenates four arrays, and asking it "is this the cursor row?"
        // inside every row made the ledger quadratic in its own length.
        let cursorRowID = keyboardCursorRowID
        return TaskReorderBand(
            tasks: tasks,
            ordering: resolved,
            onReorder: { from, to in
                guard let orderBand else { return }
                viewModel.applyManualOrder(
                    band: orderBand,
                    orderedRowIDs: TaskReorderGeometry.reordered(tasks, from: from, to: to).map(\.id)
                )
            },
            onDragInFlightChange: { inFlight in
                viewModel.isTaskDragInFlight = inFlight
            }
        ) { task in
            row(task, isKeyboardSelected: task.id == cursorRowID)
        }
    }

    // MARK: - Section Header

    /// The one header voice (peakui): small-caps label — gilt by default,
    /// tinted for semantic sections (Overdue red) — live count, ledger rule,
    /// and section actions docked in the trailing slot.
    @ViewBuilder
    private func sectionHeader(
        title: String,
        color: Color,
        trailing: String? = nil,
        isSemantic: Bool = false,
        showReschedule: Bool = false
    ) -> some View {
        CosmoSectionHeader(
            label: title,
            detail: trailing,
            tint: isSemantic ? color : nil
        ) {
            if showReschedule {
                CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                    // Row ids ("uuid" or "uuid#day") so recurring occurrences reschedule via
                    // per-day overrides instead of rewriting their template's anchor.
                    .batchSchedule(
                        title: "Reschedule overdue tasks",
                        taskUUIDs: viewModel.overdueTasks.map(\.id),
                        anchor: anchor
                    )
                } label: {
                    Label("Reschedule", systemImage: "calendar.badge.clock")
                        .font(DS.caption)
                    .foregroundStyle(DS.red.opacity(0.85))
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, DS.space4)
                }
            }
        }
        .padding(.horizontal, DS.space10)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space6)
    }

    // MARK: - Single Task Row

    private func row(_ task: TaskViewModel, isKeyboardSelected: Bool) -> some View {
        DashboardTaskRow(
            task: task,
            viewModel: viewModel,
            composer: composer,
            isKeyboardSelected: isKeyboardSelected,
            isMultiSelected: selectedTaskUUIDs.contains(task.uuid),
            selectionCount: selectedTaskUUIDs.count,
            onTap: { handleRowTap(task) },
            onRequestSeriesDelete: { requestSeriesDelete(task) },
            onDeleteSelection: {
                let toDelete = selectedTaskUUIDs
                selectedTaskUUIDs.removeAll()
                deleteSelectedTasks(toDelete)
            }
        )
    }

    /// The row the ↑↓ cursor is on, as a row id.
    private var keyboardCursorRowID: String? {
        guard let idx = viewModel.selectedTaskIndex else { return nil }
        let visible = viewModel.currentVisibleTasks
        guard visible.indices.contains(idx) else { return nil }
        return visible[idx].id
    }

    // MARK: - Batch Action Bar

    private var batchActionBar: some View {
        HStack(spacing: DS.space12) {
            Text("\(selectedTaskUUIDs.count) selected")
                .font(DS.cardMeta)
                .foregroundStyle(DS.text)
                .monospacedDigit()
                .contentTransition(.numericText())

            Spacer()

            Button {
                let toDelete = selectedTaskUUIDs
                selectedTaskUUIDs.removeAll()
                deleteSelectedTasks(toDelete)
            } label: {
                HStack(spacing: DS.space4) {
                    Image(systemName: "trash")
                        .font(DS.footnote)
                    Text("Delete")
                        .font(DS.cardMeta)
                }
                .foregroundStyle(DS.red)
            }
            .buttonStyle(.plain)
            .help("Delete the selected tasks")

            Button {
                selectedTaskUUIDs.removeAll()
            } label: {
                Text("Cancel")
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Clear the selection (Esc)")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .background(DS.surface, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                .stroke(DS.accent.opacity(0.2), lineWidth: 1)
        )
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: selectedTaskUUIDs.count)
    }

    private func handleRowTap(_ task: TaskViewModel) {
        // ⌘-click is the Mac's toggle-into-selection gesture (shift kept for
        // muscle memory until range selection lands).
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) || modifiers.contains(.shift) {
            if selectedTaskUUIDs.contains(task.uuid) {
                selectedTaskUUIDs.remove(task.uuid)
            } else {
                selectedTaskUUIDs.insert(task.uuid)
            }
        } else {
            selectedTaskUUIDs.removeAll()
            onSelectTask?(task)
        }
    }

    // MARK: - Empty State

    private func emptyState(message: String, icon: String) -> some View {
        let presentation = emptyStatePresentation(message: message, icon: icon)
        return CommandCenterEmptyPane(
            icon: icon,
            title: presentation.title,
            subtitle: presentation.subtitle
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space16)
    }

    private func emptyStatePresentation(message: String, icon: String) -> (title: String, subtitle: String) {
        switch icon {
        case "calendar":
            return ("Today is clear", "Add a task or drag one into Today when you are ready to schedule it.")
        case "checkmark.circle":
            return ("No completed tasks yet", "Completed tasks will collect here as you finish the day.")
        case "tray.full":
            return ("No anytime tasks", "Tasks without a date will wait here until you are ready to plan them.")
        case "archivebox":
            return ("Someday is empty", "Park ideas here when they matter, but not today.")
        case "folder":
            return ("No tasks in this project yet", "Add the next concrete step and keep the project moving.")
        default:
            return (message, "Add a task when you are ready.")
        }
    }

    /// The one duration voice: "2h 9m", never "129m".
    static func durationLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}

struct CommandCenterTaskCompletionState: Equatable {
    var ringProgress: CGFloat = 0
    var fillScale: CGFloat = 0.7
    var fillOpacity: Double = 0
    var checkProgress: CGFloat = 0
    var strikeProgress: CGFloat = 0
    var rowOpacity: Double = 1
    var rowScale: CGFloat = 1
    var rowOffsetY: CGFloat = 0
    var blurRadius: CGFloat = 0

    static let initial = CommandCenterTaskCompletionState()
}

struct CommandCenterCompletionTimings {
    let ringDuration: Double
    let checkDelay: Double
    let checkResponse: Double
    let strikeDelay: Double
    let strikeDuration: Double
    let fadeDelay: Double
    let fadeDuration: Double

    init(reduceMotion: Bool) {
        if reduceMotion {
            ringDuration = 0.14
            checkDelay = 0.05
            checkResponse = 0.18
            strikeDelay = 0.16
            strikeDuration = 0.10
            fadeDelay = 0.28
            fadeDuration = 0.16
        } else {
            ringDuration = 0.24
            checkDelay = 0.12
            checkResponse = 0.24
            strikeDelay = 0.32
            strikeDuration = 0.18
            fadeDelay = 0.54
            fadeDuration = 0.24
        }
    }
}

struct CommandCenterAnimatedCheckbox: View {
    let priorityColor: Color
    let isCompleted: Bool
    let completionState: CommandCenterTaskCompletionState?
    let size: CGFloat

    private var ringProgress: CGFloat {
        if isCompleted { return 1 }
        return completionState?.ringProgress ?? 0
    }

    private var fillScale: CGFloat {
        if isCompleted { return 1 }
        return completionState?.fillScale ?? 0.7
    }

    private var fillOpacity: Double {
        if isCompleted { return 1 }
        return completionState?.fillOpacity ?? 0
    }

    private var checkProgress: CGFloat {
        if isCompleted { return 1 }
        return completionState?.checkProgress ?? 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(priorityColor.opacity(isCompleted ? 0 : 0.4), lineWidth: 1.5)
                .frame(width: size, height: size)

            Circle()
                .fill(DS.green)
                .frame(width: size, height: size)
                .scaleEffect(fillScale)
                .opacity(fillOpacity)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(DS.green, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .opacity(isCompleted || completionState != nil ? 1 : 0)

            CommandCenterCheckmarkShape()
                .trim(from: 0, to: checkProgress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.52, height: size * 0.52)
        }
        .frame(width: size, height: size)
    }
}

struct CommandCenterAnimatedTaskTitle: View {
    let title: String
    let isCompleted: Bool
    let completionState: CommandCenterTaskCompletionState?
    let font: Font
    let activeColor: Color
    let completedColor: Color

    private var strikeProgress: CGFloat {
        if isCompleted { return 1 }
        return completionState?.strikeProgress ?? 0
    }

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(isCompleted || completionState != nil ? completedColor : activeColor)
            .strikethrough(isCompleted, color: completedColor)
            .overlay(alignment: .leading) {
                if !isCompleted {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(completedColor)
                            .frame(width: geo.size.width * strikeProgress, height: 1.4)
                            .position(
                                x: (geo.size.width * strikeProgress) / 2,
                                y: geo.size.height * 0.54
                            )
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

private struct CommandCenterCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.56))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.18))
        return path
    }
}

// MARK: - Evening register (Plan Tomorrow)

/// The "plan tomorrow today" ritual as a door: one click lands on tomorrow's
/// page with the capture row waiting (⌥⌘← comes back; the masthead's Today
/// pill appears on the far side). The glance line answers "how loaded is
/// tomorrow already?" before you commit the evening to it.
private struct EveningPlanRow: View {
    var viewModel: CommandCenterDashboardViewModel

    @State private var plannedCount: Int?
    @State private var isHovered = false

    private var tomorrow: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    private var metaLine: String {
        let dayName = tomorrow.formatted(.dateTime.weekday(.wide))
        guard let plannedCount else { return dayName }
        if plannedCount == 0 { return "\(dayName) · a clear slate" }
        return "\(dayName) · \(plannedCount) already waiting"
    }

    var body: some View {
        Button {
            withAnimation(ProMotionSprings.focusTransition) {
                viewModel.shiftSelectedDay(by: 1)
            }
        } label: {
            HStack(spacing: DS.space10) {
                Image(systemName: "moon.stars")
                    .font(DS.caption)
                    .foregroundStyle(DS.gilt)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Plan tomorrow")
                        .font(DS.callout.weight(.medium))
                        .foregroundStyle(DS.text)
                    Text(metaLine)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(isHovered ? DS.text : DS.textMuted)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                    .fill(isHovered ? DS.glassCardFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, DS.space8)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Open tomorrow (⌥⌘→)")
        // Re-glance when today's ledger changes — pushing a task to tomorrow
        // updates the waiting count the moment the row departs.
        .task(id: viewModel.currentVisibleTasks.count) {
            plannedCount = await viewModel.plannedOpenCount(for: tomorrow)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan tomorrow. \(metaLine). Opens tomorrow's page.")
    }
}
