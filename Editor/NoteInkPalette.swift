import SwiftUI

/// The shared ink-tone vocabulary for tinted document blocks — callouts,
/// element seats, and (later) page accents. Six muted, parchment-compatible
/// tones in the Greenhouse family, each with a light and an immersive/dark
/// variant. Tones are addressed by stable string IDs so they persist in
/// document JSON and stay portable across platforms.
struct NoteInkTone: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    private let lightHex: String
    private let darkHex: String

    init(id: String, label: String, lightHex: String, darkHex: String) {
        self.id = id
        self.label = label
        self.lightHex = lightHex
        self.darkHex = darkHex
    }

    /// The strong tone — icons, chevrons, and small accents.
    func ink(darkMode: Bool) -> Color {
        Color(hex: darkMode ? darkHex : lightHex)
    }

    /// The soft fill behind tinted blocks. Opacity is part of the token so
    /// every wash in the app reads at the same strength.
    func wash(darkMode: Bool) -> Color {
        ink(darkMode: darkMode).opacity(darkMode ? 0.16 : 0.09)
    }

    /// The hairline for tinted containers.
    func hairline(darkMode: Bool) -> Color {
        ink(darkMode: darkMode).opacity(darkMode ? 0.34 : 0.22)
    }
}

enum NoteInkPalette {
    static let defaultToneID = "moss"

    static let tones: [NoteInkTone] = [
        NoteInkTone(id: "moss", label: "Moss", lightHex: "4A7C59", darkHex: "7FB08A"),
        NoteInkTone(id: "clay", label: "Clay", lightHex: "B0674A", darkHex: "C98A6E"),
        NoteInkTone(id: "gilt", label: "Gilt", lightHex: "A9853B", darkHex: "C7A65A"),
        NoteInkTone(id: "slate", label: "Slate", lightHex: "5B7288", darkHex: "8AA2B8"),
        NoteInkTone(id: "plum", label: "Plum", lightHex: "7D5B88", darkHex: "A78BB0"),
        NoteInkTone(id: "rose", label: "Rose", lightHex: "A85C6E", darkHex: "C88A99")
    ]

    /// Lenient lookup — unknown or missing IDs resolve to the default tone so
    /// documents written by newer builds never fail to render.
    static func tone(_ id: String?) -> NoteInkTone {
        tones.first { $0.id == id } ?? tones[0]
    }
}
