// CosmoOS/UI/Sanctuary/Dimensions/Behavioral/BehavioralRoutineConsistency.swift
// Routine Consistency - Routine tracking with weekly dots and time variance
// Phase 6: Following SANCTUARY_UI_SPEC_V2.md section 3.4

import SwiftUI

// MARK: - Routine Consistency Panel

/// Panel showing routine tracking with weekly consistency dots
public struct BehavioralRoutineConsistency: View {

    // MARK: - Properties

    let routines: [RoutineTracker]

    @State private var isVisible: Bool = false
    @State private var selectedRoutine: RoutineTracker?

    // MARK: - Initialization

    public init(routines: [RoutineTracker]) {
        self.routines = routines
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("ROUTINE CONSISTENCY")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Routine cards
            VStack(spacing: SanctuaryLayout.Spacing.md) {
                ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                    RoutineConsistencyCard(
                        routine: routine,
                        isSelected: selectedRoutine?.id == routine.id,
                        onTap: {
                            withAnimation(SanctuarySprings.snappy) {
                                if selectedRoutine?.id == routine.id {
                                    selectedRoutine = nil
                                } else {
                                    selectedRoutine = routine
                                }
                            }
                        }
                    )
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 15)
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.1 + 0.1), value: isVisible)
                }
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

// MARK: - Routine Consistency Card

/// Individual routine card with weekly dots
public struct RoutineConsistencyCard: View {

    let routine: RoutineTracker
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header row
            HStack {
                // Routine name and target
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .tracking(1)

                    HStack(spacing: SanctuaryLayout.Spacing.sm) {
                        Text("Target: \(routine.formattedTarget)")
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Text.secondary)

                        Text(routine.toleranceString)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                }

                Spacer()

                // Consistency percentage
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(routine.consistency))%")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(consistencyColor)

                    Text("consistency")
                        .font(.system(size: 9))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            // Weekly dots row
            weeklyDotsRow

            // Expanded details
            if isSelected {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(
                            isSelected ? consistencyColor.opacity(0.5) : (isHovered ? SanctuaryColors.Glass.border : Color.clear),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(perform: onTap)
    }

    // MARK: - Weekly Dots Row

    private var weeklyDotsRow: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            ForEach(routine.weekData) { dayData in
                VStack(spacing: 4) {
                    // Day label
                    Text(dayData.dayLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    // Status dot
                    ZStack {
                        Circle()
                            .fill(dayData.status.color.opacity(0.2))
                            .frame(width: 24, height: 24)

                        Image(systemName: dayData.status.iconName)
                            .font(.system(size: 12))
                            .foregroundColor(dayData.status.color)
                    }

                    // Time (if available)
                    Text(dayData.formattedTime)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Expanded Details

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            HStack {
                // Average time
                VStack(alignment: .leading, spacing: 2) {
                    Text("Average")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(routine.formattedAverage)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }

                Spacer()

                // Trend
                VStack(alignment: .center, spacing: 2) {
                    Text("Trend")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(routine.trend.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(trendColor)
                }

                Spacer()

                // Variance
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Variance")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(routine.toleranceString)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
            }
        }
        .padding(.top, SanctuaryLayout.Spacing.sm)
    }

    // MARK: - Colors

    private var consistencyColor: Color {
        if routine.consistency >= 80 { return SanctuaryColors.Semantic.success }
        if routine.consistency >= 60 { return SanctuaryColors.Semantic.info }
        if routine.consistency >= 40 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }

    private var trendColor: Color {
        switch routine.trend {
        case .improving: return SanctuaryColors.Semantic.success
        case .stable: return SanctuaryColors.Text.secondary
        case .declining: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - Routine Mini Row

/// Compact routine display for embedding
public struct RoutineMiniRow: View {

    let routine: RoutineTracker

    public init(routine: RoutineTracker) {
        self.routine = routine
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Name
            Text(routine.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)

            Spacer()

            // Mini dots (last 7 days)
            HStack(spacing: 4) {
                ForEach(routine.weekData.suffix(7)) { dayData in
                    Circle()
                        .fill(dayData.status.color)
                        .frame(width: 6, height: 6)
                }
            }

            // Consistency
            Text("\(Int(routine.consistency))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(consistencyColor)
        }
        .padding(.horizontal, SanctuaryLayout.Spacing.sm)
        .padding(.vertical, SanctuaryLayout.Spacing.xs)
    }

    private var consistencyColor: Color {
        if routine.consistency >= 80 { return SanctuaryColors.Semantic.success }
        if routine.consistency >= 60 { return SanctuaryColors.Semantic.info }
        if routine.consistency >= 40 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }
}

// MARK: - Weekly Consistency Dots

/// Standalone weekly consistency dots component
public struct WeeklyConsistencyDots: View {

    let weekData: [DayRoutineData]
    let showLabels: Bool

    public init(weekData: [DayRoutineData], showLabels: Bool = true) {
        self.weekData = weekData
        self.showLabels = showLabels
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.sm) {
            ForEach(weekData) { dayData in
                VStack(spacing: 2) {
                    if showLabels {
                        Text(dayData.dayLabel)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }

                    Image(systemName: dayData.status.iconName)
                        .font(.system(size: showLabels ? 12 : 8))
                        .foregroundColor(dayData.status.color)
                }
            }
        }
    }
}

// MARK: - Routine Time Variance Chart

/// Chart showing time variance for a routine
public struct RoutineTimeVarianceChart: View {

    let routine: RoutineTracker

    @State private var isVisible: Bool = false

    public init(routine: RoutineTracker) {
        self.routine = routine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Text(routine.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Spacer()

                Text("Target: \(routine.formattedTarget)")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            // Variance chart
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let midY = height / 2

                ZStack {
                    // Target line (center)
                    Rectangle()
                        .fill(SanctuaryColors.Dimensions.behavioral.opacity(0.3))
                        .frame(height: 2)
                        .position(x: width / 2, y: midY)

                    // Tolerance zone
                    Rectangle()
                        .fill(SanctuaryColors.Semantic.success.opacity(0.1))
                        .frame(height: height * 0.6)
                        .position(x: width / 2, y: midY)

                    // Data points
                    ForEach(Array(routine.weekData.enumerated()), id: \.element.id) { index, dayData in
                        if let time = dayData.actualTime {
                            let x = width * CGFloat(index + 1) / CGFloat(routine.weekData.count + 1)
                            let offsetMinutes = minuteOffset(from: routine.targetTime, to: time)
                            let normalizedOffset = CGFloat(offsetMinutes) / CGFloat(routine.toleranceMinutes * 2)
                            let y = midY - (normalizedOffset * height * 0.4)

                            Circle()
                                .fill(dayData.status.color)
                                .frame(width: 8, height: 8)
                                .position(x: x, y: max(4, min(height - 4, y)))
                                .opacity(isVisible ? 1 : 0)
                                .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05), value: isVisible)
                        }
                    }
                }
            }
            .frame(height: 60)

            // Legend
            HStack {
                ForEach(routine.weekData.suffix(7)) { dayData in
                    Text(dayData.dayLabel)
                        .font(.system(size: 8))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                isVisible = true
            }
        }
    }

    private func minuteOffset(from target: Date, to actual: Date) -> Int {
        let calendar = Calendar.current
        let targetMinutes = calendar.component(.hour, from: target) * 60 + calendar.component(.minute, from: target)
        let actualMinutes = calendar.component(.hour, from: actual) * 60 + calendar.component(.minute, from: actual)
        return actualMinutes - targetMinutes
    }
}

// MARK: - Routine Summary Compact

/// Compact summary of all routines
public struct RoutineSummaryCompact: View {

    let routines: [RoutineTracker]

    public init(routines: [RoutineTracker]) {
        self.routines = routines
    }

    public var body: some View {
        VStack(spacing: SanctuaryLayout.Spacing.sm) {
            ForEach(routines) { routine in
                RoutineMiniRow(routine: routine)

                if routine.id != routines.last?.id {
                    Rectangle()
                        .fill(SanctuaryColors.Glass.border)
                        .frame(height: 1)
                }
            }
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
struct BehavioralRoutineConsistency_Previews: PreviewProvider {
    static var previews: some View {
        let data = BehavioralDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    BehavioralRoutineConsistency(
                        routines: [data.morningRoutine, data.sleepSchedule, data.wakeSchedule]
                    )

                    RoutineTimeVarianceChart(routine: data.morningRoutine)

                    RoutineSummaryCompact(
                        routines: [data.morningRoutine, data.sleepSchedule]
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 700)
    }
}
#endif
