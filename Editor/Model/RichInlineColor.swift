// TWIN FILE — byte-identical in CosmoOS-Swift/Editor/Model and
// CosmoOS-iOS/CosmoCoreKit/Sources/Models. Verified by Tools/verify_twins.sh.
//
// Colour discipline for inline ink, highlights, and cell tones: documents
// store NoteInkPalette tone IDs, never hex. Imports (Google Docs, HTML) map
// arbitrary colours to the nearest tone by hue in OKLCH, and drop colours
// that are really "default text" (near-black, grey) or "no highlight"
// (white, near-white).

import Foundation

public enum RichInlineColor {
    /// Mirror of NoteInkPalette's light-mode inks, kept here so the pure
    /// matcher has no UI dependency. A test on each platform asserts this
    /// table equals NoteInkPalette.
    public static let toneInks: [(id: String, hex: String)] = [
        ("moss", "4A7C59"),
        ("clay", "B0674A"),
        ("gilt", "A9853B"),
        ("slate", "5B7288"),
        ("plum", "7D5B88"),
        ("rose", "A85C6E"),
    ]

    public static let toneIDs: [String] = toneInks.map(\.id)

    public static func isKnownTone(_ id: String?) -> Bool {
        guard let id else { return false }
        return toneIDs.contains(id)
    }

    public struct RGB: Equatable, Sendable {
        public var r: Double
        public var g: Double
        public var b: Double
        public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    }

    public struct LCH: Equatable, Sendable {
        public var l: Double   // 0…1
        public var c: Double   // ~0…0.4
        public var h: Double   // degrees 0…360
    }

    /// Parses `#rgb`, `#rrggbb`, `rgb(r, g, b)`, `rgba(r, g, b, a)` and a few
    /// CSS names. Returns nil for `transparent`, `inherit`, and garbage.
    public static func parse(_ raw: String) -> RGB? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty || value == "transparent" || value == "inherit" || value == "initial" || value == "currentcolor" {
            return nil
        }
        if value.hasPrefix("#") {
            let hex = String(value.dropFirst())
            return parseHex(hex)
        }
        if value.hasPrefix("rgb") {
            let inner = value.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
            let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            func channel(_ part: String) -> Double? {
                if part.hasSuffix("%") { return Double(part.dropLast()).map { $0 / 100 } }
                return Double(part).map { $0 / 255 }
            }
            guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
            if parts.count >= 4, let alpha = Double(parts[3]), alpha <= 0.02 { return nil }
            return RGB(r: r, g: g, b: b)
        }
        if let named = namedColors[value] { return parseHex(named) }
        return parseHex(value)
    }

    public static func parseHex(_ hex: String) -> RGB? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        if digits.count == 8 { digits = String(digits.prefix(6)) }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return RGB(
            r: Double((value >> 16) & 0xFF) / 255,
            g: Double((value >> 8) & 0xFF) / 255,
            b: Double(value & 0xFF) / 255
        )
    }

    private static let namedColors: [String: String] = [
        "black": "000000", "white": "ffffff", "red": "ff0000", "green": "008000", "blue": "0000ff",
        "yellow": "ffff00", "orange": "ffa500", "purple": "800080", "pink": "ffc0cb", "gray": "808080",
        "grey": "808080", "brown": "a52a2a", "teal": "008080", "navy": "000080", "maroon": "800000",
        "olive": "808000", "lime": "00ff00", "aqua": "00ffff", "cyan": "00ffff", "magenta": "ff00ff",
        "silver": "c0c0c0", "gold": "ffd700", "beige": "f5f5dc", "ivory": "fffff0", "coral": "ff7f50",
    ]

    // MARK: OKLCH

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    public static func lch(_ rgb: RGB) -> LCH {
        let r = linear(min(max(rgb.r, 0), 1))
        let g = linear(min(max(rgb.g, 0), 1))
        let b = linear(min(max(rgb.b, 0), 1))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let okL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let okA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let okB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let chroma = sqrt(okA * okA + okB * okB)
        var hue = atan2(okB, okA) * 180 / .pi
        if hue < 0 { hue += 360 }
        return LCH(l: okL, c: chroma, h: hue)
    }

    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    private static let toneLCH: [(id: String, lch: LCH)] = toneInks.compactMap { tone in
        parseHex(tone.hex).map { (tone.id, lch($0)) }
    }

    /// The nearest tone for TEXT colour. Nil when the colour reads as
    /// default ink: near-black, dark grey, or too desaturated to be a
    /// deliberate colour.
    public static func nearestInkTone(for raw: String) -> String? {
        guard let rgb = parse(raw) else { return nil }
        let color = lch(rgb)
        if color.l < 0.30 { return nil }
        if color.c < 0.03 { return nil }
        return nearestTone(to: color)
    }

    /// The nearest tone for a HIGHLIGHT / cell background. Nil for white,
    /// near-white, transparent, and greys.
    public static func nearestHighlightTone(for raw: String) -> String? {
        guard let rgb = parse(raw) else { return nil }
        let color = lch(rgb)
        if color.l > 0.97 { return nil }
        if color.c < 0.02 { return nil }
        return nearestTone(to: color)
    }

    private static func nearestTone(to color: LCH) -> String? {
        var best: (id: String, score: Double)?
        for tone in toneLCH {
            // Hue dominates; a little lightness keeps clay vs rose honest.
            let score = hueDistance(color.h, tone.lch.h) + abs(color.l - tone.lch.l) * 40
            if best == nil || score < best!.score { best = (tone.id, score) }
        }
        return best?.id
    }
}
