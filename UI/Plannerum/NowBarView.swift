// CosmoOS/UI/Plannerum/NowBarView.swift
// Plannerium Now Bar - The living present time marker
// Glowing line with particle trail and refraction effects

import SwiftUI
import Combine

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - NOW BAR VIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// The current time marker in the day timeline.
///
/// Visual Identity:
/// ```
/// ─────────────────●═══════════════════════════════════════════►
///            NOW 14:32
///              ✧ ✧ ✧ (particles trailing)
/// ```
///
/// Features:
/// - Glowing green marker line with pulse animation
/// - Time label with live updating
/// - Particle trail effect (20-30 particles)
/// - Light refraction glow
/// - Smooth position updates
public struct NowBarView: View {

    // MARK: - Properties

    /// Width of the timeline area
    let timelineWidth: CGFloat

    /// Current Y position based on time
    let yPosition: CGFloat

    /// Offset from left (for time labels)
    let leftOffset: CGFloat

    // MARK: - State

    @State private var pulsePhase: Double = 0
    @State private var particles: [NowParticle] = []
    @State private var currentTime: Date = Date()
    @State private var timerCancellable: AnyCancellable?
    @State private var lastSpawnTime: Date = Date()

    // MARK: - Layout (per plan Animation Specifications)

    private enum Layout {
        static let lineHeight: CGFloat = 2
        // Dot animates 10pt → 14pt → 10pt
        static let dotSizeMin: CGFloat = 10
        static let dotSizeMax: CGFloat = 14
        // Glow animates 16pt → 24pt → 16pt
        static let glowRadiusMin: CGFloat = 16
        static let glowRadiusMax: CGFloat = 24
        // Pulse cycle: 2.0s exactly
        static let pulseCycleDuration: Double = 2.0
        // Particle spawn: every 150ms
        static let particleSpawnInterval: Double = 0.150
        // Particle drift: 30pt over 1.2s
        static let particleDriftDistance: CGFloat = 30
        static let particleDriftDuration: Double = 1.2
        static let particleCount: Int = 24
        static let timeLabelOffset: CGFloat = 4
    }

    // Computed animated values
    private var animatedDotSize: CGFloat {
        Layout.dotSizeMin + (Layout.dotSizeMax - Layout.dotSizeMin) * CGFloat(sin(pulsePhase) + 1) / 2
    }

    private var animatedGlowRadius: CGFloat {
        Layout.glowRadiusMin + (Layout.glowRadiusMax - Layout.glowRadiusMin) * CGFloat(sin(pulsePhase) + 1) / 2
    }

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .leading) {
            // Glow layer (blur behind line)
            glowLayer

            // Main now line
            nowLine

            // Particle trail
            particleLayer

            // Time label with dot
            timeIndicator
        }
        .frame(width: timelineWidth, height: Layout.glowRadiusMax * 3)
        .position(x: timelineWidth / 2, y: yPosition)
        .onAppear {
            setupParticles()
            startAnimations()
        }
        .onDisappear {
            timerCancellable?.cancel()
        }
    }

    // MARK: - Glow Layer (animated 16pt → 24pt → 16pt per plan)

    private var glowLayer: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        PlannerumColors.nowGlow.opacity(0),
                        PlannerumColors.nowGlow.opacity(0.4 + 0.2 * sin(pulsePhase)),
                        PlannerumColors.nowGlow.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: animatedGlowRadius)
            .blur(radius: animatedGlowRadius / 2)
            .offset(x: leftOffset)
    }

    // MARK: - Now Line (dot animates 10pt → 14pt → 10pt per plan)

    private var nowLine: some View {
        HStack(spacing: 0) {
            // Leading space for time label
            Spacer()
                .frame(width: leftOffset - animatedDotSize / 2)

            // Dot indicator
            ZStack {
                // Outer pulse ring
                Circle()
                    .stroke(PlannerumColors.nowMarker, lineWidth: 1)
                    .frame(width: animatedDotSize + 6, height: animatedDotSize + 6)
                    .opacity(0.4 + 0.3 * sin(pulsePhase))
                    .scaleEffect(1.0 + 0.15 * sin(pulsePhase))

                // Main dot (animated 10pt → 14pt → 10pt sine wave)
                Circle()
                    .fill(PlannerumColors.nowMarker)
                    .frame(width: animatedDotSize, height: animatedDotSize)
                    .shadow(color: PlannerumColors.nowGlow, radius: animatedGlowRadius / 4)
            }

            // The line itself
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            PlannerumColors.nowMarker,
                            PlannerumColors.nowMarker.opacity(0.6),
                            PlannerumColors.nowMarker.opacity(0.2),
                            PlannerumColors.nowMarker.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: Layout.lineHeight)
                .shadow(color: PlannerumColors.nowGlow, radius: animatedGlowRadius / 6)
        }
    }

    // MARK: - Particle Layer

    private var particleLayer: some View {
        ForEach(particles) { particle in
            Circle()
                .fill(PlannerumColors.nowMarker.opacity(particle.opacity))
                .frame(width: particle.size, height: particle.size)
                .blur(radius: particle.size / 4)
                .offset(x: leftOffset + particle.x, y: particle.y)
        }
    }

    // MARK: - Time Indicator

    private var timeIndicator: some View {
        VStack(alignment: .leading, spacing: 2) {
            // NOW badge
            Text("NOW")
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(PlannerumColors.nowMarker)
                .tracking(1)
                .opacity(0.8)

            // Time display
            Text(PlannerumFormatters.time.string(from: currentTime))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PlannerumColors.nowMarker)
        }
        .offset(x: Layout.timeLabelOffset, y: -Layout.glowRadiusMax - 12)
    }

    // MARK: - Setup

    private func setupParticles() {
        particles = (0..<Layout.particleCount).map { i in
            NowParticle(
                id: i,
                x: CGFloat.random(in: 0...60),
                y: CGFloat.random(in: -8...8),
                size: CGFloat.random(in: 2...5),
                opacity: Double.random(in: 0.2...0.6),
                speed: Double.random(in: 0.3...0.8)
            )
        }
    }

    private func startAnimations() {
        let frameRate: Double = 30.0
        // Pulse cycle: 2.0s → 2π radians per 2.0s → π/30 per frame at 30fps
        let pulseIncrement = (2.0 * .pi) / (Layout.pulseCycleDuration * frameRate)

        // Combined timer for pulse and particles
        timerCancellable = Timer.publish(every: 1.0 / frameRate, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                // Update pulse (exact 2.0s cycle per plan)
                pulsePhase += pulseIncrement

                // Update particles
                updateParticles()

                // Spawn new particle every 150ms per plan
                let now = Date()
                if now.timeIntervalSince(lastSpawnTime) >= Layout.particleSpawnInterval {
                    spawnParticle()
                    lastSpawnTime = now
                }

                // Update time every second (approximately)
                if Int(pulsePhase * frameRate) % Int(frameRate) == 0 {
                    currentTime = Date()
                }
            }
    }

    private func spawnParticle() {
        // Find a faded particle to recycle or add new
        if let index = particles.firstIndex(where: { $0.opacity <= 0.1 }) {
            particles[index] = NowParticle(
                id: particles[index].id,
                x: 0,
                y: CGFloat.random(in: -6...6),
                size: CGFloat.random(in: 2...4),
                opacity: Double.random(in: 0.5...0.8),
                speed: Layout.particleDriftDistance / CGFloat(Layout.particleDriftDuration * 30) // 30pt over 1.2s at 30fps
            )
        } else if particles.count < Layout.particleCount {
            particles.append(NowParticle(
                id: particles.count,
                x: 0,
                y: CGFloat.random(in: -6...6),
                size: CGFloat.random(in: 2...4),
                opacity: Double.random(in: 0.5...0.8),
                speed: Layout.particleDriftDistance / CGFloat(Layout.particleDriftDuration * 30)
            ))
        }
    }

    private func updateParticles() {
        // Per plan: Particle drift 30pt over 1.2s, then fade
        let fadeRate = 1.0 / (Layout.particleDriftDuration * 30) // Fade over 1.2s at 30fps

        for i in particles.indices {
            // Move particles to the right (30pt over 1.2s)
            particles[i].x += CGFloat(particles[i].speed)

            // Gentle vertical drift
            particles[i].y += CGFloat.random(in: -0.2...0.2)

            // Clamp vertical position
            particles[i].y = max(-8, min(8, particles[i].y))

            // Start fading when past halfway through drift
            if particles[i].x > Layout.particleDriftDistance / 2 {
                particles[i].opacity = max(0, particles[i].opacity - fadeRate * 2)
            }

            // Shrink slightly as they drift
            if particles[i].x > Layout.particleDriftDistance * 0.7 {
                particles[i].size = max(1, particles[i].size - 0.05)
            }
        }

        // Remove completely faded particles (they'll be recycled by spawnParticle)
        // particles retain their indices for recycling
    }
}

// MARK: - Now Particle Model

/// A particle in the Now bar trail
struct NowParticle: Identifiable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var speed: Double
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - COMPACT NOW INDICATOR
// ═══════════════════════════════════════════════════════════════════════════════

/// A compact "NOW" indicator for the time label column
public struct NowTimeLabel: View {

    @State private var pulsePhase: Double = 0

    public var body: some View {
        HStack(spacing: 4) {
            // Pulsing dot
            Circle()
                .fill(PlannerumColors.nowMarker)
                .frame(width: 6, height: 6)
                .shadow(color: PlannerumColors.nowGlow, radius: 3)
                .scaleEffect(1.0 + 0.2 * sin(pulsePhase))

            // Time
            Text(PlannerumFormatters.time.string(from: Date()))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(PlannerumColors.nowMarker)
        }
        .onAppear {
            withAnimation(PlannerumSprings.nowPulse) {
                pulsePhase = .pi * 2
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - NOW MARKER DOT
// ═══════════════════════════════════════════════════════════════════════════════

/// Just the dot portion of the now marker (for compact displays)
public struct NowMarkerDot: View {

    let size: CGFloat

    @State private var pulsePhase: Double = 0
    @State private var timerCancellable: AnyCancellable?

    public init(size: CGFloat = 10) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(PlannerumColors.nowMarker.opacity(0.3), lineWidth: 1)
                .frame(width: size * 1.8, height: size * 1.8)
                .scaleEffect(1.0 + 0.2 * sin(pulsePhase))
                .opacity(0.5 + 0.3 * sin(pulsePhase))

            // Middle ring
            Circle()
                .stroke(PlannerumColors.nowMarker.opacity(0.5), lineWidth: 1.5)
                .frame(width: size * 1.3, height: size * 1.3)

            // Core dot
            Circle()
                .fill(PlannerumColors.nowMarker)
                .frame(width: size, height: size)
                .shadow(color: PlannerumColors.nowGlow, radius: size / 2)
        }
        .onAppear {
            timerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    pulsePhase += 0.06
                }
        }
        .onDisappear {
            timerCancellable?.cancel()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - NOW BAR POSITION CALCULATOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Utility for calculating now bar position
public struct NowBarCalculator {

    /// Calculate Y position for current time
    public static func yPosition(
        currentTime: Date = Date(),
        startHour: Int = 5,
        hourHeight: CGFloat = PlannerumLayout.hourRowHeight
    ) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentTime)
        let minute = calendar.component(.minute, from: currentTime)

        let adjustedHour = max(hour - startHour, 0)
        return CGFloat(adjustedHour) * hourHeight + CGFloat(minute) / 60.0 * hourHeight
    }

    /// Check if now bar should be visible (within timeline hours)
    public static func isVisible(
        currentTime: Date = Date(),
        startHour: Int = 5,
        endHour: Int = 24
    ) -> Bool {
        let hour = Calendar.current.component(.hour, from: currentTime)
        return hour >= startHour && hour < endHour
    }

    /// Get scroll anchor for now bar
    public static func scrollAnchor() -> UnitPoint {
        // Position now bar slightly above center for better context
        return UnitPoint(x: 0.5, y: 0.4)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PREVIEW
// ═══════════════════════════════════════════════════════════════════════════════

#if DEBUG
struct NowBarView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            PlannerumColors.background
                .ignoresSafeArea()

            VStack(spacing: 40) {
                // Full now bar
                NowBarView(
                    timelineWidth: 400,
                    yPosition: 100,
                    leftOffset: 60
                )
                .frame(height: 100)

                // Now marker dot
                NowMarkerDot(size: 12)

                // Time label
                NowTimeLabel()
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
