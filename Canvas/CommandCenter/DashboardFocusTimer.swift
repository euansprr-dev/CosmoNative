// Canvas/CommandCenter/DashboardFocusTimer.swift
// Inline focus session timer for the Command Center Dashboard
// States: idle, running, paused
// March 2026

import SwiftUI

struct DashboardFocusTimer: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @ObservedObject private var sessionEngine = DeepWorkSessionEngine.shared

    private var session: ActiveDeepWorkSession? {
        sessionEngine.activeSession
    }

    private var isRunning: Bool {
        sessionEngine.isTimerRunning
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
                .font(DS.caption2).fontWeight(.semibold)
                .foregroundColor(DS.textMuted)

            Text("FOCUS SESSION")
                .dsSectionLabel()
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle")
                .font(DS.body).fontWeight(.light)
                .foregroundColor(DS.textMuted)

            Text("Select a task and tap play to start")
                .font(DS.subheadline)
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
                    .font(DS.subheadline).fontWeight(.medium)
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

            Text("\(Int(sessionEngine.focusScore))%")
                .font(DS.caption2).fontWeight(.medium)
                .foregroundColor(DS.textSecondary)
        }
    }

    private var focusScoreColor: Color {
        let score = sessionEngine.focusScore
        if score >= 80 { return DS.green }
        if score >= 50 { return DS.orange }
        return DS.red
    }

    private var sessionControls: some View {
        HStack(spacing: 8) {
            if isRunning {
                // Pause button
                Button {
                    sessionEngine.pauseSession()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(DS.subheadline)
                        .foregroundColor(DS.text)
                        .frame(width: 32, height: 32)
                        .background(DS.surfaceElevated, in: Circle())
                }
                .buttonStyle(.plain)
            } else if session != nil {
                // Resume button
                Button {
                    sessionEngine.resumeSession()
                } label: {
                    Image(systemName: "play.fill")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textOnAccent)
                        .frame(width: 32, height: 32)
                        .background(DS.accent, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Stop button
            Button {
                Task {
                    await sessionEngine.endSession()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(DS.subheadline)
                    .foregroundColor(DS.red)
                    .frame(width: 32, height: 32)
                    .background(DS.red.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let seconds = sessionEngine.elapsedSeconds
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
