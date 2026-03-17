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
}
