// Canvas/CommandCenter/ProjectDetailView.swift
// Project drill-in view with headed sections (Things 3-inspired)
// March 2026

import SwiftUI

struct ProjectDetailView: View {

    let project: Atom
    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State private var isEditingNotes = false
    @State private var editedNotes = ""
    @State private var newHeadingTitle = ""
    @State private var showAddHeading = false

    private var meta: ProjectMetadata? {
        project.metadataValue(as: ProjectMetadata.self)
    }

    private var projectColor: Color {
        if let hex = meta?.color {
            return Color(hex: hex)
        }
        return DS.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            projectHeader

            gradientDivider

            // Content
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    // Project notes
                    if let notes = meta?.projectNotes, !notes.isEmpty {
                        notesSection(notes)
                    }

                    // Headed sections with tasks
                    headedTaskSections

                    // Add heading button
                    addHeadingButton
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Project Header

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Back button
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.selectedProjectUUID = nil
                        viewModel.viewMode = .today
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)

                // Project name
                Text(project.title ?? "Untitled Project")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DS.text)
                    .tracking(-0.3)

                Spacer()

                // Progress
                let progress = taskProgress
                Text("\(progress.completed)/\(progress.total)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)

                // Deadline badge
                if let deadline = meta?.deadline,
                   let date = PlannerumFormatters.iso8601.date(from: deadline) {
                    deadlineBadge(date)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func deadlineBadge(_ date: Date) -> some View {
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        let color: Color = daysUntil < 0 ? .red : daysUntil <= 3 ? .orange : DS.green

        HStack(spacing: 4) {
            Image(systemName: "flag.fill")
                .font(.system(size: 9))
            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Notes

    @ViewBuilder
    private func notesSection(_ notes: String) -> some View {
        Text(notes)
            .font(.system(size: 13))
            .foregroundStyle(DS.textSecondary)
            .lineLimit(3)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    // MARK: - Headed Task Sections

    private var headedTaskSections: some View {
        let sortedHeadings = viewModel.projectHeadings.sorted { $0.sortOrder < $1.sortOrder }
        let tasksWithNoHeading = viewModel.projectTasks.filter { $0.headingUUID == nil && !$0.isCompleted }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(sortedHeadings) { heading in
                let headingTasks = viewModel.projectTasks.filter { $0.headingUUID == heading.id && !$0.isCompleted }
                headingSection(heading: heading, tasks: headingTasks)
            }

            // Unheaded tasks
            if !tasksWithNoHeading.isEmpty || sortedHeadings.isEmpty {
                if !sortedHeadings.isEmpty {
                    sectionHeader("No Heading", count: tasksWithNoHeading.count)
                }

                ForEach(tasksWithNoHeading) { task in
                    compactTaskRow(task)
                }

                SmartTaskCaptureRow(viewModel: viewModel)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func headingSection(heading: ProjectHeading, tasks: [TaskViewModel]) -> some View {
        // Heading row
        HStack(spacing: 8) {
            Image(systemName: heading.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .frame(width: 14)

            Text(heading.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.accent)

            Spacer()

            if heading.isCollapsed {
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }

            // Context menu
            Menu {
                Button("Rename") {
                    // Would trigger inline rename
                }
                Button("Delete Heading", role: .destructive) {
                    Task {
                        await viewModel.deleteHeading(projectUUID: project.uuid, headingUUID: heading.id)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textMuted)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())

        // Tasks within heading (if not collapsed)
        if !heading.isCollapsed {
            ForEach(tasks) { task in
                compactTaskRow(task)
            }
        }
    }

    // MARK: - Compact Task Row

    @ViewBuilder
    private func compactTaskRow(_ task: TaskViewModel) -> some View {
        HStack(spacing: 10) {
            // Checkbox
            Button {
                Task {
                    _ = await viewModel.completeTask(uuid: task.uuid)
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(task.isCompleted ? DS.green : DS.borderSubtle)
            }
            .buttonStyle(.plain)

            // Title
            Text(task.title)
                .font(.system(size: 13))
                .foregroundStyle(task.isCompleted ? DS.textMuted : DS.text)
                .strikethrough(task.isCompleted)
                .lineLimit(1)

            Spacer()

            // Checklist progress
            let progress = task.checklistProgress
            if progress.total > 0 {
                Text("\(progress.completed)/\(progress.total)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(progress.completed == progress.total ? DS.green : DS.textMuted)
            }

            // Deadline
            if let deadline = task.deadline {
                deadlineBadge(deadline)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Add Heading

    private var addHeadingButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showAddHeading {
                HStack(spacing: 8) {
                    TextField("Heading title...", text: $newHeadingTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.accent)
                        .onSubmit {
                            guard !newHeadingTitle.isEmpty else { return }
                            Task {
                                await viewModel.createHeading(projectUUID: project.uuid, title: newHeadingTitle)
                                newHeadingTitle = ""
                                showAddHeading = false
                            }
                        }

                    Button("Cancel") {
                        showAddHeading = false
                        newHeadingTitle = ""
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textMuted)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                Button {
                    showAddHeading = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                        Text("Add Heading")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var taskProgress: (completed: Int, total: Int) {
        let total = viewModel.projectTasks.count
        let completed = viewModel.projectTasks.filter(\.isCompleted).count
        return (completed, total)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textMuted)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var gradientDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [DS.borderSubtle.opacity(0), DS.borderSubtle, DS.borderSubtle.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}
