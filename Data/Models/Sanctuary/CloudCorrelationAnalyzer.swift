// CosmoOS/Data/Models/Sanctuary/CloudCorrelationAnalyzer.swift
// Cloud Correlation Analyzer - Uses LLMs for deep pattern recognition
// Finds insights that statistical correlation alone cannot detect

import Foundation
import GRDB

// MARK: - Cloud Model Configuration

/// Supported cloud model providers
public enum CloudModelProvider: String, Codable, Sendable {
    case gemini = "gemini"
    case claude = "claude"
    case openai = "openai"
}

/// Configuration for cloud model analysis
public struct CloudAnalysisConfig: Codable, Sendable {
    public let provider: CloudModelProvider
    public let modelId: String
    public let maxTokens: Int
    public let temperature: Double
    public let apiEndpoint: String

    public static var defaultGemini: CloudAnalysisConfig {
        CloudAnalysisConfig(
            provider: .gemini,
            modelId: "gemini-1.5-flash",
            maxTokens: 4096,
            temperature: 0.3,
            apiEndpoint: "https://generativelanguage.googleapis.com/v1beta/models"
        )
    }

    public static var defaultClaude: CloudAnalysisConfig {
        CloudAnalysisConfig(
            provider: .claude,
            modelId: "claude-3-5-sonnet-20241022",
            maxTokens: 4096,
            temperature: 0.3,
            apiEndpoint: "https://api.anthropic.com/v1/messages"
        )
    }
}

// MARK: - Analysis Request

/// Serialized data for cloud analysis
public struct CorrelationAnalysisRequest: Codable, Sendable {
    public let dateRange: DateRange
    public let dailyMetrics: [DailyMetricSummary]
    public let existingInsights: [InsightSummary]
    public let userContext: UserContext

    public struct DateRange: Codable, Sendable {
        public let start: String
        public let end: String
        public let totalDays: Int
    }

    public struct DailyMetricSummary: Codable, Sendable {
        public let date: String
        public let metrics: [String: Double]
    }

    public struct InsightSummary: Codable, Sendable {
        public let sourceMetric: String
        public let targetMetric: String
        public let correlationType: String
        public let strength: String
        public let confidence: String
        public let occurrences: Int
    }

    public struct UserContext: Codable, Sendable {
        public let primaryGoals: [String]
        public let focusAreas: [String]
        public let recentTopics: [String]
    }
}

// MARK: - Analysis Response

/// Parsed response from cloud analysis
public struct CloudAnalysisResponse: Codable, Sendable {
    public let insights: [DiscoveredInsight]
    public let patterns: [DiscoveredPattern]
    public let recommendations: [ActionableRecommendation]
    public let analysisConfidence: Double
    public let processingNotes: String?

    public struct DiscoveredInsight: Codable, Sendable {
        public let sourceMetrics: [String]
        public let targetMetric: String
        public let relationship: String
        public let lagDays: Int?
        public let confidence: Double
        public let explanation: String
        public let evidence: String
    }

    public struct DiscoveredPattern: Codable, Sendable {
        public let patternType: String
        public let description: String
        public let metrics: [String]
        public let strength: Double
        public let actionable: Bool
    }

    public struct ActionableRecommendation: Codable, Sendable {
        public let action: String
        public let expectedImpact: String
        public let impactMetrics: [String]
        public let confidence: Double
        public let priority: Int
    }
}

// MARK: - Cloud Correlation Analyzer

/// Analyzes correlation data using cloud LLMs for deeper insights
public actor CloudCorrelationAnalyzer {

    // MARK: - Dependencies

    private let database: any DatabaseWriter
    private var config: CloudAnalysisConfig

    // MARK: - State

    private var lastAnalysisDate: Date?
    private var cachedResponse: CloudAnalysisResponse?

    // MARK: - Initialization

    @MainActor
    public init(
        database: (any DatabaseWriter)? = nil,
        config: CloudAnalysisConfig = .defaultGemini
    ) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
        self.config = config
    }

    // MARK: - Configuration

    public func updateConfig(_ newConfig: CloudAnalysisConfig) {
        self.config = newConfig
    }

    // MARK: - Analysis

    /// Run cloud-based correlation analysis
    public func analyzeCorrelations(
        dailyAggregates: [DailyMetricAggregate],
        existingInsights: [CorrelationInsight],
        semanticMetrics: [DailySemanticMetrics]
    ) async throws -> CloudAnalysisResponse {
        // Build the analysis request
        let request = buildAnalysisRequest(
            dailyAggregates: dailyAggregates,
            existingInsights: existingInsights,
            semanticMetrics: semanticMetrics
        )

        // Generate the prompt
        let prompt = generateAnalysisPrompt(for: request)

        // Call the appropriate API
        let response: CloudAnalysisResponse
        switch config.provider {
        case .gemini:
            response = try await callGeminiAPI(prompt: prompt)
        case .claude:
            response = try await callClaudeAPI(prompt: prompt)
        case .openai:
            response = try await callOpenAIAPI(prompt: prompt)
        }

        // Cache and return
        cachedResponse = response
        lastAnalysisDate = Date()

        return response
    }

    // MARK: - Request Building

    private func buildAnalysisRequest(
        dailyAggregates: [DailyMetricAggregate],
        existingInsights: [CorrelationInsight],
        semanticMetrics: [DailySemanticMetrics]
    ) -> CorrelationAnalysisRequest {
        let dateFormatter = ISO8601DateFormatter()

        // Convert daily aggregates to summaries
        var dailySummaries: [CorrelationAnalysisRequest.DailyMetricSummary] = []
        for aggregate in dailyAggregates {
            var metrics = aggregate.metrics

            // Add semantic metrics for the same day
            if let semantic = semanticMetrics.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: aggregate.date)
            }) {
                metrics["journal_valence"] = semantic.avgValence
                metrics["journal_energy"] = semantic.avgEnergy
                metrics["journal_word_count"] = Double(semantic.totalWordCount)
                metrics["goal_mentions"] = Double(semantic.goalCount)
                metrics["fear_mentions"] = Double(semantic.fearCount)
                metrics["gratitude_mentions"] = Double(semantic.gratitudeCount)
            }

            dailySummaries.append(CorrelationAnalysisRequest.DailyMetricSummary(
                date: dateFormatter.string(from: aggregate.date),
                metrics: metrics
            ))
        }

        // Convert existing insights
        let insightSummaries = existingInsights.map { insight in
            CorrelationAnalysisRequest.InsightSummary(
                sourceMetric: insight.sourceMetric,
                targetMetric: insight.targetMetric,
                correlationType: insight.correlationType.rawValue,
                strength: insight.strength.rawValue,
                confidence: insight.confidence.rawValue,
                occurrences: insight.occurrences
            )
        }

        // Get date range
        let sortedDates = dailyAggregates.map { $0.date }.sorted()
        let dateRange = CorrelationAnalysisRequest.DateRange(
            start: dateFormatter.string(from: sortedDates.first ?? Date()),
            end: dateFormatter.string(from: sortedDates.last ?? Date()),
            totalDays: dailyAggregates.count
        )

        // User context from semantic analysis
        let topTopics = semanticMetrics
            .flatMap { _ in [String]() }  // Would aggregate from semantic extractions
            .prefix(10)
            .map { $0 }

        let userContext = CorrelationAnalysisRequest.UserContext(
            primaryGoals: [],  // Would come from user settings
            focusAreas: [],
            recentTopics: topTopics
        )

        return CorrelationAnalysisRequest(
            dateRange: dateRange,
            dailyMetrics: dailySummaries,
            existingInsights: insightSummaries,
            userContext: userContext
        )
    }

    // MARK: - Prompt Generation

    private func generateAnalysisPrompt(for request: CorrelationAnalysisRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let requestData = try? encoder.encode(request),
              let requestJSON = String(data: requestData, encoding: .utf8) else {
            return ""
        }

        return """
        You are an expert data analyst specializing in personal optimization and behavioral science.

        I'm providing you with \(request.dateRange.totalDays) days of personal metrics data from a Cognitive OS.
        Your task is to identify correlations, patterns, and actionable insights that would help the user optimize their life.

        ## Data Provided

        ```json
        \(requestJSON)
        ```

        ## Analysis Instructions

        1. **Cross-Metric Correlations**: Look for relationships between different metrics, especially:
           - Sleep quality → next-day performance metrics
           - Workout intensity → HRV and recovery
           - Journal sentiment → productivity and focus
           - Deep work duration → creative output

        2. **Lag Effects**: Identify delayed impacts (1-7 days later), such as:
           - "Heavy workout → lower HRV 1 day later → higher HRV 2-3 days later"
           - "Poor sleep → reduced focus next day"

        3. **Compound Patterns**: Find combinations that predict outcomes:
           - "7+ hours sleep AND morning workout → 40% higher focus score"

        4. **Threshold Effects**: Identify when metrics cross important boundaries:
           - "Below 6 hours sleep → everything suffers"
           - "Above 45min deep work → diminishing returns"

        5. **Weekly/Periodic Patterns**: Note day-of-week effects

        6. **Semantic Insights**: Use journal sentiment and content to explain why certain days were better/worse

        ## Response Format

        Respond with a JSON object matching this structure exactly:

        ```json
        {
          "insights": [
            {
              "sourceMetrics": ["metric1", "metric2"],
              "targetMetric": "target",
              "relationship": "positive|negative|compound|threshold",
              "lagDays": 0,
              "confidence": 0.85,
              "explanation": "Human-readable explanation",
              "evidence": "Specific data points supporting this"
            }
          ],
          "patterns": [
            {
              "patternType": "weekly|compound|threshold|trend",
              "description": "Pattern description",
              "metrics": ["metric1", "metric2"],
              "strength": 0.8,
              "actionable": true
            }
          ],
          "recommendations": [
            {
              "action": "Specific action to take",
              "expectedImpact": "What will improve",
              "impactMetrics": ["hrv", "focus_score"],
              "confidence": 0.75,
              "priority": 1
            }
          ],
          "analysisConfidence": 0.82,
          "processingNotes": "Any caveats or data quality issues"
        }
        ```

        Focus on insights the user couldn't easily notice themselves. Prioritize actionable, high-confidence findings.
        """
    }

    // MARK: - API Calls

    private func callGeminiAPI(prompt: String) async throws -> CloudAnalysisResponse {
        guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] else {
            throw CloudAnalysisError.missingAPIKey(provider: .gemini)
        }

        let url = URL(string: "\(config.apiEndpoint)/\(config.modelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": config.temperature,
                "maxOutputTokens": config.maxTokens,
                "responseMimeType": "application/json"
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CloudAnalysisError.apiError(message: "Gemini API returned error")
        }

        // Parse Gemini response structure
        struct GeminiResponse: Codable {
            struct Candidate: Codable {
                struct Content: Codable {
                    struct Part: Codable {
                        let text: String
                    }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let textContent = geminiResponse.candidates.first?.content.parts.first?.text else {
            throw CloudAnalysisError.invalidResponse
        }

        // Parse the JSON from the text content
        guard let jsonData = textContent.data(using: .utf8) else {
            throw CloudAnalysisError.invalidResponse
        }

        return try JSONDecoder().decode(CloudAnalysisResponse.self, from: jsonData)
    }

    private func callClaudeAPI(prompt: String) async throws -> CloudAnalysisResponse {
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
            throw CloudAnalysisError.missingAPIKey(provider: .claude)
        }

        let url = URL(string: config.apiEndpoint)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": config.modelId,
            "max_tokens": config.maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CloudAnalysisError.apiError(message: "Claude API returned error")
        }

        // Parse Claude response structure
        struct ClaudeResponse: Codable {
            struct Content: Codable {
                let type: String
                let text: String
            }
            let content: [Content]
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let textContent = claudeResponse.content.first?.text else {
            throw CloudAnalysisError.invalidResponse
        }

        // Extract JSON from response (might be wrapped in markdown code blocks)
        let jsonString = extractJSON(from: textContent)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw CloudAnalysisError.invalidResponse
        }

        return try JSONDecoder().decode(CloudAnalysisResponse.self, from: jsonData)
    }

    private func callOpenAIAPI(prompt: String) async throws -> CloudAnalysisResponse {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            throw CloudAnalysisError.missingAPIKey(provider: .openai)
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4-turbo-preview",
            "messages": [
                ["role": "system", "content": "You are an expert data analyst. Always respond with valid JSON."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CloudAnalysisError.apiError(message: "OpenAI API returned error")
        }

        // Parse OpenAI response
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let openaiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let content = openaiResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw CloudAnalysisError.invalidResponse
        }

        return try JSONDecoder().decode(CloudAnalysisResponse.self, from: jsonData)
    }

    // MARK: - Helpers

    private func extractJSON(from text: String) -> String {
        // Try to extract JSON from markdown code blocks
        if let start = text.range(of: "```json"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Or from regular code blocks
        if let start = text.range(of: "```"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find JSON object directly
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }

        return text
    }

    // MARK: - Cached Access

    public func getCachedResponse() -> CloudAnalysisResponse? {
        return cachedResponse
    }

    public func getLastAnalysisDate() -> Date? {
        return lastAnalysisDate
    }
}

// MARK: - Errors

public enum CloudAnalysisError: Error, LocalizedError {
    case missingAPIKey(provider: CloudModelProvider)
    case apiError(message: String)
    case invalidResponse
    case rateLimited
    case networkError(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Missing API key for \(provider.rawValue)"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidResponse:
            return "Invalid response from cloud model"
        case .rateLimited:
            return "Rate limited by cloud API"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
