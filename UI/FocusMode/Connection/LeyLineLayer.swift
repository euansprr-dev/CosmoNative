// CosmoOS/UI/FocusMode/Connection/LeyLineLayer.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// Quiet gilt ley lines between stations and sources. Adapted from
// KnowledgePulseLineView's bezier math but stripped of the animated pulse —
// ley lines are acts, not identities, and they should never compete with
// content for attention. 35% max opacity, 1pt stroke, soft gilt glow.

import SwiftUI

/// A single ley line endpoint pair.
struct LeyLine: Identifiable, Equatable {
    let id: UUID
    var from: CGPoint
    var to: CGPoint
    /// 0.0 – 1.0. Drives opacity.
    var strength: Double

    init(id: UUID = UUID(), from: CGPoint, to: CGPoint, strength: Double = 1.0) {
        self.id = id
        self.from = from
        self.to = to
        self.strength = max(0, min(1, strength))
    }
}

/// Renders a set of ley lines in a coordinate space. Coordinates are expected to
/// match the enclosing container — typically use `.coordinateSpace(name:)` + a
/// preference key on stations and sources to collect their centers.
struct LeyLineLayer: View {

    let lines: [LeyLine]

    /// Global hover state — all lines fade in together when true.
    var isActive: Bool

    /// Max opacity when active. Spec target: 0.35 at rest, bump to ~0.55 on hover.
    var maxOpacity: Double = 0.35

    var body: some View {
        Canvas { context, _ in
            for line in lines {
                let path = leyPath(from: line.from, to: line.to)

                // Soft glow underlay
                var glowContext = context
                glowContext.addFilter(.blur(radius: 3))
                glowContext.stroke(
                    path,
                    with: .color(DS.gilt.opacity(maxOpacity * 0.55 * line.strength)),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )

                // Crisp bezier
                context.stroke(
                    path,
                    with: .color(DS.gilt.opacity(maxOpacity * line.strength)),
                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                )
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeInOut(duration: isActive ? 0.18 : 0.3), value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Bezier

    private func leyPath(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: to, control: controlPoint(from: from, to: to))
        return path
    }

    private func controlPoint(from: CGPoint, to: CGPoint) -> CGPoint {
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return CGPoint(x: midX, y: midY) }

        // Perpendicular offset, 15% of line length (matches KnowledgePulseLineView)
        let perpX = -dy / length
        let perpY = dx / length
        let offset = length * 0.15

        // Deterministic curve side based on endpoint ordering — keeps multiple
        // lines between the same pair of zones from stacking on each other.
        let direction: CGFloat = from.x + from.y < to.x + to.y ? 1 : -1

        return CGPoint(
            x: midX + perpX * offset * direction,
            y: midY + perpY * offset * direction
        )
    }
}

// MARK: - Preference key for reporting endpoint centers

/// Collects endpoint positions from descendants. Key: an opaque string identifier
/// (station rawValue, source UUID, etc.). Value: the center point in the named
/// coordinate space.
struct LeyEndpointPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGPoint] { [:] }

    static func reduce(value: inout [String: CGPoint], nextValue: () -> [String: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Reports this view's center in the given coordinate space under `key`.
    /// The layer above collects all reports via `LeyEndpointPreferenceKey`.
    func reportLeyEndpoint(_ key: String, in coordinateSpace: String) -> some View {
        background(
            GeometryReader { geo in
                let frame = geo.frame(in: .named(coordinateSpace))
                let center = CGPoint(x: frame.midX, y: frame.midY)
                Color.clear.preference(
                    key: LeyEndpointPreferenceKey.self,
                    value: [key: center]
                )
            }
        )
    }
}

#if DEBUG
#Preview("Ley lines — active") {
    ZStack {
        DS.vellum

        LeyLineLayer(
            lines: [
                LeyLine(from: CGPoint(x: 80, y: 80), to: CGPoint(x: 320, y: 220), strength: 1.0),
                LeyLine(from: CGPoint(x: 80, y: 80), to: CGPoint(x: 260, y: 380), strength: 0.6),
                LeyLine(from: CGPoint(x: 80, y: 80), to: CGPoint(x: 420, y: 120), strength: 0.3)
            ],
            isActive: true
        )
        .frame(width: 500, height: 460)

        // Endpoint dots for orientation
        Circle().fill(DS.gilt).frame(width: 6, height: 6).position(x: 80, y: 80)
        Circle().fill(DS.gilt.opacity(0.6)).frame(width: 6, height: 6).position(x: 320, y: 220)
        Circle().fill(DS.gilt.opacity(0.6)).frame(width: 6, height: 6).position(x: 260, y: 380)
        Circle().fill(DS.gilt.opacity(0.6)).frame(width: 6, height: 6).position(x: 420, y: 120)
    }
    .frame(width: 500, height: 460)
}
#endif
