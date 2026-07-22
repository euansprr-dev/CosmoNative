// CosmoOS/AI/ConceptNoteMerge.swift
// Drop a note/sticky onto a concept → the collaborator sorts its content
// into the board as staged bullets the user reviews (July 2026).
//
// The canvas (or an open workspace's board) detects the drop, the user
// confirms on the drop card, and the handoff stashes here. When the concept's
// focus mode appears (or immediately, if the workspace is already open), it
// consumes the handoff: opens the assistant pane scoped to the concept and
// submits the composed /concept message. Everything downstream is the
// EXISTING staging grammar — ghost rows per section, per-op ✓/✗, nothing
// lands without approval. The note itself is never modified.

import Foundation

// MARK: - Handoff

/// One-shot bridge between the drop gesture and the concept focus mode —
/// the same stash/consume contract as ConnectionFocusDeepLink (the open
/// notification fires before the focus view exists, so userInfo can't
/// reach it).
@MainActor
enum ConceptMergeHandoff {
    private static var pending: (conceptUUID: String, noteUUID: String)?

    static func stash(conceptUUID: String, noteUUID: String) {
        pending = (conceptUUID, noteUUID)
    }

    static func consume(for conceptUUID: String) -> String? {
        guard let pending, pending.conceptUUID == conceptUUID else { return nil }
        self.pending = nil
        return pending.noteUUID
    }
}

// MARK: - Message composer

enum ConceptNoteMergeComposer {

    /// Body text beyond this rides a truncation marker — the collaborator
    /// works from the substance, not an unbounded dump.
    static let bodyCharacterCap = 6000

    /// True for the atom types the merge-drop accepts.
    static func isMergeableSource(_ type: AtomType) -> Bool {
        type == .note || type == .stickyNote
    }

    /// The /concept message the drop submits. Concrete instructions over
    /// vague verbs: sort, organize-not-author, skip duplicates, one receipt
    /// line, one question.
    static func mergeMessage(noteTitle: String?, noteBody: String, sourceKind: AtomType) -> String {
        let kindWord = sourceKind == .stickyNote ? "sticky note" : "note"
        let title = noteTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let heading = title.isEmpty ? kindWord.uppercased() : "\(kindWord.uppercased()) — \(title)"

        var body = noteBody
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if body.count > bodyCharacterCap {
            body = String(body.prefix(bodyCharacterCap)) + "\n[…note truncated for length]"
        }

        return """
        /concept I dropped a \(kindWord) onto this board. Merge its content in: \
        read every distinct point in the \(kindWord) below and stage each one \
        into the section where it belongs (organize and tighten my wording, \
        split multi-point passages into separate bullets, never add a claim or \
        example I didn't write). Skip anything the board already says. After \
        staging, tell me in one line what you placed where, then ask ONE \
        question about the most important thing the \(kindWord) leaves \
        unresolved.

        \(heading):
        \(body)
        """
    }

    /// Everything the drop needs from the note atom, resolved in one place.
    /// nil when the note has nothing mergeable (empty body AND empty title —
    /// the drop card never shows for those).
    static func mergePayload(from note: Atom) -> (message: String, displayTitle: String)? {
        guard isMergeableSource(note.type) else { return nil }
        let body = (note.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (note.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !title.isEmpty else { return nil }
        let effectiveBody = body.isEmpty ? title : body
        return (
            message: mergeMessage(noteTitle: title.isEmpty ? nil : title, noteBody: effectiveBody, sourceKind: note.type),
            displayTitle: title.isEmpty
                ? (note.type == .stickyNote ? "Sticky note" : "Untitled note")
                : title
        )
    }
}

// MARK: - Merge launcher

/// Starts the collaborator merge for a note into a concept whose surface is
/// (or is about to be) registered. Links the note as a source first so the
/// Sources rail carries the provenance.
@MainActor
enum ConceptNoteMergeLauncher {

    /// Called by the concept focus mode once its context provider is live —
    /// and by the open workspace directly on a board drop.
    static func begin(noteUUID: String, conceptUUID: String) async {
        guard let note = try? await AtomRepository.shared.fetch(uuid: noteUUID),
              !note.isDeleted,
              let payload = ConceptNoteMergeComposer.mergePayload(from: note) else { return }

        // Provenance: the note joins the Sources rail like any cited material.
        await ConceptMediaAttachService.writeGraphEdge(source: note, conceptUUID: conceptUUID)

        let surfaceID = "connection:\(conceptUUID)"
        let store = CosmoInlineAssistantStore.shared
        store.openPane(forSurfaceID: surfaceID)
        store.submitPrompt(payload.message, forSurfaceID: surfaceID)
    }
}
