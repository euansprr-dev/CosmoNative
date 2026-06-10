// CosmoOS/Core/Components/CosmoMenuChrome.swift
// Unified premium container styling for all CosmoOS menus
// Gradient border, floating shadow, entrance animation, haptics

import SwiftUI

struct CosmoMenuChrome: ViewModifier {
    var cornerRadius: CGFloat = 14
    var darkMode: Bool = false

    @State private var menuAppeared = false

    func body(content: Content) -> some View {
        CosmoGlassPanel(
            role: .globalSidebar,
            cornerRadius: cornerRadius
        ) {
            content
        }
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
