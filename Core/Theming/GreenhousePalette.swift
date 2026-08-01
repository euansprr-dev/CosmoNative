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

    // Text — ONE warm ink family, three rungs, monotone in value (Bear/Apple
    // law: a secondary grey is the primary ink stepped down, never a separate
    // hue). The old cool-violet trio (#1A1A1F/#6B6B78/#767685) sat on warm
    // parchment and cancelled it; these share the parchment's own temperature
    // and every rung clears WCAG AA on #F8F7F4 (13.4 / 8.1 / 4.6 : 1).
    // Rung 2 re-welded #5A574D → #4E4B42 (typography-jury follow-up): the
    // ladder's joints are now near-even (16.0 / 14.5 L*), so a one-rung step
    // — the meta line's subject vs its supporting cast — is actually visible
    // at 11pt, and rung 3 keeps AA headroom on vellum surfaces.
    let text = Color(hex: "2C2A26")
    let textSecondary = Color(hex: "4E4B42")
    let textMuted = Color(hex: "757165")
    let textOnAccent = Color.white

    // Accent
    let accent = Color(hex: "2D6A4F")
    let accentHover = Color(hex: "245943")
    var accentGlow: Color { Color(hex: "2D6A4F").opacity(0.10) }
    /// Forest with enough chroma to read as green at a 9pt stroke — #2D6A4F
    /// is correct for text/selection but crushes toward ink on hero surfaces.
    var accentVivid: Color { Color(hex: "2F8F5C") }
    let accentSoft = Color(hex: "E8F5EC")

    // Status
    let green = Color(hex: "38B764")
    var greenGlow: Color { Color(hex: "38B764").opacity(0.12) }
    let orange = Color(hex: "D97706")
    // Warm-retuned alarm (was Bootstrap #DC3545 — a foreign brand red on
    // parchment; same lightness, hue rotated toward the page's own family).
    let red = Color(hex: "C0503F")
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
    // Collapsed onto textMuted's rung: the document ink family and the UI ink
    // family are now the SAME ladder — a warm due chip can no longer sit 6pt
    // from a cool meta line at the same rank.
    let inkFaded = Color(hex: "757165")
    let sepiaBorder = Color(hex: "DDD5C8")
    let sepiaSubtle = Color(hex: "E8E1D6")

    // Borders — warm siblings of the ink ladder (the cool UI-kit greys were
    // the last foreign family: a sepia hour rule ran behind a cool card
    // border in the same column).
    let border = Color(hex: "DED8CD")
    let borderSubtle = Color(hex: "E8E1D6")
    let borderActive = Color(hex: "C9C3B6")
    var focusRing: Color { Color(hex: "2D6A4F").opacity(0.40) }

    // Glass — the hover/card layer joins the warm family: a pure-black
    // hairline + pure-white fill meant every ledger-row hover briefly
    // DESATURATED the parchment (the last achromatic tokens on the page).
    // The fill's white is nudged into the paper's own temperature; the
    // border is the ink at a whisper (ink is lighter than black, so 0.10
    // carries the old 0.08's weight).
    var glassCardFill: Color { Color(hex: "FDFBF7").opacity(0.70) }
    var glassInputFill: Color { Color.white.opacity(0.80) }
    var glassInputFillFocused: Color { Color.white.opacity(0.90) }
    var glassSectionFill: Color { Color.white.opacity(0.50) }
    var glassBorder: Color { Color(hex: "2C2A26").opacity(0.10) }
    var glassBorderFocused: Color { Color(hex: "2D6A4F").opacity(0.40) }

    // Metadata
    let name = "Greenhouse"
    let icon = "leaf.fill"
    let isDark = false
}
