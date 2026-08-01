// CosmoOS/Canvas/CanvasBlockRenderTier.swift
// Zoom-level-of-detail for canvas cards.
//
// At overview zoom every block sits inside the preload rect, so a 100–500
// block canvas mounts every card at full fidelity — full chrome, shadow
// stacks, transcript rows — even though a 300pt card is rendering 75–135pt
// wide and none of that chrome is legible. Cards read the tier from the
// environment and shed illegible chrome below these thresholds; the swap is
// visually indistinguishable at the scales where it happens.
//
// Tier flips ride the QUANTIZED effective scale (0.125 buckets during live
// gestures, exact at commit — CanvasViewportSnapshotPolicy), so a pinch never
// flips tiers per frame.

import SwiftUI

enum CanvasBlockRenderTier: Equatable {
    /// Normal card — full chrome, interactions, live media.
    case full
    /// Below ~45%: thumbnail + title only. No transcript row, hover states,
    /// resize zones, or selection toolbar; a single soft shadow.
    case poster
    /// Below ~22%: surface + media only — text is sub-3pt at this scale and
    /// typesets to smudge.
    case minimal

    // Both thresholds sit BETWEEN the live 0.125 zoom quantization buckets
    // (0.375 < 0.45 < 0.5; 0.125 < 0.22 < 0.25) so a bucket value can never
    // land exactly on a threshold.
    static let posterThreshold: CGFloat = 0.45
    static let minimalThreshold: CGFloat = 0.22

    static func tier(forEffectiveScale scale: CGFloat) -> CanvasBlockRenderTier {
        if scale < minimalThreshold { return .minimal }
        if scale < posterThreshold { return .poster }
        return .full
    }

    var isFull: Bool { self == .full }
    /// Chrome that only matters when a card is readable/interactive.
    var showsInteractiveChrome: Bool { self == .full }
    var showsText: Bool { self != .minimal }
}

private struct CanvasBlockRenderTierKey: EnvironmentKey {
    static let defaultValue: CanvasBlockRenderTier = .full
}

extension EnvironmentValues {
    var canvasBlockRenderTier: CanvasBlockRenderTier {
        get { self[CanvasBlockRenderTierKey.self] }
        set { self[CanvasBlockRenderTierKey.self] = newValue }
    }
}
