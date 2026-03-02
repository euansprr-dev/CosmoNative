// CosmoOS/UI/Sanctuary/Components/SanctuaryChartView.swift
// Sanctuary Chart View - Shared chart styling for all dimension views
// Thin lines, no grid, subtle reference lines, gradient area fills
// Motion with purpose - only animate state changes

import SwiftUI

// MARK: - Chart Period

enum ChartPeriod: String, CaseIterable {
    case week = "7d"
    case twoWeeks = "14d"
    case month = "30d"
    case threeMonths = "90d"
    case year = "1Y"

    var days: Int {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 30
        case .threeMonths: return 90
        case .year: return 365
        }
    }

    var displayName: String {
        rawValue
    }
}

// MARK: - Chart Period Selector

struct ChartPeriodSelector: View {
    @Binding var selected: ChartPeriod
    let accentColor: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(SanctuarySprings.select) {
                        selected = period
                    }
                } label: {
                    Text(period.displayName)
                        .font(.system(size: 11, weight: selected == period ? .semibold : .medium))
                        .foregroundColor(selected == period ? .white : SanctuaryColors.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(selected == period ? accentColor.opacity(0.8) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
        )
    }
}

// MARK: - Sanctuary Line Chart

struct SanctuaryLineChart: View {
    let dataPoints: [(Date, Double)]
    let accentColor: Color
    let showArea: Bool
    let referenceLines: [Double]

    init(
        dataPoints: [(Date, Double)],
        accentColor: Color,
        showArea: Bool = true,
        referenceLines: [Double] = []
    ) {
        self.dataPoints = dataPoints
        self.accentColor = accentColor
        self.showArea = showArea
        self.referenceLines = referenceLines
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Canvas { context, canvasSize in
                guard dataPoints.count >= 2 else { return }

                let minVal = computedMinValue
                let maxVal = computedMaxValue
                let range = maxVal - minVal
                guard range > 0 else { return }

                let points = normalizedPoints(in: canvasSize, minVal: minVal, range: range)

                // Draw reference lines
                for refValue in referenceLines {
                    let y = canvasSize.height - ((refValue - minVal) / range) * canvasSize.height
                    if y >= 0 && y <= canvasSize.height {
                        var refPath = Path()
                        refPath.move(to: CGPoint(x: 0, y: y))
                        refPath.addLine(to: CGPoint(x: canvasSize.width, y: y))
                        context.stroke(
                            refPath,
                            with: .color(Color.white.opacity(0.08)),
                            style: StrokeStyle(lineWidth: 0.5, dash: [4, 4])
                        )
                    }
                }

                // Build line path
                let linePath = buildLinePath(points: points)

                // Draw area fill
                if showArea {
                    var areaPath = linePath
                    areaPath.addLine(to: CGPoint(x: points.last?.x ?? canvasSize.width, y: canvasSize.height))
                    areaPath.addLine(to: CGPoint(x: points.first?.x ?? 0, y: canvasSize.height))
                    areaPath.closeSubpath()

                    context.fill(
                        areaPath,
                        with: .linearGradient(
                            Gradient(colors: [
                                accentColor.opacity(0.2),
                                accentColor.opacity(0.05),
                                accentColor.opacity(0.0)
                            ]),
                            startPoint: CGPoint(x: canvasSize.width / 2, y: 0),
                            endPoint: CGPoint(x: canvasSize.width / 2, y: canvasSize.height)
                        )
                    )
                }

                // Draw line
                context.stroke(
                    linePath,
                    with: .color(accentColor),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )

                // Draw last point indicator
                if let lastPoint = points.last {
                    let dotPath = Path(
                        ellipseIn: CGRect(
                            x: lastPoint.x - 3,
                            y: lastPoint.y - 3,
                            width: 6,
                            height: 6
                        )
                    )
                    context.fill(dotPath, with: .color(accentColor))

                    // Outer glow ring
                    let glowPath = Path(
                        ellipseIn: CGRect(
                            x: lastPoint.x - 6,
                            y: lastPoint.y - 6,
                            width: 12,
                            height: 12
                        )
                    )
                    context.stroke(
                        glowPath,
                        with: .color(accentColor.opacity(0.3)),
                        lineWidth: 1
                    )
                }
            }

            // X-axis labels
            xAxisLabels(width: size.width)
        }
    }

    // MARK: - Computed Properties

    private var computedMinValue: Double {
        let dataMin = dataPoints.map(\.1).min() ?? 0
        let refMin = referenceLines.min() ?? dataMin
        return min(dataMin, refMin) * 0.95
    }

    private var computedMaxValue: Double {
        let dataMax = dataPoints.map(\.1).max() ?? 1
        let refMax = referenceLines.max() ?? dataMax
        return max(dataMax, refMax) * 1.05
    }

    // MARK: - Helpers

    private func normalizedPoints(in size: CGSize, minVal: Double, range: Double) -> [CGPoint] {
        guard let firstDate = dataPoints.first?.0,
              let lastDate = dataPoints.last?.0 else { return [] }

        let timeRange = lastDate.timeIntervalSince(firstDate)
        guard timeRange > 0 else { return [] }

        return dataPoints.map { date, value in
            let x = CGFloat(date.timeIntervalSince(firstDate) / timeRange) * size.width
            let y = size.height - CGFloat((value - minVal) / range) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private func buildLinePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        // Catmull-Rom smoothing for natural curves
        for i in 1..<points.count {
            let p0 = points[max(0, i - 2)]
            let p1 = points[i - 1]
            let p2 = points[i]
            let p3 = points[min(points.count - 1, i + 1)]

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        return path
    }

    private func xAxisLabels(width: CGFloat) -> some View {
        HStack {
            if let first = dataPoints.first?.0 {
                Text(formatAxisDate(first))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(SanctuaryColors.textMuted)
            }

            Spacer()

            if dataPoints.count > 2,
               let mid = dataPoints[safe: dataPoints.count / 2]?.0 {
                Text(formatAxisDate(mid))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(SanctuaryColors.textMuted)
            }

            Spacer()

            if let last = dataPoints.last?.0 {
                Text(formatAxisDate(last))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(SanctuaryColors.textMuted)
            }
        }
        .frame(height: 16)
        .offset(y: -16)
    }

    private func formatAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// NOTE: subscript(safe:) defined in SlashCommandMenu.swift — not duplicated here

// MARK: - Sanctuary Bar Chart

struct SanctuaryBarChart: View {
    let data: [(String, Double)]
    let accentColor: Color
    let maxValue: Double?

    init(
        data: [(String, Double)],
        accentColor: Color,
        maxValue: Double? = nil
    ) {
        self.data = data
        self.accentColor = accentColor
        self.maxValue = maxValue
    }

    var body: some View {
        let computedMax = maxValue ?? (data.map(\.1).max() ?? 1)

        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.8), accentColor.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 2,
                            maxHeight: .infinity
                        )
                        .scaleEffect(
                            y: computedMax > 0 ? CGFloat(item.1 / computedMax) : 0,
                            anchor: .bottom
                        )

                    Text(item.0)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(SanctuaryColors.textMuted)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SanctuaryChartView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            // Period selector
            ChartPeriodSelector(
                selected: .constant(.week),
                accentColor: SanctuaryColors.cognitive
            )

            // Line chart
            SanctuaryCard(size: .half, title: "FOCUS TREND", accentColor: SanctuaryColors.cognitive) {
                SanctuaryLineChart(
                    dataPoints: (0..<7).map { i in
                        (Calendar.current.date(byAdding: .day, value: i, to: Date())!,
                         Double.random(in: 60...95))
                    },
                    accentColor: SanctuaryColors.cognitive,
                    referenceLines: [75]
                )
                .frame(height: 120)
            }

            // Bar chart
            SanctuaryCard(size: .half, title: "WEEKLY BREAKDOWN") {
                SanctuaryBarChart(
                    data: [("M", 3), ("T", 5), ("W", 2), ("T", 7), ("F", 4), ("S", 1), ("S", 0)],
                    accentColor: SanctuaryColors.creative
                )
                .frame(height: 80)
            }
        }
        .padding(24)
        .background(Color(hex: "141422"))
        .preferredColorScheme(.dark)
    }
}
#endif
