import AppKit
import XCTest
@testable import CosmoOS

/// The rich-paste pipeline against fixtures shaped like the real clipboard:
/// Google Docs (tables + mixed formatting), Sheets, Excel, Numbers, Notion,
/// a Safari article, TSV, CSV, Markdown pipe tables, and prose that must
/// stay prose.
final class ClipboardImportTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Clipboard/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func table(in blocks: [RichBlock]) throws -> RichTable {
        try XCTUnwrap(blocks.first(where: { $0.kind == .table })?.table, "no table block in \(blocks.map(\.kind))")
    }

    // MARK: Google Docs

    func testGoogleDocsTableImportsGridSpansTonesAndFormatting() throws {
        let blocks = HTMLBlockImporter.blocks(fromHTML: try fixture("google-docs-table.html"))
        XCTAssertEqual(blocks.count, 1, "the clip is exactly one table")
        let table = try table(in: blocks)
        XCTAssertTrue(table.validate().isEmpty, "\(table.validate())")
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertTrue(table.hasHeaderRow, "first row of #efefef cells + bold reads as a header")
        XCTAssertEqual(table[RichTableCellAddress(row: 0, column: 0)].plainText, "Hook")
        XCTAssertTrue(table[RichTableCellAddress(row: 0, column: 0)].inlines.first?.marks.contains(.bold) == true)

        // rowspan=2 on (1,0): (2,0) is covered by it.
        let anchor = table[RichTableCellAddress(row: 1, column: 0)]
        XCTAssertEqual(anchor.rowSpan, 2)
        XCTAssertEqual(table[RichTableCellAddress(row: 2, column: 0)].coveredBy, anchor.id)
        XCTAssertEqual(anchor.toneID, "moss", "#d9ead3 is a pale green → moss")

        // colspan=2 on (2,1): (2,2) covered.
        let merged = table[RichTableCellAddress(row: 2, column: 1)]
        XCTAssertEqual(merged.colSpan, 2)
        XCTAssertEqual(table[RichTableCellAddress(row: 2, column: 2)].coveredBy, merged.id)
        XCTAssertEqual(merged.plainText, "Merged note across two columns")

        // Inline formatting inside a cell: red italic run + two <p> + <br> → soft breaks.
        let rich = table[RichTableCellAddress(row: 1, column: 1)]
        let first = try XCTUnwrap(rich.inlines.first)
        XCTAssertTrue(first.marks.contains(.italic))
        XCTAssertNotNil(first.inkID, "#cc0000 maps to a tone")
        XCTAssertEqual(rich.plainText.components(separatedBy: "\u{2028}").count, 3, "two paragraphs + one <br> = three lines")
        XCTAssertTrue(rich.plainText.hasPrefix("Names a tension the reader feels"))

        // Score column is right-aligned in the majority of its cells.
        XCTAssertEqual(table.columns[2].alignment, .trailing)
        // colgroup widths 120/240/120 → weights 1/2/1.
        XCTAssertEqual(table.columns[1].weight / table.columns[0].weight, 2, accuracy: 0.01)
        // White cell backgrounds are not tones.
        XCTAssertNil(table[RichTableCellAddress(row: 1, column: 1)].toneID)

        let data = try JSONEncoder().encode(blocks)
        let decoded = try JSONDecoder().decode([RichBlock].self, from: data)
        XCTAssertEqual(decoded, blocks)
    }

    func testGoogleDocsMixedContentKeepsStructureAndDropsBlankParagraphs() throws {
        let blocks = HTMLBlockImporter.blocks(fromHTML: try fixture("google-docs-mixed.html"))
        let kinds = blocks.map(\.kind)
        XCTAssertEqual(kinds, [.heading1, .heading1, .paragraph, .bulletList, .bulletList, .bulletList, .numberedList, .checklist, .paragraph, .paragraph], "\(kinds)")
        XCTAssertEqual(blocks[0].plainInlineText, "Hook writing principles", "p.title → heading1")
        XCTAssertEqual(blocks[1].plainInlineText, "Morning pages")

        // The <b font-weight:normal> wrapper must NOT bold everything.
        let body = blocks[2].inlines
        XCTAssertEqual(body[0].text, "The best hooks name a ")
        XCTAssertFalse(body[0].marks.contains(.bold))
        XCTAssertEqual(body[1].text, "specific tension")
        XCTAssertTrue(body[1].marks.contains(.bold))
        XCTAssertTrue(body[2].marks.contains(.italic))
        XCTAssertTrue(body[3].marks.contains(.underline))
        XCTAssertEqual(body[4].inkID, "plum")
        XCTAssertEqual(body[4].highlightID, "gilt")

        XCTAssertEqual(blocks[5].plainInlineText, "Nested point", "nested lists flatten in order")
        XCTAssertEqual(blocks[7].checked, true, "role=checkbox aria-checked=true")
        XCTAssertEqual(blocks[7].plainInlineText, "Test against swipe file")
        XCTAssertEqual(blocks[8].inlines.first?.href, "https://cosmo.example/hooks")
        XCTAssertEqual(blocks[9].plainInlineText, "Closing line.")
        XCTAssertFalse(blocks.contains { $0.kind == .paragraph && $0.plainInlineText.trimmingCharacters(in: .whitespaces).isEmpty }, "blank &nbsp; paragraphs are dropped")
    }

    // MARK: Spreadsheets & other apps

    func testGoogleSheetsTable() throws {
        let table = try table(in: HTMLBlockImporter.blocks(fromHTML: try fixture("google-sheets.html")))
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 2)
        XCTAssertEqual(table[RichTableCellAddress(row: 2, column: 1)].plainText, "3,100")
        XCTAssertEqual(table.columns[1].alignment, .trailing)
        XCTAssertTrue(table[RichTableCellAddress(row: 0, column: 0)].inlines.first?.marks.contains(.bold) == true)
        XCTAssertEqual(table.columns[1].weight / table.columns[0].weight, 1.5, accuracy: 0.01)
    }

    func testExcelTable() throws {
        let table = try table(in: HTMLBlockImporter.blocks(fromHTML: try fixture("excel.html")))
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 2)
        XCTAssertEqual(table[RichTableCellAddress(row: 1, column: 1)].plainText, "Name the myth")
        XCTAssertEqual(table[RichTableCellAddress(row: 2, column: 1)].plainText, "2")
    }

    func testNumbersTableHeaderFromThead() throws {
        let table = try table(in: HTMLBlockImporter.blocks(fromHTML: try fixture("numbers.html")))
        XCTAssertTrue(table.hasHeaderRow)
        XCTAssertEqual(table[RichTableCellAddress(row: 0, column: 1)].plainText, "Claim")
        XCTAssertEqual(table[RichTableCellAddress(row: 1, column: 0)].plainText, "Norén")
    }

    func testNotionDivSoup() throws {
        let blocks = HTMLBlockImporter.blocks(fromHTML: try fixture("notion.html"))
        XCTAssertEqual(blocks.map(\.kind), [.heading2, .paragraph, .table, .bulletList, .bulletList])
        XCTAssertTrue(blocks[1].inlines.contains { $0.text == "tension" && $0.marks.contains(.bold) })
        let table = try table(in: blocks)
        XCTAssertTrue(table.hasHeaderRow)
        XCTAssertEqual(table[RichTableCellAddress(row: 1, column: 1)].plainText, "Low")
    }

    func testSafariArticleDropsChromeKeepsStructure() throws {
        let blocks = HTMLBlockImporter.blocks(fromHTML: try fixture("safari-article.html"))
        XCTAssertEqual(blocks.map(\.kind), [.heading1, .paragraph, .quote, .code, .divider, .paragraph])
        XCTAssertFalse(blocks.contains { $0.plainInlineText.contains("Home") }, "nav is dropped")
        XCTAssertFalse(blocks.contains { $0.plainInlineText.contains("track()") }, "script is dropped")
        XCTAssertEqual(blocks[3].plainInlineText, "let x = 1\u{2028}let y = 2")
    }

    // MARK: Plain text

    func testTSVBecomesTable() throws {
        let table = try XCTUnwrap(TabularTextImporter.table(fromPlainText: try fixture("tsv.txt")))
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertTrue(table.hasHeaderRow)
        XCTAssertEqual(table[RichTableCellAddress(row: 1, column: 2)].plainText, "9")
    }

    func testCSVWithQuotedFieldsBecomesTable() throws {
        let table = try XCTUnwrap(TabularTextImporter.table(fromPlainText: try fixture("csv.txt")))
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table[RichTableCellAddress(row: 1, column: 1)].plainText, "Hello, world")
        XCTAssertEqual(table[RichTableCellAddress(row: 2, column: 1)].plainText, "Multi\nline")
    }

    func testPipeTableWithAlignmentsAndEscapes() throws {
        let table = try XCTUnwrap(TabularTextImporter.table(fromPlainText: try fixture("pipe-table.md")))
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.columns.map(\.alignment), [.leading, .center, .trailing])
        XCTAssertEqual(table[RichTableCellAddress(row: 1, column: 1)].plainText, "Names a tension\u{2028}the reader feels")
        XCTAssertEqual(table[RichTableCellAddress(row: 2, column: 0)].plainText, "Pipe | escaped")
    }

    func testProseIsNeverATable() throws {
        XCTAssertNil(TabularTextImporter.table(fromPlainText: try fixture("prose.txt")))
        XCTAssertNil(TabularTextImporter.table(fromPlainText: "Just one line"))
        XCTAssertNil(TabularTextImporter.table(fromPlainText: "a\tb\nc"))
    }

    // MARK: Writer round trips

    func testHTMLWriterRoundTripsThroughTheImporter() throws {
        var source = RichTable(strings: [["Hook", "Score"], ["Specific", "9"], ["Clever", "4"]], hasHeaderRow: true)
        source.columns[1].alignment = .trailing
        source.rows[1].cells[0].toneID = "clay"
        source.rows[1].cells[1].inlines = [RichInlineNode(kind: .text, text: "9", marks: [.bold], inkID: "rose")]
        let html = TableClipboardWriter.html(for: source)
        let imported = try table(in: HTMLBlockImporter.blocks(fromHTML: html))
        XCTAssertEqual(imported.rowCount, 3)
        XCTAssertEqual(imported.columnCount, 2)
        XCTAssertTrue(imported.hasHeaderRow)
        XCTAssertEqual(imported.columns[1].alignment, .trailing)
        XCTAssertEqual(imported[RichTableCellAddress(row: 1, column: 0)].toneID, "clay")
        XCTAssertEqual(imported[RichTableCellAddress(row: 1, column: 1)].inlines.first?.marks.contains(.bold), true)
        XCTAssertEqual(imported[RichTableCellAddress(row: 1, column: 1)].inlines.first?.inkID, "rose")
    }

    func testHTMLWriterEmitsSpansAndClipsThem() throws {
        var source = RichTable(rowCount: 3, columnCount: 3)
        source = try RichTableOperations.mergeCells(in: source, rect: RichTableRect(rows: 1...2, columns: 0...1)).table
        let full = TableClipboardWriter.html(for: source)
        XCTAssertTrue(full.contains("rowspan=\"2\""))
        XCTAssertTrue(full.contains("colspan=\"2\""))
        let clipped = TableClipboardWriter.html(for: source, rect: RichTableRect(rows: 1...1, columns: 0...2))
        XCTAssertFalse(clipped.contains("rowspan"), "a span cut by the copied rectangle is emitted unmerged")
        let reimported = try table(in: HTMLBlockImporter.blocks(fromHTML: full))
        XCTAssertEqual(reimported[RichTableCellAddress(row: 1, column: 0)].rowSpan, 2)
        XCTAssertEqual(reimported[RichTableCellAddress(row: 1, column: 0)].colSpan, 2)
        XCTAssertTrue(reimported.validate().isEmpty)
    }

    func testTSVAndMarkdownWriters() {
        let source = RichTable(strings: [["a", "b"], ["c\u{2028}d", "e|f"]], hasHeaderRow: true)
        XCTAssertEqual(TableClipboardWriter.tsv(for: source), "a\tb\nc d\te|f")
        XCTAssertEqual(TableClipboardWriter.markdown(for: source), "| a | b |\n| --- | --- |\n| c<br>d | e\\|f |")
    }

    func testBlocksHTMLWriterCoversTheBlockKinds() {
        let blocks: [RichBlock] = [
            RichBlock(kind: .heading2, inlines: [.text("Title")]),
            RichBlock(kind: .bulletList, inlines: [.text("one")]),
            RichBlock(kind: .checklist, inlines: [.text("two")], checked: true),
            RichBlock(kind: .quote, inlines: [.text("q")]),
            RichBlock(kind: .divider),
            RichBlock.section(title: "Box", children: [.paragraph("inside")]),
            RichBlock.table(RichTable(strings: [["x"]], hasHeaderRow: false)),
        ]
        let html = TableClipboardWriter.html(forBlocks: blocks)
        XCTAssertTrue(html.contains("<h2>Title</h2>"))
        XCTAssertTrue(html.contains("<ul><li>one</li><li role=\"checkbox\" aria-checked=\"true\">☑ two</li></ul>"))
        XCTAssertTrue(html.contains("<blockquote><p>q</p></blockquote><hr>"))
        XCTAssertTrue(html.contains("<section><h2>Box</h2><p>inside</p></section>"))
        XCTAssertTrue(html.contains("<table"))
    }

    // MARK: Reader

    func testReaderHandlesEntitiesUnclosedTagsAndImplicitCloses() {
        let root = CosmoHTMLReader.parse("<P>Tom &amp; Jerry &#8212; &hellip;<p>Second<ul><li>a<li>b</ul><div>tail")
        let paragraphs = root.descendants(named: "p")
        XCTAssertEqual(paragraphs.count, 2, "an opening <p> closes the previous one")
        XCTAssertEqual(paragraphs[0].innerText, "Tom & Jerry — …")
        XCTAssertEqual(root.descendants(named: "li").map(\.innerText), ["a", "b"])
        XCTAssertEqual(root.descendants(named: "div").first?.innerText, "tail")
    }

    func testReaderDropsScriptAndStyleAndParsesAttributes() {
        let root = CosmoHTMLReader.parse("<style>p{}</style><script>alert('x')</script><a HREF='https://x.y' data-flag class=\"one two\">link</a>")
        XCTAssertTrue(root.descendants(named: "style").isEmpty || root.descendants(named: "style").allSatisfy { $0.innerText.isEmpty })
        let anchor = try? XCTUnwrap(root.descendants(named: "a").first)
        XCTAssertEqual(anchor?.attr("href"), "https://x.y")
        XCTAssertTrue(anchor?.hasAttr("data-flag") == true)
        XCTAssertEqual(anchor?.classNames, ["one", "two"])
        XCTAssertEqual(anchor?.innerText, "link")
    }

    func testReaderSurvivesRandomTagSoup() {
        var generator = SeededGenerator(seed: 0xC1A5_B0A8)
        let atoms = ["<p>", "</p>", "<div", ">", "<br/>", "&amp;", "&#x41;", "<table>", "<tr>", "<td colspan=", "\"3\"", "</td>", "</table>", "<b style='font-weight:normal'>", "text ", "<!-- c -->", "<script>", "</script>", "<", ">", "&", "\"", "'", "=", "<li>", "</ul>", "<img src=x>", "</", "<h1>", "\n"]
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<2_000 {
            let length = Int.random(in: 1...40, using: &generator)
            var soup = ""
            for _ in 0..<length { soup += atoms[Int.random(in: 0..<atoms.count, using: &generator)] }
            let root = CosmoHTMLReader.parse(soup)
            _ = HTMLBlockImporter.blocks(from: root)
        }
        let elapsed = clock.now - start
        XCTAssertLessThan(elapsed, .seconds(20), "2,000 soups must parse in well under 20 s")
    }

    // MARK: Pasteboard priority

    @MainActor
    func testPasteboardPriorityHTMLThenRTFThenPlain() throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("<table><tr><th>A</th></tr><tr><td>1</td></tr></table>", forType: .html)
        pasteboard.setString("A\n1", forType: .string)
        if case .table(let table) = ClipboardBlockImporter.read(pasteboard) {
            XCTAssertEqual(table.rowCount, 2)
        } else {
            XCTFail("HTML table should win over plain text")
        }

        pasteboard.clearContents()
        pasteboard.setString("<p>Just <b>one</b> line</p>", forType: .html)
        if case .inline(let nodes) = ClipboardBlockImporter.read(pasteboard) {
            XCTAssertEqual(nodes.map(\.plainText).joined(), "Just one line")
            XCTAssertTrue(nodes.contains { $0.marks.contains(.bold) })
        } else {
            XCTFail("a single paragraph pastes inline")
        }

        pasteboard.clearContents()
        pasteboard.setString("Hook\tScore\nA\t1", forType: .string)
        if case .table(let table) = ClipboardBlockImporter.read(pasteboard) {
            XCTAssertEqual(table.columnCount, 2)
        } else {
            XCTFail("TSV plain text becomes a table")
        }

        pasteboard.clearContents()
        pasteboard.setString("plain words", forType: .string)
        if case .text(let text) = ClipboardBlockImporter.read(pasteboard) {
            XCTAssertEqual(text, "plain words")
        } else {
            XCTFail("ordinary text stays text")
        }
        pasteboard.clearContents()
    }
}
