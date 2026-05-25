import SwiftUI

struct ElementBlockHeader: View {
    @Binding var title: String

    var isCollapsed: Bool
    var iconName: String
    var titleColor: Color = DS.documentText.opacity(0.92)
    var iconColor: Color = DS.documentTextSecondary
    var chevronColor: Color = DS.documentTextMuted
    var autoFocusTitle: Bool = false
    var onToggleCollapse: () -> Void
    var onSubmitTitle: () -> Void = {}
    var onTitleFocusChange: (Bool) -> Void = { _ in }

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(spacing: DS.space8) {
            collapseButton
            elementIcon
            titleField
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .frame(minHeight: 38, alignment: .center)
    }

    private var collapseButton: some View {
        Button(action: onToggleCollapse) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(chevronColor)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .animation(ProMotionSprings.snappy, value: isCollapsed)
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Expand element" : "Collapse element")
        .accessibilityLabel(isCollapsed ? "Expand element" : "Collapse element")
    }

    private var elementIcon: some View {
        Image(systemName: DocumentElementSymbol.validName(iconName))
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(iconColor)
            .frame(width: 16, height: 18)
            .accessibilityHidden(true)
    }

    private var titleField: some View {
        TextField("Untitled", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(titleColor)
            .lineLimit(1)
            .onSubmit(onSubmitTitle)
            .focused($isTitleFocused)
            .onChange(of: isTitleFocused) { _, isFocused in
                onTitleFocusChange(isFocused)
            }
            .onAppear {
                if autoFocusTitle {
                    isTitleFocused = true
                }
            }
            .onChange(of: autoFocusTitle) { _, shouldFocus in
                if shouldFocus {
                    isTitleFocused = true
                }
            }
            .frame(height: 22, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
