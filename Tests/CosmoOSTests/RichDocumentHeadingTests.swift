import XCTest
@testable import CosmoOS

final class RichDocumentHeadingTests: XCTestCase {
    func testOutlineExtractsNestedHeadingEntries() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [.text("Launch")]),
            .paragraph("Intro"),
            RichBlock(kind: .heading2, inlines: [.text("Draft")]),
            .paragraph("Body"),
            RichBlock(kind: .heading3, inlines: [.text("Hook")]),
            .paragraph("Hook copy"),
            RichBlock(kind: .heading2, inlines: [.text("Polish")])
        ])

        let outline = RichDocumentHeadings.outline(in: document)

        XCTAssertEqual(outline.map(\.level), [1, 2, 3, 2])
        XCTAssertEqual(outline.map(\.title), ["Launch", "Draft", "Hook", "Polish"])
        XCTAssertEqual(outline[0].parentID, nil)
        XCTAssertEqual(outline[1].parentID, outline[0].id)
        XCTAssertEqual(outline[2].parentID, outline[1].id)
        XCTAssertEqual(outline[3].parentID, outline[0].id)
    }

    func testCollapseMovesOwnedSectionIntoHeadingMetadata() throws {
        let document = RichDocument(blocks: [
            RichBlock(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, kind: .heading1, inlines: [.text("Launch")]),
            .paragraph("Intro"),
            RichBlock(kind: .heading2, inlines: [.text("Draft")]),
            .paragraph("Body"),
            RichBlock(kind: .heading1, inlines: [.text("Archive")])
        ])
        let headingID = try XCTUnwrap(document.blocks.first?.id)

        let collapsed = RichDocumentHeadings.toggledCollapse(headingID: headingID, in: document)

        XCTAssertEqual(collapsed.blocks.map(\.kind), [.heading1, .heading1])
        XCTAssertEqual(collapsed.blocks.first?.heading?.isCollapsed, true)
        XCTAssertEqual(collapsed.blocks.first?.heading?.collapsedBlocks.map(\.kind), [.paragraph, .heading2, .paragraph])
        XCTAssertEqual(collapsed.plainText, document.plainText)
    }

    func testExpandRestoresCollapsedBlocksAfterHeading() throws {
        let headingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let document = RichDocument(blocks: [
            RichBlock(
                id: headingID,
                kind: .heading1,
                inlines: [.text("Launch")],
                heading: RichHeadingMetadata(isCollapsed: true, collapsedBlocks: [
                    .paragraph("Intro"),
                    RichBlock(kind: .heading2, inlines: [.text("Draft")])
                ])
            ),
            RichBlock(kind: .heading1, inlines: [.text("Archive")])
        ])

        let expanded = RichDocumentHeadings.toggledCollapse(headingID: headingID, in: document)

        XCTAssertEqual(expanded.blocks.map(\.kind), [.heading1, .paragraph, .heading2, .heading1])
        XCTAssertEqual(expanded.blocks.first?.heading?.isCollapsed, false)
        XCTAssertEqual(expanded.blocks.first?.heading?.collapsedBlocks, [])
    }

    func testReturnBelowCollapsedHeadingInsertsVisibleParagraphOutsideHiddenBlocks() throws {
        let headingID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let document = RichDocument(blocks: [
            RichBlock(
                id: headingID,
                kind: .heading1,
                inlines: [.text("Launch")],
                heading: RichHeadingMetadata(isCollapsed: true, collapsedBlocks: [
                    .paragraph("Hidden intro")
                ])
            ),
            RichBlock(kind: .heading1, inlines: [.text("Archive")])
        ])

        let inserted = RichDocumentHeadings.insertParagraphAfterCollapsedHeading(
            headingID: headingID,
            in: document
        )

        XCTAssertEqual(inserted.blocks.map(\.kind), [.heading1, .paragraph, .heading1])
        XCTAssertEqual(inserted.blocks[1].plainInlineText, "")
        XCTAssertEqual(inserted.blocks[0].heading?.collapsedBlocks.first?.plainInlineText, "Hidden intro")
    }
}
