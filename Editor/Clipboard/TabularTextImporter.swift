// TWIN FILE — byte-identical in CosmoOS-Swift/Editor/Clipboard and
// CosmoOS-iOS/CosmoCoreKit/Sources/Models. Verified by Tools/verify_twins.sh.
//
// Plain text that is secretly a table: Markdown pipe tables, TSV (Sheets,
// Numbers, Excel and Google Docs all put tab-separated cells in the plain
// flavour), and CSV. Prose is never mistaken for a table.

import Foundation

public enum TabularTextImporter {
    /// The first tabular shape that matches, or nil for ordinary text.
    public static func table(fromPlainText text: String) -> RichTable? {
        if let table = pipeTable(from: text) { return table }
        if let grid = tsvGrid(from: text) {
            return RichTable(strings: grid, hasHeaderRow: grid.count > 1)
        }
        if let grid = csvGrid(from: text) {
            return RichTable(strings: grid, hasHeaderRow: grid.count > 1)
        }
        return nil
    }

    /// Raw cells for a cell-fill paste (no header inference).
    public static func grid(fromPlainText text: String) -> [[String]]? {
        if let table = pipeTable(from: text) {
            return table.rows.map { $0.cells.map(\.plainText) }
        }
        return tsvGrid(from: text) ?? csvGrid(from: text)
    }

    // MARK: Markdown pipe tables

    private static let separatorPattern = #"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$"#

    static func isSeparatorLine(_ line: String) -> Bool {
        line.range(of: separatorPattern, options: .regularExpression) != nil && line.contains("-")
    }

    static func pipeTable(from text: String) -> RichTable? {
        let lines = normalisedLines(text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2, lines[0].contains("|"), isSeparatorLine(lines[1]) else { return nil }
        let headerCells = splitPipeRow(lines[0])
        let alignments = splitPipeRow(lines[1]).map { marker -> RichTableAlignment in
            let trimmed = marker.trimmingCharacters(in: .whitespaces)
            let left = trimmed.hasPrefix(":")
            let right = trimmed.hasSuffix(":")
            if left && right { return .center }
            if right { return .trailing }
            return .leading
        }
        let columnCount = max(headerCells.count, alignments.count, 1)
        var rows: [[String]] = [headerCells]
        for line in lines.dropFirst(2) {
            guard line.contains("|") else { break }
            rows.append(splitPipeRow(line))
        }
        var table = RichTable(strings: rows.map { row in
            var cells = row
            while cells.count < columnCount { cells.append("") }
            return Array(cells.prefix(columnCount))
        }, hasHeaderRow: true)
        for (index, alignment) in alignments.enumerated() where table.columns.indices.contains(index) {
            table.columns[index].alignment = alignment
        }
        for rowIndex in table.rows.indices {
            for columnIndex in table.rows[rowIndex].cells.indices {
                let raw = table.rows[rowIndex].cells[columnIndex].plainText
                let decoded = raw
                    .replacingOccurrences(of: "<br>", with: "\u{2028}")
                    .replacingOccurrences(of: "<br/>", with: "\u{2028}")
                    .replacingOccurrences(of: "<br />", with: "\u{2028}")
                    .replacingOccurrences(of: "\\|", with: "|")
                if decoded != raw {
                    table.rows[rowIndex].cells[columnIndex].inlines = decoded.isEmpty ? [] : [.text(decoded)]
                }
            }
        }
        return table
    }

    /// Splits a `| a | b |` row on unescaped pipes, trimming the outer bars.
    static func splitPipeRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in line {
            if escaped {
                current.append(character == "|" ? "\\|" : "\\\(character)")
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "|" {
                cells.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        cells.append(current)
        var trimmed = cells.map { $0.trimmingCharacters(in: .whitespaces) }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("|"), !trimmed.isEmpty { trimmed.removeFirst() }
        if line.trimmingCharacters(in: .whitespaces).hasSuffix("|"), !trimmed.isEmpty, trimmed.last?.isEmpty == true { trimmed.removeLast() }
        return trimmed
    }

    // MARK: TSV

    static func tsvGrid(from text: String) -> [[String]]? {
        let lines = normalisedLines(text)
        let content = lines.filter { !$0.isEmpty }
        guard content.count >= 2 else { return nil }
        let tabCounts = content.map { $0.filter { $0 == "\t" }.count }
        guard let count = tabCounts.first, count >= 1, tabCounts.allSatisfy({ $0 == count }) else { return nil }
        return content.map { $0.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    // MARK: CSV (RFC 4180)

    static func csvGrid(from text: String) -> [[String]]? {
        guard !text.contains("\t") else { return nil }
        let records = parseCSVRecords(text).filter { !($0.count == 1 && $0[0].isEmpty) }
        guard records.count >= 2 else { return nil }
        let widths = Set(records.map(\.count))
        guard widths.count == 1, let width = widths.first, width >= 2 else { return nil }
        // Prose guard: long fields or sentence punctuation mean paragraphs.
        for record in records {
            for field in record {
                if field.count > 80 { return nil }
                if field.range(of: #"\. [A-Z]"#, options: .regularExpression) != nil { return nil }
            }
        }
        return records
    }

    static func parseCSVRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }
        while let character = next() {
            if inQuotes {
                if character == "\"" {
                    if let following = next() {
                        if following == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = following
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                inQuotes = true
            case ",":
                record.append(field)
                field = ""
            case "\r":
                continue
            case "\n":
                record.append(field)
                records.append(record)
                record = []
                field = ""
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    // MARK: Helpers

    static func normalisedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }
}
