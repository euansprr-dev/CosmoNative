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

    // Switcher — the search/browse surface every item's Back leads to.
    /// Below this width the detail pane yields and a click opens directly.
    static let switcherPreviewBreakpoint: CGFloat = 860
    static let switcherFieldHeight: CGFloat = 52
    static let switcherFieldMaxWidth: CGFloat = 680
    static let switcherFooterHeight: CGFloat = 36
    /// The rail's mark slot — the Command-K 38×50 object frame, so both
    /// surfaces read as one family.
    static let switcherMarkSize = CGSize(width: 38, height: 50)

    static func switcherPreviewWidth(for windowWidth: CGFloat) -> CGFloat {
        min(440, max(320, (windowWidth * 0.42).rounded()))
    }

    // Navigation
    static let controlSize: CGFloat = 32
    static let controlCornerRadius: CGFloat = 10
}
