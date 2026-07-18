// CosmoOS/Canvas/FilePortalGridView.swift
// Live spreadsheet tier of a file portal — a virtualized grid over an
// immutable SheetModel that renders what Excel rendered: the file's own
// column widths and row heights, solid fills, bold/italic/colored ink,
// horizontal merges, and Excel's empty-neighbor text overflow. Rows
// materialize lazily; layout math is pure (SheetGridLayout, unit-tested).
//
// Interaction split (July 18): the sheet-tab strip lives in the HOST, above
// the enter-to-interact gate — switching sheets never requires entering the
// portal. Only the scrolling grid content is gated. When editable (local
// bytes + entered/peek), double-click a cell to edit in place.

import SwiftUI

// MARK: - Async host (parse → tabs + grid)

/// Owns workbook loading through SheetModelCache, the selected-sheet state,
/// and optimistic in-memory application of cell edits. Parse failure renders
/// the caller's fallback (the Tier-0 skin), never an error wall.
struct FilePortalSheetHost: View {
    let fileURL: URL
    let cacheKey: String
    let stamp: String?
    let initialSheetIndex: Int
    let isCompact: Bool
    /// Grid content (scrolling/selection) interactivity — the tab strip is
    /// deliberately ABOVE this gate and always clickable.
    var isContentInteractive: Bool = true
    var isEditable: Bool = false
    let fallback: () -> AnyView
    var onSheetChanged: (Int) -> Void = { _ in }
    /// (sheetIndex, rowIndex, columnIndex, newText) — fired after the
    /// optimistic in-memory apply; the caller persists to disk.
    var onCommitEdit: ((Int, Int, Int, String) -> Void)?

    @State private var workbook: SheetWorkbook?
    @State private var loadFailed = false
    @State private var sheetIndex = 0

    var body: some View {
        Group {
            if let workbook {
                loadedBody(workbook)
            } else if loadFailed {
                fallback()
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(cacheKey)|\(stamp ?? "-")") { await load() }
    }

    private func loadedBody(_ workbook: SheetWorkbook) -> some View {
        VStack(spacing: 0) {
            if workbook.sheets.count > 1 {
                SheetTabStrip(
                    sheetNames: workbook.sheets.map(\.name),
                    selectedIndex: sheetIndex,
                    onSelect: { index in
                        sheetIndex = index
                        onSheetChanged(index)
                    }
                )
            }
            FilePortalGridView(
                workbook: workbook,
                sheetIndex: sheetIndex,
                isCompact: isCompact,
                isEditable: isEditable && isContentInteractive,
                onCommitEdit: { rowIndex, columnIndex, text in
                    commitEdit(rowIndex: rowIndex, columnIndex: columnIndex, text: text)
                }
            )
            .allowsHitTesting(isContentInteractive)
        }
    }

    private func load() async {
        do {
            let loaded = try await SheetModelCache.shared.workbook(for: fileURL, cacheKey: cacheKey, stamp: stamp)
            workbook = loaded
            sheetIndex = min(max(0, initialSheetIndex), loaded.sheets.count - 1)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func commitEdit(rowIndex: Int, columnIndex: Int, text: String) {
        // Optimistic: the grid shows the new value immediately; disk + sync
        // follow through the caller (portal reloads from truth on failure).
        if let current = workbook {
            workbook = current.updatingCell(
                sheetIndex: sheetIndex, rowIndex: rowIndex, columnIndex: columnIndex, text: text
            )
        }
        onCommitEdit?(sheetIndex, rowIndex, columnIndex, text)
    }
}

// MARK: - Sheet tabs

private struct SheetTabStrip: View {
    let sheetNames: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space2) {
                ForEach(Array(sheetNames.enumerated()), id: \.offset) { index, name in
                    tab(index: index, name: name)
                }
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
        }
        .background(FilePortalChrome.surfaceFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.sepiaBorder.opacity(0.4)).frame(height: 0.5)
        }
    }

    private func tab(index: Int, name: String) -> some View {
        Button {
            onSelect(index)
        } label: {
            Text(name)
                .font(DS.caption2)
                .foregroundStyle(index == selectedIndex ? DS.text : DS.textMuted)
                .lineLimit(1)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 3)
                .background(
                    index == selectedIndex ? DS.entityFile.opacity(0.14) : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sheet \(name)")
    }
}

// MARK: - Grid

struct FilePortalGridView: View {
    let workbook: SheetWorkbook
    let sheetIndex: Int
    let isCompact: Bool
    var isEditable: Bool = false
    var onCommitEdit: ((Int, Int, String) -> Void)?

    @State private var editingCell: SheetCellAddress?

    private var sheet: SheetModel {
        workbook.sheets[min(max(0, sheetIndex), workbook.sheets.count - 1)]
    }

    private var layout: SheetGridLayout {
        SheetGridLayout(
            sheet: sheet,
            styles: workbook.styles,
            maxRows: isCompact ? 300 : 5_000,
            maxColumns: isCompact ? 40 : 120
        )
    }

    var body: some View {
        let layout = self.layout
        VStack(spacing: 0) {
            gridBody(layout: layout)
            if layout.isTruncated {
                truncationNote(layout: layout)
            }
        }
        .background(CommandKPreviewPaper.fill)
        .onChange(of: sheetIndex) { _, _ in editingCell = nil }
    }

    private func gridBody(layout: SheetGridLayout) -> some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(layout.bodyRowIndices, id: \.self) { rowIndex in
                        row(layout: layout, rowIndex: rowIndex, isHeader: false)
                    }
                } header: {
                    if let headerIndex = layout.headerRowIndex {
                        row(layout: layout, rowIndex: headerIndex, isHeader: true)
                    }
                }
            }
            .background(SlimOverlayScrollerEnforcer())
        }
        .scrollIndicators(.hidden)
    }

    private func row(layout: SheetGridLayout, rowIndex: Int, isHeader: Bool) -> some View {
        SheetGridRow(
            rowIndex: rowIndex,
            slots: layout.slots(rowIndex: rowIndex),
            rowHeight: layout.rowHeight(rowIndex: rowIndex),
            isHeader: isHeader,
            isEditable: isEditable,
            editingColumn: editingCell?.rowIndex == rowIndex ? editingCell?.columnIndex : nil,
            onBeginEdit: { columnIndex in
                editingCell = SheetCellAddress(rowIndex: rowIndex, columnIndex: columnIndex)
            },
            onCommitEdit: { columnIndex, text in
                editingCell = nil
                onCommitEdit?(rowIndex, columnIndex, text)
            },
            onCancelEdit: { editingCell = nil }
        )
    }

    private func truncationNote(layout: SheetGridLayout) -> some View {
        Text(layout.truncationDescription(sheet: sheet))
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space4)
            .background(FilePortalChrome.surfaceFill)
    }
}

struct SheetCellAddress: Equatable {
    let rowIndex: Int
    let columnIndex: Int
}

// MARK: - Row

private struct SheetGridRow: View {
    let rowIndex: Int
    let slots: [SheetGridLayout.CellSlot]
    let rowHeight: CGFloat
    let isHeader: Bool
    let isEditable: Bool
    let editingColumn: Int?
    let onBeginEdit: (Int) -> Void
    let onCommitEdit: (Int, String) -> Void
    let onCancelEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(slots, id: \.columnIndex) { slot in
                SheetGridCell(
                    slot: slot,
                    rowHeight: rowHeight,
                    isHeader: isHeader,
                    isEditing: editingColumn == slot.columnIndex,
                    isEditable: isEditable,
                    onBeginEdit: { onBeginEdit(slot.columnIndex) },
                    onCommitEdit: { text in onCommitEdit(slot.columnIndex, text) },
                    onCancelEdit: onCancelEdit
                )
            }
        }
        .background(isHeader ? AnyShapeStyle(FilePortalChrome.surfaceFill) : AnyShapeStyle(Color.clear))
    }
}

// MARK: - Cell

private struct SheetGridCell: View {
    let slot: SheetGridLayout.CellSlot
    let rowHeight: CGFloat
    let isHeader: Bool
    let isEditing: Bool
    let isEditable: Bool
    let onBeginEdit: () -> Void
    let onCommitEdit: (String) -> Void
    let onCancelEdit: () -> Void

    @State private var draftText = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack(alignment: slot.style.wrapText ? .topLeading : .leading) {
            if isEditing {
                editor
            } else {
                cellText
            }
        }
        .padding(.horizontal, DS.space6)
        .padding(.vertical, slot.style.wrapText ? 3 : 0)
        .frame(width: slot.width, height: rowHeight, alignment: slot.style.wrapText ? .topLeading : .leading)
        .background(fillColor)
        .overlay(alignment: .trailing) {
            if fillColor == nil {
                Rectangle().fill(DS.sepiaBorder.opacity(0.25)).frame(width: 0.5)
            }
        }
        .overlay(alignment: .bottom) {
            if fillColor == nil {
                Rectangle().fill(DS.sepiaBorder.opacity(0.25)).frame(height: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard isEditable, !isEditing else { return }
            onBeginEdit()
        }
    }

    private var cellText: some View {
        Text(slot.text)
            .font(cellFont)
            .italic(slot.style.isItalic)
            .foregroundStyle(inkColor)
            .lineLimit(slot.style.wrapText ? nil : 1)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
    }

    private var editor: some View {
        TextField("", text: $draftText)
            .textFieldStyle(.plain)
            .font(cellFont)
            .foregroundStyle(inkColor)
            .focused($editorFocused)
            .onSubmit { onCommitEdit(draftText) }
            .onExitCommand { onCancelEdit() }
            .onAppear {
                draftText = slot.text
                editorFocused = true
            }
            .background(DS.accentGlow.opacity(0.18))
    }

    /// File font sizes map onto the app's typography rungs — fidelity of
    /// emphasis without leaving the DS type system.
    private var cellFont: Font {
        let size = slot.style.fontPointSize ?? 11
        let base: Font = size >= 14 ? DS.body : (size >= 12 ? DS.caption : DS.caption2)
        return slot.style.isBold ? base.weight(.semibold) : base
    }

    private var inkColor: Color {
        if let hex = slot.style.textColorHex {
            return Color(hex: hex)
        }
        return isHeader ? CommandKPreviewPaper.text : CommandKPreviewPaper.textSecondary
    }

    private var fillColor: Color? {
        slot.style.fillColorHex.map { Color(hex: $0) }
    }
}

// MARK: - Layout math

/// Pure, pre-computed layout for one sheet: display caps, header detection,
/// per-column widths (the file's own when declared, estimated otherwise),
/// per-row heights, merge spans, and Excel's empty-neighbor overflow. Unit-
/// tested in SheetGridLayoutTests — keep it free of SwiftUI types beyond
/// CGFloat/Font-free values.
struct SheetGridLayout: Equatable {
    struct CellSlot: Equatable {
        let columnIndex: Int
        let width: CGFloat
        let text: String
        let style: SheetCellStyle
    }

    static let defaultRowHeight: CGFloat = 22
    static let defaultFileColumnWidth: CGFloat = 64   // Excel's 8.43-char default
    static let minColumnWidth: CGFloat = 56
    static let maxColumnWidth: CGFloat = 260
    /// Estimated glyph advance for the caption-sized cell font.
    static let estimatedCharacterWidth: CGFloat = 6.4
    static let widthSampleRowCount = 60
    /// How many empty neighbors a long cell may overflow across.
    static let maxOverflowColumns = 8

    let displayRowCount: Int
    let displayColumnCount: Int
    let columnWidths: [CGFloat]
    let headerRowIndex: Int?
    let isTruncated: Bool

    private let rows: [[SheetCell]]
    private let rowHeights: [CGFloat?]?
    private let styles: [SheetCellStyle]

    init(sheet: SheetModel, styles: [SheetCellStyle] = [], maxRows: Int, maxColumns: Int) {
        rows = sheet.rows
        rowHeights = sheet.fileRowHeights
        self.styles = styles
        displayRowCount = min(sheet.rowCount, maxRows)
        displayColumnCount = min(sheet.columnCount, maxColumns)
        isTruncated = sheet.rowCount > maxRows || sheet.columnCount > maxColumns
        headerRowIndex = Self.detectHeaderRow(rows: sheet.rows, styles: styles)
        columnWidths = Self.resolveColumnWidths(
            sheet: sheet,
            displayColumnCount: displayColumnCount
        )
    }

    /// Body rows exclude the pinned header row.
    var bodyRowIndices: [Int] {
        let all = Array(0..<displayRowCount)
        guard let headerRowIndex else { return all }
        return all.filter { $0 != headerRowIndex }
    }

    func rowHeight(rowIndex: Int) -> CGFloat {
        guard let rowHeights, rowHeights.indices.contains(rowIndex),
              let height = rowHeights[rowIndex] else {
            return Self.defaultRowHeight
        }
        return max(height, Self.defaultRowHeight)
    }

    func style(for cell: SheetCell) -> SheetCellStyle {
        guard let index = cell.styleIndex, styles.indices.contains(index) else { return .plain }
        return styles[index]
    }

    /// Render slots for one row: merge anchors widen across their span,
    /// covered cells are skipped, and a long unwrapped cell overflows across
    /// consecutive empty neighbors — Excel's exact reading behavior.
    func slots(rowIndex: Int) -> [CellSlot] {
        let row = rows.indices.contains(rowIndex) ? rows[rowIndex] : []
        var result: [CellSlot] = []
        var column = 0
        while column < displayColumnCount {
            let cell = column < row.count ? row[column] : .empty
            if cell.columnSpan == 0 { column += 1; continue }

            let cellStyle = style(for: cell)
            var coveredColumns = min(max(cell.columnSpan, 1), displayColumnCount - column)

            // Overflow: plain, unwrapped, unmerged text spills over empties.
            if cell.columnSpan == 1, !cell.text.isEmpty, !cellStyle.wrapText {
                let needed = CGFloat(cell.text.count) * Self.estimatedCharacterWidth + 14
                var width = columnWidths[column]
                var next = column + 1
                while width < needed,
                      next < displayColumnCount,
                      next - column <= Self.maxOverflowColumns,
                      (next >= row.count || (row[next].text.isEmpty && row[next].columnSpan == 1)) {
                    width += columnWidths[next]
                    next += 1
                }
                coveredColumns = next - column
            }

            let width = (column..<(column + coveredColumns)).reduce(CGFloat(0)) { $0 + columnWidths[$1] }
            result.append(CellSlot(columnIndex: column, width: width, text: cell.text, style: cellStyle))
            column += coveredColumns
        }
        return result
    }

    func truncationDescription(sheet: SheetModel) -> String {
        var parts: [String] = []
        if sheet.rowCount > displayRowCount {
            parts.append("first \(displayRowCount) of \(sheet.rowCount) rows")
        }
        if sheet.columnCount > displayColumnCount {
            parts.append("first \(displayColumnCount) of \(sheet.columnCount) columns")
        }
        return "Showing " + parts.joined(separator: ", ") + " — peek for more"
    }

    // MARK: Header detection

    /// Style-aware: the first early row whose non-empty cells all share one
    /// solid fill (≥2 of them) reads as the header band. Styleless sheets
    /// (CSV) fall back to the textual heuristic. No confident match pins
    /// nothing — a wrong pin is worse than none.
    static func detectHeaderRow(rows: [[SheetCell]], styles: [SheetCellStyle]) -> Int? {
        if !styles.isEmpty {
            for rowIndex in 0..<min(rows.count, 10) {
                let filled = rows[rowIndex].filter { !$0.text.isEmpty }
                guard filled.count >= 2 else { continue }
                let fills = Set(filled.map { cell -> String? in
                    guard let index = cell.styleIndex, styles.indices.contains(index) else { return nil }
                    return styles[index].fillColorHex
                })
                if fills.count == 1, let only = fills.first, only != nil {
                    return rowIndex
                }
            }
            return nil
        }

        guard let first = rows.first, !first.isEmpty else { return nil }
        let firstLooksTextual = first.allSatisfy { !$0.text.isEmpty && Double($0.text) == nil }
        guard firstLooksTextual else { return nil }
        guard rows.count > 1 else { return 0 }
        let secondHasData = rows[1].contains { !$0.text.isEmpty }
        return secondHasData ? 0 : nil
    }

    // MARK: Widths

    static func resolveColumnWidths(sheet: SheetModel, displayColumnCount: Int) -> [CGFloat] {
        if let fileWidths = sheet.fileColumnWidths {
            return (0..<displayColumnCount).map { index in
                guard fileWidths.indices.contains(index), let width = fileWidths[index] else {
                    return defaultFileColumnWidth
                }
                return max(width, 12)
            }
        }
        return measureColumnWidths(
            rows: sheet.rows,
            columnCount: displayColumnCount,
            sampleRowCount: widthSampleRowCount
        )
    }

    static func measureColumnWidths(rows: [[SheetCell]], columnCount: Int, sampleRowCount: Int) -> [CGFloat] {
        var widths = [CGFloat](repeating: minColumnWidth, count: columnCount)
        for row in rows.prefix(sampleRowCount) {
            for (columnIndex, cell) in row.prefix(columnCount).enumerated() {
                let estimated = CGFloat(cell.text.count) * estimatedCharacterWidth + 16
                if estimated > widths[columnIndex] {
                    widths[columnIndex] = min(estimated, maxColumnWidth)
                }
            }
        }
        return widths
    }
}

// MARK: - Scroller suppression

/// The fat-legacy-scrollbar law (see CosmoSlimScroll): `.scrollIndicators`
/// alone can't stop "Show scroll bars: Always" from forcing a fat bar into
/// an NSScrollView. The grid scrolls both axes, so instead of the vertical-
/// only CosmoSlimScroll wrapper it forces overlay-style scrollers at the
/// AppKit level.
private struct SlimOverlayScrollerEnforcer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.enclosingScrollView) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.enclosingScrollView) }
    }

    private func configure(_ scrollView: NSScrollView?) {
        guard let scrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.horizontalScroller?.controlSize = .mini
    }
}
