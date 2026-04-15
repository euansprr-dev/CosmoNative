// CosmoOS/UI/Codex/CodexCardHoverModifier.swift
// Akashic hover interaction — gilt border transition, warm shadow, subtle lift.
// April 2026 — Akashic Records Premium Redesign

import SwiftUI

struct CodexCardHoverModifier: ViewModifier {
    let accentColor: Color
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .shadow(
                color: isHovered ? DS.gilt.opacity(0.15) : .clear,
                radius: isHovered ? 10 : 0,
                y: isHovered ? 3 : 0
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(
                        isHovered ? DS.giltMuted : .clear,
                        lineWidth: 0.5
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
