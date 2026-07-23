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

    // MARK: Media lightbox

    /// The media ref open in the Stage lightbox, if any. UI state only —
    /// first stop in the Esc chain.
    var presentedMediaID: UUID?

    /// URL captures in flight from a board paste/drop — the gallery renders
    /// one skeleton tile per pending capture.
    var pendingMediaCaptures = 0

    /// Swipes the attach_media agent tool staged as ghost tiles — accepted
    /// tiles become real refs, dismissed ones vanish. In-memory only.
    var stagedMediaAtoms: [Atom] = []

    /// Rebuttals the collaborator staged via handle_objection — ghost
    /// threads under their objection rows with ✓/✗. In-memory only (a
    /// live-conversation surface); accepting writes the real handling.
    var stagedObjectionHandlings: [StagedObjectionHandling] = []

    /// ⌘-clicked gallery tiles queued for side-by-side comparison (2–4).
    var compareSelection: Set<UUID> = []
    /// The compare strip overlay — sits above the lightbox in the Esc chain.
    var isComparePresented = false

    func toggleCompareSelection(_ id: UUID) {
        if compareSelection.contains(id) {
            compareSelection.remove(id)
        } else if compareSelection.count < 4 {
            compareSelection.insert(id)
        }
    }

    // MARK: Actions

    /// The section the user has spotlighted from the navigator, if any.
    /// Everything else dims around it. Drill-in (pushedSection) supersedes it.
    var focusedSection: ConnectionSectionType? {
        guard pushedSection == nil, case .section(let type) = selection else { return nil }
        return type
    }

    /// Navigator single-click: focus the section, or clear focus when the
    /// already-focused section is clicked again.
    func toggleFocus(on type: ConnectionSectionType) {
        if focusedSection == type {
            selection = .connection
        } else {
            jump(to: type)
        }
    }

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

/// A staged (not-yet-accepted) insertion, routed to the board/outline section
/// it targets and rendered as a ghost row with its own ✓/✗. Two origins share
/// the one staging grammar:
/// - concept-collaborator proposals (ephemeral; built from a pending
///   `CosmoAssistantProposalOperation` via
///   `ConnectionSurfaceSerializer.pendingInsert(for:in:)`), and
/// - persisted pending material (`ConnectionStagedInsert` on the atom's
///   metadata — inbox feeds, seedling develops; survives restarts and syncs).
struct ConnectionPendingInsert: Identifiable, Equatable {
    let proposalID: UUID
    let operationID: UUID
    let section: ConnectionSectionType
    let bullets: [String]
    /// Set when this row REVISES an existing entry (a textReplacement op):
    /// the current bullet text, shown struck-through above the new wording.
    var revisesText: String? = nil
    /// Set when an insertion anchors an existing bullet (it will land right
    /// after it) — display copy for the row's placement caption.
    var afterText: String? = nil
    /// Set when this row is persisted pending material — accept/reject then
    /// route through `ConnectionStagingStore` instead of the assistant store.
    var stagedEntryId: String? = nil

    var id: UUID { operationID }

    /// True for material that arrived from a capture (inbox/seedling) rather
    /// than an assistant proposal — the row wears a different mark.
    var isFromCapture: Bool { stagedEntryId != nil }

    /// True when this ghost row rewrites an existing entry instead of adding
    /// new ones.
    var isRevision: Bool { revisesText != nil }
}

// MARK: - Staged objection handling

/// A collaborator-proposed rebuttal awaiting the user's ✓/✗ — the handling
/// twin of ConnectionPendingInsert. One per objection at a time (a newer
/// proposal replaces the old ghost).
struct StagedObjectionHandling: Identifiable, Equatable {
    let id: UUID
    let objectionItemID: UUID
    /// Snippet of the objection text, so ghost rows on the board card read
    /// standalone.
    let objectionSnippet: String
    let text: String
    let linkedRefs: [ConnectionBoardItemRef]

    init(
        id: UUID = UUID(),
        objectionItemID: UUID,
        objectionSnippet: String,
        text: String,
        linkedRefs: [ConnectionBoardItemRef]
    ) {
        self.id = id
        self.objectionItemID = objectionItemID
        self.objectionSnippet = objectionSnippet
        self.text = text
        self.linkedRefs = linkedRefs
    }
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
    var onTitleCommit: () -> Void = {}
    var onClose: () -> Void = {}
    /// Accept a single staged insert from its section card / outline row.
    var onAcceptInsert: (ConnectionPendingInsert) -> Void = { _ in }
    /// Reject a single staged insert from its section card / outline row.
    var onRejectInsert: (ConnectionPendingInsert) -> Void = { _ in }

    // MARK: Media

    /// Open a media ref in the Stage lightbox.
    var onOpenMedia: (UUID) -> Void = { _ in }
    /// Open a media ref's source atom as a pane beside the concept.
    var onOpenMediaAsPane: (String) -> Void = { _ in }
    /// Atom uuids dropped onto the board — nil section = gallery only.
    var onDropMediaAtoms: ([String], ConnectionSectionType?) -> Void = { _, _ in }
    /// Media files (images/videos) dropped from Finder or pasted.
    var onDropMediaFiles: ([URL], ConnectionSectionType?) -> Void = { _, _ in }
    /// A platform URL pasted/dropped onto the board — runs the capture
    /// pipeline, then attaches.
    var onPasteMediaURL: (String, ConnectionSectionType?) -> Void = { _, _ in }
    /// Gallery "+": arm the shared ⌘K picker so the next pick attaches as
    /// media instead of a source link.
    var onAddMediaTapped: () -> Void = {}
    var onDetachMedia: (UUID) -> Void = { _ in }
    var onToggleMediaCover: (UUID) -> Void = { _ in }
    var onAnchorMedia: (UUID, ConnectionSectionType?) -> Void = { _, _ in }
    /// ⌘-click on a tile queues it for the compare strip.
    var onToggleCompareSelection: (UUID) -> Void = { _ in }
    var onPresentCompare: () -> Void = {}
    /// Accept / dismiss a handle_objection ghost thread (by staged id).
    var onAcceptStagedHandling: (UUID) -> Void = { _ in }
    var onRejectStagedHandling: (UUID) -> Void = { _ in }
    /// Accept / dismiss an attach_media ghost tile (by source atom uuid).
    var onAcceptStagedMedia: (String) -> Void = { _ in }
    var onRejectStagedMedia: (String) -> Void = { _ in }
}
