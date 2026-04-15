// CosmoOS/UI/Codex/CodexFrequencyIndicator.swift
// Visual frequency indicator — constellation dots for cards, gilt ring for detail views.
// April 2026 — Akashic Records Premium Redesign

import SwiftUI

struct CodexFrequencyIndicator: View {
    let frequency: String?
    let color: Color
    let mode: Mode

    enum Mode {
        case compact  // constellation dots for cards
        case full     // gilt circular ring for detail views
    }

    @State private var animatedRatio: Double = 0

    private var parsed: (numerator: Int, denominator: Int, ratio: Double)? {
        guard let freq = frequency else { return nil }
        let parts = freq.split(separator: "/")
        guard parts.count == 2,
              let num = Int(parts[0]),
              let den = Int(parts[1]),
              den > 0 else { return nil }
        return (num, den, Double(num) / Double(den))
    }

    var body: some View {
        if let data = parsed {
            switch mode {
            case .compact:
                ConstellationDots(frequency: frequency)
            case .full:
                fullRing(data)
            }
        }
    }

    // MARK: - Full Ring (gilt-styled)

    private func fullRing(_ data: (numerator: Int, denominator: Int, ratio: Double)) -> some View {
        ZStack {
            ringBackground
            ringForeground(data)
            ringLabel(data)
        }
        .frame(width: 56, height: 56)
        .onAppear {
            withAnimation(ProMotionSprings.gentle.delay(0.2)) {
                animatedRatio = data.ratio
            }
        }
    }

    private var ringBackground: some View {
        Circle()
            .stroke(DS.sepiaBorder, lineWidth: 3)
    }

    private func ringForeground(_ data: (numerator: Int, denominator: Int, ratio: Double)) -> some View {
        Circle()
            .trim(from: 0, to: animatedRatio)
            .stroke(DS.gilt, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    private func ringLabel(_ data: (numerator: Int, denominator: Int, ratio: Double)) -> some View {
        VStack(spacing: 0) {
            Text("\(Int(data.ratio * 100))")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.inkWash)
            Text("%")
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)
        }
    }
}
