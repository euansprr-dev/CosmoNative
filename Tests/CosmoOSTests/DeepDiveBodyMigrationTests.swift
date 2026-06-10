// CosmoOS/Tests/CosmoOSTests/DeepDiveBodyMigrationTests.swift

import XCTest
@testable import CosmoOS

final class DeepDiveBodyMigrationTests: XCTestCase {

    private let pollutedBody = """
    Breathwork is a diverse category of practices involving conscious manipulation of breathing patterns.

    ## Current Understanding
    Breathing occupies a unique position as both an automatic physiological function and a voluntarily controllable process.

    _Appended from Inquiry Session C9A1190C-029A-41E0-A8C5-5ECE1E18FDBF, source artifact FBAD3B66-25AE-46C7-BC84-A978C8D47DB7, 2026-05-18T03:20:17Z._

    ## Current Understanding
    This dual nature makes it a bridge between conscious and unconscious processes.

    _Appended from Inquiry Session C9A1190C-029A-41E0-A8C5-5ECE1E18FDBF, source artifact C0DB4783-914D-4036-BADE-3CD4422FCF98, 2026-05-18T03:20:17Z._
    """

    func testParsesAppendedBlocksAndCleansBody() {
        let result = DeepDiveBodyMigration.parseAppendedBlocks(from: pollutedBody)

        XCTAssertEqual(result.blocks.count, 2)
        XCTAssertEqual(result.cleanBody, "Breathwork is a diverse category of practices involving conscious manipulation of breathing patterns.")

        let first = result.blocks[0]
        XCTAssertEqual(first.title, "Current Understanding")
        XCTAssertTrue(first.body.contains("automatic physiological function"))
        XCTAssertEqual(first.sessionUUID, "C9A1190C-029A-41E0-A8C5-5ECE1E18FDBF")
        XCTAssertEqual(first.sourceArtifactUUID, "FBAD3B66-25AE-46C7-BC84-A978C8D47DB7")
        XCTAssertEqual(first.date, "2026-05-18T03:20:17Z")

        let second = result.blocks[1]
        XCTAssertEqual(second.sourceArtifactUUID, "C0DB4783-914D-4036-BADE-3CD4422FCF98")
        XCTAssertTrue(second.body.contains("bridge between conscious and unconscious"))
    }

    func testBlockOrderIsPreservedSoLatestBecomesNarrative() {
        let result = DeepDiveBodyMigration.parseAppendedBlocks(from: pollutedBody)
        XCTAssertTrue(result.blocks.last?.body.contains("dual nature") ?? false)
    }

    func testParsesOperationIdVariantFooter() {
        let body = """
        ## Update
        Some text.

        _Appended from Inquiry Session AAAA-1, source artifact BBBB-2, operation op-99, 2026-06-01T00:00:00Z._
        """
        let result = DeepDiveBodyMigration.parseAppendedBlocks(from: body)
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].sessionUUID, "AAAA-1")
        XCTAssertEqual(result.blocks[0].date, "2026-06-01T00:00:00Z")
        XCTAssertTrue(result.cleanBody.isEmpty)
    }

    func testNonPollutedBodyIsUntouched() {
        let body = "Just a normal about text with ## headings\nand more text."
        let result = DeepDiveBodyMigration.parseAppendedBlocks(from: body)
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertEqual(result.cleanBody, body)
    }

    func testNarrativeRevisionRecordingIsIdempotent() {
        var understanding = CurrentUnderstanding()
        let revision = UnderstandingNarrativeRevision(
            id: "rev-1",
            date: "2026-06-01T00:00:00Z",
            text: "First synthesis",
            originOperationId: "op-1",
            kind: .migration
        )
        XCTAssertTrue(understanding.recordNarrativeRevision(revision))
        XCTAssertFalse(understanding.recordNarrativeRevision(revision))
        XCTAssertEqual(understanding.narrativeHistory?.count, 1)
        XCTAssertEqual(understanding.narrative, "First synthesis")
    }
}
