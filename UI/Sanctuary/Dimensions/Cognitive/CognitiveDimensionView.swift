// CosmoOS/UI/Sanctuary/Dimensions/Cognitive/CognitiveDimensionView.swift
// Cognitive Dimension View - "The Mind Core" complete dimension experience
// Phase 3: Following SANCTUARY_UI_SPEC_V2.md section 3.1

import SwiftUI

// MARK: - Cognitive Dimension View

/// The complete Cognitive Dimension view with all components
/// Layout: Mind Core (center), Deep Work Timeline (top), Side Panels, Correlation Map, Interruptions
public struct CognitiveDimensionView: View {

    // MARK: - Properties

    @StateObject private var viewModel: CognitiveDimensionViewModel
    @State private var breathingScale: CGFloat = 1.0
    @State private var selectedSession: DeepWorkSession?
    @State private var selectedCorrelation: CognitiveCorrelation?
    @State private var selectedInterruption: CognitiveInterruption?
    @State private var showSessionDetail: Bool = false
    @State private var showCorrelationDetail: Bool = false
    @State private var showInterruptionDetail: Bool = false

    let onBack: () -> Void

    // MARK: - Initialization

    public init(
        data: CognitiveDimensionData = .preview,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: CognitiveDimensionViewModel(data: data))
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

                    // Deep Work Timeline (full width)
                    CognitiveDeepWorkTimeline(
                        data: viewModel.data,
                        onSessionTap: { session in
                            selectedSession = session
                            showSessionDetail = true
                        }
                    )

                    // Central section: Mind Core + Side Panels
                    centralSection

                    // Correlation Map (full width)
                    CognitiveCorrelationMap(
                        correlations: viewModel.data.topCorrelations,
                        onCorrelationTap: { correlation in
                            selectedCorrelation = correlation
                            showCorrelationDetail = true
                        }
                    )

                    // Interruption Timeline (full width)
                    CognitiveInterruptionTimeline(
                        data: viewModel.data,
                        onInterruptionTap: { interruption in
                            selectedInterruption = interruption
                            showInterruptionDetail = true
                        }
                    )

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
            startBreathingAnimation()
        }
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        ZStack {
            // Base void
            SanctuaryColors.Background.void
                .ignoresSafeArea()

            // Cognitive dimension tint
            RadialGradient(
                colors: [
                    SanctuaryColors.Dimensions.cognitive.opacity(0.15),
                    SanctuaryColors.Dimensions.cognitive.opacity(0.05),
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
                Text("COGNITIVE")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .tracking(4)

                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Text("Mind Core")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.secondary)

                    Text("•")
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("Level \(viewModel.dimensionLevel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SanctuaryColors.Dimensions.cognitive)
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

            Text("NELO: \(String(format: "%.1f", viewModel.data.neloScore))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(viewModel.data.neloStatus == .balanced ?
                    SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.warning)

            Text(viewModel.data.neloStatus.displayName)
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

    // MARK: - Central Section

    private var centralSection: some View {
        HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.lg) {
            // Left column: Mind Core with metrics below
            VStack(spacing: SanctuaryLayout.Spacing.md) {
                CognitiveMindCore(
                    data: viewModel.data,
                    breathingScale: breathingScale
                )

                // Metrics below the Mind Core
                NELOScoreCard(data: viewModel.data)
                    .frame(maxWidth: 280)
                FocusIndexCard(data: viewModel.data)
                    .frame(maxWidth: 280)
            }
            .frame(width: 300)

            // Right section: Forecast, Journal, Prediction in a row
            HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.md) {
                CognitiveHourlyForecast(
                    windows: viewModel.data.predictedOptimalWindows,
                    currentStatus: viewModel.data.currentWindowStatus
                )
                .frame(maxWidth: 260)

                CognitiveJournalDensity(
                    insightMarkersToday: viewModel.data.journalInsightMarkersToday,
                    reflectionDepthScore: viewModel.data.reflectionDepthScore,
                    detectedThemes: viewModel.data.detectedThemes,
                    journalExcerpt: viewModel.data.journalExcerpt
                )
                .frame(maxWidth: 260)

                // Prediction card moved up here
                if let prediction = viewModel.currentPrediction {
                    CognitivePredictionCard(
                        prediction: prediction,
                        onActionTap: {
                            viewModel.handlePredictionAction()
                        }
                    )
                    .frame(maxWidth: 280)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail Overlays

    @ViewBuilder
    private var detailOverlays: some View {
        // Session detail
        if showSessionDetail, let session = selectedSession {
            overlayBackground
                .onTapGesture {
                    showSessionDetail = false
                }

            DeepWorkSessionDetail(
                session: session,
                onDismiss: { showSessionDetail = false }
            )
            .frame(maxWidth: 400)
            .transition(.scale.combined(with: .opacity))
        }

        // Correlation detail
        if showCorrelationDetail, let correlation = selectedCorrelation {
            overlayBackground
                .onTapGesture {
                    showCorrelationDetail = false
                }

            CorrelationDetailView(
                correlation: correlation,
                onDismiss: { showCorrelationDetail = false }
            )
            .frame(maxWidth: 450)
            .transition(.scale.combined(with: .opacity))
        }

        // Interruption detail
        if showInterruptionDetail, let interruption = selectedInterruption {
            overlayBackground
                .onTapGesture {
                    showInterruptionDetail = false
                }

            InterruptionDetailView(
                interruption: interruption,
                onDismiss: { showInterruptionDetail = false }
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

    // MARK: - Animation

    private func startBreathingAnimation() {
        withAnimation(
            .easeInOut(duration: 4)
            .repeatForever(autoreverses: true)
        ) {
            breathingScale = 1.02
        }
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
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Cognitive Dimension View Model

@MainActor
public final class CognitiveDimensionViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var data: CognitiveDimensionData
    @Published public var isLoading: Bool = false
    @Published public var currentPrediction: CognitivePrediction?

    // MARK: - Computed Properties

    public var dimensionLevel: Int {
        // Would be loaded from CosmoLevelState
        18
    }

    // MARK: - Initialization

    public init(data: CognitiveDimensionData) {
        self.data = data
        self.currentPrediction = generatePrediction()
    }

    // MARK: - Actions

    public func handlePredictionAction() {
        // Handle reminder/action from prediction
    }

    public func refreshData() async {
        isLoading = true
        // Would load from SanctuaryDataProvider
        try? await Task.sleep(nanoseconds: 500_000_000)
        isLoading = false
    }

    // MARK: - Prediction Generation

    private func generatePrediction() -> CognitivePrediction {
        CognitivePrediction(
            message: "If you take a 15-minute break now, your 2pm-4pm deep work session is predicted to be 23% more productive. Current cognitive load is elevated.",
            confidence: 87,
            basedOn: ["NELO score", "time since last break", "historical patterns"],
            recommendedAction: "Remind",
            impact: "+23% productivity"
        )
    }
}

// MARK: - Compact Cognitive View

/// Compact version for embedding in other views
public struct CognitiveDimensionCompact: View {

    let data: CognitiveDimensionData
    let onExpand: () -> Void

    @State private var isHovered: Bool = false

    public init(data: CognitiveDimensionData, onExpand: @escaping () -> Void) {
        self.data = data
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16))
                        .foregroundColor(SanctuaryColors.Dimensions.cognitive)

                    Text("COGNITIVE")
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
                    .foregroundColor(SanctuaryColors.Dimensions.cognitive)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Key metrics row
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                compactMetric(
                    label: "NELO",
                    value: String(format: "%.1f", data.neloScore),
                    status: data.neloStatus.displayName
                )

                compactMetric(
                    label: "Focus",
                    value: "\(Int(data.focusIndex))%",
                    status: data.focusIndex >= 80 ? "Peak" : "Normal"
                )

                compactMetric(
                    label: "Deep Work",
                    value: data.formattedDeepWork,
                    status: nil
                )

                compactMetric(
                    label: "Interrupts",
                    value: "\(data.totalInterruptionsToday)",
                    status: nil
                )
            }

            // Current window indicator
            if let window = data.primaryWindow {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("Optimal window: \(window.formattedTimeRange)")
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.secondary)

                    Text("(\(Int(window.confidence))% conf)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(
                            isHovered ? SanctuaryColors.Dimensions.cognitive.opacity(0.5) : SanctuaryColors.Glass.border,
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

    private func compactMetric(label: String, value: String, status: String?) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(SanctuaryColors.Text.primary)

            if let status = status {
                Text(status)
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CognitiveDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        CognitiveDimensionView(
            data: .preview,
            onBack: {}
        )
        .frame(minWidth: 1200, minHeight: 900)
    }
}
#endif
