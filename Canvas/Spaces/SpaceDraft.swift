// CosmoOS/Canvas/Spaces/SpaceDraft.swift
// The editable shape of a space — what the composer sheet and Space settings
// read and write. One draft type for create AND edit, so the two never drift.

import Foundation

struct SpaceDraft: Equatable, Sendable {
    var name: String
    /// Explicit identity override only. A leading emoji typed into the name
    /// is lifted here by `normalized()`; rows fall back to the name's own
    /// resolved emoji when this is nil.
    var emoji: String?
    var kind: SpaceKind
    /// Ordered; the first enabled view is where the space opens until the
    /// user visits another one.
    var enabledViews: [SpaceView]
    var accentColorHex: String
    var parentThinkspaceId: String?
    var linkedClientUUID: String?

    var defaultView: SpaceView { enabledViews.first ?? .canvas }

    /// A fresh draft for the composer: the kind's preset views, its suggested emoji.
    static func new(kind: SpaceKind, parentId: String? = nil, accentHex: String) -> SpaceDraft {
        SpaceDraft(
            name: "",
            emoji: nil,
            kind: kind,
            enabledViews: kind.preset.views,
            accentColorHex: accentHex,
            parentThinkspaceId: parentId,
            linkedClientUUID: nil
        )
    }

    /// What every title-only creation path (⌘K, agent, Inbox) gets: today's
    /// three views, opening on the canvas — nothing changes for callers that
    /// never learned about kinds.
    static func programmaticDefault(name: String, parentId: String? = nil, accentHex: String) -> SpaceDraft {
        SpaceDraft(
            name: name,
            emoji: nil,
            kind: .custom,
            enabledViews: [.home, .library, .canvas, .deepDive],
            accentColorHex: accentHex,
            parentThinkspaceId: parentId,
            linkedClientUUID: nil
        )
    }

    init(
        name: String,
        emoji: String?,
        kind: SpaceKind,
        enabledViews: [SpaceView],
        accentColorHex: String,
        parentThinkspaceId: String?,
        linkedClientUUID: String?
    ) {
        self.name = name
        self.emoji = emoji
        self.kind = kind
        self.enabledViews = enabledViews
        self.accentColorHex = accentColorHex
        self.parentThinkspaceId = parentThinkspaceId
        self.linkedClientUUID = linkedClientUUID
    }

    /// The draft that edits an existing space in place.
    init(thinkspace: Thinkspace) {
        self.name = thinkspace.name
        self.emoji = thinkspace.emoji
        self.kind = thinkspace.kind ?? .custom
        self.enabledViews = thinkspace.enabledViews
        self.accentColorHex = thinkspace.accentColorHex ?? ThinkspaceManager.accentColorPalette[0]
        self.parentThinkspaceId = thinkspace.parentThinkspaceId
        self.linkedClientUUID = thinkspace.linkedClientUUID
    }

    /// Trims the name and lifts a leading emoji out of it into `emoji`
    /// (the identity law shared with capture lanes and library folders).
    func normalized() -> SpaceDraft {
        var copy = self
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = CollectionEmoji.resolve(name: trimmed, matchKeywords: false)
        if let leading = resolved.emoji, resolved.label != trimmed {
            copy.name = resolved.label
            if copy.emoji == nil { copy.emoji = leading }
        } else {
            copy.name = trimmed
        }
        if let emoji = copy.emoji?.trimmingCharacters(in: .whitespaces), emoji.isEmpty {
            copy.emoji = nil
        }
        var seen = Set<SpaceView>()
        copy.enabledViews = enabledViews.filter { seen.insert($0).inserted }
        return copy
    }

    func validate(canNest: (String) -> Bool) -> SpaceDraftValidation {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return SpaceDraftValidation(isValid: false, message: "Give the space a name.")
        }
        if enabledViews.isEmpty {
            return SpaceDraftValidation(isValid: false, message: "Keep at least one view.")
        }
        if let parent = parentThinkspaceId, !canNest(parent) {
            return SpaceDraftValidation(isValid: false, message: "That space can't contain this one.")
        }
        return SpaceDraftValidation(isValid: true, message: nil)
    }
}

struct SpaceDraftValidation: Equatable, Sendable {
    let isValid: Bool
    let message: String?
}
