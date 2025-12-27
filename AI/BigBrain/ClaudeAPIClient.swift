// CosmoOS/AI/BigBrain/ClaudeAPIClient.swift
// Claude API client for complex reasoning tasks (Big Brain)
// Replaces GeminiAPI for correlation analysis and content synthesis

import Foundation
import os.log

// MARK: - Claude API Client

/// Claude API client for complex reasoning tasks.
///
/// This actor handles all interactions with Claude Sonnet 4.5 via OpenRouter API.
/// It's the "Big Brain" of CosmoOS - handling tasks that require genuine reasoning:
/// - Correlation analysis across dimensions
/// - Content synthesis and idea generation
/// - Deep insight extraction from journals
/// - Pattern recognition across behavioral data
///
/// Usage:
/// ```swift
/// let client = ClaudeAPIClient.shared
/// client.configure(apiKey: "sk-...")
/// let response = try await client.generate(prompt: "Analyze...")
/// ```
public actor ClaudeAPIClient {

    // MARK: - Singleton

    public static let shared = ClaudeAPIClient()

    // MARK: - Configuration

    private let logger = Logger(subsystem: "com.cosmo.bigbrain", category: "ClaudeAPI")

    /// OpenRouter API base URL
    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Model identifier - Claude Sonnet 4.5 (best balance of speed and capability)
    private let modelId = "anthropic/claude-sonnet-4"

    /// API key (should be set from environment or secure storage)
    private var apiKey: String?

    /// HTTP session for API calls
    private let session: URLSession

    /// Request timeout (Claude can take a few seconds for complex reasoning)
    private let timeout: TimeInterval = 30

    // MARK: - Metrics

    private var totalRequests: Int = 0
    private var successfulRequests: Int = 0
    private var totalLatencyMs: Double = 0
    private var averageTokensGenerated: Int = 0

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        // Try to load API key from centralized APIKeys (Keychain + environment fallback)
        if let key = APIKeys.openRouter {
            self.apiKey = key
            logger.info("ClaudeAPIClient initialized with API key from APIKeys")
        } else {
            logger.warning("ClaudeAPIClient: No OpenRouter API key configured")
        }
    }

    // MARK: - Configuration

    /// Configure the Claude API client
    public func configure(apiKey: String) {
        self.apiKey = apiKey
        logger.info("ClaudeAPIClient configured with API key")
    }

    /// Check if client is configured
    public func isConfigured() -> Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }

    // MARK: - Generation

    /// Generate a response from Claude
    /// - Parameters:
    ///   - prompt: The prompt to send to Claude
    ///   - maxTokens: Maximum tokens to generate (default 2000)
    ///   - temperature: Temperature for generation (default 0.7)
    /// - Returns: Generated response text
    public func generate(
        prompt: String,
        maxTokens: Int = 2000,
        temperature: Double = 0.7
    ) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw ClaudeAPIError.notConfigured
        }

        let startTime = Date()
        totalRequests += 1

        // Build request
        let request = ClaudeRequest(
            model: modelId,
            messages: [
                ClaudeMessage(role: "user", content: prompt)
            ],
            maxTokens: maxTokens,
            temperature: temperature
        )

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        urlRequest.setValue("CosmoOS BigBrain", forHTTPHeaderField: "X-Title")

        logger.debug("Sending request to Claude API...")

        // Make request
        let (data, response) = try await session.data(for: urlRequest)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Claude API error: \(httpResponse.statusCode) - \(errorBody)")
            throw ClaudeAPIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse response
        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let content = claudeResponse.choices.first?.message.content else {
            throw ClaudeAPIError.emptyResponse
        }

        // Update metrics
        let latencyMs = Date().timeIntervalSince(startTime) * 1000
        successfulRequests += 1
        totalLatencyMs += latencyMs

        logger.info("Claude response in \(String(format: "%.0f", latencyMs))ms (\(content.count) chars)")

        return content
    }

    /// Generate with a system prompt
    public func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 2000,
        temperature: Double = 0.7
    ) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw ClaudeAPIError.notConfigured
        }

        let startTime = Date()
        totalRequests += 1

        let request = ClaudeRequest(
            model: modelId,
            messages: [
                ClaudeMessage(role: "system", content: systemPrompt),
                ClaudeMessage(role: "user", content: userPrompt)
            ],
            maxTokens: maxTokens,
            temperature: temperature
        )

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        urlRequest.setValue("CosmoOS BigBrain", forHTTPHeaderField: "X-Title")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAPIError.apiError(statusCode: statusCode, message: errorBody)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let content = claudeResponse.choices.first?.message.content else {
            throw ClaudeAPIError.emptyResponse
        }

        let latencyMs = Date().timeIntervalSince(startTime) * 1000
        successfulRequests += 1
        totalLatencyMs += latencyMs

        logger.info("Claude response in \(String(format: "%.0f", latencyMs))ms")

        return content
    }

    // MARK: - Correlation Analysis

    /// Run correlation analysis on dimensions
    /// - Parameters:
    ///   - dimensions: Which dimensions to analyze
    ///   - dataContext: The data context for analysis
    /// - Returns: Array of correlation insights
    public func analyzeCorrelations(
        dimensions: [String],
        dataContext: CorrelationDataContext
    ) async throws -> [ClaudeCorrelationInsight] {
        let prompt = CorrelationRequestBuilder.build(
            dimensions: dimensions,
            context: dataContext
        )

        let response = try await generate(
            prompt: prompt,
            maxTokens: 3000,
            temperature: 0.5  // Lower temp for analytical tasks
        )

        return try InsightProcessor.parseCorrelationInsights(response)
    }

    /// Trigger correlation analysis (called by FunctionGemma)
    public func triggerCorrelationAnalysis(
        dimensions: [String],
        triggerReason: String
    ) async throws -> String {
        // This would be called by ToolExecutor when FunctionGemma routes here
        // For now, return a correlation ID that can be tracked

        let correlationId = UUID().uuidString

        logger.info("Correlation analysis triggered: \(correlationId) for \(dimensions.joined(separator: ", "))")

        // In a full implementation, this would:
        // 1. Fetch data from AtomRepository for the dimensions
        // 2. Build the correlation context
        // 3. Call analyzeCorrelations()
        // 4. Store results as Atoms
        // 5. Return the correlation ID for tracking

        return correlationId
    }

    // MARK: - Content Synthesis

    /// Generate content ideas
    public func generateContentIdeas(
        topic: String,
        context: ContentContext,
        count: Int = 5
    ) async throws -> [ContentIdea] {
        let prompt = """
        Generate \(count) unique content ideas about "\(topic)".

        Context:
        - Platform: \(context.platform)
        - Audience: \(context.audience)
        - Past Performance: \(context.pastPerformanceSummary)
        - Tone: \(context.preferredTone)

        For each idea, provide:
        1. Title/hook
        2. Key angle
        3. Why it would resonate
        4. Suggested format

        Return as JSON array with fields: title, angle, rationale, format
        """

        let response = try await generate(prompt: prompt, temperature: 0.8)

        return try InsightProcessor.parseContentIdeas(response)
    }

    /// Synthesize insights from journal entries
    public func synthesizeJournalInsights(
        entries: [JournalEntrySummary],
        timeframe: String
    ) async throws -> JournalSynthesis {
        let entriesText = entries.map { "[\($0.date)] \($0.type): \($0.content)" }.joined(separator: "\n")

        let prompt = """
        Analyze these journal entries from \(timeframe) and provide insights:

        \(entriesText)

        Provide:
        1. Key themes (max 5)
        2. Emotional trajectory
        3. Patterns noticed
        4. Suggested actions
        5. Notable growth areas

        Return as structured JSON.
        """

        let response = try await generate(prompt: prompt, temperature: 0.6)

        return try InsightProcessor.parseJournalSynthesis(response)
    }

    // MARK: - Metrics

    /// Get client metrics
    public func getMetrics() -> ClaudeAPIMetrics {
        let avgLatency = totalRequests > 0 ? totalLatencyMs / Double(totalRequests) : 0
        let successRate = totalRequests > 0 ? Double(successfulRequests) / Double(totalRequests) : 0

        return ClaudeAPIMetrics(
            totalRequests: totalRequests,
            successfulRequests: successfulRequests,
            averageLatencyMs: avgLatency,
            successRate: successRate,
            isConfigured: isConfigured()
        )
    }
}

// MARK: - Request/Response Types

struct ClaudeRequest: Encodable {
    let model: String
    let messages: [ClaudeMessage]
    let maxTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

struct ClaudeResponse: Decodable {
    let id: String?
    let choices: [ClaudeChoice]
    let usage: ClaudeUsage?
}

struct ClaudeChoice: Decodable {
    let message: ClaudeMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct ClaudeUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Metrics

public struct ClaudeAPIMetrics: Codable, Sendable {
    public let totalRequests: Int
    public let successfulRequests: Int
    public let averageLatencyMs: Double
    public let successRate: Double
    public let isConfigured: Bool
}

// MARK: - Errors

public enum ClaudeAPIError: Error, LocalizedError {
    case notConfigured
    case invalidResponse
    case emptyResponse
    case apiError(statusCode: Int, message: String)
    case parsingError(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Claude API not configured. Set OPENROUTER_API_KEY environment variable."
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .emptyResponse:
            return "Empty response from Claude API"
        case .apiError(let statusCode, let message):
            return "Claude API error (\(statusCode)): \(message)"
        case .parsingError(let message):
            return "Failed to parse Claude response: \(message)"
        }
    }
}

// MARK: - Context Types

/// Context for content generation
public struct ContentContext: Codable, Sendable {
    public let platform: String
    public let audience: String
    public let pastPerformanceSummary: String
    public let preferredTone: String

    public init(platform: String, audience: String, pastPerformanceSummary: String, preferredTone: String) {
        self.platform = platform
        self.audience = audience
        self.pastPerformanceSummary = pastPerformanceSummary
        self.preferredTone = preferredTone
    }
}

// Note: JournalEntrySummary is defined in SanctuaryDataAggregator.swift

/// Synthesized insights from journal entries
public struct JournalSynthesis: Codable, Sendable {
    public let themes: [String]
    public let emotionalTrajectory: String
    public let patterns: [String]
    public let suggestedActions: [String]
    public let growthAreas: [String]

    public init(themes: [String], emotionalTrajectory: String, patterns: [String], suggestedActions: [String], growthAreas: [String]) {
        self.themes = themes
        self.emotionalTrajectory = emotionalTrajectory
        self.patterns = patterns
        self.suggestedActions = suggestedActions
        self.growthAreas = growthAreas
    }
}

/// A generated content idea
public struct ContentIdea: Codable, Sendable {
    public let title: String
    public let angle: String
    public let rationale: String
    public let format: String

    public init(title: String, angle: String, rationale: String, format: String) {
        self.title = title
        self.angle = angle
        self.rationale = rationale
        self.format = format
    }
}
