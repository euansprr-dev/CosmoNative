// Canvas/CommandCenter/TaskDetailInlineEditor.swift
// Inline task detail editor — expand below task row for full editing
// March 2026

import SwiftUI

struct TaskDetailInlineEditor: View {

    var viewModel: CommandCenterDashboardViewModel
    let task: TaskViewModel
    var onDismiss: () -> Void

    @State private var editTitle: String
    @State private var editPriority: TaskPriority
    @State private var editDueDate: Date?
    @State private var editIntentUUID: String?
    @State private var editNotes: String
    @State private var selectedHabitUUID: String?
    @State private var availableHabits: [HabitDefinition]
    @State private var showDatePicker: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var seriesCompletionCount = 0
    @FocusState private var titleFocused: Bool
    private let initialResolvedHabitUUID: String?

    init(viewModel: CommandCenterDashboardViewModel, task: TaskViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.task = task
        self.onDismiss = onDismiss
        let resolvedHabitUUID = viewModel.resolvedHabit(for: task)?.id
        _editTitle = State(initialValue: task.title)
        _editPriority = State(initialValue: task.priority)
        // The one date — plannedDate, so legacy split-pin rows show the day
        // the task actually lives on.
        _editDueDate = State(initialValue: task.plannedDate)
        _editIntentUUID = State(initialValue: task.intentUUID)
        _editNotes = State(initialValue: task.body ?? "")
        _selectedHabitUUID = State(initialValue: resolvedHabitUUID)
        _availableHabits = State(initialValue: viewModel.availableHabitDefinitions)
        initialResolvedHabitUUID = resolvedHabitUUID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title
            overlayTextField(
                text: $editTitle,
                placeholder: "Task name",
                textColor: DS.text,
                font: DS.callout.weight(.medium)
            )
            .focused($titleFocused)
            .onSubmit { save() }

            // Priority row
            HStack(spacing: 6) {
                Text("Priority")
                    .font(DS.footnote)
                    .foregroundColor(DS.textMuted)

                ForEach(TaskPriority.allCases, id: \.self) { p in
                    Button {
                        editPriority = p
                    } label: {
                        Circle()
                            .fill(p.color)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: editPriority == p ? 2 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(p.color, lineWidth: editPriority == p ? 1 : 0)
                                    .padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Due date
                Button {
                    showDatePicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(DS.caption2)
                        Text(editDueDate.map { dueDateLabel($0) } ?? "No date")
                            .font(DS.footnote)
                    }
                    .foregroundColor(editDueDate != nil ? DS.accent : DS.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDatePicker) {
                    datePicker
                }
            }

            HStack(spacing: 8) {
                Spacer()
                let intentPresentation = viewModel.resolvedIntentPresentation(intentUUID: editIntentUUID, legacyIntent: task.intent)

                Menu {
                    Button {
                        editIntentUUID = nil
                    } label: {
                        Label("Unassigned", systemImage: "questionmark.circle")
                    }

                    ForEach(viewModel.availableIntentDefinitions, id: \.id) { intent in
                        Button {
                            editIntentUUID = intent.id
                        } label: {
                            Label(intent.title, systemImage: intent.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: intentPresentation.icon)
                            .font(DS.caption2)
                            .foregroundColor(intentPresentation.accent)

                        Text(intentPresentation.title)
                            .font(DS.caption)
                            .foregroundColor(DS.text)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.surfaceElevated, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)

                Menu {
                    Button {
                        selectedHabitUUID = nil
                    } label: {
                        Label("No habit", systemImage: "slash.circle")
                    }

                    ForEach(availableHabits, id: \.id) { habit in
                        Button {
                            selectedHabitUUID = habit.id
                        } label: {
                            Label(habit.title, systemImage: habit.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let selectedHabit = availableHabits.first(where: { $0.id == selectedHabitUUID }) {
                            Image(systemName: selectedHabit.icon)
                                .font(DS.caption2)
                                .foregroundColor(selectedHabit.accent)

                            Text(selectedHabit.title)
                                .font(DS.caption)
                                .foregroundColor(DS.text)
                        } else {
                            Image(systemName: "repeat")
                                .font(DS.caption2)
                                .foregroundColor(DS.textSecondary)

                            Text("No habit")
                                .font(DS.caption)
                                .foregroundColor(DS.text)
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.surfaceElevated, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
            }

            // Notes
            overlayTextField(
                text: $editNotes,
                placeholder: "Notes…",
                textColor: DS.textSecondary,
                font: DS.subheadline,
                axis: .vertical
            )
                .lineLimit(2...4)

            // Actions
            HStack {
                Button(role: .destructive) {
                    if task.isOccurrence {
                        Task {
                            seriesCompletionCount = await viewModel.seriesCompletionCount(templateUUID: task.uuid)
                            showDeleteConfirm = true
                        }
                    } else {
                        showDeleteConfirm = true
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(DS.footnote)
                        .foregroundColor(DS.red)
                }
                .buttonStyle(.plain)
                .confirmationDialog("Delete task?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    if task.isOccurrence {
                        // Occurrence rows carry the series template's uuid — a plain delete
                        // would remove the whole series, not just this day.
                        Button("Remove This Occurrence", role: .destructive) {
                            Task {
                                _ = await viewModel.cancelOccurrence(task)
                                onDismiss()
                            }
                        }
                        Button("Delete series", role: .destructive) {
                            Task {
                                await viewModel.deleteTask(uuid: task.uuid)
                                onDismiss()
                            }
                        }
                    } else {
                        Button("Delete", role: .destructive) {
                            Task {
                                await viewModel.deleteTask(uuid: task.uuid)
                                onDismiss()
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if task.isOccurrence {
                        Text(SeriesDeleteCopy.message(completionCount: seriesCompletionCount))
                    }
                }

                Spacer()

                Button("Done") {
                    save()
                }
                .font(DS.caption)
                .foregroundColor(DS.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .onAppear {
            titleFocused = true
            availableHabits = viewModel.availableHabitDefinitions
        }
        .task {
            await viewModel.loadHabits()
            availableHabits = viewModel.availableHabitDefinitions
        }
        .onExitCommand { onDismiss() }
    }

    // MARK: - Date Picker Popover

    private var datePicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                quickDateButton("Today", date: Date())
                quickDateButton("Tomorrow", date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
                quickDateButton("Next Week", date: Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date())!)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            DatePicker("", selection: Binding(
                get: { editDueDate ?? Date() },
                set: { editDueDate = $0 }
            ), displayedComponents: [.date])
            .datePickerStyle(.graphical)
            .frame(width: 260)

            if editDueDate != nil {
                Button("Clear date") {
                    editDueDate = nil
                    showDatePicker = false
                }
                .font(DS.footnote)
                .foregroundColor(DS.red)
                .padding(.bottom, 8)
            }
        }
    }

    private func quickDateButton(_ label: String, date: Date) -> some View {
        Button {
            editDueDate = date
            showDatePicker = false
        } label: {
            Text(label)
                .font(DS.caption)
                .foregroundColor(DS.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DS.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func dueDateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func save() {
        Task {
            // Only pass a changed due date — occurrence rows carry the series template's
            // uuid, and an unchanged passthrough would re-anchor the whole series.
            let dueDateChanged = editDueDate.map { Calendar.current.startOfDay(for: $0) }
                != task.plannedDate.map { Calendar.current.startOfDay(for: $0) }
            await viewModel.updateTask(
                uuid: task.uuid,
                title: editTitle.isEmpty ? nil : editTitle,
                priority: editPriority != task.priority ? editPriority : nil,
                dueDate: dueDateChanged ? editDueDate : nil,
                intentUUID: editIntentUUID != task.intentUUID ? editIntentUUID : nil,
                body: editNotes.isEmpty ? nil : editNotes
            )
            if selectedHabitUUID != initialResolvedHabitUUID {
                await viewModel.applyHabit(selectedHabitUUID, to: task.uuid)
            }
            onDismiss()
        }
    }

    private func overlayTextField(
        text: Binding<String>,
        placeholder: String,
        textColor: Color,
        font: Font,
        axis: Axis = .horizontal
    ) -> some View {
        let placeholderAlignment: Alignment = axis == .vertical ? .topLeading : .leading

        return ZStack(alignment: placeholderAlignment) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundColor(DS.text.opacity(0.45))
                    .allowsHitTesting(false)
            }

            TextField("", text: text, axis: axis)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundColor(textColor)
        }
    }
}
