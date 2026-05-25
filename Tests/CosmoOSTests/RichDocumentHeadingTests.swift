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

    func testSerializerPreservesCollapsedHeadingBlocks() throws {
        let headingID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let hiddenID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let document = RichDocument(blocks: [
            RichBlock(
                id: headingID,
                kind: .heading2,
                inlines: [.text("Draft")],
                heading: RichHeadingMetadata(isCollapsed: true, collapsedBlocks: [
                    RichBlock(id: hiddenID, kind: .paragraph, inlines: [.text("Hidden body")])
                ])
            ),
            RichBlock(kind: .heading2, inlines: [.text("Next")])
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document)

        XCTAssertFalse(attributed.string.contains("Hidden body"))

        let roundTripped = RichDocumentSerializer.document(from: attributed)
        let heading = try XCTUnwrap(roundTripped.blocks.first)
        XCTAssertEqual(heading.id, headingID)
        XCTAssertEqual(heading.heading?.isCollapsed, true)
        XCTAssertEqual(heading.heading?.collapsedBlocks.first?.id, hiddenID)
        XCTAssertEqual(heading.heading?.collapsedBlocks.first?.plainInlineText, "Hidden body")
    }

    func testHeadingBlockIDsSurviveSerializerRoundTrip() throws {
        let headingID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let document = RichDocument(blocks: [
            RichBlock(id: headingID, kind: .heading3, inlines: [.text("Hook")])
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document)
        let roundTripped = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(roundTripped.blocks.first?.id, headingID)
        XCTAssertEqual(roundTripped.blocks.first?.heading?.isCollapsed, false)
        XCTAssertEqual(roundTripped.blocks.first?.heading?.collapsedBlocks, [])
    }

    func testNestedCollapsedHeadingsPreserveHiddenContentAcrossVisibleRoundTrip() throws {
        let parentID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let childID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let hiddenID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let document = RichDocument(blocks: [
            RichBlock(id: parentID, kind: .heading1, inlines: [.text("Parent")]),
            RichBlock(
                id: childID,
                kind: .heading2,
                inlines: [.text("Child")],
                heading: RichHeadingMetadata(isCollapsed: true, collapsedBlocks: [
                    RichBlock(id: hiddenID, kind: .paragraph, inlines: [.text("Hidden child body")])
                ])
            ),
            .paragraph("Visible parent body"),
            RichBlock(kind: .heading1, inlines: [.text("Next")])
        ])
        let collapsedParent = RichDocumentHeadings.toggledCollapse(headingID: parentID, in: document)

        let attributed = RichDocumentSerializer.attributedString(from: collapsedParent)

        XCTAssertFalse(attributed.string.contains("Child"))
        XCTAssertFalse(attributed.string.contains("Hidden child body"))

        let roundTripped = RichDocumentSerializer.document(from: attributed)
        XCTAssertEqual(roundTripped.plainText, document.plainText)
        XCTAssertTrue(roundTripped.containsCollapsedHiddenContent)

        let expandedParent = RichDocumentHeadings.toggledCollapse(headingID: parentID, in: roundTripped)
        let child = try XCTUnwrap(expandedParent.blocks.first { $0.id == childID })
        XCTAssertEqual(child.heading?.isCollapsed, true)
        XCTAssertEqual(child.heading?.collapsedBlocks.first?.id, hiddenID)
        XCTAssertEqual(child.heading?.collapsedBlocks.first?.plainInlineText, "Hidden child body")
    }
}
