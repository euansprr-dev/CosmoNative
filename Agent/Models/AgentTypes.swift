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
        case .openRouter: return "anthropic/claude-sonnet-4.5"
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
        ("google/gemini-3-flash-preview", "Gemini 3 Flash"),
        ("google/gemini-3.1-flash-lite-preview", "Gemini 3.1 Flash Lite"),
        ("anthropic/claude-sonnet-4.5", "Claude Sonnet 4.5"),
        ("anthropic/claude-haiku-4.5", "Claude Haiku 4.5"),
        ("anthropic/claude-opus-4.6", "Claude Opus 4.6"),
        ("openai/gpt-4o", "GPT-4o"),
        ("openai/gpt-4o-mini", "GPT-4o Mini"),
        ("google/gemini-2.5-pro-preview", "Gemini 2.5 Pro"),
        ("deepseek/deepseek-chat", "DeepSeek V3"),
        ("deepseek/deepseek-r1", "DeepSeek R1"),
    ]
}

// MARK: - Agent Intent

/// Classifies the purpose of a user message to guide tool selection and confirmation tier
enum AgentIntent: String, Codable, Sendable {
    case capture      // Save an idea, swipe, or note
    case brainstorm   // Creative ideation session
    case plan         // Schedule tasks, time blocks
    case query        // Ask about existing data
    case execute      // Take action (organize workspace, complete task)
    case debrief      // End-of-day or session review
    case reflect      // Journal-style reflection
    case correct      // Fix something (rename, update, delete)
    case meta         // Settings, preferences, help
    case strategy     // Content strategy and planning
    case research     // Research companion — synthesize from knowledge base
    case synthesize   // Learning synthesis — patterns across atoms
    case analyze      // Deep analysis (patterns, connections, audience)
    case organize     // Workspace organization — thinkspaces, blocks, templates
}

// MARK: - Request Complexity

/// Determines whether a request needs single tool execution or multi-step workflow
enum RequestComplexity: String, Codable, Sendable {
    case simple       // Direct tool execution (1-2 tools)
    case compound     // Multi-step workflow needing planning
}

// MARK: - Workflow Step

/// A single step in a multi-step workflow plan
struct WorkflowStep: Codable, Identifiable, Sendable {
    let id: String
    let index: Int
    let action: String
    let description: String
    let tools: [String]
    let confirmationRequired: Bool
    var status: WorkflowStepStatus

    init(index: Int, action: String, description: String, tools: [String], confirmationRequired: Bool = false) {
        self.id = UUID().uuidString
        self.index = index
        self.action = action
        self.description = description
        self.tools = tools
        self.confirmationRequired = confirmationRequired
        self.status = .pending
    }
}

enum WorkflowStepStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case skipped
    case awaitingConfirmation
}

// MARK: - Workflow Plan

/// A complete multi-step workflow plan
struct WorkflowPlan: Codable, Identifiable, Sendable {
    let id: String
    let summary: String
    var steps: [WorkflowStep]
    var status: WorkflowPlanStatus
    let createdAt: Date

    init(summary: String, steps: [WorkflowStep]) {
        self.id = UUID().uuidString
        self.summary = summary
        self.steps = steps
        self.status = .proposed
        self.createdAt = Date()
    }

    var currentStepIndex: Int? {
        steps.firstIndex { $0.status == .pending || $0.status == .running || $0.status == .awaitingConfirmation }
    }

    var completedStepCount: Int {
        steps.filter { $0.status == .completed }.count
    }

    var isComplete: Bool {
        steps.allSatisfy { $0.status == .completed || $0.status == .skipped }
    }
}

enum WorkflowPlanStatus: String, Codable, Sendable {
    case proposed          // Presented to user, awaiting approval
    case approved          // User approved, executing
    case executing         // Currently running steps
    case paused            // Paused mid-execution (step failed or needs confirmation)
    case completed         // All steps done
    case cancelled         // User cancelled
}

// MARK: - Intent Classification Result

/// Result of agent intent classification with complexity routing
struct AgentIntentClassification: Codable, Sendable {
    let intent: AgentIntent
    let complexity: RequestComplexity
    let entities: [String: String]
    let confidence: Double

    init(intent: AgentIntent, complexity: RequestComplexity = .simple, entities: [String: String] = [:], confidence: Double = 1.0) {
        self.intent = intent
        self.complexity = complexity
        self.entities = entities
        self.confidence = confidence
    }
}

// MARK: - Creator Taste Profile

/// Dynamic profile built from user's creative preferences and outcomes
struct CreatorTasteProfile: Codable, Sendable {
    var preferredHookTypes: [String: Double]        // Hook type → weighted preference score
    var preferredFrameworks: [String: Double]        // Framework → weighted preference score
    var topicAffinities: [String: Double]            // Topic → interest score
    var platformStrengths: [String: Double]          // Platform → performance score
    var peakCreativeHours: [Int]                     // Hours when user is most productive
    var averageSessionMinutes: Double                // Average deep work session length
    var voiceTone: String                            // Detected voice tone (casual, formal, etc.)
    var editingPatterns: [String]                    // Common editing feedback patterns
    var lastUpdated: Date

    static let empty = CreatorTasteProfile(
        preferredHookTypes: [:],
        preferredFrameworks: [:],
        topicAffinities: [:],
        platformStrengths: [:],
        peakCreativeHours: [],
        averageSessionMinutes: 0,
        voiceTone: "conversational",
        editingPatterns: [],
        lastUpdated: Date()
    )
}

// MARK: - Content Recommendation

/// A recommended content piece for the weekly plan
struct ContentRecommendation: Codable, Sendable {
    let dayOfWeek: String
    let topic: String
    let format: String
    let hookType: String
    let framework: String
    let reasoning: String
    let matchingSwipeUUIDs: [String]
    let matchingIdeaUUIDs: [String]
    let estimatedEngagement: Double
}

// MARK: - Performance Prediction

/// Predicted performance of a draft based on historical patterns
struct AgentPerformancePrediction: Codable, Sendable {
    let overallScore: Double          // 0-10
    let hookScore: Double
    let frameworkScore: Double
    let readabilityScore: Double
    let suggestions: [String]
    let comparedToAverage: Double     // Multiplier vs user's average
}

// MARK: - Agent Learning Event

/// Tracks a single user decision for learning
struct AgentLearningEvent: Codable, Sendable {
    let id: String
    let category: LearningCategory
    let offered: String               // What the agent offered
    let selected: String?             // What the user selected (nil = rejected)
    let context: [String: String]     // Additional context (topic, platform, etc.)
    let timestamp: Date

    init(category: LearningCategory, offered: String, selected: String?, context: [String: String] = [:]) {
        self.id = UUID().uuidString
        self.category = category
        self.offered = offered
        self.selected = selected
        self.context = context
        self.timestamp = Date()
    }
}

enum LearningCategory: String, Codable, Sendable {
    case hookSelection        // Which hook variant was picked
    case frameworkSelection   // Which framework was chosen
    case draftFeedback        // What editing feedback was given
    case suggestionAcceptance // Whether a suggestion was accepted
    case workflowApproval     // Whether a workflow plan was approved
    case contentPerformance   // Post-publish performance tracking
}

// MARK: - Confirmation Tier

/// Controls how the agent handles action execution
enum AgentConfirmationTier: String, Codable, Sendable {
    case auto   // Execute immediately, no confirmation needed
    case soft   // Execute and inform user what was done
    case hard   // Require explicit confirmation before executing
}

// MARK: - Agent Model Tier

/// Three-tier model routing strategy for cost/quality optimization.
/// Router (Flash Lite) → Agent (Gemini 3 Flash) → Reasoner (Sonnet) via OpenRouter.
/// NOTE: Named `AgentModelTier` to avoid collision with `ModelTier` in VoiceAtom.swift
enum AgentModelTier: String, Codable, Sendable {
    case router      // Gemini 3.1 Flash Lite — intent classification, simple routing ($0.25/$1.50)
    case agent       // Gemini 3 Flash — main tool-calling loop, 90% of traffic ($0.50/$3.00)
    case reasoner    // Claude Sonnet 4.5 — complex multi-step reasoning, escalation ($3/$15)

    var modelId: String {
        switch self {
        case .router: return "google/gemini-3.1-flash-lite-preview"
        case .agent: return "google/gemini-3-flash-preview"
        case .reasoner: return "anthropic/claude-sonnet-4.5"
        }
    }

    var maxTokens: Int {
        switch self {
        case .router: return 512
        case .agent: return 8192
        case .reasoner: return 16384
        }
    }

    var contextWindow: Int {
        switch self {
        case .router: return 1_000_000
        case .agent: return 1_000_000
        case .reasoner: return 200_000
        }
    }

    var displayName: String {
        switch self {
        case .router: return "Flash Lite"
        case .agent: return "Flash"
        case .reasoner: return "Sonnet"
        }
    }

    /// Gemini 3 Flash thinking level per intent — nil means no thinking config needed
    static func thinkingLevel(for intent: AgentIntent) -> String? {
        switch intent {
        case .capture, .correct, .meta:
            return "minimal"
        case .query, .plan, .brainstorm, .debrief, .reflect:
            return "medium"
        case .analyze, .execute, .strategy, .research, .synthesize, .organize:
            return "high"
        }
    }
}

// MARK: - System Prompt (Cacheable)

/// Structured system prompt with a stable cached portion and a dynamic portion.
/// The cached portion (identity + methodology) stays constant across requests and
/// can be marked with `cache_control` for Anthropic prompt caching, dramatically
/// reducing input token costs.
struct SystemPrompt: Sendable {
    /// Static identity + methodology text — same across requests, cacheable
    let cached: String
    /// Dynamic live context — schedule, tasks, preferences, etc. Changes every request
    let dynamic: String

    /// Combined prompt for providers that don't support cache_control
    var combined: String {
        if dynamic.isEmpty { return cached }
        return cached + "\n\n" + dynamic
    }
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
    var id: String
    var messages: [AgentMessage]
    let source: MessageSource
    let createdAt: Date
    var summary: String?
    var linkedAtomUUIDs: [String]
    var topics: [String]

    init(source: MessageSource) {
        self.id = UUID().uuidString
        self.messages = []
        self.source = source
        self.createdAt = Date()
        self.summary = nil
        self.linkedAtomUUIDs = []
        self.topics = []
    }

    init(id: String, source: MessageSource, createdAt: Date = Date()) {
        self.id = id
        self.messages = []
        self.source = source
        self.createdAt = createdAt
        self.summary = nil
        self.linkedAtomUUIDs = []
        self.topics = []
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
        provider: .openRouter,
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

// MARK: - Agent Context Trace

/// Accumulates tool call summaries during the agent loop to expose
/// what context the AI looked at when generating a response.
struct AgentContextTrace: Sendable {
    var toolCalls: [TracedToolCall] = []

    /// True if the response was served by a fallback model (e.g. Opus → GPT 5.4)
    var failoverOccurred: Bool = false

    /// The model that actually served the response (set when failover occurs)
    var actualModel: String? = nil

    /// True if any tools were called during this response
    var hasContent: Bool { !toolCalls.isEmpty }

    /// Total number of tool calls
    var lookupCount: Int { toolCalls.count }

    /// Client profile name extracted from get_client_profile calls
    var clientProfileName: String? {
        toolCalls.first { $0.name == "get_client_profile" }?
            .flatArgs["name"] ?? toolCalls.first { $0.name == "get_client_profile" }?.resultSummary
    }

    /// Swipe titles referenced via search/find calls or surfaced from writing engine tools
    var swipesReferenced: [String] {
        toolCalls
            .filter {
                $0.name == "search_swipes" ||
                $0.name == "find_similar_swipes" ||
                $0.name == "filter_swipes_by_taxonomy" ||
                $0.name == "get_swipe_analysis" ||
                $0.name == "list_all_swipes"
            }
            .compactMap(\.resultSummary)
            .filter { !$0.isEmpty && $0 != "0 results" }
    }

    /// Tools used for knowledge queries and synthesis
    var knowledgeToolsUsed: [String] {
        toolCalls
            .filter { $0.name.contains("query") || $0.name.contains("search") || $0.name.contains("synthesize") || $0.name.contains("graph") }
            .map(\.name)
    }

    /// Atoms referenced in tool results
    var atomsReferenced: [String] {
        toolCalls
            .compactMap(\.resultSummary)
            .filter { !$0.isEmpty && $0 != "0 results" }
    }

    /// Number of learned skills injected into the system prompt
    var skillsApplied: Int = 0

    /// Summary of skills by intent (e.g. "3 writing, 1 planning")
    var skillsSummary: String? = nil

    mutating func append(name: String, flatArgs: [String: String], resultSummary: String?, isEmpty: Bool) {
        toolCalls.append(TracedToolCall(name: name, flatArgs: flatArgs, resultSummary: resultSummary, isEmpty: isEmpty))
    }
}

/// A single traced tool call with flattened arguments and a result summary
struct TracedToolCall: Sendable {
    let name: String
    let flatArgs: [String: String]
    let resultSummary: String?
    let isEmpty: Bool
}

// MARK: - Model Failover Chain

/// A single model in a failover chain
struct FailoverModel: Sendable {
    let modelId: String
    let maxRetries: Int
    let label: String
}

/// An ordered chain of models to try on failure.
/// When a request fails with a retryable error, the system walks the chain
/// trying each model up to its `maxRetries` before moving to the next.
struct ModelFailoverChain: Sendable {
    let models: [FailoverModel]

    /// Agent chain: Gemini 3 Flash → Sonnet → Haiku
    static let agentChain = ModelFailoverChain(models: [
        FailoverModel(modelId: "google/gemini-3-flash-preview", maxRetries: 2, label: "Flash"),
        FailoverModel(modelId: "anthropic/claude-sonnet-4.5", maxRetries: 1, label: "Sonnet"),
        FailoverModel(modelId: "anthropic/claude-haiku-4.5", maxRetries: 1, label: "Haiku"),
    ])

    /// Reasoner chain: Sonnet → Haiku
    static let reasonerChain = ModelFailoverChain(models: [
        FailoverModel(modelId: "anthropic/claude-sonnet-4.5", maxRetries: 2, label: "Sonnet"),
        FailoverModel(modelId: "anthropic/claude-haiku-4.5", maxRetries: 1, label: "Haiku"),
    ])

    /// Router chain: Flash Lite → Haiku (lightweight fallback)
    static let routerChain = ModelFailoverChain(models: [
        FailoverModel(modelId: "google/gemini-3.1-flash-lite-preview", maxRetries: 1, label: "Flash Lite"),
        FailoverModel(modelId: "anthropic/claude-haiku-4.5", maxRetries: 1, label: "Haiku"),
    ])

    /// Get the appropriate failover chain for a model tier
    static func chain(for tier: AgentModelTier) -> ModelFailoverChain {
        switch tier {
        case .agent: return .agentChain
        case .reasoner: return .reasonerChain
        case .router: return .routerChain
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

// MARK: - Live Tool Activity (WP5)

/// Emitted live during tool execution for UI streaming
enum ToolActivityEvent: Sendable {
    case started(name: String, displayLabel: String, args: [String: String])
    case completed(name: String, displayLabel: String, resultPreview: String?)
    case allDone(totalCalls: Int)
}

/// Groups related tool calls for collapsed display
struct ToolActivityGroup: Identifiable, Sendable {
    let id: UUID
    let category: String          // "Viewed", "Searched", "Generated", etc.
    var items: [ToolActivityItem]
    var isComplete: Bool

    init(category: String, items: [ToolActivityItem] = [], isComplete: Bool = false) {
        self.id = UUID()
        self.category = category
        self.items = items
        self.isComplete = isComplete
    }
}

struct ToolActivityItem: Identifiable, Sendable {
    let id: UUID
    let icon: String              // SF Symbol
    let label: String             // "Reading burnt out reel"
    let detail: String?           // Optional result preview
    var status: ToolItemStatus    // .active / .done

    init(icon: String, label: String, detail: String? = nil, status: ToolItemStatus = .active) {
        self.id = UUID()
        self.icon = icon
        self.label = label
        self.detail = detail
        self.status = status
    }
}

enum ToolItemStatus: Sendable {
    case active   // shimmer animation
    case done     // checkmark
}
