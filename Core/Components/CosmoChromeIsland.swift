// CosmoOS/Core/Components/CosmoChromeIsland.swift
// The chrome-island grammar: floating glass capsules grouped by function,
// sitting directly over content on one shared baseline — never a full-width
// bar. The material and ghosting manner match NavigationTrailChrome, so every
// island in the app reads as one family. Islands recede while the user works
// and wake on hover (the "disappear" law).

import SwiftUI
import AppKit

/// One baseline for every floating chrome island in the app.
enum CosmoChromeMetrics {
    static let height: CGFloat = 40      // Island height (capsule ⇒ radius 20)
    static let topInset: CGFloat = CosmoSurfaceMetrics.chromeTopInset
    /// Matches `CosmoSurfaceMetrics.windowInset` so the leading island's edge
    /// lands EXACTLY on the edge of the inner window beneath it. At the old 16
    /// the band was 6pt narrower than its own sheet on each side — two visible
    /// edges 6pt apart, which reads as a mistake rather than a decision.
    static let sideInset: CGFloat = CosmoSurfaceMetrics.windowInset
    static let islandSpacing: CGFloat = 10

    /// A host's width, quantized to 24pt steps: pane-divider drags must not
    /// invalidate the chrome row on every frame.
    static func quantizedWidth(_ width: CGFloat) -> CGFloat {
        (width / 24).rounded() * 24
    }

    /// Hard title width for a center pill: the measured text, capped by the
    /// row's budget. A hard frame is the only shape that both HUGS a short
    /// title (a flexible `maxWidth` frame greedily fills, ballooning the glass
    /// island) and CAPS a long one (`.fixedSize()` reports the uncapped ideal —
    /// the bug that ran a long title clean over the side islands at pane
    /// widths). Measured at DS.buttonText.weight(.semibold) → 12pt semibold.
    static func measuredTitleWidth(_ title: String, cap: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let measured = (title as NSString)
            .size(withAttributes: [.font: font])
            .width
            .rounded(.up)
        return min(measured + 2, cap)
    }
}

/// A hugging glass capsule for a functional group of controls.
struct CosmoChromeIsland<Content: View>: View {
    /// True while the user is working in the content (reading, typing) —
    /// the island quiets to 60% and wakes on hover.
    var recede: Bool = false
    @ViewBuilder let content: Content

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space6) {
            content
        }
        .padding(.horizontal, DS.space8)
        .frame(height: CosmoChromeMetrics.height)
        .glassEffect(.regular, in: .capsule)
        .opacity(recede && !isHovered ? 0.6 : 1)
        .animation(ProMotionSprings.gentle, value: recede)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }
}

/// Lays islands out on the shared baseline: leading cluster left, trailing
/// cluster right, and the center island TRULY centered regardless of how wide
/// the side clusters are.
struct CosmoChromeRow<Leading: View, Center: View, Trailing: View>: View {
    /// Set false when a parent container already provides the chrome insets.
    var insetsEnabled: Bool = true
    /// True = the center island is truly centered via ZStack (full-screen
    /// workspaces). False = the center flows between the side clusters —
    /// at pane widths absolute centering can overlap the clusters, and flow
    /// layout makes overlap structurally impossible. Constant per mount or
    /// driven by a discrete width breakpoint — never toggled on animated state.
    var centersAbsolutely: Bool = true
    @ViewBuilder let leading: Leading
    @ViewBuilder let center: Center
    @ViewBuilder let trailing: Trailing

    var body: some View {
        rowLayout
            .padding(.horizontal, insetsEnabled ? CosmoChromeMetrics.sideInset : 0)
            .padding(.top, insetsEnabled ? CosmoChromeMetrics.topInset : 0)
            // topLeading, not top: when a host is squeezed below the row's
            // minimum, a centered overflow clips BOTH edges — the back/sidebar
            // cluster must never be the thing that falls off screen.
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var rowLayout: some View {
        if centersAbsolutely {
            ZStack {
                HStack(spacing: CosmoChromeMetrics.islandSpacing) {
                    leading
                    Spacer(minLength: CosmoChromeMetrics.islandSpacing)
                    trailing
                }
                center
            }
        } else {
            HStack(spacing: CosmoChromeMetrics.islandSpacing) {
                leading
                Spacer(minLength: CosmoChromeMetrics.islandSpacing)
                center
                Spacer(minLength: CosmoChromeMetrics.islandSpacing)
                trailing
            }
        }
    }
}
