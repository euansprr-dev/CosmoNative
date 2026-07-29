import XCTest
@testable import CosmoOS

/// Where a captured page gets cut. Pure geometry, so the boundaries a sales
/// page receives are pinned without rendering anything.
///
/// The load-bearing property is that slices TILE the page: every pixel belongs
/// to exactly one slice, in order, with no gap and no overlap. A hole means
/// the Study stage shows a band of nothing where a divider used to be; an
/// overlap means a testimonial appears twice.
final class SwipePageSlicerTests: XCTestCase {

    private func section(_ top: Int, _ height: Int, _ text: String = "") -> SwipePageSection {
        SwipePageSection(top: top, height: height, text: text)
    }

    /// The invariant every other test leans on.
    private func assertTiles(
        _ slices: [SwipePageSlice],
        contentHeight: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(slices.isEmpty, "a page always yields at least one slice", file: file, line: line)
        XCTAssertEqual(slices.first?.top, 0, "slices must start at the top of the page", file: file, line: line)
        XCTAssertEqual(slices.last?.bottom, contentHeight, "slices must reach the bottom", file: file, line: line)
        for (index, slice) in slices.enumerated() {
            XCTAssertEqual(slice.index, index, "indices must be dense and ordered", file: file, line: line)
            if index > 0 {
                XCTAssertEqual(
                    slice.top, slices[index - 1].bottom,
                    "slice \(index) must start where \(index - 1) ended — no gap, no overlap",
                    file: file, line: line
                )
            }
        }
    }

    // MARK: - Ordinary pages

    func testCleanSectionsSliceOneToOne() {
        let slices = SwipePageSlicer.slices(
            from: [section(0, 800, "hero"), section(800, 600, "proof"), section(1400, 600, "offer")],
            contentHeight: 2000
        )
        XCTAssertEqual(slices.count, 3)
        XCTAssertEqual(slices.map(\.text), ["hero", "proof", "offer"])
        assertTiles(slices, contentHeight: 2000)
    }

    func testGapsBetweenSectionsAreAbsorbedByThePrecedingSlice() {
        // A 100px spacer between two sections belongs to the one above it.
        let slices = SwipePageSlicer.slices(
            from: [section(0, 700), section(800, 600)],
            contentHeight: 1400
        )
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices[0].height, 800, "the spacer rides with the section above")
        assertTiles(slices, contentHeight: 1400)
    }

    func testAHeroThatStartsBelowTheTopStillOwnsTheTop() {
        let slices = SwipePageSlicer.slices(from: [section(60, 900)], contentHeight: 960)
        XCTAssertEqual(slices.first?.top, 0)
        assertTiles(slices, contentHeight: 960)
    }

    func testTheLastSliceAlwaysRunsToTheBottom() {
        let slices = SwipePageSlicer.slices(
            from: [section(0, 500), section(500, 400)],
            contentHeight: 1600
        )
        XCTAssertEqual(slices.last?.bottom, 1600, "the footer must not be cropped off")
        assertTiles(slices, contentHeight: 1600)
    }

    // MARK: - Noise

    /// Dividers, spacers and stray badges are not sections. They merge upward
    /// rather than earning their own image and their own role.
    func testShortSectionsMergeIntoTheOneAbove() {
        let slices = SwipePageSlicer.slices(
            from: [section(0, 800, "hero"), section(800, 20, "divider"), section(820, 700, "offer")],
            contentHeight: 1520
        )
        XCTAssertEqual(slices.count, 2)
        XCTAssertTrue(slices[0].text.contains("hero"))
        XCTAssertTrue(slices[0].text.contains("divider"), "merged text is kept, never dropped")
        assertTiles(slices, contentHeight: 1520)
    }

    func testOverlappingSectionsAreFolded() {
        let slices = SwipePageSlicer.slices(
            from: [section(0, 900, "outer"), section(400, 300, "inner")],
            contentHeight: 900
        )
        XCTAssertEqual(slices.count, 1, "a nested child must not double-count its parent's pixels")
        assertTiles(slices, contentHeight: 900)
    }

    func testSectionsAreSortedBeforeSlicing() {
        let slices = SwipePageSlicer.slices(
            from: [section(1000, 600, "third"), section(0, 500, "first"), section(500, 500, "second")],
            contentHeight: 1600
        )
        XCTAssertEqual(slices.map(\.text), ["first", "second", "third"])
        assertTiles(slices, contentHeight: 1600)
    }

    func testSectionsBeyondTheContentHeightAreClamped() {
        let slices = SwipePageSlicer.slices(
            from: [section(0, 500), section(500, 9000)],
            contentHeight: 1000
        )
        assertTiles(slices, contentHeight: 1000)
        XCTAssertTrue(slices.allSatisfy { $0.bottom <= 1000 })
    }

    // MARK: - Degenerate input

    /// A page whose DOM told us nothing is still ONE slice — never zero, or
    /// the capture silently produces a swipe with no units.
    func testAPageWithNoSectionsBecomesOneSlice() {
        let slices = SwipePageSlicer.slices(from: [], contentHeight: 3000)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices.first?.height, 3000)
        assertTiles(slices, contentHeight: 3000)
    }

    func testAZeroHeightPageYieldsNothing() {
        XCTAssertTrue(SwipePageSlicer.slices(from: [section(0, 100)], contentHeight: 0).isEmpty)
    }

    // MARK: - The cap

    /// Forty images is already more than anyone studies. The tail MERGES —
    /// the bottom of a sales page is where the offer and the guarantee live,
    /// and dropping it would lose the most valuable part.
    func testTheTailMergesRatherThanBeingDropped() {
        let sections = (0..<60).map { section($0 * 300, 300, "s\($0)") }
        let slices = SwipePageSlicer.slices(from: sections, contentHeight: 18_000)
        XCTAssertEqual(slices.count, SwipePageSlicer.maxSlices)
        assertTiles(slices, contentHeight: 18_000)
        XCTAssertTrue(slices.last?.text.contains("s59") == true, "the last section's text survives the merge")
    }

    // MARK: - Scale

    /// A retina snapshot is backed by more pixels than CSS points; every
    /// measurement scales by the same factor or the cuts land mid-section.
    func testSliceGeometryScalesToCapturePixels() {
        let slices = SwipePageSlicer.slices(
            from: [section(0, 500), section(500, 500)],
            contentHeight: 1000, scale: 2
        )
        XCTAssertEqual(slices.map(\.top), [0, 1000])
        XCTAssertEqual(slices.map(\.height), [1000, 1000])
        assertTiles(slices, contentHeight: 2000)
    }

    // MARK: - Tiling

    func testShortPagesCaptureInOnePass() {
        XCTAssertEqual(SwipePageSlicer.tileOffsets(forHeight: 8_000), [0])
        XCTAssertEqual(SwipePageSlicer.tileOffsets(forHeight: SwipePageSlicer.maxSingleCaptureHeight), [0])
    }

    func testTallPagesTileAndTheFinalTileIsShort() {
        let height = 30_000
        let offsets = SwipePageSlicer.tileOffsets(forHeight: height)
        XCTAssertEqual(offsets, [0, 12_000, 24_000])
        XCTAssertEqual(SwipePageSlicer.tileHeight(at: 0, totalHeight: height), 12_000)
        XCTAssertEqual(
            SwipePageSlicer.tileHeight(at: 24_000, totalHeight: height), 6_000,
            "the last tile must not overhang — the stitched image is exactly the page height"
        )
        let covered = offsets.reduce(0) { $0 + SwipePageSlicer.tileHeight(at: $1, totalHeight: height) }
        XCTAssertEqual(covered, height)
    }
}
