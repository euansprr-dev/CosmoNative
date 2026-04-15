// Canvas/CommandCenter/DashboardTimeTracker.swift
// Timery-style time tracking panel: active timer and today's summary
// March 2026

import SwiftUI

struct DashboardTimeTracker: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            if let session = viewModel.sessionEngine.activeSession {
                activeTimerCard(session)
            }

            todayTimeSummary
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.giltMuted)

            Text("Time Tracking")
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)
        }
    }

    @ViewBuilder
    private func activeTimerCard(_ session: ActiveDeepWorkSession) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: session.intent.iconName)
                    .font(.system(size: 10))
                    .foregroundColor(session.intent.color)

                Text(session.taskTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(focusScoreColor)
                        .frame(width: 8, height: 8)

                    Text("\(Int(viewModel.sessionEngine.focusScore))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }
            }

            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(formattedElapsedTime)
                        .font(.system(size: 28, weight: .light, design: .monospaced))
                        .foregroundColor(DS.text)
                }

                Spacer()

                HStack(spacing: 8) {
                    if viewModel.sessionEngine.isTimerRunning {
                        controlButton(icon: "pause.fill", color: DS.text, bg: DS.surfaceElevated) {
                            viewModel.sessionEngine.pauseSession()
                        }
                    } else {
                        controlButton(icon: "play.fill", color: .white, bg: DS.accent) {
                            viewModel.sessionEngine.resumeSession()
                        }
                    }

                    controlButton(icon: "stop.fill", color: DS.red, bg: DS.red.opacity(0.1)) {
                        Task { await viewModel.sessionEngine.endSession() }
                    }
                }
            }
        }
        .padding(12)
        .background(DS.vellum, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.gilt.opacity(0.4), lineWidth: 0.5)
        )
    }

    private func controlButton(icon: String, color: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(bg, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var todayTimeSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formattedTodayTotal)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.inkWash)

                Text("tracked today")
                    .font(.system(size: 12))
                    .foregroundColor(DS.inkFaded)

                Spacer()
            }

            if !viewModel.todaySessionsByIntent.isEmpty {
                intentBreakdownBar
                    .padding(2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(DS.sepiaBorder, lineWidth: 0.5)
                    )
                intentLegend
            }
        }
        .padding(10)
        .background(DS.vellum, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
    }

    private var intentBreakdownBar: some View {
        GeometryReader { geo in
            let total = max(viewModel.todayTrackedMinutes, 1)
            HStack(spacing: 1) {
                ForEach(sortedIntentEntries, id: \.key) { entry in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(entry.key.color)
                        .frame(width: max(CGFloat(entry.value) / CGFloat(total) * geo.size.width - 1, 4))
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var intentLegend: some View {
        HStack(spacing: 8) {
            ForEach(sortedIntentEntries.prefix(4), id: \.key) { entry in
                HStack(spacing: 3) {
                    Circle()
                        .fill(entry.key.color)
                        .frame(width: 6, height: 6)

                    Text(entry.key.displayName)
                        .font(.system(size: 9))
                        .foregroundColor(DS.textMuted)

                    Text("\(entry.value)m")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }
            }
        }
    }

    private var sortedIntentEntries: [(key: TaskIntent, value: Int)] {
        viewModel.todaySessionsByIntent
            .sorted { $0.value > $1.value }
    }

    private var focusScoreColor: Color {
        let score = viewModel.sessionEngine.focusScore
        if score >= 80 { return DS.green }
        if score >= 50 { return DS.orange }
        return DS.red
    }

    private var formattedElapsedTime: String {
        let totalSeconds: Int
        if let session = viewModel.sessionEngine.activeSession {
            totalSeconds = Int(session.elapsedActiveSeconds)
        } else {
            totalSeconds = 0
        }

        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    private var formattedTodayTotal: String {
        let total = viewModel.todayTrackedMinutes
        let hours = total / 60
        let mins = total % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}
