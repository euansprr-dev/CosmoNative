// CosmoOS/Core/Components/CosmoSurfaceGeometry.swift
// The window-in-window ladder: one set of numbers for every surface that puts a
// rounded content well inside a rounded container, with a chrome band above it.
//
// Before this file the ladder was six hand-typed literals — `14` declared in
// four files, `7` in two — and they drifted, because nothing forced them to
// agree. A bench sheet rendered a 14pt corner inside an 8pt pane: the inner
// shape was ROUNDER than the container holding it, which is the geometry
// equivalent of a crooked picture frame.
//
// The fix is not better literals. It is derivation: the inner corner is a
// FUNCTION of the outer corner and the inset (Apple's concentricity rule —
// nested rounded shapes share a corner center), expressed through macOS 26's
// `ConcentricRectangle` so the shape resolves against whatever container it
// actually lands in.
//
// July 2026

import SwiftUI

// MARK: - Metrics

/// The one place a surface number lives. Everything else derives.
enum CosmoSurfaceMetrics {

    /// The outer container corner: a pane, or a full-screen workspace.
    ///
    /// 22 because the unified sidebar is 22 (`UnifiedSidebar.panelCornerRadius`)
    /// and a pane is its SIBLING — both sit directly on `DS.bg`. A pane at 8
    /// beside a sidebar at 22 was the loudest geometric mismatch on screen.
    static let containerCorner: CGFloat = 22

    /// The gutter between a container and the window inset inside it. Used on
    /// all three free sides (leading, trailing, bottom); the chrome band owns
    /// the top.
    static let windowInset: CGFloat = 10

    /// Concentric result: `containerCorner - windowInset`. Never write this
    /// number in a view — it is the FLOOR handed to `.concentric(minimum:)` so
    /// the shape still resolves correctly if container-shape propagation is
    /// unavailable, and so raising `containerCorner` raises this with it.
    static var innerCorner: CGFloat { containerCorner - windowInset }

    /// Top gutter above the chrome band. Matches `windowInset` so the band is
    /// framed by the same gutter on all four sides of the container.
    static let chromeTopInset: CGFloat = 10

    /// Gap between the chrome band and the window beneath it.
    static let chromeGap: CGFloat = DS.space8

    /// The container shape itself — set on a host so concentric children can
    /// resolve against it.
    static var containerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: containerCorner, style: .continuous)
    }
}

// MARK: - Inner window

/// The rounded content well inside a container: bench sheets (Idea, Study,
/// SwipeStudy, Connection), pane wells (assistant, browser), and the pane
/// canvas. One hairline, one shape, one set of insets.
///
/// The shape is `ConcentricRectangle`, so it derives its corner from the
/// nearest container shape rather than asserting one. That matters because
/// `WorkbenchShell` renders BOTH full-screen and inside a pane — the same view,
/// two different containers. No hardcoded radius can be concentric in both;
/// this can.
private struct CosmoInnerWindow: ViewModifier {
    let insetTop: Bool

    private var shape: ConcentricRectangle {
        ConcentricRectangle(
            corners: .concentric(minimum: .fixed(CosmoSurfaceMetrics.innerCorner)),
            isUniform: true
        )
    }

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            // The hairline is the ONLY stroke in the ladder — the container's
            // own border is `DS.borderSubtle` too, so a heavy line never sits
            // 10pt from a light one (depth, not weight).
            .overlay(shape.stroke(DS.borderSubtle, lineWidth: 1))
            .padding(.top, insetTop ? CosmoSurfaceMetrics.windowInset : 0)
            .padding(.horizontal, CosmoSurfaceMetrics.windowInset)
            .padding(.bottom, CosmoSurfaceMetrics.windowInset)
    }
}

extension View {

    /// Clip, stroke, and inset this view as the container's inner window.
    ///
    /// - Parameter insetTop: `true` when nothing sits above the window (no
    ///   chrome band); `false` when a chrome band already supplied the top
    ///   gutter via `cosmoChromeBandInsets()`.
    func cosmoInnerWindow(insetTop: Bool = false) -> some View {
        modifier(CosmoInnerWindow(insetTop: insetTop))
    }

    /// Declare this view as a concentric container. Children using
    /// `cosmoInnerWindow()` resolve their corner against this shape.
    ///
    /// Applied at the two hosting sites — the pane, and a full-screen focus
    /// mode — so a bench gets the right corner in both without knowing which
    /// one it is in.
    func cosmoSurfaceContainer() -> some View {
        containerShape(CosmoSurfaceMetrics.containerShape)
    }

    /// The gutter around a chrome band sitting above an inner window. Side
    /// inset matches `windowInset` so the leading island's edge lands exactly
    /// on the window's edge, rather than 6pt inboard of it.
    func cosmoChromeBandInsets() -> some View {
        padding(.horizontal, CosmoSurfaceMetrics.windowInset)
            .padding(.top, CosmoSurfaceMetrics.chromeTopInset)
    }
}
