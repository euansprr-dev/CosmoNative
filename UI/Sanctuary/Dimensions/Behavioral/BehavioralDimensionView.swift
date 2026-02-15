// CosmoOS/UI/Sanctuary/Dimensions/Behavioral/BehavioralDimensionView.swift
// Behavioral Dimension View - "The Operator's Dashboard" complete dimension experience
// Onyx Design System — premium cognitive atelier aesthetic

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
        GeometryReader { geometry in
            let useSingleColumn = geometry.size.width < Layout.twoColumnBreakpoint

            ZStack {
                // Background
                backgroundLayer

                // Main content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: OnyxLayout.metricGroupSpacing) {
                        // Header with back button
                        headerSection

                        // Top section: Discipline Index
                        BehavioralDisciplineIndex(
                            disciplineScore: viewModel.data.disciplineIndex,
                            changePercent: viewModel.data.disciplineChange,
                            components: viewModel.data.allComponentScores
                        )

                        routineAndStreakSection(useSingleColumn: useSingleColumn)

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

                        timelineAndLevelSection(useSingleColumn: useSingleColumn)

                        // Bottom spacer for safe area
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: Layout.maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
                // Detail overlays
                detailOverlays
            }
        }
        .onAppear {
            Task {
                await dataProvider.refreshData()
                viewModel.data = dataProvider.data
            }
        }
    }

    private enum Layout {
        static let maxContentWidth: CGFloat = 1400
        static let twoColumnBreakpoint: CGFloat = 900
    }

    @ViewBuilder
    private func routineAndStreakSection(useSingleColumn: Bool) -> some View {
        if useSingleColumn {
            VStack(spacing: 16) {
                BehavioralRoutineConsistency(
                    routines: [
                        viewModel.data.morningRoutine,
                        viewModel.data.sleepSchedule,
                        viewModel.data.wakeSchedule
                    ]
                )
                .frame(maxWidth: .infinity)
                BehavioralStreakTracker(
                    activeStreaks: viewModel.data.activeStreaks,
                    endangeredStreaks: viewModel.data.endangeredStreaks
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                BehavioralRoutineConsistency(
                    routines: [
                        viewModel.data.morningRoutine,
                        viewModel.data.sleepSchedule,
                        viewModel.data.wakeSchedule
                    ]
                )
                .frame(maxWidth: .infinity)

                BehavioralStreakTracker(
                    activeStreaks: viewModel.data.activeStreaks,
                    endangeredStreaks: viewModel.data.endangeredStreaks
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func timelineAndLevelSection(useSingleColumn: Bool) -> some View {
        if useSingleColumn {
            VStack(spacing: 16) {
                BehavioralTimeline(
                    events: viewModel.data.todayEvents,
                    violations: viewModel.data.violations
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    LevelUpPathCard(levelUpPath: viewModel.data.levelUpPath)
                        .frame(maxWidth: .infinity)
                    if let prediction = viewModel.data.predictions.first {
                        BehavioralPredictionCard(prediction: prediction)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                BehavioralTimeline(
                    events: viewModel.data.todayEvents,
                    violations: viewModel.data.violations
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    LevelUpPathCard(levelUpPath: viewModel.data.levelUpPath)
                        .frame(maxWidth: .infinity)
                    if let prediction = viewModel.data.predictions.first {
                        BehavioralPredictionCard(prediction: prediction)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        ZStack {
            // Onyx base surface
            OnyxColors.Elevation.base
                .ignoresSafeArea()

            // Subtle behavioral dimension tint (reduced from 0.15 to 0.08)
            RadialGradient(
                colors: [
                    OnyxColors.DimensionVivid.behavioral.opacity(0.08),
                    OnyxColors.DimensionVivid.behavioral.opacity(0.03),
                    Color.clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 600
            )
            .ignoresSafeArea()

            // Subtle edge vignette
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.3)],
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
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))

                    Text("Sanctuary")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(OnyxColors.Text.secondary)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Title — sentence case, Onyx typography
            VStack(spacing: 2) {
                Text("Behavioral")
                    .font(OnyxTypography.viewTitle)
                    .tracking(OnyxTypography.viewTitleTracking)
                    .foregroundColor(OnyxColors.Text.primary)

                HStack(spacing: 8) {
                    Text("The Operator's Dashboard")
                        .font(.system(size: 12))
                        .foregroundColor(OnyxColors.Text.secondary)

                    Text("·")
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("Tier \(viewModel.dimensionLevel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Dimension.behavioral)

                    Text("·")
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("Disciplined")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Dimension.behavioral)
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
                    .modifier(OnyxPulseModifier())

                Text("Live")
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Text.tertiary)
            }

            Text("Discipline: \(Int(viewModel.data.disciplineIndex))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(disciplineColor)

            Text(disciplineStatus)
                .font(OnyxTypography.micro)
                .foregroundColor(OnyxColors.Text.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(OnyxColors.Elevation.raised)
        )
        .onyxShadow(.resting)
    }

    private var statusColor: Color {
        if viewModel.data.violations.isEmpty {
            return OnyxColors.Accent.sage
        }
        return OnyxColors.Accent.rose
    }

    private var disciplineColor: Color {
        if viewModel.data.disciplineIndex >= 80 { return OnyxColors.Accent.sage }
        if viewModel.data.disciplineIndex >= 60 { return OnyxColors.DimensionVivid.behavioral }
        if viewModel.data.disciplineIndex >= 40 { return OnyxColors.Accent.amber }
        return OnyxColors.Accent.rose
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

// MARK: - Onyx Pulse Modifier

@MainActor
private struct OnyxPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.5 : 1.0)
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Streak Detail Panel

/// Detail panel for a selected streak — Onyx design
public struct StreakDetailPanel: View {

    let streak: Streak
    let onDismiss: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: streak.category.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(categoryColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(streak.name)
                        .font(OnyxTypography.cardTitle)
                        .tracking(OnyxTypography.cardTitleTracking)
                        .foregroundColor(OnyxColors.Text.primary)

                    Text(streak.category.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(OnyxColors.Text.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(OnyxColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Rectangle()
                .fill(OnyxColors.Text.muted.opacity(0.3))
                .frame(height: 1)

            // Stats
            HStack(spacing: 32) {
                VStack(spacing: 4) {
                    Text("\(streak.currentDays)")
                        .font(OnyxTypography.largeMetric)
                        .foregroundColor(OnyxColors.Text.primary)

                    Text("Current")
                        .font(OnyxTypography.micro)
                        .foregroundColor(OnyxColors.Text.tertiary)
                }

                VStack(spacing: 4) {
                    Text("\(streak.personalBest)")
                        .font(OnyxTypography.largeMetric)
                        .foregroundColor(OnyxColors.Accent.amber)

                    Text("Best")
                        .font(OnyxTypography.micro)
                        .foregroundColor(OnyxColors.Text.tertiary)
                }

                VStack(spacing: 4) {
                    Text("+\(streak.xpPerDay)/day")
                        .font(OnyxTypography.compactMetric)
                        .foregroundColor(OnyxColors.Accent.amber)

                    Text("Progress")
                        .font(OnyxTypography.micro)
                        .foregroundColor(OnyxColors.Text.tertiary)
                }
            }

            // Milestone progress
            VStack(alignment: .leading, spacing: 8) {
                OnyxSectionHeader("Next Milestone")

                OnyxProgressLine(
                    progress: streak.progress,
                    color: categoryColor
                )

                HStack {
                    Text("\(streak.daysToNextMilestone) days remaining")
                        .font(OnyxTypography.micro)
                        .foregroundColor(OnyxColors.Text.secondary)

                    Spacer()

                    Text("+\(streak.milestoneXP)")
                        .font(OnyxTypography.label)
                        .tracking(OnyxTypography.labelTracking)
                        .foregroundColor(OnyxColors.Accent.amber)
                }
            }

            // Status
            if streak.isPersonalBest {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(OnyxColors.Accent.amber)

                    Text("Personal best")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Accent.amber)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(OnyxColors.Accent.amber.opacity(0.1))
                )
            }
        }
        .padding(OnyxLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(OnyxColors.Elevation.elevated)
        )
        .onyxShadow(.floating)
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

/// Compact version for embedding in other views — Onyx design
public struct BehavioralDimensionCompact: View {

    let data: BehavioralDimensionData
    let onExpand: () -> Void

    @State private var isHovered: Bool = false

    public init(data: BehavioralDimensionData, onExpand: @escaping () -> Void) {
        self.data = data
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(OnyxColors.Dimension.behavioral)

                    Text("Behavioral")
                        .font(OnyxTypography.cardTitle)
                        .tracking(OnyxTypography.cardTitleTracking)
                        .foregroundColor(OnyxColors.Text.primary)
                }

                Spacer()

                Button(action: onExpand) {
                    HStack(spacing: 4) {
                        Text("Expand")
                            .font(.system(size: 11))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(OnyxColors.Dimension.behavioral)
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
        .padding(OnyxLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(OnyxColors.Elevation.raised)
        )
        .onyxShadow(isHovered ? .hovered : .resting)
        .animation(OnyxSpring.hover, value: isHovered)
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
