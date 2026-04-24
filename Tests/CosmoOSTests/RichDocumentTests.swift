import XCTest
@testable import CosmoOS

final class RichDocumentTests: XCTestCase {
    func testLegacyMigrationParsesRequestedSlashBlocks() {
        let document = RichDocument.migrateLegacy(
            """
            # Title
            ## Subtitle
            ### Section
            │ Quote
            • Bullet
            1. Numbered
            ☑ Done
            ☐ Todo
            ---
            """
        )

        XCTAssertEqual(
            document.blocks.map(\.kind),
            [.heading1, .heading2, .heading3, .quote, .bulletList, .numberedList, .checklist, .checklist, .divider]
        )
        XCTAssertEqual(document.blocks[6].checked, true)
        XCTAssertEqual(document.blocks[7].checked, false)
    }

    func testPlainTextIncludesMentionsAndImages() {
        let mention = RichMention(
            entityUUID: "note-uuid",
            entityID: 42,
            entityType: .note,
            titleSnapshot: "Michael"
        )
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [
                .text("Hello "),
                .mention(mention),
                .text("!")
            ]),
            RichBlock(kind: .image, inlines: [
                .image(RichImageReference(path: "images/test.png", width: 320, height: 180))
            ])
        ])

        XCTAssertEqual(document.plainText, "Hello @Michael!\n[Image]")
    }

    func testMetadataPersistenceRoundTripsTitleAndBodyDocuments() {
        let titleDocument = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Connected Note")])
        ])
        let bodyDocument = RichDocument(blocks: [
            RichBlock(kind: .checklist, inlines: [.text("Ship mentions")], checked: true),
            RichBlock(kind: .paragraph, inlines: [.text("Linked to @Michael")])
        ])

        let fields = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: nil,
            titleDocument: titleDocument,
            bodyDocument: bodyDocument
        )

        XCTAssertEqual(fields.title, "Connected Note")
        XCTAssertEqual(fields.body, bodyDocument.plainText)
        XCTAssertEqual(
            RichDocumentPersistence.loadAtomDocument(field: .title, metadata: fields.metadata, fallbackPlainText: nil),
            titleDocument
        )
        XCTAssertEqual(
            RichDocumentPersistence.loadAtomDocument(field: .body, metadata: fields.metadata, fallbackPlainText: nil),
            bodyDocument
        )
    }

    func testAttributedSerializerRoundTripsInlineMarksAndMentionMetadata() {
        let mention = RichMention(
            entityUUID: "connection-uuid",
            entityID: 7,
            entityType: .connection,
            titleSnapshot: "System"
        )
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [
                .text("Bold", marks: [.bold]),
                .text(" + "),
                .text("Italic", marks: [.italic]),
                .text(" + "),
                .text("Underline", marks: [.underline]),
                .text(" "),
                .mention(mention)
            ]),
            RichBlock(kind: .checklist, inlines: [.text("Complete")], checked: true)
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document, fontSize: 16, darkMode: false)
        let roundTripped = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(roundTripped.plainText, document.plainText)
        XCTAssertEqual(roundTripped.blocks.first?.inlines.first?.marks, [.bold])
        XCTAssertEqual(roundTripped.blocks.first?.inlines[2].marks, [.italic])
        XCTAssertEqual(roundTripped.blocks.first?.inlines[4].marks, [.underline])
        XCTAssertEqual(roundTripped.blocks.first?.inlines.last?.mention, mention)
        XCTAssertEqual(roundTripped.blocks.last?.checked, true)
    }

    func testTitleNormalizationStripsHeadingFormatting() {
        let headingTitle = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [.text("Burger King", marks: [.bold])])
        ])

        let normalized = RichDocumentPersistence.normalizedTitleDocument(headingTitle)

        XCTAssertEqual(RichDocumentPersistence.titlePlainText(from: headingTitle), "Burger King")
        XCTAssertEqual(normalized.blocks.count, 1)
        XCTAssertEqual(normalized.blocks.first?.kind, .paragraph)
        XCTAssertEqual(normalized.plainText, "Burger King")
    }

    func testTitleNormalizationPreservesInlineMarksAndMentions() {
        let mention = RichMention(
            entityUUID: "connection-uuid",
            entityID: 7,
            entityType: .connection,
            titleSnapshot: "System"
        )
        let document = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [
                .text("  Alpha", marks: [.bold]),
                .text(" "),
                .mention(mention)
            ]),
            RichBlock(kind: .bulletList, inlines: [
                .text("Beta\nGamma", marks: [.italic])
            ]),
            RichBlock(kind: .image, inlines: [
                .image(RichImageReference(path: "images/title.png", width: 128, height: 96))
            ])
        ])

        let normalized = RichDocumentPersistence.normalizedTitleDocument(document)

        XCTAssertEqual(normalized.blocks.count, 1)
        XCTAssertEqual(normalized.blocks.first?.kind, .paragraph)
        XCTAssertEqual(RichDocumentPersistence.titlePlainText(from: normalized), "Alpha @System Beta Gamma")
        XCTAssertEqual(normalized.blocks.first?.inlines.first?.marks, [.bold])
        XCTAssertEqual(normalized.blocks.first?.inlines[2].mention, mention)
        XCTAssertEqual(normalized.blocks.first?.inlines.last?.marks, [.italic])
    }

    func testTitleNormalizationCollapsesWhitespaceAcrossBlocks() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("  First\nLine  ")]),
            RichBlock(kind: .checklist, inlines: [.text("Second\n\nLine")], checked: true),
            RichBlock(kind: .divider),
            RichBlock(kind: .quote, inlines: [.text(" Third ")])
        ])

        let normalized = RichDocumentPersistence.normalizedTitleDocument(document)

        XCTAssertEqual(normalized.blocks.count, 1)
        XCTAssertEqual(normalized.blocks.first?.kind, .paragraph)
        XCTAssertEqual(normalized.plainText, "First Line Second Line Third")
        XCTAssertEqual(RichDocumentPersistence.titlePlainText(from: normalized), "First Line Second Line Third")
    }

    func testTitlePayloadFactoryReturnsNormalizedDocumentAndMatchingPlainText() {
        let sourceDocument = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [
                .text("Burger", marks: [.bold])
            ]),
            RichBlock(kind: .paragraph, inlines: [
                .text(" King")
            ])
        ])
        let attributed = RichDocumentSerializer.attributedString(
            from: sourceDocument,
            fontSize: 32,
            darkMode: false,
            baseFontWeight: .bold
        )

        let payload = TitleDocumentChangePayloadFactory.payload(from: attributed)

        XCTAssertEqual(payload.plainText, "Burger King")
        XCTAssertEqual(payload.document.blocks.count, 1)
        XCTAssertEqual(payload.document.blocks.first?.kind, .paragraph)
        XCTAssertEqual(payload.document.plainText, "Burger King")
    }

    func testLoadAtomDocumentPrefersFallbackPlainTextWhenMetadataBodyIsShorter() {
        let truncatedBody = String(repeating: "A", count: 80)
        let fullBody = String(repeating: "B", count: 240)
        let fields = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: nil,
            bodyDocument: RichDocument.migrateLegacy(truncatedBody)
        )

        let loaded = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: fields.metadata,
            fallbackPlainText: fullBody,
            preferFallbackPlainTextWhenRicher: true
        )

        XCTAssertEqual(loaded.plainText, fullBody)
    }

    func testNoteSnapshotPrefersPlainBodyWhenStructuredDocumentLags() {
        let staleBody = "Short body"
        let fullBody = Array(repeating: "This is the body that should win.", count: 8).joined(separator: " ")
        let snapshot = RichDocumentPersistence.noteSnapshot(
            existingMetadata: nil,
            titleDocument: RichDocument.migrateLegacy("Recovered note"),
            bodyDocument: RichDocument.migrateLegacy(staleBody),
            plainBodyText: fullBody
        )

        XCTAssertEqual(snapshot.bodyPlainText, fullBody)
        XCTAssertEqual(snapshot.bodyDocument.plainText, fullBody)

        let payload = snapshot.noteFocusStatePayload(atomUUID: "note-uuid")
        XCTAssertEqual(payload["body"] as? String, fullBody)

        let encodedBodyDocument = payload["bodyDocumentJSON"] as? String
        let decodedBodyDocument = encodedBodyDocument
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(RichDocument.self, from: $0) }
        XCTAssertEqual(decodedBodyDocument?.plainText, fullBody)
    }

    func testSyncWriteDispositionUsesUpsertForUnsyncedAtomUpdates() {
        XCTAssertEqual(
            SyncWriteDisposition.resolve(requestedOperation: "UPDATE", serverVersion: 0),
            .upsert
        )
        XCTAssertEqual(
            SyncWriteDisposition.resolve(requestedOperation: "UPDATE", serverVersion: 3),
            .update
        )
    }

    func testCanvasBlockFromNoteAtomCarriesFullBodyAndRichDocuments() {
        let fullBody = Array(repeating: "Performance note body should survive restart.", count: 12)
            .joined(separator: " ")
        let snapshot = RichDocumentPersistence.noteSnapshot(
            existingMetadata: nil,
            titleDocument: RichDocument.migrateLegacy("Ben Call April 12"),
            bodyDocument: RichDocument.migrateLegacy("short preview"),
            plainBodyText: fullBody
        )

        var atom = Atom.new(
            type: .note,
            title: snapshot.atomTitle,
            body: snapshot.atomBody,
            metadata: snapshot.metadata
        )
        atom.id = 42

        let block = CanvasBlock.fromAtom(atom, position: .zero)

        XCTAssertEqual(block.metadata["content"], fullBody)
        XCTAssertEqual(block.metadata["title"], "Ben Call April 12")
        XCTAssertNotNil(block.metadata[RichDocumentMetadataKeys.bodyDocument])
        XCTAssertNotNil(block.metadata[RichDocumentMetadataKeys.titleDocument])
    }

    func testMentionRankingNormalizesSQLiteTimestamps() {
        var atom = Atom.new(type: .note, title: "Recent note")
        atom.updatedAt = "2026-04-22 08:30:15"

        XCTAssertEqual(
            MentionSearchRanking.recencyKey(for: atom),
            "2026-04-22T08:30:15.000Z"
        )
    }

    func testMentionRankingPrefersThinkspaceLastOpenedMetadata() throws {
        let metadata = ThinkspaceMetadata(
            name: "Greenhouse",
            lastOpened: Date(timeIntervalSince1970: 1_776_787_200)
        )
        let metadataString = try XCTUnwrap(
            String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )

        var atom = Atom.new(type: .thinkspace, title: "Workspace", metadata: metadataString)
        atom.updatedAt = "2026-04-01T10:00:00Z"

        XCTAssertEqual(
            MentionSearchRanking.recencyKey(for: atom),
            "2026-04-21T16:00:00.000Z"
        )
    }

    func testMentionRankingPrefersMoreRecentMatchOverHigherTextScore() {
        let newer = MentionSearchResult(
            atomID: 1,
            atomUUID: "newer",
            atomType: .note,
            entityType: .note,
            title: "Fresh Note",
            subtitle: nil,
            typeLabel: "Note",
            updatedAt: "2026-04-22T09:00:00Z",
            recencyKey: "2026-04-22T09:00:00.000Z",
            score: 50
        )
        let older = MentionSearchResult(
            atomID: 2,
            atomUUID: "older",
            atomType: .note,
            entityType: .note,
            title: "Older Exact Match",
            subtitle: nil,
            typeLabel: "Note",
            updatedAt: "2026-04-20T09:00:00Z",
            recencyKey: "2026-04-20T09:00:00.000Z",
            score: 400
        )

        let sorted = [older, newer].sorted(by: MentionSearchRanking.compare)

        XCTAssertEqual(sorted.map(\.atomUUID), ["newer", "older"])
    }
}
