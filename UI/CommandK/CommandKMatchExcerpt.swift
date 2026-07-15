// CosmoOS/UI/CommandK/CommandKMatchExcerpt.swift
// Matched-context excerpts for Command-K search results.
//
// Two halves of one contract:
//  - `CommandKMatchExcerpt` extracts a verbatim context window around the
//    first query match in a document body (the instant-index and fallback
//    engines' counterpart to FTS5's snippet()).
//  - `CommandKMatchHighlighter` re-derives which tokens to emphasize at
//    render time from (excerpt, query), so the excerpt travels the whole
//    pipeline as a plain String — no offset plumbing that two different
//    engines could disagree on.

import SwiftUI

// MARK: - Excerpt Extraction

enum CommandKMatchExcerpt {
    /// Characters of context on each side of the match.
    static let contextRadius = 90
    /// Hard cap on the excerpt; keeps Text layout cost bounded everywhere
    /// the excerpt is typeset (same law as CommandKPreviewExcerpt).
    static let maxLength = 240

    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// A verbatim window from `body` around the first query match: the whole
    /// phrase when it occurs, otherwise the earliest query token. Returns nil
    /// when nothing matches (e.g. the match lives in title/metadata only).
    static func excerpt(from body: String?, query: String) -> String? {
        guard let body, !body.isEmpty else { return nil }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        guard let matchRange = firstMatchRange(of: trimmedQuery, in: body) else { return nil }
        return window(around: matchRange, in: body)
    }

    /// Phrase-first, then earliest token. Tokens shorter than 2 characters
    /// are skipped — "a" would anchor the window on noise.
    static func firstMatchRange(of query: String, in text: String) -> Range<String.Index>? {
        if let phrase = text.range(of: query, options: matchOptions) {
            return phrase
        }
        let tokens = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 2 }
        var earliest: Range<String.Index>?
        for token in tokens {
            guard let range = text.range(of: token, options: matchOptions) else { continue }
            if earliest == nil || range.lowerBound < earliest!.lowerBound {
                earliest = range
            }
        }
        return earliest
    }

    /// A reading-scale window of `body` centered on the matched passage, for
    /// the detail pane's serif preview — multiline, verbatim, ellipsized at
    /// cut edges. Locates the passage by the row excerpt when it is a literal
    /// substring (FTS5 snippets are contiguous), otherwise by re-matching the
    /// query. Nil means "no better anchor than the document head".
    static func readingWindow(
        anchoredBy excerpt: String?,
        query: String,
        in body: String,
        radius: Int = 1200
    ) -> String? {
        let anchor: Range<String.Index>?
        if let literal = excerpt?.trimmingCharacters(in: CharacterSet(charactersIn: "…")),
           !literal.isEmpty,
           let range = body.range(of: literal) {
            anchor = range
        } else {
            anchor = firstMatchRange(of: query, in: body)
        }
        guard let anchor else { return nil }

        // A match near the head reads fine from the head — avoid a jarring
        // leading ellipsis for no gain.
        let headDistance = body.distance(from: body.startIndex, to: anchor.lowerBound)
        guard headDistance > radius / 2 else { return nil }

        let start = body.index(anchor.lowerBound, offsetBy: -(radius / 2), limitedBy: body.startIndex) ?? body.startIndex
        let end = body.index(anchor.upperBound, offsetBy: radius, limitedBy: body.endIndex) ?? body.endIndex
        var window = String(body[start..<end])
        // Snap the leading edge to the next line/word start so the excerpt
        // doesn't open mid-word.
        if let boundary = window.firstIndex(where: { $0.isWhitespace }) {
            window = String(window[window.index(after: boundary)...])
        }
        let leading = start > body.startIndex ? "…" : ""
        let trailing = end < body.endIndex ? "…" : ""
        return leading + window.trimmingCharacters(in: .whitespacesAndNewlines) + trailing
    }

    /// Word-boundary-snapped window with ellipses marking trimmed edges.
    /// Internal newlines collapse to spaces so the excerpt reads as one line.
    private static func window(around match: Range<String.Index>, in text: String) -> String {
        var start = text.index(match.lowerBound, offsetBy: -contextRadius, limitedBy: text.startIndex) ?? text.startIndex
        var end = text.index(match.upperBound, offsetBy: contextRadius, limitedBy: text.endIndex) ?? text.endIndex

        // Snap outward-cut edges to the nearest word boundary inside the window.
        if start > text.startIndex {
            if let space = text[start..<match.lowerBound].firstIndex(where: { $0.isWhitespace }) {
                start = text.index(after: space)
            }
        }
        if end < text.endIndex {
            if let space = text[match.upperBound..<end].lastIndex(where: { $0.isWhitespace }) {
                end = space
            }
        }

        var excerpt = String(text[start..<end])
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if excerpt.count > maxLength {
            excerpt = String(excerpt.prefix(maxLength))
        }

        let leading = start > text.startIndex ? "…" : ""
        let trailing = end < text.endIndex || excerpt.count == maxLength ? "…" : ""
        return leading + excerpt + trailing
    }
}

// MARK: - Render-Time Highlighting

enum CommandKMatchHighlighter {
    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The excerpt with every query-token occurrence emphasized: matched runs
    /// take `emphasisColor` + semibold over the caller's base styling. Query
    /// tokens match by occurrence (not word boundary) so prefix typing —
    /// "bro" while writing "brown" — still lights up.
    static func attributed(
        _ text: String,
        query: String,
        baseColor: Color,
        emphasisColor: Color,
        font: Font,
        emphasisBackground: Color? = nil
    ) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = font
        attributed.foregroundColor = baseColor

        for range in matchRanges(of: query, in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].foregroundColor = emphasisColor
            attributed[lower..<upper].font = font.weight(.semibold)
            if let emphasisBackground {
                attributed[lower..<upper].backgroundColor = emphasisBackground
            }
        }
        return attributed
    }

    /// Non-overlapping ranges of the phrase (preferred) or individual query
    /// tokens within `text`.
    static func matchRanges(of query: String, in text: String) -> [Range<String.Index>] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !text.isEmpty else { return [] }

        // Whole-phrase occurrences win: one continuous emphasis run reads
        // better than per-word confetti.
        let phraseRanges = allRanges(of: trimmedQuery, in: text)
        if !phraseRanges.isEmpty { return phraseRanges }

        let tokens = trimmedQuery
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 2 }
        var ranges: [Range<String.Index>] = []
        for token in tokens {
            ranges.append(contentsOf: allRanges(of: token, in: text))
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }

        // Merge overlaps (tokens can nest, e.g. "search" and "searching").
        var merged: [Range<String.Index>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound < last.upperBound {
                if range.upperBound > last.upperBound {
                    merged[merged.count - 1] = last.lowerBound..<range.upperBound
                }
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func allRanges(of needle: String, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: needle, options: matchOptions, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}
