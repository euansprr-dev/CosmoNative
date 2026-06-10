import SwiftUI

/// One "Turn into" choice in the block handle menu.
struct BlockTransformOption: Identifiable, Equatable {
    let kind: RichBlockKind
    let label: String
    let icon: String

    var id: String { kind.rawValue }

    static let all: [BlockTransformOption] = [
        BlockTransformOption(kind: .paragraph, label: "Text", icon: "text.alignleft"),
        BlockTransformOption(kind: .heading1, label: "Heading 1", icon: "textformat.size.larger"),
        BlockTransformOption(kind: .heading2, label: "Heading 2", icon: "textformat.size"),
        BlockTransformOption(kind: .heading3, label: "Heading 3", icon: "textformat.size.smaller"),
        BlockTransformOption(kind: .bulletList, label: "Bulleted list", icon: "list.bullet"),
        BlockTransformOption(kind: .numberedList, label: "Numbered list", icon: "list.number"),
        BlockTransformOption(kind: .checklist, label: "To-do list", icon: "checklist"),
        BlockTransformOption(kind: .quote, label: "Quote", icon: "text.quote")
    ]
}

/// The menu behind the six-dot block handle — turn into, duplicate, delete.
/// Acts on the whole block selection when more than one block is selected.
/// Rendered inside a native popover (already Liquid Glass), so inner elements
/// use flat warm fills per the design system — never more glass.
struct BlockHandleMenuView: View {
    /// Shared kind of the targeted blocks; nil when the selection is mixed.
    var currentKind: RichBlockKind?
    var selectionCount: Int = 1
    var onTransform: (RichBlockKind) -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hoveredID: String?
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel
            ForEach(Array(BlockTransformOption.all.enumerated()), id: \.element.id) { index, option in
                transformRow(option, index: index)
            }
            menuDivider
            actionRows
        }
        .padding(.vertical, DS.space6)
        .frame(width: 236)
        .onAppear {
            withAnimation(ProMotionSprings.menuAppear) { appeared = true }
        }
    }

    private var sectionLabel: some View {
        Text(selectionCount > 1 ? "TURN \(selectionCount) BLOCKS INTO" : "TURN INTO")
            .font(DS.caption2.weight(.semibold))
            .tracking(0.8)
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

    private var actionRows: some View {
        let base = BlockTransformOption.all.count
        return VStack(alignment: .leading, spacing: 0) {
            menuRow(
                id: "duplicate", icon: "plus.square.on.square", label: "Duplicate",
                trailing: .shortcut("⌘D"), isDestructive: false, index: base
            ) { onDuplicate() }
            menuRow(
                id: "delete", icon: "trash", label: "Delete",
                trailing: .shortcut("⌫"), isDestructive: true, index: base + 1
            ) { onDelete() }
        }
    }

    private func transformRow(_ option: BlockTransformOption, index: Int) -> some View {
        menuRow(
            id: option.id,
            icon: option.icon,
            label: option.label,
            trailing: currentKind == option.kind ? .checkmark : .none,
            isDestructive: false,
            index: index
        ) { onTransform(option.kind) }
    }

    private enum RowTrailing {
        case none
        case checkmark
        case shortcut(String)
    }

    private func menuRow(
        id: String,
        icon: String,
        label: String,
        trailing: RowTrailing,
        isDestructive: Bool,
        index: Int,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredID == id
        let tint: Color = isDestructive ? DS.red : DS.text

        return Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 0) {
                Image(systemName: icon)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(isHovered ? tint : tint.opacity(0.6))
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(label)
                    .font(DS.callout.weight(isHovered ? .medium : .regular))
                    .foregroundStyle(isDestructive ? DS.red : DS.text)
                    .padding(.leading, DS.space10)

                Spacer(minLength: 0)

                rowTrailingView(trailing)
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? (isDestructive ? DS.red.opacity(0.10) : DS.glassInputFillFocused) : Color.clear)
                    .padding(.horizontal, DS.space6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                hoveredID = hovering ? id : nil
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 4)
        .animation(ProMotionSprings.cascade(index: index), value: appeared)
    }

    @ViewBuilder
    private func rowTrailingView(_ trailing: RowTrailing) -> some View {
        switch trailing {
        case .none:
            EmptyView()
        case .checkmark:
            Image(systemName: "checkmark")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityLabel("Current type")
        case .shortcut(let hint):
            Text(hint)
                .font(DS.caption)
                .foregroundStyle(DS.text.opacity(0.45))
                .padding(.trailing, 2)
        }
    }
}
