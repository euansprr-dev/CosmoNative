import XCTest
@testable import CosmoOS

/// Pins the content-preservation laws added after the July 22 2026 cross-device
/// note incident (an iPhone-created empty note scaffold permanently rejected —
/// and could have wiped — the Mac's typed content):
///  1. Blank content never beats substantial content in a conflict merge.
///  2. A blank remote body never blind-overwrites a substantial local body.
///  3. Remote payloads never move the local push-ack counter
///     (`_server_version`) — the server's `_version` column is frozen at its
///     insert default and adopting it made conflict mode permanent.
/// The iOS repo (CosmoCoreKit/Sources/Sync/ConflictResolver.swift) mirrors the
/// implementation and these tests — keep both in lockstep.
final class ConflictContentPreservationTests: XCTestCase {
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - Blankness

    func testBlankContentDetectsMissingNullAndWhitespaceOnlyText() {
        XCTAssertTrue(ConflictResolver.isBlankContent(nil))
        XCTAssertTrue(ConflictResolver.isBlankContent(NSNull()))
        XCTAssertTrue(ConflictResolver.isBlankContent(""))
        XCTAssertTrue(ConflictResolver.isBlankContent("   \n\t"))
        XCTAssertFalse(ConflictResolver.isBlankContent("Probate court filings"))
        // Unknown payload shapes must never trigger content adoption.
        XCTAssertFalse(ConflictResolver.isBlankContent(42))
    }

    // MARK: - Anti-Wipe Shield

    func testBlankRemoteBodyOverSubstantialLocalBodyIsFlagged() {
        XCTAssertTrue(
            ConflictResolver.remoteWouldBlankLocalContent(
                table: "atoms",
                localData: ["body": "490 real estate deals in the last 6 years"],
                remoteData: ["body": ""]
            )
        )
        XCTAssertTrue(
            ConflictResolver.remoteWouldBlankLocalContent(
                table: "atoms",
                localData: ["body": "content"],
                remoteData: ["body": NSNull()]
            )
        )
    }

    func testAbsentRemoteBodyKeyIsSafeBecauseUpdateLeavesColumnUntouched() {
        XCTAssertFalse(
            ConflictResolver.remoteWouldBlankLocalContent(
                table: "atoms",
                localData: ["body": "content"],
                remoteData: ["title": "renamed"]
            )
        )
    }

    func testShieldOnlyGuardsAtomsAndOnlySubstantialLocalBodies() {
        XCTAssertFalse(
            ConflictResolver.remoteWouldBlankLocalContent(
                table: "canvas_blocks",
                localData: ["body": "content"],
                remoteData: ["body": ""]
            )
        )
        XCTAssertFalse(
            ConflictResolver.remoteWouldBlankLocalContent(
                table: "atoms",
                localData: ["body": ""],
                remoteData: ["body": ""]
            )
        )
        XCTAssertFalse(
            ConflictResolver.remoteWouldBlankLocalContent(
                table: "atoms",
                localData: ["body": "old"],
                remoteData: ["body": "new"]
            )
        )
    }

    // MARK: - Documents Ride With Their Text Field

    func testAdoptedBodyCarriesRemoteRichDocumentAndKeepsLocalOnlyKeys() throws {
        let localMetadata = """
        {"richBodyDocument":{"blocks":[]},"note_document_style":{"paperTone":"parchment"}}
        """
        let remoteMetadata: [String: Any] = [
            "richBodyDocument": ["blocks": [["kind": "paragraph", "inlines": [["kind": "text", "text": "full body"]]]]]
        ]

        let result = ConflictResolver.metadataAdoptingRemoteDocuments(
            merged: localMetadata,
            remote: remoteMetadata,
            adoptBody: true,
            adoptTitle: false
        )

        let dict = try XCTUnwrap(ConflictResolver.parseJSONDict(result))
        let bodyDoc = try XCTUnwrap(dict["richBodyDocument"] as? [String: Any])
        let blocks = try XCTUnwrap(bodyDoc["blocks"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 1, "remote document must replace the empty local scaffold")
        XCTAssertNotNil(dict["note_document_style"], "local-only metadata keys must survive adoption")
    }

    func testAdoptionRemovesStaleLocalDocumentWhenRemoteHasNone() throws {
        let localMetadata = """
        {"richBodyDocument":{"blocks":[]},"tags":["a"]}
        """
        let result = ConflictResolver.metadataAdoptingRemoteDocuments(
            merged: localMetadata,
            remote: ["other": "keys"],
            adoptBody: true,
            adoptTitle: false
        )

        let dict = try XCTUnwrap(ConflictResolver.parseJSONDict(result))
        XCTAssertNil(
            dict["richBodyDocument"],
            "a stale empty local document would mask the adopted plaintext fallback"
        )
        XCTAssertNotNil(dict["tags"])
    }

    func testAdoptedTitleCarriesRemoteTitleDocument() throws {
        let result = ConflictResolver.metadataAdoptingRemoteDocuments(
            merged: "{\"richTitleDocument\":{\"blocks\":[]}}",
            remote: ["richTitleDocument": ["blocks": [["kind": "paragraph"]]]],
            adoptBody: false,
            adoptTitle: true
        )
        let dict = try XCTUnwrap(ConflictResolver.parseJSONDict(result))
        let titleDoc = try XCTUnwrap(dict["richTitleDocument"] as? [String: Any])
        XCTAssertEqual((titleDoc["blocks"] as? [[String: Any]])?.count, 1)
    }

    func testUnparseableMergedMetadataFallsBackToRemoteCopy() throws {
        let result = ConflictResolver.metadataAdoptingRemoteDocuments(
            merged: "not json",
            remote: ["richBodyDocument": ["blocks": []]],
            adoptBody: true,
            adoptTitle: false
        )
        let dict = try XCTUnwrap(ConflictResolver.parseJSONDict(result))
        XCTAssertNotNil(dict["richBodyDocument"])
    }

    // MARK: - Push-Ack Counter Source Contract

    /// The regression this pins: `handleConflict`/`applyRemoteUpdate` used to
    /// assign `_server_version` from the pulled row's `_version`, which no
    /// client ever bumps — one apply regressed the ack counter and locked the
    /// row into conflict mode on every later pull.
    func testRemoteVersionColumnNeverFeedsTheLocalAckCounter() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sync/ConflictResolver.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            source.contains("merged[\"_server_version\"] = remoteData["),
            "handleConflict must not adopt the server's frozen _version counter"
        )
        XCTAssertFalse(
            source.contains("updateData[\"_server_version\"] = data["),
            "applyRemoteUpdate must not adopt the server's frozen _version counter"
        )
        XCTAssertTrue(
            source.contains("updateData.removeValue(forKey: \"_server_version\")"),
            "applyRemoteUpdate must strip _server_version so remote payloads never move the ack counter"
        )
    }
}
