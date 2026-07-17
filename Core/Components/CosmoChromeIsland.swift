// CosmoOS/Core/Components/CosmoChromeIsland.swift
// The chrome-island grammar: floating glass capsules grouped by function,
// sitting directly over content on one shared baseline — never a full-width
// bar. The material and ghosting manner match NavigationTrailChrome, so every
// island in the app reads as one family. Islands recede while the user works
// and wake on hover (the "disappear" law).

import SwiftUI

/// One baseline for every floating chrome island in the app.
enum CosmoChromeMetrics {
    static let height: CGFloat = 40      // Island height (capsule ⇒ radius 20)
    static let topInset: CGFloat = 10
    static let sideInset: CGFloat = 16
    static let islandSpacing: CGFloat = 10
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
    /// layout makes overlap structurally impossible. Constant per mount,
    /// never toggled on animated state.
    var centersAbsolutely: Bool = true
    @ViewBuilder let leading: Leading
    @ViewBuilder let center: Center
    @ViewBuilder let trailing: Trailing

    var body: some View {
        rowLayout
            .padding(.horizontal, insetsEnabled ? CosmoChromeMetrics.sideInset : 0)
            .padding(.top, insetsEnabled ? CosmoChromeMetrics.topInset : 0)
            .frame(maxWidth: .infinity, alignment: .top)
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
