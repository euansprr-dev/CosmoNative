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
