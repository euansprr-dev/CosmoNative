// CosmoOS/UI/FocusMode/Ideas/IdeaWorkspaceModel.swift
// June 2026 — Idea Focus Mode v2 (Greenhouse clean).
// Observable workspace UI state: width breakpoint and inspector visibility.
// Mirrors ConnectionWorkspaceModel's breakpoint/inspector pattern; duplicated
// locally rather than shared — Connection has three width classes and
// different thresholds, and a shared abstraction would touch freshly-shipped
// files for ~40 saved lines (accepted debt).

import SwiftUI
import Observation

// MARK: - Breakpoints

/// The bench's own geometry. The threshold between width classes is DERIVED
/// from what the sheet actually has to seat, never typed — a hardcoded number
/// silently goes wrong the moment a column width or the manuscript's measure
/// changes, and the failure is invisible in code and ugly on screen.
enum IdeaWorkspaceMetrics {
    /// Both bench columns ride the shared inspector width.
    static let columnWidth: CGFloat = StudyMetrics.panelWidth

    /// The narrowest the manuscript may be squeezed to while columns sit
    /// beside it. Below this the sheet's columns HStack reports MORE width
    /// than the sheet was given — and an oversized child of a `.frame(width:)`
    /// is centred and clipped on both edges, not compressed. That is the
    /// "text goes behind everything" state: the bench stops being a layout
    /// and becomes a too-wide picture cropped down the middle.
    static let minimumManuscriptMeasure: CGFloat = 560

    /// `cosmoInnerWindow()` insets the sheet on both sides.
    static let sheetInset: CGFloat = CosmoSurfaceMetrics.windowInset * 2

    /// Can this width seat `count` columns AND leave the manuscript its
    /// measure? Panel-count aware on purpose: the common setup is the
    /// inspector alone, which fits beside the manuscript ~300pt sooner than
    /// the inspector-plus-conversation pair does. One flat threshold has to
    /// pick a side — too low and both columns crush the manuscript, too high
    /// and the single column is thrown away for widths where it fits fine.
    static func seatsColumns(count: Int, in width: CGFloat) -> Bool {
        width - sheetInset - CGFloat(count) * columnWidth >= minimumManuscriptMeasure
    }
}

/// Width classes for the idea workspace. The manuscript is a single column,
/// so two classes suffice: when the columns the user asked for don't fit
/// beside it, they become opt-in overlays instead.
enum IdeaWorkspaceBreakpoint: Equatable {
    /// Manuscript + the requested panels side by side.
    case regular
    /// Manuscript only; panels slide over on demand.
    case compact

    /// `columns` is what the user has ASKED for — the persisted intent flags,
    /// not `isInspectorShowing`/`isConversationShowing`. Resolving against the
    /// showing state would be circular, since those read the breakpoint back.
    init(width: CGFloat, columns: Int) {
        self = IdeaWorkspaceMetrics.seatsColumns(count: columns, in: width) ? .regular : .compact
    }
}

// MARK: - Workspace model

@MainActor
@Observable
final class IdeaWorkspaceModel {
    private static let conversationDefaultsKey = "idea.workbench.conversation"

    /// Current width class — kept in sync by the host view so the toolbar
    /// and keyboard shortcuts toggle the right presentation.
    var breakpoint: IdeaWorkspaceBreakpoint = .regular

    /// Regular: inspector as a side column. On by default at full width.
    var isInspectorVisible = true
    /// Compact: inspector as a trailing overlay. Off by default — at pane
    /// widths it would cover the manuscript.
    var isInspectorOverlayPresented = false

    /// The conversation panel (the bench's left column — the resident
    /// assistant). Off by default; the choice persists across sessions.
    var isConversationVisible: Bool
    /// Compact: conversation as a leading overlay, never persisted.
    var isConversationOverlayPresented = false

    init() {
        isConversationVisible = UserDefaults.standard.bool(forKey: Self.conversationDefaultsKey)
    }

    /// Columns the user has asked for. Feeds the breakpoint, so it must read
    /// the intent flags only — never the resolved `…Showing` properties.
    var requestedColumnCount: Int {
        (isInspectorVisible ? 1 : 0) + (isConversationVisible ? 1 : 0)
    }

    var isInspectorShowing: Bool { isInspectorShowing(at: breakpoint) }

    var isConversationShowing: Bool { isConversationShowing(at: breakpoint) }

    /// The layout pass resolves the breakpoint from the width it was handed
    /// and asks these directly, so the columns it draws match the width it
    /// draws them at. `breakpoint` trails one pass behind and is only good
    /// enough for the toolbar and the keyboard shortcuts.
    func isInspectorShowing(at breakpoint: IdeaWorkspaceBreakpoint) -> Bool {
        breakpoint == .regular ? isInspectorVisible : isInspectorOverlayPresented
    }

    func isConversationShowing(at breakpoint: IdeaWorkspaceBreakpoint) -> Bool {
        breakpoint == .regular ? isConversationVisible : isConversationOverlayPresented
    }

    // MARK: Toggles

    // A toggle raises BOTH the intent flag and the overlay flag, because
    // asking for a panel can itself be what pushes the sheet out of `regular`
    // — a second column may not fit where one did. Setting only the intent
    // would answer the user's click by showing nothing at all.

    func toggleInspector() {
        if isInspectorShowing {
            isInspectorVisible = false
            isInspectorOverlayPresented = false
        } else {
            isInspectorVisible = true
            isInspectorOverlayPresented = true
            // Overlays are exclusive — opening one closes the other (the
            // Study's compact manner). Inert while both are columns.
            isConversationOverlayPresented = false
        }
    }

    func toggleConversation() {
        if isConversationShowing {
            isConversationVisible = false
            isConversationOverlayPresented = false
        } else {
            isConversationVisible = true
            isConversationOverlayPresented = true
            isInspectorOverlayPresented = false
        }
        UserDefaults.standard.set(isConversationVisible, forKey: Self.conversationDefaultsKey)
    }
}

// MARK: - Host actions

/// Host-level actions the toolbar and inspector trigger but don't own
/// (overlay flags and navigation live in the host view). Framework,
/// blueprint, and research actions were removed with their surfaces
/// (July 2026) — the rail is swipes now, and research lives in the
/// inline assistant's /Research skill.
struct IdeaWorkspaceActions {
    var onShowLinkSwipes: () -> Void = {}
    var onOpenAtomInPane: (String) -> Void = { _ in }
    var onShowProfileEditor: () -> Void = {}
    var onBeginWriting: () -> Void = {}
    var onClose: () -> Void = {}
}
