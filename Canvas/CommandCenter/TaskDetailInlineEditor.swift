// Canvas/CommandCenter/TaskDetailInlineEditor.swift
// Inline task detail editor — expand below task row for full editing
// March 2026

import SwiftUI

struct TaskDetailInlineEditor: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    let task: TaskViewModel
    var onDismiss: () -> Void

    @State private var editTitle: String
    @State private var editPriority: TaskPriority
    @State private var editDueDate: Date?
    @State private var editIntent: TaskIntent
    @State private var editNotes: String
    @State private var showDatePicker: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @FocusState private var titleFocused: Bool

    init(viewModel: CommandCenterDashboardViewModel, task: TaskViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.task = task
        self.onDismiss = onDismiss
        _editTitle = State(initialValue: task.title)
        _editPriority = State(initialValue: task.priority)
        _editDueDate = State(initialValue: task.dueDate)
        _editIntent = State(initialValue: task.intent)
        _editNotes = State(initialValue: task.body ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title
            overlayTextField(
                text: $editTitle,
                placeholder: "Task name",
                textColor: DS.text,
                font: .system(size: 14, weight: .medium)
            )
            .focused($titleFocused)
            .onSubmit { save() }

            // Priority row
            HStack(spacing: 6) {
                Text("Priority")
                    .font(.system(size: 11))
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
                            .font(.system(size: 10))
                        Text(editDueDate.map { dueDateLabel($0) } ?? "No date")
                            .font(.system(size: 11))
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

            HStack {
                Spacer()

                Menu {
                    ForEach(TaskIntent.allCases, id: \.self) { intent in
                        Button {
                            editIntent = intent
                        } label: {
                            Label(intent.displayName, systemImage: intent.iconName)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: editIntent.iconName)
                            .font(.system(size: 10))
                            .foregroundColor(editIntent.color)

                        Text(editIntent.displayName)
                            .font(.system(size: 11, weight: .medium))
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
            }

            // Notes
            overlayTextField(
                text: $editNotes,
                placeholder: "Notes...",
                textColor: DS.textSecondary,
                font: .system(size: 12),
                axis: .vertical
            )
                .lineLimit(2...4)

            // Actions
            HStack {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(DS.red)
                }
                .buttonStyle(.plain)
                .alert("Delete task?", isPresented: $showDeleteConfirm) {
                    Button("Delete", role: .destructive) {
                        Task {
                            await viewModel.deleteTask(uuid: task.uuid)
                            onDismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }

                Spacer()

                Button("Done") {
                    save()
                }
                .font(.system(size: 11, weight: .medium))
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
        .onAppear { titleFocused = true }
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
                .font(.system(size: 11))
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
                .font(.system(size: 11, weight: .medium))
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
            await viewModel.updateTask(
                uuid: task.uuid,
                title: editTitle.isEmpty ? nil : editTitle,
                priority: editPriority != task.priority ? editPriority : nil,
                dueDate: editDueDate,
                intent: editIntent != task.intent ? editIntent : nil,
                body: editNotes.isEmpty ? nil : editNotes
            )
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
