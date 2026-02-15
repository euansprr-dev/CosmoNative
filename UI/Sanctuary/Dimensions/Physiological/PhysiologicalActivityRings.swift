// CosmoOS/UI/Sanctuary/Dimensions/Physiological/PhysiologicalActivityRings.swift
// Activity Rings - Move, Exercise, Stand rings and workout log
// Phase 5: Following SANCTUARY_UI_SPEC_V2.md section 3.3

import SwiftUI

// MARK: - Activity Rings Panel

/// Panel showing daily activity rings
public struct PhysiologicalActivityRings: View {

    // MARK: - Properties

    let rings: ActivityRings
    let stepCount: Int

    @State private var isVisible: Bool = false
    @State private var ringsAnimated: Bool = false

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            Text("Daily Activity Rings")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                // Move ring
                activityRing(
                    title: "Move",
                    value: rings.moveCalories,
                    goal: rings.moveGoal,
                    unit: "cal",
                    progress: rings.moveProgress,
                    color: Color.red
                )

                // Exercise ring
                activityRing(
                    title: "Exercise",
                    value: rings.exerciseMinutes,
                    goal: rings.exerciseGoal,
                    unit: "min",
                    progress: rings.exerciseProgress,
                    color: Color.green
                )

                // Stand ring
                activityRing(
                    title: "Stand",
                    value: rings.standHours,
                    goal: rings.standGoal,
                    unit: "/\(rings.standGoal)",
                    progress: rings.standProgress,
                    color: Color.cyan
                )

                // Steps
                stepsCard
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
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                ringsAnimated = true
            }
        }
    }

    // MARK: - Activity Ring

    private func activityRing(
        title: String,
        value: Int,
        goal: Int,
        unit: String,
        progress: Double,
        color: Color
    ) -> some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            // Ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)

                // Progress ring
                Circle()
                    .trim(from: 0, to: ringsAnimated ? min(1, progress) : 0)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: ringsAnimated)

                // Overflow indicator
                if progress > 1 {
                    Circle()
                        .trim(from: 0, to: ringsAnimated ? min(1, progress - 1) : 0)
                        .stroke(
                            color.opacity(0.5),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.8).delay(0.2), value: ringsAnimated)
                }

                // Percentage
                VStack(spacing: 0) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                }
            }
            .frame(width: 70, height: 70)

            // Label
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                HStack(spacing: 2) {
                    Text("\(value)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }
        }
    }

    // MARK: - Steps Card

    private var stepsCard: some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            // Icon
            Image(systemName: "figure.walk")
                .font(.system(size: 24))
                .foregroundColor(SanctuaryColors.Dimensions.physiological)

            VStack(spacing: 2) {
                Text("Steps")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Text(formatNumber(stepCount))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(SanctuaryColors.Text.primary)

                // Goal indicator
                if stepCount >= 10000 {
                    Text("Goal ✓")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(SanctuaryColors.Semantic.success)
                } else {
                    Text("\(10000 - stepCount) to go")
                        .font(.system(size: 9))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }
        }
        .frame(width: 80)
    }

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Workout Log

/// Weekly workout log
public struct PhysiologicalWorkoutLog: View {

    // MARK: - Properties

    let workouts: [WorkoutSession]
    let weeklyVolumeLoad: Double
    let recoveryDebt: RecoveryDebtLevel

    @State private var isVisible: Bool = false

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            Text("Workout Log (This Week)")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Workout list
            VStack(spacing: SanctuaryLayout.Spacing.sm) {
                ForEach(workouts.prefix(4)) { workout in
                    workoutRow(workout)
                }
            }

            // Summary stats
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                statBlock(label: "Volume Load", value: formatVolume(weeklyVolumeLoad))
                statBlock(label: "Recovery Debt", value: recoveryDebt.displayName, color: Color(hex: recoveryDebt.color))
            }

            // View all button
            Button(action: {}) {
                HStack {
                    Text("View All Workouts")
                        .font(.system(size: 11, weight: .medium))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                }
                .foregroundColor(SanctuaryColors.Dimensions.physiological)
            }
            .buttonStyle(PlainButtonStyle())
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
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                isVisible = true
            }
        }
    }

    // MARK: - Workout Row

    private func workoutRow(_ workout: WorkoutSession) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Day
            Text(workout.formattedDate)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .frame(width: 30)

            // Type icon
            Image(systemName: workout.type.iconName)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: workout.type.color))
                .frame(width: 20)

            // Type name
            Text(workout.type.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)

            Spacer()

            // Duration
            Text(workout.formattedDuration)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.secondary)

            // Intensity
            Text(workout.intensityStars)
                .font(.system(size: 8))
                .foregroundColor(Color(hex: workout.type.color))
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private func statBlock(label: String, value: String, color: Color = SanctuaryColors.Text.primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fK lbs", volume / 1000)
        }
        return "\(Int(volume)) lbs"
    }
}

// MARK: - Workout Detail Card

/// Detailed workout session card
public struct WorkoutDetailCard: View {

    let workout: WorkoutSession
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: workout.type.iconName)
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: workout.type.color))

                    Text(workout.type.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }

                Spacer()

                Button(action: {
                    withAnimation(SanctuarySprings.snappy) {
                        onDismiss()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(SanctuaryLayout.Spacing.lg)
            .background(SanctuaryColors.Glass.highlight)

            // Content
            VStack(spacing: SanctuaryLayout.Spacing.lg) {
                // Date and duration
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Date")
                            .font(.system(size: 9))
                            .foregroundColor(SanctuaryColors.Text.tertiary)

                        Text(formattedDate)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(SanctuaryColors.Text.primary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Duration")
                            .font(.system(size: 9))
                            .foregroundColor(SanctuaryColors.Text.tertiary)

                        Text(workout.formattedDuration)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(SanctuaryColors.Text.primary)
                    }
                }

                // Metrics grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: SanctuaryLayout.Spacing.md
                ) {
                    metricCell(label: "Calories", value: "\(workout.calories)")

                    if let avgHR = workout.heartRateAvg {
                        metricCell(label: "Avg HR", value: "\(avgHR) bpm")
                    }

                    if let maxHR = workout.heartRateMax {
                        metricCell(label: "Max HR", value: "\(maxHR) bpm")
                    }

                    metricCell(label: "Intensity", value: workout.intensityStars)
                }

                // Muscles worked
                if !workout.musclesWorked.isEmpty {
                    VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                        Text("Muscles Worked")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                            .tracking(1)

                        HStack(spacing: SanctuaryLayout.Spacing.sm) {
                            ForEach(workout.musclesWorked, id: \.self) { muscle in
                                Text(muscle.shortName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color(hex: workout.type.color))
                                    .padding(.horizontal, SanctuaryLayout.Spacing.sm)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color(hex: workout.type.color).opacity(0.15))
                                    )
                            }
                        }
                    }
                }

                // Notes
                if let notes = workout.notes {
                    VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                        Text("Notes")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                            .tracking(1)

                        Text(notes)
                            .font(.system(size: 12))
                            .foregroundColor(SanctuaryColors.Text.secondary)
                    }
                }
            }
            .padding(SanctuaryLayout.Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.xl)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.xl)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 30)
        .scaleEffect(isVisible ? 1 : 0.9)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(SanctuarySprings.gentle) {
                isVisible = true
            }
        }
    }

    private func metricCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: workout.date)
    }
}

// MARK: - Compact Activity Summary

/// Compact activity summary for embedding
public struct ActivitySummaryCompact: View {

    let rings: ActivityRings
    let stepCount: Int

    public init(rings: ActivityRings, stepCount: Int) {
        self.rings = rings
        self.stepCount = stepCount
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Mini rings
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                miniRing(progress: rings.moveProgress, color: .red)
                miniRing(progress: rings.exerciseProgress, color: .green)
                miniRing(progress: rings.standProgress, color: .cyan)
            }

            // Stats
            VStack(alignment: .leading, spacing: 2) {
                Text("\(rings.moveCalories) cal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("\(rings.exerciseMinutes)min • \(formatNumber(stepCount)) steps")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Spacer()
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

    private func miniRing(progress: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)

            Circle()
                .trim(from: 0, to: min(1, progress))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24, height: 24)
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000)
        }
        return "\(value)"
    }
}

// MARK: - Preview

#if DEBUG
struct PhysiologicalActivityRings_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    PhysiologicalActivityRings(
                        rings: PhysiologicalDimensionData.preview.dailyRings,
                        stepCount: 8247
                    )

                    PhysiologicalWorkoutLog(
                        workouts: PhysiologicalDimensionData.preview.workouts,
                        weeklyVolumeLoad: 12450,
                        recoveryDebt: .low
                    )

                    ActivitySummaryCompact(
                        rings: PhysiologicalDimensionData.preview.dailyRings,
                        stepCount: 8247
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 700)
    }
}
#endif
