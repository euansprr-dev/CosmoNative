// CosmoOS/Canvas/Spaces/SpaceComposerModel.swift
// The composer sheet's model — one class for "New space" and "Space settings"
// so the two grammars never drift. Owns the draft, the identity ladder, the
// kind/view rules, and the commit. Talks to the world through
// `SpaceComposerHost` so tests run without a database.

import Foundation
import SwiftUI

// MARK: - Host

/// What the composer needs from the world — `ThinkspaceManager` in the app, a
/// stub in tests (the manager's init opens the database).
@MainActor
protocol SpaceComposerHost: AnyObject {
    var thinkspaces: [Thinkspace] { get }
    var sidebarThinkspaces: [Thinkspace] { get }
    func suggestedAccentColorHex() -> String
    func canNest(_ thinkspaceId: String, under newParentId: String) -> Bool
    func createThinkspace(draft: SpaceDraft, projectUuid: String?, isRoot: Bool) async -> Thinkspace?
    func updateSpaceSettings(_ thinkspace: Thinkspace, draft: SpaceDraft) async
}

extension ThinkspaceManager: SpaceComposerHost {}

// MARK: - Model

@MainActor
@Observable
final class SpaceComposerModel {
    enum Mode {
        case create(parentId: String?)
        case edit(Thinkspace)
    }

    /// A parent candidate with its depth in the sidebar tree (for indentation).
    struct ParentOption: Identifiable, Equatable {
        let thinkspace: Thinkspace
        let depth: Int
        var id: String { thinkspace.id }
    }

    static let lastKindDefaultsKey = "com.cosmo.spaces.lastKind"
    static let fallbackKind: SpaceKind = .custom

    let mode: Mode
    var draft: SpaceDraft
    var isEmojiPickerPresented = false
    private(set) var isCommitting = false
    private(set) var lastError: String?

    /// Whether `draft.emoji` was chosen by the user rather than seeded from
    /// the kind. A seeded mark follows kind changes; a chosen one survives them.
    private(set) var emojiIsExplicit: Bool

    @ObservationIgnored private let host: any SpaceComposerHost
    @ObservationIgnored private let defaults: UserDefaults

    convenience init(mode: Mode, manager: ThinkspaceManager = .shared, defaults: UserDefaults = .standard) {
        self.init(mode: mode, host: manager, defaults: defaults)
    }

    /// Create mode starts from the last kind the user chose (Research the
    /// first time) with the palette colour the manager would hand out next.
    /// The kind's suggested emoji is seeded into the draft — a new space
    /// carries the mark the user saw in the well, not a glyph fallback.
    init(mode: Mode, host: any SpaceComposerHost, defaults: UserDefaults = .standard) {
        self.mode = mode
        self.host = host
        self.defaults = defaults
        switch mode {
        case .create(let parentId):
            let kind = SpaceKind.custom
            var draft = SpaceDraft.new(kind: kind, parentId: parentId, accentHex: host.suggestedAccentColorHex())
            draft.enabledViews = [.canvas, .library, .deepDive]
            draft.emoji = nil
            self.draft = draft
            self.emojiIsExplicit = false
        case .edit(let thinkspace):
            self.draft = SpaceDraft(thinkspace: thinkspace)
            self.emojiIsExplicit = thinkspace.emoji != nil
        }
    }

    // MARK: Mode

    var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    var editingThinkspace: Thinkspace? {
        if case .edit(let thinkspace) = mode { return thinkspace }
        return nil
    }

    var title: String { isCreate ? "New space" : "Space settings" }

    var subtitle: String {
        isCreate
            ? "A place for your notes, sources and developing work."
            : "Identity and where this space lives."
    }

    var primaryTitle: String { isCreate ? "Create" : "Save" }

    var focusesNameOnAppear: Bool { isCreate }

    var accentColor: Color { Color(hex: draft.accentColorHex) }

    // MARK: Identity ladder

    /// A leading emoji typed into the name (the identity law: it always wins).
    private var typedEmoji: String? {
        CollectionEmoji.resolve(name: draft.name, matchKeywords: false).emoji
    }

    /// The typed mark, else a curated keyword match — what rows derive live.
    private var nameEmoji: String? {
        CollectionEmoji.resolve(name: draft.name).emoji
    }

    /// Typed → chosen/seeded → keyword → the kind's suggestion. Never nil in
    /// practice; optional so callers can fall back to the glyph.
    var resolvedEmoji: String? {
        typedEmoji ?? draft.emoji ?? nameEmoji
    }

    /// What the identity well shows: exactly the mark the space will wear
    /// after commit. A new space always gets a mark (see `outgoingDraft`);
    /// an existing one shows the glyph when nothing resolves.
    var identityPreviewEmoji: String? {
        isCreate ? resolvedEmoji : (typedEmoji ?? draft.emoji ?? nameEmoji)
    }

    /// The kind's suggestion first, then the name's keyword marks and the
    /// common ones — deduped for the picker grid.
    var emojiSuggestions: [String] {
        var seen = Set<String>()
        return ([draft.kind.suggestedEmoji] + CollectionEmoji.suggestions(for: draft.name))
            .filter { seen.insert($0).inserted }
    }

    func setEmoji(_ emoji: String?) {
        let trimmed = emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        draft.emoji = trimmed.isEmpty ? nil : trimmed
        emojiIsExplicit = !trimmed.isEmpty
        isEmojiPickerPresented = false
    }

    // MARK: Kind & views

    /// Applies the kind's preset (views in opening order). In create mode a
    /// seeded mark follows the kind; a mark the user picked stays.
    func selectKind(_ kind: SpaceKind) {
        draft.kind = kind
        draft.enabledViews = kind.preset.views
        if isCreate, !emojiIsExplicit {
            draft.emoji = kind.suggestedEmoji
        }
    }

    /// Chips in display order: the enabled run (in draft order, first opens)
    /// followed by the views this build can render but the draft leaves off.
    var viewChoices: [SpaceView] {
        draft.enabledViews + SpaceView.allCases.filter {
            SpaceView.renderable.contains($0) && !draft.enabledViews.contains($0)
        }
    }

    var openingView: SpaceView { draft.defaultView }

    func isEnabled(_ view: SpaceView) -> Bool {
        draft.enabledViews.contains(view)
    }

    /// Never below one view.
    func toggleView(_ view: SpaceView) {
        if let index = draft.enabledViews.firstIndex(of: view) {
            guard draft.enabledViews.count > 1 else { return }
            draft.enabledViews.remove(at: index)
        } else {
            draft.enabledViews.append(view)
        }
        noteViewsChanged()
    }

    /// Places `view` before `target` (nil, or a disabled target, = at the
    /// end). A disabled `view` is enabled at that position.
    func moveView(_ view: SpaceView, before target: SpaceView?) {
        guard view != target else { return }
        var views = draft.enabledViews
        views.removeAll { $0 == view }
        if let target, let index = views.firstIndex(of: target) {
            views.insert(view, at: index)
        } else {
            views.append(view)
        }
        guard views != draft.enabledViews else { return }
        draft.enabledViews = views
        noteViewsChanged()
    }

    /// ⌘←/⌘→ on a focused chip: one step along the enabled run.
    func nudgeView(_ view: SpaceView, by offset: Int) {
        guard let index = draft.enabledViews.firstIndex(of: view) else { return }
        let destination = max(0, min(draft.enabledViews.count - 1, index + offset))
        guard destination != index else { return }
        var views = draft.enabledViews
        views.remove(at: index)
        views.insert(view, at: destination)
        draft.enabledViews = views
        noteViewsChanged()
    }

    /// Diverging from the kind's preset (membership or order) makes the space
    /// custom. Client spaces keep their kind — it carries the Studio link, not
    /// a view recipe.
    private func noteViewsChanged() {
        guard draft.kind != .custom, draft.kind != .client else { return }
        if draft.enabledViews != draft.kind.preset.views {
            draft.kind = .custom
        }
    }

    // MARK: Parent

    var validation: SpaceDraftValidation {
        draft.validate { [self] parentId in canNest(under: parentId) }
    }

    private func canNest(under parentId: String) -> Bool {
        switch mode {
        case .create:
            return true
        case .edit(let thinkspace):
            return host.canNest(thinkspace.id, under: parentId)
        }
    }

    /// Every sidebar space a new one may live in; when editing, never the
    /// space itself or anything inside it.
    var parentCandidates: [Thinkspace] {
        let all = host.sidebarThinkspaces
        guard let editing = editingThinkspace else { return all }
        return all.filter { host.canNest(editing.id, under: $0.id) }
    }

    /// Candidates flattened depth-first, siblings A→Z, for an indented menu.
    /// A candidate whose parent was excluded (or is unknown) roots its own
    /// subtree; a visited set shields against cyclic data.
    var parentOptions: [ParentOption] {
        let candidates = parentCandidates
        let ids = Set(candidates.map(\.id))
        let byParent = Dictionary(grouping: candidates) { candidate -> String in
            guard let parent = candidate.parentThinkspaceId, ids.contains(parent) else { return "" }
            return parent
        }
        var result: [ParentOption] = []
        var visited = Set<String>()
        func walk(_ parentKey: String, depth: Int) {
            let siblings = (byParent[parentKey] ?? []).sorted {
                $0.identityLabel.localizedCaseInsensitiveCompare($1.identityLabel) == .orderedAscending
            }
            for candidate in siblings where visited.insert(candidate.id).inserted {
                result.append(ParentOption(thinkspace: candidate, depth: depth))
                walk(candidate.id, depth: depth + 1)
            }
        }
        walk("", depth: 0)
        return result
    }

    var selectedParent: Thinkspace? {
        guard let parentId = draft.parentThinkspaceId else { return nil }
        return host.thinkspaces.first { $0.id == parentId }
    }

    var parentLabel: String {
        "Inside · " + (selectedParent?.identityLabel ?? "Top level")
    }

    // MARK: Commit

    /// Creates or saves. Returns the resulting space (fresh from the host) or
    /// nil with `lastError` set. Create mode remembers the kind and posts
    /// `spaceComposerDidCreate`.
    @discardableResult
    func commit() async -> Thinkspace? {
        guard validation.isValid, !isCommitting else { return nil }
        isCommitting = true
        lastError = nil
        defer { isCommitting = false }
        let outgoing = outgoingDraft()
        switch mode {
        case .create:
            guard let created = await host.createThinkspace(draft: outgoing, projectUuid: nil, isRoot: false) else {
                lastError = "Couldn't create the space."
                return nil
            }
            defaults.set(outgoing.kind.rawValue, forKey: Self.lastKindDefaultsKey)
            SpaceComposerCreated(thinkspaceId: created.id, parentId: outgoing.parentThinkspaceId).post()
            return created
        case .edit(let thinkspace):
            await host.updateSpaceSettings(thinkspace, draft: outgoing)
            guard let refreshed = host.thinkspaces.first(where: { $0.id == thinkspace.id }) else {
                lastError = "Couldn't save the space."
                return nil
            }
            return refreshed
        }
    }

    /// The draft as persisted — the same mark the well showed:
    /// - a leading emoji typed into the name outranks any other mark, so the
    ///   draft's emoji is cleared and `normalized()` lifts the typed one;
    /// - a new space always carries a mark: when nothing else resolves, the
    ///   kind's suggestion is written explicitly. Name-derived marks are NOT
    ///   frozen in — rows derive them live, so a rename keeps following.
    func outgoingDraft() -> SpaceDraft {
        var draft = self.draft
        if typedEmoji != nil { draft.emoji = nil }
        var normalized = draft.normalized()
        return normalized
    }

    // MARK: Last-used kind

    /// The composer opens on the kind chosen last time; only composer kinds
    /// count (a remembered client kind falls back).
    static func lastUsedKind(in defaults: UserDefaults) -> SpaceKind {
        guard let raw = defaults.string(forKey: lastKindDefaultsKey),
              let kind = SpaceKind(rawValue: raw),
              SpaceKind.composerKinds.contains(kind) else { return fallbackKind }
        return kind
    }
}
