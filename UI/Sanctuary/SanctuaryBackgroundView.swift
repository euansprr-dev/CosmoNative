// CosmoOS/UI/Sanctuary/SanctuaryBackgroundView.swift
// Sanctuary Background - Animated particle field with depth blur
// Creates an immersive, meditative atmosphere

import SwiftUI
import Combine

// MARK: - Particle

/// A single particle in the background field
private struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var size: CGFloat
    var opacity: Double
    var speed: CGFloat
    var depth: CGFloat      // 0 = near, 1 = far
    var hue: Double
    var phase: Double

    mutating func update(dt: Double, bounds: CGSize) {
        // Gentle floating motion
        let xOffset = sin(phase + position.y * 0.01) * 0.3
        position.y -= speed * CGFloat(dt)
        position.x += CGFloat(xOffset) * speed * CGFloat(dt)

        // Wrap around
        if position.y < -size {
            position.y = bounds.height + size
            position.x = CGFloat.random(in: 0...bounds.width)
            phase = Double.random(in: 0...2 * .pi)
        }
    }
}

// MARK: - Sanctuary Background View

public struct SanctuaryBackgroundView: View {

    let animationPhase: Double

    @State private var particles: [Particle] = []
    @State private var hasInitialized = false

    // PERFORMANCE FIX: Timer for smooth async updates
    @State private var particleTimerCancellable: AnyCancellable?
    @State private var lastUpdateTime: CFTimeInterval = 0

    // PERFORMANCE FIX: Adaptive particle count based on device
    private var particleCount: Int {
        #if os(macOS)
        return 50  // Mac can handle more
        #else
        // iOS: reduce for non-Pro devices
        return 35
        #endif
    }

    private let baseColors: [Color] = [
        Color(hex: "#6366F1"),  // Indigo
        Color(hex: "#8B5CF6"),  // Purple
        Color(hex: "#EC4899"),  // Pink
        Color(hex: "#22C55E"),  // Green
    ]

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: [
                        Color(hex: "#0A0A0F"),
                        Color(hex: "#0F0A1A"),
                        Color(hex: "#0A0F1A")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Radial glow from center
                RadialGradient(
                    colors: [
                        Color(hex: "#6366F1").opacity(0.15),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 50,
                    endRadius: geometry.size.width * 0.8
                )

                // Particle field
                Canvas { context, size in
                    for particle in particles {
                        _ = particle.depth * 3  // blur: More depth = more blur (reserved for future glow effect)
                        let color = baseColors[Int(particle.hue * Double(baseColors.count)) % baseColors.count]

                        // Draw particle with glow
                        let rect = CGRect(
                            x: particle.position.x - particle.size / 2,
                            y: particle.position.y - particle.size / 2,
                            width: particle.size,
                            height: particle.size
                        )

                        // Outer glow
                        let glowRect = rect.insetBy(dx: -particle.size * 0.5, dy: -particle.size * 0.5)
                        context.fill(
                            Circle().path(in: glowRect),
                            with: .color(color.opacity(particle.opacity * 0.3))
                        )

                        // Core
                        context.fill(
                            Circle().path(in: rect),
                            with: .color(color.opacity(particle.opacity))
                        )
                    }
                }
                .blur(radius: 0.5)

                // Subtle noise texture overlay
                Rectangle()
                    .fill(
                        ImagePaint(
                            image: Image(systemName: "square.fill"),
                            scale: 0.1
                        )
                    )
                    .opacity(0.02)
                    .blendMode(.overlay)
            }
            .onAppear {
                initializeParticles(in: geometry.size)
                startParticleTimer(size: geometry.size)
            }
            .onDisappear {
                // PERFORMANCE FIX: Clean up timer
                particleTimerCancellable?.cancel()
                particleTimerCancellable = nil
            }
            // PERFORMANCE FIX: Removed onChange sync - using dedicated timer
        }
    }

    // MARK: - Particle Timer

    private func startParticleTimer(size: CGSize) {
        // PERFORMANCE FIX: Use 30fps timer independent of animationPhase
        // This runs on RunLoop, not blocking main thread with sync updates
        particleTimerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                let now = CACurrentMediaTime()
                let dt = now - lastUpdateTime
                lastUpdateTime = now

                // Only update if enough time passed (throttle)
                if dt < 0.01 { return }

                updateParticles(in: size, dt: min(dt, 0.05))
            }
    }

    // MARK: - Particle Management

    private func initializeParticles(in size: CGSize) {
        guard !hasInitialized else { return }
        hasInitialized = true

        particles = (0..<particleCount).map { _ in
            createParticle(in: size, initialY: CGFloat.random(in: 0...size.height))
        }
    }

    private func createParticle(in size: CGSize, initialY: CGFloat? = nil) -> Particle {
        let depth = CGFloat.random(in: 0...1)
        return Particle(
            position: CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: initialY ?? size.height + CGFloat.random(in: 0...50)
            ),
            size: CGFloat.random(in: 2...6) * (1 - depth * 0.5),
            opacity: Double.random(in: 0.3...0.8) * (1 - Double(depth) * 0.5),
            speed: CGFloat.random(in: 10...30) * (1 - depth * 0.5),
            depth: depth,
            hue: Double.random(in: 0...1),
            phase: Double.random(in: 0...2 * .pi)
        )
    }

    private func updateParticles(in size: CGSize, dt: Double = 1.0 / 30.0) {
        // PERFORMANCE FIX: Use actual delta time for frame-rate independent animation
        for i in particles.indices {
            particles[i].update(dt: dt, bounds: size)
        }
    }
}

// MARK: - Causality Line Effect

/// Animated line connecting correlated metrics
public struct CausalityLineView: View {

    let from: CGPoint
    let to: CGPoint
    let strength: Double
    let animationPhase: Double

    public var body: some View {
        Canvas { context, size in
            let gradient = Gradient(colors: [
                Color.white.opacity(0),
                Color.white.opacity(strength * 0.6),
                Color.white.opacity(0)
            ])

            // Animated gradient position
            let progress = (animationPhase.truncatingRemainder(dividingBy: 2.0)) / 2.0

            var path = Path()
            path.move(to: from)

            // Bezier curve for organic feel
            let midX = (from.x + to.x) / 2
            let midY = (from.y + to.y) / 2
            let control1 = CGPoint(x: midX - 20, y: midY - 30)
            let control2 = CGPoint(x: midX + 20, y: midY + 30)

            path.addCurve(to: to, control1: control1, control2: control2)

            context.stroke(
                path,
                with: .linearGradient(
                    gradient,
                    startPoint: from,
                    endPoint: to
                ),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )

            // Animated pulse along the line
            let pulsePosition = CGPoint(
                x: from.x + (to.x - from.x) * CGFloat(progress),
                y: from.y + (to.y - from.y) * CGFloat(progress)
            )

            context.fill(
                Circle().path(in: CGRect(
                    x: pulsePosition.x - 3,
                    y: pulsePosition.y - 3,
                    width: 6,
                    height: 6
                )),
                with: .color(.white.opacity(strength * 0.8))
            )
        }
    }
}

// MARK: - Depth Blur Modifier

/// Applies depth-based blur for 3D effect
struct DepthBlurModifier: ViewModifier {
    let depth: CGFloat  // 0 = front, 1 = back

    init(depth: CGFloat) {
        self.depth = depth
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: depth * 4)
            .opacity(1 - Double(depth) * 0.3)
    }
}

extension View {
    func depthBlur(_ depth: CGFloat) -> some View {
        modifier(DepthBlurModifier(depth: depth))
    }
}

// MARK: - Preview

#Preview {
    SanctuaryBackgroundView(animationPhase: 0)
        .ignoresSafeArea()
}
