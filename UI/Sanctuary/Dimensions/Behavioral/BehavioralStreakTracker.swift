// CosmoOS/UI/Sanctuary/Dimensions/Behavioral/BehavioralStreakTracker.swift
// Streak Tracker - Streak cards with milestones and personal bests
// Phase 6: Following SANCTUARY_UI_SPEC_V2.md section 3.4

import SwiftUI

// MARK: - Streak Tracker Panel

/// Panel showing active streaks with milestone progress
public struct BehavioralStreakTracker: View {

    // MARK: - Properties

    let activeStreaks: [Streak]
    let endangeredStreaks: [Streak]

    @State private var isVisible: Bool = false

    // MARK: - Initialization

    public init(activeStreaks: [Streak], endangeredStreaks: [Streak] = []) {
        self.activeStreaks = activeStreaks
        self.endangeredStreaks = endangeredStreaks
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                Text("Active Streaks")
                    .font(OnyxTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(2)

                Spacer()

                // Total XP badge
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("\(totalDailyXP) XP/day")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.XP.primary)
                }
            }

            // Endangered streaks warning
            if !endangeredStreaks.isEmpty {
                endangeredSection
            }

            // Active streak cards
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md),
                    GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md)
                ],
                spacing: SanctuaryLayout.Spacing.md
            ) {
                ForEach(Array(activeStreaks.enumerated()), id: \.element.id) { index, streak in
                    BehavioralStreakCard(streak: streak)
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : 15)
                        .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.08 + 0.15), value: isVisible)
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

    // MARK: - Endangered Section

    private var endangeredSection: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Semantic.warning)

                Text("At Risk")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Semantic.warning)
                    .tracking(1)
            }

            HStack(spacing: SanctuaryLayout.Spacing.md) {
                ForEach(endangeredStreaks) { streak in
                    EndangeredStreakBadge(streak: streak)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Semantic.warning.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.Semantic.warning.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var totalDailyXP: Int {
        activeStreaks.reduce(0) { $0 + $1.xpPerDay }
    }
}

// MARK: - Streak Card

/// Individual streak card with progress to next milestone
public struct BehavioralStreakCard: View {

    let streak: Streak

    @State private var isHovered: Bool = false
    @State private var progressAnimated: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                // Category icon
                Image(systemName: streak.category.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(categoryColor)

                VStack(alignment: .leading, spacing: 0) {
                    Text(streak.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .tracking(0.5)

                    Text(streak.category.displayName)
                        .font(.system(size: 9))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }

                Spacer()

                // Personal best badge
                if streak.isPersonalBest {
                    personalBestBadge
                }
            }

            // Current streak count
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(streak.currentDays)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("days")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.secondary)

                Spacer()

                // XP badge
                VStack(alignment: .trailing, spacing: 2) {
                    Text("+\(streak.xpPerDay)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("XP/day")
                        .font(.system(size: 8))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            // Progress to next milestone
            milestoneProgress

            // Status text
            Text(streak.statusText)
                .font(.system(size: 10))
                .foregroundColor(statusTextColor)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? categoryColor.opacity(0.5) : Color.clear, lineWidth: 1)
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

    // MARK: - Personal Best Badge

    private var personalBestBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))

            Text("PB")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(SanctuaryColors.XP.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(SanctuaryColors.XP.primary.opacity(0.2))
        )
    }

    // MARK: - Milestone Progress

    private var milestoneProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SanctuaryColors.Glass.border)
                        .frame(height: 6)

                    // Progress
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [categoryColor, categoryColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: progressAnimated ? geometry.size.width * CGFloat(streak.progress) : 0,
                            height: 6
                        )

                    // Milestone marker
                    if streak.progress < 1 {
                        Circle()
                            .fill(SanctuaryColors.Glass.border)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(categoryColor, lineWidth: 2)
                            )
                            .position(x: geometry.size.width, y: 3)
                    }
                }
            }
            .frame(height: 10)

            // Milestone info
            HStack {
                Text("\(streak.daysToNextMilestone) days to milestone")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                Text("+\(streak.milestoneXP) XP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.XP.primary.opacity(0.7))
            }
        }
    }

    // MARK: - Colors

    private var categoryColor: Color {
        Color(hex: streak.category.color)
    }

    private var statusTextColor: Color {
        if streak.isPersonalBest { return SanctuaryColors.XP.primary }
        if streak.isEndangered { return SanctuaryColors.Semantic.error }
        return SanctuaryColors.Text.tertiary
    }
}

// MARK: - Endangered Streak Badge

/// Compact badge for endangered streaks
public struct EndangeredStreakBadge: View {

    let streak: Streak

    @State private var isPulsing: Bool = false

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.xs) {
            Image(systemName: streak.category.iconName)
                .font(.system(size: 10))

            Text("\(streak.currentDays)d")
                .font(.system(size: 10, weight: .bold, design: .monospaced))

            Text(streak.name)
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .foregroundColor(SanctuaryColors.Semantic.warning)
        .padding(.horizontal, SanctuaryLayout.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(SanctuaryColors.Semantic.warning.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(SanctuaryColors.Semantic.warning.opacity(0.3), lineWidth: 1)
                )
        )
        .scaleEffect(isPulsing ? 1.02 : 1.0)
        .animation(
            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
            value: isPulsing
        )
        .onAppear { isPulsing = true }
    }
}

// MARK: - Streak Mini Card

/// Compact streak display for embedding
public struct StreakMiniCard: View {

    let streak: Streak

    public init(streak: Streak) {
        self.streak = streak
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.sm) {
            // Icon
            Image(systemName: streak.category.iconName)
                .font(.system(size: 12))
                .foregroundColor(categoryColor)

            // Days
            Text("\(streak.currentDays)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("days")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Spacer()

            // Personal best indicator
            if streak.isPersonalBest {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.XP.primary)
            }
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.background)
        )
    }

    private var categoryColor: Color {
        Color(hex: streak.category.color)
    }
}

// MARK: - Streak Leaderboard

/// List of top streaks
public struct StreakLeaderboard: View {

    let streaks: [Streak]

    public init(streaks: [Streak]) {
        self.streaks = streaks.sorted { $0.currentDays > $1.currentDays }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("Top Streaks")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            ForEach(Array(streaks.prefix(5).enumerated()), id: \.element.id) { index, streak in
                HStack(spacing: SanctuaryLayout.Spacing.md) {
                    // Rank
                    Text("#\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(rankColor(for: index))
                        .frame(width: 24)

                    // Icon
                    Image(systemName: streak.category.iconName)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: streak.category.color))

                    // Name
                    Text(streak.name)
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .lineLimit(1)

                    Spacer()

                    // Days
                    HStack(spacing: 2) {
                        Text("\(streak.currentDays)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(SanctuaryColors.Text.primary)

                        Text("d")
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                }

                if index < min(4, streaks.count - 1) {
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

    private func rankColor(for index: Int) -> Color {
        switch index {
        case 0: return SanctuaryColors.XP.primary
        case 1: return SanctuaryColors.Text.secondary
        case 2: return Color(hex: "#CD7F32")
        default: return SanctuaryColors.Text.tertiary
        }
    }
}

// MARK: - Streak Summary Compact

/// Compact summary for embedding
public struct StreakSummaryCompact: View {

    let streaks: [Streak]
    let onExpand: () -> Void

    public init(streaks: [Streak], onExpand: @escaping () -> Void) {
        self.streaks = streaks
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.Dimensions.behavioral)

                    Text("Streaks")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .tracking(1)
                }

                Spacer()

                Button(action: onExpand) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 10))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(SanctuaryColors.Dimensions.behavioral)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Top 3 streaks
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                ForEach(streaks.sorted(by: { $0.currentDays > $1.currentDays }).prefix(3)) { streak in
                    VStack(spacing: 4) {
                        Image(systemName: streak.category.iconName)
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: streak.category.color))

                        Text("\(streak.currentDays)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(SanctuaryColors.Text.primary)

                        Text("days")
                            .font(.system(size: 8))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                    .frame(maxWidth: .infinity)
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

// Note: Color.init(hex:) is defined in Core/Theme.swift

// MARK: - Preview

#if DEBUG
struct BehavioralStreakTracker_Previews: PreviewProvider {
    static var previews: some View {
        let data = BehavioralDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    BehavioralStreakTracker(
                        activeStreaks: data.activeStreaks,
                        endangeredStreaks: data.endangeredStreaks
                    )

                    StreakLeaderboard(streaks: data.activeStreaks)

                    StreakSummaryCompact(
                        streaks: data.activeStreaks,
                        onExpand: {}
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 800)
    }
}
#endif
