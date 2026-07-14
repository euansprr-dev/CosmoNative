// CosmoOS/Onboarding/ConstellationField.swift
// The First Constellation — a seeded star-chart of a workspace at rest.
// Deterministic (same sky every launch: it's authored, not random), drawn
// with TimelineView + Canvas: slow orbital drift, gilt stars breathing,
// hairline links fading with distance. All motion is computed from wall-clock
// time inside the Canvas, so entrance, drift, and the sign-in converge are
// buttery at any frame rate and cost nothing when Reduce Motion pauses the
// timeline. iOS twin: CosmoiOS/Sources/Onboarding/ConstellationField.swift —
// same seed, same geometry. One sky, two windows.

import SwiftUI

// MARK: - Deterministic PRNG (SplitMix64 — tiny, seedable, stable)

struct ConstellationRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
    mutating func range(_ r: ClosedRange<Double>) -> Double { r.lowerBound + unit() * (r.upperBound - r.lowerBound) }
}

// MARK: - The chart

struct Constellation {
    struct Node {
        var base: CGPoint          // unit space (0…1)
        var radius: CGFloat        // pt
        var tintIndex: Int         // index into the entity-tint cycle; -1 = gilt star
        var depth: CGFloat         // 0.3 far … 1.0 near (parallax + size weight)
        var orbitRadius: Double    // unit-space drift amplitude
        var orbitPhase: Double
        var orbitPeriod: Double    // seconds per orbit (slow — 24…44s)
        var breathePhase: Double
        var appearDelay: Double    // entrance stagger
    }

    struct Link { let a: Int; let b: Int }

    let nodes: [Node]
    let links: [Link]

    /// The one sky. Seed chosen once; changing it redesigns the constellation.
    static let shared = Constellation(seed: 0xC0530C05, count: 44)

    init(seed: UInt64, count: Int) {
        var rng = ConstellationRandom(seed: seed)
        var nodes: [Node] = []
        nodes.reserveCapacity(count)

        // Jittered grid, not uniform random: every region of the sky holds a
        // star, none clump — the chart reads composed, like it was drawn.
        let columns = 5
        let rows = (count + columns - 1) / columns
        for index in 0..<count {
            let cell = CGSize(width: 1.0 / Double(columns), height: 1.0 / Double(rows))
            let column = Double(index % columns)
            let row = Double(index / columns)
            let depth = CGFloat(rng.range(0.3...1.0))
            nodes.append(Node(
                base: CGPoint(
                    x: (column + rng.range(0.12...0.88)) * cell.width,
                    y: (row + rng.range(0.12...0.88)) * cell.height
                ),
                radius: 1.2 + depth * CGFloat(rng.range(0.8...2.4)),
                tintIndex: index % 7,
                depth: depth,
                orbitRadius: rng.range(0.004...0.014),
                orbitPhase: rng.range(0...(2 * .pi)),
                orbitPeriod: rng.range(24...44),
                breathePhase: rng.range(0...(2 * .pi)),
                appearDelay: rng.range(0...1.1)
            ))
        }

        // Three gilt stars — the brightest points of the sky, spread apart.
        for starIndex in [3, count / 2, count - 5] {
            nodes[starIndex].tintIndex = -1
            nodes[starIndex].radius = 2.6 + CGFloat(rng.range(0...0.8))
            nodes[starIndex].depth = 1.0
        }

        // Links: near neighbours only, max 3 per node — a chart, not a net.
        var links: [Link] = []
        var linkCount = [Int](repeating: 0, count: count)
        for a in 0..<count {
            for b in (a + 1)..<count {
                guard linkCount[a] < 3, linkCount[b] < 3 else { continue }
                let dx = nodes[a].base.x - nodes[b].base.x
                let dy = nodes[a].base.y - nodes[b].base.y
                if (dx * dx + dy * dy).squareRoot() < 0.15 {
                    links.append(Link(a: a, b: b))
                    linkCount[a] += 1
                    linkCount[b] += 1
                }
            }
        }
        self.nodes = nodes
        self.links = links
    }
}

// MARK: - The renderer

/// Full-bleed sky. `parallax` shifts layers by depth (points at depth 1);
/// `convergeStartedAt` runs the arrival choreography — every node accelerates
/// toward the heart of the canvas as the gate dissolves.
struct ConstellationFieldView: View {
    var parallax: CGSize = .zero
    var convergeStartedAt: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let convergeDuration: Double = 0.65

    /// The stars are Greenhouse gold in every theme — the Welcome sky is
    /// editorial art (the masthead-scene register), not chrome, and it shows
    /// before any theme is chosen. Mono palettes would grey it to nothing.
    private var starGold: Color {
        colorScheme == .dark ? Color(hex: "CBB37E") : Color(hex: "A08540")
    }

    /// Entity tints, in the atom-kind cycle — the sky is made of the same
    /// stuff as the workspace behind it.
    private static let tints: [Color] = [
        DS.entityResearch, DS.entityIdea, DS.entityNote, DS.entityContent,
        DS.entityConnection, DS.entityTask, DS.entityImage
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion && convergeStartedAt == nil)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, now: timeline.date)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: Date) {
        let chart = Constellation.shared
        let t = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate
        let sinceLaunch = now.timeIntervalSince(Self.launchDate)
        let converge = convergeProgress(now: now)

        var points: [CGPoint] = []
        points.reserveCapacity(chart.nodes.count)
        var alphas: [Double] = []
        alphas.reserveCapacity(chart.nodes.count)

        for node in chart.nodes {
            points.append(position(of: node, t: t, size: size, converge: converge))
            alphas.append(alpha(of: node, sinceLaunch: sinceLaunch, converge: converge))
        }

        // Hairline links, fading with the entrance and vanishing on converge.
        for link in chart.links {
            let alpha = min(alphas[link.a], alphas[link.b]) * (1 - converge)
            guard alpha > 0.01 else { continue }
            var path = Path()
            path.move(to: points[link.a])
            path.addLine(to: points[link.b])
            context.stroke(path, with: .color(DS.text.opacity(0.08 * alpha)), lineWidth: 0.75)
        }

        for (index, node) in chart.nodes.enumerated() {
            let point = points[index]
            let alpha = alphas[index]
            guard alpha > 0.01 else { continue }

            if node.tintIndex == -1 {
                // Gilt star: a slow breath — glow first, then the point.
                let breathe = reduceMotion ? 0.5 : (sin(t / 3.4 + node.breathePhase) + 1) / 2
                let glowRadius = node.radius * (2.6 + breathe * 1.6)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - glowRadius, y: point.y - glowRadius,
                                           width: glowRadius * 2, height: glowRadius * 2)),
                    with: .color(starGold.opacity((0.12 + breathe * 0.12) * alpha))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - node.radius, y: point.y - node.radius,
                                           width: node.radius * 2, height: node.radius * 2)),
                    with: .color(starGold.opacity((0.62 + breathe * 0.32) * alpha))
                )
            } else {
                let tint = Self.tints[node.tintIndex]
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - node.radius, y: point.y - node.radius,
                                           width: node.radius * 2, height: node.radius * 2)),
                    with: .color(tint.opacity((0.34 + Double(node.depth) * 0.32) * alpha))
                )
            }
        }
    }

    // MARK: Geometry

    private func position(of node: Constellation.Node, t: Double, size: CGSize, converge: Double) -> CGPoint {
        let angle = (t / node.orbitPeriod) * 2 * .pi + node.orbitPhase
        var x = (node.base.x + cos(angle) * node.orbitRadius) * size.width
        var y = (node.base.y + sin(angle) * node.orbitRadius * 0.6) * size.height
        x += parallax.width * node.depth
        y += parallax.height * node.depth
        guard converge > 0 else { return CGPoint(x: x, y: y) }
        // Ease-in pull toward the heart — far nodes arrive last.
        let pull = converge * converge * (0.7 + 0.3 * Double(node.depth))
        let heart = CGPoint(x: size.width / 2, y: size.height * 0.42)
        return CGPoint(x: x + (heart.x - x) * pull, y: y + (heart.y - y) * pull)
    }

    private func alpha(of node: Constellation.Node, sinceLaunch: Double, converge: Double) -> Double {
        let entrance = reduceMotion ? 1 : min(max((sinceLaunch - node.appearDelay) / 0.6, 0), 1)
        return entrance * (1 - converge * converge)
    }

    private func convergeProgress(now: Date) -> Double {
        guard let start = convergeStartedAt else { return 0 }
        return min(max(now.timeIntervalSince(start) / Self.convergeDuration, 0), 1)
    }

    /// Entrance clock — the sky assembles once per process, not per appear.
    private static let launchDate = Date()
}
