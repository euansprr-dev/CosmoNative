import XCTest
@testable import CosmoOS

final class XLSXWorkbookReaderTests: XCTestCase {

    // MARK: - Fixture builder (stored-entry ZIP, no compression)

    /// Builds a minimal valid ZIP with stored (method 0) entries — the reader
    /// never validates CRC, so fixtures can carry zero there.
    static func makeZip(entries: [(name: String, content: String)]) -> Data {
        var archive = Data()
        var centralDirectory = Data()

        func le16(_ value: Int) -> Data { withUnsafeBytes(of: UInt16(value).littleEndian) { Data($0) } }
        func le32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }

        for (name, content) in entries {
            let nameData = Data(name.utf8)
            let contentData = Data(content.utf8)
            let localHeaderOffset = archive.count

            archive += le32(0x04034b50)          // local header signature
            archive += le16(20) + le16(0) + le16(0) // version, flags, method (stored)
            archive += le16(0) + le16(0)          // mod time/date
            archive += le32(0)                    // crc (unvalidated)
            archive += le32(contentData.count)    // compressed size
            archive += le32(contentData.count)    // uncompressed size
            archive += le16(nameData.count) + le16(0)
            archive += nameData
            archive += contentData

            centralDirectory += le32(0x02014b50)
            centralDirectory += le16(20) + le16(20) + le16(0) + le16(0)
            centralDirectory += le16(0) + le16(0)
            centralDirectory += le32(0)
            centralDirectory += le32(contentData.count)
            centralDirectory += le32(contentData.count)
            centralDirectory += le16(nameData.count) + le16(0) + le16(0)
            centralDirectory += le16(0) + le16(0)
            centralDirectory += le32(0)
            centralDirectory += le32(localHeaderOffset)
            centralDirectory += nameData
        }

        let directoryOffset = archive.count
        archive += centralDirectory
        archive += le32(0x06054b50)
        archive += le16(0) + le16(0)
        archive += le16(entries.count) + le16(entries.count)
        archive += le32(centralDirectory.count)
        archive += le32(directoryOffset)
        archive += le16(0)
        return archive
    }

    static func fixtureEntries() -> [(name: String, content: String)] {
        let workbook = """
        <?xml version="1.0"?>
        <workbook><sheets>
        <sheet name="Data" sheetId="1" r:id="rId1"/>
        <sheet name="Notes" sheetId="2" r:id="rId2"/>
        </sheets></workbook>
        """
        let rels = """
        <?xml version="1.0"?>
        <Relationships>
        <Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="worksheet" Target="worksheets/sheet2.xml"/>
        </Relationships>
        """
        let sharedStrings = """
        <?xml version="1.0"?>
        <sst><si><t>Name</t></si><si><r><t>Rich </t></r><r><t>Text</t></r></si></sst>
        """
        let styles = """
        <?xml version="1.0"?>
        <styleSheet>
        <fonts count="2">
        <font><sz val="11"/></font>
        <font><b/><sz val="14"/><color rgb="FFFFFFFF"/></font>
        </fonts>
        <fills count="3">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF7030A0"/></patternFill></fill>
        </fills>
        <cellXfs count="3">
        <xf fontId="0" fillId="0"/>
        <xf fontId="1" fillId="2"/>
        <xf fontId="0" fillId="0"><alignment wrapText="1"/></xf>
        </cellXfs>
        </styleSheet>
        """
        let sheet1 = """
        <?xml version="1.0"?>
        <worksheet>
        <cols><col min="1" max="1" width="20" customWidth="1"/><col min="2" max="3" width="10"/></cols>
        <sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1"><v>42</v></c></row>
        <row r="2" ht="30"><c r="A2" s="2"><v>3.5</v></c><c r="B2" t="b"><v>1</v></c></row>
        <row r="4"><c r="A4" s="1" t="s"><v>1</v></c><c r="C4" t="inlineStr"><is><t>inline!</t></is></c></row>
        </sheetData>
        <mergeCells count="1"><mergeCell ref="A1:B1"/></mergeCells>
        </worksheet>
        """
        let sheet2 = """
        <?xml version="1.0"?>
        <worksheet><sheetData>
        <row r="1"><c r="A1" t="str"><v>=SUM result</v></c></row>
        </sheetData></worksheet>
        """
        return [
            ("xl/workbook.xml", workbook),
            ("xl/_rels/workbook.xml.rels", rels),
            ("xl/sharedStrings.xml", sharedStrings),
            ("xl/styles.xml", styles),
            ("xl/worksheets/sheet1.xml", sheet1),
            ("xl/worksheets/sheet2.xml", sheet2),
        ]
    }

    static func makeWorkbookFixture() -> Data {
        makeZip(entries: fixtureEntries())
    }

    // MARK: - Structure

    func testReadsSheetsInWorkbookOrder() throws {
        let workbook = try XLSXWorkbookReader.read(data: Self.makeWorkbookFixture())
        XCTAssertEqual(workbook.sheets.map(\.name), ["Data", "Notes"])
    }

    func testCellValuesTypesAndGaps() throws {
        let workbook = try XLSXWorkbookReader.read(data: Self.makeWorkbookFixture())
        let sheet = workbook.sheets[0]

        // Row 1: shared string, gap at B, integral number loses ".0"-style noise.
        XCTAssertEqual(sheet.plainRows[0], ["Name", "", "42"])
        // Row 2: plain decimal survives, boolean renders TRUE.
        XCTAssertEqual(sheet.plainRows[1], ["3.5", "TRUE", ""])
        // Row 3 was absent in the file — preserved as an empty padded row.
        XCTAssertEqual(sheet.plainRows[2], ["", "", ""])
        // Row 4: rich-text shared string concatenates runs; inline string reads.
        XCTAssertEqual(sheet.plainRows[3], ["Rich Text", "", "inline!"])
        XCTAssertEqual(sheet.columnCount, 3)
    }

    func testFormulaStringCellReadsCachedValue() throws {
        let workbook = try XLSXWorkbookReader.read(data: Self.makeWorkbookFixture())
        XCTAssertEqual(workbook.sheets[1].plainRows[0], ["=SUM result"])
    }

    // MARK: - Fidelity: geometry, merges, styles

    func testColumnWidthsAndRowHeightsComeFromTheFile() throws {
        let workbook = try XLSXWorkbookReader.read(data: Self.makeWorkbookFixture())
        let sheet = workbook.sheets[0]

        let widths = try XCTUnwrap(sheet.fileColumnWidths)
        XCTAssertEqual(widths[0], 20 * 7 + 5)   // width unit → logical px
        XCTAssertEqual(widths[1], 10 * 7 + 5)
        XCTAssertEqual(widths[2], 10 * 7 + 5)

        let heights = try XCTUnwrap(sheet.fileRowHeights)
        XCTAssertNil(heights[0])
        XCTAssertEqual(try XCTUnwrap(heights[1]), 30 * 4 / 3, accuracy: 0.01) // pt → px
    }

    func testHorizontalMergeSpansAnchorAndCoversNeighbors() throws {
        let workbook = try XLSXWorkbookReader.read(data: Self.makeWorkbookFixture())
        let row = workbook.sheets[0].rows[0]
        XCTAssertEqual(row[0].columnSpan, 2)   // A1:B1 anchor
        XCTAssertEqual(row[1].columnSpan, 0)   // covered
        XCTAssertEqual(row[2].columnSpan, 1)
    }

    func testStylesResolveFontsFillsAndWrap() throws {
        let workbook = try XLSXWorkbookReader.read(data: Self.makeWorkbookFixture())
        XCTAssertEqual(workbook.styles.count, 3)

        let headerStyle = workbook.styles[1]
        XCTAssertTrue(headerStyle.isBold)
        XCTAssertEqual(headerStyle.fontPointSize, 14)
        XCTAssertEqual(headerStyle.textColorHex, "FFFFFF")
        XCTAssertEqual(headerStyle.fillColorHex, "7030A0")

        let wrapStyle = workbook.styles[2]
        XCTAssertTrue(wrapStyle.wrapText)
        XCTAssertNil(wrapStyle.fillColorHex)

        // Cells carry their style indices.
        let sheet = workbook.sheets[0]
        XCTAssertEqual(sheet.rows[3][0].styleIndex, 1)
        XCTAssertEqual(sheet.rows[1][0].styleIndex, 2)
    }

    func testTintLightensAndDarkens() {
        XCTAssertEqual(XLSXColorMath.applyTint(0.5, to: "000000"), "808080")
        XCTAssertEqual(XLSXColorMath.applyTint(-0.5, to: "FFFFFF"), "808080")
        XCTAssertEqual(XLSXColorMath.applyTint(0, to: "ABCDEF"), "ABCDEF")
    }

    // MARK: - Failure modes

    func testGarbageDataThrowsUnreadable() {
        XCTAssertThrowsError(try XLSXWorkbookReader.read(data: Data("not a zip".utf8)))
    }

    func testMissingWorkbookPartThrows() {
        let zip = Self.makeZip(entries: [("xl/styles.xml", "<styleSheet/>")])
        XCTAssertThrowsError(try XLSXWorkbookReader.read(data: zip))
    }

    // MARK: - Cell reference math

    func testColumnIndexParsing() {
        XCTAssertEqual(WorksheetCellReference.columnIndex("A1"), 0)
        XCTAssertEqual(WorksheetCellReference.columnIndex("Z10"), 25)
        XCTAssertEqual(WorksheetCellReference.columnIndex("AA1"), 26)
        XCTAssertEqual(WorksheetCellReference.columnIndex("BC23"), 54)
        XCTAssertNil(WorksheetCellReference.columnIndex("123"))
    }

    func testColumnLettersRoundTrip() {
        for index in [0, 25, 26, 51, 52, 701, 702] {
            XCTAssertEqual(WorksheetCellReference.columnIndex(WorksheetCellReference.columnLetters(index) + "1"), index)
        }
        XCTAssertEqual(WorksheetCellReference.reference(rowIndex: 22, columnIndex: 54), "BC23")
        XCTAssertEqual(WorksheetCellReference.rowIndex("BC23"), 22)
    }
}
