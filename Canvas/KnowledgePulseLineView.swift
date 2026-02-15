// CosmoOS/Canvas/KnowledgePulseLineView.swift
// Animated bezier connection line between related blocks on the canvas
// Adapted from SanctuaryConnectionThread pattern — quadratic bezier with glow layers

import SwiftUI

/// A single animated bezier pulse line between two canvas blocks.
/// Renders with GPU-accelerated Canvas view, energy pulse via TimelineView.
struct KnowledgePulseLineView: View {

    // MARK: - Properties

    /// Start point (source block center, in canvas coordinates)
    let from: CGPoint

    /// End point (target block center, in canvas coordinates)
    let to: CGPoint

    /// Edge weight (0.0-1.0) — controls opacity and thickness
    let weight: Double

    /// Edge type — controls color
    let edgeType: GraphEdgeType

    /// Animation phase (from TimelineView timeIntervalSinceReferenceDate)
    let animationPhase: Double

    // MARK: - Layout Constants

    private enum Layout {
        static let baseWidth: CGFloat = 1.5
        static let maxWidth: CGFloat = 3.5
        static let glowBlur: CGFloat = 4         // Reduced 50% from 8
        static let glowWidthMultiplier: CGFloat = 3.0
        static let curveOffsetFactor: CGFloat = 0.15
        static let pulseSpeed: Double = 0.192     // 30% slower (0.25 / 1.3)
        static let widthModulationSpeed: Double = 0.308 // 30% slower (0.4 / 1.3)
        static let widthModulationAmount: CGFloat = 0.15
    }

    // MARK: - Computed Properties

    /// Unified Onyx iris color for all connection types
    private var lineColor: Color {
        OnyxColors.Accent.iris
    }

    /// Line width scaled by weight
    private var lineWidth: CGFloat {
        let base = Layout.baseWidth + CGFloat(weight) * (Layout.maxWidth - Layout.baseWidth)
        let modulation = Layout.widthModulationAmount * CGFloat(sin(animationPhase * Layout.widthModulationSpeed))
        return base + modulation
    }

    /// Base opacity scaled by weight — reduced for Onyx subtlety (0.20 - 0.45)
    private var baseOpacity: Double {
        0.20 + weight * 0.25
    }

    /// Control point for quadratic bezier — perpendicular offset from midpoint
    private var controlPoint: CGPoint {
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2

        // Perpendicular direction based on line angle
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return CGPoint(x: midX, y: midY) }

        // Perpendicular offset (normalized), scaled by line length
        let perpX = -dy / length
        let perpY = dx / length
        let offset = length * Layout.curveOffsetFactor

        // Consistent curve direction based on source/target ordering
        let direction: CGFloat = from.x + from.y < to.x + to.y ? 1 : -1

        return CGPoint(
            x: midX + perpX * offset * direction,
            y: midY + perpY * offset * direction
        )
    }

    /// Gradient progress for energy pulse (0-1)
    private var pulseProgress: CGFloat {
        CGFloat((animationPhase * Layout.pulseSpeed).truncatingRemainder(dividingBy: 1.0))
    }

    /// Energy flow gradient stops — clamped and ascending
    private var energyFlowStops: [Gradient.Stop] {
        let p = pulseProgress
        let stop1 = max(0, min(p, 0.79))
        let stop2 = max(stop1 + 0.001, min(p + 0.08, 0.89))
        let stop3 = max(stop2 + 0.001, min(p + 0.16, 0.99))

        return [
            .init(color: lineColor.opacity(baseOpacity * 0.3), location: 0),
            .init(color: lineColor.opacity(baseOpacity), location: stop1),
            .init(color: Color.white.opacity(baseOpacity * 1.2), location: stop2),
            .init(color: lineColor.opacity(baseOpacity), location: stop3),
            .init(color: lineColor.opacity(baseOpacity * 0.3), location: 1)
        ]
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Glow layer (blurred, wider stroke)
            connectionPath
                .stroke(
                    lineColor.opacity(baseOpacity * 0.5),
                    style: StrokeStyle(
                        lineWidth: lineWidth * Layout.glowWidthMultiplier,
                        lineCap: .round
                    )
                )
                .blur(radius: Layout.glowBlur)

            // Main line with energy flow gradient
            connectionPath
                .stroke(
                    LinearGradient(
                        stops: energyFlowStops,
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
        }
        // Fill parent so Path coordinates are absolute within the overlay
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Path

    /// Quadratic bezier path from source to target
    private var connectionPath: Path {
        Path { path in
            path.move(to: from)
            path.addQuadCurve(to: to, control: controlPoint)
        }
    }
}
