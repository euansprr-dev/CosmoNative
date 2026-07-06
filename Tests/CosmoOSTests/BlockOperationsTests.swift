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

    // MARK: - Slash apply with trigger already removed (type-through commit)

    func testApplyTransformWithTriggerAlreadyRemovedKeepsLiteralSlashesInContent() throws {
        let id = UUID()
        let document = RichDocument(blocks: [
            RichBlock(id: id, kind: .paragraph, inlines: [.text("a/b ")])
        ])

        let result = try BlockOperations.apply(
            .transform(.heading1),
            in: document,
            at: .root(index: 0),
            livePlainText: "a/b ",
            triggerAlreadyRemoved: true
        )

        XCTAssertEqual(result.document.blocks[0].id, id)
        XCTAssertEqual(result.document.blocks[0].kind, .heading1)
        XCTAssertEqual(result.document.blocks[0].plainInlineText, "a/b ")
    }

    func testApplyReplaceOrInsertWithTriggerAlreadyRemovedTreatsEmptyLiveTextAsEmptyBlock() throws {
        // The block still holds "/" in the (lagging) document, but the text
        // view already consumed the trigger — live text is authoritative.
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("/")])
        ])

        let result = try BlockOperations.apply(
            .replaceOrInsert(.divider),
            in: document,
            at: .root(index: 0),
            livePlainText: "",
            triggerAlreadyRemoved: true
        )

        XCTAssertEqual(result.document.blocks.map(\.kind), [.divider, .paragraph])
        XCTAssertEqual(result.document.blocks[1].plainInlineText, "")
    }

    // MARK: - pasteBlocks

    func testPasteBlocksSplicesMultiLineTextAtCaretWithNotionMergeSemantics() throws {
        let id = UUID()
        let document = RichDocument(blocks: [
            RichBlock(id: id, kind: .paragraph, inlines: [.text("helloworld")])
        ])

        let result = try BlockOperations.pasteBlocks(
            in: document,
            at: .root(index: 0),
            utf16Offset: 5,
            pastedText: "A\nB\nC"
        )

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["helloA", "B", "Cworld"])
        XCTAssertEqual(result.document.blocks[0].id, id, "head keeps the row's identity")
        XCTAssertEqual(result.focusPath, .root(index: 2))
        // Caret at the end of the pasted content — before "world".
        let focused = result.document.blocks[2]
        XCTAssertEqual(result.caretOffsetFromEnd(for: focused), "world".utf16.count)
    }

    func testPasteBlocksIntoEmptyParagraphAdoptsFirstPastedKind() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("")])
        ])

        let result = try BlockOperations.pasteBlocks(
            in: document,
            at: .root(index: 0),
            utf16Offset: 0,
            pastedText: "# Title\nBody"
        )

        XCTAssertEqual(result.document.blocks.map(\.kind), [.heading1, .paragraph])
        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["Title", "Body"])
    }

    func testPasteBlocksParsesMarkdownFlavors() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("")])
        ])

        let result = try BlockOperations.pasteBlocks(
            in: document,
            at: .root(index: 0),
            utf16Offset: 0,
            pastedText: "- a\n- [ ] b\n- [x] c\n> d\n---\n1. e"
        )

        XCTAssertEqual(
            result.document.blocks.map(\.kind),
            [.bulletList, .checklist, .checklist, .quote, .divider, .numberedList]
        )
        XCTAssertEqual(result.document.blocks[1].checked, false)
        XCTAssertEqual(result.document.blocks[2].checked, true)
        XCTAssertEqual(result.document.blocks[5].plainInlineText, "e")
    }

    func testPasteBlocksSingleDividerSplitsTextAroundIt() throws {
        let id = UUID()
        let document = RichDocument(blocks: [
            RichBlock(id: id, kind: .paragraph, inlines: [.text("ab")])
        ])

        let result = try BlockOperations.pasteBlocks(
            in: document,
            at: .root(index: 0),
            utf16Offset: 1,
            pastedText: "---"
        )

        XCTAssertEqual(result.document.blocks.map(\.kind), [.paragraph, .divider, .paragraph])
        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["a", "", "b"])
        XCTAssertEqual(result.document.blocks[0].id, id)
        XCTAssertNotEqual(result.document.blocks[2].id, id, "split-off tail needs a fresh identity")
        XCTAssertEqual(result.focusPath, .root(index: 2))
    }

    func testPasteBlocksTrailingNewlineDoesNotCreateEmptyBlock() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("")])
        ])

        let result = try BlockOperations.pasteBlocks(
            in: document,
            at: .root(index: 0),
            utf16Offset: 0,
            pastedText: "A\nB\n"
        )

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["A", "B"])
    }

    func testPasteBlocksPreservesInteriorBlankLinesAsEmptyParagraphs() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("")])
        ])

        let result = try BlockOperations.pasteBlocks(
            in: document,
            at: .root(index: 0),
            utf16Offset: 0,
            pastedText: "A\n\nB"
        )

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["A", "", "B"])
    }

    // MARK: - Markdown aliases (live conversion)

    func testMarkdownAliasMatchesPrefixesOnlyWithCaretRightAfterThem() {
        XCTAssertEqual(MarkdownBlockAlias.match(text: "# ", cursorLocation: 2)?.kind, .heading1)
        XCTAssertEqual(MarkdownBlockAlias.match(text: "## ", cursorLocation: 3)?.kind, .heading2)
        XCTAssertEqual(MarkdownBlockAlias.match(text: "- ", cursorLocation: 2)?.kind, .bulletList)
        XCTAssertEqual(MarkdownBlockAlias.match(text: "> ", cursorLocation: 2)?.kind, .quote)
        XCTAssertEqual(MarkdownBlockAlias.match(text: "[] ", cursorLocation: 3)?.kind, .checklist)
        XCTAssertEqual(MarkdownBlockAlias.match(text: "- [x] ", cursorLocation: 6)?.checked, true)
        XCTAssertEqual(MarkdownBlockAlias.match(text: "12. ", cursorLocation: 4)?.kind, .numberedList)
        XCTAssertEqual(MarkdownBlockAlias.match(text: "---", cursorLocation: 3)?.kind, .divider)

        // Caret elsewhere, or prefix not at block start — no conversion.
        XCTAssertNil(MarkdownBlockAlias.match(text: "# heading", cursorLocation: 9))
        XCTAssertNil(MarkdownBlockAlias.match(text: "a- ", cursorLocation: 3))
        XCTAssertNil(MarkdownBlockAlias.match(text: "-- ", cursorLocation: 3))
        XCTAssertNil(MarkdownBlockAlias.match(text: "----", cursorLocation: 4))
    }

    // MARK: - Markdown copy flavor

    func testMarkdownCopyRendersKindsAndNumbersConsecutiveOrderedItems() {
        let blocks: [RichBlock] = [
            RichBlock(kind: .heading2, inlines: [.text("Title")]),
            RichBlock(kind: .bulletList, inlines: [.text("a")]),
            RichBlock(kind: .numberedList, inlines: [.text("one")]),
            RichBlock(kind: .numberedList, inlines: [.text("two")]),
            RichBlock(kind: .checklist, inlines: [.text("done")], checked: true),
            RichBlock(kind: .divider),
            RichBlock(kind: .paragraph, inlines: [.text("plain")])
        ]
        let document = RichDocument(blocks: blocks)

        let markdown = BlockOperations.markdown(
            ofBlocksWithIDs: Set(blocks.map(\.id)),
            in: document
        )

        XCTAssertEqual(markdown, "## Title\n- a\n1. one\n2. two\n- [x] done\n---\nplain")
    }

    // MARK: - Hard-newline containment caret mapping

    func testCaretLocationMapsOffsetFromEndAcrossLines() {
        let lines = ["ab", "cd", "ef"]
        let parsed = lines.map { RichBlock.paragraph($0) }

        let end = BlockTextEditorRow.caretLocation(lines: lines, parsed: parsed, offsetFromEnd: 0)
        XCTAssertEqual(end.blockOffset, 2)
        XCTAssertEqual(end.caretOffsetFromEnd, 0)

        let midSecondLine = BlockTextEditorRow.caretLocation(lines: lines, parsed: parsed, offsetFromEnd: 4)
        XCTAssertEqual(midSecondLine.blockOffset, 1)
        XCTAssertEqual(midSecondLine.caretOffsetFromEnd, 1)

        let firstLine = BlockTextEditorRow.caretLocation(lines: lines, parsed: parsed, offsetFromEnd: 8)
        XCTAssertEqual(firstLine.blockOffset, 0)
        XCTAssertEqual(firstLine.caretOffsetFromEnd, 2)
    }

    // MARK: - Callout / Toggle / Code blocks

    func testTransformToCalloutSeedsDefaultStyleAndBackStripsIt() throws {
        let document = RichDocument(blocks: [RichBlock.paragraph("Watch this")])

        let toCallout = try BlockOperations.transformBlock(in: document, at: .root(index: 0), to: .callout)
        XCTAssertEqual(toCallout.document.blocks[0].kind, .callout)
        XCTAssertEqual(toCallout.document.blocks[0].callout, .default)

        let backToText = try BlockOperations.transformBlock(in: toCallout.document, at: .root(index: 0), to: .paragraph)
        XCTAssertNil(backToText.document.blocks[0].callout)
    }

    func testTransformToggleAwayHoistsChildrenAsSiblings() throws {
        let child = RichBlock.paragraph("inside")
        let toggle = RichBlock(kind: .toggle, inlines: [.text("Header")], children: [child])
        let document = RichDocument(blocks: [toggle, RichBlock.paragraph("after")])

        let result = try BlockOperations.transformBlock(in: document, at: .root(index: 0), to: .heading2)

        XCTAssertEqual(result.document.blocks.count, 3)
        XCTAssertEqual(result.document.blocks[0].kind, .heading2)
        XCTAssertTrue(result.document.blocks[0].children.isEmpty)
        XCTAssertEqual(result.document.blocks[1].id, child.id)
        XCTAssertEqual(result.document.blocks[2].plainInlineText, "after")
    }

    func testSplitToggleHeaderDivesIntoFirstChild() throws {
        let toggle = RichBlock(kind: .toggle, inlines: [.text("Plan")], toggleCollapsed: true)
        let document = RichDocument(blocks: [toggle])

        let result = try BlockOperations.splitTextBlock(in: document, at: .root(index: 0), utf16Offset: 4)

        let updated = result.document.blocks[0]
        XCTAssertEqual(updated.kind, .toggle)
        XCTAssertEqual(updated.toggleCollapsed, false)
        XCTAssertEqual(updated.children.count, 1)
        XCTAssertEqual(updated.children[0].kind, .paragraph)
        XCTAssertEqual(result.focusPath?.indices, [0, 0])
    }

    func testMergeBackwardAfterExpandedToggleLandsInLastChildAndKeepsChildren() throws {
        let child = RichBlock.paragraph("inside")
        let toggle = RichBlock(kind: .toggle, inlines: [.text("Header")], children: [child])
        let tail = RichBlock.paragraph("tail")
        let document = RichDocument(blocks: [toggle, tail])

        let result = try BlockOperations.mergeBackward(in: document, at: .root(index: 1))

        XCTAssertEqual(result.document.blocks.count, 1)
        XCTAssertEqual(result.document.blocks[0].children[0].plainInlineText, "insidetail")
        XCTAssertEqual(result.focusPath?.indices, [0, 0])
        XCTAssertEqual(result.caretUTF16Offset, "inside".utf16.count)
    }

    func testDeleteEmptyToggleHoistsChildren() throws {
        let child = RichBlock.paragraph("survivor")
        let toggle = RichBlock(kind: .toggle, inlines: [.text("")], children: [child])
        let document = RichDocument(blocks: [RichBlock.paragraph("first"), toggle])

        let result = try BlockOperations.deleteEmptyBlockBackward(in: document, at: .root(index: 1))

        XCTAssertEqual(result.document.blocks.count, 2)
        XCTAssertEqual(result.document.blocks[1].id, child.id)
    }

    func testExitCodeBlockTrimsTrailingEmptyLineAndInsertsParagraph() throws {
        let code = RichBlock(kind: .code, inlines: [.text("let a = 1\u{2028}")])
        let document = RichDocument(blocks: [code])

        let result = try BlockOperations.exitCodeBlock(in: document, at: .root(index: 0))

        XCTAssertEqual(result.document.blocks.count, 2)
        XCTAssertEqual(result.document.blocks[0].plainInlineText, "let a = 1")
        XCTAssertEqual(result.document.blocks[1].kind, .paragraph)
        XCTAssertEqual(result.focusPath, .root(index: 1))
    }

    func testExitEmptyCodeBlockConvertsToParagraph() throws {
        let code = RichBlock(kind: .code, inlines: [.text("")])
        let document = RichDocument(blocks: [code])

        let result = try BlockOperations.exitCodeBlock(in: document, at: .root(index: 0))

        XCTAssertEqual(result.document.blocks.count, 1)
        XCTAssertEqual(result.document.blocks[0].kind, .paragraph)
    }

    func testPasteCollapsesFencedCodeIntoOneBlockWithSoftBreaks() {
        let parsed = BlockOperations.parsedPasteBlocks(from: "before\n```\nlet a = 1\nprint(a)\n```\nafter")

        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].plainInlineText, "before")
        XCTAssertEqual(parsed[1].kind, .code)
        XCTAssertEqual(parsed[1].plainInlineText, "let a = 1\u{2028}print(a)")
        XCTAssertEqual(parsed[2].plainInlineText, "after")
    }

    func testMarkdownAliasesForCalloutAndCode() {
        XCTAssertEqual(MarkdownBlockAlias.match(text: "!! ", cursorLocation: 3)?.kind, .callout)
        XCTAssertEqual(MarkdownBlockAlias.match(text: "```", cursorLocation: 3)?.kind, .code)
        XCTAssertNil(MarkdownBlockAlias.match(text: "x!! ", cursorLocation: 4))
    }

    // MARK: - Lenient kind decoding

    func testUnknownBlockKindDecodesAsParagraphAndRoundTripsRawKind() throws {
        let json = """
        {"blocks":[{"id":"\(UUID().uuidString)","kind":"hologram","inlines":[{"id":"\(UUID().uuidString)","kind":"text","text":"future block","marks":[]}]}]}
        """
        let decoded = try JSONDecoder().decode(RichDocument.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.blocks.count, 1)
        XCTAssertEqual(decoded.blocks[0].kind, .paragraph)
        XCTAssertEqual(decoded.blocks[0].rawKind, "hologram")
        XCTAssertEqual(decoded.blocks[0].plainInlineText, "future block")

        let reencoded = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        let blocks = roundTripped?["blocks"] as? [[String: Any]]
        XCTAssertEqual(blocks?.first?["kind"] as? String, "hologram")
    }

    func testCalloutAndToggleSurviveCodableRoundTrip() throws {
        let callout = RichBlock(kind: .callout, inlines: [.text("hi")], callout: RichCalloutStyle(icon: "flame", toneID: "clay"))
        let toggle = RichBlock(kind: .toggle, inlines: [.text("head")], children: [.paragraph("body")], toggleCollapsed: true)
        let document = RichDocument(blocks: [callout, toggle])

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(RichDocument.self, from: data)

        XCTAssertEqual(decoded.blocks[0].callout?.icon, "flame")
        XCTAssertEqual(decoded.blocks[0].callout?.toneID, "clay")
        XCTAssertEqual(decoded.blocks[1].toggleCollapsed, true)
        XCTAssertEqual(decoded.blocks[1].children.count, 1)
    }
}
