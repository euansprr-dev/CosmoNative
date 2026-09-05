import AppKit
import SwiftUI

/// The ONE live editor a table hosts — mounted only in the focused cell.
/// A `CosmoDocumentEditor` in table-cell mode holding a single paragraph:
/// Tab/Return/arrows at the edges leave the cell through boundary commands,
/// Shift+Return is a soft break, pastes that look tabular fill the grid.
struct TableCellEditor: View {
    let cellID: UUID
    @Binding var inlines: [RichInlineNode]
    var typography: TableCellTypography
    var isHeader: Bool
    var alignment: RichTableAlignment
    var allowMentions: Bool
    var editorTargetID: String?
    var caretRequest: EditorCaretRequest?
    var contextMenu: () -> NSMenu?
    var onBoundaryCommand: (EditorBoundaryCommand) -> Bool

    @State private var document: RichDocument
    @State private var lastEmitted: [RichInlineNode]

    init(
        cellID: UUID,
        inlines: Binding<[RichInlineNode]>,
        typography: TableCellTypography,
        isHeader: Bool,
        alignment: RichTableAlignment,
        allowMentions: Bool,
        editorTargetID: String?,
        caretRequest: EditorCaretRequest?,
        contextMenu: @escaping () -> NSMenu?,
        onBoundaryCommand: @escaping (EditorBoundaryCommand) -> Bool
    ) {
        self.cellID = cellID
        _inlines = inlines
        self.typography = typography
        self.isHeader = isHeader
        self.alignment = alignment
        self.allowMentions = allowMentions
        self.editorTargetID = editorTargetID
        self.caretRequest = caretRequest
        self.contextMenu = contextMenu
        self.onBoundaryCommand = onBoundaryCommand
        let initial = RichDocument(blocks: [RichBlock(kind: .paragraph, inlines: inlines.wrappedValue)])
        _document = State(initialValue: initial)
        _lastEmitted = State(initialValue: inlines.wrappedValue)
    }

    var body: some View {
        CosmoDocumentEditor(
            document: $document,
            fontSize: typography.fontSize,
            fontDesign: typography.fontDesign,
            lineSpacingAdjustment: typography.lineSpacingAdjustment,
            placeholder: "",
            darkMode: typography.darkMode,
            overrideTextColor: typography.overrideTextColor,
            allowSlashCommands: false,
            allowMentions: allowMentions,
            allowSelectionMenu: true,
            allowImages: false,
            baseFontWeight: isHeader ? typography.headerWeight : .regular,
            scrollsInternally: false,
            textAlignment: alignment.nsTextAlignment,
            editorTargetID: editorTargetID.map { "\($0):cell:\(cellID.uuidString)" },
            onDocumentChange: { updated, _ in
                let next = updated.blocks.first?.inlines ?? []
                guard next != lastEmitted else { return }
                lastEmitted = next
                inlines = next
            },
            onBoundaryCommand: onBoundaryCommand,
            tableCellMode: true,
            tableContextMenu: contextMenu,
            immediateDocumentSync: true,
            caretRequest: caretRequest,
            autoFocus: true
        )
        .padding(.horizontal, TableCellTypography.horizontalPadding)
        .padding(.vertical, TableCellTypography.verticalPadding)
        .onChange(of: inlines) { _, external in
            // A fill/sort/undo rewrote this cell while it is live: rebuild
            // the editor from the table, never the other way round.
            guard external != lastEmitted else { return }
            lastEmitted = external
            document = RichDocument(blocks: [RichBlock(kind: .paragraph, inlines: external)])
        }
    }
}
