// CosmoOS/Services/FilePortalSheetModel.swift
// Immutable sheet model for spreadsheet portals, plus the cache that keeps
// parsing off the render path. The DecodedColumnCache lesson applies here:
// decode-per-access is THE lag — a workbook parses once per (uuid, stamp)
// and every grid frame reads the cached value type.
//
// Fidelity contract (July 18 round 2): cells carry their resolved style
// index, horizontal merge span, and the file's own column widths and row
// heights — the grid renders what Excel rendered, not an estimate of it.

import Foundation

// MARK: - Cells & styles

/// One resolved cell style — flattened from styles.xml at parse time so the
/// render path never touches XML structures.
struct SheetCellStyle: Equatable, Sendable {
    var isBold = false
    var isItalic = false
    var fontPointSize: CGFloat?
    /// "RRGGBB" — text ink; nil = default ink.
    var textColorHex: String?
    /// "RRGGBB" — solid fill; nil = no fill.
    var fillColorHex: String?
    var wrapText = false

    static let plain = SheetCellStyle()
}

struct SheetCell: Equatable, Sendable {
    var text: String
    /// Index into SheetWorkbook.styles; nil = unstyled.
    var styleIndex: Int?
    /// 1 = normal cell. >1 = horizontal-merge anchor spanning that many
    /// columns. 0 = covered by a preceding anchor (not rendered).
    var columnSpan: Int

    init(text: String, styleIndex: Int? = nil, columnSpan: Int = 1) {
        self.text = text
        self.styleIndex = styleIndex
        self.columnSpan = columnSpan
    }

    static let empty = SheetCell(text: "")
}

// MARK: - Model

/// One parsed worksheet: dense row-major cells (every row padded to
/// `columnCount`) plus the file's own geometry when it declares any.
struct SheetModel: Equatable, Sendable {
    let name: String
    let rows: [[SheetCell]]
    let columnCount: Int
    /// Per-column widths in points from `<cols>`; nil entries = no custom
    /// width for that column; nil array = file declared none at all.
    let fileColumnWidths: [CGFloat?]?
    /// Per-row heights in points from `ht=`; index-aligned with `rows`.
    let fileRowHeights: [CGFloat?]?

    var rowCount: Int { rows.count }
    var cellCount: Int { rows.count * columnCount }
    var plainRows: [[String]] { rows.map { $0.map(\.text) } }

    init(
        name: String,
        rows: [[SheetCell]],
        fileColumnWidths: [CGFloat?]? = nil,
        fileRowHeights: [CGFloat?]? = nil
    ) {
        let columnCount = rows.map(\.count).max() ?? 0
        self.name = name
        self.columnCount = columnCount
        self.rows = rows.map { row in
            row.count == columnCount
                ? row
                : row + Array(repeating: .empty, count: columnCount - row.count)
        }
        if let fileColumnWidths, !fileColumnWidths.isEmpty {
            self.fileColumnWidths = (0..<columnCount).map { index in
                fileColumnWidths.indices.contains(index) ? fileColumnWidths[index] : nil
            }
        } else {
            self.fileColumnWidths = nil
        }
        if let fileRowHeights, !fileRowHeights.isEmpty {
            self.fileRowHeights = (0..<self.rows.count).map { index in
                fileRowHeights.indices.contains(index) ? fileRowHeights[index] : nil
            }
        } else {
            self.fileRowHeights = nil
        }
    }

    /// Plain-text convenience (CSV path, tests).
    init(name: String, rows: [[String]]) {
        self.init(name: name, rows: rows.map { row in row.map { SheetCell(text: $0) } })
    }
}

/// A parsed workbook: sheets plus the flattened style table their cells index.
struct SheetWorkbook: Equatable, Sendable {
    let sheets: [SheetModel]
    let styles: [SheetCellStyle]

    init(sheets: [SheetModel], styles: [SheetCellStyle] = []) {
        self.sheets = sheets
        self.styles = styles
    }

    var totalCellCount: Int { sheets.reduce(0) { $0 + $1.cellCount } }

    func style(for cell: SheetCell) -> SheetCellStyle {
        guard let index = cell.styleIndex, styles.indices.contains(index) else { return .plain }
        return styles[index]
    }

    /// Optimistic-edit helper: a copy with one cell's text replaced (rows
    /// padded as needed). The cell keeps its style; disk persistence runs
    /// separately through FilePortalEditService.
    func updatingCell(sheetIndex: Int, rowIndex: Int, columnIndex: Int, text: String) -> SheetWorkbook {
        guard sheets.indices.contains(sheetIndex) else { return self }
        let sheet = sheets[sheetIndex]
        var rows = sheet.rows
        while rows.count <= rowIndex { rows.append([]) }
        while rows[rowIndex].count <= columnIndex { rows[rowIndex].append(.empty) }
        rows[rowIndex][columnIndex].text = text
        var newSheets = sheets
        newSheets[sheetIndex] = SheetModel(
            name: sheet.name,
            rows: rows,
            fileColumnWidths: sheet.fileColumnWidths,
            fileRowHeights: sheet.fileRowHeights
        )
        return SheetWorkbook(sheets: newSheets, styles: styles)
    }
}

enum SheetWorkbookError: LocalizedError {
    case unreadable
    case unsupportedFormat(String)
    case tooLarge(cellCount: Int)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Couldn't read the spreadsheet"
        case .unsupportedFormat(let ext): return "Unsupported spreadsheet format: .\(ext)"
        case .tooLarge(let cellCount): return "Sheet too large to preview (\(cellCount) cells)"
        }
    }
}

// MARK: - Loader

enum SheetWorkbookLoader {
    /// Hard cap before a workbook degrades to the Tier-0 thumbnail card —
    /// portals preview sheets, they don't replace Excel.
    static let maxCellCount = 200_000

    /// Parse a spreadsheet file into a workbook. Pure + synchronous — call it
    /// off-main (SheetModelCache does).
    static func load(url: URL) throws -> SheetWorkbook {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "csv", "tsv":
            guard let data = try? Data(contentsOf: url) else { throw SheetWorkbookError.unreadable }
            let text = Self.decodeText(data)
            let rows = CSVTableParser.parse(text, delimiter: ext == "tsv" ? "\t" : ",")
            let sheet = SheetModel(name: url.deletingPathExtension().lastPathComponent, rows: rows)
            try Self.enforceCellCap(sheet.cellCount)
            return SheetWorkbook(sheets: [sheet])
        case "xlsx", "xlsm", "xltx":
            let workbook = try XLSXWorkbookReader.read(url: url)
            try Self.enforceCellCap(workbook.totalCellCount)
            return workbook
        default:
            throw SheetWorkbookError.unsupportedFormat(ext)
        }
    }

    private static func enforceCellCap(_ cellCount: Int) throws {
        guard cellCount <= maxCellCount else {
            throw SheetWorkbookError.tooLarge(cellCount: cellCount)
        }
    }

    /// UTF-8 first (with BOM strip), then UTF-16, then Latin-1 — CSVs in the
    /// wild are messy and an encoding miss must not kill the portal.
    private static func decodeText(_ data: Data) -> String {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
        }
        return String(data: bytes, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}

// MARK: - Cache

/// Workbooks parse once, off-main, and are shared by every surface (block
/// grid, peek grid). Keyed attachmentUUID + stamp; capped LRU-ish by
/// insertion order because workbooks are bounded by maxCellCount anyway.
actor SheetModelCache {
    static let shared = SheetModelCache()

    private var cache: [String: SheetWorkbook] = [:]
    private var insertionOrder: [String] = []
    private var inFlight: [String: Task<SheetWorkbook, Error>] = [:]
    private let capacity = 12

    func workbook(for fileURL: URL, cacheKey: String, stamp: String?) async throws -> SheetWorkbook {
        let key = "\(cacheKey)|\(stamp ?? "-")"
        if let cached = cache[key] {
            return cached
        }
        if let running = inFlight[key] {
            return try await running.value
        }
        let task = Task.detached(priority: .userInitiated) {
            try SheetWorkbookLoader.load(url: fileURL)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let workbook = try await task.value
        store(workbook, key: key)
        return workbook
    }

    /// Drop every cached parse for an attachment — called after an in-portal
    /// edit rewrites the file (the stamp also changes, this is belt+braces
    /// for surfaces still holding the old stamp).
    func invalidate(cacheKey: String) {
        let prefix = "\(cacheKey)|"
        for key in insertionOrder where key.hasPrefix(prefix) {
            cache[key] = nil
        }
        insertionOrder.removeAll { $0.hasPrefix(prefix) }
    }

    private func store(_ workbook: SheetWorkbook, key: String) {
        if cache[key] == nil {
            insertionOrder.append(key)
        }
        cache[key] = workbook
        while insertionOrder.count > capacity, let evicted = insertionOrder.first {
            insertionOrder.removeFirst()
            cache[evicted] = nil
        }
    }
}
