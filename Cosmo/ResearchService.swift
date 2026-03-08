// CosmoOS/Cosmo/ResearchService.swift
// Web research via OpenRouter/Perplexity API
// This is the ONLY network-dependent feature - everything else is local-first

import Foundation

@MainActor
final class ResearchService {
    static let shared = ResearchService()

    // OpenRouter API configuration
    private let openRouterBaseURL = "https://openrouter.ai/api/v1"
    private let perplexityModel = "perplexity/sonar"

    // API key is loaded from Keychain via APIKeys
    private var apiKey: String? {
        APIKeys.openRouter
    }

    private init() {}

    // MARK: - Perform Research
    func performResearch(
        query: String,
        searchType: ResearchSearchType = .web,
        maxResults: Int = 5
    ) async throws -> ResearchResult {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ResearchError.noAPIKey
        }

        print("🔬 Research: Calling Perplexity via OpenRouter...")
        print("   Query: \(query)")
        print("   Type: \(searchType)")

        // Build the research prompt
        let prompt = buildResearchPrompt(query: query, searchType: searchType, maxResults: maxResults)

        // Make API request
        let response = try await callOpenRouter(prompt: prompt, model: perplexityModel)

        // Parse response into structured findings
        let result = parseResearchResponse(response, query: query)

        print("✅ Research complete: \(result.findings.count) findings")

        return result
    }

    // MARK: - Build Research Prompt
    private func buildResearchPrompt(
        query: String,
        searchType: ResearchSearchType,
        maxResults: Int
    ) -> String {
        switch searchType {
        case .web:
            return """
            Search the web for current, accurate information about: \(query)

            Please provide:
            1. A concise summary (2-3 sentences)
            2. Up to \(maxResults) key findings with sources
            3. Any relevant statistics or data points

            Format your response as JSON with this structure:
            {
              "summary": "Brief overview...",
              "findings": [
                {
                  "title": "Finding title",
                  "snippet": "Key information...",
                  "source": "Source name",
                  "url": "https://...",
                  "confidence": "high/medium/low"
                }
              ]
            }
            """

        case .reddit:
            return """
            Search Reddit for discussions and opinions about: \(query)

            Focus on:
            - Real user experiences and opinions
            - Common pain points and problems
            - Popular solutions and recommendations

            Please provide up to \(maxResults) relevant Reddit discussions.

            Format as JSON:
            {
              "summary": "What Reddit users are saying...",
              "findings": [
                {
                  "title": "Discussion topic",
                  "snippet": "Key quote or summary...",
                  "source": "r/subreddit",
                  "url": "https://reddit.com/...",
                  "upvotes": 0,
                  "sentiment": "positive/negative/neutral"
                }
              ]
            }
            """

        case .academic:
            return """
            Search for academic and research papers about: \(query)

            Focus on:
            - Recent peer-reviewed research
            - Key studies and findings
            - Expert consensus

            Provide up to \(maxResults) relevant academic sources.

            Format as JSON:
            {
              "summary": "Research overview...",
              "findings": [
                {
                  "title": "Paper title",
                  "snippet": "Key finding...",
                  "source": "Journal/Institution",
                  "authors": "Author names",
                  "year": 2024,
                  "citations": 0
                }
              ]
            }
            """

        case .news:
            return """
            Search for recent news about: \(query)

            Focus on:
            - Recent developments (last 30 days preferred)
            - Multiple perspectives
            - Verified sources

            Provide up to \(maxResults) news articles.

            Format as JSON:
            {
              "summary": "Recent news overview...",
              "findings": [
                {
                  "title": "Article headline",
                  "snippet": "Key information...",
                  "source": "Publication name",
                  "url": "https://...",
                  "date": "2024-12-11"
                }
              ]
            }
            """
        }
    }

    // MARK: - Content Analysis (Claude Sonnet 4.5)

    /// Analyze content with Claude Sonnet 4.5 via OpenRouter — used for deep swipe analysis
    func analyzeContent(prompt: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ResearchError.noAPIKey
        }

        let claudeModel = "anthropic/claude-sonnet-4.5"
        return try await callOpenRouter(
            prompt: prompt,
            model: claudeModel,
            maxTokens: 4000,
            temperature: 0.2
        )
    }

    // MARK: - Tier-Aware Analysis

    /// Analyze content using a specific model tier for cost/quality optimization.
    /// Defaults to `.strategist` (Sonnet 4.5) when no tier is specified.
    func analyze(
        prompt: String,
        systemPrompt: String? = nil,
        tier: AgentModelTier = .strategist,
        maxTokens: Int? = nil
    ) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ResearchError.noAPIKey
        }

        let resolvedMaxTokens = maxTokens ?? tier.maxTokens

        return try await callOpenRouter(
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: tier.modelId,
            maxTokens: resolvedMaxTokens,
            temperature: 0.3
        )
    }

    /// Analyze with a specific model ID (e.g., "google/gemini-3.1-flash-lite-preview")
    func analyze(
        prompt: String,
        systemPrompt: String? = nil,
        model: String,
        maxTokens: Int = 2000,
        temperature: Double = 0.3
    ) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ResearchError.noAPIKey
        }
        return try await callOpenRouter(
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature
        )
    }

    // MARK: - Generate With Prompt Caching

    /// Send a request with structured system content blocks, each with optional cache_control.
    /// This enables Anthropic prompt caching via OpenRouter — stable context layers are cached
    /// between requests, dramatically reducing cost and latency for mega-context prompts.
    ///
    /// - Parameters:
    ///   - systemBlocks: Structured prompt blocks. Each becomes a content block
    ///     in the system message. When `cacheControl` is true, a prompt-cache boundary
    ///     is added and optional `ttl` is passed through to the provider.
    ///   - messages: Conversation messages (user/assistant turns)
    ///   - model: OpenRouter model ID (e.g., "anthropic/claude-opus-4-6")
    ///   - maxTokens: Maximum tokens in the response
    ///   - temperature: Sampling temperature
    ///   - onToken: Optional streaming callback for token-by-token response. When provided,
    ///     the request uses SSE streaming and calls this closure for each token.
    func generateWithCaching(
        systemBlocks: [PromptCacheBlock],
        messages: [[String: Any]],
        model: String,
        maxTokens: Int = 8192,
        temperature: Double = 0.3,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ResearchError.noAPIKey
        }

        let url = URL(string: "\(openRouterBaseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CosmoOS", forHTTPHeaderField: "X-Title")

        let systemContentBlocks = buildSystemContentBlocks(systemBlocks)

        let systemMessage: [String: Any] = [
            "role": "system",
            "content": systemContentBlocks
        ]

        var allMessages: [[String: Any]] = [systemMessage]
        allMessages.append(contentsOf: messages)

        let useStreaming = onToken != nil

        var body: [String: Any] = [
            "model": model,
            "messages": allMessages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        if useStreaming {
            body["stream"] = true
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("🌐 [ResearchService.generateWithCaching] Request body size: \(request.httpBody?.count ?? 0) bytes")

        if useStreaming, let tokenHandler = onToken {
            return try await streamOpenRouter(request: request, onToken: tokenHandler)
        } else {
            return try await executeOpenRouter(request: request)
        }
    }

    func generateWithCaching(
        systemBlocks: [(content: String, cacheControl: Bool)],
        messages: [[String: Any]],
        model: String,
        maxTokens: Int = 8192,
        temperature: Double = 0.3,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await generateWithCaching(
            systemBlocks: systemBlocks.map {
                PromptCacheBlock(content: $0.content, cacheControl: $0.cacheControl)
            },
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            onToken: onToken
        )
    }

    // MARK: - Generate With Tool Use

    /// Send a request with Claude tool_use support via OpenRouter.
    /// Uses structured system content blocks with optional cache_control (same as generateWithCaching)
    /// but adds tool definitions and parses tool_use content blocks from the response.
    ///
    /// When tools are provided, this method uses non-streaming mode for reliable tool_use parsing.
    /// OpenRouter/Anthropic may return `content` as a plain string (text-only responses) or as
    /// an array of content blocks (when tools are used). Both formats are handled.
    func generateWithTools(
        systemBlocks: [PromptCacheBlock],
        messages: [[String: Any]],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int = 8192,
        temperature: Double = 0.3,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> ClaudeToolUseResponse {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ResearchError.noAPIKey
        }

        let url = URL(string: "\(openRouterBaseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120 // Opus can take a while — generous timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CosmoOS", forHTTPHeaderField: "X-Title")

        let systemContentBlocks = buildSystemContentBlocks(systemBlocks)

        let systemMessage: [String: Any] = [
            "role": "system",
            "content": systemContentBlocks
        ]

        var allMessages: [[String: Any]] = [systemMessage]
        allMessages.append(contentsOf: messages)

        // Non-streaming for reliable tool_use parsing
        let effectiveTools = cacheControlBreakpointCount(in: systemBlocks) >= 4
            ? tools
            : cacheToolDefinitions(tools, ttl: "1h")

        let body: [String: Any] = [
            "model": model,
            "messages": allMessages,
            "tools": effectiveTools,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        print("🌐 [ResearchService.generateWithTools] Sending request to \(model)")
        print("🌐 [ResearchService.generateWithTools] System blocks: \(systemBlocks.count), messages: \(messages.count), tools: \(tools.count)")

        // === EVERYTHING below runs OFF the main actor ===
        // JSON body serialization, network call, AND response parsing all happen in a
        // detached task. This prevents the main thread from blocking on any of these
        // operations, avoiding beach-ball freezes even with large conversation histories.
        let capturedRequest = request
        let capturedBody = body

        let parsed: ClaudeToolUseResponse = try await Task.detached(priority: .userInitiated) {
            // 1. Serialize JSON body (can be large with full conversation history)
            var req = capturedRequest
            req.httpBody = try JSONSerialization.data(withJSONObject: capturedBody)
            print("🌐 [ResearchService.generateWithTools] Request body size: \(req.httpBody?.count ?? 0) bytes")

            // 2. Network call
            let (data, response) = try await URLSession.shared.data(for: req)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("🌐 [ResearchService.generateWithTools] HTTP status: \(httpStatus)")

            if httpStatus != 200 {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ [ResearchService.generateWithTools] API error \(httpStatus): \(errorText.prefix(500))")
                throw ResearchError.apiError(statusCode: httpStatus, message: errorText)
            }

            if let rawStr = String(data: data, encoding: .utf8) {
                print("🌐 [ResearchService.generateWithTools] Raw response (\(data.count) bytes): \(rawStr.prefix(500))...")
            }

            // 3. Parse response JSON
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = json?["choices"] as? [[String: Any]]
            let firstChoice = choices?.first
            let message = firstChoice?["message"] as? [String: Any]
            let finishReason = firstChoice?["finish_reason"] as? String

            print("🌐 [ResearchService.generateWithTools] finish_reason: \(finishReason ?? "nil"), message keys: \(message?.keys.sorted() ?? [])")

            if let usage = json?["usage"] as? [String: Any] {
                Self.logUsage(prefix: "ResearchService (tools)", usage: usage)
            }

            var textContent = ""
            var toolCalls: [ClaudeToolUseResponse.ClaudeToolCall] = []

            // 3a. Text content (String or content blocks array)
            if let contentString = message?["content"] as? String {
                textContent = contentString
            } else if let contentBlocks = message?["content"] as? [[String: Any]] {
                for block in contentBlocks {
                    guard let blockType = block["type"] as? String else { continue }
                    switch blockType {
                    case "text":
                        textContent += block["text"] as? String ?? ""
                    case "tool_use":
                        toolCalls.append(ClaudeToolUseResponse.ClaudeToolCall(
                            id: block["id"] as? String ?? UUID().uuidString,
                            name: block["name"] as? String ?? "",
                            input: block["input"] as? [String: Any] ?? [:]))
                    default: break
                    }
                }
            }

            // 3b. OpenAI-format tool calls
            if let openAIToolCalls = message?["tool_calls"] as? [[String: Any]] {
                print("🌐 [ResearchService.generateWithTools] Found \(openAIToolCalls.count) OpenAI-format tool_calls")
                for tc in openAIToolCalls {
                    let tcId = tc["id"] as? String ?? UUID().uuidString
                    if let function = tc["function"] as? [String: Any] {
                        let name = function["name"] as? String ?? ""
                        let argsStr = function["arguments"] as? String ?? "{}"
                        let input = (try? JSONSerialization.jsonObject(with: Data(argsStr.utf8))) as? [String: Any] ?? [:]
                        toolCalls.append(ClaudeToolUseResponse.ClaudeToolCall(id: tcId, name: name, input: input))
                        print("🌐 [ResearchService.generateWithTools]   tool: \(name), id: \(tcId)")
                    }
                }
            }

            print("🌐 [ResearchService.generateWithTools] Parsed: textContent=\(textContent.count) chars, toolCalls=\(toolCalls.count)")
            if textContent.isEmpty && toolCalls.isEmpty {
                print("⚠️ [ResearchService.generateWithTools] WARNING: Both textContent and toolCalls are empty!")
            }

            return ClaudeToolUseResponse(textContent: textContent, toolCalls: toolCalls, stopReason: finishReason)
        }.value

        // Back on main actor — call onToken handler (needs main thread for UI updates)
        if !parsed.textContent.isEmpty, let tokenHandler = onToken {
            tokenHandler(parsed.textContent)
        }

        return parsed
    }

    func generateWithTools(
        systemBlocks: [(content: String, cacheControl: Bool)],
        messages: [[String: Any]],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int = 8192,
        temperature: Double = 0.3,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> ClaudeToolUseResponse {
        try await generateWithTools(
            systemBlocks: systemBlocks.map {
                PromptCacheBlock(content: $0.content, cacheControl: $0.cacheControl)
            },
            messages: messages,
            tools: tools,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            onToken: onToken
        )
    }

    private func buildSystemContentBlocks(_ systemBlocks: [PromptCacheBlock]) -> [[String: Any]] {
        systemBlocks.map { block in
            var contentBlock: [String: Any] = [
                "type": "text",
                "text": block.content
            ]
            if block.cacheControl {
                var cacheControl: [String: Any] = ["type": "ephemeral"]
                if let ttl = block.ttl, !ttl.isEmpty {
                    cacheControl["ttl"] = ttl
                }
                contentBlock["cache_control"] = cacheControl
            }
            return contentBlock
        }
    }

    private func cacheControlBreakpointCount(in systemBlocks: [PromptCacheBlock]) -> Int {
        systemBlocks.reduce(into: 0) { count, block in
            if block.cacheControl {
                count += 1
            }
        }
    }

    private func cacheToolDefinitions(_ tools: [[String: Any]], ttl: String?) -> [[String: Any]] {
        guard !tools.isEmpty else { return tools }
        var cachedTools = tools
        var lastTool = cachedTools[cachedTools.count - 1]
        var cacheControl: [String: Any] = ["type": "ephemeral"]
        if let ttl, !ttl.isEmpty {
            cacheControl["ttl"] = ttl
        }
        lastTool["cache_control"] = cacheControl
        cachedTools[cachedTools.count - 1] = lastTool
        return cachedTools
    }

    nonisolated private static func logUsage(prefix: String, usage: [String: Any]) {
        let promptTokens = usage["prompt_tokens"] as? Int ?? 0
        let completionTokens = usage["completion_tokens"] as? Int ?? 0
        let cacheHits = usage["prompt_tokens_details"] as? [String: Any]
        let cachedTokens = cacheHits?["cached_tokens"] as? Int ?? 0
        let uncachedPromptTokens = max(promptTokens - cachedTokens, 0)
        let cacheHitRate = promptTokens > 0 ? (Double(cachedTokens) / Double(promptTokens)) * 100 : 0

        print(
            "🌐 [\(prefix)] Usage: prompt=\(promptTokens), uncached=\(uncachedPromptTokens), cached=\(cachedTokens), completion=\(completionTokens), cache_hit_rate=\(String(format: "%.1f", cacheHitRate))%"
        )
    }

    // MARK: - Streaming SSE

    private func streamOpenRouter(request: URLRequest, onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResearchError.invalidResponse
        }
        if httpResponse.statusCode != 200 {
            // Collect error body
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ResearchError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        var fullContent = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            if jsonStr == "[DONE]" { break }

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let token = delta["content"] as? String else { continue }

            fullContent += token
            onToken(token)
        }

        return fullContent
    }

    // MARK: - Call OpenRouter API
    private func callOpenRouter(prompt: String, systemPrompt: String? = nil, model: String, maxTokens: Int = 2000, temperature: Double = 0.3) async throws -> String {
        guard let apiKey = apiKey else {
            throw ResearchError.noAPIKey
        }

        let url = URL(string: "\(openRouterBaseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CosmoOS", forHTTPHeaderField: "X-Title")

        var messages: [[String: Any]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await executeOpenRouter(request: request)
    }

    /// Shared response handler for non-streaming OpenRouter calls
    private func executeOpenRouter(request: URLRequest) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResearchError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("OpenRouter error \(httpResponse.statusCode): \(errorText)")
            throw ResearchError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? ""

        // Log cache usage if present
        if let usage = json?["usage"] as? [String: Any] {
            Self.logUsage(prefix: "ResearchService", usage: usage)
        }

        return content
    }

    // MARK: - Parse Research Response
    private func parseResearchResponse(_ response: String, query: String) -> ResearchResult {
        // Try to parse as JSON
        if let jsonData = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

            let summary = json["summary"] as? String ?? response
            let findingsArray = json["findings"] as? [[String: Any]] ?? []

            let findings = findingsArray.compactMap { finding -> ResearchFinding? in
                guard let title = finding["title"] as? String else { return nil }

                return ResearchFinding(
                    title: title,
                    snippet: finding["snippet"] as? String,
                    source: finding["source"] as? String ?? "Web",
                    url: finding["url"] as? String,
                    confidence: finding["confidence"] as? String ?? "medium"
                )
            }

            return ResearchResult(
                query: query,
                summary: summary,
                findings: findings
            )
        }

        // Fallback: treat entire response as summary
        return ResearchResult(
            query: query,
            summary: response,
            findings: [
                ResearchFinding(
                    title: "Research Result",
                    snippet: String(response.prefix(500)),
                    source: "Perplexity AI",
                    url: nil,
                    confidence: "medium"
                )
            ]
        )
    }
}

// MARK: - Research Types
enum ResearchSearchType: String, Codable {
    case web = "WEB"
    case reddit = "REDDIT"
    case academic = "ACADEMIC"
    case news = "NEWS"
}

struct ResearchResult: Codable {
    let query: String
    let summary: String
    let findings: [ResearchFinding]
}

struct ResearchFinding: Codable, Identifiable, Equatable {
    let id = UUID()
    let title: String
    let snippet: String?
    let source: String
    let url: String?
    let confidence: String

    enum CodingKeys: String, CodingKey {
        case title, snippet, source, url, confidence
    }

    static func == (lhs: ResearchFinding, rhs: ResearchFinding) -> Bool {
        // Intentionally ignore `id` (it's runtime-only and not persisted)
        lhs.title == rhs.title &&
            lhs.snippet == rhs.snippet &&
            lhs.source == rhs.source &&
            lhs.url == rhs.url &&
            lhs.confidence == rhs.confidence
    }
}

// MARK: - Research Errors
enum ResearchError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenRouter API key configured. Please add OPENROUTER_API_KEY to your environment."
        case .invalidResponse:
            return "Invalid response from research API"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .parsingError:
            return "Failed to parse research results"
        }
    }
}
