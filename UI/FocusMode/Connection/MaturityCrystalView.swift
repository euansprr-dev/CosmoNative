// CosmoOS/UI/FocusMode/Connection/MaturityCrystalView.swift
// Faceted crystal replacing V1's linear progress bar.
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// The crystal has 8 facets (one per section). Facets reveal with a bouncy spring
// as sections fill. When the framework crosses a maturity threshold, the latest
// facet-reveal carries a brief gilt shimmer.
//
// Two render sizes:
//   - compact (28pt) — inline in the masthead and canvas block
//   - large (96pt)   — prominent in The Atelier

import SwiftUI

struct MaturityCrystalView: View {

    /// Number of filled facets (0...8).
    let filledCount: Int

    /// Diameter of the crystal. 28 for compact (masthead/block), 96 for large (atelier).
    var diameter: CGFloat = 96

    /// Accent color for the interior glow — defaults to soft forest/connection blend.
    var tintColor: Color = DS.entityConnection

    /// Animates a new facet when this increases. Caller passes the same as `filledCount`
    /// but updated through an `.animation` binding to drive the reveal.
    @State private var lastRenderedCount: Int = -1
    @State private var shimmerPhase: Double = 0

    private var clamped: Int { max(0, min(8, filledCount)) }

    private var thresholdLabel: String {
        switch clamped {
        case 0: return "SEED"
        case 1...2: return "SEED"
        case 3...4: return "SAPLING"
        case 5...6: return "MATURE"
        case 7: return "MATURE"
        default: return "PROVEN"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            crystalCanvas
                .frame(width: diameter, height: diameter)
                .overlay(shimmerOverlay)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Maturity crystal: \(thresholdLabel), \(clamped) of 8 facets")
        }
        .onAppear {
            if lastRenderedCount < 0 { lastRenderedCount = clamped }
        }
        .onChange(of: clamped) { old, new in
            if new > old { triggerShimmer() }
            lastRenderedCount = new
        }
    }

    /// Compact label shown below the crystal in the Atelier.
    static func captionText(for filled: Int) -> String {
        let clamped = max(0, min(8, filled))
        let level: String
        switch clamped {
        case 0...2: level = "SEED"
        case 3...4: level = "SAPLING"
        case 5...7: level = "MATURE"
        default: level = "PROVEN"
        }
        return "\(level) · \(clamped)/8 STATIONS"
    }

    // MARK: - Crystal

    /// The 8 facet points — a diamond rosette around a central vertex.
    /// Indexed 0...7. Render order is an "outside-in" spiral so each reveal
    /// lands in a visually pleasing position.
    private func facetPoint(index: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        // 8 points evenly spaced around a circle, starting at top (−90°).
        let angle = -Double.pi / 2 + (Double.pi * 2 * Double(index) / 8.0)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
    }

    private var crystalCanvas: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 4

            // Draw the 8 outer facets as small diamonds
            for i in 0..<8 {
                let p = facetPoint(index: i, radius: radius * 0.72, center: center)
                drawFacet(in: &context, at: p, size: radius * 0.22, filled: i < clamped)

                // Spokes from center to facet (thin gilt filigree)
                var spoke = Path()
                spoke.move(to: center)
                spoke.addLine(to: p)
                context.stroke(
                    spoke,
                    with: .color(DS.gilt.opacity(i < clamped ? 0.55 : 0.18)),
                    lineWidth: 0.6
                )
            }

            // Outer ring — aged gilt outline
            let ring = Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
            context.stroke(ring, with: .color(DS.gilt.opacity(0.35)), lineWidth: 0.75)

            // Central vertex — filled when crystal is at least Mature
            if clamped >= 5 {
                let dot = Path(ellipseIn: CGRect(
                    x: center.x - 3, y: center.y - 3,
                    width: 6, height: 6
                ))
                context.fill(dot, with: .color(DS.gilt.opacity(0.75)))
            }
        }
    }

    private func drawFacet(in context: inout GraphicsContext, at point: CGPoint, size: CGFloat, filled: Bool) {
        let half = size / 2
        var diamond = Path()
        diamond.move(to: CGPoint(x: point.x, y: point.y - half))
        diamond.addLine(to: CGPoint(x: point.x + half, y: point.y))
        diamond.addLine(to: CGPoint(x: point.x, y: point.y + half))
        diamond.addLine(to: CGPoint(x: point.x - half, y: point.y))
        diamond.closeSubpath()

        if filled {
            // Interior glow — soft tint, very light
            context.fill(diamond, with: .color(tintColor.opacity(0.18)))
            context.stroke(diamond, with: .color(DS.gilt.opacity(0.85)), lineWidth: 0.9)
        } else {
            // Empty outline only
            context.stroke(diamond, with: .color(DS.gilt.opacity(0.35)), lineWidth: 0.6)
        }
    }

    // MARK: - Shimmer on threshold crossings

    @ViewBuilder
    private var shimmerOverlay: some View {
        if shimmerPhase > 0 {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            DS.gilt.opacity(0.35 * (1 - shimmerPhase)),
                            DS.gilt.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.9
                    )
                )
                .allowsHitTesting(false)
        }
    }

    private func triggerShimmer() {
        shimmerPhase = 0.01
        withAnimation(.easeOut(duration: 0.4)) {
            shimmerPhase = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            shimmerPhase = 0
        }
    }
}

// MARK: - Inline masthead variant — 8 small diamond glyphs in a row

/// Horizontal row of 8 diamond glyphs for the masthead. More readable than a tiny
/// orb at inline sizes and visually rhymes with "◇◇◇◆◆◆◇◇" in the plan mockup.
struct MaturityCrystalInline: View {
    let filledCount: Int
    var glyphSize: CGFloat = 8

    private var clamped: Int { max(0, min(8, filledCount)) }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { i in
                diamond(filled: i < clamped)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clamped) of 8 stations populated")
    }

    @ViewBuilder
    private func diamond(filled: Bool) -> some View {
        if filled {
            Rectangle()
                .fill(DS.gilt.opacity(0.9))
                .frame(width: glyphSize, height: glyphSize)
                .rotationEffect(.degrees(45))
        } else {
            Rectangle()
                .stroke(DS.gilt.opacity(0.4), lineWidth: 0.8)
                .frame(width: glyphSize, height: glyphSize)
                .rotationEffect(.degrees(45))
        }
    }
}

#if DEBUG
#Preview("Crystal — large") {
    VStack(spacing: 40) {
        ForEach([0, 3, 5, 8], id: \.self) { n in
            VStack(spacing: 8) {
                MaturityCrystalView(filledCount: n, diameter: 96)
                Text(MaturityCrystalView.captionText(for: n))
                    .font(DS.smallCaps)
                    .foregroundStyle(DS.giltMuted)
            }
        }
    }
    .padding(40)
    .background(DS.vellum)
}

#Preview("Crystal — inline row") {
    VStack(spacing: 16) {
        MaturityCrystalInline(filledCount: 0)
        MaturityCrystalInline(filledCount: 3)
        MaturityCrystalInline(filledCount: 5)
        MaturityCrystalInline(filledCount: 8)
    }
    .padding(24)
    .background(DS.vellum)
}
#endif
