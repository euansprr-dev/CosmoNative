import XCTest
@testable import CosmoOS

/// The Today dashboard must always be able to COMPRESS into the width it is
/// handed. Before the Aug 2026 audit its full measure was ~1111pt (gauge hero
/// row + list/timeline columns + the habits rail) and every narrower slot —
/// an open pane deck, a narrow window, the command-center pane — clipped at
/// the trailing edge. The width classes shed columns instead: timeline first
/// (Today collapses to the ONE ledger column, the mac-Today LAW — collapse,
/// never shrink the two columns into each other), then the internal
/// navigation sidebar, then the rail. Thresholds are derived from the column
/// arithmetic, never typed.
final class DashboardLayoutPolicyTests: XCTestCase {

    private var chrome: CGFloat {
        DashboardLayoutMetrics.pagePadding + DashboardLayoutMetrics.centerPadding
    }

    // MARK: - Wide window: nothing sheds

    func testFullWindowSeatsEverything() {
        let seats = DashboardLayoutMetrics.seats(width: 1920, wantsInternalSidebar: false)
        XCTAssertTrue(seats.rail)
        XCTAssertTrue(seats.timeline)
        XCTAssertFalse(seats.internalSidebar, "MainView mounts without the internal sidebar")

        let withSidebar = DashboardLayoutMetrics.seats(width: 1920, wantsInternalSidebar: true)
        XCTAssertTrue(withSidebar.rail)
        XCTAssertTrue(withSidebar.internalSidebar)
        XCTAssertTrue(withSidebar.timeline)
    }

    // MARK: - Beside a pane deck (the bug's shape): timeline sheds first

    func testPaneSqueezedSlotDropsTimelineKeepsRail() {
        // A 1920 window halved by the pane deck → ~960pt slot.
        let seats = DashboardLayoutMetrics.seats(width: 960, wantsInternalSidebar: false)
        XCTAssertTrue(seats.rail, "The habits/reports rail outranks the timeline")
        XCTAssertFalse(seats.timeline, "Today collapses to the one ledger column")
    }

    func testTimelineThresholdIsDerivedFromTheColumnBudget() {
        // Exactly enough is enough; one point less is not.
        let threshold = chrome
            + DashboardLayoutMetrics.railWidth
            + DashboardLayoutMetrics.timelineSpan
            + DashboardLayoutMetrics.minimumLedgerMeasure
        XCTAssertTrue(DashboardLayoutMetrics.seats(width: threshold, wantsInternalSidebar: false).timeline)
        XCTAssertFalse(DashboardLayoutMetrics.seats(width: threshold - 1, wantsInternalSidebar: false).timeline)
    }

    // MARK: - Narrow slots: the rail sheds last, the ledger keeps its floor

    func testRailShedsBelowItsSeatWidth() {
        let threshold = chrome
            + DashboardLayoutMetrics.railWidth
            + DashboardLayoutMetrics.minimumLedgerMeasure
        XCTAssertTrue(DashboardLayoutMetrics.seats(width: threshold, wantsInternalSidebar: false).rail)
        XCTAssertFalse(DashboardLayoutMetrics.seats(width: threshold - 1, wantsInternalSidebar: false).rail)
    }

    func testCommandCenterPaneFloorSeatsOnlyTheLedger() {
        // PaneSlotPresentationPolicy.minimumContentWidth is the narrowest slot
        // a pane body ever lays out at — the dashboard must seat a bare
        // ledger there, nothing else.
        let seats = DashboardLayoutMetrics.seats(
            width: PaneSlotPresentationPolicy.minimumContentWidth,
            wantsInternalSidebar: true
        )
        XCTAssertFalse(seats.rail)
        XCTAssertFalse(seats.internalSidebar)
        XCTAssertFalse(seats.timeline)
    }

    // MARK: - Pane hosting: navigation outlives the inspector

    func testSidebarOutranksRailWhenBothCannotSeat() {
        // A width that can seat the sidebar OR the rail but not both must
        // choose navigation (the Things grammar).
        let sidebarOnly = chrome
            + DashboardLayoutMetrics.internalSidebarSpan
            + DashboardLayoutMetrics.minimumLedgerMeasure
        let seats = DashboardLayoutMetrics.seats(width: sidebarOnly, wantsInternalSidebar: true)
        XCTAssertTrue(seats.internalSidebar)
        XCTAssertFalse(seats.rail)
    }

    // MARK: - Monotonicity: growing wider never sheds a column

    func testSeatingIsMonotonicInWidth() {
        var previousScore = -1
        for width in stride(from: 300, through: 2200, by: 10) {
            let seats = DashboardLayoutMetrics.seats(width: CGFloat(width), wantsInternalSidebar: true)
            let score = (seats.rail ? 1 : 0) + (seats.internalSidebar ? 1 : 0) + (seats.timeline ? 1 : 0)
            XCTAssertGreaterThanOrEqual(
                score, previousScore,
                "Width \(width) seats fewer columns than a narrower width did"
            )
            previousScore = score
        }
    }
}
