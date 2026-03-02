//
//  ScheduledNowCard.swift
//  CosmoOS
//
//  Hero card shown when a task with a time block is scheduled for right now.
//  Displays the task details, time range, and a single "Start Session" action.
//

import SwiftUI

// MARK: - ScheduledNowCard

struct ScheduledNowCard: View {

    // MARK: - Properties

    let task: TaskViewModel
    let scheduledEnd: Date
    let onStartSession: () -> Void

    @State private var isHovering = false
    @State private var isButtonHovering = false
    @State private var pulsePhase = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header badge + time range
            headerSection

            Spacer(minLength: FocusNowTokens.padding)

            // Task content
            taskContentSection

            Spacer(minLength: FocusNowTokens.padding)

            // Start Session button
            startButton
        }
        .padding(FocusNowTokens.padding)
        .frame(minHeight: FocusNowTokens.cardMinHeight)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: FocusNowTokens.cornerRadius, style: .continuous))
        .overlay(cardBorder)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(FocusNowTokens.pressAnimation, value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear { pulsePhase = true }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: PlannerumLayout.spacingSM) {
            // "Scheduled Now" badge with pulsing dot
            HStack(spacing: 6) {
                Circle()
                    .fill(FocusNowTokens.energyExcellent)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulsePhase ? 1.3 : 1.0)
                    .opacity(pulsePhase ? 0.7 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: pulsePhase
                    )

                Text("Scheduled Now")
                    .font(FocusNowTokens.contextFont)
                    .foregroundColor(FocusNowTokens.energyExcellent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(FocusNowTokens.energyExcellent.opacity(0.12))
            .clipShape(Capsule())

            Spacer()

            // Time range
            Text(timeRangeString)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(PlannerumColors.textSecondary)
        }
    }

    // MARK: - Task Content

    private var taskContentSection: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            // Title + intent pill
            HStack(spacing: 10) {
                Text(task.title)
                    .font(FocusNowTokens.titleFont)
                    .foregroundColor(PlannerumColors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if task.intent != .general {
                    intentPill
                }
            }

            // Metadata row: project, duration, XP
            HStack(spacing: 12) {
                if let projectName = task.projectName {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(task.projectColor)
                            .frame(width: 8, height: 8)
                        Text(projectName)
                            .font(FocusNowTokens.projectFont)
                            .foregroundColor(PlannerumColors.textSecondary)
                    }
                }

                if task.estimatedMinutes > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text("\(task.estimatedMinutes)m")
                            .font(FocusNowTokens.projectFont)
                    }
                    .foregroundColor(PlannerumColors.textTertiary)
                }

                Spacer()

                // XP badge
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("+\(task.estimatedXP) XP")
                        .font(FocusNowTokens.xpFont)
                }
                .foregroundColor(PlannerumColors.xpGold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(PlannerumColors.xpGold.opacity(0.15))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Intent Pill

    private var intentPill: some View {
        HStack(spacing: 4) {
            Image(systemName: task.intent.iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(task.intent.displayName)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(task.intent.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(task.intent.color.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button(action: onStartSession) {
            startButtonLabel
        }
        .buttonStyle(.plain)
        .onHover { isButtonHovering = $0 }
        .animation(FocusNowTokens.pressAnimation, value: isButtonHovering)
    }

    @ViewBuilder
    private var startButtonLabel: some View {
        let buttonColor = task.intent != .general ? task.intent.color : FocusNowTokens.primaryButton
        let buttonIcon = task.intent != .general ? task.intent.iconName : "play.fill"

        HStack(spacing: 8) {
            Image(systemName: buttonIcon)
                .font(.system(size: 14, weight: .semibold))
            Text("Start Session")
                .font(FocusNowTokens.buttonFont)
        }
        .foregroundColor(DS.textOnAccent)
        .frame(maxWidth: .infinity)
        .frame(height: FocusNowTokens.buttonHeight)
        .background(
            LinearGradient(
                colors: [buttonColor, buttonColor.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: FocusNowTokens.buttonCornerRadius, style: .continuous))
        .shadow(color: buttonColor.opacity(isButtonHovering ? 0.5 : 0.3), radius: isButtonHovering ? 16 : 8, y: 4)
        .scaleEffect(isButtonHovering ? 1.02 : 1.0)
    }

    // MARK: - Background & Border

    private var cardBackground: some View {
        LinearGradient(
            colors: [FocusNowTokens.gradientStart, FocusNowTokens.gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: FocusNowTokens.cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        isHovering ? FocusNowTokens.energyExcellent.opacity(0.4) : DS.border,
                        isHovering ? DS.border : DS.borderSubtle
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    // MARK: - Helpers

    private var timeRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = task.scheduledStart ?? Date()
        return "\(formatter.string(from: start)) – \(formatter.string(from: scheduledEnd))"
    }
}
