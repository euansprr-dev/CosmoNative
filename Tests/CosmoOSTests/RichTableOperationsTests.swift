import XCTest
@testable import CosmoOS

/// The pure table engine. Every operation's happy path, every thrown
/// error, the span growth/shrink/re-anchor rules, sorting, fill, resize,
/// transpose, block conversion, navigation, and a seeded 500-step fuzz that
/// asserts the grid law after every step.
final class RichTableOperationsTests: XCTestCase {

    private typealias Ops = RichTableOperations

    // MARK: - Helpers

    private func addr(_ row: Int, _ column: Int) -> RichTableCellAddress {
        RichTableCellAddress(row: row, column: column)
    }

    private func rect(_ rows: ClosedRange<Int>, _ columns: ClosedRange<Int>) -> RichTableRect {
        RichTableRect(rows: rows, columns: columns)
    }

    /// A grid whose cell (r, c) reads "r{r}c{c}".
    private func numbered(rows: Int, columns: Int, header: Bool = false) -> RichTable {
        RichTable(
            strings: (0..<rows).map { r in (0..<columns).map { c in "r\(r)c\(c)" } },
            hasHeaderRow: header
        )
    }

    private func grid(_ strings: [[String]], header: Bool = false) -> RichTable {
        RichTable(strings: strings, hasHeaderRow: header)
    }

    private func cell(_ table: RichTable, _ row: Int, _ column: Int) -> RichTableCell {
        table[addr(row, column)]
    }

    private func text(_ table: RichTable, _ row: Int, _ column: Int) -> String {
        cell(table, row, column).plainText
    }

    /// Plain text of every position; covered positions read "#".
    private func plain(_ table: RichTable) -> [[String]] {
        table.rows.map { row in row.cells.map { $0.isCovered ? "#" : $0.plainText } }
    }

    private func column(_ table: RichTable, _ index: Int) -> [String] {
        table.rows.map { $0.cells[index].isCovered ? "#" : $0.cells[index].plainText }
    }

    private func merged(_ table: RichTable, _ rows: ClosedRange<Int>, _ columns: ClosedRange<Int>) throws -> RichTable {
        try Ops.mergeCells(in: table, rect: rect(rows, columns)).table
    }

    private func assertValid(_ table: RichTable, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(table.validate(), [], file: file, line: line)
    }

    private func assertThrows<T>(
        _ expected: RichTableError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> T
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? RichTableError, expected, file: file, line: line)
        }
    }

    // MARK: - Insert row

    func testInsertRowAppendsAndFocusesFirstCell() throws {
        let table = numbered(rows: 2, columns: 3)
        let result = try Ops.insertRow(in: table, at: 2)
        XCTAssertEqual(result.table.rowCount, 3)
        XCTAssertEqual(plain(result.table)[2], ["", "", ""])
        XCTAssertEqual(result.focus, addr(2, 0))
        XCTAssertEqual(result.selection, .cell(addr(2, 0)))
        assertValid(result.table)
    }

    func testInsertRowAtTopOfHeaderTableMakesNewHeader() throws {
        let table = numbered(rows: 2, columns: 2, header: true)
        let result = try Ops.insertRow(in: table, at: 0)
        XCTAssertEqual(plain(result.table), [["", ""], ["r0c0", "r0c1"], ["r1c0", "r1c1"]])
        XCTAssertTrue(result.table.hasHeaderRow)
        assertValid(result.table)
    }

    func testInsertRowInsideVerticalSpanGrowsIt() throws {
        var table = numbered(rows: 4, columns: 3)
        table = try merged(table, 1...2, 0...0)
        let anchorID = cell(table, 1, 0).id
        let result = try Ops.insertRow(in: table, at: 2)
        let grown = result.table
        XCTAssertEqual(grown.rowCount, 5)
        XCTAssertEqual(cell(grown, 1, 0).rowSpan, 3)
        XCTAssertEqual(cell(grown, 2, 0).coveredBy, anchorID)
        XCTAssertEqual(cell(grown, 3, 0).coveredBy, anchorID)
        XCTAssertFalse(cell(grown, 2, 1).isCovered)
        XCTAssertEqual(plain(grown)[2], ["#", "", ""])
        XCTAssertEqual(plain(grown)[4], ["r3c0", "r3c1", "r3c2"])
        XCTAssertEqual(result.focus, addr(2, 1), "focus skips the covered position")
        assertValid(grown)
    }

    func testInsertRowAtSpanAnchorRowDoesNotGrow() throws {
        var table = numbered(rows: 4, columns: 2)
        table = try merged(table, 1...2, 0...0)
        let result = try Ops.insertRow(in: table, at: 1)
        XCTAssertEqual(cell(result.table, 2, 0).rowSpan, 2)
        XCTAssertEqual(plain(result.table)[1], ["", ""])
        XCTAssertEqual(result.focus, addr(1, 0))
        assertValid(result.table)
    }

    func testInsertRowBelowSpanDoesNotGrow() throws {
        var table = numbered(rows: 4, columns: 2)
        table = try merged(table, 1...2, 0...0)
        let result = try Ops.insertRow(in: table, at: 3)
        XCTAssertEqual(cell(result.table, 1, 0).rowSpan, 2)
        XCTAssertEqual(plain(result.table)[3], ["", ""])
        assertValid(result.table)
    }

    func testInsertRowCopiesStyleOfRow() throws {
        var table = numbered(rows: 2, columns: 2)
        table = try Ops.setTone(in: table, range: rect(0...0, 0...1), toneID: "moss")
        table = try Ops.setAlignment(in: table, range: rect(0...0, 1...1), alignment: .trailing)
        let result = try Ops.insertRow(in: table, at: 1, copyingStyleOfRow: 0)
        XCTAssertEqual(cell(result.table, 1, 0).toneID, "moss")
        XCTAssertEqual(cell(result.table, 1, 1).toneID, "moss")
        XCTAssertEqual(cell(result.table, 1, 1).alignment, .trailing)
        XCTAssertNil(cell(result.table, 1, 0).alignment)
        XCTAssertEqual(plain(result.table)[1], ["", ""])
        assertValid(result.table)
    }

    func testInsertRowOutOfBounds() {
        let table = numbered(rows: 2, columns: 2)
        assertThrows(.outOfBounds) { try Ops.insertRow(in: table, at: 3) }
        assertThrows(.outOfBounds) { try Ops.insertRow(in: table, at: -1) }
        assertThrows(.outOfBounds) { try Ops.insertRow(in: table, at: 1, copyingStyleOfRow: 5) }
    }

    // MARK: - Insert column

    func testInsertColumnAveragesNeighbourWeights() throws {
        var table = numbered(rows: 2, columns: 2)
        table.columns[0].weight = 1
        table.columns[1].weight = 3
        let middle = try Ops.insertColumn(in: table, at: 1).table
        XCTAssertEqual(middle.columns.map(\.weight), [1, 2, 3])
        XCTAssertEqual(plain(middle), [["r0c0", "", "r0c1"], ["r1c0", "", "r1c1"]])
        let leading = try Ops.insertColumn(in: table, at: 0).table
        XCTAssertEqual(leading.columns.map(\.weight), [1, 1, 3])
        let trailing = try Ops.insertColumn(in: table, at: 2).table
        XCTAssertEqual(trailing.columns.map(\.weight), [1, 3, 3])
        assertValid(middle)
        assertValid(leading)
        assertValid(trailing)
    }

    func testInsertColumnFocusesFirstVisibleCellOfNewColumn() throws {
        let table = numbered(rows: 2, columns: 2)
        let result = try Ops.insertColumn(in: table, at: 1)
        XCTAssertEqual(result.focus, addr(0, 1))
        XCTAssertEqual(result.selection, .cell(addr(0, 1)))
    }

    func testInsertColumnInsideHorizontalSpanGrowsIt() throws {
        var table = numbered(rows: 2, columns: 3)
        table = try merged(table, 0...0, 0...1)
        let anchorID = cell(table, 0, 0).id
        let result = try Ops.insertColumn(in: table, at: 1)
        let grown = result.table
        XCTAssertEqual(grown.columnCount, 4)
        XCTAssertEqual(cell(grown, 0, 0).colSpan, 3)
        XCTAssertEqual(cell(grown, 0, 1).coveredBy, anchorID)
        XCTAssertEqual(cell(grown, 0, 2).coveredBy, anchorID)
        XCTAssertFalse(cell(grown, 1, 1).isCovered)
        XCTAssertEqual(plain(grown)[1], ["r1c0", "", "r1c1", "r1c2"])
        XCTAssertEqual(result.focus, addr(1, 1))
        assertValid(grown)
    }

    func testInsertColumnOutOfBounds() {
        let table = numbered(rows: 2, columns: 2)
        assertThrows(.outOfBounds) { try Ops.insertColumn(in: table, at: 3) }
        assertThrows(.outOfBounds) { try Ops.insertColumn(in: table, at: -1) }
    }

    // MARK: - Delete row

    func testDeleteRowRemovesPlainRow() throws {
        let table = numbered(rows: 3, columns: 2)
        let result = try Ops.deleteRow(in: table, at: 1)
        XCTAssertEqual(plain(result), [["r0c0", "r0c1"], ["r2c0", "r2c1"]])
        assertValid(result)
    }

    func testDeleteRowShrinksSpanFromBelow() throws {
        var table = numbered(rows: 4, columns: 2)
        table = try merged(table, 1...2, 0...0)
        let result = try Ops.deleteRow(in: table, at: 2)
        XCTAssertEqual(result.rowCount, 3)
        XCTAssertEqual(cell(result, 1, 0).rowSpan, 1)
        XCTAssertFalse(cell(result, 1, 0).isSpanAnchor)
        XCTAssertEqual(text(result, 1, 0), "r1c0\u{2028}r2c0")
        XCTAssertEqual(plain(result)[2], ["r3c0", "r3c1"])
        assertValid(result)
    }

    func testDeleteRowWithAnchorMovesTextToNewTopLeft() throws {
        var table = numbered(rows: 4, columns: 2)
        table = try merged(table, 1...3, 0...0)
        let anchorID = cell(table, 1, 0).id
        let result = try Ops.deleteRow(in: table, at: 1)
        XCTAssertEqual(result.rowCount, 3)
        XCTAssertEqual(cell(result, 1, 0).id, anchorID)
        XCTAssertEqual(text(result, 1, 0), "r1c0\u{2028}r2c0\u{2028}r3c0")
        XCTAssertEqual(cell(result, 1, 0).rowSpan, 2)
        XCTAssertEqual(cell(result, 2, 0).coveredBy, anchorID)
        XCTAssertEqual(text(result, 1, 1), "r2c1")
        assertValid(result)
    }

    func testDeleteRowDissolvesHorizontalSpanLivingInIt() throws {
        var table = numbered(rows: 3, columns: 3)
        table = try merged(table, 1...1, 0...2)
        let result = try Ops.deleteRow(in: table, at: 1)
        XCTAssertFalse(result.hasAnySpan)
        XCTAssertEqual(plain(result), [["r0c0", "r0c1", "r0c2"], ["r2c0", "r2c1", "r2c2"]])
        assertValid(result)
    }

    func testDeleteRowWithTwoDimensionalSpanAnchorReanchors() throws {
        var table = numbered(rows: 3, columns: 3)
        table = try merged(table, 1...2, 0...1)
        let anchorID = cell(table, 1, 0).id
        let result = try Ops.deleteRow(in: table, at: 1)
        XCTAssertEqual(cell(result, 1, 0).id, anchorID)
        XCTAssertEqual(cell(result, 1, 0).rowSpan, 1)
        XCTAssertEqual(cell(result, 1, 0).colSpan, 2)
        XCTAssertEqual(cell(result, 1, 1).coveredBy, anchorID)
        XCTAssertEqual(text(result, 1, 2), "r2c2")
        assertValid(result)
    }

    func testDeleteHeaderRowTrimsPromotedVerticalSpan() throws {
        var table = numbered(rows: 4, columns: 2, header: true)
        table = try merged(table, 1...2, 0...0)
        let result = try Ops.deleteRow(in: table, at: 0)
        XCTAssertTrue(result.hasHeaderRow)
        XCTAssertEqual(result.rowCount, 3)
        XCTAssertEqual(cell(result, 0, 0).rowSpan, 1)
        XCTAssertEqual(text(result, 0, 0), "r1c0\u{2028}r2c0")
        XCTAssertFalse(cell(result, 1, 0).isCovered)
        XCTAssertEqual(text(result, 1, 0), "")
        assertValid(result)
    }

    func testDeleteLastRowThrows() {
        let one = numbered(rows: 1, columns: 3)
        assertThrows(.cannotDeleteLastLine) { try Ops.deleteRow(in: one, at: 0) }
        assertThrows(.outOfBounds) { try Ops.deleteRow(in: numbered(rows: 2, columns: 2), at: 2) }
    }

    // MARK: - Delete column

    func testDeleteColumnShrinksSpanFromRight() throws {
        var table = numbered(rows: 2, columns: 4)
        table = try merged(table, 0...0, 1...2)
        let result = try Ops.deleteColumn(in: table, at: 2)
        XCTAssertEqual(result.columnCount, 3)
        XCTAssertEqual(cell(result, 0, 1).colSpan, 1)
        XCTAssertEqual(plain(result), [["r0c0", "r0c1\u{2028}r0c2", "r0c3"], ["r1c0", "r1c1", "r1c3"]])
        assertValid(result)
    }

    func testDeleteColumnWithAnchorMovesTextRight() throws {
        var table = numbered(rows: 2, columns: 3)
        table = try merged(table, 0...0, 0...1)
        let anchorID = cell(table, 0, 0).id
        let result = try Ops.deleteColumn(in: table, at: 0)
        XCTAssertEqual(result.columnCount, 2)
        XCTAssertEqual(cell(result, 0, 0).id, anchorID)
        XCTAssertEqual(text(result, 0, 0), "r0c0\u{2028}r0c1")
        XCTAssertEqual(cell(result, 0, 0).colSpan, 1)
        XCTAssertEqual(plain(result)[1], ["r1c1", "r1c2"])
        assertValid(result)
    }

    func testDeleteColumnDissolvesVerticalSpanLivingInIt() throws {
        var table = numbered(rows: 3, columns: 2)
        table = try merged(table, 0...2, 1...1)
        let result = try Ops.deleteColumn(in: table, at: 1)
        XCTAssertFalse(result.hasAnySpan)
        XCTAssertEqual(column(result, 0), ["r0c0", "r1c0", "r2c0"])
        assertValid(result)
    }

    func testDeleteLastColumnThrows() {
        let one = numbered(rows: 3, columns: 1)
        assertThrows(.cannotDeleteLastLine) { try Ops.deleteColumn(in: one, at: 0) }
        assertThrows(.outOfBounds) { try Ops.deleteColumn(in: numbered(rows: 2, columns: 2), at: -1) }
    }

    // MARK: - Move row

    func testMoveRowReordersWithStableIDs() throws {
        let table = grid([["a"], ["b"], ["c"], ["d"]])
        let ids = Set(table.rows.map(\.id))
        let down = try Ops.moveRow(in: table, from: 0, to: 2)
        XCTAssertEqual(column(down, 0), ["b", "c", "a", "d"])
        let up = try Ops.moveRow(in: table, from: 3, to: 1)
        XCTAssertEqual(column(up, 0), ["a", "d", "b", "c"])
        XCTAssertEqual(Set(down.rows.map(\.id)), ids)
        XCTAssertEqual(try Ops.moveRow(in: table, from: 2, to: 2), table)
        assertValid(down)
        assertValid(up)
    }

    func testMoveRowBlockedWhenSourceInsideSpan() throws {
        var table = grid([["a"], ["b"], ["c"], ["d"]])
        table = try merged(table, 1...2, 0...0)
        assertThrows(.wouldBreakSpan) { try Ops.moveRow(in: table, from: 1, to: 3) }
        assertThrows(.wouldBreakSpan) { try Ops.moveRow(in: table, from: 2, to: 0) }
    }

    func testMoveRowBlockedWhenDestinationCutsSpan() throws {
        var table = grid([["a"], ["b"], ["c"], ["d"]])
        table = try merged(table, 1...2, 0...0)
        assertThrows(.wouldBreakSpan) { try Ops.moveRow(in: table, from: 0, to: 1) }
        assertThrows(.wouldBreakSpan) { try Ops.moveRow(in: table, from: 3, to: 2) }
        let past = try Ops.moveRow(in: table, from: 3, to: 0)
        XCTAssertEqual(column(past, 0), ["d", "a", "b\u{2028}c", "#"])
        XCTAssertEqual(cell(past, 2, 0).rowSpan, 2)
        let under = try Ops.moveRow(in: table, from: 0, to: 2)
        XCTAssertEqual(column(under, 0), ["b\u{2028}c", "#", "a", "d"])
        assertValid(past)
        assertValid(under)
    }

    func testMoveRowRefusesHeader() {
        let table = numbered(rows: 3, columns: 1, header: true)
        assertThrows(.cannotMoveHeaderRow) { try Ops.moveRow(in: table, from: 0, to: 1) }
        assertThrows(.cannotMoveHeaderRow) { try Ops.moveRow(in: table, from: 2, to: 0) }
        assertThrows(.outOfBounds) { try Ops.moveRow(in: table, from: 1, to: 3) }
    }

    // MARK: - Move column

    func testMoveColumnReordersCellsAndColumnRecords() throws {
        var table = grid([["a", "b", "c", "d"]])
        table.columns[0].weight = 4
        let moved = try Ops.moveColumn(in: table, from: 0, to: 3)
        XCTAssertEqual(plain(moved)[0], ["b", "c", "d", "a"])
        XCTAssertEqual(moved.columns.map(\.weight), [1, 1, 1, 4])
        let back = try Ops.moveColumn(in: table, from: 3, to: 1)
        XCTAssertEqual(plain(back)[0], ["a", "d", "b", "c"])
        assertValid(moved)
        assertValid(back)
    }

    func testMoveColumnBlockedBySpan() throws {
        var table = grid([["a", "b", "c", "d"], ["e", "f", "g", "h"]])
        table = try merged(table, 0...0, 1...2)
        assertThrows(.wouldBreakSpan) { try Ops.moveColumn(in: table, from: 0, to: 1) }
        assertThrows(.wouldBreakSpan) { try Ops.moveColumn(in: table, from: 2, to: 0) }
        let past = try Ops.moveColumn(in: table, from: 0, to: 3)
        XCTAssertEqual(plain(past)[0], ["b\u{2028}c", "#", "d", "a"])
        assertValid(past)
        assertThrows(.outOfBounds) { try Ops.moveColumn(in: table, from: 4, to: 0) }
    }

    // MARK: - Merge

    func testMergeJoinsTextWithSoftBreaks() throws {
        let table = grid([["A", "B"], ["C", ""]])
        let result = try Ops.mergeCells(in: table, rect: rect(0...1, 0...1))
        let merged = result.table
        XCTAssertEqual(text(merged, 0, 0), "A\u{2028}B\u{2028}C")
        XCTAssertEqual(cell(merged, 0, 0).rowSpan, 2)
        XCTAssertEqual(cell(merged, 0, 0).colSpan, 2)
        let anchorID = cell(merged, 0, 0).id
        for address in [addr(0, 1), addr(1, 0), addr(1, 1)] {
            XCTAssertEqual(merged[address].coveredBy, anchorID)
            XCTAssertTrue(merged[address].inlines.isEmpty)
        }
        XCTAssertEqual(result.focus, addr(0, 0))
        XCTAssertEqual(result.selection, .cell(addr(0, 0)))
        assertValid(merged)
    }

    func testMergeKeepsAnchorToneAndCoveredIDs() throws {
        var table = grid([["A", "B"]])
        table = try Ops.setTone(in: table, range: rect(0...0, 0...0), toneID: "moss")
        table = try Ops.setTone(in: table, range: rect(0...0, 1...1), toneID: "rust")
        let coveredID = cell(table, 0, 1).id
        let merged = try self.merged(table, 0...0, 0...1)
        XCTAssertEqual(cell(merged, 0, 0).toneID, "moss")
        XCTAssertNil(cell(merged, 0, 1).toneID)
        XCTAssertEqual(cell(merged, 0, 1).id, coveredID)
    }

    func testMergeWithEmptyAnchorStartsWithFirstNonEmptyText() throws {
        let table = grid([["", "B"], ["C", "D"]])
        let merged = try self.merged(table, 0...1, 0...1)
        XCTAssertEqual(text(merged, 0, 0), "B\u{2028}C\u{2028}D")
    }

    func testMergePreservesInlineRuns() throws {
        var table = grid([["", ""]])
        table[addr(0, 0)].inlines = [.text("bold", marks: [.bold])]
        table[addr(0, 1)].inlines = [.text("plain")]
        let merged = try self.merged(table, 0...0, 0...1)
        let nodes = cell(merged, 0, 0).inlines
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].marks, [.bold])
        XCTAssertEqual(nodes[1].text, "\u{2028}plain")
    }

    func testMergeRejectsSingleCellAndOutOfBounds() {
        let table = numbered(rows: 2, columns: 2)
        assertThrows(.invalidRange) { try Ops.mergeCells(in: table, rect: rect(0...0, 0...0)) }
        assertThrows(.outOfBounds) { try Ops.mergeCells(in: table, rect: rect(0...2, 0...0)) }
        assertThrows(.outOfBounds) { try Ops.mergeCells(in: table, rect: rect(0...0, 1...2)) }
    }

    func testMergeRejectsHeaderCrossingButAllowsHeaderWideMerge() throws {
        let table = numbered(rows: 3, columns: 2, header: true)
        assertThrows(.spanCrossesHeader) { try Ops.mergeCells(in: table, rect: rect(0...1, 0...0)) }
        let wide = try merged(table, 0...0, 0...1)
        XCTAssertEqual(cell(wide, 0, 0).colSpan, 2)
        assertValid(wide)
        let body = try merged(table, 1...2, 0...1)
        XCTAssertEqual(cell(body, 1, 0).rowSpan, 2)
        assertValid(body)
    }

    func testMergeRejectsPartialSpanAndAbsorbsWholeSpan() throws {
        var table = numbered(rows: 3, columns: 3)
        table = try merged(table, 1...2, 0...0)
        assertThrows(.invalidRange) { try Ops.mergeCells(in: table, rect: rect(1...1, 0...1)) }
        assertThrows(.invalidRange) { try Ops.mergeCells(in: table, rect: rect(0...1, 0...0)) }
        let absorbed = try merged(table, 1...2, 0...1)
        XCTAssertEqual(text(absorbed, 1, 0), "r1c0\u{2028}r2c0\u{2028}r1c1\u{2028}r2c1")
        XCTAssertEqual(cell(absorbed, 1, 0).rowSpan, 2)
        XCTAssertEqual(cell(absorbed, 1, 0).colSpan, 2)
        XCTAssertEqual(plain(absorbed)[2], ["#", "#", "r2c2"])
        assertValid(absorbed)
    }

    // MARK: - Unmerge

    func testUnmergeRestoresCells() throws {
        let table = numbered(rows: 2, columns: 2)
        let ids = table.rows.flatMap { $0.cells.map(\.id) }
        let merged = try self.merged(table, 0...1, 0...1)
        let result = try Ops.unmergeCell(in: merged, anchor: addr(0, 0))
        let restored = result.table
        XCTAssertFalse(restored.hasAnySpan)
        XCTAssertEqual(text(restored, 0, 0), "r0c0\u{2028}r0c1\u{2028}r1c0\u{2028}r1c1")
        XCTAssertEqual(plain(restored)[1], ["", ""])
        XCTAssertEqual(restored.rows.flatMap { $0.cells.map(\.id) }, ids)
        XCTAssertEqual(result.focus, addr(0, 0))
        XCTAssertEqual(result.selection, .range(rect(0...1, 0...1)))
        assertValid(restored)
    }

    func testUnmergeRejectsPlainAndCoveredCells() throws {
        let table = try merged(numbered(rows: 2, columns: 2), 0...0, 0...1)
        assertThrows(.notMerged) { try Ops.unmergeCell(in: table, anchor: addr(1, 0)) }
        assertThrows(.notMerged) { try Ops.unmergeCell(in: table, anchor: addr(0, 1)) }
        assertThrows(.outOfBounds) { try Ops.unmergeCell(in: table, anchor: addr(2, 0)) }
    }

    // MARK: - Sort

    func testSortNumericPinsHeader() throws {
        let table = grid([["n"], ["10"], ["9"], ["100"]], header: true)
        let ascending = try Ops.sortRows(in: table, byColumn: 0, ascending: true)
        XCTAssertEqual(column(ascending, 0), ["n", "9", "10", "100"])
        let descending = try Ops.sortRows(in: table, byColumn: 0, ascending: false)
        XCTAssertEqual(column(descending, 0), ["n", "100", "10", "9"])
        assertValid(ascending)
    }

    func testSortAlphaUsesLocalizedStandardCompare() throws {
        let table = grid([["b"], ["file10"], ["a"], ["file9"]])
        let ascending = try Ops.sortRows(in: table, byColumn: 0, ascending: true)
        XCTAssertEqual(column(ascending, 0), ["a", "b", "file9", "file10"])
        let descending = try Ops.sortRows(in: table, byColumn: 0, ascending: false)
        XCTAssertEqual(column(descending, 0), ["file10", "file9", "b", "a"])
    }

    func testSortEmptiesLastInBothDirections() throws {
        let table = grid([[""], ["b"], ["a"], ["  "]])
        XCTAssertEqual(column(try Ops.sortRows(in: table, byColumn: 0, ascending: true), 0), ["a", "b", "", "  "])
        XCTAssertEqual(column(try Ops.sortRows(in: table, byColumn: 0, ascending: false), 0), ["b", "a", "", "  "])
    }

    func testSortIsStableAndKeepsRowIDs() throws {
        let table = grid([["1", "x"], ["1", "y"], ["0", "z"], ["1", "w"]])
        let ids = table.rows.map(\.id)
        let ascending = try Ops.sortRows(in: table, byColumn: 0, ascending: true)
        XCTAssertEqual(column(ascending, 1), ["z", "x", "y", "w"])
        XCTAssertEqual(ascending.rows.map(\.id), [ids[2], ids[0], ids[1], ids[3]])
        let descending = try Ops.sortRows(in: table, byColumn: 0, ascending: false)
        XCTAssertEqual(column(descending, 1), ["x", "y", "w", "z"])
    }

    func testSortStripsThousandsAndCurrency() throws {
        let table = grid([["$1,200"], ["$900"], ["€50"], ["1 000"]])
        let ascending = try Ops.sortRows(in: table, byColumn: 0, ascending: true)
        XCTAssertEqual(column(ascending, 0), ["€50", "$900", "1 000", "$1,200"])
    }

    func testSortPutsNumbersBeforeText() throws {
        let table = grid([["b"], ["2"], ["a"], ["10"], ["1e1"], ["inf"]])
        let ascending = try Ops.sortRows(in: table, byColumn: 0, ascending: true)
        XCTAssertEqual(column(ascending, 0), ["2", "10", "1e1", "a", "b", "inf"])
        let descending = try Ops.sortRows(in: table, byColumn: 0, ascending: false)
        XCTAssertEqual(column(descending, 0), ["inf", "b", "a", "10", "1e1", "2"])
    }

    func testSortComparesAnchorTextForCoveredCells() throws {
        var table = grid([["b", "x"], ["a", "y"], ["c", "z"]])
        for row in 0..<3 { table = try merged(table, row...row, 0...1) }
        let sorted = try Ops.sortRows(in: table, byColumn: 1, ascending: true)
        XCTAssertEqual(column(sorted, 0), ["a\u{2028}y", "b\u{2028}x", "c\u{2028}z"])
        assertValid(sorted)
    }

    func testSortRejectsVerticalSpansAndBadColumn() throws {
        var table = numbered(rows: 4, columns: 2, header: true)
        assertThrows(.outOfBounds) { try Ops.sortRows(in: table, byColumn: 2, ascending: true) }
        table = try merged(table, 1...2, 0...0)
        assertThrows(.cannotSortWithVerticalSpans) { try Ops.sortRows(in: table, byColumn: 1, ascending: true) }
    }

    // MARK: - Widths

    func testDistributeColumns() {
        var table = numbered(rows: 1, columns: 3)
        table.columns[1].weight = 3
        table.columns[2].weight = 5
        XCTAssertEqual(Ops.distributeColumns(in: table).columns.map(\.weight), [1, 1, 1])
    }

    func testSetColumnWeightClampsToMinimumShare() throws {
        let table = numbered(rows: 1, columns: 2)
        let squeezed = try Ops.setColumnWeight(in: table, index: 0, weight: 0.01)
        let total = squeezed.columns.reduce(0) { $0 + $1.weight }
        XCTAssertEqual(squeezed.columns[0].weight / total, 0.08, accuracy: 1e-9)
        let wide = try Ops.setColumnWeight(in: table, index: 0, weight: 4)
        XCTAssertEqual(wide.columns[0].weight, 4)
        XCTAssertEqual(try Ops.setColumnWeight(in: table, index: 1, weight: .nan), table)
        assertThrows(.outOfBounds) { try Ops.setColumnWeight(in: table, index: 2, weight: 1) }
    }

    func testResizeColumnPairMovesWeightAndClamps() throws {
        let table = numbered(rows: 1, columns: 3)
        let right = try Ops.resizeColumnPair(in: table, left: 0, delta: 0.1)
        XCTAssertEqual(right.columns[0].weight, 1.3, accuracy: 1e-9)
        XCTAssertEqual(right.columns[1].weight, 0.7, accuracy: 1e-9)
        XCTAssertEqual(right.columns[2].weight, 1)
        let left = try Ops.resizeColumnPair(in: table, left: 0, delta: -0.5)
        XCTAssertEqual(left.columns[0].weight, 0.24, accuracy: 1e-9)
        XCTAssertEqual(left.columns[1].weight, 1.76, accuracy: 1e-9)
        XCTAssertEqual(left.columns.reduce(0) { $0 + $1.weight }, 3, accuracy: 1e-9)
        assertThrows(.outOfBounds) { try Ops.resizeColumnPair(in: table, left: 2, delta: 0.1) }
    }

    // MARK: - Appearance

    func testSetToneTouchesAnchorsOnly() throws {
        var table = try merged(numbered(rows: 2, columns: 2), 0...0, 0...1)
        table = try Ops.setTone(in: table, range: rect(0...1, 1...1), toneID: "moss")
        XCTAssertEqual(cell(table, 0, 0).toneID, "moss", "the covered position resolves to its anchor")
        XCTAssertNil(cell(table, 0, 1).toneID)
        XCTAssertEqual(cell(table, 1, 1).toneID, "moss")
        XCTAssertNil(cell(table, 1, 0).toneID)
        let cleared = try Ops.setTone(in: table, range: rect(0...1, 0...1), toneID: nil)
        XCTAssertTrue(cleared.rows.allSatisfy { $0.cells.allSatisfy { $0.toneID == nil } })
        assertThrows(.outOfBounds) { try Ops.setTone(in: table, range: rect(0...2, 0...0), toneID: "moss") }
    }

    func testSetAlignmentColumnClearsOverrides() throws {
        var table = numbered(rows: 2, columns: 2)
        table = try Ops.setAlignment(in: table, range: rect(0...1, 0...0), alignment: .trailing)
        XCTAssertEqual(cell(table, 1, 0).alignment, .trailing)
        table = try Ops.setAlignment(in: table, column: 0, alignment: .center)
        XCTAssertEqual(table.columns[0].alignment, .center)
        XCTAssertNil(cell(table, 0, 0).alignment)
        XCTAssertNil(cell(table, 1, 0).alignment)
        let cleared = try Ops.setAlignment(in: table, range: rect(0...0, 1...1), alignment: nil)
        XCTAssertNil(cell(cleared, 0, 1).alignment)
        assertThrows(.outOfBounds) { try Ops.setAlignment(in: table, column: 2, alignment: .center) }
    }

    func testSetVerticalAlignment() throws {
        var table = try merged(numbered(rows: 2, columns: 2), 0...1, 0...0)
        table = try Ops.setVerticalAlignment(in: table, range: rect(1...1, 0...1), alignment: .middle)
        XCTAssertEqual(cell(table, 0, 0).verticalAlignment, .middle)
        XCTAssertNil(cell(table, 1, 0).verticalAlignment)
        XCTAssertEqual(cell(table, 1, 1).verticalAlignment, .middle)
        XCTAssertNil(cell(table, 0, 1).verticalAlignment)
    }

    func testSetHeaderRowRejectsSpanAnchoredInRowZero() throws {
        var table = numbered(rows: 3, columns: 2)
        table = try merged(table, 0...1, 0...0)
        assertThrows(.spanCrossesHeader) { try Ops.setHeaderRow(in: table, enabled: true) }
        let unmerged = try Ops.unmergeCell(in: table, anchor: addr(0, 0)).table
        let header = try Ops.setHeaderRow(in: unmerged, enabled: true)
        XCTAssertTrue(header.hasHeaderRow)
        XCTAssertFalse(try Ops.setHeaderRow(in: header, enabled: false).hasHeaderRow)
        assertValid(header)
    }

    func testHeaderColumnStyleAndStripes() {
        let table = numbered(rows: 2, columns: 2)
        XCTAssertTrue(Ops.setHeaderColumn(in: table, enabled: true).hasHeaderColumn)
        XCTAssertEqual(Ops.setStyle(in: table, style: .clean).style, .clean)
        XCTAssertTrue(Ops.setStriped(in: table, isStriped: true).isStriped)
    }

    // MARK: - Content

    func testClearCellsKeepsToneAndSpan() throws {
        var table = try merged(numbered(rows: 2, columns: 2), 0...0, 0...1)
        table = try Ops.setTone(in: table, range: rect(0...0, 0...0), toneID: "moss")
        let cleared = try Ops.clearCells(in: table, range: rect(0...1, 1...1))
        XCTAssertTrue(cell(cleared, 0, 0).inlines.isEmpty)
        XCTAssertEqual(cell(cleared, 0, 0).toneID, "moss")
        XCTAssertEqual(cell(cleared, 0, 0).colSpan, 2)
        XCTAssertTrue(cell(cleared, 1, 1).inlines.isEmpty)
        XCTAssertEqual(text(cleared, 1, 0), "r1c0")
        assertValid(cleared)
    }

    private func inlineGrid(_ strings: [[String]]) -> [[[RichInlineNode]]] {
        strings.map { row in row.map { [.text($0)] } }
    }

    func testFillClipsWithoutExpand() throws {
        let table = numbered(rows: 2, columns: 2)
        let result = try Ops.fill(in: table, from: addr(1, 1), grid: inlineGrid([["a", "b"], ["c", "d"]]), expand: false)
        XCTAssertEqual(result.table.rowCount, 2)
        XCTAssertEqual(result.table.columnCount, 2)
        XCTAssertEqual(plain(result.table), [["r0c0", "r0c1"], ["r1c0", "a"]])
        XCTAssertEqual(result.selection, .range(rect(1...1, 1...1)))
        XCTAssertEqual(result.focus, addr(1, 1))
        assertValid(result.table)
    }

    func testFillExpandsRowsAndColumnsWithAverageWeight() throws {
        var table = numbered(rows: 2, columns: 2)
        table.columns[1].weight = 3
        let result = try Ops.fill(in: table, from: addr(1, 1), grid: inlineGrid([["a", "b"], ["c", "d"]]), expand: true)
        XCTAssertEqual(plain(result.table), [["r0c0", "r0c1", ""], ["r1c0", "a", "b"], ["", "c", "d"]])
        XCTAssertEqual(result.table.columns.map(\.weight), [1, 3, 2])
        XCTAssertEqual(result.selection, .range(rect(1...2, 1...2)))
        XCTAssertEqual(result.focus, addr(1, 1))
        assertValid(result.table)
    }

    func testFillWritesSpanAnchorsOnceAndPadsRaggedRows() throws {
        var table = numbered(rows: 3, columns: 3)
        table = try merged(table, 0...1, 0...1)
        let grid = inlineGrid([["A", "B", "C"], ["D"]])
        let result = try Ops.fill(in: table, from: addr(0, 0), grid: grid, expand: false)
        XCTAssertEqual(text(result.table, 0, 0), "A", "first write into the anchor wins")
        XCTAssertEqual(text(result.table, 0, 2), "C")
        XCTAssertEqual(text(result.table, 1, 2), "", "the ragged second row pads with an empty cell")
        XCTAssertEqual(plain(result.table)[2], ["r2c0", "r2c1", "r2c2"])
        XCTAssertEqual(result.selection, .range(rect(0...1, 0...2)))
        assertValid(result.table)
    }

    func testFillFromCoveredPositionFocusesAnchorAndEmptyGridIsNoOp() throws {
        let table = try merged(numbered(rows: 2, columns: 2), 0...0, 0...1)
        let result = try Ops.fill(in: table, from: addr(0, 1), grid: inlineGrid([["Z"]]), expand: false)
        XCTAssertEqual(text(result.table, 0, 0), "Z")
        XCTAssertEqual(result.focus, addr(0, 0))
        let empty = try Ops.fill(in: table, from: addr(1, 0), grid: [], expand: true)
        XCTAssertEqual(empty.table, table)
        assertThrows(.outOfBounds) { try Ops.fill(in: table, from: addr(2, 0), grid: inlineGrid([["a"]]), expand: true) }
    }

    func testResizeGrowsAndShrinks() {
        let table = numbered(rows: 2, columns: 2)
        let grown = Ops.resize(in: table, rows: 4, columns: 3)
        XCTAssertEqual(grown.rowCount, 4)
        XCTAssertEqual(grown.columnCount, 3)
        XCTAssertEqual(plain(grown)[0], ["r0c0", "r0c1", ""])
        XCTAssertEqual(plain(grown)[3], ["", "", ""])
        let shrunk = Ops.resize(in: grown, rows: 1, columns: 1)
        XCTAssertEqual(plain(shrunk), [["r0c0"]])
        let floor = Ops.resize(in: table, rows: 0, columns: -3)
        XCTAssertEqual(plain(floor), [["r0c0"]])
        assertValid(grown)
        assertValid(shrunk)
    }

    func testResizeShrinkDissolvesSpans() throws {
        var table = numbered(rows: 3, columns: 3)
        table = try merged(table, 1...2, 1...2)
        let shrunk = Ops.resize(in: table, rows: 2, columns: 2)
        XCTAssertFalse(shrunk.hasAnySpan)
        XCTAssertEqual(text(shrunk, 1, 1), "r1c1\u{2028}r1c2\u{2028}r2c1\u{2028}r2c2")
        assertValid(shrunk)
    }

    // MARK: - Transpose

    func testTransposeSwapsHeadersAndResetsAlignments() throws {
        var table = grid([["a", "b", "c"], ["d", "e", "f"]], header: true)
        table.columns[1].alignment = .center
        table.columns[2].weight = 3
        table = try Ops.setAlignment(in: table, range: rect(1...1, 0...0), alignment: .trailing)
        let rowIDs = table.rows.map(\.id)
        let columnIDs = table.columns.map(\.id)
        let transposed = try Ops.transpose(in: table)
        XCTAssertEqual(plain(transposed), [["a", "d"], ["b", "e"], ["c", "f"]])
        XCTAssertFalse(transposed.hasHeaderRow)
        XCTAssertTrue(transposed.hasHeaderColumn)
        XCTAssertEqual(transposed.columns.map(\.weight), [1, 1])
        XCTAssertTrue(transposed.columns.allSatisfy { $0.alignment == .leading })
        XCTAssertTrue(transposed.rows.allSatisfy { $0.cells.allSatisfy { $0.alignment == nil } })
        XCTAssertEqual(transposed.columns.map(\.id), rowIDs)
        XCTAssertEqual(transposed.rows.map(\.id), columnIDs)
        let twice = try Ops.transpose(in: transposed)
        XCTAssertEqual(plain(twice), plain(table))
        XCTAssertTrue(twice.hasHeaderRow)
        XCTAssertEqual(twice.rows.map(\.id), rowIDs)
        assertValid(transposed)
    }

    func testTransposeRejectsSpans() throws {
        let table = try merged(numbered(rows: 2, columns: 2), 0...0, 0...1)
        assertThrows(.wouldBreakSpan) { try Ops.transpose(in: table) }
    }

    // MARK: - Blocks

    func testBlocksToTableSplitsOnTabsFirst() {
        let table = Ops.blocksToTable([.paragraph("a\tb, c"), .paragraph("d\te, f")])
        XCTAssertEqual(plain(table), [["a", "b, c"], ["d", "e, f"]])
        XCTAssertTrue(table.hasHeaderRow)
        assertValid(table)
    }

    func testBlocksToTableSplitsOnPipesToleratingOuterPipes() {
        let table = Ops.blocksToTable([.paragraph("| a | b |"), .paragraph("c | d")])
        XCTAssertEqual(plain(table), [["a", "b"], ["c", "d"]])
    }

    func testBlocksToTableSplitsOnCommaSpace() {
        let table = Ops.blocksToTable([.paragraph("a, b, c"), .paragraph("d, e, f")])
        XCTAssertEqual(plain(table), [["a", "b", "c"], ["d", "e", "f"]])
        XCTAssertEqual(table.columnCount, 3)
    }

    func testBlocksToTableFallsBackToOneColumnKeepingRuns() {
        let block = RichBlock(kind: .bulletList, inlines: [.text("bold", marks: [.bold]), .text(" a, b")])
        let table = Ops.blocksToTable([block, .paragraph("c\td\te")])
        XCTAssertEqual(table.columnCount, 1)
        XCTAssertEqual(column(table, 0), ["bold a, b", "c\td\te"])
        XCTAssertEqual(cell(table, 0, 0).inlines.first?.marks, [.bold])
        let single = Ops.blocksToTable([.paragraph("just text")])
        XCTAssertFalse(single.hasHeaderRow)
        XCTAssertEqual(plain(single), [["just text"]])
        let none = Ops.blocksToTable([])
        XCTAssertEqual(plain(none), [[""]])
        assertValid(none)
    }

    func testTableToBlocksJoinsWithTabsAndSkipsCovered() throws {
        var table = grid([["a", "b", "c"], ["d", "e", "f"]])
        table[addr(0, 1)].inlines = [.text("b", marks: [.italic])]
        table = try merged(table, 1...1, 0...1)
        let blocks = Ops.tableToBlocks(table)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(blocks.map(\.plainInlineText), ["a\tb\tc", "d\u{2028}e\tf"])
        XCTAssertEqual(blocks[0].inlines.count, 3)
        XCTAssertEqual(blocks[0].inlines[1].marks, [.italic])
    }

    func testBlocksTableRoundTrip() {
        let blocks: [RichBlock] = [.paragraph("name\tqty"), .paragraph("ash\t2"), .paragraph("birch\t5")]
        let table = Ops.blocksToTable(blocks)
        let back = Ops.tableToBlocks(table)
        XCTAssertEqual(back.map(\.plainInlineText), blocks.map(\.plainInlineText))
        XCTAssertEqual(plain(Ops.blocksToTable(back)), plain(table))
    }

    // MARK: - Navigation

    private func navigationFixture() throws -> RichTable {
        try merged(numbered(rows: 3, columns: 3), 0...1, 0...1)
    }

    func testVisibleAddressesAreRowMajorAnchors() throws {
        let table = try navigationFixture()
        XCTAssertEqual(Ops.visibleAddresses(in: table), [addr(0, 0), addr(0, 2), addr(1, 2), addr(2, 0), addr(2, 1), addr(2, 2)])
    }

    func testSpatialNavigationSkipsCoveredAndLandsOnAnchors() throws {
        let table = try navigationFixture()
        func go(_ from: RichTableCellAddress, _ direction: RichTableDirection) -> RichTableNavigation {
            Ops.nextCellAddress(in: table, after: from, direction: direction, wrapRows: false)
        }
        XCTAssertEqual(go(addr(0, 0), .right), .cell(addr(0, 2)))
        XCTAssertEqual(go(addr(0, 2), .left), .cell(addr(0, 0)))
        XCTAssertEqual(go(addr(1, 2), .left), .cell(addr(0, 0)))
        XCTAssertEqual(go(addr(0, 0), .down), .cell(addr(2, 0)))
        XCTAssertEqual(go(addr(2, 1), .up), .cell(addr(0, 0)))
        XCTAssertEqual(go(addr(2, 2), .up), .cell(addr(1, 2)))
        XCTAssertEqual(go(addr(1, 1), .right), .cell(addr(1, 2)), "a covered address navigates from its span's edge")
    }

    func testSpatialNavigationBeyondEdges() throws {
        let table = try navigationFixture()
        func go(_ from: RichTableCellAddress, _ direction: RichTableDirection) -> RichTableNavigation {
            Ops.nextCellAddress(in: table, after: from, direction: direction, wrapRows: true)
        }
        XCTAssertEqual(go(addr(0, 0), .up), .beyondEdge(.up))
        XCTAssertEqual(go(addr(0, 2), .right), .beyondEdge(.right))
        XCTAssertEqual(go(addr(2, 0), .left), .beyondEdge(.left))
        XCTAssertEqual(go(addr(2, 2), .down), .beyondEdge(.down))
        XCTAssertEqual(go(addr(5, 5), .left), .beyondEdge(.left))
    }

    func testNextAndPreviousCellWrapRows() throws {
        let table = try navigationFixture()
        func go(_ from: RichTableCellAddress, _ direction: RichTableDirection, wrap: Bool) -> RichTableNavigation {
            Ops.nextCellAddress(in: table, after: from, direction: direction, wrapRows: wrap)
        }
        XCTAssertEqual(go(addr(0, 0), .nextCell, wrap: false), .cell(addr(0, 2)))
        XCTAssertEqual(go(addr(0, 2), .nextCell, wrap: true), .cell(addr(1, 2)))
        XCTAssertEqual(go(addr(0, 2), .nextCell, wrap: false), .beyondEdge(.nextCell))
        XCTAssertEqual(go(addr(2, 2), .nextCell, wrap: true), .beyondEdge(.nextCell))
        XCTAssertEqual(go(addr(2, 0), .previousCell, wrap: true), .cell(addr(1, 2)))
        XCTAssertEqual(go(addr(2, 0), .previousCell, wrap: false), .beyondEdge(.previousCell))
        XCTAssertEqual(go(addr(0, 0), .previousCell, wrap: true), .beyondEdge(.previousCell))
        XCTAssertEqual(go(addr(1, 0), .nextCell, wrap: false), .cell(addr(0, 2)), "covered positions resolve to their anchor first")
    }

    // MARK: - Fuzz

    func testSeededFuzzKeepsGridLawAndRoundTrips() throws {
        var rng = SeededGenerator(seed: 0x5EED_7AB1E)
        var table = numbered(rows: 4, columns: 4, header: true)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let tones: [String?] = ["moss", "rust", "sky", nil]

        func randomAddress(_ table: RichTable) -> RichTableCellAddress {
            addr(Int.random(in: 0..<table.rowCount, using: &rng), Int.random(in: 0..<table.columnCount, using: &rng))
        }
        func randomRect(_ table: RichTable) -> RichTableRect {
            RichTableRect(randomAddress(table), randomAddress(table))
        }

        for step in 1...500 {
            let before = table
            var op = Int.random(in: 0..<25, using: &rng)
            if table.rowCount > 8, op == 0 { op = 2 }
            if table.columnCount > 8, op == 1 { op = 3 }
            do {
                switch op {
                case 0:
                    let source = Bool.random(using: &rng) ? Int.random(in: 0..<table.rowCount, using: &rng) : nil
                    table = try Ops.insertRow(in: table, at: Int.random(in: 0...table.rowCount, using: &rng), copyingStyleOfRow: source).table
                case 1:
                    table = try Ops.insertColumn(in: table, at: Int.random(in: 0...table.columnCount, using: &rng)).table
                case 2:
                    table = try Ops.deleteRow(in: table, at: Int.random(in: 0..<table.rowCount, using: &rng))
                case 3:
                    table = try Ops.deleteColumn(in: table, at: Int.random(in: 0..<table.columnCount, using: &rng))
                case 4:
                    table = try Ops.moveRow(in: table, from: randomAddress(table).row, to: randomAddress(table).row)
                case 5:
                    table = try Ops.moveColumn(in: table, from: randomAddress(table).column, to: randomAddress(table).column)
                case 6, 7:
                    table = try Ops.mergeCells(in: table, rect: randomRect(table)).table
                case 8:
                    table = try Ops.unmergeCell(in: table, anchor: randomAddress(table)).table
                case 9:
                    table = try Ops.sortRows(in: table, byColumn: randomAddress(table).column, ascending: Bool.random(using: &rng))
                case 10:
                    table = Ops.distributeColumns(in: table)
                case 11:
                    table = try Ops.setColumnWeight(in: table, index: randomAddress(table).column, weight: Double.random(in: 0.01...5, using: &rng))
                case 12:
                    if table.columnCount > 1 {
                        table = try Ops.resizeColumnPair(in: table, left: Int.random(in: 0..<(table.columnCount - 1), using: &rng), delta: Double.random(in: -0.6...0.6, using: &rng))
                    }
                case 13:
                    table = try Ops.setTone(in: table, range: randomRect(table), toneID: tones[Int.random(in: 0..<tones.count, using: &rng)])
                case 14:
                    table = try Ops.setAlignment(in: table, column: randomAddress(table).column, alignment: RichTableAlignment.allCases[Int.random(in: 0..<3, using: &rng)])
                case 15:
                    table = try Ops.setAlignment(in: table, range: randomRect(table), alignment: Bool.random(using: &rng) ? .center : nil)
                case 16:
                    table = try Ops.setVerticalAlignment(in: table, range: randomRect(table), alignment: Bool.random(using: &rng) ? .bottom : nil)
                case 17:
                    table = try Ops.setHeaderRow(in: table, enabled: Bool.random(using: &rng))
                case 18:
                    table = Ops.setHeaderColumn(in: table, enabled: Bool.random(using: &rng))
                    table = Ops.setStyle(in: table, style: RichTableStyle.allCases[Int.random(in: 0..<3, using: &rng)])
                    table = Ops.setStriped(in: table, isStriped: Bool.random(using: &rng))
                case 19:
                    table = try Ops.clearCells(in: table, range: randomRect(table))
                case 20:
                    let rows = Int.random(in: 1...3, using: &rng)
                    let columns = Int.random(in: 1...3, using: &rng)
                    let grid = (0..<rows).map { r in (0..<columns).map { c in [RichInlineNode.text("f\(step)-\(r)\(c)")] } }
                    table = try Ops.fill(in: table, from: randomAddress(table), grid: grid, expand: Bool.random(using: &rng)).table
                case 21:
                    table = Ops.resize(in: table, rows: Int.random(in: 1...6, using: &rng), columns: Int.random(in: 1...6, using: &rng))
                case 22:
                    table = try Ops.transpose(in: table)
                case 23:
                    let blocks = Ops.tableToBlocks(table)
                    XCTAssertEqual(blocks.count, table.rowCount, "step \(step)")
                    let rebuilt = Ops.blocksToTable(blocks)
                    XCTAssertEqual(rebuilt.validate(), [], "step \(step)")
                default:
                    let navigation = Ops.nextCellAddress(in: table, after: randomAddress(table), direction: RichTableDirection.allCases[Int.random(in: 0..<6, using: &rng)], wrapRows: Bool.random(using: &rng))
                    if case .cell(let landed) = navigation {
                        XCTAssertFalse(table.isCovered(landed), "step \(step): navigation landed on a covered position")
                    }
                }
            } catch let error as RichTableError {
                XCTAssertEqual(table, before, "step \(step): a thrown op (\(error)) must leave the table untouched")
            }
            XCTAssertEqual(table.validate(), [], "step \(step) op \(op)")
            XCTAssertGreaterThanOrEqual(table.rowCount, 1)
            XCTAssertGreaterThanOrEqual(table.columnCount, 1)
            if step % 50 == 0 {
                let data = try encoder.encode(table)
                let decoded = try decoder.decode(RichTable.self, from: data)
                XCTAssertEqual(decoded, table, "step \(step): JSON round trip drifted")
            }
        }
    }
}
