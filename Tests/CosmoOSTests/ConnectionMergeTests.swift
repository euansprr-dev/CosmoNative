// CosmoOS/Tests/CosmoOSTests/ConnectionMergeTests.swift
// Concept pages must accumulate knowledge idempotently: merging the same
// proposed sections twice may never duplicate items or destroy user edits.
// Realigned July 2026.

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

    func testSharedProvenanceWithDistinctContentBothSurvive() {
        // Dedup is on CONTENT, not provenance: the Concept Composer splits one
        // capture into several bullets that all carry the origin extract's UUID,
        // so a provenance-only skip would collapse the split back into one item.
        // The user's own edit is never overwritten — the new bullet lands beside it.
        let existing = [
            section(.claims, items: [ConnectionItem(content: "Edited by the user", sourceAtomUUID: "extract-1")])
        ]
        let proposed = [
            section(.claims, items: [ConnectionItem(content: "A second bullet off the same capture", sourceAtomUUID: "extract-1")])
        ]
        let merged = ConnectionPromotionService.mergedSections(existing: existing, proposed: proposed)
        let claims = merged.first { $0.type == .claims }?.items ?? []
        XCTAssertEqual(claims.count, 2)
        XCTAssertEqual(claims.first?.content, "Edited by the user")
        XCTAssertTrue(claims.contains { $0.content == "A second bullet off the same capture" })
    }

    func testContentlessRowsStillCollapseOnProvenance() {
        // The one path where provenance alone decides: a row with no text to
        // distinguish by (a bare link row) may not be re-added for the same source.
        let existing = [
            section(.references, items: [ConnectionItem(content: "", sourceAtomUUID: "conn-2")])
        ]
        let proposed = [
            section(.references, items: [ConnectionItem(content: "", sourceAtomUUID: "conn-2")])
        ]
        let merged = ConnectionPromotionService.mergedSections(existing: existing, proposed: proposed)
        let refs = merged.first { $0.type == .references }?.items ?? []
        XCTAssertEqual(refs.count, 1)
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

    // MARK: - Cross-connection link rows

    func testLegacySiblingRowsUpgradeToHyperlinks() {
        let existing = [
            section(.references, items: [
                ConnectionItem(content: "Sibling Connection", sourceAtomUUID: "conn-2"),
                ConnectionItem(content: "Some Paper 2019", sourceAtomUUID: "research-1")
            ])
        ]
        let upgraded = ConnectionPromotionService.upgradedLegacyLinkRows(
            existing,
            connectionTitlesByUUID: ["conn-2": "Vagus nerve"]
        )
        let refs = upgraded.first { $0.type == .references }?.items ?? []
        XCTAssertEqual(refs.first?.linkedConnectionUUID, "conn-2")
        XCTAssertEqual(refs.first?.resolvedPlainText, "Vagus nerve")   // Real title replaces placeholder.
        XCTAssertNil(refs.last?.linkedConnectionUUID)                  // Research sources untouched.
    }

    func testMergeDoesNotDuplicateLinkRows() {
        let linkItem = ConnectionItem(
            content: "Vagus nerve",
            sourceAtomUUID: "conn-2",
            linkedConnectionUUID: "conn-2"
        )
        let once = ConnectionPromotionService.mergedSections(
            existing: [],
            proposed: [section(.references, items: [linkItem])]
        )
        let twice = ConnectionPromotionService.mergedSections(
            existing: once,
            proposed: [section(.references, items: [linkItem])]
        )
        let refs = twice.first { $0.type == .references }?.items ?? []
        XCTAssertEqual(refs.count, 1)
    }

    func testConnectionMentionsMatchesItemText() throws {
        let sections = [
            section(.claims, items: [ConnectionItem(content: "Slow pranayama raises vagal tone within minutes")])
        ]
        var atom = Atom.new(type: .connection, title: "Breath physiology")
        atom.structured = ConnectionStructuredData(sections: sections).toJSON()

        XCTAssertTrue(ConnectionPromotionService.connectionMentions(atom, names: ["Vagal tone"]))
        XCTAssertFalse(ConnectionPromotionService.connectionMentions(atom, names: ["CO2 tolerance"]))
        XCTAssertFalse(ConnectionPromotionService.connectionMentions(atom, names: ["one"]))   // Too short to count.
    }
}
