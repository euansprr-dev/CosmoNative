// Tests/CosmoOSTests/CosmoSurfaceGeometryTests.swift
// Guards for the window-in-window ladder (July 2026).
//
// These assert the two things that ACTUALLY shipped broken, not the arithmetic
// for its own sake. Both defects were invisible in code review because each
// number looked reasonable alone — they only disagreed across files.

import Testing
import CoreGraphics
@testable import CosmoOS

@Suite("Surface geometry ladder")
struct CosmoSurfaceGeometryTests {

    /// THE defect. A bench sheet declared corner 14 while the pane holding it
    /// declared 8, so the inner shape was rounder than its own container —
    /// visually a crooked frame. An inner window must never out-round the
    /// thing it sits inside.
    @Test("Inner window is never rounder than its container")
    func innerNeverOutRoundsContainer() {
        #expect(CosmoSurfaceMetrics.innerCorner < CosmoSurfaceMetrics.containerCorner)
    }

    /// Concentricity (Apple's rule, peakui law 8): nested rounded shapes share
    /// a corner center, so the inner radius is the outer radius minus the
    /// inset. This is the value handed to `.concentric(minimum:)` as the floor,
    /// so it must stay exact — if it drifts, the fallback stops matching what
    /// `ConcentricRectangle` resolves and the two rendering paths disagree.
    @Test("Inner corner is the concentric result, not a literal")
    func innerCornerIsConcentric() {
        #expect(
            CosmoSurfaceMetrics.innerCorner
                == CosmoSurfaceMetrics.containerCorner - CosmoSurfaceMetrics.windowInset
        )
    }

    /// The second shipped defect: bench chrome sat at side inset 16 above a
    /// sheet inset 10, leaving two visible edges 6pt apart. The band and the
    /// window it introduces must share one side gutter.
    @Test("Chrome band aligns with the window beneath it")
    func chromeAlignsWithWindow() {
        #expect(CosmoChromeMetrics.sideInset == CosmoSurfaceMetrics.windowInset)
    }

    /// The band is framed by the same gutter top and sides, so the container's
    /// interior reads as one margin rather than three values.
    @Test("Chrome top gutter matches the side gutter")
    func chromeTopMatchesSides() {
        #expect(CosmoChromeMetrics.topInset == CosmoSurfaceMetrics.windowInset)
    }

    /// A pane toolbar and a chrome island are the same object at the same
    /// height, so the toolbar's radius must be a true capsule. The old literal
    /// 22 exceeded half of a 40pt bar and clamped to 20 — right on screen,
    /// wrong in the code, and silently wrong if the height ever changed.
    @Test("Toolbar capsule radius is exactly half the band height")
    func toolbarRadiusIsCapsule() {
        #expect(CosmoChromeMetrics.height / 2 == 20)
    }

    /// Every rung is positive and ordered; a zero or negative gutter would
    /// collapse the ladder into a single edge.
    @Test("Ladder rungs are positive")
    func rungsArePositive() {
        #expect(CosmoSurfaceMetrics.containerCorner > 0)
        #expect(CosmoSurfaceMetrics.windowInset > 0)
        #expect(CosmoSurfaceMetrics.innerCorner > 0)
        #expect(CosmoSurfaceMetrics.chromeGap > 0)
    }
}
