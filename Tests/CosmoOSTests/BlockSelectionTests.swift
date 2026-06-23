import XCTest
@testable import CosmoOS

@MainActor
final class BlockSelectionTests: XCTestCase {
    private func makeDocument() -> RichDocument {
        RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Alpha")]),
            RichBlock(kind: .paragraph, inlines: [.text("Beta")]),
            RichBlock(kind: .heading2, inlines: [.text("Gamma")]),
            RichBlock(kind: .paragraph, inlines: [.text("Delta")])
        ])
    }

    // MARK: - BlockSelectionCoordinator

    func testSelectRangeSelectsEverythingBetweenAnchorAndTarget() {
        let document = makeDocument()
        let coordinator = BlockSelectionCoordinator()

        coordinator.select(document.blocks[0].id)
        coordinator.selectRange(to: document.blocks[2].id, in: document)

        XCTAssertEqual(coordinator.selectedBlockIDs, Set(document.blocks.prefix(3).map(\.id)))
        XCTAssertEqual(coordinator.anchorBlockID, document.blocks[0].id)
        XCTAssertEqual(coordinator.leadBlockID, document.blocks[2].id)
    }

    func testExtendMovesLeadWhileAnchorStays() {
        let document = makeDocument()
        let coordinator = BlockSelectionCoordinator()

        coordinator.select(document.blocks[1].id)
        coordinator.extend(.down, in: document)
        coordinator.extend(.down, in: document)

        XCTAssertEqual(coordinator.anchorBlockID, document.blocks[1].id)
        XCTAssertEqual(coordinator.leadBlockID, document.blocks[3].id)
        XCTAssertEqual(coordinator.selectedBlockIDs, Set(document.blocks[1...3].map(\.id)))

        coordinator.extend(.up, in: document)
        XCTAssertEqual(coordinator.selectedBlockIDs, Set(document.blocks[1...2].map(\.id)))
    }

    func testStepCollapsesSelectionToNeighborOfEdge() {
        let document = makeDocument()
        let coordinator = BlockSelectionCoordinator()

        coordinator.select(document.blocks[1].id)
        coordinator.extend(.down, in: document)
        coordinator.step(.up, in: document)

        XCTAssertEqual(coordinator.selectedBlockIDs, [document.blocks[0].id])
    }

    func testPruneDropsBlocksRemovedFromDocument() {
        var document = makeDocument()
        let coordinator = BlockSelectionCoordinator()
        coordinator.selectAll(in: document)

        document.blocks.removeFirst(2)
        coordinator.prune(against: document)

        XCTAssertEqual(coordinator.selectedBlockIDs, Set(document.blocks.map(\.id)))
    }

    // MARK: - Multi-Block Operations

    func testDeleteBlocksKeepsAnEditableParagraph() throws {
        let document = makeDocument()
        let allIDs = Set(document.blocks.map(\.id))

        let result = try XCTUnwrap(BlockOperations.deleteBlocks(withIDs: allIDs, in: document))

        XCTAssertEqual(result.document.blocks.count, 1)
        XCTAssertEqual(result.document.blocks.first?.kind, .paragraph)
        XCTAssertEqual(result.document.blocks.first?.plainInlineText, "")
    }

    func testDeleteBlocksFocusesBlockBeforeTheRemovedRange() throws {
        let document = makeDocument()
        let ids: Set<UUID> = [document.blocks[1].id, document.blocks[2].id]

        let result = try XCTUnwrap(BlockOperations.deleteBlocks(withIDs: ids, in: document))

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["Alpha", "Delta"])
        XCTAssertEqual(result.focusPath, .root(index: 0))
    }

    func testDuplicateBlocksInsertsFreshCopiesAfterLastSelected() throws {
        let document = makeDocument()
        let ids: Set<UUID> = [document.blocks[0].id, document.blocks[1].id]

        let (result, duplicatedIDs) = try XCTUnwrap(BlockOperations.duplicateBlocks(withIDs: ids, in: document))

        XCTAssertEqual(
            result.document.blocks.map(\.plainInlineText),
            ["Alpha", "Beta", "Alpha", "Beta", "Gamma", "Delta"]
        )
        XCTAssertEqual(duplicatedIDs.count, 2)
        XCTAssertTrue(Set(duplicatedIDs).isDisjoint(with: ids))
    }

    func testTransformBlocksSkipsNonTextBlocks() throws {
        var document = makeDocument()
        document.blocks.insert(RichBlock(kind: .divider), at: 1)
        let ids = Set(document.blocks.map(\.id))

        let result = try XCTUnwrap(BlockOperations.transformBlocks(withIDs: ids, in: document, to: .bulletList))

        XCTAssertEqual(
            result.document.blocks.map(\.kind),
            [.bulletList, .divider, .bulletList, .bulletList, .bulletList]
        )
    }

    func testTransformBlocksToChecklistSeedsCheckedState() throws {
        let document = makeDocument()
        let ids: Set<UUID> = [document.blocks[0].id]

        let result = try XCTUnwrap(BlockOperations.transformBlocks(withIDs: ids, in: document, to: .checklist))

        XCTAssertEqual(result.document.blocks[0].kind, .checklist)
        XCTAssertEqual(result.document.blocks[0].checked, false)
    }

    func testPlainTextOfSelectionJoinsInDocumentOrder() {
        let document = makeDocument()
        let ids: Set<UUID> = [document.blocks[3].id, document.blocks[0].id]

        let text = BlockOperations.plainText(ofBlocksWithIDs: ids, in: document)

        XCTAssertEqual(text, "Alpha\nDelta")
    }

    func testWithRegeneratedIDsCreatesFreshIdentitiesRecursively() {
        var block = RichBlock(kind: .paragraph, inlines: [.text("Parent")])
        block.children = [RichBlock(kind: .paragraph, inlines: [.text("Child")])]

        let copy = block.withRegeneratedIDs()

        XCTAssertNotEqual(copy.id, block.id)
        XCTAssertNotEqual(copy.inlines[0].id, block.inlines[0].id)
        XCTAssertNotEqual(copy.children[0].id, block.children[0].id)
        XCTAssertEqual(copy.plainInlineText, "Parent")
        XCTAssertEqual(copy.children[0].plainInlineText, "Child")
    }

    // MARK: - Structural Edit Semantics

    func testMergeBackwardPlacesCaretAtTheSeam() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Hello ")]),
            RichBlock(kind: .paragraph, inlines: [.text("world")])
        ])

        let result = try BlockOperations.mergeBackward(in: document, at: .root(index: 1))

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["Hello world"])
        XCTAssertEqual(result.caretUTF16Offset, "Hello ".utf16.count)

        let merged = result.document.blocks[0]
        XCTAssertEqual(result.caretOffsetFromEnd(for: merged), "world".utf16.count)
    }

    func testSplitResultPlacesCaretAtStartOfNewBlock() throws {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("HelloWorld")])
        ])

        let result = try BlockOperations.splitTextBlock(in: document, at: .root(index: 0), utf16Offset: 5)

        XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["Hello", "World"])
        let newBlock = result.document.blocks[1]
        XCTAssertEqual(result.caretOffsetFromEnd(for: newBlock), "World".utf16.count)
    }

    func testStrippedRenderPrefixRemovesSerializerPrefixesOnly() {
        XCTAssertEqual(RichBlockKind.bulletList.strippedRenderPrefix(from: "• Hello"), "Hello")
        XCTAssertEqual(RichBlockKind.numberedList.strippedRenderPrefix(from: "12. Hello"), "Hello")
        XCTAssertEqual(RichBlockKind.numberedList.strippedRenderPrefix(from: "1. 2024. Notes"), "2024. Notes")
        XCTAssertEqual(RichBlockKind.checklist.strippedRenderPrefix(from: "☐ Task"), "Task")
        XCTAssertEqual(RichBlockKind.checklist.strippedRenderPrefix(from: "☑ Task"), "Task")
        XCTAssertEqual(RichBlockKind.quote.strippedRenderPrefix(from: "│ Wisdom"), "Wisdom")
        XCTAssertEqual(RichBlockKind.paragraph.strippedRenderPrefix(from: "Plain text"), "Plain text")
        XCTAssertEqual(RichBlockKind.numberedList.strippedRenderPrefix(from: "No prefix here"), "No prefix here")
    }

    // MARK: - NoteDocumentStyle

    func testNoteDocumentStyleRoundTripsThroughMetadata() {
        var style = NoteDocumentStyle()
        style.fontFamily = .serif
        style.textSize = .large
        style.pageWidth = .wide

        let metadata = style.write(intoMetadata: "{\"tags\":[\"alpha\"]}")
        let loaded = NoteDocumentStyle.load(fromMetadata: metadata)

        XCTAssertEqual(loaded, style)
        XCTAssertTrue(metadata?.contains("alpha") == true, "Existing metadata keys must survive a style write")
    }

    func testNoteDocumentStyleFallsBackToDefaultForMissingOrInvalidMetadata() {
        XCTAssertEqual(NoteDocumentStyle.load(fromMetadata: nil), .default)
        XCTAssertEqual(NoteDocumentStyle.load(fromMetadata: "not json"), .default)
        XCTAssertEqual(NoteDocumentStyle.load(fromMetadata: "{}"), .default)
    }

    func testNoteDocumentStyleDecodesLegacyMetadataWithoutLineSpacing() {
        // Styles persisted before the lineSpacing field existed must keep
        // their voice — never reset to defaults because a key is missing.
        let legacyMetadata = """
        {"note_document_style":{"fontFamily":"serif","textSize":"large","pageWidth":"wide"}}
        """

        let loaded = NoteDocumentStyle.load(fromMetadata: legacyMetadata)

        XCTAssertEqual(loaded.fontFamily, .serif)
        XCTAssertEqual(loaded.textSize, .large)
        XCTAssertEqual(loaded.pageWidth, .wide)
        XCTAssertEqual(loaded.lineSpacing, .standard)
    }

    func testNoteDocumentStyleLineSpacingRoundTripsThroughMetadata() {
        var style = NoteDocumentStyle()
        style.fontFamily = .mono
        style.lineSpacing = .airy

        let metadata = style.write(intoMetadata: nil)
        let loaded = NoteDocumentStyle.load(fromMetadata: metadata)

        XCTAssertEqual(loaded, style)
        XCTAssertEqual(loaded.lineSpacing.lineSpacingDelta, 4)
        XCTAssertEqual(loaded.lineSpacing.blockGap, 9)
    }
}
