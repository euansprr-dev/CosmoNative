// CosmoOS/Tests/CosmoOSTests/ConceptMintTests.swift
// Pure contracts of concept minting: placement math keeps minted families
// beside their origin, and the name policy keeps the pill out of the way of
// ordinary copy-selection.

import XCTest
@testable import CosmoOS

final class ConceptMintTests: XCTestCase {

    // MARK: - Placement

    private let blockSize = CGSize(width: 320, height: 220)

    private func frame(at point: CGPoint) -> CGRect {
        CGRect(origin: point, size: blockSize)
    }

    func testFirstMintLandsRightOfOrigin() {
        let origin = CGRect(x: 100, y: 200, width: 320, height: 220)
        let point = ConnectionPromotionService.mintPlacementPoint(
            originFrame: origin,
            existingFrames: [origin]
        )
        XCTAssertEqual(point.x, origin.maxX + 120)
        XCTAssertEqual(point.y, origin.minY)
    }

    /// The reported bug: an unrelated block already sits in the slot beside
    /// the origin — the mint must land clear of it, never on top of it.
    func testMintNeverLandsOnAnOccupyingBlock() {
        let origin = CGRect(x: 100, y: 200, width: 320, height: 220)
        let occupying = CGRect(x: origin.maxX + 100, y: 180, width: 320, height: 220)
        let point = ConnectionPromotionService.mintPlacementPoint(
            originFrame: origin,
            existingFrames: [origin, occupying]
        )
        XCTAssertFalse(frame(at: point).intersects(occupying))
        XCTAssertFalse(frame(at: point).intersects(origin))
        XCTAssertGreaterThanOrEqual(point.y, occupying.maxY)
    }

    /// Successive mints from the same origin stack downward without overlap.
    func testSuccessiveMintsCascadeWithoutOverlap() {
        let origin = CGRect(x: 0, y: 0, width: 320, height: 220)
        var existing = [origin]
        var placed: [CGRect] = []
        for _ in 0..<3 {
            let point = ConnectionPromotionService.mintPlacementPoint(
                originFrame: origin,
                existingFrames: existing
            )
            let minted = frame(at: point)
            for other in existing {
                XCTAssertFalse(minted.intersects(other))
            }
            placed.append(minted)
            existing.append(minted)
        }
        XCTAssertEqual(Set(placed.map(\.minX)).count, 1, "the minted family stays in one column")
        XCTAssertTrue(placed[0].minY < placed[1].minY && placed[1].minY < placed[2].minY)
    }

    /// The scan steps past the NEAREST blocker first, so an open gap between
    /// two occupied rows is used instead of skipping to the very bottom.
    func testMintFillsGapBetweenOccupiedRows() {
        let origin = CGRect(x: 0, y: 0, width: 320, height: 220)
        let top = CGRect(x: origin.maxX + 120, y: 0, width: 320, height: 220)
        let bottom = CGRect(x: origin.maxX + 120, y: 900, width: 320, height: 220)
        let point = ConnectionPromotionService.mintPlacementPoint(
            originFrame: origin,
            existingFrames: [origin, top, bottom]
        )
        let minted = frame(at: point)
        XCTAssertFalse(minted.intersects(top))
        XCTAssertFalse(minted.intersects(bottom))
        XCTAssertLessThan(minted.maxY, bottom.minY, "lands in the gap, not below everything")
    }

    /// A dense field of blocks always resolves to a collision-free spot.
    func testCrowdedCanvasAlwaysResolvesFreeSlot() {
        let origin = CGRect(x: 0, y: 0, width: 320, height: 220)
        var existing = [origin]
        for row in 0..<12 {
            existing.append(CGRect(x: origin.maxX + 60, y: CGFloat(row) * 250 - 200, width: 320, height: 220))
        }
        let point = ConnectionPromotionService.mintPlacementPoint(
            originFrame: origin,
            existingFrames: existing
        )
        let minted = frame(at: point)
        for other in existing {
            XCTAssertFalse(minted.intersects(other))
        }
    }

    // MARK: - Name policy (the pill's gate)

    func testConceptNameShapedSelectionsPass() {
        XCTAssertTrue(ConceptMintPolicy.isPlausibleConceptName("flow"))
        XCTAssertTrue(ConceptMintPolicy.isPlausibleConceptName("Closed Loops"))
        XCTAssertTrue(ConceptMintPolicy.isPlausibleConceptName("state of flow"))
        XCTAssertTrue(ConceptMintPolicy.isPlausibleConceptName("CO2 tolerance"))
    }

    func testSentencesAndNoiseAreRejected() {
        XCTAssertFalse(ConceptMintPolicy.isPlausibleConceptName(""))
        XCTAssertFalse(ConceptMintPolicy.isPlausibleConceptName("a"))
        XCTAssertFalse(ConceptMintPolicy.isPlausibleConceptName("It puts you in a state of flow."))
        XCTAssertFalse(ConceptMintPolicy.isPlausibleConceptName("closed loops put you in a state of flow whenever"))
        XCTAssertFalse(ConceptMintPolicy.isPlausibleConceptName("what is flow?"))
        XCTAssertFalse(ConceptMintPolicy.isPlausibleConceptName(String(repeating: "x", count: 80)))
    }
}
