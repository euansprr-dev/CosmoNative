// TWIN FILE — byte-identical in CosmoOS-Swift/Editor/BlockEditor/Table and
// CosmoOS-iOS/CosmoCoreKit/Sources/Models. Verified by Tools/verify_twins.sh.
//
// The table grid layout. Cells are placed on a grid of resolved column
// widths; row heights come from the cells' own measured heights. Merged
// cells are single subviews spanning several rows/columns: their extra
// height, if any, is given to the LAST row they span (the Google Docs rule)
// so the rows above keep their natural height.

import SwiftUI

/// Which grid rectangle a cell subview occupies.
public struct TableCellPlacement: Equatable, Sendable {
    public var rows: ClosedRange<Int>
    public var columns: ClosedRange<Int>

    public init(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        self.rows = rows
        self.columns = columns
    }

    public init(row: Int, column: Int) {
        rows = row...row
        columns = column...column
    }
}

public struct TableCellPlacementKey: LayoutValueKey {
    public static let defaultValue = TableCellPlacement(row: 0, column: 0)
}

public extension View {
    /// Declares the grid rectangle this cell view occupies inside a
    /// `TableLayout`.
    func tableCellPlacement(_ placement: TableCellPlacement) -> some View {
        layoutValue(key: TableCellPlacementKey.self, value: placement)
    }
}

/// Resolved geometry a `TableLayout` computed for one pass — read by chrome
/// (rules, handles, selection washes) through `TableGeometryKey`.
public struct TableGeometry: Equatable, Sendable {
    public var columnWidths: [CGFloat]
    public var rowHeights: [CGFloat]

    public init(columnWidths: [CGFloat] = [], rowHeights: [CGFloat] = []) {
        self.columnWidths = columnWidths
        self.rowHeights = rowHeights
    }

    public var width: CGFloat { columnWidths.reduce(0, +) }
    public var height: CGFloat { rowHeights.reduce(0, +) }

    /// X origin of a column (0-based).
    public func columnOrigin(_ column: Int) -> CGFloat {
        columnWidths.prefix(max(0, column)).reduce(0, +)
    }

    public func rowOrigin(_ row: Int) -> CGFloat {
        rowHeights.prefix(max(0, row)).reduce(0, +)
    }

    public func rect(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> CGRect {
        let x = columnOrigin(columns.lowerBound)
        let y = rowOrigin(rows.lowerBound)
        let width = columns.compactMap { columnWidths.indices.contains($0) ? columnWidths[$0] : nil }.reduce(0, +)
        let height = rows.compactMap { rowHeights.indices.contains($0) ? rowHeights[$0] : nil }.reduce(0, +)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The column whose horizontal span contains `x` (clamped to the edges).
    public func column(at x: CGFloat) -> Int? {
        guard !columnWidths.isEmpty else { return nil }
        var cursor: CGFloat = 0
        for (index, width) in columnWidths.enumerated() {
            if x < cursor + width { return index }
            cursor += width
        }
        return columnWidths.count - 1
    }

    public func row(at y: CGFloat) -> Int? {
        guard !rowHeights.isEmpty else { return nil }
        var cursor: CGFloat = 0
        for (index, height) in rowHeights.enumerated() {
            if y < cursor + height { return index }
            cursor += height
        }
        return rowHeights.count - 1
    }
}

public struct TableGeometryKey: PreferenceKey {
    public static let defaultValue = TableGeometry()
    public static func reduce(value: inout TableGeometry, nextValue: () -> TableGeometry) {
        let next = nextValue()
        if !next.columnWidths.isEmpty { value = next }
    }
}

public struct TableLayout: Layout {
    public var columnWidths: [CGFloat]
    public var rowCount: Int
    public var minimumRowHeight: CGFloat

    public init(columnWidths: [CGFloat], rowCount: Int, minimumRowHeight: CGFloat) {
        self.columnWidths = columnWidths
        self.rowCount = max(1, rowCount)
        self.minimumRowHeight = minimumRowHeight
    }

    public struct Cache {
        public var rowHeights: [CGFloat] = []
        public var measuredForWidths: [CGFloat] = []
    }

    public func makeCache(subviews: Subviews) -> Cache { Cache() }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.rowHeights = []
        cache.measuredForWidths = []
    }

    private func width(of placement: TableCellPlacement) -> CGFloat {
        placement.columns.reduce(0) { partial, column in
            partial + (columnWidths.indices.contains(column) ? columnWidths[column] : 0)
        }
    }

    /// Row heights from the cells' measured heights at their span widths.
    public func resolvedRowHeights(subviews: Subviews, cache: inout Cache) -> [CGFloat] {
        if !cache.rowHeights.isEmpty, cache.measuredForWidths == columnWidths, cache.rowHeights.count == rowCount {
            return cache.rowHeights
        }
        var heights = Array(repeating: minimumRowHeight, count: rowCount)
        var spanned: [(placement: TableCellPlacement, height: CGFloat)] = []
        for subview in subviews {
            let placement = subview[TableCellPlacementKey.self]
            let cellWidth = width(of: placement)
            let measured = subview.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
            if placement.rows.count == 1 {
                let row = placement.rows.lowerBound
                if heights.indices.contains(row) {
                    heights[row] = max(heights[row], measured)
                }
            } else {
                spanned.append((placement, measured))
            }
        }
        // Spans: any excess goes to the last spanned row (Google Docs rule).
        for entry in spanned {
            let rows = entry.placement.rows.filter { heights.indices.contains($0) }
            guard let last = rows.last else { continue }
            let current = rows.reduce(0) { $0 + heights[$1] }
            if entry.height > current {
                heights[last] += entry.height - current
            }
        }
        cache.rowHeights = heights
        cache.measuredForWidths = columnWidths
        return heights
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let heights = resolvedRowHeights(subviews: subviews, cache: &cache)
        return CGSize(width: columnWidths.reduce(0, +), height: heights.reduce(0, +))
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let heights = resolvedRowHeights(subviews: subviews, cache: &cache)
        let geometry = TableGeometry(columnWidths: columnWidths, rowHeights: heights)
        for subview in subviews {
            let placement = subview[TableCellPlacementKey.self]
            let rect = geometry.rect(rows: placement.rows, columns: placement.columns)
            subview.place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: rect.width, height: rect.height)
            )
        }
    }
}
