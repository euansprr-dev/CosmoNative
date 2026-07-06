// CosmoOS/UI/FocusMode/Inquiry/Study/StudyBreakpoint.swift
// Width classes + shared surfaces for the Study shell. Mirrors
// ConnectionWorkspaceBreakpoint's philosophy: resolve once at the shell top,
// pass down — never sprinkle GeometryReaders through rows.

import SwiftUI

enum StudyBreakpoint: Equatable {
    /// ≥1180pt: both glass panels float beside the page.
    case regular
    /// 760–1180pt: panels default hidden and slide OVER the page; opening one
    /// closes the other.
    case compact
    /// <760pt: islands collapse to icons; panels are overlays with a scrim.
    case narrow

    init(width: CGFloat) {
        if width >= 1180 {
            self = .regular
        } else if width >= 760 {
            self = .compact
        } else {
            self = .narrow
        }
    }

    /// Panels sit beside the page only at regular width.
    var panelsDisplace: Bool { self == .regular }
}

/// Shared Study shell metrics — one source for the concentric layout.
enum StudyMetrics {
    static let panelWidth: CGFloat = 300
    static let panelCorner: CGFloat = 18
    static let edgeInset: CGFloat = 16
    /// Scroll clearance above the floating thinking bar at the sheet's foot.
    static let panelBottomInset: CGFloat = 92
    static let pageMeasure: CGFloat = 680
    /// The reader's one shared column: player, transcript, and the thinking
    /// bar all sit on this measure so their edges align as one manuscript.
    static let readerMeasure: CGFloat = 760
    /// One stable instrument width — the bar never stretches or collapses.
    /// Matches `readerMeasure` so the bar belongs to the column it serves.
    static let barMaxWidth: CGFloat = readerMeasure
}

// MARK: - The Study panel surface (the inspector idiom)

/// Apple's rule (WWDC25, AppKit session): navigation sidebars FLOAT as glass
/// above content; inspectors — panels about the current content, which is
/// what TRAIL and READING are — sit EDGE-TO-EDGE alongside the content, full
/// height, docked flush. So: a quiet near-opaque surface, a hairline on the
/// content-facing edge, square corners, no shadow. The chrome islands float
/// above them exactly like Tahoe toolbars float above sidebar regions.
struct StudyPanelSurface: ViewModifier {
    /// The window edge this inspector is docked to.
    let edge: HorizontalEdge
    /// True when the panel is presented as an overlay (compact/narrow) —
    /// overlays lift with one soft shadow so they read as temporary.
    var isOverlay: Bool = false

    func body(content: Content) -> some View {
        content
            .background(DS.surfaceCard.opacity(0.98))
            .overlay(alignment: edge == .leading ? .trailing : .leading) {
                Divider().overlay(DS.borderSubtle)
            }
            .shadow(
                color: .black.opacity(isOverlay ? 0.18 : 0),
                radius: isOverlay ? 18 : 0,
                x: isOverlay ? (edge == .leading ? 6 : -6) : 0
            )
    }
}

extension View {
    func studyPanelSurface(edge: HorizontalEdge, isOverlay: Bool = false) -> some View {
        modifier(StudyPanelSurface(edge: edge, isOverlay: isOverlay))
    }
}
