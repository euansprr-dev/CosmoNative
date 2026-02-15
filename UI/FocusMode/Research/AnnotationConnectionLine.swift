// CosmoOS/UI/FocusMode/Research/AnnotationConnectionLine.swift
// Bezier connection line between annotation anchor and dragged card
// Adapted from SanctuaryConnectionThread pattern
// February 2026 - Research Focus Mode draggable annotations

import SwiftUI

// MARK: - Annotation Connection Line

/// A curved bezier connection line from an annotation's anchor point to its
/// dragged card position. Features a subtle glow, pulsing line width, and
/// a small anchor circle at the origin point.
struct AnnotationConnectionLine: View {
    /// Anchor point (original auto-positioned location)
    let from: CGPoint

    /// Current card position (after drag offset)
    let to: CGPoint

    /// Annotation type color
    let color: Color

    // MARK: - Layout Constants

    private enum Layout {
        static let baseWidth: CGFloat = 1.0
        static let maxWidth: CGFloat = 1.5
        static let glowBlur: CGFloat = 4.0
        static let glowOpacity: Double = 0.15
        static let anchorCircleSize: CGFloat = 6.0
        static let pulseCycleDuration: Double = 4.0
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let pulseT = sin(phase * (2.0 * .pi / Layout.pulseCycleDuration))
            let lineWidth = Layout.baseWidth + (Layout.maxWidth - Layout.baseWidth) * (pulseT + 1.0) / 2.0

            Canvas { ctx, size in
                // Build the bezier path
                let bezierPath = buildBezierPath()

                // Glow layer
                ctx.addFilter(.blur(radius: Layout.glowBlur))
                ctx.stroke(
                    bezierPath,
                    with: .color(color.opacity(Layout.glowOpacity)),
                    style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: .round)
                )
            }
            // Main stroke layer and anchor on top
            .overlay {
                // Main bezier line
                buildBezierShape()
                    .stroke(
                        color.opacity(0.4),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                // Anchor circle at the origin point
                Circle()
                    .fill(color.opacity(0.6))
                    .frame(width: Layout.anchorCircleSize, height: Layout.anchorCircleSize)
                    .position(from)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Bezier Path

    /// Builds the quadratic bezier path from anchor to card
    private func buildBezierPath() -> Path {
        Path { path in
            path.move(to: from)
            let control = controlPoint
            path.addQuadCurve(to: to, control: control)
        }
    }

    /// Shape version for SwiftUI overlay stroke
    private func buildBezierShape() -> Path {
        buildBezierPath()
    }

    /// Control point perpendicular to midpoint, offset by ~30% of distance
    private var controlPoint: CGPoint {
        let midPoint = CGPoint(
            x: (from.x + to.x) / 2,
            y: (from.y + to.y) / 2
        )
        let dx = to.x - from.x
        let dy = to.y - from.y
        let perpX = -dy * 0.3
        let perpY = dx * 0.3
        return CGPoint(x: midPoint.x + perpX, y: midPoint.y + perpY)
    }
}

// MARK: - Preview

#if DEBUG
struct AnnotationConnectionLine_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AnnotationConnectionLine(
                from: CGPoint(x: 200, y: 300),
                to: CGPoint(x: 400, y: 200),
                color: Color(hex: "#8B5CF6")
            )
            .frame(width: 600, height: 500)

            // Visual markers for from/to
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .position(x: 200, y: 300)

            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .position(x: 400, y: 200)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
