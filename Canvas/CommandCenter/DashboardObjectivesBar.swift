// Canvas/CommandCenter/DashboardObjectivesBar.swift
// Compact quarterly objectives progress display
// March 2026

import SwiftUI

struct DashboardObjectivesBar: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State private var animateProgress = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.objectives.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader
                    objectivesList
                }
                .padding(14)
                .dsVellumInset(cornerRadius: 10)
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "target")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.giltMuted)

            Text("Objectives")
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)

            Spacer()

            Text("Q\(currentQuarter)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.gilt)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.giltSoft, in: .rect(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(DS.giltMuted, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Objectives List

    private var objectivesList: some View {
        VStack(spacing: 6) {
            ForEach(Array(viewModel.objectives.prefix(3).enumerated()), id: \.element.id) { index, objective in
                objectiveRow(objective, index: index)
            }
        }
        .onAppear {
            guard !animateProgress else { return }
            if reduceMotion {
                animateProgress = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        animateProgress = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func objectiveRow(_ objective: ObjectiveState, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(objective.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.inkWash)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(objective.progress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(objective.paceStatus.color)
            }

            // Track-and-bead — replaces flat progress bar
            TrackAndBead(
                progress: objective.progress,
                color: objective.paceStatus.color,
                animate: animateProgress
            )
            .animation(
                reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.1),
                value: animateProgress
            )
        }
    }

    // MARK: - Helpers

    private var currentQuarter: Int {
        let month = Calendar.current.component(.month, from: Date())
        return (month - 1) / 3 + 1
    }
}
