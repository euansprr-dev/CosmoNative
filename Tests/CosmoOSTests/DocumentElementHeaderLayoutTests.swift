import CoreGraphics
import XCTest
@testable import CosmoOS

final class DocumentElementHeaderLayoutTests: XCTestCase {
    func testHeaderLayoutUsesLargeChevronHitTargetAndAspectFitIconRect() {
        let layout = DocumentElementHeaderLayout(
            chromeRect: CGRect(x: 20, y: 40, width: 720, height: 46),
            headerMidY: 63,
            elementName: "Concept",
            instanceTitle: "Audience Situation",
            depth: 0,
            fontSize: 17
        )

        XCTAssertEqual(layout.chevronHitRect.width, 28)
        XCTAssertEqual(layout.chevronHitRect.height, 28)
        XCTAssertTrue(layout.chevronHitRect.contains(CGPoint(x: 34, y: 63)))
        XCTAssertEqual(layout.iconRect.width, layout.iconRect.height)
        XCTAssertLessThanOrEqual(layout.iconRect.width, 15)
        XCTAssertLessThan(layout.nameRect.minX, layout.titleRect.minX)
    }

    func testHeaderLayoutScalesForNestedElements() {
        let layout = DocumentElementHeaderLayout(
            chromeRect: CGRect(x: 20, y: 40, width: 720, height: 46),
            headerMidY: 63,
            elementName: "Concept",
            instanceTitle: "Nested title",
            depth: 2,
            fontSize: 17
        )

        XCTAssertGreaterThan(layout.chevronHitRect.minX, 20)
        XCTAssertGreaterThan(layout.nameRect.minX, layout.iconRect.maxX)
    }
}
