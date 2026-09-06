import XCTest
@testable import CosmoOS

/// Nested lists (Tab / ⇧Tab). The level is a flat `indent` on list blocks;
/// every render path reads the one `RichListIndent` grammar.
final class ListIndentTests: XCTestCase {

    // MARK: - Grammar

    func testGlyphLadderCyclesPerLevel() {
        XCTAssertEqual(RichListIndent.bulletPrefix(level: 0), "• ")
        XCTAssertEqual(RichListIndent.bulletPrefix(level: 1), "◦ ")
        XCTAssertEqual(RichListIndent.bulletPrefix(level: 2), "▪ ")
        XCTAssertEqual(RichListIndent.bulletPrefix(level: 3), "• ")

        XCTAssertEqual(RichListIndent.numberedPrefix(position: 3, level: 0), "3. ")
        XCTAssertEqual(RichListIndent.numberedPrefix(position: 2, level: 1), "b. ")
        XCTAssertEqual(RichListIndent.numberedPrefix(position: 4, level: 2), "iv. ")
        XCTAssertEqual(RichListIndent.numberedPrefix(position: 27, level: 1), "aa. ")
        XCTAssertEqual(RichListIndent.numberedPrefix(position: 1, level: 3), "1. ")
    }

    func testNumberedLabelsParseBackAtTheirLevelOnly() {
        XCTAssertEqual(RichListIndent.numberedPosition(in: "12. twelve", level: 0), 12)
        XCTAssertEqual(RichListIndent.numberedPosition(in: "b. bee", level: 1), 2)
        XCTAssertEqual(RichListIndent.numberedPosition(in: "iv. four", level: 2), 4)
        // Letters never count as numbering at the decimal level — prose
        // starting "e. " stays prose.
        XCTAssertNil(RichListIndent.numberedPosition(in: "e. g. things", level: 0))
        XCTAssertEqual(RichListIndent.numberedPrefixLength(in: "e. g.", allowsAlpha: false), 0)
        XCTAssertEqual(RichListIndent.numberedPrefixLength(in: "e. g.", allowsAlpha: true), 3)
        XCTAssertEqual(RichListIndent.numberedPrefixLength(in: "12. x", allowsAlpha: false), 4)
        XCTAssertEqual(RichListIndent.numberedPrefixLength(in: "1.x", allowsAlpha: false), 0)
        // Word-shaped labels are content, not numbering, even on a row that
        // knows it is numbered (it cannot know its level from text alone).
        XCTAssertEqual(RichListIndent.numberedPrefixLength(in: "mix. x", allowsAlpha: true), 0)
        XCTAssertEqual(RichListIndent.numberedPrefixLength(in: "beta. gamma", allowsAlpha: true), 0)
        XCTAssertEqual(RichListIndent.numberedPrefixLength(in: "be. x", allowsAlpha: true), 4)
        XCTAssertEqual(RichListIndent.numberedPrefixLength(in: "xxviii. x", allowsAlpha: true), 8)
        XCTAssertEqual(RichBlockKind.numberedList.renderedPrefixLength(in: "beta. gamma"), 0)
        XCTAssertNil(RichListIndent.romanValue("mix"))
        XCTAssertEqual(RichListIndent.romanValue("xiv"), 14)
    }

    /// GUARD-TWIN: the serializer's glyph and the row's measured prefix
    /// length must agree at every level, or Backspace/Return boundary
    /// detection drifts off the caret home.
    func testRenderedPrefixLengthMatchesSerializerAtEveryLevel() {
        for level in 0...RichListIndent.maxLevel {
            let bullet = RichDocument(blocks: [RichBlock(kind: .bulletList, inlines: [.text("x")], indent: level)])
            let bulletString = RichDocumentSerializer.attributedString(from: bullet, insetsListIndent: false).string
            XCTAssertEqual(
                RichBlockKind.bulletList.renderedPrefixLength(in: bulletString),
                RichListIndent.bulletPrefix(level: level).utf16.count,
                "level \(level): \(bulletString)"
            )

            let numbered = RichDocument(blocks: [RichBlock(kind: .numberedList, inlines: [.text("x")], indent: level)])
            let numberedString = RichDocumentSerializer.attributedString(from: numbered, numberedListSeed: 3, insetsListIndent: false).string
            XCTAssertEqual(
                RichBlockKind.numberedList.renderedPrefixLength(in: numberedString),
                RichListIndent.numberedPrefix(position: 4, level: level).utf16.count,
                "level \(level): \(numberedString)"
            )
            XCTAssertEqual(RichBlockKind.numberedList.strippedRenderPrefix(from: numberedString), "x")
        }
    }

    // MARK: - Numbering runs

    func testNestedItemsNeverBreakTheRunAbove() {
        let blocks: [RichBlock] = [
            RichBlock(kind: .numberedList, inlines: [.text("one")]),
            RichBlock(kind: .numberedList, inlines: [.text("a")], indent: 1),
            RichBlock(kind: .bulletList, inlines: [.text("deep bullet")], indent: 2),
            RichBlock(kind: .numberedList, inlines: [.text("b")], indent: 1),
            RichBlock(kind: .numberedList, inlines: [.text("two")]),
            RichBlock(kind: .numberedList, inlines: [.text("a again")], indent: 1),
            .paragraph("break"),
            RichBlock(kind: .numberedList, inlines: [.text("restart")])
        ]
        XCTAssertEqual(RichListIndent.numberedOrdinals(for: blocks), [0, 0, 0, 1, 1, 0, 0, 0])

        let rendered = RichDocumentSerializer.attributedString(from: RichDocument(blocks: blocks)).string
        let lines = rendered.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "1. one")
        XCTAssertEqual(lines[1], "a. a")
        XCTAssertEqual(lines[2], "▪ deep bullet")
        XCTAssertEqual(lines[3], "b. b")
        XCTAssertEqual(lines[4], "2. two")
        XCTAssertEqual(lines[5], "a. a again")
        XCTAssertEqual(lines[7], "1. restart")
    }

    func testSeedContinuesTheFirstBlocksRun() {
        let doc = RichDocument(blocks: [RichBlock(kind: .numberedList, inlines: [.text("x")], indent: 1)])
        XCTAssertTrue(RichDocumentSerializer.attributedString(from: doc, numberedListSeed: 2).string.hasPrefix("c. "))
    }

    // MARK: - Round trips

    func testIndentRoundTripsThroughCodableAndDropsOffNonLists() throws {
        let nested = RichBlock(kind: .bulletList, inlines: [.text("child")], indent: 2)
        let data = try JSONEncoder().encode(RichDocument(blocks: [nested]))
        let decoded = try JSONDecoder().decode(RichDocument.self, from: data)
        XCTAssertEqual(decoded.blocks[0].indent, 2)

        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"indent\":2"))

        // A level on a paragraph is meaningless — dropped on init and decode.
        XCTAssertNil(RichBlock(kind: .paragraph, inlines: [.text("p")], indent: 2).indent)
        let stray = #"{"blocks":[{"kind":"paragraph","inlines":[],"indent":3}]}"#
        let strayDoc = try JSONDecoder().decode(RichDocument.self, from: Data(stray.utf8))
        XCTAssertNil(strayDoc.blocks[0].indent)
        XCTAssertEqual(strayDoc.blocks[0].listIndentLevel, 0)

        // Out-of-range levels clamp instead of throwing.
        let deep = #"{"blocks":[{"kind":"bulletList","inlines":[],"indent":40}]}"#
        let deepDoc = try JSONDecoder().decode(RichDocument.self, from: Data(deep.utf8))
        XCTAssertEqual(deepDoc.blocks[0].indent, RichListIndent.maxLevel)
    }

    func testIndentRoundTripsThroughTheContinuousEditorStorage() {
        let doc = RichDocument(blocks: [
            RichBlock(kind: .bulletList, inlines: [.text("parent")]),
            RichBlock(kind: .bulletList, inlines: [.text("child")], indent: 1),
            RichBlock(kind: .numberedList, inlines: [.text("first")], indent: 1),
            RichBlock(kind: .numberedList, inlines: [.text("second")], indent: 1),
            RichBlock(kind: .checklist, inlines: [.text("todo")], checked: false, indent: 2),
            .paragraph("prose")
        ])
        let storage = RichDocumentSerializer.attributedString(from: doc)
        let parsed = RichDocumentSerializer.document(from: storage)
        XCTAssertEqual(parsed.blocks.map(\.kind), doc.blocks.map(\.kind))
        XCTAssertEqual(parsed.blocks.map(\.listIndentLevel), [0, 1, 1, 1, 2, 0])
        XCTAssertEqual(parsed.blocks.map(\.plainInlineText), ["parent", "child", "first", "second", "todo", "prose"])

        // The continuous editor carries the level as a paragraph inset;
        // block rows inset themselves and keep the storage flush.
        let childLine = storage.string.components(separatedBy: "\n")[1]
        XCTAssertEqual(childLine, "◦ child")
        let childStart = (storage.string as NSString).range(of: "◦ child").location
        let style = storage.attribute(.paragraphStyle, at: childStart, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.firstLineHeadIndent, RichListIndent.insetPerLevel)
        let flush = RichDocumentSerializer.attributedString(from: doc, insetsListIndent: false)
        let flushStyle = flush.attribute(.paragraphStyle, at: childStart, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(flushStyle?.firstLineHeadIndent, 0)
    }

    func testMarkdownCopyNestsWithTwoSpacesAndPasteReadsItBack() {
        let doc = RichDocument(blocks: [
            RichBlock(kind: .numberedList, inlines: [.text("one")]),
            RichBlock(kind: .bulletList, inlines: [.text("child")], indent: 1),
            RichBlock(kind: .checklist, inlines: [.text("todo")], checked: true, indent: 2),
            RichBlock(kind: .numberedList, inlines: [.text("two")])
        ])
        let lines = BlockOperations.markdownLines(for: doc.blocks)
        XCTAssertEqual(lines, ["1. one", "  - child", "    - [x] todo", "2. two"])

        let pasted = BlockOperations.parsedPasteBlocks(from: lines.joined(separator: "\n"))
        XCTAssertEqual(pasted.map(\.kind), [.numberedList, .bulletList, .checklist, .numberedList])
        XCTAssertEqual(pasted.map(\.listIndentLevel), [0, 1, 2, 0])
        XCTAssertEqual(pasted[2].checked, true)

        // Indented prose is not a list — the leading spaces stay content.
        let prose = BlockOperations.parsedPasteBlocks(from: "  just indented text")
        XCTAssertEqual(prose[0].kind, .paragraph)
        XCTAssertEqual(prose[0].plainInlineText, "  just indented text")
    }

    // MARK: - Operations

    private func list(_ levels: [Int], kind: RichBlockKind = .bulletList) -> RichDocument {
        RichDocument(blocks: levels.enumerated().map { index, level in
            RichBlock(kind: kind, inlines: [.text("item \(index)")], indent: level)
        })
    }

    func testTabNestsOnePastTheItemAboveAndShiftTabWalksBack() throws {
        var doc = list([0, 0])
        doc = try BlockOperations.indentListBlock(in: doc, at: .root(index: 1), deeper: true).document
        XCTAssertEqual(doc.blocks.map(\.listIndentLevel), [0, 1])

        // Capped one past the item above — a second Tab is a no-op.
        let capped = try BlockOperations.indentListBlock(in: doc, at: .root(index: 1), deeper: true)
        XCTAssertEqual(capped.document, doc)
        XCTAssertEqual(capped.focusPath, .root(index: 1))

        doc = try BlockOperations.indentListBlock(in: doc, at: .root(index: 1), deeper: false).document
        XCTAssertEqual(doc.blocks.map(\.listIndentLevel), [0, 0])
        XCTAssertNil(doc.blocks[1].indent, "the margin stores nil, not 0")

        // Nothing to nest under: the first item never indents.
        let first = try BlockOperations.indentListBlock(in: doc, at: .root(index: 0), deeper: true)
        XCTAssertEqual(first.document, doc)

        // Prose is not ours.
        XCTAssertThrowsError(try BlockOperations.indentListBlock(
            in: RichDocument(blocks: [.paragraph("p")]), at: .root(index: 0), deeper: true
        ))
    }

    func testTabMovesTheSubtreeWithItsParent() throws {
        // parent, child, grandchild, sibling-of-parent
        var doc = list([0, 0, 1, 2, 0])
        doc = try BlockOperations.indentListBlock(in: doc, at: .root(index: 1), deeper: true).document
        XCTAssertEqual(doc.blocks.map(\.listIndentLevel), [0, 1, 2, 3, 0])
        doc = try BlockOperations.indentListBlock(in: doc, at: .root(index: 1), deeper: false).document
        XCTAssertEqual(doc.blocks.map(\.listIndentLevel), [0, 0, 1, 2, 0])
        XCTAssertEqual(RichListIndent.subtreeRange(in: doc.blocks, at: 1), 1..<4)
    }

    func testSubtreeStopsAtTheDepthCeiling() throws {
        var doc = list([0, 1, 2, 3, 4, 5])
        // The deepest item cannot go past maxLevel; the rest still move.
        doc = try BlockOperations.indentListBlock(in: doc, at: .root(index: 1), deeper: true).document
        XCTAssertEqual(doc.blocks.map(\.listIndentLevel), [0, 1, 2, 3, 4, 5], "capped: item 1 is already one past item 0")
        doc = try BlockOperations.indentListBlock(in: doc, at: .root(index: 5), deeper: true).document
        XCTAssertEqual(doc.blocks[5].listIndentLevel, RichListIndent.maxLevel)
    }

    func testReturnSplitsAtTheSameLevelAndEmptyNestedReturnClimbsFirst() throws {
        let doc = RichDocument(blocks: [
            RichBlock(kind: .bulletList, inlines: [.text("parent")]),
            RichBlock(kind: .bulletList, inlines: [.text("child text")], indent: 1)
        ])
        let split = try BlockOperations.splitTextBlock(in: doc, at: .root(index: 1), utf16Offset: 5)
        XCTAssertEqual(split.document.blocks.map(\.listIndentLevel), [0, 1, 1])
        XCTAssertEqual(split.document.blocks[2].plainInlineText, " text")

        let empty = RichDocument(blocks: [
            RichBlock(kind: .bulletList, inlines: [.text("parent")]),
            RichBlock(kind: .bulletList, inlines: [.text("")], indent: 2)
        ])
        let climbed = try BlockOperations.exitEmptyListBlock(in: empty, at: .root(index: 1))
        XCTAssertEqual(climbed.document.blocks[1].kind, .bulletList, "a nested empty item climbs, it does not exit")
        XCTAssertEqual(climbed.document.blocks[1].listIndentLevel, 1)
        let climbedAgain = try BlockOperations.exitEmptyListBlock(in: climbed.document, at: .root(index: 1))
        XCTAssertEqual(climbedAgain.document.blocks[1].listIndentLevel, 0)
        let exited = try BlockOperations.exitEmptyListBlock(in: climbedAgain.document, at: .root(index: 1))
        XCTAssertEqual(exited.document.blocks[1].kind, .paragraph, "only the margin press leaves the list")
    }

    func testTransformKeepsLevelBetweenListsAndDropsItForProse() throws {
        let doc = list([0, 1])
        let todo = try BlockOperations.transformBlock(in: doc, at: .root(index: 1), to: .checklist)
        XCTAssertEqual(todo.document.blocks[1].listIndentLevel, 1)
        let prose = try BlockOperations.transformBlock(in: doc, at: .root(index: 1), to: .paragraph)
        XCTAssertNil(prose.document.blocks[1].indent)
        XCTAssertEqual(prose.document.blocks[1].listIndentLevel, 0)
    }

    func testRowSyncRestoresTheLevelAKeystrokeCannotSee() {
        let existing = RichBlock(kind: .bulletList, inlines: [.text("old")], indent: 2)
        let parsed = [RichBlock(kind: .bulletList, inlines: [.text("new")])]
        let reconciled = BlockRowSyncPolicy.reconciled(parsed: parsed, existingBlock: existing)
        XCTAssertEqual(reconciled[0].indent, 2)
        XCTAssertEqual(reconciled[0].plainInlineText, "new")
    }

    func testHandleMenuIndentMovesEachSelectedItemTopDown() {
        let doc = list([0, 0, 0])
        let ids: Set<UUID> = [doc.blocks[1].id, doc.blocks[2].id]
        let deeper = BlockOperations.indentBlocks(withIDs: ids, in: doc, deeper: true)
        XCTAssertEqual(deeper?.document.blocks.map(\.listIndentLevel), [0, 1, 2], "item 2 nests under the just-moved item 1")
        let shallower = BlockOperations.indentBlocks(withIDs: ids, in: deeper!.document, deeper: false)
        XCTAssertEqual(shallower?.document.blocks.map(\.listIndentLevel), [0, 0, 1])
        XCTAssertNil(BlockOperations.indentBlocks(withIDs: [doc.blocks[0].id], in: doc, deeper: true), "nothing could move")
    }

    func testPlainTextIndentsNestedItems() {
        let doc = RichDocument(blocks: [
            RichBlock(kind: .numberedList, inlines: [.text("one")]),
            RichBlock(kind: .bulletList, inlines: [.text("child")], indent: 1),
            RichBlock(kind: .numberedList, inlines: [.text("two")])
        ])
        XCTAssertEqual(doc.plainText, "1. one\n  ◦ child\n2. two")
    }
}
