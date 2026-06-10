// CosmoOS/Tests/CosmoOSTests/ConnectionMergeTests.swift
// Concept pages must accumulate knowledge idempotently: merging the same
// proposed sections twice may never duplicate items or destroy user edits.

import XCTest
@testable import CosmoOS

final class ConnectionMergeTests: XCTestCase {

    private func section(_ type: ConnectionSectionType, items: [ConnectionItem]) -> ConnectionSection {
        ConnectionSection(type: type, items: items)
    }

    func testMergeTwiceDoesNotDuplicate() {
        let proposed = [
            section(.claims, items: [
                ConnectionItem(content: "Slow exhales raise vagal tone", sourceAtomUUID: "extract-1"),
                ConnectionItem(content: "Bhastrika is energizing", sourceAtomUUID: "extract-2")
            ])
        ]
        let once = ConnectionPromotionService.mergedSections(existing: [], proposed: proposed)
        let twice = ConnectionPromotionService.mergedSections(existing: once, proposed: proposed)

        let claimsOnce = once.first { $0.type == .claims }?.items ?? []
        let claimsTwice = twice.first { $0.type == .claims }?.items ?? []
        XCTAssertEqual(claimsOnce.count, 2)
        XCTAssertEqual(claimsTwice.count, 2)
    }

    func testMergePreservesExistingUserItems() {
        let existing = [
            section(.claims, items: [ConnectionItem(content: "My own hand-written claim")])
        ]
        let proposed = [
            section(.claims, items: [ConnectionItem(content: "New extract claim", sourceAtomUUID: "extract-9")])
        ]
        let merged = ConnectionPromotionService.mergedSections(existing: existing, proposed: proposed)
        let claims = merged.first { $0.type == .claims }?.items ?? []
        XCTAssertEqual(claims.count, 2)
        XCTAssertTrue(claims.contains { $0.content == "My own hand-written claim" })
        XCTAssertTrue(claims.contains { $0.content == "New extract claim" })
    }

    func testProvenanceMatchSkipsEvenWhenContentEdited() {
        // User edited the item's text after the first merge — provenance still matches.
        let existing = [
            section(.claims, items: [ConnectionItem(content: "Edited by the user", sourceAtomUUID: "extract-1")])
        ]
        let proposed = [
            section(.claims, items: [ConnectionItem(content: "Original extract text", sourceAtomUUID: "extract-1")])
        ]
        let merged = ConnectionPromotionService.mergedSections(existing: existing, proposed: proposed)
        let claims = merged.first { $0.type == .claims }?.items ?? []
        XCTAssertEqual(claims.count, 1)
        XCTAssertEqual(claims.first?.content, "Edited by the user")
    }

    func testContentMatchSkipsAcrossSections() {
        // The same normalized content in another section is not duplicated.
        let existing = [
            section(.process, items: [ConnectionItem(content: "Box breathing: 4-4-4-4.")])
        ]
        let proposed = [
            section(.claims, items: [ConnectionItem(content: "box breathing 4 4 4 4")])
        ]
        let merged = ConnectionPromotionService.mergedSections(existing: existing, proposed: proposed)
        let claims = merged.first { $0.type == .claims }?.items ?? []
        XCTAssertTrue(claims.isEmpty)
    }
}
