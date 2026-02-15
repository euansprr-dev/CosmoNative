//
//  SessionTimerBar.swift
//  CosmoOS
//
//  Floating timer bar overlay shown at the bottom of the screen
//  during an active deep work session. Displays elapsed/remaining time,
//  live focus score, distraction count, and session controls.
//

import SwiftUI

// MARK: - Session Timer Bar

struct SessionTimerBar: View {

    @ObservedObject var engine: DeepWorkSessionEngine
    @State private var pulsePhase: Double = 0

    // MARK: - Layout

    private enum Layout {
        static let height: CGFloat = 56
        static let horizontalPadding: CGFloat = 20
        static let cornerRadius: CGFloat = 16
        static let bottomInset: CGFloat = 12
        static let maxWidth: CGFloat = 720
    }

    // MARK: - Body

    var body: some View {
        if let session = engine.activeSession {
            VStack {
                Spacer()

                sessionBar(session)
                    .padding(.horizontal, 24)
                    .padding(.bottom, Layout.bottomInset)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(PlannerumSprings.expand, value: engine.activeSession != nil)

            // Extension prompt overlay
            if engine.showExtensionPrompt {
                extensionPromptOverlay
            }
        }
    }

    // MARK: - Session Bar

    private func sessionBar(_ session: ActiveDeepWorkSession) -> some View {
        HStack(spacing: 16) {

            // Pulsing status dot
            statusDot(session)

            // Task title + intent badge + dimension routing
            VStack(alignment: .leading, spacing: 2) {
                Text(session.taskTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PlannerumColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: session.intent.iconName)
                            .font(.system(size: 9, weight: .semibold))
                        Text(session.intent.displayName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(session.intent.color.opacity(0.8))

                    dimensionRoutingLabel(session.intent)
                }
            }

            Spacer()

            // Focus score
            focusScoreBadge

            // Distraction count
            distractionBadge

            // Timer display
            timerDisplay(session)

            // Controls
            controlButtons(session)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(height: Layout.height)
        .frame(maxWidth: Layout.maxWidth)
        .background(barBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }

    // MARK: - Background

    private var barBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .fill(Color(red: 12/255, green: 12/255, blue: 18/255).opacity(0.95))

            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .fill(.ultraThinMaterial)
                .opacity(0.3)
        }
    }

    // MARK: - Status Dot

    private func statusDot(_ session: ActiveDeepWorkSession) -> some View {
        let isRunning = session.state == .running
        let color = isRunning ? SessionTimerTokens.progressFillRunning : SessionTimerTokens.progressFillPaused

        return ZStack {
            if isRunning {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 16, height: 16)
                    .scaleEffect(1.0 + 0.2 * sin(pulsePhase))
                    .onAppear { startPulse() }
            }

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 20, height: 20)
    }

    // MARK: - Focus Score Badge

    private var focusScoreBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(focusScoreColor)
                .frame(width: 6, height: 6)

            Text("\(Int(engine.focusScore))")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(focusScoreColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(focusScoreColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var focusScoreColor: Color {
        let score = engine.focusScore
        if score >= 80 { return Color(red: 34/255, green: 197/255, blue: 94/255) }
        if score >= 60 { return Color(red: 234/255, green: 179/255, blue: 8/255) }
        if score >= 40 { return Color(red: 249/255, green: 115/255, blue: 22/255) }
        return Color(red: 239/255, green: 68/255, blue: 68/255)
    }

    // MARK: - Distraction Badge

    private var distractionBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.slash")
                .font(.system(size: 10, weight: .medium))
            Text("\(engine.distractionCount)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(engine.distractionCount > 0 ? PlannerumColors.overdue.opacity(0.8) : PlannerumColors.textMuted)
    }

    // MARK: - Timer Display

    private func timerDisplay(_ session: ActiveDeepWorkSession) -> some View {
        let remaining = Int(session.remainingSeconds)
        let isOvertime = remaining <= 0

        let displaySeconds = isOvertime ? engine.elapsedSeconds - (session.plannedMinutes * 60) : remaining
        let minutes = abs(displaySeconds) / 60
        let seconds = abs(displaySeconds) % 60
        let prefix = isOvertime ? "+" : ""
        let timeString = String(format: "%@%02d:%02d", prefix, minutes, seconds)

        return Text(timeString)
            .font(.system(size: 20, weight: .bold, design: .monospaced))
            .foregroundColor(isOvertime ? PlannerumColors.xpGold : PlannerumColors.textPrimary)
            .monospacedDigit()
            .frame(minWidth: 80)
    }

    // MARK: - Control Buttons

    private func controlButtons(_ session: ActiveDeepWorkSession) -> some View {
        HStack(spacing: 8) {
            // Pause / Resume
            Button(action: {
                if session.state == .running {
                    engine.pauseSession()
                } else {
                    engine.resumeSession()
                }
            }) {
                pauseResumeLabel(session)
            }
            .buttonStyle(.plain)

            // End session
            Button(action: {
                Task { await engine.endSession() }
            }) {
                endButtonLabel
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func pauseResumeLabel(_ session: ActiveDeepWorkSession) -> some View {
        let isPaused = session.state == .paused
        Image(systemName: isPaused ? "play.fill" : "pause.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isPaused ? SessionTimerTokens.playButton : SessionTimerTokens.pauseButton)
            .frame(width: 32, height: 32)
            .background(
                (isPaused ? SessionTimerTokens.playButton : SessionTimerTokens.pauseButton).opacity(0.15)
            )
            .clipShape(Circle())
    }

    @ViewBuilder
    private var endButtonLabel: some View {
        Image(systemName: "stop.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(SessionTimerTokens.stopButton)
            .frame(width: 32, height: 32)
            .background(SessionTimerTokens.stopButton.opacity(0.15))
            .clipShape(Circle())
    }

    // MARK: - Dimension Routing Label

    @ViewBuilder
    private func dimensionRoutingLabel(_ intent: TaskIntent) -> some View {
        let allocations = DimensionXPRouter.routeXP(intent: intent, baseXP: 1)
        let dims = allocations.map { DimensionXPRouter.dimensionDisplayName($0.dimension) }
        let label = "XP \u{2192} " + dims.joined(separator: " & ")
        let rgb = DimensionXPRouter.dimensionColor(intent.dimension)
        let dimColor = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)

        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(dimColor.opacity(0.7))
    }

    // MARK: - Extension Prompt

    private var extensionPromptOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Text("Time's up!")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(PlannerumColors.textPrimary)

                Text("You've completed your planned session. Keep going?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PlannerumColors.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    extensionButton(label: "+15 min", minutes: 15)
                    extensionButton(label: "+30 min", minutes: 30)
                    endSessionButton
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 18/255, green: 18/255, blue: 26/255).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(PlannerumColors.xpGold.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .padding(.bottom, 80) // Above the timer bar
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(PlannerumSprings.expand, value: engine.showExtensionPrompt)
    }

    private func extensionButton(label: String, minutes: Int) -> some View {
        Button(action: { engine.extendSession(minutes: minutes) }) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PlannerumColors.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(PlannerumColors.primary.opacity(0.15))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(PlannerumColors.primary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var endSessionButton: some View {
        Button(action: {
            Task { await engine.endSession() }
        }) {
            Text("End")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PlannerumColors.nowMarker)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(PlannerumColors.nowMarker.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Animation

    private func startPulse() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            pulsePhase = .pi * 2
        }
    }
}
