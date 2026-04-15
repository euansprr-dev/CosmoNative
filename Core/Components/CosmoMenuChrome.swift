// CosmoOS/Core/Components/CosmoMenuChrome.swift
// Unified premium container styling for all CosmoOS menus
// Gradient border, floating shadow, entrance animation, haptics

import SwiftUI

struct CosmoMenuChrome: ViewModifier {
    var cornerRadius: CGFloat = 14
    var darkMode: Bool = false

    @State private var menuAppeared = false

    private var borderGradient: LinearGradient {
        if darkMode {
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [DS.accent.opacity(0.4), DS.sepiaBorder],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    func body(content: Content) -> some View {
        content
            .background(darkMode ? DS.bg : DS.vellum)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderGradient, lineWidth: 1)
            )
            .dsFloatingShadow()
            .scaleEffect(menuAppeared ? 1 : 0.95)
            .opacity(menuAppeared ? 1 : 0)
            .blur(radius: menuAppeared ? 0 : 4)
            .onAppear {
                CosmicHaptics.shared.play(.menuAppear)
                withAnimation(ProMotionSprings.bouncy) {
                    menuAppeared = true
                }
            }
    }
}

extension View {
    func cosmoMenuChrome(cornerRadius: CGFloat = 14, darkMode: Bool = false) -> some View {
        modifier(CosmoMenuChrome(cornerRadius: cornerRadius, darkMode: darkMode))
    }
}
