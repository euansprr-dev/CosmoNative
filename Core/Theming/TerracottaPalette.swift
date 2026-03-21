// CosmoOS/Core/Theming/TerracottaPalette.swift
// Warm earthy theme — burnt sienna accent, Mediterranean warmth.
// "Mediterranean creative studio at golden hour"

import SwiftUI

struct TerracottaPalette: ThemePalette {

    // Surfaces
    let bg = Color(hex: "FBF5F0")
    let surface = Color(hex: "F5EDE5")
    let surfaceElevated = Color(hex: "FFFBF7")
    let surfaceCard = Color(hex: "FFFBF7")
    let canvas = Color(hex: "F2E8DE")
    let surfaceHover = Color(hex: "EDE3D8")

    // Text
    let text = Color(hex: "3D2C2C")
    let textSecondary = Color(hex: "7A6858")
    let textMuted = Color(hex: "A09080")
    let textOnAccent = Color.white

    // Accent
    let accent = Color(hex: "C7623F")
    let accentHover = Color(hex: "B55432")
    var accentGlow: Color { Color(hex: "C7623F").opacity(0.12) }
    let accentSoft = Color(hex: "F5E0D5")

    // Status
    let green = Color(hex: "5E9E6E")
    var greenGlow: Color { Color(hex: "5E9E6E").opacity(0.12) }
    let orange = Color(hex: "D4883A")
    let red = Color(hex: "C94D4D")
    let info = Color(hex: "5A8AB5")
    let greenSoft = Color(hex: "E5F0E8")
    let orangeSoft = Color(hex: "F5EADB")
    let redSoft = Color(hex: "F5E0E0")
    let infoSoft = Color(hex: "E0EBF5")

    // Borders
    let border = Color(hex: "E0D5C8")
    let borderSubtle = Color(hex: "EAE0D5")
    let borderActive = Color(hex: "D0C0B0")
    var focusRing: Color { Color(hex: "C7623F").opacity(0.40) }

    // Glass
    var glassCardFill: Color { Color(hex: "FFFBF7").opacity(0.75) }
    var glassInputFill: Color { Color(hex: "FFFBF7").opacity(0.85) }
    var glassInputFillFocused: Color { Color(hex: "FFFBF7").opacity(0.95) }
    var glassSectionFill: Color { Color(hex: "F5EDE5").opacity(0.55) }
    var glassBorder: Color { Color(hex: "3D2C2C").opacity(0.08) }
    var glassBorderFocused: Color { Color(hex: "C7623F").opacity(0.40) }

    // Metadata
    let name = "Terracotta"
    let icon = "sun.dust.fill"
    let isDark = false
}
