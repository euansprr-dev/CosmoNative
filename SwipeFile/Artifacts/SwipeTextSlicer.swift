// CosmoOS/SwipeFile/Artifacts/SwipeTextSlicer.swift
// Long pasted text becomes a real artifact with beats.
//
// The trivial sibling of SwipePageSlicer: where the page slicer cuts a
// rendered page at its DOM sections, this cuts raw text at its blank lines.
// A pasted VSL script becomes paragraph units the analyzer can role-tag; a
// one-line hook stays exactly what it was — one unit, zero model spend.

import Foundation

enum SwipeTextSlicer {

    /// Below this, text is a saved line, not a document — never split.
    static let minimumLengthToSplit = 600
    /// A "document" has at least this many blank-line-separated blocks.
    static let minimumBlocks = 3

    /// The unit list for a note capture. Single unit (whole text) unless the
    /// text is genuinely long-form with real paragraph structure.
    static func units(from text: String) -> [SwipeArtifactUnit] {
        let trimmed = text.trimmed
        let blocks = paragraphBlocks(in: trimmed)
        guard trimmed.count >= minimumLengthToSplit, blocks.count >= minimumBlocks else {
            return [SwipeArtifactUnit(index: 0, headline: firstLine(of: trimmed), copy: trimmed)]
        }
        return blocks.enumerated().map { index, block in
            SwipeArtifactUnit(index: index, headline: firstLine(of: block), copy: block)
        }
    }

    /// Blank-line-separated blocks. Windows newlines normalized; runs of
    /// blank (or whitespace-only) lines all count as one cut.
    static func paragraphBlocks(in text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [String] = []
        var current: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if line.trimmed.isEmpty {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: "\n"))
                    current = []
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current.joined(separator: "\n")) }
        return blocks
    }

    private static func firstLine(of text: String) -> String? {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init)?.trimmed
    }
}
