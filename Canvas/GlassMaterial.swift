// CosmoOS/Canvas/GlassMaterial.swift
// Premium glass surface modifier for floating blocks
// Creates the "Cosmic Glass" effect from the Cosmo Bible

import SwiftUI

// MARK: - Glass Surface Modifier

/// A view modifier that applies a premium surface effect.
/// Apple-style approach: solid backgrounds for cards, materials only for overlays.
/// - Solid white background with subtle gradient (default, best for performance)
/// - Optional blur material for overlays (set useMaterial: true)
/// - Gradient border highlight
/// - Single optimized shadow
struct GlassSurface: ViewModifier {
    let tint: Color
    let intensity: Double
    let cornerRadius: CGFloat
    let isElevated: Bool
    let useMaterial: Bool  // Only use material for overlays/chrome, not cards

    init(
        tint: Color = .white,
        intensity: Double = 0.05,
        cornerRadius: CGFloat = 12,
        isElevated: Bool = false,
        useMaterial: Bool = false  // Default to solid for performance (Apple-style)
    ) {
        self.tint = tint
        self.intensity = intensity
        self.cornerRadius = cornerRadius
        self.isElevated = isElevated
        self.useMaterial = useMaterial
    }

    func body(content: Self.Content) -> some View {
        content
            // Layer 1: Background (solid for cards, material for overlays)
            .background(backgroundLayer)
            // Layer 2: Tint overlay
            .background(
                tint.opacity(intensity),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            // Layer 3: Gradient border highlight
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.6),
                                .white.opacity(0.2),
                                tint.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            // Layer 4: Single optimized shadow (GPU-friendly)
            .shadow(
                color: .black.opacity(isElevated ? 0.12 : 0.08),
                radius: isElevated ? 12 : 8,
                y: isElevated ? 5 : 3
            )
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if useMaterial {
            // Material for overlays/chrome only
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
        } else {
            // Solid background for cards (Apple-style, better performance)
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(CosmoColors.softWhite)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), tint.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
}

// MARK: - Glass Card Modifier

/// A complete glass card with all premium effects applied.
/// Use this for floating blocks, modals, and overlays.
struct GlassCard: ViewModifier {
    let accentColor: Color
    let isHovered: Bool
    let isExpanded: Bool

    init(
        accentColor: Color = CosmoColors.lavender,
        isHovered: Bool = false,
        isExpanded: Bool = false
    ) {
        self.accentColor = accentColor
        self.isHovered = isHovered
        self.isExpanded = isExpanded
    }

    private var shadowRadius: CGFloat {
        if isExpanded { return 24 }
        if isHovered { return 16 }
        return 10
    }

    private var shadowOpacity: Double {
        if isExpanded { return 0.25 }
        if isHovered { return 0.2 }
        return 0.12
    }

    func body(content: Self.Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(CosmoColors.softWhite)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(isExpanded ? 0.4 : 0.2),
                                CosmoColors.glassGrey.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isExpanded ? 2 : 1
                    )
            )
            // Single optimized shadow (GPU-friendly)
            .shadow(
                color: Color.black.opacity(isExpanded ? 0.15 : (isHovered ? 0.12 : 0.08)),
                radius: shadowRadius,
                y: isExpanded ? 6 : 4
            )
    }
}

// MARK: - Frosted Glass Modifier

/// A frosted glass effect for overlays and modals.
/// More opaque than GlassSurface for better text readability.
struct FrostedGlass: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double

    init(cornerRadius: CGFloat = 16, opacity: Double = 0.95) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
    }

    func body(content: Self.Content) -> some View {
        content
            .background(
                ZStack {
                    // Frosted base
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    // White overlay for opacity
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(opacity - 0.5))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
    }
}

// MARK: - Accent Seam

/// A vertical accent bar for cards to indicate entity type.
/// From the Cosmo Bible: "A 3px gradient bar on the left edge".
struct AccentSeam: View {
    let color: Color
    let position: Edge

    init(color: Color, position: Edge = .leading) {
        self.color = color
        self.position = position
    }

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.5)],
                    startPoint: position == .leading ? .top : .leading,
                    endPoint: position == .leading ? .bottom : .trailing
                )
            )
            .frame(width: position == .leading || position == .trailing ? 3 : nil)
            .frame(height: position == .top || position == .bottom ? 3 : nil)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply a glass surface effect
    func glassSurface(
        tint: Color = .white,
        intensity: Double = 0.05,
        cornerRadius: CGFloat = 12,
        isElevated: Bool = false
    ) -> some View {
        modifier(GlassSurface(
            tint: tint,
            intensity: intensity,
            cornerRadius: cornerRadius,
            isElevated: isElevated
        ))
    }

    /// Apply a glass card effect
    func glassCard(
        accentColor: Color = CosmoColors.lavender,
        isHovered: Bool = false,
        isExpanded: Bool = false
    ) -> some View {
        modifier(GlassCard(
            accentColor: accentColor,
            isHovered: isHovered,
            isExpanded: isExpanded
        ))
    }

    /// Apply a frosted glass effect
    func frostedGlass(
        cornerRadius: CGFloat = 16,
        opacity: Double = 0.95
    ) -> some View {
        modifier(FrostedGlass(
            cornerRadius: cornerRadius,
            opacity: opacity
        ))
    }

    /// Add an accent seam to indicate entity type
    func withAccentSeam(_ color: Color, position: Edge = .leading) -> some View {
        overlay(alignment: position.alignment) {
            AccentSeam(color: color, position: position)
        }
    }
}

// MARK: - Edge Extension

private extension Edge {
    var alignment: Alignment {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

// MARK: - Preview

#if DEBUG
struct GlassMaterial_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [CosmoColors.skyBlue.opacity(0.3), CosmoColors.lavender.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Glass Surface
                Text("Glass Surface")
                    .font(CosmoTypography.body)
                    .padding(20)
                    .glassSurface(tint: CosmoColors.lavender, isElevated: true)

                // Glass Card
                Text("Glass Card")
                    .font(CosmoTypography.body)
                    .padding(20)
                    .frame(width: 200)
                    .glassCard(accentColor: CosmoColors.emerald, isHovered: true)

                // Frosted Glass
                Text("Frosted Glass")
                    .font(CosmoTypography.body)
                    .padding(20)
                    .frostedGlass()

                // With Accent Seam
                Text("With Accent Seam")
                    .font(CosmoTypography.body)
                    .padding(20)
                    .background(CosmoColors.softWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .withAccentSeam(CosmoMentionColors.idea)
            }
            .padding(40)
        }
        .frame(width: 400, height: 500)
    }
}
#endif
