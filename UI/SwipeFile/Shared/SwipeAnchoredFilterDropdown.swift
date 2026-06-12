import SwiftUI

/// Tracks the Filters button frame so the dropdown can anchor beneath it.
struct SwipeFilterAnchorKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// The anchored dropdown shell shared by the library and Discover filter panels —
/// the one filter affordance per page. Scrim-tap and Esc dismiss; the panel scales
/// in from the button's corner.
struct SwipeAnchoredFilterDropdown<Panel: View>: View {
    let anchor: CGRect
    var panelWidth: CGFloat = 360
    let onDismiss: () -> Void
    @ViewBuilder let panel: (CGFloat) -> Panel

    var body: some View {
        GeometryReader { proxy in
            let topInset = anchor.maxY + 8
            let panelHeight = min(620, max(280, proxy.size.height - topInset - 24))
            let leadingX = min(
                max(16, anchor.maxX - panelWidth),
                max(16, proxy.size.width - panelWidth - 16)
            )

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                panel(panelHeight)
                    .frame(width: panelWidth)
                    .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)
                    .offset(x: leadingX, y: topInset)
                    .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .onExitCommand(perform: onDismiss)
    }
}
