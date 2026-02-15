// CosmoOS/UI/Sanctuary/Dimensions/Behavioral/BehavioralDailyOperations.swift
// Daily Operations - Dopamine delay, walks, screen time, and task tracking
// Phase 6: Following SANCTUARY_UI_SPEC_V2.md section 3.4

import SwiftUI

// MARK: - Daily Operations Panel

/// Panel showing today's behavioral operations
public struct BehavioralDailyOperations: View {

    // MARK: - Properties

    let dopamineDelay: TimeInterval
    let dopamineTarget: TimeInterval
    let walksCompleted: Int
    let walksGoal: Int
    let screenTimeAfter10pm: TimeInterval
    let screenLimit: TimeInterval
    let tasksCompleted: Int
    let tasksTotal: Int

    @State private var isVisible: Bool = false

    // MARK: - Initialization

    public init(
        dopamineDelay: TimeInterval,
        dopamineTarget: TimeInterval,
        walksCompleted: Int,
        walksGoal: Int,
        screenTimeAfter10pm: TimeInterval,
        screenLimit: TimeInterval,
        tasksCompleted: Int,
        tasksTotal: Int
    ) {
        self.dopamineDelay = dopamineDelay
        self.dopamineTarget = dopamineTarget
        self.walksCompleted = walksCompleted
        self.walksGoal = walksGoal
        self.screenTimeAfter10pm = screenTimeAfter10pm
        self.screenLimit = screenLimit
        self.tasksCompleted = tasksCompleted
        self.tasksTotal = tasksTotal
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("Today's Operations")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Operations grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md),
                    GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md)
                ],
                spacing: SanctuaryLayout.Spacing.md
            ) {
                // Dopamine Delay
                DopamineDelayCard(
                    currentDelay: dopamineDelay,
                    targetDelay: dopamineTarget
                )
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 15)
                .animation(.easeOut(duration: 0.3).delay(0.1), value: isVisible)

                // Daily Walks
                DailyWalksCard(
                    completed: walksCompleted,
                    goal: walksGoal
                )
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 15)
                .animation(.easeOut(duration: 0.3).delay(0.15), value: isVisible)

                // Screen Time
                ScreenTimeCard(
                    screenTime: screenTimeAfter10pm,
                    limit: screenLimit
                )
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 15)
                .animation(.easeOut(duration: 0.3).delay(0.2), value: isVisible)

                // Task Zero
                TaskZeroCard(
                    completed: tasksCompleted,
                    total: tasksTotal
                )
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 15)
                .animation(.easeOut(duration: 0.3).delay(0.25), value: isVisible)
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Dopamine Delay Card

/// Card showing morning dopamine delay tracking
public struct DopamineDelayCard: View {

    let currentDelay: TimeInterval
    let targetDelay: TimeInterval

    @State private var isHovered: Bool = false
    @State private var progressAnimated: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundColor(SanctuaryColors.Dimensions.behavioral)

                Text("Dopamine Delay")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                statusBadge
            }

            // Time display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(delayMinutes)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("min")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.secondary)

                Text("/ \(targetMinutes)min")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Progress bar
            progressBar

            // Subtitle
            Text("Time before first dopamine hit")
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(cardBackground)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                progressAnimated = true
            }
        }
    }

    private var statusBadge: some View {
        Text(isOnTarget ? "ON TARGET" : "EXCEEDED")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(isOnTarget ? SanctuaryColors.Semantic.success : SanctuaryColors.XP.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((isOnTarget ? SanctuaryColors.Semantic.success : SanctuaryColors.XP.primary).opacity(0.2))
            )
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(SanctuaryColors.Glass.border)
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(progressColor)
                    .frame(
                        width: progressAnimated ? geometry.size.width * CGFloat(min(1, progress)) : 0,
                        height: 6
                    )

                // Target marker
                Rectangle()
                    .fill(SanctuaryColors.Text.tertiary)
                    .frame(width: 2, height: 10)
                    .position(x: geometry.size.width, y: 3)
            }
        }
        .frame(height: 10)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
            .fill(SanctuaryColors.Glass.highlight)
            .overlay(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                    .stroke(isHovered ? progressColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
    }

    private var delayMinutes: Int { Int(currentDelay / 60) }
    private var targetMinutes: Int { Int(targetDelay / 60) }
    private var progress: Double { currentDelay / targetDelay }
    private var isOnTarget: Bool { currentDelay >= targetDelay }
    private var progressColor: Color {
        isOnTarget ? SanctuaryColors.Semantic.success : SanctuaryColors.Dimensions.behavioral
    }
}

// MARK: - Daily Walks Card

/// Card showing daily walk count
public struct DailyWalksCard: View {

    let completed: Int
    let goal: Int

    @State private var isHovered: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Image(systemName: "figure.walk")
                    .font(.system(size: 14))
                    .foregroundColor(SanctuaryColors.Semantic.success)

                Text("Daily Walks")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()
            }

            // Walk indicators
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                ForEach(0..<goal, id: \.self) { index in
                    walkIndicator(isCompleted: index < completed)
                }
            }

            // Count display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(completed)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("/ \(goal)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                if completed >= goal {
                    Text("Complete")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Semantic.success)
                } else {
                    Text("\(goal - completed) remaining")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? SanctuaryColors.Semantic.success.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func walkIndicator(isCompleted: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isCompleted ? SanctuaryColors.Semantic.success.opacity(0.2) : SanctuaryColors.Glass.border)
                .frame(width: 32, height: 32)

            Image(systemName: "figure.walk")
                .font(.system(size: 14))
                .foregroundColor(isCompleted ? SanctuaryColors.Semantic.success : SanctuaryColors.Text.tertiary)
        }
    }
}

// MARK: - Screen Time Card

/// Card showing screen time after 10pm
public struct ScreenTimeCard: View {

    let screenTime: TimeInterval
    let limit: TimeInterval

    @State private var isHovered: Bool = false
    @State private var progressAnimated: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Image(systemName: isOverLimit ? "iphone.badge.exclamationmark" : "iphone.slash")
                    .font(.system(size: 14))
                    .foregroundColor(isOverLimit ? SanctuaryColors.Semantic.error : SanctuaryColors.Semantic.info)

                Text("SCREEN AFTER 10PM")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                if isOverLimit {
                    violationBadge
                }
            }

            // Time display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(screenMinutes)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(isOverLimit ? SanctuaryColors.Semantic.error : SanctuaryColors.Text.primary)

                Text("min")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.secondary)

                Text("/ \(limitMinutes)min limit")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Progress bar
            progressBar

            // Impact message
            if isOverLimit {
                Text("Screen violation detected - impacts sleep quality")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Semantic.error)
            } else {
                Text("\(limitMinutes - screenMinutes) min remaining")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? statusColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                progressAnimated = true
            }
        }
    }

    private var violationBadge: some View {
        Text("Violation")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(SanctuaryColors.Semantic.error)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(SanctuaryColors.Semantic.error.opacity(0.2))
            )
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(SanctuaryColors.Glass.border)
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(statusColor)
                    .frame(
                        width: progressAnimated ? geometry.size.width * CGFloat(min(1.5, progress)) : 0,
                        height: 6
                    )

                // Limit marker
                Rectangle()
                    .fill(SanctuaryColors.Text.primary)
                    .frame(width: 2, height: 10)
                    .position(x: geometry.size.width, y: 3)
            }
        }
        .frame(height: 10)
    }

    private var screenMinutes: Int { Int(screenTime / 60) }
    private var limitMinutes: Int { Int(limit / 60) }
    private var progress: Double { screenTime / limit }
    private var isOverLimit: Bool { screenTime > limit }
    private var statusColor: Color {
        if isOverLimit { return SanctuaryColors.Semantic.error }
        if progress > 0.8 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.success
    }
}

// MARK: - Task Zero Card

/// Card showing daily task completion
public struct TaskZeroCard: View {

    let completed: Int
    let total: Int

    @State private var isHovered: Bool = false
    @State private var progressAnimated: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Image(systemName: completed >= total ? "checkmark.circle.fill" : "checklist")
                    .font(.system(size: 14))
                    .foregroundColor(completed >= total ? SanctuaryColors.Semantic.success : SanctuaryColors.Dimensions.behavioral)

                Text("Task Zero")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                if completed >= total {
                    Text("Achieved")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(SanctuaryColors.Semantic.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(SanctuaryColors.Semantic.success.opacity(0.2))
                        )
                }
            }

            // Count display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(completed)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("/ \(total)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(statusColor)
            }

            // Progress bar
            progressBar

            // Status message
            if completed >= total {
                Text("All tasks completed - Task Zero achieved!")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Semantic.success)
            } else {
                Text("\(total - completed) tasks remaining")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? statusColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                progressAnimated = true
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(SanctuaryColors.Glass.border)
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(statusColor)
                    .frame(
                        width: progressAnimated ? geometry.size.width * CGFloat(progress) : 0,
                        height: 6
                    )
            }
        }
        .frame(height: 6)
    }

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    private var statusColor: Color {
        if progress >= 1 { return SanctuaryColors.Semantic.success }
        if progress >= 0.75 { return SanctuaryColors.Semantic.info }
        if progress >= 0.5 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Dimensions.behavioral
    }
}

// MARK: - Operations Summary Compact

/// Compact summary of daily operations
public struct OperationsSummaryCompact: View {

    let dopamineDelay: Int
    let walksCompleted: Int
    let walksGoal: Int
    let tasksCompleted: Int
    let tasksTotal: Int
    let hasScreenViolation: Bool

    public init(
        dopamineDelay: Int,
        walksCompleted: Int,
        walksGoal: Int,
        tasksCompleted: Int,
        tasksTotal: Int,
        hasScreenViolation: Bool
    ) {
        self.dopamineDelay = dopamineDelay
        self.walksCompleted = walksCompleted
        self.walksGoal = walksGoal
        self.tasksCompleted = tasksCompleted
        self.tasksTotal = tasksTotal
        self.hasScreenViolation = hasScreenViolation
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Dopamine
            VStack(spacing: 2) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Dimensions.behavioral)

                Text("\(dopamineDelay)m")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(width: 1, height: 30)

            // Walks
            VStack(spacing: 2) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Semantic.success)

                Text("\(walksCompleted)/\(walksGoal)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(width: 1, height: 30)

            // Tasks
            VStack(spacing: 2) {
                Image(systemName: "checklist")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Dimensions.behavioral)

                Text("\(tasksCompleted)/\(tasksTotal)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(width: 1, height: 30)

            // Screen status
            VStack(spacing: 2) {
                Image(systemName: hasScreenViolation ? "iphone.badge.exclamationmark" : "iphone.slash")
                    .font(.system(size: 12))
                    .foregroundColor(hasScreenViolation ? SanctuaryColors.Semantic.error : SanctuaryColors.Semantic.success)

                Text(hasScreenViolation ? "OVER" : "OK")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(hasScreenViolation ? SanctuaryColors.Semantic.error : SanctuaryColors.Semantic.success)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#if DEBUG
struct BehavioralDailyOperations_Previews: PreviewProvider {
    static var previews: some View {
        let data = BehavioralDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    BehavioralDailyOperations(
                        dopamineDelay: data.dopamineDelay,
                        dopamineTarget: data.dopamineTarget,
                        walksCompleted: data.walksCompleted,
                        walksGoal: data.walksGoal,
                        screenTimeAfter10pm: data.screenTimeAfter10pm,
                        screenLimit: data.screenLimit,
                        tasksCompleted: data.tasksCompleted,
                        tasksTotal: data.tasksTotal
                    )

                    OperationsSummaryCompact(
                        dopamineDelay: data.dopamineDelayMinutes,
                        walksCompleted: data.walksCompleted,
                        walksGoal: data.walksGoal,
                        tasksCompleted: data.tasksCompleted,
                        tasksTotal: data.tasksTotal,
                        hasScreenViolation: data.isScreenOverLimit
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
}
#endif
