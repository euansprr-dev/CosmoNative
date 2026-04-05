// CosmoOS/UI/Codex/CodexCardHoverModifier.swift
// Shared hover interaction for Codex cards — scale, shadow, and border glow.

import SwiftUI

struct CodexCardHoverModifier: ViewModifier {
    let accentColor: Color
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(
                color: isHovered ? accentColor.opacity(0.15) : .clear,
                radius: isHovered ? 12 : 0,
                y: isHovered ? 4 : 0
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(
                        isHovered ? accentColor.opacity(0.3) : .clear,
                        lineWidth: 1.5
                    )
            )
            .animation(ProMotionSprings.hover, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func codexHover(accent: Color) -> some View {
        modifier(CodexCardHoverModifier(accentColor: accent))
    }
}
