// Canvas/CommandCenter/AreaSidebarSection.swift
// Collapsible area with project children in sidebar
// March 2026

import SwiftUI

struct AreaSidebarSection: View {

    let area: Atom
    let projects: [Atom]
    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    @State private var isCollapsed = false

    private var areaMeta: AreaMetadata? {
        area.metadataValue(as: AreaMetadata.self)
    }

    private var areaColor: Color {
        if let hex = areaMeta?.color {
            return Color(hex: hex)
        }
        return DS.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Area header
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 10)

                    Image(systemName: areaMeta?.icon ?? "square.stack.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(areaColor)

                    Text(area.title ?? "Untitled Area")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.text)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Projects within area
            if !isCollapsed {
                ForEach(projects, id: \.uuid) { project in
                    ProjectSidebarRow(
                        project: project,
                        isSelected: viewModel.selectedProjectUUID == project.uuid,
                        viewModel: viewModel
                    )
                    .padding(.leading, 16)
                }
            }
        }
        .onAppear {
            isCollapsed = areaMeta?.isCollapsed ?? false
        }
    }
}
