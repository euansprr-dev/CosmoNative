// CosmoOS/Core/DesignSystem.swift
// Unified Design System — Greenhouse Light Mode
// Every screen MUST use these tokens. No inline color/font definitions.
// March 2026 — Full light-mode rebrand

import SwiftUI

// MARK: - Design System (Greenhouse Tokens)

/// Single source of truth for all visual tokens in CosmoOS.
/// Greenhouse: warm parchment surfaces, forest green accent, quiet depth via shadows.
enum DS {

    // ═══════════════════════════════════════════════════════════════
    // SURFACES — Warm parchment base, white elevation
    // ═══════════════════════════════════════════════════════════════

    /// Page background — warm parchment
    static let bg = Color(hex: "F8F7F4")

    /// Sidebar, panels, secondary surfaces
    static let surface = Color(hex: "F5F4F0")

    /// Cards, editor areas, modals — clean white
    static let surfaceElevated = Color(hex: "FFFFFF")

    /// Thinkspace canvas cards, library cards — clean white
    static let surfaceCard = Color(hex: "FFFFFF")

    /// Canvas background — slightly warmer than bg
    static let canvas = Color(hex: "F2F1ED")

    /// Hover state tint for interactive surfaces
    static let surfaceHover = Color(hex: "F0EFEB")

    // ═══════════════════════════════════════════════════════════════
    // TEXT — Dark on light, WCAG AA compliant
    // ═══════════════════════════════════════════════════════════════

    /// Primary text, headings, editor content — near-black
    static let text = Color(hex: "1A1A1F")

    /// Descriptions, subtitles, helper text
    static let textSecondary = Color(hex: "6B6B78")

    /// Placeholders, disabled, metadata timestamps (WCAG AA 4.5:1 on white)
    static let textMuted = Color(hex: "767685")

    /// Text on accent-colored backgrounds (green buttons, accent pills)
    static let textOnAccent = Color.white

    // ═══════════════════════════════════════════════════════════════
    // ACCENT — Forest green, organic and alive
    // ═══════════════════════════════════════════════════════════════

    /// Primary accent — forest green
    static let accent = Color(hex: "2D6A4F")

    /// Accent hover/pressed state — darker green
    static let accentHover = Color(hex: "245943")

    /// Subtle accent glow for shadows
    static let accentGlow = Color(hex: "2D6A4F").opacity(0.10)

    /// Soft accent background for pills, tags, tinted areas
    static let accentSoft = Color(hex: "E8F5EC")

    // ═══════════════════════════════════════════════════════════════
    // STATUS — Clear, accessible status colors
    // ═══════════════════════════════════════════════════════════════

    /// Success, completed states
    static let green = Color(hex: "38B764")

    /// Glow behind green elements
    static let greenGlow = Color(hex: "38B764").opacity(0.12)

    /// Warning, in-progress states
    static let orange = Color(hex: "D97706")

    /// Errors, high priority
    static let red = Color(hex: "DC3545")

    /// Info, links
    static let info = Color(hex: "3B82F6")

    /// Soft status backgrounds
    static let greenSoft = Color(hex: "DCFCE7")
    static let orangeSoft = Color(hex: "FEF3C7")
    static let redSoft = Color(hex: "FEE2E2")
    static let infoSoft = Color(hex: "DBEAFE")

    // ═══════════════════════════════════════════════════════════════
    // BORDERS — Neutral gray, not warm or cold
    // ═══════════════════════════════════════════════════════════════

    /// Standard borders everywhere
    static let border = Color(hex: "DCDCE0")

    /// Section dividers, faint separations
    static let borderSubtle = Color(hex: "E8E8EC")

    /// Focus states, active inputs
    static let borderActive = Color(hex: "C8C8CC")

    /// Focus ring for keyboard navigation
    static let focusRing = Color(hex: "2D6A4F").opacity(0.40)

    // ═══════════════════════════════════════════════════════════════
    // ENTITY COLORS — Bespoke muted palette for light backgrounds
    // ═══════════════════════════════════════════════════════════════

    /// Ideas — muted indigo
    static let entityIdea = Color(hex: "6B6EA8")

    /// Research — forest teal
    static let entityResearch = Color(hex: "4A8B72")

    /// Content — slate blue
    static let entityContent = Color(hex: "5B84B0")

    /// Notes — warm umber
    static let entityNote = Color(hex: "9B8A6E")

    /// Connections — soft purple
    static let entityConnection = Color(hex: "8B6BAB")

    /// Swipe files — warm bronze
    static let entitySwipe = Color(hex: "B08C5A")

    /// Tasks — dusty rose
    static let entityTask = Color(hex: "B06B6B")

    /// Readwise Library — warm cognac (bookish, leather-bound)
    static let entityReadwise = Color(hex: "A0785A")
    static let entityReadwiseSoft = Color(hex: "F2EBE0")

    /// Images — muted teal
    static let entityImage = Color(hex: "5A9BA0")

    // ═══════════════════════════════════════════════════════════════
    // CLIENT COLORS — Deterministic palette for content profiles
    // ═══════════════════════════════════════════════════════════════

    /// 8-color palette for client profile identity. Assigned deterministically
    /// by stable hash of client UUID, so colors are consistent across views.
    static let clientPalette: [Color] = [
        Color(hex: "2E86AB"),  // Cerulean
        Color(hex: "A23B72"),  // Berry
        Color(hex: "C18C5D"),  // Warm tan
        Color(hex: "5E8C61"),  // Sage green
        Color(hex: "7B68AE"),  // Soft violet
        Color(hex: "D17B4F"),  // Burnt sienna
        Color(hex: "4A8B9B"),  // Teal
        Color(hex: "B5555A"),  // Dusty rose
    ]

    /// Deterministic color for a client profile UUID.
    static func clientColor(for uuid: String) -> Color {
        let hash = uuid.utf8.reduce(0) { ($0 &+ UInt32($1)) &* 31 }
        let index = Int(hash % UInt32(clientPalette.count))
        return clientPalette[index]
    }

    // ═══════════════════════════════════════════════════════════════
    // GLASS — For elements on .regularMaterial overlays
    // Light mode: higher opacity values for visibility
    // ═══════════════════════════════════════════════════════════════

    /// Inner card fill on material panels
    static let glassCardFill = Color.white.opacity(0.70)

    /// Input field fill on material panels
    static let glassInputFill = Color.white.opacity(0.80)

    /// Focused input field fill on material panels
    static let glassInputFillFocused = Color.white.opacity(0.90)

    /// Section container fill on material panels
    static let glassSectionFill = Color.white.opacity(0.50)

    /// Border for elements on material
    static let glassBorder = Color.black.opacity(0.08)

    /// Focused border on material
    static let glassBorderFocused = Color(hex: "2D6A4F").opacity(0.40)

    // ═══════════════════════════════════════════════════════════════
    // TYPOGRAPHY — System font (SF Pro) everywhere
    // ═══════════════════════════════════════════════════════════════

    /// Page title — 28–32px, weight 600, text color, -0.01em tracking
    static let pageTitle = Font.system(size: 28, weight: .semibold)

    /// Section label (UPPERCASE) — 11px, weight 600, textMuted, 0.08em tracking
    static let sectionLabel = Font.system(size: 11, weight: .semibold)

    /// Section description — 13px, weight 400, textSecondary
    static let sectionDesc = Font.system(size: 13, weight: .regular)

    /// Body / editor text — 15px, weight 400, text color, line-height 1.55
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

    /// Standard card chrome — white bg, 1px neutral border, resting shadow
    func dsCard() -> some View {
        self
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.border, lineWidth: 1)
            )
            .dsRestingShadow()
    }

    /// Editor card — white bg, 12px radius, accent left bar, resting shadow
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
            .dsRestingShadow()
    }

    /// Primary action button — accent green bg, white text, 8px radius
    func dsPrimaryButton() -> some View {
        self
            .font(DS.buttonText)
            .foregroundColor(DS.textOnAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(DS.accent)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
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

    /// Modal overlay — white bg, active border, 16px radius, floating shadow
    func dsModal() -> some View {
        self
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusLarge)
                    .stroke(DS.border, lineWidth: 1)
            )
            .dsFloatingShadow()
    }

    // ═══════════════════════════════════════════════════════════════
    // SHADOW MODIFIERS — Three tiers of depth
    // Soft, natural shadows for light backgrounds
    // ═══════════════════════════════════════════════════════════════

    /// Resting shadow — cards at rest, subtle depth
    func dsRestingShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
    }

    /// Hover shadow — lifted state, more presence
    func dsHoverShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 4)
            .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
    }

    /// Floating shadow — modals, popovers, dropdowns
    func dsFloatingShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 8)
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
    }

    // ═══════════════════════════════════════════════════════════════
    // GLASS MODIFIERS — For elements ON TOP of .regularMaterial
    // ═══════════════════════════════════════════════════════════════

    /// Translucent card for material panels — white fill + fine border
    func dsGlassCard(cornerRadius: CGFloat = DS.radiusSmall) -> some View {
        self
            .background(DS.glassCardFill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DS.glassBorder, lineWidth: 0.5)
            )
    }

    /// Input field on material — white fill, focus-aware border
    func dsGlassInput(isFocused: Bool = false, cornerRadius: CGFloat = DS.radiusSmall) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isFocused ? DS.glassInputFillFocused : DS.glassInputFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isFocused ? DS.glassBorderFocused : DS.glassBorder,
                        lineWidth: isFocused ? 1 : 0.5
                    )
            )
    }

    /// Subtle section container on material — groups content without visual weight
    func dsGlassSection(cornerRadius: CGFloat = 10) -> some View {
        self
            .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    // ═══════════════════════════════════════════════════════════════
    // LEGACY COMPATIBILITY — Redirect removed dark-mode modifiers
    // These no-op or redirect to light-mode equivalents so callers
    // don't break before they're migrated.
    // ═══════════════════════════════════════════════════════════════

    /// REMOVED (dark mode trick) — now applies dsCard()
    func dsPremiumCard(cornerRadius: CGFloat = DS.radiusMedium) -> some View {
        self
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DS.border, lineWidth: 1)
            )
            .dsRestingShadow()
    }

    /// REMOVED (dark mode trick) — now applies dsCard()
    func dsPremiumSection(cornerRadius: CGFloat = DS.radiusMedium) -> some View {
        self
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DS.border, lineWidth: 1)
            )
            .dsRestingShadow()
    }

    /// REMOVED (dark mode trick) — now applies dsRestingShadow()
    func dsPremiumShadow() -> some View {
        self.dsRestingShadow()
    }

    /// REMOVED (dark mode trick) — no-op
    func dsGradientBorder(cornerRadius: CGFloat = DS.radiusMedium) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DS.border, lineWidth: 1)
            )
    }

    /// REMOVED (dark mode trick) — no-op
    func dsTopHighlight(cornerRadius: CGFloat = DS.radiusLarge, height: CGFloat = 60) -> some View {
        self
    }
}
