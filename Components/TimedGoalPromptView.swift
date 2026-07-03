// CosmoOS/Components/TimedGoalPromptView.swift
// Floating top-right prompt shown when the active deep work session crosses a
// task or habit time goal. Driven by DeepWorkSessionEngine.timedGoalPrompt.

import SwiftUI

struct TimedGoalPromptView: View {
    @ObservedObject private var engine = DeepWorkSessionEngine.shared

    var body: some View {
        Group {
            if let prompt = engine.timedGoalPrompt {
                TimedGoalPromptCard(prompt: prompt)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(ProMotionSprings.modal, value: engine.timedGoalPrompt)
    }
}

private struct TimedGoalPromptCard: View {
    let prompt: TimedGoalPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            header
            actions
        }
        .padding(DS.space16)
        .frame(width: 320, alignment: .leading)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.space10) {
            Image(systemName: "timer")
                .font(DS.headline)
                .foregroundStyle(DS.accent)
                .frame(width: 32, height: 32)
                .background(DS.accentSoft, in: .circle)
                .accessibilityLabel("Time goal reached")

            VStack(alignment: .leading, spacing: DS.space2) {
                Text(prompt.kind == .habit ? "Habit goal reached" : "Time's up")
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                Text("\(prompt.title) hit \(prompt.goalMinutes) min")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: DS.space8) {
            TimedGoalPromptButton(title: prompt.kind == .habit ? "Nice, done" : "Mark Complete", isPrimary: true) {
                Task { await DeepWorkSessionEngine.shared.markTimedGoalComplete() }
            }
            .keyboardShortcut(.defaultAction)
            .help(prompt.kind == .habit ? "Wrap up the session (↩)" : "Complete the task and end the session (↩)")

            TimedGoalPromptButton(title: "Keep Going", isPrimary: false) {
                DeepWorkSessionEngine.shared.dismissTimedGoalPrompt()
            }
            .keyboardShortcut(.cancelAction)
            .help("Dismiss and keep tracking (Esc)")
        }
    }
}

private struct TimedGoalPromptButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(isPrimary ? Color.white : DS.text)
                .padding(.horizontal, DS.space12)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(background, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }

    private var background: Color {
        if isPrimary {
            return isHovered ? DS.accent.opacity(0.9) : DS.accent
        }
        return isHovered ? DS.glassCardFill.opacity(0.8) : DS.glassCardFill
    }
}
