import CoreGraphics
import XCTest
@testable import CosmoOS

final class DocumentElementHeaderLayoutTests: XCTestCase {
    func testHeaderLayoutHasChevronIconTitleProgression() {
        let layout = DocumentElementHeaderLayout(
            chromeRect: CGRect(x: 20, y: 40, width: 720, height: 46),
            headerMidY: 63,
            depth: 0,
            fontSize: 17
        )

        XCTAssertEqual(layout.chevronHitRect.width, DocumentElementHeaderLayout.chevronWidth)
        XCTAssertEqual(layout.iconRect.width, layout.iconRect.height)
        XCTAssertEqual(layout.iconRect.width, DocumentElementHeaderLayout.iconSize)
        XCTAssertLessThan(layout.chevronHitRect.maxX, layout.iconRect.minX + 4)
        XCTAssertLessThan(layout.iconRect.maxX, layout.titleRect.minX)
    }

    func testHeaderLayoutScalesForNestedElements() {
        let flat = DocumentElementHeaderLayout(
            chromeRect: CGRect(x: 20, y: 40, width: 720, height: 46),
            headerMidY: 63,
            depth: 0,
            fontSize: 17
        )
        let nested = DocumentElementHeaderLayout(
            chromeRect: CGRect(x: 20, y: 40, width: 720, height: 46),
            headerMidY: 63,
            depth: 2,
            fontSize: 17
        )

        XCTAssertGreaterThan(nested.chevronHitRect.minX, flat.chevronHitRect.minX)
        XCTAssertGreaterThan(nested.titleRect.minX, flat.titleRect.minX)
    }
}
