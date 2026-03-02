// CosmoOS/Core/Onyx/OnyxDesignSystem.swift
// Onyx Design System — Greenhouse Light Mode
// Premium design tokens: elevation, color, typography, shadow, animation
// March 2026 — Light-mode rebrand

import SwiftUI

// MARK: - Onyx Colors

/// The Onyx color architecture — adapted for light mode.
/// 5-layer elevation system + tonal accent palette + fixed text hierarchy.
struct OnyxColors {

    // MARK: Elevation Stack (Light Mode)
    // Each step uses warm whites with subtle shadow-based elevation.

    struct Elevation {
        /// L0 — True background, infinite canvas, behind everything
        static let void = Color(hex: "F2F1ED")
        /// L1 — Primary surface, the "floor" of each view
        static let base = Color(hex: "F8F7F4")
        /// L2 — Card backgrounds, primary containers
        static let raised = Color(hex: "FFFFFF")
        /// L3 — Hover states, active cards, modal backgrounds
        static let elevated = Color(hex: "FFFFFF")
        /// L4 — Popovers, tooltips, dropdown menus, toolbar
        static let floating = Color(hex: "FFFFFF")
    }

    // MARK: Accent Palette (Tonal — 3 primary + 1 alert)

    struct Accent {
        /// Primary actions, AI elements, links — forest green
        static let iris = Color(hex: "2D6A4F")
        /// XP, achievements, progress — muted gold
        static let amber = Color(hex: "C4A87A")
        /// Success, health, positive trends — green
        static let sage = Color(hex: "38B764")
        /// Warnings, attention, declining trends — rose
        static let rose = Color(hex: "DC3545")
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

    // MARK: Text Hierarchy (Fixed colors for light mode)

    struct Text {
        /// Primary — near-black, crisp on white
        static let primary = Color(hex: "1A1A1F")
        /// Secondary — medium gray, reduced emphasis
        static let secondary = Color(hex: "6B6B78")
        /// Tertiary — hints, captions, deliberate muting
        static let tertiary = Color(hex: "767685")
        /// Muted — timestamps, fine print, lightest readable
        static let muted = Color(hex: "C8C8D0")
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

    // MARK: Section Titles — New York serif

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

/// Light-mode shadow system. Soft, natural shadows at reduced opacity.
/// No colored shadows. Shadows use pure black at calibrated opacities.

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
                contactOpacity: 0.04, contactBlur: 2, contactY: 1,
                ambientOpacity: 0.02, ambientBlur: 8, ambientY: 2
            )
        case .hovered:
            return OnyxShadowValues(
                contactOpacity: 0.05, contactBlur: 3, contactY: 1,
                ambientOpacity: 0.04, ambientBlur: 12, ambientY: 4
            )
        case .floating:
            return OnyxShadowValues(
                contactOpacity: 0.06, contactBlur: 4, contactY: 2,
                ambientOpacity: 0.05, ambientBlur: 20, ambientY: 6
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
                color: (accentGlow ?? Color.clear).opacity(accentGlow != nil ? 0.08 : 0),
                radius: 16,
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
    /// Card corner radius
    static let cardCornerRadius: CGFloat = 14

    /// Card internal padding
    static let cardPadding: CGFloat = 20

    /// Progress line default height
    static let progressLineHeight: CGFloat = 2

    /// Week grid square size
    static let weekSquareSize: CGFloat = 6

    /// Section divider opacity
    static let dividerOpacity: CGFloat = 0.08

    /// Metric group spacing
    static let metricGroupSpacing: CGFloat = 32
}
