// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsRhythmView.swift
// Density waveform + energy curve + silence markers

import SwiftUI

struct PhysicsRhythmView: View {
    let rhythm: RhythmData?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text("RHYTHM & PACING")
                .font(DS.caption)
                .tracking(1.2)
                .foregroundStyle(DS.textMuted)

            if let r = rhythm {
                densityBars(r)
                momentumText(r)
                silenceMarkers(r)
            } else {
                Text("No rhythm data")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
    }

    @ViewBuilder
    private func densityBars(_ r: RhythmData) -> some View {
        let density = r.densityWaveform ?? []
        let energy = r.energyCurve ?? []
        let maxDensity = max(density.max() ?? 1.0, 1.0)

        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(density.enumerated()), id: \.offset) { index, wordCount in
                    let height = max(CGFloat(wordCount / maxDensity) * 40, 4)
                    let energyLevel = index < energy.count ? Int(energy[index]) : 3
                    let silence = (r.silenceSlides ?? []).contains(index + 1)

                    VStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(energyLevel: energyLevel, isSilence: silence))
                            .frame(height: height)

                        if density.count <= 30 {
                            Text("\(index + 1)")
                                .font(.system(size: 6, design: .monospaced))
                                .foregroundStyle(DS.textMuted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56)

            // Legend
            HStack(spacing: DS.space10) {
                legendDot(color: DS.green, label: "High energy")
                legendDot(color: DS.entitySwipe, label: "Medium")
                legendDot(color: DS.textMuted.opacity(0.4), label: "Low")
                legendDot(color: DS.info.opacity(0.3), label: "Silence")
            }
            .font(.system(size: 8))
        }
    }

    @ViewBuilder
    private func momentumText(_ r: RhythmData) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            if let momentum = r.momentumMechanism, !momentum.isEmpty {
                HStack(alignment: .top, spacing: DS.space6) {
                    Text("Momentum")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                    Text(momentum)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
            }
            if let pattern = r.pacingPattern, !pattern.isEmpty {
                HStack(alignment: .top, spacing: DS.space6) {
                    Text("Pattern")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                    Text(pattern)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func silenceMarkers(_ r: RhythmData) -> some View {
        if let silenceSlides = r.silenceSlides, !silenceSlides.isEmpty {
            HStack(spacing: DS.space4) {
                Text("🫧")
                    .font(.system(size: 10))
                Text("Silence slides: \(silenceSlides.map(String.init).joined(separator: ", "))")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(DS.textMuted)
        }
    }

    private func barColor(energyLevel: Int, isSilence: Bool) -> Color {
        if isSilence { return DS.info.opacity(0.3) }
        switch energyLevel {
        case 5: return DS.green
        case 4: return DS.green.opacity(0.7)
        case 3: return DS.entitySwipe
        case 2: return DS.textMuted.opacity(0.5)
        default: return DS.textMuted.opacity(0.3)
        }
    }
}
