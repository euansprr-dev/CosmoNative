// CosmoOS/Tests/CosmoOSTests/ConnectionStagingStoreTests.swift
// The staged-insert echo contract: inbox/seedling retries (same source, same
// section) are echoes, collaborator retries are echoes only on byte-identical
// text — two DISTINCT collaborator bullets into one section must both land
// (the never-merge law holds at the store level, not just in the prompt).

import XCTest
@testable import CosmoOS

final class ConnectionStagingStoreTests: XCTestCase {

    private func insert(
        section: ConnectionSectionType = .problems,
        text: String = "Projecting a future scenario affects present action.",
        sourceKind: String = "collaborator",
        sourceUUID: String? = nil
    ) -> ConnectionStagedInsert {
        ConnectionStagedInsert(
            section: section.rawValue,
            text: text,
            sourceKind: sourceKind,
            sourceUUID: sourceUUID
        )
    }

    // MARK: - Sourced rows (inbox / seedling)

    func testSameSourceSameSectionIsEcho() {
        let existing = [insert(sourceKind: "inbox", sourceUUID: "cap-1")]
        let retry = insert(text: "Reworded by a retry", sourceKind: "inbox", sourceUUID: "cap-1")
        XCTAssertTrue(ConnectionStagingStore.isRetryEcho(retry, existing: existing))
    }

    func testSameSourceDifferentSectionLands() {
        let existing = [insert(sourceKind: "inbox", sourceUUID: "cap-1")]
        let second = insert(section: .examples, sourceKind: "inbox", sourceUUID: "cap-1")
        XCTAssertFalse(ConnectionStagingStore.isRetryEcho(second, existing: existing))
    }

    // MARK: - Collaborator rows (no sourceUUID)

    func testDistinctCollaboratorBulletsIntoOneSectionBothLand() {
        let existing = [insert(text: "Stressing over a future exam brings imagined failure into the present.")]
        let second = insert(text: "Replaying a past trauma recreates the pain in the present.")
        XCTAssertFalse(ConnectionStagingStore.isRetryEcho(second, existing: existing))
    }

    func testIdenticalCollaboratorTextSameSectionIsEcho() {
        let existing = [insert()]
        XCTAssertTrue(ConnectionStagingStore.isRetryEcho(insert(), existing: existing))
    }

    func testIdenticalTextDifferentSectionLands() {
        let existing = [insert(section: .problems)]
        let second = insert(section: .beliefsObjections)
        XCTAssertFalse(ConnectionStagingStore.isRetryEcho(second, existing: existing))
    }

    func testCollaboratorEchoAgainstSourcedRowMatchesOnText() {
        // A collaborator bullet that byte-matches an already-staged inbox row
        // in the same section is still an echo — the material is already
        // waiting there.
        let existing = [insert(sourceKind: "inbox", sourceUUID: "cap-1")]
        XCTAssertTrue(ConnectionStagingStore.isRetryEcho(insert(), existing: existing))
    }
}
