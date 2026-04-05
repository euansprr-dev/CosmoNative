// CosmoOS/AI/Agents/IdeaResearchAgent.swift
// Tier 1 agent: finds stats, studies, and evidence tagged with codex proof types.

import Foundation

@MainActor
final class IdeaResearchAgent {
    static let shared = IdeaResearchAgent()
    private init() {}

    private let model = "google/gemini-3-flash-preview"

    func research(
        ideaText: String,
        context: String? = nil,
        clientNiche: String? = nil
    ) async throws -> [IdeaResearchResult] {
        let prompt = """
        You are a research assistant for content creators. Find 5-8 relevant statistics, studies, \
        and data points that support or inform this post idea.

        POST IDEA:
        \(ideaText)
        \(context.map { "\nADDITIONAL CONTEXT:\n\($0)" } ?? "")
        \(clientNiche.map { "\nCLIENT NICHE: \($0)" } ?? "")

        For each finding, tag it with the most appropriate proof type from this list:
        - Statistic (hard numbers, percentages, data)
        - Case Study (real-world example, brand story)
        - Expert Quote (authority figure, researcher)
        - Social Proof (user testimonials, reviews, crowd behavior)
        - Analogy (comparison to known concept)
        - Contrarian Data (surprising or counter-intuitive stat)
        - Historical Precedent (past event that mirrors the idea)
        - Scientific Study (peer-reviewed research)

        Respond ONLY in JSON:
        {
          "results": [
            {
              "title": "Short finding title",
              "snippet": "2-3 sentence summary of the finding with the key data point",
              "source": "Source name (publication, study, org)",
              "url": "https://... or null if unknown",
              "proofType": "One of the proof types above"
            }
          ]
        }
        """

        let systemPrompt = "You find real statistics, studies, and evidence for content ideas. Respond only in valid JSON."

        let response = try await ResearchService.shared.analyze(
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: model,
            maxTokens: 3000,
            temperature: 0.4
        )

        let jsonString = ArcRecommendationAgent.extractJSON(from: response)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw IdeaResearchError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(RawResearchResponse.self, from: jsonData)

        return decoded.results.map { raw in
            IdeaResearchResult(
                id: UUID(),
                title: raw.title,
                snippet: raw.snippet,
                source: raw.source,
                url: raw.url,
                proofType: raw.proofType,
                isIncluded: true
            )
        }
    }
}

// MARK: - Raw Decode Types

private struct RawResearchResponse: Codable {
    let results: [RawResearchItem]
}

private struct RawResearchItem: Codable {
    let title: String
    let snippet: String
    let source: String
    let url: String?
    let proofType: String?
}

enum IdeaResearchError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "Failed to parse research response"
    }
}
