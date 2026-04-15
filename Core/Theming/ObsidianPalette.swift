// CosmoOS/Core/Theming/ObsidianPalette.swift
// True dark theme — electric mint accent, developer cave aesthetic.
// "Deep focus cave with electric clarity"

import SwiftUI

struct ObsidianPalette: ThemePalette {

    // Surfaces
    let bg = Color(hex: "0D1117")
    let surface = Color(hex: "161B22")
    let surfaceElevated = Color(hex: "1C2128")
    let surfaceCard = Color(hex: "1C2128")
    let canvas = Color(hex: "010409")
    let surfaceHover = Color(hex: "242A32")

    // Text
    let text = Color(hex: "C9D1D9")
    let textSecondary = Color(hex: "8B949E")
    let textMuted = Color(hex: "6E7681")
    let textOnAccent = Color(hex: "0D1117")

    // Accent
    let accent = Color(hex: "58E6A0")
    let accentHover = Color(hex: "3DD68C")
    var accentGlow: Color { Color(hex: "58E6A0").opacity(0.15) }
    let accentSoft = Color(hex: "122D20")

    // Status
    let green = Color(hex: "58E6A0")
    var greenGlow: Color { Color(hex: "58E6A0").opacity(0.15) }
    let orange = Color(hex: "E8A840")
    let red = Color(hex: "F85149")
    let info = Color(hex: "58A6FF")
    let greenSoft = Color(hex: "122D20")
    let orangeSoft = Color(hex: "2D2418")
    let redSoft = Color(hex: "2D1418")
    let infoSoft = Color(hex: "12243D")

    // Akashic Codex — premium material system (true dark)
    let gilt = Color(hex: "58E6A0")
    let giltSoft = Color(hex: "122D20")
    let giltMuted = Color(hex: "2D6648")
    let vellum = Color(hex: "161B22")
    let vellumDeep = Color(hex: "0D1117")
    let inkWash = Color(hex: "C9D1D9")
    let inkFaded = Color(hex: "8B949E")
    let sepiaBorder = Color(hex: "30363D")
    let sepiaSubtle = Color(hex: "21262D")

    // Borders
    let border = Color(hex: "30363D")
    let borderSubtle = Color(hex: "21262D")
    let borderActive = Color(hex: "3D444D")
    var focusRing: Color { Color(hex: "58E6A0").opacity(0.40) }

    // Glass
    var glassCardFill: Color { Color(hex: "1C2128").opacity(0.85) }
    var glassInputFill: Color { Color(hex: "0D1117").opacity(0.90) }
    var glassInputFillFocused: Color { Color(hex: "0D1117").opacity(0.95) }
    var glassSectionFill: Color { Color(hex: "161B22").opacity(0.65) }
    var glassBorder: Color { Color.white.opacity(0.06) }
    var glassBorderFocused: Color { Color(hex: "58E6A0").opacity(0.40) }

    // Metadata
    let name = "Obsidian"
    let icon = "cube.fill"
    let isDark = true
}
