// Canvas/CommandCenter/CommandCenterSidebar.swift
// Things 3-inspired navigation sidebar: Smart Lists + Areas & Projects
// March 2026

import SwiftUI

struct CommandCenterSidebar: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State private var showNewProjectForm = false
    @State private var newProjectName = ""
    @State private var newProjectColor = "#8B5CF6"
    @State private var newProjectIsTemporary = false
    @FocusState private var isProjectNameFocused: Bool

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DS.space16) {
                smartListsSection

                gradientDivider

                compactCalendar

                gradientDivider

                areasProjectsSection
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Smart Lists

    private var smartListsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("SMART LISTS")

            ForEach(DashboardViewMode.smartLists, id: \.self) { mode in
                smartListRow(mode)
            }
        }
    }

    @ViewBuilder
    private func smartListRow(_ mode: DashboardViewMode) -> some View {
        let isSelected = viewModel.viewMode == mode && viewModel.selectedProjectUUID == nil
        let count = badgeCount(for: mode)

        Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.selectedProjectUUID = nil
                viewModel.selectedAreaUUID = nil
                viewModel.viewMode = mode
            }
        } label: {
            HStack(spacing: DS.space10) {
                Image(systemName: mode.icon)
                    .font(DS.callout)
                    .foregroundStyle(iconColor(for: mode))
                    .frame(width: DS.space20)

                Text(mode.label)
                    .font(isSelected ? DS.headline : DS.callout)
                    .foregroundStyle(isSelected ? DS.text : DS.textSecondary)

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(DS.footnote)
                        .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: DS.radiusSmall).fill(DS.surfaceElevated)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { uuids, _ in
            handleDrop(uuids: uuids, onto: mode)
            return true
        }
    }

    private func iconColor(for mode: DashboardViewMode) -> Color {
        switch mode {
        case .today: return DS.orange
        case .upcoming: return DS.red
        case .anytime: return DS.entityIdea
        case .someday: return DS.entityIdea
        case .logbook: return DS.green
        default: return DS.textMuted
        }
    }

    private func badgeCount(for mode: DashboardViewMode) -> Int {
        switch mode {
        case .today: return viewModel.todayActiveCount
        case .upcoming: return viewModel.upcomingTotalCount
        case .anytime: return viewModel.anytimeTasks.count
        case .someday: return viewModel.somedayTasks.count
        case .logbook: return viewModel.completedTodayTasks.count
        default: return 0
        }
    }

    // MARK: - Compact Calendar

    private var compactCalendar: some View {
        DashboardMonthCalendar(viewModel: viewModel)
    }

    // MARK: - Areas & Projects

    private var areasProjectsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("AREAS & PROJECTS")

            // Areas with their projects
            ForEach(viewModel.areas, id: \.uuid) { area in
                AreaSidebarSection(
                    area: area,
                    projects: projectsForArea(area.uuid),
                    viewModel: viewModel
                )
            }

            // Projects without an area
            let unassigned = projectsWithoutArea
            if !unassigned.isEmpty {
                ForEach(unassigned, id: \.uuid) { project in
                    ProjectSidebarRow(
                        project: project,
                        isSelected: viewModel.selectedProjectUUID == project.uuid,
                        viewModel: viewModel
                    )
                }
            }

            // Add project button / inline form
            if showNewProjectForm {
                newProjectForm
            } else {
                Button {
                    showNewProjectForm = true
                } label: {
                    HStack(spacing: DS.space6) {
                        Image(systemName: "plus")
                            .font(DS.caption2)
                        Text("New Project")
                            .font(DS.buttonText)
                    }
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, DS.space6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func projectsForArea(_ areaUUID: String) -> [Atom] {
        viewModel.projects.filter { project in
            project.metadataValue(as: ProjectMetadata.self)?.areaUUID == areaUUID
        }
    }

    private var projectsWithoutArea: [Atom] {
        viewModel.projects.filter { project in
            let areaUUID = project.metadataValue(as: ProjectMetadata.self)?.areaUUID
            return areaUUID == nil || areaUUID?.isEmpty == true
        }
    }

    // MARK: - New Project Form

    private let projectColors = [
        "#8B5CF6", "#2D6A4F", "#E07A5F", "#3B82F6",
        "#F59E0B", "#EF4444", "#06B6D4", "#EC4899"
    ]

    private var newProjectForm: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            newProjectNameField
            newProjectColorPicker
            newProjectTypeToggle
            newProjectActions
        }
        .padding(.vertical, DS.space8)
        .background(DS.surfaceElevated.opacity(0.5), in: .rect(cornerRadius: DS.radiusSmall))
        .padding(.horizontal, DS.space6)
        .onAppear { isProjectNameFocused = true }
    }

    private var newProjectNameField: some View {
        HStack(spacing: DS.space8) {
            Circle()
                .fill(Color(hex: newProjectColor))
                .frame(width: 10, height: 10)

            TextField("Project name...", text: $newProjectName)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused($isProjectNameFocused)
                .onSubmit { submitNewProject() }
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
    }

    private var newProjectColorPicker: some View {
        HStack(spacing: DS.space6) {
            ForEach(projectColors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(newProjectColor == hex ? DS.text : Color.clear, lineWidth: 1.5)
                    )
                    .onTapGesture { newProjectColor = hex }
            }
        }
        .padding(.horizontal, DS.space10)
    }

    private var newProjectTypeToggle: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(spacing: DS.space8) {
                projectTypeButton(label: "Permanent", icon: "square.stack.3d.up", isActive: !newProjectIsTemporary) {
                    newProjectIsTemporary = false
                }
                projectTypeButton(label: "Temporary", icon: "checklist", isActive: newProjectIsTemporary) {
                    newProjectIsTemporary = true
                }
            }
            .padding(.horizontal, DS.space10)

            Text(newProjectIsTemporary ? "Task list only — no workspace" : "Creates a Thinkspace workspace")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space10)
        }
    }

    @ViewBuilder
    private func projectTypeButton(label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Image(systemName: icon)
                    .font(DS.caption2)
                Text(label)
                    .font(DS.caption2)
            }
            .foregroundStyle(isActive ? DS.accent : DS.textMuted)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.accent.opacity(0.1))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var newProjectActions: some View {
        HStack(spacing: DS.space8) {
            Button("Cancel") {
                resetNewProjectForm()
            }
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
            .buttonStyle(.plain)

            Spacer()

            Button("Create") {
                submitNewProject()
            }
            .font(DS.caption2)
            .foregroundStyle(DS.accent)
            .buttonStyle(.plain)
            .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, DS.space10)
    }

    private func submitNewProject() {
        let title = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            await viewModel.createProject(
                title: title,
                color: newProjectColor,
                isTemporary: newProjectIsTemporary
            )
            resetNewProjectForm()
        }
    }

    private func resetNewProjectForm() {
        newProjectName = ""
        newProjectColor = "#8B5CF6"
        newProjectIsTemporary = false
        showNewProjectForm = false
    }

    // MARK: - Drag Handling

    private func handleDrop(uuids: [String], onto mode: DashboardViewMode) {
        for uuid in uuids {
            Task {
                switch mode {
                case .today:
                    await viewModel.setWhenDate(taskUUID: uuid, date: Date())
                case .someday:
                    await viewModel.setSchedulingState(taskUUID: uuid, state: "someday")
                case .anytime:
                    await viewModel.setSchedulingState(taskUUID: uuid, state: "anytime")
                default:
                    break
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
            .tracking(0.8)
            .padding(.horizontal, DS.space10)
            .padding(.bottom, DS.space4)
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
