import XCTest
@testable import CosmoOS

final class BlockDragDropTests: XCTestCase {
    func testDropTargetAboveBlockUsesBlockIndex() {
        let target = BlockDropController.target(for: .above, path: .root(index: 2))
        XCTAssertEqual(target, BlockDropTarget(parent: nil, index: 2))
    }

    func testDropTargetBelowBlockUsesNextIndex() {
        let target = BlockDropController.target(for: .below, path: .root(index: 2))
        XCTAssertEqual(target, BlockDropTarget(parent: nil, index: 3))
    }

    func testNestedDropTargetPreservesParentPath() {
        let parent = BlockPath.root(index: 0)
        let child = parent.appendingChild(index: 1)

        let target = BlockDropController.target(for: .below, path: child)

        XCTAssertEqual(target, BlockDropTarget(parent: parent, index: 2))
    }

    func testDropValidationRejectsMovingBlockIntoItselfOrDescendant() {
        let source = BlockPath.root(index: 0)
        let childTarget = BlockDropTarget(parent: source.appendingChild(index: 1), index: 0)
        let sameTarget = BlockDropTarget(parent: nil, index: 0)
        let validTarget = BlockDropTarget(parent: nil, index: 2)

        XCTAssertFalse(BlockDropController.canMove(from: source, to: childTarget))
        XCTAssertFalse(BlockDropController.canMove(from: source, to: sameTarget))
        XCTAssertTrue(BlockDropController.canMove(from: source, to: validTarget))
    }

    func testHandleMetricsAlignByBlockKindWithoutHardcodedRowOffsets() {
        XCTAssertEqual(BlockInteractionPolicy.handleMetrics(for: .paragraph).verticalAnchor, .textBaseline)
        XCTAssertEqual(BlockInteractionPolicy.handleMetrics(for: .heading1).verticalAnchor, .headingBaseline)
        XCTAssertEqual(BlockInteractionPolicy.handleMetrics(for: .divider).verticalAnchor, .center)
        XCTAssertEqual(BlockInteractionPolicy.handleMetrics(for: .element).verticalAnchor, .cardHeader)
    }

    func testHoverChromeKeepsTextColumnStable() {
        let hidden = BlockInteractionPolicy.chrome(isHovered: false, isDropTarget: false, darkMode: true)
        let hovered = BlockInteractionPolicy.chrome(isHovered: true, isDropTarget: false, darkMode: true)
        let dropping = BlockInteractionPolicy.chrome(isHovered: false, isDropTarget: true, darkMode: true)

        XCTAssertEqual(hidden.reservedLeadingWidth, hovered.reservedLeadingWidth)
        XCTAssertEqual(hovered.reservedLeadingWidth, dropping.reservedLeadingWidth)
        XCTAssertLessThan(hidden.handleOpacity, hovered.handleOpacity)
        XCTAssertGreaterThan(dropping.dropIndicatorOpacity, hovered.dropIndicatorOpacity)
    }

    func testMotionPolicyUsesFastSettlingChromeAndDropFeedback() {
        XCTAssertLessThanOrEqual(BlockMotionPolicy.chromeResponse, 0.20)
        XCTAssertGreaterThan(BlockMotionPolicy.chromeDampingFraction, 0.80)
        XCTAssertLessThanOrEqual(BlockMotionPolicy.dropResponse, 0.16)
    }
}
