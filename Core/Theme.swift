// CosmoOS/Core/Theme.swift
// Design system and theming for Cosmo OS
// "Pastel Spatial Minimalism" - Calm, airy, cognitive sanctuary

import SwiftUI
import AppKit
import GRDB

// MARK: - CosmoColors (Primary Palette)
// The soul of CosmoOS - soft, calm, breathable
struct CosmoColors {
    // ═══════════════════════════════════════════════════════════════
    // BASE LAYER - The soul of the OS
    // ═══════════════════════════════════════════════════════════════

    /// Soft Off-White (#F7F7F5)
    /// Think: sunlight hitting a blank page at 8 a.m.
    /// Warm, clean, breathable. The perfect neutral for thinking.
    static let softWhite = Color(hex: "F7F7F5")

    /// Canvas background - same as softWhite
    static let canvasBackground = softWhite
    static let background = softWhite
    static let cardBackground = softWhite

    // ═══════════════════════════════════════════════════════════════
    // DEPTH LAYER - Structural shadows
    // ═══════════════════════════════════════════════════════════════

    /// Mist Grey (#E3E4E8) - Barely-there shadows
    static let mistGrey = Color(hex: "E3E4E8")
    static let slate = Color(hex: "64748B") // Slate 500

    /// Glass Grey (#D7D9DE) - Translucent depth

    /// Glass Grey (#D7D9DE) - Translucent depth
    /// Everything feels like it's floating just a little
    static let glassGrey = Color(hex: "D7D9DE")

    // ═══════════════════════════════════════════════════════════════
    // ENERGY ACCENTS - The "thinking glow"
    // Use extremely sparingly - cognitive signals, not decorations
    // ═══════════════════════════════════════════════════════════════

    /// Pastel Sky Blue (#A8CCE8) - "Clarity"
    /// Use for: selected states, hovering, active ideas
    static let skyBlue = Color(hex: "A8CCE8")

    /// Pastel Lavender (#CAB8E8) - "Imagination"
    /// Use for: generative elements, AI actions, semantic pulls
    static let lavender = Color(hex: "CAB8E8")

    /// Soft Coral (#F4AFA0) - "Attention Focus"
    /// Use for: recording indicators, voice-active states, capture mode
    static let coral = Color(hex: "F4AFA0")

    // ═══════════════════════════════════════════════════════════════
    // STATUS COLORS
    // ═══════════════════════════════════════════════════════════════

    /// Muted Emerald (#8FC7A2) - Success/Complete
    /// The feeling of a breath landing fully in your chest
    static let emerald = Color(hex: "8FC7A2")
    static let mint = emerald
    static let amber = Color.orange.opacity(0.8) // Approximation or define specific hex
    
    /// Soft Red (#E69A9A) - Warning/Danger
    /// Warm, not aggressive. Guiding back to clarity.
    static let softRed = Color(hex: "E69A9A")

    // ═══════════════════════════════════════════════════════════════
    // TEXT COLORS
    // ═══════════════════════════════════════════════════════════════

    /// Primary text - dark but not harsh
    static let textPrimary = Color(hex: "2D2D2D")

    /// Secondary text - softer
    static let textSecondary = Color(hex: "6B6B6B")

    /// Tertiary text - hints and placeholders
    static let textTertiary = Color(hex: "9B9B9B")

    // ═══════════════════════════════════════════════════════════════
    // ENTITY COLORS (Pastel versions)
    // ═══════════════════════════════════════════════════════════════

    /// Idea - Lavender tint
    static let idea = lavender

    /// Content - Sky blue tint
    static let content = skyBlue

    /// Task - Coral tint
    static let task = coral

    /// Research - Emerald tint
    static let research = emerald

    /// Note - Light yellow
    static let note = Color(hex: "F5E6C8")

    /// Cosmo AI - Deeper lavender
    static let cosmoAI = Color(hex: "B8A0D8")

    // ═══════════════════════════════════════════════════════════════
    // THINKSPACE DARK MODE - Vast cognitive void
    // Matching Sanctuary aesthetic for immersive thinking
    // ═══════════════════════════════════════════════════════════════

    /// Deep void black (#0A0A0F) - Primary dark background
    /// The infinite canvas, vast and calm
    static let thinkspaceVoid = Color(hex: "0A0A0F")

    /// Secondary dark (#12121A) - Slightly lifted surfaces
    static let thinkspaceSecondary = Color(hex: "12121A")

    /// Tertiary dark (#1A1A25) - Block backgrounds, glass base
    static let thinkspaceTertiary = Color(hex: "1A1A25")

    /// Dark grid color (#3A3A45) - Subtle grid dots
    static let thinkspaceGrid = Color(hex: "3A3A45")

    /// Purple accent for shadows (#8B5CF6) - Sanctuary purple
    static let thinkspacePurple = Color(hex: "8B5CF6")

    /// Block accent colors (dark mode versions)
    static let blockNote = Color(hex: "F97316")       // Orange
    static let blockContent = Color(hex: "3B82F6")    // Blue
    static let blockResearch = Color(hex: "10B981")   // Green
    static let blockConnection = Color(hex: "8B5CF6") // Purple

    // ═══════════════════════════════════════════════════════════════
    // GRADIENTS - Soft, airy transitions
    // ═══════════════════════════════════════════════════════════════

    static let aiGradient = LinearGradient(
        colors: [lavender, skyBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGradient = LinearGradient(
        colors: [coral, Color(hex: "F5D0C8")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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
    // 1.5-1.7x line height reduces eye strain during extended reading
    // ═══════════════════════════════════════════════════════════════

    /// Body text line spacing (~1.5x line height)
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

// MARK: - Mention Colors (High Contrast for White Backgrounds)
/// Entity-specific colors for @mentions - darker/saturated for text visibility
/// Based on color psychology principles for cognitive association
struct CosmoMentionColors {
    // ═══════════════════════════════════════════════════════════════
    // TEXT COLORS - Darker, saturated for readability on white
    // ═══════════════════════════════════════════════════════════════

    /// Idea - Warm amber/gold (creativity, inspiration, "lightbulb" warmth)
    static let idea = Color(hex: "B8860B")

    /// Content - Strong blue (focus, clarity, depth)
    static let content = Color(hex: "2B6CB0")

    /// Task - Strong coral/red (energy, action, urgency without stress)
    static let task = Color(hex: "C53030")

    /// Research - Strong green (growth, discovery, knowledge)
    static let research = Color(hex: "276749")

    /// Connection - Strong purple (wisdom, linking, neural connections)
    static let connection = Color(hex: "6B46C1")

    /// Note - Dark gold (memory, quick capture)
    static let note = Color(hex: "975A16")

    /// Cosmo AI - Deep violet (intelligence, insight, magic)
    static let cosmoAI = Color(hex: "553C9A")

    /// Project - Indigo (organization, structure)
    static let project = Color(hex: "4338CA")

    /// Default fallback
    static let defaultColor = Color(hex: "4A5568")

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
        // Backgrounds - now using pastel palette
        static let background = CosmoColors.softWhite
        static let secondaryBackground = CosmoColors.mistGrey
        static let tertiaryBackground = CosmoColors.glassGrey
        static let canvasBackground = CosmoColors.canvasBackground
        static let blockBackground = CosmoColors.glassGrey.opacity(0.3)

        // Text
        static let text = CosmoColors.textPrimary
        static let secondaryText = CosmoColors.textSecondary
        static let tertiaryText = CosmoColors.textTertiary

        // System
        static let accent = CosmoColors.lavender
        static let success = CosmoColors.emerald
        static let warning = CosmoColors.coral
        static let error = CosmoColors.softRed

        // Entity colors (pastel)
        static let ideaColor = CosmoColors.idea
        static let contentColor = CosmoColors.content
        static let connectionColor = CosmoColors.coral
        static let researchColor = CosmoColors.research
        static let taskColor = CosmoColors.task
        static let projectColor = CosmoColors.lavender
        static let noteColor = CosmoColors.note
        static let cosmoColor = CosmoColors.cosmoAI

        // AI States
        static let aiIdle = CosmoColors.glassGrey
        static let aiThinking = CosmoColors.lavender
        static let aiResearch = CosmoColors.coral
        static let aiComplete = CosmoColors.emerald
        static let aiError = CosmoColors.softRed

        // Pastels for canvas blocks
        static let pastelPurple = CosmoColors.lavender.opacity(0.5)
        static let pastelBlue = CosmoColors.skyBlue.opacity(0.5)
        static let pastelGreen = CosmoColors.emerald.opacity(0.5)
        static let pastelPink = CosmoColors.coral.opacity(0.5)
        static let pastelYellow = CosmoColors.note.opacity(0.5)
        static let pastelOrange = CosmoColors.coral.opacity(0.6)
        static let pastelCyan = CosmoColors.skyBlue.opacity(0.6)

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
            Color.clear.shadow(color: color.opacity(0.1), radius: 4, x: 0, y: 2)
        }

        static func medium(_ color: Color = .black) -> some View {
            Color.clear.shadow(color: color.opacity(0.15), radius: 10, x: 0, y: 5)
        }

        static func large(_ color: Color = .black) -> some View {
            Color.clear.shadow(color: color.opacity(0.2), radius: 20, x: 0, y: 10)
        }

        static func glow(_ color: Color) -> some View {
            Color.clear.shadow(color: color.opacity(0.5), radius: 20, x: 0, y: 0)
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
    /// Used when a block expands inline on the canvas
    static let expand = Animation.spring(response: 0.35, dampingFraction: 0.75)

    /// Collapse spring - slightly faster (0.25s response)
    /// Used when a block collapses back to normal size
    static let collapse = Animation.spring(response: 0.25, dampingFraction: 0.8)

    /// Hover lift - quick and subtle (0.15s response)
    /// Used for hover effects on blocks
    static let hover = Animation.spring(response: 0.15, dampingFraction: 0.9)

    /// Glow pulse - slow and gentle
    /// Used for ambient glow effects on blocks
    static let glowPulse = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)

    /// Content fade - for expansion content transitions
    /// Used when content appears/disappears during expansion
    static let contentFade = Animation.easeInOut(duration: 0.2)

    /// Pop in - for block appearance on canvas
    /// Used when blocks are added to the canvas
    static let popIn = Animation.spring(response: 0.4, dampingFraction: 0.7)

    /// Pop out - for block removal from canvas
    /// Used when blocks are removed from the canvas
    static let popOut = Animation.easeOut(duration: 0.15)

    /// Staggered entry for list items within blocks
    /// Used for animated lists inside expanded blocks
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
/// All voice actions should feel instant yet smooth.
struct VoiceAnimations {
    /// Create/Appear - quick pop-in for newly created blocks
    static let create = Animation.spring(response: 0.35, dampingFraction: 0.75)

    /// Expand/Resize - smooth stretch for block/event expansion
    static let expand = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// Move/Reposition - fluid glide for moving items
    static let move = Animation.spring(response: 0.5, dampingFraction: 0.75)

    /// Delete/Fade - gentle fade out
    static let delete = Animation.easeOut(duration: 0.25)

    /// Arrange Pattern - for bulk arrangement animations
    static let arrange = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Search result placement - staggered cascade
    static func searchResult(index: Int) -> Animation {
        .spring(response: 0.35, dampingFraction: 0.75)
        .delay(Double(index) * 0.08)
    }

    /// Canvas placement - for placing blocks from voice commands
    static let place = Animation.spring(response: 0.4, dampingFraction: 0.7)
}

// MARK: - ProMotion Springs (120Hz Optimized)
/// Apple Silicon native springs tuned for 120Hz ProMotion displays.
/// Response values calibrated for buttery-smooth frame interpolation.
/// December 2025 - Cutting-edge SwiftUI animation performance.
struct ProMotionSprings {
    // ═══════════════════════════════════════════════════════════════
    // CORE INTERACTIONS - Sub-frame response times
    // ═══════════════════════════════════════════════════════════════

    /// Snappy (0.12s) - Immediate feedback for taps, toggles
    /// 120Hz allows tighter response without choppiness
    static let snappy = Animation.spring(response: 0.12, dampingFraction: 0.82)

    /// Bouncy (0.25s) - Playful bounce for emphasis
    /// Slight overshoot creates delight without feeling slow
    static let bouncy = Animation.spring(response: 0.25, dampingFraction: 0.68, blendDuration: 0.08)

    /// Gentle (0.35s) - Smooth, relaxed transitions
    /// For background changes, ambient effects
    static let gentle = Animation.spring(response: 0.35, dampingFraction: 0.85)

    // ═══════════════════════════════════════════════════════════════
    // HOVER & PRESS - Micro-interaction refinement
    // ═══════════════════════════════════════════════════════════════

    /// Hover (0.15s) - Quick response to cursor entry
    /// Fast enough to feel instant, smooth enough to not flash
    static let hover = Animation.spring(response: 0.15, dampingFraction: 0.78)

    /// Press (0.08s) - Immediate tactile feedback
    /// Must feel like touching glass
    static let press = Animation.spring(response: 0.08, dampingFraction: 0.92)

    /// Release (0.2s) - Slightly slower return from press
    /// Creates satisfying "snap back" feel
    static let release = Animation.spring(response: 0.2, dampingFraction: 0.72)

    // ═══════════════════════════════════════════════════════════════
    // CONTENT TRANSITIONS - Larger movements
    // ═══════════════════════════════════════════════════════════════

    /// Card entrance (0.4s) - Elegant appearance for cards/blocks
    /// Includes subtle overshoot for premium feel
    static let cardEntrance = Animation.spring(response: 0.4, dampingFraction: 0.75)

    /// Menu appear (0.25s) - Context menus, dropdowns
    /// Quick but not jarring
    static let menuAppear = Animation.spring(response: 0.25, dampingFraction: 0.8)

    /// Focus transition (0.3s) - Focus mode entry/exit
    /// Cinematic but not sluggish
    static let focusTransition = Animation.spring(response: 0.3, dampingFraction: 0.82)

    /// Modal (0.35s) - Full-screen overlays
    static let modal = Animation.spring(response: 0.35, dampingFraction: 0.8)

    // ═══════════════════════════════════════════════════════════════
    // WORLD-SWITCHING TRANSITIONS - Core space navigation
    // ═══════════════════════════════════════════════════════════════

    /// World exit (0.35s) - Current space recedes into the abyss
    /// Smooth scale-down with fade, like falling away
    static let worldExit = Animation.spring(response: 0.35, dampingFraction: 0.88)

    /// World enter (0.45s) - New space emerges from the abyss
    /// Slightly slower for dramatic emergence effect
    static let worldEnter = Animation.spring(response: 0.45, dampingFraction: 0.82)

    /// World switch (0.4s) - Combined transition for simultaneous switch
    /// Balanced timing for parallel fade/scale
    static let worldSwitch = Animation.spring(response: 0.4, dampingFraction: 0.85)

    // ═══════════════════════════════════════════════════════════════
    // STAGGER HELPERS - Choreographed sequences
    // ═══════════════════════════════════════════════════════════════

    /// Staggered list items (30ms between each)
    static func staggered(index: Int, baseDelay: TimeInterval = 0.03) -> Animation {
        cardEntrance.delay(Double(index) * baseDelay)
    }

    /// Cascade for menu items (25ms, faster)
    static func cascade(index: Int) -> Animation {
        menuAppear.delay(Double(index) * 0.025)
    }
}

// MARK: - CosmoShadows (Multi-Layer Depth System)
/// Apple-grade shadow system with three conceptual layers:
/// 1. Ambient - Always present, very soft (simulates ambient occlusion)
/// 2. Direct - Main shadow from overhead light source
/// 3. Soft Fill - Large, diffuse glow for depth
///
/// Shadows follow Apple's HIG: subtle, directional, purposeful.
struct CosmoShadows {
    // ═══════════════════════════════════════════════════════════════
    // SHADOW COMPONENTS - Building blocks
    // ═══════════════════════════════════════════════════════════════

    /// Ambient shadow - contact shadow, always present
    static func ambient(color: Color = .black, intensity: CGFloat = 1.0) -> Shadow {
        Shadow(color: color.opacity(0.04 * intensity), radius: 2, x: 0, y: 1)
    }

    /// Direct shadow - main light source (top-center)
    static func direct(color: Color = .black, intensity: CGFloat = 1.0) -> Shadow {
        Shadow(color: color.opacity(0.08 * intensity), radius: 8, x: 0, y: 4)
    }

    /// Soft fill shadow - large diffuse glow
    static func softFill(color: Color = .black, intensity: CGFloat = 1.0) -> Shadow {
        Shadow(color: color.opacity(0.05 * intensity), radius: 20, x: 0, y: 8)
    }

    // ═══════════════════════════════════════════════════════════════
    // SHADOW DATA TYPE
    // ═══════════════════════════════════════════════════════════════

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
}

// MARK: - Shadow View Extensions

extension View {
    /// Apply card-level 3-layer shadow with elevation state
    @ViewBuilder
    func cardShadow(elevation: CosmoShadows.Elevation, accent: Color? = nil) -> some View {
        let intensity: CGFloat = {
            switch elevation {
            case .resting: return 1.0
            case .hovered: return 1.3
            case .pressed: return 0.8
            case .dragging: return 1.6
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
            .shadow(color: .black.opacity(0.03 * intensity), radius: 1, x: 0, y: 1)
            // Layer 2: Direct
            .shadow(color: .black.opacity(0.06 * intensity), radius: 6 * intensity, x: 0, y: 3 + yOffset)
            // Layer 3: Soft fill (with optional accent)
            .shadow(
                color: (accent ?? .black).opacity(0.04 * intensity),
                radius: 16 * intensity,
                x: 0,
                y: 6 + yOffset
            )
    }

    /// Apply floating block 3-layer shadow with elevation state
    @ViewBuilder
    func floatingShadow(elevation: CosmoShadows.Elevation, accent: Color? = nil) -> some View {
        let values: (ambientOpacity: CGFloat, directRadius: CGFloat, directY: CGFloat, fillRadius: CGFloat, fillY: CGFloat) = {
            switch elevation {
            case .resting:
                return (0.04, 10, 5, 24, 10)
            case .hovered:
                return (0.05, 14, 7, 32, 14)
            case .pressed:
                return (0.03, 8, 4, 20, 8)
            case .dragging:
                return (0.06, 20, 12, 44, 20)
            }
        }()

        self
            // Layer 1: Ambient contact shadow
            .shadow(color: .black.opacity(values.ambientOpacity), radius: 2, x: 0, y: 1)
            // Layer 2: Direct light shadow
            .shadow(color: .black.opacity(0.1), radius: values.directRadius, x: 0, y: values.directY)
            // Layer 3: Soft ambient glow
            .shadow(
                color: (accent ?? .black).opacity(0.06),
                radius: values.fillRadius,
                x: 0,
                y: values.fillY
            )
    }

    /// Apply focused element shadow with accent glow
    @ViewBuilder
    func focusedShadow(accent: Color) -> some View {
        self
            // Layer 1: Tight ambient
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            // Layer 2: Medium direct
            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
            // Layer 3: Accent glow
            .shadow(color: accent.opacity(0.18), radius: 32, x: 0, y: 12)
    }
}

// MARK: - Shadow Style API
extension View {
    /// Apply cosmo shadow style with optional accent color
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
/// Premium animations for the focus mode "thinking canvas" experience.
/// Designed for smooth entry/exit transitions and spatial thinking interactions.
struct FocusModeAnimations {
    // ═══════════════════════════════════════════════════════════════
    // ENTRY ANIMATIONS - Cinematic focus mode open
    // ═══════════════════════════════════════════════════════════════

    /// Background fade + scale for immersive entry
    /// Used when focus mode first appears
    static let backgroundEntry = Animation.spring(response: 0.4, dampingFraction: 0.75)

    /// Editor slides up with spring physics
    /// Slightly delayed for cinematic sequence
    static let editorEntry = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// Vignette animates inward to draw eye to center
    static let vignetteEntry = Animation.easeOut(duration: 0.6)

    // ═══════════════════════════════════════════════════════════════
    // EXIT ANIMATIONS - Quick, clean close
    // ═══════════════════════════════════════════════════════════════

    /// Fast scale down + fade for clean exit
    static let exit = Animation.spring(response: 0.3, dampingFraction: 0.85)

    /// Editor slides down on exit
    static let editorExit = Animation.easeIn(duration: 0.2)

    // ═══════════════════════════════════════════════════════════════
    // ORBITING BLOCKS - Related content appears from sides
    // ═══════════════════════════════════════════════════════════════

    /// Orbiting blocks stagger in from sides
    /// 0.05s delay between each block for elegant cascade
    static func orbitingEntry(index: Int) -> Animation {
        .spring(response: 0.4, dampingFraction: 0.7).delay(0.1 + Double(index) * 0.05)
    }

    /// Orbiting block hover - quick lift and glow
    static let orbitingHover = Animation.spring(response: 0.15, dampingFraction: 0.8)

    /// Orbiting block drag snap back
    static let orbitingSnapBack = Animation.spring(response: 0.3, dampingFraction: 0.7)

    // ═══════════════════════════════════════════════════════════════
    // FOCUS BLOCKS - User-placed floating notes
    // ═══════════════════════════════════════════════════════════════

    /// Focus block placement - bouncy pop in
    static let focusBlockPlace = Animation.spring(response: 0.35, dampingFraction: 0.65)

    /// Focus block removal - quick fade out
    static let focusBlockRemove = Animation.spring(response: 0.25, dampingFraction: 0.8)

    /// Focus block selection highlight
    static let focusBlockSelect = Animation.spring(response: 0.2, dampingFraction: 0.85)

    // ═══════════════════════════════════════════════════════════════
    // MENTION ANIMATIONS - Entity linking magic
    // ═══════════════════════════════════════════════════════════════

    /// Mention insertion shimmer
    static let mentionInsert = Animation.spring(response: 0.2, dampingFraction: 0.8)

    /// Shimmer sweep across mention
    static let shimmerSweep = Animation.easeInOut(duration: 0.5)

    /// Sparkle particles disperse
    static let sparkleDisperse = Animation.easeOut(duration: 0.6)

    // ═══════════════════════════════════════════════════════════════
    // MENU ANIMATIONS - Slash commands, mentions
    // ═══════════════════════════════════════════════════════════════

    /// Menu pop in at cursor
    static let menuAppear = Animation.spring(response: 0.2, dampingFraction: 0.8)

    /// Menu fade out
    static let menuDismiss = Animation.easeOut(duration: 0.15)

    /// Menu item hover
    static let menuItemHover = Animation.easeOut(duration: 0.1)
}

// MARK: - Focus Mode View Modifiers
extension View {
    /// Apply focus mode entry animation with scale and fade
    func focusModeEntry(_ isAppearing: Bool) -> some View {
        self
            .scaleEffect(isAppearing ? 1.0 : 0.98)
            .opacity(isAppearing ? 1.0 : 0)
            .animation(FocusModeAnimations.backgroundEntry, value: isAppearing)
    }

    /// Apply editor slide-up animation
    func editorEntry(_ isVisible: Bool, delay: Double = 0.1) -> some View {
        self
            .offset(y: isVisible ? 0 : 30)
            .opacity(isVisible ? 1.0 : 0)
            .animation(FocusModeAnimations.editorEntry.delay(delay), value: isVisible)
    }

    /// Apply orbiting block entry with stagger
    func orbitingBlockEntry(_ isVisible: Bool, index: Int) -> some View {
        self
            .offset(x: isVisible ? 0 : (index % 2 == 0 ? -50 : 50))
            .opacity(isVisible ? 1.0 : 0)
            .animation(FocusModeAnimations.orbitingEntry(index: index), value: isVisible)
    }

    /// Premium hover effect for focus mode blocks
    func focusBlockHover(_ isHovered: Bool, entityColor: Color) -> some View {
        self
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .shadow(
                color: entityColor.opacity(isHovered ? 0.3 : 0.1),
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
    func cosmicGlow(_ color: Color, intensity: CGFloat = 0.3) -> some View {
        self
            .shadow(color: color.opacity(intensity), radius: 15, x: 0, y: 0)
            .shadow(color: color.opacity(intensity * 0.5), radius: 30, x: 0, y: 0)
    }

    /// Subtle hover scale effect
    func hoverScale(_ isHovered: Bool, scale: CGFloat = 1.02) -> some View {
        self
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
    }

    /// Card style with premium solid background (Apple-style, no blur for performance)
    func cardStyle(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(CosmoColors.softWhite)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 5)
    }

    /// AI state border
    func aiStateBorder(color: Color, isActive: Bool = false) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(isActive ? 0.8 : 0.3), lineWidth: isActive ? 2 : 1)
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
// Use standard SwiftUI modifiers instead:
// Button("Text") { action() }
//     .padding(.horizontal, 16)
//     .padding(.vertical, 10)
//     .background(Color.purple)
//     .foregroundColor(.white)
//     .cornerRadius(10)

// EntityType color and icon are defined in CosmoApp.swift

// MARK: - Cosmo Notification Names
/// Centralized notification names for cross-component communication.
/// Used for features like typing pulse, focus state changes, etc.
extension Notification.Name {
    /// Posted when a keystroke occurs in any editor (for ambient background pulse)
    static let cosmoEditorKeystroke = Notification.Name("cosmo.editor.keystroke")

    /// Posted when a block becomes focused (for context dimming)
    static let cosmoBlockFocused = Notification.Name("cosmo.block.focused")

    /// Posted when a block loses focus
    static let cosmoBlockBlurred = Notification.Name("cosmo.block.blurred")

    /// Posted when save completes successfully
    static let cosmoSaveCompleted = Notification.Name("cosmo.save.completed")

    /// Posted when an entity is created
    static let cosmoEntityCreated = Notification.Name("cosmo.entity.created")

    /// Posted when an entity is deleted
    static let cosmoEntityDeleted = Notification.Name("cosmo.entity.deleted")
}

// MARK: - 3D Tilt Effect Views
/// Apple-grade 3D tilt effect that responds to hover position.
/// Creates depth perception similar to visionOS spatial interactions.

/// Geometry-aware 3D tilt wrapper view
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
    /// Apply 3D tilt effect on hover - Apple-grade depth perception
    func cosmoTilt(maxTilt: Double = 2.5, perspective: CGFloat = 0.6) -> some View {
        GeometricTiltView(maxTilt: maxTilt, perspective: perspective) {
            self
        }
    }

    /// Apply simple tilt without geometry tracking (for static tilt amounts)
    /// NOTE: Animation should be applied at call site to avoid duplicate animations
    func cosmoTiltSimple(_ isHovered: Bool, amount: Double = 2.0) -> some View {
        self.rotation3DEffect(
            .degrees(isHovered ? amount : 0),
            axis: (x: -0.5, y: 1, z: 0),
            perspective: 0.6
        )
        // Animation removed - apply at call site to prevent duplicate animation conflicts
    }
}
