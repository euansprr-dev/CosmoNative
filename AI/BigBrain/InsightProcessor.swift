// CosmoOS/AI/BigBrain/InsightProcessor.swift
// Processes Claude API responses into structured insights
// Part of the Big Brain architecture

import Foundation
import os.log

// MARK: - Insight Processor

/// Processes Claude API responses into structured CosmoOS data types.
///
/// This struct handles parsing of Claude's JSON responses into native Swift types
/// that can be stored as Atoms or displayed in the UI.
public struct InsightProcessor {

    private static let logger = Logger(subsystem: "com.cosmo.bigbrain", category: "InsightProcessor")

    // MARK: - Correlation Insights

    /// Parse correlation insights from Claude response
    public static func parseCorrelationInsights(_ response: String) throws -> [ClaudeCorrelationInsight] {
        // Extract JSON from response (Claude might include markdown code blocks)
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8) else {
            throw ClaudeAPIError.parsingError("Invalid UTF-8 in response")
        }

        do {
            let insights = try JSONDecoder().decode([ClaudeCorrelationInsight].self, from: data)
            logger.info("Parsed \(insights.count) correlation insights")
            return insights
        } catch {
            logger.error("Failed to parse correlation insights: \(error.localizedDescription)")

            // Try to parse as a more flexible format
            return try parseFlexibleCorrelationFormat(jsonString)
        }
    }

    /// Parse a more flexible JSON format for correlations
    private static func parseFlexibleCorrelationFormat(_ jsonString: String) throws -> [ClaudeCorrelationInsight] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ClaudeAPIError.parsingError("Could not parse correlation JSON")
        }

        return json.compactMap { dict -> ClaudeCorrelationInsight? in
            guard let variables = dict["variables"] as? [String],
                  let insight = dict["insight"] as? String else {
                return nil
            }

            return ClaudeCorrelationInsight(
                id: dict["id"] as? String ?? UUID().uuidString,
                variables: variables,
                direction: dict["direction"] as? String ?? "unknown",
                strength: dict["strength"] as? String ?? "unknown",
                effectSize: dict["effectSize"] as? Double ?? 0.0,
                insight: insight,
                action: dict["action"] as? String ?? "",
                confidence: dict["confidence"] as? String ?? "medium",
                supportingData: dict["supportingData"] as? [String] ?? []
            )
        }
    }

    // MARK: - Content Ideas

    /// Parse content ideas from Claude response
    public static func parseContentIdeas(_ response: String) throws -> [ContentIdea] {
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8) else {
            throw ClaudeAPIError.parsingError("Invalid UTF-8 in response")
        }

        do {
            let ideas = try JSONDecoder().decode([ContentIdea].self, from: data)
            logger.info("Parsed \(ideas.count) content ideas")
            return ideas
        } catch {
            // Try flexible parsing
            return try parseFlexibleContentIdeas(jsonString)
        }
    }

    private static func parseFlexibleContentIdeas(_ jsonString: String) throws -> [ContentIdea] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ClaudeAPIError.parsingError("Could not parse content ideas JSON")
        }

        return json.compactMap { dict -> ContentIdea? in
            guard let title = dict["title"] as? String else { return nil }

            return ContentIdea(
                title: title,
                angle: dict["angle"] as? String ?? "",
                rationale: dict["rationale"] as? String ?? dict["why"] as? String ?? "",
                format: dict["format"] as? String ?? "post"
            )
        }
    }

    // MARK: - Journal Synthesis

    /// Parse journal synthesis from Claude response
    public static func parseJournalSynthesis(_ response: String) throws -> JournalSynthesis {
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8) else {
            throw ClaudeAPIError.parsingError("Invalid UTF-8 in response")
        }

        do {
            return try JSONDecoder().decode(JournalSynthesis.self, from: data)
        } catch {
            // Try flexible parsing
            return try parseFlexibleJournalSynthesis(jsonString)
        }
    }

    private static func parseFlexibleJournalSynthesis(_ jsonString: String) throws -> JournalSynthesis {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeAPIError.parsingError("Could not parse journal synthesis JSON")
        }

        return JournalSynthesis(
            themes: json["themes"] as? [String] ?? json["key_themes"] as? [String] ?? [],
            emotionalTrajectory: json["emotionalTrajectory"] as? String ?? json["emotional_trajectory"] as? String ?? "",
            patterns: json["patterns"] as? [String] ?? [],
            suggestedActions: json["suggestedActions"] as? [String] ?? json["suggested_actions"] as? [String] ?? json["actions"] as? [String] ?? [],
            growthAreas: json["growthAreas"] as? [String] ?? json["growth_areas"] as? [String] ?? []
        )
    }

    // MARK: - Query Responses

    /// Parse a query response (for level system queries routed to Claude)
    public static func parseQueryResponse(_ response: String) throws -> ClaudeQueryResponse {
        // For text responses that aren't structured JSON
        if !response.contains("{") {
            return ClaudeQueryResponse(
                queryType: "freeform",
                result: response,
                metadata: nil
            )
        }

        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Return as text if not JSON
            return ClaudeQueryResponse(
                queryType: "freeform",
                result: response,
                metadata: nil
            )
        }

        return ClaudeQueryResponse(
            queryType: json["queryType"] as? String ?? json["query_type"] as? String ?? "unknown",
            result: json["result"] as? String ?? json["answer"] as? String ?? response,
            metadata: json["metadata"] as? [String: String]
        )
    }

    // MARK: - Helpers

    /// Extract JSON from a response that might include markdown code blocks
    private static func extractJSON(from response: String) -> String {
        // Remove markdown code blocks if present
        var cleaned = response

        // Handle ```json ... ``` blocks
        if let jsonBlockStart = cleaned.range(of: "```json") {
            cleaned = String(cleaned[jsonBlockStart.upperBound...])
            if let jsonBlockEnd = cleaned.range(of: "```") {
                cleaned = String(cleaned[..<jsonBlockEnd.lowerBound])
            }
        }
        // Handle ``` ... ``` blocks
        else if let codeBlockStart = cleaned.range(of: "```") {
            cleaned = String(cleaned[codeBlockStart.upperBound...])
            if let codeBlockEnd = cleaned.range(of: "```") {
                cleaned = String(cleaned[..<codeBlockEnd.lowerBound])
            }
        }

        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // If still not starting with [ or {, try to find the JSON
        if !cleaned.hasPrefix("[") && !cleaned.hasPrefix("{") {
            if let arrayStart = cleaned.firstIndex(of: "[") {
                cleaned = String(cleaned[arrayStart...])
            } else if let objectStart = cleaned.firstIndex(of: "{") {
                cleaned = String(cleaned[objectStart...])
            }
        }

        return cleaned
    }

    // MARK: - Atom Conversion

    /// Convert correlation insight to Atom-compatible format
    public static func insightToAtomData(_ insight: ClaudeCorrelationInsight) -> [String: Any] {
        return [
            "type": "correlationInsight",
            "title": "Correlation: \(insight.variables.joined(separator: " ↔ "))",
            "body": insight.insight,
            "metadata": [
                "correlationId": insight.id,
                "variables": insight.variables,
                "direction": insight.direction,
                "strength": insight.strength,
                "effectSize": insight.effectSize,
                "action": insight.action,
                "confidence": insight.confidence,
                "supportingData": insight.supportingData,
                "generatedAt": ISO8601DateFormatter().string(from: Date())
            ]
        ]
    }

    /// Convert content idea to Atom-compatible format
    public static func contentIdeaToAtomData(_ idea: ContentIdea, project: String?) -> [String: Any] {
        var data: [String: Any] = [
            "type": "idea",
            "title": idea.title,
            "body": """
            **Angle:** \(idea.angle)

            **Why it works:** \(idea.rationale)

            **Suggested format:** \(idea.format)
            """,
            "metadata": [
                "source": "claude_synthesis",
                "format": idea.format,
                "generatedAt": ISO8601DateFormatter().string(from: Date())
            ]
        ]

        if let project = project {
            data["links"] = [
                ["type": "project", "query": project]
            ]
        }

        return data
    }

    /// Convert journal synthesis to Atom-compatible format
    public static func synthesisToAtomData(_ synthesis: JournalSynthesis, timeframe: String) -> [String: Any] {
        let body = """
        ## Key Themes
        \(synthesis.themes.map { "- \($0)" }.joined(separator: "\n"))

        ## Emotional Trajectory
        \(synthesis.emotionalTrajectory)

        ## Patterns Noticed
        \(synthesis.patterns.map { "- \($0)" }.joined(separator: "\n"))

        ## Suggested Actions
        \(synthesis.suggestedActions.map { "- \($0)" }.joined(separator: "\n"))

        ## Growth Areas
        \(synthesis.growthAreas.map { "- \($0)" }.joined(separator: "\n"))
        """

        return [
            "type": "journalInsight",
            "title": "Journal Synthesis: \(timeframe)",
            "body": body,
            "metadata": [
                "timeframe": timeframe,
                "themeCount": synthesis.themes.count,
                "actionCount": synthesis.suggestedActions.count,
                "generatedAt": ISO8601DateFormatter().string(from: Date())
            ]
        ]
    }
}

// MARK: - Insight Types

/// A correlation insight from Claude analysis
/// Note: Different from CausalityEngine.CorrelationInsight which is for UI display
public struct ClaudeCorrelationInsight: Codable, Sendable {
    public let id: String
    public let variables: [String]
    public let direction: String
    public let strength: String
    public let effectSize: Double
    public let insight: String
    public let action: String
    public let confidence: String
    public let supportingData: [String]

    public init(
        id: String,
        variables: [String],
        direction: String,
        strength: String,
        effectSize: Double,
        insight: String,
        action: String,
        confidence: String,
        supportingData: [String]
    ) {
        self.id = id
        self.variables = variables
        self.direction = direction
        self.strength = strength
        self.effectSize = effectSize
        self.insight = insight
        self.action = action
        self.confidence = confidence
        self.supportingData = supportingData
    }
}

/// Response from a query operation (for Claude API)
/// Note: Different from VoiceAtom.QueryResponse which is for voice responses
public struct ClaudeQueryResponse: Codable, Sendable {
    public let queryType: String
    public let result: String
    public let metadata: [String: String]?

    public init(queryType: String, result: String, metadata: [String: String]?) {
        self.queryType = queryType
        self.result = result
        self.metadata = metadata
    }
}

// MARK: - Deep Work Summary (for ToolExecutor)

/// Summary of a deep work session
public struct DeepWorkSummary: Codable, Sendable {
    public let sessionId: String
    public let durationMinutes: Int
    public let xpEarned: Int
    public let focusScore: Double
    public let distractions: Int

    public init(sessionId: String, durationMinutes: Int, xpEarned: Int, focusScore: Double, distractions: Int) {
        self.sessionId = sessionId
        self.durationMinutes = durationMinutes
        self.xpEarned = xpEarned
        self.focusScore = focusScore
        self.distractions = distractions
    }
}
