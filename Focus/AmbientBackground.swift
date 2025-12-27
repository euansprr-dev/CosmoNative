// CosmoOS/Focus/AmbientBackground.swift
// Premium ambient background with cursor-following gradient
// Leverages Metal/GPU for smooth 60fps+ animation
// December 2025 - MeshGradient, ProMotion springs, parallax effects

import SwiftUI
import AppKit

// MARK: - Cosmic Mesh Gradient Background (macOS 15+)
/// Premium animated MeshGradient background for the most immersive experience.
/// Uses Apple's new MeshGradient API for GPU-accelerated organic gradients.
@available(macOS 15.0, *)
struct CosmicMeshGradient: View {
    @State private var animationPhase: CGFloat = 0
    @State private var breathingPhase: CGFloat = 0

    /// Entity color to tint the mesh
    var entityColor: Color

    /// Animation intensity (0 = static, 1 = full animation)
    var intensity: CGFloat

    init(entityColor: Color = CosmoColors.lavender, intensity: CGFloat = 0.3) {
        self.entityColor = entityColor
        self.intensity = intensity
    }

    var body: some View {
        // Reduced to 30fps - plenty for slow ambient animation, saves CPU
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            meshGradientView(for: timeline.date.timeIntervalSince1970)
        }
        .drawingGroup() // CRITICAL: Forces GPU rendering via Metal
        .onAppear {
            withAnimation(
                .easeInOut(duration: 4)
                .repeatForever(autoreverses: true)
            ) {
                breathingPhase = 1
            }
        }
    }

    @ViewBuilder
    private func meshGradientView(for time: TimeInterval) -> some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: meshPoints(for: time),
            colors: meshColors
        )
        .ignoresSafeArea()
    }

    private func meshPoints(for time: TimeInterval) -> [SIMD2<Float>] {
        let t = Float(time)
        let i = Float(intensity)
        return [
            SIMD2(0, 0),
            SIMD2(0.5 + sin(t * 0.3) * 0.05 * i, 0),
            SIMD2(1, 0),
            SIMD2(0, 0.5 + cos(t * 0.4) * 0.03 * i),
            SIMD2(0.5 + sin(t * 0.5) * 0.08 * i, 0.5 + cos(t * 0.6) * 0.08 * i),
            SIMD2(1, 0.5 + sin(t * 0.35) * 0.03 * i),
            SIMD2(0, 1),
            SIMD2(0.5 + cos(t * 0.25) * 0.04 * i, 1),
            SIMD2(1, 1)
        ]
    }

    private var meshColors: [Color] {
        [
            CosmoColors.softWhite,
            CosmoColors.softWhite.opacity(0.95),
            CosmoColors.mistGrey.opacity(0.8),
            entityColor.opacity(0.03 + breathingPhase * 0.02),
            CosmoColors.softWhite,
            CosmoColors.skyBlue.opacity(0.04 + breathingPhase * 0.015),
            CosmoColors.mistGrey.opacity(0.6),
            CosmoColors.softWhite.opacity(0.9),
            entityColor.opacity(0.02)
        ]
    }
}

// MARK: - Parallax Layer
/// A view that moves based on cursor position for depth perception
struct ParallaxLayer<Content: View>: View {
    let depth: CGFloat  // 0 = no movement, 1 = max movement
    let maxOffset: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var mouseLocation: CGPoint = .zero
    @State private var smoothLocation: CGPoint = .zero
    @State private var containerSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            content()
                .offset(
                    x: (smoothLocation.x - containerSize.width / 2) * depth * maxOffset / containerSize.width,
                    y: (smoothLocation.y - containerSize.height / 2) * depth * maxOffset / containerSize.height
                )
                .onAppear {
                    containerSize = geo.size
                    smoothLocation = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        withAnimation(ProMotionSprings.gentle) {
                            smoothLocation = location
                        }
                    case .ended:
                        withAnimation(ProMotionSprings.gentle) {
                            smoothLocation = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
                        }
                    }
                }
        }
    }
}

// MARK: - Parallax Header
/// Premium parallax header for focus mode and detail views
struct ParallaxHeader: View {
    let title: String
    let subtitle: String?
    let entityColor: Color
    let icon: String

    @State private var scrollOffset: CGFloat = 0
    @State private var titleAppeared = false
    @State private var iconBounce = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background with parallax
            ParallaxLayer(depth: 0.3, maxOffset: 30) {
                LinearGradient(
                    colors: [
                        entityColor.opacity(0.08),
                        entityColor.opacity(0.02),
                        CosmoColors.softWhite
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Icon with symbol effect
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(entityColor)
                    .symbolEffect(.bounce, value: iconBounce)
                    .padding(.bottom, 4)

                // Title with animated underline
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(CosmoTypography.display)
                        .foregroundColor(CosmoColors.textPrimary)

                    // Animated underline
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [entityColor, entityColor.opacity(0.3), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: titleAppeared ? 120 : 0, height: 3)
                        .shadow(color: entityColor.opacity(0.3), radius: 4, y: 2)
                }

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textSecondary)
                }
            }
            .padding(32)
            .opacity(titleAppeared ? 1 : 0)
            .offset(y: titleAppeared ? 0 : 20)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance.delay(0.2)) {
                titleAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                iconBounce.toggle()
            }
        }
    }
}

/// Premium ambient background for focus mode
/// Features:
/// - Soft radial gradient that subtly follows cursor position
/// - Gentle vignette to draw eye to center
/// - Optional noise texture overlay for analog warmth
struct AmbientFocusBackground: View {
    let geometry: GeometryProxy

    // Mouse tracking state
    @State private var mouseLocation: CGPoint = .zero
    @State private var smoothMouseLocation: CGPoint = .zero
    @State private var isMouseInside = false

    // Ambient animation state
    @State private var ambientPhase: CGFloat = 0

    // Configuration
    private let gradientRadius: CGFloat = 400
    private let smoothingFactor: CGFloat = 0.1  // How quickly gradient follows cursor
    private let ambientIntensity: CGFloat = 0.06  // Subtle, not distracting

    var body: some View {
        ZStack {
            // Base - warm off-white
            CosmoColors.softWhite
                .ignoresSafeArea()

            // Vignette - draws eye to center
            RadialGradient(
                colors: [
                    .clear,
                    CosmoColors.glassGrey.opacity(0.08),
                    CosmoColors.glassGrey.opacity(0.15)
                ],
                center: .center,
                startRadius: geometry.size.width * 0.2,
                endRadius: max(geometry.size.width, geometry.size.height) * 0.7
            )
            .ignoresSafeArea()

            // Cursor-following lavender glow
            if isMouseInside {
                RadialGradient(
                    colors: [
                        CosmoColors.lavender.opacity(ambientIntensity),
                        CosmoColors.lavender.opacity(ambientIntensity * 0.5),
                        .clear
                    ],
                    center: UnitPoint(
                        x: smoothMouseLocation.x / geometry.size.width,
                        y: smoothMouseLocation.y / geometry.size.height
                    ),
                    startRadius: 50,
                    endRadius: gradientRadius
                )
                .ignoresSafeArea()
                .blendMode(.normal)
            }

            // Subtle ambient breathing glow (always present)
            ambientBreathingGlow

            // Noise texture overlay for analog warmth
            NoiseTextureOverlay()
                .ignoresSafeArea()
                .opacity(0.015)  // Very subtle - 1.5%
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                mouseLocation = location
                isMouseInside = true
                // Smooth interpolation for premium feel
                withAnimation(.linear(duration: 0.1)) {
                    smoothMouseLocation = CGPoint(
                        x: smoothMouseLocation.x + (mouseLocation.x - smoothMouseLocation.x) * smoothingFactor,
                        y: smoothMouseLocation.y + (mouseLocation.y - smoothMouseLocation.y) * smoothingFactor
                    )
                }
            case .ended:
                isMouseInside = false
            }
        }
        .onAppear {
            // Start ambient breathing animation
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                ambientPhase = 1
            }
        }
    }

    // MARK: - Ambient Breathing Glow
    private var ambientBreathingGlow: some View {
        ZStack {
            // Soft lavender pulse at center
            RadialGradient(
                colors: [
                    CosmoColors.lavender.opacity(0.03 + ambientPhase * 0.02),
                    .clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: geometry.size.width * 0.4
            )

            // Soft sky blue at top-right
            RadialGradient(
                colors: [
                    CosmoColors.skyBlue.opacity(0.02 + ambientPhase * 0.01),
                    .clear
                ],
                center: UnitPoint(x: 0.8, y: 0.2),
                startRadius: 50,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Noise Texture Overlay
/// Procedural noise texture for analog warmth
/// Prevents gradient banding and adds subtle texture
struct NoiseTextureOverlay: View {
    var body: some View {
        Canvas { context, size in
            // Generate noise pattern
            let resolution: CGFloat = 2  // Lower = more performant
            let rows = Int(size.height / resolution)
            let cols = Int(size.width / resolution)

            for row in stride(from: 0, to: rows, by: 2) {
                for col in stride(from: 0, to: cols, by: 2) {
                    let noise = CGFloat.random(in: 0...1)
                    if noise > 0.5 {
                        let rect = CGRect(
                            x: CGFloat(col) * resolution,
                            y: CGFloat(row) * resolution,
                            width: resolution,
                            height: resolution
                        )
                        context.fill(
                            Path(rect),
                            with: .color(.white.opacity(noise * 0.15))
                        )
                    }
                }
            }
        }
        .blendMode(.overlay)
        .drawingGroup()  // Rasterize for performance
    }
}

// MARK: - Static Noise Texture (Pre-rendered)
/// Pre-rendered noise for better performance
/// Use this instead of procedural noise for frequently updating views
struct StaticNoiseTexture: View {
    let seed: Int

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Use seed for consistent noise pattern
                srand48(seed)

                let cellSize: CGFloat = 2
                let cols = Int(size.width / cellSize)
                let rows = Int(size.height / cellSize)

                for row in 0..<rows {
                    for col in 0..<cols {
                        let noise = drand48()
                        if noise > 0.6 {
                            let rect = CGRect(
                                x: CGFloat(col) * cellSize,
                                y: CGFloat(row) * cellSize,
                                width: cellSize,
                                height: cellSize
                            )
                            context.fill(
                                Path(rect),
                                with: .color(.white.opacity(CGFloat(noise) * 0.1))
                            )
                        }
                    }
                }
            }
        }
        .blendMode(.overlay)
        .drawingGroup()
    }
}

// MARK: - Cursor Glow Effect
/// Standalone cursor glow that can be overlaid on any view
struct CursorGlowEffect: View {
    let color: Color
    let radius: CGFloat
    let intensity: CGFloat

    @State private var mouseLocation: CGPoint = .zero
    @State private var isActive = false

    var body: some View {
        GeometryReader { geometry in
            if isActive {
                RadialGradient(
                    colors: [
                        color.opacity(intensity),
                        color.opacity(intensity * 0.3),
                        .clear
                    ],
                    center: UnitPoint(
                        x: mouseLocation.x / geometry.size.width,
                        y: mouseLocation.y / geometry.size.height
                    ),
                    startRadius: radius * 0.2,
                    endRadius: radius
                )
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                withAnimation(.easeOut(duration: 0.15)) {
                    mouseLocation = location
                    isActive = true
                }
            case .ended:
                withAnimation(.easeOut(duration: 0.3)) {
                    isActive = false
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Typing Pulse Effect
/// Subtle pulse effect that activates when typing
/// Creates an "alive" feeling in focus mode
struct TypingPulseOverlay: View {
    @State private var pulsePhase: CGFloat = 0
    @State private var isPulsing = false

    let entityColor: Color
    let isTyping: Bool

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .stroke(entityColor.opacity(isPulsing ? 0.08 : 0), lineWidth: 2)
                .scaleEffect(isPulsing ? 2.5 : 1)
                .opacity(isPulsing ? 0 : 0.3)

            // Inner glow
            Circle()
                .fill(entityColor.opacity(isPulsing ? 0.04 : 0))
                .scaleEffect(isPulsing ? 1.5 : 1)
        }
        .frame(width: 100, height: 100)
        .onChange(of: isTyping) { _, typing in
            if typing {
                triggerPulse()
            }
        }
        .allowsHitTesting(false)
    }

    private func triggerPulse() {
        withAnimation(ProMotionSprings.snappy) {
            isPulsing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(ProMotionSprings.gentle) {
                isPulsing = false
            }
        }
    }
}

// MARK: - View Extension
extension View {
    /// Add ambient cursor-following glow to any view
    func cursorGlow(
        color: Color = CosmoColors.lavender,
        radius: CGFloat = 300,
        intensity: CGFloat = 0.08
    ) -> some View {
        self.overlay {
            CursorGlowEffect(color: color, radius: radius, intensity: intensity)
        }
    }

    /// Add noise texture overlay for analog warmth
    func noiseOverlay(opacity: CGFloat = 0.015) -> some View {
        self.overlay {
            NoiseTextureOverlay()
                .opacity(opacity)
                .allowsHitTesting(false)
        }
    }

    /// Add premium MeshGradient background (macOS 15+)
    @ViewBuilder
    func cosmicMeshBackground(entityColor: Color = CosmoColors.lavender, intensity: CGFloat = 0.3) -> some View {
        if #available(macOS 15.0, *) {
            self.background {
                CosmicMeshGradient(entityColor: entityColor, intensity: intensity)
            }
        } else {
            // Fallback for older macOS
            self.background(CosmoColors.softWhite)
        }
    }

    /// Add parallax effect to a view
    func parallax(depth: CGFloat = 0.5, maxOffset: CGFloat = 20) -> some View {
        ParallaxLayer(depth: depth, maxOffset: maxOffset) {
            self
        }
    }

    /// Add typing pulse overlay (for focus mode)
    func typingPulse(entityColor: Color, isTyping: Bool) -> some View {
        self.overlay(alignment: .center) {
            TypingPulseOverlay(entityColor: entityColor, isTyping: isTyping)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct AmbientBackground_Previews: PreviewProvider {
    static var previews: some View {
        GeometryReader { geometry in
            AmbientFocusBackground(geometry: geometry)
                .overlay {
                    Text("Move your cursor around")
                        .font(.title)
                        .foregroundColor(CosmoColors.textPrimary)
                }
        }
        .frame(width: 800, height: 600)
    }
}
#endif
