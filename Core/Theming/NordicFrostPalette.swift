// CosmoOS/Core/Theming/NordicFrostPalette.swift
// Cool minimal theme — steel blue accent, Scandinavian clarity.
// "Scandinavian clarity on a winter morning"

import SwiftUI

struct NordicFrostPalette: ThemePalette {

    // Surfaces
    let bg = Color(hex: "F0F2F5")
    let surface = Color(hex: "E8EBF0")
    let surfaceElevated = Color(hex: "FFFFFF")
    let surfaceCard = Color(hex: "FFFFFF")
    let canvas = Color(hex: "E4E7EC")
    let surfaceHover = Color(hex: "E0E3E8")

    // Text
    let text = Color(hex: "2C3E50")
    let textSecondary = Color(hex: "64748B")
    let textMuted = Color(hex: "94A3B8")
    let textOnAccent = Color.white

    // Accent
    let accent = Color(hex: "4A7B9D")
    let accentHover = Color(hex: "3A6888")
    var accentGlow: Color { Color(hex: "4A7B9D").opacity(0.12) }
    let accentSoft = Color(hex: "E0EDF5")

    // Status
    let green = Color(hex: "38B764")
    var greenGlow: Color { Color(hex: "38B764").opacity(0.12) }
    let orange = Color(hex: "D97706")
    let red = Color(hex: "DC3545")
    let info = Color(hex: "3B82F6")
    let greenSoft = Color(hex: "DCFCE7")
    let orangeSoft = Color(hex: "FEF3C7")
    let redSoft = Color(hex: "FEE2E2")
    let infoSoft = Color(hex: "DBEAFE")

    // Borders
    let border = Color(hex: "D1D5DB")
    let borderSubtle = Color(hex: "E2E5EA")
    let borderActive = Color(hex: "B8BCC4")
    var focusRing: Color { Color(hex: "4A7B9D").opacity(0.40) }

    // Glass
    var glassCardFill: Color { Color.white.opacity(0.75) }
    var glassInputFill: Color { Color.white.opacity(0.85) }
    var glassInputFillFocused: Color { Color.white.opacity(0.95) }
    var glassSectionFill: Color { Color.white.opacity(0.55) }
    var glassBorder: Color { Color.black.opacity(0.06) }
    var glassBorderFocused: Color { Color(hex: "4A7B9D").opacity(0.40) }

    // Metadata
    let name = "Nordic Frost"
    let icon = "snowflake"
    let isDark = false
}
