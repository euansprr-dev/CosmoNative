// CosmoOS/AI/WritingAIModels.swift
// The Content Focus "ask Cosmo" scope — routes the global ⌥A shortcut and the
// slash-menu Writing AI command to the active content workspace, which opens
// the ONE inline assistant pane scoped to its draft.
//
// The old Writing AI card system (WritingAICardView, ContentWritingAssistant,
// WritingAIContextBuilder and their request/response models) was removed in
// July 2026 — the inline assistant is the single writing collaborator.

import Foundation

extension Notification.Name {
    static let contentFocusOpenWritingAI = Notification.Name("contentFocusOpenWritingAI")
}

@MainActor
final class ContentFocusWritingAIScope {
    static let shared = ContentFocusWritingAIScope()

    private var activeAtomUUID: String?
    private var openHandler: (() -> Void)?

    private init() {}

    func activate(atomUUID: String, openHandler: @escaping () -> Void) {
        activeAtomUUID = atomUUID
        self.openHandler = openHandler
    }

    func deactivate(atomUUID: String) {
        guard activeAtomUUID == atomUUID else { return }
        activeAtomUUID = nil
        openHandler = nil
    }

    @discardableResult
    func tryOpen() -> Bool {
        guard let openHandler else { return false }
        openHandler()
        return true
    }
}
