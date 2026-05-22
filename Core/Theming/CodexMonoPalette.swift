// CosmoOS/Core/Theming/CodexMonoPalette.swift
// Codex-inspired light theme: white workspace, neutral chrome, charcoal accent.

import SwiftUI

struct CodexMonoPalette: ThemePalette {

    // Surfaces
    let bg = Color(hex: "FDFDFC")
    let surface = Color(hex: "F7F7F8")
    let surfaceElevated = Color(hex: "FFFFFF")
    let surfaceCard = Color(hex: "FFFFFF")
    let canvas = Color(hex: "FAFAFB")
    let surfaceHover = Color(hex: "F1F1F2")

    // Text
    let text = Color(hex: "1F2024")
    let textSecondary = Color(hex: "5F6068")
    let textMuted = Color(hex: "8B8D94")
    let textOnAccent = Color.white

    // Accent
    let accent = Color(hex: "1F2024")
    let accentHover = Color(hex: "000000")
    var accentGlow: Color { Color.black.opacity(0.08) }
    let accentSoft = Color(hex: "F5F5F6")

    // Status and semantic signals
    let green = Color(hex: "2F7D5B")
    var greenGlow: Color { Color(hex: "2F7D5B").opacity(0.12) }
    let orange = Color(hex: "F26A3D")
    let red = Color(hex: "D92D20")
    let info = Color(hex: "2563EB")
    let greenSoft = Color(hex: "EAF6EF")
    let orangeSoft = Color(hex: "FFF1EA")
    let redSoft = Color(hex: "FDEDEC")
    let infoSoft = Color(hex: "EAF1FF")

    // Akashic Codex - neutralized for monochrome chrome
    let gilt = Color(hex: "6F7178")
    let giltSoft = Color(hex: "F6F6F7")
    let giltMuted = Color(hex: "A3A4AA")
    let vellum = Color(hex: "FBFBFC")
    let vellumDeep = Color(hex: "F4F4F5")
    let inkWash = Color(hex: "1F2024")
    let inkFaded = Color(hex: "6D6E76")
    let sepiaBorder = Color(hex: "E5E5E7")
    let sepiaSubtle = Color(hex: "F1F1F2")

    // Borders
    let border = Color(hex: "E2E2E4")
    let borderSubtle = Color(hex: "F0F0F2")
    let borderActive = Color(hex: "C7C7CB")
    var focusRing: Color { Color.black.opacity(0.28) }

    // Glass
    var glassCardFill: Color { Color.white.opacity(0.950) }
    var glassInputFill: Color { Color.white.opacity(0.970) }
    var glassInputFillFocused: Color { Color.white.opacity(0.996) }
    var glassSectionFill: Color { Color.white.opacity(0.860) }
    var glassBorder: Color { Color.black.opacity(0.05) }
    var glassBorderFocused: Color { Color.black.opacity(0.20) }

    // Metadata
    let name = "Codex Mono"
    let icon = "circle.lefthalf.filled"
    let isDark = false
}
