import SwiftUI

// MARK: - Cross-Platform Colors

private extension Color {
    static var dashboardBackground: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

    static var dashboardSecondaryBackground: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
}

// MARK: - Level Dashboard View

/// Main dashboard view for the Cosmo Level System
/// Displays CI, NELO, dimensions, streaks, and daily progress
public struct LevelDashboardView: View {
    @ObservedObject var levelService: LevelSystemService
    @ObservedObject var celebrationEngine: CelebrationEngine
    @State private var selectedDimension: String?
    @State private var showingBadges = false

    public init(
        levelService: LevelSystemService,
        celebrationEngine: CelebrationEngine
    ) {
        self.levelService = levelService
        self.celebrationEngine = celebrationEngine
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Section
                heroSection

                // Dimension Bars
                dimensionBarsSection

                // Health Overview
                healthOverviewSection

                // Daily Progress
                dailyProgressSection

                // Streak Section
                streakSection

                // Badges Preview
                badgesPreviewSection
            }
            .padding()
        }
        .background(Color.dashboardBackground)
        .overlay(
            CelebrationOverlayView(engine: celebrationEngine)
        )
        .sheet(isPresented: $showingBadges) {
            BadgeGalleryView(levelService: levelService)
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 20) {
            HStack(spacing: 32) {
                // Cosmo Index
                cosmoIndexCard

                // Neuro-ELO
                neloCard
            }

            // Today's XP
            todayXPCard
        }
    }

    private var cosmoIndexCard: some View {
        VStack(spacing: 8) {
            Text("COSMO INDEX")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            if let snapshot = levelService.currentSnapshot {
                Text("\(snapshot.cosmoLevel)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: snapshot.currentLevelProgress)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 80, height: 80)

                Text("\(snapshot.xpToNextLevel) XP to next")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.dashboardSecondaryBackground)
        )
    }

    private var neloCard: some View {
        VStack(spacing: 8) {
            Text("NEURO-ELO")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            if let snapshot = levelService.currentSnapshot {
                Text("\(snapshot.overallNELO)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(neloColor(snapshot.neloTier))

                Text(snapshot.neloTier.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(neloColor(snapshot.neloTier))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(neloColor(snapshot.neloTier).opacity(0.15))
                    )

                // Trend indicator
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("Top 15%")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.green)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.dashboardSecondaryBackground)
        )
    }

    private var todayXPCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY'S XP")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                if let snapshot = levelService.currentSnapshot {
                    Text("+\(snapshot.totalXP % 1000) XP")  // Today's XP approximation
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
            }

            Spacer()

            // Streak flame
            if let snapshot = levelService.currentSnapshot {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)

                    Text("\(snapshot.streakSummary.overallState.currentStreak)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("day streak")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.dashboardSecondaryBackground)
        )
    }

    // MARK: - Dimension Bars Section

    private var dimensionBarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DIMENSIONS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            if let snapshot = levelService.currentSnapshot {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(snapshot.dimensions, id: \.name) { dimension in
                        DimensionBarView(dimension: dimension)
                            .onTapGesture {
                                selectedDimension = dimension.name
                            }
                    }
                }
            }
        }
    }

    // MARK: - Health Overview Section

    private var healthOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HEALTH")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            HStack(spacing: 12) {
                // Readiness Score
                healthMetricCard(
                    title: "Readiness",
                    value: "85%",
                    subtitle: "Peak Performance",
                    icon: "heart.fill",
                    color: .green
                )

                // HRV
                healthMetricCard(
                    title: "HRV",
                    value: "72ms",
                    subtitle: "Above baseline",
                    icon: "waveform.path.ecg",
                    color: .purple
                )
            }

            HStack(spacing: 12) {
                // Sleep
                healthMetricCard(
                    title: "Sleep",
                    value: "7h 45m",
                    subtitle: "94% efficiency",
                    icon: "moon.fill",
                    color: .indigo
                )

                // Activity
                healthMetricCard(
                    title: "Activity",
                    value: "3/3",
                    subtitle: "Rings closed",
                    icon: "circle.circle.fill",
                    color: .red
                )
            }
        }
    }

    private func healthMetricCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(color)
            }

            Spacer()

            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.dashboardSecondaryBackground)
        )
    }

    // MARK: - Daily Progress Section

    private var dailyProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DAILY QUESTS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                Spacer()

                Text("3/5 Complete")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            }

            VStack(spacing: 8) {
                QuestRowView(
                    title: "Deep Focus",
                    description: "45 min deep work",
                    progress: 1.0,
                    xp: 50,
                    isComplete: true
                )

                QuestRowView(
                    title: "Word Warrior",
                    description: "Write 500 words",
                    progress: 0.6,
                    xp: 40,
                    isComplete: false
                )

                QuestRowView(
                    title: "Recovery Check",
                    description: "Check readiness",
                    progress: 1.0,
                    xp: 20,
                    isComplete: true
                )
            }
        }
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STREAKS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            if let snapshot = levelService.currentSnapshot {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(snapshot.streakSummary.dimensionStates, id: \.dimension) { state in
                            StreakChipView(state: state)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Badges Preview Section

    private var badgesPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT BADGES")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                Spacer()

                Button("See All") {
                    showingBadges = true
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
            }

            if let snapshot = levelService.currentSnapshot {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(snapshot.recentBadges, id: \.id) { badge in
                            BadgeChipView(badge: badge)
                        }

                        // Nearest badges (faded)
                        ForEach(snapshot.nearestBadges, id: \.badgeId) { progress in
                            NearBadgeChipView(progress: progress)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func neloColor(_ tier: NELOTier) -> Color {
        switch tier {
        case .beginner: return .gray
        case .developing: return .green
        case .competent: return .blue
        case .proficient: return .purple
        case .expert: return .orange
        case .master: return .red
        case .grandmaster: return .yellow
        case .legend: return .pink
        }
    }
}

// MARK: - Dimension Bar View

struct DimensionBarView: View {
    let dimension: DimensionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForDimension(dimension.name))
                    .font(.system(size: 14))
                    .foregroundColor(colorForDimension(dimension.name))

                Text(dimension.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text("L\(dimension.level)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorForDimension(dimension.name))
                        .frame(width: geometry.size.width * dimension.levelProgress, height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("NELO: \(dimension.nelo)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if dimension.streakDays > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("\(dimension.streakDays)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.dashboardSecondaryBackground)
        )
    }

    private func iconForDimension(_ name: String) -> String {
        switch name {
        case "cognitive": return "brain.head.profile"
        case "creative": return "lightbulb.fill"
        case "physiological": return "heart.fill"
        case "behavioral": return "checkmark.circle.fill"
        case "knowledge": return "book.fill"
        case "reflection": return "person.fill.questionmark"
        default: return "circle.fill"
        }
    }

    private func colorForDimension(_ name: String) -> Color {
        switch name {
        case "cognitive": return .blue
        case "creative": return .orange
        case "physiological": return .red
        case "behavioral": return .green
        case "knowledge": return .purple
        case "reflection": return .indigo
        default: return .gray
        }
    }
}

// MARK: - Quest Row View

struct QuestRowView: View {
    let title: String
    let description: String
    let progress: Double
    let xp: Int
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Completion indicator
            ZStack {
                Circle()
                    .stroke(isComplete ? Color.green : Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isComplete ? .secondary : .primary)
                    .strikethrough(isComplete)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isComplete {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * progress, height: 4)
                    }
                }
                .frame(width: 60, height: 4)
            }

            Text("+\(xp)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(isComplete ? .green : .secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.dashboardSecondaryBackground)
        )
    }
}

// MARK: - Streak Chip View

struct StreakChipView: View {
    let state: StreakState

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundColor(state.currentStreak > 0 ? .orange : .gray)

                Text("\(state.currentStreak)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(state.currentStreak > 0 ? .primary : .secondary)
            }

            Text(state.dimension.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.dashboardSecondaryBackground)
        )
    }
}

// MARK: - Badge Chip View

struct BadgeChipView: View {
    let badge: BadgeDefinition

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(tierColor(badge.tier).opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: badge.iconName)
                    .font(.system(size: 22))
                    .foregroundColor(tierColor(badge.tier))
            }

            Text(badge.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(width: 70)
    }

    private func tierColor(_ tier: BadgeTier) -> Color {
        switch tier {
        case .bronze: return .brown
        case .silver: return .gray
        case .gold: return .yellow
        case .platinum: return .cyan
        case .diamond: return .blue
        case .cosmic: return .purple
        }
    }
}

// MARK: - Near Badge Chip View

struct NearBadgeChipView: View {
    let progress: BadgeProgress

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 48, height: 48)

                Circle()
                    .trim(from: 0, to: progress.overallProgress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }

            Text("\(Int(progress.overallProgress * 100))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(width: 70)
        .opacity(0.6)
    }
}

// MARK: - Badge Gallery View

struct BadgeGalleryView: View {
    @ObservedObject var levelService: LevelSystemService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    if let snapshot = levelService.currentSnapshot {
                        ForEach(snapshot.recentBadges, id: \.id) { badge in
                            BadgeDetailCard(badge: badge, isEarned: true)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Badges")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BadgeDetailCard: View {
    let badge: BadgeDefinition
    let isEarned: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tierGradient(badge.tier))
                    .frame(width: 60, height: 60)

                Image(systemName: badge.iconName)
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }

            Text(badge.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(badge.tier.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.dashboardSecondaryBackground)
        )
    }

    private func tierGradient(_ tier: BadgeTier) -> LinearGradient {
        let colors: [Color]
        switch tier {
        case .bronze: colors = [.brown, .orange]
        case .silver: colors = [.gray, .white]
        case .gold: colors = [.yellow, .orange]
        case .platinum: colors = [.cyan, .blue]
        case .diamond: colors = [.blue, .purple]
        case .cosmic: colors = [.purple, .pink, .orange]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Preview

#Preview {
    // Preview would require mock data
    Text("Level Dashboard Preview")
}
