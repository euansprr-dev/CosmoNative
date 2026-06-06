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

    private static var usesMonoMaterial: Bool {
        palette.name == "Codex Mono" || palette.name == "Black Mono"
    }

    private static var usesBlackMonoPaper: Bool {
        palette.name == "Black Mono"
    }

    /// Full-screen focus modes in Black Mono should feel like immersive dark
    /// rooms, while document cards and previews keep stable paper styling.
    static var usesImmersiveFocusAppearance: Bool {
        usesBlackMonoPaper
    }

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

    /// Swipe File uses the same root workspace background as Command Center.
    /// Keep this separate from document paper tokens so mono themes stay exact.
    static var swipeLibraryBackground: Color { bg }

    /// Hover state tint for interactive surfaces
    static var surfaceHover: Color { palette.surfaceHover }

    /// Compact command/dashboard chrome fill. Kept separate from document paper so
    /// Black Mono app controls stay dark while notes and cards remain white.
    static var commandChromePanelFill: Color {
        if usesBlackMonoPaper { return palette.surfaceElevated }
        return documentVellum.opacity(0.35)
    }

    /// Stronger compact command/dashboard chrome fill for nested active states.
    static var commandChromeProminentFill: Color {
        if usesBlackMonoPaper { return palette.surfaceCard }
        return documentVellum.opacity(0.50)
    }

    /// Compact command/dashboard chrome border.
    static var commandChromeBorder: Color {
        if usesBlackMonoPaper { return palette.border }
        return documentSepiaSubtle
    }

    /// Fine dividers that sit directly on compact command/dashboard chrome.
    static var commandChromeSeparator: Color {
        if usesBlackMonoPaper { return palette.borderSubtle }
        return documentSepiaSubtle
    }

    /// Stronger dividers for compact command/dashboard panel boundaries.
    static var commandChromeSeparatorStrong: Color {
        if usesBlackMonoPaper { return palette.border }
        return documentSepiaBorder
    }

    /// Stronger compact command/dashboard border.
    static var commandChromeProminentBorder: Color {
        if usesBlackMonoPaper { return palette.border }
        return documentSepiaBorder.opacity(0.65)
    }

    /// Secondary compact control fill on command/dashboard chrome.
    static var commandChromeControlFill: Color {
        if usesBlackMonoPaper { return palette.surfaceHover }
        return documentVellumDeep.opacity(0.65)
    }

    /// Secondary compact control border on command/dashboard chrome.
    static var commandChromeControlBorder: Color {
        if usesBlackMonoPaper { return palette.border }
        return documentSepiaSubtle
    }

    /// Primary Command Center text. Black Mono command chrome is dark, while
    /// document paper remains light, so command surfaces cannot reuse ink tokens.
    static var commandCenterTitleText: Color {
        if usesBlackMonoPaper { return palette.text }
        return documentInkWash
    }

    /// Secondary Command Center text on app chrome.
    static var commandCenterSecondaryText: Color {
        if usesBlackMonoPaper { return palette.textSecondary }
        return documentInkFaded
    }

    /// Muted Command Center metadata text on app chrome.
    static var commandCenterMutedText: Color {
        if usesBlackMonoPaper { return palette.textMuted }
        return documentInkFaded
    }

    /// Command Center ornamental text and icon color.
    static var commandCenterOrnamentText: Color {
        if usesBlackMonoPaper { return palette.textMuted }
        return documentGiltMuted
    }

    /// Command Center hairline separators on chrome, distinct from document paper
    /// separators so Black Mono does not draw white paper rules on black UI.
    static var commandCenterSeparator: Color {
        commandChromeSeparator
    }

    /// Stronger Command Center separator for panel boundaries.
    static var commandCenterSeparatorStrong: Color {
        commandChromeSeparatorStrong
    }

    /// Selected row fill for Command Center navigation.
    static var commandCenterSelectedRowFill: Color {
        if usesBlackMonoPaper { return commandChromeProminentFill }
        return documentVellum
    }

    // ═══════════════════════════════════════════════════════════════
    // FOCUS MODE — Immersive full-screen chrome for Black Mono.
    // These are intentionally separate from document paper tokens.
    // ═══════════════════════════════════════════════════════════════

    static var focusImmersiveBackground: Color {
        if usesBlackMonoPaper { return palette.bg }
        return documentBackground
    }

    static var focusImmersiveSurface: Color {
        if usesBlackMonoPaper { return palette.surfaceElevated }
        return documentSurface
    }

    static var focusImmersiveSurfaceElevated: Color {
        if usesBlackMonoPaper { return palette.surfaceCard }
        return documentSurface
    }

    static var focusImmersiveText: Color {
        if usesBlackMonoPaper { return palette.text }
        return documentText
    }

    static var focusImmersiveTextSecondary: Color {
        if usesBlackMonoPaper { return palette.textSecondary }
        return documentTextSecondary
    }

    static var focusImmersiveTextMuted: Color {
        if usesBlackMonoPaper { return palette.textMuted }
        return documentTextMuted
    }

    static var focusImmersiveBorder: Color {
        if usesBlackMonoPaper { return palette.border }
        return documentBorder
    }

    // ═══════════════════════════════════════════════════════════════
    // DOCUMENT PAPER — Stable light surfaces for notes, content drafts,
    // connection manuscripts, and other long-form reading/writing areas.
    // Dark app chrome can change, but paper should remain paper.
    // ═══════════════════════════════════════════════════════════════

    static var documentBackground: Color {
        if usesBlackMonoPaper { return palette.vellumDeep }
        return palette.isDark ? Color(hex: "F8F7F4") : palette.bg
    }

    static var documentSurface: Color {
        if usesBlackMonoPaper { return palette.vellum }
        return palette.isDark ? Color(hex: "FFFFFF") : palette.surfaceElevated
    }

    /// Canvas document cards stay paper-like in Black Mono, but use a softened
    /// near-white to avoid glowing against the black dotted canvas.
    static var canvasDocumentSurface: Color {
        if usesBlackMonoPaper { return Color(hex: "F7F7F5") }
        return documentSurface
    }

    static var canvasDocumentText: Color {
        documentText
    }

    static var canvasDocumentBorder: Color {
        documentBorderSubtle
    }

    static var documentSurfaceHover: Color {
        if usesBlackMonoPaper { return palette.sepiaSubtle }
        return palette.isDark ? Color(hex: "F0EFEB") : palette.surfaceHover
    }

    static var documentText: Color {
        if usesBlackMonoPaper { return palette.inkWash }
        return palette.isDark ? Color(hex: "1A1A1F") : palette.text
    }

    static var documentTextSecondary: Color {
        if usesBlackMonoPaper { return palette.inkFaded }
        return palette.isDark ? Color(hex: "6B6B78") : palette.textSecondary
    }

    static var documentTextMuted: Color {
        if usesBlackMonoPaper { return palette.inkFaded }
        return palette.isDark ? Color(hex: "767685") : palette.textMuted
    }

    static var documentBorder: Color {
        if usesBlackMonoPaper { return palette.sepiaBorder }
        return palette.isDark ? Color(hex: "DCDCE0") : palette.border
    }

    static var documentBorderSubtle: Color {
        if usesBlackMonoPaper { return palette.sepiaBorder }
        return palette.isDark ? Color(hex: "E8E8EC") : palette.borderSubtle
    }

    static var documentVellum: Color {
        if usesBlackMonoPaper { return palette.vellum }
        return palette.isDark ? Color(hex: "F3EDE4") : palette.vellum
    }

    static var documentVellumDeep: Color {
        if usesBlackMonoPaper { return palette.vellumDeep }
        return palette.isDark ? Color(hex: "EDE5D8") : palette.vellumDeep
    }

    static var documentInkWash: Color {
        if usesBlackMonoPaper { return palette.inkWash }
        return palette.isDark ? Color(hex: "2C2A26") : palette.inkWash
    }

    static var documentInkFaded: Color {
        if usesBlackMonoPaper { return palette.inkFaded }
        return palette.isDark ? Color(hex: "7A7568") : palette.inkFaded
    }

    static var documentSepiaBorder: Color {
        if usesBlackMonoPaper { return palette.sepiaBorder }
        return palette.isDark ? Color(hex: "DDD5C8") : palette.sepiaBorder
    }

    static var documentSepiaSubtle: Color {
        if usesBlackMonoPaper { return palette.sepiaSubtle }
        return palette.isDark ? Color(hex: "E8E1D6") : palette.sepiaSubtle
    }

    static var documentGilt: Color {
        if usesBlackMonoPaper { return palette.gilt }
        return palette.isDark ? Color(hex: "C4A265") : palette.gilt
    }

    static var documentGiltSoft: Color {
        if usesBlackMonoPaper { return palette.giltSoft }
        return palette.isDark ? Color(hex: "F5EDD8") : palette.giltSoft
    }

    static var documentGiltMuted: Color {
        if usesBlackMonoPaper { return palette.giltMuted }
        return palette.isDark ? Color(hex: "D4C9A8") : palette.giltMuted
    }

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
    static var gilt: Color { documentGilt }

    /// Subtle gold wash for premium backgrounds
    static var giltSoft: Color { documentGiltSoft }

    /// Fine lines, filigree strokes, section labels
    static var giltMuted: Color { documentGiltMuted }

    /// Aged paper surface (warmer than surface)
    static var vellum: Color { documentVellum }

    /// Deeper parchment for inset/recessed areas
    static var vellumDeep: Color { documentVellumDeep }

    /// Near-black with warm undertone for display text
    static var inkWash: Color { documentInkWash }

    /// Faded ink for secondary information (WCAG AA safe)
    static var inkFaded: Color { documentInkFaded }

    /// Warm border replacing cool gray
    static var sepiaBorder: Color { documentSepiaBorder }

    /// Warm subtle border
    static var sepiaSubtle: Color { documentSepiaSubtle }

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

    /// Classification color for the "new" Inbox triage state (cool indigo,
    /// matches the visual feel of a freshly captured thought)
    static let classNew = Color(hex: "818CF8")

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
    // CANVAS CLUSTERS — Large-zone visual weight per theme
    // ═══════════════════════════════════════════════════════════════

    /// Neutral cluster body wash. Black Mono intentionally uses the light-mode
    /// wash model so clusters stay luminous against the black canvas.
    static func canvasClusterSurfaceFill(
        isDropTarget: Bool,
        isUserCreated: Bool,
        usesExpandedContent: Bool
    ) -> Color {
        let opacity = canvasClusterSurfaceFillOpacity(
            isDropTarget: isDropTarget,
            isUserCreated: isUserCreated,
            usesExpandedContent: usesExpandedContent
        )

        if palette.isDark && !usesBlackMonoPaper {
            return Color.black.opacity(opacity)
        }
        return Color.white.opacity(opacity)
    }

    static func canvasClusterSurfaceFillOpacity(
        isDropTarget: Bool,
        isUserCreated: Bool,
        usesExpandedContent: Bool
    ) -> Double {
        if usesBlackMonoPaper {
            if isDropTarget { return 0.045 }
            if isUserCreated { return usesExpandedContent ? 0.038 : 0.032 }
            return 0.024
        }

        if !palette.isDark {
            if isDropTarget { return 0.030 }
            if isUserCreated { return usesExpandedContent ? 0.026 : 0.022 }
            return 0.018
        }

        if isDropTarget { return 0.050 }
        if isUserCreated { return usesExpandedContent ? 0.040 : 0.032 }
        return 0.026
    }

    static func canvasClusterAccentWashOpacity(
        isDropTarget: Bool,
        isUserCreated: Bool,
        usesExpandedContent: Bool
    ) -> Double {
        if usesBlackMonoPaper {
            if isDropTarget { return 0.30 }
            if isUserCreated { return usesExpandedContent ? 0.245 : 0.215 }
            return 0.16
        }

        if !palette.isDark {
            if isDropTarget { return 0.22 }
            if isUserCreated { return usesExpandedContent ? 0.18 : 0.155 }
            return 0.12
        }

        if isDropTarget { return 0.075 }
        if isUserCreated { return usesExpandedContent ? 0.040 : 0.032 }
        return 0.022
    }

    static func canvasClusterStrokeOpacity(
        isSelected: Bool,
        isHovered: Bool,
        isDropTarget: Bool
    ) -> Double {
        if isDropTarget { return 0.96 }
        if isSelected { return 0.88 }
        if usesBlackMonoPaper {
            return isHovered ? 0.78 : 0.68
        }
        if !palette.isDark {
            return isHovered ? 0.68 : 0.54
        }
        return isHovered ? 0.52 : 0.36
    }

    // ═══════════════════════════════════════════════════════════════
    // SIDEBAR MATERIAL — Semantic glass panel tokens
    // ═══════════════════════════════════════════════════════════════

    /// Base wash layered above native macOS material for major app sidebars.
    static var sidebarMaterialBase: Color {
        if palette.isDark { return Color.black.opacity(0.018) }
        return usesMonoMaterial ? Color.white.opacity(0.665) : Color.white.opacity(0.010)
    }

    /// Opacity for the native material layer. Light mode needs a lower value so
    /// bright canvas content can still register through the sidebar.
    static var sidebarMaterialNativeOpacity: Double {
        if palette.isDark { return 0.94 }
        return usesMonoMaterial ? 0.650 : 0.74
    }

    /// Solid fallback used when Reduce Transparency is enabled.
    static var sidebarMaterialFallback: Color {
        if palette.isDark { return palette.surface }
        return palette.surfaceElevated
    }

    /// Hairline material edge.
    static var sidebarMaterialBorder: Color {
        if palette.isDark { return Color.white.opacity(0.16) }
        return Color.black.opacity(usesMonoMaterial ? 0.058 : 0.085)
    }

    /// Top/leading highlight for the glass surface.
    static var sidebarMaterialHighlight: Color {
        if palette.isDark { return Color.white.opacity(0.18) }
        return Color.white.opacity(usesMonoMaterial ? 0.64 : 0.30)
    }

    /// Inner shade that keeps translucent panels readable.
    static var sidebarMaterialInnerShade: Color {
        if palette.isDark { return Color.black.opacity(0.018) }
        return Color.black.opacity(usesMonoMaterial ? 0 : 0.010)
    }

    /// Ambient scene tint cap for global sidebars.
    static var sidebarMaterialAmbientOpacity: Double {
        0
    }

    /// Stronger tint cap along the content-facing edge.
    static var sidebarMaterialEdgeTintOpacity: Double {
        0
    }

    /// Subtle edge response used only when canvas content is physically near the sidebar.
    static var sidebarMaterialCanvasEdgeOpacity: Double {
        0
    }

    /// Tiny rim-only accent cap for focus or compatibility tints.
    static var sidebarMaterialRimAccentOpacity: Double {
        0
    }

    /// Optional material texture opacity for major glass panels.
    static var sidebarMaterialNoiseOpacity: Double {
        0
    }

    /// Exterior shadow for inset glass panels.
    static var sidebarMaterialShadow: Color {
        if palette.isDark { return Color.black.opacity(0.075) }
        return Color.black.opacity(usesMonoMaterial ? 0.034 : 0.028)
    }

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

    /// Space title serif — 21pt regular New York, Command-K space plate names
    static let spaceTitleSerif = Font.system(size: 21, weight: .regular, design: .serif)

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

// MARK: - Focus Mode Entry Transition

private struct FocusImmersiveEntryTransitionModifier: ViewModifier {
    @State private var showScrim = true

    func body(content: Content) -> some View {
        content
            .overlay {
                if DS.usesImmersiveFocusAppearance && showScrim {
                    DS.canvasDocumentSurface
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard DS.usesImmersiveFocusAppearance else {
                    showScrim = false
                    return
                }
                withAnimation(.easeOut(duration: 0.24)) {
                    showScrim = false
                }
            }
    }
}

extension View {
    func focusImmersiveEntryTransition() -> some View {
        modifier(FocusImmersiveEntryTransitionModifier())
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

    /// Greenhouse glass card — warm glass fill + a content-adaptive tint wash ("lensing")
    /// + a specular hairline that thickens on hover. The workhorse surface from
    /// GREENHOUSE_GLASS §5.1. Apply motion (`scaleEffect`, `cardShadow`) at the *call site*
    /// so this stays usable for static skeletons and previews.
    func glassCard(isHovered: Bool = false, tint: Color = DS.accent, cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(tint.opacity(isHovered ? 0.10 : 0.06), in: shape)   // lensing wash
            .background(DS.glassCardFill, in: shape)                        // warm glass
            .overlay(
                shape.strokeBorder(
                    isHovered ? DS.glassBorderFocused : DS.glassBorder,
                    lineWidth: isHovered ? 1 : 0.5
                )
            )
            .clipShape(shape)
    }

    /// Resting → hover card shadow as ONE constant-structure modifier. Never branch structure
    /// on animated state inside a modifier (GREENHOUSE_GLASS §7.1) — values interpolate here,
    /// so the lift animates for free without rebuilding the wrapped subtree.
    func cardShadow(isHovered: Bool = false) -> some View {
        let isDark = DS.palette.isDark
        return self
            .shadow(
                color: .black.opacity(isHovered ? (isDark ? 0.4 : 0.06) : (isDark ? 0.3 : 0.04)),
                radius: isHovered ? (isDark ? 8 : 16) : (isDark ? 4 : 8),
                x: 0, y: isHovered ? (isDark ? 2 : 4) : (isDark ? 1 : 2)
            )
            .shadow(
                color: .black.opacity(isHovered ? (isDark ? 0.25 : 0.03) : (isDark ? 0.2 : 0.02)),
                radius: isHovered ? (isDark ? 2 : 4) : (isDark ? 1 : 2),
                x: 0, y: isHovered ? (isDark ? 1 : 2) : (isDark ? 0 : 1)
            )
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
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
            Rectangle()
                .fill(DS.commandCenterSeparator.opacity(0.5))
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
