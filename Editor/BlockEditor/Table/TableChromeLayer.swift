import AppKit
import SwiftUI

/// Anchor preference every cell reports so chrome can be laid over the
/// grid without a second measuring pass.
struct TableCellFramesKey: PreferenceKey {
    static let defaultValue: [RichTableCellAddress: Anchor<CGRect>] = [:]
    static func reduce(value: inout [RichTableCellAddress: Anchor<CGRect>], nextValue: () -> [RichTableCellAddress: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Resolved grid metrics in the grid's own coordinate space.
struct TableGridMetrics: Equatable {
    var columnWidths: [CGFloat]
    var rowOrigins: [CGFloat]
    var rowHeights: [CGFloat]

    var width: CGFloat { columnWidths.reduce(0, +) }
    var height: CGFloat { (rowOrigins.last ?? 0) + (rowHeights.last ?? 0) }

    func columnOrigin(_ column: Int) -> CGFloat { columnWidths.prefix(max(0, column)).reduce(0, +) }

    func columnIndex(at x: CGFloat) -> Int {
        var cursor: CGFloat = 0
        for (index, width) in columnWidths.enumerated() {
            if x < cursor + width { return index }
            cursor += width
        }
        return max(0, columnWidths.count - 1)
    }

    /// Insertion slot (0…count) nearest to `x` — before the column whose
    /// midpoint x is past.
    func columnInsertionIndex(at x: CGFloat) -> Int {
        var cursor: CGFloat = 0
        for (index, width) in columnWidths.enumerated() {
            if x < cursor + width / 2 { return index }
            cursor += width
        }
        return columnWidths.count
    }

    func rowIndex(at y: CGFloat) -> Int {
        for (index, origin) in rowOrigins.enumerated() {
            let height = rowHeights.indices.contains(index) ? rowHeights[index] : 0
            if y < origin + height { return index }
        }
        return max(0, rowOrigins.count - 1)
    }

    func rowInsertionIndex(at y: CGFloat) -> Int {
        for (index, origin) in rowOrigins.enumerated() {
            let height = rowHeights.indices.contains(index) ? rowHeights[index] : 0
            if y < origin + height / 2 { return index }
        }
        return rowOrigins.count
    }

    static func resolve(
        table: RichTable,
        widths: [CGFloat],
        frames: [RichTableCellAddress: CGRect]
    ) -> TableGridMetrics {
        var origins = Array(repeating: CGFloat.greatestFiniteMagnitude, count: table.rowCount)
        var ends = Array(repeating: CGFloat.zero, count: table.rowCount)
        for (address, frame) in frames {
            guard table.contains(address) else { continue }
            let span = table.spanRect(ofAnchorAt: address)
            let first = span.rows.lowerBound
            let last = span.rows.upperBound
            if origins.indices.contains(first) { origins[first] = min(origins[first], frame.minY) }
            if ends.indices.contains(last) { ends[last] = max(ends[last], frame.maxY) }
        }
        // Rows fully covered by spans have no anchor of their own: fill from
        // neighbours so every row has an origin and a height.
        var cursor: CGFloat = 0
        for index in origins.indices {
            if origins[index] == .greatestFiniteMagnitude { origins[index] = cursor }
            if ends[index] == 0 { ends[index] = index + 1 < origins.count && origins[index + 1] != .greatestFiniteMagnitude ? origins[index + 1] : origins[index] }
            cursor = max(cursor, ends[index])
        }
        var heights: [CGFloat] = []
        for index in origins.indices {
            let next = index + 1 < origins.count ? origins[index + 1] : ends[index]
            heights.append(max(0, next - origins[index]))
        }
        return TableGridMetrics(columnWidths: widths, rowOrigins: origins, rowHeights: heights)
    }
}

/// Handles, insertion affordances, selection wash, divider resize zones,
/// the corner grabber and the drag insertion indicator. Sits over the grid
/// (never clipped) in the 12 pt apron the table reserves around itself.
struct TableChromeLayer: View {
    var table: RichTable
    var metrics: TableGridMetrics
    var coordinator: TableFocusCoordinator
    var isHovered: Bool
    var darkMode: Bool
    var onSelectRow: (Int, Bool) -> Void
    var onSelectColumn: (Int, Bool) -> Void
    var onMoveRow: (Int, Int) -> Void
    var onMoveColumn: (Int, Int) -> Void
    var onInsertRow: (Int) -> Void
    var onInsertColumn: (Int) -> Void
    var onResizeColumns: (Int, CGFloat) -> Void
    var onDistributeColumns: () -> Void
    var onResizeGrid: (Int, Int) -> Void
    var onOptions: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredDivider: Int?
    @State private var hoveredAddRow = false
    @State private var hoveredAddColumn = false
    @State private var hoveredOptions = false
    @State private var hoveredHandle: HandleID?

    private enum HandleID: Hashable {
        case row(Int)
        case column(Int)
    }

    static let apron: CGFloat = 12
    private let handleThickness: CGFloat = 4
    private let handleLength: CGFloat = 18

    private var chromeVisible: Bool {
        isHovered || coordinator.focusedCell != nil || coordinator.selection != nil || coordinator.drag != nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            selectionWash
            columnHandles
            rowHandles
            dividerZones
            insertionIndicator
            addColumnPill
            addRowBar
            cornerGrabber
            optionsChip
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: chromeVisible)
    }

    // MARK: Selection

    @ViewBuilder
    private var selectionWash: some View {
        if let selection = coordinator.selection, let rect = selection.rect(in: table) {
            let expanded = table.expandedToSpans(rect)
            let frame = frameOf(expanded)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(DS.accent, lineWidth: 1.5)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func frameOf(_ rect: RichTableRect) -> CGRect {
        let x = metrics.columnOrigin(rect.columns.lowerBound)
        let width = rect.columns.reduce(CGFloat.zero) { $0 + (metrics.columnWidths.indices.contains($1) ? metrics.columnWidths[$1] : 0) }
        let y = metrics.rowOrigins.indices.contains(rect.rows.lowerBound) ? metrics.rowOrigins[rect.rows.lowerBound] : 0
        let height = rect.rows.reduce(CGFloat.zero) { $0 + (metrics.rowHeights.indices.contains($1) ? metrics.rowHeights[$1] : 0) }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: Handles

    private var columnHandles: some View {
        ForEach(Array(metrics.columnWidths.indices), id: \.self) { column in
            let origin = metrics.columnOrigin(column)
            let width = metrics.columnWidths[column]
            handle(
                id: .column(column),
                size: CGSize(width: min(handleLength, max(10, width - 12)), height: handleThickness),
                center: CGPoint(x: origin + width / 2, y: -Self.apron / 2),
                selected: isColumnSelected(column),
                help: "Select column — drag to move"
            )
            .gesture(columnDrag(column))
            .simultaneousGesture(TapGesture().onEnded {
                onSelectColumn(column, NSEvent.modifierFlags.contains(.shift))
            })
        }
    }

    private var rowHandles: some View {
        ForEach(Array(metrics.rowOrigins.indices), id: \.self) { row in
            let origin = metrics.rowOrigins[row]
            let height = metrics.rowHeights.indices.contains(row) ? metrics.rowHeights[row] : 0
            handle(
                id: .row(row),
                size: CGSize(width: handleThickness, height: min(handleLength, max(10, height - 8))),
                center: CGPoint(x: -Self.apron / 2, y: origin + height / 2),
                selected: isRowSelected(row),
                help: "Select row — drag to move"
            )
            .gesture(rowDrag(row))
            .simultaneousGesture(TapGesture().onEnded {
                onSelectRow(row, NSEvent.modifierFlags.contains(.shift))
            })
        }
    }

    private func handle(id: HandleID, size: CGSize, center: CGPoint, selected: Bool, help: String) -> some View {
        let isHot = hoveredHandle == id || selected
        return Capsule(style: .continuous)
            .fill(isHot ? DS.accent : DS.textMuted.opacity(0.42))
            .frame(width: size.width, height: size.height)
            .frame(width: max(size.width, 16), height: max(size.height, 16))
            .contentShape(Rectangle())
            .position(center)
            .opacity(chromeVisible ? 1 : 0)
            .onHover { hovering in hoveredHandle = hovering ? id : (hoveredHandle == id ? nil : hoveredHandle) }
            .help(help)
            .accessibilityLabel(help)
    }

    private func isRowSelected(_ row: Int) -> Bool {
        if case .rows(let rows) = coordinator.selection { return rows.contains(row) }
        if case .table = coordinator.selection { return true }
        return false
    }

    private func isColumnSelected(_ column: Int) -> Bool {
        if case .columns(let columns) = coordinator.selection { return columns.contains(column) }
        if case .table = coordinator.selection { return true }
        return false
    }

    private func columnDrag(_ column: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(TableChromeLayer.coordinateSpace))
            .onChanged { value in
                let target = metrics.columnInsertionIndex(at: value.location.x)
                coordinator.drag = .init(axis: .column, source: column, target: target)
            }
            .onEnded { value in
                let target = metrics.columnInsertionIndex(at: value.location.x)
                coordinator.drag = nil
                onMoveColumn(column, target)
            }
    }

    private func rowDrag(_ row: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(TableChromeLayer.coordinateSpace))
            .onChanged { value in
                let target = metrics.rowInsertionIndex(at: value.location.y)
                coordinator.drag = .init(axis: .row, source: row, target: target)
            }
            .onEnded { value in
                let target = metrics.rowInsertionIndex(at: value.location.y)
                coordinator.drag = nil
                onMoveRow(row, target)
            }
    }

    static let coordinateSpace = "cosmo.table.chrome"

    // MARK: Insertion indicator

    @ViewBuilder
    private var insertionIndicator: some View {
        if let drag = coordinator.drag {
            switch drag.axis {
            case .column:
                let x = drag.target >= metrics.columnWidths.count ? metrics.width : metrics.columnOrigin(drag.target)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(DS.accent)
                    .frame(width: 2, height: metrics.height)
                    .offset(x: x - 1, y: 0)
                    .allowsHitTesting(false)
            case .row:
                let y = drag.target >= metrics.rowOrigins.count ? metrics.height : metrics.rowOrigins[drag.target]
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(DS.accent)
                    .frame(width: metrics.width, height: 2)
                    .offset(x: 0, y: y - 1)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Dividers (column resize)

    private var dividerZones: some View {
        ForEach(Array(metrics.columnWidths.indices.dropLast()), id: \.self) { column in
            let x = metrics.columnOrigin(column + 1)
            Rectangle()
                .fill(hoveredDivider == column ? DS.accent.opacity(0.35) : Color.clear)
                .frame(width: hoveredDivider == column ? 2 : 6, height: metrics.height)
                .contentShape(Rectangle().size(width: 8, height: metrics.height))
                .position(x: x, y: metrics.height / 2)
                .onHover { hovering in
                    hoveredDivider = hovering ? column : (hoveredDivider == column ? nil : hoveredDivider)
                    if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named(TableChromeLayer.coordinateSpace))
                        .onChanged { value in
                            let start = coordinator.dividerDrag?.startX ?? x
                            if coordinator.dividerDrag == nil {
                                coordinator.dividerDrag = .init(leftColumn: column, startX: x)
                            }
                            let delta = (value.location.x - start) / max(metrics.width, 1)
                            onResizeColumns(column, delta)
                            coordinator.dividerDrag = .init(leftColumn: column, startX: value.location.x)
                        }
                        .onEnded { _ in coordinator.dividerDrag = nil }
                )
                .simultaneousGesture(TapGesture(count: 2).onEnded { onDistributeColumns() })
                .help("Drag to resize — double-click to distribute")
        }
    }

    // MARK: Add affordances

    private var addColumnPill: some View {
        Button { onInsertColumn(table.columnCount) } label: {
            Image(systemName: "plus")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(hoveredAddColumn ? DS.accent : DS.textMuted)
                .frame(width: 10, height: 22)
                .background(
                    Capsule(style: .continuous)
                        .fill(hoveredAddColumn ? DS.accentSoft : DS.glassCardFill)
                )
                .overlay(Capsule(style: .continuous).strokeBorder(DS.documentBorderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .frame(width: 16, height: 26)
        .contentShape(Rectangle())
        .position(x: metrics.width + Self.apron / 2, y: metrics.height / 2)
        .opacity(chromeVisible ? 1 : 0)
        .onHover { hoveredAddColumn = $0 }
        .help("Add column")
        .accessibilityLabel("Add column")
    }

    private var addRowBar: some View {
        Button { onInsertRow(table.rowCount) } label: {
            Image(systemName: "plus")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(hoveredAddRow ? DS.accent : DS.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(hoveredAddRow ? DS.accentSoft : DS.glassCardFill)
                )
                .overlay(Capsule(style: .continuous).strokeBorder(DS.documentBorderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .frame(width: max(0, metrics.width - 24), height: 16)
        .contentShape(Rectangle())
        .position(x: metrics.width / 2, y: metrics.height + Self.apron / 2)
        .opacity(chromeVisible ? 1 : 0)
        .onHover { hoveredAddRow = $0 }
        .help("Add row")
        .accessibilityLabel("Add row")
    }

    private var cornerGrabber: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(DS.textMuted)
            .frame(width: 12, height: 12)
            .contentShape(Rectangle())
            .position(x: metrics.width + Self.apron / 2, y: metrics.height + Self.apron / 2)
            .opacity(chromeVisible ? 0.9 : 0)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(TableChromeLayer.coordinateSpace))
                    .onChanged { value in
                        let avgWidth = max(metrics.width / CGFloat(max(1, table.columnCount)), 40)
                        let avgHeight = max(metrics.height / CGFloat(max(1, table.rowCount)), 22)
                        let columns = max(1, table.columnCount + Int(((value.location.x - metrics.width) / avgWidth).rounded()))
                        let rows = max(1, table.rowCount + Int(((value.location.y - metrics.height) / avgHeight).rounded()))
                        coordinator.cornerDrag = (rows: rows, columns: columns)
                    }
                    .onEnded { _ in
                        if let target = coordinator.cornerDrag {
                            onResizeGrid(target.rows, target.columns)
                        }
                        coordinator.cornerDrag = nil
                    }
            )
            .help("Drag to add rows and columns")
            .accessibilityLabel("Resize table")
    }

    private var optionsChip: some View {
        Button(action: onOptions) {
            Image(systemName: "ellipsis")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(hoveredOptions ? DS.text : DS.textMuted)
                .frame(width: 22, height: 16)
                .background(
                    Capsule(style: .continuous)
                        .fill(hoveredOptions ? DS.glassSectionFill : DS.glassCardFill)
                )
                .overlay(Capsule(style: .continuous).strokeBorder(DS.documentBorderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .position(x: metrics.width - 14, y: -Self.apron / 2)
        .opacity(chromeVisible ? 1 : 0)
        .onHover { hoveredOptions = $0 }
        .help("Table options (⌥⌘T)")
        .accessibilityLabel("Table options")
    }
}
