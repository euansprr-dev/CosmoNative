// CosmoOS/Services/GoogleDrive/DriveExportBuilder.swift
// Turning finished sections into a file Drive will accept, and remembering
// where each one landed.
//
// The interesting decision here is how a draft becomes a *Google Doc*. Drive
// converts on ingest when the metadata mime type is
// `application/vnd.google-apps.document`, but only from a source format it
// understands — and the fidelity of the result is entirely down to what we
// send. Sending the raw draft as `text/plain` produces a Doc with literal
// `**asterisks**` in it, which is worse than useless.
//
// So we render Markdown to HTML ourselves rather than hoping Drive's Markdown
// support does what we want. It's a small renderer, it's deterministic, it's
// covered by tests, and it doesn't depend on a Google feature whose behaviour
// we can't pin down. Drafts that contain no Markdown at all pass through it
// unharmed — plain paragraphs are still plain paragraphs.
// July 2026

import Foundation

// MARK: - Format

enum DriveExportFormat: String, CaseIterable, Identifiable, Sendable {
    case googleDoc
    case markdown
    case plainText

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleDoc: return "Google Doc"
        case .markdown: return "Markdown"
        case .plainText: return "Plain Text"
        }
    }

    var icon: String {
        switch self {
        case .googleDoc: return "doc.richtext"
        case .markdown: return "chevron.left.forwardslash.chevron.right"
        case .plainText: return "doc.plaintext"
        }
    }

    /// What the file becomes in Drive.
    var targetMimeType: String {
        switch self {
        case .googleDoc: return GoogleDriveClient.googleDocMimeType
        case .markdown: return "text/markdown"
        case .plainText: return "text/plain"
        }
    }

    /// What we actually put on the wire.
    var sourceMimeType: String {
        switch self {
        case .googleDoc: return "text/html"
        case .markdown: return "text/markdown"
        case .plainText: return "text/plain"
        }
    }

    /// Native Google Docs carry no file extension.
    var fileExtension: String? {
        switch self {
        case .googleDoc: return nil
        case .markdown: return "md"
        case .plainText: return "txt"
        }
    }

    var explanation: String {
        switch self {
        case .googleDoc: return "Editable in Drive, with headings and formatting preserved."
        case .markdown: return "A .md file — the draft's source, unchanged."
        case .plainText: return "A .txt file with no formatting."
        }
    }
}

// MARK: - Builder

enum DriveExportBuilder {

    /// Build the upload payload for one platform's worth of sections.
    static func document(
        title: String,
        platform: ExportPlatform,
        sections: [ExportSection],
        format: DriveExportFormat,
        date: Date = Date()
    ) -> DriveUpload {
        let name = fileName(title: title, platform: platform, format: format, date: date)
        let body: String
        switch format {
        case .googleDoc:
            body = html(title: title, platform: platform, sections: sections)
        case .markdown:
            body = markdown(title: title, platform: platform, sections: sections)
        case .plainText:
            body = ContentExportFormatter.combined(sections)
        }
        return DriveUpload(
            name: name,
            targetMimeType: format.targetMimeType,
            sourceMimeType: format.sourceMimeType,
            data: Data(body.utf8)
        )
    }

    // MARK: - Naming

    static func fileName(
        title: String,
        platform: ExportPlatform,
        format: DriveExportFormat,
        date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let cleanTitle = sanitize(title).isEmpty ? "Untitled" : sanitize(title)
        let base = "\(cleanTitle) — \(platform.displayName) — \(formatter.string(from: date))"
        guard let ext = format.fileExtension else { return base }
        return "\(base).\(ext)"
    }

    /// Drive tolerates almost anything in a name, but a slash reads as a path
    /// separator in enough downstream tools (and in Drive's own export to
    /// disk) that stripping it is the kind thing to do.
    static func sanitize(_ name: String) -> String {
        let stripped = name.unicodeScalars
            .map { scalar -> Character in
                if CharacterSet.controlCharacters.contains(scalar) { return " " }
                if scalar == "/" || scalar == "\\" || scalar == ":" { return "-" }
                return Character(scalar)
            }
        let collapsed = String(stripped)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(120))
    }

    // MARK: - Markdown output

    static func markdown(title: String, platform: ExportPlatform, sections: [ExportSection]) -> String {
        var lines = ["# \(title.isEmpty ? "Untitled" : title)", "", "*\(platform.displayName)*", ""]
        // A single unlabelled section is just the draft — a "## Post" heading
        // above it would be noise in the file the user actually reads.
        if sections.count == 1 {
            lines.append(sections[0].text)
        } else {
            for section in sections {
                lines.append("## \(section.label)")
                lines.append("")
                lines.append(section.text)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: - HTML output (the Google Doc path)

    static func html(title: String, platform: ExportPlatform, sections: [ExportSection]) -> String {
        var body = ""
        body += "<h1>\(escape(title.isEmpty ? "Untitled" : title))</h1>\n"
        body += "<p><i>\(escape(platform.displayName))</i></p>\n"

        if sections.count == 1 {
            body += markdownToHTML(sections[0].text)
        } else {
            for section in sections {
                body += "<h2>\(escape(section.label))</h2>\n"
                body += markdownToHTML(section.text)
            }
        }

        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>\(escape(title.isEmpty ? "Untitled" : title))</title></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// A deliberately small Markdown subset: headings, bullet and numbered
    /// lists, blockquotes, horizontal rules, and the inline four (code, links,
    /// bold, italic). Anything it doesn't recognise survives as paragraph text,
    /// which is the correct failure mode for a draft that was never Markdown
    /// to begin with.
    static func markdownToHTML(_ text: String) -> String {
        var output = ""
        var paragraph: [String] = []
        var listKind: String?

        func closeParagraph() {
            guard !paragraph.isEmpty else { return }
            output += "<p>\(paragraph.joined(separator: "<br>\n"))</p>\n"
            paragraph = []
        }
        func closeList() {
            guard let kind = listKind else { return }
            output += "</\(kind)>\n"
            listKind = nil
        }
        func openList(_ kind: String) {
            if listKind != kind {
                closeList()
                output += "<\(kind)>\n"
                listKind = kind
            }
        }

        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                closeParagraph()
                closeList()
                continue
            }

            if let (level, content) = heading(in: line) {
                closeParagraph(); closeList()
                output += "<h\(level)>\(inline(content))</h\(level)>\n"
                continue
            }

            if isHorizontalRule(line) {
                closeParagraph(); closeList()
                output += "<hr>\n"
                continue
            }

            if let content = bulletContent(in: line) {
                closeParagraph()
                openList("ul")
                output += "<li>\(inline(content))</li>\n"
                continue
            }

            if let content = numberedContent(in: line) {
                closeParagraph()
                openList("ol")
                output += "<li>\(inline(content))</li>\n"
                continue
            }

            if line.hasPrefix(">") {
                closeParagraph(); closeList()
                let content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                output += "<blockquote>\(inline(content))</blockquote>\n"
                continue
            }

            closeList()
            paragraph.append(inline(line))
        }

        closeParagraph()
        closeList()
        return output
    }

    // MARK: Block helpers

    private static func heading(in line: String) -> (Int, String)? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", level < 6 {
            level += 1
            index = line.index(after: index)
        }
        guard level > 0, index < line.endIndex, line[index] == " " else { return nil }
        let content = String(line[index...]).trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : (level, content)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        return line.allSatisfy { $0 == "-" } || line.allSatisfy { $0 == "*" } || line.allSatisfy { $0 == "_" }
    }

    private static func bulletContent(in line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedContent(in line: String) -> String? {
        var digits = ""
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard !digits.isEmpty, index < line.endIndex, line[index] == "." else { return nil }
        index = line.index(after: index)
        guard index < line.endIndex, line[index] == " " else { return nil }
        return String(line[index...]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Inline helpers

    /// Escape first, then apply inline formatting. Doing it the other way round
    /// would let a draft containing `<b>` inject real markup into the Doc.
    /// Code spans go before links so a backticked URL stays literal.
    static func inline(_ text: String) -> String {
        var result = escape(text)
        result = replace(result, pattern: "`([^`]+)`", template: "<code>$1</code>")
        result = replace(result, pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#, template: "<a href=\"$2\">$1</a>")
        result = replace(result, pattern: #"\*\*([^*]+)\*\*"#, template: "<b>$1</b>")
        result = replace(result, pattern: #"(?<![*\w])\*([^*\n]+)\*(?![*\w])"#, template: "<i>$1</i>")
        result = replace(result, pattern: #"(?<![_\w])_([^_\n]+)_(?![_\w])"#, template: "<i>$1</i>")
        return result
    }

    private static func replace(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

// MARK: - Export Ledger

/// Where a given draft last landed in Drive, so a re-export updates the same
/// document instead of littering the folder with dated duplicates.
///
/// This is a local convenience cache, not a source of truth: UserDefaults, not
/// the database, and never synced. Losing it costs one duplicate file, which is
/// why it doesn't warrant a schema change. Drive itself remains authoritative —
/// every read is re-validated against the live file before it's used.
struct DriveExportRecord: Codable, Sendable, Equatable {
    var fileID: String
    var fileName: String
    var webViewLink: String?
    var exportedAt: Date
}

@MainActor
final class DriveExportLedger {
    static let shared = DriveExportLedger()

    private let defaultsKey = "googleDriveExportLedger"
    private let entryCap = 500
    private var entries: [String: DriveExportRecord]

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: DriveExportRecord].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    /// Pure key derivation — no state, so it needn't be main-actor bound.
    nonisolated static func key(
        atomUUID: String,
        platform: ExportPlatform,
        format: DriveExportFormat
    ) -> String {
        "\(atomUUID)|\(platform.rawValue)|\(format.rawValue)"
    }

    func record(atomUUID: String, platform: ExportPlatform, format: DriveExportFormat) -> DriveExportRecord? {
        entries[Self.key(atomUUID: atomUUID, platform: platform, format: format)]
    }

    func store(
        _ record: DriveExportRecord,
        atomUUID: String,
        platform: ExportPlatform,
        format: DriveExportFormat
    ) {
        entries[Self.key(atomUUID: atomUUID, platform: platform, format: format)] = record
        pruneIfNeeded()
        persist()
    }

    func forget(atomUUID: String, platform: ExportPlatform, format: DriveExportFormat) {
        entries.removeValue(forKey: Self.key(atomUUID: atomUUID, platform: platform, format: format))
        persist()
    }

    /// Disconnecting an account invalidates every file ID we know about — they
    /// belonged to that Drive, not this one.
    func clear() {
        entries = [:]
        persist()
    }

    private func pruneIfNeeded() {
        guard entries.count > entryCap else { return }
        let survivors = entries
            .sorted { $0.value.exportedAt > $1.value.exportedAt }
            .prefix(entryCap)
        entries = Dictionary(uniqueKeysWithValues: survivors.map { ($0.key, $0.value) })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
