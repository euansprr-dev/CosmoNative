// CosmoOS/AI/Agents/ArcRecommendationAgent.swift
// Tier 1 agent: cheap/fast arc type recommendation using Gemini Flash.

import Foundation

@MainActor
final class ArcRecommendationAgent {
    static let shared = ArcRecommendationAgent()
    private init() {}

    private let model = "google/gemini-3-flash-preview"

    struct RecommendationResult {
        let detectedElements: DetectedElements
        let arcRecommendations: [ArcRecommendation]
        let blueprintRecommendations: [BlueprintRecommendation]
    }

    func recommend(
        ideaText: String,
        clientNiche: String?,
        arcShapes: [(name: String, definition: String, frequency: String)],
        blueprintTitles: [(title: String, arcShape: String)]
    ) async throws -> RecommendationResult {
        let arcList = arcShapes.map { "- \($0.name): \($0.definition) (\($0.frequency))" }.joined(separator: "\n")
        let bpList = blueprintTitles.map { "- \($0.title) (arc: \($0.arcShape))" }.joined(separator: "\n")

        let prompt = """
        You are a Content Physics arc advisor. Given a post idea, recommend the best structural approaches.

        POST IDEA:
        \(ideaText)
        \(clientNiche.map { "\nCLIENT NICHE: \($0)" } ?? "")

        AVAILABLE ARC TYPES:
        \(arcList)

        AVAILABLE BLUEPRINTS:
        \(bpList)

        Respond ONLY in JSON:
        {
          "detectedElements": {
            "motivations": ["..."],
            "proofTypes": ["..."],
            "speechActs": ["..."],
            "signals": ["..."]
          },
          "arcRecommendations": [
            {
              "arcName": "...",
              "explanation": "...",
              "prioritizes": ["element1", "element2"],
              "tradesOff": ["element1"],
              "matchingBlueprintTitles": ["..."],
              "confidence": 0.9
            }
          ],
          "blueprintRecommendations": [
            { "title": "...", "explanation": "..." }
          ]
        }
        """

        let systemPrompt = "You analyze content ideas and recommend arc shapes. Respond only in valid JSON."

        let response = try await ResearchService.shared.analyze(
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: model,
            maxTokens: 2000,
            temperature: 0.3
        )

        let jsonString = Self.extractJSON(from: response)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ArcRecommendationError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(RawRecommendation.self, from: jsonData)

        return RecommendationResult(
            detectedElements: decoded.detectedElements,
            arcRecommendations: decoded.arcRecommendations.map { raw in
                ArcRecommendation(
                    id: UUID(),
                    arcName: raw.arcName,
                    explanation: raw.explanation,
                    prioritizes: raw.prioritizes ?? [],
                    tradesOff: raw.tradesOff ?? [],
                    matchingBlueprintTitles: raw.matchingBlueprintTitles ?? [],
                    confidence: raw.confidence ?? 0.8
                )
            },
            blueprintRecommendations: decoded.blueprintRecommendations.map {
                BlueprintRecommendation(title: $0.title, explanation: $0.explanation)
            }
        )
    }

    // MARK: - JSON Extraction

    static func extractJSON(from text: String) -> String {
        if let start = text.range(of: "```json"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}

// MARK: - Raw Decode Types

private struct RawRecommendation: Codable {
    let detectedElements: DetectedElements
    let arcRecommendations: [RawArc]
    let blueprintRecommendations: [RawBlueprint]
}

private struct RawArc: Codable {
    let arcName: String
    let explanation: String
    let prioritizes: [String]?
    let tradesOff: [String]?
    let matchingBlueprintTitles: [String]?
    let confidence: Double?
}

private struct RawBlueprint: Codable {
    let title: String
    let explanation: String
}

enum ArcRecommendationError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "Failed to parse arc recommendation response"
    }
}
