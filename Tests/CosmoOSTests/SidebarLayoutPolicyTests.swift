import XCTest
@testable import CosmoOS

final class SidebarLayoutPolicyTests: XCTestCase {
    func testCanvasDestinationsAllowContentBehindSidebar() {
        let inset = MainSidebarContentLayoutPolicy.contentLeadingInset(
            for: .thinkspace(id: "alpha"),
            isSidebarHidden: false,
            isFocusModeActive: false,
            sidebarReservedWidth: 320
        )

        XCTAssertEqual(inset, 0)
    }

    func testNonCanvasDestinationsReserveSidebarSpaceWithoutChangingShell() {
        let destinations: [SidebarDestination] = [.commandCenter, .inbox, .codex]

        for destination in destinations {
            let inset = MainSidebarContentLayoutPolicy.contentLeadingInset(
                for: destination,
                isSidebarHidden: false,
                isFocusModeActive: false,
                sidebarReservedWidth: 320
            )

            XCTAssertEqual(inset, 320)
        }
    }

    func testHiddenSidebarDoesNotReserveContentSpace() {
        XCTAssertEqual(
            MainSidebarContentLayoutPolicy.contentLeadingInset(
                for: .commandCenter,
                isSidebarHidden: true,
                isFocusModeActive: false,
                sidebarReservedWidth: 320
            ),
            0
        )
    }

    func testFocusModeKeepsContentReservedBesideSidebar() {
        XCTAssertEqual(
            MainSidebarContentLayoutPolicy.contentLeadingInset(
                for: .thinkspace(id: "alpha"),
                isSidebarHidden: false,
                isFocusModeActive: true,
                sidebarReservedWidth: 320
            ),
            320
        )
    }
}
