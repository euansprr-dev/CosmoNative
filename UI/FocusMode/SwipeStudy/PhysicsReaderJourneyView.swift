// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsReaderJourneyView.swift
// Reader state vector trajectory — multi-line visualization + tap for detail

import SwiftUI

struct PhysicsReaderJourneyView: View {
    let simulation: [ReaderState]
    let rsvPoints: [RSVPoint]
    let physicsEvents: PhysicsEvents?

    @State private var selectedSlide: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text("READER JOURNEY")
                .font(DS.caption)
                .tracking(1.2)
                .foregroundStyle(DS.textMuted)

            if !simulation.isEmpty {
                readerChart
                selectedDetail
            } else if !rsvPoints.isEmpty {
                rsvSummary
            } else {
                Text("No reader simulation data")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
    }

    @ViewBuilder
    private var readerChart: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            // Investment progression as colored bar segments
            HStack(spacing: 0) {
                ForEach(simulation) { state in
                    let isSelected = selectedSlide == state.afterSlide
                    Rectangle()
                        .fill(investmentColor(state.investmentLevel ?? "low"))
                        .frame(height: 24)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(DS.accent, lineWidth: 2)
                            }
                        }
                        .onTapGesture {
                            withAnimation(.spring(response: 0.2)) {
                                selectedSlide = isSelected ? nil : state.afterSlide
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXSmall))

            // Slide number labels
            HStack(spacing: 0) {
                ForEach(simulation) { state in
                    Text("\(state.afterSlide)")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(DS.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            // Physics event markers
            eventMarkers

            // Legend
            HStack(spacing: DS.space12) {
                legendItem(color: DS.textMuted.opacity(0.3), label: "Low")
                legendItem(color: DS.info.opacity(0.5), label: "Medium")
                legendItem(color: DS.orange.opacity(0.7), label: "High")
                legendItem(color: DS.red, label: "Locked In")
            }
            .font(.system(size: 9))
        }
    }

    @ViewBuilder
    private var eventMarkers: some View {
        if let events = physicsEvents {
            HStack(spacing: DS.space8) {
                if let brk = events.symmetryBreak?.slideNumber, brk > 0 {
                    Text("⚡ Break @\(brk)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.orange)
                }
                if let pt = events.phaseTransition?.slideNumber, pt > 0 {
                    Text("🔮 Transition @\(pt)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.info)
                }
                if let pg = events.peakGravity?.slideNumber, pg > 0 {
                    Text("🌀 Gravity @\(pg)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.entitySwipe)
                }
            }
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let slideNum = selectedSlide, let state = simulation.first(where: { $0.afterSlide == slideNum }) {
            VStack(alignment: .leading, spacing: DS.space6) {
                Text("After Slide \(slideNum)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)

                if let emotion = state.dominantEmotion {
                    detailRow(label: "Emotion", value: emotion, color: DS.entitySwipe)
                }
                if let investment = state.investmentLevel {
                    detailRow(label: "Investment", value: investment, color: investmentColor(investment))
                }
                if let prediction = state.prediction, !prediction.isEmpty {
                    detailRow(label: "Predicts", value: prediction, color: DS.info)
                }
                if let questions = state.activeQuestions, !questions.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Questions (\(questions.count))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.textMuted)
                        ForEach(questions.prefix(5), id: \.self) { q in
                            Text("• \(q)")
                                .font(DS.caption2)
                                .foregroundStyle(DS.textSecondary)
                        }
                    }
                }
                if let assumptions = state.builtAssumptions, !assumptions.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assumptions Built")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.textMuted)
                        ForEach(assumptions.prefix(3), id: \.self) { a in
                            Text("• \(a)")
                                .font(DS.caption2)
                                .foregroundStyle(DS.textSecondary)
                        }
                    }
                }
            }
            .padding(DS.space12)
            .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var rsvSummary: some View {
        ForEach(rsvPoints) { point in
            HStack(spacing: DS.space8) {
                Text("@\(point.afterSlide)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.text)
                    .frame(width: 30)
                if let loops = point.openLoops {
                    Text("\(loops.count) loops")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.info)
                }
                if let trust = point.trust {
                    Text(trust)
                        .font(.system(size: 9))
                        .foregroundStyle(DS.green)
                }
                if let frame = point.frame {
                    Text(frame)
                        .font(.system(size: 9))
                        .foregroundStyle(DS.textMuted)

                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: DS.space6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 65, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 8)
            Text(label)
                .foregroundStyle(DS.textMuted)
        }
    }

    private func investmentColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "locked-in", "locked in": return DS.red
        case "high": return DS.orange.opacity(0.7)
        case "medium", "building": return DS.info.opacity(0.5)
        default: return DS.textMuted.opacity(0.3)
        }
    }
}
