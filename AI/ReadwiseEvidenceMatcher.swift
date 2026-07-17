// CosmoOS/AI/ReadwiseEvidenceMatcher.swift
// The "right concept, right time" gate for Readwise evidence. Highlights
// surface in a development conversation ONLY when the concept's own words
// (name, aliases) appear in the highlight text, the user's note, or the
// highlight's tags — deterministic, legible, and abstaining by default.
// A book being ABOUT a topic never volunteers every line of it: book-title
// matches only boost, they never qualify on their own.
//
// Pure scoring over in-memory atoms; the async wrapper fetches the mirror.
// July 2026 — READWISE_INTEGRATION_PLAN.md §6.

import Foundation

enum ReadwiseEvidenceMatcher {

    struct Match: Equatable, Sendable {
        var bookUUID: String
        var bookTitle: String
        var author: String?
        var highlightId: String
        var text: String
        var note: String?
        var readwiseUrl: String?
        var score: Double
    }

    /// Below this, silence. Guessed evidence is worse than none.
    static let scoreFloor: Double = 0.6

    /// Words that carry no concept identity — never allowed to qualify a
    /// match on their own ("Constraints as a creative gift" must match on
    /// constraints/creative/gift, not "as"/"a").
    private static let stopTokens: Set<String> = [
        "a", "an", "the", "of", "as", "to", "in", "on", "for", "and", "or",
        "is", "are", "be", "it", "its", "your", "my", "how", "what", "why", "with"
    ]

    // MARK: - Async assembly

    /// Matching highlights for a concept across the whole Readwise mirror.
    static func evidence(
        conceptName: String,
        aliases: [String] = [],
        limit: Int = 6
    ) async -> [Match] {
        let books = await ReadwiseService.mirrorAtoms()
        return matches(conceptName: conceptName, aliases: aliases, in: books, limit: limit)
    }

    // MARK: - Pure matching

    static func matches(
        conceptName: String,
        aliases: [String],
        in books: [Atom],
        limit: Int = 6
    ) -> [Match] {
        let keys = keyPhrases(conceptName: conceptName, aliases: aliases)
        guard !keys.isEmpty else { return [] }

        var out: [Match] = []
        for book in books {
            guard let structured = book.readwiseStructured else { continue }
            let bookTitle = book.title ?? "Untitled"
            let titleHaystack = normalized(bookTitle)
            for highlight in structured.highlights {
                let score = score(highlight: highlight, bookTitleNormalized: titleHaystack, keys: keys)
                guard score >= scoreFloor else { continue }
                out.append(Match(
                    bookUUID: book.uuid,
                    bookTitle: bookTitle,
                    author: book.readwiseAuthor,
                    highlightId: highlight.id,
                    text: highlight.text,
                    note: highlight.note,
                    readwiseUrl: highlight.readwiseUrl,
                    score: score
                ))
            }
        }

        return out
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0001 { return lhs.score > rhs.score }
                return lhs.highlightId > rhs.highlightId   // stable: newer Readwise ids are larger
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Scoring

    struct KeyPhrase: Equatable {
        /// Space-joined normalized phrase (" attention residue ").
        let phrase: String
        /// Identity-bearing tokens (stop words removed).
        let tokens: Set<String>
    }

    static func keyPhrases(conceptName: String, aliases: [String]) -> [KeyPhrase] {
        ([conceptName] + aliases)
            .map(normalized)
            .filter { !$0.isEmpty }
            .compactMap { phrase in
                let tokens = Set(phrase.split(separator: " ").map(String.init))
                    .subtracting(stopTokens)
                guard !tokens.isEmpty else { return nil }
                return KeyPhrase(phrase: phrase, tokens: tokens)
            }
    }

    /// One highlight against every key phrase — the best rule wins, weaker
    /// signals only boost:
    ///  - full phrase in the highlight text            → 0.90
    ///  - full phrase in the user's note, or in a tag  → 0.85
    ///  - all identity tokens present (multi-token)    → 0.75
    ///  - ≥ ⅔ of identity tokens present (multi-token) → 0.60
    ///  - single-token key present in text             → 0.50 base — clears
    ///    the floor only with support (note/tag/title mention, or the token
    ///    appearing more than once). A lone common word is not evidence.
    ///  - book-title mention                           → +0.10 boost, never
    ///    qualifying on its own.
    static func score(
        highlight: ReadwiseMirrorHighlight,
        bookTitleNormalized: String,
        keys: [KeyPhrase]
    ) -> Double {
        let text = normalized(highlight.text)
        guard !text.isEmpty else { return 0 }
        let textTokens = tokenCounts(text)
        let note = highlight.note.map(normalized) ?? ""
        let tagPhrases = highlight.tags.map(normalized)

        var best: Double = 0
        for key in keys {
            var score: Double = 0

            // The phrase rules are for multi-word keys only — a lone word
            // "matching as a phrase" is just the word appearing once, which
            // belongs to the (stricter) single-token branch below.
            let isMultiWordPhrase = key.phrase.contains(" ")

            if isMultiWordPhrase, containsPhrase(text, key.phrase) {
                score = 0.90
            } else if isMultiWordPhrase, !note.isEmpty, containsPhrase(note, key.phrase) {
                score = 0.85
            } else if isMultiWordPhrase, tagPhrases.contains(where: { containsPhrase($0, key.phrase) }) {
                score = 0.85
            } else if key.tokens.count >= 2 {
                let present = key.tokens.filter { textTokens[$0] != nil }
                let coverage = Double(present.count) / Double(key.tokens.count)
                if coverage >= 0.999 {
                    score = 0.75
                } else if coverage >= 0.66 {
                    score = 0.60
                }
            } else if let token = key.tokens.first, let count = textTokens[token] {
                score = 0.50
                let supported = (!note.isEmpty && containsPhrase(note, token))
                    || tagPhrases.contains(where: { containsPhrase($0, token) })
                    || containsPhrase(bookTitleNormalized, token)
                    || count >= 2
                if supported { score += 0.15 }
            }

            // Context boost — the book being about the concept strengthens a
            // real match; it never creates one.
            if score > 0, containsPhrase(bookTitleNormalized, key.phrase) {
                score = min(1.0, score + 0.10)
            }

            best = max(best, score)
        }
        return best
    }

    // MARK: - Text mechanics

    /// The shared normalization voice (ConceptResolver.conceptKey): lowercase,
    /// alphanumeric tokens, single-space joined.
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Whole-token phrase containment (" habit " never matches "inhabit").
    private static func containsPhrase(_ haystack: String, _ phrase: String) -> Bool {
        guard !haystack.isEmpty, !phrase.isEmpty else { return false }
        return " \(haystack) ".contains(" \(phrase) ")
    }

    private static func tokenCounts(_ normalizedText: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for token in normalizedText.split(separator: " ") {
            counts[String(token), default: 0] += 1
        }
        return counts
    }
}
