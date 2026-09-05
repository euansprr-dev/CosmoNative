import XCTest
@testable import CosmoOS

/// The table model itself: codable round trips and lenient decoding,
/// `validate()`/`repaired()`, the markdown and TSV renderers, column width
/// resolution, and unknown-key passthrough on blocks and inline nodes.
final class RichTableModelTests: XCTestCase {

    // MARK: - Helpers

    private func addr(_ row: Int, _ column: Int) -> RichTableCellAddress {
        RichTableCellAddress(row: row, column: column)
    }

    private func rect(_ rows: ClosedRange<Int>, _ columns: ClosedRange<Int>) -> RichTableRect {
        RichTableRect(rows: rows, columns: columns)
    }

    private func grid(_ strings: [[String]], header: Bool = true) -> RichTable {
        RichTable(strings: strings, hasHeaderRow: header)
    }

    private func text(_ table: RichTable, _ row: Int, _ column: Int) -> String {
        table[addr(row, column)].plainText
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A 3 × 3 table with a 2 × 2 span at (1, 1), tones, alignments and a
    /// mixed-run cell.
    private func fixture() throws -> RichTable {
        var table = grid([["h1", "h2", "h3"], ["a", "b", "c"], ["d", "e", "f"]])
        table.columns[1].alignment = .center
        table.columns[2].alignment = .trailing
        table.columns[2].weight = 2.5
        table.style = .lines
        table.isStriped = true
        table.hasHeaderColumn = true
        table[addr(0, 0)].inlines = [.text("h", marks: [.bold]), .text("1")]
        table[addr(1, 0)].toneID = "moss"
        table[addr(1, 0)].alignment = .center
        table[addr(1, 0)].verticalAlignment = .bottom
        table = try RichTableOperations.mergeCells(in: table, rect: rect(1...2, 1...2)).table
        table[addr(1, 1)].toneID = "rust"
        return table
    }

    // MARK: - Codable

    func testRoundTripPreservesEverything() throws {
        let table = try fixture()
        XCTAssertEqual(table.validate(), [])
        let decoded = try roundTrip(table)
        XCTAssertEqual(decoded, table)
        XCTAssertEqual(decoded[addr(1, 1)].rowSpan, 2)
        XCTAssertEqual(decoded[addr(1, 1)].colSpan, 2)
        XCTAssertEqual(decoded[addr(2, 2)].coveredBy, table[addr(1, 1)].id)
        XCTAssertEqual(decoded[addr(1, 0)].toneID, "moss")
        XCTAssertEqual(decoded[addr(1, 0)].alignment, .center)
        XCTAssertEqual(decoded[addr(1, 0)].verticalAlignment, .bottom)
        XCTAssertEqual(decoded.columns.map(\.alignment), [.leading, .center, .trailing])
        XCTAssertEqual(decoded.columns[2].weight, 2.5)
        XCTAssertEqual(decoded.style, .lines)
        XCTAssertTrue(decoded.isStriped)
        XCTAssertTrue(decoded.hasHeaderColumn)
        XCTAssertEqual(decoded[addr(0, 0)].inlines.first?.marks, [.bold])
    }

    func testEncodingOmitsDefaultSpanFields() throws {
        let table = try fixture()
        let object = try json(table)
        let rows = try XCTUnwrap(object["rows"] as? [[String: Any]])
        let cells = try XCTUnwrap(rows[0]["cells"] as? [[String: Any]])
        XCTAssertNil(cells[0]["rowSpan"])
        XCTAssertNil(cells[0]["colSpan"])
        XCTAssertNil(cells[0]["coveredBy"])
        XCTAssertNil(cells[0]["toneID"])
        let body = try XCTUnwrap(rows[1]["cells"] as? [[String: Any]])
        XCTAssertEqual(body[1]["rowSpan"] as? Int, 2)
        XCTAssertEqual(body[1]["colSpan"] as? Int, 2)
        XCTAssertEqual(body[1]["toneID"] as? String, "rust")
        XCTAssertNotNil(body[2]["coveredBy"])
    }

    func testLenientDecodeFillsMissingFields() throws {
        let raw = """
        {"rows":[{"cells":[{"inlines":[{"kind":"text","text":"a"}]},{"inlines":[]}]}]}
        """
        let table = try JSONDecoder().decode(RichTable.self, from: Data(raw.utf8))
        XCTAssertEqual(table.columnCount, 2, "columns are rebuilt from the widest row")
        XCTAssertEqual(table.rowCount, 1)
        XCTAssertEqual(text(table, 0, 0), "a")
        XCTAssertTrue(table.hasHeaderRow)
        XCTAssertFalse(table.hasHeaderColumn)
        XCTAssertEqual(table.style, .grid)
        XCTAssertFalse(table.isStriped)
        XCTAssertEqual(table.columns.map(\.weight), [1, 1])
        XCTAssertEqual(table.validate(), [])
    }

    func testLenientDecodeUnknownStyleWeightAndSpanOverflow() throws {
        let raw = """
        {"style":"neon","hasHeaderRow":false,
         "columns":[{"weight":-3},{"weight":"x","alignment":"diagonal"}],
         "rows":[{"cells":[{"inlines":[{"kind":"text","text":"a"}],"colSpan":5},{"inlines":[]}]}]}
        """
        let table = try JSONDecoder().decode(RichTable.self, from: Data(raw.utf8))
        XCTAssertEqual(table.style, .grid)
        XCTAssertEqual(table.columns.map(\.weight), [1, 1])
        XCTAssertEqual(table.columns[1].alignment, .leading)
        XCTAssertEqual(table[addr(0, 0)].colSpan, 1, "an overflowing span is dissolved at decode")
        XCTAssertEqual(text(table, 0, 0), "a")
        XCTAssertEqual(table.validate(), [])
    }

    func testEmptyObjectDecodesToOneByOne() throws {
        let table = try JSONDecoder().decode(RichTable.self, from: Data("{}".utf8))
        XCTAssertEqual(table.rowCount, 1)
        XCTAssertEqual(table.columnCount, 1)
        XCTAssertEqual(table.validate(), [])
    }

    // MARK: - Validate / repair

    func testValidateReportsViolations() {
        var ragged = grid([["a", "b"], ["c", "d"]], header: false)
        ragged.rows[1].cells.removeLast()
        XCTAssertEqual(ragged.validate(), [.raggedRow(1)])

        var crossing = grid([["a", "b"], ["c", "d"]], header: true)
        crossing[addr(0, 0)].rowSpan = 2
        crossing[addr(1, 0)] = .covered(by: crossing[addr(0, 0)].id)
        XCTAssertEqual(crossing.validate(), [.spanCrossesHeader(anchor: addr(0, 0))])

        var overflow = grid([["a", "b"]], header: false)
        overflow[addr(0, 1)].colSpan = 2
        XCTAssertEqual(overflow.validate(), [.spanOutOfBounds(anchor: addr(0, 1))])

        var dangling = grid([["a", ""]], header: false)
        dangling[addr(0, 1)].coveredBy = UUID()
        XCTAssertEqual(dangling.validate(), [.danglingCover(addr(0, 1))])

        var content = grid([["a", "b"]], header: false)
        content[addr(0, 0)].colSpan = 2
        content[addr(0, 1)].coveredBy = content[addr(0, 0)].id
        XCTAssertEqual(content.validate(), [.coveredCellCarriesContent(addr(0, 1))])

        var weight = grid([["a"]], header: false)
        weight.columns[0].weight = 0
        XCTAssertEqual(weight.validate(), [.nonPositiveWeight(column: 0)])

        var duplicate = grid([["a", "b"]], header: false)
        duplicate[addr(0, 1)].id = duplicate[addr(0, 0)].id
        XCTAssertEqual(duplicate.validate(), [.duplicateID])
    }

    func testRepairedPadsAndTrimsRaggedRows() {
        var table = grid([["a", "b", "c"], ["d", "e", "f"]], header: false)
        table.rows[0].cells.removeLast()
        table.rows[1].cells.append(.text("g"))
        let repaired = table.repaired()
        XCTAssertEqual(repaired.validate(), [])
        XCTAssertEqual(repaired.rows.map { $0.cells.map(\.plainText) }, [["a", "b", ""], ["d", "e", "f"]])
    }

    func testRepairedDissolvesOverflowingAndHeaderCrossingSpans() {
        var overflow = grid([["a", "b"], ["c", "d"]], header: false)
        overflow[addr(1, 1)].rowSpan = 2
        overflow[addr(1, 1)].colSpan = 2
        let fixed = overflow.repaired()
        XCTAssertEqual(fixed.validate(), [])
        XCTAssertFalse(fixed.hasAnySpan)
        XCTAssertEqual(text(fixed, 1, 1), "d")

        var crossing = grid([["a", "b"], ["c", "d"]], header: true)
        crossing[addr(0, 0)].rowSpan = 2
        crossing[addr(1, 0)] = .covered(by: crossing[addr(0, 0)].id)
        let uncrossed = crossing.repaired()
        XCTAssertEqual(uncrossed.validate(), [])
        XCTAssertEqual(uncrossed[addr(0, 0)].rowSpan, 1)
        XCTAssertFalse(uncrossed[addr(1, 0)].isCovered)
    }

    func testRepairedFixesCoversAndDuplicateIDs() {
        var table = grid([["a", "b", "c"], ["d", "e", "f"]], header: false)
        table[addr(0, 0)].colSpan = 2
        table[addr(1, 2)].coveredBy = UUID()
        table[addr(1, 1)].id = table[addr(0, 1)].id
        let repaired = table.repaired()
        XCTAssertEqual(repaired.validate(), [])
        XCTAssertEqual(repaired[addr(0, 1)].coveredBy, repaired[addr(0, 0)].id, "a missing cover is written")
        XCTAssertTrue(repaired[addr(0, 1)].inlines.isEmpty)
        XCTAssertNil(repaired[addr(1, 2)].coveredBy, "a cover pointing nowhere is cleared")
        XCTAssertEqual(text(repaired, 1, 2), "f")
        XCTAssertEqual(Set(repaired.rows.flatMap { $0.cells.map(\.id) }).count, 6)
    }

    func testRepairedRebuildsEmptyGrid() {
        let empty = RichTable(columns: [], rows: [], hasHeaderRow: true)
        let repaired = empty.repaired()
        XCTAssertEqual(repaired.rowCount, 1)
        XCTAssertEqual(repaired.columnCount, 1)
        XCTAssertEqual(repaired.validate(), [])
    }

    // MARK: - Geometry helpers

    func testSpanHelpers() throws {
        let table = try fixture()
        XCTAssertEqual(table.anchorAddress(of: addr(2, 2)), addr(1, 1))
        XCTAssertEqual(table.anchorAddress(of: addr(0, 2)), addr(0, 2))
        XCTAssertTrue(table.isCovered(addr(1, 2)))
        XCTAssertEqual(table.spanRect(ofAnchorAt: addr(1, 1)), rect(1...2, 1...2))
        XCTAssertEqual(table.spanRect(ofAnchorAt: addr(0, 0)), rect(0...0, 0...0))
        XCTAssertEqual(table.anchors(intersecting: rect(2...2, 0...2)), [addr(2, 0), addr(1, 1)])
        XCTAssertEqual(table.expandedToSpans(rect(2...2, 2...2)), rect(1...2, 1...2))
        XCTAssertEqual(table.expandedToSpans(rect(0...0, 0...1)), rect(0...0, 0...1))
        XCTAssertTrue(table.hasAnySpan)
        XCTAssertTrue(table.hasVerticalSpanInBody)
        XCTAssertEqual(table.bodyRowIndices, 1..<3)
        XCTAssertEqual(table.address(ofCellID: table[addr(2, 0)].id), addr(2, 0))
    }

    func testSelectionRects() {
        let table = grid([["a", "b", "c"], ["d", "e", "f"]])
        XCTAssertEqual(RichTableSelection.cell(addr(1, 2)).rect(in: table), rect(1...1, 2...2))
        XCTAssertEqual(RichTableSelection.rows(0...1).rect(in: table), rect(0...1, 0...2))
        XCTAssertEqual(RichTableSelection.columns(1...1).rect(in: table), rect(0...1, 1...1))
        XCTAssertEqual(RichTableSelection.table.rect(in: table), rect(0...1, 0...2))
        XCTAssertEqual(RichTableRect(addr(1, 2), addr(0, 0)), rect(0...1, 0...2), "corners normalise")
    }

    // MARK: - Markdown

    func testMarkdownHeaderSeparatorAndAlignmentMarkers() {
        var table = grid([["Name", "Qty", "Price"], ["Ash", "2", "$1"]])
        table.columns[1].alignment = .center
        table.columns[2].alignment = .trailing
        XCTAssertEqual(table.markdownLines(), [
            "| Name | Qty | Price |",
            "| --- | :---: | ---: |",
            "| Ash | 2 | $1 |",
        ])
        XCTAssertEqual(table.markdown, table.markdownLines().joined(separator: "\n"))
    }

    func testMarkdownWithoutHeaderEmitsEmptyHeaderLine() {
        let table = grid([["a", "b"]], header: false)
        XCTAssertEqual(table.markdownLines(), ["|  |  |", "| --- | --- |", "| a | b |"])
    }

    func testMarkdownEscapesPipesAndRendersSoftBreaksAndCoveredCells() throws {
        var table = grid([["a|b", "x\u{2028}y", "C"]], header: false)
        table = try RichTableOperations.mergeCells(in: table, rect: rect(0...0, 0...1)).table
        XCTAssertEqual(table.markdownLines()[2], "| a\\|b<br>x<br>y |  | C |")
        var newline = grid([["l1\nl2"]], header: false)
        newline[addr(0, 0)].inlines = [.text("l1\nl2")]
        XCTAssertEqual(newline.markdownLines()[2], "| l1<br>l2 |")
    }

    // MARK: - TSV

    func testTSVWholeTableAndRect() throws {
        var table = grid([["a", "b"], ["c\u{2028}d", "e\tf"], ["g", "h"]], header: false)
        XCTAssertEqual(table.tsv(), "a\tb\nc d\te f\ng\th")
        XCTAssertEqual(table.tsv(rect(1...2, 0...0)), "c d\ng")
        table = try RichTableOperations.mergeCells(in: table, rect: rect(2...2, 0...1)).table
        XCTAssertEqual(table.tsv(rect(2...2, 0...1)), "g h\t")
    }

    // MARK: - Widths

    func testResolvedColumnWidthsFollowWeights() {
        var table = grid([["a", "b"]])
        table.columns[1].weight = 3
        XCTAssertEqual(table.resolvedColumnWidths(available: 400), [100, 300])
    }

    func testResolvedColumnWidthsLiftFlooredColumns() {
        var table = grid([["a", "b"]])
        table.columns[1].weight = 9
        let widths = table.resolvedColumnWidths(available: 400)
        XCTAssertEqual(widths[0], RichTable.minimumColumnWidth)
        XCTAssertEqual(widths[1], 328, accuracy: 1e-9)
        XCTAssertEqual(widths.reduce(0, +), 400, accuracy: 1e-9)
    }

    func testResolvedColumnWidthsOverflowWhenFloorCannotBeMet() {
        let table = grid([["a", "b", "c"]])
        let widths = table.resolvedColumnWidths(available: 100)
        XCTAssertEqual(widths, [72, 72, 72])
        XCTAssertGreaterThan(widths.reduce(0, +), 100)
        XCTAssertEqual(table.resolvedColumnWidths(available: 300, minimum: 50), [100, 100, 100])
    }

    // MARK: - Passthrough

    func testUnknownBlockKeySurvivesDecodeEncode() throws {
        let table = grid([["h"], ["x"]])
        var object = try json(RichBlock.table(table))
        XCTAssertEqual(object["kind"] as? String, "table")
        object["futureField"] = ["x": 1]
        let data = try JSONSerialization.data(withJSONObject: object)
        let block = try JSONDecoder().decode(RichBlock.self, from: data)
        XCTAssertEqual(block.kind, .table)
        XCTAssertEqual(block.table, table)
        XCTAssertEqual(block.passthrough["futureField"], .object(["x": .number(1)]))
        let reencoded = try json(block)
        let future = try XCTUnwrap(reencoded["futureField"] as? [String: Any])
        XCTAssertEqual(future["x"] as? Double, 1)
        XCTAssertEqual(reencoded["kind"] as? String, "table")
        XCTAssertNotNil(reencoded["table"])
    }

    func testUnknownInlineKeySurvivesAndUnknownMarkIsDropped() throws {
        let raw = """
        {"kind":"text","text":"hi","marks":["bold","sparkle"],"glow":{"level":2,"on":true}}
        """
        let node = try JSONDecoder().decode(RichInlineNode.self, from: Data(raw.utf8))
        XCTAssertEqual(node.text, "hi")
        XCTAssertEqual(node.marks, [.bold])
        XCTAssertEqual(node.passthrough["glow"], .object(["level": .number(2), "on": .bool(true)]))
        let reencoded = try json(node)
        XCTAssertEqual(reencoded["marks"] as? [String], ["bold"])
        let glow = try XCTUnwrap(reencoded["glow"] as? [String: Any])
        XCTAssertEqual(glow["level"] as? Double, 2)
        XCTAssertEqual(glow["on"] as? Bool, true)
    }

    func testUnknownMarkInsideTableCellDoesNotThrow() throws {
        let raw = """
        {"columns":[{}],"rows":[{"cells":[{"inlines":[{"kind":"text","text":"x","marks":["sparkle"]}],"future":[1,2]}]}],"tableFuture":null}
        """
        let table = try JSONDecoder().decode(RichTable.self, from: Data(raw.utf8))
        XCTAssertEqual(text(table, 0, 0), "x")
        XCTAssertEqual(table[addr(0, 0)].inlines.first?.marks, [])
        XCTAssertEqual(table[addr(0, 0)].passthrough["future"], .array([.number(1), .number(2)]))
        XCTAssertEqual(table.passthrough["tableFuture"], .null)
        let reencoded = try json(table)
        XCTAssertTrue(reencoded.keys.contains("tableFuture"))
        let rows = try XCTUnwrap(reencoded["rows"] as? [[String: Any]])
        let cells = try XCTUnwrap(rows[0]["cells"] as? [[String: Any]])
        XCTAssertEqual(cells[0]["future"] as? [Double], [1, 2])
    }
}
