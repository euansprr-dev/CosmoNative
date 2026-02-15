// CosmoOS/UI/Sanctuary/Dimensions/Creative/PipelineFunnelView.swift
// Pipeline funnel visualization showing content counts across phases
// Phase 4: Creative Dashboard Integration

import SwiftUI

struct PipelineFunnelView: View {
    let funnelData: [(phase: ContentPhase, count: Int)]

    private var maxCount: Int {
        funnelData.map(\.count).max() ?? 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                Text("Content Pipeline")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.bottom, 16)

            // Funnel chevrons
            ForEach(Array(funnelData.enumerated()), id: \.element.phase) { index, entry in
                funnelChevron(phase: entry.phase, count: entry.count, index: index)

                if index < funnelData.count - 1 {
                    conversionArrow(from: entry.count, to: funnelData[index + 1].count)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Chevron

    @ViewBuilder
    private func funnelChevron(phase: ContentPhase, count: Int, index: Int) -> some View {
        let widthFraction = maxCount > 0 ? max(0.3, Double(count) / Double(maxCount)) : 0.3
        let color = phaseColor(index: index, total: funnelData.count)

        HStack(spacing: 10) {
            Image(systemName: phase.iconName)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 20)

            Text(phase.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Text("\(count)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            ChevronShape()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.15), color.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: CGFloat(widthFraction) * 300 + 60)
                .frame(maxWidth: .infinity, alignment: .leading)
        )
        .overlay(
            ChevronShape()
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Conversion Arrow

    @ViewBuilder
    private func conversionArrow(from: Int, to: Int) -> some View {
        let rate: String = {
            guard from > 0, to > 0 else { return "" }
            let percentage = Double(to) / Double(from) * 100
            return String(format: "%.0f%%", min(percentage, 100))
        }()

        HStack {
            Spacer()
            if !rate.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(rate)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
        }
        .frame(height: 16)
    }

    // MARK: - Phase Color

    private func phaseColor(index: Int, total: Int) -> Color {
        guard total > 1 else { return .blue }
        let t = Double(index) / Double(total - 1)
        // Blend from blue (early) to green (late)
        return Color(
            red: 0.2 * (1 - t) + 0.06 * t,
            green: 0.4 * (1 - t) + 0.78 * t,
            blue: 0.9 * (1 - t) + 0.45 * t
        )
    }
}

// MARK: - Chevron Shape

private struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        let arrowDepth: CGFloat = 8
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width - arrowDepth, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width - arrowDepth, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: arrowDepth, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
