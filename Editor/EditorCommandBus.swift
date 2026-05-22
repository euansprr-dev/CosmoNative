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
    // Re-declare internal ones here if needed, or rely on TextKitCoordinator's own
    static let insertMentionInEditor = Notification.Name("insertMentionInEditor") 
}
