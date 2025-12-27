// CosmoOS/UI/Plannerum/XPTracerView.swift
// Plannerum XP Tracer - Particle animation for XP awards
// PLANERIUM_SPEC.md Section 6.3 compliant

import SwiftUI
import Combine

// MARK: - XP Tracer View

/// Animated XP particles that fly from source to the XP bar.
///
/// From PLANERIUM_SPEC.md Section 6.3:
/// ```
/// XP TRACER VISUAL SEQUENCE
///
/// T=200ms   XP particles spawn
///           └── Count: 8-15 particles
///           └── Size: 4-8pt circles
///           └── Color: Dimension colors (split by %)
///           └── Initial position: Block center
///
/// T=300ms   Particles begin flight
///           └── Path: Bezier curve toward XP bar
///           └── Stagger: 30ms between particles
///           └── Speed: Fast at start, ease out
///           └── Trail: Subtle glow trail
///
/// T=600ms   First particles reach XP bar
/// T=900ms   All particles absorbed
/// T=1200ms  Settle
/// ```
public struct XPTracerView: View {

    // MARK: - Properties

    let xpAmount: Int
    let sourcePosition: CGPoint
    let targetPosition: CGPoint
    let dimensionColors: [Color]
    let onComplete: () -> Void

    // MARK: - State

    @State private var particles: [XPParticle] = []
    @State private var isAnimating = false

    // MARK: - Constants (Spec compliant)

    private enum Config {
        static let particleCountMin = 8
        static let particleCountMax = 15
        static let particleSizeMin: CGFloat = 4
        static let particleSizeMax: CGFloat = 8
        static let staggerDelay: Double = 0.03  // 30ms
        static let flightDuration: Double = 0.8  // 800ms
        static let fadeStartPercent: Double = 0.7
    }

    // MARK: - Init

    public init(
        xpAmount: Int,
        sourcePosition: CGPoint,
        targetPosition: CGPoint,
        dimensionColors: [Color] = [PlannerumColors.primary, PlannerumColors.xpGold],
        onComplete: @escaping () -> Void
    ) {
        self.xpAmount = xpAmount
        self.sourcePosition = sourcePosition
        self.targetPosition = targetPosition
        self.dimensionColors = dimensionColors
        self.onComplete = onComplete
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Particle layer
            ForEach(particles) { particle in
                XPParticleView(particle: particle)
            }
        }
        .onAppear {
            spawnParticles()
        }
    }

    // MARK: - Spawn Particles

    private func spawnParticles() {
        let count = Int.random(in: Config.particleCountMin...Config.particleCountMax)

        // Generate particles with staggered start
        for i in 0..<count {
            let delay = Double(i) * Config.staggerDelay

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let particle = XPParticle(
                    id: UUID(),
                    startPosition: sourcePosition,
                    endPosition: targetPosition,
                    size: CGFloat.random(in: Config.particleSizeMin...Config.particleSizeMax),
                    color: dimensionColors.randomElement() ?? PlannerumColors.xpGold,
                    controlOffset: randomControlOffset(),
                    duration: Config.flightDuration
                )

                withAnimation(.easeOut(duration: Config.flightDuration)) {
                    particles.append(particle)
                }
            }
        }

        // Complete callback after all particles finish
        let totalDuration = Double(count) * Config.staggerDelay + Config.flightDuration + 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            onComplete()
        }
    }

    private func randomControlOffset() -> CGPoint {
        CGPoint(
            x: CGFloat.random(in: -80...80),
            y: CGFloat.random(in: -120 ... -40)
        )
    }
}

// MARK: - XP Particle Model

public struct XPParticle: Identifiable {
    public let id: UUID
    public let startPosition: CGPoint
    public let endPosition: CGPoint
    public let size: CGFloat
    public let color: Color
    public let controlOffset: CGPoint
    public let duration: Double

    /// Bezier control point for curved path
    public var controlPoint: CGPoint {
        CGPoint(
            x: (startPosition.x + endPosition.x) / 2 + controlOffset.x,
            y: min(startPosition.y, endPosition.y) + controlOffset.y
        )
    }
}

// MARK: - XP Particle View

public struct XPParticleView: View {

    let particle: XPParticle

    @State private var progress: CGFloat = 0
    @State private var opacity: CGFloat = 1

    public var body: some View {
        ZStack {
            // Glow trail
            Circle()
                .fill(particle.color.opacity(0.3))
                .frame(width: particle.size * 2, height: particle.size * 2)
                .blur(radius: particle.size)

            // Core particle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            particle.color,
                            particle.color.opacity(0.8)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: particle.size / 2
                    )
                )
                .frame(width: particle.size, height: particle.size)

            // Bright center
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: particle.size * 0.4, height: particle.size * 0.4)
        }
        .position(currentPosition)
        .opacity(opacity)
        .onAppear {
            // Animate along bezier path
            withAnimation(.timingCurve(0.0, 0.0, 0.2, 1.0, duration: particle.duration)) {
                progress = 1
            }

            // Fade out in last 30%
            let fadeDelay = particle.duration * 0.7
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay) {
                withAnimation(.easeOut(duration: particle.duration * 0.3)) {
                    opacity = 0
                }
            }
        }
    }

    private var currentPosition: CGPoint {
        bezierPoint(
            t: progress,
            p0: particle.startPosition,
            p1: particle.controlPoint,
            p2: particle.endPosition
        )
    }

    /// Quadratic bezier interpolation
    private func bezierPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint) -> CGPoint {
        let oneMinusT = 1 - t
        let x = oneMinusT * oneMinusT * p0.x + 2 * oneMinusT * t * p1.x + t * t * p2.x
        let y = oneMinusT * oneMinusT * p0.y + 2 * oneMinusT * t * p1.y + t * t * p2.y
        return CGPoint(x: x, y: y)
    }
}

// MARK: - XP Tracer Overlay

/// Overlay view that manages XP tracer animations across the app
public struct XPTracerOverlay: View {

    @StateObject private var manager = XPTracerManager.shared

    public init() {}

    public var body: some View {
        ZStack {
            ForEach(manager.activeTracers) { tracer in
                XPTracerView(
                    xpAmount: tracer.xpAmount,
                    sourcePosition: tracer.sourcePosition,
                    targetPosition: tracer.targetPosition,
                    dimensionColors: tracer.colors,
                    onComplete: {
                        manager.removeTracer(id: tracer.id)
                    }
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - XP Tracer Manager

@MainActor
public class XPTracerManager: ObservableObject {

    public static let shared = XPTracerManager()

    @Published public var activeTracers: [XPTracerConfig] = []

    private init() {
        // Listen for XP award notifications
        NotificationCenter.default.addObserver(
            forName: .xpAwarded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let xpAmount = info["xpAmount"] as? Int,
                  let sourcePosition = info["sourcePosition"] as? CGPoint,
                  let targetPosition = info["targetPosition"] as? CGPoint
            else { return }

            let colors = (info["colors"] as? [Color]) ?? [PlannerumColors.xpGold]
            self?.triggerTracer(
                xpAmount: xpAmount,
                from: sourcePosition,
                to: targetPosition,
                colors: colors
            )
        }
    }

    public func triggerTracer(
        xpAmount: Int,
        from source: CGPoint,
        to target: CGPoint,
        colors: [Color] = [PlannerumColors.xpGold]
    ) {
        let config = XPTracerConfig(
            id: UUID(),
            xpAmount: xpAmount,
            sourcePosition: source,
            targetPosition: target,
            colors: colors
        )

        activeTracers.append(config)
    }

    public func removeTracer(id: UUID) {
        activeTracers.removeAll { $0.id == id }
    }
}

// MARK: - XP Tracer Config

public struct XPTracerConfig: Identifiable {
    public let id: UUID
    public let xpAmount: Int
    public let sourcePosition: CGPoint
    public let targetPosition: CGPoint
    public let colors: [Color]
}

// MARK: - Notification Name

extension Notification.Name {
    public static let xpAwarded = Notification.Name("xpAwarded")
}

// MARK: - XP Award Helper

public struct XPAwardHelper {

    /// Triggers an XP tracer animation
    public static func awardXP(
        amount: Int,
        from sourceFrame: CGRect,
        to targetFrame: CGRect,
        in coordinateSpace: CoordinateSpace = .global,
        dimensionColors: [Color] = [PlannerumColors.xpGold]
    ) {
        let sourceCenter = CGPoint(
            x: sourceFrame.midX,
            y: sourceFrame.midY
        )
        let targetCenter = CGPoint(
            x: targetFrame.midX,
            y: targetFrame.midY
        )

        NotificationCenter.default.post(
            name: .xpAwarded,
            object: nil,
            userInfo: [
                "xpAmount": amount,
                "sourcePosition": sourceCenter,
                "targetPosition": targetCenter,
                "colors": dimensionColors
            ]
        )
    }
}

// MARK: - XP Burst Effect

/// A burst effect that plays at the source when XP is awarded
public struct XPBurstView: View {

    let position: CGPoint
    let color: Color

    @State private var scale: CGFloat = 0.5
    @State private var opacity: CGFloat = 1

    public init(position: CGPoint, color: Color = PlannerumColors.xpGold) {
        self.position = position
        self.color = color
    }

    public var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(color.opacity(0.5), lineWidth: 2)
                .frame(width: 40, height: 40)
                .scaleEffect(scale * 1.5)

            // Inner ring
            Circle()
                .stroke(color, lineWidth: 3)
                .frame(width: 30, height: 30)
                .scaleEffect(scale)

            // Center flash
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .scaleEffect(scale * 0.5)
        }
        .position(position)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.5
            }

            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                opacity = 0
            }
        }
    }
}

// MARK: - Impact Flash

/// A flash effect when particles reach the XP bar
public struct XPImpactFlash: View {

    let position: CGPoint

    @State private var scale: CGFloat = 0.3
    @State private var opacity: CGFloat = 1

    public var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white,
                        PlannerumColors.xpGold.opacity(0.5),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 30
                )
            )
            .frame(width: 60, height: 60)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(position)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.2
                    opacity = 0
                }
            }
    }
}

// MARK: - Preview

#if DEBUG
struct XPTracerView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            PlannerumColors.voidPrimary
                .ignoresSafeArea()

            // Demo tracer
            XPTracerView(
                xpAmount: 125,
                sourcePosition: CGPoint(x: 200, y: 500),
                targetPosition: CGPoint(x: 350, y: 50),
                dimensionColors: [
                    PlannerumColors.primary,
                    PlannerumColors.xpGold,
                    PlannerumColors.nowMarker
                ],
                onComplete: {}
            )

            // Source marker
            Circle()
                .fill(PlannerumColors.primary)
                .frame(width: 20, height: 20)
                .position(x: 200, y: 500)

            // Target marker
            Circle()
                .fill(PlannerumColors.xpGold)
                .frame(width: 20, height: 20)
                .position(x: 350, y: 50)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
