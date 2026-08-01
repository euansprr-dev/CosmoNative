import SwiftUI

/// Chrome for a toggle block — the Craft model: a rotating chevron, an
/// inline rich-text header (injected by `BlockListView` as a normal text
/// row), and indented children that collapse behind the header. No card, no
/// wash: a toggle is structure, not decoration.
struct ToggleBlockRowView<Header: View, Children: View>: View {
    var isCollapsed: Bool
    var hasChildren: Bool
    var darkMode: Bool = false
    var onToggleCollapse: () -> Void
    var onAddFirstChild: () -> Void
    @ViewBuilder var header: Header
    @ViewBuilder var children: Children

    @State private var chevronHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var childIndent: CGFloat { 22 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.space4) {
                chevron
                header
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if !isCollapsed {
                childArea
                    .padding(.leading, Self.childIndent)
                    .padding(.top, DS.space2)
            }
        }
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: isCollapsed)
    }

    private var chevron: some View {
        Button(action: onToggleCollapse) {
            Image(systemName: "chevron.right")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(chevronColor)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .frame(width: 18, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 1)
        .onHover { chevronHovered = $0 }
        .help(isCollapsed ? "Expand" : "Collapse")
        .accessibilityLabel(isCollapsed ? "Expand toggle" : "Collapse toggle")
    }

    @ViewBuilder
    private var childArea: some View {
        if hasChildren {
            children
        } else {
            Button(action: onAddFirstChild) {
                Text("Empty — press Return on the header, or click to add")
                    .font(DS.subheadline)
                    .foregroundStyle(mutedColor)
                    .padding(.vertical, DS.space2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add content to toggle")
        }
    }

    private var chevronColor: Color {
        if chevronHovered {
            return darkMode ? DS.focusImmersiveTextSecondary : DS.documentTextSecondary
        }
        return darkMode ? DS.focusImmersiveTextMuted : DS.documentTextMuted
    }

    private var mutedColor: Color {
        darkMode ? DS.focusImmersiveTextMuted : DS.documentTextMuted
    }
}
