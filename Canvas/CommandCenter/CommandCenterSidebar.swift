// Canvas/CommandCenter/CommandCenterSidebar.swift
// Things 3-inspired navigation sidebar: Smart Lists + Areas & Projects
// March 2026

import SwiftUI

struct CommandCenterSidebar: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
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
            HStack(spacing: 10) {
                Image(systemName: mode.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor(for: mode))
                    .frame(width: 20)

                Text(mode.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DS.text : DS.textSecondary)

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 8).fill(DS.surfaceElevated)
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
        case .today: return Color(hex: "F59E0B")    // Amber
        case .upcoming: return Color(hex: "EF4444")  // Red
        case .anytime: return Color(hex: "6366F1")   // Indigo
        case .someday: return Color(hex: "8B5CF6")   // Purple
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

            // Add project button
            Button {
                // Will trigger project creation modal
                NotificationCenter.default.post(name: .init("com.cosmo.createProject"), object: nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                    Text("New Project")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
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
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DS.textMuted)
            .tracking(0.8)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
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
