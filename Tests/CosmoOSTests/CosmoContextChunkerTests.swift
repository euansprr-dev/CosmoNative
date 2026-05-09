import XCTest
@testable import CosmoOS

final class CosmoContextChunkerTests: XCTestCase {
    func testContextSourceKeepsAtomIdentityAndHashes() {
        let source = ContextSource(
            id: "source-1",
            kind: .atom,
            title: "Walking Beam brief",
            atomUUID: "atom-123",
            bodyHash: "body-hash",
            metadataHash: "meta-hash",
            clientUUID: "client-1",
            pinState: .pinned
        )

        XCTAssertEqual(source.kind, .atom)
        XCTAssertEqual(source.atomUUID, "atom-123")
        XCTAssertEqual(source.pinState, .pinned)
        XCTAssertTrue(source.needsReindex(currentBodyHash: "new-hash", currentMetadataHash: "meta-hash"))
        XCTAssertFalse(source.needsReindex(currentBodyHash: "body-hash", currentMetadataHash: "meta-hash"))
    }

    func testContextSessionKeepsPinnedSourcesInOrderWithoutDuplicates() {
        var session = ContextSession(id: "conversation-1", surface: .cosmoWindow)
        session.pinSourceID("source-a")
        session.pinSourceID("source-b")
        session.pinSourceID("source-a")

        XCTAssertEqual(session.pinnedSourceIDs, ["source-a", "source-b"])
    }

    func testChunkerPreservesExactPhraseInLaterChunk() {
        let intro = String(repeating: "Intro setup sentence. ", count: 160)
        let phrase = "All bedroom doors need working locks on doors before tenant intake."
        let body = intro + phrase + String(repeating: " Closing details.", count: 120)

        let chunks = ContextChunker.chunk(
            sourceID: "source-1",
            title: "Walking Beam brief",
            body: body,
            bodyHash: "hash",
            maxCharacters: 900,
            overlapCharacters: 180
        )

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.contains { $0.rawText.contains(phrase) })
    }

    func testChunkerAddsUsefulAnchors() {
        let body = "First paragraph.\n\nSecond paragraph about locks on doors.\n\nThird paragraph."
        let chunks = ContextChunker.chunk(
            sourceID: "source-1",
            title: "Brief",
            body: body,
            bodyHash: "hash",
            maxCharacters: 80,
            overlapCharacters: 10
        )

        XCTAssertTrue(chunks.allSatisfy { $0.anchor?.hasPrefix("chunk-") == true })
    }
}
