import AppKit
import SwiftUI

struct TitleEditorConfiguration: Equatable, Sendable {
    let previewLineLimit: Int
    let editingLineLimit: Int
    let commitsOnReturn: Bool

    init(
        previewLineLimit: Int,
        editingLineLimit: Int,
        commitsOnReturn: Bool = true
    ) {
        self.previewLineLimit = previewLineLimit
        self.editingLineLimit = editingLineLimit
        self.commitsOnReturn = commitsOnReturn
    }
}

enum SharedTitleSurfaceStyle {
    case noteCanvas
    case noteFocus
    case connectionCanvas
    case connectionFocus

    var fontSize: CGFloat {
        switch self {
        case .noteCanvas:
            return 28
        case .noteFocus:
            return 32
        case .connectionCanvas:
            return 22
        case .connectionFocus:
            return 28
        }
    }

    var baseFontWeight: NSFont.Weight {
        switch self {
        case .noteCanvas, .connectionCanvas, .connectionFocus:
            return .semibold
        case .noteFocus:
            return .bold
        }
    }

    var compact: Bool {
        switch self {
        case .noteCanvas, .connectionCanvas, .connectionFocus:
            return true
        case .noteFocus:
            return false
        }
    }

    var previewLineLimit: Int {
        switch self {
        case .noteCanvas:
            return 2
        case .noteFocus:
            return 3
        case .connectionCanvas, .connectionFocus:
            return 2
        }
    }

    var editingLineLimit: Int {
        switch self {
        case .noteCanvas:
            return 3
        case .noteFocus:
            return 3
        case .connectionCanvas, .connectionFocus:
            return 2
        }
    }

    var textAlignment: NSTextAlignment {
        switch self {
        case .connectionFocus:
            return .center
        case .noteCanvas, .noteFocus, .connectionCanvas:
            return .natural
        }
    }

    var swiftUIFont: Font {
        .system(size: fontSize, weight: baseFontWeight.swiftUIFontWeight)
    }

    var swiftUITextAlignment: TextAlignment {
        textAlignment.swiftUITextAlignment
    }

    var minimumHeight: CGFloat {
        EditorLayoutMetrics.titleHeight(
            fontSize: fontSize,
            compact: compact,
            baseFontWeight: baseFontWeight,
            lineCount: 1
        )
    }

    var previewMaxHeight: CGFloat {
        EditorLayoutMetrics.titleHeight(
            fontSize: fontSize,
            compact: compact,
            baseFontWeight: baseFontWeight,
            lineCount: previewLineLimit
        )
    }

    var editingMaxHeight: CGFloat {
        EditorLayoutMetrics.titleHeight(
            fontSize: fontSize,
            compact: compact,
            baseFontWeight: baseFontWeight,
            lineCount: editingLineLimit
        )
    }

    var titleConfiguration: TitleEditorConfiguration {
        TitleEditorConfiguration(
            previewLineLimit: previewLineLimit,
            editingLineLimit: editingLineLimit
        )
    }
}

extension NSFont.Weight {
    var swiftUIFontWeight: Font.Weight {
        switch self {
        case .ultraLight:
            return .ultraLight
        case .thin:
            return .thin
        case .light:
            return .light
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        case .heavy:
            return .heavy
        case .black:
            return .black
        default:
            return .regular
        }
    }
}

extension NSTextAlignment {
    var swiftUITextAlignment: TextAlignment {
        switch self {
        case .center:
            return .center
        case .right:
            return .trailing
        default:
            return .leading
        }
    }
}
