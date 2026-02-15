// CosmoOS/UI/Sanctuary/Dimensions/Knowledge/KnowledgeDimensionView.swift
// Knowledge Dimension View - "The Semantic Constellation" complete dimension experience
// Onyx Design System — premium cognitive atelier aesthetic

import SwiftUI

// MARK: - Knowledge Dimension View

/// The complete Knowledge Dimension view with all components
/// Layout: Flow Metrics, Constellation, Research Timeline, Stamina, Captures, Insights
public struct KnowledgeDimensionView: View {

    // MARK: - Properties

    @StateObject private var viewModel: KnowledgeDimensionViewModel
    @StateObject private var dataProvider = KnowledgeDataProvider()
    @State private var selectedNode: KnowledgeNode?
    @State private var selectedCapture: KnowledgeCapture?
    @State private var showNodeDetail: Bool = false
    @State private var showCaptureDetail: Bool = false
    let onBack: () -> Void

    // MARK: - Initialization

    public init(
        data: KnowledgeDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: KnowledgeDimensionViewModel(data: data))
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

                        // Knowledge Flow Metrics
                        KnowledgeFlowPanel(
                            capturesToday: viewModel.data.capturesToday,
                            capturesChange: viewModel.data.capturesChange,
                            processedToday: viewModel.data.processedToday,
                            connectionsToday: viewModel.data.connectionsToday,
                            semanticDensity: viewModel.data.semanticDensity
                        )

                        // 3D Knowledge Constellation
                        KnowledgeConstellation(
                            nodes: viewModel.data.nodes,
                            edges: viewModel.data.edges,
                            positions: viewModel.data.nodePositions,
                            clusters: viewModel.data.clusters,
                            onNodeTap: { node in
                                selectedNode = node
                                showNodeDetail = true
                            }
                        )

                        timelineAndStaminaSection(useSingleColumn: useSingleColumn)

                        // Recent Captures
                        KnowledgeRecentCaptures(
                            captures: viewModel.data.recentCaptures,
                            onCaptureTap: { capture in
                                selectedCapture = capture
                                showCaptureDetail = true
                            },
                            onViewAll: {}
                        )

                        // Cluster Insights
                        KnowledgeClusterInsights(
                            growingClusters: viewModel.data.growingClusters,
                            dormantClusters: viewModel.data.dormantClusters,
                            emergingLinks: viewModel.data.emergingLinks,
                            predictions: viewModel.data.predictions
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
        .task {
            await dataProvider.refreshData()
            viewModel.data = dataProvider.data
        }
        .onChange(of: dataProvider.data.capturesToday) { _ in
            viewModel.data = dataProvider.data
        }
    }

    private enum Layout {
        static let maxContentWidth: CGFloat = 1400
        static let twoColumnBreakpoint: CGFloat = 900
    }

    @ViewBuilder
    private func timelineAndStaminaSection(useSingleColumn: Bool) -> some View {
        if useSingleColumn {
            VStack(spacing: 16) {
                KnowledgeResearchTimeline(
                    timeline: viewModel.data.researchTimeline,
                    peakHour: viewModel.data.peakResearchHour,
                    peakMinutes: viewModel.data.peakResearchMinutes,
                    totalToday: viewModel.data.totalResearchToday,
                    weeklyData: viewModel.data.weeklyResearchData,
                    weeklyTotal: viewModel.data.weeklyTotalMinutes
                )
                .frame(maxWidth: .infinity)

                KnowledgeStaminaPanel(
                    stamina: viewModel.data.knowledgeStamina,
                    optimalWindowStart: viewModel.data.optimalWindowStart,
                    optimalWindowEnd: viewModel.data.optimalWindowEnd,
                    rechargeNeeded: viewModel.data.rechargeNeededMinutes,
                    factors: viewModel.data.staminaFactors
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                KnowledgeResearchTimeline(
                    timeline: viewModel.data.researchTimeline,
                    peakHour: viewModel.data.peakResearchHour,
                    peakMinutes: viewModel.data.peakResearchMinutes,
                    totalToday: viewModel.data.totalResearchToday,
                    weeklyData: viewModel.data.weeklyResearchData,
                    weeklyTotal: viewModel.data.weeklyTotalMinutes
                )
                .frame(maxWidth: .infinity)

                KnowledgeStaminaPanel(
                    stamina: viewModel.data.knowledgeStamina,
                    optimalWindowStart: viewModel.data.optimalWindowStart,
                    optimalWindowEnd: viewModel.data.optimalWindowEnd,
                    rechargeNeeded: viewModel.data.rechargeNeededMinutes,
                    factors: viewModel.data.staminaFactors
                )
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

            // Subtle knowledge dimension tint
            RadialGradient(
                colors: [
                    OnyxColors.DimensionVivid.knowledge.opacity(0.08),
                    OnyxColors.DimensionVivid.knowledge.opacity(0.03),
                    Color.clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 600
            )
            .ignoresSafeArea()

            // Constellation pattern overlay (subtle)
            ForEach(0..<30, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(Double.random(in: 0.01...0.05)))
                    .frame(width: CGFloat.random(in: 1...3))
                    .position(
                        x: CGFloat.random(in: 0...1200),
                        y: CGFloat.random(in: 0...1000)
                    )
            }

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
                Text("Knowledge")
                    .font(OnyxTypography.viewTitle)
                    .tracking(OnyxTypography.viewTitleTracking)
                    .foregroundColor(OnyxColors.Text.primary)

                HStack(spacing: 8) {
                    Text("Semantic Constellation")
                        .font(.system(size: 12))
                        .foregroundColor(OnyxColors.Text.secondary)

                    Text("·")
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("Tier \(viewModel.dimensionLevel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Dimension.knowledge)

                    Text("·")
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("Scholar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Dimension.knowledge)
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
                    .fill(OnyxColors.Accent.sage)
                    .frame(width: 6, height: 6)
                    .modifier(OnyxPulseModifier())

                Text("Live")
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Text.tertiary)
            }

            Text("Density: \(String(format: "%.2f", viewModel.data.semanticDensity))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(OnyxColors.DimensionVivid.knowledge)

            Text("\(viewModel.data.totalNodeCount) nodes")
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

    // MARK: - Detail Overlays

    @ViewBuilder
    private var detailOverlays: some View {
        // Node detail
        if showNodeDetail, let node = selectedNode {
            overlayBackground
                .onTapGesture {
                    showNodeDetail = false
                }

            NodeDetailPanel(
                node: node,
                connectedNodes: connectedNodes(for: node),
                edges: viewModel.data.edges.filter { $0.sourceNodeID == node.id || $0.targetNodeID == node.id },
                onDismiss: { showNodeDetail = false }
            )
            .frame(maxWidth: 450)
            .transition(.scale.combined(with: .opacity))
        }

        // Capture detail
        if showCaptureDetail, let capture = selectedCapture {
            overlayBackground
                .onTapGesture {
                    showCaptureDetail = false
                }

            CaptureDetailView(
                capture: capture,
                onDismiss: { showCaptureDetail = false }
            )
            .frame(maxWidth: 450)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var overlayBackground: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .transition(.opacity)
    }

    private func connectedNodes(for node: KnowledgeNode) -> [KnowledgeNode] {
        let connectedIDs = viewModel.data.edges
            .filter { $0.sourceNodeID == node.id || $0.targetNodeID == node.id }
            .flatMap { [$0.sourceNodeID, $0.targetNodeID] }
            .filter { $0 != node.id }

        return viewModel.data.nodes.filter { connectedIDs.contains($0.id) }
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

// MARK: - Knowledge Dimension View Model

@MainActor
public final class KnowledgeDimensionViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var data: KnowledgeDimensionData
    @Published public var isLoading: Bool = false
    @Published public var searchQuery: String = ""

    // MARK: - Computed Properties

    public var dimensionLevel: Int {
        // Would be loaded from CosmoLevelState
        22
    }

    public var filteredNodes: [KnowledgeNode] {
        if searchQuery.isEmpty {
            return data.nodes
        }
        return data.nodes.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
        }
    }

    // MARK: - Initialization

    public init(data: KnowledgeDimensionData) {
        self.data = data
    }

    // MARK: - Actions

    public func refreshData() async {
        isLoading = true
        // Would load from SanctuaryDataProvider / knowledge systems
        try? await Task.sleep(nanoseconds: 500_000_000)
        isLoading = false
    }

    public func searchNodes(_ query: String) {
        searchQuery = query
    }
}

// MARK: - Compact Knowledge View

/// Compact version for embedding in other views — Onyx design
public struct KnowledgeDimensionCompact: View {

    let data: KnowledgeDimensionData
    let onExpand: () -> Void

    @State private var isHovered: Bool = false

    public init(data: KnowledgeDimensionData, onExpand: @escaping () -> Void) {
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
                        .foregroundColor(OnyxColors.Dimension.knowledge)

                    Text("Knowledge")
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
                    .foregroundColor(OnyxColors.Dimension.knowledge)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Flow summary
            FlowSummaryCompact(
                captures: data.capturesToday,
                processed: data.processedToday,
                connections: data.connectionsToday,
                density: data.semanticDensity
            )

            // Research timeline
            ResearchTimelineCompact(
                timeline: data.researchTimeline,
                totalToday: data.totalResearchToday
            )

            // Stamina
            StaminaCompact(
                stamina: data.knowledgeStamina,
                optimalWindow: data.optimalWindowFormatted
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
struct KnowledgeDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        KnowledgeDimensionView(
            data: .preview,
            onBack: {}
        )
        .frame(minWidth: 1200, minHeight: 1000)
    }
}
#endif
