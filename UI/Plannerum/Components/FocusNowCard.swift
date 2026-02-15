//
//  FocusNowCard.swift
//  CosmoOS
//
//  Hero card displaying the AI-recommended Focus Now task with
//  energy match indicators, XP preview, and Start Session action.
//

import SwiftUI

// MARK: - FocusNowCard

/// Main Focus Now recommendation card
/// Displays the AI-recommended task based on energy, deadlines, and priorities
public struct FocusNowCard: View {

    // MARK: - Properties

    let recommendation: TaskRecommendation?
    let contextMessage: String
    let currentEnergy: Int
    let currentFocus: Int
    let onStartSession: () -> Void
    let onSkip: () -> Void
    let onTaskTap: (TaskViewModel) -> Void

    @State private var isHovering = false
    @State private var isStartButtonHovering = false
    @State private var isSkipButtonHovering = false
    @State private var isAnimatingOut = false

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with context
            headerSection

            if let recommendation = recommendation {
                // Task content
                taskContentSection(recommendation)

                Spacer(minLength: FocusNowTokens.padding)

                // Action buttons
                actionButtons
            } else {
                // Empty state
                emptyState
            }
        }
        .padding(FocusNowTokens.padding)
        .frame(minHeight: FocusNowTokens.cardMinHeight)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: FocusNowTokens.cornerRadius, style: .continuous))
        .overlay(cardBorder)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(FocusNowTokens.pressAnimation, value: isHovering)
        .onHover { isHovering = $0 }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: PlannerumLayout.spacingSM) {
            // Context badge
            HStack(spacing: 6) {
                Circle()
                    .fill(contextIndicatorColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .fill(contextIndicatorColor)
                            .blur(radius: 4)
                    )

                Text(contextMessage)
                    .font(FocusNowTokens.contextFont)
                    .foregroundColor(PlannerumColors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(FocusNowTokens.contextBackground)
            .clipShape(Capsule())

            Spacer()

            // Energy/Focus indicators
            if recommendation != nil {
                HStack(spacing: 12) {
                    energyIndicator
                    focusIndicator
                }
            }
        }
        .padding(.bottom, FocusNowTokens.padding)
    }

    private var contextIndicatorColor: Color {
        if currentEnergy >= 70 && currentFocus >= 70 {
            return FocusNowTokens.energyExcellent
        } else if currentEnergy >= 40 || currentFocus >= 40 {
            return FocusNowTokens.energyGood
        }
        return FocusNowTokens.energyPoor
    }

    private var energyIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("\(currentEnergy)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(PlannerumHeaderTokens.energyColor(percent: currentEnergy))
    }

    private var focusIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 10, weight: .semibold))
            Text("\(currentFocus)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(PlannerumHeaderTokens.focusColor(percent: currentFocus))
    }

    // MARK: - Task Content Section

    @ViewBuilder
    private func taskTitleRow(_ task: TaskViewModel) -> some View {
        HStack(spacing: 10) {
            Text(task.title)
                .font(FocusNowTokens.titleFont)
                .foregroundColor(PlannerumColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if task.intent != .general {
                intentPill(for: task.intent)
            }
        }
    }

    private func taskContentSection(_ recommendation: TaskRecommendation) -> some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            // Task title + intent pill
            taskTitleRow(recommendation.task)

            // Project & metadata row
            HStack(spacing: 12) {
                // Project tag
                if let projectName = recommendation.task.projectName {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(recommendation.task.projectColor)
                            .frame(width: 8, height: 8)
                        Text(projectName)
                            .font(FocusNowTokens.projectFont)
                            .foregroundColor(PlannerumColors.textSecondary)
                    }
                }

                // Duration
                if recommendation.task.estimatedMinutes > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text("\(recommendation.task.estimatedMinutes)m")
                            .font(FocusNowTokens.projectFont)
                    }
                    .foregroundColor(PlannerumColors.textTertiary)
                }

                // Due indicator
                if let dueInfo = recommendation.task.dueInfo {
                    HStack(spacing: 4) {
                        Image(systemName: recommendation.task.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                            .font(.system(size: 11))
                        Text(dueInfo)
                            .font(FocusNowTokens.projectFont)
                    }
                    .foregroundColor(recommendation.task.isOverdue ? FocusNowTokens.deadlineUrgent : FocusNowTokens.deadlineApproaching)
                }

                Spacer()

                // XP estimate
                xpBadge(for: recommendation.task)
            }

            // Recommendation reason
            HStack(spacing: 6) {
                Image(systemName: reasonIcon(for: recommendation.reason))
                    .font(.system(size: 11, weight: .medium))
                Text(recommendation.reason.displayMessage)
                    .font(FocusNowTokens.reasonFont)
            }
            .foregroundColor(reasonColor(for: recommendation.reason))
            .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTaskTap(recommendation.task)
        }
    }

    private func intentPill(for intent: TaskIntent) -> some View {
        HStack(spacing: 4) {
            Image(systemName: intent.iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(intent.displayName)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(intent.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(intent.color.opacity(0.15))
        .clipShape(Capsule())
    }

    private func xpBadge(for task: TaskViewModel) -> some View {
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

    private func reasonIcon(for reason: RecommendationReason) -> String {
        switch reason {
        case .deadlinePressure: return "clock.badge.exclamationmark"
        case .energyMatch: return "bolt.fill"
        case .focusMatch: return "brain.head.profile"
        case .timeAvailable: return "clock"
        case .streakContinuation: return "flame.fill"
        case .userPrioritized: return "flag.fill"
        case .projectFocus: return "folder.fill"
        }
    }

    private func reasonColor(for reason: RecommendationReason) -> Color {
        switch reason {
        case .deadlinePressure: return FocusNowTokens.deadlineUrgent
        case .energyMatch: return FocusNowTokens.energyExcellent
        case .focusMatch: return PlannerumColors.primary
        case .timeAvailable: return PlannerumColors.textSecondary
        case .streakContinuation: return DailyQuestsTokens.streakFire
        case .userPrioritized: return NowViewTokens.priorityHigh
        case .projectFocus: return PlannerumColors.projectInbox
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Skip button
            Button(action: {
                withAnimation(FocusNowTokens.skipAnimation) {
                    onSkip()
                }
            }) {
                skipButtonLabel
            }
            .buttonStyle(.plain)
            .onHover { isSkipButtonHovering = $0 }

            // Start Session button
            Button(action: onStartSession) {
                startSessionButtonLabel
            }
            .buttonStyle(.plain)
            .onHover { isStartButtonHovering = $0 }
            .animation(FocusNowTokens.pressAnimation, value: isStartButtonHovering)
        }
    }

    @ViewBuilder
    private var skipButtonLabel: some View {
        Text("Skip")
            .font(FocusNowTokens.buttonFont)
            .foregroundColor(PlannerumColors.textSecondary)
            .frame(width: FocusNowTokens.skipButtonWidth, height: FocusNowTokens.buttonHeight)
            .background(isSkipButtonHovering ? Color.white.opacity(0.12) : FocusNowTokens.skipButton)
            .clipShape(RoundedRectangle(cornerRadius: FocusNowTokens.buttonCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var startSessionButtonLabel: some View {
        let intent = recommendation?.task.intent ?? .general
        let buttonColor = intent != .general ? intent.color : FocusNowTokens.primaryButton
        let buttonIcon = intent != .general ? intent.iconName : "play.fill"

        HStack(spacing: 8) {
            Image(systemName: buttonIcon)
                .font(.system(size: 14, weight: .semibold))
            Text(intent != .general ? intent.displayName : "Start Session")
                .font(FocusNowTokens.buttonFont)
        }
        .foregroundColor(.white)
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
        .shadow(color: buttonColor.opacity(isStartButtonHovering ? 0.5 : 0.3), radius: isStartButtonHovering ? 16 : 8, y: 4)
        .scaleEffect(isStartButtonHovering ? 1.02 : 1.0)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(FocusNowTokens.energyExcellent.opacity(0.6))

            Text("All caught up!")
                .font(FocusNowTokens.titleFont)
                .foregroundColor(PlannerumColors.textPrimary)

            Text("Time to capture new ideas or take a break.")
                .font(FocusNowTokens.reasonFont)
                .foregroundColor(PlannerumColors.textTertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
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
                        Color.white.opacity(isHovering ? 0.15 : 0.08),
                        Color.white.opacity(isHovering ? 0.08 : 0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

// MARK: - Preview

#if DEBUG
struct FocusNowCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            PlannerumColors.voidPrimary.ignoresSafeArea()

            VStack(spacing: 24) {
                // With recommendation
                FocusNowCard(
                    recommendation: TaskRecommendation(
                        task: TaskViewModel(
                            uuid: "1",
                            title: "Review quarterly metrics dashboard",
                            projectUuid: "proj1",
                            projectName: "Analytics",
                            projectColor: .blue,
                            dueDate: Calendar.current.date(byAdding: .hour, value: 6, to: Date()),
                            estimatedMinutes: 45,
                            priority: .high,
                            taskType: .deepWork,
                            energyLevel: .high,
                            cognitiveLoad: .deep
                        ),
                        score: 0.85,
                        reason: .deadlinePressure(hoursUntilDue: 6)
                    ),
                    contextMessage: "Peak state - perfect for deep work.",
                    currentEnergy: 78,
                    currentFocus: 82,
                    onStartSession: {},
                    onSkip: {},
                    onTaskTap: { _ in }
                )

                // Empty state
                FocusNowCard(
                    recommendation: nil,
                    contextMessage: "All caught up!",
                    currentEnergy: 65,
                    currentFocus: 70,
                    onStartSession: {},
                    onSkip: {},
                    onTaskTap: { _ in }
                )
            }
            .padding(24)
        }
        .frame(width: 600, height: 700)
    }
}
#endif
