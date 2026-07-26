import XCTest
@testable import CosmoOS

/// The swap-in centering math: when a staged proposal replaces the editor with
/// the in-document diff, the first change row must land mid-viewport — never a
/// preserved pixel offset pointing at arbitrary prose.
final class CosmoInlineReviewCenteringTests: XCTestCase {

    // MARK: - Mid-document changes center exactly

    func testChangeDeepInDocumentCentersOnViewportMiddle() {
        let offset = CosmoInlineReviewCenteringDriver.desiredOffsetY(
            anchorMidY: 4000,
            viewportHeight: 800,
            documentHeight: 10000
        )
        // Anchor at 4000, viewport 800 → top of viewport at 3600 puts the
        // anchor dead center.
        XCTAssertEqual(offset, 3600)
    }

    // MARK: - Clamping

    func testChangeNearTopClampsToDocumentStart() {
        let offset = CosmoInlineReviewCenteringDriver.desiredOffsetY(
            anchorMidY: 100,
            viewportHeight: 800,
            documentHeight: 10000
        )
        // Centering would need a negative offset — pin to the top instead.
        XCTAssertEqual(offset, 0)
    }

    func testChangeNearBottomClampsToScrollableRange() {
        let offset = CosmoInlineReviewCenteringDriver.desiredOffsetY(
            anchorMidY: 9900,
            viewportHeight: 800,
            documentHeight: 10000
        )
        // Ideal top would be 9500, but the document only scrolls to 9200.
        XCTAssertEqual(offset, 9200)
    }

    func testDocumentShorterThanViewportNeverScrolls() {
        let offset = CosmoInlineReviewCenteringDriver.desiredOffsetY(
            anchorMidY: 300,
            viewportHeight: 800,
            documentHeight: 500
        )
        XCTAssertEqual(offset, 0)
    }

    func testAnchorExactlyAtCenterIsStable() {
        // A repeat attempt on an already-centered viewport must compute the
        // same offset, so the settle ladder becomes a no-op instead of a nudge.
        let first = CosmoInlineReviewCenteringDriver.desiredOffsetY(
            anchorMidY: 5000,
            viewportHeight: 900,
            documentHeight: 12000
        )
        let second = CosmoInlineReviewCenteringDriver.desiredOffsetY(
            anchorMidY: 5000,
            viewportHeight: 900,
            documentHeight: 12000
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, 4550)
    }
}
