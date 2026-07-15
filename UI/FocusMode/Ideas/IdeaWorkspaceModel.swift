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

/// Width classes for the idea workspace. The manuscript is a single column,
/// so two classes suffice: at pane widths the inspector becomes an opt-in
/// overlay instead of a side column.
enum IdeaWorkspaceBreakpoint: Equatable {
    /// ≥1000pt: manuscript + inspector side by side.
    case regular
    /// <1000pt: manuscript only; inspector slides over on demand.
    case compact

    init(width: CGFloat) {
        self = width >= 1000 ? .regular : .compact
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

    var isInspectorShowing: Bool {
        breakpoint == .regular ? isInspectorVisible : isInspectorOverlayPresented
    }

    var isConversationShowing: Bool {
        breakpoint == .regular ? isConversationVisible : isConversationOverlayPresented
    }

    func toggleInspector() {
        switch breakpoint {
        case .regular:
            isInspectorVisible.toggle()
        case .compact:
            // Compact overlays are exclusive — opening one closes the other
            // (the Study's compact manner).
            isInspectorOverlayPresented.toggle()
            if isInspectorOverlayPresented { isConversationOverlayPresented = false }
        }
    }

    func toggleConversation() {
        switch breakpoint {
        case .regular:
            isConversationVisible.toggle()
            UserDefaults.standard.set(isConversationVisible, forKey: Self.conversationDefaultsKey)
        case .compact:
            isConversationOverlayPresented.toggle()
            if isConversationOverlayPresented { isInspectorOverlayPresented = false }
        }
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
