// CosmoOS/Core/Theming/ThemePalette.swift
// Protocol defining all swappable color tokens for themes.

import SwiftUI

/// Every theme must provide values for these tokens.
/// Typography, spacing, radii, and animations are constant across themes.
protocol ThemePalette {

    // MARK: - Surfaces

    var bg: Color { get }
    var surface: Color { get }
    var surfaceElevated: Color { get }
    var surfaceCard: Color { get }
    var canvas: Color { get }
    var surfaceHover: Color { get }

    // MARK: - Text

    var text: Color { get }
    var textSecondary: Color { get }
    var textMuted: Color { get }
    var textOnAccent: Color { get }

    // MARK: - Accent

    var accent: Color { get }
    var accentHover: Color { get }
    var accentGlow: Color { get }
    var accentSoft: Color { get }

    /// The accent at hero-surface chroma (large arcs, the day's primary CTA).
    /// MUST be a protocol requirement: extension-only members dispatch
    /// statically through `any ThemePalette`, so Greenhouse's vivid hex was
    /// shadowed by the `{ accent }` default and never rendered (iOS R2 jury
    /// find, July 2026 — same bug both repos).
    var accentVivid: Color { get }

    // MARK: - Status

    var green: Color { get }
    var greenGlow: Color { get }
    var orange: Color { get }
    var red: Color { get }
    var info: Color { get }
    var greenSoft: Color { get }
    var orangeSoft: Color { get }
    var redSoft: Color { get }
    var infoSoft: Color { get }

    // MARK: - Borders

    var border: Color { get }
    var borderSubtle: Color { get }
    var borderActive: Color { get }
    var focusRing: Color { get }

    // MARK: - Akashic Codex (premium material system)

    var gilt: Color { get }
    var giltSoft: Color { get }
    var giltMuted: Color { get }
    var vellum: Color { get }
    var vellumDeep: Color { get }
    var inkWash: Color { get }
    var inkFaded: Color { get }
    var sepiaBorder: Color { get }
    var sepiaSubtle: Color { get }

    // MARK: - Glass

    var glassCardFill: Color { get }
    var glassInputFill: Color { get }
    var glassInputFillFocused: Color { get }
    var glassSectionFill: Color { get }
    var glassBorder: Color { get }
    var glassBorderFocused: Color { get }

    // MARK: - Metadata

    var name: String { get }
    var icon: String { get }
    var isDark: Bool { get }
}

extension ThemePalette {
    /// The accent at hero-surface chroma (large arcs, the day's primary CTA).
    /// Themes whose accent already survives at stroke scale — including the
    /// mono palettes, whose accent IS ink — simply inherit `accent`.
    var accentVivid: Color { accent }
}
