import SwiftUI

/// One "Turn into" choice in the block handle menu.
struct BlockTransformOption: Identifiable, Equatable {
    let kind: RichBlockKind
    let label: String
    let icon: String
    /// Key equivalent taught in place (trailing hint) — wired in
    /// `CosmoTextView.performKeyEquivalent` → `.blockShortcut`.
    var shortcutHint: String? = nil

    var id: String { kind.rawValue }

    static let all: [BlockTransformOption] = [
        BlockTransformOption(kind: .paragraph, label: "Text", icon: "text.alignleft"),
        BlockTransformOption(kind: .heading1, label: "Heading 1", icon: "textformat.size.larger", shortcutHint: "⌥⌘1"),
        BlockTransformOption(kind: .heading2, label: "Heading 2", icon: "textformat.size", shortcutHint: "⌥⌘2"),
        BlockTransformOption(kind: .heading3, label: "Heading 3", icon: "textformat.size.smaller", shortcutHint: "⌥⌘3"),
        BlockTransformOption(kind: .bulletList, label: "Bulleted list", icon: "list.bullet"),
        BlockTransformOption(kind: .numberedList, label: "Numbered list", icon: "list.number"),
        BlockTransformOption(kind: .checklist, label: "To-do list", icon: "checklist", shortcutHint: "⇧⌘L"),
        BlockTransformOption(kind: .quote, label: "Quote", icon: "text.quote"),
        BlockTransformOption(kind: .callout, label: "Callout", icon: "exclamationmark.bubble"),
        BlockTransformOption(kind: .toggle, label: "Toggle", icon: "chevron.forward.square"),
        BlockTransformOption(kind: .section, label: "Section", icon: "square.text.square"),
        BlockTransformOption(kind: .code, label: "Code", icon: "curlybraces")
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
    /// Sections only: hoist the children, drop the box. nil hides the row.
    var onUngroup: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        // Sentence-case source + smallCaps() — .smallCaps() on an UPPERCASE
        // string is a no-op; ONE small-caps dialect app-wide.
        Text(selectionCount > 1 ? "Turn \(selectionCount) blocks into" : "Turn into")
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

    private var actionRows: some View {
        let base = BlockTransformOption.all.count
        return VStack(alignment: .leading, spacing: 0) {
            if let onUngroup, currentKind == .section {
                menuRow(
                    id: "ungroup", icon: "square.dashed", label: "Ungroup",
                    trailing: .none, isDestructive: false, index: base
                ) { onUngroup() }
            }
            menuRow(
                id: "duplicate", icon: "plus.square.on.square", label: "Duplicate",
                trailing: .shortcut("⌘D"), isDestructive: false, index: base + 1
            ) { onDuplicate() }
            menuRow(
                id: "delete", icon: "trash", label: "Delete",
                trailing: .shortcut("⌫"), isDestructive: true, index: base + 2
            ) { onDelete() }
        }
    }

    private func transformRow(_ option: BlockTransformOption, index: Int) -> some View {
        let trailing: RowTrailing
        if currentKind == option.kind {
            trailing = .checkmark
        } else if let hint = option.shortcutHint {
            trailing = .shortcut(hint)
        } else {
            trailing = .none
        }
        return menuRow(
            id: option.id,
            icon: option.icon,
            label: option.label,
            trailing: trailing,
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

                // Constant weight — a row must not re-typeset under the
                // pointer; hover speaks through the wash alone.
                Text(label)
                    .font(DS.callout)
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
        // Cascade caps at ~8 (peakui) and gates on Reduce Motion.
        .animation(reduceMotion ? nil : ProMotionSprings.cascade(index: min(index, 8)), value: appeared)
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
            // ONE keycap dialect app-wide; keycap ink = SECONDARY (an opacity
            // on the ink ladder broke AA on the Today pass).
            Text(hint)
                .font(DS.keycap)
                .foregroundStyle(DS.textSecondary)
                .padding(.trailing, 2)
        }
    }
}
