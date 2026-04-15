// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsArcVisualizationView.swift
// Visual narrative arc — energy curve chart with arc type badge

import SwiftUI
import Charts

struct PhysicsArcVisualizationView: View {
    let arcQuarks: ArcQuarks?
    let energyCurve: [Double]?
    @Binding var selectedSlide: Int?
    @State private var drawProgress: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            arcTypeBadge
            arcChart
            arcDescription
            dominantFrameRow
            tensionInfo
        }
        .padding(DS.space20)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
        .dsRestingShadow()
        .onAppear { withAnimation(.easeInOut(duration: 0.8)) { drawProgress = 1 } }
    }

    // MARK: - Arc Type Badge

    @ViewBuilder
    private var arcTypeBadge: some View {
        HStack(spacing: DS.space8) {
            if let shape = arcQuarks?.shape, !shape.isEmpty {
                let arcType = extractArcType(from: shape)
                CodexConceptTag(name: arcType, color: DS.entitySwipe)
            }
            if let reversals = arcQuarks?.winLossReversals, reversals > 0 {
                Label("\(reversals) reversals", systemImage: "arrow.up.arrow.down")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityLabel("\(reversals) reversals")
            }
            Spacer()
            Text("Narrative Arc")
                .dsSmallCapsLabel()
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var arcChart: some View {
        if let curve = energyCurve, !curve.isEmpty {
            energyCurveChart(curve)
        } else {
            fallbackArcShape
        }
    }

    @ViewBuilder
    private func energyCurveChart(_ curve: [Double]) -> some View {
        let dataPoints = curve.enumerated().map { ArcDataPoint(slide: $0.offset + 1, energy: $0.element * drawProgress) }

        Chart(dataPoints) { point in
            AreaMark(
                x: .value("Slide", point.slide),
                y: .value("Energy", point.energy)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [DS.entitySwipe.opacity(0.25), DS.entitySwipe.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Slide", point.slide),
                y: .value("Energy", point.energy)
            )
            .foregroundStyle(DS.entitySwipe)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)

            if selectedSlide == point.slide {
                PointMark(
                    x: .value("Slide", point.slide),
                    y: .value("Energy", point.energy)
                )
                .foregroundStyle(DS.entitySwipe)
                .symbolSize(40)
            }
        }
        .chartXScale(domain: 1 ... curve.count)
        .chartXAxis {
            AxisMarks(values: Array(1...curve.count)) {
                AxisValueLabel()
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(DS.borderSubtle)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(DS.borderSubtle)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x - geo[proxy.plotFrame!].origin.x
                                if let slide: Int = proxy.value(atX: x) {
                                    selectedSlide = max(1, min(slide, curve.count))
                                }
                            }
                            .onEnded { _ in selectedSlide = nil }
                    )
            }
        }
        .frame(height: 120)
        .accessibilityLabel("Energy curve chart showing narrative arc across \(curve.count) slides")
    }

    @ViewBuilder
    private var fallbackArcShape: some View {
        RoundedRectangle(cornerRadius: DS.radiusSmall)
            .fill(DS.entitySwipe.opacity(0.04))
            .frame(height: 60)
            .overlay {
                Text("No energy curve data")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
    }

    // MARK: - Description

    @ViewBuilder
    private var arcDescription: some View {
        if let shape = arcQuarks?.shape, !shape.isEmpty {
            Text(shape)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var tensionInfo: some View {
        if let tension = arcQuarks?.internalExternalTension, tension.present == true {
            HStack(spacing: DS.space6) {
                Image(systemName: "waveform.path.ecg")
                    .font(DS.caption)
                    .foregroundStyle(DS.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let peak = tension.peakSlide {
                        Text("Internal/External tension peaks @slide \(peak)")
                            .font(DS.caption)
                            .foregroundStyle(DS.red)
                    }
                    if let desc = tension.description, !desc.isEmpty {
                        Text(desc)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                    }
                }
            }
        }
    }

    // MARK: - Dominant Frame

    @ViewBuilder
    private var dominantFrameRow: some View {
        if let df = arcQuarks?.dominantFrame, let type = df.type, !type.isEmpty {
            HStack(spacing: DS.space6) {
                Image(systemName: "rectangle.3.group")
                    .font(DS.caption)
                    .foregroundStyle(DS.entitySwipe)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dominant Frame: \(type.replacingOccurrences(of: "_", with: " "))")
                        .font(DS.caption)
                        .foregroundStyle(DS.entitySwipe)
                    if let mechanism = df.mechanism, !mechanism.isEmpty {
                        Text(mechanism)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func extractArcType(from shape: String) -> String {
        let separators: [Character] = [":", ","]
        if let firstSep = shape.firstIndex(where: { separators.contains($0) }) {
            let prefix = String(shape[shape.startIndex..<firstSep]).trimmingCharacters(in: .whitespaces)
            if prefix.count <= 60 { return prefix.replacingOccurrences(of: "_", with: " ") }
        }
        return shape.replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Data Point

private struct ArcDataPoint: Identifiable {
    let slide: Int
    let energy: Double
    var id: Int { slide }
}
