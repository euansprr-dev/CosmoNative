import SwiftUI

/// The table's settings — presented as a native popover (already glass), so
/// rows are flat warm fills, one small-caps section voice, keycap hints.
struct TableOptionsPopover: View {
    var table: RichTable
    var darkMode: Bool
    var onToggleHeaderRow: () -> Void
    var onToggleHeaderColumn: () -> Void
    var onToggleStriped: () -> Void
    var onSetStyle: (RichTableStyle) -> Void
    var onDistribute: () -> Void
    var onSort: (Int, Bool) -> Void
    var onTranspose: () -> Void
    var onConvertToText: () -> Void
    var onCopy: (TableCopyFormat) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hoveredID: String?

    enum TableCopyFormat: String, CaseIterable, Identifiable {
        case tsv = "Tab-separated"
        case markdown = "Markdown"
        case html = "HTML"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Layout")
            toggleRow(id: "header-row", icon: "tablecells.fill", label: "Header row", isOn: table.hasHeaderRow, action: onToggleHeaderRow)
            toggleRow(id: "header-column", icon: "rectangle.lefthalf.filled", label: "Header column", isOn: table.hasHeaderColumn, action: onToggleHeaderColumn)
            toggleRow(id: "striped", icon: "rectangle.split.3x1", label: "Striped rows", isOn: table.isStriped, action: onToggleStriped)
            styleRow
            menuDivider
            sectionLabel("Arrange")
            actionRow(id: "distribute", icon: "arrow.left.and.right", label: "Distribute columns", action: onDistribute)
            sortRow
            actionRow(id: "transpose", icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Transpose", action: onTranspose)
                .disabled(table.hasAnySpan)
                .help(table.hasAnySpan ? "Unmerge cells to transpose" : "Swap rows and columns")
            menuDivider
            actionRow(id: "convert", icon: "text.alignleft", label: "Convert to text", action: onConvertToText)
            copyRow
            menuDivider
            actionRow(id: "delete", icon: "trash", label: "Delete table", shortcut: "⌫", isDestructive: true, action: onDelete)
        }
        .padding(.vertical, DS.space6)
        .frame(width: 248)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.smallCaps)
            .tracking(DS.smallCapsTracking)
            .foregroundStyle(DS.textMuted)
            .padding(.horizontal, DS.space12)
            .padding(.top, DS.space6)
            .padding(.bottom, DS.space4)
    }

    private var menuDivider: some View {
        Divider()
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space4)
    }

    private var styleRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "square.grid.3x3")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.text.opacity(0.6))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text("Style")
                .font(DS.callout)
                .foregroundStyle(DS.text)
            Spacer(minLength: DS.space8)
            CosmoSegmentedSwitcher(
                options: RichTableStyle.allCases,
                label: { style in
                    switch style {
                    case .grid: return "Grid"
                    case .lines: return "Lines"
                    case .clean: return "Clean"
                    }
                },
                help: { style in
                    switch style {
                    case .grid: return "Every rule"
                    case .lines: return "Horizontal rules only"
                    case .clean: return "No rules, one under the header"
                    }
                },
                chrome: .bare,
                selection: Binding(get: { table.style }, set: { onSetStyle($0) })
            )
        }
        .padding(.horizontal, DS.space12)
        .frame(minHeight: 30)
    }

    private var sortRow: some View {
        Menu {
            ForEach(Array(table.columns.indices), id: \.self) { column in
                let title = columnTitle(column)
                Button("\(title) — ascending") { onSort(column, true); dismiss() }
                Button("\(title) — descending") { onSort(column, false); dismiss() }
            }
        } label: {
            rowLabel(icon: "arrow.up.arrow.down", label: "Sort by column", trailing: nil, isDestructive: false, isHovered: hoveredID == "sort")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(table.hasVerticalSpanInBody)
        .help(table.hasVerticalSpanInBody ? "Unmerge cells to sort" : "Sort rows (the header stays)")
        .onHover { hoveredID = $0 ? "sort" : (hoveredID == "sort" ? nil : hoveredID) }
        .padding(.horizontal, DS.space6)
    }

    private var copyRow: some View {
        Menu {
            ForEach(TableCopyFormat.allCases) { format in
                Button(format.rawValue) { onCopy(format); dismiss() }
            }
        } label: {
            rowLabel(icon: "doc.on.doc", label: "Copy as", trailing: nil, isDestructive: false, isHovered: hoveredID == "copy")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hoveredID = $0 ? "copy" : (hoveredID == "copy" ? nil : hoveredID) }
        .padding(.horizontal, DS.space6)
    }

    private func columnTitle(_ column: Int) -> String {
        if table.hasHeaderRow, let cell = table.cell(at: RichTableCellAddress(row: 0, column: column)) {
            let text = cell.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(24)) }
        }
        return "Column \(column + 1)"
    }

    private func toggleRow(id: String, icon: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(icon: icon, label: label, trailing: isOn ? "checkmark" : nil, isDestructive: false, isHovered: hoveredID == id)
        }
        .buttonStyle(.plain)
        .onHover { hoveredID = $0 ? id : (hoveredID == id ? nil : hoveredID) }
        .padding(.horizontal, DS.space6)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func actionRow(id: String, icon: String, label: String, shortcut: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            rowLabel(icon: icon, label: label, trailing: nil, shortcut: shortcut, isDestructive: isDestructive, isHovered: hoveredID == id)
        }
        .buttonStyle(.plain)
        .onHover { hoveredID = $0 ? id : (hoveredID == id ? nil : hoveredID) }
        .padding(.horizontal, DS.space6)
    }

    private func rowLabel(icon: String, label: String, trailing: String?, shortcut: String? = nil, isDestructive: Bool, isHovered: Bool) -> some View {
        let tint: Color = isDestructive ? DS.red : DS.text
        return HStack(spacing: DS.space8) {
            Image(systemName: icon)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(isHovered ? tint : tint.opacity(0.6))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(label)
                .font(DS.callout)
                .foregroundStyle(tint)
            Spacer(minLength: DS.space8)
            if let trailing {
                Image(systemName: trailing)
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.accent)
            } else if let shortcut {
                Text(shortcut)
                    .font(DS.keycap)
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(.horizontal, DS.space6)
        .frame(minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? DS.glassSectionFill : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
