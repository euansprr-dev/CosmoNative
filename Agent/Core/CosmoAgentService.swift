// CosmoOS/Agent/Core/CosmoAgentService.swift
// Main orchestrator for the Cosmo Agent system — v2 with workflow planning

import Foundation
import Combine

struct ExplicitLessonSaveRequest: Equatable {
    let rule: String
    let evidence: String
    let category: String
}

enum ExplicitLessonCaptureParser {
    private static let queryPrefixes = [
        "what lessons", "show my lessons", "show lessons", "list lessons",
        "get lessons", "what have you learned", "what rules", "which lessons"
    ]

    private static let directivePatterns = [
        #"(?i)\bplease\s+save\s+this\s+as\s+a\s+lesson(?:\s+for\s+future\s+reference)?\b"#,
        #"(?i)\bsave\s+this\s+as\s+a\s+lesson(?:\s+for\s+future\s+reference)?\b"#,
        #"(?i)\bsave\s+this\s+lesson(?:\s+for\s+future\s+reference)?\b"#,
        #"(?i)\bsave\s+as\s+a\s+lesson(?:\s+for\s+future\s+reference)?\b"#,
        #"(?i)\bsave\s+this\s+rule(?:\s+for\s+future\s+reference)?\b"#,
        #"(?i)\bremember\s+this\s+rule(?:\s+for\s+future\s+reference)?\b"#,
        #"(?i)\blearn\s+this(?:\s+for\s+future\s+reference)?\b"#,
        #"(?i)\bsave\s+this\s+for\s+future\s+reference\b"#,
        #"(?i)\bremember\s+this\s+for\s+future\s+reference\b"#
    ]

    static func parse(_ text: String) -> ExplicitLessonSaveRequest? {
        let normalized = normalize(text)
        guard !normalized.isEmpty, !isLessonQuery(normalized) else { return nil }
        guard let lessonBody = strippedLessonBody(from: normalized) else { return nil }

        let paragraphs = splitParagraphs(lessonBody)
        guard let rule = paragraphs.first, !rule.isEmpty else { return nil }

        let evidence: String
        if paragraphs.count > 1 {
            evidence = paragraphs.dropFirst().joined(separator: "\n\n")
        } else {
            evidence = "Explicitly shared by user"
        }

        return ExplicitLessonSaveRequest(
            rule: rule,
            evidence: evidence,
            category: inferredCategory(from: normalized)
        )
    }

    static func shouldForceAgentFallback(_ text: String) -> Bool {
        if parse(text) != nil {
            return true
        }

        let normalized = normalize(text).lowercased()
        guard !isLessonQuery(normalized) else { return false }

        let hasDirectiveVerb = containsAny(normalized, ["save", "remember", "learn"])
        let hasLessonNoun = containsAny(normalized, ["lesson", "rule", "future reference"])
        return hasDirectiveVerb && hasLessonNoun
    }

    private static func strippedLessonBody(from text: String) -> String? {
        for pattern in directivePatterns {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let suffix = String(text[range.upperBound...])
            let trimmed = suffix.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-"))
            )
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private static func splitParagraphs(_ text: String) -> [String] {
        var paragraphs: [String] = []
        var currentLines: [String] = []

        for rawLine in text.components(separatedBy: "\n") {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                if !currentLines.isEmpty {
                    paragraphs.append(currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
                    currentLines.removeAll()
                }
                continue
            }
            currentLines.append(trimmedLine)
        }

        if !currentLines.isEmpty {
            paragraphs.append(currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return paragraphs.filter { !$0.isEmpty }
    }

    private static func inferredCategory(from text: String) -> String {
        let lower = text.lowercased()

        if containsAny(lower, ["hook", "opening line", "first line", "headline", "scroll stop", "open loop"]) {
            return "hook_style"
        }

        if containsAny(lower, ["cta", "call to action", "comment ", "dm ", "reply with", "keyword", "book a call"]) {
            return "cta"
        }

        if containsAny(lower, ["voice", "tone", "conversational", "cadence", "rhythm", "phrasing", "spoken", "sounds like", "sound like", "natural", "human"]) {
            return "voice"
        }

        if containsAny(lower, ["structure", "sequence", "flow", "order", "logic", "causal", "transition", "outline", "beat", "framework"]) {
            return "structure"
        }

        if containsAny(lower, ["format", "slide", "slides", "word count", "layout", "platform", "carousel", "thread", "tweet", "reel", "line break", "spacing", "density"]) {
            return "format"
        }

        return "general"
    }

    private static func isLessonQuery(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return queryPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

@MainActor
class CosmoAgentService: ObservableObject {
    static let shared = CosmoAgentService()

    // MARK: - Published State

    /// True when at least one session is processing (supports concurrent sessions).
    @Published var isProcessing = false
    private var activeSessionCount = 0
    @Published var currentConversation: AgentConversation?
    @Published var activeProvider: AgentProvider = .anthropic
    @Published var selectedModel: String = AgentProvider.anthropic.defaultModel
    @Published var lastError: String?
    @Published var activeWorkflowPlan: WorkflowPlan?

    // MARK: - Dependencies

    private var llmProvider: LLMProvider?
    private let toolRegistry = AgentToolRegistry.shared
    private let toolExecutor = AgentToolExecutor.shared
    private let contextAssembler = AgentContextAssembler.shared
    private let workflowPlanner = AgentWorkflowPlanner.shared

    /// Maximum tool call iterations for simple intents (queries, captures, corrections)
    private let baseMaxToolIterations = 12

    /// Returns the max tool iterations for a given intent. Creative/analytical
    /// intents that chain many tools (profile → swipes → beats → draft → score)
    /// get a higher ceiling to avoid "ran out of processing steps" on complex requests.
    private func maxToolIterations(for intent: AgentIntent) -> Int {
        switch intent {
        case .draft, .strategy, .brainstorm:
            return 16
        case .analyze, .execute, .debrief:
            return 12
        case .capture, .query, .plan, .correct, .reflect, .meta:
            return baseMaxToolIterations
        }
    }

    /// Per-conversation token tracking for cost guard
    private var conversationTokenCounts: [String: Int] = [:]
    private let tokenWarningThreshold = 20_000

    /// Per-conversation feedback tracking: conversationId → (generationId, agentResponse).
    /// Scoped per conversation to prevent cross-topic contamination in Forum Topics.
    private var pendingFeedback: [String: (generationId: UUID, response: String)] = [:]

    /// Per-conversation active numbered items from the last tool result,
    /// so numbered references like "number one" resolve within the correct conversation.
    private var activeItemsContext: [String: String] = [:]

    // MARK: - Init

    private init() {
        // Load saved provider preference from UserDefaults
        if let saved = UserDefaults.standard.string(forKey: "agent_provider"),
           let provider = AgentProvider(rawValue: saved) {
            activeProvider = provider
        }
        if let model = UserDefaults.standard.string(forKey: "agent_model") {
            selectedModel = Self.migrateModelId(model)
            if selectedModel != model {
                UserDefaults.standard.set(selectedModel, forKey: "agent_model")
            }
        }
        refreshProvider()
    }

    // MARK: - Provider Management

    func setProvider(_ provider: AgentProvider) {
        activeProvider = provider
        selectedModel = provider.defaultModel
        UserDefaults.standard.set(provider.rawValue, forKey: "agent_provider")
        UserDefaults.standard.set(selectedModel, forKey: "agent_model")
        refreshProvider()
    }

    func setModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "agent_model")
    }

    /// Migrate old model IDs to current OpenRouter format
    private static func migrateModelId(_ model: String) -> String {
        let migrations: [String: String] = [
            "anthropic/claude-sonnet-4-5-20250929": "anthropic/claude-sonnet-4.5",
            "anthropic/claude-haiku-4-5-20251001": "anthropic/claude-haiku-4.5",
        ]
        return migrations[model] ?? model
    }

    private func refreshProvider() {
        let apiKey: String?
        if activeProvider == .openRouter {
            apiKey = APIKeys.openRouter
        } else {
            apiKey = APIKeys.agentLLM
        }
        let baseProvider = LLMProviderFactory.create(
            provider: activeProvider,
            apiKey: apiKey,
            baseURL: APIKeys.agentLLMBaseURL
        )

        // Wrap OpenRouter in failover — it supports multiple models on the same API
        if activeProvider == .openRouter {
            llmProvider = FailoverLLMProvider(
                wrapping: baseProvider,
                chain: .defaultChain
            )
        } else {
            llmProvider = baseProvider
        }
    }

    // MARK: - Connection Test

    func testConnection() async -> (success: Bool, message: String) {
        guard let provider = llmProvider else {
            return (false, "No provider configured")
        }
        do {
            let testMessage = AgentMessage.user("Say 'connected' in one word.")
            let response = try await provider.complete(
                messages: [testMessage],
                tools: nil,
                model: selectedModel
            )
            let reply = response.content ?? "OK"
            return (true, "Connected -- \(reply)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Summarize (Internal LLM access for memory service)

    /// Simple LLM completion without tools, used by ConversationMemoryService.
    /// Defaults to Haiku tier for cost efficiency — summarization is a simple extraction task.
    func summarize(messages: [AgentMessage], tier: AgentModelTier = .sensor) async throws -> String? {
        guard let provider = llmProvider else { return nil }
        let response = try await provider.complete(
            messages: messages,
            tools: nil,
            model: selectedModel,
            tier: tier
        )
        return response.content
    }

    // MARK: - Process Message (Main Entry Point)

    /// Process a user message through the full agent pipeline:
    /// classify intent -> check complexity -> route to workflow or direct -> return response
    func processMessage(
        _ text: String,
        conversationId: String? = nil,
        source: MessageSource = .inApp,
        tierOverride: AgentModelTier? = nil,
        onToolActivity: (@Sendable (ToolActivityEvent) -> Void)? = nil
    ) async -> (String, AgentContextTrace) {
        activeSessionCount += 1
        isProcessing = true
        lastError = nil
        defer {
            activeSessionCount -= 1
            if activeSessionCount == 0 { isProcessing = false }
        }

        guard let provider = llmProvider else {
            let msg = "Cosmo Agent is not configured. Please set up an AI provider in Settings."
            lastError = msg
            return (msg, AgentContextTrace())
        }

        // 0. Fast-path: intercept "Idea for [client]: [title]" and "Idea: [title]" patterns.
        // Creates the idea directly without calling the LLM — zero latency, zero API cost.
        if let fastResult = await tryFastIdeaCapture(text) {
            return (fastResult, AgentContextTrace())
        }

        // 0b. Fast-path explicit lesson saves so they never fall through to idea capture.
        if let lessonResult = await tryExplicitLessonSave(text, conversationId: conversationId, source: source) {
            return (lessonResult, AgentContextTrace())
        }

        // 1. Check for active workflow interactions
        if let chatId = conversationId, let plan = workflowPlanner.activeWorkflows[chatId] {
            if plan.status == .proposed {
                let response = await handleWorkflowResponse(text: text, chatId: chatId)
                return (response, AgentContextTrace())
            }
        }

        // 2. Classify intent (fast keyword heuristic + complexity detection)
        let classification = classifyIntent(text)

        // 3. Load or create conversation
        var conversation: AgentConversation
        if let convId = conversationId,
           let existing = await ConversationMemoryService.shared.loadConversation(id: convId) {
            conversation = existing
        } else if let convId = conversationId {
            conversation = AgentConversation(id: convId, source: source)
        } else {
            conversation = AgentConversation(source: source)
        }

        // 4. Topic-based session boundary detection for Telegram (WP8)
        // When the user starts a new content piece in an existing long conversation,
        // compress the old conversation into a summary and start fresh.
        if source == .telegram || source == .whatsapp {
            let shouldRotate = detectSessionBoundary(text: text, intent: classification.intent, conversation: conversation)
            if shouldRotate {
                await rotateConversationSession(&conversation)
            }
        }

        // 5. Add user message
        conversation.append(.user(text))

        // 6. Escalate intent if conversation has creative history
        // Prevents mid-conversation regression from Opus to Haiku when giving
        // creative direction without explicit draft keywords
        let effectiveIntent = escalateIntentFromConversation(classification.intent, conversation: conversation)

        // 7. Route to direct tool execution for all sources
        // The LLM handles multi-step operations naturally through its tool loop
        // (maxToolIterations = 8). No need for workflow plan approval gates.
        return await processSimpleMessage(
            text: text,
            intent: effectiveIntent,
            conversation: &conversation,
            provider: provider,
            tierOverride: tierOverride,
            onToolActivity: onToolActivity
        )
    }

    // MARK: - Simple Message Processing

    private func processSimpleMessage(
        text: String,
        intent: AgentIntent,
        conversation: inout AgentConversation,
        provider: LLMProvider,
        tierOverride: AgentModelTier? = nil,
        onToolActivity: (@Sendable (ToolActivityEvent) -> Void)? = nil
    ) async -> (String, AgentContextTrace) {
        // --- Feedback classification for previous generation (scoped per conversation) ---
        if let feedback = pendingFeedback[conversation.id] {
            let lower = text.lowercased()
            let rejectionSignals = ["try again", "redo", "change", "not quite", "wrong", "no,",
                                    "no.", "different", "rewrite", "too ", "less ", "more "]
            let acceptanceSignals = ["looks good", "perfect", "yes", "love it", "great",
                                     "send it", "next", "continue", "awesome", "nice", "ship it"]
            let isRejection = rejectionSignals.contains { lower.contains($0) }
            let isAcceptance = acceptanceSignals.contains { lower.contains($0) }

            let accepted = isAcceptance || !isRejection
            let agentOutput = feedback.response
            let userFeedback = text

            Task {
                await AgentOutcomeTracker.shared.trackSuggestionAcceptance(
                    suggestion: agentOutput,
                    userFeedback: userFeedback,
                    accepted: accepted,
                    category: intent.rawValue
                )
            }
            pendingFeedback.removeValue(forKey: conversation.id)
        }

        // Get preferences
        let preferences = await PreferenceLearningEngine.shared.getAllPreferences(scope: nil)

        // Get tools for intent (source-gated: Telegram vs in-app UX tools)
        let tools = toolRegistry.toolsForIntent(intent, source: conversation.source)

        // Assemble system prompt with intent-aware context (cached/dynamic split)
        let systemPrompt = await contextAssembler.assembleSystemPrompt(
            conversation: conversation,
            preferences: preferences,
            tools: tools,
            intent: intent,
            activeItemsContext: activeItemsContext[conversation.id]
        )

        // Build message array for LLM (no system message — passed separately for caching)
        var llmMessages: [AgentMessage] = []

        // Add conversation history with token-aware windowing (WP3)
        // For lightweight intents (capture/correct), use a smaller window and aggressively
        // truncate tool results to prevent heavy writing context from overwhelming Haiku.
        let lightweightIntents: Set<AgentIntent> = [.capture, .correct, .meta]
        let rawWindow: [AgentMessage]
        if lightweightIntents.contains(intent) {
            rawWindow = buildLightweightWindow(conversation.messages)
        } else {
            rawWindow = buildTokenAwareWindow(conversation.messages)
        }
        // Sanitize to remove orphaned tool_result messages whose tool_use was truncated
        let historyWindow = sanitizeToolPairs(rawWindow)
        llmMessages.append(contentsOf: historyWindow)

        // --- Intent-based model tier routing ---
        let modelTier: AgentModelTier
        if let override = tierOverride {
            modelTier = override
        } else {
            switch intent {
            case .capture, .plan, .query, .correct:
                modelTier = .sensor      // Haiku — data operations, lookups, captures
            case .analyze, .strategy, .debrief, .reflect, .execute, .meta:
                modelTier = .strategist  // Sonnet — analytical reasoning, strategy
            case .brainstorm, .draft:
                modelTier = .writer      // Opus — creative writing coordination needs full reasoning to follow tool-use instructions precisely
            }
        }

        // For draft intent, guide the agent to use writing tools (not inline text)
        // but let it decide whether to continue existing content or create new
        if intent == .draft || intent == .brainstorm {
            let linkedUUIDs = conversation.linkedAtomUUIDs
            var toolGuidance = "IMPORTANT: Do NOT write slides, tweets, scripts, or any content longer than 3 sentences directly in your response. " +
                "Use generate_draft() or generate_outline() — the writing engine has full client context, swipe blueprints, and voice fingerprints that you lack."

            if conversation.source == .telegram || conversation.source == .whatsapp {
                // Remote sources: ALWAYS create fresh content to avoid overwriting in-app work
                toolGuidance += "\n\nALWAYS call create_content() first to create a fresh content atom, then use the new UUID for generate_outline / generate_draft. " +
                    "NEVER reuse an existing contentUUID — the user may have that content open in the app."
            } else if let lastUUID = linkedUUIDs.last {
                toolGuidance += "\n\nThe most recent content atom is \(lastUUID). " +
                    "If the user is continuing work on that same piece, use it. " +
                    "If the user is requesting NEW or DIFFERENT content, call create_content() first to create a fresh atom, then use the new UUID."
            }

            llmMessages.append(AgentMessage.system(toolGuidance))
        }

        // Context trace — accumulates tool call summaries for transparency
        var contextTrace = AgentContextTrace()

        // Populate skills transparency from assembled prompt
        let appliedSkills = contextAssembler.lastInjectedSkills
        if !appliedSkills.isEmpty {
            var byIntent: [String: Int] = [:]
            for s in appliedSkills {
                byIntent[s.intent ?? "universal", default: 0] += 1
            }
            contextTrace.skillsApplied = appliedSkills.count
            contextTrace.skillsSummary = byIntent.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
        }

        // Update failover chain for the current model tier (OpenRouter only)
        if let failoverProvider = provider as? FailoverLLMProvider {
            let tierChain = ModelFailoverChain.chain(for: modelTier)
            // Re-wrap the inner provider with the tier-appropriate chain
            let updatedProvider = FailoverLLMProvider(
                wrapping: failoverProvider,
                chain: tierChain
            )
            // Use updatedProvider for completions in this call
            return await executeToolLoop(
                provider: updatedProvider,
                llmMessages: &llmMessages,
                tools: tools,
                modelTier: modelTier,
                systemPrompt: systemPrompt,
                intent: intent,
                conversation: &conversation,
                contextTrace: &contextTrace,
                onToolActivity: onToolActivity
            )
        }

        return await executeToolLoop(
            provider: provider,
            llmMessages: &llmMessages,
            tools: tools,
            modelTier: modelTier,
            systemPrompt: systemPrompt,
            intent: intent,
            conversation: &conversation,
            contextTrace: &contextTrace,
            onToolActivity: onToolActivity
        )
    }

    /// Execute the LLM tool loop, iterating until the LLM returns text-only or the limit is reached.
    private func executeToolLoop(
        provider: LLMProvider,
        llmMessages: inout [AgentMessage],
        tools: [LLMToolDefinition],
        modelTier: AgentModelTier,
        systemPrompt: SystemPrompt,
        intent: AgentIntent,
        conversation: inout AgentConversation,
        contextTrace: inout AgentContextTrace,
        onToolActivity: (@Sendable (ToolActivityEvent) -> Void)? = nil
    ) async -> (String, AgentContextTrace) {
        // Tool loop — iterate until the LLM returns a text-only response
        let iterationLimit = maxToolIterations(for: intent)
        var iterations = 0
        var finalResponse = ""

        // Pass the activity callback to the tool executor so context-loading
        // sub-tools (load_client_profile, load_swipe, etc.) can stream progress.
        // Each session gets a unique token so concurrent sessions on different chats
        // don't clear each other's callbacks.
        let sessionToken = UUID()
        toolExecutor.setToolActivity(onToolActivity, token: sessionToken)

        while iterations < iterationLimit {
            iterations += 1

            do {
                let response = try await provider.complete(
                    messages: llmMessages,
                    tools: tools.isEmpty ? nil : tools,
                    model: selectedModel,
                    tier: modelTier,
                    systemPrompt: systemPrompt
                )

                if response.toolCalls.isEmpty {
                    finalResponse = response.content ?? "I couldn't generate a response."
                    break
                }

                // Assistant requested tool calls — execute them
                let assistantMsg = AgentMessage.assistant(
                    response.content ?? "",
                    toolCalls: response.toolCalls
                )
                llmMessages.append(assistantMsg)
                conversation.append(assistantMsg)

                let generationTools: Set<String> = ["generate_draft", "generate_outline", "generate_hooks", "write_draft"]
                for toolCall in response.toolCalls {
                    // Emit tool activity started event
                    let flatArgs = flattenArguments(toolCall.arguments)
                    let displayLabel = toolDisplayLabel(for: toolCall.name, args: flatArgs)
                    onToolActivity?(.started(name: toolCall.name, displayLabel: displayLabel, args: flatArgs))

                    let result: String
                    do {
                        result = try await toolExecutor.execute(
                            toolName: toolCall.name,
                            arguments: toolCall.arguments
                        )
                    } catch {
                        result = "{\"error\": \"\(error.localizedDescription)\"}"
                    }

                    // Emit tool activity completed event
                    let preview = extractResultSummary(result, toolName: toolCall.name)
                    onToolActivity?(.completed(name: toolCall.name, displayLabel: displayLabel, resultPreview: preview))

                    // Track created atom UUIDs in conversation memory
                    if let data = result.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let uuid = json["uuid"] as? String,
                       json["success"] as? Bool == true {
                        if !conversation.linkedAtomUUIDs.contains(uuid) {
                            conversation.linkedAtomUUIDs.append(uuid)
                        }
                    }

                    // Track active items for numbered reference resolution
                    if let data = result.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = json["results"] as? [[String: Any]],
                       results.count >= 2 {
                        var itemLines: [String] = ["[ACTIVE ITEMS from last tool result]"]
                        for (i, item) in results.prefix(10).enumerated() {
                            let title = item["title"] as? String ?? "Untitled"
                            let uuid = item["uuid"] as? String ?? ""
                            itemLines.append("\(i + 1). \(title) (uuid: \(uuid))")
                        }
                        activeItemsContext[conversation.id] = itemLines.joined(separator: "\n")
                    }

                    // Flag generation tools for acceptance tracking on next user message (scoped per conversation)
                    if generationTools.contains(toolCall.name) {
                        pendingFeedback[conversation.id] = (generationId: UUID(), response: "")
                    }

                    // Accumulate context trace
                    contextTrace.append(
                        name: toolCall.name,
                        flatArgs: flatArgs,
                        resultSummary: preview,
                        isEmpty: isEmptyResult(result)
                    )

                    let toolMsg = AgentMessage.tool(callId: toolCall.id, content: result)
                    llmMessages.append(toolMsg)
                    conversation.append(toolMsg)
                }

            } catch {
                lastError = error.localizedDescription
                finalResponse = "Sorry, I encountered an error: \(error.localizedDescription)"
                break
            }
        }

        if finalResponse.isEmpty {
            finalResponse = "I ran out of processing steps. Please try a simpler request."
        }

        // Track failover in context trace for transparency
        if let failover = provider as? FailoverLLMProvider, failover.failoverOccurred {
            contextTrace.failoverOccurred = true
            contextTrace.actualModel = failover.lastUsedModel
        }

        // Emit all-done event for live activity UI
        onToolActivity?(.allDone(totalCalls: contextTrace.toolCalls.count))

        // Clear the callback only if this session's token still owns it.
        // Prevents Session A from nilling out Session B's callback in concurrent chats.
        toolExecutor.clearToolActivity(token: sessionToken)

        // Track token usage for cost guard (internal only — never shown to user)
        let messageTokens = conversation.estimatedTokenCount
        let convId = conversation.id
        conversationTokenCounts[convId] = messageTokens

        // Compress old tool results to reduce token usage in future messages
        compressOldToolResults(&conversation)

        // Save assistant response to conversation
        conversation.append(.assistant(finalResponse))
        currentConversation = conversation

        // Store response for learning feedback on next user message (scoped per conversation)
        if pendingFeedback[conversation.id] != nil {
            pendingFeedback[conversation.id]?.response = finalResponse
        }

        // Persist conversation to memory
        await ConversationMemoryService.shared.saveConversation(conversation)

        return (finalResponse, contextTrace)
    }

    // MARK: - Streaming Message Processing

    /// Process a user message with streaming text output via onChunk callback.
    /// Tool execution runs normally (non-streamed); only the final LLM text response streams.
    func processMessageStreaming(
        _ text: String,
        conversationId: String? = nil,
        source: MessageSource = .telegram,
        onChunk: @escaping @Sendable (String) -> Void
    ) async -> (String, AgentContextTrace) {
        activeSessionCount += 1
        isProcessing = true
        lastError = nil
        defer {
            activeSessionCount -= 1
            if activeSessionCount == 0 { isProcessing = false }
        }

        guard let provider = llmProvider else {
            let msg = "Cosmo Agent is not configured. Please set up an AI provider in Settings."
            lastError = msg
            return (msg, AgentContextTrace())
        }

        if let lessonResult = await tryExplicitLessonSave(text, conversationId: conversationId, source: source) {
            return (lessonResult, AgentContextTrace())
        }

        // Load or create conversation
        var conversation: AgentConversation
        if let convId = conversationId,
           let existing = await ConversationMemoryService.shared.loadConversation(id: convId) {
            conversation = existing
        } else if let convId = conversationId {
            conversation = AgentConversation(id: convId, source: source)
        } else {
            conversation = AgentConversation(source: source)
        }

        // Session boundary for Telegram
        if source == .telegram || source == .whatsapp {
            let classification = classifyIntent(text)
            if detectSessionBoundary(text: text, intent: classification.intent, conversation: conversation) {
                await rotateConversationSession(&conversation)
            }
        }

        conversation.append(.user(text))

        let classification = classifyIntent(text)
        let effectiveIntent = escalateIntentFromConversation(classification.intent, conversation: conversation)

        let preferences = await PreferenceLearningEngine.shared.getAllPreferences(scope: nil)
        let tools = toolRegistry.toolsForIntent(effectiveIntent, source: conversation.source)

        let systemPrompt = await contextAssembler.assembleSystemPrompt(
            conversation: conversation,
            preferences: preferences,
            tools: tools,
            intent: effectiveIntent,
            activeItemsContext: activeItemsContext[conversation.id]
        )

        var llmMessages: [AgentMessage] = []
        let lightweightIntents: Set<AgentIntent> = [.capture, .correct, .meta]
        let rawWindow: [AgentMessage]
        if lightweightIntents.contains(effectiveIntent) {
            rawWindow = buildLightweightWindow(conversation.messages)
        } else {
            rawWindow = buildTokenAwareWindow(conversation.messages)
        }
        let historyWindow = sanitizeToolPairs(rawWindow)
        llmMessages.append(contentsOf: historyWindow)

        let modelTier: AgentModelTier
        switch effectiveIntent {
        case .capture, .plan, .query, .correct:
            modelTier = .sensor
        case .analyze, .strategy, .debrief, .reflect, .execute, .meta:
            modelTier = .strategist
        case .brainstorm, .draft:
            modelTier = .writer      // Opus — creative writing coordination needs full reasoning to follow tool-use instructions precisely
        }

        // For draft intent with active content, inject a system message forcing tool use
        if effectiveIntent == .draft || effectiveIntent == .brainstorm {
            let linkedUUIDs = conversation.linkedAtomUUIDs
            if conversation.source == .telegram || conversation.source == .whatsapp {
                // Remote sources: ALWAYS create fresh content to avoid overwriting in-app work
                let forceToolMsg = AgentMessage.system(
                    "REMINDER: ALWAYS call create_content() first, then use the NEW UUID for generate_draft() or generate_outline(). " +
                    "NEVER reuse an existing contentUUID — the user may have that content open in the app."
                )
                llmMessages.append(forceToolMsg)
            } else if let activeUUID = linkedUUIDs.last {
                let forceToolMsg = AgentMessage.system(
                    "REMINDER: You MUST use generate_draft(contentUUID: \"\(activeUUID)\") or generate_outline(contentUUID: \"\(activeUUID)\") for ALL content creation. " +
                    "Do NOT write slides, tweets, scripts, or any content longer than 3 sentences directly in your response. " +
                    "The writing engine has full client context, swipe blueprints, and voice fingerprints that you lack."
                )
                llmMessages.append(forceToolMsg)
            }
        }

        var contextTrace = AgentContextTrace()

        // Tool loop with streaming on final text response
        let iterationLimit = maxToolIterations(for: effectiveIntent)
        var iterations = 0
        var finalResponse = ""

        // Resolve provider with tier-appropriate failover chain
        let activeProvider: LLMProvider
        if let failoverProvider = provider as? FailoverLLMProvider {
            let tierChain = ModelFailoverChain.chain(for: modelTier)
            activeProvider = FailoverLLMProvider(wrapping: failoverProvider, chain: tierChain)
        } else {
            activeProvider = provider
        }

        while iterations < iterationLimit {
            iterations += 1

            do {
                let response: LLMResponse

                // Check if we can stream: must be a streaming provider
                if let streamingProvider = activeProvider as? StreamingLLMProvider {
                    // Stream with full system prompt and tools
                    response = try await streamingProvider.completeStreaming(
                        messages: llmMessages,
                        tools: tools.isEmpty ? nil : tools,
                        model: selectedModel,
                        tier: modelTier,
                        systemPrompt: systemPrompt,
                        onChunk: { chunk in
                            onChunk(chunk)
                        }
                    )
                } else {
                    response = try await activeProvider.complete(
                        messages: llmMessages,
                        tools: tools.isEmpty ? nil : tools,
                        model: selectedModel,
                        tier: modelTier,
                        systemPrompt: systemPrompt
                    )
                }

                if response.toolCalls.isEmpty {
                    finalResponse = response.content ?? "I couldn't generate a response."
                    break
                }

                // Tool calls — execute non-streamed
                let assistantMsg = AgentMessage.assistant(
                    response.content ?? "",
                    toolCalls: response.toolCalls
                )
                llmMessages.append(assistantMsg)
                conversation.append(assistantMsg)

                let generationTools: Set<String> = ["generate_draft", "generate_outline", "generate_hooks", "write_draft"]
                for toolCall in response.toolCalls {
                    let result: String
                    do {
                        result = try await toolExecutor.execute(
                            toolName: toolCall.name,
                            arguments: toolCall.arguments
                        )
                    } catch {
                        result = "{\"error\": \"\(error.localizedDescription)\"}"
                    }

                    if let data = result.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let uuid = json["uuid"] as? String,
                       json["success"] as? Bool == true {
                        if !conversation.linkedAtomUUIDs.contains(uuid) {
                            conversation.linkedAtomUUIDs.append(uuid)
                        }
                    }

                    if generationTools.contains(toolCall.name) {
                        pendingFeedback[conversation.id] = (generationId: UUID(), response: "")
                    }

                    contextTrace.append(
                        name: toolCall.name,
                        flatArgs: flattenArguments(toolCall.arguments),
                        resultSummary: extractResultSummary(result, toolName: toolCall.name),
                        isEmpty: isEmptyResult(result)
                    )

                    let toolMsg = AgentMessage.tool(callId: toolCall.id, content: result)
                    llmMessages.append(toolMsg)
                    conversation.append(toolMsg)
                }

            } catch {
                lastError = error.localizedDescription
                finalResponse = "Sorry, I encountered an error: \(error.localizedDescription)"
                break
            }
        }

        if finalResponse.isEmpty {
            finalResponse = "I ran out of processing steps. Please try a simpler request."
        }

        // Track failover in context trace for transparency
        if let failover = activeProvider as? FailoverLLMProvider, failover.failoverOccurred {
            contextTrace.failoverOccurred = true
            contextTrace.actualModel = failover.lastUsedModel
        }

        compressOldToolResults(&conversation)
        conversation.append(.assistant(finalResponse))
        currentConversation = conversation
        if pendingFeedback[conversation.id] != nil {
            pendingFeedback[conversation.id]?.response = finalResponse
        }
        await ConversationMemoryService.shared.saveConversation(conversation)

        return (finalResponse, contextTrace)
    }

    // MARK: - Workflow Response Handling

    private func handleWorkflowResponse(text: String, chatId: String) async -> String {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)

        if lower == "approve" || lower == "go" || lower == "yes" || lower == "ok" {
            guard var plan = workflowPlanner.activeWorkflows[chatId] else {
                return "No active plan to approve."
            }
            plan.status = .approved
            workflowPlanner.activeWorkflows[chatId] = plan

            let result = await workflowPlanner.executeWorkflow(&plan, chatId: chatId)
            workflowPlanner.activeWorkflows.removeValue(forKey: chatId)
            activeWorkflowPlan = nil

            return result
        } else if lower == "cancel" || lower == "no" || lower == "stop" {
            workflowPlanner.activeWorkflows.removeValue(forKey: chatId)
            activeWorkflowPlan = nil
            return "Plan cancelled. What would you like to do instead?"
        } else {
            return "I have a plan waiting for your approval. Reply 'approve' to proceed or 'cancel' to discard it."
        }
    }

    // MARK: - Intent Classification

    // MARK: - Fast Idea Capture

    /// Save an explicit lesson/rule immediately, without running the LLM tool loop.
    /// Used as a guardrail before Telegram/agent routing so lesson directives can't become idea captures.
    func tryExplicitLessonSave(
        _ text: String,
        conversationId: String? = nil,
        source: MessageSource = .inApp
    ) async -> String? {
        guard let lesson = ExplicitLessonCaptureParser.parse(text) else { return nil }

        var arguments: [String: Any] = [
            "lessons": [[
                "rule": lesson.rule,
                "category": lesson.category,
                "evidence": lesson.evidence
            ]]
        ]

        let resolvedClientName = await resolveExplicitLessonClientName(in: text)
        if let resolvedClientName {
            arguments["clientName"] = resolvedClientName
        }

        let responseText: String
        do {
            let result = try await toolExecutor.execute(toolName: "save_lessons", arguments: arguments)
            let savedCount = extractSavedLessonCount(from: result)

            if savedCount > 0 {
                let moduleName = PromptTemplateStore.shared.moduleForCategory(lesson.category)?.title
                let scopeNote = resolvedClientName.map { " for \($0)" } ?? ""
                responseText = buildExplicitLessonSuccessMessage(moduleName: moduleName, scopeNote: scopeNote)
            } else {
                responseText = "I couldn't save that lesson right now."
            }
        } catch {
            responseText = "I couldn't save that lesson right now."
        }

        await persistFastPathConversation(text: text, response: responseText, conversationId: conversationId, source: source)
        return responseText
    }

    /// Intercepts idea-capture patterns and creates the atom directly without the LLM.
    /// Returns nil if the message doesn't match any pattern (falls through to normal processing).
    ///
    /// Supported patterns:
    ///   - "Idea for [client]: [content]"
    ///   - "Idea [client]: [content]"  (no "for")
    ///   - "Idea: [content]"
    ///   - "save this idea [content]" / "save idea [content]" / "new idea [content]"
    ///
    /// Metadata lines like "Format: reel" or "Platform: instagram" are parsed from trailing lines.
    func tryFastIdeaCapture(_ text: String) async -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern 1: "Idea for [client]: [title + optional body]"
        if lower.hasPrefix("idea for ") {
            let afterPrefix = String(text.dropFirst("idea for ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIdx = afterPrefix.firstIndex(of: ":") else { return nil }
            let clientName = String(afterPrefix[afterPrefix.startIndex..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawContent = String(afterPrefix[afterPrefix.index(after: colonIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawContent.isEmpty else { return nil }

            let (ideaContent, format, platform) = extractIdeaMetadataLines(rawContent)
            let (title, body) = splitIdeaTitleBody(ideaContent)

            return await createFastIdea(title: title, body: body, clientName: clientName, format: format, platform: platform)
        }

        // Pattern 2: "Idea: [title + optional body]"
        if lower.hasPrefix("idea:") {
            let rawContent = String(text.dropFirst("idea:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawContent.isEmpty else { return nil }

            let (ideaContent, format, platform) = extractIdeaMetadataLines(rawContent)
            let (title, body) = splitIdeaTitleBody(ideaContent)

            return await createFastIdea(title: title, body: body, clientName: nil, format: format, platform: platform)
        }

        // Pattern 3: "Idea [client]: [content]" — client name directly after "idea" (no "for")
        // Matches: "Idea josh: co-living vs rental", "Idea michael: podcast series"
        if lower.hasPrefix("idea ") && !lower.hasPrefix("idea for ") {
            let afterIdea = String(text.dropFirst("idea ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let colonIdx = afterIdea.firstIndex(of: ":") {
                let clientName = String(afterIdea[afterIdea.startIndex..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawContent = String(afterIdea[afterIdea.index(after: colonIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Only match if client name is short (1-3 words) and content is non-empty
                guard !rawContent.isEmpty, !clientName.isEmpty, clientName.split(separator: " ").count <= 3 else { return nil }

                let (ideaContent, format, platform) = extractIdeaMetadataLines(rawContent)
                let (title, body) = splitIdeaTitleBody(ideaContent)

                return await createFastIdea(title: title, body: body, clientName: clientName, format: format, platform: platform)
            }
        }

        // Pattern 4: "save [this] idea ..." / "new idea ..."
        let saveIdeaPrefixes = ["save this idea ", "save idea: ", "save idea ", "new idea: ", "new idea "]
        for prefix in saveIdeaPrefixes {
            guard lower.hasPrefix(prefix) else { continue }
            let rawContent = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawContent.isEmpty else { continue }

            let (ideaContent, format, platform) = extractIdeaMetadataLines(rawContent)

            // Check for trailing "for [client]" pattern
            let (contentWithoutClient, clientName) = extractTrailingClient(ideaContent)
            let (title, body) = splitIdeaTitleBody(contentWithoutClient)

            return await createFastIdea(title: title, body: body, clientName: clientName, format: format, platform: platform)
        }

        return nil
    }

    /// Create an idea atom with optional client link and metadata. Returns the confirmation message.
    private func createFastIdea(title: String, body: String?, clientName: String?, format: ContentFormat?, platform: IdeaPlatform?) async -> String? {
        let repo = AtomRepository.shared

        // Build metadata if format or platform specified
        var metadataJSON: String? = nil
        if format != nil || platform != nil {
            var meta = IdeaMetadata()
            meta.ideaStatus = .spark
            meta.contentFormat = format
            meta.platform = platform
            metadataJSON = try? String(data: JSONEncoder().encode(meta), encoding: .utf8)
        }

        let atom: Atom
        do {
            atom = try await repo.create(type: .idea, title: title, body: body, metadata: metadataJSON)
        } catch {
            return nil
        }

        // Link to client if specified
        var clientNote = ""
        if let clientName = clientName, !clientName.isEmpty {
            if let clientAtom = try? await repo.fuzzyFindClient(query: clientName) {
                let link = AtomLink(type: AtomLinkType.ideaToClient.rawValue, uuid: clientAtom.uuid, entityType: "clientProfile")
                _ = try? await repo.update(uuid: atom.uuid) { a in
                    let updated = a.addingLink(link)
                    a.links = updated.links
                }
                clientNote = " for \(clientAtom.title ?? clientName)"
            } else {
                clientNote = " for \(clientName)"
            }
        }

        var extras: [String] = []
        if let f = format { extras.append(f.displayName) }
        if let p = platform { extras.append(p.displayName) }
        let extraNote = extras.isEmpty ? "" : " [\(extras.joined(separator: ", "))]"

        return "Saved idea\(clientNote): \"\(title)\"\(extraNote)"
    }

    /// Extract "Format: reel" / "Platform: instagram" metadata from trailing lines.
    /// Returns the content without metadata lines, plus parsed format and platform.
    private func extractIdeaMetadataLines(_ content: String) -> (content: String, format: ContentFormat?, platform: IdeaPlatform?) {
        let lines = content.components(separatedBy: "\n")
        var contentLines: [String] = []
        var format: ContentFormat?
        var platform: IdeaPlatform?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("format:") {
                let value = trimmed.dropFirst("format:".count).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                format = ContentFormat(rawValue: value)
                // Handle common aliases
                if format == nil {
                    switch value {
                    case "long form", "long-form", "longform", "blog": format = .longForm
                    case "video": format = .youtube
                    default: break
                    }
                }
            } else if lower.hasPrefix("platform:") {
                let value = trimmed.dropFirst("platform:".count).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                platform = IdeaPlatform(rawValue: value)
                if platform == nil {
                    switch value {
                    case "twitter": platform = .x
                    case "ig": platform = .instagram
                    case "yt": platform = .youtube
                    case "tt": platform = .tiktok
                    default: break
                    }
                }
            } else if !trimmed.isEmpty {
                contentLines.append(trimmed)
            }
        }

        let cleanContent = contentLines.joined(separator: "\n")
        return (cleanContent.isEmpty ? content : cleanContent, format, platform)
    }

    /// Extract trailing "for [client]" from idea content.
    /// "morning routines for michael" → ("morning routines", "michael")
    private func extractTrailingClient(_ content: String) -> (content: String, clientName: String?) {
        let lower = content.lowercased()
        guard let forRange = lower.range(of: " for ", options: .backwards) else {
            return (content, nil)
        }
        let afterFor = String(content[forRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = afterFor.split(separator: " ")
        // Only treat as client name if 1-3 words and doesn't look like a description
        guard !words.isEmpty, words.count <= 3 else { return (content, nil) }
        let descriptionWords: Set<String> = ["the", "a", "an", "my", "our", "this", "that", "next", "every"]
        if let first = words.first, descriptionWords.contains(String(first).lowercased()) {
            return (content, nil)
        }
        let contentWithout = String(content[content.startIndex..<forRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (contentWithout, afterFor)
    }

    /// Split idea content into title (first sentence/line) and body (rest).
    private func splitIdeaTitleBody(_ content: String) -> (title: String, body: String?) {
        // First try splitting on newline
        if let newlineIdx = content.firstIndex(of: "\n") {
            let title = String(content[content.startIndex..<newlineIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(content[content.index(after: newlineIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, body.isEmpty ? nil : body)
        }
        // If single line, use the whole thing as title (up to 200 chars)
        if content.count > 200 {
            let title = String(content.prefix(200))
            return (title, content)
        }
        return (content, nil)
    }

    private func resolveExplicitLessonClientName(in text: String) async -> String? {
        let lower = text.lowercased()
        guard let clients = try? await AtomRepository.shared.clientProfiles() else { return nil }

        let sortedNames = clients
            .compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for name in sortedNames {
            let nameLower = name.lowercased()
            if lower.contains("for \(nameLower)") || lower.contains("client \(nameLower)") || lower.contains("\(nameLower)'s") {
                return name
            }
        }

        return nil
    }

    private func extractSavedLessonCount(from result: String) -> Int {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return 0
        }

        if let savedCount = json["savedCount"] as? Int {
            return savedCount
        }
        if let savedCount = json["savedCount"] as? NSNumber {
            return savedCount.intValue
        }
        return 0
    }

    private func buildExplicitLessonSuccessMessage(moduleName: String?, scopeNote: String) -> String {
        var parts = ["Saved lesson\(scopeNote)."]
        if let moduleName, !moduleName.isEmpty {
            parts.append("Added to \(moduleName).")
        }
        parts.append("This will be treated as a non-negotiable in future writing.")
        return parts.joined(separator: " ")
    }

    private func persistFastPathConversation(
        text: String,
        response: String,
        conversationId: String?,
        source: MessageSource
    ) async {
        var conversation: AgentConversation
        if let conversationId,
           let existing = await ConversationMemoryService.shared.loadConversation(id: conversationId) {
            conversation = existing
        } else if let conversationId {
            conversation = AgentConversation(id: conversationId, source: source)
        } else {
            conversation = AgentConversation(source: source)
        }

        conversation.append(.user(text))
        conversation.append(.assistant(response))
        currentConversation = conversation
        await ConversationMemoryService.shared.saveConversation(conversation)
    }

    /// Classify user message intent using keyword heuristics with complexity detection.
    func classifyIntent(_ text: String) -> AgentIntentClassification {
        let lower = text.lowercased()
        let intent = classifyIntentType(lower)
        let complexity = detectComplexity(lower, intent: intent)

        return AgentIntentClassification(
            intent: intent,
            complexity: complexity,
            entities: extractEntities(lower),
            confidence: 0.85
        )
    }

    private func classifyIntentType(_ lower: String) -> AgentIntent {
        // Check for quick idea capture patterns FIRST (highest priority)
        // "Idea for Michael: 5 underrated locations..." → capture, not brainstorm
        // "Idea: build a calculator app" → capture
        // "Idea josh: co-living vs rental" → capture (no "for")
        if lower.hasPrefix("idea for ") || lower.hasPrefix("idea:") || lower.hasPrefix("task:")
            || lower.hasPrefix("save idea") || lower.hasPrefix("save this idea") || lower.hasPrefix("new idea") {
            return .capture
        }

        // "Idea [name]: ..." — idea followed by short name then colon
        if lower.hasPrefix("idea ") {
            let afterIdea = String(lower.dropFirst("idea ".count))
            if let colonIdx = afterIdea.firstIndex(of: ":") {
                let possibleName = afterIdea[afterIdea.startIndex..<colonIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                if !possibleName.isEmpty && possibleName.split(separator: " ").count <= 3 {
                    return .capture
                }
            }
        }

        // Lesson / preference / rule — must be checked BEFORE capture,
        // because "save this as a lesson" matches the capture pattern "save" + "this"/"as".
        if containsAny(lower, ["lesson", "save lesson", "remember this rule", "learn this",
                                "never have that", "never do that", "never use that",
                                "rule for future", "for future reference"]) {
            return .meta
        }

        // Draft — checked BEFORE capture because long writing messages may contain
        // incidental capture keywords (e.g. "save $40K" in deal context).
        // Writing intent takes precedence when explicit writing verbs are present.
        let draftKeywords = ["draft", "write a thread", "write a reel", "write about",
                             "write this", "write for ", "writing this", "writing a ",
                             "writing for ", "start writing", "want to write",
                             "reel for ", "thread for ", "carousel for ",
                             "create this reel", "create a reel",
                             "create this thread", "create a thread",
                             "create this carousel", "create a carousel",
                             "make it punchier", "more punchy", "shorter", "longer",
                             "condense", "expand", "rephrase", "rewrite",
                             "generate an outline", "give me an outline", "write the draft",
                             "generate hooks", "hook variants", "let's write",
                             "make this a content piece", "let's draft this", "write this up",
                             "let's make this", "i want to write",
                             "feedback on slide", "feedback on hook", "feedback on this",
                             "feedback on section", "feedback on the", "what do you think of this",
                             "what do you think about this", "thoughts on this hook",
                             "thoughts on this slide", "does this hook work",
                             "make it more ", "make this more ", "make this sound",
                             "make it sound", "too formal", "too casual", "too salesy",
                             "what structure", "what framework", "what's a good structure",
                             "what's a good hook", "what's a good opening", "what angle",
                             "hook ideas", "hook options", "opening ideas",
                             "punch up", "tighten this", "clean this up",
                             "check the flow", "does this flow", "how does this read",
                             "make the hook", "using this as the swipe", "using the swipe", "using that as",
                             "let's use the blueprint", "use the blueprint", "using the blueprint",
                             "use a hook like", "using a hook like"]
        if containsAny(lower, draftKeywords) {
            return .draft
        }

        // Check for capture patterns (after draft, so writing intent wins)
        let hasURL = lower.contains("http://") || lower.contains("https://") ||
                     lower.contains("youtu.be/") || lower.contains("youtube.com") ||
                     lower.contains("instagram.com") || lower.contains("x.com") ||
                     lower.contains("twitter.com") || lower.contains("threads.net")

        let captureKeywords = ["swipe", "capture", "save this", "save that", "grab this",
                               "snag this", "file this", "add to swipes", "swipe this",
                               "research this", "note this", "jot down"]

        // Idea-from-swipe keywords — URL + idea-related language
        let ideaSwipeKeywords = ["idea", "could do", "similar", "angle", "topic",
                                 "great for", "inspiration", "we should", "let's try",
                                 "perfect for", "good for", "try this"]

        if (lower.contains("idea") && containsAny(lower, ["save", "capture", "new idea", "jot down", "note this"])) ||
           (lower.contains("save") && containsAny(lower, ["this", "that", "as"])) ||
           (hasURL && containsAny(lower, captureKeywords)) ||
           (hasURL && containsAny(lower, ideaSwipeKeywords)) {
            return .capture
        }

        // Strategy
        if containsAny(lower, ["what should i create", "content plan", "weekly plan", "content strategy",
                                "what to post", "what's next", "content gap", "what should i write"]) {
            return .strategy
        }

        // Analyze
        if containsAny(lower, ["analyze", "analyse", "performance", "why did my", "underperform",
                                "compare to", "review this draft", "persuasion", "audience",
                                "engagement", "predict", "score this", "study this swipe"]) {
            return .analyze
        }

        // Brainstorm — broad coverage for natural exploratory language
        if containsAny(lower, ["brainstorm", "let's think", "think this through", "think through",
                                "what if", "spitball", "riff on", "explore ideas",
                                "let's explore", "riff on this", "what angles", "ideas for",
                                "content ideas", "topic ideas", "angle ideas",
                                "what are some ideas", "give me ideas", "let's brainstorm"]) {
            return .brainstorm
        }

        // Plan / Schedule
        if containsAny(lower, ["schedule", "plan my", "block time", "calendar", "time block", "what's on"]) {
            return .plan
        }

        // Correct / Modify
        if containsAny(lower, ["delete", "remove", "rename", "change the", "update the", "fix the", "correct"]) {
            return .correct
        }

        // Execute / Advance
        if containsAny(lower, ["advance", "complete", "finish", "publish", "move to next", "mark done",
                                "start session", "activate",
                                "activate this idea", "promote this idea", "turn this into content",
                                "take action", "action on this", "action this", "act on this", "act on the"]) {
            return .execute
        }

        // Debrief
        if containsAny(lower, ["review", "debrief", "how did", "recap", "summary of today", "end of day"]) {
            return .debrief
        }

        // Reflect
        if containsAny(lower, ["reflect", "journal", "feeling", "mood", "i feel", "grateful"]) {
            return .reflect
        }

        // Meta / Settings / Standing Instructions / Lessons
        if containsAny(lower, ["setting", "prefer", "remember that", "help", "configure", "how do i",
                                "don't use", "stop using", "can you not", "don't do", "stop doing",
                                "please don't", "instead of", "from now on", "always use",
                                "never use", "going forward",
                                "every day", "every morning", "every weekday", "every week",
                                "standing instruction", "recurring", "remind me daily",
                                "schedule a daily", "schedule a recurring",
                                "lesson", "lessons", "save lesson", "save lessons",
                                "learn this", "remember this rule", "what have you learned",
                                "what lessons", "what rules"]) {
            return .meta
        }

        return .query
    }

    /// Detect if a request is compound (needs multi-step workflow) or simple
    private func detectComplexity(_ lower: String, intent: AgentIntent) -> RequestComplexity {
        // Multi-step patterns
        let compoundPatterns = [
            "draft a thread", "write a thread about", "create content about",
            "build a post", "full pipeline", "voice to content",
            "activate my idea about", "activate idea",
            "plan my week", "weekly content plan",
            "draft.*using.*swipes", "research.*then.*draft",
            "find.*swipes.*and.*write"
        ]

        for pattern in compoundPatterns {
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return .compound
            }
        }

        // Conjunction patterns suggesting multiple steps
        if containsAny(lower, [" then ", " and then ", " after that ", " followed by ", " next "]) &&
           lower.count > 50 {
            return .compound
        }

        return .simple
    }

    /// Extract simple entities from the message
    private func extractEntities(_ lower: String) -> [String: String] {
        var entities: [String: String] = [:]

        // Extract URLs
        if let urlRange = lower.range(of: #"https?://\S+"#, options: .regularExpression) {
            entities["url"] = String(lower[urlRange])
        }

        // Extract platform mentions
        let platforms = ["twitter", "instagram", "youtube", "linkedin", "tiktok", "newsletter", "threads"]
        for platform in platforms where lower.contains(platform) {
            entities["platform"] = platform
            break
        }

        return entities
    }

    // MARK: - Conversation-Aware Intent Escalation

    /// Escalate intent based on conversation history. When a conversation has been
    /// about creative work (draft/brainstorm) and the current message is generic (query),
    /// maintain the creative intent to keep the right model tier and context active.
    /// This prevents mid-conversation regression from Opus to Haiku when the user gives
    /// creative direction without explicit draft keywords.
    private func escalateIntentFromConversation(_ intent: AgentIntent, conversation: AgentConversation) -> AgentIntent {
        // Only escalate from generic .query intent
        guard intent == .query else { return intent }
        guard !conversation.messages.isEmpty else { return intent }

        // Check recent user messages for creative/drafting signals
        let recentUserMessages = conversation.messages
            .filter { $0.role == .user }
            .suffix(5)

        let creativeSignals = ["write", "writing", "draft", "reel", "thread", "carousel",
                               "hook", "outline", "slide", "content piece", "angle",
                               "brainstorm", "let's make", "punchier", "rewrite",
                               "make it", "too formal", "too long", "too short"]

        let hasCreativeHistory = recentUserMessages.contains { msg in
            let lower = msg.content.lowercased()
            return creativeSignals.contains { lower.contains($0) }
        }

        if hasCreativeHistory {
            return .draft
        }

        // Check recent tool usage for creative tools
        let recentAssistantMessages = conversation.messages
            .filter { $0.role == .assistant }
            .suffix(5)

        let creativeTools: Set<String> = ["get_client_profile", "generate_outline",
                                           "generate_draft", "generate_hooks", "create_content",
                                           "get_beat_patterns", "revise_draft", "search_swipes",
                                           "find_similar_swipes", "filter_swipes_by_taxonomy"]

        let hasCreativeToolHistory = recentAssistantMessages.contains { msg in
            msg.toolCalls?.contains { creativeTools.contains($0.name) } == true
        }

        if hasCreativeToolHistory {
            return .draft
        }

        return intent
    }

    // MARK: - Confirm Action (Hard Tier)

    func confirmAction(confirmationId: String) async -> String {
        guard let pending = toolExecutor.pendingConfirmations[confirmationId] else {
            return "Confirmation expired or not found."
        }
        toolExecutor.pendingConfirmations.removeValue(forKey: confirmationId)

        do {
            let result = try await toolExecutor.execute(
                toolName: pending.toolName,
                arguments: pending.arguments
            )
            return "Done! \(pending.description)\n\(result)"
        } catch {
            return "Failed to execute: \(error.localizedDescription)"
        }
    }

    func rejectAction(confirmationId: String) {
        toolExecutor.pendingConfirmations.removeValue(forKey: confirmationId)
    }

    func cleanExpiredConfirmations() {
        let cutoff = Date().addingTimeInterval(-300)
        toolExecutor.pendingConfirmations = toolExecutor.pendingConfirmations.filter {
            $0.value.createdAt > cutoff
        }
    }

    // MARK: - Conversation Management

    func newConversation(source: MessageSource = .inApp) {
        currentConversation = AgentConversation(source: source)
        activeItemsContext.removeAll()
    }

    func loadConversation(id: String) async {
        currentConversation = await ConversationMemoryService.shared.loadConversation(id: id)
    }

    // MARK: - Session Boundary Detection (WP8)

    /// Detect when a Telegram conversation should start a fresh session.
    /// Triggers when the user starts a new content piece in an existing long conversation.
    private func detectSessionBoundary(text: String, intent: AgentIntent, conversation: AgentConversation) -> Bool {
        // Only rotate for draft intent with "new" signals and long conversations
        guard conversation.messages.count > 10 else { return false }

        let lower = text.lowercased()

        // Explicit reset command
        if lower.hasPrefix("/new") { return true }

        // New content signals with draft intent
        if intent == .draft {
            let newContentSignals = ["new post", "new thread", "new draft", "new reel",
                                     "let's start", "next piece", "fresh draft",
                                     "new carousel", "new content"]
            return newContentSignals.contains { lower.contains($0) }
        }

        return false
    }

    /// Compress the current conversation into a summary and start fresh.
    private func rotateConversationSession(_ conversation: inout AgentConversation) async {
        // Generate a compact summary of the current conversation using Haiku
        let messageText = conversation.messages.suffix(20).map { msg in
            "\(msg.role == .user ? "User" : "Agent"): \(String(msg.content.prefix(150)))"
        }.joined(separator: "\n")

        var summary = conversation.summary ?? ""

        if !messageText.isEmpty {
            // Preserve creative decisions, client context, and content atoms — not just topics.
            let prompt = """
                Summarize this creative writing conversation for a ghostwriter AI. Be concise but preserve:
                - Client name and platform (if mentioned)
                - What content atoms/drafts were created (titles, UUIDs if present)
                - Key creative decisions made (formats chosen, hooks agreed on, frameworks used)
                - Feedback given and acted on (e.g., "hook was too salesy, shortened to 1 line")
                - What was NOT working (so it's not repeated next session)

                Conversation:
                \(messageText)

                Output: 3-5 sentences maximum. No headers. Plain text only.
                """
            do {
                let messages = [
                    AgentMessage(role: .system, content: "You are a creative writing assistant summarizer. Preserve writing decisions, rejected approaches, and client voice details. Respond with only the summary."),
                    AgentMessage.user(prompt)
                ]
                if let newSummary = try await summarize(messages: messages, tier: .sensor) {
                    summary = (summary.isEmpty ? "" : summary + " | ") + newSummary
                }
            } catch {
                // Fallback: extractive summary
                let userMsgs = conversation.messages.filter { $0.role == .user }
                let topics = userMsgs.suffix(3).map { String($0.content.prefix(60)) }.joined(separator: "; ")
                summary = (summary.isEmpty ? "" : summary + " | ") + "Previous: \(topics)"
            }
        }

        // Store summary and clear messages + linked atoms for fresh session
        conversation.summary = summary
        conversation.messages = []
        conversation.linkedAtomUUIDs = []

        print("[CosmoAgent] Session rotated. Summary: \(summary.prefix(100))...")
    }

    // MARK: - Clear Conversation (Public)

    /// Clears the conversation context for a given chat. Rotates the session
    /// (summarizes + clears messages) so old context is preserved as a summary
    /// but won't be sent to the LLM for future messages.
    func clearConversation(chatId: String, source: MessageSource) async {
        guard var conversation = await ConversationMemoryService.shared.loadConversation(id: chatId) else { return }
        await rotateConversationSession(&conversation)
        await ConversationMemoryService.shared.saveConversation(conversation)
    }

    // MARK: - Context Trace Helpers

    /// Converts tool arguments dictionary to flat string-keyed display values
    private func flattenArguments(_ args: [String: Any]) -> [String: String] {
        var flat: [String: String] = [:]
        for (key, value) in args {
            if let str = value as? String {
                flat[key] = str
            } else if let num = value as? NSNumber {
                flat[key] = num.stringValue
            } else if let arr = value as? [String] {
                flat[key] = arr.joined(separator: ", ")
            } else {
                flat[key] = "\(value)"
            }
        }
        return flat
    }

    /// Extracts a human-readable summary from a tool result (capped at 200 chars)
    private func extractResultSummary(_ result: String, toolName: String) -> String? {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
        }

        // Client profile
        if toolName == "get_client_profile",
           let name = json["name"] as? String ?? json["clientName"] as? String {
            return name
        }

        // Writing engine tools — surface the swipes they used internally
        if toolName.hasPrefix("generate_") || toolName == "revise_draft" {
            if let swipeTitles = json["swipesUsed"] as? [String], !swipeTitles.isEmpty {
                let count = json["swipeCount"] as? Int ?? swipeTitles.count
                let swipeInfo = swipeTitles.prefix(4).joined(separator: ", ")
                let label = json["message"] as? String ?? toolName
                return "\(String(label.prefix(60))) | Swipes(\(count)): \(swipeInfo)"
            }
            if let message = json["message"] as? String {
                return String(message.prefix(200))
            }
        }

        // Search results with titles
        if let results = json["results"] as? [[String: Any]] {
            let titles = results.prefix(4).compactMap { $0["title"] as? String }.filter { !$0.isEmpty }
            if titles.isEmpty { return "0 results" }
            return titles.joined(separator: ", ")
        }

        // Scorecard
        if let score = json["overallScore"] as? Double {
            return "Score: \(String(format: "%.1f", score))/10"
        }

        // Title-bearing results (e.g. get_swipe_analysis returns atom with title)
        if let title = json["title"] as? String, !title.isEmpty {
            return title
        }

        // Count-based results
        if let count = json["count"] as? Int {
            return "\(count) results"
        }

        // Success message
        if let message = json["message"] as? String {
            return String(message.prefix(200))
        }

        return nil
    }

    /// Returns a human-readable display label for a tool call, used by live activity UI.
    /// Includes atom names/titles from args where available for specific context.
    private func toolDisplayLabel(for toolName: String, args: [String: String]) -> String {
        let client = args["clientName"] ?? args["client_name"] ?? args["name"] ?? ""
        let clientSuffix = client.isEmpty ? "" : " for \(client)"
        let title = args["title"] ?? ""

        switch toolName {
        case "search_swipes": return "Searching swipes for \"\(args["query"] ?? "")\""
        case "search_ideas": return "Searching ideas for \"\(args["query"] ?? "")\""
        case "get_idea": return "Reading idea"
        case "get_swipe_analysis": return "Analyzing swipe"
        case "get_client_profile": return client.isEmpty ? "Loading client profile" : "Loading profile: \(client)"
        case "get_content": return "Reading content"
        case "get_content_pipeline": return "Checking content pipeline\(clientSuffix)"
        case "generate_outline": return "Generating outline\(clientSuffix)"
        case "generate_draft": return "Writing draft\(clientSuffix)"
        case "generate_hooks": return "Generating hook variants\(clientSuffix)"
        case "revise_draft": return "Revising draft\(clientSuffix)"
        case "score_draft": return "Scoring draft"
        case "get_beat_patterns": return "Analyzing beat patterns"
        case "capture_swipe": return "Capturing swipe"
        case "create_content": return title.isEmpty ? "Creating content\(clientSuffix)" : "Creating: \(title)"
        case "create_idea": return title.isEmpty ? "Creating idea" : "Creating idea: \(title)"
        case "web_search": return "Searching the web for \"\(args["query"] ?? "")\""
        case "list_all_swipes": return "Loading swipe library"
        case "filter_swipes_by_taxonomy": return "Filtering swipes"
        case "find_similar_swipes": return "Finding similar swipes"
        case "get_calendar_blocks": return "Checking calendar"
        case "save_lessons": return "Saving lessons"
        case "get_lessons": return "Loading lessons"
        default:
            return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Checks whether a tool result represents an empty/no-data response
    private func isEmptyResult(_ result: String) -> Bool {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if let count = json["count"] as? Int, count == 0 { return true }
        if let results = json["results"] as? [Any], results.isEmpty { return true }
        return false
    }

    // MARK: - Helpers

    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    // MARK: - Token-Aware History Window (WP3)

    /// Build a token-aware history window. If estimated tokens exceed 10K,
    /// progressively reduce window size while keeping at least 6 messages.
    private func buildTokenAwareWindow(_ messages: [AgentMessage]) -> [AgentMessage] {
        // Start with up to 12 messages
        var window = Array(messages.suffix(12))
        let estimatedTokens = window.reduce(0) { $0 + ($1.content.count / 4) }

        if estimatedTokens > 10_000 {
            // First reduction: 8 messages
            window = Array(messages.suffix(8))
            let tokens8 = window.reduce(0) { $0 + ($1.content.count / 4) }

            if tokens8 > 10_000 {
                // Second reduction: 6 messages
                window = Array(messages.suffix(6))
                let tokens6 = window.reduce(0) { $0 + ($1.content.count / 4) }

                if tokens6 > 10_000 {
                    // Final reduction: minimum 4 messages
                    window = Array(messages.suffix(4))
                }
            }
        }

        return window
    }

    /// Lightweight window for simple intents (capture, correct, meta).
    /// Only includes the last 4 messages and aggressively truncates tool results
    /// to prevent writing-heavy context from confusing Haiku on simple operations.
    private func buildLightweightWindow(_ messages: [AgentMessage]) -> [AgentMessage] {
        // Take only the last 4 messages — just enough for immediate context
        let window = Array(messages.suffix(4))

        // Truncate any tool results to compact summaries
        return window.map { msg in
            if msg.role == .tool && msg.content.count > 300 {
                return AgentMessage(
                    role: .tool,
                    content: compactToolResultSummary(msg.content),
                    toolCallId: msg.toolCallId
                )
            }
            return msg
        }
    }

    // MARK: - Tool Result Compression (WP2)

    /// Compress old tool results in conversation history to reduce token usage.
    /// Keeps the 2 most recent tool result pairs intact, compresses older ones
    /// to compact summaries (title/type/count extraction from JSON).
    private func compressOldToolResults(_ conversation: inout AgentConversation) {
        let messages = conversation.messages

        // Find indices of all tool result messages
        var toolResultIndices: [Int] = []
        for (index, msg) in messages.enumerated() {
            if msg.role == .tool {
                toolResultIndices.append(index)
            }
        }

        // Keep the last 2 tool results (approximately 1 tool call exchange) intact
        guard toolResultIndices.count > 2 else { return }
        let indicesToCompress = Set(toolResultIndices.dropLast(2))

        var newMessages: [AgentMessage] = []
        for (index, msg) in messages.enumerated() {
            if indicesToCompress.contains(index) && msg.content.count > 200 {
                // Compress this tool result to a compact summary
                let summary = compactToolResultSummary(msg.content)
                let compressed = AgentMessage(
                    role: .tool,
                    content: summary,
                    toolCallId: msg.toolCallId
                )
                newMessages.append(compressed)
            } else {
                newMessages.append(msg)
            }
        }

        conversation.messages = newMessages
    }

    /// Extract key fields from a tool result JSON to create a compact summary.
    private func compactToolResultSummary(_ content: String) -> String {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Not JSON — just truncate
            return "[Previously retrieved: \(String(content.prefix(80)))...]"
        }

        var parts: [String] = []

        // Extract common fields
        if let title = json["title"] as? String { parts.append("title: \(title)") }
        if let uuid = json["uuid"] as? String { parts.append("uuid: \(uuid.prefix(8))...") }
        if let success = json["success"] as? Bool { parts.append("success: \(success)") }
        if let count = json["count"] as? Int { parts.append("count: \(count)") }
        if let type = json["type"] as? String { parts.append("type: \(type)") }

        // Handle arrays (search results)
        if let results = json["results"] as? [[String: Any]] {
            let titles = results.prefix(3).compactMap { $0["title"] as? String }
            parts.append("results(\(results.count)): \(titles.joined(separator: ", "))")
        }

        if let error = json["error"] as? String { parts.append("error: \(error)") }

        // Preserve writing feedback fields critical for self-correction
        if let weakAreas = json["weakAreas"] as? [String], !weakAreas.isEmpty {
            parts.append("needs_improvement: \(weakAreas.joined(separator: "; "))")
        }
        if let issues = json["complianceIssues"] as? [String], !issues.isEmpty {
            parts.append("violations: \(issues.joined(separator: "; "))")
        }
        // Scorecard results — preserve scores so multi-turn refinement can track improvements
        if let hookScore = json["hookScore"] as? Double {
            parts.append("hookScore: \(String(format: "%.1f", hookScore))")
        }
        if let copyScore = json["copyScore"] as? Double {
            parts.append("copyScore: \(String(format: "%.1f", copyScore))")
        }
        if let ctaScore = json["ctaScore"] as? Double {
            parts.append("ctaScore: \(String(format: "%.1f", ctaScore))")
        }
        if let voiceMatch = json["voiceMatch"] as? Double {
            parts.append("voiceMatch: \(String(format: "%.0f", voiceMatch))%")
        }
        if let overallConfidence = json["overallConfidence"] as? Int {
            parts.append("confidence: \(overallConfidence)%")
        }
        // Engine notes from writing tools — preserve strategic reasoning
        if let engineNotes = json["engineNotes"] as? String, !engineNotes.isEmpty {
            parts.append("notes: \(String(engineNotes.prefix(200)))")
        }
        // Content format for draft tools
        if let format = json["format"] as? String {
            parts.append("format: \(format)")
        }
        if let message = json["message"] as? String {
            parts.append("message: \(String(message.prefix(120)))")
        }
        if let wordCount = json["wordCount"] as? Int {
            parts.append("words: \(wordCount)")
        }

        if parts.isEmpty {
            return "[Previously retrieved data. Full data available via tools.]"
        }
        return "[Previously retrieved: \(parts.joined(separator: "; ")). Full data available via tools.]"
    }

    /// Remove orphaned tool_result messages whose corresponding tool_use assistant
    /// message was truncated by the history window. The Anthropic API requires every
    /// tool_result to have a matching tool_use in the preceding assistant message.
    private func sanitizeToolPairs(_ messages: [AgentMessage]) -> [AgentMessage] {
        // Collect all tool call IDs defined by assistant messages in this window
        var availableToolCallIds = Set<String>()
        for msg in messages {
            if msg.role == .assistant, let calls = msg.toolCalls {
                for call in calls {
                    availableToolCallIds.insert(call.id)
                }
            }
        }

        // Filter out tool messages that reference a tool_use not in this window
        return messages.filter { msg in
            if msg.role == .tool, let callId = msg.toolCallId {
                return availableToolCallIds.contains(callId)
            }
            return true
        }
    }
}
