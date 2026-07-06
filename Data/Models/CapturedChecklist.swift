// CosmoOS/Data/Models/CapturedChecklist.swift
// The checkbox grammar of captured text — one vocabulary from ink to atom.
// Handwriting transcription and typed captures may carry checkboxes as
// markdown (`- [ ]` / `- [x]`) or note glyphs (`☐ ` / `☑ `); this normalizes
// everything to the glyph form the note editor already renders as REAL
// checklist blocks (RichDocument.migrateLegacy), extracts items for task
// subtasks (ChecklistItem), and toggles a line in place for the capture
// field's tap-to-check.
//
// PARITY: keep in lockstep with CosmoOS-iOS/CosmoCoreKit/Sources/Models/CapturedChecklist.swift.

import Foundation

public enum CapturedChecklist {

    public static let uncheckedGlyph = "☐"
    public static let checkedGlyph = "☑"

    /// One checkbox line, extracted.
    public struct Item: Equatable, Sendable {
        public let title: String
        public let checked: Bool

        public init(title: String, checked: Bool) {
            self.title = title
            self.checked = checked
        }
    }

    // MARK: - Line recognition

    /// `- [ ] milk`, `* [x] eggs`, `[ ] scallions`, `☐ bread`, `☑ done` —
    /// returns (checked, title) when the line is a checkbox line.
    static func parseLine(_ line: Substring) -> (checked: Bool, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Glyph form (already normalized).
        if trimmed.hasPrefix("\(uncheckedGlyph) ") || trimmed == uncheckedGlyph {
            return (false, String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))
        }
        if trimmed.hasPrefix("\(checkedGlyph) ") || trimmed == checkedGlyph {
            return (true, String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))
        }

        // Markdown form: optional list bullet, then [ ] / [x] / [X].
        var rest = trimmed
        for bullet in ["- ", "* ", "+ "] where rest.hasPrefix(bullet) {
            rest = String(rest.dropFirst(bullet.count))
            break
        }
        guard rest.hasPrefix("[") else { return nil }
        let lower = rest.lowercased()
        if lower.hasPrefix("[ ]") || lower.hasPrefix("[]") {
            let markerLength = lower.hasPrefix("[ ]") ? 3 : 2
            return (false, String(rest.dropFirst(markerLength)).trimmingCharacters(in: .whitespaces))
        }
        if lower.hasPrefix("[x]") {
            return (true, String(rest.dropFirst(3)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    // MARK: - Normalization (markdown → note glyphs)

    /// Rewrite every checkbox line to the glyph form (`☐ item` / `☑ item`).
    /// Non-checkbox lines pass through byte-for-byte; returns the input
    /// unchanged (same instance) when nothing needed rewriting.
    public static func normalizeGlyphs(_ text: String) -> String {
        guard text.contains("[") || text.contains(uncheckedGlyph) || text.contains(checkedGlyph) else { return text }
        var changed = false
        let lines = text.components(separatedBy: "\n").map { line -> String in
            guard let parsed = parseLine(Substring(line)) else { return line }
            let glyphLine = "\(parsed.checked ? checkedGlyph : uncheckedGlyph) \(parsed.title)"
            if glyphLine != line { changed = true }
            return glyphLine
        }
        return changed ? lines.joined(separator: "\n") : text
    }

    // MARK: - Extraction

    public static func items(in text: String) -> [Item] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line in
                guard let parsed = parseLine(line), !parsed.title.isEmpty else { return nil }
                return Item(title: parsed.title, checked: parsed.checked)
            }
    }

    public static func containsItems(_ text: String) -> Bool {
        text.split(separator: "\n").contains { parseLine($0) != nil }
    }

    /// The text with its checkbox lines removed — what remains is prose
    /// (a task's notes, a title candidate).
    public static func strippingItems(from text: String) -> String {
        text.components(separatedBy: "\n")
            .filter { parseLine(Substring($0)) == nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Task payload (checkboxes → Things-style subtasks)

    /// How a checkbox-bearing capture becomes a task: prose becomes the
    /// title (first line) and notes, checkbox lines become the subtask list.
    /// nil when the text has no checkboxes — plain captures keep their flow.
    public struct TaskPayload: Sendable {
        public let title: String
        public let notes: String
        public let checklist: [ChecklistItem]
    }

    public static func taskPayload(from text: String) -> TaskPayload? {
        let extracted = items(in: text)
        guard !extracted.isEmpty else { return nil }

        let prose = strippingItems(from: text)
        let proseLines = prose.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // A pure checklist page still needs a task name — the first item
        // graduates to the title and the rest stay subtasks.
        let title: String
        var checklistItems = extracted
        var notes: String
        if let firstProse = proseLines.first {
            title = firstProse
            notes = proseLines.dropFirst().joined(separator: "\n")
        } else {
            title = checklistItems.removeFirst().title
            notes = ""
        }
        if checklistItems.isEmpty, let promoted = extracted.first {
            // Single-item capture with no prose: the item IS the task.
            return TaskPayload(title: promoted.title, notes: "", checklist: [])
        }

        return TaskPayload(
            title: title,
            notes: notes,
            checklist: checklistItems.enumerated().map { index, item in
                ChecklistItem(title: item.title, isCompleted: item.checked, sortOrder: index)
            }
        )
    }

    /// Encode a checklist for TaskMetadata.checklist (a JSON-array string).
    public static func checklistJSON(_ items: [ChecklistItem]) -> String? {
        guard !items.isEmpty, let data = try? JSONEncoder().encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Tap-to-toggle (the capture field's checkmark UI)

    /// Toggle the checkbox on the line containing `utf16Offset`, but only
    /// when the tap landed ON the box itself (the line's leading glyph) —
    /// taps in the item's words keep normal text editing. Returns the
    /// rewritten text, or nil when the tap wasn't a checkbox hit.
    public static func togglingCheckbox(atUTF16Offset utf16Offset: Int, in text: String) -> String? {
        let nsText = text as NSString
        guard utf16Offset >= 0, utf16Offset <= nsText.length else { return nil }
        let lineRange = nsText.lineRange(for: NSRange(location: min(utf16Offset, max(0, nsText.length - 1)), length: 0))
        let line = nsText.substring(with: lineRange)
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        let isChecked: Bool
        if trimmedLine.hasPrefix(checkedGlyph) {
            isChecked = true
        } else if trimmedLine.hasPrefix(uncheckedGlyph) {
            isChecked = false
        } else {
            return nil
        }

        // The box is the line's first glyph — accept the glyph and the space
        // after it (a comfortable target without hijacking word taps).
        let leadingWhitespace = line.prefix(while: { $0 == " " || $0 == "\t" }).utf16.count
        let glyphStart = lineRange.location + leadingWhitespace
        guard utf16Offset >= glyphStart, utf16Offset <= glyphStart + 2 else { return nil }

        let newGlyph = isChecked ? uncheckedGlyph : checkedGlyph
        let glyphRange = NSRange(location: glyphStart, length: 1)
        return nsText.replacingCharacters(in: glyphRange, with: newGlyph)
    }
}
