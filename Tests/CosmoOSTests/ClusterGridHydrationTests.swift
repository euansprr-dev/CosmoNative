// Tests/CosmoOSTests/ClusterGridHydrationTests.swift
// Locks the cluster-grid hydration invariants (July 2026): cell frames are
// canonical pure math that must stay in lockstep with estimatedGridHeight
// (the engine sizes clusters from it), and the band policy hydrates exactly
// the near-visible cells so scrolling never reveals a placeholder.

import XCTest
@testable import CosmoOS

@MainActor
final class ClusterGridHydrationTests: XCTestCase {

    private func makeBlock(_ type: EntityType) -> CanvasBlock {
        CanvasBlock(
            id: UUID().uuidString,
            position: .zero,
            entityType: type,
            entityId: 0,
            entityUuid: UUID().uuidString,
            title: "T"
        )
    }

    func testCellFramesAgreeWithEstimatedGridHeight() {
        let blocks: [CanvasBlock] = [
            makeBlock(.content), makeBlock(.note), makeBlock(.idea),
            makeBlock(.task), makeBlock(.content), makeBlock(.research),
        ]
        for width in [CGFloat(300), 700, 1200] {
            let frames = ClusterGridContent.cellFrames(blocks: blocks, availableWidth: width)
            XCTAssertEqual(frames.count, blocks.count)
            XCTAssertEqual(
                frames.map(\.maxY).max() ?? 0,
                ClusterGridContent.estimatedGridHeight(blocks: blocks, availableWidth: width),
                "hydration frames and engine sizing must share one masonry math"
            )
        }
        XCTAssertEqual(ClusterGridContent.estimatedGridHeight(blocks: [], availableWidth: 500), 0)
    }

    func testBandPolicyHydratesNearCellsAndSkipsFarOnes() {
        let band = ClusterGridHydrationPolicy.quantizedBand(minY: 0, maxY: 600)
        let margin = ClusterGridHydrationPolicy.preloadMargin

        let visible = CGRect(x: 0, y: 100, width: 220, height: 300)
        let justBelow = CGRect(x: 0, y: 600 + margin - 1, width: 220, height: 300)
        let farBelow = CGRect(x: 0, y: 600 + margin + ClusterGridHydrationPolicy.bandQuantum + 1, width: 220, height: 300)

        XCTAssertTrue(ClusterGridHydrationPolicy.isNearBand(cellFrame: visible, band: band))
        XCTAssertTrue(ClusterGridHydrationPolicy.isNearBand(cellFrame: justBelow, band: band))
        XCTAssertFalse(ClusterGridHydrationPolicy.isNearBand(cellFrame: farBelow, band: band))
    }

    func testQuantizedBandBucketsScrollNoise() {
        // Sub-quantum scroll deltas must produce IDENTICAL bands, so the
        // scroll-geometry action never fires per frame.
        let a = ClusterGridHydrationPolicy.quantizedBand(minY: 10, maxY: 500)
        let b = ClusterGridHydrationPolicy.quantizedBand(minY: 90, maxY: 580)
        XCTAssertEqual(a, b)

        let c = ClusterGridHydrationPolicy.quantizedBand(
            minY: 10 + ClusterGridHydrationPolicy.bandQuantum,
            maxY: 500 + ClusterGridHydrationPolicy.bandQuantum
        )
        XCTAssertNotEqual(a, c)
    }
}
