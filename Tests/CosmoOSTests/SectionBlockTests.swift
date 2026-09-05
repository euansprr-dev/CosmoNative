import XCTest
@testable import CosmoOS

/// The Section block on macOS: a titled, tinted, collapsible container.
/// Pins the structural rules (children never strand, the title row carries
/// the box through every text re-emission), the slash/handle-menu surface,
/// the "/3x4" table sizing, and the one-container-grammar law.
final class SectionBlockTests: XCTestCase {

    // MARK: - Transform hoisting

    func testTransformSectionAwayHoistsChildrenAsSiblings() throws {
        let child = RichBlock.paragraph("inside")
        let section = RichBlock.section(title: "Intro", children: [child])
        let document = RichDocument(blocks: [section, RichBlock.paragraph("after")])

        let result = try BlockOperations.transformBlock(in: document, at: .root(index: 0), to: .heading2)

        XCTAssertEqual(result.document.blocks.count, 3)
        XCTAssertEqual(result.document.blocks[0].kind, .heading2)
        XCTAssertNil(result.document.blocks[0].section)
        XCTAssertTrue(result.document.blocks[0].children.isEmpty)
        XCTAssertEqual(result.document.blocks[1].id, child.id)
        XCTAssertEqual(result.document.blocks[2].plainInlineText, "after")
    }

    func testTransformParagraphToSectionMakesTextTheTitleWithDefaultStyle() throws {
        let document = RichDocument(blocks: [RichBlock.paragraph("Change begins with clarity")])

        let result = try BlockOperations.transformBlock(in: document, at: .root(index: 0), to: .section)

        let section = result.document.blocks[0]
        XCTAssertEqual(section.kind, .section)
        XCTAssertEqual(section.plainInlineText, "Change begins with clarity")
        XCTAssertEqual(section.section, .default)
        XCTAssertTrue(section.children.isEmpty)
    }

    func testToggleAndSectionSwapKeepsTheBody() throws {
        let child = RichBlock.paragraph("body")
        let toggle = RichBlock(kind: .toggle, inlines: [.text("Head")], children: [child])
        let document = RichDocument(blocks: [toggle])

        let toSection = try BlockOperations.transformBlock(in: document, at: .root(index: 0), to: .section)
        XCTAssertEqual(toSection.document.blocks.count, 1)
        XCTAssertEqual(toSection.document.blocks[0].children.map(\.id), [child.id])
        XCTAssertNil(toSection.document.blocks[0].toggleCollapsed)

        let backToToggle = try BlockOperations.transformBlock(in: toSection.document, at: .root(index: 0), to: .toggle)
        XCTAssertEqual(backToToggle.document.blocks.count, 1)
        XCTAssertEqual(backToToggle.document.blocks[0].children.map(\.id), [child.id])
        XCTAssertNil(backToToggle.document.blocks[0].section)
    }

    func testMultiSelectTransformOfSectionAwayHoistsChildren() throws {
        let child = RichBlock.paragraph("inside")
        let section = RichBlock.section(title: "Intro", children: [child])
        let plain = RichBlock.paragraph("plain")
        let document = RichDocument(blocks: [section, plain])

        let result = BlockOperations.transformBlocks(withIDs: [section.id, plain.id], in: document, to: .bulletList)

        let blocks = try XCTUnwrap(result?.document.blocks)
        XCTAssertEqual(blocks.map(\.kind), [.bulletList, .paragraph, .bulletList])
        XCTAssertEqual(blocks[1].id, child.id)
        XCTAssertNil(blocks[0].section)
    }

    // MARK: - Wrap / ungroup

    func testWrapInSectionMakesFirstBlockTheTitleAndTheRestChildren() throws {
        let first = RichBlock(kind: .heading2, inlines: [.text("Section 1")])
        let second = RichBlock.paragraph("one")
        let third = RichBlock.paragraph("two")
        let untouched = RichBlock.paragraph("after")
        let document = RichDocument(blocks: [first, second, third, untouched])

        let result = BlockOperations.wrapInSection(blockIDs: [first.id, second.id, third.id], in: document)

        let blocks = try XCTUnwrap(result?.document.blocks)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .section)
        XCTAssertEqual(blocks[0].id, first.id)
        XCTAssertEqual(blocks[0].plainInlineText, "Section 1")
        XCTAssertNil(blocks[0].heading)
        XCTAssertEqual(blocks[0].children.map(\.id), [second.id, third.id])
        XCTAssertEqual(blocks[1].id, untouched.id)
    }

    func testWrapInSectionWithNonTextFirstBlockBuildsAnUntitledSection() throws {
        let divider = RichBlock(kind: .divider)
        let paragraph = RichBlock.paragraph("text")
        let document = RichDocument(blocks: [divider, paragraph])

        let result = BlockOperations.wrapInSection(blockIDs: [divider.id, paragraph.id], in: document)

        let blocks = try XCTUnwrap(result?.document.blocks)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .section)
        XCTAssertTrue(blocks[0].plainInlineText.isEmpty)
        XCTAssertEqual(blocks[0].children.map(\.id), [divider.id, paragraph.id])
    }

    func testUngroupSectionHoistsChildrenAndKeepsTitleAsParagraph() throws {
        let child = RichBlock.paragraph("inside")
        let section = RichBlock.section(title: "Intro", children: [child])
        let document = RichDocument(blocks: [section, RichBlock.paragraph("after")])

        let result = try BlockOperations.ungroupSection(in: document, at: .root(index: 0))

        let blocks = result.document.blocks
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .paragraph, .paragraph])
        XCTAssertEqual(blocks[0].id, section.id)
        XCTAssertEqual(blocks[0].plainInlineText, "Intro")
        XCTAssertNil(blocks[0].section)
        XCTAssertEqual(blocks[1].id, child.id)
        XCTAssertEqual(blocks[2].plainInlineText, "after")
    }

    func testUngroupEmptySectionLeavesOneEmptyParagraph() throws {
        let section = RichBlock.section(title: "")
        let document = RichDocument(blocks: [section])

        let result = try BlockOperations.ungroupSection(in: document, at: .root(index: 0))

        XCTAssertEqual(result.document.blocks.count, 1)
        XCTAssertEqual(result.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(result.document.blocks[0].id, section.id)
    }

    func testUngroupSectionsActsOnEverySelectedSectionOnly() throws {
        let a = RichBlock.section(title: "", children: [RichBlock.paragraph("a1")])
        let plain = RichBlock.paragraph("plain")
        let b = RichBlock.section(title: "B", children: [RichBlock.paragraph("b1")])
        let document = RichDocument(blocks: [a, plain, b])

        XCTAssertNil(BlockOperations.ungroupSections(withIDs: [plain.id], in: document))
        let result = BlockOperations.ungroupSections(withIDs: [a.id, plain.id, b.id], in: document)

        let texts = try XCTUnwrap(result?.document.blocks.map(\.plainInlineText))
        XCTAssertEqual(texts, ["a1", "plain", "B", "b1"])
    }

    // MARK: - Row-only field carriage (the title IS a block row)

    func testSectionTitleRowHandsTheEditorAParagraphProxy() {
        let section = RichBlock.section(title: "Intro", children: [RichBlock.paragraph("child")])

        let proxy = BlockRowSyncPolicy.editorRowBlock(for: section)

        XCTAssertEqual(proxy.kind, .paragraph)
        XCTAssertEqual(proxy.id, section.id)
        XCTAssertEqual(proxy.plainInlineText, "Intro")
        XCTAssertTrue(proxy.children.isEmpty)
        XCTAssertNil(proxy.section)
        // Other kinds pass straight through.
        let bullet = RichBlock(kind: .bulletList, inlines: [.text("x")])
        XCTAssertEqual(BlockRowSyncPolicy.editorRowBlock(for: bullet), bullet)
    }

    func testRestoreRowOnlyFieldsCarriesSectionTableAndPassthrough() {
        var existing = RichBlock.section(
            title: "Intro",
            style: RichSectionStyle(toneID: "clay", appearance: .bar, icon: "flame", isCollapsed: true),
            children: [RichBlock.paragraph("child")]
        )
        existing.passthrough = ["futureKey": .string("kept")]
        existing.table = RichTable(rowCount: 2, columnCount: 2)
        let parsed = RichBlock(kind: .paragraph, inlines: [.text("Intro!")])

        let reconciled = BlockRowSyncPolicy.reconciled(parsed: [parsed], existingBlock: existing)

        XCTAssertEqual(reconciled.count, 1)
        XCTAssertEqual(reconciled[0].id, existing.id)
        XCTAssertEqual(reconciled[0].kind, .section)
        XCTAssertEqual(reconciled[0].plainInlineText, "Intro!")
        XCTAssertEqual(reconciled[0].section, existing.section)
        XCTAssertEqual(reconciled[0].table, existing.table)
        XCTAssertEqual(reconciled[0].passthrough, existing.passthrough)
        XCTAssertEqual(reconciled[0].children.map(\.id), existing.children.map(\.id))
    }

    func testTypingInSectionTitleKeepsSectionAndChildrenInTheDocument() throws {
        let child = RichBlock.paragraph("child")
        let section = RichBlock.section(title: "Intr", style: RichSectionStyle(toneID: "plum"), children: [child])
        var document = RichDocument(blocks: [section])
        let path = BlockPath.root(index: 0)

        // The text view re-emits the proxy paragraph with one more character.
        let proxy = BlockRowSyncPolicy.editorRowBlock(for: section)
        let parsed = RichBlock(kind: .paragraph, inlines: [.text(proxy.plainInlineText + "o")])
        let reconciled = BlockRowSyncPolicy.reconciled(parsed: [parsed], existingBlock: document.blocks[0])
        document = try BlockOperations.replaceBlocks(in: document, at: path, with: reconciled).document

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].kind, .section)
        XCTAssertEqual(document.blocks[0].plainInlineText, "Intro")
        XCTAssertEqual(document.blocks[0].section?.toneID, "plum")
        XCTAssertEqual(document.blocks[0].children.map(\.id), [child.id])
    }

    // MARK: - Enter / exit boundaries

    func testReturnInSectionTitleWithRemainderCreatesFirstChild() throws {
        let existingChild = RichBlock.paragraph("existing")
        let section = RichBlock.section(
            title: "Plan ahead",
            style: RichSectionStyle(isCollapsed: true),
            children: [existingChild]
        )
        let document = RichDocument(blocks: [section])

        let result = try BlockOperations.splitTextBlock(in: document, at: .root(index: 0), utf16Offset: 4)

        let updated = result.document.blocks[0]
        XCTAssertEqual(updated.kind, .section)
        XCTAssertEqual(updated.plainInlineText, "Plan")
        XCTAssertEqual(updated.section?.isCollapsed, false)
        XCTAssertEqual(updated.children.count, 2)
        XCTAssertEqual(updated.children[0].plainInlineText, " ahead")
        XCTAssertEqual(updated.children[1].id, existingChild.id)
        XCTAssertEqual(result.focusPath?.indices, [0, 0])
        XCTAssertEqual(result.caretUTF16Offset, 0)
    }

    func testReturnAtEndOfSectionTitleFocusesExistingFirstChild() throws {
        let first = RichBlock.paragraph("first")
        let section = RichBlock.section(title: "Plan", children: [first])
        let document = RichDocument(blocks: [section])

        let result = try BlockOperations.splitTextBlock(in: document, at: .root(index: 0), utf16Offset: 4)

        XCTAssertEqual(result.document.blocks[0].children.map(\.id), [first.id])
        XCTAssertEqual(result.focusPath?.indices, [0, 0])
        XCTAssertEqual(result.focusBlockID, first.id)
    }

    func testReturnInEmptyBodiedSectionCreatesAnEmptyParagraphChild() throws {
        let section = RichBlock.section(title: "Plan")
        let document = RichDocument(blocks: [section])

        let result = try BlockOperations.enterSectionBody(in: document, at: .root(index: 0))

        let updated = result.document.blocks[0]
        XCTAssertEqual(updated.children.count, 1)
        XCTAssertEqual(updated.children[0].kind, .paragraph)
        XCTAssertTrue(updated.children[0].plainInlineText.isEmpty)
        XCTAssertEqual(result.focusPath?.indices, [0, 0])
    }

    func testMergeBackwardAfterExpandedSectionLandsInLastChild() throws {
        let child = RichBlock.paragraph("inside")
        let section = RichBlock.section(title: "Head", children: [child])
        let document = RichDocument(blocks: [section, RichBlock.paragraph("tail")])

        let result = try BlockOperations.mergeBackward(in: document, at: .root(index: 1))

        XCTAssertEqual(result.document.blocks.count, 1)
        XCTAssertEqual(result.document.blocks[0].children[0].plainInlineText, "insidetail")
        XCTAssertEqual(result.focusPath?.indices, [0, 0])
        XCTAssertEqual(result.caretUTF16Offset, "inside".utf16.count)
    }

    func testMergeBackwardAfterCollapsedSectionNeverWritesIntoTheTitle() {
        let section = RichBlock.section(
            title: "Head",
            style: RichSectionStyle(isCollapsed: true),
            children: [RichBlock.paragraph("inside")]
        )
        let document = RichDocument(blocks: [section, RichBlock.paragraph("tail")])

        XCTAssertThrowsError(try BlockOperations.mergeBackward(in: document, at: .root(index: 1)))
    }

    func testDeleteEmptyBlockAfterSectionFocusesTheSection() throws {
        let section = RichBlock.section(title: "Head")
        let document = RichDocument(blocks: [section, RichBlock.paragraph("")])

        let result = try BlockOperations.deleteEmptyBlockBackward(in: document, at: .root(index: 1))

        XCTAssertEqual(result.document.blocks.count, 1)
        XCTAssertEqual(result.focusBlockID, section.id)
    }

    // MARK: - Catalog

    func testBlockCommandCatalogOffersSectionAndTable() throws {
        let commands = BlockCommandCatalog.baseCommands
        let section = try XCTUnwrap(commands.first { $0.action == .transform(.section) })
        XCTAssertEqual(section.title, "Section")
        XCTAssertEqual(section.systemImage, "square.text.square")
        XCTAssertTrue(section.aliases.contains("box"))

        let table = try XCTUnwrap(commands.first { $0.action == .replaceOrInsert(.table) })
        XCTAssertEqual(table.title, "Table")
        XCTAssertEqual(table.systemImage, "tablecells")
        XCTAssertTrue(table.aliases.contains("matrix"))

        XCTAssertEqual(BlockCommandCatalog.action(for: .section), .transform(.section))
        XCTAssertEqual(BlockCommandCatalog.action(for: .table), .replaceOrInsert(.table))
        XCTAssertEqual(BlockCommand.Action.insertTable(rows: 3, columns: 4).undoActionName, "Insert Table")
        XCTAssertEqual(BlockCommand.Action.transform(.section).undoActionName, "Transform to Section")
    }

    func testSlashCatalogOffersSectionAndTableAsBlockEditorOnlyStructure() throws {
        let commands = SlashCommandCatalog.baseCommands
        let table = try XCTUnwrap(commands.first { $0.type == .table })
        XCTAssertEqual(table.section, .structure)
        XCTAssertEqual(table.icon, "tablecells")
        XCTAssertEqual(table.subtitle, "Rows and columns")
        let section = try XCTUnwrap(commands.first { $0.type == .section })
        XCTAssertEqual(section.section, .structure)
        XCTAssertEqual(section.subtitle, "Titled box for a group of blocks")

        XCTAssertTrue(SlashCommandType.table.requiresBlockEditor)
        XCTAssertTrue(SlashCommandType.section.requiresBlockEditor)
        XCTAssertEqual(SlashCommandType.table.stableID, "table")
        XCTAssertEqual(SlashCommandType.section.stableID, "section")
    }

    func testHandleMenuTurnIntoOffersSection() {
        XCTAssertTrue(BlockTransformOption.all.contains { $0.kind == .section })
    }

    // MARK: - "/3x4"

    func testTableSizeQueryParsesRowsByColumns() {
        XCTAssertEqual(SlashTableSizeQuery.parse("3x4")?.rows, 3)
        XCTAssertEqual(SlashTableSizeQuery.parse("3x4")?.columns, 4)
        XCTAssertEqual(SlashTableSizeQuery.parse("2X5")?.columns, 5)
        XCTAssertEqual(SlashTableSizeQuery.parse(" 4×2 ")?.rows, 4)
        XCTAssertNil(SlashTableSizeQuery.parse("0x3"))
        XCTAssertNil(SlashTableSizeQuery.parse("12x3"))
        XCTAssertNil(SlashTableSizeQuery.parse("table"))
        XCTAssertNil(SlashTableSizeQuery.parse(""))
    }

    func testSizedTableQueryMatchesTheTableCommandFirstInBothCatalogs() {
        XCTAssertEqual(BlockCommandCatalog.filteredCommands(query: "3x4").first?.action, .replaceOrInsert(.table))

        let slash = SlashCommandCatalog.filteredCommands(matching: "3x4", commands: SlashCommandCatalog.baseCommands)
        XCTAssertEqual(slash.first?.type, .table)
    }

    func testTableSlashCommandWithSizeQueryInsertsThatGrid() throws {
        var command = try XCTUnwrap(SlashCommandCatalog.baseCommands.first { $0.type == .table })
        command.invocationQuery = "3x4"
        let action = try XCTUnwrap(BlockCommandCatalog.action(for: command))
        XCTAssertEqual(action, .insertTable(rows: 3, columns: 4))

        let document = RichDocument(blocks: [RichBlock.paragraph("")])
        let result = try BlockOperations.apply(
            action,
            in: document,
            at: .root(index: 0),
            livePlainText: "",
            triggerAlreadyRemoved: true
        )

        XCTAssertEqual(result.document.blocks.map(\.kind), [.table, .paragraph])
        XCTAssertEqual(result.document.blocks[0].table?.rowCount, 3)
        XCTAssertEqual(result.document.blocks[0].table?.columnCount, 4)
        XCTAssertEqual(result.document.blocks[0].table?.hasHeaderRow, true)
        XCTAssertEqual(result.focusPath?.indices, [1])
    }

    func testTableSlashCommandWithoutSizeInsertsTheDefaultGrid() throws {
        let command = try XCTUnwrap(SlashCommandCatalog.baseCommands.first { $0.type == .table })
        let action = try XCTUnwrap(BlockCommandCatalog.action(for: command))
        XCTAssertEqual(action, .replaceOrInsert(.table))

        let document = RichDocument(blocks: [RichBlock.paragraph("")])
        let result = try BlockOperations.apply(action, in: document, at: .root(index: 0), livePlainText: "", triggerAlreadyRemoved: true)

        XCTAssertEqual(result.document.blocks[0].table?.rowCount, RichTable.defaultRowCount)
        XCTAssertEqual(result.document.blocks[0].table?.columnCount, RichTable.defaultColumnCount)
    }

    func testSectionSlashCommandMakesTheTypedTextTheTitle() throws {
        let document = RichDocument(blocks: [RichBlock.paragraph("Intro")])

        let result = try BlockOperations.apply(
            .transform(.section),
            in: document,
            at: .root(index: 0),
            livePlainText: "Intro",
            triggerAlreadyRemoved: true
        )

        XCTAssertEqual(result.document.blocks.count, 1)
        XCTAssertEqual(result.document.blocks[0].kind, .section)
        XCTAssertEqual(result.document.blocks[0].plainInlineText, "Intro")
        XCTAssertEqual(result.document.blocks[0].section, .default)
    }

    // MARK: - Copy output

    func testMarkdownAndPlainTextRenderSectionsAndTables() {
        let section = RichBlock.section(
            title: "Intro",
            children: [RichBlock.paragraph("one"), RichBlock(kind: .bulletList, inlines: [.text("two")])]
        )
        let table = RichBlock.table(RichTable(strings: [["h1", "h2"], ["a", "b"]]))
        let document = RichDocument(blocks: [section, table])
        let ids: Set<UUID> = [section.id, table.id]

        let markdown = BlockOperations.markdown(ofBlocksWithIDs: ids, in: document)
        XCTAssertEqual(markdown, "## Intro\none\n- two\n" + table.table!.markdownLines().joined(separator: "\n"))
        XCTAssertTrue(markdown.contains("| h1 | h2 |"))

        let plain = BlockOperations.plainText(ofBlocksWithIDs: ids, in: document)
        XCTAssertTrue(plain.hasPrefix("▣ Intro\n"))
        XCTAssertTrue(plain.contains("| a | b |"))
    }

    // MARK: - Rhythm

    func testRhythmGivesSectionsAndTablesDividerAir() {
        let gap: CGFloat = 6
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .section, following: .paragraph, baseGap: gap), gap + 6)
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .table, following: .paragraph, baseGap: gap), gap + 6)
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .paragraph, following: .section, baseGap: gap), gap + 6)
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .paragraph, following: .table, baseGap: gap), gap + 6)
    }

    // MARK: - Drop into a section body

    func testMoveBlockByIDIntoASectionBodyFromThePage() throws {
        let child = RichBlock.paragraph("child")
        let section = RichBlock.section(title: "Box", children: [child])
        let mover = RichBlock.paragraph("mover")
        let document = RichDocument(blocks: [mover, section])

        let result = try BlockOperations.moveBlock(withID: mover.id, relativeTo: child.id, position: .below, in: document)

        XCTAssertEqual(result.document.blocks.count, 1)
        XCTAssertEqual(result.document.blocks[0].children.map(\.id), [child.id, mover.id])
        XCTAssertEqual(result.focusPath?.indices, [0, 1])
    }

    func testMoveSectionIntoItsOwnBodyIsRefused() {
        let child = RichBlock.paragraph("child")
        let section = RichBlock.section(title: "Box", children: [child])
        let document = RichDocument(blocks: [section])

        XCTAssertThrowsError(try BlockOperations.moveBlock(withID: section.id, relativeTo: child.id, position: .above, in: document))
    }

    // MARK: - One container grammar

    func testElementAndSectionDrawThroughTheSharedContainerChrome() throws {
        let editor = repositoryRoot.appendingPathComponent("Editor/BlockEditor")
        let element = try String(contentsOf: editor.appendingPathComponent("ElementBlockView.swift"), encoding: .utf8)
        let section = try String(contentsOf: editor.appendingPathComponent("SectionBlockView.swift"), encoding: .utf8)

        XCTAssertTrue(element.contains("ContainerBlockSurface("))
        XCTAssertTrue(element.contains("ContainerBlockChrome("))
        XCTAssertTrue(section.contains("ContainerBlockSurface("))
        XCTAssertTrue(section.contains("ContainerBlockChrome("))
        // The Element card's constants moved, not changed.
        XCTAssertEqual(ContainerBlockChrome.cornerRadius, 10)
        XCTAssertEqual(ContainerBlockChrome.washOpacity, 0.55)
        XCTAssertEqual(ContainerBlockChrome.restingHairlineOpacity, 0.65)
        XCTAssertFalse(element.contains("RoundedRectangle(cornerRadius: 10, style: .continuous)"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
