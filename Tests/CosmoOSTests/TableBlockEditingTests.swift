import AppKit
import SwiftUI
import XCTest
@testable import CosmoOS

/// Editor-side contracts for tables and sections: the opaque round trip
/// through the continuous editor, the canvas edit gate, cell typography
/// parity, grid metrics, and the row-only field carriage.
@MainActor
final class TableBlockEditingTests: XCTestCase {

    private func sampleTable() -> RichTable {
        var table = RichTable(strings: [["Hook", "Score"], ["Specific", "9"], ["Clever", "4"]], hasHeaderRow: true)
        table.columns[1].alignment = .trailing
        table.rows[1].cells[0].toneID = "clay"
        return table
    }

    // MARK: Opaque round trip (continuous editor)

    func testTableSurvivesTheContinuousEditorRoundTrip() {
        let table = RichBlock.table(sampleTable())
        let section = RichBlock.section(title: "Box", style: RichSectionStyle(toneID: "plum", appearance: .bar), children: [.paragraph("inside")])
        let document = RichDocument(blocks: [.paragraph("before"), table, section, .paragraph("after")])

        let attributed = RichDocumentSerializer.attributedString(from: document, fontSize: 17, darkMode: false)
        XCTAssertTrue(attributed.string.contains("Table · 3 × 2"), "the continuous editor shows a muted chip, never cells")
        XCTAssertTrue(attributed.string.contains("Section · Box"))

        let parsed = RichDocumentSerializer.document(from: attributed)
        XCTAssertEqual(parsed.blocks.map(\.kind), [.paragraph, .table, .section, .paragraph])
        XCTAssertEqual(parsed.blocks[1].table, table.table, "cells, tones and alignment come back byte-for-byte")
        XCTAssertEqual(parsed.blocks[2].section, section.section)
        XCTAssertEqual(parsed.blocks[2].children, section.children)
        XCTAssertEqual(parsed.blocks[2].inlines.map(\.plainText).joined(), "Box")
    }

    func testRequiresBlockEditorFlagsStructuredKindsAtAnyDepth() {
        XCTAssertFalse(RichDocument(blocks: [.paragraph("a"), RichBlock(kind: .bulletList, inlines: [.text("b")])]).requiresBlockEditor)
        XCTAssertTrue(RichDocument(blocks: [.table()]).requiresBlockEditor)
        XCTAssertTrue(RichDocument(blocks: [.section(title: "s")]).requiresBlockEditor)
        XCTAssertTrue(RichDocument(blocks: [RichBlock(kind: .callout, inlines: [.text("c")])]).requiresBlockEditor)
        let nested = RichBlock(kind: .toggle, inlines: [.text("t")], children: [.table()])
        XCTAssertTrue(RichDocument(blocks: [nested]).requiresBlockEditor)
    }

    /// The canvas card must open focus mode for such notes instead of its
    /// continuous editor (which would flatten them).
    func testCanvasNoteCardGatesStructuredNotesIntoFocusMode() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Canvas/NoteBlockView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("if noteBodyDocument.requiresBlockEditor {"), "the tap handler consults requiresBlockEditor")
        let tapRange = try XCTUnwrap(source.range(of: "if noteBodyDocument.requiresBlockEditor {"))
        let tail = source[tapRange.upperBound...].prefix(120)
        XCTAssertTrue(tail.contains("openFocusMode()"), "structured notes enter through focus mode")
    }

    // MARK: Plain text

    func testPlainTextRendersPipeTablesAndSectionHeaders() {
        let document = RichDocument(blocks: [
            .table(sampleTable()),
            .section(title: "Part one", children: [.paragraph("child")]),
        ])
        let text = document.plainText
        XCTAssertTrue(text.hasPrefix("| Hook | Score |\n| --- | ---: |\n| Specific | 9 |\n| Clever | 4 |"), text)
        XCTAssertTrue(text.contains("▣ Part one\n  child"))
    }

    // MARK: Cell typography parity

    func testHeaderCellsAreSemiboldAndAlignmentRidesTheParagraphStyle() {
        let typography = TableCellTypography(fontSize: 17, fontDesign: .serif, lineSpacingAdjustment: 0, darkMode: false, overrideTextColor: nil)
        let header = typography.attributedString(for: [.text("Hook")], isHeader: true, alignment: .trailing)
        let font = try? XCTUnwrap(header.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font?.pointSize, 17)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, "header weight is semibold (reads as bold trait)")
        let paragraph = header.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.alignment, .right)

        let inked = typography.attributedString(
            for: [RichInlineNode(kind: .text, text: "x", inkID: "plum")],
            isHeader: false,
            alignment: .leading
        )
        XCTAssertEqual(inked.attribute(RichDocumentAttributeKeys.inkID, at: 0, effectiveRange: nil) as? String, "plum")
    }

    func testOverrideTextColorSkipsInkedRuns() {
        let typography = TableCellTypography(fontSize: 17, fontDesign: .default, lineSpacingAdjustment: 0, darkMode: true, overrideTextColor: .white)
        let attributed = typography.attributedString(
            for: [.text("plain "), RichInlineNode(kind: .text, text: "inked", inkID: "rose")],
            isHeader: false,
            alignment: .leading
        )
        let plainColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let inkedColor = attributed.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor
        XCTAssertEqual(plainColor, .white)
        XCTAssertNotEqual(inkedColor, .white, "deliberate ink keeps its tone under a theme override")
    }

    // MARK: Grid metrics

    func testGridMetricsResolveRowsFromAnchorFramesIncludingSpans() throws {
        var table = RichTable(rowCount: 3, columnCount: 2)
        table = try RichTableOperations.mergeCells(in: table, rect: RichTableRect(rows: 1...2, columns: 0...0)).table
        let widths: [CGFloat] = [100, 140]
        let frames: [RichTableCellAddress: CGRect] = [
            RichTableCellAddress(row: 0, column: 0): CGRect(x: 0, y: 0, width: 100, height: 30),
            RichTableCellAddress(row: 0, column: 1): CGRect(x: 100, y: 0, width: 140, height: 30),
            RichTableCellAddress(row: 1, column: 0): CGRect(x: 0, y: 30, width: 100, height: 70),
            RichTableCellAddress(row: 1, column: 1): CGRect(x: 100, y: 30, width: 140, height: 30),
            RichTableCellAddress(row: 2, column: 1): CGRect(x: 100, y: 60, width: 140, height: 40),
        ]
        let metrics = TableGridMetrics.resolve(table: table, widths: widths, frames: frames)
        XCTAssertEqual(metrics.rowOrigins, [0, 30, 60])
        XCTAssertEqual(metrics.rowHeights, [30, 30, 40])
        XCTAssertEqual(metrics.width, 240)
        XCTAssertEqual(metrics.height, 100)
        XCTAssertEqual(metrics.columnIndex(at: 150), 1)
        XCTAssertEqual(metrics.columnInsertionIndex(at: 30), 0)
        XCTAssertEqual(metrics.columnInsertionIndex(at: 90), 1)
        XCTAssertEqual(metrics.columnInsertionIndex(at: 239), 2)
        XCTAssertEqual(metrics.rowIndex(at: 65), 2)
        XCTAssertEqual(metrics.rowInsertionIndex(at: 10), 0)
        XCTAssertEqual(metrics.rowInsertionIndex(at: 95), 3)
    }

    func testResolvedColumnWidthsHonourFloorsAndOverflow() {
        var table = RichTable(rowCount: 1, columnCount: 3)
        table.columns[0].weight = 4
        table.columns[1].weight = 1
        table.columns[2].weight = 1
        let widths = table.resolvedColumnWidths(available: 600, minimum: 72)
        XCTAssertEqual(widths.reduce(0, +), 600, accuracy: 0.01)
        XCTAssertEqual(widths[0], 400, accuracy: 0.01)
        let floored = table.resolvedColumnWidths(available: 300, minimum: 72)
        XCTAssertEqual(floored[1], 72, accuracy: 0.01)
        XCTAssertEqual(floored[2], 72, accuracy: 0.01)
        XCTAssertEqual(floored[0], 156, accuracy: 0.01)
        let overflow = table.resolvedColumnWidths(available: 100, minimum: 72)
        XCTAssertGreaterThan(overflow.reduce(0, +), 100, "when floors cannot fit, the table scrolls")
    }

    // MARK: Row-only carriage

    func testSectionTitleTypingKeepsChildrenAndStyle() throws {
        let style = RichSectionStyle(toneID: "rose", appearance: .outline, icon: "flame")
        let existing = RichBlock.section(title: "Part", style: style, children: [.paragraph("child")])
        var reemitted = RichBlock(id: existing.id, kind: .paragraph, inlines: [.text("Part one")])
        reemitted.passthrough = [:]
        let restored = try XCTUnwrap(BlockRowSyncPolicy.reconciled(parsed: [reemitted], existingBlock: existing).first)
        XCTAssertEqual(restored.kind, .section)
        XCTAssertEqual(restored.section, style)
        XCTAssertEqual(restored.children, existing.children)
        XCTAssertEqual(restored.inlines.map(\.plainText).joined(), "Part one")
    }

    func testEditorRowBlockProxiesTheSectionTitle() {
        let existing = RichBlock.section(title: "Part", children: [.paragraph("child")])
        let proxy = BlockRowSyncPolicy.editorRowBlock(for: existing)
        XCTAssertEqual(proxy.kind, .paragraph)
        XCTAssertEqual(proxy.id, existing.id)
        XCTAssertEqual(proxy.inlines, existing.inlines)
        XCTAssertEqual(BlockRowSyncPolicy.editorRowBlock(for: .paragraph("x")).kind, .paragraph)
    }
}
