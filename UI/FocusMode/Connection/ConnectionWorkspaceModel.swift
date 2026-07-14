// CosmoOS/UI/FocusMode/Connection/ConnectionWorkspaceModel.swift
// June 2026 — Connection workspace revamp.
// Observable UI state for the structured 3-pane connection workspace:
// view mode, selection, search, pane visibility, and width breakpoints.

import SwiftUI
import Observation

// MARK: - View mode

/// The center column's presentation. Persisted in ConnectionFocusModeState
/// under the legacy `forgeMode` key (old `forge`/`chalkboard` values map to
/// `.board`).
enum ConnectionViewMode: String, Codable, CaseIterable {
    case board
    case outline
    case manuscript

    var displayName: String {
        switch self {
        case .board: return "Board"
        case .outline: return "Outline"
        case .manuscript: return "Manuscript"
        }
    }

    var icon: String {
        switch self {
        case .board: return "square.grid.2x2"
        case .outline: return "list.bullet"
        case .manuscript: return "text.book.closed"
        }
    }

    /// Tolerant decode for persisted V2 values.
    init(legacyRawValue: String) {
        switch legacyRawValue {
        case "manuscript": self = .manuscript
        case "outline": self = .outline
        default: self = .board // "forge", "chalkboard", unknown
        }
    }
}

// MARK: - Breakpoints

/// Width classes for the adaptive 3-pane layout. The workspace is hosted
/// full-screen, in panes, and in standalone windows — including beside the
/// open assistant pane — so it must collapse gracefully.
enum ConnectionWorkspaceBreakpoint: Equatable {
    /// ≥1100pt: navigator + board + inspector side by side.
    case regular
    /// 700–1100pt: icon rail + board; inspector slides over.
    case compact
    /// <700pt: single column; navigator and inspector are overlays.
    case narrow

    init(width: CGFloat) {
        if width >= 1100 {
            self = .regular
        } else if width >= 700 {
            self = .compact
        } else {
            self = .narrow
        }
    }
}

// MARK: - Selection

/// What the inspector describes. Selection is UI state, never persisted.
enum ConnectionWorkspaceSelection: Equatable {
    case connection
    case section(ConnectionSectionType)
    case item(ConnectionSectionType, UUID)
    case source(String)
}

// MARK: - Workspace model

@MainActor
@Observable
final class ConnectionWorkspaceModel {
    var viewMode: ConnectionViewMode = .board
    var selection: ConnectionWorkspaceSelection = .connection

    /// Drill-in section detail shown in the center column (replaces the old
    /// full-screen Station Mode overlay).
    var pushedSection: ConnectionSectionType?

    // MARK: Search

    var searchQuery: String = ""
    /// Incremented to ask the toolbar to focus the search field (⌘F).
    var searchFocusTick: Int = 0

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Pane visibility

    /// Current width class — kept in sync by ConnectionWorkspaceView so the
    /// toolbar and keyboard shortcuts toggle the right presentation.
    var breakpoint: ConnectionWorkspaceBreakpoint = .regular

    /// User preference: collapse the navigator to the 44pt icon rail (regular).
    var isNavigatorCollapsed = false
    /// Regular: inspector as a side column. On by default at full width.
    var isInspectorVisible = true
    /// Compact/narrow: full navigator presented as a leading overlay.
    var isNavigatorOverlayPresented = false
    /// Compact/narrow: inspector presented as a trailing overlay. Off by
    /// default — at pane widths it would cover board content.
    var isInspectorOverlayPresented = false

    /// Whether the inspector is currently showing in this breakpoint's form.
    var isInspectorShowing: Bool {
        breakpoint == .regular ? isInspectorVisible : isInspectorOverlayPresented
    }

    var isNavigatorShowing: Bool {
        breakpoint == .regular ? !isNavigatorCollapsed : isNavigatorOverlayPresented
    }

    func toggleNavigator() {
        switch breakpoint {
        case .regular:
            isNavigatorCollapsed.toggle()
        case .compact, .narrow:
            isNavigatorOverlayPresented.toggle()
        }
    }

    func toggleInspector() {
        switch breakpoint {
        case .regular:
            isInspectorVisible.toggle()
        case .compact, .narrow:
            isInspectorOverlayPresented.toggle()
        }
    }

    /// Board scroll target — set by navigator clicks, consumed by the board.
    var scrollTarget: ConnectionSectionType?

    // MARK: Actions

    func jump(to type: ConnectionSectionType) {
        selection = .section(type)
        if pushedSection != nil {
            pushedSection = type
        } else {
            scrollTarget = type
        }
        isNavigatorOverlayPresented = false
    }

    func openSection(_ type: ConnectionSectionType) {
        selection = .section(type)
        pushedSection = type
        isNavigatorOverlayPresented = false
    }

    func popSection() {
        pushedSection = nil
        if case .section(let type) = selection {
            scrollTarget = type
        }
    }

    // MARK: Search filtering

    /// Sections whose name, prompt, or item text matches the query.
    /// An empty query matches everything.
    func matchingSections(in sections: [ConnectionSection]) -> [ConnectionSection] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sections }
        return sections.filter { sectionMatches($0, query: query) }
    }

    func sectionMatches(_ section: ConnectionSection, query: String? = nil) -> Bool {
        let q = (query ?? searchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if section.type.displayName.localizedCaseInsensitiveContains(q) { return true }
        return section.items.contains { $0.resolvedPlainText.localizedCaseInsensitiveContains(q) }
    }

    func matchingItems(in section: ConnectionSection) -> [ConnectionItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return section.items }
        return section.items.filter { $0.resolvedPlainText.localizedCaseInsensitiveContains(q) }
    }

    func sourceMatches(_ atom: Atom) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return (atom.title ?? "").localizedCaseInsensitiveContains(q)
    }
}

// MARK: - Pending staged insert

/// A staged (not-yet-accepted) concept-collaborator insertion, routed to the
/// board/outline section it targets. This is what lets the assistant's edits
/// render as ghost rows *inside* the section card (or inline in Outline) with
/// their own ✓/✗ — instead of the full-screen linear text diff. Built from a
/// pending `CosmoAssistantProposalOperation` via
/// `ConnectionSurfaceSerializer.pendingInsert(for:in:)`.
struct ConnectionPendingInsert: Identifiable, Equatable {
    let proposalID: UUID
    let operationID: UUID
    let section: ConnectionSectionType
    let bullets: [String]

    var id: UUID { operationID }
}

// MARK: - Host data + actions

/// Linked/suggested source data assembled by the host focus-mode view.
struct ConnectionWorkspaceSources {
    var linked: [Atom] = []
    var suggested: [Atom] = []
    var isLoadingSuggestions = false
    var isShowingSuggestions = false
    /// Section contributions per source UUID (which sections cite it).
    var contributions: [String: Set<ConnectionSectionType>] = [:]
}

/// One-shot deep link from the canvas block into a specific section: the
/// block stashes the target before posting the open-focus notification, and
/// the focus mode consumes it on appear (the notification fires before the
/// focus view exists, so userInfo alone can't reach it).
@MainActor
enum ConnectionFocusDeepLink {
    private static var pending: (atomUUID: String, section: ConnectionSectionType)?

    static func stash(atomUUID: String, section: ConnectionSectionType) {
        pending = (atomUUID, section)
    }

    static func consume(for atomUUID: String) -> ConnectionSectionType? {
        guard let pending, pending.atomUUID == atomUUID else { return nil }
        self.pending = nil
        return pending.section
    }
}

/// Host-level actions the workspace triggers but doesn't own.
struct ConnectionWorkspaceActions {
    var onSourceTap: (String) -> Void = { _ in }
    var onAddSource: () -> Void = {}
    var onRequestSuggestions: () -> Void = {}
    var onLinkSuggestedSource: (Atom) -> Void = { _ in }
    var onRefreshInsights: () -> Void = {}
    var onDismissInsight: (UUID) -> Void = { _ in }
    var onTitleCommit: () -> Void = {}
    var onClose: () -> Void = {}
    /// Accept a single staged insert from its section card / outline row.
    var onAcceptInsert: (ConnectionPendingInsert) -> Void = { _ in }
    /// Reject a single staged insert from its section card / outline row.
    var onRejectInsert: (ConnectionPendingInsert) -> Void = { _ in }
}
