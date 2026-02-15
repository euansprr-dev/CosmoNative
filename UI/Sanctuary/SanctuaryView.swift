// CosmoOS/UI/Sanctuary/SanctuaryView.swift
// Sanctuary View - Neural interface dashboard for holistic self-understanding
// Apple-level quality with Metal shaders and fluid animations
// Phase 2+9+10: Complete Home Sanctuary with Sound, Haptics, and Living Intelligence

import SwiftUI
import Combine

// MARK: - Sanctuary View Mode

/// Current interaction mode for the Sanctuary
public enum SanctuaryMode: String, CaseIterable {
    case overview      // Hero orb with dimension summary
    case dimension     // Expanded single dimension view
    case insight       // Focus on a specific insight
    case compare       // Compare two dimensions
}

// MARK: - Sanctuary View

/// Main Sanctuary dashboard view with Living Intelligence integration.
///
/// Integrations:
/// - SanctuaryDataProvider: Live-updating dimension and metric data
/// - LivingIntelligenceEngine: Telepathic insights that evolve over time
/// - SanctuarySoundscape: Ambient audio and feedback sounds
/// - SanctuaryHaptics: Tactile feedback for interactions
/// - Voice Actions: Responds to FunctionGemma navigation commands
public struct SanctuaryView: View {

    // MARK: - State

    @StateObject private var dataProvider: SanctuaryDataProvider
    @StateObject private var dimensionStream: DimensionStateStream
    @StateObject private var insightStream: InsightStream
    @StateObject private var livingInsightStream: LivingInsightStream
    @StateObject private var choreographer = SanctuaryAnimationChoreographer()
    @StateObject private var transitionManager = SanctuaryTransitionManager()

    // DI-based glow: observe the shared DimensionIndexEngine for live scores
    @ObservedObject private var dimensionIndexEngine = DimensionIndexEngine.shared

    @State private var mode: SanctuaryMode = .overview
    @State private var selectedDimension: LevelDimension?
    @State private var selectedInsight: CorrelationInsight?
    @State private var selectedLivingInsight: LivingInsight?
    @State private var showingDimensionDetail = false
    // animationPhase is provided by choreographer.animationPhase
    @State private var showNewInsightBadge = false

    // Metal rendering enabled
    @State private var useMetalRendering = true

    // Satellite navigation state
    @State private var plannerumHovered = false
    @State private var thinkspaceHovered = false
    @State private var showingPlannerum = false

    // Settings
    @State private var showingSanctuarySettings = false

    // Bottom summary hover
    @State private var summaryHovered = false

    // Notification subscriptions
    @State private var cancellables = Set<AnyCancellable>()

    // Animation timer reference (to properly invalidate)
    @State private var animationTimer: Timer?

    // MARK: - Initialization

    public init() {
        let provider = SanctuaryDataProvider()
        _dataProvider = StateObject(wrappedValue: provider)
        _dimensionStream = StateObject(wrappedValue: DimensionStateStream(provider: provider))
        _insightStream = StateObject(wrappedValue: InsightStream(provider: provider))
        _livingInsightStream = StateObject(wrappedValue: LivingInsightStream(provider: provider))
    }

    // MARK: - Layout Constants (from SanctuaryTokens)

    private enum Layout {
        static let maxContentWidth: CGFloat = 720
        static let orbAreaSize: CGFloat = SanctuaryLayout.Sizing.heroOrbArea  // 480pt per spec
        static let headerHeight: CGFloat = 120  // Per spec
        static let constellationHeight: CGFloat = 480  // Per spec
        static let insightStreamHeight: CGFloat = 140  // Per spec
        static let sectionSpacing: CGFloat = SanctuaryLayout.Spacing.xxxl
        static let orbRadius: CGFloat = SanctuaryLayout.Sizing.dimensionOrbRadius  // 190pt per spec
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background — Onyx void base
                OnyxColors.Elevation.void
                    .ignoresSafeArea()

                // Transition background overlay
                SanctuaryTransitionBackground(manager: transitionManager)

                // Aurora overlay — reduced to ~8-10% opacity per Onyx spec
                if useMetalRendering {
                    SanctuaryAuroraMetalView(
                        colorA: OnyxColors.Dimension.cognitive,
                        colorB: OnyxColors.Dimension.creative,
                        colorC: OnyxColors.Dimension.physiological,
                        intensity: 0.12,
                        speed: 0.4
                    )
                    .opacity(choreographer.backgroundOpacity * 0.4)
                    .ignoresSafeArea()
                }

                // Subtle radial vignette
                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.05)],
                    center: .center,
                    startRadius: 200,
                    endRadius: 600
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // SATELLITE CONNECTION THREADS (behind constellation)
                // These connect Plannerum and Thinkspace to the hero orb
                GeometryReader { satelliteGeometry in
                    let heroCenter = CGPoint(
                        x: satelliteGeometry.size.width / 2,
                        y: satelliteGeometry.size.height * 0.45
                    )
                    let plannerumPos = CGPoint(
                        x: satelliteGeometry.size.width * SanctuaryLayout.plannerumPositionX,
                        y: satelliteGeometry.size.height * SanctuaryLayout.satellitePositionY
                    )
                    let thinkspacePos = CGPoint(
                        x: satelliteGeometry.size.width * SanctuaryLayout.thinkspacePositionX,
                        y: satelliteGeometry.size.height * SanctuaryLayout.satellitePositionY
                    )

                    SatelliteConnectionsView(
                        heroCenter: heroCenter,
                        plannerumPosition: plannerumPos,
                        thinkspacePosition: thinkspacePos,
                        plannerumActive: plannerumHovered,
                        thinkspaceActive: thinkspaceHovered,
                        animationPhase: choreographer.animationPhase
                    )
                    .opacity(choreographer.backgroundOpacity * 0.25)  // Satellite connection: 0.04 base opacity
                }
                .allowsHitTesting(false)

                // SATELLITE NODES (Plannerum left, Thinkspace right)
                // FIX: Hover is now handled inside SatelliteNodeView with proper contentShape
                GeometryReader { nodeGeometry in
                    // Plannerum node (left)
                    SatelliteNodeView(
                        type: .plannerum,
                        isHovered: plannerumHovered,
                        animationPhase: choreographer.animationPhase,
                        badgeCount: inboxBadgeCount,
                        onTap: {
                            handlePlannerumTap()
                        },
                        onHoverChanged: { hovering in
                            withAnimation(SanctuarySprings.hover) {
                                plannerumHovered = hovering
                            }
                        }
                    )
                    .position(
                        x: nodeGeometry.size.width * SanctuaryLayout.plannerumPositionX,
                        y: nodeGeometry.size.height * SanctuaryLayout.satellitePositionY
                    )
                    .opacity(choreographer.backgroundOpacity * 0.85 * transitionManager.otherOrbsOpacity)
                    .scaleEffect(0.92)  // Slightly smaller for depth

                    // Thinkspace node (right)
                    SatelliteNodeView(
                        type: .thinkspace,
                        isHovered: thinkspaceHovered,
                        animationPhase: choreographer.animationPhase,
                        badgeCount: nil,  // TODO: Canvas block count
                        onTap: {
                            handleThinkspaceTap()
                        },
                        onHoverChanged: { hovering in
                            withAnimation(SanctuarySprings.hover) {
                                thinkspaceHovered = hovering
                            }
                        }
                    )
                    .position(
                        x: nodeGeometry.size.width * SanctuaryLayout.thinkspacePositionX,
                        y: nodeGeometry.size.height * SanctuaryLayout.satellitePositionY
                    )
                    .opacity(choreographer.backgroundOpacity * 0.85 * transitionManager.otherOrbsOpacity)
                    .scaleEffect(0.92)  // Slightly smaller for depth
                }
                .allowsHitTesting(transitionManager.state == .home)  // Disable satellite hit testing when dimension is active

                // Main content container
                // Disable hit testing when dimension detail is active to prevent tap-through
                VStack(spacing: 0) {
                    // HEADER ZONE (Top 120pt) - Phase 2 component
                    SanctuaryHeaderView(
                        cosmoIndex: dataProvider.state?.cosmoIndex,
                        liveMetrics: dataProvider.state?.liveMetrics,
                        showBackButton: transitionManager.state != .home || showingPlannerum,
                        onBack: {
                            if showingPlannerum {
                                withAnimation(SanctuarySprings.smooth) {
                                    showingPlannerum = false
                                }
                            } else {
                                Task {
                                    await transitionManager.transitionToHome()
                                }
                            }
                        }
                    )
                    .opacity(choreographer.backgroundOpacity)

                    Spacer(minLength: Layout.sectionSpacing)

                    // CONSTELLATION ZONE (Center 480pt)
                    ZStack {
                        // Connection lines between dimensions
                        connectionLinesView
                            .sanctuaryTransitionConnections(manager: transitionManager)

                        // Dimension orbs arranged in hexagon
                        dimensionOrbsView
                            .opacity(choreographer.dimensionsOpacity)
                            .sanctuaryTransitionOther(manager: transitionManager)

                        // Hero orb in center - Phase 2 enhanced version
                        SanctuaryHeroOrb(
                            state: dataProvider.state?.cosmoIndex,
                            liveMetrics: dataProvider.state?.liveMetrics,
                            breathingScale: choreographer.breathingScale,
                            isActive: dataProvider.state?.liveMetrics.currentHRV != nil
                        )
                        .scaleEffect(choreographer.heroScale)
                        .opacity(choreographer.heroOpacity)
                        .sanctuaryTransitionHero(manager: transitionManager)
                        .onTapGesture {
                            handleHeroOrbTap()
                        }
                    }
                    .frame(width: Layout.orbAreaSize, height: Layout.orbAreaSize)

                    Spacer(minLength: SanctuaryLayout.Spacing.sm)

                    // THIS WEEK SUMMARY - Hidden by default, hover to reveal
                    thisWeekSummaryHoverView
                        .opacity(choreographer.dimensionsOpacity)
                        .sanctuaryTransitionInsights(manager: transitionManager)

                    Spacer(minLength: SanctuaryLayout.Spacing.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(transitionManager.state == .home || transitionManager.state == .returning)

                // Dimension detail view (shown during/after transition)
                // contentShape + background prevent taps from falling through to constellation
                if case .dimension(let dimension) = transitionManager.state {
                    dimensionDetailView(for: dimension)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .sanctuaryTransitionContent(manager: transitionManager)
                }
            }
        }
        .onAppear {
            Task { @MainActor in
                // Start animations
                await choreographer.playEntrySequence()

                // Start Living Intelligence
                await dataProvider.startLivingIntelligence()

                // Start soundscape
                do {
                    try await SanctuarySoundscape.shared.start()
                    await SanctuarySoundscape.shared.startAmbient()
                } catch {
                    print("[Sanctuary] Failed to start soundscape: \(error)")
                }
            }
            dataProvider.startLiveUpdates()
            // Note: choreographer.startContinuousAnimations() handles animation timing
            // We don't need a separate timer - animationPhase is updated by choreographer
            setupVoiceNotifications()
        }
        .onDisappear {
            // Stop animation timer if it exists
            animationTimer?.invalidate()
            animationTimer = nil

            choreographer.stopContinuousAnimations()
            dataProvider.stopLiveUpdates()
            dataProvider.stopLivingIntelligence()

            Task {
                await SanctuarySoundscape.shared.stop()
            }
        }
        .onChange(of: dataProvider.hasNewInsights) { _, hasNew in
            if hasNew {
                showNewInsightBadge = true
                Task {
                    await SanctuarySoundscape.shared.playInsightSound(isGrail: false)
                    SanctuaryHaptics.shared.insightReveal()
                }
            }
        }
        .overlay {
            // Desktop-style floating panel for dimension details
            if showingDimensionDetail, let dimension = selectedDimension {
                ZStack {
                    // Backdrop
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingDimensionDetail = false
                            }
                        }

                    // Floating panel
                    DimensionDetailView(
                        dimension: dimension,
                        state: dimensionStream.state(for: dimension),
                        insights: insightStream.insights.filter { insight in
                            metricsForDimension(dimension).contains(insight.sourceMetric) ||
                            metricsForDimension(dimension).contains(insight.targetMetric)
                        },
                        onDismiss: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingDimensionDetail = false
                            }
                        }
                    )
                    .frame(maxWidth: 560, maxHeight: 720)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.4), radius: 40, x: 0, y: 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingDimensionDetail)
        .overlay(alignment: .topTrailing) {
            // Sanctuary settings gear — 18pt, tertiary, only visible on home
            if transitionManager.state == .home && !showingPlannerum {
                Button(action: { showingSanctuarySettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(OnyxColors.Text.tertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, SanctuaryLayout.Spacing.lg)
                .padding(.top, SanctuaryLayout.Spacing.lg)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingSanctuarySettings) {
            SanctuarySettingsView()
                .frame(width: 720, height: 540)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var sanctuaryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sanctuary")
                    .font(OnyxTypography.viewTitle)
                    .tracking(OnyxTypography.viewTitleTracking)
                    .foregroundColor(OnyxColors.Text.primary)

                if let state = dataProvider.state {
                    Text("Tier \(SanctuaryHeaderView.romanNumeral(for: state.cosmoIndex.level)) \u{00B7} \(state.cosmoIndex.rank)")
                        .font(OnyxTypography.label)
                        .tracking(OnyxTypography.labelTracking)
                        .foregroundColor(OnyxColors.Text.secondary)
                }
            }

            Spacer()

            // Live indicator
            if dataProvider.state?.liveMetrics.currentHRV != nil {
                HStack(spacing: 6) {
                    Circle()
                        .fill(OnyxColors.Accent.sage)
                        .frame(width: 6, height: 6)

                    Text("Live")
                        .font(OnyxTypography.micro)
                        .foregroundColor(OnyxColors.Accent.sage)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(OnyxColors.Accent.sage.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Dimension Orbs

    private func dimensionOrbs(orbAreaSize: CGFloat) -> some View {
        let center = CGPoint(x: orbAreaSize / 2, y: orbAreaSize / 2)

        return ZStack {
            ForEach(LevelDimension.allCases, id: \.self) { dimension in
                positionedDimensionOrb(dimension: dimension, center: center, radius: Layout.orbRadius)
            }
        }
    }

    private func positionedDimensionOrb(dimension: LevelDimension, center: CGPoint, radius: CGFloat) -> some View {
        let index = LevelDimension.allCases.firstIndex(of: dimension) ?? 0
        let count = LevelDimension.allCases.count
        let angle: Double = (Double(index) / Double(count)) * 2 * .pi - .pi / 2
        let x: CGFloat = center.x + radius * cos(angle)
        let y: CGFloat = center.y + radius * sin(angle)

        return DimensionOrbGlowWrapper(
            dimension: dimension,
            dimensionState: dimensionStream.state(for: dimension),
            isSelected: selectedDimension == dimension,
            animationPhase: choreographer.animationPhase
        )
        .sanctuaryTransitionSelected(manager: transitionManager, dimension: dimension)
        .position(x: x, y: y)
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                if selectedDimension == dimension {
                    let normalizedPosition = CGPoint(x: x / Layout.orbAreaSize, y: y / Layout.orbAreaSize)
                    handleDimensionTap(dimension, position: normalizedPosition)
                } else {
                    selectedDimension = dimension
                }
            }
        }
    }

    private func connectionLines(orbAreaSize: CGFloat) -> some View {
        let center = CGPoint(x: orbAreaSize / 2, y: orbAreaSize / 2)
        let radius = Layout.orbRadius

        return Canvas { context, size in
            let dimensions = LevelDimension.allCases

            for i in 0..<dimensions.count {
                let angle1 = (Double(i) / Double(dimensions.count)) * 2 * .pi - .pi / 2
                let x1 = center.x + radius * cos(angle1)
                let y1 = center.y + radius * sin(angle1)

                let nextIndex = (i + 1) % dimensions.count
                let angle2 = (Double(nextIndex) / Double(dimensions.count)) * 2 * .pi - .pi / 2
                let x2 = center.x + radius * cos(angle2)
                let y2 = center.y + radius * sin(angle2)

                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x2, y: y2))

                // White-only lines at low opacity (0.07)
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.07)),
                    lineWidth: 0.5
                )
            }
        }
        .frame(width: orbAreaSize, height: orbAreaSize)
    }

    // MARK: - Hero Orb Overlay

    @ViewBuilder
    private var heroOrbOverlay: some View {
        // Cosmo Index number only — no "CI" label, hover tooltip shows "Cosmo Index"
        if let state = dataProvider.state?.cosmoIndex {
            Text("\(state.level)")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundColor(OnyxColors.Text.primary)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .help("Cosmo Index")
        }

        // Live HRV indicator
        if let hrv = dataProvider.state?.liveMetrics.currentHRV {
            VStack {
                Spacer()

                HStack(spacing: SanctuaryLayout.Spacing.xs) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundColor(OnyxColors.Accent.rose)

                    Text("\(Int(hrv))")
                        .font(OnyxTypography.micro)
                        .foregroundColor(OnyxColors.Text.secondary)
                }
                .padding(.horizontal, SanctuaryLayout.Spacing.sm)
                .padding(.vertical, SanctuaryLayout.Spacing.xs)
                .background(OnyxColors.Elevation.raised)
                .clipShape(Capsule())
                .offset(y: SanctuaryLayout.Sizing.heroOrb * 0.35)
            }
        }
    }

    // MARK: - Metal Connection Lines

    private func metalConnectionLines(orbAreaSize: CGFloat) -> some View {
        let center = CGPoint(x: orbAreaSize / 2, y: orbAreaSize / 2)
        let radius = Layout.orbRadius
        let dimensions = LevelDimension.allCases
        let count = dimensions.count

        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let nextIndex = (i + 1) % count
                let isAdjacentToSelected = selectedDimension == dimensions[i] || selectedDimension == dimensions[nextIndex]
                let lineOpacity: Double = isAdjacentToSelected ? 0.25 : 0.07

                connectionLineView(
                    index: i,
                    center: center,
                    radius: radius,
                    dimensions: dimensions,
                    count: count,
                    opacity: lineOpacity
                )
                .animation(OnyxSpring.standard, value: selectedDimension)
            }
        }
        .frame(width: orbAreaSize, height: orbAreaSize)
    }

    private func connectionLineView(
        index i: Int,
        center: CGPoint,
        radius: CGFloat,
        dimensions: [LevelDimension],
        count: Int,
        opacity: Double = 0.07
    ) -> some View {
        let angle1 = (Double(i) / Double(count)) * 2 * .pi - .pi / 2
        let x1 = center.x + radius * Darwin.cos(angle1)
        let y1 = center.y + radius * Darwin.sin(angle1)

        let nextIndex = (i + 1) % count
        let angle2 = (Double(nextIndex) / Double(count)) * 2 * .pi - .pi / 2
        let x2 = center.x + radius * Darwin.cos(angle2)
        let y2 = center.y + radius * Darwin.sin(angle2)

        // White-only connection lines — brighten to 0.25 on adjacent orb hover
        return SanctuaryConnectionLine(
            from: CGPoint(x: x1, y: y1),
            to: CGPoint(x: x2, y: y2),
            color1: Color.white,
            color2: Color.white,
            glowIntensity: opacity,
            isAnimated: true
        )
    }

    // MARK: - Hero Orb Tap Handler

    private func handleHeroOrbTap() {
        choreographer.pulseHeroOrb()
    }

    // MARK: - Phase 2 View Components

    /// Connection lines view (uses Metal or Canvas)
    private var connectionLinesView: some View {
        Group {
            if useMetalRendering {
                metalConnectionLines(orbAreaSize: Layout.orbAreaSize)
            } else {
                connectionLines(orbAreaSize: Layout.orbAreaSize)
            }
        }
    }

    /// Dimension orbs arranged in hexagon
    private var dimensionOrbsView: some View {
        dimensionOrbs(orbAreaSize: Layout.orbAreaSize)
    }

    // MARK: - This Week Summary

    /// Hover-to-reveal summary — no hint text, reveals on hover
    private var thisWeekSummaryHoverView: some View {
        VStack(spacing: 0) {
            if summaryHovered {
                thisWeekSummaryCard
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(height: summaryHovered ? nil : 20)
        .padding(.horizontal, SanctuaryLayout.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(OnyxSpring.standard) {
                summaryHovered = hovering
            }
        }
    }

    /// Full "This Week" summary card (shown on hover)
    private var thisWeekSummaryCard: some View {
        let overallDI = dimensionIndexEngine.sanctuaryLevel
        let trend = dimensionIndexEngine.overallTrend
        let indices = dimensionIndexEngine.dimensionIndices
        let topDimension = indices.max(by: { $0.value.score < $1.value.score })

        return SanctuaryCard(size: .quarter, title: "This week") {
            HStack(spacing: SanctuaryLayout.Spacing.lg) {
                HStack(alignment: .firstTextBaseline, spacing: SanctuaryLayout.Spacing.xs) {
                    Text("\(Int(overallDI))")
                        .font(SanctuaryTypography.metricLarge)
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Image(systemName: trend.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(trend.color)
                }

                Rectangle()
                    .fill(SanctuaryColors.Glass.borderSubtle)
                    .frame(width: 1, height: 40)

                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    if let top = topDimension {
                        HStack(spacing: SanctuaryLayout.Spacing.xs) {
                            Circle()
                                .fill(SanctuaryColors.color(for: top.key))
                                .frame(width: 6, height: 6)

                            Text(top.key.displayName)
                                .font(SanctuaryTypography.labelSmall)
                                .foregroundColor(SanctuaryColors.Text.secondary)

                            Text("leading")
                                .font(SanctuaryTypography.labelSmall)
                                .foregroundColor(SanctuaryColors.Text.tertiary)
                        }
                    }

                    Text(thisWeekInsightText)
                        .font(SanctuaryTypography.caption)
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// Generate a one-line insight based on current DI data
    private var thisWeekInsightText: String {
        let overallDI = dimensionIndexEngine.sanctuaryLevel
        let trend = dimensionIndexEngine.overallTrend
        let indices = dimensionIndexEngine.dimensionIndices

        // Find weakest dimension with data
        let weakest = indices
            .filter { $0.value.confidence >= 0.3 }
            .min(by: { $0.value.score < $1.value.score })

        if overallDI < 1 {
            return "Gathering data across dimensions..."
        }

        switch trend {
        case .rising:
            return "Momentum building across your dimensions"
        case .falling:
            if let weak = weakest {
                return "\(weak.key.displayName) needs attention this week"
            }
            return "Consider rebalancing your focus areas"
        case .stable:
            if overallDI > 70 {
                return "Strong consistency across all dimensions"
            } else if let weak = weakest {
                return "Boost \(weak.key.displayName) to raise your index"
            }
            return "Steady rhythm — small gains compound"
        }
    }

    /// Insight stream carousel (Phase 2+10 with Living Intelligence)
    private var insightStreamView: some View {
        Group {
            // Prefer living insights (telepathic, lifecycle-managed)
            if !livingInsightStream.insights.isEmpty {
                VStack(spacing: SanctuaryLayout.Spacing.sm) {
                    // New insight badge
                    if showNewInsightBadge {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text("New insights")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(SanctuaryColors.XP.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SanctuaryColors.XP.primary.opacity(0.2))
                        .clipShape(Capsule())
                        .transition(.scale.combined(with: .opacity))
                    }

                    SanctuaryInsightStream(
                        insights: livingInsightStream.insights.map { InsightCardModel.fromLiving($0) },
                        onCardTap: { card in
                            // Handle living insight card tap
                            if let insight = livingInsightStream.insights.first(where: { $0.id == card.id }) {
                                selectedLivingInsight = insight
                                SanctuaryHaptics.shared.nodeSelect()
                                Task {
                                    await SanctuarySoundscape.shared.playFeedback(.nodeTap)
                                    await livingInsightStream.markFeaturedViewed()
                                }
                            }
                        }
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            } else if let insights = dataProvider.state?.topInsights, !insights.isEmpty {
                // Fallback to regular insights
                SanctuaryInsightStream(
                    insights: insights.map { InsightCardModel.from($0) },
                    onCardTap: { card in
                        if let insight = dataProvider.state?.topInsights.first(where: { $0.uuid == card.id }) {
                            selectedInsight = insight
                            SanctuaryHaptics.shared.nodeSelect()
                        }
                    }
                )
                .frame(maxWidth: .infinity)
            } else {
                // Placeholder when no insights
                VStack(spacing: SanctuaryLayout.Spacing.md) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("Insights will appear as patterns emerge")
                        .font(SanctuaryTypography.body)
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    if dataProvider.isIntelligenceSyncing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: SanctuaryColors.Text.tertiary))
                            .scaleEffect(0.8)
                    }
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .sanctuaryGlass(.subtle)
                .padding(.horizontal, SanctuaryLayout.Spacing.xxl)
                .padding(.bottom, SanctuaryLayout.Spacing.xxxl)
            }
        }
        .animation(.easeInOut, value: showNewInsightBadge)
    }

    /// Dimension detail view (shown after transition) - routes to actual dimension views
    @ViewBuilder
    private func dimensionDetailView(for dimension: LevelDimension) -> some View {
        switch dimension {
        case .cognitive:
            CognitiveDimensionView(onBack: handleDimensionBack)

        case .creative:
            CreativeDimensionView(onBack: handleDimensionBack)

        case .physiological:
            PhysiologicalDimensionView(onBack: handleDimensionBack)

        case .behavioral:
            BehavioralDimensionView(onBack: handleDimensionBack)

        case .knowledge:
            KnowledgeDimensionView(onBack: handleDimensionBack)

        case .reflection:
            ReflectionDimensionView(onBack: handleDimensionBack)
        }
    }

    /// Handle back button from dimension views
    private func handleDimensionBack() {
        Task { @MainActor in
            await transitionManager.transitionToHome()
            selectedDimension = nil
        }
    }

    /// Handle dimension orb tap with transition
    private func handleDimensionTap(_ dimension: LevelDimension, position: CGPoint) {
        // Play haptic and sound
        SanctuaryHaptics.shared.dimensionTransition()
        Task {
            await SanctuarySoundscape.shared.transitionToDimension(
                SanctuaryDimension(rawValue: dimension.rawValue) ?? .cognitive
            )
            await transitionManager.transitionToDimension(dimension, fromPosition: position)
        }
    }

    // MARK: - Voice Notification Handlers

    /// Setup listeners for voice-triggered navigation commands
    private func setupVoiceNotifications() {
        // Dimension navigation
        NotificationCenter.default.publisher(for: .sanctuaryDimensionRequested)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                if let dimensionStr = notification.userInfo?["dimension"] as? String,
                   let dimension = LevelDimension(rawValue: dimensionStr) {
                    // Trigger dimension navigation
                    selectedDimension = dimension
                    SanctuaryHaptics.shared.dimensionTransition()
                    Task {
                        await SanctuarySoundscape.shared.transitionToDimension(
                            SanctuaryDimension(rawValue: dimensionStr) ?? .cognitive
                        )
                        let center = CGPoint(x: 0.5, y: 0.5)
                        await transitionManager.transitionToDimension(dimension, fromPosition: center)
                    }
                }
            }
            .store(in: &cancellables)

        // Home navigation
        NotificationCenter.default.publisher(for: .sanctuaryHomeRequested)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                SanctuaryHaptics.shared.panelClose()
                Task {
                    await SanctuarySoundscape.shared.returnToHome()
                    await transitionManager.transitionToHome()
                }
            }
            .store(in: &cancellables)

        // Panel toggle
        NotificationCenter.default.publisher(for: .sanctuaryPanelToggleRequested)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                let show = notification.userInfo?["show"] as? Bool ?? true
                if show {
                    SanctuaryHaptics.shared.panelOpen()
                    Task { await SanctuarySoundscape.shared.playTransition(.panelOpen) }
                } else {
                    SanctuaryHaptics.shared.panelClose()
                    Task { await SanctuarySoundscape.shared.playTransition(.panelClose) }
                }
            }
            .store(in: &cancellables)

        // Mood log
        NotificationCenter.default.publisher(for: .moodLogRequested)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                if let valence = notification.userInfo?["valence"] as? Double,
                   let energy = notification.userInfo?["energy"] as? Double {
                    SanctuaryHaptics.shared.moodLog(valence: valence, energy: energy)
                    Task { await SanctuarySoundscape.shared.playMoodLogSound(valence: valence, energy: energy) }
                }
            }
            .store(in: &cancellables)

        // Meditation session
        NotificationCenter.default.publisher(for: .meditationSessionRequested)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                SanctuaryHaptics.shared.meditationStart()
            }
            .store(in: &cancellables)

        // Journal entry
        NotificationCenter.default.publisher(for: .journalEntryRequested)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                SanctuaryHaptics.shared.journalOpen()
            }
            .store(in: &cancellables)
    }

    // MARK: - Animation
    // Animation is now handled entirely by SanctuaryAnimationChoreographer
    // No separate timer needed - choreographer.animationPhase provides the phase value

    // MARK: - Helpers

    private func metricsForDimension(_ dimension: LevelDimension) -> Set<String> {
        switch dimension {
        case .cognitive:
            return ["deep_work_minutes", "deep_work_quality", "focus_score", "tasks_completed"]
        case .creative:
            return ["words_written", "writing_minutes", "daily_word_count", "content_reach", "content_engagement"]
        case .physiological:
            return ["hrv", "resting_hr", "sleep_hours", "deep_sleep_minutes", "readiness_score", "workout_minutes"]
        case .behavioral:
            return ["tasks_completed", "sleep_schedule_deviation"]
        case .knowledge:
            return ["xp_earned"]
        case .reflection:
            return ["journal_entries", "journal_word_count", "emotional_valence", "emotional_energy"]
        }
    }

    // MARK: - Satellite Navigation

    /// Computed inbox badge count for Plannerum satellite
    /// Shows total uncommitted items across all inboxes
    private var inboxBadgeCount: Int? {
        // TODO: Connect to actual inbox data from ATOM system
        // For now, return nil to hide badge
        return nil
    }

    /// Handle tap on Plannerum satellite node
    /// Triggers transition to the planning realm
    private func handlePlannerumTap() {
        SanctuaryHaptics.shared.nodeSelect()

        Task {
            await SanctuarySoundscape.shared.playFeedback(.nodeTap)
        }

        // Post notification for MainView to handle navigation
        NotificationCenter.default.post(
            name: .sanctuaryPlannerumRequested,
            object: nil
        )

        // Animate transition
        withAnimation(SanctuarySprings.cinematic) {
            showingPlannerum = true
        }
    }

    /// Handle tap on Thinkspace satellite node
    /// Triggers transition to the creative canvas
    private func handleThinkspaceTap() {
        SanctuaryHaptics.shared.nodeSelect()

        Task {
            await SanctuarySoundscape.shared.playFeedback(.nodeTap)
        }

        // Post notification for MainView to handle navigation to Canvas
        NotificationCenter.default.post(
            name: .sanctuaryThinkspaceRequested,
            object: nil
        )
    }
}

// MARK: - Dimension Orb Glow Wrapper (isolated re-render boundary)

/// Wraps DimensionOrbView with its own observation of DimensionIndexEngine.
/// Only re-renders when THIS dimension's score changes, not when other dimensions update.
private struct DimensionOrbGlowWrapper: View {
    let dimension: LevelDimension
    let dimensionState: SanctuaryDimensionState?
    let isSelected: Bool
    let animationPhase: Double

    @ObservedObject private var engine = DimensionIndexEngine.shared

    var body: some View {
        let diScore = engine.index(for: dimension).score
        let glowRadius: CGFloat = diScore < 30 ? 3 : (diScore > 80 ? 12 : 3 + CGFloat((diScore - 30) / 50) * 9)
        let glowColor = OnyxColors.Dimension.color(for: dimension)

        DimensionOrbView(
            dimension: dimension,
            state: dimensionState,
            isSelected: isSelected,
            animationPhase: animationPhase
        )
        .shadow(color: glowColor.opacity(0.35), radius: glowRadius, x: 0, y: 0)
    }
}

// MARK: - Sanctuary Navigation Notifications

extension Notification.Name {
    /// Request to navigate to Plannerum (planning realm)
    static let sanctuaryPlannerumRequested = Notification.Name("sanctuaryPlannerumRequested")

    /// Request to navigate to Thinkspace (creative canvas)
    static let sanctuaryThinkspaceRequested = Notification.Name("sanctuaryThinkspaceRequested")
}

// MARK: - Preview

#Preview {
    SanctuaryView()
}
