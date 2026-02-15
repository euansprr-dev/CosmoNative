// CosmoOS/UI/Sanctuary/Dimensions/Knowledge/KnowledgeFlowMetrics.swift
// Knowledge Flow Metrics - Today's knowledge flow cards (Captured, Processed, Connected, Density)
// Phase 7: Following SANCTUARY_UI_SPEC_V2.md section 3.5

import SwiftUI

// MARK: - Knowledge Flow Panel

/// Panel showing today's knowledge flow metrics
public struct KnowledgeFlowPanel: View {

    // MARK: - Properties

    let capturesToday: Int
    let capturesChange: Int
    let processedToday: Int
    let connectionsToday: Int
    let semanticDensity: Double

    @State private var isVisible: Bool = false

    // MARK: - Initialization

    public init(
        capturesToday: Int,
        capturesChange: Int,
        processedToday: Int,
        connectionsToday: Int,
        semanticDensity: Double
    ) {
        self.capturesToday = capturesToday
        self.capturesChange = capturesChange
        self.processedToday = processedToday
        self.connectionsToday = connectionsToday
        self.semanticDensity = semanticDensity
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("Today's Knowledge Flow")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Flow cards row
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                // Captured
                FlowMetricCard(
                    title: "Captured",
                    value: capturesToday,
                    unit: "ideas",
                    change: capturesChange,
                    icon: "square.and.arrow.down.fill"
                )
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 15)
                .animation(.easeOut(duration: 0.3).delay(0.1), value: isVisible)

                // Flow arrow
                flowArrow
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.15), value: isVisible)

                // Processed
                FlowMetricCard(
                    title: "Processed",
                    value: processedToday,
                    unit: "embeddings",
                    change: nil,
                    icon: "cpu.fill"
                )
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 15)
                .animation(.easeOut(duration: 0.3).delay(0.2), value: isVisible)

                // Flow arrow
                flowArrow
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.25), value: isVisible)

                // Connected
                FlowMetricCard(
                    title: "Connected",
                    value: connectionsToday,
                    unit: "links",
                    change: nil,
                    icon: "link"
                )
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 15)
                .animation(.easeOut(duration: 0.3).delay(0.3), value: isVisible)

                // Density indicator
                DensityIndicator(density: semanticDensity)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 15)
                    .animation(.easeOut(duration: 0.3).delay(0.35), value: isVisible)
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }

    private var flowArrow: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(SanctuaryColors.Dimensions.knowledge.opacity(0.5))
                .frame(width: 20, height: 2)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.Dimensions.knowledge.opacity(0.5))
        }
    }
}

// MARK: - Flow Metric Card

/// Individual flow metric card
public struct FlowMetricCard: View {

    let title: String
    let value: Int
    let unit: String
    let change: Int?
    let icon: String

    @State private var isHovered: Bool = false
    @State private var valueAnimated: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Dimensions.knowledge)
            }

            // Value
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(valueAnimated ? value : 0)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .contentTransition(.numericText())

                Text(unit)
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            // Change indicator
            if let change = change {
                HStack(spacing: 2) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))

                    Text("\(change >= 0 ? "+" : "")\(change) today")
                        .font(.system(size: 10))
                }
                .foregroundColor(change >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? SanctuaryColors.Dimensions.knowledge.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                valueAnimated = true
            }
        }
    }
}

// MARK: - Density Indicator

/// Semantic density indicator with progress bar
public struct DensityIndicator: View {

    let density: Double

    @State private var isHovered: Bool = false
    @State private var progressAnimated: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Text("Density")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Image(systemName: "circle.hexagonpath.fill")
                    .font(.system(size: 12))
                    .foregroundColor(densityColor)
            }

            // Value
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", density))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text(densityLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(densityColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SanctuaryColors.Glass.border)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [densityColor, densityColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: progressAnimated ? geometry.size.width * CGFloat(density) : 0,
                            height: 6
                        )
                }
            }
            .frame(height: 6)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .frame(width: 120)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? densityColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.4)) {
                progressAnimated = true
            }
        }
    }

    private var densityLabel: String {
        if density >= 0.8 { return "HIGH" }
        if density >= 0.5 { return "MEDIUM" }
        return "LOW"
    }

    private var densityColor: Color {
        if density >= 0.8 { return SanctuaryColors.Semantic.success }
        if density >= 0.5 { return SanctuaryColors.Semantic.info }
        return SanctuaryColors.Semantic.warning
    }
}

// MARK: - Flow Summary Compact

/// Compact flow summary for embedding
public struct FlowSummaryCompact: View {

    let captures: Int
    let processed: Int
    let connections: Int
    let density: Double

    public init(captures: Int, processed: Int, connections: Int, density: Double) {
        self.captures = captures
        self.processed = processed
        self.connections = connections
        self.density = density
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Captures
            compactMetric(value: "\(captures)", label: "captured", icon: "square.and.arrow.down")

            divider

            // Processed
            compactMetric(value: "\(processed)", label: "processed", icon: "cpu")

            divider

            // Connections
            compactMetric(value: "\(connections)", label: "links", icon: "link")

            divider

            // Density
            compactMetric(value: String(format: "%.2f", density), label: "density", icon: "circle.hexagonpath")
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

    private func compactMetric(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(SanctuaryColors.Dimensions.knowledge)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text(label)
                .font(.system(size: 8))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(SanctuaryColors.Glass.border)
            .frame(width: 1, height: 40)
    }
}

// MARK: - Flow Arrow Animated

/// Animated flow arrow between metrics
public struct FlowArrowAnimated: View {

    @State private var isAnimating: Bool = false

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(SanctuaryColors.Dimensions.knowledge)
                    .frame(width: 4, height: 4)
                    .opacity(isAnimating ? (index == 2 ? 1 : 0.3) : (index == 0 ? 1 : 0.3))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(SanctuaryColors.Dimensions.knowledge)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Flow Pipeline View

/// Visual representation of the knowledge pipeline
public struct FlowPipelineView: View {

    let stages: [(String, Int, String)]

    public init(stages: [(String, Int, String)]) {
        self.stages = stages
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                VStack(spacing: 4) {
                    Text("\(stage.1)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text(stage.0)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SanctuaryLayout.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(SanctuaryColors.Glass.highlight)
                )

                if index < stages.count - 1 {
                    FlowArrowAnimated()
                        .padding(.horizontal, SanctuaryLayout.Spacing.xs)
                }
            }
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
}

// MARK: - Preview

#if DEBUG
struct KnowledgeFlowMetrics_Previews: PreviewProvider {
    static var previews: some View {
        let data = KnowledgeDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    KnowledgeFlowPanel(
                        capturesToday: data.capturesToday,
                        capturesChange: data.capturesChange,
                        processedToday: data.processedToday,
                        connectionsToday: data.connectionsToday,
                        semanticDensity: data.semanticDensity
                    )

                    FlowSummaryCompact(
                        captures: data.capturesToday,
                        processed: data.processedToday,
                        connections: data.connectionsToday,
                        density: data.semanticDensity
                    )

                    FlowPipelineView(stages: [
                        ("CAPTURE", 47, "ideas"),
                        ("PROCESS", 23, "embeddings"),
                        ("CONNECT", 12, "links")
                    ])
                }
                .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 500)
    }
}
#endif
