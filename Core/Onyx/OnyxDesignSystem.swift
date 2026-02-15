// CosmoOS/Core/Onyx/OnyxDesignSystem.swift
// Onyx Design System — The Cognitive Atelier
// Premium design tokens: elevation, color, typography, shadow, animation
// PRD Section 4: "Every screen should feel like opening a $300 leather notebook
// that happens to be alive with intelligence."

import SwiftUI

// MARK: - Onyx Colors

/// The Onyx color architecture.
/// 5-layer elevation system + tonal accent palette + fixed text hierarchy.
struct OnyxColors {

    // MARK: Elevation Stack (The "Onyx Stack")
    // Each step is a deliberate 7-8 lightness increase with subtle blue-violet undertone.

    struct Elevation {
        /// L0 — True background, infinite canvas, behind everything
        static let void = Color(hex: "08080C")
        /// L1 — Primary surface, the "floor" of each view
        static let base = Color(hex: "0F0F14")
        /// L2 — Card backgrounds, primary containers
        static let raised = Color(hex: "16161E")
        /// L3 — Hover states, active cards, modal backgrounds
        static let elevated = Color(hex: "1E1E28")
        /// L4 — Popovers, tooltips, dropdown menus, toolbar
        static let floating = Color(hex: "262632")
    }

    // MARK: Accent Palette (Tonal — 3 primary + 1 alert)

    struct Accent {
        /// Primary actions, AI elements, links — desaturated indigo
        static let iris = Color(hex: "8B8FE8")
        /// XP, achievements, progress — muted gold (replaces #FFD700)
        static let amber = Color(hex: "C4A87A")
        /// Success, health, positive trends — muted green
        static let sage = Color(hex: "7BAF8E")
        /// Warnings, attention, declining trends — muted rose
        static let rose = Color(hex: "C48B8B")
    }

    // MARK: Dimension Colors — Desaturated (~40% saturation)
    // Used in Sanctuary overview and cross-context references.

    struct Dimension {
        static let cognitive = Color(hex: "7B7EC0")
        static let creative = Color(hex: "C4A870")
        static let physiological = Color(hex: "6BAF8E")
        static let behavioral = Color(hex: "7199C4")
        static let knowledge = Color(hex: "9585C0")
        static let reflection = Color(hex: "C07B9E")

        /// Look up desaturated color for a dimension.
        static func color(for dimension: LevelDimension) -> Color {
            switch dimension {
            case .cognitive: return cognitive
            case .creative: return creative
            case .physiological: return physiological
            case .behavioral: return behavioral
            case .knowledge: return knowledge
            case .reflection: return reflection
            }
        }
    }

    // MARK: Dimension Colors — Full Saturation
    // Used ONLY inside that dimension's detail view for the primary metric and active data.
    // Creates a "lights come on" effect when entering a dimension.

    struct DimensionVivid {
        static let cognitive = Color(hex: "6366F1")
        static let creative = Color(hex: "F59E0B")
        static let physiological = Color(hex: "10B981")
        static let behavioral = Color(hex: "3B82F6")
        static let knowledge = Color(hex: "8B5CF6")
        static let reflection = Color(hex: "EC4899")

        /// Look up vivid color for a dimension.
        static func color(for dimension: LevelDimension) -> Color {
            switch dimension {
            case .cognitive: return cognitive
            case .creative: return creative
            case .physiological: return physiological
            case .behavioral: return behavioral
            case .knowledge: return knowledge
            case .reflection: return reflection
            }
        }
    }

    // MARK: Text Hierarchy (Fixed colors, not opacity-based)

    struct Text {
        /// Primary — slightly warm, not pure white, reduces glare
        static let primary = Color(hex: "E8E8EC")
        /// Secondary — reduced emphasis, fixed color
        static let secondary = Color(hex: "9898A8")
        /// Tertiary — hints, captions, deliberate muting
        static let tertiary = Color(hex: "5C5C6E")
        /// Muted — timestamps, fine print, barely there
        static let muted = Color(hex: "3E3E4E")
    }
}

// MARK: - Onyx Typography

/// Typography pairings: SF Pro Display + New York (serif accent).
/// Hero metrics go ultralight. Section titles get New York serif.
/// ALL CAPS are replaced with sentence case + tracking.
struct OnyxTypography {

    // MARK: Hero Metrics — precision instrument feel

    /// 56pt Ultralight — Cosmo Index, dimension scores
    static let heroMetric = Font.system(size: 56, weight: .ultraLight, design: .default)

    /// 32pt Light — secondary hero values, large card metrics
    static let largeMetric = Font.system(size: 32, weight: .light, design: .default)

    /// 22pt Light — compact hero values
    static let compactMetric = Font.system(size: 22, weight: .light, design: .default)

    /// 28pt Light — medium metrics
    static let mediumMetric = Font.system(size: 28, weight: .light, design: .default)

    // MARK: Section Titles — New York serif for "leather notebook" feel

    /// 15pt New York Regular — section titles in dimension views
    static let sectionTitle = Font.system(size: 15, weight: .regular, design: .serif)

    // MARK: View Titles

    /// 24pt SF Pro Display Semibold — "Sanctuary", "Plannerum"
    static let viewTitle = Font.system(size: 24, weight: .semibold, design: .default)

    // MARK: Card Typography

    /// 13pt SF Pro Display Medium — card titles
    static let cardTitle = Font.system(size: 13, weight: .medium, design: .default)

    // MARK: Body

    /// 14pt SF Pro Text Regular — general body text
    static let body = Font.system(size: 14, weight: .regular, design: .default)

    // MARK: Labels & Metadata

    /// 11pt SF Pro Text Medium — labels, metadata, badges
    static let label = Font.system(size: 11, weight: .medium, design: .default)

    // MARK: Micro

    /// 10pt SF Mono Regular — timestamps, fine-print data
    static let micro = Font.system(size: 10, weight: .regular, design: .monospaced)

    // MARK: Tracking Constants (for use with .tracking())

    /// Section title tracking (+0.3pt)
    static let sectionTitleTracking: CGFloat = 0.3

    /// View title tracking (+1.5pt)
    static let viewTitleTracking: CGFloat = 1.5

    /// Card title tracking (+0.2pt)
    static let cardTitleTracking: CGFloat = 0.2

    /// Label tracking (+0.5pt)
    static let labelTracking: CGFloat = 0.5
}

// MARK: - Onyx Shadows

/// Neutral-only shadow system. Color glow reserved for the primary interactive element.
/// No more purple-tinted shadows. Shadows use pure black at calibrated opacities.

enum OnyxElevation: CaseIterable {
    /// L2 on L1 — card at rest
    case resting
    /// L3 on L1 — card hovered
    case hovered
    /// L4 on L1 — floating (popover, tooltip)
    case floating
}

struct OnyxShadowValues {
    let contactOpacity: CGFloat
    let contactBlur: CGFloat
    let contactY: CGFloat
    let ambientOpacity: CGFloat
    let ambientBlur: CGFloat
    let ambientY: CGFloat

    static func values(for elevation: OnyxElevation) -> OnyxShadowValues {
        switch elevation {
        case .resting:
            return OnyxShadowValues(
                contactOpacity: 0.08, contactBlur: 1, contactY: 1,
                ambientOpacity: 0.20, ambientBlur: 6, ambientY: 2
            )
        case .hovered:
            return OnyxShadowValues(
                contactOpacity: 0.10, contactBlur: 2, contactY: 1,
                ambientOpacity: 0.28, ambientBlur: 10, ambientY: 4
            )
        case .floating:
            return OnyxShadowValues(
                contactOpacity: 0.12, contactBlur: 3, contactY: 2,
                ambientOpacity: 0.35, ambientBlur: 16, ambientY: 6
            )
        }
    }
}

/// ViewModifier that applies the Onyx dual-layer neutral shadow.
struct OnyxShadowModifier: ViewModifier {
    let elevation: OnyxElevation
    var accentGlow: Color?

    func body(content: Content) -> some View {
        let v = OnyxShadowValues.values(for: elevation)
        content
            .shadow(
                color: Color.black.opacity(v.contactOpacity),
                radius: v.contactBlur,
                x: 0, y: v.contactY
            )
            .shadow(
                color: Color.black.opacity(v.ambientOpacity),
                radius: v.ambientBlur,
                x: 0, y: v.ambientY
            )
            .shadow(
                color: (accentGlow ?? Color.clear).opacity(accentGlow != nil ? 0.12 : 0),
                radius: 20,
                x: 0, y: 0
            )
    }
}

extension View {
    /// Apply Onyx elevation shadow. Optionally pass a dimension/accent color for a focused glow.
    func onyxShadow(_ elevation: OnyxElevation, accentGlow: Color? = nil) -> some View {
        modifier(OnyxShadowModifier(elevation: elevation, accentGlow: accentGlow))
    }
}

// MARK: - Onyx Springs (Animation)

/// Critically-damped spring variants for data views.
/// Reserve bouncy springs for Thinkspace canvas only.
struct OnyxSpring {

    /// Instant micro-interaction (0.12s, critically damped)
    static let micro = Animation.spring(response: 0.12, dampingFraction: 0.95)

    /// Quick hover feedback (0.15s, near-critically damped)
    static let hover = Animation.spring(response: 0.15, dampingFraction: 0.92)

    /// Standard transition (0.35s, critically damped)
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.95)

    /// Card entrance (0.4s, near-critically damped)
    static let cardEntrance = Animation.spring(response: 0.40, dampingFraction: 0.92)

    /// View transition / dimension entry (0.4s spring, slight exhale feel)
    static let viewTransition = Animation.spring(response: 0.40, dampingFraction: 0.90)

    /// Metric count-up settle (0.6s easeOut)
    static let metricSettle = Animation.easeOut(duration: 0.6)

    /// Staggered card entrance (50ms between each — deliberate, premium cascade)
    static func staggered(index: Int, baseDelay: TimeInterval = 0.05) -> Animation {
        cardEntrance.delay(Double(index) * baseDelay)
    }

    /// Cascade for menu items (35ms — slightly faster for lists)
    static func cascade(index: Int) -> Animation {
        standard.delay(Double(index) * 0.035)
    }
}

// MARK: - Onyx Layout Constants

struct OnyxLayout {
    /// Card corner radius (tighter than current 16pt for precision)
    static let cardCornerRadius: CGFloat = 14

    /// Card internal padding
    static let cardPadding: CGFloat = 20

    /// Progress line default height
    static let progressLineHeight: CGFloat = 2

    /// Week grid square size
    static let weekSquareSize: CGFloat = 6

    /// Section divider opacity
    static let dividerOpacity: CGFloat = 0.04

    /// Metric group spacing
    static let metricGroupSpacing: CGFloat = 32
}
