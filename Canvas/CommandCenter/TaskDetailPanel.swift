// Canvas/CommandCenter/TaskDetailPanel.swift
// Right-column task detail editing panel (Things 3-inspired)
// March 2026

import SwiftUI

struct TaskDetailPanel: View {

    let task: TaskViewModel
    var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController
    var onDeleted: (String) -> Void = { _ in }

    @State private var editedTitle: String = ""
    @State private var editedNotes: String = ""
    @State private var editedWhenDate: Date?
    @State private var editedDeadline: Date?
    @State private var editedTimeOfDay: String?
    @State private var editedSchedulingState: String?
    @State private var editedChecklist: [ChecklistItem] = []
    @State private var editedPriority: TaskPriority = .medium
    @State private var editedTimeGoalMinutes: Int? = nil
    @State private var editedIntentUUID: String? = nil
    @State private var editedHabitUUID: String? = nil
    @State private var editedLinkedAtoms: [TaskLinkedAtom] = []
    @State private var editedTitleMentions: [RichMention] = []
    @State private var titleEditScope: RecurringTaskTitleEditScope = .currentOnly

    @State private var recurrenceRule: RecurrenceRule?
    @State private var recurrencePreset: TaskDetailRepeatPreset = .weekly
    @State private var recurrenceDays: Set<DayOfWeek> = []
    @State private var recurrenceHasLoaded = false

    // Schedule-block membership: the blocks occurring on the task's planned
    // day (plus the currently linked block, wherever it lives).
    @State private var editedScheduleBlockUUID: String? = nil
    @State private var availableBlocks: [ScheduleBlockEntry] = []

    @State private var showDeleteConfirmation = false
    @State private var seriesCompletionCount = 0

    // Cross-fade for switching between tasks — the panel stays mounted
    @State private var contentOpacity: Double = 1
    @State private var taskSwitchGeneration = 0

    var body: some View {
        ScrollViewReader { scrollProxy in
            panelScrollView(scrollProxy: scrollProxy)
        }
    }

    private func panelScrollView(scrollProxy: ScrollViewProxy) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DS.space16) {
                Color.clear.frame(height: 0).id("detail-top")

                // Title
                titleSection

                gradientDivider

                // Scheduling
                schedulingSection

                gradientDivider

                // Recurrence
                recurrenceSection

                gradientDivider

                // Priority & Intent
                metadataSection

                gradientDivider

                // Notes
                notesSection

                // Checklist
                if !editedChecklist.isEmpty || true {
                    gradientDivider
                    checklistSection
                }

                // Connected atoms (always visible — interactive picker)
                gradientDivider
                connectedAtomsSection

                Spacer(minLength: 20)

                // Delete
                deleteSection
                deleteSeriesButton
            }
            .padding(DS.space16)
        }
        .scrollIndicators(.hidden)
        .opacity(contentOpacity)
        .onAppear {
            syncStateFromTask()
            Task { await loadRecurrence() }
            Task { await loadAvailableBlocks() }
        }
        .onChange(of: task) { oldTask, newTask in
            // Same-task external updates only — uuid changes cross-fade below
            guard oldTask.uuid == newTask.uuid else { return }
            syncStateFromTask()
        }
        .onChange(of: task.uuid) {
            crossFadeToCurrentTask(scrollProxy: scrollProxy)
        }
    }

    private func crossFadeToCurrentTask(scrollProxy: ScrollViewProxy) {
        taskSwitchGeneration += 1
        let generation = taskSwitchGeneration

        withAnimation(.easeOut(duration: 0.1)) { contentOpacity = 0 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard generation == taskSwitchGeneration else { return }
            syncStateFromTask()
            recurrenceHasLoaded = false
            recurrenceRule = nil
            showDeleteConfirmation = false
            Task { await loadRecurrence() }
            Task { await loadAvailableBlocks() }
            scrollProxy.scrollTo("detail-top", anchor: .top)
            withAnimation(.easeIn(duration: 0.16)) { contentOpacity = 1 }
        }
    }

    private func syncStateFromTask() {
        editedTitle = task.title
        editedNotes = task.body ?? ""
        editedWhenDate = task.whenDate
        editedDeadline = task.deadline
        editedTimeOfDay = task.timeOfDay
        editedSchedulingState = task.schedulingState
        editedChecklist = task.checklist
        editedPriority = task.priority
        editedTimeGoalMinutes = task.timeGoalMinutes
        editedIntentUUID = task.intentUUID
        editedHabitUUID = task.habitUUID
        editedLinkedAtoms = task.linkedAtoms
        editedTitleMentions = task.titleMentions
        editedScheduleBlockUUID = task.scheduleBlockUUID
        titleEditScope = .currentOnly
    }

    // MARK: - Title (with @ mentions)

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TaskTitleMentionField(
                title: $editedTitle,
                mentions: $editedTitleMentions,
                onSubmit: {
                    saveTitle()
                    saveTitleMentions()
                }
            )

            if showsTitleScopeSelector {
                titleScopeSelector
            }
        }
    }

    private var showsTitleScopeSelector: Bool {
        task.recurrenceParentUUID != nil
    }

    private var titleScopeSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent)

                Text(recurrenceRule?.shortDisplayText ?? "Repeats")
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent)

                Spacer()

                Text("Apply to")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            HStack(spacing: 6) {
                titleScopeButton(.currentOnly, label: "\(titleScopeDateLabel) only")
                titleScopeButton(.currentAndFuture, label: "\(titleScopeDateLabel) + future")
            }
        }
        .padding(8)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    private func titleScopeButton(_ scope: RecurringTaskTitleEditScope, label: String) -> some View {
        let isActive = titleEditScope == scope

        return Button {
            titleEditScope = scope
        } label: {
            Text(label)
                .font(DS.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(isActive ? DS.textOnAccent : DS.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(
                    isActive ? DS.accent : DS.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isActive ? Color.clear : DS.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var titleScopeDateLabel: String {
        let date = task.whenDate ?? task.dueDate ?? task.calendarStart ?? Date()
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Scheduling

    private var schedulingSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            // When date
            detailRow(label: "When", icon: "calendar") {
                if let date = editedWhenDate {
                    CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                        .taskDate(task: task, target: .whenDate, currentDate: editedWhenDate, anchor: anchor)
                    } label: {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    }
                    .font(DS.buttonText)
                    .foregroundStyle(DS.accent)

                    Button {
                        editedWhenDate = nil
                        Task { await viewModel.setWhenDate(taskUUID: task.uuid, date: nil) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                } else {
                    CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                        .taskDate(task: task, target: .whenDate, currentDate: editedWhenDate, anchor: anchor)
                    } label: {
                        Text("Set date")
                    }
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.textMuted)
                }
            }

            // Time of day
            if editedWhenDate != nil {
                detailRow(label: "Time", icon: "sun.max") {
                    HStack(spacing: 6) {
                        timeOfDayChip("Morning", value: "morning", icon: "sun.horizon")
                        timeOfDayChip("Evening", value: "evening", icon: "moon.stars")
                    }
                    .fixedSize()
                }
            }

            // Deadline
            detailRow(label: "Deadline", icon: "flag") {
                if let date = editedDeadline {
                    CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                        .taskDate(task: task, target: .deadline, currentDate: editedDeadline, anchor: anchor)
                    } label: {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    }
                    .font(DS.buttonText)
                    .foregroundStyle(DS.orange)

                    Button {
                        editedDeadline = nil
                        Task { await viewModel.setDeadline(taskUUID: task.uuid, date: nil) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                } else {
                    CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                        .taskDate(task: task, target: .deadline, currentDate: editedDeadline, anchor: anchor)
                    } label: {
                        Text("Set deadline")
                    }
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.textMuted)
                }
            }

            // Scheduling state
            detailRow(label: "Schedule", icon: "tray") {
                HStack(spacing: 6) {
                    schedulingChip("Anytime", state: "anytime")
                    schedulingChip("Someday", state: "someday")
                }
            }

            // Schedule block — nest the task inside a block on its planned
            // day. The block owns the time; this never time-boxes the task.
            if !availableBlocks.isEmpty {
                detailRow(label: "Block", icon: "calendar.day.timeline.left") {
                    blockPicker
                }
            }
        }
    }

    /// Menu of the planned day's blocks, each with its palette swatch;
    /// "None" pops the task back out of its block.
    private var blockPicker: some View {
        Menu {
            Button("None") {
                editedScheduleBlockUUID = nil
                Task { await viewModel.setScheduleBlock(taskUUID: task.uuid, blockUUID: nil) }
            }
            Divider()
            ForEach(availableBlocks) { block in
                Button {
                    editedScheduleBlockUUID = block.id
                    Task { await viewModel.setScheduleBlock(taskUUID: task.uuid, blockUUID: block.id) }
                } label: {
                    if editedScheduleBlockUUID == block.id {
                        Label(block.title, systemImage: "checkmark")
                    } else {
                        Text(block.title)
                    }
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let selected = availableBlocks.first(where: { $0.id == editedScheduleBlockUUID }) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(selected.colorHex.map(Color.init(hex:)) ?? DS.accent)
                        .frame(width: 7, height: 7)
                    Text(selected.title)
                        .font(DS.buttonText)
                        .foregroundStyle(DS.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Add to block")
                        .font(DS.cardMeta)
                        .foregroundStyle(DS.textMuted)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help("Nest this task inside a time block — the block keeps its own hours.")
    }

    /// Blocks the task could nest in: those occurring on its planned day
    /// (when ?? deadline ?? today). A link to a block that doesn't occur that
    /// day still shows (prepended) so the picker never lies about state; a
    /// dangling link (block deleted) hides quietly — the repository never
    /// returns tombstones.
    private func loadAvailableBlocks() async {
        let day = task.whenDate ?? task.deadline ?? Date()
        var blocks = await ScheduleBlockEngine.blocks(on: day)
        if let linked = task.scheduleBlockUUID, !blocks.contains(where: { $0.id == linked }) {
            if let atom = try? await AtomRepository.shared.fetch(uuid: linked),
               atom.type == .scheduleBlock,
               let meta = atom.metadataValue(as: ScheduleBlockMetadata.self) {
                blocks.insert(ScheduleBlockEntry(
                    id: atom.uuid,
                    title: atom.title ?? "Untitled",
                    start: meta.startTime.flatMap(ISO8601.date(from:)) ?? day,
                    end: meta.endTime.flatMap(ISO8601.date(from:)) ?? day,
                    isCompleted: meta.isCompleted ?? false,
                    colorHex: meta.color,
                    location: meta.location,
                    isRecurring: meta.recurrence.flatMap(RecurrenceRule.fromJSON) != nil,
                    recurrenceText: nil
                ), at: 0)
            }
        }
        availableBlocks = blocks
    }

    @ViewBuilder
    private func timeOfDayChip(_ label: String, value: String, icon: String) -> some View {
        let isActive = editedTimeOfDay == value

        Button {
            if isActive {
                editedTimeOfDay = nil
                Task { await viewModel.setTimeOfDay(taskUUID: task.uuid, value: nil) }
            } else {
                editedTimeOfDay = value
                Task { await viewModel.setTimeOfDay(taskUUID: task.uuid, value: value) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(DS.caption2)
                Text(label)
                    .font(DS.caption)
            }
            .foregroundStyle(isActive ? DS.accent : DS.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isActive ? DS.accentSoft : DS.surface,
                in: Capsule()
            )
            .overlay(Capsule().stroke(isActive ? DS.accent.opacity(0.3) : DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func schedulingChip(_ label: String, state: String) -> some View {
        let isActive = editedSchedulingState == state

        Button {
            if isActive {
                editedSchedulingState = nil
                Task { await viewModel.setSchedulingState(taskUUID: task.uuid, state: nil) }
            } else {
                editedSchedulingState = state
                Task { await viewModel.setSchedulingState(taskUUID: task.uuid, state: state) }
            }
        } label: {
            Text(label)
                .font(DS.caption)
                .foregroundStyle(isActive ? DS.accent : DS.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isActive ? DS.accentSoft : DS.surface,
                    in: Capsule()
                )
                .overlay(Capsule().stroke(isActive ? DS.accent.opacity(0.3) : DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Priority — full-width segmented buttons
            prioritySection

            // Intent — interactive picker
            intentSection

            // Habit — interactive picker
            habitSection

            // Time goal — completing the goal prompts completion
            timeGoalSection

            // Session tracking
            if task.totalFocusMinutes > 0 {
                detailRow(label: "Tracked", icon: "timer") {
                    Text(trackedSummary)
                        .font(DS.cardMeta)
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
    }

    private var trackedSummary: String {
        if let goal = task.timeGoalMinutes, !task.isRecurring {
            return "\(task.sessionCount) sessions, \(task.totalFocusMinutes) of \(goal)m"
        }
        return "\(task.sessionCount) sessions, \(task.totalFocusMinutes)m"
    }

    // MARK: - Time Goal (timed tasks)

    private static let timeGoalPresets = [15, 25, 30, 45, 60, 90, 120]

    private var timeGoalSection: some View {
        detailRow(label: "Time goal", icon: "timer") {
            Menu {
                Button("None") { saveTimeGoal(nil) }
                Divider()
                ForEach(Self.timeGoalPresets, id: \.self) { minutes in
                    Button("\(minutes) min") { saveTimeGoal(minutes) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(editedTimeGoalMinutes.map { "\($0) min" } ?? "None")
                        .font(DS.caption)
                    Image(systemName: "chevron.down")
                        .font(DS.caption2)
                }
                .foregroundStyle(editedTimeGoalMinutes != nil ? DS.accent : DS.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((editedTimeGoalMinutes != nil ? DS.accent : DS.textMuted).opacity(0.08), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Track this much time to complete the task")
        }
    }

    private func saveTimeGoal(_ minutes: Int?) {
        editedTimeGoalMinutes = minutes
        Task {
            await viewModel.updateTask(uuid: task.uuid, timeGoalMinutes: .some(minutes))
        }
    }

    // MARK: - Priority (full-width)

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                Text("Priority")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }

            HStack(spacing: 6) {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    priorityButton(priority)
                }
            }
        }
    }

    @ViewBuilder
    private func priorityButton(_ priority: TaskPriority) -> some View {
        let isActive = editedPriority == priority

        Button {
            editedPriority = priority
            Task {
                await viewModel.updateTask(uuid: task.uuid, priority: priority)
            }
        } label: {
            Text(priority.displayName)
                .font(DS.caption)
                .foregroundStyle(isActive ? priority.color : DS.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    isActive ? priority.color.opacity(0.12) : DS.surface,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? priority.color.opacity(0.3) : DS.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Intent (interactive picker)

    private var intentSection: some View {
        let intentPresentation = viewModel.resolvedIntentPresentation(intentUUID: editedIntentUUID, legacyIntent: task.intent)
        return detailRow(label: "Intent", icon: "sparkles") {
            CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                .taskIntent(task: task, currentIntentUUID: editedIntentUUID, anchor: anchor)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: intentPresentation.icon)
                        .font(DS.caption2)
                    Text(intentPresentation.title)
                        .font(DS.caption)
                    Image(systemName: "chevron.down")
                        .font(DS.caption2)
                }
                .foregroundStyle(intentPresentation.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(intentPresentation.accent.opacity(0.08), in: Capsule())
            }
        }
    }

    // MARK: - Habit (interactive picker)

    private var habitSection: some View {
        let currentHabit = viewModel.habitDefinition(for: editedHabitUUID)

        return detailRow(label: "Habit", icon: "tag") {
            CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                .taskHabit(task: task, currentHabitUUID: editedHabitUUID, anchor: anchor)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: currentHabit?.icon ?? "slash.circle")
                        .font(DS.caption2)
                    Text(currentHabit?.title ?? "None")
                        .font(DS.caption)
                    Image(systemName: "chevron.down")
                        .font(DS.caption2)
                }
                .foregroundStyle(currentHabit?.accent ?? DS.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((currentHabit?.accent ?? DS.textMuted).opacity(0.08), in: Capsule())
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)

            TextEditor(text: $editedNotes)
                .font(DS.cardMeta)
                .foregroundStyle(DS.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 120)
                .padding(8)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.borderSubtle, lineWidth: 1)
                )
        }
    }

    // MARK: - Checklist

    private var checklistSection: some View {
        TaskChecklistEditor(items: $editedChecklist) {
            saveChecklist()
        }
    }

    // MARK: - Connected Atoms (interactive, max 3)

    private var connectedAtomsSection: some View {
        TaskLinkedAtomPicker(linkedAtoms: $editedLinkedAtoms) {
            saveLinkedAtoms()
        }
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Button(role: .destructive) {
            if task.isOccurrence {
                // Occurrence rows carry the series template's uuid — default delete removes
                // just this occurrence; deleting the series needs explicit confirmation.
                onDeleted(task.uuid)
                Task { _ = await viewModel.cancelOccurrence(task) }
            } else if task.isRecurring && task.recurrenceParentUUID == nil {
                // Series template: removes the current + future occurrences — confirm first.
                Task {
                    seriesCompletionCount = await viewModel.seriesCompletionCount(templateUUID: task.uuid)
                    showDeleteConfirmation = true
                }
            } else {
                let scope: RecurringTaskTitleEditScope = task.isRecurring ? .currentAndFuture : .currentOnly
                onDeleted(task.uuid)
                Task {
                    await viewModel.deleteTask(uuid: task.uuid, recurrenceScope: scope)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(DS.footnote)
                Text(task.isOccurrence ? "Remove This Occurrence" : "Delete Task")
                    .font(DS.buttonText)
            }
            .foregroundStyle(DS.red.opacity(0.8))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Delete \"\(task.title)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete series", role: .destructive) {
                onDeleted(task.uuid)
                Task { await viewModel.deleteTask(uuid: task.uuid) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SeriesDeleteCopy.message(completionCount: seriesCompletionCount))
        }
    }

    /// Occurrence rows get a second, explicit path to delete the whole series.
    @ViewBuilder
    private var deleteSeriesButton: some View {
        if task.isOccurrence {
            Button(role: .destructive) {
                Task {
                    seriesCompletionCount = await viewModel.seriesCompletionCount(templateUUID: task.uuid)
                    showDeleteConfirmation = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash.slash")
                        .font(DS.footnote)
                    Text("Delete Series…")
                        .font(DS.buttonText)
                }
                .foregroundStyle(DS.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func detailRow<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 14)
                Text(label)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            .frame(width: 80, alignment: .leading)

            content()
        }
    }

    private func saveTitle() {
        // Same brain as capture: scheduling tokens typed into the title
        // ("tomorrow", "deadline: friday", "/evening", "every monday", "p1")
        // are stripped out of the text and applied to their detail fields.
        // Habit keywords ("for Ben") stay in the title — the title-save path
        // re-resolves the habit from them downstream.
        let edit = TaskInputParser.parseDetailEdit(editedTitle, mentions: editedTitleMentions)
        let newTitle = edit.title.isEmpty ? task.title : edit.title
        editedTitle = newTitle

        let titleChanged = newTitle != task.title
        guard titleChanged || edit.hasSchedulingChanges else { return }

        // Mirror the field states so the panel reflects the edit immediately.
        if let when = edit.whenDate { editedWhenDate = when }
        if let deadline = edit.deadline { editedDeadline = deadline }
        if let timeOfDay = edit.timeOfDay { editedTimeOfDay = timeOfDay }
        if let state = edit.schedulingState { editedSchedulingState = state }
        if let priority = edit.priority { editedPriority = priority }
        if let rule = edit.recurrenceRule {
            recurrenceRule = rule
            hydrateRecurrenceEditor()
        }

        let scope = titleEditScope
        let occurrenceDay = task.occurrenceDay
        let taskUUID = task.uuid
        Task {
            // Sequential on purpose — each call is a read-modify-write of the
            // same atom; interleaving them could drop a field.
            if titleChanged {
                await viewModel.updateRecurringTaskTitle(
                    uuid: taskUUID,
                    title: newTitle,
                    scope: scope,
                    occurrenceDay: occurrenceDay
                )
            }
            if let when = edit.whenDate {
                await viewModel.setWhenDate(taskUUID: taskUUID, date: when)
            }
            if let deadline = edit.deadline {
                await viewModel.setDeadline(taskUUID: taskUUID, date: deadline)
            }
            if let timeOfDay = edit.timeOfDay {
                await viewModel.setTimeOfDay(taskUUID: taskUUID, value: timeOfDay)
            }
            if let state = edit.schedulingState {
                await viewModel.setSchedulingState(taskUUID: taskUUID, state: state)
            }
            if let priority = edit.priority {
                await viewModel.updateTask(uuid: taskUUID, priority: priority)
            }
            if let rule = edit.recurrenceRule {
                await viewModel.setTaskRecurrence(uuid: taskUUID, rule: rule)
            }
        }
    }

    private func saveChecklist() {
        Task {
            do {
                var applied = false
                _ = try await AtomRepository.shared.update(uuid: task.uuid) { atom in
                    guard var meta = atom.decodedTaskMetadataForDetailWrite(context: "TaskDetailPanel.saveChecklist") else { return }
                    guard let encoded = try? JSONEncoder().encode(editedChecklist) else { return }
                    meta.checklist = String(data: encoded, encoding: .utf8)
                    guard let merged = atom.mergingTaskMetadata(meta, context: "TaskDetailPanel.saveChecklist(\(task.uuid.prefix(8)))") else { return }
                    atom = merged
                    applied = true
                }
                if !applied {
                    PersistenceHealth.note(.writeFailure, context: "TaskDetailPanel.saveChecklist(\(task.uuid.prefix(8)))", detail: "write refused")
                }
            } catch {
                PersistenceHealth.note(.writeFailure, context: "TaskDetailPanel.saveChecklist(\(task.uuid.prefix(8)))", detail: error.localizedDescription)
            }
        }
    }

    private func saveLinkedAtoms() {
        Task {
            do {
                _ = try await AtomRepository.shared.update(uuid: task.uuid) { atom in
                    guard var meta = atom.decodedTaskMetadataForDetailWrite(context: "TaskDetailPanel.saveLinkedAtoms") else { return }
                    guard let encoded = try? JSONEncoder().encode(editedLinkedAtoms) else { return }
                    meta.linkedAtoms = String(data: encoded, encoding: .utf8)
                    guard let merged = atom.mergingTaskMetadata(meta, context: "TaskDetailPanel.saveLinkedAtoms(\(task.uuid.prefix(8)))") else { return }
                    atom = merged
                }
                await viewModel.refreshTasks()
            } catch {
                PersistenceHealth.note(.writeFailure, context: "TaskDetailPanel.saveLinkedAtoms(\(task.uuid.prefix(8)))", detail: error.localizedDescription)
            }
        }
    }

    private func saveTitleMentions() {
        Task {
            do {
                _ = try await AtomRepository.shared.update(uuid: task.uuid) { atom in
                    guard var meta = atom.decodedTaskMetadataForDetailWrite(context: "TaskDetailPanel.saveTitleMentions") else { return }
                    guard let encoded = try? JSONEncoder().encode(editedTitleMentions) else { return }
                    meta.titleMentions = String(data: encoded, encoding: .utf8)
                    guard let merged = atom.mergingTaskMetadata(meta, context: "TaskDetailPanel.saveTitleMentions(\(task.uuid.prefix(8)))") else { return }
                    atom = merged
                }
                await viewModel.refreshTasks()
            } catch {
                PersistenceHealth.note(.writeFailure, context: "TaskDetailPanel.saveTitleMentions(\(task.uuid.prefix(8)))", detail: error.localizedDescription)
            }
        }
    }

    private var gradientDivider: some View {
        Rectangle()
            .fill(DS.borderSubtle.opacity(0.5))
            .frame(height: 1)
    }

    // MARK: - Recurrence

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "repeat")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                Text("Repeat")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                if recurrenceRule != nil || task.isRecurring {
                    Button("Stop") {
                        clearRecurrence()
                    }
                    .font(DS.caption2)
                    .foregroundStyle(DS.red)
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                ForEach(TaskDetailRepeatPreset.allCases, id: \.self) { preset in
                    Button {
                        selectPreset(preset)
                    } label: {
                        Text(preset.label)
                            .font(DS.caption2)
                            .foregroundStyle(isPresetActive(preset) ? DS.textOnAccent : DS.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                isPresetActive(preset) ? DS.accent : DS.surface,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(isPresetActive(preset) ? Color.clear : DS.borderSubtle, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if recurrenceRule != nil && recurrencePreset.requiresDaySelection {
                HStack(spacing: 4) {
                    ForEach(DayOfWeek.allCases, id: \.self) { day in
                        Button {
                            toggleDay(day)
                        } label: {
                            Text(day.shortName)
                                .font(DS.caption2)
                                .foregroundStyle(recurrenceDays.contains(day) ? DS.textOnAccent : DS.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    recurrenceDays.contains(day) ? DS.accent : DS.surface,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func isPresetActive(_ preset: TaskDetailRepeatPreset) -> Bool {
        recurrenceRule != nil && recurrencePreset == preset
    }

    private func loadRecurrence() async {
        let rule = await viewModel.recurrenceRule(for: task)
        await MainActor.run {
            recurrenceRule = rule
            hydrateRecurrenceEditor()
            recurrenceHasLoaded = true
        }
    }

    private func hydrateRecurrenceEditor() {
        guard let rule = recurrenceRule else {
            recurrencePreset = .weekly
            recurrenceDays = defaultDays(for: .weekly)
            return
        }
        switch rule.frequency {
        case .daily: recurrencePreset = .daily
        case .weekdays: recurrencePreset = .weekdays
        case .monthly, .yearly: recurrencePreset = .monthly
        case .weekly, .biweekly: recurrencePreset = .weekly
        case .custom: recurrencePreset = .custom
        }
        if let days = rule.daysOfWeek {
            recurrenceDays = Set(days)
        } else {
            recurrenceDays = defaultDays(for: recurrencePreset)
        }
    }

    private func selectPreset(_ preset: TaskDetailRepeatPreset) {
        recurrencePreset = preset
        if recurrenceDays.isEmpty || !preset.requiresDaySelection {
            recurrenceDays = defaultDays(for: preset)
        }
        applyRecurrence()
    }

    private func toggleDay(_ day: DayOfWeek) {
        if recurrenceDays.contains(day) {
            recurrenceDays.remove(day)
        } else {
            recurrenceDays.insert(day)
        }
        applyRecurrence()
    }

    private func applyRecurrence() {
        let rule = buildRule()
        recurrenceRule = rule
        Task { await viewModel.setTaskRecurrence(uuid: task.uuid, rule: rule) }
    }

    private func clearRecurrence() {
        recurrenceRule = nil
        Task { await viewModel.setTaskRecurrence(uuid: task.uuid, rule: nil) }
    }

    private func defaultDays(for preset: TaskDetailRepeatPreset) -> Set<DayOfWeek> {
        switch preset {
        case .weekdays:
            return Set(DayOfWeek.weekdays)
        case .daily, .monthly, .weekly, .custom:
            let weekday = Calendar.current.component(.weekday, from: task.dueDate ?? Date())
            return Set(DayOfWeek.allCases.filter { $0.rawValue == weekday })
        }
    }

    private func buildRule() -> RecurrenceRule {
        switch recurrencePreset {
        case .daily:
            return .daily()
        case .weekdays:
            return .weekdays()
        case .weekly:
            let days = recurrenceDays.isEmpty ? Array(defaultDays(for: .weekly)) : Array(recurrenceDays)
            return .weekly(on: days.sorted { $0.rawValue < $1.rawValue })
        case .monthly:
            let day = Calendar.current.component(.day, from: task.dueDate ?? Date())
            return .monthly(onDay: day)
        case .custom:
            let days = recurrenceDays.isEmpty ? Array(defaultDays(for: .custom)) : Array(recurrenceDays)
            return RecurrenceRule(
                frequency: .custom,
                interval: 1,
                daysOfWeek: days.sorted { $0.rawValue < $1.rawValue },
                dayOfMonth: nil,
                monthOfYear: nil,
                endCondition: .never
            )
        }
    }
}

// MARK: - Write Guard

private extension Atom {
    /// Decode-state guard for detail-panel writes: absent → fresh metadata, corrupt → nil
    /// (reported via PersistenceHealth). Callers must bail out of the write when this
    /// returns nil so a corrupt column is never overwritten with defaults.
    func decodedTaskMetadataForDetailWrite(context: String) -> TaskMetadata? {
        switch decodedMetadata(as: TaskMetadata.self) {
        case .absent:
            return TaskMetadata()
        case .value(let metadata):
            return metadata
        case .corrupt(let error):
            PersistenceHealth.note(.decodeFailure, context: "\(context)(\(uuid.prefix(8)))", detail: "task metadata undecodable; refusing write (\(error.localizedDescription))")
            return nil
        }
    }
}

private enum TaskDetailRepeatPreset: CaseIterable {
    case daily, weekdays, weekly, monthly, custom

    var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .custom: return "Custom"
        }
    }

    var requiresDaySelection: Bool {
        switch self {
        case .weekly, .custom: return true
        case .daily, .weekdays, .monthly: return false
        }
    }
}
