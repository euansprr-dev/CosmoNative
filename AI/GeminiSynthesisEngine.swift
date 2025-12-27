// CosmoOS/AI/GeminiSynthesisEngine.swift
// Gemini 3 Pro synthesis via OpenRouter API
// Handles creative generation, deep synthesis, and cross-domain analysis
// Supports streaming for real-time UI feedback
// macOS 26+ optimized

import Foundation

// MARK: - Synthesis Request

/// Request for Gemini synthesis
public struct SynthesisRequest: Sendable {
    public let userQuery: String
    public let intent: ClassifiedVoiceIntent
    public let contextSize: ContextSize
    public let hotContext: HotContext?
    public let specificEntities: [ContextEntityRef]?

    public init(
        userQuery: String,
        intent: ClassifiedVoiceIntent,
        contextSize: ContextSize,
        hotContext: HotContext? = nil,
        specificEntities: [ContextEntityRef]? = nil
    ) {
        self.userQuery = userQuery
        self.intent = intent
        self.contextSize = contextSize
        self.hotContext = hotContext
        self.specificEntities = specificEntities
    }
}

// NOTE: SynthesisResult and SuggestedAction are defined in ContextAssembler.swift

// MARK: - Gemini Synthesis Engine

/// Handles Gemini 3 Pro API calls via OpenRouter
public actor GeminiSynthesisEngine {

    // MARK: - Singleton

    public static let shared = GeminiSynthesisEngine()

    // MARK: - OpenRouter Configuration

    private let baseURL = "https://openrouter.ai/api/v1"
    private let model = "google/gemini-3-flash-preview"  // Faster, same accuracy
    private let fallbackModel = "google/gemini-2.5-pro-preview"  // Fallback to Pro if needed

    private var apiKey: String? {
        APIKeys.openRouter
    }

    // MARK: - Usage Tracking

    private var sessionTokensUsed: Int = 0
    private var sessionCost: Double = 0.0
    private var requestCount: Int = 0

    // MARK: - Configuration

    private let defaultTemperature: Double = 0.7
    private let defaultMaxTokens: Int = 4096
    private let streamingChunkSize: Int = 100

    // MARK: - Initialization

    private init() {}

    // MARK: - Main Synthesis API

    /// Synthesize content using Gemini (non-streaming)
    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        let startTime = Date()

        // Assemble context
        let config = AssemblyConfig.from(contextSize: request.contextSize)
        let context = try await ContextAssembler.shared.assemble(
            query: request.userQuery,
            config: config,
            hotContext: request.hotContext
        )

        // Get intent-specific prompt
        let prompt = GeminiPrompts.prompt(
            for: request.intent,
            query: request.userQuery,
            context: context.relevantContent
        )

        // Call OpenRouter API
        let response = try await callGemini(
            prompt: prompt,
            systemPrompt: context.systemPrompt,
            streaming: false
        )

        let latencyMs = Date().timeIntervalSince(startTime) * 1000

        // Parse suggested actions from response
        let suggestedActions = parseSuggestedActions(from: response.content)

        // Update usage tracking
        sessionTokensUsed += response.tokensUsed
        requestCount += 1

        ConsoleLog.info(
            "GeminiSynthesis: \(response.tokensUsed) tokens in \(String(format: "%.0f", latencyMs))ms",
            subsystem: .voice
        )

        return SynthesisResult(
            content: response.content,
            sources: context.sources,
            tokensUsed: response.tokensUsed,
            latencyMs: latencyMs,
            suggestedActions: suggestedActions
        )
    }

    /// Synthesize content with streaming (for typewriter effect)
    public func synthesizeStreaming(
        _ request: SynthesisRequest,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> SynthesisResult {
        let startTime = Date()

        // Assemble context
        let config = AssemblyConfig.from(contextSize: request.contextSize)
        let context = try await ContextAssembler.shared.assemble(
            query: request.userQuery,
            config: config,
            hotContext: request.hotContext
        )

        // Get intent-specific prompt
        let prompt = GeminiPrompts.prompt(
            for: request.intent,
            query: request.userQuery,
            context: context.relevantContent
        )

        // Call OpenRouter API with streaming
        let response = try await callGeminiStreaming(
            prompt: prompt,
            systemPrompt: context.systemPrompt,
            onChunk: onChunk
        )

        let latencyMs = Date().timeIntervalSince(startTime) * 1000

        // Parse suggested actions from response
        let suggestedActions = parseSuggestedActions(from: response.content)

        // Update usage tracking
        sessionTokensUsed += response.tokensUsed
        requestCount += 1

        ConsoleLog.info(
            "GeminiSynthesis (streaming): \(response.tokensUsed) tokens in \(String(format: "%.0f", latencyMs))ms",
            subsystem: .voice
        )

        return SynthesisResult(
            content: response.content,
            sources: context.sources,
            tokensUsed: response.tokensUsed,
            latencyMs: latencyMs,
            suggestedActions: suggestedActions
        )
    }

    // MARK: - OpenRouter API

    private struct GeminiResponse {
        let content: String
        let tokensUsed: Int
    }

    private func callGemini(
        prompt: String,
        systemPrompt: String,
        streaming: Bool
    ) async throws -> GeminiResponse {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CosmoOS Generative Intelligence", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": defaultTemperature,
            "max_tokens": defaultMaxTokens,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            ConsoleLog.error("Gemini API error \(httpResponse.statusCode): \(errorText)", subsystem: .voice)

            // Try fallback model on specific errors
            if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                return try await callGeminiFallback(prompt: prompt, systemPrompt: systemPrompt)
            }

            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GeminiError.parsingError
        }

        // Extract token usage
        let usage = json["usage"] as? [String: Any]
        let totalTokens = usage?["total_tokens"] as? Int ?? 0

        return GeminiResponse(content: content, tokensUsed: totalTokens)
    }

    private func callGeminiStreaming(
        prompt: String,
        systemPrompt: String,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> GeminiResponse {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CosmoOS Generative Intelligence", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": defaultTemperature,
            "max_tokens": defaultMaxTokens,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Use bytes(for:) for streaming
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // For streaming errors, we need to collect the error message
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        // Process streaming response
        var fullContent = ""
        var totalTokens = 0

        for try await line in bytes.lines {
            // Skip empty lines and "data: [DONE]"
            guard line.hasPrefix("data: "),
                  !line.contains("[DONE]") else {
                continue
            }

            let jsonString = String(line.dropFirst(6))

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            fullContent += content
            onChunk(content)

            // Extract usage if present (usually in final chunk)
            if let usage = json["usage"] as? [String: Any],
               let tokens = usage["total_tokens"] as? Int {
                totalTokens = tokens
            }
        }

        // Estimate tokens if not provided
        if totalTokens == 0 {
            totalTokens = Int(Float(fullContent.count) * 0.25) + Int(Float(prompt.count) * 0.25)
        }

        return GeminiResponse(content: fullContent, tokensUsed: totalTokens)
    }

    private func callGeminiFallback(
        prompt: String,
        systemPrompt: String
    ) async throws -> GeminiResponse {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        ConsoleLog.warning("Falling back to \(fallbackModel)", subsystem: .voice)

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CosmoOS Generative Intelligence", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": fallbackModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": defaultTemperature,
            "max_tokens": defaultMaxTokens,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GeminiError.parsingError
        }

        let usage = json["usage"] as? [String: Any]
        let totalTokens = usage?["total_tokens"] as? Int ?? 0

        return GeminiResponse(content: content, tokensUsed: totalTokens)
    }

    // MARK: - Action Parsing

    private func parseSuggestedActions(from content: String) -> [SuggestedAction]? {
        // Look for action patterns in the response
        var actions: [SuggestedAction] = []

        // Pattern: "Create idea: <title>"
        let ideaPattern = /Create idea[:\s]+(.+)/
        if let match = content.firstMatch(of: ideaPattern) {
            actions.append(SuggestedAction(
                type: .createIdea,
                title: String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        // Pattern: "Add to swipe file: <content>"
        let swipePattern = /Add to swipe file[:\s]+(.+)/
        if let match = content.firstMatch(of: swipePattern) {
            actions.append(SuggestedAction(
                type: .addToSwipeFile,
                title: String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        // Pattern: "Create connection: <title>"
        let connectionPattern = /Create connection[:\s]+(.+)/
        if let match = content.firstMatch(of: connectionPattern) {
            actions.append(SuggestedAction(
                type: .createConnection,
                title: String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        return actions.isEmpty ? nil : actions
    }

    // MARK: - Usage Statistics

    /// Get current session usage stats
    public func getUsageStats() -> (tokensUsed: Int, requestCount: Int, estimatedCost: Double) {
        // Estimate cost based on Gemini Pro pricing via OpenRouter
        // These are approximate - check OpenRouter for current rates
        let inputCostPer1k = 0.00125  // $1.25 per million
        let outputCostPer1k = 0.005   // $5 per million

        let estimatedCost = Double(sessionTokensUsed) / 1000.0 * (inputCostPer1k + outputCostPer1k) / 2

        return (sessionTokensUsed, requestCount, estimatedCost)
    }

    /// Reset session usage tracking
    public func resetUsageStats() {
        sessionTokensUsed = 0
        sessionCost = 0.0
        requestCount = 0
    }

    // MARK: - Health Check

    /// Check if Gemini API is available
    public func isAvailable() async -> Bool {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return false
        }

        // Simple health check - just verify API key format
        return apiKey.count > 20
    }
}

// MARK: - Gemini Errors

public enum GeminiError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingError
    case rateLimited
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenRouter API key configured. Add OPENROUTER_API_KEY to your environment."
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .apiError(let code, let message):
            return "Gemini API error (\(code)): \(message)"
        case .parsingError:
            return "Failed to parse Gemini response"
        case .rateLimited:
            return "Rate limited by Gemini API"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    /// Posted when a streaming chunk is received from Gemini
    static let geminiStreamChunk = Notification.Name("geminiStreamChunk")
}
