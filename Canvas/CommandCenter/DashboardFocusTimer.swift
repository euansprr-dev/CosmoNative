// Canvas/CommandCenter/DashboardFocusTimer.swift
// Inline focus session timer for the Command Center Dashboard
// States: idle, running, paused
// March 2026

import SwiftUI

struct DashboardFocusTimer: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    private var session: ActiveDeepWorkSession? {
        viewModel.sessionEngine.activeSession
    }

    private var isRunning: Bool {
        viewModel.sessionEngine.isTimerRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader

            if let session = session {
                activeSessionView(session)
            } else {
                idleView
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.textMuted)

            Text("FOCUS SESSION")
                .dsSectionLabel()
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(DS.textMuted)

            Text("Select a task and tap play to start")
                .font(.system(size: 12))
                .foregroundColor(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Active Session

    @ViewBuilder
    private func activeSessionView(_ session: ActiveDeepWorkSession) -> some View {
        VStack(spacing: 8) {
            HStack {
                // Task name
                Text(session.taskTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Spacer()

                // Focus score indicator
                focusScoreDot
            }

            HStack(spacing: 12) {
                // Timer display
                Text(formattedTime)
                    .font(.system(size: 24, weight: .light, design: .monospaced))
                    .foregroundColor(DS.text)

                Spacer()

                // Controls
                sessionControls
            }
        }
        .padding(12)
        .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private var focusScoreDot: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(focusScoreColor)
                .frame(width: 8, height: 8)

            Text("\(Int(viewModel.sessionEngine.focusScore))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textSecondary)
        }
    }

    private var focusScoreColor: Color {
        let score = viewModel.sessionEngine.focusScore
        if score >= 80 { return DS.green }
        if score >= 50 { return DS.orange }
        return PlannerumColors.overdue
    }

    private var sessionControls: some View {
        HStack(spacing: 8) {
            if isRunning {
                // Pause button
                Button {
                    viewModel.sessionEngine.pauseSession()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 12))
                        .foregroundColor(DS.text)
                        .frame(width: 32, height: 32)
                        .background(DS.surfaceElevated, in: Circle())
                }
                .buttonStyle(.plain)
            } else if session != nil {
                // Resume button
                Button {
                    viewModel.sessionEngine.resumeSession()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(DS.accent, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Stop button
            Button {
                Task {
                    await viewModel.sessionEngine.endSession()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.overdue)
                    .frame(width: 32, height: 32)
                    .background(PlannerumColors.overdue.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let seconds = viewModel.sessionEngine.elapsedSeconds
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
