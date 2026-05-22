// CosmoOS/Core/Theming/BlackMonoPalette.swift
// Inverted mono theme: black workspace chrome, white UI signal, light paper.

import SwiftUI

struct BlackMonoPalette: ThemePalette {

    // Surfaces
    let bg = Color(hex: "000000")
    let surface = Color(hex: "050505")
    let surfaceElevated = Color(hex: "0B0B0D")
    let surfaceCard = Color(hex: "101012")
    let canvas = Color(hex: "000000")
    let surfaceHover = Color(hex: "171717")

    // Text
    let text = Color(hex: "F5F5F7")
    let textSecondary = Color(hex: "B7B7C0")
    let textMuted = Color(hex: "7C7D86")
    let textOnAccent = Color(hex: "000000")

    // Accent
    let accent = Color(hex: "F5F5F7")
    let accentHover = Color(hex: "FFFFFF")
    var accentGlow: Color { Color.white.opacity(0.16) }
    let accentSoft = Color(hex: "17171A")

    // Status and semantic signals
    let green = Color(hex: "3DDC84")
    var greenGlow: Color { Color(hex: "3DDC84").opacity(0.18) }
    let orange = Color(hex: "F59E0B")
    let red = Color(hex: "F87171")
    let info = Color(hex: "60A5FA")
    let greenSoft = Color(hex: "06170D")
    let orangeSoft = Color(hex: "1A1000")
    let redSoft = Color(hex: "1A0505")
    let infoSoft = Color(hex: "06111F")

    // Akashic Codex - paper stays readable while chrome inverts.
    let gilt = Color(hex: "D9D9DF")
    let giltSoft = Color(hex: "151517")
    let giltMuted = Color(hex: "8F9098")
    let vellum = Color(hex: "FFFFFF")
    let vellumDeep = Color(hex: "F8F7F4")
    let inkWash = Color(hex: "1A1A1F")
    let inkFaded = Color(hex: "6B6B78")
    let sepiaBorder = Color(hex: "E8E8EC")
    let sepiaSubtle = Color(hex: "F5F4F0")

    // Borders
    let border = Color(hex: "303034")
    let borderSubtle = Color(hex: "202024")
    let borderActive = Color(hex: "F5F5F7")
    var focusRing: Color { Color.white.opacity(0.42) }

    // Glass
    var glassCardFill: Color { Color(hex: "0B0B0D").opacity(0.940) }
    var glassInputFill: Color { Color(hex: "000000").opacity(0.960) }
    var glassInputFillFocused: Color { Color(hex: "000000").opacity(0.985) }
    var glassSectionFill: Color { Color(hex: "101012").opacity(0.840) }
    var glassBorder: Color { Color.white.opacity(0.120) }
    var glassBorderFocused: Color { Color.white.opacity(0.32) }

    // Metadata
    let name = "Black Mono"
    let icon = "circle.fill"
    let isDark = true
}
