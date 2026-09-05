import AppKit
import SwiftUI

/// The table block in the note editor. Content, not chrome: the grid sits in
/// the reading measure with hairline rules; handles, insertion affordances
/// and washes live in a 12 pt apron around it and only appear on hover or
/// while the table is being worked. ONE live editor (the focused cell);
/// every other cell is the serializer's static text.
struct TableBlockView: View {
    @Binding var block: RichBlock
    let focusCoordinator: BlockFocusCoordinator
    var typography: TableCellTypography
    var allowMentions: Bool = true
    var editorTargetID: String? = nil
    /// Esc / ⌘A escalation: the host selects this block.
    var onSelectBlock: () -> Void = {}
    /// ⌘A past the block: the host selects every block.
    var onSelectAllBlocks: () -> Bool = { false }
    /// ↑ beyond the first row / ↓ beyond the last row.
    var onExitUp: () -> Void = {}
    var onExitDown: () -> Void = {}
    var onDeleteTable: () -> Void = {}
    /// "Convert to text": the host replaces this block with paragraphs.
    var onReplaceWithBlocks: ([RichBlock]) -> Void = { _ in }
    /// Structural commits with an undo action name. nil → the binding.
    var onEdit: ((RichBlock, String) -> Void)? = nil

    @State private var coordinator = TableFocusCoordinator()
    @State private var contentWidth: CGFloat = 0
    @State private var isHovered = false
    @State private var metrics = TableGridMetrics(columnWidths: [], rowOrigins: [], rowHeights: [])
    @State private var hint: String?
    @State private var hintTask: Task<Void, Never>?
    @State private var menuBuilders: [RichTableCellAddress: TableCellNSMenuBuilder] = [:]
    @FocusState private var chromeFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var table: RichTable { block.table ?? RichTable() }
    private var rowState: BlockRowFocusState { focusCoordinator.rowState(for: block.id) }

    private var minimumColumnWidth: CGFloat { max(56, (typography.fontSize * 4.2).rounded()) }
    private var minimumRowHeight: CGFloat { typography.lineHeight + TableCellTypography.verticalPadding * 2 }

    private var resolvedWidths: [CGFloat] {
        let available = Double(contentWidth > 0 ? contentWidth : 320)
        return table.resolvedColumnWidths(available: available, minimum: Double(minimumColumnWidth)).map { CGFloat($0) }
    }

    // MARK: Body

    var body: some View {
        canvas
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(widthReader)
            .onHover { isHovered = $0 }
            .onAppear { focusCoordinator.register(block.id) }
            .onDisappear { focusCoordinator.unregister(block.id) }
            .onChange(of: rowState.isFocused, initial: true) { _, focused in handleBlockFocusChange(focused) }
            .onChange(of: coordinator.focusedCell) { _, cell in
                if cell != nil { focusCoordinator.focus(block.id) }
            }
            .overlay(alignment: .top) { hintCapsule }
            .focusable(coordinator.hasRangeSelection)
            .focused($chromeFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handleChromeKey(press) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Table, \(table.rowCount) rows by \(table.columnCount) columns")
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size.width, initial: true) { _, width in
                    let next = max(0, width - TableChromeLayer.apron * 2)
                    if abs(next - contentWidth) > 0.5 { contentWidth = next }
                }
        }
    }

    @ViewBuilder
    private var canvas: some View {
        let widths = resolvedWidths
        let naturalWidth = widths.reduce(0, +)
        if contentWidth > 0, naturalWidth > contentWidth + 0.5 {
            ScrollView(.horizontal, showsIndicators: false) {
                gridWithChrome(widths).padding(TableChromeLayer.apron)
            }
            .scrollClipDisabled()
            .mask(horizontalFadeMask)
        } else {
            gridWithChrome(widths).padding(TableChromeLayer.apron)
        }
    }

    private var horizontalFadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 18)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18)
        }
    }

    private func gridWithChrome(_ widths: [CGFloat]) -> some View {
        ZStack(alignment: .topLeading) {
            grid(widths)
                .clipShape(outerShape)
                .overlay(outerBorder)
        }
        .coordinateSpace(name: TableChromeLayer.coordinateSpace)
        .overlayPreferenceValue(TableCellFramesKey.self) { anchors in
            GeometryReader { proxy in
                let resolved = TableGridMetrics.resolve(
                    table: table,
                    widths: widths,
                    frames: anchors.mapValues { proxy[$0] }
                )
                chromeLayer(resolved)
                    .onChange(of: resolved, initial: true) { _, next in
                        if next != metrics { metrics = next }
                    }
            }
        }
        .popover(isPresented: $coordinator.showsOptions, arrowEdge: .top) { optionsPopover }
    }

    private var outerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: table.style == .clean ? 0 : 8, style: .continuous)
    }

    @ViewBuilder
    private var outerBorder: some View {
        switch table.style {
        case .grid:
            outerShape.strokeBorder(DS.documentBorderSubtle, lineWidth: 0.5)
        case .lines:
            VStack(spacing: 0) {
                Rectangle().fill(DS.documentBorderSubtle).frame(height: 0.5)
                Spacer(minLength: 0)
                Rectangle().fill(DS.documentBorderSubtle).frame(height: 0.5)
            }
        case .clean:
            EmptyView()
        }
    }

    // MARK: Grid

    private struct AnchorEntry: Identifiable {
        let id: UUID
        let address: RichTableCellAddress
        let cell: RichTableCell
    }

    private var anchorEntries: [AnchorEntry] {
        var entries: [AnchorEntry] = []
        for (rowIndex, row) in table.rows.enumerated() {
            for (columnIndex, cell) in row.cells.enumerated() where !cell.isCovered {
                entries.append(AnchorEntry(id: cell.id, address: RichTableCellAddress(row: rowIndex, column: columnIndex), cell: cell))
            }
        }
        return entries
    }

    private func grid(_ widths: [CGFloat]) -> some View {
        TableLayout(columnWidths: widths, rowCount: table.rowCount, minimumRowHeight: minimumRowHeight) {
            ForEach(anchorEntries) { entry in
                cellView(entry.address, cell: entry.cell)
                    .tableCellPlacement(placement(for: entry.address))
                    .anchorPreference(key: TableCellFramesKey.self, value: .bounds) { [entry.address: $0] }
            }
        }
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: table.rows.map(\.id))
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: table.columns.map(\.id))
    }

    private func placement(for address: RichTableCellAddress) -> TableCellPlacement {
        let span = table.spanRect(ofAnchorAt: address)
        return TableCellPlacement(rows: span.rows, columns: span.columns)
    }

    private func isHeader(_ address: RichTableCellAddress) -> Bool {
        (table.hasHeaderRow && address.row == 0) || (table.hasHeaderColumn && address.column == 0)
    }

    private func alignment(_ address: RichTableCellAddress, cell: RichTableCell) -> RichTableAlignment {
        cell.alignment ?? (table.columns.indices.contains(address.column) ? table.columns[address.column].alignment : .leading)
    }

    @ViewBuilder
    private func cellView(_ address: RichTableCellAddress, cell: RichTableCell) -> some View {
        let header = isHeader(address)
        let align = alignment(address, cell: cell)
        let focused = coordinator.focusedCell == address
        TableCellFrame(
            background: background(for: address, cell: cell, isHeader: header),
            rules: rules(for: address),
            isSelected: isSelected(address),
            isFocused: focused,
            darkMode: typography.darkMode
        ) {
            if focused {
                TableCellEditor(
                    cellID: cell.id,
                    inlines: inlinesBinding(address),
                    typography: typography,
                    isHeader: header,
                    alignment: align,
                    allowMentions: allowMentions,
                    editorTargetID: editorTargetID,
                    caretRequest: coordinator.pendingCaret,
                    contextMenu: { nsMenu(for: address) },
                    onBoundaryCommand: { handleBoundary($0, at: address) }
                )
            } else {
                TableStaticCell(
                    inlines: cell.inlines,
                    typography: typography,
                    isHeader: header,
                    alignment: align,
                    verticalAlignment: cell.verticalAlignment ?? .top
                )
                .equatable()
                .contentShape(Rectangle())
                .onTapGesture { tapCell(address) }
                .gesture(rangeDrag(from: address))
                .contextMenu {
                    TableCellContextMenu(context: menuContext(address)) { perform($0, at: address) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(header ? "Header, row \(address.row + 1), column \(address.column + 1)" : "Row \(address.row + 1), column \(address.column + 1)")
    }

    private func background(for address: RichTableCellAddress, cell: RichTableCell, isHeader: Bool) -> Color? {
        if let toneID = cell.toneID, RichInlineColor.isKnownTone(toneID) {
            return NoteInkPalette.tone(toneID).ink(darkMode: typography.darkMode).opacity(typography.darkMode ? 0.24 : 0.16)
        }
        if isHeader {
            return NoteInkPalette.tone("gilt").ink(darkMode: typography.darkMode).opacity(typography.darkMode ? 0.14 : 0.08)
        }
        if table.isStriped, table.bodyRowIndices.contains(address.row) {
            let bodyIndex = address.row - table.bodyRowIndices.lowerBound
            if bodyIndex % 2 == 1 { return DS.glassSectionFill.opacity(0.5) }
        }
        return nil
    }

    private func rules(for address: RichTableCellAddress) -> TableCellRules {
        let span = table.spanRect(ofAnchorAt: address)
        let lastColumn = span.columns.upperBound >= table.columnCount - 1
        let lastRow = span.rows.upperBound >= table.rowCount - 1
        switch table.style {
        case .grid:
            return TableCellRules(right: !lastColumn, bottom: !lastRow, bottomIsHeaderRule: false)
        case .lines:
            return TableCellRules(right: false, bottom: !lastRow, bottomIsHeaderRule: false)
        case .clean:
            let closesHeader = table.hasHeaderRow && span.rows.upperBound == 0 && table.rowCount > 1
            return TableCellRules(right: false, bottom: closesHeader, bottomIsHeaderRule: true)
        }
    }

    private func isSelected(_ address: RichTableCellAddress) -> Bool {
        guard let rect = coordinator.selection?.rect(in: table) else { return false }
        return table.expandedToSpans(rect).contains(address)
    }

    private func inlinesBinding(_ address: RichTableCellAddress) -> Binding<[RichInlineNode]> {
        Binding(
            get: { block.table?.cell(at: address)?.inlines ?? [] },
            set: { next in
                guard var current = block.table, current.contains(address), current[address].inlines != next else { return }
                current[address].inlines = next
                var updated = block
                updated.table = current
                block = updated
            }
        )
    }

    // MARK: Chrome

    private func chromeLayer(_ metrics: TableGridMetrics) -> some View {
        TableChromeLayer(
            table: table,
            metrics: metrics,
            coordinator: coordinator,
            isHovered: isHovered,
            darkMode: typography.darkMode,
            onSelectRow: selectRow,
            onSelectColumn: selectColumn,
            onMoveRow: { from, slot in moveLine(.row, from: from, slot: slot) },
            onMoveColumn: { from, slot in moveLine(.column, from: from, slot: slot) },
            onInsertRow: { index in insertRow(at: index, focusColumn: 0) },
            onInsertColumn: { index in insertColumn(at: index) },
            onResizeColumns: { left, delta in
                mutate("Resize Column") { try RichTableOperations.resizeColumnPair(in: $0, left: left, delta: Double(delta)) }
            },
            onDistributeColumns: { mutate("Distribute Columns") { RichTableOperations.distributeColumns(in: $0) } },
            onResizeGrid: { rows, columns in mutate("Resize Table") { try RichTableOperations.resize(in: $0, rows: rows, columns: columns) } },
            onOptions: { coordinator.showsOptions = true }
        )
    }

    @ViewBuilder
    private var hintCapsule: some View {
        if let hint {
            Text(hint)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.text)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space4)
                .background(Capsule(style: .continuous).fill(DS.glassCardFill))
                .overlay(Capsule(style: .continuous).strokeBorder(DS.documentBorderSubtle, lineWidth: 0.5))
                .offset(y: -6)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                .allowsHitTesting(false)
        }
    }

    private var optionsPopover: some View {
        TableOptionsPopover(
            table: table,
            darkMode: typography.darkMode,
            onToggleHeaderRow: { mutate("Header Row") { try RichTableOperations.setHeaderRow(in: $0, enabled: !$0.hasHeaderRow) } },
            onToggleHeaderColumn: { mutate("Header Column") { RichTableOperations.setHeaderColumn(in: $0, enabled: !$0.hasHeaderColumn) } },
            onToggleStriped: { mutate("Striped Rows") { RichTableOperations.setStriped(in: $0, isStriped: !$0.isStriped) } },
            onSetStyle: { style in mutate("Table Style") { RichTableOperations.setStyle(in: $0, style: style) } },
            onDistribute: { mutate("Distribute Columns") { RichTableOperations.distributeColumns(in: $0) } },
            onSort: { column, ascending in sort(column: column, ascending: ascending) },
            onTranspose: { mutate("Transpose Table") { try RichTableOperations.transpose(in: $0) } },
            onConvertToText: { onReplaceWithBlocks(RichTableOperations.tableToBlocks(table)) },
            onCopy: { format in copyWholeTable(as: format) },
            onDelete: onDeleteTable
        )
    }

    // MARK: Focus & selection

    private func handleBlockFocusChange(_ focused: Bool) {
        if focused {
            guard coordinator.focusedCell == nil, coordinator.selection == nil, table.rowCount > 0 else { return }
            let row = focusCoordinator.lastNavigationOffset < 0 ? table.rowCount - 1 : 0
            let address = table.anchorAddress(of: RichTableCellAddress(row: row, column: 0))
            coordinator.focus(address, caretOffsetFromEnd: 0)
        } else {
            coordinator.blur()
            coordinator.clearSelection()
        }
    }

    private func tapCell(_ address: RichTableCellAddress) {
        if NSEvent.modifierFlags.contains(.shift), coordinator.focusedCell != nil || coordinator.selection != nil {
            resignEditor()
            coordinator.extendSelection(to: address)
            chromeFocused = true
            return
        }
        coordinator.focus(address, caretOffsetFromEnd: 0, windowPoint: NSApp.currentEvent?.locationInWindow)
    }

    private func rangeDrag(from origin: RichTableCellAddress) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(TableChromeLayer.coordinateSpace))
            .onChanged { value in
                let target = address(at: value.location)
                if coordinator.focusedCell != nil { resignEditor() }
                coordinator.selectionAnchor = origin
                coordinator.selection = .range(RichTableRect(origin, target))
            }
            .onEnded { _ in chromeFocused = true }
    }

    private func address(at point: CGPoint) -> RichTableCellAddress {
        let column = metrics.columnIndex(at: point.x)
        let row = metrics.rowIndex(at: point.y)
        return table.anchorAddress(of: RichTableCellAddress(row: row, column: column))
    }

    private func selectRow(_ row: Int, extend: Bool) {
        resignEditor()
        if extend, case .rows(let rows) = coordinator.selection {
            coordinator.select(.rows(min(rows.lowerBound, row)...max(rows.upperBound, row)))
        } else {
            coordinator.select(.rows(row...row))
        }
        chromeFocused = true
    }

    private func selectColumn(_ column: Int, extend: Bool) {
        resignEditor()
        if extend, case .columns(let columns) = coordinator.selection {
            coordinator.select(.columns(min(columns.lowerBound, column)...max(columns.upperBound, column)))
        } else {
            coordinator.select(.columns(column...column))
        }
        chromeFocused = true
    }

    /// The live editor's text view must give up first responder before the
    /// SwiftUI focus layer can own the keyboard.
    private func resignEditor() {
        if coordinator.focusedCell != nil { coordinator.blur() }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    // MARK: Boundary commands from the live cell

    private func handleBoundary(_ command: EditorBoundaryCommand, at address: RichTableCellAddress) -> Bool {
        switch command {
        case .tableNavigate(let direction, _, let live):
            commitLiveText(live, at: address)
            return navigate(direction, from: address, isReturn: false)
        case .tableReturn(_, let live):
            commitLiveText(live, at: address)
            return navigate(.down, from: address, isReturn: true)
        case .tableEdge(let direction):
            return jumpToEdge(direction, from: address)
        case .tableAddRowBelow(let live):
            commitLiveText(live, at: address)
            let span = table.spanRect(ofAnchorAt: address)
            insertRow(at: span.rows.upperBound + 1, focusColumn: address.column)
            return true
        case .tablePasteGrid(let grid, let live):
            commitLiveText(live, at: address)
            fill(grid, from: address)
            return true
        case .escapeSelectBlock:
            resignEditor()
            coordinator.clearSelection()
            onSelectBlock()
            return true
        case .selectAllBlocks:
            resignEditor()
            coordinator.select(.table)
            coordinator.selectAllRung = 1
            chromeFocused = true
            return true
        case .blockShortcut(let shortcut, let live):
            return handleShortcut(shortcut, live: live, at: address)
        default:
            return false
        }
    }

    private func handleShortcut(_ shortcut: BlockKeyboardShortcut, live: String, at address: RichTableCellAddress) -> Bool {
        commitLiveText(live, at: address)
        switch shortcut {
        case .moveUp:
            moveLine(.row, from: address.row, slot: address.row - 1)
            return true
        case .moveDown:
            moveLine(.row, from: address.row, slot: address.row + 2)
            return true
        case .tableAddRowBelow:
            let span = table.spanRect(ofAnchorAt: address)
            insertRow(at: span.rows.upperBound + 1, focusColumn: address.column)
            return true
        case .tableMoveColumn(let delta):
            moveLine(.column, from: address.column, slot: delta < 0 ? address.column - 1 : address.column + 2)
            return true
        case .tableMergeCells:
            mergeSelection(fallbackAnchor: address)
            return true
        case .tableUnmergeCells:
            unmerge(at: address)
            return true
        case .tableOptions:
            coordinator.showsOptions = true
            return true
        case .duplicate, .heading, .checklistToggle:
            return false
        }
    }

    private func commitLiveText(_ live: String, at address: RichTableCellAddress) {
        guard var current = block.table, current.contains(address) else { return }
        let cell = current[address]
        guard cell.plainText != live else { return }
        current[address].inlines = live.isEmpty ? [] : [.text(live)]
        var updated = block
        updated.table = current
        block = updated
    }

    private func navigate(_ direction: RichTableDirection, from address: RichTableCellAddress, isReturn: Bool) -> Bool {
        switch RichTableOperations.nextCellAddress(in: table, after: address, direction: direction, wrapRows: true) {
        case .cell(let next):
            let length = table.cell(at: next)?.plainText.utf16.count ?? 0
            let entersAtStart = direction == .right || direction == .nextCell || direction == .down || direction == .up
            coordinator.focus(next, caretOffsetFromEnd: entersAtStart ? length : 0)
            return true
        case .beyondEdge(let edge):
            switch edge {
            case .down:
                if isReturn {
                    insertRow(at: table.rowCount, focusColumn: address.column)
                } else {
                    resignEditor()
                    onExitDown()
                }
                return true
            case .nextCell:
                insertRow(at: table.rowCount, focusColumn: 0)
                return true
            case .up:
                resignEditor()
                onExitUp()
                return true
            case .left, .previousCell, .right:
                return true
            }
        }
    }

    private func jumpToEdge(_ direction: RichTableDirection, from address: RichTableCellAddress) -> Bool {
        var target = address
        switch direction {
        case .up: target.row = 0
        case .down: target.row = table.rowCount - 1
        case .left: target.column = 0
        case .right: target.column = table.columnCount - 1
        case .nextCell, .previousCell: return false
        }
        let resolved = table.anchorAddress(of: target)
        guard resolved != address else { return true }
        coordinator.focus(resolved, caretOffsetFromEnd: 0)
        return true
    }

    // MARK: Chrome keyboard (range / row / column selection)

    private func handleChromeKey(_ press: KeyPress) -> KeyPress.Result {
        guard let selection = coordinator.selection, let rect = selection.rect(in: table) else { return .ignored }
        let shift = press.modifiers.contains(.shift)
        let command = press.modifiers.contains(.command)
        switch press.key {
        case .escape:
            coordinator.clearSelection()
            onSelectBlock()
            return .handled
        case .return:
            coordinator.focus(table.anchorAddress(of: rect.topLeft), caretOffsetFromEnd: 0)
            return .handled
        case .delete, .deleteForward:
            deleteSelection(selection, rect: rect)
            return .handled
        case .upArrow, .downArrow, .leftArrow, .rightArrow:
            let lead = coordinator.selectionAnchor == rect.topLeft ? rect.bottomRight : rect.topLeft
            var next = lead
            switch press.key {
            case .upArrow: next.row = max(0, lead.row - 1)
            case .downArrow: next.row = min(table.rowCount - 1, lead.row + 1)
            case .leftArrow: next.column = max(0, lead.column - 1)
            default: next.column = min(table.columnCount - 1, lead.column + 1)
            }
            if shift {
                coordinator.extendSelection(to: next)
            } else {
                coordinator.focus(table.anchorAddress(of: next), caretOffsetFromEnd: 0)
            }
            return .handled
        default:
            break
        }
        guard command, let character = press.characters.lowercased().first else { return .ignored }
        switch character {
        case "c":
            copySelection(rect)
            return .handled
        case "x":
            copySelection(rect)
            mutate("Cut Cells") { try RichTableOperations.clearCells(in: $0, range: rect) }
            return .handled
        case "v":
            pasteIntoSelection(rect)
            return .handled
        case "a":
            if coordinator.selectAllRung <= 1 {
                coordinator.selectAllRung = 2
                coordinator.clearSelection()
                onSelectBlock()
            } else {
                _ = onSelectAllBlocks()
            }
            return .handled
        default:
            return .ignored
        }
    }

    private func deleteSelection(_ selection: RichTableSelection, rect: RichTableRect) {
        switch selection {
        case .rows(let rows):
            guard rows.count < table.rowCount else { onDeleteTable(); return }
            mutate("Delete Rows") { table in
                var next = table
                for row in rows.reversed() { next = try RichTableOperations.deleteRow(in: next, at: row) }
                return next
            }
            coordinator.clearSelection()
        case .columns(let columns):
            guard columns.count < table.columnCount else { onDeleteTable(); return }
            mutate("Delete Columns") { table in
                var next = table
                for column in columns.reversed() { next = try RichTableOperations.deleteColumn(in: next, at: column) }
                return next
            }
            coordinator.clearSelection()
        case .table:
            onDeleteTable()
        case .cell, .range:
            mutate("Clear Cells") { try RichTableOperations.clearCells(in: $0, range: rect) }
        }
    }

    // MARK: Mutations

    private func commit(_ updated: RichBlock, _ name: String) {
        if let onEdit {
            onEdit(updated, name)
        } else {
            block = updated
        }
    }

    private func mutate(_ name: String, _ transform: (RichTable) throws -> RichTable) {
        guard let current = block.table else { return }
        do {
            let next = try transform(current)
            guard next != current else { return }
            var updated = block
            updated.table = next
            commit(updated, name)
        } catch let error as RichTableError {
            showHint(Self.hint(for: error))
        } catch {
            showHint("That change isn't possible here")
        }
    }

    private func mutateResult(_ name: String, _ transform: (RichTable) throws -> RichTableEditResult) {
        guard let current = block.table else { return }
        do {
            let result = try transform(current)
            var updated = block
            updated.table = result.table
            commit(updated, name)
            if let selection = result.selection {
                coordinator.select(selection)
            }
            if let focus = result.focus {
                coordinator.focus(focus, caretOffsetFromEnd: 0)
            }
        } catch let error as RichTableError {
            showHint(Self.hint(for: error))
        } catch {
            showHint("That change isn't possible here")
        }
    }

    static func hint(for error: RichTableError) -> String {
        switch error {
        case .wouldBreakSpan: return "Unmerge cells to move this"
        case .spanCrossesHeader: return "A merged cell can't cross the header row"
        case .invalidRange: return "Select a rectangle of cells"
        case .notMerged: return "These cells aren't merged"
        case .cannotSortWithVerticalSpans: return "Unmerge cells to sort"
        case .cannotDeleteLastLine: return "A table keeps at least one row and column"
        case .cannotMoveHeaderRow: return "The header row stays on top"
        case .outOfBounds: return "That change isn't possible here"
        }
    }

    private func showHint(_ text: String) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        hintTask?.cancel()
        withAnimation(reduceMotion ? nil : ProMotionSprings.snappy) { hint = text }
        hintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : ProMotionSprings.gentle) { hint = nil }
        }
    }

    private enum LineAxis { case row, column }

    private func moveLine(_ axis: LineAxis, from: Int, slot: Int) {
        let count = axis == .row ? table.rowCount : table.columnCount
        let clampedSlot = max(0, min(count, slot))
        let to = clampedSlot > from ? clampedSlot - 1 : clampedSlot
        guard to != from, to >= 0, to < count else { return }
        switch axis {
        case .row:
            mutate("Move Row") { try RichTableOperations.moveRow(in: $0, from: from, to: to) }
            if case .rows = coordinator.selection { coordinator.select(.rows(to...to)) }
            if let focused = coordinator.focusedCell, focused.row == from {
                coordinator.focus(RichTableCellAddress(row: to, column: focused.column), caretOffsetFromEnd: 0)
            }
        case .column:
            mutate("Move Column") { try RichTableOperations.moveColumn(in: $0, from: from, to: to) }
            if case .columns = coordinator.selection { coordinator.select(.columns(to...to)) }
            if let focused = coordinator.focusedCell, focused.column == from {
                coordinator.focus(RichTableCellAddress(row: focused.row, column: to), caretOffsetFromEnd: 0)
            }
        }
    }

    private func insertRow(at index: Int, focusColumn: Int) {
        mutateResult("Insert Row") { table in
            var result = try RichTableOperations.insertRow(in: table, at: index, copyingStyleOfRow: max(0, index - 1))
            result.focus = result.table.anchorAddress(of: RichTableCellAddress(row: min(index, result.table.rowCount - 1), column: focusColumn))
            return result
        }
    }

    private func insertColumn(at index: Int) {
        mutateResult("Insert Column") { table in
            var result = try RichTableOperations.insertColumn(in: table, at: index)
            let row = coordinator.focusedCell?.row ?? 0
            result.focus = result.table.anchorAddress(of: RichTableCellAddress(row: row, column: min(index, result.table.columnCount - 1)))
            return result
        }
    }

    private func sort(column: Int, ascending: Bool) {
        mutate("Sort Rows") { try RichTableOperations.sortRows(in: $0, byColumn: column, ascending: ascending) }
    }

    private func mergeSelection(fallbackAnchor: RichTableCellAddress) {
        guard let rect = coordinator.selection?.rect(in: table), !rect.isSingleCell else {
            showHint("Select the cells to merge")
            return
        }
        mutateResult("Merge Cells") { try RichTableOperations.mergeCells(in: $0, rect: $0.expandedToSpans(rect)) }
    }

    private func unmerge(at address: RichTableCellAddress) {
        mutateResult("Unmerge Cells") { try RichTableOperations.unmergeCell(in: $0, anchor: $0.anchorAddress(of: address)) }
    }

    private func fill(_ grid: [[[RichInlineNode]]], from anchor: RichTableCellAddress) {
        mutateResult("Paste Cells") { try RichTableOperations.fill(in: $0, from: anchor, grid: grid, expand: true) }
    }

    // MARK: Clipboard

    private func subtable(_ rect: RichTableRect) -> RichTable {
        var rows: [RichTableRow] = []
        for rowIndex in rect.rows {
            var cells: [RichTableCell] = []
            for columnIndex in rect.columns {
                let address = RichTableCellAddress(row: rowIndex, column: columnIndex)
                let anchor = table.anchorAddress(of: address)
                var cell = table.cell(at: anchor) ?? RichTableCell()
                if anchor != address { cell = RichTableCell() }
                cell.id = UUID()
                cell.rowSpan = 1
                cell.colSpan = 1
                cell.coveredBy = nil
                cells.append(cell)
            }
            rows.append(RichTableRow(cells: cells))
        }
        let columns = rect.columns.map { index -> RichTableColumn in
            var column = table.columns.indices.contains(index) ? table.columns[index] : RichTableColumn()
            column.id = UUID()
            return column
        }
        return RichTable(
            columns: columns,
            rows: rows,
            hasHeaderRow: table.hasHeaderRow && rect.rows.lowerBound == 0,
            hasHeaderColumn: table.hasHeaderColumn && rect.columns.lowerBound == 0,
            style: table.style,
            isStriped: table.isStriped
        )
    }

    private func copySelection(_ rect: RichTableRect) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(table.tsv(rect), forType: .string)
        pasteboard.setString(TableClipboardWriter.html(for: table, rect: rect), forType: .html)
        if let data = try? JSONEncoder().encode([RichBlock.table(subtable(rect))]) {
            pasteboard.setData(data, forType: .cosmoBlocks)
        }
    }

    private func copyWholeTable(as format: TableOptionsPopover.TableCopyFormat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch format {
        case .tsv:
            pasteboard.setString(table.tsv(), forType: .string)
        case .markdown:
            pasteboard.setString(table.markdown, forType: .string)
        case .html:
            let html = TableClipboardWriter.html(for: table)
            pasteboard.setString(html, forType: .html)
            pasteboard.setString(html, forType: .string)
        }
        if let data = try? JSONEncoder().encode([block]) {
            pasteboard.setData(data, forType: .cosmoBlocks)
        }
    }

    private func pasteIntoSelection(_ rect: RichTableRect) {
        let pasteboard = NSPasteboard.general
        var grid: [[[RichInlineNode]]] = []
        if let data = pasteboard.data(forType: .cosmoBlocks),
           let blocks = try? JSONDecoder().decode([RichBlock].self, from: data), !blocks.isEmpty {
            if blocks.count == 1, let pasted = blocks[0].table {
                grid = pasted.rows.map { $0.cells.map { $0.isCovered ? [] : $0.inlines } }
            } else {
                grid = blocks.map { [$0.inlines] }
            }
        } else {
            switch ClipboardBlockImporter.read(pasteboard) {
            case .table(let pasted):
                grid = pasted.rows.map { $0.cells.map { $0.isCovered ? [] : $0.inlines } }
            case .blocks(let blocks):
                grid = blocks.map { [$0.inlines] }
            case .inline(let nodes):
                grid = [[nodes]]
            case .text(let text):
                grid = text.split(separator: "\n", omittingEmptySubsequences: false).map { [[.text(String($0))]] }
            case .none:
                return
            }
        }
        fill(grid, from: table.anchorAddress(of: rect.topLeft))
    }

    // MARK: Context menu

    private func menuContext(_ address: RichTableCellAddress) -> TableCellMenuContext {
        let cell = table.cell(at: address) ?? RichTableCell()
        let rect = coordinator.selection?.rect(in: table)
        let canMerge = (rect.map { !$0.isSingleCell } ?? false)
        return TableCellMenuContext(
            canMerge: canMerge,
            canUnmerge: cell.isSpanAnchor,
            canDeleteRow: table.rowCount > 1,
            canDeleteColumn: table.columnCount > 1,
            canSort: !table.hasVerticalSpanInBody,
            currentTone: cell.toneID,
            currentAlignment: alignment(address, cell: cell),
            currentVerticalAlignment: cell.verticalAlignment ?? .top
        )
    }

    private func nsMenu(for address: RichTableCellAddress) -> NSMenu? {
        let builder = TableCellNSMenuBuilder(context: menuContext(address)) { action in
            perform(action, at: address)
        }
        menuBuilders[address] = builder
        return builder.makeMenu()
    }

    private func perform(_ action: TableCellAction, at address: RichTableCellAddress) {
        let span = table.spanRect(ofAnchorAt: address)
        let targetRect: RichTableRect = {
            if let rect = coordinator.selection?.rect(in: table), rect.contains(address) { return rect }
            return RichTableRect(cell: address)
        }()
        switch action {
        case .insertRowAbove:
            insertRow(at: span.rows.lowerBound, focusColumn: address.column)
        case .insertRowBelow:
            insertRow(at: span.rows.upperBound + 1, focusColumn: address.column)
        case .insertColumnLeft:
            insertColumn(at: span.columns.lowerBound)
        case .insertColumnRight:
            insertColumn(at: span.columns.upperBound + 1)
        case .deleteRow:
            mutate("Delete Row") { try RichTableOperations.deleteRow(in: $0, at: address.row) }
            coordinator.blur()
        case .deleteColumn:
            mutate("Delete Column") { try RichTableOperations.deleteColumn(in: $0, at: address.column) }
            coordinator.blur()
        case .mergeCells:
            mergeSelection(fallbackAnchor: address)
        case .unmergeCell:
            unmerge(at: address)
        case .tone(let toneID):
            mutate("Cell Colour") { try RichTableOperations.setTone(in: $0, range: targetRect, toneID: toneID) }
        case .align(let alignment):
            if targetRect.isSingleCell {
                mutate("Align Column") { try RichTableOperations.setAlignment(in: $0, column: address.column, alignment: alignment) }
            } else {
                mutate("Align Cells") { try RichTableOperations.setAlignment(in: $0, range: targetRect, alignment: alignment) }
            }
        case .verticalAlign(let alignment):
            mutate("Vertical Alignment") { try RichTableOperations.setVerticalAlignment(in: $0, range: targetRect, alignment: alignment) }
        case .clearContents:
            mutate("Clear Cells") { try RichTableOperations.clearCells(in: $0, range: targetRect) }
        case .sortAscending:
            sort(column: address.column, ascending: true)
        case .sortDescending:
            sort(column: address.column, ascending: false)
        case .tableOptions:
            coordinator.showsOptions = true
        }
    }
}
