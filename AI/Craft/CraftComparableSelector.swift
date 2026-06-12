// CosmoOS/AI/Craft/CraftComparableSelector.swift
// Zero-LLM comparable retrieval for the craft engine. Where the old pipeline
// paid Sonnet to screen swipes, this picks 6-8 raw transcripts in Swift:
// format filter → keyword pre-rank → local-embedding re-rank → diversity cap.
// Every swipe in the library is curated, so nothing here gates on hookScore —
// engagement numbers ride along as evidence, never as a filter.
// June 2026

import Foundation

struct CraftComparableQuery: Sendable {
    var format: CraftFormat
    var draftTitle: String
    var draftText: String
    var clientNiche: String?
    var limit: Int = 8

    /// The text embedded/keyword-matched to find topically similar swipes.
    var topicText: String {
        let body = String(draftText.prefix(600))
        return [draftTitle, body]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum CraftComparableSelector {
    /// Embedding provider injected so tests stay deterministic and the daemon
    /// stays optional — keyword ranking alone is a sound fallback.
    typealias Embedder = @Sendable (String) async -> [Float]?

    static func select(
        from swipeAtoms: [Atom],
        query: CraftComparableQuery,
        embed: Embedder? = nil
    ) async -> [CraftComparable] {
        let formatMatched = swipeAtoms.filter { atom in
            atom.isSwipeFileAtom && query.format.writingFormat.matchesSwipeAtom(atom)
        }
        // A thin library beats an empty context: fall back to all swipes when
        // the format filter leaves too few to compare against.
        let pool = formatMatched.count >= 3 ? formatMatched : swipeAtoms.filter(\.isSwipeFileAtom)
        guard !pool.isEmpty else { return [] }

        let queryTokens = tokens(in: query.topicText)
        let nicheLower = query.clientNiche?.lowercased()

        // Cheap pre-rank: keyword overlap + niche boost. Bounds the embedding
        // pass to a couple dozen candidates so first-run latency stays low.
        let preRanked = pool
            .map { atom -> (atom: Atom, score: Double) in
                var score = keywordOverlap(queryTokens: queryTokens, atom: atom)
                if let nicheLower,
                   let atomNiche = atom.swipeAnalysis?.niche?.lowercased(),
                   atomNiche.contains(nicheLower) || nicheLower.contains(atomNiche) {
                    score += 0.15
                }
                return (atom, score)
            }
            .sorted { $0.score > $1.score }

        let shortlist = preRanked.prefix(max(query.limit * 3, 24)).map(\.atom)

        // Embedding re-rank when the daemon is available.
        var scored: [(atom: Atom, similarity: Float?)]
        if let embed, let queryVector = await embed(query.topicText) {
            var results: [(Atom, Float?)] = []
            for atom in shortlist {
                let candidateText = candidateTopicText(for: atom)
                if let vector = await embed(candidateText) {
                    results.append((atom, cosineSimilarity(queryVector, vector)))
                } else {
                    results.append((atom, nil))
                }
            }
            scored = results.sorted { ($0.1 ?? -1) > ($1.1 ?? -1) }
        } else {
            scored = shortlist.map { ($0, nil) }
        }

        // Diversity cap: at most 3 comparables per hook mechanism so the model
        // sees different ways the beat gets executed, not one pattern 8 times.
        var hookTypeCounts: [String: Int] = [:]
        var selected: [CraftComparable] = []
        for (atom, similarity) in scored {
            guard selected.count < query.limit else { break }
            let hookType = atom.swipeAnalysis?.hookType?.rawValue ?? "unclassified"
            if hookTypeCounts[hookType, default: 0] >= 3 { continue }
            hookTypeCounts[hookType, default: 0] += 1
            selected.append(comparable(from: atom, format: query.format, similarity: similarity))
        }
        return selected
    }

    // MARK: - Comparable construction

    static func comparable(from atom: Atom, format: CraftFormat, similarity: Float? = nil) -> CraftComparable {
        let analysis = atom.swipeAnalysis
        return CraftComparable(
            uuid: atom.uuid,
            title: atom.title ?? "Untitled swipe",
            transcript: transcript(for: atom),
            format: format,
            views: analysis?.viewsCount,
            likes: analysis?.likesCount,
            comments: analysis?.commentsCount,
            engagementRate: analysis?.engagementRate,
            hookType: analysis?.hookType?.rawValue,
            hookText: analysis?.hookText,
            niche: analysis?.niche,
            beatFingerprint: analysis?.beatFingerprint,
            similarity: similarity
        )
    }

    /// The raw transcript is the ground truth the model studies — slide-by-slide
    /// when capture produced slides, atom body otherwise. Capped to keep eight
    /// comparables inside the token budget.
    static func transcript(for atom: Atom, maxLength: Int = 1_800) -> String {
        let raw: String
        if let slides = atom.swipeAnalysis?.transcriptSlides, !slides.isEmpty {
            raw = slides
                .sorted { $0.slideNumber < $1.slideNumber }
                .map { "SLIDE \($0.slideNumber): \($0.text)" }
                .joined(separator: "\n")
        } else {
            raw = atom.body ?? ""
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }

    // MARK: - Ranking primitives

    private static func candidateTopicText(for atom: Atom) -> String {
        let hook = atom.swipeAnalysis?.hookText ?? atom.hook ?? ""
        let body = String((atom.body ?? "").prefix(400))
        let title = atom.title ?? ""
        return [title, hook, body].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func tokens(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 4 && !stopWords.contains($0) }
        )
    }

    static func keywordOverlap(queryTokens: Set<String>, atom: Atom) -> Double {
        guard !queryTokens.isEmpty else { return 0 }
        let candidateTokens = tokens(in: candidateTopicText(for: atom))
        guard !candidateTokens.isEmpty else { return 0 }
        let overlap = queryTokens.intersection(candidateTokens).count
        return Double(overlap) / Double(queryTokens.count)
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for index in 0..<count {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    private static let stopWords: Set<String> = [
        "this", "that", "with", "from", "have", "your", "what", "when",
        "they", "them", "then", "than", "will", "just", "like", "into",
        "about", "because", "their", "there", "here", "where", "which",
        "slide", "tweet", "scene"
    ]
}
