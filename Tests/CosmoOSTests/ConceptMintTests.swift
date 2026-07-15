// CosmoOS/Tests/CosmoOSTests/ConceptMintTests.swift
// Pure contracts of concept minting: placement math keeps minted families
// beside their origin, and the name policy keeps the pill out of the way of
// ordinary copy-selection.

import XCTest
@testable import CosmoOS

final class ConceptMintTests: XCTestCase {

    // MARK: - Placement

    func testFirstMintLandsRightOfOrigin() {
        let origin = CGRect(x: 100, y: 200, width: 320, height: 220)
        let point = ConnectionPromotionService.mintPlacementPoint(originFrame: origin, cascadeIndex: 0)
        XCTAssertEqual(point.x, origin.maxX + 120)
        XCTAssertEqual(point.y, origin.minY)
    }

    func testSuccessiveMintsCascadeDownward() {
        let origin = CGRect(x: 0, y: 0, width: 320, height: 220)
        let first = ConnectionPromotionService.mintPlacementPoint(originFrame: origin, cascadeIndex: 0)
        let third = ConnectionPromotionService.mintPlacementPoint(originFrame: origin, cascadeIndex: 2)
        XCTAssertEqual(first.x, third.x)
        XCTAssertEqual(third.y - first.y, 128)
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
