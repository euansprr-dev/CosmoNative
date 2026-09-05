// TWIN FILE — byte-identical in CosmoOS-Swift/Editor/Model and
// CosmoOS-iOS/CosmoCoreKit/Sources/Models. Verified by Tools/verify_twins.sh.
//
// The pure table-editing engine. Every operation takes a `RichTable` value
// and returns a new one — or a `RichTableEditResult` carrying the focus and
// selection the host should adopt afterwards. No AppKit, no UIKit, no side
// effects, no mutation of the input. GRID LAW: every operation keeps the
// table rectangular with explicit span anchors and covered cells, and
// asserts `validate()` is empty in DEBUG builds before returning.
//
// Span vocabulary used throughout: an ANCHOR is the top-left cell of a
// merged region (`rowSpan`/`colSpan` > 1); every other position inside the
// region is COVERED (`coveredBy == anchor.id`, no content). A span "crosses"
// an insertion index when the anchor lies before it and the region extends
// past it; such spans grow. A span is "cut" by a move when a line leaves or
// enters the middle of its region; such moves are refused.

import Foundation

/// The outcome of an operation that also decides where editing continues.
public struct RichTableEditResult: Equatable, Sendable {
    public var table: RichTable
    /// The anchor the host should place the caret in, when the op moved it.
    public var focus: RichTableCellAddress?
    /// The selection the host should show, when the op changed it.
    public var selection: RichTableSelection?

    public init(table: RichTable, focus: RichTableCellAddress? = nil, selection: RichTableSelection? = nil) {
        self.table = table
        self.focus = focus
        self.selection = selection
    }
}

public enum RichTableError: Error, Equatable, Sendable {
    /// An index or rectangle lies outside the grid.
    case outOfBounds
    /// The move (or transpose) would split a merged region.
    case wouldBreakSpan
    /// A merged region would straddle the header row boundary.
    case spanCrossesHeader
    /// A merge rectangle is a single cell or only partially covers a span.
    case invalidRange
    /// Unmerge was asked of a cell that is not a span anchor.
    case notMerged
    /// Rows cannot be reordered while a body span is taller than one row.
    case cannotSortWithVerticalSpans
    /// A table always keeps at least one row and one column.
    case cannotDeleteLastLine
    /// The header row is pinned; it neither moves nor is moved over.
    case cannotMoveHeaderRow
}

public enum RichTableDirection: Hashable, Sendable, CaseIterable {
    case left
    case right
    case up
    case down
    /// Row-major successor (Tab).
    case nextCell
    /// Row-major predecessor (Shift-Tab).
    case previousCell
}

public enum RichTableNavigation: Equatable, Sendable {
    case cell(RichTableCellAddress)
    /// Leaving the table in `direction`; the host exits the block (or, for
    /// `.nextCell`, appends a row).
    case beyondEdge(RichTableDirection)
}

public enum RichTableOperations {

    /// The smallest share of the total width a column may be squeezed to by
    /// weight edits (8 %). Hosts also floor the rendered width in points.
    public static let defaultMinimumColumnFraction: Double = 0.08

    /// The soft line break joining merged cell texts (one rich paragraph per
    /// cell; never a hard newline).
    public static let softBreak = "\u{2028}"

    // MARK: - Rows

    /// Inserts an empty row before `index` (`index == rowCount` appends).
    /// Vertical spans whose anchor lies above `index` and whose region
    /// reaches `index` grow by one row (Google Docs). When
    /// `copyingStyleOfRow` names a row, each new cell inherits the tone and
    /// alignment overrides of that row's cell in the same column. Focus is
    /// the first visible cell of the new row.
    public static func insertRow(
        in table: RichTable,
        at index: Int,
        copyingStyleOfRow styleSource: Int? = nil
    ) throws -> RichTableEditResult {
        guard index >= 0, index <= table.rowCount else { throw RichTableError.outOfBounds }
        if let styleSource, !(styleSource >= 0 && styleSource < table.rowCount) { throw RichTableError.outOfBounds }
        var cells: [RichTableCell] = (0..<table.columnCount).map { _ in RichTableCell() }
        if let styleSource {
            for column in 0..<table.columnCount {
                let source = table[table.anchorAddress(of: RichTableCellAddress(row: styleSource, column: column))]
                cells[column].toneID = source.toneID
                cells[column].alignment = source.alignment
                cells[column].verticalAlignment = source.verticalAlignment
            }
        }
        var result = table
        for span in spanAnchors(in: table) where span.rect.rows.lowerBound < index && span.rect.rows.upperBound >= index {
            result[span.address].rowSpan += 1
            for column in span.rect.columns {
                cells[column] = RichTableCell(coveredBy: span.id)
            }
        }
        result.rows.insert(RichTableRow(cells: cells), at: index)
        let focus = firstVisibleAddress(inRow: index, of: result)
        return RichTableEditResult(table: checked(result), focus: focus, selection: focus.map { .cell($0) })
    }

    /// Removes row `index`. Spans touching the row shrink by one; a span
    /// anchored in the row keeps its content by re-anchoring at the row
    /// below (the new top-left), or dissolves with the row when it was only
    /// one row tall. Deleting the header row promotes the next row: a
    /// vertical span anchored there is trimmed to the header row (the cells
    /// beneath become plain, empty cells) because spans may not cross the
    /// header boundary.
    public static func deleteRow(in table: RichTable, at index: Int) throws -> RichTable {
        guard index >= 0, index < table.rowCount else { throw RichTableError.outOfBounds }
        guard table.rowCount > 1 else { throw RichTableError.cannotDeleteLastLine }
        return checked(removingRow(at: index, from: table))
    }

    /// Reorders rows so the row at `from` ends up at `to` (both in the
    /// original numbering; standard remove-then-insert semantics).
    /// Refuses when either the moved row or the landing gap lies inside a
    /// vertical span, and never moves the header row or over it.
    public static func moveRow(in table: RichTable, from: Int, to: Int) throws -> RichTable {
        guard from >= 0, from < table.rowCount, to >= 0, to < table.rowCount else { throw RichTableError.outOfBounds }
        if table.hasHeaderRow, from == 0 || to == 0 { throw RichTableError.cannotMoveHeaderRow }
        guard from != to else { return table }
        for span in spanAnchors(in: table) where span.rect.rows.count > 1 {
            if span.rect.rows.contains(from) { throw RichTableError.wouldBreakSpan }
            if gap(from: from, to: to, cuts: span.rect.rows) { throw RichTableError.wouldBreakSpan }
        }
        var result = table
        let row = result.rows.remove(at: from)
        result.rows.insert(row, at: to)
        return checked(result)
    }

    /// Stable sort of the body rows (the header stays pinned) by the text in
    /// `column`; covered positions compare by their anchor's text. Keys that
    /// parse as numbers (thousands separators and currency symbols stripped,
    /// locale-independent) order numerically and come before text; text
    /// orders by `localizedStandardCompare`; empty cells sort last in both
    /// directions. Row ids survive, so the reorder animates.
    public static func sortRows(in table: RichTable, byColumn column: Int, ascending: Bool) throws -> RichTable {
        guard column >= 0, column < table.columnCount else { throw RichTableError.outOfBounds }
        guard !table.hasVerticalSpanInBody else { throw RichTableError.cannotSortWithVerticalSpans }
        let body = Array(table.bodyRowIndices)
        guard body.count > 1 else { return table }
        let keyed: [(position: Int, row: RichTableRow, key: SortKey)] = body.enumerated().map { position, rowIndex in
            let anchor = table.anchorAddress(of: RichTableCellAddress(row: rowIndex, column: column))
            return (position, table.rows[rowIndex], SortKey(text: table[anchor].plainText))
        }
        let sorted = keyed.sorted { lhs, rhs in
            switch SortKey.compare(lhs.key, rhs.key, ascending: ascending) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.position < rhs.position
            }
        }
        var result = table
        for (slot, entry) in zip(body, sorted) { result.rows[slot] = entry.row }
        return checked(result)
    }

    // MARK: - Columns

    /// Inserts an empty column before `index` (`index == columnCount`
    /// appends). Its weight is the average of its neighbours. Horizontal
    /// spans crossing `index` grow by one column. Focus is the first visible
    /// cell of the new column.
    public static func insertColumn(in table: RichTable, at index: Int) throws -> RichTableEditResult {
        guard index >= 0, index <= table.columnCount else { throw RichTableError.outOfBounds }
        let neighbours = [index - 1, index]
            .filter { $0 >= 0 && $0 < table.columnCount }
            .map { table.columns[$0].weight }
        let weight = neighbours.isEmpty ? 1 : neighbours.reduce(0, +) / Double(neighbours.count)
        var result = table
        result.columns.insert(RichTableColumn(weight: weight), at: index)
        for row in result.rows.indices {
            result.rows[row].cells.insert(RichTableCell(), at: index)
        }
        for span in spanAnchors(in: table) where span.rect.columns.lowerBound < index && span.rect.columns.upperBound >= index {
            result[span.address].colSpan += 1
            for row in span.rect.rows {
                result.rows[row].cells[index] = RichTableCell(coveredBy: span.id)
            }
        }
        let focus = firstVisibleAddress(inColumn: index, of: result)
        return RichTableEditResult(table: checked(result), focus: focus, selection: focus.map { .cell($0) })
    }

    /// Removes column `index` with the same shrink/re-anchor/dissolve rules
    /// as `deleteRow`.
    public static func deleteColumn(in table: RichTable, at index: Int) throws -> RichTable {
        guard index >= 0, index < table.columnCount else { throw RichTableError.outOfBounds }
        guard table.columnCount > 1 else { throw RichTableError.cannotDeleteLastLine }
        return checked(removingColumn(at: index, from: table))
    }

    /// Reorders columns so the column at `from` ends up at `to`. Refuses
    /// when the moved column or the landing gap lies inside a horizontal
    /// span. The header column is not pinned.
    public static func moveColumn(in table: RichTable, from: Int, to: Int) throws -> RichTable {
        guard from >= 0, from < table.columnCount, to >= 0, to < table.columnCount else { throw RichTableError.outOfBounds }
        guard from != to else { return table }
        for span in spanAnchors(in: table) where span.rect.columns.count > 1 {
            if span.rect.columns.contains(from) { throw RichTableError.wouldBreakSpan }
            if gap(from: from, to: to, cuts: span.rect.columns) { throw RichTableError.wouldBreakSpan }
        }
        var result = table
        let column = result.columns.remove(at: from)
        result.columns.insert(column, at: to)
        for row in result.rows.indices {
            let cell = result.rows[row].cells.remove(at: from)
            result.rows[row].cells.insert(cell, at: to)
        }
        return checked(result)
    }

    /// Resets every column weight to 1.
    public static func distributeColumns(in table: RichTable) -> RichTable {
        var result = table
        for index in result.columns.indices { result.columns[index].weight = 1 }
        return checked(result)
    }

    /// Sets one column's weight, clamped so its share of the total stays at
    /// or above `minimumFraction`. Non-finite weights are ignored.
    public static func setColumnWeight(
        in table: RichTable,
        index: Int,
        weight: Double,
        minimumFraction: Double = RichTableOperations.defaultMinimumColumnFraction
    ) throws -> RichTable {
        guard index >= 0, index < table.columnCount else { throw RichTableError.outOfBounds }
        guard weight.isFinite else { return table }
        var result = table
        let others = table.columns.enumerated().reduce(0.0) { $0 + ($1.offset == index ? 0 : $1.element.weight) }
        let fraction = min(max(minimumFraction, 0), 0.999)
        let minimumWeight = others > 0 ? fraction * others / (1 - fraction) : 0
        result.columns[index].weight = max(weight, minimumWeight, 0.0001)
        return checked(result)
    }

    /// Divider drag between column `index` and `index + 1`: moves `delta`
    /// (a fraction of the total weight, negative to move left) from the
    /// right column to the left one. Neither column drops below
    /// `minimumFraction` of the total, and the total weight is unchanged.
    public static func resizeColumnPair(
        in table: RichTable,
        left index: Int,
        delta: Double,
        minimumFraction: Double = RichTableOperations.defaultMinimumColumnFraction
    ) throws -> RichTable {
        guard index >= 0, index + 1 < table.columnCount else { throw RichTableError.outOfBounds }
        guard delta.isFinite else { return table }
        var result = table
        let total = table.columns.reduce(0) { $0 + $1.weight }
        let minimum = min(max(minimumFraction, 0), 0.5) * total
        let left = table.columns[index].weight
        let right = table.columns[index + 1].weight
        let lower = minimum - left
        let upper = right - minimum
        guard lower <= upper else { return table }
        let amount = min(max(delta * total, lower), upper)
        result.columns[index].weight = max(left + amount, 0.0001)
        result.columns[index + 1].weight = max(right - amount, 0.0001)
        return checked(result)
    }

    // MARK: - Merging

    /// Merges every cell in `rect` into its top-left cell. The rectangle
    /// must hold at least two cells, lie within the grid, not straddle the
    /// header boundary, and fully contain every span it touches. Texts of
    /// the other non-empty cells are appended to the anchor's, row-major,
    /// joined by soft breaks; the anchor keeps its tone.
    public static func mergeCells(in table: RichTable, rect: RichTableRect) throws -> RichTableEditResult {
        guard contains(rect, in: table) else { throw RichTableError.outOfBounds }
        guard rect.cellCount >= 2 else { throw RichTableError.invalidRange }
        if table.hasHeaderRow, rect.rows.contains(0), rect.rows.count > 1 { throw RichTableError.spanCrossesHeader }
        guard table.expandedToSpans(rect) == rect else { throw RichTableError.invalidRange }
        let anchorAddress = rect.topLeft
        var anchor = table[anchorAddress]
        var parts: [[RichInlineNode]] = []
        for address in rect.addresses {
            let cell = table[address]
            guard !cell.isCovered, !cell.isEmptyContent else { continue }
            parts.append(cell.inlines)
        }
        anchor.inlines = joined(parts, separator: .text(softBreak))
        anchor.rowSpan = rect.rows.count
        anchor.colSpan = rect.columns.count
        anchor.coveredBy = nil
        var result = table
        result[anchorAddress] = anchor
        for address in rect.addresses where address != anchorAddress {
            result[address] = RichTableCell(id: table[address].id, coveredBy: anchor.id)
        }
        return RichTableEditResult(table: checked(result), focus: anchorAddress, selection: .cell(anchorAddress))
    }

    /// Splits the span anchored at `address` back into 1×1 cells. The
    /// anchor keeps its text and tone; the others come back empty. The
    /// selection is the former span rectangle.
    public static func unmergeCell(in table: RichTable, anchor address: RichTableCellAddress) throws -> RichTableEditResult {
        guard table.contains(address) else { throw RichTableError.outOfBounds }
        let cell = table[address]
        guard cell.isSpanAnchor, !cell.isCovered else { throw RichTableError.notMerged }
        let rect = table.spanRect(ofAnchorAt: address)
        var result = table
        result[address].rowSpan = 1
        result[address].colSpan = 1
        for position in rect.addresses where position != address {
            result[position] = RichTableCell(id: table[position].id)
        }
        return RichTableEditResult(table: checked(result), focus: address, selection: .range(rect))
    }

    // MARK: - Appearance

    /// Applies (or, with `nil`, clears) a wash tone on every anchor that
    /// intersects `rect`. Covered cells are never touched.
    public static func setTone(in table: RichTable, range rect: RichTableRect, toneID: String?) throws -> RichTable {
        guard contains(rect, in: table) else { throw RichTableError.outOfBounds }
        var result = table
        for anchor in table.anchors(intersecting: rect) {
            result[anchor].toneID = toneID
        }
        return checked(result)
    }

    /// Sets a column's alignment and clears every per-cell override in it.
    public static func setAlignment(in table: RichTable, column: Int, alignment: RichTableAlignment) throws -> RichTable {
        guard column >= 0, column < table.columnCount else { throw RichTableError.outOfBounds }
        var result = table
        result.columns[column].alignment = alignment
        for row in result.rows.indices {
            result.rows[row].cells[column].alignment = nil
        }
        return checked(result)
    }

    /// Sets (or, with `nil`, clears) the per-cell alignment override on
    /// every anchor intersecting `rect`.
    public static func setAlignment(in table: RichTable, range rect: RichTableRect, alignment: RichTableAlignment?) throws -> RichTable {
        guard contains(rect, in: table) else { throw RichTableError.outOfBounds }
        var result = table
        for anchor in table.anchors(intersecting: rect) {
            result[anchor].alignment = alignment
        }
        return checked(result)
    }

    /// Sets (or, with `nil`, clears) the vertical alignment on every anchor
    /// intersecting `rect`.
    public static func setVerticalAlignment(
        in table: RichTable,
        range rect: RichTableRect,
        alignment: RichTableVerticalAlignment?
    ) throws -> RichTable {
        guard contains(rect, in: table) else { throw RichTableError.outOfBounds }
        var result = table
        for anchor in table.anchors(intersecting: rect) {
            result[anchor].verticalAlignment = alignment
        }
        return checked(result)
    }

    /// Pins (or unpins) row 0 as the header. Enabling is refused while a
    /// span anchored in row 0 reaches into the body; the UI offers Unmerge.
    public static func setHeaderRow(in table: RichTable, enabled: Bool) throws -> RichTable {
        if enabled, let first = table.rows.first,
           first.cells.contains(where: { !$0.isCovered && $0.rowSpan > 1 }) {
            throw RichTableError.spanCrossesHeader
        }
        var result = table
        result.hasHeaderRow = enabled
        return checked(result)
    }

    public static func setHeaderColumn(in table: RichTable, enabled: Bool) -> RichTable {
        var result = table
        result.hasHeaderColumn = enabled
        return checked(result)
    }

    public static func setStyle(in table: RichTable, style: RichTableStyle) -> RichTable {
        var result = table
        result.style = style
        return checked(result)
    }

    public static func setStriped(in table: RichTable, isStriped: Bool) -> RichTable {
        var result = table
        result.isStriped = isStriped
        return checked(result)
    }

    // MARK: - Content

    /// Empties the text of every anchor intersecting `rect`; tones, spans
    /// and alignments stay.
    public static func clearCells(in table: RichTable, range rect: RichTableRect) throws -> RichTable {
        guard contains(rect, in: table) else { throw RichTableError.outOfBounds }
        var result = table
        for anchor in table.anchors(intersecting: rect) {
            result[anchor].inlines = []
        }
        return checked(result)
    }

    /// Multi-cell paste. Writes `grid` (rows of cell inlines; ragged rows
    /// pad with empty cells) right and down from `anchor`. With `expand`
    /// the table grows to fit (appended columns take the average weight);
    /// otherwise the grid is clipped at the edges. A position inside a span
    /// writes into the span's anchor and the first write to an anchor wins.
    /// The selection is the written rectangle; focus is the anchor.
    public static func fill(
        in table: RichTable,
        from anchor: RichTableCellAddress,
        grid: [[[RichInlineNode]]],
        expand: Bool
    ) throws -> RichTableEditResult {
        guard table.contains(anchor) else { throw RichTableError.outOfBounds }
        let gridRows = grid.count
        let gridColumns = grid.map(\.count).max() ?? 0
        guard gridRows > 0, gridColumns > 0 else {
            return RichTableEditResult(table: table, focus: anchor, selection: .cell(anchor))
        }
        var result = table
        if expand {
            result = appendingLines(to: result, rows: anchor.row + gridRows, columns: anchor.column + gridColumns)
        }
        let lastRow = min(anchor.row + gridRows - 1, result.rowCount - 1)
        let lastColumn = min(anchor.column + gridColumns - 1, result.columnCount - 1)
        let target = RichTableRect(rows: anchor.row...lastRow, columns: anchor.column...lastColumn)
        var written = Set<RichTableCellAddress>()
        for (rowOffset, gridRow) in grid.enumerated() {
            let row = anchor.row + rowOffset
            guard row <= lastRow else { break }
            for columnOffset in 0..<gridColumns {
                let column = anchor.column + columnOffset
                guard column <= lastColumn else { break }
                let cellAnchor = result.anchorAddress(of: RichTableCellAddress(row: row, column: column))
                guard written.insert(cellAnchor).inserted else { continue }
                result[cellAnchor].inlines = columnOffset < gridRow.count ? gridRow[columnOffset] : []
            }
        }
        let focus = result.anchorAddress(of: anchor)
        return RichTableEditResult(table: checked(result), focus: focus, selection: .range(target))
    }

    /// Corner-drag resize: appends or removes rows at the bottom and
    /// columns at the right until the grid is `rows` × `columns` (never
    /// below 1 × 1). Removals follow the delete rules — spans reaching the
    /// removed line shrink, spans living only there dissolve.
    public static func resize(in table: RichTable, rows: Int, columns: Int) -> RichTable {
        let targetRows = max(1, rows)
        let targetColumns = max(1, columns)
        var result = table
        while result.rowCount > targetRows {
            result = removingRow(at: result.rowCount - 1, from: result)
        }
        while result.columnCount > targetColumns {
            result = removingColumn(at: result.columnCount - 1, from: result)
        }
        result = appendingLines(to: result, rows: targetRows, columns: targetColumns)
        return checked(result)
    }

    /// Swaps rows and columns. Refused while any span exists (the UI says
    /// "unmerge first"). Header row and header column flags swap, column
    /// weights reset to 1, and horizontal alignments (column and per-cell)
    /// reset. Row ids become column ids and vice versa, so transposing
    /// twice restores every identity.
    public static func transpose(in table: RichTable) throws -> RichTable {
        guard !table.hasAnySpan else { throw RichTableError.wouldBreakSpan }
        var result = table
        result.columns = table.rows.map { RichTableColumn(id: $0.id) }
        result.rows = table.columns.enumerated().map { columnIndex, column in
            RichTableRow(id: column.id, cells: table.rows.map { row in
                var cell = row.cells[columnIndex]
                cell.alignment = nil
                return cell
            })
        }
        result.hasHeaderRow = table.hasHeaderColumn
        result.hasHeaderColumn = table.hasHeaderRow
        return checked(result)
    }

    // MARK: - Blocks

    /// "Convert to table": one row per block. Every block's plain text is
    /// split into columns on tabs, else on " | " (outer pipes tolerated),
    /// else on ", " — the first separator on which every line yields the
    /// same count of at least two wins. Otherwise a one-column table whose
    /// cells keep the blocks' inline runs. The header row is on when there
    /// are at least two rows.
    static func blocksToTable(_ blocks: [RichBlock]) -> RichTable {
        guard !blocks.isEmpty else { return RichTable(rowCount: 1, columnCount: 1, hasHeaderRow: false) }
        let rows: [RichTableRow]
        let columnCount: Int
        if let split = splitLines(blocks.map { $0.inlines.map(\.plainText).joined() }) {
            columnCount = split.first?.count ?? 1
            rows = split.map { line in RichTableRow(cells: line.map { RichTableCell.text($0) }) }
        } else {
            columnCount = 1
            rows = blocks.map { RichTableRow(cells: [RichTableCell(inlines: $0.inlines)]) }
        }
        let table = RichTable(
            columns: (0..<columnCount).map { _ in RichTableColumn() },
            rows: rows,
            hasHeaderRow: rows.count >= 2
        )
        return checked(table)
    }

    /// "Convert to text": one paragraph per row, visible cells joined with
    /// a tab. Covered positions are skipped; inline runs survive.
    static func tableToBlocks(_ table: RichTable) -> [RichBlock] {
        table.rows.map { row in
            let parts = row.cells.filter { !$0.isCovered }.map(\.inlines)
            return RichBlock(kind: .paragraph, inlines: joined(parts, separator: .text("\t")))
        }
    }

    /// Column separators tried in priority order by `blocksToTable`.
    private static let columnSeparators = ["\t", " | ", ", "]

    /// The first separator on which every line splits into the same number
    /// (at least two) of columns, applied; `nil` when none does. Cells are
    /// whitespace-trimmed; a pipe split tolerates one outer pipe per side.
    private static func splitLines(_ lines: [String]) -> [[String]]? {
        guard !lines.isEmpty else { return nil }
        for separator in columnSeparators {
            let split: [[String]] = lines.map { line in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                if separator == " | " {
                    if trimmed.hasPrefix("|") { trimmed.removeFirst() }
                    if trimmed.hasSuffix("|") { trimmed.removeLast() }
                    trimmed = trimmed.trimmingCharacters(in: .whitespaces)
                }
                return trimmed.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
            }
            guard let count = split.first?.count, count >= 2, split.allSatisfy({ $0.count == count }) else { continue }
            return split
        }
        return nil
    }

    // MARK: - Navigation

    /// Every anchor (unmerged cell or span anchor), row-major.
    public static func visibleAddresses(in table: RichTable) -> [RichTableCellAddress] {
        var result: [RichTableCellAddress] = []
        for (rowIndex, row) in table.rows.enumerated() {
            for (columnIndex, cell) in row.cells.enumerated() where !cell.isCovered {
                result.append(RichTableCellAddress(row: rowIndex, column: columnIndex))
            }
        }
        return result
    }

    /// The anchor reached by moving from `address` in `direction`. Spatial
    /// moves step past the whole span the address belongs to and land on
    /// the anchor of whatever position is there. `.nextCell`/`.previousCell`
    /// walk the visible anchors row-major; without `wrapRows` the end of a
    /// row is an edge. Leaving the grid yields `.beyondEdge(direction)` —
    /// `.nextCell` from the last anchor is how the host knows to add a row.
    public static func nextCellAddress(
        in table: RichTable,
        after address: RichTableCellAddress,
        direction: RichTableDirection,
        wrapRows: Bool
    ) -> RichTableNavigation {
        guard table.contains(address) else { return .beyondEdge(direction) }
        let anchor = table.anchorAddress(of: address)
        let span = table.spanRect(ofAnchorAt: anchor)
        func land(_ probe: RichTableCellAddress) -> RichTableNavigation {
            table.contains(probe) ? .cell(table.anchorAddress(of: probe)) : .beyondEdge(direction)
        }
        switch direction {
        case .left:
            return land(RichTableCellAddress(row: address.row, column: span.columns.lowerBound - 1))
        case .right:
            return land(RichTableCellAddress(row: address.row, column: span.columns.upperBound + 1))
        case .up:
            return land(RichTableCellAddress(row: span.rows.lowerBound - 1, column: address.column))
        case .down:
            return land(RichTableCellAddress(row: span.rows.upperBound + 1, column: address.column))
        case .nextCell, .previousCell:
            let visible = visibleAddresses(in: table)
            guard let index = visible.firstIndex(of: anchor) else { return .beyondEdge(direction) }
            let nextIndex = direction == .nextCell ? index + 1 : index - 1
            guard visible.indices.contains(nextIndex) else { return .beyondEdge(direction) }
            let candidate = visible[nextIndex]
            if candidate.row != anchor.row, !wrapRows { return .beyondEdge(direction) }
            return .cell(candidate)
        }
    }

    // MARK: - Private: spans

    private struct SpanInfo {
        let address: RichTableCellAddress
        let id: UUID
        let rect: RichTableRect
    }

    private static func spanAnchors(in table: RichTable) -> [SpanInfo] {
        var result: [SpanInfo] = []
        for (rowIndex, row) in table.rows.enumerated() {
            for (columnIndex, cell) in row.cells.enumerated() where cell.isSpanAnchor && !cell.isCovered {
                let address = RichTableCellAddress(row: rowIndex, column: columnIndex)
                result.append(SpanInfo(address: address, id: cell.id, rect: table.spanRect(ofAnchorAt: address)))
            }
        }
        return result
    }

    /// Whether moving line `from` to `to` (remove-then-insert) lands the
    /// line strictly inside `span`. The landing gap, in original numbering,
    /// sits after `to` when moving down and before `to` when moving up.
    private static func gap(from: Int, to: Int, cuts span: ClosedRange<Int>) -> Bool {
        let gap = from < to ? to + 1 : to
        return span.lowerBound < gap && gap <= span.upperBound
    }

    private static func removingRow(at index: Int, from table: RichTable) -> RichTable {
        var result = table
        for span in spanAnchors(in: table) where span.rect.rows.contains(index) {
            if span.address.row == index {
                // Anchored in the deleted row: re-anchor one row down (the
                // moved cell keeps its id, so the remaining covers stay
                // valid) or dissolve with the row when only one row tall.
                guard span.rect.rows.count > 1 else { continue }
                var moved = result[span.address]
                moved.rowSpan -= 1
                result[span.address.offset(rows: 1)] = moved
            } else {
                result[span.address].rowSpan -= 1
            }
        }
        result.rows.remove(at: index)
        if result.hasHeaderRow, index == 0 {
            result = trimmingVerticalSpans(inRow: 0, of: result)
        }
        return result
    }

    private static func removingColumn(at index: Int, from table: RichTable) -> RichTable {
        var result = table
        for span in spanAnchors(in: table) where span.rect.columns.contains(index) {
            if span.address.column == index {
                guard span.rect.columns.count > 1 else { continue }
                var moved = result[span.address]
                moved.colSpan -= 1
                result[span.address.offset(columns: 1)] = moved
            } else {
                result[span.address].colSpan -= 1
            }
        }
        result.columns.remove(at: index)
        for row in result.rows.indices {
            result.rows[row].cells.remove(at: index)
        }
        return result
    }

    /// Cuts every vertical span anchored in `rowIndex` down to that row;
    /// the positions beneath become plain empty cells. Used when a body row
    /// becomes the header.
    private static func trimmingVerticalSpans(inRow rowIndex: Int, of table: RichTable) -> RichTable {
        guard rowIndex >= 0, rowIndex < table.rowCount else { return table }
        var result = table
        for span in spanAnchors(in: table) where span.address.row == rowIndex && span.rect.rows.count > 1 {
            result[span.address].rowSpan = 1
            for row in span.rect.rows.dropFirst() {
                for column in span.rect.columns {
                    let position = RichTableCellAddress(row: row, column: column)
                    result[position] = RichTableCell(id: table[position].id)
                }
            }
        }
        return result
    }

    /// Appends empty rows at the bottom and columns at the right until the
    /// grid is at least `rows` × `columns`. Appended columns take the
    /// average of the existing weights. Appending never crosses a span.
    private static func appendingLines(to table: RichTable, rows: Int, columns: Int) -> RichTable {
        var result = table
        if result.columnCount < columns {
            let average = result.columns.reduce(0) { $0 + $1.weight } / Double(max(1, result.columnCount))
            let weight = average.isFinite && average > 0 ? average : 1
            while result.columnCount < columns {
                result.columns.append(RichTableColumn(weight: weight))
                for row in result.rows.indices {
                    result.rows[row].cells.append(RichTableCell())
                }
            }
        }
        while result.rowCount < rows {
            result.rows.append(RichTableRow(cells: (0..<result.columnCount).map { _ in RichTableCell() }))
        }
        return result
    }

    // MARK: - Private: geometry

    private static func contains(_ rect: RichTableRect, in table: RichTable) -> Bool {
        rect.rows.lowerBound >= 0 && rect.rows.upperBound < table.rowCount
            && rect.columns.lowerBound >= 0 && rect.columns.upperBound < table.columnCount
    }

    private static func firstVisibleAddress(inRow row: Int, of table: RichTable) -> RichTableCellAddress? {
        guard row >= 0, row < table.rowCount else { return nil }
        if let column = table.rows[row].cells.firstIndex(where: { !$0.isCovered }) {
            return RichTableCellAddress(row: row, column: column)
        }
        return table.columnCount > 0 ? table.anchorAddress(of: RichTableCellAddress(row: row, column: 0)) : nil
    }

    private static func firstVisibleAddress(inColumn column: Int, of table: RichTable) -> RichTableCellAddress? {
        guard column >= 0, column < table.columnCount else { return nil }
        if let row = table.rows.firstIndex(where: { !$0.cells[column].isCovered }) {
            return RichTableCellAddress(row: row, column: column)
        }
        return table.rowCount > 0 ? table.anchorAddress(of: RichTableCellAddress(row: 0, column: column)) : nil
    }

    // MARK: - Private: inlines

    /// Concatenates runs with `separator` between parts. Adjacent unstyled
    /// text runs coalesce so the result never carries two plain runs in a
    /// row (the serializer's own normal form).
    private static func joined(_ parts: [[RichInlineNode]], separator: RichInlineNode) -> [RichInlineNode] {
        var result: [RichInlineNode] = []
        for (index, part) in parts.enumerated() {
            if index > 0 { append(separator, to: &result) }
            for node in part { append(node, to: &result) }
        }
        return result
    }

    private static func append(_ node: RichInlineNode, to nodes: inout [RichInlineNode]) {
        if let last = nodes.last, isPlainText(last), isPlainText(node) {
            nodes[nodes.count - 1].text = (last.text ?? "") + (node.text ?? "")
        } else {
            nodes.append(node)
        }
    }

    private static func isPlainText(_ node: RichInlineNode) -> Bool {
        node.kind == .text && node.marks.isEmpty && node.inkID == nil && node.highlightID == nil
            && node.href == nil && node.passthrough.isEmpty
    }

    // MARK: - Private: sorting

    private enum SortKey {
        case number(Double)
        case text(String)
        case empty

        init(text raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                self = .empty
            } else if let number = SortKey.parseNumber(trimmed) {
                self = .number(number)
            } else {
                self = .text(trimmed)
            }
        }

        /// Plain decimal text (optional sign, fraction, exponent) after
        /// stripping thousands separators, currency symbols and inner
        /// whitespace. Locale-independent; never `inf`/`nan`/hex.
        static func parseNumber(_ text: String) -> Double? {
            var cleaned = ""
            for scalar in text.unicodeScalars {
                if scalar == "," || scalar.properties.generalCategory == .currencySymbol
                    || scalar.properties.isWhitespace {
                    continue
                }
                guard numericScalars.contains(scalar) else { return nil }
                cleaned.unicodeScalars.append(scalar)
            }
            guard !cleaned.isEmpty, cleaned.unicodeScalars.contains(where: { $0.properties.numericType != nil }),
                  let value = Double(cleaned), value.isFinite else { return nil }
            return value
        }

        private static let numericScalars: Set<Unicode.Scalar> = Set("0123456789.+-eE".unicodeScalars)

        /// Numbers before text before empties when ascending; descending
        /// reverses the number and text orders but keeps empties last.
        static func compare(_ lhs: SortKey, _ rhs: SortKey, ascending: Bool) -> ComparisonResult {
            switch (lhs, rhs) {
            case (.empty, .empty):
                return .orderedSame
            case (.empty, _):
                return .orderedDescending
            case (_, .empty):
                return .orderedAscending
            case (.number(let a), .number(let b)):
                let result: ComparisonResult = a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
                return ascending ? result : flipped(result)
            case (.number, .text):
                return ascending ? .orderedAscending : .orderedDescending
            case (.text, .number):
                return ascending ? .orderedDescending : .orderedAscending
            case (.text(let a), .text(let b)):
                let result = a.localizedStandardCompare(b)
                return ascending ? result : flipped(result)
            }
        }

        private static func flipped(_ result: ComparisonResult) -> ComparisonResult {
            switch result {
            case .orderedAscending: return .orderedDescending
            case .orderedDescending: return .orderedAscending
            case .orderedSame: return .orderedSame
            }
        }
    }

    // MARK: - Private: invariants

    /// Every mutating operation funnels its result through here: in DEBUG
    /// the grid law is asserted; in release the table is returned as
    /// computed.
    private static func checked(_ table: RichTable) -> RichTable {
        assert(table.validate().isEmpty, "RichTableOperations produced an invalid table: \(table.validate())")
        return table
    }
}
