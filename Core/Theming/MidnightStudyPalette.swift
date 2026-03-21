// CosmoOS/Core/Theming/MidnightStudyPalette.swift
// Dark warm theme — deep navy surfaces, warm amber accent.
// "Late-night deep work by lamplight"

import SwiftUI

struct MidnightStudyPalette: ThemePalette {

    // Surfaces
    let bg = Color(hex: "1A1B2E")
    let surface = Color(hex: "1F2037")
    let surfaceElevated = Color(hex: "232438")
    let surfaceCard = Color(hex: "262840")
    let canvas = Color(hex: "16172A")
    let surfaceHover = Color(hex: "2A2B46")

    // Text
    let text = Color(hex: "E8E4DC")
    let textSecondary = Color(hex: "9B978E")
    let textMuted = Color(hex: "6B6860")
    let textOnAccent = Color(hex: "1A1B2E")

    // Accent
    let accent = Color(hex: "D4A76A")
    let accentHover = Color(hex: "C4944E")
    var accentGlow: Color { Color(hex: "D4A76A").opacity(0.15) }
    let accentSoft = Color(hex: "2E2820")

    // Status
    let green = Color(hex: "5EC48A")
    var greenGlow: Color { Color(hex: "5EC48A").opacity(0.15) }
    let orange = Color(hex: "E8A840")
    let red = Color(hex: "E85C5C")
    let info = Color(hex: "6BA3E8")
    let greenSoft = Color(hex: "1E2E24")
    let orangeSoft = Color(hex: "2E2818")
    let redSoft = Color(hex: "2E1E1E")
    let infoSoft = Color(hex: "1E2430")

    // Borders
    let border = Color(hex: "2E2F42")
    let borderSubtle = Color(hex: "262838")
    let borderActive = Color(hex: "3A3C54")
    var focusRing: Color { Color(hex: "D4A76A").opacity(0.40) }

    // Glass
    var glassCardFill: Color { Color(hex: "232438").opacity(0.80) }
    var glassInputFill: Color { Color(hex: "1A1B2E").opacity(0.85) }
    var glassInputFillFocused: Color { Color(hex: "1A1B2E").opacity(0.95) }
    var glassSectionFill: Color { Color(hex: "1F2037").opacity(0.60) }
    var glassBorder: Color { Color.white.opacity(0.06) }
    var glassBorderFocused: Color { Color(hex: "D4A76A").opacity(0.40) }

    // Metadata
    let name = "Midnight Study"
    let icon = "lamp.desk.fill"
    let isDark = true
}
