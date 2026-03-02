// CosmoOS/Core/FilmGrainOverlay.swift
// Subtle film grain texture overlay for organic warmth
// Applied to canvas and sanctuary hero areas
// March 2026 — Greenhouse Design Language

import SwiftUI

/// A tiled noise texture overlay that adds subtle film grain to surfaces.
/// Used on the canvas and sanctuary hero to create organic warmth.
/// Performance: generates the noise bitmap ONCE in onAppear, not every frame.
struct FilmGrainOverlay: View {
    var opacity: Double = 0.025

    /// Pre-rendered grain texture (generated once)
    @State private var grainImage: CGImage?

    var body: some View {
        GeometryReader { geo in
            if let cgImage = grainImage {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .opacity(opacity)
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            generateGrainTexture()
        }
    }

    /// Generate the grain noise bitmap once using CGContext.
    /// Same algorithm as the old per-frame Canvas: deterministic LCG hash,
    /// 2x2 dots, black at normalized * 0.15 opacity.
    private func generateGrainTexture() {
        // Use a fixed tile size — will be stretched by .resizable()
        let tileWidth = 512
        let tileHeight = 512
        let dotSize = 2
        let columns = tileWidth / dotSize
        let rows = tileHeight / dotSize

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: tileWidth,
            height: tileHeight,
            bitsPerComponent: 8,
            bytesPerRow: tileWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return }

        // Fill with white (transparent grain — we'll use this as a mask-like overlay)
        ctx.setFillColor(gray: 1.0, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: tileWidth, height: tileHeight))

        for row in 0..<rows {
            for col in 0..<columns {
                let seed = UInt64(row * columns + col)
                let hash = (seed &* 6364136223846793005) &+ 1442695040888963407
                let normalized = Double(hash % 256) / 255.0

                // Black dot at normalized * 0.15 opacity → gray value = 1.0 - (normalized * 0.15)
                let gray = 1.0 - (normalized * 0.15)
                ctx.setFillColor(gray: CGFloat(gray), alpha: 1.0)
                ctx.fill(CGRect(
                    x: col * dotSize,
                    y: row * dotSize,
                    width: dotSize,
                    height: dotSize
                ))
            }
        }

        grainImage = ctx.makeImage()
    }
}

// MARK: - View Modifier

extension View {
    /// Apply film grain texture overlay at specified opacity
    func filmGrain(opacity: Double = 0.025) -> some View {
        self.overlay(
            FilmGrainOverlay(opacity: opacity)
        )
    }
}
