// CosmoOS/UI/Sanctuary/SanctuaryTokens.swift
// Sanctuary Design Tokens - Apple-grade design system for the neural dashboard
// Phase 1 Foundation: All visual constants, colors, and spatial relationships

import SwiftUI

// MARK: - Sanctuary Color System

/// The 6-dimension color palette for the Sanctuary neural dashboard
/// Each dimension has a distinct identity while maintaining visual harmony
public struct SanctuaryColors {

    // ═══════════════════════════════════════════════════════════════
    // DIMENSION COLORS - Primary identities
    // ═══════════════════════════════════════════════════════════════

    /// Cognitive - Deep Indigo (Focus, clarity, mental acuity)
    /// Think: The color of a focused mind at 2am
    public static let cognitive = Color(hex: "6366F1")
    public static let cognitiveDark = Color(hex: "4338CA")
    public static let cognitiveLight = Color(hex: "818CF8")

    /// Creative - Vibrant Amber (Inspiration, expression, flow)
    /// Think: Sunlight hitting a canvas
    public static let creative = Color(hex: "F59E0B")
    public static let creativeDark = Color(hex: "D97706")
    public static let creativeLight = Color(hex: "FBBF24")

    /// Physiological - Vital Green (Health, vitality, recovery)
    /// Think: The pulse of life, a strong heartbeat
    public static let physiological = Color(hex: "10B981")
    public static let physiologicalDark = Color(hex: "059669")
    public static let physiologicalLight = Color(hex: "34D399")

    /// Behavioral - Strong Blue (Discipline, consistency, habits)
    /// Think: The steady rhythm of routine
    public static let behavioral = Color(hex: "3B82F6")
    public static let behavioralDark = Color(hex: "2563EB")
    public static let behavioralLight = Color(hex: "60A5FA")

    /// Knowledge - Rich Purple (Wisdom, understanding, synthesis)
    /// Think: The depth of accumulated insight
    public static let knowledge = Color(hex: "8B5CF6")
    public static let knowledgeDark = Color(hex: "7C3AED")
    public static let knowledgeLight = Color(hex: "A78BFA")

    /// Reflection - Warm Pink (Introspection, emotion, growth)
    /// Think: The warmth of self-understanding
    public static let reflection = Color(hex: "EC4899")
    public static let reflectionDark = Color(hex: "DB2777")
    public static let reflectionLight = Color(hex: "F472B6")

    // ═══════════════════════════════════════════════════════════════
    // SATELLITE REGIONS - Plannerum & Thinkspace
    // ═══════════════════════════════════════════════════════════════

    /// Plannerum - Soft Violet (Planning, foresight, direction)
    /// Think: A calm holographic command chamber
    public static let plannerumPrimary = Color(hex: "A78BFA")
    public static let plannerumDark = Color(hex: "8B5CF6")
    public static let plannerumLight = Color(hex: "C4B5FD")
    public static let plannerumGlow = Color(hex: "A78BFA").opacity(0.3)

    /// Thinkspace - Soft Mint (Creation, growth, infinite canvas)
    /// Think: The infinite creative production realm
    public static let thinkspacePrimary = Color(hex: "34D399")
    public static let thinkspaceDark = Color(hex: "10B981")
    public static let thinkspaceLight = Color(hex: "6EE7B7")
    public static let thinkspaceGlow = Color(hex: "34D399").opacity(0.3)

    // ═══════════════════════════════════════════════════════════════
    // CONNECTION THREADS - Satellite orbital paths
    // ═══════════════════════════════════════════════════════════════

    /// Dormant connection thread (idle state)
    public static let threadDormant = Color.white.opacity(0.15)

    /// Active connection thread (hover/selected)
    public static let threadActive = Color.white.opacity(0.4)

    /// Pulsing connection thread (data flow)
    public static let threadPulse = Color.white.opacity(0.6)

    // ═══════════════════════════════════════════════════════════════
    // HERO ORB - The central Cosmo Index visualization
    // ═══════════════════════════════════════════════════════════════

    /// Hero orb primary gradient colors
    public static let heroPrimary = Color(hex: "6366F1")
    public static let heroSecondary = Color(hex: "8B5CF6")
    public static let heroTertiary = Color(hex: "A855F7")

    /// Hero orb glow colors
    public static let heroGlow = Color(hex: "818CF8")
    public static let heroInnerGlow = Color.white.opacity(0.35)

    // ═══════════════════════════════════════════════════════════════
    // BACKGROUND SYSTEM - Aurora and void
    // ═══════════════════════════════════════════════════════════════

    /// Deep void background - nearly black with subtle warmth
    public static let voidPrimary = Color(hex: "0A0A0F")
    public static let voidSecondary = Color(hex: "12121A")
    public static let voidTertiary = Color(hex: "1A1A25")

    /// Aurora accent colors for background animation
    public static let auroraBlue = Color(hex: "3B82F6").opacity(0.15)
    public static let auroraPurple = Color(hex: "8B5CF6").opacity(0.12)
    public static let auroraPink = Color(hex: "EC4899").opacity(0.08)

    // ═══════════════════════════════════════════════════════════════
    // GLASS MATERIALS - Translucent surfaces
    // ═══════════════════════════════════════════════════════════════

    /// Primary glass (cards, panels) - visible but subtle
    public static let glassPrimary = Color.white.opacity(0.08)

    /// Secondary glass (nested elements) - more subtle
    public static let glassSecondary = Color.white.opacity(0.05)

    /// Accent glass (highlighted states) - more visible
    public static let glassAccent = Color.white.opacity(0.12)

    /// Glass border highlight
    public static let glassBorder = Color.white.opacity(0.15)

    /// Glass border subtle
    public static let glassBorderSubtle = Color.white.opacity(0.08)

    // ═══════════════════════════════════════════════════════════════
    // TEXT HIERARCHY - On dark backgrounds
    // ═══════════════════════════════════════════════════════════════

    /// Primary text - high visibility
    public static let textPrimary = Color.white

    /// Secondary text - reduced emphasis
    public static let textSecondary = Color.white.opacity(0.7)

    /// Tertiary text - hints, captions
    public static let textTertiary = Color.white.opacity(0.5)

    /// Muted text - disabled, less important
    public static let textMuted = Color.white.opacity(0.35)

    // ═══════════════════════════════════════════════════════════════
    // STATUS COLORS - For indicators and alerts
    // ═══════════════════════════════════════════════════════════════

    /// Live indicator green
    public static let live = Color(hex: "22C55E")

    /// Warning amber
    public static let warning = Color(hex: "F59E0B")

    /// Danger red
    public static let danger = Color(hex: "EF4444")

    /// Prediction diamond amber
    public static let prediction = Color(hex: "F59E0B")

    // ═══════════════════════════════════════════════════════════════
    // CORRELATION LINES - Data connection visualization
    // ═══════════════════════════════════════════════════════════════

    /// Strong correlation (r > 0.7)
    public static let correlationStrong = Color.white.opacity(0.4)

    /// Medium correlation (r > 0.4)
    public static let correlationMedium = Color.white.opacity(0.25)

    /// Weak correlation (r > 0.2)
    public static let correlationWeak = Color.white.opacity(0.12)

    // ═══════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// Get dimension color by enum case
    public static func color(for dimension: LevelDimension) -> Color {
        switch dimension {
        case .cognitive: return cognitive
        case .creative: return creative
        case .physiological: return physiological
        case .behavioral: return behavioral
        case .knowledge: return knowledge
        case .reflection: return reflection
        }
    }

    /// Get dimension dark variant
    public static func darkColor(for dimension: LevelDimension) -> Color {
        switch dimension {
        case .cognitive: return cognitiveDark
        case .creative: return creativeDark
        case .physiological: return physiologicalDark
        case .behavioral: return behavioralDark
        case .knowledge: return knowledgeDark
        case .reflection: return reflectionDark
        }
    }

    /// Get dimension light variant
    public static func lightColor(for dimension: LevelDimension) -> Color {
        switch dimension {
        case .cognitive: return cognitiveLight
        case .creative: return creativeLight
        case .physiological: return physiologicalLight
        case .behavioral: return behavioralLight
        case .knowledge: return knowledgeLight
        case .reflection: return reflectionLight
        }
    }

    /// Get dimension gradient
    public static func gradient(for dimension: LevelDimension) -> LinearGradient {
        let dark = darkColor(for: dimension)
        let light = lightColor(for: dimension)
        return LinearGradient(
            colors: [light, color(for: dimension), dark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Get radial gradient for orbs
    public static func orbGradient(for dimension: LevelDimension) -> RadialGradient {
        let primary = color(for: dimension)
        let dark = darkColor(for: dimension)
        return RadialGradient(
            colors: [
                Color.white.opacity(0.15),
                primary.opacity(0.85),
                dark.opacity(0.95)
            ],
            center: .topLeading,
            startRadius: 0,
            endRadius: 60
        )
    }

    // ═══════════════════════════════════════════════════════════════
    // NESTED NAMESPACES - For dot-syntax access
    // ═══════════════════════════════════════════════════════════════

    /// Hero orb colors namespace
    public struct HeroOrb {
        public static let primary = SanctuaryColors.heroPrimary
        public static let secondary = SanctuaryColors.heroSecondary
        public static let tertiary = SanctuaryColors.heroTertiary
        public static let glow = SanctuaryColors.heroGlow

        /// Get orb colors based on level (returns a set of colors that evolve with level)
        public static func forLevel(_ level: Int) -> HeroOrbColors {
            // Colors evolve as level increases
            let rankColor = SanctuaryRanks.rankColor(for: level)
            return HeroOrbColors(
                primary: primary,
                secondary: secondary,
                tertiary: rankColor.opacity(0.8),
                glow: rankColor.opacity(0.6)
            )
        }
    }

    /// Struct to hold hero orb color set
    public struct HeroOrbColors {
        public let primary: Color
        public let secondary: Color
        public let tertiary: Color
        public let glow: Color
    }

    /// Text colors namespace
    public struct Text {
        public static let primary = SanctuaryColors.textPrimary
        public static let secondary = SanctuaryColors.textSecondary
        public static let tertiary = SanctuaryColors.textTertiary
        public static let muted = SanctuaryColors.textMuted
    }

    /// Semantic colors namespace
    public struct Semantic {
        public static let success = Color(hex: "22C55E")
        public static let warning = SanctuaryColors.warning
        public static let danger = SanctuaryColors.danger
        public static let error = SanctuaryColors.danger
        public static let info = SanctuaryColors.behavioral
    }

    /// Dimension colors namespace
    public struct Dimensions {
        public static let cognitive = SanctuaryColors.cognitive
        public static let creative = SanctuaryColors.creative
        public static let physiological = SanctuaryColors.physiological
        public static let behavioral = SanctuaryColors.behavioral
        public static let knowledge = SanctuaryColors.knowledge
        public static let reflection = SanctuaryColors.reflection

        /// Get color for a dimension
        public static func color(for dimension: LevelDimension) -> Color {
            SanctuaryColors.color(for: dimension)
        }
    }

    /// XP and level colors namespace
    public struct XP {
        public static let primary = Color(hex: "F59E0B")
        public static let secondary = Color(hex: "FBBF24")
        public static let glow = Color(hex: "F59E0B").opacity(0.6)
        public static let track = Color.white.opacity(0.1)
        public static let fill = Color(hex: "F59E0B")
    }

    /// Background colors namespace
    public struct Background {
        public static let primary = SanctuaryColors.voidPrimary
        public static let secondary = SanctuaryColors.voidSecondary
        public static let tertiary = SanctuaryColors.voidTertiary
        public static let void = SanctuaryColors.voidPrimary
    }

    /// Satellite region colors namespace
    public struct Satellite {
        // Plannerum (left satellite - planning realm)
        public static let plannerumPrimary = SanctuaryColors.plannerumPrimary
        public static let plannerumDark = SanctuaryColors.plannerumDark
        public static let plannerumLight = SanctuaryColors.plannerumLight
        public static let plannerumGlow = SanctuaryColors.plannerumGlow

        // Thinkspace (right satellite - creative canvas)
        public static let thinkspacePrimary = SanctuaryColors.thinkspacePrimary
        public static let thinkspaceDark = SanctuaryColors.thinkspaceDark
        public static let thinkspaceLight = SanctuaryColors.thinkspaceLight
        public static let thinkspaceGlow = SanctuaryColors.thinkspaceGlow

        // Connection threads
        public static let threadDormant = SanctuaryColors.threadDormant
        public static let threadActive = SanctuaryColors.threadActive
        public static let threadPulse = SanctuaryColors.threadPulse

        /// Get gradient for satellite type
        public static func gradient(for type: SatelliteType) -> RadialGradient {
            switch type {
            case .plannerum:
                return RadialGradient(
                    colors: [
                        Color.white.opacity(0.15),
                        plannerumPrimary.opacity(0.85),
                        plannerumDark.opacity(0.95)
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 60
                )
            case .thinkspace:
                return RadialGradient(
                    colors: [
                        Color.white.opacity(0.15),
                        thinkspacePrimary.opacity(0.85),
                        thinkspaceDark.opacity(0.95)
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 60
                )
            }
        }
    }

    /// Satellite type identifier
    public enum SatelliteType: String, CaseIterable {
        case plannerum
        case thinkspace

        public var displayName: String {
            switch self {
            case .plannerum: return "Plannerum"
            case .thinkspace: return "Thinkspace"
            }
        }

        public var icon: String {
            switch self {
            case .plannerum: return "compass.drawing"  // Astrolabe/compass motif
            case .thinkspace: return "square.on.square"  // Nested squares/canvas
            }
        }

        public var primaryColor: Color {
            switch self {
            case .plannerum: return SanctuaryColors.plannerumPrimary
            case .thinkspace: return SanctuaryColors.thinkspacePrimary
            }
        }

        public var glowColor: Color {
            switch self {
            case .plannerum: return SanctuaryColors.plannerumGlow
            case .thinkspace: return SanctuaryColors.thinkspaceGlow
            }
        }
    }

    /// Glass effect colors namespace
    public struct Glass {
        public static let primary = SanctuaryColors.glassPrimary
        public static let secondary = SanctuaryColors.glassSecondary
        public static let accent = SanctuaryColors.glassAccent
        public static let border = SanctuaryColors.glassBorder
        public static let borderSubtle = SanctuaryColors.glassBorderSubtle
        public static let background = SanctuaryColors.voidSecondary
        public static let highlight = Color.white.opacity(0.2)
    }
}

// MARK: - Sanctuary Layout System

/// Spatial constants for the Sanctuary UI
/// All values are designed for Apple-grade visual hierarchy
public struct SanctuaryLayout {

    // ═══════════════════════════════════════════════════════════════
    // SANCTUARY HOME - Main overview layout
    // ═══════════════════════════════════════════════════════════════

    /// Maximum content width (centered on large displays)
    public static let maxContentWidth: CGFloat = 720

    /// Orb visualization area (square container)
    public static let orbAreaSize: CGFloat = 520

    /// Radius for dimension orb hexagon arrangement
    public static let dimensionOrbRadius: CGFloat = 190

    /// Hero orb size (center orb)
    public static let heroOrbSize: CGFloat = 140

    /// Dimension orb size (surrounding orbs)
    public static let dimensionOrbSize: CGFloat = 72

    /// Canvas level orb size (floating corner orb)
    public static let canvasOrbSize: CGFloat = 56

    // ═══════════════════════════════════════════════════════════════
    // SATELLITE NODES - Plannerum & Thinkspace positioning
    // ═══════════════════════════════════════════════════════════════

    /// Satellite orb size (same as dimension orbs)
    public static let satelliteOrbSize: CGFloat = 72

    /// Plannerum node horizontal position (percentage of screen width)
    public static let plannerumPositionX: CGFloat = 0.12  // 12% from left

    /// Thinkspace node horizontal position (percentage of screen width)
    public static let thinkspacePositionX: CGFloat = 0.88  // 88% from left (12% from right)

    /// Satellite vertical position (percentage of screen height, aligned with hero)
    public static let satellitePositionY: CGFloat = 0.45  // 45% from top (centered with constellation)

    /// Satellite z-depth (recessed behind constellation)
    public static let satelliteZDepth: CGFloat = -50

    /// Connection thread curve control point offset
    public static let connectionCurveOffset: CGFloat = 80

    // ═══════════════════════════════════════════════════════════════
    // HEADER & NAVIGATION
    // ═══════════════════════════════════════════════════════════════

    /// Top padding for header
    public static let headerPaddingTop: CGFloat = 24

    /// Horizontal padding for header
    public static let headerPaddingHorizontal: CGFloat = 32

    /// Section spacing (between major areas)
    public static let sectionSpacing: CGFloat = 40

    /// Insight carousel bottom padding
    public static let insightPaddingBottom: CGFloat = 48

    // ═══════════════════════════════════════════════════════════════
    // DIMENSION DETAIL PANELS
    // ═══════════════════════════════════════════════════════════════

    /// Floating panel max width
    public static let panelMaxWidth: CGFloat = 560

    /// Floating panel max height
    public static let panelMaxHeight: CGFloat = 720

    /// Panel corner radius
    public static let panelCornerRadius: CGFloat = 16

    /// Panel internal padding
    public static let panelPadding: CGFloat = 24

    /// Card spacing within panels
    public static let cardSpacing: CGFloat = 16

    // ═══════════════════════════════════════════════════════════════
    // CARDS & METRICS
    // ═══════════════════════════════════════════════════════════════

    /// Metric card height (small)
    public static let metricCardHeightSmall: CGFloat = 80

    /// Metric card height (medium)
    public static let metricCardHeightMedium: CGFloat = 120

    /// Metric card height (large)
    public static let metricCardHeightLarge: CGFloat = 180

    /// Card corner radius
    public static let cardCornerRadius: CGFloat = 12

    /// Card internal padding
    public static let cardPadding: CGFloat = 16

    /// Card border width
    public static let cardBorderWidth: CGFloat = 1

    // ═══════════════════════════════════════════════════════════════
    // SPACING SCALE - 4pt base unit
    // ═══════════════════════════════════════════════════════════════

    public static let spacing2: CGFloat = 2
    public static let spacing4: CGFloat = 4
    public static let spacing6: CGFloat = 6
    public static let spacing8: CGFloat = 8
    public static let spacing12: CGFloat = 12
    public static let spacing16: CGFloat = 16
    public static let spacing20: CGFloat = 20
    public static let spacing24: CGFloat = 24
    public static let spacing32: CGFloat = 32
    public static let spacing40: CGFloat = 40
    public static let spacing48: CGFloat = 48
    public static let spacing64: CGFloat = 64

    // ═══════════════════════════════════════════════════════════════
    // CORNER RADIUS SCALE
    // ═══════════════════════════════════════════════════════════════

    public static let radiusSmall: CGFloat = 6
    public static let radiusMedium: CGFloat = 10
    public static let radiusLarge: CGFloat = 14
    public static let radiusXL: CGFloat = 20
    public static let radiusFull: CGFloat = 9999

    // ═══════════════════════════════════════════════════════════════
    // ICON SIZES
    // ═══════════════════════════════════════════════════════════════

    public static let iconSizeSmall: CGFloat = 14
    public static let iconSizeMedium: CGFloat = 18
    public static let iconSizeLarge: CGFloat = 24
    public static let iconSizeXL: CGFloat = 32

    // ═══════════════════════════════════════════════════════════════
    // NESTED NAMESPACES - For dot-syntax access
    // ═══════════════════════════════════════════════════════════════

    /// Sizing namespace for orb and component sizes
    public struct Sizing {
        public static let heroOrb = SanctuaryLayout.heroOrbSize
        public static let heroOrbArea = SanctuaryLayout.orbAreaSize
        public static let dimensionOrb = SanctuaryLayout.dimensionOrbSize
        public static let dimensionOrbRadius = SanctuaryLayout.dimensionOrbRadius
        public static let canvasOrb = SanctuaryLayout.canvasOrbSize
        public static let orbArea = SanctuaryLayout.orbAreaSize
    }

    /// Spacing namespace for semantic spacing values
    public struct Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
        public static let xxxl: CGFloat = 64
    }

    /// Corner radius namespace
    public struct CornerRadius {
        public static let xs: CGFloat = 4
        public static let sm = SanctuaryLayout.radiusSmall
        public static let small = SanctuaryLayout.radiusSmall
        public static let md = SanctuaryLayout.radiusMedium
        public static let medium = SanctuaryLayout.radiusMedium
        public static let lg = SanctuaryLayout.radiusLarge
        public static let large = SanctuaryLayout.radiusLarge
        public static let xl = SanctuaryLayout.radiusXL
        public static let card = SanctuaryLayout.cardCornerRadius
        public static let panel = SanctuaryLayout.panelCornerRadius
    }
}

// MARK: - Sanctuary Typography

/// Typography system for dark-mode Sanctuary UI
public struct SanctuaryTypography {

    // ═══════════════════════════════════════════════════════════════
    // DISPLAY - Hero numbers and titles
    // ═══════════════════════════════════════════════════════════════

    /// Hero level number (large, bold)
    public static let heroNumber = Font.system(size: 48, weight: .bold, design: .rounded)

    /// Large display title
    public static let displayLarge = Font.system(size: 32, weight: .bold, design: .rounded)

    /// Medium display title
    public static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)

    /// Small display title
    public static let displaySmall = Font.system(size: 24, weight: .bold, design: .rounded)

    // ═══════════════════════════════════════════════════════════════
    // TITLES - Section and card headers
    // ═══════════════════════════════════════════════════════════════

    /// Section title
    public static let titleLarge = Font.system(size: 22, weight: .semibold, design: .rounded)

    /// Card title
    public static let titleMedium = Font.system(size: 18, weight: .semibold, design: .rounded)

    /// Subsection title
    public static let titleSmall = Font.system(size: 15, weight: .semibold, design: .rounded)

    /// Default title alias
    public static let title = titleMedium

    /// Default display alias
    public static let display = displayMedium

    /// Body text
    public static let body = Font.system(size: 15, weight: .regular, design: .rounded)

    // ═══════════════════════════════════════════════════════════════
    // METRICS - Numbers and values
    // ═══════════════════════════════════════════════════════════════

    /// Default metric alias
    public static let metric = Font.system(size: 12, weight: .medium, design: .rounded)

    /// Large metric value
    public static let metricLarge = Font.system(size: 36, weight: .bold, design: .rounded)

    /// Medium metric value
    public static let metricMedium = Font.system(size: 24, weight: .bold, design: .rounded)

    /// Small metric value
    public static let metricSmall = Font.system(size: 18, weight: .semibold, design: .rounded)

    /// Metric unit label
    public static let metricUnit = Font.system(size: 14, weight: .medium, design: .rounded)

    // ═══════════════════════════════════════════════════════════════
    // BODY - Content text
    // ═══════════════════════════════════════════════════════════════

    /// Primary body text
    public static let bodyLarge = Font.system(size: 16, weight: .regular, design: .default)

    /// Secondary body text
    public static let bodyMedium = Font.system(size: 14, weight: .regular, design: .default)

    /// Small body text
    public static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)

    // ═══════════════════════════════════════════════════════════════
    // UI - Labels and captions
    // ═══════════════════════════════════════════════════════════════

    /// Button/badge label
    public static let label = Font.system(size: 13, weight: .medium, design: .default)

    /// Small label
    public static let labelSmall = Font.system(size: 11, weight: .medium, design: .default)

    /// Caption text
    public static let caption = Font.system(size: 11, weight: .regular, design: .default)

    /// Micro text (timestamps, etc.)
    public static let micro = Font.system(size: 10, weight: .regular, design: .default)

    // ═══════════════════════════════════════════════════════════════
    // ORB LABELS - Dimension orb text
    // ═══════════════════════════════════════════════════════════════

    /// Level number inside orb
    public static let orbLevel = Font.system(size: 20, weight: .bold, design: .rounded)

    /// NELO value below orb
    public static let orbNelo = Font.system(size: 10, weight: .medium, design: .rounded)

    /// Dimension name label
    public static let orbLabel = Font.system(size: 9, weight: .semibold, design: .rounded)
}

// MARK: - Sanctuary Animation Durations

/// Timing constants for Sanctuary animations
/// All values optimized for 120Hz ProMotion displays
public struct SanctuaryDurations {

    // ═══════════════════════════════════════════════════════════════
    // MICRO INTERACTIONS - Immediate feedback
    // ═══════════════════════════════════════════════════════════════

    /// Instant feedback (hover, press)
    public static let instant: TimeInterval = 0.08

    /// Fast response (toggles, small changes)
    public static let fast: TimeInterval = 0.15

    /// Quick transition (selection changes)
    public static let quick: TimeInterval = 0.2

    /// Medium transition (between quick and normal)
    public static let medium: TimeInterval = 0.25

    // ═══════════════════════════════════════════════════════════════
    // CONTENT TRANSITIONS - View changes
    // ═══════════════════════════════════════════════════════════════

    /// Normal transition (card reveals, mode changes)
    public static let normal: TimeInterval = 0.35

    /// Slow transition (major view changes)
    public static let slow: TimeInterval = 0.5

    /// Cinematic transition (dimension zoom)
    public static let cinematic: TimeInterval = 0.8

    // ═══════════════════════════════════════════════════════════════
    // ENTRY SEQUENCES - Choreographed animations
    // ═══════════════════════════════════════════════════════════════

    /// Background fade in
    public static let backgroundEntry: TimeInterval = 0.6

    /// Hero orb appear
    public static let heroEntry: TimeInterval = 0.8

    /// Dimension orbs appear
    public static let dimensionEntry: TimeInterval = 0.6

    /// Stagger delay between items
    public static let staggerDelay: TimeInterval = 0.05

    // ═══════════════════════════════════════════════════════════════
    // CONTINUOUS ANIMATIONS
    // ═══════════════════════════════════════════════════════════════

    /// Breathing pulse cycle
    public static let breathingCycle: TimeInterval = 3.5

    /// Breathing animation alias
    public static let breathing: TimeInterval = breathingCycle

    /// Orb rotation cycle (slow)
    public static let rotationSlow: TimeInterval = 40.0

    /// Default rotation animation alias
    public static let rotation: TimeInterval = rotationSlow

    /// Orb rotation cycle (medium)
    public static let rotationMedium: TimeInterval = 25.0

    /// Orb rotation cycle (fast)
    public static let rotationFast: TimeInterval = 15.0

    /// Glow pulse cycle
    public static let glowPulse: TimeInterval = 2.0

    /// Aurora drift cycle
    public static let auroraDrift: TimeInterval = 20.0
}

// MARK: - Sanctuary Springs

/// Spring animation configurations for Sanctuary
/// Tuned for 120Hz ProMotion and Apple-grade feel
public struct SanctuarySprings {

    // ═══════════════════════════════════════════════════════════════
    // MICRO INTERACTIONS
    // ═══════════════════════════════════════════════════════════════

    /// Instant press feedback
    public static let press = Animation.spring(response: 0.08, dampingFraction: 0.92)

    /// Quick hover response
    public static let hover = Animation.spring(response: 0.15, dampingFraction: 0.78)

    /// Selection toggle
    public static let select = Animation.spring(response: 0.2, dampingFraction: 0.85)

    // ═══════════════════════════════════════════════════════════════
    // CONTENT TRANSITIONS
    // ═══════════════════════════════════════════════════════════════

    /// Snappy bounce (toggles, pops)
    public static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.68)

    /// Smooth transition (most animations)
    public static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.78)

    /// Gentle ease (backgrounds, large elements)
    public static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.85)

    // ═══════════════════════════════════════════════════════════════
    // SPECIAL ANIMATIONS
    // ═══════════════════════════════════════════════════════════════

    /// Bouncy pop (celebrations, achievements)
    public static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)

    /// Elastic (level up, XP burst)
    public static let elastic = Animation.spring(response: 0.35, dampingFraction: 0.55)

    /// Cinematic zoom (dimension entry)
    public static let cinematic = Animation.spring(response: 0.8, dampingFraction: 0.75)

    // ═══════════════════════════════════════════════════════════════
    // ORB ANIMATIONS
    // ═══════════════════════════════════════════════════════════════

    /// Hero orb entry
    public static let heroEntry = Animation.spring(response: 0.8, dampingFraction: 0.6)

    /// Dimension orb tap
    public static let orbTap = Animation.spring(response: 0.4, dampingFraction: 0.7)

    /// Orb pulse on data update
    public static let orbPulse = Animation.spring(response: 0.3, dampingFraction: 0.7)

    // ═══════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// Staggered entry animation
    public static func staggered(index: Int, baseDelay: TimeInterval = 0.05) -> Animation {
        smooth.delay(Double(index) * baseDelay)
    }

    /// Cascading entry (faster stagger)
    public static func cascade(index: Int) -> Animation {
        snappy.delay(Double(index) * 0.03)
    }
}

// MARK: - Sanctuary Gradients

/// Pre-defined gradient configurations for Sanctuary UI
public struct SanctuaryGradients {

    // ═══════════════════════════════════════════════════════════════
    // HERO ORB GRADIENTS
    // ═══════════════════════════════════════════════════════════════

    /// Primary hero orb fill
    public static let heroOrb = RadialGradient(
        colors: [
            Color.white.opacity(0.15),
            SanctuaryColors.heroPrimary.opacity(0.85),
            SanctuaryColors.heroSecondary.opacity(0.95)
        ],
        center: .topLeading,
        startRadius: 0,
        endRadius: SanctuaryLayout.heroOrbSize
    )

    /// Hero orb glow rings
    public static let heroGlow = AngularGradient(
        colors: [
            SanctuaryColors.heroPrimary,
            SanctuaryColors.heroSecondary,
            SanctuaryColors.heroTertiary,
            SanctuaryColors.heroPrimary
        ],
        center: .center
    )

    // ═══════════════════════════════════════════════════════════════
    // BACKGROUND GRADIENTS
    // ═══════════════════════════════════════════════════════════════

    /// Deep void background
    public static let voidBackground = RadialGradient(
        colors: [
            SanctuaryColors.voidSecondary,
            SanctuaryColors.voidPrimary
        ],
        center: .center,
        startRadius: 0,
        endRadius: 800
    )

    /// Aurora overlay
    public static let aurora = LinearGradient(
        colors: [
            SanctuaryColors.auroraBlue,
            SanctuaryColors.auroraPurple,
            SanctuaryColors.auroraPink,
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // ═══════════════════════════════════════════════════════════════
    // GLASS GRADIENTS
    // ═══════════════════════════════════════════════════════════════

    /// Glass surface highlight
    public static let glassHighlight = LinearGradient(
        colors: [
            Color.white.opacity(0.12),
            Color.white.opacity(0.04),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Glass border
    public static let glassBorder = LinearGradient(
        colors: [
            Color.white.opacity(0.2),
            Color.white.opacity(0.08)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // ═══════════════════════════════════════════════════════════════
    // XP PROGRESS GRADIENTS
    // ═══════════════════════════════════════════════════════════════

    /// XP progress ring
    public static let xpProgress = LinearGradient(
        colors: [Color(hex: "22C55E"), Color(hex: "10B981")],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// XP background track
    public static let xpTrack = LinearGradient(
        colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Dimension Icon Configuration

/// Icon and symbol configuration for dimensions
public struct SanctuaryIcons {

    /// Get SF Symbol name for dimension
    public static func symbol(for dimension: LevelDimension) -> String {
        switch dimension {
        case .cognitive: return "brain.head.profile"
        case .creative: return "paintbrush.pointed"
        case .physiological: return "heart.fill"
        case .behavioral: return "flame.fill"
        case .knowledge: return "books.vertical.fill"
        case .reflection: return "person.fill"
        }
    }

    /// Get emoji for dimension (for compact display)
    public static func emoji(for dimension: LevelDimension) -> String {
        switch dimension {
        case .cognitive: return "🧠"
        case .creative: return "🎨"
        case .physiological: return "❤️"
        case .behavioral: return "🔥"
        case .knowledge: return "📚"
        case .reflection: return "🪞"
        }
    }

    /// Get display name for dimension
    public static func displayName(for dimension: LevelDimension) -> String {
        switch dimension {
        case .cognitive: return "Cognitive"
        case .creative: return "Creative"
        case .physiological: return "Physiological"
        case .behavioral: return "Behavioral"
        case .knowledge: return "Knowledge"
        case .reflection: return "Reflection"
        }
    }

    /// Get short name for dimension (compact UI)
    public static func shortName(for dimension: LevelDimension) -> String {
        switch dimension {
        case .cognitive: return "COG"
        case .creative: return "CRE"
        case .physiological: return "PHY"
        case .behavioral: return "BEH"
        case .knowledge: return "KNO"
        case .reflection: return "REF"
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // NESTED NAMESPACES - For dot-syntax access
    // ═══════════════════════════════════════════════════════════════

    /// Dimension icons namespace
    public struct Dimensions {
        /// Get SF Symbol icon for dimension
        public static func icon(for dimension: LevelDimension) -> String {
            SanctuaryIcons.symbol(for: dimension)
        }

        public static let cognitive = "brain.head.profile"
        public static let creative = "paintbrush.pointed"
        public static let physiological = "heart.fill"
        public static let behavioral = "flame.fill"
        public static let knowledge = "books.vertical.fill"
        public static let reflection = "person.fill"
    }

    /// Action icons namespace
    public struct Actions {
        public static let insight = "lightbulb.fill"
        public static let add = "plus"
        public static let edit = "pencil"
        public static let delete = "trash"
        public static let share = "square.and.arrow.up"
        public static let settings = "gearshape"
        public static let close = "xmark"
        public static let back = "chevron.left"
        public static let forward = "chevron.right"
        public static let expand = "arrow.up.left.and.arrow.down.right"
        public static let collapse = "arrow.down.right.and.arrow.up.left"
    }
}

// MARK: - Rank System

/// Rank thresholds and display names
public struct SanctuaryRanks {

    /// Get rank name for level
    public static func rankName(for level: Int) -> String {
        switch level {
        case 0..<5: return "Novice"
        case 5..<10: return "Apprentice"
        case 10..<15: return "Adept"
        case 15..<20: return "Expert"
        case 20..<25: return "Master"
        case 25..<30: return "Grandmaster"
        case 30..<40: return "Legend"
        case 40..<50: return "Mythic"
        case 50...: return "Transcendent"
        default: return "Unknown"
        }
    }

    /// Get rank color for level
    public static func rankColor(for level: Int) -> Color {
        switch level {
        case 0..<5: return Color(hex: "9CA3AF")   // Gray
        case 5..<10: return Color(hex: "22C55E")  // Green
        case 10..<15: return Color(hex: "3B82F6") // Blue
        case 15..<20: return Color(hex: "8B5CF6") // Purple
        case 20..<25: return Color(hex: "F59E0B") // Amber
        case 25..<30: return Color(hex: "EF4444") // Red
        case 30..<40: return Color(hex: "EC4899") // Pink
        case 40..<50: return Color(hex: "06B6D4") // Cyan
        case 50...: return Color(hex: "FBBF24")   // Gold
        default: return Color.gray
        }
    }

    /// Get rank color for rank name
    public static func color(for rank: String) -> Color {
        switch rank.lowercased() {
        case "novice": return Color(hex: "9CA3AF")
        case "apprentice": return Color(hex: "22C55E")
        case "adept": return Color(hex: "3B82F6")
        case "expert": return Color(hex: "8B5CF6")
        case "master": return Color(hex: "F59E0B")
        case "grandmaster": return Color(hex: "EF4444")
        case "legend": return Color(hex: "EC4899")
        case "mythic": return Color(hex: "06B6D4")
        case "transcendent": return Color(hex: "FBBF24")
        default: return Color.gray
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct SanctuaryTokens_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Dimension Colors
                Text("Dimension Colors")
                    .font(SanctuaryTypography.titleLarge)
                    .foregroundColor(.white)

                HStack(spacing: 16) {
                    ForEach(LevelDimension.allCases, id: \.self) { dimension in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(SanctuaryColors.color(for: dimension))
                                .frame(width: 40, height: 40)
                            Text(SanctuaryIcons.shortName(for: dimension))
                                .font(SanctuaryTypography.labelSmall)
                                .foregroundColor(.white)
                        }
                    }
                }

                // Typography
                Text("Typography")
                    .font(SanctuaryTypography.titleLarge)
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hero Number").font(SanctuaryTypography.heroNumber)
                    Text("Display Large").font(SanctuaryTypography.displayLarge)
                    Text("Title Medium").font(SanctuaryTypography.titleMedium)
                    Text("Body Medium").font(SanctuaryTypography.bodyMedium)
                    Text("Label Small").font(SanctuaryTypography.labelSmall)
                }
                .foregroundColor(.white)
            }
            .padding(32)
        }
        .background(SanctuaryColors.voidPrimary)
        .preferredColorScheme(.dark)
    }
}
#endif
