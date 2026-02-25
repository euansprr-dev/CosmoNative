// CosmoOS/Core/DesignSystem.swift
// Unified Design System — Sanctuary-Level Visual Coherence
// Every screen MUST use these tokens. No inline color/font definitions.
// February 2026

import SwiftUI

// MARK: - Design System (Sanctuary Tokens)

/// Single source of truth for all visual tokens in CosmoOS.
/// Extracted from the Sanctuary hub — every screen must match.
enum DS {

    // ═══════════════════════════════════════════════════════════════
    // COLORS — Sanctuary Dark Theme
    // ═══════════════════════════════════════════════════════════════

    /// Page background — match Sanctuary's exact background
    static let bg = Color(hex: "0A0A0F")

    /// Sidebar, panels, rails
    static let surface = Color(hex: "111118")

    /// Cards, editor areas, modals
    static let surfaceElevated = Color(hex: "16161F")

    /// Thinkspace canvas cards, library cards
    static let surfaceCard = Color(hex: "1A1A24")

    /// Standard borders everywhere
    static let border = Color.white.opacity(0.06)

    /// Section dividers, faint separations
    static let borderSubtle = Color.white.opacity(0.04)

    /// Focus states, active inputs
    static let borderActive = Color.white.opacity(0.12)

    /// Primary text, headings, editor content
    static let text = Color(hex: "E8E8ED")

    /// Descriptions, subtitles, helper text
    static let textSecondary = Color(hex: "8888A0")

    /// Placeholders, disabled, metadata timestamps
    static let textMuted = Color(hex: "555566")

    /// Sanctuary purple — active phases, primary buttons
    static let accent = Color(hex: "7C6AFF")

    /// Glow shadows behind accent elements
    static let accentGlow = Color(hex: "7C6AFF").opacity(0.15)

    /// Subtle button backgrounds, hover states
    static let accentSoft = Color(hex: "7C6AFF").opacity(0.08)

    /// Plannerum green, completed states, Sanctuary green orbs
    static let green = Color(hex: "38B764")

    /// Glow behind green elements
    static let greenGlow = Color(hex: "38B764").opacity(0.12)

    /// Warning, in-progress states
    static let orange = Color(hex: "E8A838")

    /// Errors, high priority
    static let red = Color(hex: "E85454")

    // ═══════════════════════════════════════════════════════════════
    // TYPOGRAPHY — System font (SF Pro) everywhere
    // ═══════════════════════════════════════════════════════════════

    /// Page title — 28–32px, weight 600, text color, -0.01em tracking
    static let pageTitle = Font.system(size: 28, weight: .semibold)

    /// Section label (UPPERCASE) — 11px, weight 600, textMuted, 0.08em tracking
    static let sectionLabel = Font.system(size: 11, weight: .semibold)

    /// Section description — 13px, weight 400, textSecondary
    static let sectionDesc = Font.system(size: 13, weight: .regular)

    /// Body / editor text — 15px, weight 400, text color, line-height 1.7
    static let body = Font.system(size: 15, weight: .regular)

    /// Card title — 15–16px, weight 500, text color
    static let cardTitle = Font.system(size: 15, weight: .medium)

    /// Card metadata — 12px, weight 400, textSecondary
    static let cardMeta = Font.system(size: 12, weight: .regular)

    /// Button text — 12–13px, weight 500, accent or white, 0.01em tracking
    static let buttonText = Font.system(size: 12, weight: .medium)

    /// Timestamp / counts — 11px, weight 400, textMuted
    static let timestamp = Font.system(size: 11, weight: .regular)

    /// Nav bar title — 14px, weight 500, text color
    static let navTitle = Font.system(size: 14, weight: .medium)

    /// Nav bar badge — 10px, weight 500, textSecondary, 0.02em tracking
    static let navBadge = Font.system(size: 10, weight: .medium)

    // ═══════════════════════════════════════════════════════════════
    // RADII — Only 3 values exist
    // ═══════════════════════════════════════════════════════════════

    /// Buttons, inputs
    static let radiusSmall: CGFloat = 8

    /// Cards
    static let radiusMedium: CGFloat = 12

    /// Modals, overlays
    static let radiusLarge: CGFloat = 16

    // ═══════════════════════════════════════════════════════════════
    // SPACING — Consistent throughout
    // ═══════════════════════════════════════════════════════════════

    /// Spacing between sections
    static let sectionSpacing: CGFloat = 36

    /// Padding inside cards
    static let cardPadding: CGFloat = 18

    /// Page margins
    static let pageMargin: CGFloat = 40
}

// MARK: - Reusable View Modifiers

extension View {

    /// Standard section label style — 11px UPPERCASE textMuted with 0.08em tracking
    func dsSectionLabel() -> some View {
        self
            .font(DS.sectionLabel)
            .foregroundColor(DS.textMuted)
            .tracking(0.88) // 0.08em at 11px
            .textCase(.uppercase)
    }

    /// Standard card chrome — surfaceElevated bg, 1px border, 12px radius
    func dsCard() -> some View {
        self
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.border, lineWidth: 1)
            )
    }

    /// Editor card — surfaceElevated bg, 12px radius, accent left bar
    func dsEditorCard() -> some View {
        self
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.border, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.accent.opacity(0.5))
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 1)
            }
    }

    /// Primary action button — accent solid bg, white text, 8px radius, accentGlow shadow
    func dsPrimaryButton() -> some View {
        self
            .font(DS.buttonText)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(DS.accent)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
            .shadow(color: DS.accentGlow, radius: 8)
    }

    /// Ghost button — transparent bg, 1px border, textSecondary
    func dsGhostButton() -> some View {
        self
            .font(DS.buttonText)
            .foregroundColor(DS.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.border, lineWidth: 1)
            )
    }

    /// Soft accent button — accentSoft bg, accent text, 8px radius
    func dsAccentSoftButton() -> some View {
        self
            .font(DS.buttonText)
            .foregroundColor(DS.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(DS.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.accent.opacity(0.2), lineWidth: 1)
            )
    }

    /// Modal overlay — surfaceElevated bg, borderActive, 16px radius, shadow
    func dsModal() -> some View {
        self
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusLarge)
                    .stroke(DS.borderActive, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 32, y: 8)
    }
}
