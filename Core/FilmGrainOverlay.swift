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
        // The grain's base/dot polarity is keyed on the palette's isDark.
        // This used to refresh via the app-root theme nuke re-running
        // onAppear; with in-place theme re-rendering it must listen itself.
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Theme.changed)) { _ in
            generateGrainTexture()
        }
    }

    /// Generate the grain noise bitmap once using CGContext.
    /// Same algorithm as the old per-frame Canvas: deterministic LCG hash,
    /// 2x2 dots. Light theme: white base + dark dots. Dark theme: dark base + light dots.
    private func generateGrainTexture() {
        let isDark = DS.palette.isDark

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

        // Base fill: white for light themes, dark for dark themes
        let baseFill: CGFloat = isDark ? 0.0 : 1.0
        ctx.setFillColor(gray: baseFill, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: tileWidth, height: tileHeight))

        for row in 0..<rows {
            for col in 0..<columns {
                let seed = UInt64(row * columns + col)
                let hash = (seed &* 6364136223846793005) &+ 1442695040888963407
                let normalized = Double(hash % 256) / 255.0

                // Light theme: dark dots on white (gray = 1.0 - noise)
                // Dark theme: light dots on dark (gray = 0.0 + noise)
                let gray: Double
                if isDark {
                    gray = normalized * 0.15
                } else {
                    gray = 1.0 - (normalized * 0.15)
                }
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
