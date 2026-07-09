// CosmoOS/UI/AtomWindow/AtomWindowMetrics.swift
// Layout constants for the floating atom viewer panel

import Foundation

enum AtomWindowMetrics {
    // Panel dimensions — the default comfortably fits the notes reading
    // measure (680pt + block gutter + margins); the ceiling leaves room for
    // the Wide page setting (940pt measure) to actually read wide.
    static let defaultWidth: CGFloat = 880
    static let defaultHeight: CGFloat = 640
    static let minWidth: CGFloat = 560
    static let minHeight: CGFloat = 480
    static let maxWidth: CGFloat = 1440
    static let maxHeight: CGFloat = 1000

    // Chrome
    static let panelCornerRadius: CGFloat = 20
    static let headerHeight: CGFloat = 48
    static let focusToolbarHeight: CGFloat = 44
    static let contentPadding: CGFloat = 16

    // Search overlay
    static let searchOverlayMaxHeight: CGFloat = 500
    static let searchFieldHeight: CGFloat = 40
    static let searchResultRowHeight: CGFloat = 52
    static let filterChipHeight: CGFloat = 30

    // Navigation
    static let controlSize: CGFloat = 32
    static let controlCornerRadius: CGFloat = 10
}
