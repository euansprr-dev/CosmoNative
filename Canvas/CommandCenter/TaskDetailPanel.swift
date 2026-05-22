// Canvas/CommandCenter/TaskDetailPanel.swift
// Right-column task detail editing panel (Things 3-inspired)
// March 2026

import SwiftUI

struct TaskDetailPanel: View {

    let task: TaskViewModel
    @ObservedObject var viewModel: CommandCenterDashboardViewModel
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
    @State private var editedIntentUUID: String? = nil
    @State private var editedHabitUUID: String? = nil
    @State private var editedLinkedAtoms: [TaskLinkedAtom] = []
    @State private var editedTitleMentions: [RichMention] = []
    @State private var titleEditScope: RecurringTaskTitleEditScope = .currentOnly

    @State private var recurrenceRule: RecurrenceRule?
    @State private var recurrencePreset: TaskDetailRepeatPreset = .weekly
    @State private var recurrenceDays: Set<DayOfWeek> = []
    @State private var recurrenceHasLoaded = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DS.space16) {
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
            }
            .padding(DS.space16)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            syncStateFromTask()
            Task { await loadRecurrence() }
        }
        .onChange(of: task) {
            syncStateFromTask()
        }
        .onChange(of: task.uuid) {
            syncStateFromTask()
            recurrenceHasLoaded = false
            recurrenceRule = nil
            Task { await loadRecurrence() }
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
        editedIntentUUID = task.intentUUID
        editedHabitUUID = task.habitUUID
        editedLinkedAtoms = task.linkedAtoms
        editedTitleMentions = task.titleMentions
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
        }
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

            // Session tracking
            if task.totalFocusMinutes > 0 {
                detailRow(label: "Tracked", icon: "timer") {
                    Text("\(task.sessionCount) sessions, \(task.totalFocusMinutes)m")
                        .font(DS.cardMeta)
                        .foregroundStyle(DS.textSecondary)
                }
            }
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
            let scope = task.recurrenceParentUUID == nil ? .currentOnly : titleEditScope
            onDeleted(task.uuid)
            Task {
                await viewModel.deleteTask(uuid: task.uuid, recurrenceScope: scope)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(DS.footnote)
                Text("Delete Task")
                    .font(DS.buttonText)
            }
            .foregroundStyle(DS.red.opacity(0.8))
        }
        .buttonStyle(.plain)
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
        guard editedTitle != task.title else { return }
        Task {
            await viewModel.updateRecurringTaskTitle(
                uuid: task.uuid,
                title: editedTitle,
                scope: titleEditScope
            )
        }
    }

    private func saveChecklist() {
        Task {
            do {
                guard var atom = try await AtomRepository.shared.fetch(uuid: task.uuid) else { return }
                var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                let encoded = try JSONEncoder().encode(editedChecklist)
                meta.checklist = String(data: encoded, encoding: .utf8)
                atom = atom.withMetadata(meta)
                try await AtomRepository.shared.update(atom)
            } catch {
                print("❌ TaskDetailPanel: Failed to save checklist: \(error)")
            }
        }
    }

    private func saveLinkedAtoms() {
        Task {
            do {
                guard var atom = try await AtomRepository.shared.fetch(uuid: task.uuid) else { return }
                var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                let encoded = try JSONEncoder().encode(editedLinkedAtoms)
                meta.linkedAtoms = String(data: encoded, encoding: .utf8)
                atom = atom.withMetadata(meta)
                try await AtomRepository.shared.update(atom)
                await viewModel.refreshTasks()
            } catch {
                print("❌ TaskDetailPanel: Failed to save linked atoms: \(error)")
            }
        }
    }

    private func saveTitleMentions() {
        Task {
            do {
                guard var atom = try await AtomRepository.shared.fetch(uuid: task.uuid) else { return }
                var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                let encoded = try JSONEncoder().encode(editedTitleMentions)
                meta.titleMentions = String(data: encoded, encoding: .utf8)
                atom = atom.withMetadata(meta)
                try await AtomRepository.shared.update(atom)
                await viewModel.refreshTasks()
            } catch {
                print("❌ TaskDetailPanel: Failed to save title mentions: \(error)")
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
