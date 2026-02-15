// CosmoOS/UI/Sanctuary/Dimensions/Physiological/PhysiologicalDimensionView.swift
// Physiological Dimension View - "The Body Interface" complete dimension experience
// Phase 5: Following SANCTUARY_UI_SPEC_V2.md section 3.3

import SwiftUI

// MARK: - Physiological Dimension View

/// The complete Physiological Dimension view with all components
/// Layout: Body Scanner, Vital Signs, HRV Trend, Sleep Analysis, Activity Rings, Workout Log, Correlations
public struct PhysiologicalDimensionView: View {

    // MARK: - Properties

    @StateObject private var viewModel: PhysiologicalDimensionViewModel
    @StateObject private var dataProvider = PhysiologicalDataProvider()
    @State private var selectedMuscle: MuscleStatus?
    @State private var selectedWorkout: WorkoutSession?
    @State private var showMuscleDetail: Bool = false
    @State private var showWorkoutDetail: Bool = false
    @State private var showSettings: Bool = false

    let onBack: () -> Void

    // MARK: - Initialization

    public init(
        data: PhysiologicalDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: PhysiologicalDimensionViewModel(data: data))
        self.onBack = onBack
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Background
            backgroundLayer

            if viewModel.data.isEmpty {
                // Empty state
                VStack {
                    headerSection
                        .padding(.horizontal, SanctuaryLayout.Spacing.xl)
                        .padding(.top, SanctuaryLayout.Spacing.lg)
                    Spacer()
                    PlaceholderCard(
                        state: .notConnected(
                            source: "Apple Health",
                            description: "Enable Apple Health in Settings to track HRV, sleep, recovery, and activity data from your Apple Watch.",
                            connectAction: { showSettings = true }
                        ),
                        accentColor: SanctuaryColors.Dimensions.physiological
                    )
                    .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                // Main content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: SanctuaryLayout.Spacing.lg) {
                        // Header with back button
                        headerSection

                        // HealthKit connection banner (shown when not connected)
                        if !dataProvider.isConnected {
                            healthConnectBanner
                        }

                        // Top section: Body Scanner + Vital Signs (side by side)
                        HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.lg) {
                            // Body Scanner
                            PhysiologicalBodyScanner(
                                muscleMap: viewModel.data.muscleRecoveryMap,
                                stressLevel: viewModel.data.stressLevel,
                                cortisolEstimate: viewModel.data.cortisolEstimate,
                                breathingRate: viewModel.data.breathingRatePerMin,
                                currentHRV: viewModel.data.currentHRV,
                                onMuscleTap: { muscle in
                                    selectedMuscle = muscle
                                    showMuscleDetail = true
                                }
                            )
                            .frame(maxWidth: 500)

                            // Vital Signs panel (right side)
                            PhysiologicalVitalSigns(data: viewModel.data)
                                .frame(maxWidth: .infinity)
                        }

                        // Second row: Sleep Analysis + HRV Trend (side by side to fill dead space)
                        HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.lg) {
                            // Sleep Analysis (compact, left side)
                            PhysiologicalSleepAnalysis(
                                sleep: viewModel.data.lastNightSleep,
                                sleepDebt: viewModel.data.sleepDebt,
                                sleepTrend: viewModel.data.sleepTrend
                            )
                            .frame(maxWidth: .infinity)

                            // HRV Trend (right side)
                            HRVTrendChart(
                                trend: viewModel.data.hrvTrend,
                                currentHRV: viewModel.data.currentHRV
                            )
                            .frame(maxWidth: 380)
                        }

                        // Third row: Activity Rings + Workout Log (side by side)
                        HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.lg) {
                            PhysiologicalActivityRings(
                                rings: viewModel.data.dailyRings,
                                stepCount: viewModel.data.stepCount
                            )
                            .frame(maxWidth: 450)

                            PhysiologicalWorkoutLog(
                                workouts: viewModel.data.workouts,
                                weeklyVolumeLoad: viewModel.data.weeklyVolumeLoad,
                                recoveryDebt: viewModel.data.recoveryDebt
                            )
                            .frame(maxWidth: .infinity)
                        }

                        // Correlation Map + Predictions (full width)
                        PhysiologicalCorrelationMap(
                            correlations: viewModel.data.correlations,
                            predictions: viewModel.data.predictions
                        )

                        // Sleep Trend Chart
                        SleepTrendChart(scores: viewModel.data.sleepTrend)

                        // Bottom spacer for safe area
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, SanctuaryLayout.Spacing.xl)
                    .padding(.top, SanctuaryLayout.Spacing.lg)
                }
            }

            // Loading overlay
            if dataProvider.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            // Detail overlays
            detailOverlays
        }
        .sheet(isPresented: $showSettings) {
            SanctuarySettingsView()
        }
        .task {
            await loadHealthData()
        }
        .onReceive(dataProvider.$data) { newData in
            viewModel.data = newData
        }
    }

    // MARK: - Health Data Loading

    private func loadHealthData() async {
        await dataProvider.connect()
        if dataProvider.isConnected {
            await dataProvider.refreshData()
        }
    }

    // MARK: - Health Connect Banner

    private var healthConnectBanner: some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 32))
                .foregroundColor(SanctuaryColors.Dimensions.physiological.opacity(0.6))

            Text("Connect Apple Health")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("Unlock real-time body data from your iPhone and Apple Watch. HRV, sleep analysis, activity rings, and recovery scores will replace preview data.")
                .font(.system(size: 12))
                .foregroundColor(SanctuaryColors.Text.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button(action: {
                Task { await loadHealthData() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                    Text("Connect Health")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SanctuaryColors.Dimensions.physiological)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Dimensions.physiological.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        ZStack {
            // Base void
            SanctuaryColors.Background.void
                .ignoresSafeArea()

            // Physiological dimension tint
            RadialGradient(
                colors: [
                    SanctuaryColors.Dimensions.physiological.opacity(0.15),
                    SanctuaryColors.Dimensions.physiological.opacity(0.05),
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
                Text("PHYSIOLOGICAL")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .tracking(4)

                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Text("The Body Interface")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.secondary)

                    Text("•")
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("Level \(viewModel.dimensionLevel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SanctuaryColors.Dimensions.physiological)

                    Text("•")
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("Rank: PRIMAL")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SanctuaryColors.Dimensions.physiological)
                }
            }

            Spacer()

            // Live indicator
            liveIndicator
        }
    }

    private var liveIndicator: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .modifier(PulseModifier())

                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Text("Recovery: \(Int(viewModel.data.recoveryScore))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(recoveryColor)

            Text(viewModel.data.recoveryStatus)
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

    private var recoveryColor: Color {
        if viewModel.data.recoveryScore >= 80 { return SanctuaryColors.Semantic.success }
        if viewModel.data.recoveryScore >= 60 { return SanctuaryColors.Semantic.info }
        if viewModel.data.recoveryScore >= 40 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }

    // MARK: - Detail Overlays

    @ViewBuilder
    private var detailOverlays: some View {
        // Muscle detail
        if showMuscleDetail, let muscle = selectedMuscle {
            overlayBackground
                .onTapGesture {
                    showMuscleDetail = false
                }

            MuscleDetailPanel(
                muscle: muscle,
                onDismiss: { showMuscleDetail = false }
            )
            .frame(maxWidth: 300)
            .transition(.scale.combined(with: .opacity))
        }

        // Workout detail
        if showWorkoutDetail, let workout = selectedWorkout {
            overlayBackground
                .onTapGesture {
                    showWorkoutDetail = false
                }

            WorkoutDetailCard(
                workout: workout,
                onDismiss: { showWorkoutDetail = false }
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

// MARK: - Physiological Dimension View Model

@MainActor
public final class PhysiologicalDimensionViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var data: PhysiologicalDimensionData
    @Published public var isLoading: Bool = false

    // MARK: - Computed Properties

    public var dimensionLevel: Int {
        // Would be loaded from CosmoLevelState
        19
    }

    // MARK: - Initialization

    public init(data: PhysiologicalDimensionData) {
        self.data = data
    }

    // MARK: - Actions

    public func refreshData() async {
        isLoading = true
        // Would load from SanctuaryDataProvider / HealthKit
        try? await Task.sleep(nanoseconds: 500_000_000)
        isLoading = false
    }
}

// MARK: - Compact Physiological View

/// Compact version for embedding in other views
public struct PhysiologicalDimensionCompact: View {

    let data: PhysiologicalDimensionData
    let onExpand: () -> Void

    @State private var isHovered: Bool = false

    public init(data: PhysiologicalDimensionData, onExpand: @escaping () -> Void) {
        self.data = data
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 16))
                        .foregroundColor(SanctuaryColors.Dimensions.physiological)

                    Text("PHYSIOLOGICAL")
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
                    .foregroundColor(SanctuaryColors.Dimensions.physiological)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Key metrics row
            VitalsRowCompact(
                hrv: data.currentHRV,
                rhr: data.restingHeartRate,
                recovery: data.recoveryScore,
                readiness: data.readinessScore
            )

            // Activity summary
            ActivitySummaryCompact(
                rings: data.dailyRings,
                stepCount: data.stepCount
            )

            // Sleep summary
            SleepCardCompact(sleep: data.lastNightSleep)
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(
                            isHovered ? SanctuaryColors.Dimensions.physiological.opacity(0.5) : SanctuaryColors.Glass.border,
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
struct PhysiologicalDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        PhysiologicalDimensionView(
            data: .preview,
            onBack: {}
        )
        .frame(minWidth: 1200, minHeight: 1000)
    }
}
#endif
