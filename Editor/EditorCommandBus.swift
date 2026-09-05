// CosmoOS/Editor/EditorCommandBus.swift
// Lightweight command bus for cross-surface editor actions.
// Keeps focus mode / canvas UI decoupled from TextKit implementation details.

import Foundation

@MainActor
final class EditorCommandBus: ObservableObject {
    static let shared = EditorCommandBus()
    private init() {}

    /// Insert an @mention at the current cursor position
    func insertMention(entityType: EntityType, entityId: Int64, title: String) {
        NotificationCenter.default.post(
            name: .insertMentionInEditor,
            object: nil,
            userInfo: [
                "entityType": entityType.rawValue,
                "entityId": entityId,
                "title": title
            ]
        )
    }

    /// Insert plain text at the current cursor position
    func insertText(
        _ text: String,
        at position: InsertPosition = .cursor,
        targetEditorID: String? = nil,
        allowInactive: Bool = false
    ) {
        NotificationCenter.default.post(
            name: .insertTextInEditor,
            object: nil,
            userInfo: EditorCommandPayload.insertText(
                text,
                position: position,
                targetEditorID: targetEditorID,
                allowInactive: allowInactive
            )
        )
    }

    /// Replace the current editor selection with plain text.
    func replaceSelection(with text: String, targetEditorID: String? = nil, allowInactive: Bool = false) {
        NotificationCenter.default.post(
            name: .replaceSelectionInEditor,
            object: nil,
            userInfo: EditorCommandPayload.replaceSelection(
                text,
                targetEditorID: targetEditorID,
                allowInactive: allowInactive
            )
        )
    }

    /// Insert research findings as formatted text
    func insertResearchFindings(title: String, summary: String, findings: [(title: String, snippet: String?, source: String)]) {
        var text = "## Research: \(title)\n\n"
        text += summary + "\n\n"
        text += "### Findings\n\n"

        for (idx, finding) in findings.enumerated() {
            text += "\(idx + 1). **\(finding.title)**\n"
            if let snippet = finding.snippet {
                text += "   \(snippet)\n"
            }
            text += "   _Source: \(finding.source)_\n\n"
        }

        insertText(text, at: .cursor)
    }

    /// Position for text insertion
    enum InsertPosition: String {
        case cursor = "cursor"
        case endOfDocument = "end"
        case newParagraph = "newParagraph"
    }

    /// Toggle formatting for current selection
    func toggleFormatting(_ type: FormattingType) {
        NotificationCenter.default.post(
            name: .toggleEditorFormatting,
            object: nil,
            userInfo: ["type": type]
        )
    }

    // MARK: - Inline colour (ink / highlight / link)
    //
    // Contract with TextKitCoordinator: one `.applyEditorInlineStyle` post
    // carries EXACTLY ONE of the keys "ink" / "highlight" / "link" (a
    // NoteInkPalette tone id or a URL; "" clears) plus an optional
    // "targetEditorID". The coordinator applies it to the selection, or to
    // the typing attributes when the caret is collapsed.

    /// Colour the selection's text with a palette tone; nil restores the
    /// document ink. A chosen tone is remembered for the next session.
    func applyInk(_ toneID: String?, targetEditorID: String? = nil) {
        if let toneID, !toneID.isEmpty { InlineStyleMemory.shared.lastInkTone = toneID }
        postInlineStyle(key: "ink", value: toneID, targetEditorID: targetEditorID)
    }

    /// Wash the selection with a palette tone; nil removes the highlight.
    /// A chosen tone becomes what ⌘⇧H re-applies.
    func applyHighlight(_ toneID: String?, targetEditorID: String? = nil) {
        if let toneID, !toneID.isEmpty { InlineStyleMemory.shared.lastHighlightTone = toneID }
        postInlineStyle(key: "highlight", value: toneID, targetEditorID: targetEditorID)
    }

    /// Attach an http(s)/mailto link to the selection; nil removes it.
    func applyLink(_ url: String?, targetEditorID: String? = nil) {
        postInlineStyle(key: "link", value: url, targetEditorID: targetEditorID)
    }

    /// ⌘⇧H — posts the remembered highlight tone. Toggling is the
    /// coordinator's call: a selection already carrying that tone clears.
    func toggleLastHighlight(targetEditorID: String? = nil) {
        applyHighlight(InlineStyleMemory.shared.lastHighlightTone, targetEditorID: targetEditorID)
    }

    private func postInlineStyle(key: String, value: String?, targetEditorID: String?) {
        NotificationCenter.default.post(
            name: .applyEditorInlineStyle,
            object: nil,
            userInfo: EditorCommandPayload.inlineStyle(key: key, value: value, targetEditorID: targetEditorID)
        )
    }
}

/// The last-used inline colour tones — what ⌘⇧H re-applies and what the
/// quill bar's swatches pre-select. Persisted so the choice survives launches.
@MainActor
final class InlineStyleMemory {
    static let shared = InlineStyleMemory()

    static let highlightKey = "editor.lastHighlightTone"
    static let inkKey = "editor.lastInkTone"
    static let defaultHighlightTone = "gilt"
    static let defaultInkTone = "clay"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastHighlightTone: String {
        get { knownTone(defaults.string(forKey: Self.highlightKey)) ?? Self.defaultHighlightTone }
        set { store(newValue, forKey: Self.highlightKey) }
    }

    var lastInkTone: String {
        get { knownTone(defaults.string(forKey: Self.inkKey)) ?? Self.defaultInkTone }
        set { store(newValue, forKey: Self.inkKey) }
    }

    /// Unknown ids never persist — a stale or foreign tone would otherwise
    /// resolve to the palette's fallback and lie about what ⌘⇧H applies.
    private func store(_ toneID: String, forKey key: String) {
        guard RichInlineColor.isKnownTone(toneID) else { return }
        defaults.set(toneID, forKey: key)
    }

    private func knownTone(_ id: String?) -> String? {
        RichInlineColor.isKnownTone(id) ? id : nil
    }
}

enum EditorCommandTarget {
    static func noteBody(_ atomUUID: String) -> String {
        "note:\(atomUUID):body"
    }
}

enum EditorCommandPayload {
    static func insertText(
        _ text: String,
        position: EditorCommandBus.InsertPosition,
        targetEditorID: String? = nil,
        allowInactive: Bool = false
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "text": text,
            "position": position.rawValue,
            "allowInactive": allowInactive
        ]
        if let targetEditorID, !targetEditorID.isEmpty {
            payload["targetEditorID"] = targetEditorID
        }
        return payload
    }

    static func replaceSelection(
        _ text: String,
        targetEditorID: String? = nil,
        allowInactive: Bool = false
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "text": text,
            "allowInactive": allowInactive
        ]
        if let targetEditorID, !targetEditorID.isEmpty {
            payload["targetEditorID"] = targetEditorID
        }
        return payload
    }

    /// `.applyEditorInlineStyle` userInfo: exactly one of "ink" /
    /// "highlight" / "link" per post; nil becomes "" (clear/remove).
    static func inlineStyle(
        key: String,
        value: String?,
        targetEditorID: String? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [key: value ?? ""]
        if let targetEditorID, !targetEditorID.isEmpty {
            payload["targetEditorID"] = targetEditorID
        }
        return payload
    }
}

enum FormattingType: String {
    case bold
    case italic
    case underline
    case strikethrough
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case checklist
}

// MARK: - Notification Names
extension Notification.Name {
    static let insertTextInEditor = Notification.Name("com.cosmo.insertTextInEditor")
    static let replaceSelectionInEditor = Notification.Name("com.cosmo.replaceSelectionInEditor")
    static let toggleEditorFormatting = Notification.Name("com.cosmo.toggleEditorFormatting")
    /// Inline ink / highlight / link — see `EditorCommandBus.applyInk` for the
    /// userInfo contract the TextKit coordinator observes.
    static let applyEditorInlineStyle = Notification.Name("ApplyEditorInlineStyle")
    // Re-declare internal ones here if needed, or rely on TextKitCoordinator's own
    static let insertMentionInEditor = Notification.Name("insertMentionInEditor") 
}
