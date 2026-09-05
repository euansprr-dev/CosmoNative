import AppKit
import SwiftUI

/// The actions a right-click on a cell offers. One list, two renderings:
/// SwiftUI `.contextMenu` for static cells, an `NSMenu` for the live cell
/// (the NSTextView owns its own right-click).
enum TableCellAction: Hashable {
    case insertRowAbove
    case insertRowBelow
    case insertColumnLeft
    case insertColumnRight
    case deleteRow
    case deleteColumn
    case mergeCells
    case unmergeCell
    case tone(String?)
    case align(RichTableAlignment)
    case verticalAlign(RichTableVerticalAlignment)
    case clearContents
    case sortAscending
    case sortDescending
    case tableOptions

    var title: String {
        switch self {
        case .insertRowAbove: return "Insert row above"
        case .insertRowBelow: return "Insert row below"
        case .insertColumnLeft: return "Insert column left"
        case .insertColumnRight: return "Insert column right"
        case .deleteRow: return "Delete row"
        case .deleteColumn: return "Delete column"
        case .mergeCells: return "Merge cells"
        case .unmergeCell: return "Unmerge cells"
        case .tone(let id):
            guard let id else { return "None" }
            return NoteInkPalette.tone(id).label
        case .align(let alignment):
            switch alignment {
            case .leading: return "Left"
            case .center: return "Center"
            case .trailing: return "Right"
            }
        case .verticalAlign(let alignment):
            switch alignment {
            case .top: return "Top"
            case .middle: return "Middle"
            case .bottom: return "Bottom"
            }
        case .clearContents: return "Clear contents"
        case .sortAscending: return "Sort ascending"
        case .sortDescending: return "Sort descending"
        case .tableOptions: return "Table options…"
        }
    }

    var systemImage: String {
        switch self {
        case .insertRowAbove: return "arrow.up.to.line"
        case .insertRowBelow: return "arrow.down.to.line"
        case .insertColumnLeft: return "arrow.left.to.line"
        case .insertColumnRight: return "arrow.right.to.line"
        case .deleteRow, .deleteColumn: return "trash"
        case .mergeCells: return "rectangle.2.swap"
        case .unmergeCell: return "rectangle.split.2x1"
        case .tone: return "paintpalette"
        case .align(.leading): return "text.alignleft"
        case .align(.center): return "text.aligncenter"
        case .align(.trailing): return "text.alignright"
        case .verticalAlign: return "arrow.up.and.down"
        case .clearContents: return "eraser"
        case .sortAscending: return "arrow.up.arrow.down"
        case .sortDescending: return "arrow.down.arrow.up"
        case .tableOptions: return "tablecells"
        }
    }

    var shortcutHint: String? {
        switch self {
        case .insertRowBelow: return "⌘⏎"
        case .mergeCells: return "⇧⌘M"
        case .unmergeCell: return "⇧⌘U"
        case .tableOptions: return "⌥⌘T"
        default: return nil
        }
    }
}

/// What the menu should offer for the clicked cell.
struct TableCellMenuContext {
    var canMerge: Bool
    var canUnmerge: Bool
    var canDeleteRow: Bool
    var canDeleteColumn: Bool
    var canSort: Bool
    var currentTone: String?
    var currentAlignment: RichTableAlignment
    var currentVerticalAlignment: RichTableVerticalAlignment
}

/// SwiftUI rendering — attach with `.contextMenu { TableCellContextMenu(...) }`.
struct TableCellContextMenu: View {
    var context: TableCellMenuContext
    var perform: (TableCellAction) -> Void

    var body: some View {
        Group {
            row(.insertRowAbove)
            row(.insertRowBelow)
            row(.insertColumnLeft)
            row(.insertColumnRight)
            Divider()
            if context.canMerge { row(.mergeCells) }
            if context.canUnmerge { row(.unmergeCell) }
            Menu("Cell colour") {
                ForEach(NoteInkPalette.tones) { tone in
                    toneRow(tone.id, label: tone.label)
                }
                Divider()
                toneRow(nil, label: "None")
            }
            Menu("Align") {
                ForEach(RichTableAlignment.allCases, id: \.self) { alignment in
                    checkRow(.align(alignment), checked: context.currentAlignment == alignment)
                }
                Divider()
                ForEach(RichTableVerticalAlignment.allCases, id: \.self) { alignment in
                    checkRow(.verticalAlign(alignment), checked: context.currentVerticalAlignment == alignment)
                }
            }
            if context.canSort {
                Menu("Sort") {
                    row(.sortAscending)
                    row(.sortDescending)
                }
            }
            row(.clearContents)
            Divider()
            row(.deleteRow).disabled(!context.canDeleteRow)
            row(.deleteColumn).disabled(!context.canDeleteColumn)
            Divider()
            row(.tableOptions)
        }
    }

    private func row(_ action: TableCellAction) -> some View {
        Button { perform(action) } label: {
            Label(action.title, systemImage: action.systemImage)
        }
    }

    private func checkRow(_ action: TableCellAction, checked: Bool) -> some View {
        Button { perform(action) } label: {
            if checked {
                Label(action.title, systemImage: "checkmark")
            } else {
                Text(action.title)
            }
        }
    }

    private func toneRow(_ id: String?, label: String) -> some View {
        Button { perform(.tone(id)) } label: {
            if context.currentTone == id {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }
}

/// AppKit rendering for the live cell's NSTextView menu.
@MainActor
final class TableCellNSMenuBuilder: NSObject {
    private let perform: (TableCellAction) -> Void
    private let context: TableCellMenuContext

    init(context: TableCellMenuContext, perform: @escaping (TableCellAction) -> Void) {
        self.context = context
        self.perform = perform
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Table")
        menu.autoenablesItems = false
        add(.insertRowAbove, to: menu)
        add(.insertRowBelow, to: menu)
        add(.insertColumnLeft, to: menu)
        add(.insertColumnRight, to: menu)
        menu.addItem(.separator())
        if context.canMerge { add(.mergeCells, to: menu) }
        if context.canUnmerge { add(.unmergeCell, to: menu) }
        let tone = NSMenuItem(title: "Cell colour", action: nil, keyEquivalent: "")
        let toneMenu = NSMenu(title: "Cell colour")
        for option in NoteInkPalette.tones {
            add(.tone(option.id), to: toneMenu, checked: context.currentTone == option.id)
        }
        toneMenu.addItem(.separator())
        add(.tone(nil), to: toneMenu, checked: context.currentTone == nil)
        tone.submenu = toneMenu
        menu.addItem(tone)
        let align = NSMenuItem(title: "Align", action: nil, keyEquivalent: "")
        let alignMenu = NSMenu(title: "Align")
        for option in RichTableAlignment.allCases {
            add(.align(option), to: alignMenu, checked: context.currentAlignment == option)
        }
        alignMenu.addItem(.separator())
        for option in RichTableVerticalAlignment.allCases {
            add(.verticalAlign(option), to: alignMenu, checked: context.currentVerticalAlignment == option)
        }
        align.submenu = alignMenu
        menu.addItem(align)
        if context.canSort {
            let sort = NSMenuItem(title: "Sort", action: nil, keyEquivalent: "")
            let sortMenu = NSMenu(title: "Sort")
            add(.sortAscending, to: sortMenu)
            add(.sortDescending, to: sortMenu)
            sort.submenu = sortMenu
            menu.addItem(sort)
        }
        add(.clearContents, to: menu)
        menu.addItem(.separator())
        add(.deleteRow, to: menu, enabled: context.canDeleteRow)
        add(.deleteColumn, to: menu, enabled: context.canDeleteColumn)
        menu.addItem(.separator())
        add(.tableOptions, to: menu)
        return menu
    }

    private func add(_ action: TableCellAction, to menu: NSMenu, checked: Bool = false, enabled: Bool = true) {
        let item = NSMenuItem(title: action.title, action: #selector(handle(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = TableCellActionBox(action: action)
        item.image = NSImage(systemSymbolName: action.systemImage, accessibilityDescription: nil)
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        menu.addItem(item)
    }

    @objc private func handle(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? TableCellActionBox else { return }
        perform(box.action)
    }
}

final class TableCellActionBox: NSObject {
    let action: TableCellAction
    init(action: TableCellAction) { self.action = action }
}
