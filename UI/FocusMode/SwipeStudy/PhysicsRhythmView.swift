// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsRhythmView.swift
// Triple stacked waveform charts: density bars + energy curve + info rate

import SwiftUI
import Charts

struct PhysicsRhythmView: View {
    let rhythm: RhythmData?
    @Binding var selectedSlide: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionHeader
            if let r = rhythm {
                rhythmContent(r)
            } else {
                emptyState
            }
        }
        .padding(DS.space20)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsRestingShadow()
    }

    // MARK: - Header & Empty

    private var sectionHeader: some View {
        Text("Rhythm & Pacing")
            .font(DS.smallCaps)
            .foregroundStyle(DS.green)
    }

    private var emptyState: some View {
        Text("No rhythm data")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
    }

    // MARK: - Main Content

    @ViewBuilder
    private func rhythmContent(_ r: RhythmData) -> some View {
        let density = r.densityWaveform ?? []
        let energy = r.energyCurve ?? []
        let infoRate = r.informationRate ?? []
        let silences = r.silenceSlides ?? []
        let hasEnergy = !energy.isEmpty
        let hasInfoRate = !infoRate.isEmpty

        let dataCount = max(density.count, energy.count, infoRate.count, 1)

        VStack(spacing: DS.space16) {
            if !density.isEmpty {
                densityChart(
                    density: density,
                    silences: silences,
                    hideXAxis: hasEnergy || hasInfoRate,
                    dataCount: dataCount
                )
            }
            if hasEnergy {
                energyChart(
                    energy: energy,
                    silences: silences,
                    hideXAxis: hasInfoRate,
                    dataCount: dataCount
                )
            }
            if hasInfoRate {
                infoRateChart(infoRate: infoRate, silences: silences, dataCount: dataCount)
            }
        }

        selectedSlideDetail(r)
        callouts(r)
    }

    // MARK: - Density Chart

    @ViewBuilder
    private func densityChart(
        density: [Double],
        silences: [Int],
        hideXAxis: Bool,
        dataCount: Int
    ) -> some View {
        chartContainer(label: "Density", hideXAxis: hideXAxis, dataCount: dataCount) {
            Chart {
                ForEach(Array(density.enumerated()), id: \.offset) { index, value in
                    BarMark(
                        x: .value("Slide", index + 1),
                        y: .value("Density", value)
                    )
                    .foregroundStyle(
                        silences.contains(index + 1)
                            ? DS.info.opacity(0.3)
                            : DS.entitySwipe.opacity(0.6)
                    )
                }
                ForEach(silences, id: \.self) { slide in
                    RuleMark(x: .value("Silence", slide))
                        .foregroundStyle(DS.info.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                if let s = selectedSlide {
                    RuleMark(x: .value("Selected", s))
                        .foregroundStyle(DS.green.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartOverlay { proxy in hoverOverlay(proxy: proxy) }
        }
    }

    // MARK: - Energy Chart

    @ViewBuilder
    private func energyChart(
        energy: [Double],
        silences: [Int],
        hideXAxis: Bool,
        dataCount: Int
    ) -> some View {
        chartContainer(label: "Energy", hideXAxis: hideXAxis, dataCount: dataCount) {
            Chart {
                ForEach(Array(energy.enumerated()), id: \.offset) { index, value in
                    AreaMark(
                        x: .value("Slide", index + 1),
                        y: .value("Energy", value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(DS.green.opacity(0.15))

                    LineMark(
                        x: .value("Slide", index + 1),
                        y: .value("Energy", value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(DS.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(silences, id: \.self) { slide in
                    RuleMark(x: .value("Silence", slide))
                        .foregroundStyle(DS.info.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                if let s = selectedSlide {
                    RuleMark(x: .value("Selected", s))
                        .foregroundStyle(DS.green.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartOverlay { proxy in hoverOverlay(proxy: proxy) }
        }
    }

    // MARK: - Information Rate Chart

    @ViewBuilder
    private func infoRateChart(infoRate: [Double], silences: [Int], dataCount: Int) -> some View {
        chartContainer(label: "Info Rate", hideXAxis: false, dataCount: dataCount) {
            Chart {
                ForEach(Array(infoRate.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Slide", index + 1),
                        y: .value("Info Rate", value)
                    )
                    .foregroundStyle(DS.info)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                ForEach(silences, id: \.self) { slide in
                    RuleMark(x: .value("Silence", slide))
                        .foregroundStyle(DS.info.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                if let s = selectedSlide {
                    RuleMark(x: .value("Selected", s))
                        .foregroundStyle(DS.green.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartOverlay { proxy in hoverOverlay(proxy: proxy) }
        }
    }

    // MARK: - Chart Container

    @ViewBuilder
    private func chartContainer<C: View>(
        label: String,
        hideXAxis: Bool,
        dataCount: Int,
        @ViewBuilder chart: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            chart()
                .frame(height: 60)
                .chartXScale(domain: 1 ... dataCount)
                .chartXAxis(hideXAxis ? .hidden : .automatic)
                .chartYAxis(.hidden)
        }
    }

    // MARK: - Selected Slide Detail

    @ViewBuilder
    private func selectedSlideDetail(_ r: RhythmData) -> some View {
        if let slide = selectedSlide {
            let density = r.densityWaveform ?? []
            let energy = r.energyCurve ?? []
            let infoRate = r.informationRate ?? []
            let index = slide - 1
            let isSilence = (r.silenceSlides ?? []).contains(slide)

            VStack(alignment: .leading, spacing: DS.space4) {
                Text("Slide \(slide)")
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                HStack(spacing: DS.space16) {
                    if index >= 0, index < density.count {
                        detailMetric(label: "Density", value: String(format: "%.0f", density[index]), color: DS.entitySwipe)
                    }
                    if index >= 0, index < energy.count {
                        detailMetric(label: "Energy", value: String(format: "%.1f", energy[index]), color: DS.green)
                    }
                    if index >= 0, index < infoRate.count {
                        detailMetric(label: "Info Rate", value: String(format: "%.1f", infoRate[index]), color: DS.info)
                    }
                    if isSilence {
                        detailMetric(label: "Type", value: "Silence", color: DS.info)
                    }
                }
            }
            .padding(DS.space10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func detailMetric(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DS.callout)
                .foregroundStyle(color)
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Hover Overlay

    private func hoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = value.location.x - geo[plotFrame].origin.x
                            if let slide: Int = proxy.value(atX: x) {
                                selectedSlide = max(1, slide)
                            }
                        }
                        .onEnded { _ in
                            selectedSlide = nil
                        }
                )
        }
    }

    // MARK: - Callouts

    @ViewBuilder
    private func callouts(_ r: RhythmData) -> some View {
        if let momentum = r.momentumMechanism, !momentum.isEmpty {
            calloutBlock(label: "Momentum", text: momentum)
        }
        if let pattern = r.pacingPattern, !pattern.isEmpty {
            calloutBlock(label: "Pacing", text: pattern)
        }
    }

    @ViewBuilder
    private func calloutBlock(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(label)
                .font(DS.caption)
                .fontWeight(.semibold)
                .foregroundStyle(DS.green)

            Text(text)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
