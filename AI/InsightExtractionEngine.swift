// CosmoOS/AI/InsightExtractionEngine.swift
// AI-powered insight extraction from research transcripts and content
// February 2026

import Foundation

// MARK: - Draft Insight Atom

/// An AI-suggested insight extracted from research content
struct DraftInsightAtom: Identifiable, Codable {
    let id: UUID
    let type: AnnotationType
    let content: String
    let suggestedTimestamp: TimeInterval
    let suggestedSectionID: UUID?
    let confidence: Double
    var isAccepted: Bool
    var isDismissed: Bool

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        content: String,
        suggestedTimestamp: TimeInterval = 0,
        suggestedSectionID: UUID? = nil,
        confidence: Double = 0.7,
        isAccepted: Bool = false,
        isDismissed: Bool = false
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.suggestedTimestamp = suggestedTimestamp
        self.suggestedSectionID = suggestedSectionID
        self.confidence = confidence
        self.isAccepted = isAccepted
        self.isDismissed = isDismissed
    }
}

// MARK: - Research Analysis

/// Full AI analysis of a research item
struct ResearchAnalysis: Codable {
    let keyArguments: [KeyArgument]
    let contrarianTakes: [ContrarianTake]
    let actionableTakeaways: [ActionableTakeaway]
    let connectionSuggestions: [ConnectionSuggestion]

    struct KeyArgument: Identifiable, Codable {
        let id: UUID
        let claim: String
        let evidence: String?

        init(id: UUID = UUID(), claim: String, evidence: String? = nil) {
            self.id = id
            self.claim = claim
            self.evidence = evidence
        }
    }

    struct ContrarianTake: Identifiable, Codable {
        let id: UUID
        let take: String
        let reasoning: String?

        init(id: UUID = UUID(), take: String, reasoning: String? = nil) {
            self.id = id
            self.take = take
            self.reasoning = reasoning
        }
    }

    struct ActionableTakeaway: Identifiable, Codable {
        let id: UUID
        let action: String
        let relevance: String?

        init(id: UUID = UUID(), action: String, relevance: String? = nil) {
            self.id = id
            self.action = action
            self.relevance = relevance
        }
    }

    struct ConnectionSuggestion: Identifiable, Codable {
        let id: UUID
        let connectionTitle: String
        let reasoning: String
        let existingConnectionUUID: String?

        init(id: UUID = UUID(), connectionTitle: String, reasoning: String, existingConnectionUUID: String? = nil) {
            self.id = id
            self.connectionTitle = connectionTitle
            self.reasoning = reasoning
            self.existingConnectionUUID = existingConnectionUUID
        }
    }
}

// MARK: - Related Item

/// A related item found via semantic search
struct RelatedItem: Identifiable {
    let id: UUID
    let atomUUID: String
    let title: String
    let type: AtomType
    let relevanceScore: Double
    let preview: String
    let matchReason: String

    init(
        id: UUID = UUID(),
        atomUUID: String,
        title: String,
        type: AtomType,
        relevanceScore: Double,
        preview: String,
        matchReason: String = "Semantically related"
    ) {
        self.id = id
        self.atomUUID = atomUUID
        self.title = title
        self.type = type
        self.relevanceScore = relevanceScore
        self.preview = preview
        self.matchReason = matchReason
    }
}

// MARK: - Insight Extraction Engine

@MainActor
final class InsightExtractionEngine {
    static let shared = InsightExtractionEngine()

    private let researchService = ResearchService.shared

    private init() {}

    // MARK: - Extract Insights

    /// Extract draft insight atoms from research transcript
    /// Uses Strategist tier (Sonnet) for analysis
    func extractInsights(
        research: Atom,
        sections: [TranscriptSection]
    ) async throws -> [DraftInsightAtom] {
        let transcriptText = buildTranscriptText(sections: sections)
        guard !transcriptText.isEmpty else { return [] }

        let title = research.title ?? "Research"

        let prompt = """
        Analyze this research transcript and extract 5-10 key insights as structured annotations.

        Research Title: \(title)

        Transcript:
        \(transcriptText.prefix(8000))

        For each insight, determine:
        1. The type: "note" (observation/fact), "question" (open question raised), or "insight" (key realization/synthesis)
        2. A concise summary (1-2 sentences max)
        3. The approximate timestamp (in seconds) where this insight appears
        4. A confidence score (0.0-1.0) for how significant this insight is

        Respond in JSON format:
        {
          "insights": [
            {
              "type": "insight",
              "content": "The main argument is that...",
              "timestamp": 120,
              "confidence": 0.9
            }
          ]
        }
        """

        let response = try await researchService.analyze(
            prompt: prompt,
            tier: .agent,
            maxTokens: 4000
        )

        return parseInsightsResponse(response, sections: sections)
    }

    // MARK: - Analyze Research

    /// Full AI analysis producing key arguments, contrarian takes, actionable takeaways, and connection suggestions
    func analyzeResearch(
        research: Atom,
        sections: [TranscriptSection],
        existingConnections: [Atom],
        existingResearchTitles: [String]
    ) async throws -> ResearchAnalysis {
        let transcriptText = buildTranscriptText(sections: sections)
        let title = research.title ?? "Research"
        let body = research.body ?? ""

        let connectionNames = existingConnections.map { $0.title ?? "Untitled" }
        let connectionsContext = connectionNames.isEmpty
            ? "None yet."
            : connectionNames.joined(separator: ", ")

        let researchContext = existingResearchTitles.isEmpty
            ? "None yet."
            : existingResearchTitles.prefix(20).joined(separator: ", ")

        let contentToAnalyze = transcriptText.isEmpty ? body : transcriptText

        let prompt = """
        Perform a deep analysis of this research content.

        Research Title: \(title)

        Content:
        \(contentToAnalyze.prefix(10000))

        Existing Connections (mental models/frameworks the user tracks):
        \(connectionsContext)

        Other Research the user has saved:
        \(researchContext)

        Produce a structured analysis with exactly these sections:

        1. KEY ARGUMENTS (3-5): The main claims or ideas presented. One sentence each.
        2. CONTRARIAN TAKES (2-3): Challenges to conventional wisdom found in this content. These are gold for content creation.
        3. ACTIONABLE TAKEAWAYS (3-5): Specific, implementable actions the user could take based on this research.
        4. CONNECTION SUGGESTIONS (2-4): Mental models or frameworks this research could feed into. Reference existing connections by name if applicable, or suggest new ones.

        Respond in JSON format:
        {
          "keyArguments": [{"claim": "...", "evidence": "..."}],
          "contrarianTakes": [{"take": "...", "reasoning": "..."}],
          "actionableTakeaways": [{"action": "...", "relevance": "..."}],
          "connectionSuggestions": [{"connectionTitle": "...", "reasoning": "..."}]
        }
        """

        let response = try await researchService.analyze(
            prompt: prompt,
            tier: .agent,
            maxTokens: 4000
        )

        return parseAnalysisResponse(response, existingConnections: existingConnections)
    }

    // MARK: - Find Related Items

    /// Semantic search across connections, research, and content
    func findRelatedItems(
        research: Atom,
        sections: [TranscriptSection]
    ) async throws -> [RelatedItem] {
        let query = buildSearchQuery(research: research, sections: sections)
        guard !query.isEmpty else { return [] }

        var results: [RelatedItem] = []
        var seenUUIDs: Set<String> = [research.uuid]

        // Search connections
        let connectionResults = try await HybridSearchEngine.shared.search(
            query: query,
            limit: 5,
            entityTypes: [.connection]
        )
        for result in connectionResults {
            let uuid = result.entityUUID ?? "\(result.entityId)"
            guard !seenUUIDs.contains(uuid) else { continue }
            seenUUIDs.insert(uuid)
            results.append(RelatedItem(
                atomUUID: uuid,
                title: result.title,
                type: .connection,
                relevanceScore: result.combinedScore,
                preview: result.preview,
                matchReason: result.matchReason.rawValue
            ))
        }

        // Search other research
        let researchResults = try await HybridSearchEngine.shared.search(
            query: query,
            limit: 5,
            entityTypes: [.research]
        )
        for result in researchResults {
            let uuid = result.entityUUID ?? "\(result.entityId)"
            guard !seenUUIDs.contains(uuid) else { continue }
            seenUUIDs.insert(uuid)
            results.append(RelatedItem(
                atomUUID: uuid,
                title: result.title,
                type: .research,
                relevanceScore: result.combinedScore,
                preview: result.preview,
                matchReason: result.matchReason.rawValue
            ))
        }

        // Search content
        let contentResults = try await HybridSearchEngine.shared.search(
            query: query,
            limit: 4,
            entityTypes: [.content]
        )
        for result in contentResults {
            let uuid = result.entityUUID ?? "\(result.entityId)"
            guard !seenUUIDs.contains(uuid) else { continue }
            seenUUIDs.insert(uuid)
            results.append(RelatedItem(
                atomUUID: uuid,
                title: result.title,
                type: .content,
                relevanceScore: result.combinedScore,
                preview: result.preview,
                matchReason: result.matchReason.rawValue
            ))
        }

        // Sort by relevance
        results.sort { $0.relevanceScore > $1.relevanceScore }
        return results
    }

    // MARK: - Private Helpers

    private func buildTranscriptText(sections: [TranscriptSection]) -> String {
        sections.map { section in
            let time = section.startTimeString
            return "[\(time)] \(section.text)"
        }.joined(separator: "\n")
    }

    private func buildSearchQuery(research: Atom, sections: [TranscriptSection]) -> String {
        var parts: [String] = []
        if let title = research.title { parts.append(title) }

        // Use first few transcript sections for semantic context
        let transcriptSnippet = sections.prefix(3).map { $0.text }.joined(separator: " ")
        if !transcriptSnippet.isEmpty {
            parts.append(String(transcriptSnippet.prefix(300)))
        }

        // Fall back to body if no transcript
        if parts.count <= 1, let body = research.body, !body.isEmpty {
            parts.append(String(body.prefix(300)))
        }

        return parts.joined(separator: " ")
    }

    private func parseInsightsResponse(_ response: String, sections: [TranscriptSection]) -> [DraftInsightAtom] {
        guard let data = extractJSON(from: response),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let insights = json["insights"] as? [[String: Any]] else {
            return []
        }

        return insights.compactMap { insight -> DraftInsightAtom? in
            guard let content = insight["content"] as? String else { return nil }

            let typeString = insight["type"] as? String ?? "insight"
            let type: AnnotationType
            switch typeString {
            case "note": type = .note
            case "question": type = .question
            default: type = .insight
            }

            let timestamp = (insight["timestamp"] as? Double) ?? 0
            let confidence = (insight["confidence"] as? Double) ?? 0.7

            // Find the section closest to this timestamp
            let closestSection = sections.min(by: {
                abs($0.startTime - timestamp) < abs($1.startTime - timestamp)
            })

            return DraftInsightAtom(
                type: type,
                content: content,
                suggestedTimestamp: timestamp,
                suggestedSectionID: closestSection?.id,
                confidence: confidence
            )
        }
    }

    private func parseAnalysisResponse(_ response: String, existingConnections: [Atom]) -> ResearchAnalysis {
        guard let data = extractJSON(from: response),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ResearchAnalysis(
                keyArguments: [],
                contrarianTakes: [],
                actionableTakeaways: [],
                connectionSuggestions: []
            )
        }

        // Parse key arguments
        let keyArgs = (json["keyArguments"] as? [[String: Any]] ?? []).compactMap { item -> ResearchAnalysis.KeyArgument? in
            guard let claim = item["claim"] as? String else { return nil }
            return ResearchAnalysis.KeyArgument(claim: claim, evidence: item["evidence"] as? String)
        }

        // Parse contrarian takes
        let contrarian = (json["contrarianTakes"] as? [[String: Any]] ?? []).compactMap { item -> ResearchAnalysis.ContrarianTake? in
            guard let take = item["take"] as? String else { return nil }
            return ResearchAnalysis.ContrarianTake(take: take, reasoning: item["reasoning"] as? String)
        }

        // Parse actionable takeaways
        let takeaways = (json["actionableTakeaways"] as? [[String: Any]] ?? []).compactMap { item -> ResearchAnalysis.ActionableTakeaway? in
            guard let action = item["action"] as? String else { return nil }
            return ResearchAnalysis.ActionableTakeaway(action: action, relevance: item["relevance"] as? String)
        }

        // Parse connection suggestions, matching existing connections by name
        let connectionSugs = (json["connectionSuggestions"] as? [[String: Any]] ?? []).compactMap { item -> ResearchAnalysis.ConnectionSuggestion? in
            guard let title = item["connectionTitle"] as? String,
                  let reasoning = item["reasoning"] as? String else { return nil }

            // Try to match to an existing connection by fuzzy title match
            let existingMatch = existingConnections.first { conn in
                guard let connTitle = conn.title else { return false }
                return connTitle.lowercased().contains(title.lowercased()) ||
                       title.lowercased().contains(connTitle.lowercased())
            }

            return ResearchAnalysis.ConnectionSuggestion(
                connectionTitle: title,
                reasoning: reasoning,
                existingConnectionUUID: existingMatch?.uuid
            )
        }

        return ResearchAnalysis(
            keyArguments: keyArgs,
            contrarianTakes: contrarian,
            actionableTakeaways: takeaways,
            connectionSuggestions: connectionSugs
        )
    }

    /// Extract JSON object from a response that may contain markdown fences or extra text
    private func extractJSON(from response: String) -> Data? {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the first { and last }
        guard let start = jsonString.firstIndex(of: "{"),
              let end = jsonString.lastIndex(of: "}") else {
            return nil
        }
        jsonString = String(jsonString[start...end])

        return jsonString.data(using: .utf8)
    }
}
