import XCTest
@testable import CosmoOS

final class SheetGridLayoutTests: XCTestCase {

    private func sheet(_ rows: [[String]]) -> SheetModel {
        SheetModel(name: "Test", rows: rows)
    }

    // MARK: - SheetModel invariants

    func testSheetModelPadsRaggedRows() {
        let model = sheet([["a", "b", "c"], ["d"], []])
        XCTAssertEqual(model.columnCount, 3)
        XCTAssertEqual(model.plainRows[1], ["d", "", ""])
        XCTAssertEqual(model.plainRows[2], ["", "", ""])
        XCTAssertEqual(model.cellCount, 9)
    }

    func testUpdatingCellPadsAndReplaces() {
        let workbook = SheetWorkbook(sheets: [sheet([["a"]])])
        let updated = workbook.updatingCell(sheetIndex: 0, rowIndex: 2, columnIndex: 2, text: "new")
        XCTAssertEqual(updated.sheets[0].plainRows[2], ["", "", "new"])
        XCTAssertEqual(updated.sheets[0].plainRows[0], ["a", "", ""])
    }

    // MARK: - Header detection

    func testTextualFirstRowOverDataPinsAsHeaderWhenStyleless() {
        let layout = SheetGridLayout(
            sheet: sheet([["Name", "Amount"], ["Rent", "1200"]]),
            maxRows: 100, maxColumns: 100
        )
        XCTAssertEqual(layout.headerRowIndex, 0)
        XCTAssertEqual(layout.bodyRowIndices, [1])
    }

    func testNumericFirstRowDoesNotPin() {
        let layout = SheetGridLayout(
            sheet: sheet([["1", "2"], ["3", "4"]]),
            maxRows: 100, maxColumns: 100
        )
        XCTAssertNil(layout.headerRowIndex)
        XCTAssertEqual(layout.bodyRowIndices, [0, 1])
    }

    func testStyledSheetPinsTheSharedFillBand() {
        // Row 0: unstyled title. Row 2: two cells sharing one solid fill.
        let styles = [
            SheetCellStyle.plain,
            SheetCellStyle(isBold: true, isItalic: false, fontPointSize: 11,
                           textColorHex: "FFFFFF", fillColorHex: "7030A0", wrapText: false)
        ]
        let rows: [[SheetCell]] = [
            [SheetCell(text: "Big Title")],
            [],
            [SheetCell(text: "Example", styleIndex: 1), SheetCell(text: "Notes", styleIndex: 1)],
            [SheetCell(text: "Chillhouse"), SheetCell(text: "NYC")]
        ]
        let layout = SheetGridLayout(
            sheet: SheetModel(name: "S", rows: rows),
            styles: styles,
            maxRows: 100, maxColumns: 100
        )
        XCTAssertEqual(layout.headerRowIndex, 2)
    }

    func testStyledSheetWithoutFillBandPinsNothing() {
        let styles = [SheetCellStyle.plain]
        let rows: [[SheetCell]] = [[SheetCell(text: "Name"), SheetCell(text: "Amount")],
                                   [SheetCell(text: "Rent"), SheetCell(text: "1200")]]
        let layout = SheetGridLayout(
            sheet: SheetModel(name: "S", rows: rows),
            styles: styles,
            maxRows: 100, maxColumns: 100
        )
        XCTAssertNil(layout.headerRowIndex)
    }

    // MARK: - Display caps

    func testTruncationCapsRowsAndColumns() {
        let bigRows = (0..<50).map { row in (0..<40).map { "r\(row)c\($0)" } }
        let layout = SheetGridLayout(sheet: sheet(bigRows), maxRows: 10, maxColumns: 5)
        XCTAssertEqual(layout.displayRowCount, 10)
        XCTAssertEqual(layout.displayColumnCount, 5)
        XCTAssertTrue(layout.isTruncated)

        let note = layout.truncationDescription(sheet: sheet(bigRows))
        XCTAssertTrue(note.contains("10 of 50 rows"))
        XCTAssertTrue(note.contains("5 of 40 columns"))
    }

    // MARK: - Geometry from the file

    func testFileColumnWidthsWinOverEstimation() {
        let model = SheetModel(
            name: "S",
            rows: [[SheetCell(text: "abc"), SheetCell(text: "def")]],
            fileColumnWidths: [120, nil]
        )
        let layout = SheetGridLayout(sheet: model, maxRows: 10, maxColumns: 10)
        XCTAssertEqual(layout.columnWidths[0], 120)
        XCTAssertEqual(layout.columnWidths[1], SheetGridLayout.defaultFileColumnWidth)
    }

    func testFileRowHeightsApplyWithDefaultFloor() {
        let model = SheetModel(
            name: "S",
            rows: [[SheetCell(text: "a")], [SheetCell(text: "b")]],
            fileRowHeights: [40, nil]
        )
        let layout = SheetGridLayout(sheet: model, maxRows: 10, maxColumns: 10)
        XCTAssertEqual(layout.rowHeight(rowIndex: 0), 40)
        XCTAssertEqual(layout.rowHeight(rowIndex: 1), SheetGridLayout.defaultRowHeight)
    }

    // MARK: - Slots: merges + overflow

    func testMergedAnchorProducesOneWideSlot() {
        var anchor = SheetCell(text: "Merged Title")
        anchor.columnSpan = 3
        var covered = SheetCell.empty
        covered.columnSpan = 0
        let model = SheetModel(
            name: "S",
            rows: [[anchor, covered, covered, SheetCell(text: "x")]],
            fileColumnWidths: [50, 50, 50, 50]
        )
        let layout = SheetGridLayout(sheet: model, maxRows: 10, maxColumns: 10)
        let slots = layout.slots(rowIndex: 0)
        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots[0].width, 150)
        XCTAssertEqual(slots[1].columnIndex, 3)
    }

    func testLongTextOverflowsAcrossEmptyNeighbors() {
        let long = String(repeating: "x", count: 40) // needs ~270pt
        let model = SheetModel(
            name: "S",
            rows: [[SheetCell(text: long), .empty, .empty, SheetCell(text: "stop")]],
            fileColumnWidths: [60, 60, 60, 60]
        )
        let layout = SheetGridLayout(sheet: model, maxRows: 10, maxColumns: 10)
        let slots = layout.slots(rowIndex: 0)
        // Overflow may only claim the two empties — never the "stop" cell.
        XCTAssertEqual(slots[0].width, 180)
        XCTAssertEqual(slots[1].columnIndex, 3)
    }

    func testShortTextDoesNotOverflow() {
        let model = SheetModel(
            name: "S",
            rows: [[SheetCell(text: "ok"), .empty]],
            fileColumnWidths: [60, 60]
        )
        let layout = SheetGridLayout(sheet: model, maxRows: 10, maxColumns: 10)
        let slots = layout.slots(rowIndex: 0)
        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots[0].width, 60)
    }

    // MARK: - Estimated widths (CSV path)

    func testColumnWidthsClampToBounds() {
        let longText = String(repeating: "x", count: 400)
        let layout = SheetGridLayout(
            sheet: sheet([["a", longText]]),
            maxRows: 10, maxColumns: 10
        )
        XCTAssertEqual(layout.columnWidths[0], SheetGridLayout.minColumnWidth)
        XCTAssertEqual(layout.columnWidths[1], SheetGridLayout.maxColumnWidth)
    }
}
