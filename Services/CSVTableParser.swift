// CosmoOS/Services/CSVTableParser.swift
// RFC 4180 CSV/TSV parsing for spreadsheet portals. Streaming state machine —
// quoted fields may contain delimiters, escaped quotes ("") and newlines;
// CRLF/CR/LF all terminate records; ragged rows are preserved (SheetModel
// pads them). Pure functions, unit-tested in CSVTableParserTests.

import Foundation

enum CSVTableParser {
    /// Parse delimited text into rows of fields. Never throws — malformed
    /// input (e.g. an unterminated quote) parses as literally as possible,
    /// because a portal preview must always show *something*.
    static func parse(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false

        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()

        func advance() -> Character? {
            let current = pending
            pending = iterator.next()
            return current
        }

        func endField() {
            currentRow.append(currentField)
            currentField = ""
        }

        func endRecord() {
            endField()
            rows.append(currentRow)
            currentRow = []
        }

        while let char = advance() {
            if insideQuotes {
                if char == "\"" {
                    if pending == "\"" {
                        currentField.append("\"")
                        _ = advance()
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
                continue
            }

            switch char {
            case "\"" where currentField.isEmpty:
                insideQuotes = true
            case delimiter:
                endField()
            case "\r\n": // Swift treats CRLF as ONE grapheme-cluster Character
                endRecord()
            case "\r":
                if pending == "\n" { _ = advance() }
                endRecord()
            case "\n":
                endRecord()
            default:
                currentField.append(char)
            }
        }

        // Trailing record without a final newline.
        if !currentField.isEmpty || !currentRow.isEmpty {
            endRecord()
        }

        // A lone trailing newline should not manufacture an empty row.
        if rows.last == [""] {
            rows.removeLast()
        }
        return rows
    }
}
