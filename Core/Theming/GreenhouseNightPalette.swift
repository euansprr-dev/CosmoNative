// CosmoOS/Core/Theming/GreenhouseNightPalette.swift
// The greenhouse after dark: Black Mono's ink-slab structure, warmed and
// green-lit. Surfaces are near-black with a leaf-green undertone, ink is warm
// off-white, and the one living signal is a bright botanical green. Gilt goes
// warm for earned moments; chrome labels stay neutral green-grey.
// PAIRED with CosmoOS-iOS/CosmoiOS/Sources/Design/GreenhouseNightPalette.swift
// — values identical, keep in lockstep.
// "The glasshouse at night — moonlit leaves, warm lamplight on the bench."

import SwiftUI

struct GreenhouseNightPalette: ThemePalette {

    // Surfaces — near-black with a breath of green, stepping warmer as they rise.
    let bg = Color(hex: "0A0C0A")
    let surface = Color(hex: "0E110E")
    let surfaceElevated = Color(hex: "121612")
    let surfaceCard = Color(hex: "161B17")
    let canvas = Color(hex: "080A08")
    let surfaceHover = Color(hex: "1B211C")

    // Text — warm off-white ladder (green-grey, never blue-grey).
    let text = Color(hex: "F2F5F0")
    let textSecondary = Color(hex: "B3BCB2")
    let textMuted = Color(hex: "798077")
    let textOnAccent = Color(hex: "04150C")

    // Accent — living green, bright enough to read as light on the slab.
    let accent = Color(hex: "3DDC84")
    let accentHover = Color(hex: "5BE79A")
    var accentGlow: Color { Color(hex: "3DDC84").opacity(0.16) }
    let accentSoft = Color(hex: "0D2417")

    // Status and semantic signals
    let green = Color(hex: "3DDC84")
    var greenGlow: Color { Color(hex: "3DDC84").opacity(0.18) }
    let orange = Color(hex: "F59E0B")
    let red = Color(hex: "F87171")
    let info = Color(hex: "60A5FA")
    let greenSoft = Color(hex: "0D2417")
    let orangeSoft = Color(hex: "1F1503")
    let redSoft = Color(hex: "220A0A")
    let infoSoft = Color(hex: "0A1626")

    // Akashic Codex — warm gilt for earned moments; neutral labels.
    let gilt = Color(hex: "CBB37E")
    let giltSoft = Color(hex: "191711")
    let giltMuted = Color(hex: "8B9489")
    let vellum = Color(hex: "F8F5EE")
    let vellumDeep = Color(hex: "F1EBDF")
    let inkWash = Color(hex: "1E1D19")
    let inkFaded = Color(hex: "6E6C60")
    let sepiaBorder = Color(hex: "23291F")
    let sepiaSubtle = Color(hex: "171C15")

    // Borders — green-tinted hairlines.
    let border = Color(hex: "242B22")
    let borderSubtle = Color(hex: "171C15")
    let borderActive = Color(hex: "3A453A")
    var focusRing: Color { Color(hex: "3DDC84").opacity(0.42) }

    // Glass
    var glassCardFill: Color { Color(hex: "121612").opacity(0.940) }
    var glassInputFill: Color { Color(hex: "0A0C0A").opacity(0.960) }
    var glassInputFillFocused: Color { Color(hex: "0A0C0A").opacity(0.985) }
    var glassSectionFill: Color { Color(hex: "161B17").opacity(0.840) }
    var glassBorder: Color { Color.white.opacity(0.10) }
    var glassBorderFocused: Color { Color(hex: "3DDC84").opacity(0.40) }

    // Metadata
    let name = "Greenhouse Night"
    let icon = "leaf.fill"
    let isDark = true
}
