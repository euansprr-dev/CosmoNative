// CosmoOS/Agent/Core/CosmoAgentService.swift
// Main orchestrator for the Cosmo Agent system

import Foundation
import Combine

@MainActor
class CosmoAgentService: ObservableObject {
    static let shared = CosmoAgentService()

    // MARK: - Published State

    @Published var isProcessing = false
    @Published var currentConversation: AgentConversation?
    @Published var activeProvider: AgentProvider = .anthropic
    @Published var selectedModel: String = AgentProvider.anthropic.defaultModel
    @Published var lastError: String?

    // MARK: - Dependencies

    private var llmProvider: LLMProvider?
    private let toolRegistry = AgentToolRegistry.shared
    private let toolExecutor = AgentToolExecutor.shared
    private let contextAssembler = AgentContextAssembler.shared

    /// Maximum tool call iterations per message to prevent infinite loops
    private let maxToolIterations = 5

    // MARK: - Init

    private init() {
        // Load saved provider preference from UserDefaults
        if let saved = UserDefaults.standard.string(forKey: "agent_provider"),
           let provider = AgentProvider(rawValue: saved) {
            activeProvider = provider
        }
        if let model = UserDefaults.standard.string(forKey: "agent_model") {
            selectedModel = model
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

    private func refreshProvider() {
        let apiKey: String?
        if activeProvider == .openRouter {
            apiKey = APIKeys.openRouter
        } else {
            apiKey = APIKeys.agentLLM
        }
        llmProvider = LLMProviderFactory.create(
            provider: activeProvider,
            apiKey: apiKey,
            baseURL: APIKeys.agentLLMBaseURL
        )
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

    // MARK: - Process Message (Main Entry Point)

    /// Process a user message through the full agent pipeline:
    /// classify intent -> load context -> tool loop -> return response
    func processMessage(
        _ text: String,
        conversationId: String? = nil,
        source: MessageSource = .inApp
    ) async -> String {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        guard let provider = llmProvider else {
            let msg = "Cosmo Agent is not configured. Please set up an AI provider in Settings."
            lastError = msg
            return msg
        }

        // 1. Classify intent
        let intent = classifyIntent(text)

        // 2. Load or create conversation
        var conversation: AgentConversation
        if let convId = conversationId,
           let existing = await ConversationMemoryService.shared.loadConversation(id: convId) {
            conversation = existing
        } else {
            conversation = AgentConversation(source: source)
        }

        // 3. Add user message
        conversation.append(.user(text))

        // 4. Get preferences
        let preferences = await PreferenceLearningEngine.shared.getAllPreferences(scope: nil)

        // 5. Get tools for intent
        let tools = toolRegistry.toolsForIntent(intent)

        // 6. Assemble system prompt
        let systemPrompt = await contextAssembler.assembleSystemPrompt(
            conversation: conversation,
            preferences: preferences,
            tools: tools
        )

        // 7. Build message array for LLM
        var llmMessages: [AgentMessage] = [.system(systemPrompt)]

        // Add conversation history (last 20 messages to stay within context)
        let historyWindow = Array(conversation.messages.suffix(20))
        llmMessages.append(contentsOf: historyWindow)

        // 8. Tool loop — iterate until the LLM returns a text-only response
        var iterations = 0
        var finalResponse = ""

        while iterations < maxToolIterations {
            iterations += 1

            do {
                let response = try await provider.complete(
                    messages: llmMessages,
                    tools: tools.isEmpty ? nil : tools,
                    model: selectedModel
                )

                if response.toolCalls.isEmpty {
                    // No tool calls — this is the final text response
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

        // 9. Save assistant response to conversation
        conversation.append(.assistant(finalResponse))
        currentConversation = conversation

        // 10. Persist conversation to memory
        await ConversationMemoryService.shared.saveConversation(conversation)

        return finalResponse
    }

    // MARK: - Intent Classification

    /// Classify user message intent using keyword heuristics.
    /// This is fast and runs locally. The LLM refines via tool selection.
    func classifyIntent(_ text: String) -> AgentIntent {
        let lower = text.lowercased()

        // Check for capture patterns first (most specific)
        if lower.hasPrefix("idea:") || lower.hasPrefix("task:") ||
           (lower.contains("idea") && containsAny(lower, ["save", "capture", "new idea", "jot down", "note this"])) ||
           (lower.contains("save") && containsAny(lower, ["this", "that", "as"])) {
            return .capture
        }

        // Brainstorm
        if containsAny(lower, ["brainstorm", "let's think", "what if", "spitball", "riff on", "explore ideas"]) {
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
        if containsAny(lower, ["advance", "complete", "finish", "publish", "move to next", "mark done", "start session"]) {
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

        // Meta / Settings
        if containsAny(lower, ["setting", "prefer", "remember that", "help", "configure", "how do i"]) {
            return .meta
        }

        // Default to query — asking about data
        return .query
    }

    // MARK: - Confirm Action (Hard Tier)

    /// Execute a previously pending confirmation
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

    /// Reject a pending confirmation
    func rejectAction(confirmationId: String) {
        toolExecutor.pendingConfirmations.removeValue(forKey: confirmationId)
    }

    /// Clean up expired confirmations (older than 5 minutes)
    func cleanExpiredConfirmations() {
        let cutoff = Date().addingTimeInterval(-300)
        toolExecutor.pendingConfirmations = toolExecutor.pendingConfirmations.filter {
            $0.value.createdAt > cutoff
        }
    }

    // MARK: - Conversation Management

    /// Start a new conversation, discarding the current one
    func newConversation(source: MessageSource = .inApp) {
        currentConversation = AgentConversation(source: source)
    }

    /// Load an existing conversation by ID
    func loadConversation(id: String) async {
        currentConversation = await ConversationMemoryService.shared.loadConversation(id: id)
    }

    // MARK: - Helpers

    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
