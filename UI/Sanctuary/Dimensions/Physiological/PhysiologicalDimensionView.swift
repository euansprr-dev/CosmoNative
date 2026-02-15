// CosmoOS/UI/Sanctuary/Dimensions/Physiological/PhysiologicalDimensionView.swift
// Physiological Dimension View - "The Body Interface" complete dimension experience
// Onyx Design System — premium cognitive atelier aesthetic

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
        GeometryReader { geometry in
            let useSingleColumn = geometry.size.width < Layout.twoColumnBreakpoint

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
                    .frame(maxWidth: Layout.maxContentWidth)
                    .frame(maxWidth: .infinity)
                } else {
                    // Main content
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: OnyxLayout.metricGroupSpacing) {
                            // Header with back button
                            headerSection

                            // HealthKit connection banner (shown when not connected)
                            if !dataProvider.isConnected {
                                healthConnectBanner
                            }

                            bodyScannerAndVitalsSection(useSingleColumn: useSingleColumn)
                            sleepAndHRVSection(useSingleColumn: useSingleColumn)
                            activityAndWorkoutSection(useSingleColumn: useSingleColumn)

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
                        .frame(maxWidth: Layout.maxContentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
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

    private enum Layout {
        static let maxContentWidth: CGFloat = 1400
        static let twoColumnBreakpoint: CGFloat = 900
    }

    @ViewBuilder
    private func bodyScannerAndVitalsSection(useSingleColumn: Bool) -> some View {
        if useSingleColumn {
            VStack(spacing: 16) {
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
                .frame(maxWidth: .infinity)

                PhysiologicalVitalSigns(data: viewModel.data)
                    .frame(maxWidth: .infinity)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
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
                .frame(maxWidth: .infinity)

                PhysiologicalVitalSigns(data: viewModel.data)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func sleepAndHRVSection(useSingleColumn: Bool) -> some View {
        if useSingleColumn {
            VStack(spacing: 16) {
                PhysiologicalSleepAnalysis(
                    sleep: viewModel.data.lastNightSleep,
                    sleepDebt: viewModel.data.sleepDebt,
                    sleepTrend: viewModel.data.sleepTrend
                )
                .frame(maxWidth: .infinity)
                HRVTrendChart(
                    trend: viewModel.data.hrvTrend,
                    currentHRV: viewModel.data.currentHRV
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                PhysiologicalSleepAnalysis(
                    sleep: viewModel.data.lastNightSleep,
                    sleepDebt: viewModel.data.sleepDebt,
                    sleepTrend: viewModel.data.sleepTrend
                )
                .frame(maxWidth: .infinity)

                HRVTrendChart(
                    trend: viewModel.data.hrvTrend,
                    currentHRV: viewModel.data.currentHRV
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func activityAndWorkoutSection(useSingleColumn: Bool) -> some View {
        if useSingleColumn {
            VStack(spacing: 16) {
                PhysiologicalActivityRings(
                    rings: viewModel.data.dailyRings,
                    stepCount: viewModel.data.stepCount
                )
                .frame(maxWidth: .infinity)
                PhysiologicalWorkoutLog(
                    workouts: viewModel.data.workouts,
                    weeklyVolumeLoad: viewModel.data.weeklyVolumeLoad,
                    recoveryDebt: viewModel.data.recoveryDebt
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                PhysiologicalActivityRings(
                    rings: viewModel.data.dailyRings,
                    stepCount: viewModel.data.stepCount
                )
                .frame(maxWidth: .infinity)

                PhysiologicalWorkoutLog(
                    workouts: viewModel.data.workouts,
                    weeklyVolumeLoad: viewModel.data.weeklyVolumeLoad,
                    recoveryDebt: viewModel.data.recoveryDebt
                )
                .frame(maxWidth: .infinity)
            }
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
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 24))
                .foregroundColor(OnyxColors.Text.tertiary)

            Text("Connect Apple Health")
                .font(OnyxTypography.cardTitle)
                .tracking(OnyxTypography.cardTitleTracking)
                .foregroundColor(OnyxColors.Text.primary)

            Text("Unlock real-time body data from your iPhone and Apple Watch. HRV, sleep analysis, activity rings, and recovery scores will replace preview data.")
                .font(.system(size: 12))
                .foregroundColor(OnyxColors.Text.secondary)
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
                        .fill(OnyxColors.DimensionVivid.physiological)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(OnyxLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(OnyxColors.Elevation.raised)
        )
        .onyxShadow(.resting)
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        ZStack {
            // Onyx base surface
            OnyxColors.Elevation.base
                .ignoresSafeArea()

            // Subtle physiological dimension tint
            RadialGradient(
                colors: [
                    OnyxColors.DimensionVivid.physiological.opacity(0.08),
                    OnyxColors.DimensionVivid.physiological.opacity(0.03),
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
                Text("Physiological")
                    .font(OnyxTypography.viewTitle)
                    .tracking(OnyxTypography.viewTitleTracking)
                    .foregroundColor(OnyxColors.Text.primary)

                HStack(spacing: 8) {
                    Text("The Body Interface")
                        .font(.system(size: 12))
                        .foregroundColor(OnyxColors.Text.secondary)

                    Text("·")
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("Tier \(viewModel.dimensionLevel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Dimension.physiological)

                    Text("·")
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("Primal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Dimension.physiological)
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
                    .fill(OnyxColors.Accent.sage)
                    .frame(width: 6, height: 6)
                    .modifier(OnyxPulseModifier())

                Text("Live")
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Text.tertiary)
            }

            Text("Recovery: \(Int(viewModel.data.recoveryScore))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(recoveryColor)

            Text(viewModel.data.recoveryStatus)
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

    private var recoveryColor: Color {
        if viewModel.data.recoveryScore >= 80 { return OnyxColors.Accent.sage }
        if viewModel.data.recoveryScore >= 60 { return OnyxColors.DimensionVivid.physiological }
        if viewModel.data.recoveryScore >= 40 { return OnyxColors.Accent.amber }
        return OnyxColors.Accent.rose
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
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 16))
                        .foregroundColor(OnyxColors.Dimension.physiological)

                    Text("Physiological")
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
                    .foregroundColor(OnyxColors.Dimension.physiological)
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
