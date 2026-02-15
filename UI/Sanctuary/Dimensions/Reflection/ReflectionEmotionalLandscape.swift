// CosmoOS/UI/Sanctuary/Dimensions/Reflection/ReflectionEmotionalLandscape.swift
// Emotional Landscape - Valence-Energy 2D mood map visualization
// Phase 8: Following SANCTUARY_UI_SPEC_V2.md section 3.6

import SwiftUI

// MARK: - Emotional Landscape Panel

/// Main emotional landscape with 2D valence-energy map
public struct EmotionalLandscapePanel: View {

    // MARK: - Properties

    let currentState: EmotionalState
    let dataPoints: [EmotionalDataPoint]
    let weekAverage: EmotionalState
    let trendDirection: TrendDirection
    let moodTimeline: [HourlyMood]

    @State private var isVisible: Bool = false
    @State private var selectedPoint: EmotionalDataPoint?

    // MARK: - Initialization

    public init(
        currentState: EmotionalState,
        dataPoints: [EmotionalDataPoint],
        weekAverage: EmotionalState,
        trendDirection: TrendDirection,
        moodTimeline: [HourlyMood]
    ) {
        self.currentState = currentState
        self.dataPoints = dataPoints
        self.weekAverage = weekAverage
        self.trendDirection = trendDirection
        self.moodTimeline = moodTimeline
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            headerSection

            // Main 2D map
            emotionalMap
                .frame(height: 280)

            // Mood timeline
            moodTimelineSection

            // Trend indicator
            trendSection
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
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Emotional Landscape")
                    .font(OnyxTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(2)

                Text("Valence-Energy Map")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            Spacer()

            // Current state indicator
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Text(currentState.dominantMood)
                    .font(.system(size: 24))

                VStack(alignment: .trailing, spacing: 2) {
                    Text(currentState.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SanctuaryColors.Dimensions.reflection)

                    Text("Now")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }
        }
    }

    // MARK: - Emotional Map

    private var emotionalMap: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                emotionalMapGrid(in: geometry.size)

                // Quadrant labels
                quadrantLabels(in: geometry.size)

                // Axis labels
                axisLabels(in: geometry.size)

                // Historical data points
                ForEach(dataPoints.prefix(20)) { point in
                    emotionalDataPointView(point, in: geometry.size)
                }

                // Week average indicator
                weekAverageIndicator(in: geometry.size)

                // Current position (highlighted)
                currentPositionIndicator(in: geometry.size)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private func emotionalMapGrid(in size: CGSize) -> some View {
        ZStack {
            // Horizontal lines
            ForEach(-2..<3) { i in
                let y = size.height / 2 + CGFloat(i) * (size.height / 4)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(
                    i == 0 ? SanctuaryColors.Glass.border.opacity(0.6) : SanctuaryColors.Glass.border.opacity(0.3),
                    lineWidth: i == 0 ? 1.5 : 0.5
                )
            }

            // Vertical lines
            ForEach(-2..<3) { i in
                let x = size.width / 2 + CGFloat(i) * (size.width / 4)
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                .stroke(
                    i == 0 ? SanctuaryColors.Glass.border.opacity(0.6) : SanctuaryColors.Glass.border.opacity(0.3),
                    lineWidth: i == 0 ? 1.5 : 0.5
                )
            }
        }
    }

    private func quadrantLabels(in size: CGSize) -> some View {
        ZStack {
            // Top-right: High Energy, Positive
            Text("Excited")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.tertiary.opacity(0.6))
                .position(x: size.width * 0.75, y: size.height * 0.15)

            // Top-left: High Energy, Negative
            Text("Anxious")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.tertiary.opacity(0.6))
                .position(x: size.width * 0.25, y: size.height * 0.15)

            // Bottom-right: Low Energy, Positive
            Text("Calm")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.tertiary.opacity(0.6))
                .position(x: size.width * 0.75, y: size.height * 0.85)

            // Bottom-left: Low Energy, Negative
            Text("Sad")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.tertiary.opacity(0.6))
                .position(x: size.width * 0.25, y: size.height * 0.85)
        }
    }

    private func axisLabels(in size: CGSize) -> some View {
        ZStack {
            // X-axis: Valence
            Text("VALENCE →")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(SanctuaryColors.Dimensions.reflection.opacity(0.7))
                .tracking(1)
                .position(x: size.width - 35, y: size.height / 2 + 12)

            Text("Negative")
                .font(.system(size: 8))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .position(x: 30, y: size.height / 2 + 12)

            Text("Positive")
                .font(.system(size: 8))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .position(x: size.width - 30, y: size.height / 2 + 12)

            // Y-axis: Energy
            Text("Energy")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(SanctuaryColors.Dimensions.reflection.opacity(0.7))
                .tracking(1)
                .rotationEffect(.degrees(-90))
                .position(x: size.width / 2 - 12, y: 30)

            Text("High")
                .font(.system(size: 8))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .position(x: size.width / 2 + 20, y: 15)

            Text("Low")
                .font(.system(size: 8))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .position(x: size.width / 2 + 20, y: size.height - 15)
        }
    }

    private func emotionalDataPointView(_ point: EmotionalDataPoint, in size: CGSize) -> some View {
        let position = coordinateToPosition(valence: point.valence, energy: point.energy, in: size)
        let isToday = Calendar.current.isDateInToday(point.timestamp)
        let opacity = isToday ? 0.8 : max(0.2, 1.0 - Double(dataPoints.firstIndex(where: { $0.id == point.id }) ?? 0) * 0.05)

        return Text(point.emoji)
            .font(.system(size: isToday ? 20 : 14))
            .opacity(opacity)
            .position(position)
            .onTapGesture {
                selectedPoint = point
            }
    }

    private func weekAverageIndicator(in size: CGSize) -> some View {
        let position = coordinateToPosition(valence: weekAverage.valence, energy: weekAverage.energy, in: size)

        return ZStack {
            // Outer ring
            Circle()
                .stroke(SanctuaryColors.Dimensions.reflection.opacity(0.3), lineWidth: 2)
                .frame(width: 40, height: 40)

            // Label
            Text("7d")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(SanctuaryColors.Dimensions.reflection)
        }
        .position(position)
    }

    private func currentPositionIndicator(in size: CGSize) -> some View {
        let position = coordinateToPosition(valence: currentState.valence, energy: currentState.energy, in: size)

        return ZStack {
            // Pulse effect
            Circle()
                .fill(SanctuaryColors.Dimensions.reflection.opacity(0.2))
                .frame(width: 50, height: 50)
                .modifier(PulseAnimationModifier())

            // Inner glow
            Circle()
                .fill(SanctuaryColors.Dimensions.reflection.opacity(0.4))
                .frame(width: 30, height: 30)

            // Emoji
            Text(currentState.dominantMood)
                .font(.system(size: 24))
        }
        .position(position)
    }

    private func coordinateToPosition(valence: Double, energy: Double, in size: CGSize) -> CGPoint {
        // Valence: -1 (left) to +1 (right)
        // Energy: -1 (bottom) to +1 (top)
        let x = size.width / 2 + CGFloat(valence) * (size.width / 2 - 20)
        let y = size.height / 2 - CGFloat(energy) * (size.height / 2 - 20)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Mood Timeline

    private var moodTimelineSection: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("TODAY'S JOURNEY")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SanctuaryLayout.Spacing.md) {
                    ForEach(moodTimeline) { mood in
                        VStack(spacing: 4) {
                            Text(mood.emoji)
                                .font(.system(size: 20))

                            Text(formatHour(mood.hour))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(SanctuaryColors.Text.tertiary)
                        }
                        .padding(.vertical, SanctuaryLayout.Spacing.sm)
                        .padding(.horizontal, SanctuaryLayout.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                .fill(mood.isHighlight ? SanctuaryColors.Dimensions.reflection.opacity(0.1) : Color.clear)
                        )
                    }
                }
            }
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let suffix = hour >= 12 ? "pm" : "am"
        let displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return "\(displayHour)\(suffix)"
    }

    // MARK: - Trend Section

    private var trendSection: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Trend indicator
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Image(systemName: trendIcon)
                    .font(.system(size: 12))
                    .foregroundColor(trendColor)

                Text(trendLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(trendColor)
            }
            .padding(.horizontal, SanctuaryLayout.Spacing.md)
            .padding(.vertical, SanctuaryLayout.Spacing.sm)
            .background(
                Capsule()
                    .fill(trendColor.opacity(0.1))
            )

            Spacer()

            // 7-day summary
            Text("Valence \(trendDirection == .improving ? "improving" : trendDirection == .stable ? "stable" : "declining") over past 7 days")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.secondary)
        }
    }

    private var trendIcon: String {
        switch trendDirection {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }

    private var trendColor: Color {
        switch trendDirection {
        case .improving: return SanctuaryColors.Semantic.success
        case .stable: return SanctuaryColors.Semantic.info
        case .declining: return SanctuaryColors.Semantic.warning
        }
    }

    private var trendLabel: String {
        switch trendDirection {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .declining: return "Declining"
        }
    }
}

// MARK: - Pulse Animation Modifier

@MainActor
private struct PulseAnimationModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.4 : 0.8)
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Emotional Map Compact

/// Compact version for embedding
public struct EmotionalLandscapeCompact: View {

    let currentState: EmotionalState
    let trendDirection: TrendDirection
    let onExpand: () -> Void

    @State private var isHovered: Bool = false

    public init(
        currentState: EmotionalState,
        trendDirection: TrendDirection,
        onExpand: @escaping () -> Void
    ) {
        self.currentState = currentState
        self.trendDirection = trendDirection
        self.onExpand = onExpand
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Current mood
            Text(currentState.dominantMood)
                .font(.system(size: 36))

            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                Text("Emotional State")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Text(currentState.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)

                HStack(spacing: 4) {
                    Image(systemName: trendIcon)
                        .font(.system(size: 10))
                        .foregroundColor(trendColor)

                    Text(trendLabel)
                        .font(.system(size: 10))
                        .foregroundColor(trendColor)
                }
            }

            Spacer()

            Button(action: onExpand) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Dimensions.reflection)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(
                            isHovered ? SanctuaryColors.Dimensions.reflection.opacity(0.5) : SanctuaryColors.Glass.border,
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var trendIcon: String {
        switch trendDirection {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }

    private var trendColor: Color {
        switch trendDirection {
        case .improving: return SanctuaryColors.Semantic.success
        case .stable: return SanctuaryColors.Semantic.info
        case .declining: return SanctuaryColors.Semantic.warning
        }
    }

    private var trendLabel: String {
        switch trendDirection {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .declining: return "Declining"
        }
    }
}

// MARK: - Mood Quick Capture

/// Quick mood capture button
public struct MoodQuickCapture: View {

    let onMoodSelected: (String, Double, Double) -> Void

    private let quickMoods: [(emoji: String, label: String, valence: Double, energy: Double)] = [
        ("😊", "Happy", 0.7, 0.5),
        ("😌", "Calm", 0.5, -0.3),
        ("😤", "Frustrated", -0.6, 0.7),
        ("😢", "Sad", -0.7, -0.5),
        ("🤔", "Thoughtful", 0.2, 0.3),
        ("😴", "Tired", -0.2, -0.8)
    ]

    public init(onMoodSelected: @escaping (String, Double, Double) -> Void) {
        self.onMoodSelected = onMoodSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("HOW ARE YOU FEELING?")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            HStack(spacing: SanctuaryLayout.Spacing.md) {
                ForEach(quickMoods, id: \.emoji) { mood in
                    Button(action: {
                        onMoodSelected(mood.emoji, mood.valence, mood.energy)
                    }) {
                        VStack(spacing: 4) {
                            Text(mood.emoji)
                                .font(.system(size: 28))

                            Text(mood.label)
                                .font(.system(size: 9))
                                .foregroundColor(SanctuaryColors.Text.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SanctuaryLayout.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                .fill(SanctuaryColors.Glass.highlight)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
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
    }
}

// MARK: - Valence Energy Mini Chart

/// Mini visualization of valence/energy coordinates
public struct ValenceEnergyMini: View {

    let valence: Double
    let energy: Double

    public init(valence: Double, energy: Double) {
        self.valence = valence
        self.energy = energy
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(SanctuaryColors.Glass.highlight)

                // Cross lines
                Path { path in
                    path.move(to: CGPoint(x: size / 2, y: 4))
                    path.addLine(to: CGPoint(x: size / 2, y: size - 4))
                }
                .stroke(SanctuaryColors.Glass.border, lineWidth: 0.5)

                Path { path in
                    path.move(to: CGPoint(x: 4, y: size / 2))
                    path.addLine(to: CGPoint(x: size - 4, y: size / 2))
                }
                .stroke(SanctuaryColors.Glass.border, lineWidth: 0.5)

                // Position dot
                Circle()
                    .fill(SanctuaryColors.Dimensions.reflection)
                    .frame(width: 6, height: 6)
                    .position(
                        x: size / 2 + CGFloat(valence) * (size / 2 - 8),
                        y: size / 2 - CGFloat(energy) * (size / 2 - 8)
                    )
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ReflectionEmotionalLandscape_Previews: PreviewProvider {
    static var previews: some View {
        let data = ReflectionDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    EmotionalLandscapePanel(
                        currentState: data.currentEmotionalState,
                        dataPoints: data.emotionalDataPoints,
                        weekAverage: data.weekAverageState,
                        trendDirection: data.emotionalTrend,
                        moodTimeline: data.todayMoodTimeline
                    )

                    EmotionalLandscapeCompact(
                        currentState: data.currentEmotionalState,
                        trendDirection: data.emotionalTrend,
                        onExpand: {}
                    )

                    MoodQuickCapture(onMoodSelected: { _, _, _ in })

                    ValenceEnergyMini(valence: 0.5, energy: 0.3)
                        .frame(width: 60, height: 60)
                }
                .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 800)
    }
}
#endif
