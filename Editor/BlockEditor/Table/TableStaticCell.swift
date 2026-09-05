import AppKit
import SwiftUI

/// The note's typography as it applies inside a table cell. Static cells and
/// the live cell editor both derive their text from `RichDocumentSerializer`
/// through this one struct, so what a cell shows at rest is exactly what
/// it shows while editing (the hydration-is-a-render-path law).
struct TableCellTypography: Equatable {
    var fontSize: CGFloat
    var fontDesign: NSFontDescriptor.SystemDesign
    var lineSpacingAdjustment: CGFloat
    var darkMode: Bool
    var overrideTextColor: NSColor?

    /// Header cells (header row / header column) speak semibold.
    var headerWeight: NSFont.Weight { .semibold }

    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 6

    func baseFont(isHeader: Bool) -> NSFont {
        EditorFontPolicy.font(ofSize: fontSize, weight: isHeader ? headerWeight : .regular, design: fontDesign)
    }

    /// One line of the cell font — the row floor.
    var lineHeight: CGFloat {
        let font = baseFont(isHeader: false)
        return ceil(NSLayoutManager().defaultLineHeight(for: font) + 6 + lineSpacingAdjustment)
    }

    func attributedString(
        for inlines: [RichInlineNode],
        isHeader: Bool,
        alignment: RichTableAlignment
    ) -> NSAttributedString {
        let block = RichBlock(kind: .paragraph, inlines: inlines)
        var attributed = RichDocumentSerializer.attributedString(
            from: RichDocument(blocks: [block]),
            fontSize: fontSize,
            darkMode: darkMode,
            baseFontWeight: isHeader ? headerWeight : .regular
        )
        attributed = EditorFontPolicy.applyingDesign(fontDesign, to: attributed)
        attributed = EditorRhythmPolicy.applyingLineSpacing(lineSpacingAdjustment, to: attributed)
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: mutable.length)
        if let overrideTextColor {
            mutable.enumerateAttribute(RichDocumentAttributeKeys.inkID, in: fullRange, options: []) { ink, range, _ in
                guard ink == nil else { return }
                mutable.enumerateAttribute(RichDocumentAttributeKeys.entityType, in: range, options: []) { entity, subrange, _ in
                    guard entity == nil else { return }
                    mutable.addAttribute(.foregroundColor, value: overrideTextColor, range: subrange)
                }
            }
        }
        mutable.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.alignment = alignment.nsTextAlignment
            mutable.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return mutable
    }
}

extension RichTableAlignment {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }

    var swiftUIAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var frameAlignment: Alignment { swiftUIAlignment }
}

/// A cell at rest: the serializer's attributed text, nothing live. Equatable
/// so an idle cell never re-renders while a neighbour is being typed in.
struct TableStaticCell: View, Equatable {
    var inlines: [RichInlineNode]
    var typography: TableCellTypography
    var isHeader: Bool
    var alignment: RichTableAlignment
    var verticalAlignment: RichTableVerticalAlignment

    static func == (lhs: TableStaticCell, rhs: TableStaticCell) -> Bool {
        lhs.inlines == rhs.inlines
            && lhs.typography == rhs.typography
            && lhs.isHeader == rhs.isHeader
            && lhs.alignment == rhs.alignment
            && lhs.verticalAlignment == rhs.verticalAlignment
    }

    private var attributed: AttributedString {
        let source = typography.attributedString(for: inlines, isHeader: isHeader, alignment: alignment)
        if source.length == 0 {
            // A zero-width placeholder keeps the row one line tall.
            return AttributedString(" ", attributes: AttributeContainer().font(Font(typography.baseFont(isHeader: isHeader))))
        }
        return (try? AttributedString(source, including: \.appKit)) ?? AttributedString(source.string)
    }

    var body: some View {
        Text(attributed)
            .lineSpacing(0)
            .multilineTextAlignment(alignment.textAlignment)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cellAlignment)
            .padding(.horizontal, TableCellTypography.horizontalPadding)
            .padding(.vertical, TableCellTypography.verticalPadding)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cellAlignment: Alignment {
        switch (verticalAlignment, alignment) {
        case (.top, .leading): return .topLeading
        case (.top, .center): return .top
        case (.top, .trailing): return .topTrailing
        case (.middle, .leading): return .leading
        case (.middle, .center): return .center
        case (.middle, .trailing): return .trailing
        case (.bottom, .leading): return .bottomLeading
        case (.bottom, .center): return .bottom
        case (.bottom, .trailing): return .bottomTrailing
        }
    }
}

extension RichTableAlignment {
    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
