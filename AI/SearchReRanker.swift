// CosmoOS/AI/SearchReRanker.swift
// AI Conceptual Re-Ranker — streams re-ranked results after initial hybrid search
// Uses Claude via ResearchService to reason about semantic relevance, emotional tone, and conceptual relationships

import Foundation

/// AI re-ranker that conceptually re-orders search results after initial hybrid scoring.
/// Runs asynchronously — initial results display instantly, AI re-ranking applies 1-2s later.
@MainActor
final class SearchReRanker {
    static let shared = SearchReRanker()

    // MARK: - Configuration

    /// Maximum number of results to send for re-ranking
    private let maxResultsToReRank = 25

    /// Minimum query length to trigger re-ranking
    private let minQueryLength = 3

    /// Threshold: if top result has >90% score, skip re-ranking (obvious match)
    private let exactMatchThreshold: Double = 0.9

    /// Threshold: if top 10 results are within this spread, re-ranking is valuable
    private let clusterSpreadThreshold: Double = 0.15

    /// Cache capacity
    private let maxCachedQueries = 20

    /// Cache TTL in seconds (5 minutes)
    private let cacheTTL: TimeInterval = 300

    // MARK: - State

    /// Cached re-ranking results: query → (timestamp, ranked UUIDs with scores)
    private var cache: [String: (timestamp: Date, rankings: [ReRankedItem])] = [:]

    private init() {}

    // MARK: - Re-Rank

    /// Whether a fresh AI ranking exists for this query. The palette uses it
    /// to badge cache-served results whose ordering came from the re-ranker —
    /// the re-ranker never reorders a list that is already on screen.
    func hasCachedRanking(for query: String) -> Bool {
        let key = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard let cached = cache[key] else { return false }
        return Date().timeIntervalSince(cached.timestamp) < cacheTTL
    }

    /// Re-rank search results using Claude for conceptual understanding.
    /// Returns nil if re-ranking should be skipped (exact match, short query, etc.)
    func reRank(
        query: String,
        results: [ReRankInput]
    ) async -> [ReRankedItem]? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces).lowercased()

        // Skip for very short queries
        guard trimmedQuery.count >= minQueryLength else { return nil }

        // Skip if top result is an obvious exact match
        if let topScore = results.first?.score, topScore > exactMatchThreshold {
            return nil
        }

        // Skip if too few results to meaningfully re-rank
        guard results.count >= 3 else { return nil }

        // Check if scores are clustered (re-ranking is most valuable here)
        let topScores = results.prefix(min(10, results.count)).map(\.score)
        if let highest = topScores.max(), let lowest = topScores.min() {
            let spread = highest - lowest
            // If results are well-differentiated, hybrid search already did a good job
            if spread > clusterSpreadThreshold * 2 && results.first!.score > 0.7 {
                return nil
            }
        }

        // Check cache
        if let cached = cache[trimmedQuery],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.rankings
        }

        // Build re-ranking prompt
        let itemsList = results.prefix(maxResultsToReRank).enumerated().map { index, item in
            "[\(index)] \(item.type): \"\(item.title)\" — \(item.preview)"
        }.joined(separator: "\n")

        let prompt = """
        Given the search query "\(query)", re-rank these items by relevance.
        Consider semantic meaning, emotional tone, conceptual relationships, and topic proximity.

        Items:
        \(itemsList)

        Return ONLY a JSON array of objects with "index" (original position) and "score" (0-100 confidence).
        Order by most relevant first. Example: [{"index": 2, "score": 95}, {"index": 0, "score": 80}]

        Return ONLY the JSON array, no other text.
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)

            // Parse response
            let rankings = parseReRankResponse(response, originalResults: Array(results.prefix(maxResultsToReRank)))

            if !rankings.isEmpty {
                // Update cache
                cache[trimmedQuery] = (timestamp: Date(), rankings: rankings)
                evictCacheIfNeeded()
                return rankings
            }
        } catch {
            print("⚠️ SearchReRanker failed: \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - Parse Response

    private func parseReRankResponse(_ response: String, originalResults: [ReRankInput]) -> [ReRankedItem] {
        // Extract JSON array from response
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the JSON array in the response
        guard let startIndex = trimmed.firstIndex(of: "["),
              let endIndex = trimmed.lastIndex(of: "]") else {
            return []
        }

        let jsonString = String(trimmed[startIndex...endIndex])
        guard let data = jsonString.data(using: .utf8) else { return [] }

        struct RankEntry: Decodable {
            let index: Int
            let score: Int
        }

        guard let entries = try? JSONDecoder().decode([RankEntry].self, from: data) else {
            return []
        }

        // Map back to original results. The model is untrusted output: it can
        // echo the same index more than once. Keep only the first (highest-
        // ranked) occurrence so every returned uuid stays unique — downstream
        // builds a Dictionary keyed on uuid, which traps on duplicate keys.
        var reRanked: [ReRankedItem] = []
        var seenIndices = Set<Int>()
        for entry in entries {
            guard entry.index >= 0 && entry.index < originalResults.count else { continue }
            guard seenIndices.insert(entry.index).inserted else { continue }
            let original = originalResults[entry.index]
            reRanked.append(ReRankedItem(
                uuid: original.uuid,
                aiScore: Double(entry.score) / 100.0,
                originalScore: original.score
            ))
        }

        return reRanked
    }

    // MARK: - Cache Management

    private func evictCacheIfNeeded() {
        guard cache.count > maxCachedQueries else { return }

        // Remove oldest entries
        let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
        let toRemove = sorted.prefix(cache.count - maxCachedQueries)
        for (key, _) in toRemove {
            cache.removeValue(forKey: key)
        }
    }

    /// Clear the re-ranking cache
    func clearCache() {
        cache.removeAll()
    }
}

// MARK: - Data Types

/// Input to the re-ranker
struct ReRankInput {
    let uuid: String
    let type: String
    let title: String
    let preview: String
    let score: Double
}

/// Output from the re-ranker
struct ReRankedItem {
    let uuid: String
    let aiScore: Double
    let originalScore: Double

    /// Blended score: 60% AI, 40% original
    var blendedScore: Double {
        (aiScore * 0.6) + (originalScore * 0.4)
    }
}
