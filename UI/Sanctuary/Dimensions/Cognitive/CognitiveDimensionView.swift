// CosmoOS/UI/Sanctuary/Dimensions/Cognitive/CognitiveDimensionView.swift
// Cognitive Dimension View - "The Mind Core" complete dimension experience
// Onyx Design System — premium cognitive atelier aesthetic

import SwiftUI

// MARK: - Cognitive Dimension View

/// The complete Cognitive Dimension view with all components
/// Layout: Mind Core (center), Deep Work Timeline (top), Side Panels, Correlation Map, Interruptions
public struct CognitiveDimensionView: View {

    // MARK: - Properties

    @StateObject private var viewModel: CognitiveDimensionViewModel
    @StateObject private var dataProvider = CognitiveDataProvider()
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
        data: CognitiveDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: CognitiveDimensionViewModel(data: data))
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

                        // Deep Work Timeline (full width)
                        CognitiveDeepWorkTimeline(
                            data: viewModel.data,
                            onSessionTap: { session in
                                selectedSession = session
                                showSessionDetail = true
                            }
                        )

                        // Central section: Mind Core + Side Panels
                        centralSection(useSingleColumn: useSingleColumn)

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
            startBreathingAnimation()
        }
        .task {
            await dataProvider.refreshData()
            viewModel.data = dataProvider.data
        }
    }

    private enum Layout {
        static let maxContentWidth: CGFloat = 1400
        static let twoColumnBreakpoint: CGFloat = 900
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        ZStack {
            // Onyx base surface
            OnyxColors.Elevation.base
                .ignoresSafeArea()

            // Subtle cognitive dimension tint
            RadialGradient(
                colors: [
                    OnyxColors.DimensionVivid.cognitive.opacity(0.08),
                    OnyxColors.DimensionVivid.cognitive.opacity(0.03),
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
                Text("Cognitive")
                    .font(OnyxTypography.viewTitle)
                    .tracking(OnyxTypography.viewTitleTracking)
                    .foregroundColor(OnyxColors.Text.primary)

                HStack(spacing: 8) {
                    Text("Mind Core")
                        .font(.system(size: 12))
                        .foregroundColor(OnyxColors.Text.secondary)

                    Text("·")
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("Tier \(viewModel.dimensionLevel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Dimension.cognitive)
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

            Text("NELO: \(String(format: "%.1f", viewModel.data.neloScore))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(viewModel.data.neloStatus == .balanced ?
                    OnyxColors.Accent.sage : OnyxColors.Accent.rose)

            Text(viewModel.data.neloStatus.displayName)
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

    // MARK: - Central Section

    @ViewBuilder
    private func centralSection(useSingleColumn: Bool) -> some View {
        if useSingleColumn {
            VStack(spacing: 16) {
                CognitiveMindCore(
                    data: viewModel.data,
                    breathingScale: breathingScale
                )

                NELOScoreCard(data: viewModel.data)
                    .frame(maxWidth: .infinity)
                FocusIndexCard(data: viewModel.data)
                    .frame(maxWidth: .infinity)

                CognitiveHourlyForecast(
                    windows: viewModel.data.predictedOptimalWindows,
                    currentStatus: viewModel.data.currentWindowStatus
                )
                .frame(maxWidth: .infinity)

                CognitiveJournalDensity(
                    insightMarkersToday: viewModel.data.journalInsightMarkersToday,
                    reflectionDepthScore: viewModel.data.reflectionDepthScore,
                    detectedThemes: viewModel.data.detectedThemes,
                    journalExcerpt: viewModel.data.journalExcerpt
                )
                .frame(maxWidth: .infinity)

                if let prediction = viewModel.currentPrediction {
                    CognitivePredictionCard(
                        prediction: prediction,
                        onActionTap: {
                            viewModel.handlePredictionAction()
                        }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                // Left column: Mind Core with metrics below
                VStack(spacing: 12) {
                    CognitiveMindCore(
                        data: viewModel.data,
                        breathingScale: breathingScale
                    )

                    NELOScoreCard(data: viewModel.data)
                        .frame(maxWidth: .infinity)
                    FocusIndexCard(data: viewModel.data)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                // Right section: Forecast, Journal, Prediction stacked
                VStack(spacing: 12) {
                    CognitiveHourlyForecast(
                        windows: viewModel.data.predictedOptimalWindows,
                        currentStatus: viewModel.data.currentWindowStatus
                    )
                    .frame(maxWidth: .infinity)

                    CognitiveJournalDensity(
                        insightMarkersToday: viewModel.data.journalInsightMarkersToday,
                        reflectionDepthScore: viewModel.data.reflectionDepthScore,
                        detectedThemes: viewModel.data.detectedThemes,
                        journalExcerpt: viewModel.data.journalExcerpt
                    )
                    .frame(maxWidth: .infinity)

                    if let prediction = viewModel.currentPrediction {
                        CognitivePredictionCard(
                            prediction: prediction,
                            onActionTap: {
                                viewModel.handlePredictionAction()
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
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
        let provider = CognitiveDataProvider()
        await provider.refreshData()
        data = provider.data
        currentPrediction = generatePrediction()
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

/// Compact version for embedding in other views — Onyx design
public struct CognitiveDimensionCompact: View {

    let data: CognitiveDimensionData
    let onExpand: () -> Void

    @State private var isHovered: Bool = false

    public init(data: CognitiveDimensionData, onExpand: @escaping () -> Void) {
        self.data = data
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16))
                        .foregroundColor(OnyxColors.Dimension.cognitive)

                    Text("Cognitive")
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
                    .foregroundColor(OnyxColors.Dimension.cognitive)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Key metrics row
            HStack(spacing: 24) {
                compactMetric(
                    label: "NELO",
                    value: String(format: "%.1f", data.neloScore),
                    status: data.neloStatus.displayName
                )

                compactMetric(
                    label: "Focus",
                    value: "\(Int(data.focusIndex))",
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
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(OnyxColors.Accent.amber)

                    Text("Optimal window: \(window.formattedTimeRange)")
                        .font(.system(size: 11))
                        .foregroundColor(OnyxColors.Text.secondary)

                    Text("(\(Int(window.confidence))% conf)")
                        .font(OnyxTypography.micro)
                        .foregroundColor(OnyxColors.Text.tertiary)
                }
            }
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

    private func compactMetric(label: String, value: String, status: String?) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(OnyxTypography.micro)
                .foregroundColor(OnyxColors.Text.tertiary)

            Text(value)
                .font(.system(size: 16, weight: .light))
                .foregroundColor(OnyxColors.Text.primary)

            if let status = status {
                Text(status)
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Text.secondary)
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
