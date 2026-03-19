// Canvas/CommandCenter/TaskDetailPanel.swift
// Right-column task detail editing panel (Things 3-inspired)
// March 2026

import SwiftUI

struct TaskDetailPanel: View {

    let task: TaskViewModel
    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    @State private var editedTitle: String = ""
    @State private var editedNotes: String = ""
    @State private var editedWhenDate: Date?
    @State private var editedDeadline: Date?
    @State private var editedTimeOfDay: String?
    @State private var editedSchedulingState: String?
    @State private var editedChecklist: [ChecklistItem] = []
    @State private var editedPriority: TaskPriority = .medium
    @State private var editedIntent: TaskIntent = .general
    @State private var editedHabitUUID: String? = nil
    @State private var editedLinkedAtoms: [TaskLinkedAtom] = []
    @State private var editedTitleMentions: [RichMention] = []
    @State private var showWhenPicker = false
    @State private var showDeadlinePicker = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                titleSection

                gradientDivider

                // Scheduling
                schedulingSection

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
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            syncStateFromTask()
        }
        .onChange(of: task.uuid) {
            syncStateFromTask()
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
        editedIntent = task.intent
        editedHabitUUID = task.habitUUID
        editedLinkedAtoms = task.linkedAtoms
        editedTitleMentions = task.titleMentions
    }

    // MARK: - Title (with @ mentions)

    private var titleSection: some View {
        TaskTitleMentionField(
            title: $editedTitle,
            mentions: $editedTitleMentions,
            onSubmit: {
                saveTitle()
                saveTitleMentions()
            }
        )
    }

    // MARK: - Scheduling

    private var schedulingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // When date
            detailRow(label: "When", icon: "calendar") {
                if let date = editedWhenDate {
                    Button(date.formatted(.dateTime.month(.abbreviated).day())) {
                        showWhenPicker.toggle()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.accent)
                    .buttonStyle(.plain)

                    Button {
                        editedWhenDate = nil
                        Task { await viewModel.setWhenDate(taskUUID: task.uuid, date: nil) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Set date") {
                        editedWhenDate = Date()
                        showWhenPicker = true
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textMuted)
                    .buttonStyle(.plain)
                }
            }

            // Time of day
            if editedWhenDate != nil {
                detailRow(label: "Time", icon: "sun.max") {
                    HStack(spacing: 6) {
                        timeOfDayChip("Morning", value: "morning", icon: "sun.horizon")
                        timeOfDayChip("Evening", value: "evening", icon: "moon.stars")
                    }
                }
            }

            // Deadline
            detailRow(label: "Deadline", icon: "flag") {
                if let date = editedDeadline {
                    Button(date.formatted(.dateTime.month(.abbreviated).day())) {
                        showDeadlinePicker.toggle()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .buttonStyle(.plain)

                    Button {
                        editedDeadline = nil
                        Task { await viewModel.setDeadline(taskUUID: task.uuid, date: nil) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Set deadline") {
                        editedDeadline = Calendar.current.date(byAdding: .day, value: 7, to: Date())
                        showDeadlinePicker = true
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textMuted)
                    .buttonStyle(.plain)
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
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 11, weight: .medium))
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
                        .font(.system(size: 12))
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
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
                Text("Priority")
                    .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
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
        detailRow(label: "Intent", icon: "sparkles") {
            Menu {
                ForEach([TaskIntent.general, .writeContent, .research, .studySwipes, .deepThink, .review], id: \.rawValue) { intent in
                    Button {
                        editedIntent = intent
                        Task {
                            await viewModel.updateTask(uuid: task.uuid, intent: intent)
                        }
                    } label: {
                        Label(intent.displayName, systemImage: intent.iconName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: editedIntent.iconName)
                        .font(.system(size: 10))
                    Text(editedIntent.displayName)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(editedIntent.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(editedIntent.color.opacity(0.08), in: Capsule())
            }
            .menuStyle(.borderlessButton)
        }
    }

    // MARK: - Habit (interactive picker)

    private var habitSection: some View {
        let currentHabit = viewModel.habitDefinition(for: editedHabitUUID)

        return detailRow(label: "Habit", icon: "tag") {
            Menu {
                Button("None") {
                    editedHabitUUID = nil
                    Task {
                        await viewModel.applyHabit(nil, to: task.uuid)
                    }
                }

                ForEach(viewModel.availableHabitDefinitions, id: \.id) { habit in
                    Button {
                        editedHabitUUID = habit.id
                        Task {
                            await viewModel.applyHabit(habit.id, to: task.uuid)
                        }
                    } label: {
                        Label {
                            Text(habit.title)
                        } icon: {
                            Image(systemName: habit.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: currentHabit?.icon ?? "slash.circle")
                        .font(.system(size: 10))
                    Text(currentHabit?.title ?? "None")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(currentHabit?.accent ?? DS.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((currentHabit?.accent ?? DS.textMuted).opacity(0.08), in: Capsule())
            }
            .menuStyle(.borderlessButton)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.textSecondary)

            TextEditor(text: $editedNotes)
                .font(.system(size: 12))
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
            Task {
                await viewModel.deleteTask(uuid: task.uuid)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                Text("Delete Task")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.red.opacity(0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func detailRow<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
            }
            .frame(width: 80, alignment: .leading)

            content()
        }
    }

    private func saveTitle() {
        guard editedTitle != task.title else { return }
        Task {
            await viewModel.updateTask(uuid: task.uuid, title: editedTitle)
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
}
