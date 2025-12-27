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
                // Background with transition support
                SanctuaryTransitionBackground(manager: transitionManager)

                // Aurora overlay when Metal is enabled
                if useMetalRendering {
                    SanctuaryAuroraMetalView(
                        colorA: SanctuaryColors.Dimensions.cognitive,
                        colorB: SanctuaryColors.Dimensions.creative,
                        colorC: SanctuaryColors.Dimensions.physiological,
                        intensity: 0.25,
                        speed: 0.4
                    )
                    .opacity(choreographer.backgroundOpacity)
                    .ignoresSafeArea()
                }

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
                    .opacity(choreographer.backgroundOpacity * 0.7)  // Recessed depth
                    .blur(radius: 1)  // Subtle depth blur
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
                    .opacity(choreographer.backgroundOpacity * 0.85)  // Slightly recessed
                    .blur(radius: 0.5)  // Very subtle depth blur
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
                    .opacity(choreographer.backgroundOpacity * 0.85)  // Slightly recessed
                    .blur(radius: 0.5)  // Very subtle depth blur
                    .scaleEffect(0.92)  // Slightly smaller for depth
                }
                .allowsHitTesting(true)  // Ensure hit testing is enabled for satellite nodes

                // Main content container
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

                    Spacer(minLength: SanctuaryLayout.Spacing.lg)  // Reduced from 64pt to 24pt to move insight stream higher

                    // INSIGHT STREAM (Bottom 140pt) - Phase 2 component
                    insightStreamView
                        .frame(maxWidth: .infinity)  // PERFORMANCE FIX: Ensure full width for GeometryReader
                        .opacity(choreographer.dimensionsOpacity)
                        .sanctuaryTransitionInsights(manager: transitionManager)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Dimension detail view (shown during/after transition)
                if case .dimension(let dimension) = transitionManager.state {
                    dimensionDetailView(for: dimension)
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
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var sanctuaryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sanctuary")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if let state = dataProvider.state {
                    Text("Level \(state.cosmoIndex.level) • \(state.cosmoIndex.rank)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()

            // Live indicator
            if dataProvider.state?.liveMetrics.currentHRV != nil {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.green.opacity(0.5), lineWidth: 2)
                                .scaleEffect(1.5)
                                .opacity(0.5)
                        )

                    Text("Live")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15))
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

        return DimensionOrbView(
            dimension: dimension,
            state: dimensionStream.state(for: dimension),
            isSelected: selectedDimension == dimension,
            animationPhase: choreographer.animationPhase
        )
        .sanctuaryTransitionSelected(manager: transitionManager, dimension: dimension)
        .position(x: x, y: y)
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                if selectedDimension == dimension {
                    // Second tap - trigger dimension zoom transition
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

                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: dimensions[i].colorHex).opacity(0.3),
                            Color(hex: dimensions[nextIndex].colorHex).opacity(0.3)
                        ]),
                        startPoint: CGPoint(x: x1, y: y1),
                        endPoint: CGPoint(x: x2, y: y2)
                    ),
                    lineWidth: 1
                )
            }
        }
        .frame(width: orbAreaSize, height: orbAreaSize)
    }

    // MARK: - Hero Orb Overlay

    @ViewBuilder
    private var heroOrbOverlay: some View {
        VStack(spacing: SanctuaryLayout.Spacing.xs) {
            Text("CI")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.secondary)

            if let state = dataProvider.state?.cosmoIndex {
                Text("\(state.level)")
                    .font(SanctuaryTypography.display)
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

                // XP progress ring
                SanctuaryProgressRingMetalView(
                    progress: CGFloat(state.xpProgress),
                    progressColor: SanctuaryColors.XP.primary,
                    trackColor: SanctuaryColors.XP.track,
                    ringWidth: 0.08,
                    isAnimating: true
                )
                .frame(width: 100, height: 100)
            }
        }

        // Live HRV indicator
        if let hrv = dataProvider.state?.liveMetrics.currentHRV {
            VStack {
                Spacer()

                HStack(spacing: SanctuaryLayout.Spacing.xs) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)

                    Text("\(Int(hrv))")
                        .font(SanctuaryTypography.metric)
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
                .padding(.horizontal, SanctuaryLayout.Spacing.sm)
                .padding(.vertical, SanctuaryLayout.Spacing.xs)
                .background(SanctuaryColors.Glass.background)
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
                connectionLineView(
                    index: i,
                    center: center,
                    radius: radius,
                    dimensions: dimensions,
                    count: count
                )
            }
        }
        .frame(width: orbAreaSize, height: orbAreaSize)
    }

    private func connectionLineView(
        index i: Int,
        center: CGPoint,
        radius: CGFloat,
        dimensions: [LevelDimension],
        count: Int
    ) -> some View {
        let angle1 = (Double(i) / Double(count)) * 2 * .pi - .pi / 2
        let x1 = center.x + radius * Darwin.cos(angle1)
        let y1 = center.y + radius * Darwin.sin(angle1)

        let nextIndex = (i + 1) % count
        let angle2 = (Double(nextIndex) / Double(count)) * 2 * .pi - .pi / 2
        let x2 = center.x + radius * Darwin.cos(angle2)
        let y2 = center.y + radius * Darwin.sin(angle2)

        return SanctuaryConnectionLine(
            from: CGPoint(x: x1, y: y1),
            to: CGPoint(x: x2, y: y2),
            color1: SanctuaryColors.Dimensions.color(for: dimensions[i]),
            color2: SanctuaryColors.Dimensions.color(for: dimensions[nextIndex]),
            glowIntensity: 0.4,
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
                            Text("NEW INSIGHTS")
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
            CognitiveDimensionView(
                data: .preview,  // TODO: Load from SanctuaryDataProvider
                onBack: handleDimensionBack
            )

        case .creative:
            CreativeDimensionView(
                data: .preview,  // TODO: Load from SanctuaryDataProvider
                onBack: handleDimensionBack
            )

        case .physiological:
            PhysiologicalDimensionView(
                data: .preview,  // TODO: Load from SanctuaryDataProvider
                onBack: handleDimensionBack
            )

        case .behavioral:
            BehavioralDimensionView(
                data: .preview,  // TODO: Load from SanctuaryDataProvider
                onBack: handleDimensionBack
            )

        case .knowledge:
            KnowledgeDimensionView(
                data: .preview,  // TODO: Load from SanctuaryDataProvider
                onBack: handleDimensionBack
            )

        case .reflection:
            ReflectionDimensionView(
                data: .preview,  // TODO: Load from SanctuaryDataProvider
                onBack: handleDimensionBack
            )
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
