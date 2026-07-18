// CosmoOS/Services/XLSXWorkbookReader.swift
// Self-contained XLSX reading for spreadsheet portals — no third-party
// dependency. An .xlsx is a ZIP of XML parts; this file implements exactly
// the slice a faithful read-only preview needs:
//   • a minimal ZIP central-directory reader (stored + deflate entries,
//     inflated one-shot via the Compression framework's raw-DEFLATE codec)
//   • SAX parsing (Foundation XMLParser) of workbook.xml (sheet order),
//     workbook rels (part paths), sharedStrings.xml, styles.xml (fonts,
//     solid fills, wrap flags), theme1.xml (scheme colors + tint), and each
//     worksheet (cells, column widths, row heights, merged ranges).
// Anything outside that slice (zip64, encrypted workbooks, style-driven date
// formats) throws — and the portal degrades to its Tier-0 thumbnail card,
// which QuickLook renders for xlsx anyway. Failure here is never fatal UI.
// Unit-tested in XLSXWorkbookReaderTests against fixtures built in-test.

import Compression
import Foundation

enum XLSXWorkbookReader {
    /// In-parse guard so a hostile sheet fails fast instead of exhausting
    /// memory before the loader's post-parse cap check.
    private static let parseCellCeiling = SheetWorkbookLoader.maxCellCount + SheetWorkbookLoader.maxCellCount / 5

    static func read(url: URL) throws -> SheetWorkbook {
        guard let data = try? Data(contentsOf: url) else { throw SheetWorkbookError.unreadable }
        return try read(data: data)
    }

    static func read(data: Data) throws -> SheetWorkbook {
        let archive = try ZipArchiveReader(data: data)

        let sharedStrings: [String]
        if let sharedData = try archive.entryData(named: "xl/sharedStrings.xml") {
            sharedStrings = try SharedStringsParser.parse(sharedData)
        } else {
            sharedStrings = []
        }

        // Theme first (styles reference its scheme colors), then styles.
        var themeColors: [String] = []
        if let themeData = try archive.entryData(named: "xl/theme/theme1.xml") {
            themeColors = (try? ThemeColorParser.parse(themeData)) ?? []
        }
        var styles: [SheetCellStyle] = []
        if let stylesData = try archive.entryData(named: "xl/styles.xml") {
            styles = (try? StylesParser.parse(stylesData, themeColors: themeColors)) ?? []
        }

        guard let workbookData = try archive.entryData(named: "xl/workbook.xml") else {
            throw SheetWorkbookError.unreadable
        }
        let declaredSheets = try WorkbookSheetListParser.parse(workbookData)
        guard !declaredSheets.isEmpty else { throw SheetWorkbookError.unreadable }

        let relationships: [String: String]
        if let relsData = try archive.entryData(named: "xl/_rels/workbook.xml.rels") {
            relationships = try RelationshipsParser.parse(relsData)
        } else {
            relationships = [:]
        }

        var sheets: [SheetModel] = []
        var parsedCells = 0
        for (index, declared) in declaredSheets.enumerated() {
            let partPath = Self.sheetPartPath(relationshipId: declared.relationshipId,
                                              relationships: relationships,
                                              fallbackIndex: index)
            guard let sheetData = try archive.entryData(named: partPath) else { continue }
            let parsed = try WorksheetParser.parse(
                sheetData,
                sharedStrings: sharedStrings,
                cellBudget: parseCellCeiling - parsedCells
            )
            let mergedRows = Self.applyMerges(parsed.mergeRanges, to: parsed.rows)
            let sheet = SheetModel(
                name: declared.name,
                rows: mergedRows,
                fileColumnWidths: parsed.columnWidths,
                fileRowHeights: parsed.rowHeights
            )
            parsedCells += sheet.cellCount
            sheets.append(sheet)
        }

        guard !sheets.isEmpty else { throw SheetWorkbookError.unreadable }
        return SheetWorkbook(sheets: sheets, styles: styles)
    }

    /// Which archive part holds a sheet — used by the reader here and by the
    /// cell patcher when writing an edit back.
    static func sheetPartPath(inArchive data: Data, sheetIndex: Int) throws -> String {
        let archive = try ZipArchiveReader(data: data)
        guard let workbookData = try archive.entryData(named: "xl/workbook.xml") else {
            throw SheetWorkbookError.unreadable
        }
        let declaredSheets = try WorkbookSheetListParser.parse(workbookData)
        guard declaredSheets.indices.contains(sheetIndex) else { throw SheetWorkbookError.unreadable }
        var relationships: [String: String] = [:]
        if let relsData = try archive.entryData(named: "xl/_rels/workbook.xml.rels") {
            relationships = try RelationshipsParser.parse(relsData)
        }
        return sheetPartPath(
            relationshipId: declaredSheets[sheetIndex].relationshipId,
            relationships: relationships,
            fallbackIndex: sheetIndex
        )
    }

    /// Rels targets are relative to `xl/` ("worksheets/sheet1.xml") or
    /// package-absolute ("/xl/worksheets/sheet1.xml"). No rels part at all
    /// falls back to the conventional sheetN.xml naming.
    private static func sheetPartPath(relationshipId: String?, relationships: [String: String], fallbackIndex: Int) -> String {
        if let relationshipId, let target = relationships[relationshipId] {
            if target.hasPrefix("/") {
                return String(target.dropFirst())
            }
            return "xl/" + target
        }
        return "xl/worksheets/sheet\(fallbackIndex + 1).xml"
    }

    /// Horizontal merges widen the anchor (span = column count) and zero the
    /// covered cells; vertical merges need no work — XLSX stores the value in
    /// the anchor only, so covered rows are already empty.
    private static func applyMerges(_ ranges: [String], to rows: [[SheetCell]]) -> [[SheetCell]] {
        guard !ranges.isEmpty else { return rows }
        var rows = rows
        for range in ranges {
            let corners = range.split(separator: ":")
            guard corners.count == 2,
                  let startColumn = WorksheetCellReference.columnIndex(String(corners[0])),
                  let endColumn = WorksheetCellReference.columnIndex(String(corners[1])),
                  let startRow = WorksheetCellReference.rowIndex(String(corners[0])),
                  endColumn > startColumn,
                  rows.indices.contains(startRow) else { continue }
            var row = rows[startRow]
            while row.count <= endColumn { row.append(.empty) }
            row[startColumn].columnSpan = endColumn - startColumn + 1
            for covered in (startColumn + 1)...endColumn {
                row[covered].columnSpan = 0
            }
            rows[startRow] = row
        }
        return rows
    }
}

// MARK: - Minimal ZIP reader

/// Reads a ZIP archive's central directory and extracts entries. Supports
/// stored (0) and deflate (8) compression; rejects zip64 and anything exotic.
/// Also exposes raw entries (compressed payload + CRC, in central-directory
/// order) so ZipArchiveWriter can rebuild an archive copying untouched
/// entries verbatim.
struct ZipArchiveReader {
    struct RawEntry {
        let name: String
        let compressionMethod: UInt16
        let crc32: UInt32
        let compressedData: Data
        let uncompressedSize: Int
    }

    private struct Entry {
        let compressionMethod: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private var entries: [String: Entry] = [:]
    private(set) var entryNamesInOrder: [String] = []

    init(data: Data) throws {
        self.data = data
        try readCentralDirectory()
    }

    /// Bytes of a named entry, or nil when the archive has no such part.
    func entryData(named name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        let payload = try compressedPayload(for: entry)
        switch entry.compressionMethod {
        case 0:
            return payload
        case 8:
            return try Self.inflate(payload, uncompressedSize: entry.uncompressedSize)
        default:
            throw SheetWorkbookError.unreadable
        }
    }

    /// Raw (still-compressed) entry for archive rebuilding.
    func rawEntry(named name: String) throws -> RawEntry? {
        guard let entry = entries[name] else { return nil }
        return RawEntry(
            name: name,
            compressionMethod: entry.compressionMethod,
            crc32: entry.crc32,
            compressedData: try compressedPayload(for: entry),
            uncompressedSize: entry.uncompressedSize
        )
    }

    private func compressedPayload(for entry: Entry) throws -> Data {
        // Local header: sizes there may be zeroed (streaming writers set the
        // bit-3 data-descriptor flag) — the central directory's sizes,
        // already captured, are authoritative. The local header is read only
        // to find where the payload starts.
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count, readUInt32(at: base) == 0x04034b50 else {
            throw SheetWorkbookError.unreadable
        }
        let nameLength = Int(readUInt16(at: base + 26))
        let extraLength = Int(readUInt16(at: base + 28))
        let payloadStart = base + 30 + nameLength + extraLength
        guard payloadStart + entry.compressedSize <= data.count else {
            throw SheetWorkbookError.unreadable
        }
        return data.subdata(in: payloadStart..<(payloadStart + entry.compressedSize))
    }

    private mutating func readCentralDirectory() throws {
        // End-of-central-directory record: scan backwards over the (≤64KB)
        // trailing comment for the signature.
        let minimumEOCD = 22
        guard data.count >= minimumEOCD else { throw SheetWorkbookError.unreadable }
        let scanFloor = max(0, data.count - minimumEOCD - 65_535)
        var eocdOffset = -1
        var cursor = data.count - minimumEOCD
        while cursor >= scanFloor {
            if readUInt32(at: cursor) == 0x06054b50 {
                eocdOffset = cursor
                break
            }
            cursor -= 1
        }
        guard eocdOffset >= 0 else { throw SheetWorkbookError.unreadable }

        let entryCount = Int(readUInt16(at: eocdOffset + 10))
        let directoryOffset = Int(readUInt32(at: eocdOffset + 16))
        guard directoryOffset != 0xFFFFFFFF, entryCount != 0xFFFF else {
            throw SheetWorkbookError.unreadable // zip64 — outside the preview slice
        }

        var offset = directoryOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, readUInt32(at: offset) == 0x02014b50 else {
                throw SheetWorkbookError.unreadable
            }
            let compressionMethod = readUInt16(at: offset + 10)
            let crc = readUInt32(at: offset + 16)
            let compressedSize = Int(readUInt32(at: offset + 20))
            let uncompressedSize = Int(readUInt32(at: offset + 24))
            let nameLength = Int(readUInt16(at: offset + 28))
            let extraLength = Int(readUInt16(at: offset + 30))
            let commentLength = Int(readUInt16(at: offset + 32))
            let localHeaderOffset = Int(readUInt32(at: offset + 42))
            guard compressedSize != 0xFFFFFFFF, uncompressedSize != 0xFFFFFFFF,
                  localHeaderOffset != 0xFFFFFFFF else {
                throw SheetWorkbookError.unreadable // zip64 sizes
            }
            guard offset + 46 + nameLength <= data.count else { throw SheetWorkbookError.unreadable }
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            if let name = String(data: nameData, encoding: .utf8) {
                entries[name] = Entry(
                    compressionMethod: compressionMethod,
                    crc32: crc,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
                entryNamesInOrder.append(name)
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
    }

    /// One-shot raw-DEFLATE inflate — Apple's COMPRESSION_ZLIB is headerless
    /// DEFLATE, exactly what ZIP entries store.
    private static func inflate(_ payload: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        var destination = Data(count: uncompressedSize)
        let written = destination.withUnsafeMutableBytes { destPointer -> Int in
            payload.withUnsafeBytes { sourcePointer -> Int in
                guard let dest = destPointer.bindMemory(to: UInt8.self).baseAddress,
                      let source = sourcePointer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    dest, uncompressedSize,
                    source, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == uncompressedSize else { throw SheetWorkbookError.unreadable }
        return destination
    }

    private func readUInt16(at offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset]) | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        UInt32(readUInt16(at: offset)) | (UInt32(readUInt16(at: offset + 2)) << 16)
    }
}

// MARK: - workbook.xml (sheet list)

private final class WorkbookSheetListParser: NSObject, XMLParserDelegate {
    struct DeclaredSheet {
        let name: String
        let relationshipId: String?
    }

    private var sheets: [DeclaredSheet] = []

    static func parse(_ data: Data) throws -> [DeclaredSheet] {
        let delegate = WorkbookSheetListParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SheetWorkbookError.unreadable }
        return delegate.sheets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard elementName == "sheet" else { return }
        let name = attributes["name"] ?? "Sheet \(sheets.count + 1)"
        let relationshipId = attributes["r:id"] ?? attributes["id"]
        sheets.append(DeclaredSheet(name: name, relationshipId: relationshipId))
    }
}

// MARK: - workbook.xml.rels

private final class RelationshipsParser: NSObject, XMLParserDelegate {
    private var relationships: [String: String] = [:]

    static func parse(_ data: Data) throws -> [String: String] {
        let delegate = RelationshipsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SheetWorkbookError.unreadable }
        return delegate.relationships
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard elementName == "Relationship",
              let id = attributes["Id"],
              let target = attributes["Target"] else { return }
        relationships[id] = target
    }
}

// MARK: - sharedStrings.xml

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentString = ""
    private var insideStringItem = false
    private var insideText = false
    /// Phonetic runs (`<rPh>`, furigana) render above cells in Excel — they
    /// are not cell content and must not leak into the preview.
    private var phoneticDepth = 0

    static func parse(_ data: Data) throws -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SheetWorkbookError.unreadable }
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "si":
            insideStringItem = true
            currentString = ""
        case "rPh":
            phoneticDepth += 1
        case "t":
            insideText = insideStringItem && phoneticDepth == 0
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText {
            currentString += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "si":
            strings.append(currentString)
            insideStringItem = false
        case "rPh":
            phoneticDepth = max(0, phoneticDepth - 1)
        case "t":
            insideText = false
        default:
            break
        }
    }
}

// MARK: - theme1.xml (scheme colors)

/// Extracts the theme's scheme colors in Excel's cell-color index order.
/// The clrScheme part lists dk1/lt1/dk2/lt2/accent1–6/hlink/folHlink, but
/// cells index them with dk1↔lt1 and dk2↔lt2 swapped (the long-standing
/// Excel quirk every reader implements).
private final class ThemeColorParser: NSObject, XMLParserDelegate {
    private var schemeColors: [String: String] = [:]
    private var insideScheme = false
    private var currentSlot: String?

    private static let slotNames: Set<String> = [
        "dk1", "lt1", "dk2", "lt2",
        "accent1", "accent2", "accent3", "accent4", "accent5", "accent6",
        "hlink", "folHlink"
    ]

    static func parse(_ data: Data) throws -> [String] {
        let delegate = ThemeColorParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SheetWorkbookError.unreadable }
        let s = delegate.schemeColors
        let indexOrder = ["lt1", "dk1", "lt2", "dk2",
                          "accent1", "accent2", "accent3", "accent4", "accent5", "accent6",
                          "hlink", "folHlink"]
        return indexOrder.map { s[$0] ?? "000000" }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "clrScheme" {
            insideScheme = true
            return
        }
        guard insideScheme else { return }
        if Self.slotNames.contains(local) {
            currentSlot = local
        } else if let slot = currentSlot {
            if local == "srgbClr", let value = attributes["val"] {
                schemeColors[slot] = value.uppercased()
            } else if local == "sysClr", let value = attributes["lastClr"] {
                schemeColors[slot] = value.uppercased()
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "clrScheme" { insideScheme = false }
        if Self.slotNames.contains(local) { currentSlot = nil }
    }
}

// MARK: - styles.xml

/// Flattens styles.xml into a table of resolved SheetCellStyle, indexed by
/// cellXf position (what a cell's `s=` attribute points at).
private final class StylesParser: NSObject, XMLParserDelegate {
    private struct FontSpec {
        var bold = false
        var italic = false
        var size: CGFloat?
        var colorHex: String?
    }

    private let themeColors: [String]
    private var fonts: [FontSpec] = []
    private var fills: [String?] = []      // solid fill hex per fill index
    private var styles: [SheetCellStyle] = []

    private enum Section { case none, fonts, fills, cellXfs }
    private var section: Section = .none
    private var currentFont: FontSpec?
    private var insidePatternFill = false
    private var currentFillIsSolid = false
    private var currentFillHex: String?
    private var currentXfWrapsText = false
    private var currentXfFontId: Int?
    private var currentXfFillId: Int?
    private var insideXf = false

    private init(themeColors: [String]) {
        self.themeColors = themeColors
    }

    static func parse(_ data: Data, themeColors: [String]) throws -> [SheetCellStyle] {
        let delegate = StylesParser(themeColors: themeColors)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SheetWorkbookError.unreadable }
        return delegate.styles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "fonts": section = .fonts
        case "fills": section = .fills
        case "cellXfs": section = .cellXfs
        case "font" where section == .fonts:
            currentFont = FontSpec()
        case "b" where currentFont != nil: currentFont?.bold = true
        case "i" where currentFont != nil: currentFont?.italic = true
        case "sz" where currentFont != nil:
            currentFont?.size = (attributes["val"]).flatMap { Double($0) }.map { CGFloat($0) }
        case "color" where currentFont != nil:
            currentFont?.colorHex = resolveColor(attributes)
        case "fill" where section == .fills:
            currentFillIsSolid = false
            currentFillHex = nil
        case "patternFill" where section == .fills:
            insidePatternFill = true
            currentFillIsSolid = attributes["patternType"] == "solid"
        case "fgColor" where insidePatternFill && currentFillIsSolid:
            currentFillHex = resolveColor(attributes)
        case "xf" where section == .cellXfs:
            insideXf = true
            currentXfWrapsText = false
            currentXfFontId = attributes["fontId"].flatMap { Int($0) }
            currentXfFillId = attributes["fillId"].flatMap { Int($0) }
        case "alignment" where insideXf:
            currentXfWrapsText = attributes["wrapText"] == "1" || attributes["wrapText"] == "true"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "fonts", "fills", "cellXfs": section = .none
        case "font":
            if let font = currentFont { fonts.append(font) }
            currentFont = nil
        case "patternFill": insidePatternFill = false
        case "fill" where section == .fills:
            fills.append(currentFillIsSolid ? currentFillHex : nil)
        case "xf" where insideXf:
            insideXf = false
            styles.append(resolvedStyle())
        default:
            break
        }
    }

    private func resolvedStyle() -> SheetCellStyle {
        var style = SheetCellStyle()
        if let fontId = currentXfFontId, fonts.indices.contains(fontId) {
            let font = fonts[fontId]
            style.isBold = font.bold
            style.isItalic = font.italic
            style.fontPointSize = font.size
            style.textColorHex = font.colorHex
        }
        // Fill 0 is "none" and fill 1 the gray125 pattern by convention —
        // only explicit solid fills beyond those color a cell.
        if let fillId = currentXfFillId, fillId > 1, fills.indices.contains(fillId) {
            style.fillColorHex = fills[fillId]
        }
        style.wrapText = currentXfWrapsText
        return style
    }

    /// rgb="AARRGGBB|RRGGBB" wins; theme="n" (+ tint) resolves through the
    /// theme scheme; indexed/auto colors fall back to nil (default ink).
    private func resolveColor(_ attributes: [String: String]) -> String? {
        if let rgb = attributes["rgb"] {
            let hex = rgb.count == 8 ? String(rgb.suffix(6)) : rgb
            return hex.uppercased()
        }
        if let themeIndexString = attributes["theme"], let themeIndex = Int(themeIndexString),
           themeColors.indices.contains(themeIndex) {
            let base = themeColors[themeIndex]
            let tint = attributes["tint"].flatMap { Double($0) } ?? 0
            return XLSXColorMath.applyTint(tint, to: base)
        }
        return nil
    }

}

/// Excel tint math: negative darkens toward black, positive lightens toward
/// white (per-channel approximation, matching common reader behavior).
/// Internal (not private) so tests can pin the formula.
enum XLSXColorMath {
    static func applyTint(_ tint: Double, to hex: String) -> String {
        guard tint != 0, hex.count == 6, let value = UInt32(hex, radix: 16) else { return hex }
        func channel(_ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) }
        func tinted(_ c: Double) -> UInt32 {
            let result = tint < 0 ? c * (1 + tint) : c + (255 - c) * tint
            return UInt32(max(0, min(255, result.rounded())))
        }
        let r = tinted(channel(16)), g = tinted(channel(8)), b = tinted(channel(0))
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

// MARK: - worksheet xml

private final class WorksheetParser: NSObject, XMLParserDelegate {
    struct ParsedSheet {
        let rows: [[SheetCell]]
        let rowHeights: [CGFloat?]
        let columnWidths: [CGFloat?]?
        let mergeRanges: [String]
    }

    private let sharedStrings: [String]
    private let cellBudget: Int

    private var rows: [[SheetCell]] = []
    private var rowHeights: [CGFloat?] = []
    private var currentRow: [SheetCell] = []
    private var currentRowHeight: CGFloat?
    private var currentRowNumber = 0
    private var lastEmittedRowNumber = 0

    private var columnWidthRanges: [(min: Int, max: Int, width: CGFloat)] = []
    private var mergeRanges: [String] = []

    private var currentCellColumn = -1
    private var currentCellType = ""
    private var currentCellStyleIndex: Int?
    private var currentValue = ""
    private var capturingValue = false
    private var insideInlineString = false
    private var cellCount = 0
    private var overBudget = false

    private init(sharedStrings: [String], cellBudget: Int) {
        self.sharedStrings = sharedStrings
        self.cellBudget = cellBudget
    }

    static func parse(_ data: Data, sharedStrings: [String], cellBudget: Int) throws -> ParsedSheet {
        let delegate = WorksheetParser(sharedStrings: sharedStrings, cellBudget: cellBudget)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let finished = parser.parse()
        if delegate.overBudget {
            throw SheetWorkbookError.tooLarge(cellCount: delegate.cellCount)
        }
        guard finished else { throw SheetWorkbookError.unreadable }
        return ParsedSheet(
            rows: delegate.rows,
            rowHeights: delegate.rowHeights,
            columnWidths: delegate.resolvedColumnWidths(),
            mergeRanges: delegate.mergeRanges
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "col":
            // Excel's width unit is character-count based; the widely used
            // conversion to logical pixels is width × 7 + 5 (Calibri 11).
            if let minString = attributes["min"], let maxString = attributes["max"],
               let widthString = attributes["width"],
               let minColumn = Int(minString), let maxColumn = Int(maxString),
               let width = Double(widthString) {
                let clampedMax = min(maxColumn, 1_024)
                columnWidthRanges.append((
                    min: minColumn - 1,
                    max: clampedMax - 1,
                    width: CGFloat(width * 7 + 5)
                ))
            }
        case "row":
            currentRow = []
            currentRowNumber = Int(attributes["r"] ?? "") ?? (lastEmittedRowNumber + 1)
            // ht is typography points; logical px at 96dpi is ×4/3 (Excel's
            // default 15pt row renders 20px).
            currentRowHeight = attributes["ht"].flatMap { Double($0) }.map { CGFloat($0 * 4 / 3) }
        case "c":
            // Column from the A1-style ref; a missing ref means "next cell".
            if let ref = attributes["r"], let column = WorksheetCellReference.columnIndex(ref) {
                currentCellColumn = column
            } else {
                currentCellColumn = currentRow.count
            }
            currentCellType = attributes["t"] ?? ""
            currentCellStyleIndex = attributes["s"].flatMap { Int($0) }
            currentValue = ""
        case "mergeCell":
            if let ref = attributes["ref"] { mergeRanges.append(ref) }
        case "is":
            insideInlineString = true
        case "v":
            capturingValue = true
        case "t" where insideInlineString:
            capturingValue = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingValue {
            currentValue += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "v", "t":
            capturingValue = false
        case "is":
            insideInlineString = false
        case "c":
            placeCurrentCell()
        case "row":
            emitCurrentRow(parser: parser)
        default:
            break
        }
    }

    private func resolvedColumnWidths() -> [CGFloat?]? {
        guard !columnWidthRanges.isEmpty else { return nil }
        let highestColumn = columnWidthRanges.map(\.max).max() ?? 0
        var widths = [CGFloat?](repeating: nil, count: highestColumn + 1)
        for range in columnWidthRanges {
            guard range.min >= 0 else { continue }
            for column in range.min...range.max where widths.indices.contains(column) {
                widths[column] = range.width
            }
        }
        return widths
    }

    private func placeCurrentCell() {
        let cell = SheetCell(text: displayValue(), styleIndex: currentCellStyleIndex)
        guard currentCellColumn >= 0 else { return }
        if currentRow.count < currentCellColumn {
            currentRow.append(contentsOf: Array(repeating: .empty, count: currentCellColumn - currentRow.count))
        }
        if currentRow.count == currentCellColumn {
            currentRow.append(cell)
        } else if currentCellColumn < currentRow.count {
            currentRow[currentCellColumn] = cell
        }
        currentCellColumn = -1
        currentCellStyleIndex = nil
    }

    private func emitCurrentRow(parser: XMLParser) {
        // Preserve vertical layout: skipped row numbers become empty rows.
        while lastEmittedRowNumber + 1 < currentRowNumber {
            rows.append([])
            rowHeights.append(nil)
            lastEmittedRowNumber += 1
        }
        rows.append(currentRow)
        rowHeights.append(currentRowHeight)
        lastEmittedRowNumber = currentRowNumber

        cellCount += max(currentRow.count, 1)
        if cellCount > cellBudget {
            overBudget = true
            parser.abortParsing()
        }
    }

    private func displayValue() -> String {
        switch currentCellType {
        case "s":
            guard let index = Int(currentValue), sharedStrings.indices.contains(index) else { return "" }
            return sharedStrings[index]
        case "b":
            return currentValue == "1" ? "TRUE" : "FALSE"
        case "inlineStr", "str", "e":
            return currentValue
        default:
            // Numeric (or untyped). Values are decimal text; integral doubles
            // drop the trailing ".0" Excel never shows. Style-driven date
            // formats are out of the preview slice — serials display raw.
            guard !currentValue.isEmpty else { return "" }
            if let number = Double(currentValue),
               number.truncatingRemainder(dividingBy: 1) == 0,
               abs(number) < 1e15,
               !currentValue.lowercased().contains("e") {
                return String(Int64(number))
            }
            return currentValue
        }
    }
}

// MARK: - Cell reference math

enum WorksheetCellReference {
    /// "BC23" → zero-based column 54. Nil when the ref has no letters.
    static func columnIndex(_ ref: String) -> Int? {
        var column = 0
        var sawLetter = false
        for scalar in ref.unicodeScalars {
            guard scalar.properties.isAlphabetic else { break }
            let upper = Character(scalar).uppercased().unicodeScalars.first!
            guard upper.value >= 65, upper.value <= 90 else { return nil }
            column = column * 26 + Int(upper.value - 64)
            sawLetter = true
        }
        return sawLetter ? column - 1 : nil
    }

    /// "BC23" → zero-based row 22. Nil when the ref has no digits.
    static func rowIndex(_ ref: String) -> Int? {
        let digits = ref.drop { !$0.isNumber }
        guard let number = Int(digits), number > 0 else { return nil }
        return number - 1
    }

    /// Zero-based column 54 → "BC".
    static func columnLetters(_ index: Int) -> String {
        var value = index + 1
        var letters = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            letters = String(UnicodeScalar(UInt8(65 + remainder))) + letters
            value = (value - 1) / 26
        }
        return letters
    }

    /// Zero-based (row, column) → "BC23".
    static func reference(rowIndex: Int, columnIndex: Int) -> String {
        columnLetters(columnIndex) + String(rowIndex + 1)
    }
}
