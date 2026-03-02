// CosmoOS/UI/Sanctuary/Dimensions/Behavioral/BehavioralDisciplineIndex.swift
// Discipline Index - Main discipline score with component breakdown
// Phase 6: Following SANCTUARY_UI_SPEC_V2.md section 3.4

import SwiftUI

// MARK: - Discipline Index Panel

/// Main discipline score panel with component breakdown
public struct BehavioralDisciplineIndex: View {

    // MARK: - Properties

    let disciplineScore: Double
    let changePercent: Double
    let components: [ComponentScore]

    @State private var isVisible: Bool = false
    @State private var progressAnimated: Bool = false

    // MARK: - Initialization

    public init(
        disciplineScore: Double,
        changePercent: Double,
        components: [ComponentScore]
    ) {
        self.disciplineScore = disciplineScore
        self.changePercent = changePercent
        self.components = components
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xl) {
            // Header
            Text("DISCIPLINE INDEX")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Main score display
            mainScoreSection

            // Progress bar
            disciplineProgressBar

            // Component grid
            componentGrid
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                progressAnimated = true
            }
        }
    }

    // MARK: - Main Score Section

    private var mainScoreSection: some View {
        HStack(alignment: .bottom, spacing: SanctuaryLayout.Spacing.md) {
            // Large score
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", disciplineScore))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("%")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            Spacer()

            // Change indicator
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: changePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .bold))

                    Text("\(changePercent >= 0 ? "+" : "")\(String(format: "%.1f", changePercent))%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                }
                .foregroundColor(changePercent >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)

                Text("vs last week")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
        }
    }

    // MARK: - Progress Bar

    private var disciplineProgressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(SanctuaryColors.Glass.border)
                    .frame(height: 8)

                // Progress
                RoundedRectangle(cornerRadius: 4)
                    .fill(progressGradient)
                    .frame(
                        width: progressAnimated ? geometry.size.width * CGFloat(disciplineScore / 100) : 0,
                        height: 8
                    )

                // Glow effect
                RoundedRectangle(cornerRadius: 4)
                    .fill(progressColor.opacity(0.5))
                    .blur(radius: 4)
                    .frame(
                        width: progressAnimated ? geometry.size.width * CGFloat(disciplineScore / 100) : 0,
                        height: 8
                    )
            }
        }
        .frame(height: 8)
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [progressColor, progressColor.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var progressColor: Color {
        if disciplineScore >= 80 { return SanctuaryColors.Semantic.success }
        if disciplineScore >= 60 { return SanctuaryColors.Semantic.info }
        if disciplineScore >= 40 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }

    // MARK: - Component Grid

    private var componentGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md),
                GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md),
                GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md)
            ],
            spacing: SanctuaryLayout.Spacing.md
        ) {
            ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
                ComponentScoreCard(component: component)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 10)
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05 + 0.2), value: isVisible)
            }
        }
    }
}

// MARK: - Component Score Card

/// Individual component score card with progress and status
public struct ComponentScoreCard: View {

    let component: ComponentScore

    @State private var isHovered: Bool = false
    @State private var progressAnimated: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            // Header with name and status dots
            HStack {
                Text(component.name)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                // Status dots
                HStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { index in
                        Circle()
                            .fill(index < component.statusDots ? statusColor : SanctuaryColors.Glass.border)
                            .frame(width: 6, height: 6)
                    }
                }
            }

            // Score with trend
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(component.currentScore))")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.secondary)

                Spacer()

                // Trend arrow
                Image(systemName: component.trend.iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(component.trend.color)
            }

            // Progress bar
            progressBar
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? statusColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                progressAnimated = true
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(SanctuaryColors.Glass.border)
                    .frame(height: 4)

                // Progress
                RoundedRectangle(cornerRadius: 2)
                    .fill(statusColor)
                    .frame(
                        width: progressAnimated ? geometry.size.width * CGFloat(component.currentScore / 100) : 0,
                        height: 4
                    )
            }
        }
        .frame(height: 4)
    }

    private var statusColor: Color {
        switch component.status {
        case .excellent: return SanctuaryColors.Semantic.success
        case .good: return SanctuaryColors.Semantic.info
        case .needsWork: return SanctuaryColors.Semantic.warning
        case .atRisk: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - Discipline Mini Card

/// Compact discipline display for embedding
public struct DisciplineMiniCard: View {

    let score: Double
    let trend: ScoreTrend

    @State private var isHovered: Bool = false

    public init(score: Double, trend: ScoreTrend) {
        self.score = score
        self.trend = trend
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Score
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.0f", score))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            // Trend
            Image(systemName: trend.iconName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(trend.color)

            Spacer()

            // Label
            Text("DISCIPLINE")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? SanctuaryColors.Dimensions.behavioral.opacity(0.5) : SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Discipline Trend Chart

/// Line chart showing discipline trend over time
public struct DisciplineTrendChart: View {

    let dataPoints: [Double]
    let labels: [String]

    @State private var isVisible: Bool = false

    public init(dataPoints: [Double], labels: [String]) {
        self.dataPoints = dataPoints
        self.labels = labels
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Text("TREND")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Text("7 DAYS")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Chart
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let minVal = (dataPoints.min() ?? 0) - 5
                let maxVal = (dataPoints.max() ?? 100) + 5
                let range = maxVal - minVal

                ZStack {
                    // Grid lines
                    ForEach(0..<4, id: \.self) { index in
                        let y = height * CGFloat(index) / 3
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                    }

                    // Line path
                    if dataPoints.count > 1 {
                        Path { path in
                            for (index, value) in dataPoints.enumerated() {
                                let x = width * CGFloat(index) / CGFloat(dataPoints.count - 1)
                                let y = height - (height * CGFloat((value - minVal) / range))

                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .trim(from: 0, to: isVisible ? 1 : 0)
                        .stroke(
                            LinearGradient(
                                colors: [SanctuaryColors.Dimensions.behavioral, SanctuaryColors.Dimensions.behavioral.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )

                        // Data points
                        ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, value in
                            let x = width * CGFloat(index) / CGFloat(dataPoints.count - 1)
                            let y = height - (height * CGFloat((value - minVal) / range))

                            Circle()
                                .fill(SanctuaryColors.Dimensions.behavioral)
                                .frame(width: 6, height: 6)
                                .position(x: x, y: y)
                                .opacity(isVisible ? 1 : 0)
                        }
                    }
                }
            }
            .frame(height: 60)

            // Labels
            HStack {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 8))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    if label != labels.last {
                        Spacer()
                    }
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Component Summary Row

/// Horizontal summary of component scores
public struct ComponentSummaryRow: View {

    let components: [ComponentScore]

    public init(components: [ComponentScore]) {
        self.components = components
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.sm) {
            ForEach(components) { component in
                VStack(spacing: 4) {
                    Text("\(Int(component.currentScore))")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor(for: component))

                    Text(component.name.prefix(3).uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity)

                if component.id != components.last?.id {
                    Rectangle()
                        .fill(SanctuaryColors.Glass.border)
                        .frame(width: 1, height: 30)
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

    private func statusColor(for component: ComponentScore) -> Color {
        switch component.status {
        case .excellent: return SanctuaryColors.Semantic.success
        case .good: return SanctuaryColors.Semantic.info
        case .needsWork: return SanctuaryColors.Semantic.warning
        case .atRisk: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BehavioralDisciplineIndex_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    BehavioralDisciplineIndex(
                        disciplineScore: 78.4,
                        changePercent: 2.3,
                        components: BehavioralDimensionData.preview.allComponentScores
                    )

                    DisciplineMiniCard(score: 78.4, trend: .up)

                    DisciplineTrendChart(
                        dataPoints: [72.1, 74.5, 73.2, 76.8, 77.1, 78.0, 78.4],
                        labels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    )

                    ComponentSummaryRow(
                        components: BehavioralDimensionData.preview.allComponentScores
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 800)
    }
}
#endif
