import XCTest
@testable import CosmoOS

final class FilePortalEditEngineTests: XCTestCase {

    // MARK: - CRC32

    func testCRC32KnownVector() {
        // The canonical check value for "123456789".
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }

    // MARK: - ZIP writer

    func testRebuildArchiveReplacesOneEntryAndPreservesOthers() throws {
        let original = XLSXWorkbookReaderTests.makeWorkbookFixture()
        let newSheet = """
        <?xml version="1.0"?>
        <worksheet><sheetData>
        <row r="1"><c r="A1" t="inlineStr"><is><t>patched</t></is></c></row>
        </sheetData></worksheet>
        """
        let rebuilt = try ZipArchiveWriter.rebuildArchive(
            original: original,
            replacing: "xl/worksheets/sheet2.xml",
            with: Data(newSheet.utf8)
        )

        let reader = try ZipArchiveReader(data: rebuilt)
        // Entry order preserved.
        let originalReader = try ZipArchiveReader(data: original)
        XCTAssertEqual(reader.entryNamesInOrder, originalReader.entryNamesInOrder)
        // Untouched entries byte-identical.
        XCTAssertEqual(
            try reader.entryData(named: "xl/workbook.xml"),
            try originalReader.entryData(named: "xl/workbook.xml")
        )
        // Whole workbook still parses; sheet 2 shows the patch, sheet 1 intact.
        let workbook = try XLSXWorkbookReader.read(data: rebuilt)
        XCTAssertEqual(workbook.sheets[1].plainRows[0], ["patched"])
        XCTAssertEqual(workbook.sheets[0].plainRows[0], ["Name", "", "42"])
    }

    func testRebuildArchiveThrowsForUnknownEntry() {
        let original = XLSXWorkbookReaderTests.makeWorkbookFixture()
        XCTAssertThrowsError(
            try ZipArchiveWriter.rebuildArchive(original: original, replacing: "xl/nope.xml", with: Data())
        )
    }

    // MARK: - Cell patcher

    private let sheetXML = """
    <?xml version="1.0"?>
    <worksheet><sheetData>
    <row r="1"><c r="A1" s="3" t="s"><v>0</v></c><c r="C1"><v>42</v></c></row>
    <row r="3"><c r="B3"><v>7</v></c></row>
    </sheetData></worksheet>
    """

    private func value(at rowIndex: Int, _ columnIndex: Int, in xml: String) throws -> String {
        let zip = XLSXWorkbookReaderTests.makeZip(entries: [
            ("xl/workbook.xml", "<workbook><sheets><sheet name=\"S\" sheetId=\"1\"/></sheets></workbook>"),
            ("xl/sharedStrings.xml", "<sst><si><t>Name</t></si></sst>"),
            ("xl/worksheets/sheet1.xml", xml),
        ])
        let workbook = try XLSXWorkbookReader.read(data: zip)
        let rows = workbook.sheets[0].plainRows
        guard rows.indices.contains(rowIndex), rows[rowIndex].indices.contains(columnIndex) else { return "" }
        return rows[rowIndex][columnIndex]
    }

    func testEditExistingCellKeepsStyleIndex() throws {
        let patched = try XLSXCellPatcher.patchedSheetXML(sheetXML, rowIndex: 0, columnIndex: 0, newText: "Hello & <World>")
        XCTAssertTrue(patched.contains("s=\"3\""))
        XCTAssertEqual(try value(at: 0, 0, in: patched), "Hello & <World>")
        // Untouched neighbor survives.
        XCTAssertEqual(try value(at: 0, 2, in: patched), "42")
    }

    func testInsertCellIntoExistingRowInColumnOrder() throws {
        let patched = try XLSXCellPatcher.patchedSheetXML(sheetXML, rowIndex: 0, columnIndex: 1, newText: "middle")
        XCTAssertEqual(try value(at: 0, 1, in: patched), "middle")
        XCTAssertEqual(try value(at: 0, 0, in: patched), "Name")
        XCTAssertEqual(try value(at: 0, 2, in: patched), "42")
        // Ordered before C1 in the XML.
        let bRange = try XCTUnwrap(patched.range(of: "r=\"B1\""))
        let cRange = try XCTUnwrap(patched.range(of: "r=\"C1\""))
        XCTAssertLessThan(bRange.lowerBound, cRange.lowerBound)
    }

    func testInsertMissingRowInNumericOrder() throws {
        let patched = try XLSXCellPatcher.patchedSheetXML(sheetXML, rowIndex: 1, columnIndex: 0, newText: "row2")
        XCTAssertEqual(try value(at: 1, 0, in: patched), "row2")
        XCTAssertEqual(try value(at: 2, 1, in: patched), "7")
        let row2 = try XCTUnwrap(patched.range(of: "<row r=\"2\""))
        let row3 = try XCTUnwrap(patched.range(of: "<row r=\"3\""))
        XCTAssertLessThan(row2.lowerBound, row3.lowerBound)
    }

    func testAppendRowAtEnd() throws {
        let patched = try XLSXCellPatcher.patchedSheetXML(sheetXML, rowIndex: 9, columnIndex: 1, newText: "tail")
        XCTAssertEqual(try value(at: 9, 1, in: patched), "tail")
    }

    func testEmptyTextClearsCell() throws {
        let patched = try XLSXCellPatcher.patchedSheetXML(sheetXML, rowIndex: 0, columnIndex: 0, newText: "")
        XCTAssertEqual(try value(at: 0, 0, in: patched), "")
        XCTAssertTrue(patched.contains("<c r=\"A1\" s=\"3\"/>"))
    }

    func testPatchIntoSelfClosingSheetData() throws {
        let emptySheet = "<?xml version=\"1.0\"?><worksheet><sheetData/></worksheet>"
        let patched = try XLSXCellPatcher.patchedSheetXML(emptySheet, rowIndex: 0, columnIndex: 0, newText: "first")
        XCTAssertEqual(try value(at: 0, 0, in: patched), "first")
    }

    // MARK: - CSV serialization

    func testCSVSerializationQuotesOnlyWhenNeeded() {
        let rows = [["plain", "with,comma", "with \"quote\"", "line\nbreak"]]
        let serialized = CSVTableParser.serialize(rows)
        XCTAssertEqual(serialized, "plain,\"with,comma\",\"with \"\"quote\"\"\",\"line\nbreak\"")
        // Round-trip through the parser.
        XCTAssertEqual(CSVTableParser.parse(serialized), rows)
    }

    func testCSVSerializationTabDelimiter() {
        let rows = [["a", "b\tc"], ["d", "e"]]
        let serialized = CSVTableParser.serialize(rows, delimiter: "\t")
        XCTAssertEqual(CSVTableParser.parse(serialized, delimiter: "\t"), rows)
    }
}
