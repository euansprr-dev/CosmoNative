// CosmoOS/Agent/Core/LLMProviderAdapter.swift
// Multi-provider LLM adapter for Cosmo Agent

import Foundation

// MARK: - LLM Provider Protocol

/// Abstraction over different LLM APIs. Each provider implements the specific
/// request/response format for its API while presenting a uniform interface.
protocol LLMProvider: Sendable {
    var providerType: AgentProvider { get }

    /// Send a completion request with optional tool definitions.
    /// Returns the LLM's response including any tool call requests.
    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?
    ) async throws -> LLMResponse

    /// Tier-aware completion: when a ModelTier is provided, it overrides the model parameter
    /// with the tier's model ID and uses the tier's max tokens.
    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?
    ) async throws -> LLMResponse

    /// Completion with structured system prompt for prompt caching.
    /// The cached portion of the system prompt is marked with cache_control
    /// so providers can cache the static identity text across requests.
    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        systemPrompt: SystemPrompt
    ) async throws -> LLMResponse
}

// MARK: - Default Implementations

extension LLMProvider {
    /// Default implementation: resolves tier to model ID and delegates to the base `complete`.
    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?
    ) async throws -> LLMResponse {
        let resolvedModel = tier?.modelId ?? model
        return try await complete(messages: messages, tools: tools, model: resolvedModel)
    }

    /// Default implementation: injects system prompt as a regular system message.
    /// Providers that support cache_control (Anthropic) should override this.
    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        systemPrompt: SystemPrompt
    ) async throws -> LLMResponse {
        var allMessages = [AgentMessage.system(systemPrompt.combined)]
        allMessages.append(contentsOf: messages)
        return try await complete(messages: allMessages, tools: tools, model: model)
    }

    /// Combined tier + systemPrompt completion. When a tier is provided, it overrides
    /// the model parameter with the tier's model ID.
    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt
    ) async throws -> LLMResponse {
        let resolvedModel = tier?.modelId ?? model
        return try await complete(messages: messages, tools: tools, model: resolvedModel, systemPrompt: systemPrompt)
    }
}

// MARK: - LLM Response

/// Normalized response from any LLM provider
struct LLMResponse: Sendable {
    let content: String?
    let toolCalls: [AgentToolCall]
    let inputTokens: Int
    let outputTokens: Int
    /// Prompt tokens served from the provider's prompt cache (~10% of input price).
    let cacheReadInputTokens: Int
    /// Prompt tokens written to the provider's prompt cache this request (~125% of input price).
    let cacheCreationInputTokens: Int

    init(
        content: String?,
        toolCalls: [AgentToolCall],
        inputTokens: Int,
        outputTokens: Int,
        cacheReadInputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }

    /// Whether the LLM requested tool calls in this response
    var hasToolCalls: Bool { !toolCalls.isEmpty }
}

// MARK: - Cache Telemetry

/// Rolling prompt-cache statistics so cache regressions are visible instead of silent.
/// A healthy inline-assistant integration should sustain a read ratio ≥ 0.85;
/// a sudden drop to zero means a byte-level invalidator crept into the cached prefix.
final class LLMCacheTelemetry: @unchecked Sendable {
    static let shared = LLMCacheTelemetry()

    struct Snapshot: Sendable {
        var requestCount = 0
        var uncachedInputTokens = 0
        var cacheReadTokens = 0
        var cacheWriteTokens = 0

        /// Fraction of cacheable prompt tokens that were served from cache.
        var readRatio: Double {
            let cacheable = cacheReadTokens + cacheWriteTokens
            guard cacheable > 0 else { return 0 }
            return Double(cacheReadTokens) / Double(cacheable)
        }
    }

    private let lock = NSLock()
    private var snapshot = Snapshot()

    func record(response: LLMResponse, label: String) {
        lock.lock()
        snapshot.requestCount += 1
        snapshot.uncachedInputTokens += response.inputTokens
        snapshot.cacheReadTokens += response.cacheReadInputTokens
        snapshot.cacheWriteTokens += response.cacheCreationInputTokens
        let rolling = snapshot
        lock.unlock()

        if response.cacheReadInputTokens > 0 || response.cacheCreationInputTokens > 0 {
            print("📦 [LLM Cache] \(label): read=\(response.cacheReadInputTokens) write=\(response.cacheCreationInputTokens) uncached=\(response.inputTokens) | rolling readRatio=\(String(format: "%.2f", rolling.readRatio)) over \(rolling.requestCount) requests")
        }
    }

    func current() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}

// MARK: - Tool Definition

/// JSON Schema-based tool definition sent to the LLM
struct LLMToolDefinition: Sendable {
    let name: String
    let description: String
    let parametersSchema: [String: Any] // JSON Schema: {"type":"object","properties":{...},"required":[...]}

    /// Convert to Anthropic Messages API tool format
    func toAnthropicDict() -> [String: Any] {
        return [
            "name": name,
            "description": description,
            "input_schema": parametersSchema
        ]
    }

    /// Convert to OpenAI Chat Completions API tool format
    func toOpenAIDict() -> [String: Any] {
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parametersSchema
            ] as [String: Any]
        ]
    }
}

// MARK: - Errors

enum LLMProviderError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case networkError(Error)
    case unsupportedFeature(String)
    case serviceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured for the selected LLM provider."
        case .invalidResponse:
            return "Received an invalid response from the LLM provider."
        case .apiError(let message):
            return "LLM API error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unsupportedFeature(let feature):
            return "Feature not supported by this provider: \(feature)"
        case .serviceUnavailable(let message):
            return message
        }
    }

    /// Extract HTTP status code from apiError strings (e.g., "Anthropic 429: ...")
    var httpStatusCode: Int? {
        switch self {
        case .apiError(let message):
            // Pattern: "Provider NNN: ..."
            let parts = message.split(separator: " ")
            for part in parts {
                if let code = Int(part.trimmingCharacters(in: .punctuationCharacters)),
                   (400...599).contains(code) {
                    return code
                }
            }
            return nil
        case .networkError:
            return nil
        default:
            return nil
        }
    }

    /// Whether this error is retryable (server-side or rate limit)
    var isRetryable: Bool {
        switch self {
        case .networkError:
            return true
        case .serviceUnavailable:
            return true
        case .apiError:
            guard let code = httpStatusCode else { return false }
            return [429, 500, 502, 503, 529].contains(code)
        default:
            return false
        }
    }
}

// MARK: - Circuit Breaker

/// Tracks consecutive LLM API failures and opens the circuit after a threshold,
/// preventing a flood of requests to a downed service. Resets after a cooldown period.
final class LLMCircuitBreaker: @unchecked Sendable {
    static let shared = LLMCircuitBreaker()

    private var failureCount = 0
    private var lastFailureTime: Date?
    private let failureThreshold = 3
    private let resetTimeout: TimeInterval = 60  // 1 minute cooldown

    private let lock = NSLock()

    /// Whether the circuit is open (too many recent failures)
    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard failureCount >= failureThreshold else { return false }
        if let lastFailure = lastFailureTime,
           Date().timeIntervalSince(lastFailure) > resetTimeout {
            // Cooldown elapsed — reset to half-open (allow one attempt)
            failureCount = 0
            return false
        }
        return true
    }

    func recordSuccess() {
        lock.lock()
        defer { lock.unlock() }
        failureCount = 0
        lastFailureTime = nil
    }

    func recordFailure() {
        lock.lock()
        defer { lock.unlock() }
        failureCount += 1
        lastFailureTime = Date()
        print("[CircuitBreaker] Failure #\(failureCount)")
    }
}

// MARK: - Provider Factory

/// Creates the appropriate LLM provider for a given configuration
enum LLMProviderFactory {
    static func create(provider: AgentProvider, apiKey: String?, baseURL: String?) -> LLMProvider {
        switch provider {
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey ?? "")
        case .openai:
            return OpenAIProvider(apiKey: apiKey ?? "", baseURL: "https://api.openai.com/v1")
        case .openRouter:
            return OpenAIProvider(apiKey: apiKey ?? "", baseURL: "https://openrouter.ai/api/v1")
        case .ollama:
            return OllamaProvider(baseURL: baseURL ?? "http://localhost:11434")
        case .custom:
            return OpenAIProvider(apiKey: apiKey ?? "", baseURL: baseURL ?? "")
        }
    }
}

// MARK: - Anthropic Provider

/// Implements the Anthropic Messages API (api.anthropic.com/v1/messages)
final class AnthropicProvider: LLMProvider, @unchecked Sendable {
    let providerType: AgentProvider = .anthropic
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1"
    private static let promptCacheControl: [String: String] = [
        "type": "ephemeral",
        "ttl": "1h"
    ]

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Model tiers store OpenRouter-style IDs ("anthropic/claude-haiku-4.5").
    /// The direct Anthropic API needs native IDs ("claude-haiku-4-5"), so the same
    /// tier definitions work regardless of which transport is active.
    static func nativeModelID(_ model: String) -> String {
        var native = model
        if native.hasPrefix("anthropic/") {
            native = String(native.dropFirst("anthropic/".count))
        }
        // "claude-haiku-4.5" → "claude-haiku-4-5"
        if let versionDot = native.range(of: #"(\d)\.(\d)"#, options: .regularExpression) {
            native = native.replacingCharacters(
                in: versionDot,
                with: native[versionDot].replacingOccurrences(of: ".", with: "-")
            )
        }
        return native
    }

    private func resolvedMaxTokens(for model: String) -> Int {
        if model.contains("opus") { return 16384 }
        if model.contains("sonnet") { return 8192 }
        return 4096
    }

    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?
    ) async throws -> LLMResponse {
        // Plain-system path: wrap any leading system message and delegate to the
        // structured builder with no cache breakpoints.
        let systemText = messages.first(where: { $0.role == .system })?.content
        let body = try requestBody(
            messages: messages,
            tools: tools,
            model: model,
            systemPrompt: systemText.map { SystemPrompt(cached: $0, dynamic: "") },
            useCacheControl: false,
            stream: false,
            maxTokensOverride: nil
        )
        let data = try await send(body: body)
        return try Self.parseResponse(data)
    }

    /// Prompt-caching path. Sends the system prompt as content blocks with
    /// `cache_control` on the stable portion so Anthropic caches tools + identity
    /// across requests (cache reads cost ~10% of base input price).
    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        systemPrompt: SystemPrompt
    ) async throws -> LLMResponse {
        let body = try requestBody(
            messages: messages,
            tools: tools,
            model: model,
            systemPrompt: systemPrompt,
            useCacheControl: true,
            stream: false,
            maxTokensOverride: nil
        )
        let data = try await send(body: body)
        let response = try Self.parseResponse(data)
        LLMCacheTelemetry.shared.record(response: response, label: "anthropic")
        return response
    }

    /// Writes the tools + cached-system prefix into Anthropic's prompt cache without
    /// generating output, so the next real request starts from a warm cache.
    /// `max_tokens: 0` runs prefill only and returns immediately with empty content.
    func prewarm(
        tools: [LLMToolDefinition]?,
        model: String?,
        systemPrompt: SystemPrompt
    ) async throws {
        let body = try requestBody(
            messages: [.user("warmup")],
            tools: tools,
            model: model,
            systemPrompt: systemPrompt,
            useCacheControl: true,
            stream: false,
            maxTokensOverride: 0
        )
        _ = try await send(body: body)
    }

    // MARK: Request Building

    private func requestBody(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        systemPrompt: SystemPrompt?,
        useCacheControl: Bool,
        stream: Bool,
        maxTokensOverride: Int?
    ) throws -> [String: Any] {
        let resolvedModel = Self.nativeModelID(model ?? AgentProvider.anthropic.defaultModel)

        var conversation = Self.conversationMessages(from: messages)
        if useCacheControl {
            // Incremental message caching: a breakpoint on the FINAL message
            // makes the next request (same prefix + more messages) a cache
            // extend instead of a full-price re-read — each tool-loop
            // iteration and each turn only pays for its new tokens.
            conversation = Self.markingLastMessageForCache(conversation)
        }
        var body: [String: Any] = [
            "model": resolvedModel,
            "messages": conversation,
            "max_tokens": maxTokensOverride ?? resolvedMaxTokens(for: resolvedModel)
        ]

        if let systemPrompt {
            if useCacheControl {
                var systemBlocks: [[String: Any]] = [
                    [
                        "type": "text",
                        "text": systemPrompt.cached,
                        "cache_control": Self.promptCacheControl
                    ]
                ]
                if !systemPrompt.dynamic.isEmpty {
                    systemBlocks.append(["type": "text", "text": systemPrompt.dynamic])
                }
                body["system"] = systemBlocks
            } else {
                body["system"] = systemPrompt.combined
            }
        }

        if let tools, !tools.isEmpty {
            var toolDicts = tools.map { $0.toAnthropicDict() }
            if useCacheControl, var lastTool = toolDicts.last {
                // Tools render before system in the cache prefix — a breakpoint here
                // lets the system block's breakpoint extend the same cache entry.
                lastTool["cache_control"] = Self.promptCacheControl
                toolDicts[toolDicts.count - 1] = lastTool
            }
            body["tools"] = toolDicts
        }

        if stream {
            body["stream"] = true
        }

        return body
    }

    private func makeURLRequest(body: [String: Any]) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw LLMProviderError.noAPIKey }
        let url = URL(string: "\(baseURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func send(body: [String: Any]) async throws -> Data {
        let request = try makeURLRequest(body: body)
        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.apiError("Anthropic \(httpResponse.statusCode): \(errorText)")
        }
        return data
    }

    /// Stamps `cache_control` on the last content block of the final message.
    /// Uses the 4th breakpoint slot (tools + cached-system take two); the
    /// breakpoint moves forward every request, so consecutive requests in a
    /// loop or session match the longest previously-cached prefix.
    static func markingLastMessageForCache(_ messages: [[String: Any]]) -> [[String: Any]] {
        guard var last = messages.last else { return messages }

        var blocks: [[String: Any]]
        if let existing = last["content"] as? [[String: Any]] {
            blocks = existing
        } else if let text = last["content"] as? String, !text.isEmpty {
            blocks = [["type": "text", "text": text]]
        } else {
            return messages
        }
        guard var lastBlock = blocks.last else { return messages }
        lastBlock["cache_control"] = promptCacheControl
        blocks[blocks.count - 1] = lastBlock
        last["content"] = blocks

        var result = messages
        result[result.count - 1] = last
        return result
    }

    static func conversationMessages(from messages: [AgentMessage]) -> [[String: Any]] {
        var conversationMessages: [[String: Any]] = []
        for msg in messages {
            if msg.role == .system { continue } // System rides the top-level field

            var msgDict: [String: Any] = ["role": anthropicRole(msg.role)]

            if msg.role == .assistant, let calls = msg.toolCalls, !calls.isEmpty {
                var contentBlocks: [[String: Any]] = []
                if !msg.content.isEmpty {
                    contentBlocks.append(["type": "text", "text": msg.content])
                }
                for call in calls {
                    var toolUseBlock: [String: Any] = [
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name
                    ]
                    if let inputData = call.argumentsJSON.data(using: .utf8),
                       let inputObj = try? JSONSerialization.jsonObject(with: inputData) {
                        toolUseBlock["input"] = inputObj
                    } else {
                        toolUseBlock["input"] = [String: Any]()
                    }
                    contentBlocks.append(toolUseBlock)
                }
                msgDict["content"] = contentBlocks
            } else if msg.role == .tool {
                msgDict["role"] = "user"
                msgDict["content"] = [
                    [
                        "type": "tool_result",
                        "tool_use_id": msg.toolCallId ?? "",
                        "content": msg.content
                    ] as [String: Any]
                ]
            } else {
                msgDict["content"] = msg.content
            }

            conversationMessages.append(msgDict)
        }
        return conversationMessages
    }

    static func parseResponse(_ data: Data) throws -> LLMResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.invalidResponse
        }

        guard let contentBlocks = json["content"] as? [[String: Any]] else {
            throw LLMProviderError.invalidResponse
        }

        var textContent = ""
        var toolCalls: [AgentToolCall] = []

        for block in contentBlocks {
            let blockType = block["type"] as? String
            if blockType == "text" {
                textContent += (block["text"] as? String ?? "")
            } else if blockType == "tool_use" {
                let callId = block["id"] as? String ?? UUID().uuidString
                let name = block["name"] as? String ?? ""
                let input = block["input"] ?? [String: Any]()
                let inputJSON: String
                if let inputData = try? JSONSerialization.data(withJSONObject: input),
                   let inputStr = String(data: inputData, encoding: .utf8) {
                    inputJSON = inputStr
                } else {
                    inputJSON = "{}"
                }
                toolCalls.append(AgentToolCall(id: callId, name: name, argumentsJSON: inputJSON))
            }
        }

        let usage = json["usage"] as? [String: Any]
        return LLMResponse(
            content: textContent.isEmpty ? nil : textContent,
            toolCalls: toolCalls,
            inputTokens: usage?["input_tokens"] as? Int ?? 0,
            outputTokens: usage?["output_tokens"] as? Int ?? 0,
            cacheReadInputTokens: usage?["cache_read_input_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: usage?["cache_creation_input_tokens"] as? Int ?? 0
        )
    }

    static func anthropicRole(_ role: AgentMessage.MessageRole) -> String {
        switch role {
        case .user, .tool: return "user"
        case .assistant: return "assistant"
        case .system: return "user" // System handled separately
        }
    }
}

// MARK: - OpenAI Provider

/// Implements the OpenAI Chat Completions API. Also used for OpenAI-compatible endpoints.
final class OpenAIProvider: LLMProvider, @unchecked Sendable {
    let providerType: AgentProvider = .openai
    private let apiKey: String
    private let baseURL: String

    init(apiKey: String, baseURL: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    private func maxTokens(for model: String) -> Int {
        let lower = model.lowercased()
        if lower.contains("gpt-5.5") { return 16384 }
        if lower.contains("gpt-chat-latest") { return 8192 }
        if lower.contains("opus") { return 16384 }
        if lower.contains("sonnet") { return 8192 }
        if lower.contains("gemini-flash-latest") { return 8192 }
        if lower.contains("gemini-3") { return 8192 }
        return 4096
    }

    static func reasoningEffort(for model: String) -> String? {
        switch model.lowercased() {
        case "openai/gpt-5.5":
            return "high"
        default:
            return nil
        }
    }

    private func reasoningPayload(for model: String) -> [String: Any]? {
        guard let effort = Self.reasoningEffort(for: model) else { return nil }
        return [
            "effort": effort,
            "exclude": true
        ]
    }

    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?
    ) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMProviderError.noAPIKey }

        let resolvedModel = model ?? AgentProvider.openai.defaultModel
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var openAIMessages: [[String: Any]] = []

        for msg in messages {
            var msgDict: [String: Any] = ["role": openAIRole(msg.role)]

            if msg.role == .assistant, let calls = msg.toolCalls, !calls.isEmpty {
                msgDict["content"] = msg.content.isEmpty ? NSNull() : msg.content
                var toolCallDicts: [[String: Any]] = []
                for call in calls {
                    toolCallDicts.append([
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.argumentsJSON
                        ] as [String: Any]
                    ])
                }
                msgDict["tool_calls"] = toolCallDicts
            } else if msg.role == .tool {
                msgDict["tool_call_id"] = msg.toolCallId ?? ""
                msgDict["content"] = msg.content
            } else {
                msgDict["content"] = msg.content
            }

            openAIMessages.append(msgDict)
        }

        let baseMaxTokens = maxTokens(for: resolvedModel)

        var body: [String: Any] = [
            "model": resolvedModel,
            "messages": openAIMessages,
            "max_tokens": baseMaxTokens
        ]

        if let reasoning = reasoningPayload(for: resolvedModel) {
            body["reasoning"] = reasoning
        }

        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { $0.toOpenAIDict() }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.apiError("OpenAI \(httpResponse.statusCode): \(errorText)")
        }

        return try parseOpenAIResponse(data)
    }

    private func parseOpenAIResponse(_ data: Data) throws -> LLMResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw LLMProviderError.invalidResponse
        }

        // Handle both string content and array content blocks (Anthropic thinking format)
        let content: String?
        if let strContent = message["content"] as? String {
            content = strContent
        } else if let blocks = message["content"] as? [[String: Any]] {
            // Extract only text blocks, skip thinking blocks
            content = blocks
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        } else {
            content = nil
        }
        var toolCalls: [AgentToolCall] = []

        if let rawToolCalls = message["tool_calls"] as? [[String: Any]] {
            for rawCall in rawToolCalls {
                let callId = rawCall["id"] as? String ?? UUID().uuidString
                if let function = rawCall["function"] as? [String: Any] {
                    let name = function["name"] as? String ?? ""
                    let arguments = function["arguments"] as? String ?? "{}"
                    toolCalls.append(AgentToolCall(id: callId, name: name, argumentsJSON: arguments))
                }
            }
        }

        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0
        let (cacheRead, cacheWrite) = Self.cacheTokens(fromUsage: usage)

        let response = LLMResponse(
            content: content,
            toolCalls: toolCalls,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadInputTokens: cacheRead,
            cacheCreationInputTokens: cacheWrite
        )
        LLMCacheTelemetry.shared.record(response: response, label: "openrouter")
        return response
    }

    /// Extract cache metrics from an OpenAI/OpenRouter usage payload.
    /// OpenRouter normalizes Anthropic cache reads into `prompt_tokens_details.cached_tokens`
    /// and (for Anthropic models) may also surface `cache_creation_input_tokens`.
    static func cacheTokens(fromUsage usage: [String: Any]?) -> (read: Int, write: Int) {
        guard let usage else { return (0, 0) }
        var read = 0
        if let promptDetails = usage["prompt_tokens_details"] as? [String: Any] {
            read = promptDetails["cached_tokens"] as? Int ?? 0
        }
        if read == 0 {
            read = usage["cache_read_input_tokens"] as? Int ?? 0
        }
        let write = usage["cache_creation_input_tokens"] as? Int ?? 0
        return (read, write)
    }

    private func openAIRole(_ role: AgentMessage.MessageRole) -> String {
        switch role {
        case .system: return "system"
        case .user: return "user"
        case .assistant: return "assistant"
        case .tool: return "tool"
        }
    }
}

// MARK: - Ollama Provider

/// Implements the Ollama local API (localhost:11434/api/chat)
final class OllamaProvider: LLMProvider, @unchecked Sendable {
    let providerType: AgentProvider = .ollama
    private let baseURL: String

    init(baseURL: String) {
        self.baseURL = baseURL
    }

    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?
    ) async throws -> LLMResponse {
        let resolvedModel = model ?? AgentProvider.ollama.defaultModel
        let url = URL(string: "\(baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var ollamaMessages: [[String: Any]] = []
        for msg in messages {
            var msgDict: [String: Any] = [
                "role": ollamaRole(msg.role),
                "content": msg.content
            ]

            if msg.role == .assistant, let calls = msg.toolCalls, !calls.isEmpty {
                var toolCallDicts: [[String: Any]] = []
                for call in calls {
                    var functionDict: [String: Any] = ["name": call.name]
                    if let argsData = call.argumentsJSON.data(using: .utf8),
                       let argsObj = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                        functionDict["arguments"] = argsObj
                    }
                    toolCallDicts.append(["function": functionDict])
                }
                msgDict["tool_calls"] = toolCallDicts
            }

            ollamaMessages.append(msgDict)
        }

        var body: [String: Any] = [
            "model": resolvedModel,
            "messages": ollamaMessages,
            "stream": false
        ]

        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { $0.toOpenAIDict() }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.apiError("Ollama \(httpResponse.statusCode): \(errorText)")
        }

        return try parseOllamaResponse(data)
    }

    private func parseOllamaResponse(_ data: Data) throws -> LLMResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any] else {
            throw LLMProviderError.invalidResponse
        }

        let content = message["content"] as? String
        var toolCalls: [AgentToolCall] = []

        if let rawToolCalls = message["tool_calls"] as? [[String: Any]] {
            for rawCall in rawToolCalls {
                if let function = rawCall["function"] as? [String: Any] {
                    let name = function["name"] as? String ?? ""
                    let callId = UUID().uuidString // Ollama doesn't return IDs
                    let arguments: String
                    if let argsDict = function["arguments"] as? [String: Any],
                       let argsData = try? JSONSerialization.data(withJSONObject: argsDict),
                       let argsStr = String(data: argsData, encoding: .utf8) {
                        arguments = argsStr
                    } else {
                        arguments = "{}"
                    }
                    toolCalls.append(AgentToolCall(id: callId, name: name, argumentsJSON: arguments))
                }
            }
        }

        // Ollama doesn't provide token counts in non-streaming mode reliably
        let promptEvalCount = json["prompt_eval_count"] as? Int ?? 0
        let evalCount = json["eval_count"] as? Int ?? 0

        return LLMResponse(
            content: content,
            toolCalls: toolCalls,
            inputTokens: promptEvalCount,
            outputTokens: evalCount
        )
    }

    private func ollamaRole(_ role: AgentMessage.MessageRole) -> String {
        switch role {
        case .system: return "system"
        case .user: return "user"
        case .assistant: return "assistant"
        case .tool: return "tool"
        }
    }
}

// MARK: - Failover LLM Provider

/// Wraps any LLMProvider with failover chain support.
/// On retryable errors (429, 500, 502, 503, 529, network errors),
/// retries on the current model up to its maxRetries, then falls over
/// to the next model in the chain. Non-retryable errors (400, 401)
/// propagate immediately.
final class FailoverLLMProvider: LLMProvider, @unchecked Sendable {
    let providerType: AgentProvider
    private let inner: LLMProvider
    private let chain: ModelFailoverChain

    /// After a complete() call, reflects which model was actually used
    private(set) var lastUsedModel: String?
    /// True if the response came from a fallback model, not the primary
    private(set) var failoverOccurred: Bool = false

    /// The raw (non-failover) provider for external access when re-wrapping with a new chain
    var baseProvider: LLMProvider { inner }

    init(wrapping provider: LLMProvider, chain: ModelFailoverChain) {
        // Unwrap nested FailoverLLMProviders to avoid double-failover
        if let failover = provider as? FailoverLLMProvider {
            self.inner = failover.inner
        } else {
            self.inner = provider
        }
        self.providerType = provider.providerType
        self.chain = chain
    }

    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?
    ) async throws -> LLMResponse {
        return try await completeWithFailover(messages: messages, tools: tools, model: model) { provider, msgs, tls, mdl in
            try await provider.complete(messages: msgs, tools: tls, model: mdl)
        }
    }

    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?
    ) async throws -> LLMResponse {
        // When a tier is set, the chain is already tier-appropriate;
        // resolve the primary model from the tier
        let resolvedModel = tier?.modelId ?? model
        return try await completeWithFailover(messages: messages, tools: tools, model: resolvedModel) { provider, msgs, tls, mdl in
            try await provider.complete(messages: msgs, tools: tls, model: mdl)
        }
    }

    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        systemPrompt: SystemPrompt
    ) async throws -> LLMResponse {
        return try await completeWithFailover(messages: messages, tools: tools, model: model) { provider, msgs, tls, mdl in
            try await provider.complete(messages: msgs, tools: tls, model: mdl, systemPrompt: systemPrompt)
        }
    }

    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt
    ) async throws -> LLMResponse {
        let resolvedModel = tier?.modelId ?? model
        return try await completeWithFailover(messages: messages, tools: tools, model: resolvedModel) { provider, msgs, tls, mdl in
            try await provider.complete(messages: msgs, tools: tls, model: mdl, systemPrompt: systemPrompt)
        }
    }

    // MARK: - Core Failover Logic

    private typealias CompletionBlock = (LLMProvider, [AgentMessage], [LLMToolDefinition]?, String?) async throws -> LLMResponse

    private func completeWithFailover(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        completion: CompletionBlock
    ) async throws -> LLMResponse {
        failoverOccurred = false
        lastUsedModel = model

        // Find the starting index in the chain that matches the requested model
        let startIndex = chain.models.firstIndex { $0.modelId == model } ?? 0

        var lastError: Error?

        for chainIndex in startIndex..<chain.models.count {
            let failoverModel = chain.models[chainIndex]
            let isFailover = chainIndex > startIndex

            if isFailover {
                failoverOccurred = true
                print("[Failover] Falling over to \(failoverModel.label) (\(failoverModel.modelId))")
            }

            for attempt in 0...failoverModel.maxRetries {
                if attempt > 0 {
                    // Exponential backoff: 0.5s, 1.0s
                    let delay = 0.5 * pow(2.0, Double(attempt - 1))
                    print("[Failover] Retry \(attempt)/\(failoverModel.maxRetries) for \(failoverModel.label) after \(delay)s")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                do {
                    let response = try await completion(inner, messages, tools, failoverModel.modelId)
                    lastUsedModel = failoverModel.modelId
                    return response
                } catch let error as LLMProviderError {
                    lastError = error

                    // Non-retryable errors propagate immediately
                    if !error.isRetryable {
                        throw error
                    }

                    print("[Failover] \(failoverModel.label) attempt \(attempt) failed: \(error.localizedDescription)")
                } catch {
                    lastError = error
                    // Network-level errors are retryable
                    print("[Failover] \(failoverModel.label) attempt \(attempt) network error: \(error.localizedDescription)")
                }
            }
        }

        // All models in the chain exhausted
        throw lastError ?? LLMProviderError.serviceUnavailable("All models in failover chain exhausted.")
    }
}

// MARK: - Streaming Support

/// Callback for streaming text chunks
typealias StreamingCallback = @Sendable (String) -> Void

/// A normalized streaming event. Text deltas stream the assistant's prose;
/// tool-call argument deltas let UIs stream structured deliverables (like the
/// inline assistant's pane answer, which arrives as `answer_in_assistant_pane`
/// tool-call JSON) instead of waiting for the full response.
enum LLMStreamEvent: Sendable {
    case text(String)
    case toolCallBegan(index: Int, id: String, name: String)
    case toolCallArgumentsDelta(index: Int, name: String, accumulatedJSON: String)
}

typealias LLMStreamEventCallback = @Sendable (LLMStreamEvent) -> Void

/// Protocol extension for providers that support streaming
protocol StreamingLLMProvider: LLMProvider {
    func completeStreaming(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        onChunk: StreamingCallback
    ) async throws -> LLMResponse

    func completeStreaming(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        onChunk: StreamingCallback
    ) async throws -> LLMResponse

    func completeStreaming(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt,
        onChunk: StreamingCallback
    ) async throws -> LLMResponse

    /// Event-level streaming with prompt caching: text deltas AND tool-call
    /// argument deltas, with the structured (cache_control) system prompt intact.
    func completeStreamingEvents(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt?,
        onEvent: LLMStreamEventCallback
    ) async throws -> LLMResponse
}

extension StreamingLLMProvider {
    func completeStreaming(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        onChunk: StreamingCallback
    ) async throws -> LLMResponse {
        let resolvedModel = tier?.modelId ?? model
        return try await completeStreaming(messages: messages, tools: tools, model: resolvedModel, onChunk: onChunk)
    }

    func completeStreaming(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt,
        onChunk: StreamingCallback
    ) async throws -> LLMResponse {
        let resolvedModel = tier?.modelId ?? model
        // Default: inject system prompt as first message and delegate
        var allMessages = [AgentMessage.system(systemPrompt.combined)]
        allMessages.append(contentsOf: messages)
        return try await completeStreaming(messages: allMessages, tools: tools, model: resolvedModel, onChunk: onChunk)
    }

    /// Default event streaming: fall back to non-streaming completion and emit the
    /// final text as a single event. Providers with native SSE override this.
    func completeStreamingEvents(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt?,
        onEvent: LLMStreamEventCallback
    ) async throws -> LLMResponse {
        let response: LLMResponse
        if let systemPrompt {
            response = try await complete(messages: messages, tools: tools, model: model, tier: tier, systemPrompt: systemPrompt)
        } else {
            response = try await complete(messages: messages, tools: tools, model: model, tier: tier)
        }
        if let content = response.content {
            onEvent(.text(content))
        }
        return response
    }
}

/// Streaming implementation for Anthropic — real SSE over the Messages API.
/// Parses `content_block_start` / `content_block_delta` / `content_block_stop` /
/// `message_delta` events, emitting text deltas and tool-call argument deltas
/// as they arrive, with prompt caching intact.
extension AnthropicProvider: StreamingLLMProvider {
    func completeStreaming(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        onChunk: StreamingCallback
    ) async throws -> LLMResponse {
        try await completeStreamingEvents(
            messages: messages,
            tools: tools,
            model: model,
            tier: nil,
            systemPrompt: nil
        ) { event in
            if case .text(let delta) = event {
                onChunk(delta)
            }
        }
    }

    func completeStreamingEvents(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt?,
        onEvent: LLMStreamEventCallback
    ) async throws -> LLMResponse {
        let resolvedModel = tier?.modelId ?? model
        let systemText = systemPrompt == nil
            ? messages.first(where: { $0.role == .system })?.content
            : nil
        let body = try requestBody(
            messages: messages,
            tools: tools,
            model: resolvedModel,
            systemPrompt: systemPrompt ?? systemText.map { SystemPrompt(cached: $0, dynamic: "") },
            useCacheControl: systemPrompt != nil,
            stream: true,
            maxTokensOverride: nil
        )
        let request = try makeURLRequest(body: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        if httpResponse.statusCode != 200 {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count > 4096 { break }
            }
            let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.apiError("Anthropic \(httpResponse.statusCode): \(errorText)")
        }

        var textContent = ""
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheWriteTokens = 0
        var stopReason: String?

        // Per-block accumulation: Anthropic streams tool_use input as raw partial
        // JSON via input_json_delta, keyed by content block index.
        struct PartialToolUse {
            var id: String
            var name: String
            var argumentsJSON: String
        }
        var partialToolUses: [Int: PartialToolUse] = [:]

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventType = json["type"] as? String else {
                continue
            }

            switch eventType {
            case "message_start":
                if let message = json["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    inputTokens = usage["input_tokens"] as? Int ?? 0
                    cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
                    cacheWriteTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
                }

            case "content_block_start":
                guard let index = json["index"] as? Int,
                      let block = json["content_block"] as? [String: Any],
                      block["type"] as? String == "tool_use" else { break }
                let id = block["id"] as? String ?? UUID().uuidString
                let name = block["name"] as? String ?? ""
                partialToolUses[index] = PartialToolUse(id: id, name: name, argumentsJSON: "")
                onEvent(.toolCallBegan(index: index, id: id, name: name))

            case "content_block_delta":
                guard let index = json["index"] as? Int,
                      let delta = json["delta"] as? [String: Any],
                      let deltaType = delta["type"] as? String else { break }
                if deltaType == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                    textContent += text
                    onEvent(.text(text))
                } else if deltaType == "input_json_delta",
                          let partialJSON = delta["partial_json"] as? String,
                          var partial = partialToolUses[index] {
                    partial.argumentsJSON += partialJSON
                    partialToolUses[index] = partial
                    onEvent(.toolCallArgumentsDelta(
                        index: index,
                        name: partial.name,
                        accumulatedJSON: partial.argumentsJSON
                    ))
                }

            case "message_delta":
                if let usage = json["usage"] as? [String: Any] {
                    outputTokens = usage["output_tokens"] as? Int ?? outputTokens
                }
                if let delta = json["delta"] as? [String: Any],
                   let reason = delta["stop_reason"] as? String {
                    stopReason = reason
                }

            case "message_stop":
                break

            default:
                break
            }
        }

        let toolCalls = partialToolUses.keys.sorted().compactMap { index -> AgentToolCall? in
            guard let partial = partialToolUses[index] else { return nil }
            // A max_tokens cutoff mid-stream leaves tool-call JSON truncated; the
            // arguments parser would degrade it to `[:]` and the tool would execute
            // with empty/default parameters. Drop unparseable calls instead and
            // let the loop surface the failure.
            if stopReason == "max_tokens", !partial.argumentsJSON.isEmpty {
                let parses = (try? JSONSerialization.jsonObject(
                    with: Data(partial.argumentsJSON.utf8)
                )) != nil
                if !parses {
                    print("⚠️ [LLMProviderAdapter] Dropping tool call \(partial.name) — arguments truncated at max_tokens")
                    return nil
                }
            }
            return AgentToolCall(
                id: partial.id,
                name: partial.name,
                argumentsJSON: partial.argumentsJSON.isEmpty ? "{}" : partial.argumentsJSON
            )
        }

        let result = LLMResponse(
            content: textContent.isEmpty ? nil : textContent,
            toolCalls: toolCalls,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadInputTokens: cacheReadTokens,
            cacheCreationInputTokens: cacheWriteTokens
        )
        LLMCacheTelemetry.shared.record(response: result, label: "anthropic/stream")
        return result
    }
}

// MARK: - OpenAI Provider: Prompt Caching for OpenRouter/Anthropic

extension OpenAIProvider {
    /// Override with prompt caching support for OpenRouter's Anthropic models.
    /// Sends the system prompt as structured content blocks with `cache_control`,
    /// so the static identity portion is cached across requests (90% cost reduction).
    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        systemPrompt: SystemPrompt
    ) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMProviderError.noAPIKey }

        let resolvedModel = model ?? AgentProvider.openai.defaultModel
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var openAIMessages: [[String: Any]] = []

        // Build system message with cache_control content blocks for Anthropic models on OpenRouter
        let isAnthropicModel = resolvedModel.hasPrefix("anthropic/")
        if isAnthropicModel {
            // Structured content blocks with cache_control for OpenRouter's Anthropic passthrough
            var contentBlocks: [[String: Any]] = [
                [
                    "type": "text",
                    "text": systemPrompt.cached,
                    "cache_control": ["type": "ephemeral"]
                ]
            ]
            if !systemPrompt.dynamic.isEmpty {
                contentBlocks.append([
                    "type": "text",
                    "text": systemPrompt.dynamic
                ])
            }
            openAIMessages.append([
                "role": "system",
                "content": contentBlocks
            ])
        } else {
            // Non-Anthropic models: plain text system message
            openAIMessages.append([
                "role": "system",
                "content": systemPrompt.combined
            ])
        }

        // Build conversation messages (skip any system messages in the array)
        for msg in messages {
            if msg.role == .system { continue }

            var msgDict: [String: Any] = ["role": openAIRole(msg.role)]

            if msg.role == .assistant, let calls = msg.toolCalls, !calls.isEmpty {
                msgDict["content"] = msg.content.isEmpty ? NSNull() : msg.content
                var toolCallDicts: [[String: Any]] = []
                for call in calls {
                    toolCallDicts.append([
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.argumentsJSON
                        ] as [String: Any]
                    ])
                }
                msgDict["tool_calls"] = toolCallDicts
            } else if msg.role == .tool {
                msgDict["tool_call_id"] = msg.toolCallId ?? ""
                msgDict["content"] = msg.content
            } else {
                msgDict["content"] = msg.content
            }

            openAIMessages.append(msgDict)
        }

        if resolvedModel.hasPrefix("anthropic/") {
            Self.markLastUserMessageForAnthropicCache(&openAIMessages)
        }

        let resolvedMaxTokens = maxTokens(for: resolvedModel)

        var body: [String: Any] = [
            "model": resolvedModel,
            "messages": openAIMessages,
            "max_tokens": resolvedMaxTokens
        ]

        if let reasoning = reasoningPayload(for: resolvedModel) {
            body["reasoning"] = reasoning
        }

        if let tools = tools, !tools.isEmpty {
            var toolDicts = tools.map { $0.toOpenAIDict() }
            // Cache tool definitions — they're static across requests
            if var lastTool = toolDicts.last {
                lastTool["cache_control"] = ["type": "ephemeral"]
                toolDicts[toolDicts.count - 1] = lastTool
            }
            body["tools"] = toolDicts
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.apiError("OpenAI \(httpResponse.statusCode): \(errorText)")
        }

        return try parseOpenAIResponse(data)
    }
}

extension OpenAIProvider {
    /// Incremental message caching for OpenRouter's Anthropic passthrough:
    /// converts the final user message to content-parts form and stamps
    /// `cache_control`, so the next request in the conversation extends the
    /// cache instead of re-reading the whole history. Only user messages —
    /// OpenRouter's parts mapping for tool-role content is undocumented.
    static func markLastUserMessageForAnthropicCache(_ messages: inout [[String: Any]]) {
        guard var last = messages.last,
              last["role"] as? String == "user",
              let text = last["content"] as? String,
              !text.isEmpty else {
            return
        }
        last["content"] = [[
            "type": "text",
            "text": text,
            "cache_control": ["type": "ephemeral"]
        ] as [String: Any]]
        messages[messages.count - 1] = last
    }
}

/// Streaming implementation for OpenAI-compatible providers (real SSE)
extension OpenAIProvider: StreamingLLMProvider {
    func completeStreaming(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        onChunk: StreamingCallback
    ) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMProviderError.noAPIKey }

        let resolvedModel = model ?? AgentProvider.openai.defaultModel
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var openAIMessages: [[String: Any]] = []
        for msg in messages {
            var msgDict: [String: Any] = ["role": openAIRole(msg.role)]
            if msg.role == .assistant, let calls = msg.toolCalls, !calls.isEmpty {
                msgDict["content"] = msg.content.isEmpty ? NSNull() : msg.content
                var toolCallDicts: [[String: Any]] = []
                for call in calls {
                    toolCallDicts.append([
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.argumentsJSON
                        ] as [String: Any]
                    ])
                }
                msgDict["tool_calls"] = toolCallDicts
            } else if msg.role == .tool {
                msgDict["tool_call_id"] = msg.toolCallId ?? ""
                msgDict["content"] = msg.content
            } else {
                msgDict["content"] = msg.content
            }
            openAIMessages.append(msgDict)
        }

        let resolvedMaxTokens = maxTokens(for: resolvedModel)

        var body: [String: Any] = [
            "model": resolvedModel,
            "messages": openAIMessages,
            "max_tokens": resolvedMaxTokens,
            "stream": true
        ]

        if let reasoning = reasoningPayload(for: resolvedModel) {
            body["reasoning"] = reasoning
        }

        // Include tools in streaming — the SSE parser accumulates tool call deltas
        if let tools = tools, !tools.isEmpty {
            var toolDicts = tools.map { $0.toOpenAIDict() }
            // Cache tool definitions — they're static across requests
            if var lastTool = toolDicts.last {
                lastTool["cache_control"] = ["type": "ephemeral"]
                toolDicts[toolDicts.count - 1] = lastTool
            }
            body["tools"] = toolDicts
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Use URLSession bytes API for SSE streaming
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // Collect error body
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count > 4096 { break }
            }
            let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.apiError("OpenAI \(httpResponse.statusCode): \(errorText)")
        }

        var fullContent = ""
        var toolCalls: [AgentToolCall] = []
        var inputTokens = 0
        var outputTokens = 0

        // Accumulate partial tool calls by index
        var partialToolCalls: [Int: (id: String, name: String, args: String)] = [:]

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else {
                continue
            }

            // Text content delta
            if let content = delta["content"] as? String, !content.isEmpty {
                fullContent += content
                onChunk(content)
            }

            // Tool call deltas (accumulated across multiple SSE events)
            if let tcDeltas = delta["tool_calls"] as? [[String: Any]] {
                for tcDelta in tcDeltas {
                    let index = tcDelta["index"] as? Int ?? 0
                    if let id = tcDelta["id"] as? String {
                        let funcDict = tcDelta["function"] as? [String: Any]
                        let name = funcDict?["name"] as? String ?? ""
                        partialToolCalls[index] = (id: id, name: name, args: "")
                    }
                    if let funcDict = tcDelta["function"] as? [String: Any],
                       let argChunk = funcDict["arguments"] as? String {
                        var partial = partialToolCalls[index] ?? (id: "", name: "", args: "")
                        partial.args += argChunk
                        partialToolCalls[index] = partial
                    }
                }
            }

            // Usage (some providers include it in the last chunk)
            if let usage = json["usage"] as? [String: Any] {
                inputTokens = usage["prompt_tokens"] as? Int ?? inputTokens
                outputTokens = usage["completion_tokens"] as? Int ?? outputTokens

                // Log cache metrics for monitoring
                if let promptDetails = usage["prompt_tokens_details"] as? [String: Any] {
                    let cached = promptDetails["cached_tokens"] as? Int ?? 0
                    if cached > 0 {
                        print("📦 [LLM Cache] Stream hit: \(cached) cached tokens out of \(inputTokens) total (\(inputTokens > 0 ? Int(Double(cached) / Double(inputTokens) * 100) : 0)%)")
                    }
                }
            }
        }

        // Assemble accumulated tool calls
        for index in partialToolCalls.keys.sorted() {
            if let tc = partialToolCalls[index] {
                toolCalls.append(AgentToolCall(id: tc.id, name: tc.name, argumentsJSON: tc.args.isEmpty ? "{}" : tc.args))
            }
        }

        return LLMResponse(
            content: fullContent.isEmpty ? nil : fullContent,
            toolCalls: toolCalls,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}

/// Streaming with system prompt for OpenAI-compatible providers
extension OpenAIProvider {
    func completeStreaming(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt,
        onChunk: StreamingCallback
    ) async throws -> LLMResponse {
        try await completeStreamingEvents(
            messages: messages,
            tools: tools,
            model: model,
            tier: tier,
            systemPrompt: systemPrompt
        ) { event in
            if case .text(let delta) = event {
                onChunk(delta)
            }
        }
    }

    /// Event-level SSE streaming. Unlike the legacy streaming path, this keeps the
    /// structured `cache_control` system blocks for Anthropic models on OpenRouter,
    /// so streaming no longer trades away the prompt cache.
    func completeStreamingEvents(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt?,
        onEvent: LLMStreamEventCallback
    ) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMProviderError.noAPIKey }

        let resolvedModel = tier?.modelId ?? model ?? AgentProvider.openai.defaultModel
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var openAIMessages: [[String: Any]] = []

        if let systemPrompt {
            if resolvedModel.hasPrefix("anthropic/") {
                var contentBlocks: [[String: Any]] = [
                    [
                        "type": "text",
                        "text": systemPrompt.cached,
                        "cache_control": ["type": "ephemeral"]
                    ]
                ]
                if !systemPrompt.dynamic.isEmpty {
                    contentBlocks.append(["type": "text", "text": systemPrompt.dynamic])
                }
                openAIMessages.append(["role": "system", "content": contentBlocks])
            } else {
                openAIMessages.append(["role": "system", "content": systemPrompt.combined])
            }
        }

        for msg in messages {
            if msg.role == .system, systemPrompt != nil { continue }
            var msgDict: [String: Any] = ["role": openAIRole(msg.role)]
            if msg.role == .assistant, let calls = msg.toolCalls, !calls.isEmpty {
                msgDict["content"] = msg.content.isEmpty ? NSNull() : msg.content
                var toolCallDicts: [[String: Any]] = []
                for call in calls {
                    toolCallDicts.append([
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.argumentsJSON
                        ] as [String: Any]
                    ])
                }
                msgDict["tool_calls"] = toolCallDicts
            } else if msg.role == .tool {
                msgDict["tool_call_id"] = msg.toolCallId ?? ""
                msgDict["content"] = msg.content
            } else {
                msgDict["content"] = msg.content
            }
            openAIMessages.append(msgDict)
        }

        if resolvedModel.hasPrefix("anthropic/") {
            Self.markLastUserMessageForAnthropicCache(&openAIMessages)
        }

        var body: [String: Any] = [
            "model": resolvedModel,
            "messages": openAIMessages,
            "max_tokens": maxTokens(for: resolvedModel),
            "stream": true,
            // Ask OpenRouter to attach usage (incl. cache metrics) to the final chunk
            "usage": ["include": true]
        ]

        if let reasoning = reasoningPayload(for: resolvedModel) {
            body["reasoning"] = reasoning
        }

        if let tools, !tools.isEmpty {
            var toolDicts = tools.map { $0.toOpenAIDict() }
            if var lastTool = toolDicts.last {
                lastTool["cache_control"] = ["type": "ephemeral"]
                toolDicts[toolDicts.count - 1] = lastTool
            }
            body["tools"] = toolDicts
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        if httpResponse.statusCode != 200 {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count > 4096 { break }
            }
            let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.apiError("OpenAI \(httpResponse.statusCode): \(errorText)")
        }

        var fullContent = ""
        var inputTokens = 0
        var outputTokens = 0
        var cacheRead = 0
        var cacheWrite = 0
        var partialToolCalls: [Int: (id: String, name: String, args: String)] = [:]

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any] {
                if let content = delta["content"] as? String, !content.isEmpty {
                    fullContent += content
                    onEvent(.text(content))
                }

                if let tcDeltas = delta["tool_calls"] as? [[String: Any]] {
                    for tcDelta in tcDeltas {
                        let index = tcDelta["index"] as? Int ?? 0
                        if let id = tcDelta["id"] as? String {
                            let funcDict = tcDelta["function"] as? [String: Any]
                            let name = funcDict?["name"] as? String ?? ""
                            partialToolCalls[index] = (id: id, name: name, args: "")
                            onEvent(.toolCallBegan(index: index, id: id, name: name))
                        }
                        if let funcDict = tcDelta["function"] as? [String: Any],
                           let argChunk = funcDict["arguments"] as? String, !argChunk.isEmpty {
                            var partial = partialToolCalls[index] ?? (id: "", name: "", args: "")
                            if partial.name.isEmpty,
                               let name = funcDict["name"] as? String {
                                partial.name = name
                            }
                            partial.args += argChunk
                            partialToolCalls[index] = partial
                            onEvent(.toolCallArgumentsDelta(
                                index: index,
                                name: partial.name,
                                accumulatedJSON: partial.args
                            ))
                        }
                    }
                }
            }

            if let usage = json["usage"] as? [String: Any] {
                inputTokens = usage["prompt_tokens"] as? Int ?? inputTokens
                outputTokens = usage["completion_tokens"] as? Int ?? outputTokens
                let cache = Self.cacheTokens(fromUsage: usage)
                cacheRead = max(cacheRead, cache.read)
                cacheWrite = max(cacheWrite, cache.write)
            }
        }

        var toolCalls: [AgentToolCall] = []
        for index in partialToolCalls.keys.sorted() {
            if let tc = partialToolCalls[index] {
                toolCalls.append(AgentToolCall(id: tc.id, name: tc.name, argumentsJSON: tc.args.isEmpty ? "{}" : tc.args))
            }
        }

        let result = LLMResponse(
            content: fullContent.isEmpty ? nil : fullContent,
            toolCalls: toolCalls,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadInputTokens: cacheRead,
            cacheCreationInputTokens: cacheWrite
        )
        LLMCacheTelemetry.shared.record(response: result, label: "openrouter/stream")
        return result
    }
}

/// Streaming support for FailoverLLMProvider — delegates to inner if it supports streaming
extension FailoverLLMProvider: StreamingLLMProvider {
    func completeStreaming(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        onChunk: StreamingCallback
    ) async throws -> LLMResponse {
        guard let streamingInner = inner as? StreamingLLMProvider else {
            // Fallback: non-streaming complete + deliver as single chunk
            let response = try await complete(messages: messages, tools: tools, model: model)
            if let content = response.content {
                onChunk(content)
            }
            return response
        }

        failoverOccurred = false
        lastUsedModel = model

        let startIndex = chain.models.firstIndex { $0.modelId == model } ?? 0
        var lastError: Error?

        for chainIndex in startIndex..<chain.models.count {
            let failoverModel = chain.models[chainIndex]
            if chainIndex > startIndex {
                failoverOccurred = true
                print("[Failover/Stream] Falling over to \(failoverModel.label)")
            }

            for attempt in 0...failoverModel.maxRetries {
                if attempt > 0 {
                    let delay = 0.5 * pow(2.0, Double(attempt - 1))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                do {
                    let response = try await streamingInner.completeStreaming(
                        messages: messages,
                        tools: tools,
                        model: failoverModel.modelId,
                        onChunk: onChunk
                    )
                    lastUsedModel = failoverModel.modelId
                    return response
                } catch let error as LLMProviderError where error.isRetryable {
                    lastError = error
                    print("[Failover/Stream] \(failoverModel.label) attempt \(attempt) failed: \(error.localizedDescription)")
                } catch let error as LLMProviderError {
                    throw error // Non-retryable
                } catch {
                    lastError = error
                }
            }
        }

        throw lastError ?? LLMProviderError.serviceUnavailable("All models in failover chain exhausted.")
    }

    func completeStreaming(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt,
        onChunk: StreamingCallback
    ) async throws -> LLMResponse {
        guard let streamingInner = inner as? StreamingLLMProvider else {
            // Fallback: non-streaming complete with system prompt
            let response = try await complete(messages: messages, tools: tools, model: model, systemPrompt: systemPrompt)
            if let content = response.content {
                onChunk(content)
            }
            return response
        }

        failoverOccurred = false
        let resolvedModel = tier?.modelId ?? model
        lastUsedModel = resolvedModel

        let startIndex = chain.models.firstIndex { $0.modelId == resolvedModel } ?? 0
        var lastError: Error?

        for chainIndex in startIndex..<chain.models.count {
            let failoverModel = chain.models[chainIndex]
            if chainIndex > startIndex {
                failoverOccurred = true
                print("[Failover/Stream] Falling over to \(failoverModel.label)")
            }

            for attempt in 0...failoverModel.maxRetries {
                if attempt > 0 {
                    let delay = 0.5 * pow(2.0, Double(attempt - 1))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                do {
                    let response = try await streamingInner.completeStreaming(
                        messages: messages,
                        tools: tools,
                        model: failoverModel.modelId,
                        tier: nil,
                        systemPrompt: systemPrompt,
                        onChunk: onChunk
                    )
                    lastUsedModel = failoverModel.modelId
                    return response
                } catch let error as LLMProviderError where error.isRetryable {
                    lastError = error
                    print("[Failover/Stream] \(failoverModel.label) attempt \(attempt) failed: \(error.localizedDescription)")
                } catch let error as LLMProviderError {
                    throw error
                } catch {
                    lastError = error
                }
            }
        }

        throw lastError ?? LLMProviderError.serviceUnavailable("All models in failover chain exhausted.")
    }

    func completeStreamingEvents(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?,
        tier: AgentModelTier?,
        systemPrompt: SystemPrompt?,
        onEvent: LLMStreamEventCallback
    ) async throws -> LLMResponse {
        guard let streamingInner = inner as? StreamingLLMProvider else {
            let response: LLMResponse
            if let systemPrompt {
                response = try await complete(messages: messages, tools: tools, model: model, tier: tier, systemPrompt: systemPrompt)
            } else {
                response = try await complete(messages: messages, tools: tools, model: model, tier: tier)
            }
            if let content = response.content {
                onEvent(.text(content))
            }
            return response
        }

        failoverOccurred = false
        let resolvedModel = tier?.modelId ?? model
        lastUsedModel = resolvedModel

        let startIndex = chain.models.firstIndex { $0.modelId == resolvedModel } ?? 0
        var lastError: Error?

        for chainIndex in startIndex..<chain.models.count {
            let failoverModel = chain.models[chainIndex]
            if chainIndex > startIndex {
                failoverOccurred = true
                print("[Failover/StreamEvents] Falling over to \(failoverModel.label)")
            }

            for attempt in 0...failoverModel.maxRetries {
                if attempt > 0 {
                    let delay = 0.5 * pow(2.0, Double(attempt - 1))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                do {
                    let response = try await streamingInner.completeStreamingEvents(
                        messages: messages,
                        tools: tools,
                        model: failoverModel.modelId,
                        tier: nil,
                        systemPrompt: systemPrompt,
                        onEvent: onEvent
                    )
                    lastUsedModel = failoverModel.modelId
                    return response
                } catch let error as LLMProviderError where error.isRetryable {
                    lastError = error
                    print("[Failover/StreamEvents] \(failoverModel.label) attempt \(attempt) failed: \(error.localizedDescription)")
                } catch let error as LLMProviderError {
                    throw error
                } catch {
                    lastError = error
                }
            }
        }

        throw lastError ?? LLMProviderError.serviceUnavailable("All models in failover chain exhausted.")
    }
}

// MARK: - Partial Tool-Argument Extraction

/// Extracts a string field's value from a *partial* JSON object as it streams.
/// Used to stream `answer_in_assistant_pane`'s "answer" field into the pane
/// while the tool-call arguments are still arriving over SSE.
enum LLMPartialToolArguments {
    /// Returns the (possibly still-growing) value of `field` inside `partialJSON`,
    /// or nil if the field's opening quote hasn't arrived yet. Handles standard
    /// JSON string escapes; an unterminated value returns everything decoded so far.
    static func stringValue(of field: String, inPartialJSON partialJSON: String) -> String? {
        guard let keyRange = partialJSON.range(of: "\"\(field)\"") else { return nil }

        var index = keyRange.upperBound
        // Skip whitespace, then require the colon, then skip to the opening quote.
        while index < partialJSON.endIndex, partialJSON[index].isWhitespace {
            index = partialJSON.index(after: index)
        }
        guard index < partialJSON.endIndex, partialJSON[index] == ":" else { return nil }
        index = partialJSON.index(after: index)
        while index < partialJSON.endIndex, partialJSON[index].isWhitespace {
            index = partialJSON.index(after: index)
        }
        guard index < partialJSON.endIndex, partialJSON[index] == "\"" else { return nil }
        index = partialJSON.index(after: index)

        var decoded = ""
        var pendingEscape = false
        var pendingUnicode: String? = nil

        while index < partialJSON.endIndex {
            let character = partialJSON[index]

            if var unicodeDigits = pendingUnicode {
                unicodeDigits.append(character)
                if unicodeDigits.count == 4 {
                    if let scalarValue = UInt32(unicodeDigits, radix: 16),
                       let scalar = Unicode.Scalar(scalarValue) {
                        decoded.append(Character(scalar))
                    }
                    pendingUnicode = nil
                } else {
                    pendingUnicode = unicodeDigits
                }
            } else if pendingEscape {
                pendingEscape = false
                switch character {
                case "n": decoded.append("\n")
                case "t": decoded.append("\t")
                case "r": decoded.append("\r")
                case "\"": decoded.append("\"")
                case "\\": decoded.append("\\")
                case "/": decoded.append("/")
                case "b", "f": break // rare control escapes — drop in streamed preview
                case "u": pendingUnicode = ""
                default: decoded.append(character)
                }
            } else if character == "\\" {
                pendingEscape = true
            } else if character == "\"" {
                return decoded // Field value complete
            } else {
                decoded.append(character)
            }

            index = partialJSON.index(after: index)
        }

        // Stream still mid-value: return what has decoded so far.
        return decoded
    }
}

// MARK: - Cache Pre-warming

/// Providers that can write the tools + cached-system prefix into the prompt cache
/// ahead of the first real request, removing the cold-write latency from the
/// user's first interaction.
protocol PrewarmingLLMProvider {
    func prewarm(
        tools: [LLMToolDefinition]?,
        model: String?,
        systemPrompt: SystemPrompt
    ) async throws
}

extension AnthropicProvider: PrewarmingLLMProvider {}

extension OpenAIProvider: PrewarmingLLMProvider {
    /// OpenRouter has no `max_tokens: 0` prefill mode, so warm with a 1-token
    /// completion and `tool_choice: "none"` (tool_choice changes don't invalidate
    /// the tools/system cache tiers — only the message tier).
    func prewarm(
        tools: [LLMToolDefinition]?,
        model: String?,
        systemPrompt: SystemPrompt
    ) async throws {
        guard !apiKey.isEmpty else { throw LLMProviderError.noAPIKey }

        let resolvedModel = model ?? AgentProvider.openai.defaultModel
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var openAIMessages: [[String: Any]] = []
        if resolvedModel.hasPrefix("anthropic/") {
            var contentBlocks: [[String: Any]] = [
                [
                    "type": "text",
                    "text": systemPrompt.cached,
                    "cache_control": ["type": "ephemeral"]
                ]
            ]
            if !systemPrompt.dynamic.isEmpty {
                contentBlocks.append(["type": "text", "text": systemPrompt.dynamic])
            }
            openAIMessages.append(["role": "system", "content": contentBlocks])
        } else {
            openAIMessages.append(["role": "system", "content": systemPrompt.combined])
        }
        openAIMessages.append(["role": "user", "content": "warmup"])

        var body: [String: Any] = [
            "model": resolvedModel,
            "messages": openAIMessages,
            "max_tokens": 1
        ]

        if let tools, !tools.isEmpty {
            var toolDicts = tools.map { $0.toOpenAIDict() }
            if var lastTool = toolDicts.last {
                lastTool["cache_control"] = ["type": "ephemeral"]
                toolDicts[toolDicts.count - 1] = lastTool
            }
            body["tools"] = toolDicts
            body["tool_choice"] = "none"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.apiError("Prewarm failed: \(errorText)")
        }
    }
}

extension FailoverLLMProvider: PrewarmingLLMProvider {
    func prewarm(
        tools: [LLMToolDefinition]?,
        model: String?,
        systemPrompt: SystemPrompt
    ) async throws {
        guard let prewarming = baseProvider as? PrewarmingLLMProvider else { return }
        try await prewarming.prewarm(tools: tools, model: model, systemPrompt: systemPrompt)
    }
}

// MARK: - Shared Networking

/// Shared URLSession helper used by all providers.
/// Checks the circuit breaker before making the request and records success/failure.
private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
    let breaker = LLMCircuitBreaker.shared

    if breaker.isOpen {
        throw LLMProviderError.serviceUnavailable(
            "AI service is temporarily unavailable after repeated failures. Please try again in a minute."
        )
    }

    do {
        let result = try await URLSession.shared.data(for: request)
        if let http = result.1 as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 500 {
            // 2xx-4xx are valid server responses (not network failures)
            breaker.recordSuccess()
        }
        return result
    } catch {
        breaker.recordFailure()
        throw LLMProviderError.networkError(error)
    }
}
