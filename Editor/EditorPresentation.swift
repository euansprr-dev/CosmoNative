// CosmoOS/Editor/EditorPresentation.swift
// Shared presentation mode for editors (Focus Mode vs embedded in blocks)

import SwiftUI

enum EditorPresentation: Sendable {
    case focus
    case embedded

    var showsChromeHeader: Bool {
        switch self {
        case .focus: return true
        case .embedded: return false
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .focus: return 32
        case .embedded: return 12
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .focus: return 20
        case .embedded: return 10
        }
    }

    var constrainReadingWidth: Bool {
        switch self {
        case .focus: return true
        case .embedded: return false
        }
    }

    var showsDateAndTags: Bool {
        switch self {
        case .focus: return true
        case .embedded: return false
        }
    }
}

