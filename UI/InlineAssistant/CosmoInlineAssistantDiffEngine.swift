import Foundation

enum CosmoInlineAssistantDiffEngine {
    static func hunks(original: String, proposed: String) -> [CosmoProposalHunk] {
        let originalLines = normalizedLines(original)
        let proposedLines = normalizedLines(proposed)
        let maxCount = max(originalLines.count, proposedLines.count)
        var hunks: [CosmoProposalHunk] = []

        for index in 0..<maxCount {
            let oldLine = index < originalLines.count ? originalLines[index] : nil
            let newLine = index < proposedLines.count ? proposedLines[index] : nil

            switch (oldLine, newLine) {
            case let (.some(old), .some(new)) where old == new:
                hunks.append(CosmoProposalHunk(kind: .context, text: old))
            case let (.some(old), .some(new)):
                hunks.append(CosmoProposalHunk(kind: .removed, text: old))
                hunks.append(CosmoProposalHunk(kind: .added, text: new))
            case let (.some(old), .none):
                hunks.append(CosmoProposalHunk(kind: .removed, text: old))
            case let (.none, .some(new)):
                hunks.append(CosmoProposalHunk(kind: .added, text: new))
            case (.none, .none):
                break
            }
        }

        return hunks
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

// MARK: - Locator

/// Finds where a proposal's `originalText` lives inside the *current* surface text.
///
/// LLM-supplied `originalText` rarely byte-matches the live document — whitespace,
/// blank lines, and smart punctuation drift. The locator first tries an exact match,
/// then a whitespace-normalized match that maps back to a real range in the source.
/// This is the single source of truth for "can this edit still apply" and "where do we
/// splice the inline diff", so matching and applying never disagree.
enum CosmoInlineDiffLocator {
    /// Best-effort range of `needle` within `haystack`. Exact first, then whitespace-normalized.
    static func range(of needle: String, in haystack: String) -> Range<String.Index>? {
        let trimmedNeedle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNeedle.isEmpty else { return nil }

        if let exact = haystack.range(of: needle) { return exact }
        if let trimmed = haystack.range(of: trimmedNeedle) { return trimmed }
        return normalizedRange(of: trimmedNeedle, in: haystack)
    }

    /// Whether `needle` can be located in `haystack` (exact or whitespace-normalized).
    static func matches(_ needle: String, in haystack: String) -> Bool {
        range(of: needle, in: haystack) != nil
    }

    private static func normalizedRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        // Build a whitespace-collapsed projection of the haystack while remembering,
        // for every projected character, the real source indices it came from.
        var projected: [Character] = []
        var startIndex: [String.Index] = []
        var endIndex: [String.Index] = []
        var previousWasSpace = false

        var cursor = haystack.startIndex
        while cursor < haystack.endIndex {
            let character = haystack[cursor]
            let next = haystack.index(after: cursor)

            if character.isWhitespace {
                if previousWasSpace, let last = endIndex.indices.last {
                    endIndex[last] = next // extend the run the single space already represents
                } else if !projected.isEmpty {
                    projected.append(" ")
                    startIndex.append(cursor)
                    endIndex.append(next)
                }
                previousWasSpace = true
            } else {
                projected.append(canonical(character))
                startIndex.append(cursor)
                endIndex.append(next)
                previousWasSpace = false
            }
            cursor = next
        }

        if projected.last == " " {
            projected.removeLast()
            startIndex.removeLast()
            endIndex.removeLast()
        }

        let needleChars = Array(collapseWhitespace(needle))
        guard !needleChars.isEmpty,
              let matchStart = firstIndex(of: needleChars, in: projected) else { return nil }

        let matchEnd = matchStart + needleChars.count
        return startIndex[matchStart]..<endIndex[matchEnd - 1]
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var result: [Character] = []
        var previousWasSpace = false
        for character in text {
            if character.isWhitespace {
                if !previousWasSpace, !result.isEmpty { result.append(" ") }
                previousWasSpace = true
            } else {
                result.append(canonical(character))
                previousWasSpace = false
            }
        }
        if result.last == " " { result.removeLast() }
        return String(result)
    }

    /// Folds typographic variants the model commonly substitutes (smart quotes, dashes)
    /// to a canonical form. Each fold is 1:1, so the source index map stays valid and the
    /// red "removed" lines still render with the document's real characters.
    private static func canonical(_ character: Character) -> Character {
        switch character {
        case "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}", "\u{2033}": return "\""
        case "\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}", "\u{2032}": return "'"
        case "\u{2014}", "\u{2013}", "\u{2212}", "\u{2012}", "\u{2015}": return "-"
        default: return character
        }
    }

    private static func firstIndex(of needle: [Character], in haystack: [Character]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        let lastStart = haystack.count - needle.count
        var start = 0
        while start <= lastStart {
            var offset = 0
            while offset < needle.count, haystack[start + offset] == needle[offset] {
                offset += 1
            }
            if offset == needle.count { return start }
            start += 1
        }
        return nil
    }
}

// MARK: - Inline review segments

/// A single located change in the live document, derived from one proposal operation.
struct CosmoInlineDiffChange: Identifiable, Equatable {
    /// Matches the originating operation's id so accept/reject route back correctly.
    let id: UUID
    let removedLines: [String]
    let addedLines: [String]
    let rationale: String
    let status: CosmoProposalStatus
    /// True when the original text could no longer be located — the edit is stale.
    let isConflicted: Bool
}

/// An ordered slice of the document review: untouched prose or a change block.
enum CosmoInlineDiffSegment: Identifiable, Equatable {
    case unchanged(id: String, text: String)
    case change(CosmoInlineDiffChange)

    var id: String {
        switch self {
        case let .unchanged(id, _): return id
        case let .change(change): return "change-\(change.id.uuidString)"
        }
    }
}

/// Turns a live source string + a proposal's operations into an ordered, in-document
/// diff. Removed text is read straight from the *current* document (not the model's
/// echo), so the red lines always match what is really there.
enum CosmoInlineDiffReviewBuilder {
    static func segments(
        sourceText: String,
        operations: [CosmoAssistantProposalOperation]
    ) -> [CosmoInlineDiffSegment] {
        let reviewable = operations.filter { $0.status == .pending || $0.status == .conflicted }

        // Positioned edits are woven into the document at a real location. Trailing
        // insertions have no anchor and append at the end. Conflicts are genuinely
        // stale — a replacement whose original text no longer exists.
        var positioned: [PositionedChange] = []
        var trailingInsertions: [CosmoAssistantProposalOperation] = []
        var conflicts: [CosmoAssistantProposalOperation] = []

        for operation in reviewable {
            switch operation.kind {
            case .textReplacement, .structuredFieldReplacement:
                if let original = operation.originalText, isAnchorable(original) {
                    if let range = CosmoInlineDiffLocator.range(of: original, in: sourceText) {
                        positioned.append(PositionedChange(operation: operation, placement: .replace(range)))
                    } else {
                        // A real original that is gone is the only true conflict.
                        conflicts.append(operation)
                    }
                } else {
                    // No original text to replace — this is additive content, not a conflict.
                    trailingInsertions.append(operation)
                }
            case .textInsertion:
                if let anchor = operation.originalText, isAnchorable(anchor),
                   let range = CosmoInlineDiffLocator.range(of: anchor, in: sourceText) {
                    positioned.append(PositionedChange(operation: operation, placement: .insertAfter(range)))
                } else {
                    trailingInsertions.append(operation)
                }
            case .canvasPlan:
                conflicts.append(operation)
            }
        }

        positioned.sort { $0.sortIndex < $1.sortIndex }

        var segments: [CosmoInlineDiffSegment] = []
        var cursor = sourceText.startIndex

        for change in positioned {
            switch change.placement {
            case let .replace(range):
                // Skip an edit that collides with one already woven in.
                guard range.lowerBound >= cursor else {
                    conflicts.append(change.operation)
                    continue
                }
                if range.lowerBound > cursor {
                    appendUnchanged(String(sourceText[cursor..<range.lowerBound]), to: &segments)
                }
                segments.append(.change(CosmoInlineDiffChange(
                    id: change.operation.id,
                    removedLines: displayLines(String(sourceText[range])),
                    addedLines: displayLines(change.operation.proposedText ?? ""),
                    rationale: change.operation.rationale,
                    status: change.operation.status,
                    isConflicted: false
                )))
                cursor = range.upperBound

            case let .insertAfter(range):
                let insertionPoint = range.upperBound
                guard insertionPoint >= cursor else {
                    trailingInsertions.append(change.operation)
                    continue
                }
                // Emit everything up to and including the anchor, then the added lines.
                if insertionPoint > cursor {
                    appendUnchanged(String(sourceText[cursor..<insertionPoint]), to: &segments)
                }
                segments.append(.change(CosmoInlineDiffChange(
                    id: change.operation.id,
                    removedLines: [],
                    addedLines: displayLines(change.operation.proposedText ?? ""),
                    rationale: change.operation.rationale,
                    status: change.operation.status,
                    isConflicted: false
                )))
                cursor = insertionPoint
            }
        }

        if cursor < sourceText.endIndex {
            appendUnchanged(String(sourceText[cursor...]), to: &segments)
        }

        for operation in trailingInsertions {
            segments.append(.change(CosmoInlineDiffChange(
                id: operation.id,
                removedLines: [],
                addedLines: displayLines(operation.proposedText ?? ""),
                rationale: operation.rationale,
                status: operation.status,
                isConflicted: false
            )))
        }

        for operation in conflicts {
            segments.append(.change(CosmoInlineDiffChange(
                id: operation.id,
                removedLines: displayLines(operation.originalText ?? ""),
                addedLines: displayLines(operation.proposedText ?? ""),
                rationale: operation.rationale,
                status: operation.status,
                isConflicted: true
            )))
        }

        return segments
    }

    private struct PositionedChange {
        enum Placement {
            case replace(Range<String.Index>)
            case insertAfter(Range<String.Index>)
        }

        let operation: CosmoAssistantProposalOperation
        let placement: Placement

        var sortIndex: String.Index {
            switch placement {
            case let .replace(range): return range.lowerBound
            case let .insertAfter(range): return range.upperBound
            }
        }
    }

    private static func isAnchorable(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func appendUnchanged(_ text: String, to segments: inout [CosmoInlineDiffSegment]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        segments.append(.unchanged(id: "unchanged-\(segments.count)", text: text))
    }

    private static func displayLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }
            .filter { !$0.isEmpty }
    }
}
