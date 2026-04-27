// CosmoOS/Core/Theme.swift
// Design system and theming for Cosmo OS
// "Greenhouse" — Warm, natural, alive with ideas growing
// March 2026 — Light-mode rebrand

import SwiftUI
import AppKit
import GRDB

// MARK: - CosmoColors (Theme-Aware Palette)
// Surface, text, accent, and status colors now forward to DS (dynamic per theme).
// Entity colors and specialty colors remain static (identity, not chrome).
struct CosmoColors {
    // ═══════════════════════════════════════════════════════════════
    // BASE LAYER — Forwarded to DS (dynamic per theme)
    // ═══════════════════════════════════════════════════════════════

    static var softWhite: Color { DS.bg }
    static var canvasBackground: Color { DS.canvas }
    static var background: Color { DS.bg }
    static var cardBackground: Color { DS.surfaceElevated }

    // ═══════════════════════════════════════════════════════════════
    // DEPTH LAYER — Structural (static, works in all themes)
    // ═══════════════════════════════════════════════════════════════

    static let mistGrey = Color(hex: "E3E4E8")
    static let slate = Color(hex: "64748B")
    static let glassGrey = Color(hex: "D7D9DE")

    // ═══════════════════════════════════════════════════════════════
    // ENERGY ACCENTS — Accent forwarded, specialty static
    // ═══════════════════════════════════════════════════════════════

    static let skyBlue = Color(hex: "A8CCE8")
    static var lavender: Color { DS.accent }
    static let coral = Color(hex: "F4AFA0")

    // ═══════════════════════════════════════════════════════════════
    // STATUS COLORS — Forwarded to DS (dynamic per theme)
    // ═══════════════════════════════════════════════════════════════

    static var emerald: Color { DS.green }
    static var mint: Color { DS.green }
    static var amber: Color { DS.orange }
    static var softRed: Color { DS.red }

    // ═══════════════════════════════════════════════════════════════
    // TEXT COLORS — Forwarded to DS (dynamic per theme)
    // ═══════════════════════════════════════════════════════════════

    static var textPrimary: Color { DS.text }
    static var textSecondary: Color { DS.textSecondary }
    static var textTertiary: Color { DS.textMuted }

    // ═══════════════════════════════════════════════════════════════
    // ENTITY COLORS — Static (identity, not chrome)
    // ═══════════════════════════════════════════════════════════════

    static let idea = Color(hex: "6B6EA8")
    static let content = Color(hex: "5B84B0")
    static let task = Color(hex: "B06B6B")
    static let research = Color(hex: "4A8B72")
    static let note = Color(hex: "9B8A6E")
    static let cosmoAI = Color(hex: "2D6A4F")

    // ═══════════════════════════════════════════════════════════════
    // THINKSPACE — Forwarded to DS (dynamic per theme)
    // ═══════════════════════════════════════════════════════════════

    static var thinkspaceVoid: Color { DS.canvas }
    static var thinkspaceSecondary: Color { DS.surface }
    static var thinkspaceTertiary: Color { DS.surfaceElevated }
    static var thinkspaceGrid: Color { DS.borderSubtle }
    static var thinkspacePurple: Color { DS.accent }

    /// Block accent colors — static (entity identity)
    static let blockNote = Color(hex: "9B8A6E")
    static let blockContent = Color(hex: "5B84B0")
    static let blockResearch = Color(hex: "4A8B72")
    static let blockConnection = Color(hex: "8B6BAB")

    // ═══════════════════════════════════════════════════════════════
    // GRADIENTS — Use dynamic accent
    // ═══════════════════════════════════════════════════════════════

    static var aiGradient: LinearGradient {
        LinearGradient(
            colors: [DS.accent, DS.accent.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var warmGradient: LinearGradient {
        LinearGradient(
            colors: [coral, Color(hex: "F5D0C8")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Premium Typography (Cognitive Optimized)
/// Type scale based on Minor Third ratio (1.2) for visual harmony
/// Optimized for reading flow and reduced cognitive load
struct CosmoTypography {
    // ═══════════════════════════════════════════════════════════════
    // DISPLAY - For titles, hero headers (used sparingly)
    // ═══════════════════════════════════════════════════════════════

    /// Large display text - document titles, hero headers
    static let display = Font.system(size: 32, weight: .bold, design: .default)

    /// Medium display - section headers in focus mode
    static let displayMedium = Font.system(size: 28, weight: .semibold, design: .default)
    static let displayLarge = display
    static let displaySmall = displayMedium

    // ═══════════════════════════════════════════════════════════════
    // TITLE - Section and block headers
    // ═══════════════════════════════════════════════════════════════

    /// Primary title - card headers, modal titles
    static let title = Font.system(size: 22, weight: .semibold, design: .default)

    /// Smaller title - floating block headers
    static let titleSmall = Font.system(size: 18, weight: .semibold, design: .default)

    // ═══════════════════════════════════════════════════════════════
    // BODY - Main content (optimized for extended reading)
    // Research shows 15-17pt optimal for screen reading
    // ═══════════════════════════════════════════════════════════════

    /// Large body - primary editor content
    static let bodyLarge = Font.system(size: 17, weight: .regular, design: .default)

    /// Standard body - general content
    static let body = Font.system(size: 15, weight: .regular, design: .default)

    /// Small body - secondary content, previews
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)

    // ═══════════════════════════════════════════════════════════════
    // UI - Interface labels and controls
    // ═══════════════════════════════════════════════════════════════

    /// Labels - buttons, badges, metadata
    static let label = Font.system(size: 13, weight: .medium, design: .default)

    /// Small labels - tags, timestamps
    static let labelSmall = Font.system(size: 11, weight: .medium, design: .default)

    /// Captions - footnotes, hints
    static let caption = Font.system(size: 11, weight: .regular, design: .default)

    // ═══════════════════════════════════════════════════════════════
    // MONOSPACE - Code and technical content
    // ═══════════════════════════════════════════════════════════════

    /// Code blocks
    static let code = Font.system(size: 14, weight: .regular, design: .monospaced)

    /// Inline code
    static let codeSmall = Font.system(size: 13, weight: .regular, design: .monospaced)

    // ═══════════════════════════════════════════════════════════════
    // SPACING - Cognitive science-backed line heights
    // 1.5-1.55x line height reduces eye strain during extended reading
    // ═══════════════════════════════════════════════════════════════

    /// Body text line spacing (~1.55x line height)
    static let bodyLineSpacing: CGFloat = 6

    /// Title line spacing
    static let titleLineSpacing: CGFloat = 4

    /// Paragraph spacing (visual breathing room)
    static let paragraphSpacing: CGFloat = 12

    // ═══════════════════════════════════════════════════════════════
    // READING OPTIMIZATION
    // 65-75 characters per line is optimal for reading flow
    // ═══════════════════════════════════════════════════════════════

    /// Optimal content width for reading flow
    static let optimalReadingWidth: CGFloat = 680

    /// Minimum content width
    static let minReadingWidth: CGFloat = 400

    /// Maximum content width (for very wide screens)
    static let maxReadingWidth: CGFloat = 800
}

// MARK: - Mention Colors (High Contrast for Light Backgrounds)
/// Entity-specific colors for @mentions — bespoke palette for light mode
/// Based on color psychology principles for cognitive association
struct CosmoMentionColors {
    // ═══════════════════════════════════════════════════════════════
    // TEXT COLORS - Saturated for readability on white
    // ═══════════════════════════════════════════════════════════════

    /// Idea - Muted indigo
    static let idea = Color(hex: "6B6EA8")

    /// Content - Slate blue
    static let content = Color(hex: "5B84B0")

    /// Task - Dusty rose
    static let task = Color(hex: "B06B6B")

    /// Research - Forest teal
    static let research = Color(hex: "4A8B72")

    /// Connection - Soft purple
    static let connection = Color(hex: "8B6BAB")

    /// Note - Warm umber
    static let note = Color(hex: "9B8A6E")

    /// Cosmo AI - Forest green
    static let cosmoAI = Color(hex: "2D6A4F")

    /// Project - Muted indigo
    static let project = Color(hex: "6B6EA8")

    /// Swipe File - Warm bronze
    static let swipeFile = Color(hex: "B08C5A")

    /// Sticky Note - Warm yellow
    static let stickyNote = Color(hex: "D4C36A")

    /// Default fallback
    static let defaultColor = Color(hex: "6B6B78")

    // ═══════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// Get mention color for entity type
    static func color(for type: EntityType) -> Color {
        switch type {
        case .idea: return idea
        case .content: return content
        case .task: return task
        case .research: return research
        case .connection: return connection
        case .note: return note
        case .cosmo, .cosmoAI: return cosmoAI
        case .project: return project
        case .swipeFile: return swipeFile
        case .stickyNote: return stickyNote
        // Inquiry Workspace — portals lean indigo/purple, sessions accent
        case .deepDive: return Color(hex: "8B6BAB")
        case .inquirySession: return DS.accent
        default: return defaultColor
        }
    }

    /// Get light background color for mention pills
    static func pillBackground(for type: EntityType) -> Color {
        color(for: type).opacity(0.12)
    }

    /// Get NSColor for TextKit integration
    static func nsColor(for type: EntityType) -> NSColor {
        NSColor(color(for: type))
    }
}

// MARK: - Legacy CosmoTheme (for backwards compatibility)
struct CosmoTheme {
    struct Colors {
        // Backgrounds - warm parchment palette
        static let background = CosmoColors.softWhite
        static let secondaryBackground = CosmoColors.mistGrey
        static let tertiaryBackground = CosmoColors.glassGrey
        static let canvasBackground = CosmoColors.canvasBackground
        static let blockBackground = Color.white

        // Text
        static let text = CosmoColors.textPrimary
        static let secondaryText = CosmoColors.textSecondary
        static let tertiaryText = CosmoColors.textTertiary

        // System
        static let accent = CosmoColors.lavender
        static let success = CosmoColors.emerald
        static let warning = CosmoColors.amber
        static let error = CosmoColors.softRed

        // Entity colors (bespoke palette)
        static let ideaColor = CosmoColors.idea
        static let contentColor = CosmoColors.content
        static let connectionColor = Color(hex: "8B6BAB")
        static let researchColor = CosmoColors.research
        static let taskColor = CosmoColors.task
        static let projectColor = CosmoColors.idea
        static let noteColor = CosmoColors.note
        static let cosmoColor = CosmoColors.cosmoAI

        // AI States
        static let aiIdle = CosmoColors.glassGrey
        static let aiThinking = CosmoColors.lavender
        static let aiResearch = CosmoColors.coral
        static let aiComplete = CosmoColors.emerald
        static let aiError = CosmoColors.softRed

        // Pastels for canvas blocks
        static let pastelPurple = Color(hex: "8B6BAB").opacity(0.15)
        static let pastelBlue = Color(hex: "5B84B0").opacity(0.15)
        static let pastelGreen = Color(hex: "4A8B72").opacity(0.15)
        static let pastelPink = Color(hex: "B06B6B").opacity(0.15)
        static let pastelYellow = Color(hex: "9B8A6E").opacity(0.15)
        static let pastelOrange = Color(hex: "B08C5A").opacity(0.15)
        static let pastelCyan = Color(hex: "5B84B0").opacity(0.15)

        // Gradients
        static let cosmicGradient = CosmoColors.aiGradient
        static let aiThinkingGradient = CosmoColors.aiGradient
        static let aiResearchGradient = CosmoColors.warmGradient
    }

    // MARK: - Typography
    struct Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.medium)
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2

        // Custom sizes
        static func custom(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
    }

    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    struct CornerRadius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let pill: CGFloat = 9999
    }

    // MARK: - Shadows
    struct Shadows {
        static func small(_ color: Color = .black) -> some View {
            Color.clear.shadow(color: color.opacity(0.06), radius: 4, x: 0, y: 2)
        }

        static func medium(_ color: Color = .black) -> some View {
            Color.clear.shadow(color: color.opacity(0.08), radius: 10, x: 0, y: 5)
        }

        static func large(_ color: Color = .black) -> some View {
            Color.clear.shadow(color: color.opacity(0.10), radius: 20, x: 0, y: 10)
        }

        static func glow(_ color: Color) -> some View {
            Color.clear.shadow(color: color.opacity(0.3), radius: 20, x: 0, y: 0)
        }
    }

    // MARK: - Animations (MAGICAL!)
    struct Animations {
        // Spring animations for that premium feel
        static let springSnappy = Animation.spring(response: 0.2, dampingFraction: 0.8)
        static let springBouncy = Animation.spring(response: 0.3, dampingFraction: 0.6)
        static let springSmooth = Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let springGentle = Animation.spring(response: 0.5, dampingFraction: 0.8)

        // Standard animations
        static let easeOutFast = Animation.easeOut(duration: 0.15)
        static let easeOutMedium = Animation.easeOut(duration: 0.25)
        static let easeOutSlow = Animation.easeOut(duration: 0.4)

        static let easeInFast = Animation.easeIn(duration: 0.1)
        static let easeInMedium = Animation.easeIn(duration: 0.2)

        // Interactive animations
        static let interactiveSpring = Animation.interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.25)

        // Delayed stagger for lists
        static func staggered(index: Int, baseDelay: Double = 0.03) -> Animation {
            .spring(response: 0.3, dampingFraction: 0.7).delay(Double(index) * baseDelay)
        }
    }
}

// MARK: - Block Animations (Premium Floating Block Springs)
/// Specialized animations for floating blocks on the canvas.
/// These animations are tuned for smooth, Apple-grade block interactions.
struct BlockAnimations {
    /// Expansion spring - snappy but not jarring (0.35s response)
    static let expand = Animation.spring(response: 0.35, dampingFraction: 0.75)

    /// Collapse spring - slightly faster (0.25s response)
    static let collapse = Animation.spring(response: 0.25, dampingFraction: 0.8)

    /// Hover lift - quick and subtle (0.15s response)
    static let hover = Animation.spring(response: 0.15, dampingFraction: 0.9)

    /// Glow pulse - slow and gentle
    static let glowPulse = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)

    /// Content fade - for expansion content transitions
    static let contentFade = Animation.easeInOut(duration: 0.2)

    /// Pop in - for block appearance on canvas
    static let popIn = Animation.spring(response: 0.4, dampingFraction: 0.7)

    /// Pop out - for block removal from canvas
    static let popOut = Animation.easeOut(duration: 0.15)

    /// Staggered entry for list items within blocks
    static func staggered(index: Int, baseDelay: Double = 0.05) -> Animation {
        .spring(response: 0.3, dampingFraction: 0.7).delay(Double(index) * baseDelay)
    }

    /// Drag feedback - immediate response during drag
    static let dragFeedback = Animation.interactiveSpring(response: 0.15, dampingFraction: 0.9, blendDuration: 0.1)

    /// Selection highlight - quick toggle for selection state
    static let selection = Animation.spring(response: 0.2, dampingFraction: 0.85)
}

// MARK: - Voice Command Animations (LLM-First Architecture)
/// Animations optimized for voice-triggered actions.
struct VoiceAnimations {
    static let create = Animation.spring(response: 0.35, dampingFraction: 0.75)
    static let expand = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let move = Animation.spring(response: 0.5, dampingFraction: 0.75)
    static let delete = Animation.easeOut(duration: 0.25)
    static let arrange = Animation.spring(response: 0.3, dampingFraction: 0.7)

    static func searchResult(index: Int) -> Animation {
        .spring(response: 0.35, dampingFraction: 0.75)
        .delay(Double(index) * 0.08)
    }

    static let place = Animation.spring(response: 0.4, dampingFraction: 0.7)
}

// MARK: - ProMotion Springs (120Hz Optimized)
/// Apple Silicon native springs tuned for 120Hz ProMotion displays.
struct ProMotionSprings {
    // CORE INTERACTIONS
    static let snappy = Animation.spring(response: 0.12, dampingFraction: 0.82)
    static let bouncy = Animation.spring(response: 0.25, dampingFraction: 0.68, blendDuration: 0.08)
    static let gentle = Animation.spring(response: 0.35, dampingFraction: 0.85)

    // HOVER & PRESS
    static let hover = Animation.spring(response: 0.15, dampingFraction: 0.78)
    static let press = Animation.spring(response: 0.08, dampingFraction: 0.92)
    static let release = Animation.spring(response: 0.2, dampingFraction: 0.72)

    // SIDEBAR
    static let sidebar = Animation.spring(response: 0.28, dampingFraction: 0.92)

    // CONTENT TRANSITIONS
    static let cardEntrance = Animation.spring(response: 0.4, dampingFraction: 0.75)
    static let menuAppear = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let focusTransition = Animation.spring(response: 0.3, dampingFraction: 0.82)
    static let modal = Animation.spring(response: 0.35, dampingFraction: 0.8)

    // WORLD-SWITCHING
    static let worldExit = Animation.spring(response: 0.35, dampingFraction: 0.88)
    static let worldEnter = Animation.spring(response: 0.45, dampingFraction: 0.82)
    static let worldSwitch = Animation.spring(response: 0.4, dampingFraction: 0.85)

    // STAGGER HELPERS
    static func staggered(index: Int, baseDelay: TimeInterval = 0.03) -> Animation {
        cardEntrance.delay(Double(index) * baseDelay)
    }
    static func cascade(index: Int) -> Animation {
        menuAppear.delay(Double(index) * 0.025)
    }
}

// MARK: - CosmoShadows (Light Mode Shadow System)
/// Soft, natural shadows for light backgrounds.
/// Shadows follow Apple's HIG: subtle, directional, purposeful.
struct CosmoShadows {

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    enum Elevation {
        case resting
        case hovered
        case pressed
        case dragging
    }

    static func ambient(color: Color = .black, intensity: CGFloat = 1.0) -> Shadow {
        Shadow(color: color.opacity(0.03 * intensity), radius: 2, x: 0, y: 1)
    }

    static func direct(color: Color = .black, intensity: CGFloat = 1.0) -> Shadow {
        Shadow(color: color.opacity(0.05 * intensity), radius: 8, x: 0, y: 4)
    }

    static func softFill(color: Color = .black, intensity: CGFloat = 1.0) -> Shadow {
        Shadow(color: color.opacity(0.03 * intensity), radius: 20, x: 0, y: 8)
    }
}

// MARK: - Shadow View Extensions

extension View {
    /// Apply card-level shadow with elevation state
    @ViewBuilder
    func cardShadow(elevation: CosmoShadows.Elevation, accent: Color? = nil) -> some View {
        let intensity: CGFloat = {
            switch elevation {
            case .resting: return 1.0
            case .hovered: return 1.5
            case .pressed: return 0.8
            case .dragging: return 2.0
            }
        }()

        let yOffset: CGFloat = {
            switch elevation {
            case .resting: return 0
            case .hovered: return -1
            case .pressed: return 1
            case .dragging: return -2
            }
        }()

        self
            // Layer 1: Ambient
            .shadow(color: .black.opacity(0.02 * intensity), radius: 1, x: 0, y: 1)
            // Layer 2: Direct
            .shadow(color: .black.opacity(0.04 * intensity), radius: 6 * intensity, x: 0, y: 3 + yOffset)
            // Layer 3: Soft fill
            .shadow(
                color: (accent ?? .black).opacity(0.02 * intensity),
                radius: 16 * intensity,
                x: 0,
                y: 6 + yOffset
            )
    }

    /// Apply floating block shadow with elevation state
    @ViewBuilder
    func floatingShadow(elevation: CosmoShadows.Elevation, accent: Color? = nil) -> some View {
        let values: (ambientOpacity: CGFloat, directRadius: CGFloat, directY: CGFloat, fillRadius: CGFloat, fillY: CGFloat) = {
            switch elevation {
            case .resting:
                return (0.03, 10, 5, 24, 10)
            case .hovered:
                return (0.04, 14, 7, 32, 14)
            case .pressed:
                return (0.02, 8, 4, 20, 8)
            case .dragging:
                return (0.05, 20, 12, 44, 20)
            }
        }()

        self
            .shadow(color: .black.opacity(values.ambientOpacity), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.06), radius: values.directRadius, x: 0, y: values.directY)
            .shadow(
                color: (accent ?? .black).opacity(0.03),
                radius: values.fillRadius,
                x: 0,
                y: values.fillY
            )
    }

    /// Apply focused element shadow with accent glow
    @ViewBuilder
    func focusedShadow(accent: Color) -> some View {
        self
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
            .shadow(color: accent.opacity(0.12), radius: 24, x: 0, y: 8)
    }
}

// MARK: - Shadow Style API
extension View {
    @ViewBuilder
    func cosmoShadow(_ style: CosmoShadowStyle, accent: Color? = nil) -> some View {
        switch style {
        case .card:
            self.cardShadow(elevation: .resting, accent: accent)
        case .cardHovered:
            self.cardShadow(elevation: .hovered, accent: accent)
        case .floating:
            self.floatingShadow(elevation: .resting, accent: accent)
        case .floatingHovered:
            self.floatingShadow(elevation: .hovered, accent: accent)
        case .dragging:
            self.floatingShadow(elevation: .dragging, accent: accent)
        case .focused(let accentColor):
            self.focusedShadow(accent: accentColor)
        }
    }
}

enum CosmoShadowStyle {
    case card
    case cardHovered
    case floating
    case floatingHovered
    case dragging
    case focused(Color)
}

// MARK: - Focus Mode Animations (Thinking Canvas)
struct FocusModeAnimations {
    // ENTRY
    static let backgroundEntry = Animation.spring(response: 0.4, dampingFraction: 0.75)
    static let editorEntry = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let vignetteEntry = Animation.easeOut(duration: 0.6)

    // EXIT
    static let exit = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let editorExit = Animation.easeIn(duration: 0.2)

    // ORBITING BLOCKS
    static func orbitingEntry(index: Int) -> Animation {
        .spring(response: 0.4, dampingFraction: 0.7).delay(0.1 + Double(index) * 0.05)
    }
    static let orbitingHover = Animation.spring(response: 0.15, dampingFraction: 0.8)
    static let orbitingSnapBack = Animation.spring(response: 0.3, dampingFraction: 0.7)

    // FOCUS BLOCKS
    static let focusBlockPlace = Animation.spring(response: 0.35, dampingFraction: 0.65)
    static let focusBlockRemove = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let focusBlockSelect = Animation.spring(response: 0.2, dampingFraction: 0.85)

    // MENTIONS
    static let mentionInsert = Animation.spring(response: 0.2, dampingFraction: 0.8)
    static let shimmerSweep = Animation.easeInOut(duration: 0.5)
    static let sparkleDisperse = Animation.easeOut(duration: 0.6)

    // MENUS
    static let menuAppear = Animation.spring(response: 0.2, dampingFraction: 0.8)
    static let menuDismiss = Animation.easeOut(duration: 0.15)
    static let menuItemHover = Animation.easeOut(duration: 0.1)
}

// MARK: - Focus Mode View Modifiers
extension View {
    func focusModeEntry(_ isAppearing: Bool) -> some View {
        self
            .scaleEffect(isAppearing ? 1.0 : 0.98)
            .opacity(isAppearing ? 1.0 : 0)
            .animation(FocusModeAnimations.backgroundEntry, value: isAppearing)
    }

    func editorEntry(_ isVisible: Bool, delay: Double = 0.1) -> some View {
        self
            .offset(y: isVisible ? 0 : 30)
            .opacity(isVisible ? 1.0 : 0)
            .animation(FocusModeAnimations.editorEntry.delay(delay), value: isVisible)
    }

    func orbitingBlockEntry(_ isVisible: Bool, index: Int) -> some View {
        self
            .offset(x: isVisible ? 0 : (index % 2 == 0 ? -50 : 50))
            .opacity(isVisible ? 1.0 : 0)
            .animation(FocusModeAnimations.orbitingEntry(index: index), value: isVisible)
    }

    /// Hover effect for focus mode blocks — shadow lift, not scale
    func focusBlockHover(_ isHovered: Bool, entityColor: Color) -> some View {
        self
            .shadow(
                color: entityColor.opacity(isHovered ? 0.15 : 0.05),
                radius: isHovered ? 16 : 8,
                y: isHovered ? 6 : 3
            )
            .animation(FocusModeAnimations.orbitingHover, value: isHovered)
    }
}

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers for Consistent Styling

extension View {
    /// Apply cosmic glow effect (for AI blocks, selected items)
    func cosmicGlow(_ color: Color, intensity: CGFloat = 0.2) -> some View {
        self
            .shadow(color: color.opacity(intensity), radius: 12, x: 0, y: 0)
            .shadow(color: color.opacity(intensity * 0.4), radius: 24, x: 0, y: 0)
    }

    /// Subtle hover shadow effect (NOT scale — shadow lift only)
    func hoverScale(_ isHovered: Bool, scale: CGFloat = 1.02) -> some View {
        self
            .shadow(
                color: .black.opacity(isHovered ? 0.06 : 0.03),
                radius: isHovered ? 12 : 6,
                y: isHovered ? 4 : 2
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
    }

    /// Card style with white bg and soft shadow
    func cardStyle(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DS.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
    }

    /// AI state border
    func aiStateBorder(color: Color, isActive: Bool = false) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(isActive ? 0.6 : 0.2), lineWidth: isActive ? 2 : 1)
            )
    }

    /// Pulsing effect for processing states
    func pulsingOpacity(isActive: Bool) -> some View {
        self
            .opacity(isActive ? 0.7 : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: isActive
            )
    }
}

// MARK: - Button Styles
// Note: Custom ButtonStyles removed due to compilation issues
// Use standard SwiftUI modifiers instead

// EntityType color and icon are defined in CosmoApp.swift

// MARK: - Cosmo Notification Names
extension Notification.Name {
    static let cosmoEditorKeystroke = Notification.Name("cosmo.editor.keystroke")
    static let cosmoBlockFocused = Notification.Name("cosmo.block.focused")
    static let cosmoBlockBlurred = Notification.Name("cosmo.block.blurred")
    static let cosmoSaveCompleted = Notification.Name("cosmo.save.completed")
    static let cosmoEntityCreated = Notification.Name("cosmo.entity.created")
    static let cosmoEntityDeleted = Notification.Name("cosmo.entity.deleted")
}

// MARK: - 3D Tilt Effect Views

struct GeometricTiltView<Content: View>: View {
    var maxTilt: Double
    var perspective: CGFloat
    var content: Content

    @State private var isHovered = false
    @State private var normalizedPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)

    init(maxTilt: Double = 2.5, perspective: CGFloat = 0.6, @ViewBuilder content: () -> Content) {
        self.maxTilt = maxTilt
        self.perspective = perspective
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .rotation3DEffect(
                    .degrees(isHovered ? maxTilt : 0),
                    axis: (
                        x: (normalizedPosition.y - 0.5) * -2,
                        y: (normalizedPosition.x - 0.5) * 2,
                        z: 0
                    ),
                    perspective: perspective
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        withAnimation(ProMotionSprings.hover) {
                            isHovered = true
                            normalizedPosition = CGPoint(
                                x: location.x / geometry.size.width,
                                y: location.y / geometry.size.height
                            )
                        }
                    case .ended:
                        withAnimation(ProMotionSprings.hover) {
                            isHovered = false
                            normalizedPosition = CGPoint(x: 0.5, y: 0.5)
                        }
                    }
                }
        }
    }
}

extension View {
    func cosmoTilt(maxTilt: Double = 2.5, perspective: CGFloat = 0.6) -> some View {
        GeometricTiltView(maxTilt: maxTilt, perspective: perspective) {
            self
        }
    }

    func cosmoTiltSimple(_ isHovered: Bool, amount: Double = 2.0) -> some View {
        self.rotation3DEffect(
            .degrees(isHovered ? amount : 0),
            axis: (x: -0.5, y: 1, z: 0),
            perspective: 0.6
        )
    }
}
