import XCTest
@testable import CosmoOS

final class BlockOperationsTests: XCTestCase {
    func testBlockPathAddressesRootAndNestedBlocks() throws {
        let root = BlockPath.root(index: 2)
        XCTAssertEqual(root.indices, [2])
        XCTAssertEqual(root.parent, nil)
        XCTAssertEqual(root.depth, 0)

        let nested = root.appendingChild(index: 1)
        XCTAssertEqual(nested.indices, [2, 1])
        XCTAssertEqual(nested.parent?.indices, [2])
        XCTAssertEqual(nested.depth, 1)
    }

    func testBlockPathRejectsNegativeIndices() {
        XCTAssertNil(BlockPath(indices: [-1]))
        XCTAssertNil(BlockPath(indices: [0, -1]))
        XCTAssertEqual(BlockPath(indices: [0, 2])?.indices, [0, 2])
    }

    func testPathLookupFollowsBlockIdentityAfterEarlierSiblingIsRemoved() throws {
        let first = RichBlock.paragraph("A")
        let second = RichBlock.paragraph("B")
        let third = RichBlock.paragraph("C")
        let document = RichDocument(blocks: [first, second, third])

        let deleted = try BlockOperations.deleteEmptyBlockBackward(
            in: RichDocument(blocks: [first, RichBlock(id: second.id, kind: .paragraph, inlines: [.text("")]), third]),
            at: .root(index: 1)
        )

        XCTAssertEqual(BlockOperations.path(of: third.id, in: deleted.document), .root(index: 1))
        XCTAssertNil(BlockOperations.path(of: second.id, in: deleted.document))
        XCTAssertEqual(BlockOperations.path(of: first.id, in: document), .root(index: 0))
    }

    func testTransformPreservesInlineContentAndChangesKind() throws {
        let id = UUID()
        let document = RichDocument(blocks: [
            RichBlock(id: id, kind: .paragraph, inlines: [.text("Launch idea")])
        ])

        let result = try BlockOperations.transformBlock(
            in: document,
            at: .root(index: 0),
            to: .heading2
        )

        XCTAssertEqual(result.document.blocks[0].id, id)
        XCTAssertEqual(result.document.blocks[0].kind, .heading2)
        XCTAssertEqual(result.document.blocks[0].plainInlineText, "Launch idea")
        XCTAssertEqual(result.focusPath, .root(index: 0))
    }

    func testBodyPlaceholderOnlyAppearsOnFirstEmptyRootBlock() {
        let first = RichBlock.paragraph("")
        let second = RichBlock.paragraph("")
        let document = RichDocument(blocks: [first, second])

        XCTAssertTrue(BlockPlaceholderPolicy.shouldShowBodyPlaceholder(for: first, at: .root(index: 0), in: document))
        XCTAssertFalse(BlockPlaceholderPolicy.shouldShowBodyPlaceholder(for: second, at: .root(index: 1), in: document))
    }

    func testBodyPlaceholderHidesWhenFirstRootBlockHasText() {
        let first = RichBlock.paragraph("Already writing")
        let second = RichBlock.paragraph("")
        let document = RichDocument(blocks: [first, second])

        XCTAssertFalse(BlockPlaceholderPolicy.shouldShowBodyPlaceholder(for: first, at: .root(index: 0), in: document))
        XCTAssertFalse(BlockPlaceholderPolicy.shouldShowBodyPlaceholder(for: second, at: .root(index: 1), in: document))
    }

    func testBodyPlaceholderAppearsAfterEmptyDocumentIsSeeded() {
        let seeded = RichBlock.paragraph("")
        let document = RichDocument(blocks: [seeded])

        XCTAssertTrue(BlockPlaceholderPolicy.shouldShowBodyPlaceholder(for: seeded, at: .root(index: 0), in: document))
    }

    func testInsertAfterAddsBlockAndFocusesInsertedBlock() throws {
        let document = RichDocument(blocks: [.paragraph("A")])
        let inserted = RichBlock(kind: .checklist, inlines: [.text("")], checked: false)

        let result = try BlockOperations.insertBlock(inserted, in: document, after: .root(index: 0))

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["A", ""])
        XCTAssertEqual(result.document.blocks[1].kind, .checklist)
        XCTAssertEqual(result.focusPath, .root(index: 1))
    }

    func testSplitParagraphAtTextOffsetCreatesTwoBlocks() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Hello world")])
        ])

        let result = try BlockOperations.splitTextBlock(
            in: document,
            at: .root(index: 0),
            utf16Offset: 5
        )

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["Hello", " world"])
        XCTAssertEqual(result.document.blocks.map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(result.focusPath, .root(index: 1))
    }

    func testSplitParagraphAtStartCreatesEmptyBlockBeforeOriginalText() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("This is a test")])
        ])

        let result = try BlockOperations.splitTextBlock(
            in: document,
            at: .root(index: 0),
            utf16Offset: 0
        )

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["", "This is a test"])
        XCTAssertEqual(result.document.blocks.map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(result.focusPath, .root(index: 1))
        XCTAssertEqual(result.caretUTF16Offset, 0)
    }

    func testEditorImmediateResizeAllowsEmptySplitBlockToReleaseStaleHeight() {
        let shouldResize = EditorImmediateResizePolicy.shouldApplyImmediateResize(
            newHeight: 24,
            textViewHeight: 552,
            scrollViewHeight: 552,
            intrinsicHeight: 552,
            widthChanged: false,
            plainText: ""
        )

        XCTAssertTrue(shouldResize)
    }

    func testEditorImmediateResizeStillDefersNonEmptyShrinkWithoutWidthChange() {
        let shouldResize = EditorImmediateResizePolicy.shouldApplyImmediateResize(
            newHeight: 550,
            textViewHeight: 552,
            scrollViewHeight: 552,
            intrinsicHeight: 552,
            widthChanged: false,
            plainText: "Still typing"
        )

        XCTAssertFalse(shouldResize)
    }

    func testHeadingSplitContinuesAsParagraph() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [.text("Hello world")])
        ])

        let result = try BlockOperations.splitTextBlock(
            in: document,
            at: .root(index: 0),
            utf16Offset: 5
        )

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["Hello", " world"])
        XCTAssertEqual(result.document.blocks.map(\.kind), [.heading1, .paragraph])
    }

    func testMergeBackwardCombinesTextBlocksAndFocusesMergedBlock() throws {
        let firstID = UUID()
        let document = RichDocument(blocks: [
            RichBlock(id: firstID, kind: .paragraph, inlines: [.text("Hello")]),
            RichBlock(kind: .paragraph, inlines: [.text(" world")])
        ])

        let result = try BlockOperations.mergeBackward(in: document, at: .root(index: 1))

        XCTAssertEqual(result.document.blocks.count, 1)
        XCTAssertEqual(result.document.blocks[0].id, firstID)
        XCTAssertEqual(result.document.blocks[0].plainInlineText, "Hello world")
        XCTAssertEqual(result.focusPath, .root(index: 0))
        // Caret lands at the seam between the two merged texts (Notion behavior).
        XCTAssertEqual(result.caretUTF16Offset, 5)
    }

    func testMoveRootBlockBeforeAnotherRootBlock() throws {
        let document = RichDocument(blocks: [.paragraph("A"), .paragraph("B"), .paragraph("C")])

        let result = try BlockOperations.moveBlock(
            in: document,
            from: .root(index: 2),
            to: BlockDropTarget(parent: nil, index: 0)
        )

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["C", "A", "B"])
        XCTAssertEqual(result.focusPath, .root(index: 0))
    }

    func testReturnOnEmptyChecklistExitsToParagraph() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .checklist, inlines: [.text("")], checked: false)
        ])

        let result = try BlockOperations.exitEmptyListBlock(in: document, at: .root(index: 0))

        XCTAssertEqual(result.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(result.document.blocks[0].checked, nil)
        XCTAssertEqual(result.focusPath, .root(index: 0))
    }

    func testBackspaceAtStartOfEmptyParagraphRemovesBlock() throws {
        let document = RichDocument(blocks: [.paragraph("A"), .paragraph("")])

        let result = try BlockOperations.deleteEmptyBlockBackward(in: document, at: .root(index: 1))

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["A"])
        XCTAssertEqual(result.focusPath, .root(index: 0))
    }

    func testApplyBlockCommandTransformRemovesSlashTriggerAndPreservesBlockIdentity() throws {
        let id = UUID()
        let document = RichDocument(blocks: [
            RichBlock(id: id, kind: .paragraph, inlines: [.text("/Launch plan")])
        ])

        let result = try BlockOperations.apply(
            .transform(.heading1),
            in: document,
            at: .root(index: 0),
            livePlainText: "/Launch plan"
        )

        XCTAssertEqual(result.document.blocks[0].id, id)
        XCTAssertEqual(result.document.blocks[0].kind, .heading1)
        XCTAssertEqual(result.document.blocks[0].plainInlineText, "Launch plan")
        XCTAssertEqual(result.focusBlockID, id)
        XCTAssertEqual(result.intent, .preserveCaret)
    }

    func testAbandonedSlashTriggerClearsEmptyTriggerBlock() throws {
        let id = UUID()
        let document = RichDocument(blocks: [
            RichBlock(id: id, kind: .paragraph, inlines: [.text("/")])
        ])

        let result = try BlockOperations.clearAbandonedSlashTrigger(
            in: document,
            at: .root(index: 0)
        )

        XCTAssertEqual(result.document.blocks[0].id, id)
        XCTAssertEqual(result.document.blocks[0].plainInlineText, "")
        XCTAssertEqual(result.focusPath, .root(index: 0))
        XCTAssertEqual(result.caretUTF16Offset, 0)
    }

    func testAbandonedSlashTriggerKeepsSlashInsideRealText() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Open / menu")])
        ])

        let result = try BlockOperations.clearAbandonedSlashTrigger(
            in: document,
            at: .root(index: 0)
        )

        XCTAssertEqual(result.document, document)
        XCTAssertEqual(result.focusPath, .root(index: 0))
        XCTAssertNil(result.caretUTF16Offset)
    }

    func testApplyReplaceOrInsertDividerReplacesEmptyTriggerAndCreatesEditableParagraphAfter() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("/")])
        ])

        let result = try BlockOperations.apply(
            .replaceOrInsert(.divider),
            in: document,
            at: .root(index: 0),
            livePlainText: "/"
        )

        XCTAssertEqual(result.document.blocks.map(\.kind), [.divider, .paragraph])
        XCTAssertEqual(result.focusPath, .root(index: 1))
        XCTAssertEqual(result.caretUTF16Offset, 0)
    }

    func testApplyReplaceOrInsertDividerAfterTypedTextRemovesSlashTriggerBeforeInsertion() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Intro /")])
        ])

        let result = try BlockOperations.apply(
            .replaceOrInsert(.divider),
            in: document,
            at: .root(index: 0),
            livePlainText: "Intro /"
        )

        XCTAssertEqual(result.document.blocks.map(\.kind), [.paragraph, .divider, .paragraph])
        XCTAssertEqual(result.document.blocks[0].plainInlineText, "Intro ")
        XCTAssertEqual(result.focusPath, .root(index: 2))
        XCTAssertEqual(result.caretUTF16Offset, 0)
    }

    func testApplyReplaceOrInsertContentPreservesTypedTextAsStructuredBlockBody() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("/Draft idea")])
        ])

        let result = try BlockOperations.apply(
            .replaceOrInsert(.content),
            in: document,
            at: .root(index: 0),
            livePlainText: "/Draft idea"
        )

        XCTAssertEqual(result.document.blocks.map(\.kind), [.content])
        XCTAssertEqual(result.document.blocks[0].plainInlineText, "Draft idea")
        XCTAssertEqual(result.intent, .preserveCaret)
    }
}
