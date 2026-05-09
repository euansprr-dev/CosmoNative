import Foundation

actor CosmoRetrievalService {
    static let shared = CosmoRetrievalService()

    private let indexStore: ContextIndexStore

    init(indexStore: ContextIndexStore = .shared) {
        self.indexStore = indexStore
    }

    func retrieve(_ request: ContextRetrievalRequest) async throws -> [ContextRetrievalResult] {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard !request.pinnedSourceIDs.isEmpty else { return [] }

        var merged = try await keywordResults(for: request)

        if merged.count < request.maxChunks {
            let lexical = try await lexicalFallbackResults(for: request)
            merged.append(contentsOf: lexical)
        }

        let reranked = merged.map { result in
            ContextRetrievalResult(
                chunk: result.chunk,
                source: result.source,
                score: Self.rerankScore(
                    query: request.query,
                    candidateText: result.chunk.searchableText,
                    baseScore: result.score,
                    purpose: request.purpose
                ),
                matchType: result.matchType
            )
        }

        return Array(dedupe(reranked).prefix(max(1, request.maxChunks)))
    }

    nonisolated static func rerankScore(
        query: String,
        candidateText: String,
        baseScore: Double,
        purpose: RetrievalPurpose
    ) -> Double {
        let normalizedQuery = query.lowercased()
        let normalizedCandidate = candidateText.lowercased()
        var score = baseScore

        if purpose == .factLookup {
            if normalizedCandidate.contains(normalizedQuery) {
                score += 2.0
            }
            let queryTerms = ContextIndexStoreSearchTerms.terms(in: normalizedQuery)
            let matches = queryTerms.filter { normalizedCandidate.contains($0) }.count
            score += Double(matches) * 0.25

            let quoted = quotedPhrases(in: normalizedQuery)
            if quoted.contains(where: { normalizedCandidate.contains($0) }) {
                score += 2.0
            }
        }

        return score
    }

    private func keywordResults(for request: ContextRetrievalRequest) async throws -> [ContextRetrievalResult] {
        let keywordResults = try await indexStore.keywordSearch(
            query: keywordQuery(for: request.query, purpose: request.purpose),
            sourceIDs: request.pinnedSourceIDs,
            limit: max(request.maxChunks * 2, request.maxChunks)
        )

        return keywordResults.map { source, chunk, score in
            ContextRetrievalResult(
                chunk: chunk,
                source: source,
                score: score,
                matchType: "keyword"
            )
        }
    }

    private func lexicalFallbackResults(for request: ContextRetrievalRequest) async throws -> [ContextRetrievalResult] {
        let chunks = try await indexStore.chunks(sourceIDs: request.pinnedSourceIDs)
        let sources = try await indexStore.sources(ids: request.pinnedSourceIDs)
        let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let queryTerms = Set(ContextIndexStoreSearchTerms.terms(in: request.query))
        guard !queryTerms.isEmpty else { return [] }

        return chunks.compactMap { chunk -> ContextRetrievalResult? in
            guard let source = sourceByID[chunk.sourceID] else { return nil }
            let chunkTerms = Set(ContextIndexStoreSearchTerms.terms(in: chunk.searchableText))
            let overlap = queryTerms.intersection(chunkTerms).count
            guard overlap > 0 else { return nil }
            let score = Double(overlap) / Double(max(1, queryTerms.count))
            return ContextRetrievalResult(chunk: chunk, source: source, score: score, matchType: "lexical")
        }
        .sorted { $0.score > $1.score }
    }

    private func keywordQuery(for query: String, purpose: RetrievalPurpose) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard purpose == .factLookup else { return trimmed }
        if trimmed.contains("\"") { return trimmed }

        let importantWords = ContextIndexStoreSearchTerms.terms(in: trimmed)
            .filter { !Self.factLookupStopWords.contains($0) }
        return importantWords.isEmpty ? trimmed : importantWords.joined(separator: " ")
    }

    private func dedupe(_ results: [ContextRetrievalResult]) -> [ContextRetrievalResult] {
        var seen = Set<String>()
        var output: [ContextRetrievalResult] = []
        for result in results.sorted(by: { $0.score > $1.score }) where seen.insert(result.chunk.id).inserted {
            output.append(result)
        }
        return output
    }

    private static let factLookupStopWords: Set<String> = [
        "does", "did", "the", "brief", "mention", "mentions", "what", "where",
        "when", "how", "this", "that", "there", "with", "about", "from"
    ]
}

private enum ContextIndexStoreSearchTerms {
    static func terms(in text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .filter { !stopWords.contains($0) }
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "from", "that", "this", "with", "does", "did",
        "brief", "mention", "mentions", "what", "where", "when", "how", "are",
        "was", "were", "you", "your", "into", "about", "there"
    ]
}

private func quotedPhrases(in query: String) -> [String] {
    var phrases: [String] = []
    var current = ""
    var insideQuote = false

    for character in query {
        if character == "\"" {
            if insideQuote {
                let phrase = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !phrase.isEmpty {
                    phrases.append(phrase)
                }
                current = ""
            }
            insideQuote.toggle()
        } else if insideQuote {
            current.append(character)
        }
    }

    return phrases
}
