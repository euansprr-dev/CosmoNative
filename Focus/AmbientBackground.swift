// CosmoOS/Focus/AmbientBackground.swift
// Premium ambient background with cursor-following gradient
// December 2025 - MeshGradient, ProMotion springs, parallax effects

import SwiftUI
import AppKit

/// Premium ambient background for focus mode
/// Features:
/// - Soft radial gradient that subtly follows cursor position
/// - Gentle vignette to draw eye to center
/// - Optional noise texture overlay for analog warmth
struct AmbientFocusBackground: View {
    let geometry: GeometryProxy

    // Mouse tracking state
    @State private var smoothMouseLocation: CGPoint = .zero
    @State private var isMouseInside = false

    // Ambient animation state
    @State private var ambientPhase: CGFloat = 0

    // Configuration
    private let gradientRadius: CGFloat = 400
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
                if !isMouseInside { isMouseInside = true }
                // A retargeting spring tracks the cursor: each event redirects
                // the one in-flight animation instead of stacking a fresh one.
                withAnimation(ProMotionSprings.gentle) {
                    smoothMouseLocation = location
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
