import XCTest
@testable import CosmoOS

final class CanvasClusterLayoutResolverTests: XCTestCase {
    private let gutter = CanvasClusterLayoutResolver.defaultGutter

    private func box(
        _ id: UUID = UUID(),
        x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
        fixed: Bool = false
    ) -> CanvasClusterLayoutResolver.Box {
        .init(id: id, rect: CGRect(x: x, y: y, width: w, height: h), isFixed: fixed)
    }

    private func applying(
        _ displacements: [UUID: CGSize],
        to boxes: [CanvasClusterLayoutResolver.Box]
    ) -> [CanvasClusterLayoutResolver.Box] {
        boxes.map { original in
            var moved = original
            if let delta = displacements[original.id] {
                moved.rect.origin.x += delta.width
                moved.rect.origin.y += delta.height
            }
            return moved
        }
    }

    func testSeparatedClustersDoNotMove() {
        let boxes = [
            box(x: 0, y: 0, w: 400, h: 300),
            box(x: 600, y: 0, w: 400, h: 300)
        ]
        XCTAssertTrue(CanvasClusterLayoutResolver.displacements(for: boxes).isEmpty)
    }

    func testOverlappingPairSeparatesWithGutter() {
        let boxes = [
            box(x: 0, y: 0, w: 400, h: 300),
            box(x: 200, y: 100, w: 400, h: 300)
        ]
        let displacements = CanvasClusterLayoutResolver.displacements(for: boxes)
        XCTAssertFalse(displacements.isEmpty)

        let resolved = applying(displacements, to: boxes)
        XCTAssertFalse(CanvasClusterLayoutResolver.hasMovableOverlap(resolved, gutter: gutter))
    }

    func testHeavilyStackedClustersAllSeparate() {
        // Four clusters piled on nearly the same spot — the organize-plan
        // worst case (screenshot bug: all regions overlapping).
        let boxes = (0..<4).map { index in
            box(x: CGFloat(index) * 40, y: CGFloat(index) * 30, w: 700, h: 500)
        }
        let displacements = CanvasClusterLayoutResolver.displacements(for: boxes)
        let resolved = applying(displacements, to: boxes)
        XCTAssertFalse(CanvasClusterLayoutResolver.hasMovableOverlap(resolved, gutter: gutter))
    }

    func testFixedZoneNeverMovesButPushesClusters() {
        let zoneID = UUID()
        let boxes = [
            box(zoneID, x: 0, y: 0, w: 600, h: 400, fixed: true),
            box(x: 100, y: 100, w: 400, h: 300)
        ]
        let displacements = CanvasClusterLayoutResolver.displacements(for: boxes)
        XCTAssertNil(displacements[zoneID], "fixed zones are obstacles, never movers")

        let resolved = applying(displacements, to: boxes)
        XCTAssertFalse(CanvasClusterLayoutResolver.hasMovableOverlap(resolved, gutter: gutter))
    }

    func testResolutionStaysClose() {
        // "Organize them very closely" — a simple two-box overlap should move
        // each box by roughly half the overlap, not fling them apart.
        let a = UUID()
        let b = UUID()
        let boxes = [
            box(a, x: 0, y: 0, w: 400, h: 300),
            box(b, x: 380, y: 0, w: 400, h: 300)
        ]
        let displacements = CanvasClusterLayoutResolver.displacements(for: boxes)
        let resolved = applying(displacements, to: boxes)
        XCTAssertFalse(CanvasClusterLayoutResolver.hasMovableOverlap(resolved, gutter: gutter))

        let totalTravel = displacements.values.reduce(CGFloat(0)) {
            $0 + abs($1.width) + abs($1.height)
        }
        // Needed separation is ~overlap (20) + gutter (48); anything over 3x
        // that means the relaxation is flinging instead of nudging.
        XCTAssertLessThan(totalTravel, 220)
    }

    func testDeterministicForSameInput() {
        let ids = (0..<5).map { _ in UUID() }
        let make: () -> [CanvasClusterLayoutResolver.Box] = {
            ids.enumerated().map { index, id in
                self.box(id, x: CGFloat(index) * 60, y: CGFloat(index % 2) * 50, w: 500, h: 400)
            }
        }
        let first = CanvasClusterLayoutResolver.displacements(for: make())
        let second = CanvasClusterLayoutResolver.displacements(for: make())
        XCTAssertEqual(first, second)
    }
}
