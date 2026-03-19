// Canvas/CommandCenter/TaskChecklistEditor.swift
// Inline checklist editor for task subtasks (Things 3-style)
// March 2026

import SwiftUI

struct TaskChecklistEditor: View {

    @Binding var items: [ChecklistItem]
    var onUpdate: () -> Void

    @State private var newItemTitle = ""
    @FocusState private var isNewItemFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with progress
            if !items.isEmpty {
                HStack {
                    Text("Checklist")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.textSecondary)

                    Spacer()

                    let completed = items.filter(\.isCompleted).count
                    Text("\(completed)/\(items.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(completed == items.count ? DS.green : DS.textMuted)
                }
                .padding(.bottom, 6)
            }

            // Checklist items
            ForEach(items.sorted(by: { $0.sortOrder < $1.sortOrder })) { item in
                checklistItemRow(item)
            }

            // Add new item
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 16)

                TextField("Add item...", text: $newItemTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text)
                    .focused($isNewItemFocused)
                    .onSubmit {
                        addItem()
                    }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func checklistItemRow(_ item: ChecklistItem) -> some View {
        HStack(spacing: 8) {
            // Checkbox
            Button {
                toggleItem(item)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(item.isCompleted ? DS.green : DS.borderSubtle)
            }
            .buttonStyle(.plain)
            .frame(width: 16)

            // Title
            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(item.isCompleted ? DS.textMuted : DS.text)
                .strikethrough(item.isCompleted)
                .lineLimit(1)

            Spacer()

            // Delete button (on hover)
            Button {
                removeItem(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
            .opacity(0.5)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Actions

    private func addItem() {
        guard !newItemTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let newItem = ChecklistItem(
            title: newItemTitle.trimmingCharacters(in: .whitespaces),
            sortOrder: items.count
        )
        items.append(newItem)
        newItemTitle = ""
        isNewItemFocused = true
        onUpdate()
    }

    private func toggleItem(_ item: ChecklistItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isCompleted.toggle()
        onUpdate()
    }

    private func removeItem(_ item: ChecklistItem) {
        items.removeAll { $0.id == item.id }
        onUpdate()
    }
}
