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
    func insertText(_ text: String, at position: InsertPosition = .cursor) {
        NotificationCenter.default.post(
            name: .insertTextInEditor,
            object: nil,
            userInfo: [
                "text": text,
                "position": position.rawValue
            ]
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

enum FormattingType: String {
    case bold
    case italic
    case strikethrough
    case heading1
    case heading2
    case bulletList
}

// MARK: - Notification Names
extension Notification.Name {
    static let insertTextInEditor = Notification.Name("com.cosmo.insertTextInEditor")
    static let toggleEditorFormatting = Notification.Name("com.cosmo.toggleEditorFormatting")
    // Re-declare internal ones here if needed, or rely on TextKitCoordinator's own
    static let insertMentionInEditor = Notification.Name("insertMentionInEditor") 
}

