// CosmoOS/Core/DesignSystem.swift
// Unified Design System — Multi-Theme Support
// Every screen MUST use these tokens. No inline color/font definitions.
// March 2026 — Themeable architecture

import SwiftUI

// MARK: - Design System (Dynamic Tokens)

/// Single source of truth for all visual tokens in CosmoOS.
/// Color tokens are dynamic — they read from the active ThemePalette.
/// Typography, spacing, radii, and animations are constant across themes.
enum DS {

    /// The active palette — swapped by ThemeManager on theme change.
    /// All color properties below are computed from this.
    nonisolated(unsafe) static var palette: ThemePalette = GreenhousePalette()

    // ═══════════════════════════════════════════════════════════════
    // SURFACES — Dynamic per theme
    // ═══════════════════════════════════════════════════════════════

    /// Page background
    static var bg: Color { palette.bg }

    /// Sidebar, panels, secondary surfaces
    static var surface: Color { palette.surface }

    /// Cards, editor areas, modals
    static var surfaceElevated: Color { palette.surfaceElevated }

    /// Thinkspace canvas cards, library cards
    static var surfaceCard: Color { palette.surfaceCard }

    /// Canvas background
    static var canvas: Color { palette.canvas }

    /// Hover state tint for interactive surfaces
    static var surfaceHover: Color { palette.surfaceHover }

    // ═══════════════════════════════════════════════════════════════
    // TEXT — Dynamic per theme, always WCAG AA compliant
    // ═══════════════════════════════════════════════════════════════

    /// Primary text, headings, editor content
    static var text: Color { palette.text }

    /// Descriptions, subtitles, helper text
    static var textSecondary: Color { palette.textSecondary }

    /// Placeholders, disabled, metadata timestamps
    static var textMuted: Color { palette.textMuted }

    /// Text on accent-colored backgrounds
    static var textOnAccent: Color { palette.textOnAccent }

    // ═══════════════════════════════════════════════════════════════
    // ACCENT — Dynamic per theme
    // ═══════════════════════════════════════════════════════════════

    /// Primary accent color
    static var accent: Color { palette.accent }

    /// Accent hover/pressed state
    static var accentHover: Color { palette.accentHover }

    /// Subtle accent glow for shadows
    static var accentGlow: Color { palette.accentGlow }

    /// Soft accent background for pills, tags, tinted areas
    static var accentSoft: Color { palette.accentSoft }

    // ═══════════════════════════════════════════════════════════════
    // STATUS — Dynamic per theme (adapted for light/dark contrast)
    // ═══════════════════════════════════════════════════════════════

    /// Success, completed states
    static var green: Color { palette.green }

    /// Glow behind green elements
    static var greenGlow: Color { palette.greenGlow }

    /// Warning, in-progress states
    static var orange: Color { palette.orange }

    /// Errors, high priority
    static var red: Color { palette.red }

    /// Info, links
    static var info: Color { palette.info }

    /// Soft status backgrounds
    static var greenSoft: Color { palette.greenSoft }
    static var orangeSoft: Color { palette.orangeSoft }
    static var redSoft: Color { palette.redSoft }
    static var infoSoft: Color { palette.infoSoft }

    // ═══════════════════════════════════════════════════════════════
    // BORDERS — Dynamic per theme
    // ═══════════════════════════════════════════════════════════════

    /// Standard borders everywhere
    static var border: Color { palette.border }

    /// Section dividers, faint separations
    static var borderSubtle: Color { palette.borderSubtle }

    /// Focus states, active inputs
    static var borderActive: Color { palette.borderActive }

    /// Focus ring for keyboard navigation
    static var focusRing: Color { palette.focusRing }

    // ═══════════════════════════════════════════════════════════════
    // AKASHIC CODEX — Premium material system
    // Gilt ornaments, vellum surfaces, warm ink, sepia borders
    // ═══════════════════════════════════════════════════════════════

    /// Gold accent for ornamental details — never a fill, never a bar
    static var gilt: Color { palette.gilt }

    /// Subtle gold wash for premium backgrounds
    static var giltSoft: Color { palette.giltSoft }

    /// Fine lines, filigree strokes, section labels
    static var giltMuted: Color { palette.giltMuted }

    /// Aged paper surface (warmer than surface)
    static var vellum: Color { palette.vellum }

    /// Deeper parchment for inset/recessed areas
    static var vellumDeep: Color { palette.vellumDeep }

    /// Near-black with warm undertone for display text
    static var inkWash: Color { palette.inkWash }

    /// Faded ink for secondary information (WCAG AA safe)
    static var inkFaded: Color { palette.inkFaded }

    /// Warm border replacing cool gray
    static var sepiaBorder: Color { palette.sepiaBorder }

    /// Warm subtle border
    static var sepiaSubtle: Color { palette.sepiaSubtle }

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

    /// Sticky notes — warm yellow
    static let entityStickyNote = Color(hex: "D4C36A")

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
    // GLASS — Dynamic per theme
    // ═══════════════════════════════════════════════════════════════

    /// Inner card fill on material panels
    static var glassCardFill: Color { palette.glassCardFill }

    /// Input field fill on material panels
    static var glassInputFill: Color { palette.glassInputFill }

    /// Focused input field fill on material panels
    static var glassInputFillFocused: Color { palette.glassInputFillFocused }

    /// Section container fill on material panels
    static var glassSectionFill: Color { palette.glassSectionFill }

    /// Border for elements on material
    static var glassBorder: Color { palette.glassBorder }

    /// Focused border on material
    static var glassBorderFocused: Color { palette.glassBorderFocused }

    // ═══════════════════════════════════════════════════════════════
    // TYPOGRAPHY — System font (SF Pro) everywhere
    // Complete type scale: display → caption2
    // ═══════════════════════════════════════════════════════════════

    /// Display — 32pt bold, splash/onboarding hero text
    static let display = Font.system(size: 32, weight: .bold)

    /// Page title — 28pt semibold, screen titles
    static let pageTitle = Font.system(size: 28, weight: .semibold)

    /// Title 1 — 22pt semibold, modal/panel titles
    static let title1 = Font.system(size: 22, weight: .semibold)

    /// Title 2 — 18pt semibold, section headers
    static let title2 = Font.system(size: 18, weight: .semibold)

    /// Title 3 — 15pt medium, card titles, list group headers
    static let title3 = Font.system(size: 15, weight: .medium)

    /// Headline — 15pt semibold, emphasized body, bold labels
    static let headline = Font.system(size: 15, weight: .semibold)

    /// Body — 15pt regular, default content, editor text (line-height 1.55)
    static let body = Font.system(size: 15, weight: .regular)

    /// Callout — 13pt regular, secondary content, descriptions
    static let callout = Font.system(size: 13, weight: .regular)

    /// Subheadline — 12pt regular, metadata, timestamps
    static let subheadline = Font.system(size: 12, weight: .regular)

    /// Footnote — 11pt regular, tertiary info, hints
    static let footnote = Font.system(size: 11, weight: .regular)

    /// Caption — 11pt medium, badges, small labels
    static let caption = Font.system(size: 11, weight: .medium)

    /// Caption 2 — 10pt regular, smallest readable text
    static let caption2 = Font.system(size: 10, weight: .regular)

    // ═══════════════════════════════════════════════════════════════
    // AKASHIC CODEX TYPOGRAPHY — Serif display, monospace data
    // ═══════════════════════════════════════════════════════════════

    /// Display serif — 32pt light New York, greeting hero ONLY
    static let displaySerif = Font.system(size: 32, weight: .light, design: .serif)

    /// Date serif — 14pt regular New York, date line below greeting ONLY
    static let dateSerif = Font.system(size: 14, weight: .regular, design: .serif)

    /// Monospace tabular — 28pt ultralight, timer digits
    static let monoTabular = Font.system(size: 28, weight: .ultraLight, design: .monospaced)

    /// Small caps — 10pt semibold, section labels (replaces uppercase + tracking)
    static let smallCaps = Font.system(size: 10, weight: .semibold).smallCaps()

    // Legacy aliases (map to new scale for backward compat)

    /// Section label (UPPERCASE) — 11px, weight 600, textMuted, 0.08em tracking
    static let sectionLabel = Font.system(size: 11, weight: .semibold)

    /// Section description — alias for callout
    static let sectionDesc = callout

    /// Card title — alias for title3
    static let cardTitle = title3

    /// Card metadata — alias for subheadline
    static let cardMeta = subheadline

    /// Button text — 12pt medium, buttons and controls
    static let buttonText = Font.system(size: 12, weight: .medium)

    /// Timestamp — alias for footnote
    static let timestamp = footnote

    /// Nav bar title — 14pt medium
    static let navTitle = Font.system(size: 14, weight: .medium)

    /// Nav bar badge — alias for caption2
    static let navBadge = Font.system(size: 10, weight: .medium)

    // ═══════════════════════════════════════════════════════════════
    // RADII — 5 values covering all use cases
    // ═══════════════════════════════════════════════════════════════

    /// Badges, tiny inline elements
    static let radiusXSmall: CGFloat = 4

    /// Buttons, inputs
    static let radiusSmall: CGFloat = 8

    /// Cards
    static let radiusMedium: CGFloat = 12

    /// Modals, overlays
    static let radiusLarge: CGFloat = 16

    /// Capsule / pill shape
    static let radiusFull: CGFloat = 9999

    // ═══════════════════════════════════════════════════════════════
    // SPACING — 4px grid, consistent throughout
    // Every padding/margin/gap MUST use one of these values.
    // ═══════════════════════════════════════════════════════════════

    /// 2pt — hairline gaps, inline icon spacing
    static let space2: CGFloat = 2

    /// 4pt — tight padding, compact elements
    static let space4: CGFloat = 4

    /// 6pt — tight-compact, between related elements
    static let space6: CGFloat = 6

    /// 8pt — compact spacing, small card padding
    static let space8: CGFloat = 8

    /// 10pt — between label and content
    static let space10: CGFloat = 10

    /// 12pt — default inner padding
    static let space12: CGFloat = 12

    /// 16pt — standard section spacing
    static let space16: CGFloat = 16

    /// 18pt — card inner padding (legacy alias)
    static let space18: CGFloat = 18

    /// 20pt — comfortable padding
    static let space20: CGFloat = 20

    /// 24pt — group spacing
    static let space24: CGFloat = 24

    /// 32pt — major section breaks
    static let space32: CGFloat = 32

    /// 36pt — between major sections (legacy alias)
    static let space36: CGFloat = 36

    /// 40pt — page margins
    static let space40: CGFloat = 40

    /// 48pt — page-level spacing, large gaps
    static let space48: CGFloat = 48

    // Legacy aliases
    static let sectionSpacing: CGFloat = 36
    static let cardPadding: CGFloat = 18
    static let pageMargin: CGFloat = 40

    // ═══════════════════════════════════════════════════════════════
    // OPACITY — Semantic opacity values
    // ═══════════════════════════════════════════════════════════════

    /// Disabled elements
    static let opacityDisabled: Double = 0.4

    /// Secondary/supporting elements
    static let opacitySecondary: Double = 0.6

    /// Pressed state overlay
    static let opacityPressed: Double = 0.15

    /// Subtle tint (entity soft backgrounds, hover fills)
    static let opacitySubtle: Double = 0.12

    /// Hover state overlay
    static let opacityHover: Double = 0.08

    /// Faint hint (borders, separators)
    static let opacityFaint: Double = 0.04
}

// MARK: - Button Styles

/// Primary action button with hover/press feedback
struct DSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.buttonText)
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? DS.accentHover : DS.accent)
            .clipShape(.rect(cornerRadius: DS.radiusSmall))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.0), value: configuration.isPressed)
    }
}

/// Ghost button with border and hover/press feedback
struct DSGhostButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.buttonText)
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isHovered ? DS.surfaceHover : Color.clear)
            .clipShape(.rect(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.0), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

/// Soft accent button with hover/press feedback
struct DSAccentSoftButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.buttonText)
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isHovered ? DS.accentSoft.opacity(0.8) : DS.accentSoft)
            .clipShape(.rect(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.accent.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.0), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Reusable View Modifiers

extension View {

    /// Akashic section label — 10px smallCaps in warm gilt
    func dsSectionLabel() -> some View {
        self
            .font(DS.smallCaps)
            .foregroundStyle(DS.giltMuted)
    }

    /// Standard card chrome — white bg, warm sepia border, resting shadow
    func dsCard() -> some View {
        self
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.sepiaBorder, lineWidth: 0.5)
            )
            .dsRestingShadow()
    }

    /// DEPRECATED — Use dsGiltCornerOrnament() instead. Accent left bar is removed.
    @available(*, deprecated, renamed: "dsGiltCornerOrnament")
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
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(DS.accent)
            .clipShape(.rect(cornerRadius: DS.radiusSmall))
    }

    /// Ghost button — transparent bg, 1px border, textSecondary
    func dsGhostButton() -> some View {
        self
            .font(DS.buttonText)
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.clear)
            .clipShape(.rect(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.border, lineWidth: 1)
            )
    }

    /// Soft accent button — accentSoft bg, accent text, 8px radius
    func dsAccentSoftButton() -> some View {
        self
            .font(DS.buttonText)
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(DS.accentSoft)
            .clipShape(.rect(cornerRadius: DS.radiusSmall))
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
        let isDark = DS.palette.isDark
        return self
            .shadow(color: .black.opacity(isDark ? 0.3 : 0.04), radius: isDark ? 4 : 8, x: 0, y: isDark ? 1 : 2)
            .shadow(color: .black.opacity(isDark ? 0.2 : 0.02), radius: isDark ? 1 : 2, x: 0, y: isDark ? 0 : 1)
    }

    /// Hover shadow — lifted state, more presence
    func dsHoverShadow() -> some View {
        let isDark = DS.palette.isDark
        return self
            .shadow(color: .black.opacity(isDark ? 0.4 : 0.06), radius: isDark ? 8 : 16, x: 0, y: isDark ? 2 : 4)
            .shadow(color: .black.opacity(isDark ? 0.25 : 0.03), radius: isDark ? 2 : 4, x: 0, y: isDark ? 1 : 2)
    }

    /// Floating shadow — modals, popovers, dropdowns
    func dsFloatingShadow() -> some View {
        let isDark = DS.palette.isDark
        return self
            .shadow(color: .black.opacity(isDark ? 0.5 : 0.08), radius: isDark ? 16 : 24, x: 0, y: isDark ? 4 : 8)
            .shadow(color: .black.opacity(isDark ? 0.3 : 0.04), radius: isDark ? 4 : 6, x: 0, y: isDark ? 2 : 3)
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

    // ═══════════════════════════════════════════════════════════════
    // AKASHIC CODEX MODIFIERS — Premium material card system
    // ═══════════════════════════════════════════════════════════════

    /// Vellum card — warm aged-paper surface, sepia border, resting shadow
    func dsVellumCard(cornerRadius: CGFloat = 10) -> some View {
        self
            .background(DS.vellum, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DS.sepiaBorder, lineWidth: 0.5)
            )
            .dsRestingShadow()
    }

    /// Vellum inset — deeper parchment for recessed areas (calendars, chart containers)
    func dsVellumInset(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(DS.vellumDeep, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DS.sepiaBorder, lineWidth: 0.5)
            )
    }

    /// Gilt corner ornament card — replaces dsEditorCard. Vellum bg + L-bracket at top-left
    func dsGiltCornerOrnament(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(DS.vellum, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DS.sepiaBorder, lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                GiltCornerBracket()
                    .stroke(DS.gilt, lineWidth: 0.8)
                    .frame(width: 12, height: 12)
                    .padding(6)
            }
            .dsRestingShadow()
    }

    /// Small caps section label — replaces dsSectionLabel (no more uppercase + tracking hack)
    func dsSmallCapsLabel() -> some View {
        self
            .font(DS.smallCaps)
            .foregroundStyle(DS.giltMuted)
    }
}

// MARK: - Akashic Codex Section Divider

/// Double-line divider replacing gradient dividers — two parallel 0.5px lines, 2px apart
struct AkashicSectionDivider: View {
    var body: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(height: 0.5)
            Rectangle()
                .fill(DS.sepiaSubtle.opacity(0.5))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Gilt Corner Bracket Shape

/// L-shaped bracket for top-left corner of premium cards.
/// Replaces the generic accent bar pattern.
struct GiltCornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Horizontal line from left to right
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        // Corner bend down
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        return path
    }
}

// MARK: - Ornamental Rule

/// Horizontal decorative rule with diamond center — used in greeting, empty states.
/// A thin line (40px) with a small rotated square at center.
struct OrnamentalRule: View {
    var width: CGFloat = 40
    var color: Color = DS.gilt

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: (width - 8) / 2, height: 0.5)

            Rectangle()
                .fill(color)
                .frame(width: 4, height: 4)
                .rotationEffect(.degrees(45))

            Rectangle()
                .fill(color)
                .frame(width: (width - 8) / 2, height: 0.5)
        }
        .frame(height: 6)
    }
}

// MARK: - Track and Bead Progress

/// Navigational progress indicator for objectives — 1px track + filled portion + circle bead.
/// Replaces flat progress bars with a cartographic-feeling plot line.
struct TrackAndBead: View {
    let progress: Double
    let color: Color
    let animate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let fillWidth = geo.size.width * (animate ? min(progress, 1.0) : 0)

            ZStack(alignment: .leading) {
                // Track (unfilled)
                Rectangle()
                    .fill(DS.sepiaSubtle)
                    .frame(height: 1)

                // Filled portion
                Rectangle()
                    .fill(color)
                    .frame(width: fillWidth, height: 2)

                // Bead at endpoint
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .offset(x: max(fillWidth - 2.5, 0))
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 5)
    }
}
