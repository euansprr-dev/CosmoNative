import SwiftUI

/// Which rule edges a cell draws. Interior rules are owned by the cell on
/// their top-left side: every cell draws its RIGHT and BOTTOM edges (when it
/// has a neighbour there), the table frame draws the outer border. One line
/// per boundary, no seams, spans follow for free.
struct TableCellRules: Equatable {
    var right: Bool
    var bottom: Bool
    /// The header's closing rule in the `clean` style — gilt, not grey.
    var bottomIsHeaderRule: Bool
}

/// The chrome around one cell: wash, zebra, rules, selection. The content
/// (static text or the live editor) is injected so this stays a pure
/// presentation shell.
struct TableCellFrame<Content: View>: View {
    var background: Color?
    var rules: TableCellRules
    var isSelected: Bool
    var isFocused: Bool
    var darkMode: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(backgroundFill)
            .overlay(alignment: .trailing) {
                if rules.right {
                    Rectangle()
                        .fill(DS.documentBorderSubtle)
                        .frame(width: 0.5)
                }
            }
            .overlay(alignment: .bottom) {
                if rules.bottom {
                    Rectangle()
                        .fill(rules.bottomIsHeaderRule ? headerRuleColor : DS.documentBorderSubtle)
                        .frame(height: rules.bottomIsHeaderRule ? 1 : 0.5)
                }
            }
            .overlay {
                if isSelected {
                    Rectangle()
                        .fill(DS.accentSoft.opacity(0.55))
                        .allowsHitTesting(false)
                }
            }
    }

    private var backgroundFill: some View {
        Rectangle().fill(background ?? .clear)
    }

    private var headerRuleColor: Color {
        NoteInkPalette.tone("gilt").hairline(darkMode: darkMode)
    }
}
