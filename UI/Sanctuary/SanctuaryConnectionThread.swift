// CosmoOS/UI/Sanctuary/SanctuaryConnectionThread.swift
// Sanctuary Connection Thread - Curved bezier connections between satellites and core
// Apple-level quality with animated glow and energy flow

import SwiftUI

/// A curved bezier connection line between a satellite node and the Sanctuary core.
/// Features:
/// - Curved bezier path (not straight line)
/// - Subtle glow effect (4pt blur, 10% opacity)
/// - Width modulation animation (1pt → 1.5pt → 1pt, 6s cycle)
/// - Energy flow animation (gradient traveling along line)
/// - Diamond waypoint markers that pulse
public struct SanctuaryConnectionThread: View {

    // MARK: - Properties

    /// Start point of the connection (satellite position)
    let from: CGPoint

    /// End point of the connection (hero orb center)
    let to: CGPoint

    /// Primary color of the connection (satellite color)
    let color: Color

    /// Whether the connection is active (hovered/selected)
    let isActive: Bool

    /// Animation phase for continuous animations
    let animationPhase: Double

    // MARK: - Layout Constants

    private enum Layout {
        static let baseWidth: CGFloat = 1.0
        static let activeWidth: CGFloat = 1.5
        static let glowBlur: CGFloat = 4
        static let curveOffset: CGFloat = SanctuaryLayout.connectionCurveOffset
        static let waypointSize: CGFloat = 4
    }

    // MARK: - Computed Properties

    /// Animated line width (subtle modulation)
    private var lineWidth: CGFloat {
        let base = isActive ? Layout.activeWidth : Layout.baseWidth
        let modulation: CGFloat = 0.3
        return base + modulation * CGFloat(sin(animationPhase * 0.5))
    }

    /// Opacity based on state
    private var threadOpacity: Double {
        isActive ? 0.4 : 0.15
    }

    /// Control point for bezier curve
    private var controlPoint: CGPoint {
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2

        // Curve direction: up for left satellite, down for right satellite
        let curveDirection: CGFloat = from.x < to.x ? -1 : 1
        let curveY = midY + (Layout.curveOffset * curveDirection)

        return CGPoint(x: midX, y: curveY)
    }

    /// Gradient progress for energy flow animation (0-1)
    private var gradientProgress: CGFloat {
        CGFloat((animationPhase * 0.3).truncatingRemainder(dividingBy: 1.0))
    }

    /// Energy flow gradient stops - properly clamped and ordered to avoid SwiftUI warnings
    private var energyFlowStops: [Gradient.Stop] {
        let p = gradientProgress
        // Clamp all stops to valid range and ensure ascending order
        let stop1 = max(0, min(p, 0.79))
        let stop2 = max(stop1 + 0.001, min(p + 0.1, 0.89))
        let stop3 = max(stop2 + 0.001, min(p + 0.2, 0.99))

        return [
            .init(color: color.opacity(threadOpacity * 0.3), location: 0),
            .init(color: color.opacity(threadOpacity), location: stop1),
            .init(color: Color.white.opacity(threadOpacity * 1.5), location: stop2),
            .init(color: color.opacity(threadOpacity), location: stop3),
            .init(color: color.opacity(threadOpacity * 0.3), location: 1)
        ]
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Glow layer (blurred version of the path)
            connectionPath
                .stroke(
                    color.opacity(0.15),
                    style: StrokeStyle(
                        lineWidth: lineWidth * 3,
                        lineCap: .round
                    )
                )
                .blur(radius: Layout.glowBlur)

            // Main connection line with gradient
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

            // Waypoint diamonds along the path
            waypointMarkers
        }
        .drawingGroup()  // Rasterize glow blur + gradient to GPU texture
        .animation(SanctuarySprings.smooth, value: isActive)
    }

    // MARK: - Path

    /// The curved bezier path
    private var connectionPath: Path {
        Path { path in
            path.move(to: from)
            path.addQuadCurve(to: to, control: controlPoint)
        }
    }

    // MARK: - Waypoint Markers

    /// Diamond waypoint markers along the path
    private var waypointMarkers: some View {
        // Place 3 waypoints along the path
        ForEach(0..<3, id: \.self) { index in
            let t = CGFloat(index + 1) / 4.0
            let position = pointOnBezier(t: t)

            // Diamond shape
            Diamond()
                .fill(color.opacity(waypointOpacity(at: index)))
                .frame(width: Layout.waypointSize, height: Layout.waypointSize)
                .rotationEffect(.degrees(45))
                .position(position)
                .scaleEffect(waypointScale(at: index))
        }
    }

    /// Calculate point on quadratic bezier at parameter t
    private func pointOnBezier(t: CGFloat) -> CGPoint {
        let oneMinusT = 1 - t
        let x = oneMinusT * oneMinusT * from.x +
                2 * oneMinusT * t * controlPoint.x +
                t * t * to.x
        let y = oneMinusT * oneMinusT * from.y +
                2 * oneMinusT * t * controlPoint.y +
                t * t * to.y
        return CGPoint(x: x, y: y)
    }

    /// Waypoint opacity based on animation phase (pulsing)
    private func waypointOpacity(at index: Int) -> Double {
        let base: Double = isActive ? 0.6 : 0.3
        let phase = animationPhase + Double(index) * 0.3
        let pulse = sin(phase * 2) * 0.2
        return base + pulse
    }

    /// Waypoint scale based on animation phase (subtle pulse)
    private func waypointScale(at index: Int) -> CGFloat {
        let base: CGFloat = 1.0
        let phase = animationPhase + Double(index) * 0.3
        let pulse = CGFloat(sin(phase * 2)) * 0.2
        return base + pulse
    }
}

// MARK: - Diamond Shape

/// A diamond (rotated square) shape for waypoint markers
struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2

        path.move(to: CGPoint(x: center.x, y: center.y - halfHeight))
        path.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + halfHeight))
        path.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y))
        path.closeSubpath()

        return path
    }
}

// MARK: - Satellite Connection View

/// Container view that renders both satellite connections
/// Uses choreographer's animationPhase for subtle ambient motion (2fps — no TimelineView overhead)
public struct SatelliteConnectionsView: View {

    let heroCenter: CGPoint
    let plannerumPosition: CGPoint
    let thinkspacePosition: CGPoint
    let plannerumActive: Bool
    let thinkspaceActive: Bool
    let animationPhase: Double

    public var body: some View {
        ZStack {
            SanctuaryConnectionThread(
                from: plannerumPosition,
                to: heroCenter,
                color: SanctuaryColors.plannerumPrimary,
                isActive: plannerumActive,
                animationPhase: animationPhase
            )

            SanctuaryConnectionThread(
                from: thinkspacePosition,
                to: heroCenter,
                color: SanctuaryColors.thinkspacePrimary,
                isActive: thinkspaceActive,
                animationPhase: animationPhase
            )
        }
        .drawingGroup()  // Rasterize connection lines + glow blur to GPU texture
    }
}

// MARK: - Preview

#if DEBUG
struct SanctuaryConnectionThread_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            SanctuaryColors.voidPrimary
                .ignoresSafeArea()

            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let leftPos = CGPoint(x: geometry.size.width * 0.12, y: geometry.size.height / 2)
                let rightPos = CGPoint(x: geometry.size.width * 0.88, y: geometry.size.height / 2)

                SatelliteConnectionsView(
                    heroCenter: center,
                    plannerumPosition: leftPos,
                    thinkspacePosition: rightPos,
                    plannerumActive: true,
                    thinkspaceActive: false,
                    animationPhase: 0
                )

                // Hero orb indicator
                Circle()
                    .fill(SanctuaryColors.heroPrimary)
                    .frame(width: 100, height: 100)
                    .position(center)

                // Satellite indicators
                Circle()
                    .fill(SanctuaryColors.plannerumPrimary)
                    .frame(width: 72, height: 72)
                    .position(leftPos)

                Circle()
                    .fill(SanctuaryColors.thinkspacePrimary)
                    .frame(width: 72, height: 72)
                    .position(rightPos)
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
