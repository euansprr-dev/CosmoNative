import AppKit
import Foundation
import SwiftUI

/// Per-table focus, selection and chrome state. One instance per mounted
/// table block; the block list's `BlockFocusCoordinator` still owns
/// block-level focus (the table registers as ONE navigation stop) and this
/// coordinator owns everything inside the grid.
///
/// The one-live-editor rule: exactly one cell — `focusedCell` — hosts a
/// real text editor; every other cell is the serializer's static output.
@Observable
@MainActor
final class TableFocusCoordinator {
    /// The cell whose editor is mounted (an anchor address).
    var focusedCell: RichTableCellAddress?
    /// Range / row / column / whole-table selection (nil = caret only).
    var selection: RichTableSelection?
    /// The selection's anchor for ⇧-extension and drag ranges.
    var selectionAnchor: RichTableCellAddress?
    /// One-shot caret placement for the editor that mounts next.
    var pendingCaret: EditorCaretRequest?
    /// Hover state for handles — written by pointer crossings only.
    var hoveredRow: Int?
    var hoveredColumn: Int?
    /// Live drag of a row/column handle.
    var drag: TableDragState?
    /// Live column-divider resize.
    var dividerDrag: TableDividerDrag?
    /// Live corner-grabber resize (target rows/columns).
    var cornerDrag: (rows: Int, columns: Int)?
    /// Whether the options popover is presented.
    var showsOptions = false
    /// ⌘A escalation rung: text → all cells → block.
    var selectAllRung = 0

    @ObservationIgnored private var caretToken = 0

    struct TableDragState: Equatable {
        enum Axis { case row, column }
        var axis: Axis
        var source: Int
        /// Insertion index in the original numbering (0…count).
        var target: Int
    }

    struct TableDividerDrag: Equatable {
        var leftColumn: Int
        var startX: CGFloat
    }

    init() {}

    // MARK: Focus

    func focus(_ address: RichTableCellAddress, caretOffsetFromEnd: Int = 0, windowPoint: CGPoint? = nil) {
        caretToken += 1
        pendingCaret = EditorCaretRequest(
            utf16OffsetFromEnd: caretOffsetFromEnd,
            token: caretToken,
            windowPoint: windowPoint
        )
        selection = nil
        selectionAnchor = address
        selectAllRung = 0
        if focusedCell != address {
            focusedCell = address
        }
    }

    func blur() {
        if focusedCell != nil { focusedCell = nil }
        pendingCaret = nil
        selectAllRung = 0
    }

    func clearSelection() {
        if selection != nil { selection = nil }
        selectAllRung = 0
    }

    /// Extends (⇧-click / ⇧-arrow / drag) from the anchor to `address`.
    func extendSelection(to address: RichTableCellAddress) {
        let anchor = selectionAnchor ?? focusedCell ?? address
        selectionAnchor = anchor
        let rect = RichTableRect(anchor, address)
        selection = .range(rect)
    }

    func select(_ selection: RichTableSelection) {
        self.selection = selection
        if focusedCell != nil { focusedCell = nil }
    }

    var hasRangeSelection: Bool {
        if case .cell = selection { return false }
        return selection != nil
    }
}
