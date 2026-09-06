import XCTest
@testable import CosmoOS

final class UnifiedPageRichTextEditTests: XCTestCase {
    private func operation(_ source: RichDocument, original: String?, proposed: String?,
                           kind: CosmoAssistantProposalOperationKind = .textReplacement,
                           mark: CosmoAssistantFormatMark? = nil) -> CosmoAssistantProposalOperation {
        CosmoAssistantProposalOperation(kind: kind, targetID: "note:page:body", anchorID: "body",
            originalText: original, proposedText: proposed,
            sourceHash: CosmoEditableSurfaceHasher.hash(source.plainText), rationale: "Test edit", formatMark: mark)
    }

    func testReplacementKeepsVisualBlocksAndAllUntouchedRunFields() throws {
        let before = RichInlineNode(kind: .text, text: "Read ", marks: [.italic], inkID: "sage", href: "https://example.com",
                                    passthrough: ["futureRun": .bool(true)])
        let after = RichInlineNode(kind: .text, text: " today", marks: [.bold], highlightID: "sand")
        var paragraph = RichBlock(kind: .paragraph, inlines: [before, .text("the draft"), after])
        paragraph.passthrough = ["futureBlock": .string("kept")]
        let image = RichBlock(kind: .image, inlines: [.image(RichImageReference(path: "photo.png", width: 120, height: 80))])
        let section = RichBlock.section(title: "Exercise", children: [.paragraph("Keep the nested material")])
        let source = RichDocument(blocks: [paragraph, image, .table(), section])

        let result = try UnifiedPageRichTextEdit.applying(operation(source, original: "the draft", proposed: "the final version"), to: source)

        XCTAssertEqual(result.blocks[0].plainInlineText, "Read the final version today")
        XCTAssertEqual(result.blocks[0].id, paragraph.id)
        XCTAssertEqual(result.blocks[0].passthrough, paragraph.passthrough)
        XCTAssertEqual(result.blocks[0].inlines.first, before)
        XCTAssertEqual(result.blocks[0].inlines.last, after)
        XCTAssertEqual(Array(result.blocks.dropFirst()), Array(source.blocks.dropFirst()))
    }

    func testBoundaryRunSplittingKeepsMarksLinksUnknownFieldsAndUnicode() throws {
        let run = RichInlineNode(kind: .text, text: "👩🏽‍💻 café draft résumé", marks: [.bold], inkID: "sage",
                                 highlightID: "sand", href: "https://example.com", passthrough: ["future": .bool(true)])
        let source = RichDocument(blocks: [RichBlock(kind: .paragraph, inlines: [run])])
        let result = try UnifiedPageRichTextEdit.applying(operation(source, original: "draft", proposed: "finished"), to: source)
        XCTAssertEqual(result.plainText, "👩🏽‍💻 café finished résumé")
        XCTAssertEqual(result.blocks[0].inlines.map(\.styling), Array(repeating: run.styling, count: 3))
        XCTAssertTrue(result.blocks[0].inlines.allSatisfy { $0.passthrough == run.passthrough })
        XCTAssertEqual(Set(result.blocks[0].inlines.map(\.id)).count, 3)
    }

    func testMultilineParagraphEditPreservesStyledBoundaryFragmentsAndFollowingBlocks() throws {
        let run = RichInlineNode(kind: .text, text: "Before draft after", marks: [.underline], href: "https://example.com")
        let paragraph = RichBlock(kind: .paragraph, inlines: [run])
        let table = RichBlock.table()
        let source = RichDocument(blocks: [paragraph, table])
        let result = try UnifiedPageRichTextEdit.applying(operation(source, original: "draft", proposed: "first\nsecond"), to: source)
        XCTAssertEqual(result.blocks.map(\.kind), [.paragraph, .paragraph, .table])
        XCTAssertEqual(result.blocks[0].plainInlineText, "Before first")
        XCTAssertEqual(result.blocks[1].plainInlineText, "second after")
        XCTAssertEqual(result.blocks[0].id, paragraph.id)
        XCTAssertEqual(result.blocks[1].inlines.last?.styling, run.styling)
        XCTAssertEqual(result.blocks[2], table)
        let ids = result.blocks.flatMap(\.inlines).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testNestedAndCollapsedTextEditsPreserveTheirContainers() throws {
        let source = RichDocument(blocks: [
            .section(title: "Container", children: [.paragraph("Nested target")]),
            RichBlock(kind: .heading2, inlines: [.text("Folded")], heading: RichHeadingMetadata(
                isCollapsed: true, collapsedBlocks: [.paragraph("Hidden target")], isCollapsible: true))
        ])
        let first = try UnifiedPageRichTextEdit.applying(operation(source, original: "Nested target", proposed: "Nested revision"), to: source)
        XCTAssertEqual(first.blocks[0].id, source.blocks[0].id)
        XCTAssertEqual(first.blocks[0].section, source.blocks[0].section)
        XCTAssertEqual(first.blocks[0].children[0].id, source.blocks[0].children[0].id)
        XCTAssertEqual(first.blocks[1], source.blocks[1])
        let second = try UnifiedPageRichTextEdit.applying(operation(first, original: "Hidden target", proposed: "Hidden revision"), to: first)
        XCTAssertEqual(second.blocks[1].heading?.isCollapsed, true)
        XCTAssertEqual(second.blocks[1].heading?.isCollapsible, true)
        XCTAssertEqual(second.blocks[1].heading?.collapsedBlocks[0].id, source.blocks[1].heading?.collapsedBlocks[0].id)
        XCTAssertEqual(second.blocks[0], first.blocks[0])
    }

    func testCrossBlockEditFailsWithoutFlatteningSource() {
        let source = RichDocument(blocks: [.paragraph("First paragraph"), .paragraph("Second paragraph"), .table()])
        XCTAssertThrowsError(try UnifiedPageRichTextEdit.applying(operation(source,
            original: "First paragraph\nSecond paragraph", proposed: "Merged text"), to: source)) {
            XCTAssertEqual($0 as? UnifiedPageRichTextEdit.Failure, .unsupportedStructure)
        }
        XCTAssertEqual(source.blocks.count, 3)
        XCTAssertEqual(source.blocks.last?.kind, .table)
    }

    func testRepeatedOrStaleTargetFailsInsteadOfEditingArbitraryTextOrAppending() {
        let source = RichDocument(blocks: [.paragraph("Repeated words"), .paragraph("Repeated words")])
        XCTAssertThrowsError(try UnifiedPageRichTextEdit.applying(operation(source, original: "Repeated words", proposed: "New text"), to: source)) {
            XCTAssertEqual($0 as? UnifiedPageRichTextEdit.Failure, .ambiguousTarget)
        }
        XCTAssertThrowsError(try UnifiedPageRichTextEdit.applying(operation(source, original: "Stale words", proposed: "New text"), to: source)) {
            XCTAssertEqual($0 as? UnifiedPageRichTextEdit.Failure, .missingTarget)
        }
    }

    func testEmbeddedMentionCannotBeReplacedAsOrdinaryText() {
        let mention = RichInlineNode.mention(RichMention(entityUUID: "source", entityID: nil, entityType: .note, titleSnapshot: "Source"))
        let source = RichDocument(blocks: [RichBlock(kind: .paragraph, inlines: [.text("See "), mention, .text(" for detail")])])
        XCTAssertThrowsError(try UnifiedPageRichTextEdit.applying(operation(source, original: "@Source", proposed: "A different source"), to: source)) {
            XCTAssertEqual($0 as? UnifiedPageRichTextEdit.Failure, .unsupportedStructure)
        }
        XCTAssertEqual(source.blocks[0].inlines[1], mention)
    }

    func testFormattingChangesOnlySelectedWordsAndRetainsAllOtherRunFields() throws {
        let run = RichInlineNode(kind: .text, text: "Before selected after", marks: [.italic], inkID: "sage",
                                 highlightID: "sand", href: "https://example.com", passthrough: ["future": .bool(true)])
        let source = RichDocument(blocks: [RichBlock(kind: .paragraph, inlines: [run]), .table()])
        let result = try UnifiedPageRichTextEdit.applying(operation(source, original: "selected", proposed: nil,
            kind: .formatMarks, mark: .bold), to: source)
        XCTAssertEqual(result.plainText, source.plainText)
        let inlines = result.blocks[0].inlines
        XCTAssertEqual(inlines.map(\.marks), [[.italic], [.italic, .bold], [.italic]])
        XCTAssertTrue(inlines.allSatisfy { $0.href == run.href && $0.inkID == run.inkID && $0.highlightID == run.highlightID && $0.passthrough == run.passthrough })
        XCTAssertEqual(result.blocks[1], source.blocks[1])
    }

    func testInsertionAndExplicitAppendKeepExistingBlocks() throws {
        let source = RichDocument(blocks: [.paragraph("Anchor sentence"), .table()])
        let inserted = try UnifiedPageRichTextEdit.applying(operation(source, original: "Anchor sentence", proposed: "Added paragraph", kind: .textInsertion), to: source)
        XCTAssertEqual(inserted.blocks[0], source.blocks[0])
        XCTAssertEqual(inserted.blocks[1].plainInlineText, "Added paragraph")
        XCTAssertEqual(inserted.blocks[2], source.blocks[1])
        let appended = try UnifiedPageRichTextEdit.applying(operation(source, original: nil, proposed: "Appended paragraph", kind: .textInsertion), to: source)
        XCTAssertEqual(Array(appended.blocks.prefix(2)), source.blocks)
        XCTAssertEqual(appended.plainText, source.plainText + "\n\nAppended paragraph")
    }

    func testMultilineReplacementInsideHeadingLeavesHeadingAndHiddenContentUntouched() {
        let source = RichDocument(blocks: [RichBlock(kind: .heading1, inlines: [.text("Heading")], heading: RichHeadingMetadata(
            isCollapsed: true, collapsedBlocks: [.paragraph("Preserved body")], isCollapsible: true))])
        XCTAssertThrowsError(try UnifiedPageRichTextEdit.applying(operation(source, original: "Heading", proposed: "Heading\nSecond heading"), to: source)) {
            XCTAssertEqual($0 as? UnifiedPageRichTextEdit.Failure, .unsupportedStructure)
        }
        XCTAssertEqual(source.blocks[0].heading?.collapsedBlocks[0].plainInlineText, "Preserved body")
    }
}
