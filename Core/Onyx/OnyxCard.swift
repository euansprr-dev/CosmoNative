// CosmoOS/Core/Onyx/OnyxCard.swift
// Borderless elevation card — replaces SanctuaryCard and gray-bordered containers.
// PRD Section 6.1: "Depth Through Elevation, Not Borders"

import SwiftUI

/// Hover behavior for OnyxCard.
enum OnyxHoverBehavior {
    /// Card lifts to elevated shadow on hover
    case lift
    /// Card gains a subtle accent glow on hover
    case glow
    /// No hover effect
    case none
}

/// Premium borderless card using the Onyx elevation system.
/// No visible borders by default — elevation creates implicit containment.
struct OnyxCard<Content: View>: View {
    let elevation: OnyxElevation
    var accentEdge: Edge?
    var accentColor: Color?
    var hoverBehavior: OnyxHoverBehavior
    @ViewBuilder var content: () -> Content

    @State private var isHovered = false

    init(
        elevation: OnyxElevation = .resting,
        accentEdge: Edge? = nil,
        accentColor: Color? = nil,
        hoverBehavior: OnyxHoverBehavior = .lift,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.elevation = elevation
        self.accentEdge = accentEdge
        self.accentColor = accentColor
        self.hoverBehavior = hoverBehavior
        self.content = content
    }

    private var backgroundForElevation: Color {
        switch currentElevation {
        case .resting: return OnyxColors.Elevation.raised
        case .hovered: return OnyxColors.Elevation.elevated
        case .floating: return OnyxColors.Elevation.floating
        }
    }

    private var currentElevation: OnyxElevation {
        guard isHovered else { return elevation }
        switch hoverBehavior {
        case .lift:
            // Step up one elevation level on hover
            switch elevation {
            case .resting: return .hovered
            case .hovered: return .floating
            case .floating: return .floating
            }
        case .glow, .none:
            return elevation
        }
    }

    private var glowColor: Color? {
        guard isHovered, hoverBehavior == .glow else { return nil }
        return accentColor
    }

    var body: some View {
        content()
            .padding(OnyxLayout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                    .fill(backgroundForElevation)
            )
            .overlay(accentEdgeOverlay)
            .overlay(hoverBorderOverlay)
            .clipShape(RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius))
            .onyxShadow(currentElevation, accentGlow: glowColor)
            .onHover { hovering in
                withAnimation(OnyxSpring.hover) {
                    isHovered = hovering
                }
            }
    }

    // MARK: - Accent edge (optional thin color bar on one edge)

    @ViewBuilder
    private var accentEdgeOverlay: some View {
        if let edge = accentEdge, let color = accentColor {
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(Color.clear)
                .overlay(alignment: alignment(for: edge)) {
                    edgeBar(color: color, edge: edge)
                }
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func edgeBar(color: Color, edge: Edge) -> some View {
        switch edge {
        case .leading:
            color
                .frame(width: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: OnyxLayout.cardCornerRadius,
                        bottomLeadingRadius: OnyxLayout.cardCornerRadius
                    )
                )
        case .trailing:
            color
                .frame(width: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomTrailingRadius: OnyxLayout.cardCornerRadius,
                        topTrailingRadius: OnyxLayout.cardCornerRadius
                    )
                )
        case .top:
            color
                .frame(height: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: OnyxLayout.cardCornerRadius,
                        topTrailingRadius: OnyxLayout.cardCornerRadius
                    )
                )
        case .bottom:
            color
                .frame(height: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: OnyxLayout.cardCornerRadius,
                        bottomTrailingRadius: OnyxLayout.cardCornerRadius
                    )
                )
        }
    }

    private func alignment(for edge: Edge) -> Alignment {
        switch edge {
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    // MARK: - Hover border (1pt accent on the hovered/most-important card)

    @ViewBuilder
    private var hoverBorderOverlay: some View {
        if isHovered, let color = accentColor, hoverBehavior == .glow {
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .stroke(color.opacity(0.3), lineWidth: 1)
        }
    }
}
