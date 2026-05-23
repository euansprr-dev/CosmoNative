// Canvas/CommandCenter/DashboardTimeTracker.swift
// Compact macOS command strip for time tracking
// March 2026

import SwiftUI

struct DashboardTimeTracker: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @ObservedObject private var sessionEngine = DeepWorkSessionEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            compactCommandStrip

            if let session = sessionEngine.activeSession {
                activeTimerCard(session)
            }
        }
    }

    private var compactCommandStrip: some View {
        HStack(spacing: DS.space12) {
            HStack(spacing: DS.space8) {
                Image(systemName: "timer")
                    .font(DS.caption)
                    .foregroundStyle(DS.commandCenterOrnamentText)

                Text("Time Tracking")
                    .font(DS.smallCaps)
                    .foregroundStyle(DS.commandCenterOrnamentText)

                Text(formattedTodayTotal)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.text)

                Text("today")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }

            if !viewModel.todayIntentSummaries.isEmpty {
                intentBreakdownBar
                    .frame(width: 140)
            }

            Spacer(minLength: DS.space16)

            primaryAction
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
        .background(DS.commandChromePanelFill, in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.commandChromeBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var primaryAction: some View {
        if sessionEngine.activeSession != nil {
            if sessionEngine.isTimerRunning {
                commandButton(title: "Pause", icon: "pause.fill", isProminent: false) {
                    sessionEngine.pauseSession()
                }
            } else {
                commandButton(title: "Resume", icon: "play.fill", isProminent: true) {
                    sessionEngine.resumeSession()
                }
            }
        } else {
            commandButton(
                title: focusCandidate == nil ? "Select a task" : "Start focus",
                icon: "play.fill",
                isProminent: focusCandidate != nil
            ) {
                guard let task = focusCandidate else { return }
                viewModel.startFocusSession(for: task)
            }
            .disabled(focusCandidate == nil)
            .opacity(focusCandidate == nil ? 0.55 : 1)
        }
    }

    @ViewBuilder
    private func activeTimerCard(_ session: ActiveDeepWorkSession) -> some View {
        let intentPresentation = viewModel.resolvedIntentPresentation(
            intentUUID: session.intentUUID,
            legacyIntentRaw: session.intent.rawValue
        )

        VStack(alignment: .leading, spacing: DS.space10) {
            HStack(spacing: DS.space8) {
                Image(systemName: intentPresentation.icon)
                    .font(DS.caption)
                    .foregroundStyle(intentPresentation.accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.taskTitle)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    HStack(spacing: DS.space6) {
                        Text(intentPresentation.title)
                            .font(DS.caption2)
                            .foregroundStyle(intentPresentation.accent)

                        if let habitTitle = session.habitTitleSnapshot {
                            Text(habitTitle)
                                .font(DS.caption2)
                                .foregroundStyle(DS.textMuted)
                        }
                    }
                }

                Spacer()

                HStack(spacing: DS.space6) {
                    Circle()
                        .fill(focusScoreColor)
                        .frame(width: 6, height: 6)

                    Text("\(Int(sessionEngine.focusScore))%")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
            }

            HStack(spacing: DS.space12) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(formattedElapsedTime)
                        .font(.system(size: 24, weight: .light, design: .monospaced))
                        .foregroundStyle(DS.text)
                }

                Spacer()

                HStack(spacing: DS.space8) {
                    if sessionEngine.isTimerRunning {
                        iconControlButton(icon: "pause.fill", color: DS.text, bg: DS.commandChromeControlFill) {
                            sessionEngine.pauseSession()
                        }
                    } else {
                        iconControlButton(icon: "play.fill", color: DS.textOnAccent, bg: DS.accent) {
                            sessionEngine.resumeSession()
                        }
                    }

                    iconControlButton(icon: "stop.fill", color: DS.red, bg: DS.redSoft.opacity(0.7)) {
                        Task { await sessionEngine.endSession() }
                    }
                }
            }
        }
        .padding(DS.space12)
        .background(DS.commandChromeProminentFill, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.commandChromeProminentBorder, lineWidth: 0.5)
        )
    }

    private func commandButton(title: String, icon: String, isProminent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space6) {
                Image(systemName: icon)
                    .font(DS.caption2)
                Text(title)
                    .font(DS.caption)
            }
            .foregroundStyle(isProminent ? DS.textOnAccent : DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(isProminent ? DS.accent : DS.commandChromeControlFill, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isProminent ? DS.accent.opacity(0.25) : DS.commandChromeControlBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconControlButton(icon: String, color: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.caption)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(bg, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var intentBreakdownBar: some View {
        GeometryReader { geo in
            let total = max(viewModel.todayTrackedMinutes, 1)
            HStack(spacing: 1) {
                ForEach(sortedIntentEntries, id: \.key.id) { entry in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(entry.key.accent.opacity(0.75))
                        .frame(width: max(CGFloat(entry.value) / CGFloat(total) * geo.size.width - 1, 3))
                }
            }
        }
        .frame(height: 5)
        .clipShape(.rect(cornerRadius: 2.5))
    }

    private var sortedIntentEntries: [(key: IntentSummary, value: Int)] {
        viewModel.todayIntentSummaries
            .map { (key: $0, value: $0.minutes) }
            .sorted { $0.value > $1.value }
    }

    private var focusCandidate: TaskViewModel? {
        if let index = viewModel.selectedTaskIndex,
           viewModel.currentVisibleTasks.indices.contains(index) {
            let selected = viewModel.currentVisibleTasks[index]
            if !selected.isCompleted {
                return selected
            }
        }

        return viewModel.currentVisibleTasks.first { !$0.isCompleted }
    }

    private var focusScoreColor: Color {
        let score = sessionEngine.focusScore
        if score >= 80 { return DS.green }
        if score >= 50 { return DS.orange }
        return DS.red
    }

    private var formattedElapsedTime: String {
        let totalSeconds: Int
        if let session = sessionEngine.activeSession {
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
