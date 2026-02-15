// CosmoOS/Agent/Models/AgentTypes.swift
// Core types for the Cosmo Agent system

import Foundation

// MARK: - Agent Provider

/// LLM providers supported by Cosmo Agent
enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openai
    case openRouter
    case ollama
    case custom // OpenAI-compatible endpoint

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama (Local)"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-5-20250929"
        case .openai: return "gpt-4o"
        case .openRouter: return "anthropic/claude-sonnet-4-5-20250929"
        case .ollama: return "llama3.2"
        case .custom: return "gpt-4o"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openai: return "https://api.openai.com"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .ollama: return "http://localhost:11434"
        case .custom: return ""
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .anthropic, .openai, .openRouter, .custom: return true
        case .ollama: return false
        }
    }

    /// Popular models available on OpenRouter
    static let openRouterModels: [(id: String, label: String)] = [
        ("anthropic/claude-sonnet-4-5-20250929", "Claude Sonnet 4.5"),
        ("anthropic/claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
        ("openai/gpt-4o", "GPT-4o"),
        ("openai/gpt-4o-mini", "GPT-4o Mini"),
        ("google/gemini-2.0-flash-001", "Gemini 2.0 Flash"),
        ("google/gemini-2.5-pro-preview", "Gemini 2.5 Pro"),
        ("deepseek/deepseek-chat", "DeepSeek V3"),
        ("deepseek/deepseek-r1", "DeepSeek R1"),
        ("meta-llama/llama-3.3-70b-instruct", "Llama 3.3 70B"),
        ("mistralai/mistral-large-latest", "Mistral Large"),
        ("qwen/qwen-2.5-72b-instruct", "Qwen 2.5 72B"),
    ]
}

// MARK: - Agent Intent

/// Classifies the purpose of a user message to guide tool selection and confirmation tier
enum AgentIntent: String, Codable, Sendable {
    case capture      // Save an idea, swipe, or note
    case brainstorm   // Creative ideation session
    case plan         // Schedule tasks, time blocks
    case query        // Ask about existing data
    case execute      // Take action (advance pipeline, complete task)
    case debrief      // End-of-day or session review
    case reflect      // Journal-style reflection
    case correct      // Fix something (rename, update, delete)
    case meta         // Settings, preferences, help
}

// MARK: - Confirmation Tier

/// Controls how the agent handles action execution
enum AgentConfirmationTier: String, Codable, Sendable {
    case auto   // Execute immediately, no confirmation needed
    case soft   // Execute and inform user what was done
    case hard   // Require explicit confirmation before executing
}

// MARK: - Agent Message

/// A single message in an agent conversation
struct AgentMessage: Codable, Identifiable, Sendable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    var toolCalls: [AgentToolCall]?
    var toolCallId: String?

    enum MessageRole: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    init(role: MessageRole, content: String, toolCalls: [AgentToolCall]? = nil, toolCallId: String? = nil) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    static func user(_ content: String) -> AgentMessage {
        AgentMessage(role: .user, content: content)
    }

    static func assistant(_ content: String, toolCalls: [AgentToolCall]? = nil) -> AgentMessage {
        AgentMessage(role: .assistant, content: content, toolCalls: toolCalls)
    }

    static func tool(callId: String, content: String) -> AgentMessage {
        AgentMessage(role: .tool, content: content, toolCallId: callId)
    }

    static func system(_ content: String) -> AgentMessage {
        AgentMessage(role: .system, content: content)
    }
}

// MARK: - Tool Call

/// Represents a tool invocation requested by the LLM
struct AgentToolCall: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let argumentsJSON: String
    var result: String?

    /// Parse argumentsJSON into a dictionary. Returns empty dict on parse failure.
    var arguments: [String: Any] {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    init(id: String, name: String, argumentsJSON: String, result: String? = nil) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.result = result
    }
}

// MARK: - Conversation

/// A complete agent conversation with message history and linked atoms
struct AgentConversation: Codable, Identifiable, Sendable {
    let id: String
    var messages: [AgentMessage]
    let source: MessageSource
    let createdAt: Date
    var summary: String?
    var linkedAtomUUIDs: [String]

    init(source: MessageSource) {
        self.id = UUID().uuidString
        self.messages = []
        self.source = source
        self.createdAt = Date()
        self.summary = nil
        self.linkedAtomUUIDs = []
    }

    mutating func append(_ message: AgentMessage) {
        messages.append(message)
    }

    /// Total token count estimate (rough: 4 chars per token)
    var estimatedTokenCount: Int {
        messages.reduce(0) { $0 + ($1.content.count / 4) }
    }
}

// MARK: - Message Source

/// Where the conversation originated
enum MessageSource: String, Codable, Sendable {
    case telegram
    case whatsapp
    case inApp
}

// MARK: - Personality

/// Configures the agent's communication style
struct AgentPersonality: Codable, Sendable {
    let name: String
    let tone: String
    let verbosityLevel: Int // 1 = terse, 2 = balanced, 3 = detailed

    static let `default` = AgentPersonality(
        name: "Cosmo",
        tone: "warm, direct, creative partner",
        verbosityLevel: 2
    )

    /// Build the system prompt personality prefix
    var systemPromptFragment: String {
        let verbosity: String
        switch verbosityLevel {
        case 1: verbosity = "Be extremely concise. One or two sentences max."
        case 3: verbosity = "Be thorough and detailed in your responses."
        default: verbosity = "Be clear and concise but not terse."
        }
        return """
        You are \(name), a \(tone). \(verbosity)
        """
    }
}

// MARK: - Agent Configuration

/// Runtime configuration for the agent system
struct AgentConfiguration: Codable, Sendable {
    var provider: AgentProvider
    var model: String?
    var baseURL: String?
    var personality: AgentPersonality
    var defaultConfirmationTier: AgentConfirmationTier
    var maxConversationTokens: Int
    var enableProactiveInsights: Bool

    /// The model to use, falling back to the provider default
    var resolvedModel: String {
        model ?? provider.defaultModel
    }

    /// The base URL to use, falling back to the provider default
    var resolvedBaseURL: String {
        baseURL ?? provider.defaultBaseURL
    }

    static let `default` = AgentConfiguration(
        provider: .anthropic,
        model: nil,
        baseURL: nil,
        personality: .default,
        defaultConfirmationTier: .soft,
        maxConversationTokens: 100_000,
        enableProactiveInsights: true
    )

    /// Load from UserDefaults, falling back to default
    static func load() -> AgentConfiguration {
        guard let data = UserDefaults.standard.data(forKey: "agent_configuration"),
              let config = try? JSONDecoder().decode(AgentConfiguration.self, from: data) else {
            return .default
        }
        return config
    }

    /// Persist to UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "agent_configuration")
        }
    }
}

// MARK: - Agent Action Result

/// Result of an agent tool execution, returned to the orchestrator
struct AgentActionResult: Sendable {
    let toolCallId: String
    let success: Bool
    let output: String
    let atomsCreated: [String]   // UUIDs of atoms created
    let atomsModified: [String]  // UUIDs of atoms modified
    let requiresFollowUp: Bool

    static func success(_ output: String, toolCallId: String, created: [String] = [], modified: [String] = []) -> AgentActionResult {
        AgentActionResult(
            toolCallId: toolCallId,
            success: true,
            output: output,
            atomsCreated: created,
            atomsModified: modified,
            requiresFollowUp: false
        )
    }

    static func failure(_ error: String, toolCallId: String) -> AgentActionResult {
        AgentActionResult(
            toolCallId: toolCallId,
            success: false,
            output: error,
            atomsCreated: [],
            atomsModified: [],
            requiresFollowUp: false
        )
    }
}
