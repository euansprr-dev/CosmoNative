// CosmoOS/Core/Theming/GreenhousePalette.swift
// Default theme — warm parchment surfaces, forest green accent.
// "Morning coffee in a sunlit studio"

import SwiftUI

struct GreenhousePalette: ThemePalette {

    // Surfaces
    let bg = Color(hex: "F8F7F4")
    let surface = Color(hex: "F5F4F0")
    let surfaceElevated = Color(hex: "FFFFFF")
    let surfaceCard = Color(hex: "FFFFFF")
    let canvas = Color(hex: "F2F1ED")
    let surfaceHover = Color(hex: "F0EFEB")

    // Text
    let text = Color(hex: "1A1A1F")
    let textSecondary = Color(hex: "6B6B78")
    let textMuted = Color(hex: "767685")
    let textOnAccent = Color.white

    // Accent
    let accent = Color(hex: "2D6A4F")
    let accentHover = Color(hex: "245943")
    var accentGlow: Color { Color(hex: "2D6A4F").opacity(0.10) }
    let accentSoft = Color(hex: "E8F5EC")

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

    // Akashic Codex — premium material system
    let gilt = Color(hex: "A08540")
    let giltSoft = Color(hex: "F5EDD8")
    let giltMuted = Color(hex: "8A8578")
    let vellum = Color(hex: "F3EDE4")
    let vellumDeep = Color(hex: "EDE5D8")
    let inkWash = Color(hex: "2C2A26")
    let inkFaded = Color(hex: "7A7568")
    let sepiaBorder = Color(hex: "DDD5C8")
    let sepiaSubtle = Color(hex: "E8E1D6")

    // Borders
    let border = Color(hex: "DCDCE0")
    let borderSubtle = Color(hex: "E8E8EC")
    let borderActive = Color(hex: "C8C8CC")
    var focusRing: Color { Color(hex: "2D6A4F").opacity(0.40) }

    // Glass
    var glassCardFill: Color { Color.white.opacity(0.70) }
    var glassInputFill: Color { Color.white.opacity(0.80) }
    var glassInputFillFocused: Color { Color.white.opacity(0.90) }
    var glassSectionFill: Color { Color.white.opacity(0.50) }
    var glassBorder: Color { Color.black.opacity(0.08) }
    var glassBorderFocused: Color { Color(hex: "2D6A4F").opacity(0.40) }

    // Metadata
    let name = "Greenhouse"
    let icon = "leaf.fill"
    let isDark = false
}
