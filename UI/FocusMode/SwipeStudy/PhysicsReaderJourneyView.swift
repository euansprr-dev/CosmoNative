// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsReaderJourneyView.swift
// Reader investment trajectory — Swift Charts area chart with physics event overlays

import Charts
import SwiftUI

struct PhysicsReaderJourneyView: View {
    let simulation: [ReaderState]
    let rsvPoints: [RSVPoint]
    let physicsEvents: PhysicsEvents?
    @Binding var selectedSlide: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionHeader
            if !simulation.isEmpty {
                investmentChart
                chartLegend
                selectedSlideDetail
            } else if !rsvPoints.isEmpty {
                rsvSummary
            } else {
                emptyState
            }
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
        .dsRestingShadow()
    }
}

// MARK: - Header & Empty State

private extension PhysicsReaderJourneyView {
    var sectionHeader: some View {
        Text("READER JOURNEY")
            .font(DS.caption)
            .tracking(1.2)
            .foregroundStyle(DS.orange)
    }

    var emptyState: some View {
        Text("No reader simulation data")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
    }
}

// MARK: - Investment Chart

private extension PhysicsReaderJourneyView {
    var investmentChart: some View {
        Chart {
            chartAreaAndLine
            chartSelectedPoint
            chartEventRules
        }
        .frame(height: 160)
        .chartXScale(domain: 1 ... max(simulation.map(\.afterSlide).max() ?? 1, 1))
        .chartYScale(domain: 0.5 ... 4.5)
        .chartYAxis { yAxisContent }
        .chartXAxis { xAxisContent }
        .chartOverlay { proxy in
            chartDragOverlay(proxy: proxy)
        }
    }

    @ChartContentBuilder
    var chartAreaAndLine: some ChartContent {
        ForEach(simulation) { state in
            AreaMark(
                x: .value("Slide", state.afterSlide),
                y: .value("Investment", numericLevel(for: state.investmentLevel))
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [DS.orange.opacity(0.4), DS.orange.opacity(0.08)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Slide", state.afterSlide),
                y: .value("Investment", numericLevel(for: state.investmentLevel))
            )
            .foregroundStyle(DS.orange)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    var chartSelectedPoint: some ChartContent {
        if let slide = selectedSlide,
           let state = simulation.first(where: { $0.afterSlide == slide }) {
            PointMark(
                x: .value("Slide", state.afterSlide),
                y: .value("Investment", numericLevel(for: state.investmentLevel))
            )
            .foregroundStyle(DS.orange)
            .symbolSize(64)
        }
    }

    @ChartContentBuilder
    var chartEventRules: some ChartContent {
        if let events = physicsEvents {
            if let brk = events.symmetryBreak?.slideNumber, brk > 0 {
                RuleMark(x: .value("Event", brk))
                    .foregroundStyle(DS.orange.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let pt = events.phaseTransition?.slideNumber, pt > 0 {
                RuleMark(x: .value("Event", pt))
                    .foregroundStyle(DS.info.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let pg = events.peakGravity?.slideNumber, pg > 0 {
                RuleMark(x: .value("Event", pg))
                    .foregroundStyle(DS.entitySwipe.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }

    @AxisContentBuilder
    var yAxisContent: some AxisContent {
        AxisMarks(values: [1, 2, 3, 4]) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(DS.border)
            AxisValueLabel {
                Text(yAxisLabel(for: value.as(Int.self) ?? 1))
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    @AxisContentBuilder
    var xAxisContent: some AxisContent {
        AxisMarks(values: Array(simulation.map(\.afterSlide))) { value in
            AxisValueLabel {
                if let slide = value.as(Int.self) {
                    Text("\(slide)")
                        .font(DS.caption2)
                        .monospacedDigit()
                        .foregroundStyle(DS.textMuted)
                }
            }
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(DS.borderSubtle)
        }
    }

    func chartDragOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let origin = geometry[proxy.plotFrame!].origin
                            let location = CGPoint(
                                x: drag.location.x - origin.x,
                                y: drag.location.y - origin.y
                            )
                            if let slideValue: Int = proxy.value(atX: location.x) {
                                let nearest = simulation
                                    .min(by: { abs($0.afterSlide - slideValue) < abs($1.afterSlide - slideValue) })
                                withAnimation(.snappy(duration: 0.15)) {
                                    selectedSlide = nearest?.afterSlide
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.snappy(duration: 0.15)) {
                                selectedSlide = nil
                            }
                        }
                )
        }
    }
}

// MARK: - Legend

private extension PhysicsReaderJourneyView {
    var chartLegend: some View {
        HStack(spacing: DS.space12) {
            legendItem(color: DS.orange, label: "Investment", dashed: false)
            if physicsEvents != nil {
                legendItem(color: DS.info, label: "Open Loops", dashed: true)
            }
        }
    }

    func legendItem(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            if dashed {
                dashedLegendLine(color: color)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 14, height: 3)
            }
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    func dashedLegendLine(color: Color) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: 2)
            }
        }
        .frame(width: 14)
    }
}

// MARK: - Selected Slide Detail

private extension PhysicsReaderJourneyView {
    @ViewBuilder
    var selectedSlideDetail: some View {
        if let slideNum = selectedSlide,
           let state = simulation.first(where: { $0.afterSlide == slideNum }) {
            slideDetailCard(slideNum: slideNum, state: state)
                .transition(.opacity)
        }
    }

    func slideDetailCard(slideNum: Int, state: ReaderState) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text("After Slide \(slideNum)")
                .font(DS.headline)
                .foregroundStyle(DS.text)

            detailFields(state: state)
            questionsSection(state: state)
            assumptionsSection(state: state)
        }
        .padding(DS.space12)
        .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    @ViewBuilder
    func detailFields(state: ReaderState) -> some View {
        if let emotion = state.dominantEmotion {
            detailRow(label: "Emotion", value: emotion, color: DS.entitySwipe)
        }
        if let investment = state.investmentLevel {
            detailRow(label: "Investment", value: investment, color: DS.orange)
        }
        if let prediction = state.prediction, !prediction.isEmpty {
            detailRow(label: "Predicts", value: prediction, color: DS.info)
        }
    }

    @ViewBuilder
    func questionsSection(state: ReaderState) -> some View {
        if let questions = state.activeQuestions, !questions.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open Questions (\(questions.count))")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                ForEach(questions.prefix(5), id: \.self) { q in
                    Text("- \(q)")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    func assumptionsSection(state: ReaderState) -> some View {
        if let assumptions = state.builtAssumptions, !assumptions.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Assumptions Built")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                ForEach(assumptions.prefix(3), id: \.self) { a in
                    Text("- \(a)")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
    }

    func detailRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: DS.space6) {
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .frame(width: 65, alignment: .leading)
            Text(value)
                .font(DS.callout)
                .foregroundStyle(color)
        }
    }
}

// MARK: - RSV Fallback

private extension PhysicsReaderJourneyView {
    var rsvSummary: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(rsvPoints) { point in
                rsvRow(point: point)
            }
        }
    }

    func rsvRow(point: RSVPoint) -> some View {
        HStack(spacing: DS.space8) {
            Text("@\(point.afterSlide)")
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .frame(width: 30)
            if let loops = point.openLoops {
                Text("\(loops.count) loops")
                    .font(DS.caption2)
                    .foregroundStyle(DS.info)
            }
            if let trust = point.trust {
                Text(trust)
                    .font(DS.caption2)
                    .foregroundStyle(DS.green)
            }
            if let frame = point.frame {
                Text(frame)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }
}

// MARK: - Helpers

private extension PhysicsReaderJourneyView {
    func numericLevel(for level: String?) -> Int {
        switch (level ?? "low").lowercased() {
        case "locked-in", "locked in": return 4
        case "high": return 3
        case "medium", "building": return 2
        default: return 1
        }
    }

    func yAxisLabel(for value: Int) -> String {
        switch value {
        case 1: return "Low"
        case 2: return "Med"
        case 3: return "High"
        case 4: return "Locked"
        default: return ""
        }
    }
}
