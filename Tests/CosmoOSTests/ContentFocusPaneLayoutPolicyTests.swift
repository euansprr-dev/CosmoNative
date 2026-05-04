import XCTest
@testable import CosmoOS

final class ContentFocusPaneLayoutPolicyTests: XCTestCase {
    func testPaneContextSuppressesMarginaliaRailsEvenWhenWideEnoughForFullLayout() {
        XCTAssertFalse(
            ContentFocusLayoutPolicy.showsMarginaliaRails(
                isPaneContext: true,
                zenMode: false,
                layoutMode: .full,
                availableWidth: 1_200
            )
        )
    }

    func testPaneContextUsesPaneWidthForManuscriptInsteadOfFullWindowRailBudget() {
        let width = ContentFocusLayoutPolicy.manuscriptWidth(
            availableWidth: 720,
            preferredWritingWidth: 860,
            isPaneContext: true,
            zenMode: false,
            layoutMode: .regular
        )

        XCTAssertEqual(width, 672)
    }

    func testFullWindowKeepsSideRailAllowance() {
        let width = ContentFocusLayoutPolicy.manuscriptWidth(
            availableWidth: 1_200,
            preferredWritingWidth: 860,
            isPaneContext: false,
            zenMode: false,
            layoutMode: .full
        )

        XCTAssertEqual(width, 620)
    }
}
