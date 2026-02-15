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
}

// MARK: - LLM Response

/// Normalized response from any LLM provider
struct LLMResponse: Sendable {
    let content: String?
    let toolCalls: [AgentToolCall]
    let inputTokens: Int
    let outputTokens: Int

    /// Whether the LLM requested tool calls in this response
    var hasToolCalls: Bool { !toolCalls.isEmpty }
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
        }
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

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func complete(
        messages: [AgentMessage],
        tools: [LLMToolDefinition]?,
        model: String?
    ) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMProviderError.noAPIKey }

        let resolvedModel = model ?? AgentProvider.anthropic.defaultModel
        let url = URL(string: "\(baseURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Separate system message from conversation messages
        var systemPrompt: String? = nil
        var conversationMessages: [[String: Any]] = []

        for msg in messages {
            if msg.role == .system {
                systemPrompt = msg.content
                continue
            }

            var msgDict: [String: Any] = ["role": anthropicRole(msg.role)]

            if msg.role == .assistant, let calls = msg.toolCalls, !calls.isEmpty {
                // Assistant message with tool use
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
                // Tool result message
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

        var body: [String: Any] = [
            "model": resolvedModel,
            "messages": conversationMessages,
            "max_tokens": 4096
        ]

        if let systemPrompt = systemPrompt {
            body["system"] = systemPrompt
        }

        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { $0.toAnthropicDict() }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.apiError("Anthropic \(httpResponse.statusCode): \(errorText)")
        }

        return try parseAnthropicResponse(data)
    }

    private func parseAnthropicResponse(_ data: Data) throws -> LLMResponse {
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
        let inputTokens = usage?["input_tokens"] as? Int ?? 0
        let outputTokens = usage?["output_tokens"] as? Int ?? 0

        return LLMResponse(
            content: textContent.isEmpty ? nil : textContent,
            toolCalls: toolCalls,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    private func anthropicRole(_ role: AgentMessage.MessageRole) -> String {
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

        var body: [String: Any] = [
            "model": resolvedModel,
            "messages": openAIMessages,
            "max_tokens": 4096
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

        let content = message["content"] as? String
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

        return LLMResponse(
            content: content,
            toolCalls: toolCalls,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
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

// MARK: - Shared Networking

/// Shared URLSession helper used by all providers
private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
    do {
        return try await URLSession.shared.data(for: request)
    } catch {
        throw LLMProviderError.networkError(error)
    }
}
