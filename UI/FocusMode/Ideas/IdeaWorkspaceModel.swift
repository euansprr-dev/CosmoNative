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
    /// Current width class — kept in sync by the host view so the toolbar
    /// and keyboard shortcuts toggle the right presentation.
    var breakpoint: IdeaWorkspaceBreakpoint = .regular

    /// Regular: inspector as a side column. On by default at full width.
    var isInspectorVisible = true
    /// Compact: inspector as a trailing overlay. Off by default — at pane
    /// widths it would cover the manuscript.
    var isInspectorOverlayPresented = false

    var isInspectorShowing: Bool {
        breakpoint == .regular ? isInspectorVisible : isInspectorOverlayPresented
    }

    func toggleInspector() {
        switch breakpoint {
        case .regular:
            isInspectorVisible.toggle()
        case .compact:
            isInspectorOverlayPresented.toggle()
        }
    }
}

// MARK: - Host actions

/// Host-level actions the toolbar and inspector trigger but don't own
/// (sheet flags and navigation live in the host view).
struct IdeaWorkspaceActions {
    var onShowLinkSwipes: () -> Void = {}
    var onSuggestFramework: () -> Void = {}
    var onChangeFramework: () -> Void = {}
    var onShowBlueprintSheet: () -> Void = {}
    var onShowBlueprintPicker: () -> Void = {}
    var onShowResearch: () -> Void = {}
    var onOpenAtomInPane: (String) -> Void = { _ in }
    var onShowProfileEditor: () -> Void = {}
    var onBeginWriting: () -> Void = {}
    var onClose: () -> Void = {}
}
