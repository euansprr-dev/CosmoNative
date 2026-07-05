// Core/Companion.swift
// The Greenhouse Companions — PORTED FROM CosmoOS-iOS (CosmoiOS/Sources/Design/
// Companion.swift); keep the art and palettes in lockstep. Twelve small
// hand-drawn marks that are the user's identity across both platforms. Each is vector art (Canvas paths in a 100×100
// design space) so it stays crisp at every size, and each carries a fixed
// botanical palette (like DS.clientPalette — never theme-dependent) so a
// companion keeps its face across themes and devices. The badge wash and
// ring, by contrast, ARE theme tokens, so the mark always sits correctly
// on the active palette.

import SwiftUI

// MARK: - The cast

enum Companion: String, CaseIterable, Identifiable, Codable {
    case sprout
    case fern
    case monstera
    case cactus
    case mushroom
    case snail
    case bee
    case moth
    case sun
    case moon
    case wateringCan
    case paperPlane

    var id: String { rawValue }

    /// The companion's given name — picker-only charm, never chrome.
    var name: String {
        switch self {
        case .sprout: return "Pip"
        case .fern: return "Fiddle"
        case .monstera: return "Delia"
        case .cactus: return "Otto"
        case .mushroom: return "Morel"
        case .snail: return "Juniper"
        case .bee: return "Clementine"
        case .moth: return "Luna"
        case .sun: return "Sol"
        case .moon: return "Sable"
        case .wateringCan: return "Wallace"
        case .paperPlane: return "Scout"
        }
    }

    var species: String {
        switch self {
        case .sprout: return "the sprout"
        case .fern: return "the fern"
        case .monstera: return "the monstera"
        case .cactus: return "the cactus"
        case .mushroom: return "the mushroom"
        case .snail: return "the snail"
        case .bee: return "the bee"
        case .moth: return "the moth"
        case .sun: return "the sun"
        case .moon: return "the moon"
        case .wateringCan: return "the watering can"
        case .paperPlane: return "the paper plane"
        }
    }

    /// One line of character — the picker's serif whisper.
    var bio: String {
        switch self {
        case .sprout: return "Small beginnings."
        case .fern: return "Unfurls in its own time."
        case .monstera: return "Grows toward the light."
        case .cactus: return "Thrives on very little."
        case .mushroom: return "Comfortable in the shade."
        case .snail: return "Slow is smooth."
        case .bee: return "Busy, never rushed."
        case .moth: return "Drawn to bright ideas."
        case .sun: return "Shows up every day."
        case .moon: return "Best work after dark."
        case .wateringCan: return "Keeper of small rituals."
        case .paperPlane: return "Already off on an errand."
        }
    }

    /// Primary ink — also drives the badge wash.
    var tint: Color {
        switch self {
        case .sprout: return Color(hex: "7FB069")
        case .fern: return Color(hex: "4A8B72")
        case .monstera: return Color(hex: "3E7C5B")
        case .cactus: return Color(hex: "7FA37A")
        case .mushroom: return Color(hex: "C1694F")
        case .snail: return Color(hex: "B08C5A")
        case .bee: return Color(hex: "E0A83C")
        case .moth: return Color(hex: "A3B899")
        case .sun: return Color(hex: "E8B84B")
        case .moon: return Color(hex: "6B7BA8")
        case .wateringCan: return Color(hex: "8FA5A8")
        case .paperPlane: return Color(hex: "8FA8C9")
        }
    }

    /// Deep ink for the second tone.
    var shade: Color {
        switch self {
        case .sprout: return Color(hex: "2D6A4F")
        case .fern: return Color(hex: "2F5D4A")
        case .monstera: return Color(hex: "2B5741")
        case .cactus: return Color(hex: "567553")
        case .mushroom: return Color(hex: "8F4A37")
        case .snail: return Color(hex: "7E633D")
        case .bee: return Color(hex: "3A342A")
        case .moth: return Color(hex: "5F7561")
        case .sun: return Color(hex: "D08A2E")
        case .moon: return Color(hex: "4A5680")
        case .wateringCan: return Color(hex: "5F787B")
        case .paperPlane: return Color(hex: "5B84B0")
        }
    }

    /// Cream/soft third tone for spots, wings, drops.
    var detail: Color {
        switch self {
        case .mushroom, .snail: return Color(hex: "F3EDE4")
        case .bee: return Color(hex: "FAF7EF")
        case .moth: return Color(hex: "F3EDE4")
        case .moon: return Color(hex: "D9B44A")
        case .cactus: return Color(hex: "E8909C")
        case .wateringCan: return Color(hex: "8FBFD9")
        case .paperPlane: return Color(hex: "EDF2F8")
        default: return Color(hex: "F3EDE4")
        }
    }

    var accessibilityDescription: String {
        "\(name) \(species)"
    }
}

// MARK: - Vitality (the living part — fed by the focus streak)

/// How the companion carries itself today. Never punitive: the worst state
/// is simply "resting". Raw values are stable for the demo launch flag.
enum CompanionVitality: String {
    /// The everyday state.
    case resting
    /// Today's focus goal is met — a quiet accent ring.
    case thriving
    /// A 7-day focus streak — the ring turns gilt and shimmers once.
    case radiant
    /// A 30-day focus streak — the gilt ring earns a small star.
    case luminous
}

// MARK: - The badge

/// The companion in its round parchment badge — the app's identity mark.
/// The wash and ring are theme tokens; the drawing is the companion's own.
struct CompanionMark: View {
    let companion: Companion
    var size: CGFloat = 32
    var vitality: CompanionVitality = .resting

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Angle of the gilt shimmer sweep (radiant only, runs once on appear).
    @State private var shimmerAngle: Double = -90
    /// One proud bow when vitality rises while on screen.
    @State private var celebrating = false

    var body: some View {
        ZStack {
            Circle().fill(DS.vellum)
            Circle().fill(companion.tint.opacity(DS.palette.isDark ? 0.24 : 0.15))
            Canvas { ctx, canvasSize in
                ctx.scaleBy(x: canvasSize.width / 100, y: canvasSize.height / 100)
                CompanionArt.draw(companion, in: &ctx, month: Self.month)
            }
            ring
        }
        .overlay(alignment: .topTrailing) {
            if vitality == .luminous {
                // The thirty-day star — worn just off the shoulder of the ring.
                CompanionSparkle(color: DS.gilt)
                    .frame(width: size * 0.32, height: size * 0.32)
                    .offset(x: size * 0.06, y: -size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(celebrating ? 1.08 : 1)
        .onAppear {
            guard vitality == .radiant || vitality == .luminous, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6)) { shimmerAngle = 270 }
        }
        .onChange(of: vitality) { old, new in
            // The companion notices the moment you cross the line today.
            guard old == .resting, new != .resting, !reduceMotion else { return }
            withAnimation(ProMotionSprings.bouncy) { celebrating = true }
            Task {
                try? await Task.sleep(for: .milliseconds(280))
                withAnimation(ProMotionSprings.gentle) { celebrating = false }
            }
        }
        .accessibilityHidden(true) // callers label the whole control
    }

    private var ringWidth: CGFloat { max(1, size / 30) }

    @ViewBuilder
    private var ring: some View {
        switch vitality {
        case .resting:
            Circle().strokeBorder(DS.sepiaBorder, lineWidth: ringWidth)
        case .thriving:
            Circle().strokeBorder(DS.accent.opacity(0.55), lineWidth: ringWidth)
        case .radiant, .luminous:
            Circle().strokeBorder(
                AngularGradient(
                    colors: [DS.gilt, Color(hex: "E8D28A"), DS.gilt, DS.gilt],
                    center: .center,
                    angle: .degrees(shimmerAngle)
                ),
                lineWidth: ringWidth * 1.2
            )
        }
    }

    /// Current month, overridable headlessly for seasonal screenshots.
    static var month: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-cosmo-demo-month"),
           args.indices.contains(index + 1),
           let forced = Int(args[index + 1]), (1...12).contains(forced) {
            return forced
        }
        #endif
        return Calendar.current.component(.month, from: .now)
    }
}

/// The four-point gilt star, as a standalone view (the 30-day mark).
struct CompanionSparkle: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 100, y: size.height / 100)
            ctx.fill(
                CompanionArt.sparklePath(center: CGPoint(x: 50, y: 50), radius: 46),
                with: .color(color)
            )
        }
    }
}

// MARK: - The art

/// All drawing happens in a 100×100 space; the badge's visual safe zone is
/// roughly the 22…78 square. Everything is flat two-tone with round caps —
/// the same rounded, warm geometry as the rest of the app.
private enum CompanionArt {

    static func draw(_ companion: Companion, in ctx: inout GraphicsContext, month: Int = 6) {
        switch companion {
        case .sprout: sprout(&ctx)
        case .fern: fern(&ctx, month: month)
        case .monstera: monstera(&ctx)
        case .cactus: cactus(&ctx)
        case .mushroom: mushroom(&ctx)
        case .snail: snail(&ctx)
        case .bee: bee(&ctx)
        case .moth: moth(&ctx)
        case .sun: sun(&ctx)
        case .moon: moon(&ctx)
        case .wateringCan: wateringCan(&ctx)
        case .paperPlane: paperPlane(&ctx)
        }
        seasonalAccent(for: companion, month: month, in: &ctx)
    }

    // MARK: Seasons — one whisper per quarter, two companions each.
    // Small enough that noticing it feels like a secret, never a costume.

    private enum Season {
        case spring, summer, autumn, winter

        init(month: Int) {
            switch month {
            case 3...5: self = .spring
            case 6...8: self = .summer
            case 9...11: self = .autumn
            default: self = .winter
            }
        }
    }

    private static let blossom = Color(hex: "E8909C")
    private static let snow = Color(hex: "F8F5EE")
    private static let amber = Color(hex: "D08A2E")
    private static let giltStar = Color(hex: "D9B44A")

    private static func seasonalAccent(
        for companion: Companion, month: Int, in ctx: inout GraphicsContext
    ) {
        switch (Season(month: month), companion) {
        case (.spring, .sprout):
            // Pip flowers — one blossom where the leaves meet.
            ctx.fill(circle(50, 48, 3), with: .color(blossom))
            ctx.fill(circle(50, 48, 1.2), with: .color(snow))
        case (.spring, .snail):
            // something small growing on Juniper's shell
            ctx.fill(circle(56, 30, 2.4), with: .color(blossom))
            ctx.fill(circle(56, 30, 1), with: .color(snow))
        case (.summer, .sun):
            // high summer — Sol throws one extra glint
            ctx.fill(sparklePath(center: CGPoint(x: 76, y: 26), radius: 5), with: .color(giltStar))
        case (.summer, .bee):
            // pollen on the air behind Clementine
            ctx.fill(circle(20, 44, 1.8), with: .color(giltStar))
            ctx.fill(circle(15, 52, 1.3), with: .color(giltStar))
        case (.autumn, .paperPlane):
            // one leaf riding Scout's slipstream
            ctx.fill(
                leaf(from: CGPoint(x: 24, y: 52), to: CGPoint(x: 31, y: 46), bulge: 3),
                with: .color(amber)
            )
        case (.winter, .moon):
            // long nights — Sable keeps a second star
            ctx.fill(sparklePath(center: CGPoint(x: 30, y: 30), radius: 4.5), with: .color(giltStar))
        case (.winter, .mushroom):
            // first snow resting on Morel's cap
            ctx.fill(circle(44, 26, 1.7), with: .color(snow))
            ctx.fill(circle(55, 24.5, 1.3), with: .color(snow))
            ctx.fill(circle(33, 40, 1.2), with: .color(snow))
        default:
            break
        }
    }

    // MARK: Shared geometry

    /// A leaf: two mirrored quad curves between tip and base.
    private static func leaf(from a: CGPoint, to b: CGPoint, bulge: CGFloat) -> Path {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(sqrt(dx * dx + dy * dy), 0.001)
        let n = CGPoint(x: -dy / len, y: dx / len)
        var p = Path()
        p.move(to: a)
        p.addQuadCurve(to: b, control: CGPoint(x: mid.x + n.x * bulge, y: mid.y + n.y * bulge))
        p.addQuadCurve(to: a, control: CGPoint(x: mid.x - n.x * bulge, y: mid.y - n.y * bulge))
        p.closeSubpath()
        return p
    }

    private static func spiral(
        center: CGPoint, from startRadius: CGFloat, to endRadius: CGFloat,
        turns: CGFloat, startAngle: CGFloat = 0
    ) -> Path {
        var p = Path()
        let steps = max(Int(turns * 48), 12)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = startAngle + t * turns * 2 * .pi
            let r = startRadius + (endRadius - startRadius) * t
            let pt = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    private static func line(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    private static func stroke(
        _ ctx: inout GraphicsContext, _ path: Path, _ color: Color,
        _ width: CGFloat, dash: [CGFloat] = []
    ) {
        ctx.stroke(
            path, with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
        )
    }

    // MARK: Pip the sprout — two leaves finding their way up

    private static func sprout(_ ctx: inout GraphicsContext) {
        let c = Companion.sprout
        // soil
        ctx.fill(
            Path(ellipseIn: CGRect(x: 36, y: 71, width: 28, height: 8)),
            with: .color(c.shade.opacity(0.28))
        )
        // stem — a gentle S
        var stem = Path()
        stem.move(to: CGPoint(x: 50, y: 74))
        stem.addQuadCurve(to: CGPoint(x: 50, y: 50), control: CGPoint(x: 45, y: 62))
        stroke(&ctx, stem, c.shade, 3.5)
        // small left leaf (deep), big right leaf (fresh)
        ctx.fill(leaf(from: CGPoint(x: 49, y: 60), to: CGPoint(x: 31, y: 46), bulge: 9), with: .color(c.shade))
        ctx.fill(leaf(from: CGPoint(x: 50, y: 53), to: CGPoint(x: 71, y: 34), bulge: 11), with: .color(c.tint))
    }

    // MARK: Fiddle the fern — a fiddlehead mid-unfurl

    private static func fern(_ ctx: inout GraphicsContext, month: Int) {
        let c = Companion.fern
        // autumn: the lowest leaflet turns first
        let firstLeaflet = Season(month: month) == .autumn ? amber : c.tint
        // stem sweeping up to the curl
        var stem = Path()
        stem.move(to: CGPoint(x: 35, y: 80))
        stem.addQuadCurve(to: CGPoint(x: 57, y: 42), control: CGPoint(x: 38, y: 56))
        stroke(&ctx, stem, c.shade, 3)
        // the curl
        stroke(
            &ctx,
            spiral(center: CGPoint(x: 61, y: 34), from: 11, to: 1.5, turns: 1.45, startAngle: .pi * 0.72),
            c.shade, 3
        )
        // leaflets, alternating, shrinking upward
        ctx.fill(leaf(from: CGPoint(x: 40, y: 70), to: CGPoint(x: 25, y: 63), bulge: 6), with: .color(firstLeaflet))
        ctx.fill(leaf(from: CGPoint(x: 43, y: 62), to: CGPoint(x: 57, y: 60), bulge: 5.5), with: .color(c.tint))
        ctx.fill(leaf(from: CGPoint(x: 47, y: 53), to: CGPoint(x: 34, y: 45), bulge: 5), with: .color(c.tint))
    }

    // MARK: Delia the monstera — the split leaf

    private static func monstera(_ ctx: inout GraphicsContext) {
        let c = Companion.monstera
        ctx.drawLayer { layer in
            // the blade — a rounded heart, tip at the bottom
            var blade = Path()
            blade.move(to: CGPoint(x: 50, y: 24))
            blade.addCurve(to: CGPoint(x: 74, y: 46), control1: CGPoint(x: 66, y: 24), control2: CGPoint(x: 74, y: 32))
            blade.addCurve(to: CGPoint(x: 52, y: 76), control1: CGPoint(x: 74, y: 62), control2: CGPoint(x: 62, y: 70))
            blade.addCurve(to: CGPoint(x: 26, y: 46), control1: CGPoint(x: 42, y: 70), control2: CGPoint(x: 26, y: 62))
            blade.addCurve(to: CGPoint(x: 50, y: 24), control1: CGPoint(x: 26, y: 32), control2: CGPoint(x: 34, y: 24))
            blade.closeSubpath()
            layer.fill(blade, with: .color(c.tint))
            // midrib
            layer.stroke(
                line([CGPoint(x: 50, y: 32), CGPoint(x: 52, y: 72)]),
                with: .color(c.shade.opacity(0.55)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            // punch the signature splits and holes out of the blade
            layer.blendMode = .destinationOut
            let punch = StrokeStyle(lineWidth: 4.5, lineCap: .round)
            layer.stroke(line([CGPoint(x: 50, y: 18), CGPoint(x: 50, y: 33)]), with: .color(.black), style: punch)
            layer.stroke(line([CGPoint(x: 25, y: 42), CGPoint(x: 43, y: 46)]), with: .color(.black), style: punch)
            layer.stroke(line([CGPoint(x: 27, y: 57), CGPoint(x: 44, y: 59)]), with: .color(.black), style: punch)
            layer.stroke(line([CGPoint(x: 75, y: 42), CGPoint(x: 57, y: 46)]), with: .color(.black), style: punch)
            layer.stroke(line([CGPoint(x: 73, y: 57), CGPoint(x: 56, y: 59)]), with: .color(.black), style: punch)
            layer.fill(circle(46, 51, 2.2), with: .color(.black))
            layer.fill(circle(58, 52, 1.8), with: .color(.black))
        }
    }

    // MARK: Otto the cactus — arms up, flowering anyway

    private static func cactus(_ ctx: inout GraphicsContext) {
        let c = Companion.cactus
        let pot = Companion.mushroom.tint // shared terracotta
        // trunk and arms first (they sit behind the pot rim)
        stroke(&ctx, line([CGPoint(x: 50, y: 34), CGPoint(x: 50, y: 62)]), c.tint, 13)
        stroke(&ctx, line([CGPoint(x: 45, y: 48), CGPoint(x: 36, y: 48), CGPoint(x: 36, y: 39)]), c.tint, 7)
        stroke(&ctx, line([CGPoint(x: 55, y: 53), CGPoint(x: 64, y: 53), CGPoint(x: 64, y: 44)]), c.tint, 7)
        // a few quiet ribs
        stroke(&ctx, line([CGPoint(x: 50, y: 38), CGPoint(x: 50, y: 58)]), c.shade.opacity(0.5), 1.5)
        // the pot
        var body = Path()
        body.move(to: CGPoint(x: 38, y: 64))
        body.addLine(to: CGPoint(x: 62, y: 64))
        body.addLine(to: CGPoint(x: 59, y: 78))
        body.addQuadCurve(to: CGPoint(x: 41, y: 78), control: CGPoint(x: 50, y: 80))
        body.closeSubpath()
        ctx.fill(body, with: .color(pot))
        ctx.fill(
            Path(roundedRect: CGRect(x: 35, y: 58, width: 30, height: 7), cornerRadius: 2.5),
            with: .color(Companion.mushroom.shade)
        )
        // one small stubborn bloom
        ctx.fill(circle(50, 29, 3.4), with: .color(c.detail))
        ctx.fill(circle(50, 29, 1.3), with: .color(Color(hex: "FAF7EF")))
    }

    // MARK: Morel the mushroom — spotted, content

    private static func mushroom(_ ctx: inout GraphicsContext) {
        let c = Companion.mushroom
        // stem
        stroke(&ctx, line([CGPoint(x: 50, y: 57), CGPoint(x: 50, y: 71)]), c.detail, 13)
        // cap
        var cap = Path()
        cap.move(to: CGPoint(x: 24, y: 53))
        cap.addCurve(to: CGPoint(x: 76, y: 53), control1: CGPoint(x: 26, y: 22), control2: CGPoint(x: 74, y: 22))
        cap.addQuadCurve(to: CGPoint(x: 24, y: 53), control: CGPoint(x: 50, y: 60))
        cap.closeSubpath()
        ctx.fill(cap, with: .color(c.tint))
        // spots
        ctx.fill(circle(40, 38, 4), with: .color(c.detail))
        ctx.fill(circle(57, 32, 3), with: .color(c.detail))
        ctx.fill(circle(62, 44, 2.5), with: .color(c.detail))
        // gill line
        stroke(&ctx, line([CGPoint(x: 33, y: 54), CGPoint(x: 67, y: 54)]), c.shade.opacity(0.4), 1.5)
    }

    // MARK: Juniper the snail — spiral home, out for a walk

    private static func snail(_ ctx: inout GraphicsContext) {
        let c = Companion.snail
        // body — head rises at the left
        var body = Path()
        body.move(to: CGPoint(x: 30, y: 57))
        body.addLine(to: CGPoint(x: 30, y: 66))
        body.addQuadCurve(to: CGPoint(x: 70, y: 68), control: CGPoint(x: 50, y: 71))
        stroke(&ctx, body, c.detail, 9)
        // antennae
        stroke(&ctx, line([CGPoint(x: 28, y: 54), CGPoint(x: 23, y: 45)]), c.shade, 2)
        stroke(&ctx, line([CGPoint(x: 33, y: 53), CGPoint(x: 32, y: 43)]), c.shade, 2)
        ctx.fill(circle(22.5, 43.5, 2), with: .color(c.shade))
        ctx.fill(circle(31.8, 41.5, 2), with: .color(c.shade))
        // shell
        ctx.fill(circle(56, 50, 18), with: .color(c.tint))
        stroke(
            &ctx,
            spiral(center: CGPoint(x: 56, y: 50), from: 15.5, to: 2, turns: 1.4, startAngle: .pi),
            c.shade, 2.5
        )
    }

    // MARK: Clementine the bee — mid-flight, stripes that follow her curve

    private static func bee(_ ctx: inout GraphicsContext) {
        let c = Companion.bee
        // Everything tilts 10° head-up: she's climbing, chin forward.
        let tilt = rotation(degrees: 10, around: CGPoint(x: 52, y: 54))

        // wings first — a close pair off the thorax, both raked back, overlapping
        let rearWing = leaf(from: CGPoint(x: 48, y: 48), to: CGPoint(x: 68, y: 24), bulge: 9.5)
            .applying(tilt)
        let frontWing = leaf(from: CGPoint(x: 45, y: 48), to: CGPoint(x: 57, y: 16), bulge: 11)
            .applying(tilt)
        for (wing, vein) in [
            (rearWing, line([CGPoint(x: 52, y: 44), CGPoint(x: 63, y: 29)]).applying(tilt)),
            (frontWing, line([CGPoint(x: 48, y: 42), CGPoint(x: 54, y: 23)]).applying(tilt)),
        ] {
            ctx.fill(wing, with: .color(c.detail.opacity(0.92)))
            stroke(&ctx, wing, c.shade.opacity(0.28), 1.1)
            stroke(&ctx, vein, c.shade.opacity(0.22), 1)
        }

        // body — a plump teardrop, rounder at the shoulder, easing to the tail
        var body = Path()
        body.move(to: CGPoint(x: 36, y: 56))
        body.addCurve(to: CGPoint(x: 74, y: 59), control1: CGPoint(x: 43, y: 42), control2: CGPoint(x: 68, y: 45))
        body.addCurve(to: CGPoint(x: 36, y: 56), control1: CGPoint(x: 69, y: 72), control2: CGPoint(x: 44, y: 71))
        body.closeSubpath()
        let tiltedBody = body.applying(tilt)

        ctx.drawLayer { layer in
            layer.fill(tiltedBody, with: .color(c.tint))
            layer.clip(to: tiltedBody)
            // stripes curve with her — arcs, not bars, tapering into the seams
            for (x, w) in [(CGFloat(47), CGFloat(5)), (56, 6), (65, 5)] {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x + 2, y: 40))
                stripe.addQuadCurve(
                    to: CGPoint(x: x - 2, y: 76),
                    control: CGPoint(x: x + 4.5, y: 58)
                )
                layer.stroke(
                    stripe.applying(tilt), with: .color(c.shade),
                    style: StrokeStyle(lineWidth: w, lineCap: .round)
                )
            }
            // belly shadow — one soft crescent of volume along her underside
            layer.fill(
                Path(ellipseIn: CGRect(x: 26, y: 62, width: 56, height: 34)).applying(tilt),
                with: .color(c.shade.opacity(0.18))
            )
        }

        // head — level with the body's shoulder, eye looking where she's going
        ctx.fill(circle(32, 55, 8).applying(tilt), with: .color(c.shade))
        ctx.fill(circle(28.8, 53, 1.8).applying(tilt), with: .color(c.detail))
        var antenna = Path()
        antenna.move(to: CGPoint(x: 29, y: 48))
        antenna.addQuadCurve(to: CGPoint(x: 23, y: 40), control: CGPoint(x: 23, y: 47))
        stroke(&ctx, antenna.applying(tilt), c.shade, 1.6)
        ctx.fill(circle(23, 40, 1.5).applying(tilt), with: .color(c.shade))
    }

    // MARK: Luna the moth — the classic spread silhouette, eyespots riding the blades

    private static func moth(_ ctx: inout GraphicsContext) {
        let c = Companion.moth

        // antennae — thin curves with dot tips (the set's shared insect voice)
        for side: CGFloat in [-1, 1] {
            var shaft = Path()
            shaft.move(to: CGPoint(x: 50 + side * 1, y: 41))
            shaft.addQuadCurve(
                to: CGPoint(x: 50 + side * 9, y: 27),
                control: CGPoint(x: 50 + side * 4, y: 32)
            )
            stroke(&ctx, shaft, c.shade, 1.3)
            ctx.fill(circle(50 + side * 9, 27, 1.5), with: .color(c.shade))
        }

        // hindwings — small scalloped fans behind the body's tail
        ctx.fill(leaf(from: CGPoint(x: 50, y: 53), to: CGPoint(x: 40, y: 65), bulge: -6), with: .color(c.shade))
        ctx.fill(leaf(from: CGPoint(x: 50, y: 53), to: CGPoint(x: 60, y: 65), bulge: 6), with: .color(c.shade))

        // forewings — broad delta blades, the whole silhouette of a moth
        for side: CGFloat in [-1, 1] {
            var wing = Path()
            wing.move(to: CGPoint(x: 50, y: 45))
            // leading edge out to the raised tip
            wing.addQuadCurve(
                to: CGPoint(x: 50 + side * 26, y: 32),
                control: CGPoint(x: 50 + side * 13, y: 31)
            )
            // trailing edge home in two gentle scallops
            wing.addQuadCurve(
                to: CGPoint(x: 50 + side * 13, y: 50),
                control: CGPoint(x: 50 + side * 23, y: 46)
            )
            wing.addQuadCurve(
                to: CGPoint(x: 50, y: 53),
                control: CGPoint(x: 50 + side * 6, y: 53)
            )
            wing.closeSubpath()
            ctx.fill(wing, with: .color(c.tint))
        }

        // eyespots — ring in ring, one per blade
        for x in [CGFloat(35), 65] {
            ctx.fill(circle(x, 40, 3.2), with: .color(c.detail))
            ctx.fill(circle(x, 40, 1.4), with: .color(c.shade))
        }

        // body — slim, segmented, tapering between the wings
        stroke(&ctx, line([CGPoint(x: 50, y: 44), CGPoint(x: 50, y: 62)]), c.shade, 5)
        ctx.drawLayer { layer in
            for y in [CGFloat(50), 54, 58] {
                layer.stroke(
                    line([CGPoint(x: 48, y: y), CGPoint(x: 52, y: y)]),
                    with: .color(c.tint.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 1)
                )
            }
        }
        ctx.fill(circle(50, 42.5, 2.9), with: .color(c.shade))
    }

    // MARK: Sol the sun — eight rounded rays

    private static func sun(_ ctx: inout GraphicsContext) {
        let c = Companion.sun
        let center = CGPoint(x: 50, y: 51)
        // rays alternate long and short — a drawn sun, not a stamped one
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 + .pi / 8
            let long = i.isMultiple(of: 2)
            let from = CGPoint(x: center.x + cos(angle) * 20.5, y: center.y + sin(angle) * 20.5)
            let reach: CGFloat = long ? 29 : 25
            let to = CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach)
            stroke(&ctx, line([from, to]), c.tint, long ? 4.5 : 3.4)
        }
        ctx.fill(circle(center.x, center.y, 14), with: .color(c.tint))
        stroke(&ctx, circle(center.x, center.y, 9.5), c.shade.opacity(0.5), 1.5)
        // one catchlight on the disc's shoulder
        ctx.fill(circle(44.5, 45, 2), with: .color(Color(hex: "FAF3DC").opacity(0.9)))
    }

    // MARK: Sable the moon — a crescent and one gilt star

    private static func moon(_ ctx: inout GraphicsContext) {
        let c = Companion.moon
        ctx.drawLayer { layer in
            layer.fill(circle(47, 53, 24), with: .color(c.tint))
            // craters — quiet discs of a deeper slate along the lit band
            layer.fill(circle(36, 44, 3), with: .color(c.shade.opacity(0.45)))
            layer.fill(circle(33, 56, 1.9), with: .color(c.shade.opacity(0.45)))
            layer.fill(circle(42, 66, 2.4), with: .color(c.shade.opacity(0.45)))
            layer.fill(circle(40, 51, 1.2), with: .color(c.shade.opacity(0.35)))
            layer.blendMode = .destinationOut
            layer.fill(circle(58, 45, 20), with: .color(.black))
        }
        // a small constellation, placed — one star and two lesser companions
        ctx.fill(sparklePath(center: CGPoint(x: 67, y: 33), radius: 6.5), with: .color(c.detail))
        ctx.fill(circle(74, 45, 1.7), with: .color(c.detail))
        ctx.fill(circle(61, 23, 1.1), with: .color(c.detail.opacity(0.8)))
    }

    // MARK: Wallace the watering can — mid-pour, always

    private static func wateringCan(_ ctx: inout GraphicsContext) {
        let c = Companion.wateringCan
        // handle
        var handle = Path()
        handle.move(to: CGPoint(x: 46, y: 48))
        handle.addQuadCurve(to: CGPoint(x: 63, y: 48), control: CGPoint(x: 54.5, y: 33))
        stroke(&ctx, handle, c.shade, 3.5)
        // spout, then the rose
        stroke(&ctx, line([CGPoint(x: 43, y: 58), CGPoint(x: 25, y: 38)]), c.tint, 5.5)
        ctx.fill(
            Path(ellipseIn: CGRect(x: 18.5, y: 32.5, width: 10, height: 9)),
            with: .color(c.shade)
        )
        // body
        ctx.fill(
            Path(roundedRect: CGRect(x: 40, y: 48, width: 27, height: 25), cornerRadius: 6),
            with: .color(c.tint)
        )
        stroke(&ctx, line([CGPoint(x: 44, y: 53), CGPoint(x: 63, y: 53)]), c.shade.opacity(0.45), 1.5)
        // drops fanning from the rose, shrinking as they fall
        ctx.fill(circle(13, 43, 2.2), with: .color(c.detail))
        ctx.fill(circle(11, 51, 1.8), with: .color(c.detail))
        ctx.fill(circle(16, 56, 1.5), with: .color(c.detail))
        ctx.fill(circle(21, 49, 1.1), with: .color(c.detail.opacity(0.8)))
    }

    // MARK: Scout the paper plane — two folds and a trail

    private static func paperPlane(_ ctx: inout GraphicsContext) {
        let c = Companion.paperPlane
        // trail — a dotted S-swoop from wherever it's been
        var trail = Path()
        trail.move(to: CGPoint(x: 12, y: 74))
        trail.addCurve(
            to: CGPoint(x: 40, y: 64),
            control1: CGPoint(x: 22, y: 80),
            control2: CGPoint(x: 30, y: 66)
        )
        stroke(&ctx, trail, c.shade.opacity(0.5), 2, dash: [0.5, 6])
        // three facets — far wing, visible fuselage fold, near keel
        ctx.fill(
            line([CGPoint(x: 76, y: 30), CGPoint(x: 26, y: 44), CGPoint(x: 46, y: 54)]).closedIf(),
            with: .color(c.tint)
        )
        ctx.fill(
            line([CGPoint(x: 76, y: 30), CGPoint(x: 46, y: 54), CGPoint(x: 43, y: 62)]).closedIf(),
            with: .color(c.detail)
        )
        ctx.fill(
            line([CGPoint(x: 76, y: 30), CGPoint(x: 43, y: 62), CGPoint(x: 40, y: 70)]).closedIf(),
            with: .color(c.shade)
        )
        // crease hairlines where the folds meet
        stroke(&ctx, line([CGPoint(x: 76, y: 30), CGPoint(x: 46, y: 54)]), c.shade.opacity(0.35), 0.8)
        stroke(&ctx, line([CGPoint(x: 76, y: 30), CGPoint(x: 43, y: 62)]), c.shade.opacity(0.35), 0.8)
    }

    // MARK: Small helpers

    private static func rotation(degrees: CGFloat, around center: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -center.x, y: -center.y)
    }

    /// A four-point star with gently concave sides.
    static func sparklePath(center: CGPoint, radius r: CGFloat) -> Path {
        let inner = r * 0.22
        var p = Path()
        p.move(to: CGPoint(x: center.x, y: center.y - r))
        p.addQuadCurve(
            to: CGPoint(x: center.x + r, y: center.y),
            control: CGPoint(x: center.x + inner, y: center.y - inner)
        )
        p.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y + r),
            control: CGPoint(x: center.x + inner, y: center.y + inner)
        )
        p.addQuadCurve(
            to: CGPoint(x: center.x - r, y: center.y),
            control: CGPoint(x: center.x - inner, y: center.y + inner)
        )
        p.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - r),
            control: CGPoint(x: center.x - inner, y: center.y - inner)
        )
        p.closeSubpath()
        return p
    }
}

private extension Path {
    /// Close an open polyline so it fills as a polygon.
    func closedIf() -> Path {
        var p = self
        p.closeSubpath()
        return p
    }
}
