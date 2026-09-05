// TWIN FILE — byte-identical in CosmoOS-Swift/Editor/Model and
// CosmoOS-iOS/CosmoCoreKit/Sources/Models. Verified by Tools/verify_twins.sh.
//
// The table block model. GRID LAW: a table is always rectangular — every
// row carries exactly `columns.count` cells. Merged cells are explicit: the
// top-left cell is the ANCHOR (rowSpan/colSpan > 1) and every other position
// inside its rectangle is a COVERED cell (`coveredBy == anchor.id`, no
// content). Never store a sparse HTML-style grid; every operation validates.

import Foundation

public enum RichTableAlignment: String, Codable, Hashable, Sendable, CaseIterable {
    case leading
    case center
    case trailing
}

public enum RichTableVerticalAlignment: String, Codable, Hashable, Sendable, CaseIterable {
    case top
    case middle
    case bottom
}

/// The three looks. `grid` = every rule; `lines` = horizontal rules only
/// (editorial comparison tables); `clean` = no rules, one rule under the
/// header.
public enum RichTableStyle: String, Codable, Hashable, Sendable, CaseIterable {
    case grid
    case lines
    case clean
}

public struct RichTableCellAddress: Hashable, Sendable, Codable, Comparable {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public static func < (lhs: RichTableCellAddress, rhs: RichTableCellAddress) -> Bool {
        lhs.row != rhs.row ? lhs.row < rhs.row : lhs.column < rhs.column
    }

    public func offset(rows: Int = 0, columns: Int = 0) -> RichTableCellAddress {
        RichTableCellAddress(row: row + rows, column: column + columns)
    }
}

/// An inclusive rectangle of cells. Normalised on construction so any two
/// corners describe it.
public struct RichTableRect: Hashable, Sendable, Codable {
    public var rows: ClosedRange<Int>
    public var columns: ClosedRange<Int>

    public init(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        self.rows = rows
        self.columns = columns
    }

    public init(_ a: RichTableCellAddress, _ b: RichTableCellAddress) {
        rows = min(a.row, b.row)...max(a.row, b.row)
        columns = min(a.column, b.column)...max(a.column, b.column)
    }

    public init(cell: RichTableCellAddress) {
        rows = cell.row...cell.row
        columns = cell.column...cell.column
    }

    public var topLeft: RichTableCellAddress { RichTableCellAddress(row: rows.lowerBound, column: columns.lowerBound) }
    public var bottomRight: RichTableCellAddress { RichTableCellAddress(row: rows.upperBound, column: columns.upperBound) }
    public var cellCount: Int { rows.count * columns.count }
    public var isSingleCell: Bool { cellCount == 1 }

    public func contains(_ address: RichTableCellAddress) -> Bool {
        rows.contains(address.row) && columns.contains(address.column)
    }

    public func contains(_ other: RichTableRect) -> Bool {
        rows.lowerBound <= other.rows.lowerBound && rows.upperBound >= other.rows.upperBound
            && columns.lowerBound <= other.columns.lowerBound && columns.upperBound >= other.columns.upperBound
    }

    public func intersects(_ other: RichTableRect) -> Bool {
        rows.overlaps(other.rows) && columns.overlaps(other.columns)
    }

    public var addresses: [RichTableCellAddress] {
        rows.flatMap { row in columns.map { RichTableCellAddress(row: row, column: $0) } }
    }
}

public enum RichTableSelection: Hashable, Sendable {
    case cell(RichTableCellAddress)
    case range(RichTableRect)
    case rows(ClosedRange<Int>)
    case columns(ClosedRange<Int>)
    case table

    /// The rectangle of cells this selection covers in `table`.
    public func rect(in table: RichTable) -> RichTableRect? {
        guard table.rowCount > 0, table.columnCount > 0 else { return nil }
        switch self {
        case .cell(let address):
            return RichTableRect(cell: address)
        case .range(let rect):
            return rect
        case .rows(let rows):
            return RichTableRect(rows: rows, columns: 0...(table.columnCount - 1))
        case .columns(let columns):
            return RichTableRect(rows: 0...(table.rowCount - 1), columns: columns)
        case .table:
            return RichTableRect(rows: 0...(table.rowCount - 1), columns: 0...(table.columnCount - 1))
        }
    }
}

public struct RichTableColumn: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// Relative width. Resolved width = weight / Σweights × available.
    public var weight: Double
    public var alignment: RichTableAlignment

    public init(id: UUID = UUID(), weight: Double = 1, alignment: RichTableAlignment = .leading) {
        self.id = id
        self.weight = weight
        self.alignment = alignment
    }

    private enum CodingKeys: String, CodingKey { case id, weight, alignment }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        let decodedWeight = (try? container.decodeIfPresent(Double.self, forKey: .weight)) ?? 1
        weight = decodedWeight.isFinite && decodedWeight > 0 ? decodedWeight : 1
        alignment = (try? container.decodeIfPresent(RichTableAlignment.self, forKey: .alignment)) ?? .leading
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(weight, forKey: .weight)
        try container.encode(alignment, forKey: .alignment)
    }
}

public struct RichTableCell: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// One rich paragraph. Soft breaks are U+2028. Mentions allowed.
    public var inlines: [RichInlineNode]
    /// NoteInkPalette tone id for the cell wash; nil = none.
    public var toneID: String?
    public var rowSpan: Int
    public var colSpan: Int
    /// The anchor cell id when this position lies inside a merged span.
    public var coveredBy: UUID?
    /// Overrides the column alignment when set.
    public var alignment: RichTableAlignment?
    public var verticalAlignment: RichTableVerticalAlignment?
    public var passthrough: [String: JSONValue]

    public init(
        id: UUID = UUID(),
        inlines: [RichInlineNode] = [],
        toneID: String? = nil,
        rowSpan: Int = 1,
        colSpan: Int = 1,
        coveredBy: UUID? = nil,
        alignment: RichTableAlignment? = nil,
        verticalAlignment: RichTableVerticalAlignment? = nil,
        passthrough: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.inlines = inlines
        self.toneID = toneID
        self.rowSpan = max(1, rowSpan)
        self.colSpan = max(1, colSpan)
        self.coveredBy = coveredBy
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.passthrough = passthrough
    }

    public static func text(_ text: String) -> RichTableCell {
        RichTableCell(inlines: text.isEmpty ? [] : [.text(text)])
    }

    public static func covered(by anchor: UUID) -> RichTableCell {
        RichTableCell(coveredBy: anchor)
    }

    public var isCovered: Bool { coveredBy != nil }
    public var isSpanAnchor: Bool { rowSpan > 1 || colSpan > 1 }
    public var plainText: String { inlines.map(\.plainText).joined() }
    public var isEmptyContent: Bool {
        inlines.allSatisfy { node in
            switch node.kind {
            case .text: return (node.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .mention, .imageRef: return false
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, inlines, toneID, rowSpan, colSpan, coveredBy, alignment, verticalAlignment
        static var known: Set<String> { Set(["id", "inlines", "toneID", "rowSpan", "colSpan", "coveredBy", "alignment", "verticalAlignment"]) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        inlines = (try? container.decodeIfPresent([RichInlineNode].self, forKey: .inlines)) ?? []
        toneID = try? container.decodeIfPresent(String.self, forKey: .toneID)
        rowSpan = max(1, (try? container.decodeIfPresent(Int.self, forKey: .rowSpan)) ?? 1)
        colSpan = max(1, (try? container.decodeIfPresent(Int.self, forKey: .colSpan)) ?? 1)
        coveredBy = try? container.decodeIfPresent(UUID.self, forKey: .coveredBy)
        alignment = try? container.decodeIfPresent(RichTableAlignment.self, forKey: .alignment)
        verticalAlignment = try? container.decodeIfPresent(RichTableVerticalAlignment.self, forKey: .verticalAlignment)
        passthrough = RichPassthrough.unknownKeys(from: decoder, known: CodingKeys.known)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(inlines, forKey: .inlines)
        try container.encodeIfPresent(toneID, forKey: .toneID)
        if rowSpan > 1 { try container.encode(rowSpan, forKey: .rowSpan) }
        if colSpan > 1 { try container.encode(colSpan, forKey: .colSpan) }
        try container.encodeIfPresent(coveredBy, forKey: .coveredBy)
        try container.encodeIfPresent(alignment, forKey: .alignment)
        try container.encodeIfPresent(verticalAlignment, forKey: .verticalAlignment)
        try RichPassthrough.encode(passthrough, to: encoder, known: CodingKeys.known)
    }
}

public struct RichTableRow: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var cells: [RichTableCell]

    public init(id: UUID = UUID(), cells: [RichTableCell]) {
        self.id = id
        self.cells = cells
    }

    private enum CodingKeys: String, CodingKey { case id, cells }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        cells = (try? container.decodeIfPresent([RichTableCell].self, forKey: .cells)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(cells, forKey: .cells)
    }
}

public enum RichTableViolation: Equatable, Sendable {
    case noRows
    case noColumns
    case raggedRow(Int)
    case coveredCellCarriesContent(RichTableCellAddress)
    case spanOutOfBounds(anchor: RichTableCellAddress)
    case overlappingSpans(RichTableCellAddress)
    case danglingCover(RichTableCellAddress)
    case spanCrossesHeader(anchor: RichTableCellAddress)
    case nonPositiveWeight(column: Int)
    case duplicateID
}

public struct RichTable: Codable, Hashable, Sendable {
    public var columns: [RichTableColumn]
    public var rows: [RichTableRow]
    public var hasHeaderRow: Bool
    public var hasHeaderColumn: Bool
    public var style: RichTableStyle
    public var isStriped: Bool
    public var passthrough: [String: JSONValue]

    /// The narrowest a column may render, in points at the standard 17 pt
    /// body size. Hosts scale it with the body point size (4.2 × size).
    public static let minimumColumnWidth: Double = 72
    public static let defaultRowCount = 3
    public static let defaultColumnCount = 3

    public init(
        columns: [RichTableColumn],
        rows: [RichTableRow],
        hasHeaderRow: Bool = true,
        hasHeaderColumn: Bool = false,
        style: RichTableStyle = .grid,
        isStriped: Bool = false,
        passthrough: [String: JSONValue] = [:]
    ) {
        self.columns = columns
        self.rows = rows
        self.hasHeaderRow = hasHeaderRow
        self.hasHeaderColumn = hasHeaderColumn
        self.style = style
        self.isStriped = isStriped
        self.passthrough = passthrough
    }

    /// An empty grid.
    public init(rowCount: Int = RichTable.defaultRowCount, columnCount: Int = RichTable.defaultColumnCount, hasHeaderRow: Bool = true) {
        let safeColumns = max(1, columnCount)
        let safeRows = max(1, rowCount)
        columns = (0..<safeColumns).map { _ in RichTableColumn() }
        rows = (0..<safeRows).map { _ in RichTableRow(cells: (0..<safeColumns).map { _ in RichTableCell() }) }
        self.hasHeaderRow = hasHeaderRow
        hasHeaderColumn = false
        style = .grid
        isStriped = false
        passthrough = [:]
    }

    /// A grid from plain strings — rows of cells. Ragged input is padded.
    public init(strings: [[String]], hasHeaderRow: Bool = true) {
        let columnCount = max(1, strings.map(\.count).max() ?? 1)
        columns = (0..<columnCount).map { _ in RichTableColumn() }
        rows = strings.map { row in
            var cells = row.map { RichTableCell.text($0) }
            while cells.count < columnCount { cells.append(RichTableCell()) }
            return RichTableRow(cells: cells)
        }
        if rows.isEmpty { rows = [RichTableRow(cells: (0..<columnCount).map { _ in RichTableCell() })] }
        self.hasHeaderRow = hasHeaderRow
        hasHeaderColumn = false
        style = .grid
        isStriped = false
        passthrough = [:]
    }

    // MARK: Shape

    public var rowCount: Int { rows.count }
    public var columnCount: Int { columns.count }
    public var headerRowIndex: Int? { hasHeaderRow && !rows.isEmpty ? 0 : nil }
    public var bodyRowIndices: Range<Int> { (hasHeaderRow && rows.count > 0 ? 1 : 0)..<rows.count }

    public func contains(_ address: RichTableCellAddress) -> Bool {
        address.row >= 0 && address.row < rowCount && address.column >= 0 && address.column < columnCount
    }

    public subscript(address: RichTableCellAddress) -> RichTableCell {
        get { rows[address.row].cells[address.column] }
        set { rows[address.row].cells[address.column] = newValue }
    }

    public func cell(at address: RichTableCellAddress) -> RichTableCell? {
        guard contains(address) else { return nil }
        return self[address]
    }

    public func address(ofCellID id: UUID) -> RichTableCellAddress? {
        for (rowIndex, row) in rows.enumerated() {
            if let columnIndex = row.cells.firstIndex(where: { $0.id == id }) {
                return RichTableCellAddress(row: rowIndex, column: columnIndex)
            }
        }
        return nil
    }

    /// The anchor for any position: itself, or the cell that covers it.
    public func anchorAddress(of address: RichTableCellAddress) -> RichTableCellAddress {
        guard contains(address) else { return address }
        let cell = self[address]
        if let anchorID = cell.coveredBy, let anchor = self.address(ofCellID: anchorID) {
            return anchor
        }
        return address
    }

    public func isCovered(_ address: RichTableCellAddress) -> Bool {
        cell(at: address)?.isCovered ?? false
    }

    /// The rectangle an anchor spans (its own cell when unmerged).
    public func spanRect(ofAnchorAt address: RichTableCellAddress) -> RichTableRect {
        guard let cell = cell(at: address) else { return RichTableRect(cell: address) }
        let lastRow = min(rowCount - 1, address.row + cell.rowSpan - 1)
        let lastColumn = min(columnCount - 1, address.column + cell.colSpan - 1)
        return RichTableRect(rows: address.row...max(address.row, lastRow), columns: address.column...max(address.column, lastColumn))
    }

    /// Every anchor (unmerged cell or span anchor) whose rectangle touches `rect`.
    public func anchors(intersecting rect: RichTableRect) -> [RichTableCellAddress] {
        var seen = Set<RichTableCellAddress>()
        var result: [RichTableCellAddress] = []
        for address in rect.addresses where contains(address) {
            let anchor = anchorAddress(of: address)
            if seen.insert(anchor).inserted { result.append(anchor) }
        }
        return result
    }

    /// The smallest rectangle containing `rect` and every span it touches.
    public func expandedToSpans(_ rect: RichTableRect) -> RichTableRect {
        var current = rect
        var changed = true
        while changed {
            changed = false
            for anchor in anchors(intersecting: current) {
                let span = spanRect(ofAnchorAt: anchor)
                let union = RichTableRect(
                    rows: min(current.rows.lowerBound, span.rows.lowerBound)...max(current.rows.upperBound, span.rows.upperBound),
                    columns: min(current.columns.lowerBound, span.columns.lowerBound)...max(current.columns.upperBound, span.columns.upperBound)
                )
                if union != current {
                    current = union
                    changed = true
                }
            }
        }
        return current
    }

    public var isEmptyContent: Bool {
        rows.allSatisfy { $0.cells.allSatisfy(\.isEmptyContent) }
    }

    public var hasAnySpan: Bool {
        rows.contains { $0.cells.contains(where: \.isSpanAnchor) }
    }

    public var hasVerticalSpanInBody: Bool {
        for rowIndex in bodyRowIndices {
            if rows[rowIndex].cells.contains(where: { $0.rowSpan > 1 }) { return true }
        }
        return false
    }

    // MARK: Widths

    /// Column widths for `available` points honouring `minimum` per column.
    /// When the floor cannot be met the widths sum past `available` and the
    /// host scrolls horizontally.
    public func resolvedColumnWidths(available: Double, minimum: Double = RichTable.minimumColumnWidth) -> [Double] {
        guard !columns.isEmpty else { return [] }
        let totalWeight = columns.reduce(0) { $0 + max($1.weight, 0.0001) }
        let raw = columns.map { max($0.weight, 0.0001) / totalWeight * available }
        if raw.allSatisfy({ $0 >= minimum }) { return raw }
        // Lift floored columns to the minimum and share the remainder by weight.
        var widths = Array(repeating: 0.0, count: columns.count)
        var floored = Set<Int>()
        var remaining = available
        var remainingWeight = totalWeight
        var progress = true
        while progress {
            progress = false
            for (index, column) in columns.enumerated() where !floored.contains(index) {
                let proposed = remainingWeight > 0 ? max(column.weight, 0.0001) / remainingWeight * remaining : minimum
                if proposed < minimum {
                    floored.insert(index)
                    widths[index] = minimum
                    remaining -= minimum
                    remainingWeight -= max(column.weight, 0.0001)
                    progress = true
                }
            }
        }
        for (index, column) in columns.enumerated() where !floored.contains(index) {
            widths[index] = remainingWeight > 0 ? max(column.weight, 0.0001) / remainingWeight * max(remaining, 0) : minimum
            widths[index] = max(widths[index], minimum)
        }
        return widths
    }

    // MARK: Validation

    public func validate() -> [RichTableViolation] {
        var violations: [RichTableViolation] = []
        if rows.isEmpty { violations.append(.noRows) }
        if columns.isEmpty { violations.append(.noColumns) }
        guard !rows.isEmpty, !columns.isEmpty else { return violations }

        for (index, column) in columns.enumerated() where !(column.weight > 0) || !column.weight.isFinite {
            violations.append(.nonPositiveWeight(column: index))
        }
        for (index, row) in rows.enumerated() where row.cells.count != columns.count {
            violations.append(.raggedRow(index))
        }
        guard !violations.contains(where: { if case .raggedRow = $0 { return true } else { return false } }) else {
            return violations
        }

        var ids = Set<UUID>()
        var coverage: [RichTableCellAddress: UUID] = [:]
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, cell) in row.cells.enumerated() {
                if !ids.insert(cell.id).inserted { violations.append(.duplicateID) }
                let address = RichTableCellAddress(row: rowIndex, column: columnIndex)
                if cell.isCovered {
                    if !cell.inlines.isEmpty || cell.rowSpan > 1 || cell.colSpan > 1 || cell.toneID != nil {
                        violations.append(.coveredCellCarriesContent(address))
                    }
                    continue
                }
                guard cell.isSpanAnchor else { continue }
                let lastRow = rowIndex + cell.rowSpan - 1
                let lastColumn = columnIndex + cell.colSpan - 1
                if lastRow >= rowCount || lastColumn >= columnCount {
                    violations.append(.spanOutOfBounds(anchor: address))
                    continue
                }
                if hasHeaderRow, rowIndex == 0, cell.rowSpan > 1 {
                    violations.append(.spanCrossesHeader(anchor: address))
                }
                for r in rowIndex...lastRow {
                    for c in columnIndex...lastColumn where !(r == rowIndex && c == columnIndex) {
                        let covered = RichTableCellAddress(row: r, column: c)
                        if coverage[covered] != nil {
                            violations.append(.overlappingSpans(covered))
                        }
                        coverage[covered] = cell.id
                    }
                }
            }
        }
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, cell) in row.cells.enumerated() {
                let address = RichTableCellAddress(row: rowIndex, column: columnIndex)
                if let anchorID = cell.coveredBy {
                    if coverage[address] != anchorID { violations.append(.danglingCover(address)) }
                } else if coverage[address] != nil {
                    // A position inside a span that is not marked covered.
                    violations.append(.danglingCover(address))
                }
            }
        }
        return violations
    }

    /// Best-effort repair for documents written by buggy or older builds:
    /// pads short rows, trims long ones, dissolves spans that do not fit
    /// and clears covers that point nowhere. Never throws, never loses
    /// cell text (dissolved covers keep whatever text they carried).
    public func repaired() -> RichTable {
        var table = self
        if table.columns.isEmpty {
            let width = table.rows.map(\.cells.count).max() ?? 1
            table.columns = (0..<max(1, width)).map { _ in RichTableColumn() }
        }
        for index in table.columns.indices where !(table.columns[index].weight > 0) || !table.columns[index].weight.isFinite {
            table.columns[index].weight = 1
        }
        if table.rows.isEmpty {
            table.rows = [RichTableRow(cells: table.columns.map { _ in RichTableCell() })]
        }
        let width = table.columns.count
        for index in table.rows.indices {
            while table.rows[index].cells.count < width { table.rows[index].cells.append(RichTableCell()) }
            if table.rows[index].cells.count > width { table.rows[index].cells.removeLast(table.rows[index].cells.count - width) }
        }
        var ids = Set<UUID>()
        for r in table.rows.indices {
            for c in table.rows[r].cells.indices where !ids.insert(table.rows[r].cells[c].id).inserted {
                table.rows[r].cells[c].id = UUID()
            }
        }
        // Dissolve spans that overflow or cross the header; clear their covers.
        for r in table.rows.indices {
            for c in table.rows[r].cells.indices {
                let cell = table.rows[r].cells[c]
                guard cell.isSpanAnchor, !cell.isCovered else { continue }
                let overflows = r + cell.rowSpan > table.rowCount || c + cell.colSpan > table.columnCount
                let crossesHeader = table.hasHeaderRow && r == 0 && cell.rowSpan > 1
                if overflows || crossesHeader {
                    table.rows[r].cells[c].rowSpan = 1
                    table.rows[r].cells[c].colSpan = 1
                }
            }
        }
        // Rebuild coverage from the surviving anchors; anything covered by
        // a missing anchor becomes a plain cell again.
        var coverage: [RichTableCellAddress: UUID] = [:]
        for r in table.rows.indices {
            for c in table.rows[r].cells.indices {
                let cell = table.rows[r].cells[c]
                guard cell.isSpanAnchor, !cell.isCovered else { continue }
                for rr in r..<(r + cell.rowSpan) {
                    for cc in c..<(c + cell.colSpan) where !(rr == r && cc == c) {
                        let address = RichTableCellAddress(row: rr, column: cc)
                        if coverage[address] != nil {
                            // Overlap: the later anchor loses its span.
                            table.rows[r].cells[c].rowSpan = 1
                            table.rows[r].cells[c].colSpan = 1
                        } else {
                            coverage[address] = cell.id
                        }
                    }
                }
            }
        }
        for r in table.rows.indices {
            for c in table.rows[r].cells.indices {
                let address = RichTableCellAddress(row: r, column: c)
                if let anchor = coverage[address] {
                    var covered = table.rows[r].cells[c]
                    covered.coveredBy = anchor
                    covered.rowSpan = 1
                    covered.colSpan = 1
                    covered.toneID = nil
                    covered.inlines = []
                    table.rows[r].cells[c] = covered
                } else if table.rows[r].cells[c].coveredBy != nil {
                    table.rows[r].cells[c].coveredBy = nil
                }
            }
        }
        return table
    }

    // MARK: Text

    /// GitHub pipe-table lines — the note's plain text, search body, the
    /// assistant digest, and markdown copy all speak this.
    public func markdownLines() -> [String] {
        guard !rows.isEmpty, !columns.isEmpty else { return [] }
        func render(_ cell: RichTableCell) -> String {
            guard !cell.isCovered else { return "" }
            return cell.plainText
                .replacingOccurrences(of: "\u{2028}", with: "<br>")
                .replacingOccurrences(of: "\n", with: "<br>")
                .replacingOccurrences(of: "|", with: "\\|")
                .trimmingCharacters(in: .whitespaces)
        }
        func line(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }
        let separator = line(columns.map { column in
            switch column.alignment {
            case .leading: return "---"
            case .center: return ":---:"
            case .trailing: return "---:"
            }
        })
        var lines: [String] = []
        if hasHeaderRow {
            lines.append(line(rows[0].cells.map(render)))
            lines.append(separator)
            for row in rows.dropFirst() { lines.append(line(row.cells.map(render))) }
        } else {
            lines.append(line(columns.map { _ in "" }))
            lines.append(separator)
            for row in rows { lines.append(line(row.cells.map(render))) }
        }
        return lines
    }

    public var markdown: String { markdownLines().joined(separator: "\n") }

    /// Tab-separated values for a rectangle (default: the whole table).
    /// Soft breaks and tabs inside cells become spaces so the grid stays
    /// rectangular for spreadsheets.
    public func tsv(_ rect: RichTableRect? = nil) -> String {
        guard let rect = rect ?? RichTableSelection.table.rect(in: self) else { return "" }
        return rect.rows.map { rowIndex in
            rect.columns.map { columnIndex in
                let address = RichTableCellAddress(row: rowIndex, column: columnIndex)
                guard let cell = cell(at: address), !cell.isCovered else { return "" }
                return cell.plainText
                    .replacingOccurrences(of: "\u{2028}", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\t", with: " ")
            }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case columns, rows, hasHeaderRow, hasHeaderColumn, style, isStriped
        static var known: Set<String> { Set(["columns", "rows", "hasHeaderRow", "hasHeaderColumn", "style", "isStriped"]) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columns = (try? container.decodeIfPresent([RichTableColumn].self, forKey: .columns)) ?? []
        rows = (try? container.decodeIfPresent([RichTableRow].self, forKey: .rows)) ?? []
        hasHeaderRow = (try? container.decodeIfPresent(Bool.self, forKey: .hasHeaderRow)) ?? true
        hasHeaderColumn = (try? container.decodeIfPresent(Bool.self, forKey: .hasHeaderColumn)) ?? false
        style = (try? container.decodeIfPresent(RichTableStyle.self, forKey: .style)) ?? .grid
        isStriped = (try? container.decodeIfPresent(Bool.self, forKey: .isStriped)) ?? false
        passthrough = RichPassthrough.unknownKeys(from: decoder, known: CodingKeys.known)
        if !validate().isEmpty {
            self = repaired()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(columns, forKey: .columns)
        try container.encode(rows, forKey: .rows)
        try container.encode(hasHeaderRow, forKey: .hasHeaderRow)
        try container.encode(hasHeaderColumn, forKey: .hasHeaderColumn)
        try container.encode(style, forKey: .style)
        try container.encode(isStriped, forKey: .isStriped)
        try RichPassthrough.encode(passthrough, to: encoder, known: CodingKeys.known)
    }
}
