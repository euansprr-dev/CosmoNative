// Canvas/CommandCenter/DashboardObjectivesBar.swift
// Compact quarterly objectives progress display
// March 2026

import SwiftUI

struct DashboardObjectivesBar: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.objectives.isEmpty {
                sectionHeader
                objectivesList
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "target")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.textMuted)

            Text("OBJECTIVES")
                .dsSectionLabel()

            Spacer()

            Text("Q\(currentQuarter)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DS.surface, in: Capsule())
        }
    }

    // MARK: - Objectives List

    private var objectivesList: some View {
        VStack(spacing: 6) {
            ForEach(viewModel.objectives.prefix(3)) { objective in
                objectiveRow(objective)
            }
        }
    }

    @ViewBuilder
    private func objectiveRow(_ objective: ObjectiveState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(objective.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(objective.progress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(objective.paceStatus.color)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.surface)
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(objective.paceStatus.color)
                        .frame(width: geo.size.width * min(objective.progress, 1.0), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Helpers

    private var currentQuarter: Int {
        let month = Calendar.current.component(.month, from: Date())
        return (month - 1) / 3 + 1
    }
}
