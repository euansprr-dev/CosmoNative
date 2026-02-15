// CosmoOS/UI/Sanctuary/Dimensions/Behavioral/BehavioralDimensionView.swift
// Behavioral Dimension View - "The Operator's Dashboard" complete dimension experience
// Phase 6: Following SANCTUARY_UI_SPEC_V2.md section 3.4

import SwiftUI

// MARK: - Behavioral Dimension View

/// The complete Behavioral Dimension view with all components
/// Layout: Discipline Index, Routine Consistency, Streaks, Daily Ops, Timeline, Level Up
public struct BehavioralDimensionView: View {

    // MARK: - Properties

    @StateObject private var viewModel: BehavioralDimensionViewModel
    @StateObject private var dataProvider = BehavioralDataProvider()
    @State private var selectedStreak: Streak?
    @State private var showStreakDetail: Bool = false
    let onBack: () -> Void

    // MARK: - Initialization

    public init(
        data: BehavioralDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: BehavioralDimensionViewModel(data: data))
        self.onBack = onBack
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Background
            backgroundLayer

            // Main content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SanctuaryLayout.Spacing.xxl) {
                    // Header with back button
                    headerSection

                    // Top section: Discipline Index
                    BehavioralDisciplineIndex(
                        disciplineScore: viewModel.data.disciplineIndex,
                        changePercent: viewModel.data.disciplineChange,
                        components: viewModel.data.allComponentScores
                    )

                    // Routine and Streaks row
                    HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.xl) {
                        // Routine Consistency
                        BehavioralRoutineConsistency(
                            routines: [
                                viewModel.data.morningRoutine,
                                viewModel.data.sleepSchedule,
                                viewModel.data.wakeSchedule
                            ]
                        )
                        .frame(maxWidth: .infinity)

                        // Streak Tracker
                        BehavioralStreakTracker(
                            activeStreaks: viewModel.data.activeStreaks,
                            endangeredStreaks: viewModel.data.endangeredStreaks
                        )
                        .frame(maxWidth: .infinity)
                    }

                    // Daily Operations
                    BehavioralDailyOperations(
                        dopamineDelay: viewModel.data.dopamineDelay,
                        dopamineTarget: viewModel.data.dopamineTarget,
                        walksCompleted: viewModel.data.walksCompleted,
                        walksGoal: viewModel.data.walksGoal,
                        screenTimeAfter10pm: viewModel.data.screenTimeAfter10pm,
                        screenLimit: viewModel.data.screenLimit,
                        tasksCompleted: viewModel.data.tasksCompleted,
                        tasksTotal: viewModel.data.tasksTotal
                    )

                    // Timeline and Level Up row
                    HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.xl) {
                        // Timeline
                        BehavioralTimeline(
                            events: viewModel.data.todayEvents,
                            violations: viewModel.data.violations
                        )
                        .frame(maxWidth: .infinity)

                        // Level Up + Prediction
                        VStack(spacing: SanctuaryLayout.Spacing.lg) {
                            LevelUpPathCard(levelUpPath: viewModel.data.levelUpPath)

                            if let prediction = viewModel.data.predictions.first {
                                BehavioralPredictionCard(prediction: prediction)
                            }
                        }
                        .frame(maxWidth: 400)
                    }

                    // Bottom spacer for safe area
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SanctuaryLayout.Spacing.xl)
                .padding(.top, SanctuaryLayout.Spacing.lg)
            }

            // Detail overlays
            detailOverlays
        }
        .onAppear {
            Task {
                await dataProvider.refreshData()
                viewModel.data = dataProvider.data
            }
        }
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        ZStack {
            // Base void
            SanctuaryColors.Background.void
                .ignoresSafeArea()

            // Behavioral dimension tint
            RadialGradient(
                colors: [
                    SanctuaryColors.Dimensions.behavioral.opacity(0.15),
                    SanctuaryColors.Dimensions.behavioral.opacity(0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 600
            )
            .ignoresSafeArea()

            // Edge vignette
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.4)],
                center: .center,
                startRadius: 300,
                endRadius: 800
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center) {
            // Back button
            Button(action: onBack) {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Sanctuary")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(SanctuaryColors.Text.secondary)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Title
            VStack(spacing: 2) {
                Text("BEHAVIORAL")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .tracking(4)

                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Text("The Operator's Dashboard")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.secondary)

                    Text("•")
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("Level \(viewModel.dimensionLevel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SanctuaryColors.Dimensions.behavioral)

                    Text("•")
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("Rank: DISCIPLINED")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SanctuaryColors.Dimensions.behavioral)
                }
            }

            Spacer()

            // Status indicator
            statusIndicator
        }
    }

    private var statusIndicator: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .modifier(PulseModifier())

                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Text("Discipline: \(Int(viewModel.data.disciplineIndex))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(disciplineColor)

            Text(disciplineStatus)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
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

    private var statusColor: Color {
        if viewModel.data.violations.isEmpty {
            return SanctuaryColors.Semantic.success
        }
        return SanctuaryColors.Semantic.warning
    }

    private var disciplineColor: Color {
        if viewModel.data.disciplineIndex >= 80 { return SanctuaryColors.Semantic.success }
        if viewModel.data.disciplineIndex >= 60 { return SanctuaryColors.Semantic.info }
        if viewModel.data.disciplineIndex >= 40 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }

    private var disciplineStatus: String {
        if viewModel.data.disciplineIndex >= 80 { return "Excellent" }
        if viewModel.data.disciplineIndex >= 60 { return "Good" }
        if viewModel.data.disciplineIndex >= 40 { return "Needs Work" }
        return "At Risk"
    }

    // MARK: - Detail Overlays

    @ViewBuilder
    private var detailOverlays: some View {
        // Streak detail
        if showStreakDetail, let streak = selectedStreak {
            overlayBackground
                .onTapGesture {
                    showStreakDetail = false
                }

            StreakDetailPanel(
                streak: streak,
                onDismiss: { showStreakDetail = false }
            )
            .frame(maxWidth: 400)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var overlayBackground: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .transition(.opacity)
    }
}

// MARK: - Pulse Modifier

@MainActor
private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 1)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Streak Detail Panel

/// Detail panel for a selected streak
public struct StreakDetailPanel: View {

    let streak: Streak
    let onDismiss: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                Image(systemName: streak.category.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(categoryColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(streak.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text(streak.category.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Stats
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                VStack(spacing: 4) {
                    Text("\(streak.currentDays)")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text("Current")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }

                VStack(spacing: 4) {
                    Text("\(streak.personalBest)")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("Best")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }

                VStack(spacing: 4) {
                    Text("+\(streak.xpPerDay)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("XP/day")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            // Milestone progress
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                Text("NEXT MILESTONE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SanctuaryColors.Glass.border)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(categoryColor)
                            .frame(
                                width: geometry.size.width * CGFloat(streak.progress),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(streak.daysToNextMilestone) days remaining")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.secondary)

                    Spacer()

                    Text("+\(streak.milestoneXP) XP")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.XP.primary)
                }
            }

            // Status
            if streak.isPersonalBest {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("Personal Best!")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(SanctuaryColors.XP.primary)
                }
                .padding(SanctuaryLayout.Spacing.sm)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(SanctuaryColors.XP.primary.opacity(0.1))
                )
            }
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(categoryColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var categoryColor: Color {
        Color(hex: streak.category.color)
    }
}

// MARK: - Behavioral Dimension View Model

@MainActor
public final class BehavioralDimensionViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var data: BehavioralDimensionData
    @Published public var isLoading: Bool = false

    // MARK: - Computed Properties

    public var dimensionLevel: Int {
        // Would be loaded from CosmoLevelState
        17
    }

    // MARK: - Initialization

    public init(data: BehavioralDimensionData) {
        self.data = data
    }

    // MARK: - Actions

    public func refreshData() async {
        isLoading = true
        // Would load from SanctuaryDataProvider / behavioral tracking systems
        try? await Task.sleep(nanoseconds: 500_000_000)
        isLoading = false
    }
}

// MARK: - Compact Behavioral View

/// Compact version for embedding in other views
public struct BehavioralDimensionCompact: View {

    let data: BehavioralDimensionData
    let onExpand: () -> Void

    @State private var isHovered: Bool = false

    public init(data: BehavioralDimensionData, onExpand: @escaping () -> Void) {
        self.data = data
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(SanctuaryColors.Dimensions.behavioral)

                    Text("BEHAVIORAL")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .tracking(2)
                }

                Spacer()

                Button(action: onExpand) {
                    HStack(spacing: 4) {
                        Text("Expand")
                            .font(.system(size: 11))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(SanctuaryColors.Dimensions.behavioral)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Discipline mini card
            DisciplineMiniCard(
                score: data.disciplineIndex,
                trend: data.disciplineChange >= 0 ? .up : .down
            )

            // Operations summary
            OperationsSummaryCompact(
                dopamineDelay: data.dopamineDelayMinutes,
                walksCompleted: data.walksCompleted,
                walksGoal: data.walksGoal,
                tasksCompleted: data.tasksCompleted,
                tasksTotal: data.tasksTotal,
                hasScreenViolation: data.isScreenOverLimit
            )

            // Streak summary
            StreakSummaryCompact(
                streaks: data.activeStreaks,
                onExpand: onExpand
            )
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(
                            isHovered ? SanctuaryColors.Dimensions.behavioral.opacity(0.5) : SanctuaryColors.Glass.border,
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
}

// MARK: - Preview

#if DEBUG
struct BehavioralDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        BehavioralDimensionView(
            data: .preview,
            onBack: {}
        )
        .frame(minWidth: 1200, minHeight: 1000)
    }
}
#endif
