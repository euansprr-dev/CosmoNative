// CosmoOS/UI/Sanctuary/Dimensions/Reflection/ReflectionJournalingRhythm.swift
// Journaling Rhythm - Streak tracking, word counts, and depth analysis
// Phase 8: Following SANCTUARY_UI_SPEC_V2.md section 3.6

import SwiftUI

// MARK: - Journaling Rhythm Panel

/// Main journaling rhythm panel with streak and depth metrics
public struct JournalingRhythmPanel: View {

    // MARK: - Properties

    let currentStreak: Int
    let longestStreak: Int
    let todayWordCount: Int
    let averageWordCount: Int
    let todayDepthScore: Double
    let weeklyDepthData: [DailyJournalDepth]
    let consistency: Double

    @State private var isVisible: Bool = false
    @State private var streakAnimated: Bool = false

    // MARK: - Initialization

    public init(
        currentStreak: Int,
        longestStreak: Int,
        todayWordCount: Int,
        averageWordCount: Int,
        todayDepthScore: Double,
        weeklyDepthData: [DailyJournalDepth],
        consistency: Double
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.todayWordCount = todayWordCount
        self.averageWordCount = averageWordCount
        self.todayDepthScore = todayDepthScore
        self.weeklyDepthData = weeklyDepthData
        self.consistency = consistency
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("Journaling Rhythm")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Streak and consistency row
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                streakDisplay
                consistencyGauge
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Word count and depth row
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                wordCountSection
                depthSection
            }

            // Weekly depth chart
            weeklyDepthChart
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
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                streakAnimated = true
            }
        }
    }

    // MARK: - Streak Display

    private var streakDisplay: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("Current Streak")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            HStack(alignment: .lastTextBaseline, spacing: SanctuaryLayout.Spacing.sm) {
                Text("\(streakAnimated ? currentStreak : 0)")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Dimensions.reflection)

                VStack(alignment: .leading, spacing: 2) {
                    Text("days")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.Text.secondary)

                    if currentStreak > 0 {
                        Text("🔥")
                            .font(.system(size: 20))
                    }
                }
            }

            // Longest streak reference
            HStack(spacing: 4) {
                Text("Longest:")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("\(longestStreak) days")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.secondary)

                if currentStreak >= longestStreak && currentStreak > 0 {
                    Text("⭐ NEW RECORD")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Semantic.success)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Consistency Gauge

    private var consistencyGauge: some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            Text("Consistency")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            ZStack {
                // Background circle
                Circle()
                    .stroke(SanctuaryColors.Glass.border, lineWidth: 8)

                // Progress circle
                Circle()
                    .trim(from: 0, to: streakAnimated ? CGFloat(consistency) : 0)
                    .stroke(
                        LinearGradient(
                            colors: [SanctuaryColors.Dimensions.reflection, SanctuaryColors.Dimensions.reflection.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // Center percentage
                VStack(spacing: 0) {
                    Text("\(Int(consistency * 100))")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text("%")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }
            .frame(width: 80, height: 80)

            Text("30-day rate")
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }

    // MARK: - Word Count Section

    private var wordCountSection: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("TODAY'S WORDS")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(todayWordCount)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("words")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            // Comparison to average
            let diff = todayWordCount - averageWordCount
            let diffPercent = averageWordCount > 0 ? abs(diff) * 100 / averageWordCount : 0

            HStack(spacing: 4) {
                Image(systemName: diff >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9))
                    .foregroundColor(diff >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Text.tertiary)

                Text("\(diffPercent)% \(diff >= 0 ? "above" : "below") avg")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            Text("Avg: \(averageWordCount) words")
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Depth Section

    private var depthSection: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("Depth Score")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", todayDepthScore))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(depthColor)

                Text("/ 10")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            // Depth bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SanctuaryColors.Glass.border)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(depthColor)
                        .frame(width: geometry.size.width * CGFloat(todayDepthScore / 10), height: 8)
                }
            }
            .frame(height: 8)

            Text(depthLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(depthColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var depthColor: Color {
        if todayDepthScore >= 8 { return SanctuaryColors.Semantic.success }
        if todayDepthScore >= 5 { return SanctuaryColors.Semantic.info }
        if todayDepthScore >= 3 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Text.tertiary
    }

    private var depthLabel: String {
        if todayDepthScore >= 8 { return "Deep Reflection" }
        if todayDepthScore >= 5 { return "Thoughtful" }
        if todayDepthScore >= 3 { return "Surface Level" }
        return "Brief Entry"
    }

    // MARK: - Weekly Depth Chart

    private var weeklyDepthChart: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("Weekly Depth")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                ForEach(weeklyDepthData) { day in
                    VStack(spacing: 4) {
                        // Depth bar
                        GeometryReader { geometry in
                            VStack {
                                Spacer()

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(day.isToday ? SanctuaryColors.Dimensions.reflection : dayDepthColor(day.depthScore))
                                    .frame(height: max(4, geometry.size.height * CGFloat(day.depthScore / 10)))
                            }
                        }
                        .frame(height: 60)

                        // Day label
                        Text(day.dayLabel)
                            .font(.system(size: 9, weight: day.isToday ? .bold : .regular))
                            .foregroundColor(day.isToday ? SanctuaryColors.Dimensions.reflection : SanctuaryColors.Text.tertiary)

                        // Score
                        if day.hasEntry {
                            Text(String(format: "%.0f", day.depthScore))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(SanctuaryColors.Text.secondary)
                        } else {
                            Text("-")
                                .font(.system(size: 8))
                                .foregroundColor(SanctuaryColors.Text.tertiary)
                        }
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

    private func dayDepthColor(_ score: Double) -> Color {
        if score >= 8 { return SanctuaryColors.Semantic.success }
        if score >= 5 { return SanctuaryColors.Semantic.info }
        if score >= 3 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Glass.border
    }
}

// MARK: - Daily Journal Depth Model

public struct DailyJournalDepth: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let dayLabel: String
    public let depthScore: Double
    public let wordCount: Int
    public let hasEntry: Bool
    public let isToday: Bool

    public init(
        id: UUID = UUID(),
        date: Date,
        dayLabel: String,
        depthScore: Double,
        wordCount: Int,
        hasEntry: Bool,
        isToday: Bool = false
    ) {
        self.id = id
        self.date = date
        self.dayLabel = dayLabel
        self.depthScore = depthScore
        self.wordCount = wordCount
        self.hasEntry = hasEntry
        self.isToday = isToday
    }
}

// MARK: - Streak Card

/// Standalone streak card for embedding
public struct JournalingStreakCard: View {

    let currentStreak: Int
    let longestStreak: Int
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    public init(currentStreak: Int, longestStreak: Int, onTap: @escaping () -> Void) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: SanctuaryLayout.Spacing.lg) {
                // Flame icon
                Text("🔥")
                    .font(.system(size: 32))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(currentStreak) DAY STREAK")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(SanctuaryColors.Dimensions.reflection)

                    Text("Keep it going!")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Best")
                        .font(.system(size: 9))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("\(longestStreak)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }
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
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Journal Prompt Card

/// Daily journal prompt suggestion
public struct JournalPromptCard: View {

    let prompt: String
    let category: String
    let onStart: () -> Void
    let onSkip: () -> Void

    public init(
        prompt: String,
        category: String,
        onStart: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.category = category
        self.onStart = onStart
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Text("TODAY'S PROMPT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Text(category)
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Dimensions.reflection)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(SanctuaryColors.Dimensions.reflection.opacity(0.1))
                    )
            }

            // Prompt text
            Text("\"\(prompt)\"")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)
                .italic()
                .lineLimit(3)

            // Actions
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                Button(action: onStart) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))

                        Text("Start Writing")
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

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
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

// MARK: - Journaling Compact

/// Compact journaling summary
public struct JournalingRhythmCompact: View {

    let currentStreak: Int
    let todayWordCount: Int
    let consistency: Double
    let onExpand: () -> Void

    public init(
        currentStreak: Int,
        todayWordCount: Int,
        consistency: Double,
        onExpand: @escaping () -> Void
    ) {
        self.currentStreak = currentStreak
        self.todayWordCount = todayWordCount
        self.consistency = consistency
        self.onExpand = onExpand
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Streak
            HStack(spacing: 4) {
                Text("🔥")
                    .font(.system(size: 20))

                Text("\(currentStreak)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Dimensions.reflection)
            }

            // Divider
            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(width: 1, height: 30)

            // Word count
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("\(todayWordCount) words")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            Spacer()

            // Consistency
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(consistency * 100))%")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("consistency")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
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

// MARK: - Preview

#if DEBUG
struct ReflectionJournalingRhythm_Previews: PreviewProvider {
    static var previews: some View {
        let weeklyData: [DailyJournalDepth] = [
            DailyJournalDepth(date: Date(), dayLabel: "M", depthScore: 7.5, wordCount: 450, hasEntry: true),
            DailyJournalDepth(date: Date(), dayLabel: "T", depthScore: 5.2, wordCount: 280, hasEntry: true),
            DailyJournalDepth(date: Date(), dayLabel: "W", depthScore: 8.1, wordCount: 620, hasEntry: true),
            DailyJournalDepth(date: Date(), dayLabel: "T", depthScore: 0, wordCount: 0, hasEntry: false),
            DailyJournalDepth(date: Date(), dayLabel: "F", depthScore: 6.8, wordCount: 380, hasEntry: true),
            DailyJournalDepth(date: Date(), dayLabel: "S", depthScore: 9.2, wordCount: 850, hasEntry: true),
            DailyJournalDepth(date: Date(), dayLabel: "S", depthScore: 7.0, wordCount: 420, hasEntry: true, isToday: true)
        ]

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    JournalingRhythmPanel(
                        currentStreak: 14,
                        longestStreak: 21,
                        todayWordCount: 420,
                        averageWordCount: 350,
                        todayDepthScore: 7.0,
                        weeklyDepthData: weeklyData,
                        consistency: 0.82
                    )

                    JournalingStreakCard(
                        currentStreak: 14,
                        longestStreak: 21,
                        onTap: {}
                    )

                    JournalPromptCard(
                        prompt: "What would you do if you knew you couldn't fail?",
                        category: "Self-Discovery",
                        onStart: {},
                        onSkip: {}
                    )

                    JournalingRhythmCompact(
                        currentStreak: 14,
                        todayWordCount: 420,
                        consistency: 0.82,
                        onExpand: {}
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 900)
    }
}
#endif
