// Canvas/CommandCenter/DashboardTaskRow.swift
// One task row in the Command Center ledger — extracted from DashboardTaskList
// so that hovering it, pressing it, or checking it off repaints THIS row and
// nothing else.
//
// It used to be a method on the list, reading list-level @State (hoveredTaskUUID,
// completionStates, dropTargetTaskUUID…). Every pointer move across the ledger
// therefore rebuilt the entire list body: all sections, every row, every drag
// preview and closure. That was the jitter. A row is a view; a view owns its own
// interaction state.
// July 2026

import SwiftUI

struct DashboardTaskRow: View {

    let task: TaskViewModel
    var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController
    /// Keyboard cursor (↑↓) — owned by the list, which knows the flat order.
    let isKeyboardSelected: Bool
    let isMultiSelected: Bool
    /// How many rows the ⌘-click selection holds, for the batch delete verb.
    let selectionCount: Int
    let onTap: () -> Void
    let onRequestSeriesDelete: () -> Void
    let onDeleteSelection: () -> Void

    @State private var isHovered = false
    @State private var completion: CommandCenterTaskCompletionState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focus: ActiveFocusSignal { .shared }
    private var dragPilot: TaskDragPilot { .shared }

    private var isActiveSession: Bool { focus.runningTaskUUID == task.uuid }
    private var isAnimatingCompletion: Bool { completion != nil }

    /// Hover is suppressed mid-completion: the row is already choreographing a
    /// scale/opacity/offset sequence, and a hover fill arriving on top of it
    /// reads as a flicker.
    private var showsHover: Bool { isHovered && !isAnimatingCompletion }

    private var showsInlineActions: Bool {
        showsHover || isKeyboardSelected || isActiveSession || composer.isShowingTaskAction(for: task.uuid)
    }

    var body: some View {
        rowBase
            .background(
                CommandCenterRowGlass(
                    isActive: isActiveSession,
                    isSelected: isMultiSelected || isKeyboardSelected,
                    isHovered: showsHover,
                    tint: task.priority.color
                )
                .padding(.horizontal, DS.space8)
            )
            .overlay(alignment: .bottom) { priorityWash }
            // Completed work recedes as a group on Today — remaining tasks own
            // the list. (Logbook keeps full strength; it's a list OF completed.)
            .opacity(task.isCompleted && !isAnimatingCompletion && viewModel.viewMode == .today ? 0.7 : 1)
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: showsHover)
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isKeyboardSelected)
            .scaleEffect(completion?.rowScale ?? 1)
            .opacity(completion?.rowOpacity ?? 1)
            .offset(y: completion?.rowOffsetY ?? 0)
            .blur(radius: completion?.blurRadius ?? 0)
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }
            .onHover { isHovered = $0 }
            .contextMenu { menu }
            .help(helpText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isMultiSelected || isKeyboardSelected ? [.isSelected] : [])
            .accessibilityAction(named: task.isCompleted ? "Reopen" : "Complete") {
                toggleCompletion()
            }
    }

    // MARK: - Row body

    private var rowBase: some View {
        HStack(spacing: 0) {
            priorityLead
            rowContent
                .padding(.trailing, DS.space8)
        }
        .padding(.vertical, DS.space6)
    }

    @ViewBuilder
    private var priorityLead: some View {
        if task.priority == .high || task.priority == .critical {
            Rectangle()
                .fill(task.priority.color.opacity(0.36))
                .frame(width: 3.5, height: 3.5)
                .rotationEffect(.degrees(45))
                .padding(.leading, 6)
                .padding(.trailing, 2)
                .accessibilityHidden(true)
        } else {
            Spacer().frame(width: 12)
        }
    }

    @ViewBuilder
    private var priorityWash: some View {
        if !task.isCompleted && !isAnimatingCompletion {
            LinearGradient(
                colors: [task.priority.color.opacity(0.035), Color.clear],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.4, y: 0.5)
            )
            .frame(height: 1)
            .clipShape(.rect(cornerRadius: 6))
            .accessibilityHidden(true)
        }
    }

    private var rowContent: some View {
        HStack(spacing: DS.space10) {
            checkbox

            taskContent

            Spacer(minLength: DS.space8)

            dueSlot

            if !task.isCompleted && !isAnimatingCompletion {
                HStack(spacing: DS.space4) {
                    playButton
                    actionButton
                }
                .opacity(showsInlineActions ? 1 : 0)
            }
        }
    }

    /// Inside Today, "Due today" is ambient context — every row repeating it is
    /// chrome noise (Things shows nothing). Overdue keeps its chip; other lists
    /// keep due dates. Overdue is judged from the VIEWED day, so scrolling back
    /// to a task's due day drops the "Overdue" chip — it's a normal item that
    /// day. Browsing AHEAD must never brand today's still-live tasks overdue
    /// either: the day sections anchor overdue to the REAL today, so this row
    /// does too. (Otherwise, in the frame between the day cursor advancing and
    /// the sections reloading, today's tasks flash the overdue chip while
    /// momentarily judged against tomorrow.)
    @ViewBuilder
    private var dueSlot: some View {
        let overdue = task.isOverdue(asOf: viewModel.selectedDate)
            && (viewModel.viewMode != .today || viewModel.isViewingToday)
        if let dueInfo = task.dueInfo(asOf: viewModel.selectedDate), !task.isCompleted,
           viewModel.viewMode != .today || overdue {
            HStack(spacing: 3) {
                if overdue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(DS.red)
                        .accessibilityHidden(true)
                }
                Text(dueInfo)
                    .font(DS.caption2)
                    .foregroundStyle(overdue ? DS.red : DS.commandCenterMutedText)
            }
            .frame(width: 76, alignment: .trailing)
        } else {
            Color.clear
                .frame(width: 76, height: 1)
        }
    }

    // MARK: - Checkbox

    private var checkbox: some View {
        Button {
            toggleCompletion()
        } label: {
            CommandCenterAnimatedCheckbox(
                priorityColor: task.priority.color,
                isCompleted: task.isCompleted,
                completionState: completion,
                size: 18
            )
            // The glyph stays 18pt (ledger density) but the target is a real
            // one — an 18pt circle is a dart board for a mouse.
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(task.isCompleted ? "Reopen (⌫)" : "Complete (⌫)")
        .accessibilityHidden(true)
    }

    // MARK: - Content

    /// Rows are monochrome until interaction matters (peakui — the accent-
    /// discipline law proven on iOS): intent, habit, repeat, and project meta all
    /// speak muted ink at rest; color arrives only on the row whose focus session
    /// is live. Identity colors live on identity surfaces, never sprayed across a
    /// ledger.
    private var taskContent: some View {
        let resolvedHabit = viewModel.resolvedHabit(for: task)
        let intentPresentation = viewModel.resolvedIntentPresentation(for: task)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.space4) {
                if !intentPresentation.isUnassigned {
                    Image(systemName: intentPresentation.icon)
                        .font(DS.caption2)
                        .foregroundStyle(isActiveSession ? intentPresentation.accent : DS.textMuted)
                        .accessibilityHidden(true)
                }

                if !task.titleMentions.isEmpty && completion == nil && !task.isCompleted {
                    TaskTitleWithMentions(
                        title: task.title,
                        mentions: task.titleMentions,
                        font: DS.callout
                    ) { mention in
                        NotificationCenter.default.post(
                            name: .init("com.cosmo.navigateToAtom"),
                            object: nil,
                            userInfo: ["uuid": mention.entityUUID, "intent": "general"]
                        )
                    }
                } else {
                    CommandCenterAnimatedTaskTitle(
                        title: task.title,
                        isCompleted: task.isCompleted,
                        completionState: completion,
                        font: DS.callout,
                        activeColor: DS.text,
                        completedColor: DS.textMuted
                    )
                    .lineLimit(1)
                }
            }

            metaLine(resolvedHabit: resolvedHabit)
        }
    }

    @ViewBuilder
    private func metaLine(resolvedHabit: HabitDefinition?) -> some View {
        HStack(spacing: DS.space6) {
            if let timeInfo = task.timeInfo {
                Label(timeInfo, systemImage: "clock")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            if task.isRecurring {
                Label("Repeats", systemImage: "repeat")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            if let resolvedHabit {
                Label(resolvedHabit.title, systemImage: resolvedHabit.icon)
                    .font(DS.caption2)
                    .foregroundStyle(isActiveSession ? resolvedHabit.accent : DS.textMuted)
            }

            blockBadge

            if let projectName = task.projectName {
                Text(projectName)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            focusMeta
        }
    }

    @ViewBuilder
    private var focusMeta: some View {
        if let goal = task.timeGoalMinutes {
            // Timed task: progress toward the goal (recurring per-day progress is
            // session-scoped, so template rows show the goal itself). A met goal
            // is a live achievement — the one meta accent.
            Label(
                task.isRecurring
                    ? "\(DashboardTaskList.durationLabel(goal)) goal"
                    : "\(DashboardTaskList.durationLabel(min(task.totalFocusMinutes, goal))) of \(DashboardTaskList.durationLabel(goal))",
                systemImage: "timer"
            )
            .font(DS.caption2)
            .foregroundStyle(!task.isRecurring && task.totalFocusMinutes >= goal ? DS.accent : DS.textMuted)
        } else if task.sessionCount > 0 {
            Label("\(DashboardTaskList.durationLabel(task.totalFocusMinutes)) tracked", systemImage: "timer")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    /// The block-membership badge — the same bare icon-plus-text grammar as the
    /// row's other meta labels, never a pill. Quiet by default (a small swatch in
    /// the block's color, muted text); while the block's occurrence is live the
    /// swatch becomes a play glyph and the name takes the color — "this is what I
    /// should be doing now".
    @ViewBuilder
    private var blockBadge: some View {
        if let blockTitle = task.blockTitle {
            let tint = task.blockColorHex.map(Color.init(hex:)) ?? DS.accent
            let isLive = !task.isCompleted && task.blockIsLive()
            HStack(spacing: 3) {
                if isLive {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(tint)
                } else {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(tint)
                        .frame(width: 6, height: 6)
                }
                Text(blockTitle)
                    .font(DS.caption2)
                    .foregroundStyle(isLive ? tint : DS.textMuted)
                    .lineLimit(1)
            }
            .help(isLive ? "In block \(blockTitle) — happening now" : "In block \(blockTitle)")
        }
    }

    // MARK: - Trailing controls

    private var playButton: some View {
        Button {
            guard !isDragMouseUp else { return }
            if isActiveSession {
                Sound.focusPause()
                DeepWorkSessionEngine.shared.pauseSession()
            } else {
                viewModel.startFocusSession(for: task)
            }
        } label: {
            // iOS-parity time-tracking affordance: dusty-rose task accent.
            Image(systemName: isActiveSession ? "pause.circle.fill" : "play.circle")
                .font(.system(size: 20))
                .foregroundStyle(DS.entityTask)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isActiveSession ? "Pause session (Space)" : "Start focus session (Space)")
        .accessibilityLabel(isActiveSession ? "Pause focus session" : "Start focus session")
    }

    private var actionButton: some View {
        CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
            .taskActions(task: task, anchor: anchor)
        } label: {
            Image(systemName: "ellipsis")
                .font(DS.caption2).fontWeight(.bold)
                .foregroundStyle(composer.isShowingTaskAction(for: task.uuid) ? DS.text : DS.textMuted)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(composer.isShowingTaskAction(for: task.uuid) ? DS.accentSoft : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(
                            composer.isShowingTaskAction(for: task.uuid) ? DS.accent.opacity(0.22) : Color.clear,
                            lineWidth: 0.8
                        )
                )
        }
        .help("Task actions")
        .accessibilityLabel("Task actions")
    }

    // MARK: - Menu

    @ViewBuilder
    private var menu: some View {
        Button {
            toggleCompletion()
        } label: {
            Label(
                task.isCompleted ? "Mark Incomplete" : "Complete",
                systemImage: task.isCompleted ? "circle" : "checkmark.circle"
            )
        }

        Divider()

        if isMultiSelected && selectionCount > 1 {
            Button(role: .destructive, action: onDeleteSelection) {
                Label("Delete \(selectionCount) Tasks", systemImage: "trash")
            }
        } else if task.isOccurrence {
            // Occurrence rows share the series template's uuid — a plain delete
            // would end the whole series, not just this day.
            Button(role: .destructive) {
                Sound.deleteTuck()
                Task { _ = await viewModel.cancelOccurrence(task) }
            } label: {
                Label("Remove This Occurrence", systemImage: "trash")
            }
            Button(role: .destructive, action: onRequestSeriesDelete) {
                Label("Delete Series…", systemImage: "trash.slash")
            }
        } else {
            Button(role: .destructive) {
                Sound.deleteTuck()
                Task { await viewModel.deleteTask(uuid: task.uuid) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Interaction

    /// A tap that arrives while a lift is in flight (or in the breath after a
    /// drop) is the drag's own mouse-up, not a click — dropping a row must never
    /// open it. See TaskDragPilot.suppressesRowTap.
    private var isDragMouseUp: Bool { dragPilot.suppressesRowTap }

    private func handleTap() {
        guard !isAnimatingCompletion, !isDragMouseUp else { return }
        onTap()
    }

    private var helpText: String {
        var parts = [task.title]
        if let due = task.dueInfo(asOf: viewModel.selectedDate) { parts.append(due) }
        parts.append(task.isCompleted ? "Click to open" : "Drag to reorder · click to open")
        return parts.joined(separator: " — ")
    }

    private var accessibilityLabel: String {
        var parts = [task.title]
        if task.isCompleted { parts.append("completed") }
        if let due = task.dueInfo(asOf: viewModel.selectedDate) { parts.append(due) }
        if let projectName = task.projectName { parts.append("in \(projectName)") }
        if isActiveSession { parts.append("focus session running") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Completion choreography

    private func toggleCompletion() {
        // A short pull that started on the 28pt checkbox lifts the row AND
        // releases inside the button — without this, dragging from the checkbox
        // completes the task.
        guard completion == nil, !isDragMouseUp else { return }

        if task.isCompleted {
            Task { _ = await viewModel.uncompleteTask(task) }
            return
        }

        let timings = CommandCenterCompletionTimings(reduceMotion: reduceMotion)
        // The signature cue rides the animation keyframes: swish with the ring,
        // pen stroke with the check, landing note with the strike.
        Sound.taskCompletion(timings: timings)
        completion = .initial

        withAnimation(.easeInOut(duration: timings.ringDuration)) {
            update { state in
                state.ringProgress = 1
                state.fillScale = 1
                state.fillOpacity = 1
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(timings.checkDelay))
            withAnimation(.spring(response: timings.checkResponse, dampingFraction: 0.78)) {
                update { $0.checkProgress = 1 }
            }

            try? await Task.sleep(for: .seconds(timings.strikeDelay - timings.checkDelay))
            withAnimation(.easeInOut(duration: timings.strikeDuration)) {
                update { $0.strikeProgress = 1 }
            }

            try? await Task.sleep(for: .seconds(timings.fadeDelay - timings.strikeDelay))
            withAnimation(.easeInOut(duration: timings.fadeDuration)) {
                update { state in
                    // Settle into the receded "completed" look (0.7, matching the
                    // Completed section) and drift downward — the row files
                    // itself into the pile below instead of vanishing, so the
                    // hand-off to the Completed section reads as one continuous
                    // move.
                    state.rowOpacity = 0.7
                    state.rowOffsetY = reduceMotion ? 4 : 12
                }
            }

            try? await Task.sleep(for: .seconds(timings.fadeDuration))
            let completed = await viewModel.completeTask(task)

            if completed {
                completion = nil
                viewModel.notifyCompletedTaskArrival()
                // The last open task of the day fell — the one earned moment.
                // (completeTask refreshed the section arrays before returning, so
                // isDayClear speaks the post-completion truth.)
                if viewModel.viewMode == .today, viewModel.isDayClear {
                    Sound.dayClear()
                }
            } else {
                // Persistence failed — reverse the optimistic animation so the
                // row comes back instead of silently vanishing while the task
                // stays incomplete. Habit/XP credit was withheld inside
                // completeTask.
                withAnimation(.easeOut(duration: 0.2)) {
                    update { $0 = .initial }
                }
                try? await Task.sleep(for: .milliseconds(250))
                completion = nil
            }
        }
    }

    private func update(_ change: (inout CommandCenterTaskCompletionState) -> Void) {
        var state = completion ?? .initial
        change(&state)
        completion = state
    }
}

// MARK: - Equality

/// Compared by its VALUES, so a drag frame — which changes only the band's
/// offsets — never re-runs twenty row bodies. Observed reads inside the body
/// (viewModel.viewMode, composer state, the focus signal) still invalidate this
/// row on their own; this only stops the parent from rebuilding it for nothing.
///
/// The closures are deliberately excluded from the comparison. They are only
/// stale when a value in the comparison also changed: the tap closure reads the
/// list's selection, and `isMultiSelected`/`selectionCount` are both compared.
extension DashboardTaskRow: Equatable {
    static func == (lhs: DashboardTaskRow, rhs: DashboardTaskRow) -> Bool {
        lhs.task == rhs.task
            && lhs.isKeyboardSelected == rhs.isKeyboardSelected
            && lhs.isMultiSelected == rhs.isMultiSelected
            && lhs.selectionCount == rhs.selectionCount
            && lhs.viewModel === rhs.viewModel
            && lhs.composer === rhs.composer
    }
}
