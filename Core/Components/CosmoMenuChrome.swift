// CosmoOS/Core/Components/CosmoMenuChrome.swift
// Unified premium container styling for all CosmoOS menus
// Gradient border, floating shadow, entrance animation, haptics

import SwiftUI

struct CosmoMenuChrome: ViewModifier {
    /// How far the panel's drop shadow visibly extends past the panel body
    /// (globalSidebar role: blur radius 18 + y-offset 6). Anything positioning
    /// a menu inside a clipped container (editor columns, scroll viewports)
    /// must clamp the BODY this far from the clip edge, or the shadow gets
    /// sliced into a hard line at the boundary.
    static let shadowClearance: CGFloat = 40

    var cornerRadius: CGFloat = 14
    var darkMode: Bool = false

    @State private var menuAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // INVARIANT: the glass is a BACKDROP layer behind the content, never
        // the content's container. The AppKit glass layer latches its
        // composite when its layout size changes inside an animated
        // transaction (see glass_layer_animated_frame_latch) — menus resize
        // as their rows change, and with rows rendered INSIDE glassEffect the
        // on-screen pixels froze while SwiftUI kept rendering fresh bodies
        // (the @-menu "results never update while typing" bug). Content in
        // the plain SwiftUI tree can never be captured by the latch.
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background {
                CosmoGlassPanel(role: .globalSidebar, cornerRadius: cornerRadius) {
                    Color.clear
                }
            }
            .scaleEffect(menuAppeared ? 1 : 0.95)
            .opacity(menuAppeared ? 1 : 0)
            // No animated blur: every entrance frame had to render the menu
            // offscreen, Gaussian-blur it, and composite it over a glass
            // backdrop that is itself re-sampling — the classic ProMotion
            // frame-budget killer. Scale + opacity carry the entrance.
            .onAppear {
                CosmicHaptics.shared.play(.menuAppear)
                // Every menu in the app enters through this modifier — the
                // Reduce Motion gate lives HERE so call sites inherit it.
                withAnimation(reduceMotion ? nil : ProMotionSprings.bouncy) {
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
