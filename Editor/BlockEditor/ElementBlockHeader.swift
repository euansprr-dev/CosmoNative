import SwiftUI

struct ElementBlockHeader: View {
    @Binding var title: String

    var isCollapsed: Bool
    var iconName: String
    var tone: NoteInkTone = NoteInkPalette.tone(nil)
    var darkMode: Bool = false
    /// Shown muted after the title while collapsed — how much is hiding.
    var collapsedChildCount: Int = 0
    var titleColor: Color = DS.documentText.opacity(0.92)
    var chevronColor: Color = DS.documentTextMuted
    var autoFocusTitle: Bool = false
    var onToggleCollapse: () -> Void
    var onSubmitTitle: () -> Void = {}
    var onTitleFocusChange: (Bool) -> Void = { _ in }

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(spacing: DS.space8) {
            collapseButton
            iconSeat
            titleField
            if isCollapsed, collapsedChildCount > 0 {
                Text("\(collapsedChildCount) block\(collapsedChildCount == 1 ? "" : "s")")
                    .font(DS.caption)
                    .monospacedDigit()
                    .foregroundStyle(chevronColor)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, DS.space10)
        .frame(minHeight: 30, alignment: .center)
    }

    private var collapseButton: some View {
        Button(action: onToggleCollapse) {
            Image(systemName: "chevron.right")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(chevronColor)
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .animation(ProMotionSprings.snappy, value: isCollapsed)
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Expand element" : "Collapse element")
        .accessibilityLabel(isCollapsed ? "Expand element" : "Collapse element")
    }

    /// The element's tone lives on a small tinted seat — color as identity,
    /// not decoration.
    private var iconSeat: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tone.wash(darkMode: darkMode))
            .frame(width: 20, height: 20)
            .overlay(
                Image(systemName: DocumentElementSymbol.validName(iconName))
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(tone.ink(darkMode: darkMode))
            )
            .accessibilityHidden(true)
    }

    private var titleField: some View {
        TextField("Untitled", text: $title)
            .textFieldStyle(.plain)
            .font(DS.callout.weight(.semibold))
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
