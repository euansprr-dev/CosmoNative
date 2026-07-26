// CosmoOS/AI/ConceptNoteMerge.swift
// Drop a note/sticky/content piece onto a concept → the collaborator sorts
// its content into the board as staged bullets the user reviews (July 2026).
//
// The canvas (or an open workspace's board) detects the drop, the user
// confirms on the drop card, and the handoff stashes here. When the concept's
// focus mode appears (or immediately, if the workspace is already open), it
// consumes the handoff: opens the assistant pane scoped to the concept and
// submits the composed /concept message. Everything downstream is the
// EXISTING staging grammar — ghost rows per section, per-op ✓/✗, nothing
// lands without approval. The source itself is never modified.

import Foundation

// MARK: - Source snapshot

/// Everything the drop knows about the dragged source at drop time.
/// Canvas stickies (and note/content blocks created without a backing atom)
/// are canvas-only — entity_id = -1, text lives on the canvas_blocks row —
/// so an atom fetch alone can NEVER be the merge's only source of truth.
struct ConceptMergeSourceSnapshot: Equatable {
    let uuid: String
    let kind: AtomType
    /// Raw title (nil when empty), not the card's display fallback.
    let title: String?
    /// The block's inline text (metadata["content"]) captured at drop time —
    /// the only body a canvas-only sticky has.
    let inlineBody: String?

    init(uuid: String, kind: AtomType, title: String?, inlineBody: String?) {
        self.uuid = uuid
        self.kind = kind
        self.title = title
        self.inlineBody = inlineBody
    }

    /// Builds the snapshot from a canvas block, or nil when the block can't
    /// offer a merge: wrong type, no uuid, or canvas-only (entityId <= 0)
    /// with nothing to merge — the drop card must never promise a merge the
    /// launcher can't run.
    init?(block: CanvasBlock) {
        let kind: AtomType
        switch block.entityType {
        case .note: kind = .note
        case .stickyNote: kind = .stickyNote
        case .content: kind = .content
        default: return nil
        }
        guard !block.entityUuid.isEmpty else { return nil }
        let inline = (block.metadata["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAtomBacked = block.entityId > 0
        guard isAtomBacked || !inline.isEmpty || !title.isEmpty else { return nil }
        self.init(
            uuid: block.entityUuid,
            kind: kind,
            title: title.isEmpty ? nil : title,
            inlineBody: inline.isEmpty ? nil : inline
        )
    }
}

// MARK: - Handoff

/// One-shot bridge between the drop gesture and the concept focus mode —
/// the same stash/consume contract as ConnectionFocusDeepLink (the open
/// notification fires before the focus view exists, so userInfo can't
/// reach it).
@MainActor
enum ConceptMergeHandoff {
    private static var pending: (conceptUUID: String, source: ConceptMergeSourceSnapshot)?

    static func stash(conceptUUID: String, source: ConceptMergeSourceSnapshot) {
        pending = (conceptUUID, source)
    }

    static func consume(for conceptUUID: String) -> ConceptMergeSourceSnapshot? {
        guard let pending, pending.conceptUUID == conceptUUID else { return nil }
        self.pending = nil
        return pending.source
    }
}

// MARK: - Message composer

enum ConceptNoteMergeComposer {

    /// Body text beyond this rides a truncation marker — the collaborator
    /// works from the substance, not an unbounded dump.
    static let bodyCharacterCap = 6000

    /// True for the atom types the merge-drop accepts.
    static func isMergeableSource(_ type: AtomType) -> Bool {
        type == .note || type == .stickyNote || type == .content
    }

    /// The human word for the source in card copy and the /concept message.
    static func kindWord(for type: AtomType) -> String {
        switch type {
        case .stickyNote: return "sticky note"
        case .content: return "content piece"
        default: return "note"
        }
    }

    static func untitledFallback(for type: AtomType) -> String {
        switch type {
        case .stickyNote: return "Sticky note"
        case .content: return "Untitled content"
        default: return "Untitled note"
        }
    }

    /// The /concept message the drop submits. Concrete instructions over
    /// vague verbs: sort, organize-not-author, skip duplicates, one receipt
    /// line, one question.
    static func mergeMessage(noteTitle: String?, noteBody: String, sourceKind: AtomType) -> String {
        let kindWord = kindWord(for: sourceKind)
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

    /// Everything the drop needs from the source atom, resolved in one place.
    /// nil when the atom has nothing mergeable (empty body AND empty title).
    static func mergePayload(from note: Atom) -> (message: String, displayTitle: String)? {
        guard isMergeableSource(note.type) else { return nil }
        return mergePayload(
            title: note.title,
            body: note.body,
            kind: note.type
        )
    }

    /// Payload from a drop-time snapshot — the ONLY path for canvas-only
    /// stickies, whose text never reaches the atoms table.
    static func mergePayload(from snapshot: ConceptMergeSourceSnapshot) -> (message: String, displayTitle: String)? {
        guard isMergeableSource(snapshot.kind) else { return nil }
        return mergePayload(
            title: snapshot.title,
            body: snapshot.inlineBody,
            kind: snapshot.kind
        )
    }

    private static func mergePayload(
        title rawTitle: String?,
        body rawBody: String?,
        kind: AtomType
    ) -> (message: String, displayTitle: String)? {
        let body = (rawBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (rawTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !title.isEmpty else { return nil }
        let effectiveBody = body.isEmpty ? title : body
        return (
            message: mergeMessage(
                noteTitle: title.isEmpty ? nil : title,
                noteBody: effectiveBody,
                sourceKind: kind
            ),
            displayTitle: title.isEmpty ? untitledFallback(for: kind) : title
        )
    }
}

// MARK: - Merge launcher

/// Starts the collaborator merge for a source into a concept whose surface is
/// (or is about to be) registered. Links the source as provenance first so
/// the Sources rail carries it — atom-backed sources only; a canvas-only
/// sticky has no atom row to link.
@MainActor
enum ConceptNoteMergeLauncher {

    /// Called by the concept focus mode once its context provider is live —
    /// and by the open workspace directly on a board drop.
    static func begin(source: ConceptMergeSourceSnapshot, conceptUUID: String) async {
        // The live atom wins when one exists (fresher body than the block's
        // mirror, plus provenance). The snapshot is the full fallback, not a
        // nice-to-have: canvas stickies have NO atom behind them.
        var payload: (message: String, displayTitle: String)?
        var provenanceAtom: Atom?
        if let atom = try? await AtomRepository.shared.fetch(uuid: source.uuid), !atom.isDeleted {
            payload = ConceptNoteMergeComposer.mergePayload(from: atom)
            provenanceAtom = atom
        }
        if payload == nil {
            payload = ConceptNoteMergeComposer.mergePayload(from: source)
        }
        guard let payload else { return }

        if let provenanceAtom {
            // Provenance: the source joins the Sources rail like any cited
            // material.
            await ConceptMediaAttachService.writeGraphEdge(source: provenanceAtom, conceptUUID: conceptUUID)
        }

        let surfaceID = "connection:\(conceptUUID)"
        let store = CosmoInlineAssistantStore.shared
        store.openPane(forSurfaceID: surfaceID)
        store.submitPrompt(payload.message, forSurfaceID: surfaceID)
    }
}
