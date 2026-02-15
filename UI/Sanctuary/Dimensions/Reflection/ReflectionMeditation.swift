// CosmoOS/UI/Sanctuary/Dimensions/Reflection/ReflectionMeditation.swift
// Meditation Tracking - Daily practice, streaks, and session history
// Phase 8: Following SANCTUARY_UI_SPEC_V2.md section 3.6

import SwiftUI

// MARK: - Meditation Panel

/// Main meditation tracking panel
public struct MeditationPanel: View {

    // MARK: - Properties

    let todayMinutes: Int
    let goalMinutes: Int
    let currentStreak: Int
    let totalSessions: Int
    let totalMinutes: Int
    let weeklyData: [DailyMeditation]
    let preferredTime: String

    @State private var isVisible: Bool = false
    @State private var progressAnimated: Bool = false

    // MARK: - Initialization

    public init(
        todayMinutes: Int,
        goalMinutes: Int,
        currentStreak: Int,
        totalSessions: Int,
        totalMinutes: Int,
        weeklyData: [DailyMeditation],
        preferredTime: String
    ) {
        self.todayMinutes = todayMinutes
        self.goalMinutes = goalMinutes
        self.currentStreak = currentStreak
        self.totalSessions = totalSessions
        self.totalMinutes = totalMinutes
        self.weeklyData = weeklyData
        self.preferredTime = preferredTime
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            headerSection

            // Progress ring and stats
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                progressRing
                todayStats
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Weekly overview
            weeklyOverview

            // Lifetime stats
            lifetimeStats
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
            withAnimation(.easeOut(duration: 0.5)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                progressAnimated = true
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meditation")
                    .font(OnyxTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(2)

                Text("Mindfulness Practice")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            Spacer()

            // Streak badge
            if currentStreak > 0 {
                HStack(spacing: 4) {
                    Text("🧘")
                        .font(.system(size: 14))

                    Text("\(currentStreak) day streak")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SanctuaryColors.Dimensions.reflection)
                }
                .padding(.horizontal, SanctuaryLayout.Spacing.md)
                .padding(.vertical, SanctuaryLayout.Spacing.xs)
                .background(
                    Capsule()
                        .fill(SanctuaryColors.Dimensions.reflection.opacity(0.1))
                )
            }
        }
    }

    // MARK: - Progress Ring

    private var progressRing: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(SanctuaryColors.Glass.border, lineWidth: 12)

            // Progress circle
            Circle()
                .trim(from: 0, to: progressAnimated ? min(1.0, CGFloat(todayMinutes) / CGFloat(goalMinutes)) : 0)
                .stroke(
                    LinearGradient(
                        colors: [
                            SanctuaryColors.Dimensions.reflection,
                            SanctuaryColors.Dimensions.reflection.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: 4) {
                Text("\(todayMinutes)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("/ \(goalMinutes) min")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.secondary)

                if todayMinutes >= goalMinutes {
                    Text("✓ Goal Met")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SanctuaryColors.Semantic.success)
                }
            }
        }
        .frame(width: 120, height: 120)
    }

    // MARK: - Today Stats

    private var todayStats: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("Today")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            // Progress percentage
            let progress = min(100, (todayMinutes * 100) / max(1, goalMinutes))
            HStack(spacing: 4) {
                Text("\(progress)%")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(progressColor)

                Text("complete")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            // Remaining
            if todayMinutes < goalMinutes {
                let remaining = goalMinutes - todayMinutes
                Text("\(remaining) min remaining")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Preferred time
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("Best time: \(preferredTime)")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            Spacer()

            // Start button
            Button(action: {}) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))

                    Text("Start Session")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, SanctuaryLayout.Spacing.lg)
                .padding(.vertical, SanctuaryLayout.Spacing.sm)
                .background(
                    Capsule()
                        .fill(SanctuaryColors.Dimensions.reflection)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressColor: Color {
        let progress = Double(todayMinutes) / Double(max(1, goalMinutes))
        if progress >= 1.0 { return SanctuaryColors.Semantic.success }
        if progress >= 0.5 { return SanctuaryColors.Semantic.info }
        if progress >= 0.25 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Text.secondary
    }

    // MARK: - Weekly Overview

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("This Week")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                ForEach(weeklyData) { day in
                    VStack(spacing: 4) {
                        // Status indicator
                        ZStack {
                            Circle()
                                .fill(day.isToday ? SanctuaryColors.Dimensions.reflection.opacity(0.2) : Color.clear)
                                .frame(width: 36, height: 36)

                            if day.completedGoal {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(SanctuaryColors.Semantic.success)
                            } else if day.minutes > 0 {
                                ZStack {
                                    Circle()
                                        .stroke(SanctuaryColors.Glass.border, lineWidth: 2)
                                        .frame(width: 24, height: 24)

                                    Circle()
                                        .trim(from: 0, to: CGFloat(day.minutes) / CGFloat(goalMinutes))
                                        .stroke(SanctuaryColors.Dimensions.reflection, lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                        .rotationEffect(.degrees(-90))
                                }
                            } else {
                                Circle()
                                    .stroke(SanctuaryColors.Glass.border, lineWidth: 2)
                                    .frame(width: 24, height: 24)
                            }
                        }

                        // Day label
                        Text(day.dayLabel)
                            .font(.system(size: 10, weight: day.isToday ? .bold : .regular))
                            .foregroundColor(day.isToday ? SanctuaryColors.Dimensions.reflection : SanctuaryColors.Text.tertiary)

                        // Minutes
                        Text("\(day.minutes)m")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(SanctuaryColors.Text.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    // MARK: - Lifetime Stats

    private var lifetimeStats: some View {
        HStack(spacing: SanctuaryLayout.Spacing.xl) {
            statItem(value: "\(totalSessions)", label: "sessions", icon: "circle.grid.3x3")
            statItem(value: formatMinutes(totalMinutes), label: "total time", icon: "clock")
            statItem(value: "\(currentStreak)", label: "day streak", icon: "flame")
        }
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(SanctuaryColors.Dimensions.reflection)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins > 0 {
                return "\(hours)h \(mins)m"
            }
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - Meditation Timer View

/// Active meditation session timer
public struct MeditationTimerView: View {

    let targetMinutes: Int
    @Binding var elapsedSeconds: Int
    @Binding var isActive: Bool
    let onComplete: () -> Void

    @State private var breathPhase: BreathPhase = .inhale

    private enum BreathPhase {
        case inhale, hold, exhale

        var label: String {
            switch self {
            case .inhale: return "Breathe In"
            case .hold: return "Hold"
            case .exhale: return "Breathe Out"
            }
        }
    }

    public init(
        targetMinutes: Int,
        elapsedSeconds: Binding<Int>,
        isActive: Binding<Bool>,
        onComplete: @escaping () -> Void
    ) {
        self.targetMinutes = targetMinutes
        _elapsedSeconds = elapsedSeconds
        _isActive = isActive
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: SanctuaryLayout.Spacing.xl) {
            // Breathing guide
            breathingGuide

            // Timer display
            timerDisplay

            // Progress bar
            progressBar

            // Controls
            controlButtons
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Dimensions.reflection.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var breathingGuide: some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            // Breathing circle
            ZStack {
                Circle()
                    .fill(SanctuaryColors.Dimensions.reflection.opacity(0.1))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(SanctuaryColors.Dimensions.reflection.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .scaleEffect(breathPhase == .inhale ? 1.3 : (breathPhase == .hold ? 1.3 : 0.8))
                    .animation(.easeInOut(duration: 4), value: breathPhase)

                Circle()
                    .fill(SanctuaryColors.Dimensions.reflection)
                    .frame(width: 20, height: 20)
            }

            Text(breathPhase.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)
        }
    }

    private var timerDisplay: some View {
        VStack(spacing: 4) {
            Text(formatTime(elapsedSeconds))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("/ \(targetMinutes):00")
                .font(.system(size: 14))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(SanctuaryColors.Glass.border)
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 4)
                    .fill(SanctuaryColors.Dimensions.reflection)
                    .frame(
                        width: geometry.size.width * min(1.0, CGFloat(elapsedSeconds) / CGFloat(targetMinutes * 60)),
                        height: 6
                    )
            }
        }
        .frame(height: 6)
    }

    private var controlButtons: some View {
        HStack(spacing: SanctuaryLayout.Spacing.xl) {
            // Cancel
            Button(action: { isActive = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(SanctuaryColors.Glass.highlight)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            // Play/Pause
            Button(action: { isActive.toggle() }) {
                Image(systemName: isActive ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 70, height: 70)
                    .background(
                        Circle()
                            .fill(SanctuaryColors.Dimensions.reflection)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            // Complete
            Button(action: onComplete) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18))
                    .foregroundColor(SanctuaryColors.Semantic.success)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(SanctuaryColors.Semantic.success.opacity(0.2))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Meditation Compact

/// Compact meditation summary
public struct MeditationCompact: View {

    let todayMinutes: Int
    let goalMinutes: Int
    let currentStreak: Int
    let onExpand: () -> Void

    public init(
        todayMinutes: Int,
        goalMinutes: Int,
        currentStreak: Int,
        onExpand: @escaping () -> Void
    ) {
        self.todayMinutes = todayMinutes
        self.goalMinutes = goalMinutes
        self.currentStreak = currentStreak
        self.onExpand = onExpand
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Mini progress ring
            ZStack {
                Circle()
                    .stroke(SanctuaryColors.Glass.border, lineWidth: 4)

                Circle()
                    .trim(from: 0, to: min(1.0, CGFloat(todayMinutes) / CGFloat(goalMinutes)))
                    .stroke(SanctuaryColors.Dimensions.reflection, lineWidth: 4)
                    .rotationEffect(.degrees(-90))

                Text("🧘")
                    .font(.system(size: 16))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Meditation")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Text("\(todayMinutes)/\(goalMinutes) min")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            Spacer()

            if currentStreak > 0 {
                HStack(spacing: 2) {
                    Text("🔥")
                        .font(.system(size: 12))

                    Text("\(currentStreak)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Dimensions.reflection)
                }
            }

            Button(action: onExpand) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Dimensions.reflection)
            }
            .buttonStyle(PlainButtonStyle())
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

// MARK: - Session Card

/// Individual meditation session card
public struct MeditationSessionCard: View {

    let date: Date
    let duration: Int
    let type: String
    let completedGoal: Bool

    public init(date: Date, duration: Int, type: String, completedGoal: Bool) {
        self.date = date
        self.duration = duration
        self.type = type
        self.completedGoal = completedGoal
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Status icon
            Image(systemName: completedGoal ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(completedGoal ? SanctuaryColors.Semantic.success : SanctuaryColors.Text.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(type)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text(formatDate(date))
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Spacer()

            Text("\(duration) min")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Dimensions.reflection)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#if DEBUG
struct ReflectionMeditation_Previews: PreviewProvider {
    static var previews: some View {
        let weeklyData: [DailyMeditation] = [
            DailyMeditation(dayOfWeek: "M", minutes: 15),
            DailyMeditation(dayOfWeek: "T", minutes: 10),
            DailyMeditation(dayOfWeek: "W", minutes: 15),
            DailyMeditation(dayOfWeek: "T", minutes: 0),
            DailyMeditation(dayOfWeek: "F", minutes: 20),
            DailyMeditation(dayOfWeek: "S", minutes: 15),
            DailyMeditation(dayOfWeek: "S", minutes: 8, isToday: true)
        ]

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    MeditationPanel(
                        todayMinutes: 8,
                        goalMinutes: 15,
                        currentStreak: 5,
                        totalSessions: 127,
                        totalMinutes: 1890,
                        weeklyData: weeklyData,
                        preferredTime: "7:00 AM"
                    )

                    MeditationCompact(
                        todayMinutes: 8,
                        goalMinutes: 15,
                        currentStreak: 5,
                        onExpand: {}
                    )

                    MeditationSessionCard(
                        date: Date(),
                        duration: 15,
                        type: "Focused Attention",
                        completedGoal: true
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 900)
    }
}
#endif
