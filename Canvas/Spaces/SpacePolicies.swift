// CosmoOS/Canvas/Spaces/SpacePolicies.swift
// Pure decision tables for the space shell — testable without a window.

import AppKit

// MARK: - ⌘1…⌘n → view index

/// Mirrors `CanvasKeyboardShortcutPolicy`: the gates are explicit inputs so
/// the table can be pinned by tests. Exactly ⌘ (no ⇧/⌥/⌃) — ⌘⌥digit is a
/// Place jump, ⌘⌃digit is a pane, ⌃digit is a workbench.
enum SpaceKeyboardShortcutPolicy {
    static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6]

    static func viewIndex(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        enabledCount: Int,
        isThinkspaceActive: Bool,
        hasFocusedEntity: Bool,
        isCommandKVisible: Bool,
        isTextInputFocused: Bool
    ) -> Int? {
        guard isThinkspaceActive, !hasFocusedEntity, !isCommandKVisible, !isTextInputFocused else {
            return nil
        }
        let relevant = modifiers.intersection([.command, .shift, .option, .control])
        guard relevant == [.command] else { return nil }
        guard let digit = digitKeyCodes[keyCode], digit <= enabledCount else { return nil }
        return digit - 1
    }
}

// MARK: - Deep Dive → its space

/// A deep dive opens INSIDE its home space's Deep Dive view when it is that
/// space's profile and the space can show the view. Secondary dives parented
/// to a space (a space can host many) keep the focus overlay — otherwise a
/// portal block for dive B would land you on profile A.
enum SpaceDeepDiveRoutingPolicy {
    struct Redirect: Equatable {
        let thinkspaceId: String
    }

    static func spaceRedirect(
        deepDiveUUID: String,
        primaryThinkspaceUUID: String?,
        thinkspaces: [Thinkspace]
    ) -> Redirect? {
        // 1. The space whose recorded profile is this dive.
        if let owner = thinkspaces.first(where: { $0.deepDiveProfileUUID == deepDiveUUID }) {
            return owner.renderableViews.contains(.deepDive) ? Redirect(thinkspaceId: owner.id) : nil
        }
        // 2. No profile recorded yet: the dive's own primary home counts,
        //    but only while that space has not adopted a DIFFERENT profile.
        if let primary = primaryThinkspaceUUID,
           let home = thinkspaces.first(where: { $0.id == primary }),
           home.deepDiveProfileUUID == nil,
           home.renderableViews.contains(.deepDive) {
            return Redirect(thinkspaceId: home.id)
        }
        return nil
    }

    static func spaceRedirect(for atom: Atom, thinkspaces: [Thinkspace]) -> Redirect? {
        guard atom.type == .deepDive else { return nil }
        let metadata = atom.deepDiveMetadata
        return spaceRedirect(
            deepDiveUUID: atom.uuid,
            primaryThinkspaceUUID: metadata?.primaryThinkspaceUUID ?? metadata?.parentThinkspaceUUIDs?.first,
            thinkspaces: thinkspaces
        )
    }
}
