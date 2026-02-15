// CosmoOS/UI/Sanctuary/Dimensions/Creative/CreativePerformanceGraph.swift
// Performance Graph - Time-series chart with multiple metrics
// Phase 4: Following SANCTUARY_UI_SPEC_V2.md section 3.2

import SwiftUI

// MARK: - Performance Graph

/// Interactive time-series performance chart
public struct CreativePerformanceGraph: View {

    // MARK: - Properties

    let data: [PerformanceDataPoint]
    @Binding var selectedRange: CreativeTimeRange
    let onPointTap: ((PerformanceDataPoint) -> Void)?

    @State private var isVisible: Bool = false
    @State private var graphAnimated: Bool = false
    @State private var hoveredPoint: UUID?
    @State private var tooltipPosition: CGPoint = .zero

    // MARK: - Initialization

    public init(
        data: [PerformanceDataPoint],
        selectedRange: Binding<CreativeTimeRange>,
        onPointTap: ((PerformanceDataPoint) -> Void)? = nil
    ) {
        self.data = data
        self._selectedRange = selectedRange
        self.onPointTap = onPointTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header with range selector
            header

            // Graph
            GeometryReader { geometry in
                graphContent(in: geometry)
            }
            .frame(height: 200)

            // Legend
            legend
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
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                graphAnimated = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Performance Graph")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            Spacer()

            // Range selector
            HStack(spacing: 2) {
                ForEach(CreativeTimeRange.allCases, id: \.self) { range in
                    rangeButton(range)
                }
            }
            .padding(2)
            .background(SanctuaryColors.Glass.highlight)
            .clipShape(Capsule())
        }
    }

    private func rangeButton(_ range: CreativeTimeRange) -> some View {
        let isSelected = selectedRange == range

        return Button(action: {
            withAnimation(SanctuarySprings.snappy) {
                selectedRange = range
            }
        }) {
            Text(range.displayName)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? SanctuaryColors.Text.primary : SanctuaryColors.Text.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? SanctuaryColors.Dimensions.creative.opacity(0.2) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Graph Content

    private func graphContent(in geometry: GeometryProxy) -> some View {
        let width = geometry.size.width
        let height = geometry.size.height
        let padding: CGFloat = 40

        let filteredData = filterData(for: selectedRange)

        return ZStack {
            // Grid lines
            gridLines(width: width, height: height, padding: padding, data: filteredData)

            // Y-axis labels
            yAxisLabels(height: height, padding: padding, data: filteredData)

            // X-axis labels
            xAxisLabels(width: width, height: height, padding: padding, data: filteredData)

            // Lines
            graphLines(width: width, height: height, padding: padding, data: filteredData)

            // Hover tooltip
            if let hoveredId = hoveredPoint,
               let point = filteredData.first(where: { $0.id == hoveredId }) {
                tooltip(for: point)
                    .position(tooltipPosition)
            }
        }
    }

    private func filterData(for range: CreativeTimeRange) -> [PerformanceDataPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: Date()) ?? Date()
        return data.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    private func gridLines(width: CGFloat, height: CGFloat, padding: CGFloat, data: [PerformanceDataPoint]) -> some View {
        let graphHeight = height - padding
        let lineCount = 4

        return ZStack {
            ForEach(0..<lineCount, id: \.self) { i in
                let y = padding / 2 + graphHeight * CGFloat(i) / CGFloat(lineCount - 1)

                Path { path in
                    path.move(to: CGPoint(x: padding, y: y))
                    path.addLine(to: CGPoint(x: width - 10, y: y))
                }
                .stroke(SanctuaryColors.Glass.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    private func yAxisLabels(height: CGFloat, padding: CGFloat, data: [PerformanceDataPoint]) -> some View {
        let maxReach = data.map { $0.reach }.max() ?? 1
        let graphHeight = height - padding
        let lineCount = 4

        return VStack(spacing: 0) {
            ForEach(0..<lineCount, id: \.self) { i in
                let value = maxReach - (maxReach * i / (lineCount - 1))
                let label = formatAxisValue(value)

                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .frame(width: 35, alignment: .trailing)

                if i < lineCount - 1 {
                    Spacer()
                }
            }
        }
        .frame(height: graphHeight)
        .padding(.top, padding / 2)
    }

    private func xAxisLabels(width: CGFloat, height: CGFloat, padding: CGFloat, data: [PerformanceDataPoint]) -> some View {
        let graphWidth = width - padding - 10

        guard !data.isEmpty else { return AnyView(EmptyView()) }

        let labelCount = min(6, data.count)
        let step = max(1, data.count / labelCount)

        var labelViews: [AnyView] = []
        for i in stride(from: 0, to: data.count, by: step) {
            let point = data[i]
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            labelViews.append(AnyView(
                Text(formatter.string(from: point.date))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .frame(maxWidth: .infinity)
            ))
        }

        return AnyView(
            HStack(spacing: 0) {
                ForEach(Array(labelViews.enumerated()), id: \.offset) { _, view in
                    view
                }
            }
            .frame(width: graphWidth)
            .offset(x: padding, y: height - 15)
        )
    }

    private func graphLines(width: CGFloat, height: CGFloat, padding: CGFloat, data: [PerformanceDataPoint]) -> some View {
        let graphWidth = width - padding - 10
        let graphHeight = height - padding

        guard data.count > 1 else { return AnyView(EmptyView()) }

        let maxReach = data.map { $0.reach }.max() ?? 1
        let maxEngagement = data.map { $0.engagement }.max() ?? 1

        return AnyView(
            ZStack {
                // Reach line (primary)
                linePath(
                    data: data.map { Double($0.reach) },
                    maxValue: Double(maxReach),
                    width: graphWidth,
                    height: graphHeight
                )
                .trim(from: 0, to: graphAnimated ? 1 : 0)
                .stroke(
                    SanctuaryColors.Dimensions.creative,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .offset(x: padding, y: padding / 2)

                // Engagement line (dashed)
                linePath(
                    data: data.map { $0.engagement },
                    maxValue: maxEngagement,
                    width: graphWidth,
                    height: graphHeight
                )
                .trim(from: 0, to: graphAnimated ? 1 : 0)
                .stroke(
                    SanctuaryColors.Semantic.success,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [6, 4])
                )
                .offset(x: padding, y: padding / 2)

                // Interactive points
                ForEach(data) { point in
                    let index = data.firstIndex(where: { $0.id == point.id }) ?? 0
                    let x = padding + graphWidth * CGFloat(index) / CGFloat(max(1, data.count - 1))
                    let y = padding / 2 + graphHeight * (1 - CGFloat(point.reach) / CGFloat(maxReach))

                    Circle()
                        .fill(hoveredPoint == point.id ? SanctuaryColors.Dimensions.creative : Color.clear)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                        .opacity(graphAnimated ? 1 : 0)
                        .onHover { hovering in
                            if hovering {
                                hoveredPoint = point.id
                                tooltipPosition = CGPoint(x: x, y: y - 40)
                            } else if hoveredPoint == point.id {
                                hoveredPoint = nil
                            }
                        }
                        .onTapGesture {
                            onPointTap?(point)
                        }
                }
            }
            .animation(.easeOut(duration: 0.8), value: graphAnimated)
        )
    }

    private func linePath(data: [Double], maxValue: Double, width: CGFloat, height: CGFloat) -> Path {
        guard data.count > 1, maxValue > 0 else { return Path() }

        let stepX = width / CGFloat(data.count - 1)

        return Path { path in
            for (index, value) in data.enumerated() {
                let x = CGFloat(index) * stepX
                let y = height * (1 - CGFloat(value) / CGFloat(maxValue))

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func tooltip(for point: PerformanceDataPoint) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        return VStack(alignment: .leading, spacing: 4) {
            Text(formatter.string(from: point.date))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.primary)

            HStack(spacing: 8) {
                Text("Reach: \(formatAxisValue(point.reach))")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Dimensions.creative)

                Text("Eng: \(String(format: "%.1f", point.engagement))%")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Semantic.success)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 8)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: SanctuaryLayout.Spacing.xl) {
            legendItem(color: SanctuaryColors.Dimensions.creative, label: "Reach (primary)", dashed: false)
            legendItem(color: SanctuaryColors.Semantic.success, label: "Engagement", dashed: true)
            legendItem(color: SanctuaryColors.Dimensions.behavioral, label: "Followers", dashed: false, dotted: true)
        }
    }

    private func legendItem(color: Color, label: String, dashed: Bool, dotted: Bool = false) -> some View {
        HStack(spacing: 6) {
            if dashed {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 5))
                    path.addLine(to: CGPoint(x: 20, y: 5))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 20, height: 10)
            } else if dotted {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 5))
                    path.addLine(to: CGPoint(x: 20, y: 5))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 20, height: 10)
            } else {
                Rectangle()
                    .fill(color)
                    .frame(width: 20, height: 2)
            }

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }

    // MARK: - Helpers

    private func formatAxisValue(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.0fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

// MARK: - Preview

#if DEBUG
struct CreativePerformanceGraph_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CreativePerformanceGraph(
                data: CreativeDimensionData.preview.performanceTimeSeries,
                selectedRange: .constant(.month)
            )
            .frame(height: 300)
            .padding()
        }
    }
}
#endif
