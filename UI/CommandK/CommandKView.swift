// CosmoOS/UI/CommandK/CommandKView.swift
// Main Command-K overlay view - NodeGraph OS search interface
// Glass material overlay with constellation visualization

import SwiftUI

// MARK: - CommandKView
/// Main overlay for Command-K search interface
/// Features: glass material, constellation view, results list, preview drawer
public struct CommandKView: View {

    // MARK: - State
    @StateObject private var viewModel = CommandKViewModel()
    @FocusState private var isSearchFocused: Bool
    @State private var showPreview: Bool = false

    // MARK: - Layout Constants
    private let overlayWidthPercent: CGFloat = 0.75
    private let overlayHeightPercent: CGFloat = 0.70
    private let overlayMinSize = CGSize(width: 900, height: 600)
    private let overlayMaxSize = CGSize(width: 1400, height: 900)
    private let cornerRadius: CGFloat = 24

    // MARK: - Body
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background blur and dim
                backgroundLayer

                // Main overlay container
                overlayContainer(geometry: geometry)
            }
            .ignoresSafeArea()
            .onAppear {
                isSearchFocused = true
                viewModel.constellationSize = CGSize(
                    width: geometry.size.width * 0.45,
                    height: geometry.size.height * 0.5
                )
            }
        }
        .onKeyPress(.escape) {
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            return .handled
        }
        // Arrow key navigation
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            showPreview = true
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            showPreview = true
            return .handled
        }
        // Return key to open selected
        .onKeyPress(.return) {
            viewModel.openSelected()
            return .handled
        }
        // Tab key to toggle preview
        .onKeyPress(.tab) {
            withAnimation(ProMotionSprings.snappy) {
                showPreview.toggle()
            }
            return .handled
        }
    }

    // MARK: - Background Layer
    private var backgroundLayer: some View {
        ZStack {
            // Blur underlying content
            Rectangle()
                .fill(.ultraThinMaterial)
                .blur(radius: 20)

            // Void overlay
            Color(hex: "#0A0A0F")
                .opacity(0.7)

            // Subtle aurora glow
            RadialGradient(
                colors: [
                    Color(hex: "#6366F1").opacity(0.05),
                    .clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 600
            )
        }
        .onTapGesture {
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        }
    }

    // MARK: - Overlay Container
    private func overlayContainer(geometry: GeometryProxy) -> some View {
        let width = min(max(geometry.size.width * overlayWidthPercent, overlayMinSize.width), overlayMaxSize.width)
        let height = min(max(geometry.size.height * overlayHeightPercent, overlayMinSize.height), overlayMaxSize.height)

        return VStack(spacing: 0) {
            // Search bar section
            searchBarSection

            Divider()
                .background(Color.white.opacity(0.15))

            // Filter chips
            filterChipsSection

            Divider()
                .background(Color.white.opacity(0.15))

            // Main content area
            HStack(spacing: 0) {
                // Constellation view (60%)
                constellationSection
                    .frame(width: width * 0.6)

                Divider()
                    .background(Color.white.opacity(0.15))

                // Results list (40%)
                resultsSection
                    .frame(width: width * 0.4)
            }

            // Preview drawer (if item selected)
            if showPreview, viewModel.selectedNodeId != nil {
                Divider()
                    .background(Color.white.opacity(0.15))

                previewDrawer
            }
        }
        .frame(width: width, height: height)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
    }

    // MARK: - Glass Background
    private var glassBackground: some View {
        ZStack {
            // Base glass
            Color(hex: "#12121A")
                .opacity(0.95)

            // Glass overlay
            Color.white.opacity(0.08)

            // Border glow
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Search Bar Section
    private var searchBarSection: some View {
        HStack(spacing: 16) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            // Text field
            TextField("Search your knowledge...", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .foregroundColor(.white)
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.openSelected()
                }

            Spacer()

            // Voice toggle
            Button {
                viewModel.isVoiceActive.toggle()
            } label: {
                Image(systemName: viewModel.isVoiceActive ? "mic.fill" : "mic")
                    .font(.system(size: 18))
                    .foregroundColor(viewModel.isVoiceActive ? Color(hex: "#6366F1") : .white.opacity(0.5))
            }
            .buttonStyle(.plain)

            // Search phase indicator
            if viewModel.currentPhase == .searching {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 72)
    }

    // MARK: - Filter Chips Section (Multi-select with counts)
    private var filterChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // All filter (clears selection)
                FilterChipWithCount(
                    title: "All",
                    count: viewModel.totalCount,
                    isSelected: viewModel.selectedTypeFilters.isEmpty,
                    color: Color(hex: "#6366F1")
                ) {
                    viewModel.clearTypeFilters()
                }

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 24)

                // Type filters (multi-select)
                ForEach(viewModel.filterTypes, id: \.rawValue) { type in
                    let count = viewModel.countForType(type)
                    FilterChipWithCount(
                        title: type.displayName,
                        count: count,
                        isSelected: viewModel.isTypeFilterActive(type),
                        color: colorForType(type),
                        isDisabled: count == 0
                    ) {
                        viewModel.toggleTypeFilter(type)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 52)
    }

    // MARK: - Constellation Section (with hover highlighting)
    private var constellationSection: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(hex: "#0A0A0F")

                // Edges (with hover highlighting)
                ForEach(viewModel.constellationEdges) { edge in
                    ConstellationEdgeView(
                        edge: edge,
                        isHighlighted: viewModel.isEdgeHighlighted(edge)
                    )
                }

                // Nodes (with hover highlighting)
                ForEach(viewModel.constellationNodes) { node in
                    ConstellationNodeView(
                        node: node,
                        isSelected: node.atomUUID == viewModel.selectedNodeId,
                        isHighlighted: viewModel.isNodeHighlighted(node.atomUUID),
                        isDimmed: viewModel.hoveredNodeId != nil && !viewModel.isNodeHighlighted(node.atomUUID)
                    )
                    .position(node.position)
                    .onHover { hovering in
                        viewModel.setHoveredNode(hovering ? node.atomUUID : nil)
                    }
                    .onTapGesture {
                        viewModel.select(uuid: node.atomUUID)
                        showPreview = true
                    }
                    .onTapGesture(count: 2) {
                        viewModel.select(uuid: node.atomUUID)
                        viewModel.openSelected()
                    }
                }

                // Empty state
                if viewModel.constellationNodes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.3))

                        Text("Start typing to explore your knowledge")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .onAppear {
                viewModel.constellationSize = geometry.size
            }
        }
    }

    // MARK: - Results Section
    private var resultsSection: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(viewModel.results) { result in
                    ResultRow(
                        result: result,
                        isSelected: result.atomUUID == viewModel.selectedNodeId
                    )
                    .onTapGesture {
                        viewModel.select(uuid: result.atomUUID)
                        showPreview = true
                    }
                    .onTapGesture(count: 2) {
                        viewModel.select(uuid: result.atomUUID)
                        viewModel.openSelected()
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Preview Drawer
    private var previewDrawer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedId = viewModel.selectedNodeId,
               let result = viewModel.results.first(where: { $0.atomUUID == selectedId }) {

                HStack {
                    // Type icon
                    Image(systemName: iconForType(result.atomType))
                        .font(.system(size: 16))
                        .foregroundColor(colorForType(result.atomType))

                    // Title
                    Text(result.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    // Open button
                    Button("Open") {
                        viewModel.openSelected()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#6366F1"))
                    .cornerRadius(8)
                }

                // Snippet
                if let snippet = result.snippet {
                    Text(snippet)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }

                // Metadata
                HStack(spacing: 16) {
                    Label("\(result.relevancePercent)%", systemImage: "chart.bar.fill")
                    Label(result.updatedAt.prefix(10).description, systemImage: "clock")
                }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(24)
        .frame(height: showPreview ? 160 : 0)
        .clipped()
    }

    // MARK: - Helpers

    private func colorForType(_ type: AtomType) -> Color {
        switch type.category {
        case .core:
            return Color(hex: "#6366F1")  // Cognitive
        case .contentPipeline:
            return Color(hex: "#F59E0B")  // Creative
        case .knowledge:
            return Color(hex: "#8B5CF6")  // Knowledge
        case .reflection:
            return Color(hex: "#EC4899")  // Reflection
        case .cognitive:
            return Color(hex: "#3B82F6")  // Behavioral
        case .physiology:
            return Color(hex: "#10B981")  // Physiological
        case .leveling, .system, .sanctuary:
            return Color(hex: "#6366F1")  // Default
        }
    }

    private func iconForType(_ type: AtomType) -> String {
        switch type {
        case .idea: return "lightbulb.fill"
        case .task: return "checkmark.circle.fill"
        case .research: return "book.fill"
        case .content: return "doc.text.fill"
        case .connection: return "person.2.fill"
        case .project: return "folder.fill"
        default: return "circle.fill"
        }
    }
}

// MARK: - Filter Chip with Count (Multi-select)
private struct FilterChipWithCount: View {
    let title: String
    let count: Int
    let isSelected: Bool
    var color: Color = Color(hex: "#6366F1")
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))

                // Count badge
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? color : .white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? color.opacity(0.3) : Color.white.opacity(0.1))
                    )
            }
            .foregroundColor(isDisabled ? .white.opacity(0.3) : (isSelected ? .white : .white.opacity(0.7)))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? color.opacity(0.25) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? color.opacity(0.6) : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Result Row
private struct ResultRow: View {
    let result: RankedResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: iconForType(result.atomType))
                .font(.system(size: 14))
                .foregroundColor(colorForType(result.atomType))
                .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let snippet = result.snippet {
                    Text(snippet)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Relevance
            Text("\(result.relevancePercent)%")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
        )
    }

    private func colorForType(_ type: AtomType) -> Color {
        switch type.category {
        case .core: return Color(hex: "#6366F1")
        case .contentPipeline: return Color(hex: "#F59E0B")
        case .knowledge: return Color(hex: "#8B5CF6")
        case .reflection: return Color(hex: "#EC4899")
        case .cognitive: return Color(hex: "#3B82F6")
        case .physiology: return Color(hex: "#10B981")
        case .leveling, .system, .sanctuary: return Color(hex: "#6366F1")
        }
    }

    private func iconForType(_ type: AtomType) -> String {
        switch type {
        case .idea: return "lightbulb.fill"
        case .task: return "checkmark.circle.fill"
        case .research: return "book.fill"
        case .content: return "doc.text.fill"
        case .connection: return "person.2.fill"
        case .project: return "folder.fill"
        default: return "circle.fill"
        }
    }
}

// MARK: - Constellation Node View (with hover highlighting)
private struct ConstellationNodeView: View {
    let node: ConstellationNode
    let isSelected: Bool
    var isHighlighted: Bool = false
    var isDimmed: Bool = false

    private var effectiveOpacity: Double {
        if isDimmed { return 0.3 }
        return 1.0
    }

    private var glowMultiplier: Double {
        if isHighlighted { return 1.5 }
        return 1.0
    }

    var body: some View {
        ZStack {
            // Glow layer (enhanced on hover)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: node.dimensionColor).opacity(0.4 * node.glowIntensity * glowMultiplier),
                            Color(hex: node.dimensionColor).opacity(0.1 * node.glowIntensity * glowMultiplier),
                            .clear
                        ],
                        center: .center,
                        startRadius: node.radius * 0.5,
                        endRadius: node.radius * (isHighlighted ? 2.5 : 2)
                    )
                )
                .frame(width: node.radius * 4, height: node.radius * 4)

            // Core orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: node.dimensionColor).opacity(0.9),
                            Color(hex: node.dimensionColor).opacity(0.6)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: node.radius
                    )
                )
                .frame(width: node.radius * 2, height: node.radius * 2)
                .overlay(
                    Circle()
                        .strokeBorder(
                            (isSelected || isHighlighted) ? Color.white.opacity(0.8) : Color.white.opacity(0.2),
                            lineWidth: (isSelected || isHighlighted) ? 2.5 : 1
                        )
                )

            // Title label on hover
            if isHighlighted {
                Text(node.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.7))
                    )
                    .offset(y: node.radius * 2 + 12)
            }
        }
        .opacity(effectiveOpacity)
        .scaleEffect(isSelected ? 1.15 : (isHighlighted ? 1.1 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: isHighlighted)
        .animation(.easeInOut(duration: 0.15), value: isDimmed)
    }
}

// MARK: - Constellation Edge View (with hover highlighting)
private struct ConstellationEdgeView: View {
    let edge: ConstellationEdge
    var isHighlighted: Bool = false

    private var effectiveOpacity: Double {
        if isHighlighted { return min(edge.opacity * 2.5, 0.8) }
        return edge.opacity
    }

    private var effectiveLineWidth: CGFloat {
        if isHighlighted { return edge.lineWidth * 1.8 }
        return edge.lineWidth
    }

    var body: some View {
        Path { path in
            path.move(to: edge.sourcePosition)
            path.addQuadCurve(
                to: edge.targetPosition,
                control: edge.controlPoint
            )
        }
        .stroke(
            isHighlighted ? Color(hex: "#6366F1").opacity(effectiveOpacity) : Color.white.opacity(effectiveOpacity),
            style: StrokeStyle(lineWidth: effectiveLineWidth, lineCap: .round)
        )
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }
}
