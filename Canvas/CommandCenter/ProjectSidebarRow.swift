// Canvas/CommandCenter/ProjectSidebarRow.swift
// Single project row in sidebar with progress ring
// March 2026

import SwiftUI

struct ProjectSidebarRow: View {

    let project: Atom
    let isSelected: Bool
    var viewModel: CommandCenterDashboardViewModel

    private var projectMeta: ProjectMetadata? {
        project.metadataValue(as: ProjectMetadata.self)
    }

    private var projectColor: Color {
        if let hex = projectMeta?.color {
            return Color(hex: hex)
        }
        return DS.accent
    }

    var body: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.selectedProjectUUID = project.uuid
                viewModel.selectedAreaUUID = nil
                viewModel.viewMode = .project
                Task {
                    await viewModel.loadProjectTasks(projectUUID: project.uuid)
                }
            }
        } label: {
            HStack(spacing: DS.space8) {
                // Progress ring
                progressRing
                    .frame(width: DS.space16, height: DS.space16)

                // Project name
                Text(project.title ?? "Untitled")
                    .font(isSelected ? DS.headline : DS.callout)
                    .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                    .lineLimit(1)

                Spacer()

                // Task count
                let taskCount = taskCountForProject
                if taskCount > 0 {
                    Text("\(taskCount)")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space4)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: DS.radiusSmall).fill(DS.surfaceElevated)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { uuids, _ in
            for uuid in uuids {
                Task {
                    await viewModel.moveTaskToProject(taskUUID: uuid, projectUUID: project.uuid)
                }
            }
            return true
        }
    }

    // MARK: - Progress Ring

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(projectColor.opacity(0.2), lineWidth: 2)

            Circle()
                .trim(from: 0, to: progressValue)
                .stroke(projectColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private var progressValue: Double {
        // This would ideally be computed from actual task data
        // For now, return 0 until project tasks are loaded
        0.0
    }

    private var taskCountForProject: Int {
        // Approximate count — real count would need a query
        0
    }
}
