// CosmoOS/UI/Codex/CodexFrequencyIndicator.swift
// Visual frequency indicator — compact bar for cards, full ring for detail views.

import SwiftUI

struct CodexFrequencyIndicator: View {
    let frequency: String?
    let color: Color
    let mode: Mode

    enum Mode {
        case compact  // thin horizontal bar for cards
        case full     // circular ring for detail views
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
            case .compact: compactBar(data)
            case .full: fullRing(data)
            }
        }
    }

    // MARK: - Compact Bar

    private func compactBar(_ data: (numerator: Int, denominator: Int, ratio: Double)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            frequencyBarTrack(data)
            frequencyBarLabel(data)
        }
        .onAppear {
            withAnimation(ProMotionSprings.gentle) {
                animatedRatio = data.ratio
            }
        }
    }

    private func frequencyBarTrack(_ data: (numerator: Int, denominator: Int, ratio: Double)) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.12))
                    .frame(height: 4)
                Capsule()
                    .fill(color.opacity(0.6))
                    .frame(width: geo.size.width * animatedRatio, height: 4)
            }
        }
        .frame(height: 4)
    }

    private func frequencyBarLabel(_ data: (numerator: Int, denominator: Int, ratio: Double)) -> some View {
        Text("\(data.numerator)/\(data.denominator)")
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
    }

    // MARK: - Full Ring

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
            .stroke(color.opacity(0.12), lineWidth: 4)
    }

    private func ringForeground(_ data: (numerator: Int, denominator: Int, ratio: Double)) -> some View {
        Circle()
            .trim(from: 0, to: animatedRatio)
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    private func ringLabel(_ data: (numerator: Int, denominator: Int, ratio: Double)) -> some View {
        VStack(spacing: 0) {
            Text("\(Int(data.ratio * 100))")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
            Text("%")
                .font(.system(size: 9))
                .foregroundStyle(DS.textMuted)
        }
    }
}
