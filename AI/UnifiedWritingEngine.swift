// CosmoOS/AI/UnifiedWritingEngine.swift
// Unified Writing Engine — ONE continuous Claude conversation per content piece
// Replaces 4 disconnected engines (BrainstormAI, OpusWriting, ContentAICollaborator, AIWritingAssistant)
// with a single agentic conversation from brainstorm → outline → draft → polish
// February 2026

import Foundation
import SwiftUI
import GRDB

// MARK: - Notification

extension Notification.Name {
    static let cosmoWritingEngineContextLoaded = Notification.Name("cosmoWritingEngineContextLoaded")
}

// MARK: - Loaded Context Info

struct LoadedContextInfo {
    var clientName: String?
    var swipeCount: Int = 0
    var swipeTitles: [String] = []
    var beatPattern: String?
    var failureRuleCount: Int = 0
    var estimatedTokens: Int = 0

    static let empty = LoadedContextInfo()
}

// MARK: - Nonisolated API Call

/// Perform an OpenRouter tool-use API call entirely off the main actor.
/// This free function runs on the cooperative thread pool, so its continuations
/// (after network I/O) resume without needing the main thread.
/// This is the KEY fix for the freeze: the conversation loop calls this instead
/// of ResearchService.shared.generateWithTools(), avoiding main actor starvation.
private func performWritingAPICall(
    apiKey: String,
    systemBlocks: [PromptCacheBlock],
    messages: [[String: Any]],
    tools: [[String: Any]],
    model: String,
    maxTokens: Int = 16384,
    temperature: Double = 0.3
) async throws -> ClaudeToolUseResponse {
    let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
    request.setValue("CosmoOS", forHTTPHeaderField: "X-Title")

    // Build system message with cache control blocks
    let systemContentBlocks = systemBlocks.map { block -> [String: Any] in
        var contentBlock: [String: Any] = ["type": "text", "text": block.content]
        if block.cacheControl {
            var cacheControl: [String: Any] = ["type": "ephemeral"]
            if let ttl = block.ttl, !ttl.isEmpty {
                cacheControl["ttl"] = ttl
            }
            contentBlock["cache_control"] = cacheControl
        }
        return contentBlock
    }

    let systemMessage: [String: Any] = ["role": "system", "content": systemContentBlocks]
    var allMessages: [[String: Any]] = [systemMessage]
    allMessages.append(contentsOf: messages)

    // Mark last tool with cache_control so providers cache static tool definitions
    var cachedTools = tools
    let cacheableBlockCount = systemBlocks.reduce(into: 0) { count, block in
        if block.cacheControl {
            count += 1
        }
    }
    if !cachedTools.isEmpty, cacheableBlockCount < 4 {
        var lastTool = cachedTools[cachedTools.count - 1]
        lastTool["cache_control"] = ["type": "ephemeral", "ttl": "1h"]
        cachedTools[cachedTools.count - 1] = lastTool
    }

    let body: [String: Any] = [
        "model": model,
        "messages": allMessages,
        "tools": cachedTools,
        "temperature": temperature,
        "max_tokens": maxTokens
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    print("🌐 [WritingAPICall] Request body: \(request.httpBody?.count ?? 0) bytes, model: \(model)")

    // Retry loop for transient failures (429 rate limit, 5xx server errors)
    var responseData: Data!
    var lastHTTPError: Error?
    for attempt in 0..<3 {
        if attempt > 0 {
            let backoff = Double(attempt) * 2.0
            print("⏳ [WritingAPICall] Retry \(attempt)/2 after \(Int(backoff))s backoff")
            try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        }
        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        let httpStatus = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        print("🌐 [WritingAPICall] HTTP \(httpStatus)")

        if httpStatus == 429 || (httpStatus >= 500 && httpStatus < 600) {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            print("⚠️ [WritingAPICall] Retryable error \(httpStatus): \(errorText.prefix(200))")
            lastHTTPError = ResearchError.apiError(statusCode: httpStatus, message: errorText)
            continue
        }
        if httpStatus != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ [WritingAPICall] Error: \(errorText.prefix(500))")
            throw ResearchError.apiError(statusCode: httpStatus, message: errorText)
        }
        responseData = data
        lastHTTPError = nil
        break
    }
    if let error = lastHTTPError { throw error }

    // Parse response
    let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
    let choices = json?["choices"] as? [[String: Any]]
    let firstChoice = choices?.first
    let message = firstChoice?["message"] as? [String: Any]
    let finishReason = firstChoice?["finish_reason"] as? String
    let nativeFinishReason = firstChoice?["native_finish_reason"] as? String
        ?? message?["stop_reason"] as? String
        ?? message?["finish_reason"] as? String
    let responseId = json?["id"] as? String
    let completionTokens = (json?["usage"] as? [String: Any])?["completion_tokens"] as? Int

    if let usage = json?["usage"] as? [String: Any] {
        let promptTokens = usage["prompt_tokens"] as? Int ?? 0
        let completionTokens = usage["completion_tokens"] as? Int ?? 0
        let details = usage["prompt_tokens_details"] as? [String: Any]
        let cachedTokens = details?["cached_tokens"] as? Int ?? 0
        let uncachedPromptTokens = max(promptTokens - cachedTokens, 0)
        let cacheHitRate = promptTokens > 0 ? (Double(cachedTokens) / Double(promptTokens)) * 100 : 0
        print(
            "🌐 [WritingAPICall] Usage: prompt=\(promptTokens), uncached=\(uncachedPromptTokens), cached=\(cachedTokens), completion=\(completionTokens), cache_hit_rate=\(String(format: "%.1f", cacheHitRate))%"
        )
        // Claude Opus pricing, June 2026: $5/M in, $25/M out, cache read ~0.1x.
        // Keep in sync with CraftUsage in AI/Craft/CosmoCraftEngine.swift.
        let inputCost = Double(uncachedPromptTokens) * 5.0 / 1_000_000
            + Double(cachedTokens) * 0.5 / 1_000_000
        let outputCost = Double(completionTokens) * 25.0 / 1_000_000
        print("💰 [WritingAPICall] Est. cost: $\(String(format: "%.4f", inputCost + outputCost)) (input: $\(String(format: "%.4f", inputCost)), output: $\(String(format: "%.4f", outputCost)))")
    }

    var textContent = ""
    var toolCalls: [ClaudeToolUseResponse.ClaudeToolCall] = []

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

    // OpenAI-format tool calls (from OpenRouter)
    if let openAIToolCalls = message?["tool_calls"] as? [[String: Any]] {
        for tc in openAIToolCalls {
            let tcId = tc["id"] as? String ?? UUID().uuidString
            if let function = tc["function"] as? [String: Any] {
                let name = function["name"] as? String ?? ""
                let argsStr = function["arguments"] as? String ?? "{}"
                let input = (try? JSONSerialization.jsonObject(with: Data(argsStr.utf8))) as? [String: Any] ?? [:]
                toolCalls.append(ClaudeToolUseResponse.ClaudeToolCall(id: tcId, name: name, input: input))
            }
        }
    }

    print(
        "🌐 [WritingAPICall] Parsed: text=\(textContent.count) chars, tools=\(toolCalls.count), id=\(responseId ?? "nil"), finish=\(finishReason ?? "nil"), native_finish=\(nativeFinishReason ?? "nil"), completion=\(completionTokens.map { String($0) } ?? "nil")"
    )
    return ClaudeToolUseResponse(
        textContent: textContent,
        toolCalls: toolCalls,
        stopReason: finishReason,
        responseId: responseId,
        nativeFinishReason: nativeFinishReason,
        completionTokens: completionTokens
    )
}

// MARK: - Unified Writing Engine

@MainActor
final class UnifiedWritingEngine: ObservableObject {

    // MARK: - Published State

    @Published var messages: [WritingMessage] = []
    @Published var isProcessing = false
    @Published var error: String?
    @Published var toolChainSteps: [WritingToolChainStep] = []
    @Published var loadedContext: LoadedContextInfo = .empty

    /// Optional callback emitting context-loading progress events (client profile, swipes, preferences, etc.)
    var onContextActivity: ((ToolActivityEvent) -> Void)?

    // MARK: - Context Cache

    private var cachedBlock1: String?
    private var cachedBlock2: String?
    private var cachedBlock3A: String?
    private var cachedContextVersion: UUID?
    private var contentAtom: Atom?
    private var clientProfileAtom: Atom?
    private var clientMeta: ClientProfileMetadata?
    private var selectedSwipes: [CompressedSwipe] = []
    private(set) var conversationSummary: String = ""
    private var isCancelled = false
    private var refinementIterations = 0

    /// On-demand reference material cache — bodies loaded via tools persist in Block 3.
    private var cachedReferenceMaterial: [String: String] = [:]
    private var referenceMaterialCharCount: Int { cachedReferenceMaterial.values.reduce(0) { $0 + $1.count } }
    private let referenceMaterialMaxChars = 25_000

    /// Client post metadata index — populated during init, no body text.
    private var clientPostIndex: [(id: UUID, title: String, category: String, engagement: String, charCount: Int, format: String)] = []

    private let database = CosmoDatabase.shared

    /// Notification observer for lesson changes — invalidates cachedBlock2
    private var lessonChangeObserver: NSObjectProtocol?

    // MARK: - Constants

    private let writerModel = ContentModelTier.writer.rawValue
    private let brainstormModel = ContentModelTier.writer.rawValue  // Opus for ALL phases — outline quality matters
    private let maxRetries = 2
    private let promptCacheTTL = "1h"
    private let tokenSummarizationThreshold = 100_000  // Opus 4.6 has 1M context — don't summarize mid-session

    /// Optional model override for Telegram A/B testing (Opus vs GPT 5.4).
    /// When set, replaces writerModel/brainstormModel.
    var writerModelOverride: String?

    // MARK: - Phase-Aware Model Selection

    /// Returns the appropriate model for each writing phase.
    /// All phases use Opus — outline quality is the foundation, and skill modules
    /// (Dinner Table Test, Hook Craft, Causal Chaining) need Opus-level reasoning.
    private func modelForPhase(_ phase: ContentStep) -> String {
        switch phase {
        case .brainstorm:
            return writerModelOverride ?? brainstormModel
        case .draft, .polish:
            return writerModelOverride ?? writerModel
        }
    }

    // MARK: - Lifecycle

    /// Initialize the engine with a content atom. Loads all context, caches prompt blocks,
    /// and restores any persisted conversation history.
    func initialize(contentAtom: Atom, existingMessages: [WritingMessage] = [], existingSummary: String = "") async {
        print("🔧 [UnifiedWritingEngine] Initializing with atom: \(contentAtom.uuid) title: \(contentAtom.body?.prefix(60) ?? "nil")")
        self.contentAtom = contentAtom
        self.cachedBlock1 = nil
        self.cachedBlock2 = nil
        self.cachedContextVersion = nil
        self.selectedSwipes = []
        self.refinementIterations = 0
        self.cachedReferenceMaterial = [:]
        self.clientPostIndex = []

        // Observe lesson changes to invalidate Block 2 cache (new/confirmed/corrected lessons)
        if lessonChangeObserver == nil {
            lessonChangeObserver = NotificationCenter.default.addObserver(
                forName: .cosmoTasteChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.cachedBlock2 = nil
                print("🔧 [UnifiedWritingEngine] Block 2 cache invalidated (lesson changed)")
            }
        }

        // Restore persisted conversation — prefer in-memory messages, fall back to atom persistence
        if !existingMessages.isEmpty {
            self.messages = existingMessages
            self.conversationSummary = existingSummary
            print("🔧 [UnifiedWritingEngine] Restored \(existingMessages.count) messages from in-memory persistence (summary: \(existingSummary.count) chars)")
        } else {
            // B1: Restore from atom.structured["writingConversation"] if available
            let restored = self.restorePersistedConversation(from: contentAtom)
            if !restored.isEmpty {
                self.messages = restored
                print("🔧 [UnifiedWritingEngine] Restored \(restored.count) messages from atom.structured persistence")
            }
        }

        // D1: Emit context activity events as each piece loads
        onContextActivity?(.started(name: "load_client_profile", displayLabel: "Loading client profile", args: [:]))
        await loadClientProfile(contentAtom: contentAtom)
        let clientName = clientMeta?.clientName ?? "none"
        let clientLabel = clientName == "none" ? "No profile linked" : clientName
        onContextActivity?(.completed(name: "load_client_profile", displayLabel: "Loaded profile: \(clientLabel)", resultPreview: clientLabel))
        print("🔧 [UnifiedWritingEngine] Client profile: \(clientMeta?.clientName ?? "NONE") (profileAtom: \(clientProfileAtom?.uuid ?? "nil"))")

        onContextActivity?(.started(name: "select_swipes", displayLabel: "Selecting swipe examples", args: [:]))
        await selectSwipes(contentAtom: contentAtom)
        // Emit individual swipe events
        for swipe in selectedSwipes {
            let label = swipe.isClientExample ? "Client post: \(swipe.title)" : "Swipe: \(swipe.title)"
            onContextActivity?(.completed(name: "load_swipe", displayLabel: label, resultPreview: "score \(String(format: "%.1f", swipe.hookScore))/10"))
        }
        onContextActivity?(.completed(name: "select_swipes", displayLabel: "Selected \(selectedSwipes.count) swipe examples", resultPreview: selectedSwipes.map(\.title).joined(separator: ", ")))
        print("🔧 [UnifiedWritingEngine] Selected \(selectedSwipes.count) swipes: \(selectedSwipes.map(\.title))")

        // Emit best performers event if client posts were indexed
        if !clientPostIndex.isEmpty {
            let sameFormat = clientPostIndex.filter { $0.format == "same_format" }.count
            let crossFormat = clientPostIndex.filter { $0.format == "cross_format" }.count
            var parts: [String] = []
            if sameFormat > 0 { parts.append("\(sameFormat) same-format") }
            if crossFormat > 0 { parts.append("\(crossFormat) cross-format") }
            let preview = "\(clientPostIndex.count) posts (\(parts.joined(separator: ", ")))"
            onContextActivity?(.completed(name: "load_best_performers", displayLabel: "Client best performers indexed", resultPreview: preview))
        }

        buildCachedBlocks(contentAtom: contentAtom)
        print("🔧 [UnifiedWritingEngine] Block1 length: \(cachedBlock1?.count ?? 0) chars, Block2 length: \(cachedBlock2?.count ?? 0) chars")

        // Load the client's taste profile (learned beliefs + pinned rules)
        let contentMeta = contentAtom.metadataValue(as: ContentAtomMetadata.self)
        if let clientUUID = contentMeta?.clientProfileUUID {
            onContextActivity?(.started(name: "load_preferences", displayLabel: "Loading learned rules", args: [:]))

            // Resolve lessons from canonical atom storage (single source of truth)
            let format = detectContentFormat().rawValue
            let policy = await TasteContext.resolveForWritingEngine(
                clientUUID: clientUUID,
                intent: "draft",
                format: format
            )

            // Also load simple key-value user preferences
            let userPrefs = await loadUserPreferences(clientUUID: clientUUID)

            if var block2 = cachedBlock2, !block2.isEmpty {
                if !policy.formattedBlock.isEmpty {
                    block2 += policy.formattedBlock
                }
                if !userPrefs.isEmpty {
                    let prefsText = userPrefs.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
                    block2 += "\n\n## User Preferences\n\(prefsText)"
                }
                cachedBlock2 = block2
                let hardCount = policy.hardRules.count
                let advisoryCount = policy.advisoryRules.count
                print("🔧 [UnifiedWritingEngine] Injected \(hardCount) hard + \(advisoryCount) advisory lessons into Block 2")
            }
            onContextActivity?(.completed(name: "load_preferences", displayLabel: "Learned rules loaded", resultPreview: "\(policy.totalCount) rules (\(policy.hardRules.count) hard)"))

            // Inject batch analyses relevant to this content's format
            let batchInsights = loadBatchAnalyses(format: detectContentFormat())
            if !batchInsights.isEmpty, var block2 = cachedBlock2, !block2.isEmpty {
                block2 += "\n\n## Batch Analysis Insights (from swipe library patterns)\n\(batchInsights)"
                cachedBlock2 = block2
                print("🔧 [UnifiedWritingEngine] Injected batch analysis insights into Block 2")
            }

        }

        // D1: Emit skill modules loaded event
        onContextActivity?(.completed(name: "load_skill_modules", displayLabel: "Skill modules loaded", resultPreview: "methodology + platform constraints"))

        // Build context info for transparency UI
        var info = LoadedContextInfo()
        info.clientName = clientMeta?.clientName
        info.swipeCount = selectedSwipes.count
        info.swipeTitles = selectedSwipes.map(\.title)
        if let model = clientMeta?.intelligenceModel {
            let fingerprint = model.failureFingerprint
            let reelFp = model.reelFailureFingerprint
            let threadFp = model.threadFailureFingerprint
            info.failureRuleCount = (fingerprint?.rules.count ?? 0)
                + (reelFp?.rules.count ?? 0)
                + (threadFp?.rules.count ?? 0)
        }
        info.estimatedTokens = estimateTokenCount()
        self.loadedContext = info

        // D1: Final "all done" event
        let totalContextPieces = 3 + selectedSwipes.count  // profile + swipes + preferences + skill modules
        onContextActivity?(.allDone(totalCalls: totalContextPieces))

        print("🔧 [UnifiedWritingEngine] ✅ Initialization complete. Estimated tokens: \(info.estimatedTokens), model: \(writerModel), messages: \(messages.count)")
        NotificationCenter.default.post(name: .cosmoWritingEngineContextLoaded, object: nil)
    }

    /// Refresh cached context (call when content atom changes externally)
    func refreshContext() async {
        guard let atom = contentAtom else { return }
        let freshAtom = try? await database.asyncRead { db in
            try Atom.filter(Column("uuid") == atom.uuid).filter(Column("is_deleted") == false).fetchOne(db)
        }
        if let fresh = freshAtom {
            self.contentAtom = fresh
        }
        guard let currentAtom = self.contentAtom else { return }
        await loadClientProfile(contentAtom: currentAtom)
        cachedBlock2 = nil
        cachedBlock3A = nil
        cachedReferenceMaterial.removeAll()
        buildCachedBlocks(contentAtom: currentAtom)
    }

    // MARK: - Conversation

    /// Send a user message and run the full conversation loop (tool calls + multi-turn).
    ///
    /// ARCHITECTURE: This method runs on the main actor to set @Published state,
    /// then delegates the actual conversation loop to a `nonisolated` method.
    /// The nonisolated loop runs API calls on the cooperative thread pool, so its
    /// continuations DON'T need the main actor — SwiftUI re-renders can't starve it.
    func sendMessage(_ text: String, phase: ContentStep) async -> WritingMessage? {
        guard !isProcessing else {
            print("⚠️ [UnifiedWritingEngine] sendMessage BLOCKED — isProcessing is already true")
            return nil
        }
        isProcessing = true
        isCancelled = false
        error = nil
        toolChainSteps = []

        print("💬 [UnifiedWritingEngine] sendMessage: \"\(text.prefix(80))\" phase: \(phase.rawValue)")
        print("💬 [UnifiedWritingEngine] Conversation has \(messages.count) messages, contentAtom: \(contentAtom?.uuid ?? "NIL")")

        // Append user message
        let userMsg = WritingMessage(role: .user, content: text)
        messages.append(userMsg)

        // Summarize if needed (still on main actor, before capturing state)
        await summarizeHistoryIfNeeded()

        // === Capture all state for the nonisolated loop ===
        let snapshot = self.messages   // Array value copy
        let systemBlocks = assembleSystemBlocks()
        let tools = assembleToolDefinitions(phase: phase)
        let model = modelForPhase(phase)
        print("💬 [UnifiedWritingEngine] Phase: \(phase.rawValue) → Model: \(model)")
        let apiKey = APIKeys.openRouter ?? ""

        do {
            let result = try await runConversationLoopOffMain(
                snapshot: snapshot,
                systemBlocks: systemBlocks,
                tools: tools,
                model: model,
                apiKey: apiKey,
                phase: phase
            )

            var committedMessages = result.newMessages
            var finalMessage = result.lastMessage
            if finalMessage == nil {
                let fallback = WritingMessage(role: .assistant, content: Self.noFinalResponseMessage)
                committedMessages.append(fallback)
                finalMessage = fallback
                print("⚠️ [UnifiedWritingEngine] Loop ended without a final assistant message — injecting fallback response")
            }

            // Commit results on main actor (single batch update)
            if !committedMessages.isEmpty {
                messages.append(contentsOf: committedMessages)
                print("💬 [UnifiedWritingEngine] Committed \(committedMessages.count) messages (total: \(messages.count))")
            }

            // B1: Persist conversation to atom.structured for cross-session restoration
            await persistConversation()

            isProcessing = false
            print("💬 [UnifiedWritingEngine] ✅ sendMessage complete. Response: \(finalMessage?.content.prefix(100) ?? "nil")")
            return finalMessage
        } catch is CancellationError {
            isProcessing = false
            print("⚠️ [UnifiedWritingEngine] sendMessage CANCELLED by user")
            let cancelMsg = WritingMessage(role: .assistant, content: "Request cancelled.")
            messages.append(cancelMsg)
            return nil
        } catch {
            isProcessing = false
            self.error = error.localizedDescription
            print("❌ [UnifiedWritingEngine] sendMessage ERROR: \(error)")
            let errorMsg = WritingMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
            messages.append(errorMsg)
            return nil
        }
    }

    /// Cancel any in-flight API request. The loop will exit after the current API call finishes.
    func cancel() {
        isCancelled = true
        // Don't set isProcessing = false here — let the CancellationError handler in sendMessage do it.
        // Otherwise the user could send a new message before the old request finishes, causing a race.
        print("⚠️ [UnifiedWritingEngine] cancel() called — will stop after current API call completes")
    }

    // MARK: - Single-Shot Generation (Agent Bridge)

    /// One-shot request→response bridge for agent tools.
    ///
    /// Creates a temporary engine instance, loads all context for the given content atom,
    /// sends a single instruction, runs the conversation loop (including tool calls like
    /// `update_outline`, `add_hooks`, `write_draft`), and returns the final text response.
    ///
    /// Side effects (outline/hooks/draft updates) are posted via NotificationCenter as usual,
    /// so the agent can observe them if needed.
    ///
    /// - Parameters:
    ///   - instruction: The user-facing instruction to send (e.g., "Generate an outline...")
    ///   - contentUUID: UUID string of the content atom to load context for
    ///   - phase: The content step phase (determines which tools are available)
    /// - Returns: The final assistant text response, or an error description.
    static func singleShotGenerate(
        instruction: String,
        contentUUID: UUID,
        phase: ContentStep = .brainstorm
    ) async -> String {
        let engine = UnifiedWritingEngine()

        // Fetch the content atom
        guard let atom = try? await AtomRepository.shared.fetch(uuid: contentUUID.uuidString) else {
            return "Error: content atom \(contentUUID) not found"
        }

        // Initialize engine — loads client profile, selects swipes, builds cached blocks
        await engine.initialize(contentAtom: atom)

        // Send instruction and run conversation loop
        let response = await engine.sendMessage(instruction, phase: phase)

        // Return the assistant's final text response
        let text = response?.content ?? ""
        return text.isEmpty ? "No response generated." : text
    }

    /// Inject a phase transition marker into the conversation.
    /// Prunes tool-call noise from history while preserving think analysis as plain text.
    func handlePhaseTransition(from: ContentStep, to: ContentStep, state: ContentFocusModeState) {
        // Prune tool-call pattern from conversation history while preserving reasoning.
        // The model mimics brainstorm tool-call chains (think→think→tools) degenerately
        // in draft phase. All structured outputs (outline, hooks, title) are in Block 3,
        // but think analysis (swipe breakdowns, structural reasoning) is NOT — extract it
        // as plain assistant text to preserve draft quality.
        let beforeCount = messages.count
        var cleaned: [WritingMessage] = []

        for msg in messages {
            switch msg.role {
            case .toolResult:
                // Drop all tool results — outputs live in Block 3 / atom metadata
                continue

            case .assistant:
                // Extract think content from tool calls before discarding them
                var thinkContent = ""
                if let toolCalls = msg.toolCalls {
                    for tc in toolCalls where tc.toolName == "think" {
                        if let data = tc.parameters.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let thought = json["thought"] as? String,
                           !thought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            thinkContent += thought + "\n"
                        }
                    }
                }
                let combinedContent = [msg.content, thinkContent]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")

                if !combinedContent.isEmpty {
                    // Keep as plain text assistant message (no toolCalls)
                    cleaned.append(WritingMessage(
                        id: msg.id, role: .assistant, content: combinedContent, timestamp: msg.timestamp
                    ))
                }
                // If neither text nor think content → drop entirely (tool-call-only noise)

            case .user, .system:
                cleaned.append(msg)
            }
        }

        messages = cleaned
        print("🔧 [UnifiedWritingEngine] Phase transition: pruned \(beforeCount) → \(messages.count) messages (think analysis preserved as text)")

        let outlineCount = state.outline.count
        let hookText = state.hooks.first ?? "(none)"

        let transitionText: String
        switch to {
        case .brainstorm:
            transitionText = "[Phase transition: \(from.label) → Brainstorm]\nReturning to brainstorm phase."
        case .draft:
            transitionText = """
            [Phase transition: \(from.label) → Draft]
            The outline has been finalized with \(outlineCount) sections.
            Selected hook: "\(hookText)"
            Description: \(state.contentDescription.isEmpty ? "(none)" : state.contentDescription)
            Your task is now to write the full first draft following the outline beat-by-beat.
            """
        case .polish:
            let wordCount = state.draftContent.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            transitionText = """
            [Phase transition: \(from.label) → Polish]
            The draft is complete (\(wordCount) words).
            Focus on refinement: voice drift correction, CTA strengthening, weak-section rewrites.
            Be surgical, not wholesale.
            """
        }

        let systemMsg = WritingMessage(role: .system, content: transitionText)
        messages.append(systemMsg)
    }

    // MARK: - Quick Actions

    /// Suggest an outline using the AI conversation.
    func suggestOutline() async {
        let prompt = """
        Analyze the content brief and create a structured outline. Use the think tool first \
        to evaluate which beat pattern best fits this content, then use update_outline to set \
        the outline sections, and add_hooks to generate 3-5 hook variants.
        """
        _ = await sendMessage(prompt, phase: .brainstorm)
    }

    /// Generate a full draft from the current outline.
    func generateDraft() async {
        let prompt = """
        Write the full first draft following the outline beat-by-beat. Use the think tool first \
        to plan your approach — verify voice fingerprint requirements, format constraints, and \
        failure rules to avoid. Then use write_draft to output the complete draft.
        """
        _ = await sendMessage(prompt, phase: .draft)
    }

    /// Perform an inline edit (expand/condense/rephrase) on selected text.
    func inlineEdit(action: InlineEditAction, selectedText: String, context: String) async -> String? {
        guard !isProcessing else { return nil }
        isProcessing = true
        error = nil
        toolChainSteps = []

        let instruction: String
        switch action {
        case .expand: instruction = "Expand this section with more detail, examples, or emotional depth while maintaining voice consistency."
        case .condense: instruction = "Condense this section to be more punchy and concise while preserving the core message."
        case .rephrase: instruction = "Rephrase this section with different wording while maintaining the same meaning, tone, and voice."
        }

        let userMsg = WritingMessage(role: .user, content: """
        [Inline edit: \(action.rawValue)]
        Selected text: "\(selectedText)"
        Surrounding context: "\(context.prefix(500))"
        Instruction: \(instruction)
        Use edit_section to apply the change.
        """)
        messages.append(userMsg)

        // Capture state for the nonisolated loop
        let snapshot = self.messages
        let systemBlocks = assembleSystemBlocks()
        let tools = assembleToolDefinitions(phase: .draft)
        let model = modelForPhase(.draft)
        let apiKey = APIKeys.openRouter ?? ""

        do {
            let result = try await runConversationLoopOffMain(
                snapshot: snapshot,
                systemBlocks: systemBlocks,
                tools: tools,
                model: model,
                apiKey: apiKey,
                phase: .draft
            )
            if !result.newMessages.isEmpty {
                messages.append(contentsOf: result.newMessages)
            }
            isProcessing = false
            return result.lastMessage?.content
        } catch {
            isProcessing = false
            self.error = error.localizedDescription
            return nil
        }
    }

    enum InlineEditAction: String {
        case expand, condense, rephrase
    }

    // MARK: - Conversation Loop (Nonisolated)

    /// Result type for the off-main conversation loop.
    struct ConversationLoopResult {
        let newMessages: [WritingMessage]
        let lastMessage: WritingMessage?
    }

    nonisolated private static let maxTransientEmptyNoToolRetries = 1
    nonisolated private static let truncatedResponseWarning =
        "\n\n[System] The model hit its output limit before finishing. Ask me to continue from where it left off."
    nonisolated private static let emptyResponseAbortMessage =
        "The writing engine stopped after empty provider responses. I stopped retrying so this does not keep burning tokens. Please try again or ask me to continue."
    nonisolated private static let noFinalResponseMessage =
        "The writing engine stopped without a final response. No further automatic retries were attempted."

    nonisolated static func classifyLoopResponse(
        response: ClaudeToolUseResponse,
        cleanedText: String,
        emptyNoToolResponseCount: Int,
        maxTransientRetries: Int = UnifiedWritingEngine.maxTransientEmptyNoToolRetries
    ) -> WritingLoopResponseDisposition {
        let trimmedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard response.toolCalls.isEmpty else {
            return WritingLoopResponseDisposition(
                decision: .acceptFinal,
                assistantText: cleanedText,
                logReason: "tool-calling response"
            )
        }

        if !trimmedText.isEmpty {
            if response.stopReason == "length" {
                return WritingLoopResponseDisposition(
                    decision: .acceptFinal,
                    assistantText: cleanedText + truncatedResponseWarning,
                    logReason: "accepted truncated no-tool response"
                )
            }

            return WritingLoopResponseDisposition(
                decision: .acceptFinal,
                assistantText: cleanedText,
                logReason: "accepted non-empty no-tool response"
            )
        }

        if emptyNoToolResponseCount < maxTransientRetries {
            return WritingLoopResponseDisposition(
                decision: .retryTransient,
                assistantText: "",
                logReason: "empty no-tool response \(emptyNoToolResponseCount + 1)/\(maxTransientRetries) — retrying"
            )
        }

        return WritingLoopResponseDisposition(
            decision: .abort,
            assistantText: emptyResponseAbortMessage,
            logReason: "empty no-tool response repeated after retry budget"
        )
    }

    nonisolated private static func noProgressSignature(
        for response: ClaudeToolUseResponse,
        cleanedText: String
    ) -> String {
        let trimmedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            response.stopReason ?? "nil",
            response.nativeFinishReason ?? "nil",
            response.completionTokens.map { String($0) } ?? "nil",
            trimmedText
        ].joined(separator: "|")
    }

    /// Core conversation loop — runs OFF the main actor.
    ///
    /// This is `nonisolated` so that API call continuations resume on the cooperative
    /// thread pool instead of the main actor. SwiftUI re-renders cannot starve this loop.
    ///
    /// - `snapshot`: The committed messages at the time of the call (value copy).
    /// - Tool execution hops to main actor briefly via `await self.executeToolCalls()`.
    /// - @Published state is NOT modified here — the caller commits results.
    nonisolated private func runConversationLoopOffMain(
        snapshot: [WritingMessage],
        systemBlocks: [PromptCacheBlock],
        tools: [[String: Any]],
        model: String,
        apiKey: String,
        phase: ContentStep
    ) async throws -> ConversationLoopResult {
        var pendingMessages: [WritingMessage] = []
        var lastAssistantMessage: WritingMessage?
        var consecutiveThinkOnly = 0
        var consecutiveTransientNoToolResponses = 0
        var consecutiveNoProgressResponses = 0
        var lastNoProgressSignature: String?
        var thinkToolRemoved = false
        var activeTools = tools
        // WP6: Anti-stall — repetition detection
        var toolCallHistory: [(name: String, paramHash: Int)] = []
        // WP6: Anti-stall — violation escalation tracking
        var previousViolationRules: Set<String> = []

        let toolNames = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        print("🔄 [UnifiedWritingEngine] Starting conversation loop (nonisolated). System blocks: \(systemBlocks.count), tools: \(toolNames)")

        conversationLoop: for iteration in 0..<10 {
            // Check cancellation (brief main actor hop)
            let cancelled = await self.isCancelled
            guard !cancelled else {
                print("⚠️ [UnifiedWritingEngine] Conversation loop cancelled at iteration \(iteration)")
                throw CancellationError()
            }

            // Build API messages from snapshot + pending
            let allMessages = snapshot + pendingMessages
            let apiMessages = Self.buildAPIMessages(from: allMessages)
            print("🔄 [UnifiedWritingEngine] Iteration \(iteration): sending \(apiMessages.count) messages to \(model)")

            // API call — nonisolated free function.
            // Continuation resumes on cooperative pool, NOT main actor. ✅
            let response: ClaudeToolUseResponse
            do {
                response = try await performWritingAPICall(
                    apiKey: apiKey,
                    systemBlocks: systemBlocks,
                    messages: apiMessages,
                    tools: activeTools,
                    model: model,
                    maxTokens: 16384,
                    temperature: 0.3
                )
            } catch {
                print("❌ [UnifiedWritingEngine] API call FAILED: \(error)")
                throw error
            }

            // Check cancellation after API returns (still on cooperative pool)
            let cancelledAfter = await self.isCancelled
            guard !cancelledAfter else {
                print("⚠️ [UnifiedWritingEngine] Cancelled after API response received")
                throw CancellationError()
            }

            print(
                "🔄 [UnifiedWritingEngine] Response: text=\(response.textContent.count)chars, tools=\(response.toolCalls.count), stop=\(response.stopReason ?? "nil"), native=\(response.nativeFinishReason ?? "nil"), completion=\(response.completionTokens.map { String($0) } ?? "nil"), id=\(response.responseId ?? "nil")"
            )

            // Build WritingToolCall objects from response
            var assistantToolCalls: [WritingToolCall] = []
            for call in response.toolCalls {
                let paramsJSON: String
                if let data = try? JSONSerialization.data(withJSONObject: call.input),
                   let str = String(data: data, encoding: .utf8) {
                    paramsJSON = str
                } else {
                    paramsJSON = "{}"
                }
                assistantToolCalls.append(WritingToolCall(
                    id: call.id,
                    toolName: call.name,
                    parameters: paramsJSON
                ))
            }

            // Strip thinking/analysis tags from response text
            let cleanedText = stripThinkingTags(response.textContent)
            var finalAssistantText = cleanedText
            let hasToolCalls = !response.toolCalls.isEmpty

            if !hasToolCalls {
                var disposition = Self.classifyLoopResponse(
                    response: response,
                    cleanedText: cleanedText,
                    emptyNoToolResponseCount: consecutiveTransientNoToolResponses
                )

                let trimmedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedText.isEmpty {
                    let signature = Self.noProgressSignature(for: response, cleanedText: cleanedText)
                    if signature == lastNoProgressSignature {
                        consecutiveNoProgressResponses += 1
                    } else {
                        lastNoProgressSignature = signature
                        consecutiveNoProgressResponses = 1
                    }
                } else {
                    lastNoProgressSignature = nil
                    consecutiveNoProgressResponses = 0
                }

                if disposition.decision == .retryTransient && consecutiveNoProgressResponses > 1 {
                    disposition = WritingLoopResponseDisposition(
                        decision: .abort,
                        assistantText: Self.emptyResponseAbortMessage,
                        logReason: "repeated no-progress response with identical signature — aborting to avoid replay loop"
                    )
                }

                switch disposition.decision {
                case .retryTransient:
                    consecutiveTransientNoToolResponses += 1
                    let backoffSeconds = min(pow(2.0, Double(consecutiveTransientNoToolResponses)), 4.0)
                    print("⚠️ [UnifiedWritingEngine] No-tool response retry: \(disposition.logReason)")
                    print("⏳ [UnifiedWritingEngine] Backing off \(Int(backoffSeconds))s before retry (attempt \(consecutiveTransientNoToolResponses)/\(Self.maxTransientEmptyNoToolRetries))")
                    try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                    continue conversationLoop

                case .abort:
                    consecutiveTransientNoToolResponses = 0
                    let abortMsg = WritingMessage(role: .assistant, content: disposition.assistantText)
                    pendingMessages.append(abortMsg)
                    lastAssistantMessage = abortMsg
                    print("❌ [UnifiedWritingEngine] \(disposition.logReason)")
                    break conversationLoop

                case .acceptFinal:
                    consecutiveTransientNoToolResponses = 0
                    finalAssistantText = disposition.assistantText
                    print("🔄 [UnifiedWritingEngine] Accepting no-tool response: \(disposition.logReason)")
                }
            } else {
                consecutiveTransientNoToolResponses = 0
                consecutiveNoProgressResponses = 0
                lastNoProgressSignature = nil
            }

            let hasText = !finalAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Build assistant message
            if hasText || !hasToolCalls {
                let assistantMsg = WritingMessage(
                    role: .assistant,
                    content: finalAssistantText,
                    toolCalls: assistantToolCalls.isEmpty ? nil : assistantToolCalls
                )
                pendingMessages.append(assistantMsg)
                lastAssistantMessage = assistantMsg
            } else if hasToolCalls {
                let hiddenMsg = WritingMessage(
                    role: .assistant,
                    content: "",
                    toolCalls: assistantToolCalls
                )
                pendingMessages.append(hiddenMsg)
                lastAssistantMessage = hiddenMsg
            }

            // If no tool calls, conversation is done
            if !hasToolCalls {
                print("🔄 [UnifiedWritingEngine] No tool calls — conversation complete at iteration \(iteration)")
                break conversationLoop
            }

            // Execute tool calls — hops to main actor briefly for notifications + @Published updates.
            // Returns to cooperative pool after each call.
            print("🔄 [UnifiedWritingEngine] Executing \(response.toolCalls.count) tool calls...")
            let toolResults = await self.executeToolCalls(response.toolCalls, phase: phase)
            for result in toolResults {
                let resultMsg = WritingMessage(role: .toolResult, content: result.content, toolResults: [result])
                pendingMessages.append(resultMsg)
            }

            // --- WP6: Repetition detection ---
            for call in response.toolCalls where call.name != "think" {
                let paramData = (try? JSONSerialization.data(withJSONObject: call.input, options: .sortedKeys)) ?? Data()
                let paramHash = paramData.hashValue
                let entry = (name: call.name, paramHash: paramHash)
                if let prevIdx = toolCallHistory.firstIndex(where: { $0.name == entry.name && $0.paramHash == entry.paramHash }) {
                    // Duplicate detected — inject nudge into pending messages
                    let prevResult = toolResults.first { $0.toolCallId == call.id }?.content ?? "(no result)"
                    let nudge = WritingMessage(
                        role: .system,
                        content: "[System] You called \(call.name) with identical parameters as a previous call. Previous result: \(String(prevResult.prefix(300))). Try a different approach or adjust your parameters."
                    )
                    pendingMessages.append(nudge)
                    toolCallHistory.remove(at: prevIdx)
                    print("⚠️ [UnifiedWritingEngine] Repetition detected: \(call.name) called with identical params")
                }
                toolCallHistory.append(entry)
            }

            // --- WP6: Violation escalation — check for repeated violations across write_draft calls ---
            for call in response.toolCalls where call.name == "write_draft" {
                if let result = toolResults.first(where: { $0.toolCallId == call.id }),
                   result.content.contains("[COMPLIANCE CHECK") {
                    // Extract current violation rules from the result
                    let lines = result.content.components(separatedBy: "\n")
                    let violationLines = lines.filter { line in
                        line.contains("VIOLATION:") || line.contains("BANNED PHRASE") || line.contains("FATAL PATTERN")
                    }
                    let currentRules = Set(violationLines.map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) })
                    let repeatedRules = currentRules.intersection(previousViolationRules)
                    if !repeatedRules.isEmpty {
                        let escalation = WritingMessage(
                            role: .system,
                            content: "[System] CRITICAL: You repeated \(repeatedRules.count) violation(s) from your previous draft attempt. These exact phrases must be DELETED — do not try to rephrase around them, remove them entirely:\n\(repeatedRules.joined(separator: "\n"))\n\nWrite the revised draft with these phrases completely removed."
                        )
                        pendingMessages.append(escalation)
                        print("🚨 [UnifiedWritingEngine] Violation escalation: \(repeatedRules.count) repeated violations")
                    }
                    previousViolationRules = currentRules
                }
            }

            // --- Anti-loop guard ---
            let isThinkOnly = response.toolCalls.allSatisfy { $0.name == "think" }
            let isEmptyThinkOnly = isThinkOnly && response.toolCalls.allSatisfy { call in
                ((call.input["thought"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            if isThinkOnly {
                consecutiveThinkOnly += 1
            } else {
                consecutiveThinkOnly = 0
            }

            // Trigger: >=1 empty-think-only turn, OR >=2 consecutive think-only turns
            if (isEmptyThinkOnly || consecutiveThinkOnly >= 2) && !thinkToolRemoved {
                print("⚠️ [UnifiedWritingEngine] Anti-loop guard: removing think tool (thinkOnly=\(consecutiveThinkOnly), emptyThink=\(isEmptyThinkOnly))")
                thinkToolRemoved = true
                activeTools = activeTools.filter { tool in
                    (tool["function"] as? [String: Any])?["name"] as? String != "think"
                }
                let nudge = WritingMessage(role: .system, content: "[System] Proceed with a concrete action — use write_draft, update_outline, edit_section, or produce your final text response.")
                pendingMessages.append(nudge)
            }

            // --- End anti-loop guard ---
        }

        print("🔄 [UnifiedWritingEngine] Loop done. \(pendingMessages.count) new messages.")
        return ConversationLoopResult(newMessages: pendingMessages, lastMessage: lastAssistantMessage)
    }

    /// Build API messages from a WritingMessage array.
    /// `nonisolated static` so it can be called from the off-main conversation loop.
    nonisolated static func buildAPIMessages(from messages: [WritingMessage]) -> [[String: Any]] {
        var apiMessages: [[String: Any]] = []
        let preserveFromIndex = max(0, messages.count - 6)
        var compactedToolCallIds = Set<String>()

        for (index, msg) in messages.enumerated() {
            switch msg.role {
            case .user:
                apiMessages.append(["role": "user", "content": msg.content])

            case .assistant:
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    let shouldCompact = index < preserveFromIndex
                        && toolCalls.allSatisfy { compactableHistoricalToolNames.contains($0.toolName) }

                    if shouldCompact {
                        compactedToolCallIds.formUnion(toolCalls.map(\.id))
                        let summary = compactedAssistantSummary(from: msg, toolCalls: toolCalls)
                        if !summary.isEmpty {
                            apiMessages.append(["role": "assistant", "content": summary])
                        }
                        continue
                    }

                    var assistantMsg: [String: Any] = ["role": "assistant"]
                    if !msg.content.isEmpty {
                        assistantMsg["content"] = msg.content
                    } else {
                        assistantMsg["content"] = NSNull()
                    }
                    var tcArray: [[String: Any]] = []
                    for call in toolCalls {
                        tcArray.append([
                            "id": call.id,
                            "type": "function",
                            "function": [
                                "name": call.toolName,
                                "arguments": call.parameters
                            ]
                        ])
                    }
                    assistantMsg["tool_calls"] = tcArray
                    apiMessages.append(assistantMsg)
                } else {
                    apiMessages.append(["role": "assistant", "content": msg.content])
                }

            case .toolResult:
                if let results = msg.toolResults {
                    for result in results {
                        if compactedToolCallIds.contains(result.toolCallId) {
                            continue
                        }
                        apiMessages.append([
                            "role": "tool",
                            "tool_call_id": result.toolCallId,
                            "content": result.content
                        ])
                    }
                }

            case .system:
                apiMessages.append(["role": "user", "content": "[System] \(msg.content)"])
            }
        }

        return apiMessages
    }

    nonisolated private static let compactableHistoricalToolNames: Set<String> = [
        "set_title",
        "set_description",
        "update_outline",
        "add_hooks",
        "write_draft",
        "edit_section",
        "get_client_profile",
        "read_client_post",
        "read_swipe_body"
    ]

    nonisolated private static func compactedAssistantSummary(
        from message: WritingMessage,
        toolCalls: [WritingToolCall]
    ) -> String {
        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolNames = toolCalls.map(\.toolName).joined(separator: ", ")

        if toolCalls.contains(where: { $0.toolName == "get_client_profile" }) {
            if trimmedContent.isEmpty {
                return "[Earlier tool result compacted: client profile already loaded into system context.]"
            }
            return trimmedContent
        }

        if trimmedContent.isEmpty {
            return "[Earlier tool actions already applied to session state: \(toolNames)]"
        }
        return trimmedContent + "\n\n[Earlier tool actions already applied to session state: \(toolNames)]"
    }

    // MARK: - Context Assembly

    /// Assemble the 4-tier system blocks for the API call.
    private func assembleSystemBlocks() -> [PromptCacheBlock] {
        let block1 = cachedBlock1 ?? assembleBlock1()
        let block2 = (cachedBlock2?.isEmpty == false) ? cachedBlock2 : nil
        let stableBlock3 = assembleStableBlock3()
        let dynamicBlock3 = assembleDynamicBlock3()

        return Self.composeSystemBlocks(
            block1: block1,
            block2: block2,
            stableBlock3: stableBlock3,
            dynamicBlock3: dynamicBlock3,
            ttl: promptCacheTTL
        )
    }

    nonisolated static func composeSystemBlocks(
        block1: String,
        block2: String?,
        stableBlock3: String,
        dynamicBlock3: String,
        ttl: String
    ) -> [PromptCacheBlock] {
        var blocks: [PromptCacheBlock] = []

        blocks.append(PromptCacheBlock(
            content: block1,
            cacheControl: true,
            ttl: ttl,
            label: "Block 1"
        ))

        if let block2, !block2.isEmpty {
            blocks.append(PromptCacheBlock(
                content: block2,
                cacheControl: true,
                ttl: ttl,
                label: "Block 2"
            ))
        }

        if !stableBlock3.isEmpty {
            blocks.append(PromptCacheBlock(
                content: stableBlock3,
                cacheControl: true,
                ttl: ttl,
                label: "Block 3A"
            ))
        }

        if !dynamicBlock3.isEmpty {
            blocks.append(PromptCacheBlock(
                content: dynamicBlock3,
                cacheControl: false,
                label: "Block 3B"
            ))
        }

        return blocks
    }

    /// Block 1: System prompt + methodology + platform constraints.
    /// Uses PromptTemplateStore.shared.assembledSystemPrompt() which injects
    /// {METHODOLOGY_TEXT} and {PLATFORM_CONSTRAINTS} into the unified prompt template.
    /// Stable across ALL requests for all clients.
    private func assembleBlock1() -> String {
        let formatStr = detectContentFormat().rawValue
        let block = PromptTemplateStore.shared.assembledSystemPrompt(format: formatStr)
        cachedBlock1 = block
        return block
    }

    /// Block 2: Client intelligence model (voice + performance + failures + brand story).
    /// Top transcripts are NO LONGER included here — they live in Block 3 as client examples (C2).
    /// Failure fingerprint condensed to HIGH severity + top 3 MEDIUM rules, capped at 800 chars (C3).
    /// Brand story capped at 1 doc, 1000 chars (C3). Target: ~15-20K chars.
    private func assembleBlock2() -> String {
        guard let profileAtom = clientProfileAtom,
              let meta = clientMeta else {
            return ""
        }

        var lines: [String] = []
        lines.append("=== CLIENT INTELLIGENCE MODEL ===")
        lines.append("")
        lines.append("Client: \(meta.clientName)")
        if let handle = meta.handle { lines.append("Handle: \(handle)") }

        let platforms = meta.platforms.map(\.displayName).joined(separator: ", ")
        if !platforms.isEmpty { lines.append("Platforms: \(platforms)") }
        lines.append("")

        // Intelligence Model summary (voice + performance + audience + positioning + condensed failures)
        if let model = meta.intelligenceModel {
            let modelSummary = ClientIntelligenceEngine.shared.getModelForDrafting(profile: profileAtom)
            if !modelSummary.isEmpty {
                lines.append("--- INTELLIGENCE MODEL ---")
                lines.append(modelSummary)
                lines.append("")
            }

            // Actionable voice targets — concrete numeric thresholds from the voice fingerprint
            let vf = model.voiceFingerprint
            var voiceTargets: [String] = []
            voiceTargets.append("--- VOICE TARGETS (check every draft against these) ---")
            if vf.avgSentenceLength > 0 {
                let low = Int(vf.avgSentenceLength * 0.7)
                let high = Int(vf.avgSentenceLength * 1.3)
                voiceTargets.append("Sentence length: target \(low)-\(high) words (client avg: \(Int(vf.avgSentenceLength))). >50% deviation = voice drift.")
            }
            if !vf.signaturePhrases.isEmpty {
                let phrases = vf.signaturePhrases.prefix(5).joined(separator: "\", \"")
                voiceTargets.append("Signature phrases (use at least 1-2 per piece): \"\(phrases)\"")
            }
            if !vf.ctaPattern.isEmpty {
                voiceTargets.append("CTA style: \(vf.ctaPattern)")
            }
            if !vf.formattingQuirks.isEmpty {
                voiceTargets.append("Style markers: \(vf.formattingQuirks.joined(separator: ", "))")
            }
            if !vf.punctuationStyle.isEmpty {
                voiceTargets.append("Punctuation: \(vf.punctuationStyle)")
            }
            if !vf.powerWords.isEmpty {
                let words = vf.powerWords.prefix(8).joined(separator: ", ")
                voiceTargets.append("Power words (weave in naturally): \(words)")
            }
            if voiceTargets.count > 1 {
                lines.append(contentsOf: voiceTargets)
                lines.append("")
            }

            // C3: Condensed failure fingerprint — HIGH severity + top 3 MEDIUM, capped at 800 chars
            appendCondensedFailureFingerprint(to: &lines, model: model)

            // C2: Top transcripts REMOVED from Block 2 — they now live in Block 3 as client examples

            // C3: Brand story + voice guide — full content, no truncation
            if let documents = meta.documents {
                let storyDocs = documents.filter { $0.category == .story }
                if let firstStory = storyDocs.first {
                    lines.append("--- BRAND STORY CONTEXT ---")
                    lines.append(firstStory.content)
                    lines.append("")
                }
                let voiceGuideDocs = documents.filter { $0.category == .voiceGuide }
                if let firstGuide = voiceGuideDocs.first {
                    lines.append("--- VOICE GUIDE ---")
                    lines.append(firstGuide.content)
                    lines.append("")
                }
            }
        } else {
            // Legacy fallback — no intelligence model
            appendLegacyProfile(to: &lines, meta: meta)
        }

        // Top 5 best-performing posts for this client, filtered by current content format
        appendTopPerformingPosts(to: &lines, meta: meta, format: detectContentFormat())

        let result = lines.joined(separator: "\n")
        cachedBlock2 = result
        return result
    }

    /// Block 3A: Session-stable swipe/reference context.
    private func assembleStableBlock3() -> String {
        if let cached = cachedBlock3A { return cached }
        guard let atom = contentAtom else { return "" }

        var lines: [String] = []
        lines.append("=== STABLE SESSION CONTEXT ===")
        lines.append("")

        // Selected swipe examples (compressed)
        if !selectedSwipes.isEmpty {
            // Niche guard — remind the LLM that swipe topics may differ from client niche
            let clientNiche = clientMeta?.intelligenceModel?.nicheAndPositioning.specificNiche
                ?? clientMeta?.niche
            if let niche = clientNiche, !niche.isEmpty {
                lines.append("CLIENT NICHE: \(niche). All content must be about this niche. The swipe examples below are high-performing posts — study their voice, pacing, and structure. Their topics may differ from the client's niche.")
                lines.append("")
            }

            lines.append("--- SAME-TYPE SWIPE EXAMPLES (\(selectedSwipes.count) selected) ---")
            for (i, swipe) in selectedSwipes.enumerated() {
                lines.append("SWIPE #\(i + 1) (UUID: \(swipe.id.uuidString)):")
                lines.append(swipe.formatted())
                lines.append("")
            }

            // Persistent swipe application rules — survive across all turns including revisions
            lines.append("--- SWIPE APPLICATION RULES (apply on EVERY turn, including revisions) ---")
            let primarySwipe = selectedSwipes.first(where: { $0.isPrimary })
            if let primary = primarySwipe {
                lines.append("PRIMARY BLUEPRINT: \"\(primary.title)\"")
                lines.append("  Beat pattern: \(primary.beatSequence.joined(separator: " > "))")
                lines.append("  Hook type: \(primary.hookType) (score: \(String(format: "%.1f", primary.hookScore))/10)")
                // Beat function breakdown — explains the structural ROLE of each position
                if !primary.beatSequence.isEmpty {
                    lines.append("  Beat functions (apply these structural roles, NOT the blueprint's topic):")
                    for (i, beat) in primary.beatSequence.enumerated() {
                        let transition = i < primary.keyTransitions.count ? " — \(primary.keyTransitions[i])" : ""
                        lines.append("    \(i + 1). [\(beat)]\(transition)")
                    }
                }
            }
            lines.append("""
            RULES:
            1. These \(selectedSwipes.count) swipes are your PERMANENT reference library for this session. Their full bodies are loaded — read and absorb them.
            2. The PRIMARY swipe is your closest structural anchor — mirror its beat pattern, hook type, and emotional arc.
            3. On EVERY revision, maintain the PRIMARY swipe's structural DNA — beat pattern, section count, and emotional arc.
            4. When shortening/lengthening, REDISTRIBUTE content to preserve the beat pattern — don't flatten the structure.
            5. Study how the top-scoring swipes write transitions, hooks, and CTAs. Match their energy in the client's voice.
            6. Use list_client_posts + read_client_post to access the client's own post bodies on demand.
            """)
            lines.append("")

            // Cross-swipe pattern intelligence (WP2)
            lines.append(buildPatternIntelligence())
            lines.append("")
        }

        let result = lines.joined(separator: "\n")
        cachedBlock3A = result
        return result
    }

    /// Block 3B: Mutable per-turn context.
    private func assembleDynamicBlock3() -> String {
        guard let atom = contentAtom else { return "" }

        var lines: [String] = []
        lines.append("=== DYNAMIC CONTEXT ===")
        lines.append("")
        lines.append(buildDynamicContextInstruction())
        lines.append("")

        lines.append("--- CURRENT CONTENT STATE ---")
        lines.append("Title: \(atom.title ?? "Untitled")")
        let contentMeta = atom.metadataValue(as: ContentAtomMetadata.self)
        if let platform = contentMeta?.platform {
            lines.append("Platform: \(platform.displayName)")
        }
        lines.append("Phase: \(contentMeta?.phase.displayName ?? "Unknown")")

        let body = atom.body ?? ""
        if !body.isEmpty {
            let truncated = body.count > 1000 ? String(body.prefix(1000)) + "... [truncated, full text available via read_draft]" : body
            lines.append("Core Idea:\n\(truncated)")
        }

        if let focusState = ContentFocusModeState.from(atom: atom) {
            if !focusState.contentDescription.isEmpty {
                lines.append("Description: \(focusState.contentDescription)")
            }
            if !focusState.outline.isEmpty {
                lines.append("Outline:")
                for item in focusState.sortedOutline {
                    lines.append("  \(item.sortOrder + 1). [\(item.title)]")
                    if !item.reasoning.isEmpty {
                        lines.append("     Notes: \(item.reasoning)")
                    }
                }
            }
            if !focusState.hooks.isEmpty {
                lines.append("Hooks:")
                for (i, hook) in focusState.hooks.enumerated() {
                    lines.append("  \(i + 1). \(hook)")
                }
            }
            if !focusState.draftContent.isEmpty {
                lines.append("Current Draft: \(focusState.draftContent.count) chars written. Use read_draft tool to access full text.")
            }
        }

        if let framework = contentMeta?.inheritedFramework {
            lines.append("Selected Framework: \(framework)")
        }
        if let hooks = contentMeta?.inheritedHooks, !hooks.isEmpty {
            lines.append("Inherited Hooks: \(hooks.joined(separator: " | "))")
        }

        // Conversation summary (if history was summarized)
        if !conversationSummary.isEmpty {
            lines.append("")
            lines.append("--- CONVERSATION SUMMARY (earlier turns) ---")
            lines.append(conversationSummary)
        }

        return lines.joined(separator: "\n")
    }

    private func buildDynamicContextInstruction() -> String {
        var parts: [String] = []
        parts.append("[SESSION DIRECTIVE]")
        parts.append("Use the loaded same-type swipe set before making any writing decision.")
        if selectedSwipes.contains(where: { $0.isPrimary }) {
            parts.append("Treat the PRIMARY BLUEPRINT as the structural anchor. Supporting swipes are evidence for what works in this exact format.")
        }
        if let meta = clientMeta {
            parts.append("Client profile is already loaded for \(meta.clientName). Do not call get_client_profile again unless the user explicitly switches creators.")
        } else {
            parts.append("No client profile is loaded. Use get_client_profile only if the user identifies a creator.")
        }
        parts.append("Do not search or load cross-format swipes for this piece.")
        return parts.joined(separator: " ")
    }

    // MARK: - Tool Definitions

    /// Build Claude tool_use definitions, filtered by phase.
    private func assembleToolDefinitions(phase: ContentStep) -> [[String: Any]] {
        var tools: [[String: Any]] = []

        // think — always available
        tools.append(buildTool(
            name: "think",
            description: "Reason through a complex decision before responding. Use this to verify voice consistency, check constraint compliance, or plan multi-step edits.",
            properties: [
                "thought": ["type": "string", "description": "Your internal reasoning"]
            ],
            required: ["thought"]
        ))

        // set_title — always available
        tools.append(buildTool(
            name: "set_title",
            description: "Set or update the content atom's title. Use the hook text or a concise content title.",
            properties: [
                "title": ["type": "string", "description": "The new title for this content"]
            ],
            required: ["title"]
        ))

        // update_outline — brainstorm + draft
        if phase == .brainstorm || phase == .draft {
            tools.append(buildTool(
                name: "update_outline",
                description: "Replace the current outline with a new structured outline.",
                properties: [
                    "sections": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "beatLabel": ["type": "string"],
                                "title": ["type": "string"],
                                "description": ["type": "string"],
                                "estimatedSeconds": ["type": "integer"],
                                "notes": ["type": "string"]
                            ],
                            "required": ["beatLabel", "title", "description"]
                        ]
                    ],
                    "reasoning": ["type": "string", "description": "Why this outline structure was chosen"]
                ],
                required: ["sections", "reasoning"]
            ))
        }

        // add_hooks — brainstorm + draft
        if phase == .brainstorm || phase == .draft {
            tools.append(buildTool(
                name: "add_hooks",
                description: "Add hook variants with scoring and reasoning.",
                properties: [
                    "hooks": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "text": ["type": "string"],
                                "hookType": ["type": "string"],
                                "estimatedScore": ["type": "number"],
                                "reasoning": ["type": "string"]
                            ],
                            "required": ["text", "hookType", "estimatedScore", "reasoning"]
                        ]
                    ]
                ],
                required: ["hooks"]
            ))
        }

        // set_description — brainstorm
        if phase == .brainstorm {
            tools.append(buildTool(
                name: "set_description",
                description: "Set the content description/theme.",
                properties: [
                    "description": ["type": "string", "description": "The content description"]
                ],
                required: ["description"]
            ))
        }

        // write_draft — draft + polish
        if phase == .draft || phase == .polish {
            tools.append(buildTool(
                name: "write_draft",
                description: "Write or replace the full draft content. For carousel format, output JSON as {\"slides\": [{\"number\": 1, \"text\": \"...\"}]} — do NOT include visualDirection or any other fields. For thread format, output JSON as {\"tweets\": [{\"number\": 1, \"text\": \"...\"}]}. HARD RULES: Max 300 characters per slide/tweet. 3-4 sentences per slide. Each sentence on its own line (use \\n\\n between sentences). Max 15 slides. IMPORTANT: When revising, include ALL slides/sections — even unchanged ones. Never reduce the slide count unless explicitly asked.",
                properties: [
                    "content": ["type": "string", "description": "The full draft content"],
                    "format": [
                        "type": "string",
                        "enum": ["plaintext", "carousel_json", "thread_json", "script"],
                        "description": "Output format"
                    ],
                    "selfEvaluation": [
                        "type": "object",
                        "properties": [
                            "confidenceScore": ["type": "number"],
                            "voiceMatchScore": ["type": "number"],
                            "weakAreas": ["type": "array", "items": ["type": "string"]]
                        ],
                        "required": ["confidenceScore", "voiceMatchScore", "weakAreas"]
                    ]
                ],
                required: ["content", "format", "selfEvaluation"]
            ))
        }

        // edit_section — draft + polish
        if phase == .draft || phase == .polish {
            tools.append(buildTool(
                name: "edit_section",
                description: "Replace a specific section of the draft. Identify the section by its text or label.",
                properties: [
                    "sectionIdentifier": ["type": "string", "description": "The section to replace (e.g., 'the hook', 'slide 3', a text excerpt)"],
                    "newContent": ["type": "string", "description": "The replacement content"],
                    "reasoning": ["type": "string", "description": "Why this edit improves the draft"]
                ],
                required: ["sectionIdentifier", "newContent", "reasoning"]
            ))
        }

        // search_swipes — always available
        tools.append(buildTool(
            name: "search_swipes",
            description: "Search the swipe file library for relevant same-type examples. Returns compressed swipe summaries with UUIDs. Defaults to the current writing format unless an explicit format filter is provided. Use read_swipe_body to load the full body text of any result.",
            properties: [
                "query": ["type": "string", "description": "Search query for finding relevant swipes"],
                "format": ["type": "string", "description": "Filter by format (optional)"],
                "hookType": ["type": "string", "description": "Filter by hook type (optional)"],
                "minScore": ["type": "number", "description": "Minimum hook score filter (optional)"]
            ],
            required: ["query"]
        ))

        // list_client_posts — always available
        tools.append(buildTool(
            name: "list_client_posts",
            description: "List all client posts with title, category, engagement metrics, and char count. No body text — use read_client_post to load specific post bodies. Recommended: load 4-5 same-format posts for voice reference.",
            properties: [:],
            required: []
        ))

        // read_client_post — always available
        tools.append(buildTool(
            name: "read_client_post",
            description: "Read a client post's full body text. Returns the complete post content. Use list_client_posts first to find the post ID.",
            properties: [
                "post_id": ["type": "string", "description": "The UUID of the client post to load"]
            ],
            required: ["post_id"]
        ))

        // read_swipe_body — always available
        tools.append(buildTool(
            name: "read_swipe_body",
            description: "Read a swipe's full body text. Returns the complete swipe content. Use the UUID from the swipe examples or search_swipes results.",
            properties: [
                "swipe_id": ["type": "string", "description": "The UUID of the swipe to load"]
            ],
            required: ["swipe_id"]
        ))

        // search_connections — always available
        tools.append(buildTool(
            name: "search_connections",
            description: "Search the user's knowledge graph for intellectual frameworks, research notes, and connections relevant to the content. Use this to add originality and depth.",
            properties: [
                "query": ["type": "string", "description": "What to search for in connections and research"]
            ],
            required: ["query"]
        ))

        // analyze_swipe_patterns — always available
        tools.append(buildTool(
            name: "analyze_swipe_patterns",
            description: "Analyze patterns across all loaded swipe examples. Returns aggregated intelligence: hook performance by type, persuasion technique frequency, emotional arc consensus, and engagement correlations. Use this to make data-driven creative decisions before writing.",
            properties: [
                "focus": ["type": "string", "description": "Analysis focus: 'hooks', 'persuasion', 'emotional_arc', 'engagement', or 'all' (default: 'all')"]
            ],
            required: []
        ))

        // read_draft — draft + polish
        if phase == .draft || phase == .polish {
            tools.append(buildTool(
                name: "read_draft",
                description: "Read the current full draft content. Use this in polish phase to see sections that may have been truncated in the context window.",
                properties: [:],
                required: []
            ))
        }

        // get_client_profile — always available
        tools.append(buildTool(
            name: "get_client_profile",
            description: "Search for and load a client/creator profile by name. Returns their voice fingerprint, intelligence model, top-performing posts, brand context, and uploaded documents. Use this when you need to understand a creator's voice and style, or when no client profile is currently loaded.",
            properties: [
                "query": ["type": "string", "description": "Client name or handle to search for"]
            ],
            required: ["query"]
        ))

        return tools
    }

    /// Helper to build a tool definition dict.
    private func buildTool(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required
                ]
            ]
        ]
    }

    // MARK: - Tool Execution

    /// Execute tool calls from Claude's response, return tool results to feed back.
    private func executeToolCalls(_ toolCalls: [ClaudeToolUseResponse.ClaudeToolCall], phase: ContentStep) async -> [WritingToolResult] {
        var results: [WritingToolResult] = []

        for call in toolCalls {
            // Track in tool chain steps
            let step = WritingToolChainStep(
                toolName: call.name,
                label: labelForTool(call.name),
                timestamp: Date(),
                status: .executing
            )
            toolChainSteps.append(step)

            // Emit started event for thinking UI
            onContextActivity?(.started(name: call.name, displayLabel: labelForTool(call.name), args: [:]))

            let resultContent: String
            let isError: Bool

            do {
                switch call.name {
                case "think":
                    let thought = (call.input["thought"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if thought.isEmpty {
                        resultContent = "Error: thought content is empty. Proceed with a concrete tool (write_draft, update_outline, etc.) or provide your final text response."
                        isError = true
                    } else {
                        resultContent = handleThink(call.input)
                        isError = false
                    }

                case "set_title":
                    resultContent = await handleSetTitle(call.input)
                    isError = false

                case "update_outline":
                    resultContent = await handleUpdateOutline(call.input)
                    isError = false

                case "add_hooks":
                    resultContent = await handleAddHooks(call.input)
                    isError = false

                case "set_description":
                    resultContent = await handleSetDescription(call.input)
                    isError = false

                case "write_draft":
                    resultContent = await handleWriteDraft(call.input)
                    isError = false

                case "edit_section":
                    resultContent = await handleEditSection(call.input)
                    isError = false

                case "search_swipes":
                    resultContent = await handleSearchSwipes(call.input)
                    isError = false

                case "search_connections":
                    resultContent = await handleSearchConnections(call.input)
                    isError = false

                case "read_draft":
                    resultContent = handleReadDraft()
                    isError = false

                case "get_client_profile":
                    resultContent = await handleGetClientProfile(call.input)
                    isError = false

                case "list_client_posts":
                    resultContent = handleListClientPosts()
                    isError = false

                case "read_client_post":
                    resultContent = await handleReadClientPost(call.input)
                    isError = false

                case "read_swipe_body":
                    resultContent = await handleReadSwipeBody(call.input)
                    isError = false

                case "analyze_swipe_patterns":
                    resultContent = handleAnalyzeSwipePatterns(call.input)
                    isError = false

                default:
                    resultContent = "Unknown tool: \(call.name)"
                    isError = true
                }
            } catch {
                resultContent = "Tool error: \(error.localizedDescription)"
                isError = true
            }

            // Update step status
            if let idx = toolChainSteps.lastIndex(where: { $0.toolName == call.name }) {
                toolChainSteps[idx].status = isError ? .failed : .completed
            }

            // Emit completed event for thinking UI
            let preview = isError ? "Error" : String(resultContent.prefix(80))
            onContextActivity?(.completed(name: call.name, displayLabel: labelForTool(call.name), resultPreview: preview))

            results.append(WritingToolResult(
                toolCallId: call.id,
                content: resultContent,
                isError: isError
            ))
        }

        // Emit allDone after all tool calls complete
        if !results.isEmpty {
            onContextActivity?(.allDone(totalCalls: results.count))
        }

        return results
    }

    // MARK: - Tool Handlers

    private func handleThink(_ input: [String: Any]) -> String {
        let thought = input["thought"] as? String ?? ""
        print("UnifiedWritingEngine [think]: \(thought.prefix(200))")

        // Dynamically update the tool chain step label based on what the AI is analyzing.
        // This shows the user what the AI is actually reading/doing.
        let thoughtLower = thought.lowercased()
        let detectedLabel: String?
        if thoughtLower.contains("swipe") || thoughtLower.contains("example") || thoughtLower.contains("reference") {
            detectedLabel = "Analyzing swipe library..."
        } else if thoughtLower.contains("profile") || thoughtLower.contains("voice") || thoughtLower.contains("brand") || thoughtLower.contains("client") {
            detectedLabel = "Reading content profile..."
        } else if thoughtLower.contains("constraint") || thoughtLower.contains("platform") || thoughtLower.contains("format") {
            detectedLabel = "Checking platform constraints..."
        } else if thoughtLower.contains("hook") || thoughtLower.contains("opening") {
            detectedLabel = "Evaluating hook patterns..."
        } else if thoughtLower.contains("outline") || thoughtLower.contains("structure") || thoughtLower.contains("beat") {
            detectedLabel = "Planning content structure..."
        } else if thoughtLower.contains("failure") || thoughtLower.contains("avoid") || thoughtLower.contains("rule") {
            detectedLabel = "Checking failure rules..."
        } else if thoughtLower.contains("top perform") || thoughtLower.contains("best post") || thoughtLower.contains("high perform") {
            detectedLabel = "Reviewing top-performing posts..."
        } else {
            detectedLabel = nil
        }

        if let label = detectedLabel,
           let idx = toolChainSteps.lastIndex(where: { $0.toolName == "think" && $0.status == .executing }) {
            toolChainSteps[idx].label = label
        }

        return "Thinking noted."
    }

    private func handleUpdateOutline(_ input: [String: Any]) async -> String {
        guard let sectionsArray = input["sections"] as? [[String: Any]] else {
            return "Error: missing sections array"
        }
        let reasoning = input["reasoning"] as? String ?? ""

        // Post notification to update ContentFocusModeState outline
        var outlineItems: [OutlineItem] = []
        for (i, section) in sectionsArray.enumerated() {
            let beatLabel = section["beatLabel"] as? String ?? "Uncategorized"
            let title = section["title"] as? String ?? ""
            let description = section["description"] as? String ?? ""
            let seconds = section["estimatedSeconds"] as? Int
            let notes = section["notes"] as? String ?? ""
            let fullReasoning = description + (notes.isEmpty ? "" : "\n\(notes)")

            outlineItems.append(OutlineItem(
                title: "[\(beatLabel)] \(title)",
                reasoning: fullReasoning,
                estimatedSeconds: seconds,
                sortOrder: i
            ))
        }

        // Post notification for the view model to pick up — scoped by contentUUID so
        // a concurrent session's open editor can't absorb another content's outline.
        NotificationCenter.default.post(
            name: .unifiedEngineOutlineUpdate,
            object: nil,
            userInfo: [
                "items": outlineItems,
                "reasoning": reasoning,
                "contentUUID": contentAtom?.uuid ?? ""
            ]
        )

        // Persist outline directly to atom metadata in GRDB
        // This is critical for the agent/Telegram path where no UI observer exists.
        // IMPORTANT: persist the encoded OutlineItems (id/sortOrder included) — the raw
        // tool sections lacked both, so the UI's decoder silently failed and the next
        // focus-mode save deleted the outline key.
        if let atomUUID = contentAtom?.uuid {
            do {
                let outlineData = try JSONEncoder().encode(outlineItems)
                let outlineJSON = try JSONSerialization.jsonObject(with: outlineData)
                guard var atom = try await AtomRepository.shared.fetch(uuid: atomUUID) else {
                    return "Error: content atom not found for outline persistence"
                }
                var meta = atom.metadataDict ?? [:]
                meta["outline"] = outlineJSON
                if let metaData = try? JSONSerialization.data(withJSONObject: meta),
                   let metaStr = String(data: metaData, encoding: .utf8) {
                    atom.metadata = metaStr
                }
                // Route through the repository so the write bumps the optimistic-lock
                // version, sets _local_pending, and is tracked for sync (the old raw
                // atom.update(db) was invisible to both).
                contentAtom = try await AtomRepository.shared.update(atom)
                print("💾 [UnifiedWritingEngine] Persisted outline (\(outlineItems.count) sections) to atom \(atomUUID)")
            } catch {
                print("❌ [UnifiedWritingEngine] Failed to persist outline: \(error)")
                PersistenceHealth.note(.writeFailure, context: "UnifiedWritingEngine.handleUpdateOutline(\(atomUUID.prefix(8)))", detail: error.localizedDescription)
            }
        }

        return "Outline updated with \(outlineItems.count) sections. Reasoning: \(reasoning)"
    }

    private func handleAddHooks(_ input: [String: Any]) async -> String {
        guard let hooksArray = input["hooks"] as? [[String: Any]] else {
            return "Error: missing hooks array"
        }

        var hookTexts: [String] = []
        var hookVariants: [HookVariant] = []

        for hook in hooksArray {
            let text = hook["text"] as? String ?? ""
            let hookType = hook["hookType"] as? String ?? ""
            let score = hook["estimatedScore"] as? Double ?? 0
            let reasoning = hook["reasoning"] as? String ?? ""

            hookTexts.append(text)
            hookVariants.append(HookVariant(
                text: text,
                hookType: hookType,
                estimatedScore: score,
                reasoning: reasoning
            ))
        }

        NotificationCenter.default.post(
            name: .unifiedEngineHooksUpdate,
            object: nil,
            userInfo: [
                "hooks": hookTexts,
                "variants": hookVariants,
                "contentUUID": contentAtom?.uuid ?? ""
            ]
        )

        // Persist hooks directly to atom metadata in GRDB
        // This is critical for the agent/Telegram path where no UI observer exists
        if let atomUUID = contentAtom?.uuid {
            do {
                guard var atom = try await AtomRepository.shared.fetch(uuid: atomUUID) else {
                    return "Error: content atom not found for hooks persistence"
                }
                var meta = atom.metadataDict ?? [:]
                meta["hooks"] = hookTexts
                if let metaData = try? JSONSerialization.data(withJSONObject: meta),
                   let metaStr = String(data: metaData, encoding: .utf8) {
                    atom.metadata = metaStr
                }
                // Repository update: version bump + _local_pending + sync tracking.
                contentAtom = try await AtomRepository.shared.update(atom)
                print("💾 [UnifiedWritingEngine] Persisted \(hookTexts.count) hooks to atom \(atomUUID)")
            } catch {
                print("❌ [UnifiedWritingEngine] Failed to persist hooks: \(error)")
                PersistenceHealth.note(.writeFailure, context: "UnifiedWritingEngine.handleAddHooks(\(atomUUID.prefix(8)))", detail: error.localizedDescription)
            }
        }

        return "Added \(hookTexts.count) hook variants."
    }

    private func handleSetTitle(_ input: [String: Any]) async -> String {
        let title = input["title"] as? String ?? ""
        guard !title.isEmpty else { return "Error: title is empty." }

        // Persist title to atom in GRDB
        if let atomUUID = contentAtom?.uuid {
            do {
                // Repository update: version bump + _local_pending + sync tracking.
                contentAtom = try await AtomRepository.shared.update(uuid: atomUUID) { atom in
                    atom.title = title
                } ?? contentAtom
                print("💾 [UnifiedWritingEngine] Set title to '\(title)' on atom \(atomUUID)")
            } catch {
                print("❌ [UnifiedWritingEngine] Failed to set title: \(error)")
                PersistenceHealth.note(.writeFailure, context: "UnifiedWritingEngine.handleSetTitle(\(atomUUID.prefix(8)))", detail: error.localizedDescription)
                return "Error setting title: \(error.localizedDescription)"
            }
        }

        // Notify UI to refresh
        NotificationCenter.default.post(
            name: .unifiedEngineTitleUpdate,
            object: nil,
            userInfo: ["title": title, "contentUUID": contentAtom?.uuid ?? ""]
        )

        return "Title set to: \(title)"
    }

    private func handleSetDescription(_ input: [String: Any]) async -> String {
        let description = input["description"] as? String ?? ""

        NotificationCenter.default.post(
            name: .unifiedEngineDescriptionUpdate,
            object: nil,
            userInfo: ["description": description, "contentUUID": contentAtom?.uuid ?? ""]
        )

        // Persist description to atom metadata in GRDB
        if let atomUUID = contentAtom?.uuid, !description.isEmpty {
            do {
                // Repository update: version bump + _local_pending + sync tracking.
                contentAtom = try await AtomRepository.shared.update(uuid: atomUUID) { atom in
                    var meta = atom.metadataDict ?? [:]
                    meta["contentDescription"] = description
                    if let metaData = try? JSONSerialization.data(withJSONObject: meta),
                       let metaStr = String(data: metaData, encoding: .utf8) {
                        atom.metadata = metaStr
                    }
                } ?? contentAtom
                print("💾 [UnifiedWritingEngine] Persisted description to atom \(atomUUID)")
            } catch {
                print("❌ [UnifiedWritingEngine] Failed to persist description: \(error)")
                PersistenceHealth.note(.writeFailure, context: "UnifiedWritingEngine.handleSetDescription(\(atomUUID.prefix(8)))", detail: error.localizedDescription)
            }
        }

        return "Content description set."
    }

    private func handleWriteDraft(_ input: [String: Any]) async -> String {
        let content = input["content"] as? String ?? ""
        let formatStr = input["format"] as? String ?? "plaintext"
        let format = WriteDraftParams.DraftFormat(rawValue: formatStr) ?? .plaintext

        // Validate draft content
        let validationResult = validateDraft(content, format: detectContentFormat())
        var validationNote = ""
        if case .needsCorrection(let violations) = validationResult.status {
            let violationText = violations.map(\.description).joined(separator: "\n")
            validationNote = "\nWARNING: Draft has constraint violations:\n\(violationText)\nPlease fix these issues."
        }

        // Self-evaluation
        var evalSummary = ""
        if let eval = input["selfEvaluation"] as? [String: Any] {
            let confidence = eval["confidenceScore"] as? Double ?? 0
            let voiceMatch = eval["voiceMatchScore"] as? Double ?? 0
            let weakAreas = eval["weakAreas"] as? [String] ?? []
            evalSummary = " (confidence: \(Int(confidence))%, voice: \(Int(voiceMatch))%, weak: \(weakAreas.joined(separator: ", ")))"
        }

        let wordCount = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count

        // Convert structured JSON (carousel slides, thread tweets) to clean plaintext
        // before storing and notifying. Strips internal fields like visualDirection.
        let renderedContent = AgentToolExecutor.renderDraftForDisplay(content)

        NotificationCenter.default.post(
            name: .unifiedEngineDraftUpdate,
            object: nil,
            userInfo: [
                "content": renderedContent,
                "format": format.rawValue,
                "contentUUID": contentAtom?.uuid ?? ""
            ]
        )

        // Persist draft content directly to atom body in GRDB
        // This is critical for the agent/Telegram path where no UI observer exists
        if let atomUUID = contentAtom?.uuid, !content.isEmpty {
            if AtomRepository.shared.isBeingEdited(atomUUID) {
                // The user has this content open in an editor. The scoped notification
                // above delivers the draft to that editor (which pushes an AI-undo
                // snapshot and persists through its own write path) — overwriting the
                // body here from underneath the open editor destroyed live keystrokes.
                print("✋ [UnifiedWritingEngine] Skipping direct body write for \(atomUUID) — editing lock held; draft delivered via scoped notification")
            } else {
                do {
                    guard var atom = try await AtomRepository.shared.fetch(uuid: atomUUID) else {
                        return "Error: content atom not found for draft persistence"
                    }

                    // Snapshot the previous draft as a versioned .contentDraft atom so
                    // an unwanted AI overwrite is always recoverable.
                    if let previousBody = atom.body,
                       !previousBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       previousBody != renderedContent {
                        do {
                            _ = try await ContentPipelineService().saveDraft(
                                contentUUID: atomUUID,
                                body: previousBody,
                                authorNotes: "Auto-snapshot before AI write_draft"
                            )
                        } catch {
                            print("⚠️ [UnifiedWritingEngine] Pre-write draft snapshot failed: \(error)")
                        }
                    }

                    atom.body = renderedContent

                    // Sync richDraftDocument in metadata so the UI sees the fresh draft.
                    // The UI prefers richDraftDocument over atom.body — without this,
                    // a stale rich document from a previous session overrides the fresh draft.
                    let richDoc = RichDocument.migrateLegacy(renderedContent)
                    atom.metadata = RichDocumentMetadataStorage.writeDocument(
                        richDoc,
                        into: atom.metadata,
                        key: RichDocumentMetadataKeys.contentDraftDocument
                    )

                    // Repository update: optimistic-lock version bump + _local_pending +
                    // sync tracking (the old raw atom.update(db) was invisible to both).
                    contentAtom = try await AtomRepository.shared.update(atom)
                    print("💾 [UnifiedWritingEngine] Persisted draft (\(wordCount) words) to atom \(atomUUID)")
                } catch {
                    print("❌ [UnifiedWritingEngine] Failed to persist draft: \(error)")
                    PersistenceHealth.note(.writeFailure, context: "UnifiedWritingEngine.handleWriteDraft(\(atomUUID.prefix(8)))", detail: error.localizedDescription)
                }
            }
        }

        // Voice verification — lightweight heuristic check against brand voice
        let voiceNote = verifyVoiceCompliance(draft: content)

        // Deterministic hard-rule compliance check (~50ms, no API call)
        var complianceNote = ""
        let contentMeta2 = contentAtom?.metadataValue(as: ContentAtomMetadata.self)
        let clientUUID2 = contentMeta2?.clientProfileUUID
        let policy = await TasteContext.resolveForWritingEngine(
            clientUUID: clientUUID2,
            intent: "draft",
            format: formatStr
        )
        // Run deterministic validators unconditionally — static validators don't need hard rules
        let violations = DeterministicWritingValidatorRunner.validate(
            draft: renderedContent,
            format: formatStr,
            hardRules: policy.hardRules
        )
        if let violationMessage = DeterministicWritingValidatorRunner.formatViolationMessage(violations) {
            complianceNote = "\n\n\(violationMessage)"
        }

        var result = "Draft written (\(wordCount) words, format: \(formatStr))\(evalSummary)\(validationNote)\(voiceNote)\(complianceNote)"

        return result
    }

    // MARK: - Voice Compliance Verification

    /// Lightweight heuristic voice check — scans draft sections for blacklisted phrases,
    /// generic AI-sounding openers, and divergence from brand voice keywords.
    /// Does NOT make LLM calls (too expensive per draft). Returns a note string to append
    /// to the tool result, or empty string if all sections pass.
    private func verifyVoiceCompliance(draft: String) -> String {
        guard let meta = clientMeta,
              let model = meta.intelligenceModel else { return "" }

        let voiceFP = model.voiceFingerprint
        let blacklisted = voiceFP.blacklistedPhrases
        let draftLower = draft.lowercased()

        var issues: [String] = []

        // Check blacklisted phrases from voice fingerprint
        for phrase in blacklisted where !phrase.isEmpty {
            let phraseLower = phrase.lowercased()
            if draftLower.contains(phraseLower) {
                issues.append("Blacklisted phrase detected: \"\(phrase)\"")
            }
        }

        // Check for common AI-sounding generic openers
        let genericOpeners = [
            "in today's world", "in today's fast-paced", "in the ever-evolving",
            "have you ever wondered", "are you tired of", "imagine this:",
            "picture this:", "in today's digital", "it's no secret that",
            "let's face it", "in today's competitive"
        ]
        for opener in genericOpeners {
            if draftLower.contains(opener) {
                issues.append("Generic AI opener detected: \"\(opener)\" — replace with a specific, voice-authentic hook")
            }
        }

        // Check for filler words that conflict with concise voice styles
        let fillerPhrases = [
            "it's worth noting that", "it goes without saying",
            "needless to say", "at the end of the day",
            "when all is said and done", "the fact of the matter is"
        ]
        for filler in fillerPhrases {
            if draftLower.contains(filler) {
                issues.append("Filler phrase: \"\(filler)\" — cut for conciseness")
            }
        }

        // Check sentence length against voice fingerprint (if avg is known)
        if voiceFP.avgSentenceLength > 0 {
            let sentences = draft.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !sentences.isEmpty {
                let avgWords = Double(sentences.reduce(0) { $0 + $1.split(separator: " ").count }) / Double(sentences.count)
                let targetAvg = voiceFP.avgSentenceLength
                // Flag if avg sentence length diverges by more than 50%
                if avgWords > targetAvg * 1.5 {
                    issues.append("Sentences averaging \(Int(avgWords)) words — client voice averages \(Int(targetAvg)). Consider shorter sentences.")
                } else if avgWords < targetAvg * 0.5 && targetAvg > 10 {
                    issues.append("Sentences averaging \(Int(avgWords)) words — client voice averages \(Int(targetAvg)). Consider more developed sentences.")
                }
            }
        }

        // Check signature phrase presence
        if !voiceFP.signaturePhrases.isEmpty {
            let found = voiceFP.signaturePhrases.filter { draftLower.contains($0.lowercased()) }
            if found.isEmpty {
                let examples = voiceFP.signaturePhrases.prefix(3).joined(separator: "\", \"")
                issues.append("No signature phrases detected. Client uses: \"\(examples)\" — weave at least one in naturally.")
            }
        }

        // Check banned AI verbs (from system prompt banned list)
        let bannedVerbs = ["delve", "dive deep", "unleash", "unlock", "game-changer",
                           "revolutionize", "supercharge", "harness", "leverage"]
        for verb in bannedVerbs {
            if draftLower.contains(verb) {
                issues.append("Banned AI word: \"\(verb)\" — replace with client's natural vocabulary")
            }
        }

        // Check contraction usage (natural voice uses contractions)
        let formalForms = ["cannot", "will not", "do not", "does not", "is not",
                           "are not", "would not", "should not", "could not", "have not"]
        let totalWords = draft.split(separator: " ").count
        if totalWords > 80 {
            let formalCount = formalForms.reduce(0) { count, form in
                count + draftLower.components(separatedBy: form).count - 1
            }
            if formalCount >= 3 {
                issues.append("Found \(formalCount) un-contracted forms (cannot, will not, etc.) — client voice uses contractions naturally. Use can't, won't, don't.")
            }
        }

        guard !issues.isEmpty else { return "" }

        let issueList = issues.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "\n\nVOICE COMPLIANCE CHECK (\(issues.count) issue\(issues.count == 1 ? "" : "s")):\n\(issueList)\nPlease address these voice issues in the draft."
    }

    private func handleEditSection(_ input: [String: Any]) async -> String {
        let sectionId = input["sectionIdentifier"] as? String ?? ""
        let newContent = input["newContent"] as? String ?? ""
        let reasoning = input["reasoning"] as? String ?? ""

        NotificationCenter.default.post(
            name: .unifiedEngineSectionEdit,
            object: nil,
            userInfo: [
                "sectionIdentifier": sectionId,
                "newContent": newContent,
                "reasoning": reasoning,
                "contentUUID": contentAtom?.uuid ?? ""
            ]
        )

        // Persist headless — the notification above only lands when a focus mode is
        // open. For Telegram/agent sessions there is no observer: the edit was lost
        // while the model reported success. Mirrors handleWriteDraft's safe path.
        if let atomUUID = contentAtom?.uuid, !newContent.isEmpty {
            if AtomRepository.shared.isBeingEdited(atomUUID) {
                // Open editor receives the scoped notification and persists it itself.
                print("✋ [UnifiedWritingEngine] Skipping headless section persist for \(atomUUID) — editing lock held")
            } else {
                do {
                    guard var atom = try await AtomRepository.shared.fetch(uuid: atomUUID) else {
                        return "Error: content atom not found for section edit persistence"
                    }
                    let currentBody = atom.body ?? ""

                    // Snapshot the previous draft before mutating (recoverable).
                    if !currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        do {
                            _ = try await ContentPipelineService().saveDraft(
                                contentUUID: atomUUID,
                                body: currentBody,
                                authorNotes: "Auto-snapshot before AI edit_section (\(sectionId))"
                            )
                        } catch {
                            print("⚠️ [UnifiedWritingEngine] Pre-edit draft snapshot failed: \(error)")
                        }
                    }

                    // Locator-scoped replacement of the identified section; fall back to
                    // whole-draft replacement only when the section can't be located
                    // (mirrors the UI handler's fallback semantics).
                    let updatedBody: String
                    if !sectionId.isEmpty,
                       let range = CosmoInlineDiffLocator.range(of: sectionId, in: currentBody) {
                        updatedBody = currentBody.replacingCharacters(in: range, with: newContent)
                    } else {
                        updatedBody = newContent
                    }

                    atom.body = updatedBody
                    let richDoc = RichDocument.migrateLegacy(updatedBody)
                    atom.metadata = RichDocumentMetadataStorage.writeDocument(
                        richDoc,
                        into: atom.metadata,
                        key: RichDocumentMetadataKeys.contentDraftDocument
                    )
                    contentAtom = try await AtomRepository.shared.update(atom)
                    print("💾 [UnifiedWritingEngine] Persisted section edit '\(sectionId)' to atom \(atomUUID)")
                } catch {
                    print("❌ [UnifiedWritingEngine] Failed to persist section edit: \(error)")
                    PersistenceHealth.note(.writeFailure, context: "UnifiedWritingEngine.handleEditSection(\(atomUUID.prefix(8)))", detail: error.localizedDescription)
                    return "Error persisting section edit: \(error.localizedDescription)"
                }
            }
        }

        return "Section '\(sectionId)' edited. Reasoning: \(reasoning)"
    }

    private func handleSearchSwipes(_ input: [String: Any]) async -> String {
        let query = input["query"] as? String ?? ""
        let formatFilter = input["format"] as? String
        let hookTypeFilter = input["hookType"] as? String
        let minScore = input["minScore"] as? Double

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: empty search query"
        }

        do {
            // Query atoms_fts directly — HybridSearchEngine uses semantic_fts which
            // doesn't index atom-based swipes (only legacy research table entries).
            let ftsQuery = query.split(separator: " ")
                .map { String($0).replacingOccurrences(of: "\"", with: "") }
                .filter { $0.count > 2 }
                .joined(separator: " OR ")

            guard !ftsQuery.isEmpty else {
                return "No matching swipes found for: \(query)"
            }

            let atoms: [Atom] = try await database.asyncRead { db in
                try Atom.fetchAll(db, sql: """
                    SELECT atoms.* FROM atoms
                    JOIN atoms_fts ON atoms.uuid = atoms_fts.uuid
                    WHERE atoms_fts MATCH ?
                      AND atoms.type = 'research'
                      AND atoms.is_deleted = 0
                    ORDER BY bm25(atoms_fts, 0, 0, 1, 2, 1)
                    LIMIT 20
                    """, arguments: [ftsQuery])
            }

            let allowedFormats = formatFilter.flatMap { WritingContentFormat.matchingSwipeFormats(for: $0) }
                ?? detectContentFormat().swipeFormatFamily
            var swipeResults: [String] = []
            for atom in atoms {
                guard atom.isSwipeFileAtom else { continue }

                let analysis = atom.swipeAnalysis
                guard let swipeFormat = analysis?.swipeContentFormat,
                      allowedFormats.contains(swipeFormat) else { continue }
                let hookScore = analysis?.hookScore ?? 0

                // Apply filters
                if let minScore = minScore, hookScore < minScore { continue }
                if let hookTypeFilter = hookTypeFilter, analysis?.hookType?.rawValue != hookTypeFilter { continue }

                let compressed = compressSwipe(atom)
                if let compressed = compressed {
                    swipeResults.append("UUID: \(compressed.id.uuidString)\n\(compressed.formatted())")
                }

                if swipeResults.count >= 5 { break }
            }

            if swipeResults.isEmpty {
                return "No matching swipes found for: \(query)"
            }

            return "Found \(swipeResults.count) matching swipes:\n\n" + swipeResults.joined(separator: "\n\n")
        } catch {
            return "Search error: \(error.localizedDescription)"
        }
    }

    private func handleGetClientProfile(_ input: [String: Any]) async -> String {
        let query = input["query"] as? String ?? ""

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: empty search query. Provide a client name to search for."
        }

        let queryLower = query.lowercased()

        // SHORT-CIRCUIT: If this client is already loaded, don't re-fetch.
        // The profile data is already in the system prompt (Block 2). The AI has
        // full access to the intelligence model, voice fingerprint, and top posts.
        if let currentMeta = clientMeta {
            let currentName = currentMeta.clientName.lowercased()
            if currentName.contains(queryLower) || queryLower.contains(currentName) {
                return "Client '\(currentMeta.clientName)' is already loaded in system context. Do not call get_client_profile again unless the user switches creators."
            }
        }

        // Fetch all client profile atoms
        let profiles: [Atom] = (try? await database.asyncRead { db in
            try Atom.filter(Column("type") == AtomType.clientProfile.rawValue)
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
        }) ?? []

        // Match by client name or handle
        var matches: [(atom: Atom, meta: ClientProfileMetadata)] = []
        for profile in profiles {
            if let meta = profile.metadataValue(as: ClientProfileMetadata.self) {
                let name = meta.clientName.lowercased()
                let handle = (meta.handle ?? "").lowercased()
                if name.contains(queryLower) || handle.contains(queryLower) || queryLower.contains(name) {
                    matches.append((atom: profile, meta: meta))
                }
            }
        }

        if matches.isEmpty {
            let available = profiles.compactMap { $0.metadataValue(as: ClientProfileMetadata.self)?.clientName }
            if available.isEmpty {
                return "No client profiles found in the system. The user needs to create a client profile first."
            }
            return "No client profile matching '\(query)'. Available profiles: \(available.joined(separator: ", "))"
        }

        guard let match = matches.first else {
            return "Client profile search returned empty results unexpectedly."
        }
        let profileAtom = match.atom
        let meta = match.meta

        // Update engine state — this profile will be used for the rest of the conversation
        self.clientProfileAtom = profileAtom
        self.clientMeta = meta
        self.cachedBlock2 = nil
        _ = assembleBlock2()
        await buildClientPostIndex(targetFormat: detectContentFormat())

        // Update loaded context info for UI transparency
        var info = self.loadedContext
        info.clientName = meta.clientName
        self.loadedContext = info

        print("🔧 [UnifiedWritingEngine] get_client_profile loaded: \(meta.clientName)")
        let documentCount = meta.documents?.count ?? 0
        return """
        Loaded client profile '\(meta.clientName)' into system context. \
        Intelligence model: \(meta.intelligenceModel != nil ? "yes" : "no"). \
        Client posts indexed: \(clientPostIndex.count). Uploaded documents: \(documentCount). \
        Do not call get_client_profile again unless the user switches creators.
        """
    }

    // MARK: - Reference Material Tool Handlers

    private func handleListClientPosts() -> String {
        guard !clientPostIndex.isEmpty else {
            return "No client posts available. Load a client profile first with get_client_profile."
        }

        let budgetUsed = referenceMaterialCharCount
        let budgetRemaining = referenceMaterialMaxChars - budgetUsed

        var lines: [String] = []
        lines.append("CLIENT POSTS (\(clientPostIndex.count) available) — Reference material budget: \(budgetRemaining) chars remaining")
        lines.append("")

        let sameFormat = clientPostIndex.filter { $0.format == "same_format" }
        let crossFormat = clientPostIndex.filter { $0.format == "cross_format" }
        let underperforming = clientPostIndex.filter { $0.format == "underperforming" }

        if !sameFormat.isEmpty {
            lines.append("SAME FORMAT (\(sameFormat.count)):")
            for post in sameFormat {
                let loaded = cachedReferenceMaterial["client_post:\(post.id.uuidString)"] != nil ? " [LOADED]" : ""
                lines.append("  ID: \(post.id.uuidString) | \"\(post.title)\" | \(post.engagement) | \(post.charCount) chars\(loaded)")
            }
            lines.append("")
        }

        if !crossFormat.isEmpty {
            lines.append("CROSS FORMAT (\(crossFormat.count)):")
            for post in crossFormat {
                let loaded = cachedReferenceMaterial["client_post:\(post.id.uuidString)"] != nil ? " [LOADED]" : ""
                lines.append("  ID: \(post.id.uuidString) | \"\(post.title)\" | \(post.engagement) | \(post.charCount) chars\(loaded)")
            }
            lines.append("")
        }

        if !underperforming.isEmpty {
            lines.append("UNDERPERFORMING (\(underperforming.count)) [study what NOT to do]:")
            for post in underperforming {
                let loaded = cachedReferenceMaterial["client_post:\(post.id.uuidString)"] != nil ? " [LOADED]" : ""
                lines.append("  ID: \(post.id.uuidString) | [UNDERPERFORMING] \"\(post.title)\" | \(post.engagement) | \(post.charCount) chars\(loaded)")
            }
            lines.append("")
        }

        lines.append("RECOMMENDATION: Load 4-5 same-format posts + 1-2 underperforming for voice reference.")
        lines.append("Use read_client_post with the post ID to read the full body text.")
        return lines.joined(separator: "\n")
    }

    private func handleReadClientPost(_ input: [String: Any]) async -> String {
        let postIdString = input["post_id"] as? String ?? ""
        guard let postId = UUID(uuidString: postIdString) else {
            return "Error: invalid post_id. Use list_client_posts to get valid IDs."
        }

        // Check if already loaded
        let cacheKey = "client_post:\(postId.uuidString)"
        if let cached = cachedReferenceMaterial[cacheKey] {
            return cached
        }

        // Find the document
        guard let meta = clientMeta, let documents = meta.documents else {
            return "Error: no client profile loaded."
        }
        guard let doc = documents.first(where: { $0.id == postId }) else {
            return "Error: no client post found with ID \(postIdString). Use list_client_posts to see available posts."
        }

        // Check budget
        let bodySize = doc.content.count
        if referenceMaterialCharCount + bodySize > referenceMaterialMaxChars {
            return "Error: reference material budget exceeded. Currently using \(referenceMaterialCharCount)/\(referenceMaterialMaxChars) chars. This post is \(bodySize) chars. Remove other material or skip this post."
        }

        // Cache it
        let engagement = formatEngagement(doc: doc)
        cachedReferenceMaterial[cacheKey] = """
        [CLIENT POST] "\(doc.title)" (\(doc.category.displayName))
        Engagement: \(engagement.isEmpty ? "N/A" : engagement)
        Full body text:
        \(doc.content)
        """

        print("🔧 [UnifiedWritingEngine] Loaded client post into reference material: \(doc.title) (\(bodySize) chars)")
        return cachedReferenceMaterial[cacheKey]!
    }

    private func handleReadSwipeBody(_ input: [String: Any]) async -> String {
        let swipeIdString = input["swipe_id"] as? String ?? ""
        guard let swipeUUID = UUID(uuidString: swipeIdString) else {
            return "Error: invalid swipe_id UUID format."
        }

        // Check if already loaded
        let cacheKey = "swipe:\(swipeUUID.uuidString)"
        if let cached = cachedReferenceMaterial[cacheKey] {
            return cached
        }

        // Fetch from database
        guard let atom = try? await database.asyncRead({ db in
            try Atom.filter(Column("uuid") == swipeUUID.uuidString).filter(Column("is_deleted") == false).fetchOne(db)
        }), let body = atom.body, !body.isEmpty else {
            return "Error: swipe not found or has no body text."
        }

        let title = atom.title ?? "Untitled"

        // Check budget
        if referenceMaterialCharCount + body.count > referenceMaterialMaxChars {
            return "Error: reference material budget exceeded. Currently using \(referenceMaterialCharCount)/\(referenceMaterialMaxChars) chars. This swipe body is \(body.count) chars."
        }

        // Cache it
        cachedReferenceMaterial[cacheKey] = """
        [SWIPE] "\(title)"
        Full body text:
        \(body)
        """

        print("🔧 [UnifiedWritingEngine] Loaded swipe body into reference material: \(title) (\(body.count) chars)")
        return cachedReferenceMaterial[cacheKey]!
    }

    /// Analyze patterns across all loaded swipe examples (WP4).
    private func handleAnalyzeSwipePatterns(_ input: [String: Any]) -> String {
        let focus = (input["focus"] as? String)?.lowercased() ?? "all"
        guard !selectedSwipes.isEmpty else {
            return "No swipe examples loaded. Use search_swipes to find relevant swipes first."
        }

        var analysis: [String] = ["=== SWIPE PATTERN ANALYSIS ==="]

        // Hook analysis
        if focus == "hooks" || focus == "all" {
            analysis.append("\n## HOOK ANALYSIS")
            let hookGroups = Dictionary(grouping: selectedSwipes, by: { $0.hookType })
            for (type, swipes) in hookGroups.sorted(by: { $0.value.map(\.hookScore).reduce(0, +) > $1.value.map(\.hookScore).reduce(0, +) }) {
                guard type != "Unknown" else { continue }
                let avg = swipes.map(\.hookScore).reduce(0, +) / Double(swipes.count)
                let best = swipes.max(by: { $0.hookScore < $1.hookScore })
                let bestTitle = best?.title ?? ""
                analysis.append("  \(type): avg \(String(format: "%.1f", avg))/10 (\(swipes.count) swipes)")
                if !bestTitle.isEmpty { analysis.append("    Best example: \"\(bestTitle)\" (\(String(format: "%.1f", best?.hookScore ?? 0))/10)") }
            }
        }

        // Persuasion analysis
        if focus == "persuasion" || focus == "all" {
            analysis.append("\n## PERSUASION TECHNIQUE ANALYSIS")
            var techCounts: [String: (count: Int, totalIntensity: Double)] = [:]
            for swipe in selectedSwipes {
                for technique in swipe.persuasionTechniques {
                    let name = technique.components(separatedBy: " (").first ?? technique
                    let intensityStr = technique.components(separatedBy: "(").last?.replacingOccurrences(of: ")", with: "") ?? "0.5"
                    let intensity = Double(intensityStr) ?? 0.5
                    let existing = techCounts[name] ?? (count: 0, totalIntensity: 0)
                    techCounts[name] = (count: existing.count + 1, totalIntensity: existing.totalIntensity + intensity)
                }
            }
            let sorted = techCounts.sorted { $0.value.count > $1.value.count }
            for (name, data) in sorted.prefix(8) {
                let avgIntensity = data.totalIntensity / Double(data.count)
                analysis.append("  \(name): \(data.count)/\(selectedSwipes.count) swipes, avg intensity \(String(format: "%.1f", avgIntensity))")
            }
            // Top combos
            let swipesWithTechniques = selectedSwipes.filter { !$0.persuasionTechniques.isEmpty }
            if swipesWithTechniques.count >= 3 {
                analysis.append("  Top combination pattern: \(sorted.prefix(3).map(\.key).joined(separator: " + "))")
            }
        }

        // Emotional arc analysis
        if focus == "emotional_arc" || focus == "all" {
            analysis.append("\n## EMOTIONAL ARC ANALYSIS")
            var arcPatterns: [String: Int] = [:]
            for swipe in selectedSwipes where !swipe.emotionalArc.isEmpty {
                let key = swipe.emotionalArc.prefix(4).joined(separator: " \u{2192} ")
                arcPatterns[key, default: 0] += 1
            }
            for (arc, count) in arcPatterns.sorted(by: { $0.value > $1.value }).prefix(5) {
                analysis.append("  \(arc) (\(count) swipes)")
            }
        }

        // Engagement analysis
        if focus == "engagement" || focus == "all" {
            analysis.append("\n## ENGAGEMENT ANALYSIS")
            let engagedSwipes = selectedSwipes.filter { $0.engagementRate > 0 }
            if engagedSwipes.isEmpty {
                analysis.append("  No engagement data available for loaded swipes.")
            } else {
                let sorted = engagedSwipes.sorted { $0.engagementRate > $1.engagementRate }
                let avg = sorted.map(\.engagementRate).reduce(0, +) / Double(sorted.count)
                analysis.append("  Avg engagement: \(String(format: "%.1f", avg))%")
                analysis.append("  Top 3 performers:")
                for swipe in sorted.prefix(3) {
                    analysis.append("    \"\(swipe.title)\" — \(String(format: "%.1f", swipe.engagementRate))% | \(swipe.hookType) hook | \(swipe.persuasionTechniques.prefix(2).joined(separator: ", "))")
                }
            }
        }

        return analysis.joined(separator: "\n")
    }

    private func handleSearchConnections(_ input: [String: Any]) async -> String {
        let query = input["query"] as? String ?? ""
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: empty search query"
        }

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 5,
                entityTypes: [.connection, .research]
            )

            let formatted = results.map { result in
                let title = result.title.isEmpty ? "Untitled" : result.title
                let excerpt = String(result.preview.prefix(300))
                return "**\(title)**\n\(excerpt)"
            }.joined(separator: "\n\n")

            return formatted.isEmpty ? "No relevant connections found." : "Found \(results.count) connections:\n\n\(formatted)"
        } catch {
            return "Search error: \(error.localizedDescription)"
        }
    }

    private func handleReadDraft() -> String {
        guard let atom = contentAtom,
              let focusState = ContentFocusModeState.from(atom: atom) else {
            return "No draft written yet."
        }
        let draft = focusState.draftContent
        if draft.isEmpty {
            return "No draft written yet."
        }
        return "Current draft (\(draft.count) characters):\n\n\(draft)"
    }

    // MARK: - Swipe Selection

    /// Select up to 10 same-type library swipe examples using 4-axis scoring:
    /// exact format match, structural fingerprint similarity, stylistic similarity, and performance score.
    /// The primary blueprint remains the structural anchor across the selected library set.
    private func selectSwipes(contentAtom: Atom) async {
        let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self)
        let targetWritingFormat = detectContentFormat()
        let contentFormat = targetWritingFormat.rawValue
        print("📊 [selectSwipes] Detected format: \(contentFormat) (\(targetWritingFormat.displayName)) for atom \(contentAtom.uuid) | explicitFormat: \(contentAtom.metadataDict?["explicitFormat"] as? String ?? "nil") | platform: \(metadata?.platform?.rawValue ?? "nil") | contentFormat meta: \(metadata?.contentFormat ?? "nil")")
        var candidates: [Atom] = []

        // Build set of primary swipe UUIDs (inherited from idea activation + source idea's linked swipes)
        var primarySwipeUUIDs = Set<String>()
        if let inherited = metadata?.inheritedSwipeUUIDs {
            primarySwipeUUIDs.formUnion(inherited)
        }
        if let sourceIdeaUUID = metadata?.sourceIdeaUUID {
            if let ideaAtom = try? await database.asyncRead({ db in
                try Atom.filter(Column("uuid") == sourceIdeaUUID).filter(Column("is_deleted") == false).fetchOne(db)
            }), let linkedIds = ideaAtom.ideaMetadata?.linkedSwipeIds {
                primarySwipeUUIDs.formUnion(linkedIds)

                for uuid in linkedIds.prefix(20) {
                    if let swipe = try? await database.asyncRead({ db in
                        try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db)
                    }) {
                        candidates.append(swipe)
                    }
                }
            }
        }

        // First: inherited swipes from idea activation
        if let swipeUUIDs = metadata?.inheritedSwipeUUIDs {
            for uuid in swipeUUIDs.prefix(20) {
                if let swipe = try? await database.asyncRead({ db in
                    try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db)
                }) {
                    candidates.append(swipe)
                }
            }
        }

        candidates = Self.uniqueSwipeAtoms(candidates)
        let sameTypeCandidates = Self.filterSameTypeLibrarySwipes(candidates, targetFormat: targetWritingFormat)
        let strictPrimarySwipeUUIDs = Set(
            sameTypeCandidates
                .filter { primarySwipeUUIDs.contains($0.uuid) }
                .map(\.uuid)
        )
        let excludedPrimaryCount = primarySwipeUUIDs.count - strictPrimarySwipeUUIDs.count
        if excludedPrimaryCount > 0 {
            print("⚠️ [UnifiedWritingEngine] Excluded \(excludedPrimaryCount) primary swipe(s) due to format mismatch for \(targetWritingFormat.displayName)")
        }

        // Second: search for more if needed
        if sameTypeCandidates.count < 20 {
            // Vary the query by appending a random body sentence to broaden results
            let baseQuery = contentAtom.title ?? contentAtom.body ?? ""
            let query: String
            if let body = contentAtom.body, let title = contentAtom.title,
               !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let sentences = body.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count > 10 }
                if !sentences.isEmpty {
                    query = title + " " + sentences[Int.random(in: 0..<sentences.count)]
                } else {
                    query = baseQuery
                }
            } else {
                query = baseQuery
            }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let existingUUIDs = Set(sameTypeCandidates.map(\.uuid))
                // Use direct FTS on atoms_fts — HybridSearchEngine queries semantic_fts
                // which does NOT index swipe atoms, causing 0 results for swipe backfill.
                let ftsResults = await searchSwipesFTS(query: query, limit: 40, excludeUUIDs: existingUUIDs)
                for atom in ftsResults {
                    guard targetWritingFormat.matchesSwipeAtom(atom) else { continue }
                    candidates.append(atom)
                    if candidates.count >= 50 { break }
                }
            }
        }

        candidates = Self.uniqueSwipeAtoms(candidates)
        let exactTypeCandidates = Self.filterSameTypeLibrarySwipes(candidates, targetFormat: targetWritingFormat)

        // Filter: accept swipes with ANY analysis (not just hookType).
        // Many valid swipes have analysis but hookType was not classified.
        let analyzed = exactTypeCandidates.filter { $0.swipeAnalysis != nil }
        let withHookType = analyzed.filter { $0.swipeAnalysis?.hookType != nil }
        let unanalyzed = exactTypeCandidates.filter { $0.swipeAnalysis == nil }
        let targetSwipeCount = 20
        print("📊 [selectSwipes] inherited=\(sameTypeCandidates.count), total candidates=\(candidates.count), exactType=\(exactTypeCandidates.count), analyzed=\(analyzed.count) (hookType=\(withHookType.count)), unanalyzed=\(unanalyzed.count)")

        // If we have very few analyzed swipes, supplement with unanalyzed ones
        let scoringPool: [Atom]
        if analyzed.count >= 5 {
            scoringPool = analyzed
        } else {
            scoringPool = analyzed + unanalyzed
            print("📊 [selectSwipes] Pool supplemented with \(unanalyzed.count) unanalyzed swipes")
        }

        guard !scoringPool.isEmpty else {
            // Same-type-only fallback when we have no analyzed matches.
            selectedSwipes = await selectSwipesFallback(
                contentAtom: contentAtom,
                targetFormat: targetWritingFormat,
                needed: targetSwipeCount,
                existingUUIDs: Set()
            )
            promotePrimaryBlueprintIfNeeded(preferredUUIDs: strictPrimarySwipeUUIDs)
            if selectedSwipes.count < targetSwipeCount {
                print("⚠️ [UnifiedWritingEngine] Same-type swipe shortfall: loaded \(selectedSwipes.count)/\(targetSwipeCount) for \(targetWritingFormat.displayName)")
            }
            await buildClientPostIndex(targetFormat: targetWritingFormat)
            return
        }

        // Pre-fetch top patterns for this content format
        let topPatterns = await BeatPatternService.shared.findTopPatterns(format: contentFormat, limit: 10)
        let topFingerprints = Set(topPatterns.map(\.fingerprint))

        var scored: [(atom: Atom, finalScore: Double, hookType: String)] = []

        for atom in scoringPool {
            let analysis = atom.swipeAnalysis  // May be nil for unanalyzed swipes

            // Axis 1: Exact type match
            var formatScore = 0.0
            if let swipeFormat = analysis?.swipeContentFormat {
                formatScore = targetWritingFormat.matchesSwipeFormat(swipeFormat) ? 1.0 : 0.0
            }

            // Axis 2: Structural score via BeatPatternService (0.0-1.0)
            var structuralScore = 0.3
            if let fp = analysis?.beatFingerprint, !fp.isEmpty {
                structuralScore = topFingerprints.contains(fp) ? 1.0 : 0.3
            }

            // Axis 3: Stylistic score (0.0-1.0)
            let transcript = atom.body ?? ""
            let stylisticScore = computeStylisticScore(swipeTranscript: transcript, clientProfile: clientMeta)

            // Axis 4: Performance score (normalized 0.0-1.0)
            let perfScore = min((analysis?.hookScore ?? 0.0) / 10.0, 1.0)

            // Weighted fusion — unanalyzed swipes get baseline 0.3 format score
            var finalScore = 0.3 * (analysis != nil ? formatScore : 0.3) + 0.25 * structuralScore + 0.2 * stylisticScore + 0.25 * perfScore

            // Priority boost for primary swipes (inherited from idea activation or linked by user)
            if strictPrimarySwipeUUIDs.contains(atom.uuid) {
                finalScore += 0.5
            }

            let hookType = analysis?.hookType?.rawValue ?? "unknown"

            scored.append((atom: atom, finalScore: finalScore, hookType: hookType))
        }

        // Weighted random sampling — higher scores are more likely but not guaranteed,
        // so different swipes surface each session while still favoring quality.
        var selected: [Atom] = []
        var selectedHookTypes = Set<String>()
        var usedFingerprints: Set<String> = []
        var selectedUUIDs = Set<String>()

        // Always pick primary swipes first (inherited from idea/user-linked)
        for entry in scored where strictPrimarySwipeUUIDs.contains(entry.atom.uuid) {
            selected.append(entry.atom)
            selectedUUIDs.insert(entry.atom.uuid)
            selectedHookTypes.insert(entry.hookType)
            usedFingerprints.insert(entry.atom.swipeAnalysis?.beatFingerprint ?? UUID().uuidString)
        }

        // Build pool excluding already-selected primaries
        var pool = scored.filter { !selectedUUIDs.contains($0.atom.uuid) }

        while selected.count < targetSwipeCount && !pool.isEmpty {
            // Square scores to widen gap between good and mediocre
            let weights = pool.map { max($0.finalScore * $0.finalScore, 0.01) }
            let totalWeight = weights.reduce(0, +)
            let roll = Double.random(in: 0..<totalWeight)

            var cumulative = 0.0
            var pickedIndex = 0
            for (i, w) in weights.enumerated() {
                cumulative += w
                if roll < cumulative {
                    pickedIndex = i
                    break
                }
            }

            let pick = pool[pickedIndex]
            let fp = pick.atom.swipeAnalysis?.beatFingerprint ?? UUID().uuidString

            // Skip duplicate fingerprints for diversity, but accept if pool is exhausted
            if usedFingerprints.contains(fp) && pool.count > 1 {
                pool.remove(at: pickedIndex)
                continue
            }

            selected.append(pick.atom)
            selectedUUIDs.insert(pick.atom.uuid)
            selectedHookTypes.insert(pick.hookType)
            usedFingerprints.insert(fp)
            pool.remove(at: pickedIndex)
        }

        // If below target, backfill with same-type fallback swipes only.
        if selected.count < targetSwipeCount {
            let existingUUIDs = Set(selected.map(\.uuid))
            let fallbacks = await selectSwipesFallback(
                contentAtom: contentAtom,
                targetFormat: targetWritingFormat,
                needed: targetSwipeCount - selected.count,
                existingUUIDs: existingUUIDs
            )
            selectedSwipes = selected.compactMap { atom in
                guard var compressed = compressSwipe(atom) else { return nil }
                if strictPrimarySwipeUUIDs.contains(atom.uuid) {
                    compressed.isPrimary = true
                }
                return compressed
            }
            selectedSwipes.append(contentsOf: fallbacks)
        } else {
            selectedSwipes = selected.compactMap { atom in
                guard var compressed = compressSwipe(atom) else { return nil }
                if strictPrimarySwipeUUIDs.contains(atom.uuid) {
                    compressed.isPrimary = true
                }
                return compressed
            }
        }

        promotePrimaryBlueprintIfNeeded(preferredUUIDs: strictPrimarySwipeUUIDs)
        if selectedSwipes.count < targetSwipeCount {
            print("⚠️ [UnifiedWritingEngine] Same-type swipe shortfall: loaded \(selectedSwipes.count)/\(targetSwipeCount) for \(targetWritingFormat.displayName)")
        } else {
            print("🔧 [UnifiedWritingEngine] Loaded \(selectedSwipes.count) same-type library swipes for \(targetWritingFormat.displayName)")
        }

        // Build metadata-only client post index (bodies loaded on demand via tools)
        await buildClientPostIndex(targetFormat: targetWritingFormat)
    }

    /// Same-type fallback search when scored selection does not fill the target set.
    /// Uses direct FTS on atoms_fts and includes same-type library swipes,
    /// even if they lack hookType analysis (compressSwipeMinimal handles those).
    private func selectSwipesFallback(
        contentAtom: Atom,
        targetFormat: WritingContentFormat,
        needed: Int,
        existingUUIDs: Set<String>
    ) async -> [CompressedSwipe] {
        guard needed > 0 else { return [] }

        var fallbackSwipes: [CompressedSwipe] = []
        var seenUUIDs = existingUUIDs
        var queries: [String] = targetFormat.swipeSearchTerms
        let topicQuery = contentAtom.title ?? contentAtom.body ?? ""
        if !topicQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queries.insert(topicQuery, at: 0)
        }

        for query in queries where fallbackSwipes.count < needed {
            // Use direct FTS on atoms_fts — HybridSearchEngine queries semantic_fts
            // which does NOT index swipe atoms.
            let ftsResults = await searchSwipesFTS(query: query, limit: 25, excludeUUIDs: seenUUIDs)
            for atom in ftsResults {
                guard fallbackSwipes.count < needed else { break }
                guard targetFormat.matchesSwipeAtom(atom) else { continue }
                // Use compressSwipe first, fall back to minimal for un-analyzed swipes
                guard var compressed = compressSwipe(atom) ?? compressSwipeMinimal(atom) else { continue }

                seenUUIDs.insert(atom.uuid)
                if !fallbackSwipes.isEmpty {
                    compressed.isPrimary = false
                }
                fallbackSwipes.append(compressed)
            }
        }

        print("🔧 [UnifiedWritingEngine] Same-type fallback found \(fallbackSwipes.count) additional swipes for format '\(targetFormat.displayName)'")
        return fallbackSwipes
    }

    // MARK: - Direct FTS Swipe Search

    /// Search swipe atoms via atoms_fts (NOT semantic_fts which doesn't index swipe atoms).
    /// Reuses the proven BM25 pattern from handleSearchSwipes.
    private func searchSwipesFTS(query: String, limit: Int, excludeUUIDs: Set<String> = []) async -> [Atom] {
        let ftsQuery = query.split(separator: " ")
            .map { word in
                var w = String(word)
                for ch in ["\"", "*", "(", ")", "{", "}", "^", "~"] {
                    w = w.replacingOccurrences(of: ch, with: "")
                }
                return w
            }
            .filter { $0.count > 2 }
            .joined(separator: " OR ")

        guard !ftsQuery.isEmpty else { return [] }

        do {
            let atoms: [Atom] = try await database.asyncRead { db in
                try Atom.fetchAll(db, sql: """
                    SELECT atoms.* FROM atoms
                    JOIN atoms_fts ON atoms.uuid = atoms_fts.uuid
                    WHERE atoms_fts MATCH ?
                      AND atoms.type = 'research'
                      AND atoms.is_deleted = 0
                    ORDER BY bm25(atoms_fts, 0, 0, 1, 2, 1)
                    LIMIT ?
                    """, arguments: [ftsQuery, limit])
            }
            return atoms.filter { $0.isSwipeFileAtom && !excludeUUIDs.contains($0.uuid) }
        } catch {
            print("⚠️ [UnifiedWritingEngine] searchSwipesFTS error: \(error.localizedDescription)")
            return []
        }
    }

    nonisolated static func filterSameTypeLibrarySwipes(
        _ atoms: [Atom],
        targetFormat: WritingContentFormat
    ) -> [Atom] {
        atoms.filter { atom in
            guard atom.isSwipeFileAtom else { return false }
            return targetFormat.matchesSwipeAtom(atom)
        }
    }

    nonisolated private static func uniqueSwipeAtoms(_ atoms: [Atom]) -> [Atom] {
        var seen = Set<String>()
        var unique: [Atom] = []
        for atom in atoms where !seen.contains(atom.uuid) {
            seen.insert(atom.uuid)
            unique.append(atom)
        }
        return unique
    }

    private func promotePrimaryBlueprintIfNeeded(preferredUUIDs: Set<String>) {
        if let preferredIndex = selectedSwipes.firstIndex(where: { preferredUUIDs.contains($0.id.uuidString) }) {
            for idx in selectedSwipes.indices {
                selectedSwipes[idx].isPrimary = (idx == preferredIndex)
            }
            return
        }

        guard !selectedSwipes.isEmpty else { return }
        for idx in selectedSwipes.indices {
            selectedSwipes[idx].isPrimary = (idx == 0)
        }
    }

    /// C2: Load client's top-performing posts in the target format and append as client examples.
    /// Cap at 5 same-format posts and 2 other-format posts.
    private func appendClientTopPosts(targetFormat: WritingContentFormat) async {
        guard let profileAtom = clientProfileAtom,
              let meta = clientMeta,
              meta.documents != nil else { return }

        // Determine which ProfileDocumentCategory matches the target format
        let targetCategory: ProfileDocumentCategory = targetFormat.isVideoFormat ? .reel : .thread

        // Load same-format top posts
        let sameFormatTranscripts = ClientIntelligenceEngine.shared.getTopTranscripts(
            profile: profileAtom,
            count: 8,
            category: targetCategory
        )

        // Load other-format top posts (for cross-pollination)
        let otherCategory: ProfileDocumentCategory = targetCategory == .reel ? .thread : .reel
        let otherFormatTranscripts = ClientIntelligenceEngine.shared.getTopTranscripts(
            profile: profileAtom,
            count: 2,
            category: otherCategory
        )

        // Get documents for titles and engagement metadata
        let documents = meta.documents ?? []
        let sameFormatDocs = documents.filter { $0.category == targetCategory }
        let otherFormatDocs = documents.filter { $0.category == otherCategory }

        // Build CompressedSwipe entries for same-format client posts
        for (i, transcript) in sameFormatTranscripts.enumerated() {
            let doc = i < sameFormatDocs.count ? sameFormatDocs[i] : nil
            let title = doc?.title ?? "Client \(targetCategory.displayName) #\(i + 1)"
            let engagement = formatEngagement(doc: doc)

            selectedSwipes.append(CompressedSwipe(
                id: UUID(),
                title: title,
                hookText: String(transcript.prefix(200)),
                hookType: "Client",
                hookScore: 0,
                beatSequence: [],
                keyTransitions: [],
                ctaText: "",
                framework: "Client Original",
                format: targetCategory.displayName,
                isClientExample: true,
                engagementSummary: engagement,
                fullBodyExcerpt: String(transcript.prefix(2000))
            ))
        }

        // Build CompressedSwipe entries for other-format client posts
        for (i, transcript) in otherFormatTranscripts.enumerated() {
            let doc = i < otherFormatDocs.count ? otherFormatDocs[i] : nil
            let title = doc?.title ?? "Client \(otherCategory.displayName) #\(i + 1)"
            let engagement = formatEngagement(doc: doc)

            selectedSwipes.append(CompressedSwipe(
                id: UUID(),
                title: title,
                hookText: String(transcript.prefix(200)),
                hookType: "Client",
                hookScore: 0,
                beatSequence: [],
                keyTransitions: [],
                ctaText: "",
                framework: "Client Original",
                format: otherCategory.displayName,
                isClientExample: true,
                engagementSummary: engagement,
                fullBodyExcerpt: String(transcript.prefix(1500))
            ))
        }

        let clientPostCount = sameFormatTranscripts.count + otherFormatTranscripts.count
        if clientPostCount > 0 {
            print("🔧 [UnifiedWritingEngine] Appended \(clientPostCount) client top posts (\(sameFormatTranscripts.count) same-format, \(otherFormatTranscripts.count) other-format)")
        }
    }

    /// Build metadata-only index of client posts — no body text stored.
    /// Includes ALL categories (reels, threads, underperforming) so the AI can choose "what not to do" examples.
    private func buildClientPostIndex(targetFormat: WritingContentFormat) async {
        guard let meta = clientMeta, let documents = meta.documents else {
            clientPostIndex = []
            return
        }
        let targetCategory: ProfileDocumentCategory = targetFormat.isVideoFormat ? .reel : .thread
        // Only index top-performing content posts — skip brand story, voice guide, underperforming
        let topPerformerCategories: Set<ProfileDocumentCategory> = [.reel, .thread]
        var sameFormatIndex: [(id: UUID, title: String, category: String, engagement: String, charCount: Int, format: String)] = []
        var crossFormatIndex: [(id: UUID, title: String, category: String, engagement: String, charCount: Int, format: String)] = []
        for doc in documents where topPerformerCategories.contains(doc.category) {
            let entry = (id: doc.id, title: doc.title, category: doc.category.displayName,
                         engagement: formatEngagement(doc: doc), charCount: doc.content.count,
                         format: doc.category == targetCategory ? "same_format" : "cross_format")
            if doc.category == targetCategory {
                sameFormatIndex.append(entry)
            } else {
                crossFormatIndex.append(entry)
            }
        }
        // All same-format, cap cross-format at 3
        clientPostIndex = sameFormatIndex + Array(crossFormatIndex.prefix(3))
        print("🔧 [UnifiedWritingEngine] Built client post index: \(clientPostIndex.count) posts (\(sameFormatIndex.count) same-format, \(min(crossFormatIndex.count, 3)) cross-format)")
    }

    /// Auto-load the primary (blueprint) swipe body into reference material so it's always available.

    /// Format engagement metrics from a ProfileDocument into a human-readable string.
    private func formatEngagement(doc: ProfileDocument?) -> String {
        guard let doc = doc else { return "" }
        var parts: [String] = []
        if let likes = doc.likes, likes > 0 { parts.append(formatMetric(likes, "likes")) }
        if let shares = doc.shares, shares > 0 { parts.append(formatMetric(shares, "shares")) }
        if let saves = doc.saves, saves > 0 { parts.append(formatMetric(saves, "saves")) }
        if let comments = doc.comments, comments > 0 { parts.append(formatMetric(comments, "comments")) }
        if let leads = doc.leads, leads > 0 { parts.append(formatMetric(leads, "leads")) }
        return parts.joined(separator: ", ")
    }

    /// Format a number with K/M suffix for readability.
    private func formatMetric(_ value: Int, _ label: String) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM %@", Double(value) / 1_000_000.0, label)
        } else if value >= 1_000 {
            return String(format: "%.1fK %@", Double(value) / 1_000.0, label)
        } else {
            return "\(value) \(label)"
        }
    }

    /// Compute stylistic similarity score between a swipe transcript and the client profile.
    private func computeStylisticScore(swipeTranscript: String, clientProfile: ClientProfileMetadata?) -> Double {
        guard clientProfile != nil, !swipeTranscript.isEmpty else { return 0.5 }

        let swipeSentences = swipeTranscript.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let avgSwipeSentenceLen = swipeSentences.isEmpty ? 0
            : swipeSentences.map { $0.split(separator: " ").count }.reduce(0, +) / swipeSentences.count

        let swipeWords = swipeTranscript.split(separator: " ")
        let avgWordLen = swipeWords.isEmpty ? 0
            : swipeWords.map { $0.count }.reduce(0, +) / swipeWords.count

        var score = 0.5
        if avgSwipeSentenceLen >= 5 && avgSwipeSentenceLen <= 15 { score += 0.25 }
        if avgWordLen >= 3 && avgWordLen <= 7 { score += 0.25 }

        return min(score, 1.0)
    }

    /// Compress a swipe atom into a ~200 token summary.
    private func compressSwipe(_ atom: Atom) -> CompressedSwipe? {
        guard let analysis = atom.swipeAnalysis else { return nil }

        let body = atom.body ?? ""
        let sentences = body.components(separatedBy: ". ")

        // Hook: full hook text (formatted() will truncate for non-primary swipes)
        let hookText = analysis.hookText ?? sentences.prefix(4).joined(separator: ". ")

        // Beat sequence
        let beats: [String]
        if let fp = analysis.beatFingerprint {
            beats = fp.components(separatedBy: ">")
        } else if let sections = analysis.sections {
            beats = sections.map(\.label)
        } else {
            beats = []
        }

        // Key transitions: first sentence of each non-hook section
        var transitions: [String] = []
        if let sections = analysis.sections {
            for section in sections.dropFirst() {
                let sectionText = section.purpose.isEmpty ? section.label : section.purpose
                let firstSentence = sectionText.components(separatedBy: ". ").first ?? sectionText
                transitions.append(String(firstSentence.prefix(100)))
            }
        }

        // CTA: last paragraph
        let paragraphs = body.components(separatedBy: "\n\n")
        let ctaText = paragraphs.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Persuasion techniques with intensity
        let persuasionLabels: [String] = (analysis.persuasionTechniques ?? [])
            .sorted { $0.intensity > $1.intensity }
            .prefix(5)
            .map { "\($0.type.displayName) (\(String(format: "%.1f", $0.intensity)))" }

        // Emotional arc progression
        let arcLabels: [String] = (analysis.emotionalArc ?? [])
            .prefix(6)
            .map { $0.emotion.displayName }

        // Engagement summary
        var engSummary = ""
        var parts: [String] = []
        if let views = analysis.viewsCount, views > 0 { parts.append(Self.formatCount(views) + " views") }
        if let likes = analysis.likesCount, likes > 0 { parts.append(Self.formatCount(likes) + " likes") }
        if let comments = analysis.commentsCount, comments > 0 { parts.append(Self.formatCount(comments) + " comments") }
        engSummary = parts.joined(separator: ", ")

        var swipe = CompressedSwipe(
            id: UUID(uuidString: atom.uuid) ?? UUID(),
            title: atom.title ?? "Untitled",
            hookText: String(hookText.prefix(500)),
            hookType: analysis.hookType?.displayName ?? "Unknown",
            hookScore: analysis.hookScore ?? 0,
            beatSequence: beats,
            keyTransitions: transitions,
            ctaText: String(ctaText.prefix(150)),
            framework: analysis.frameworkType?.displayName ?? "Unknown",
            format: analysis.swipeContentFormat?.displayName ?? "Unknown"
        )
        swipe.engagementSummary = engSummary
        swipe.fullBody = body
        swipe.structuralBreakdown = buildStructuralBreakdown(analysis: analysis, body: body)
        swipe.persuasionTechniques = persuasionLabels
        swipe.emotionalArc = arcLabels
        swipe.engagementRate = analysis.engagementRate ?? 0
        swipe.hookScoreReason = analysis.hookScoreReason ?? ""
        return swipe
    }

    /// Format large numbers compactly (e.g. 1200 → "1.2K")
    private static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    /// Minimal compression for swipes that lack full SwipeAnalysis (used in fallback path).
    /// Creates a basic CompressedSwipe from title + body so the swipe isn't silently dropped.
    private func compressSwipeMinimal(_ atom: Atom) -> CompressedSwipe? {
        guard let body = atom.body, !body.isEmpty else { return nil }
        let sentences = body.components(separatedBy: ". ")
        let hookText = sentences.prefix(4).joined(separator: ". ")
        return CompressedSwipe(
            id: UUID(uuidString: atom.uuid) ?? UUID(),
            title: atom.title ?? "Untitled",
            hookText: String(hookText.prefix(500)),
            hookType: atom.swipeAnalysis?.hookType?.displayName ?? "Unknown",
            hookScore: atom.swipeAnalysis?.hookScore ?? 0,
            beatSequence: [],
            keyTransitions: [],
            ctaText: "",
            framework: "Unknown",
            format: "Unknown",
            fullBody: body
        )
    }

    /// Aggregate cross-swipe pattern intelligence for Block 3 injection (WP2).
    private func buildPatternIntelligence() -> String {
        guard !selectedSwipes.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("--- PATTERN INTELLIGENCE (aggregated from \(selectedSwipes.count) loaded swipes) ---")

        // Hook performance by type
        let hookGroups = Dictionary(grouping: selectedSwipes, by: { $0.hookType })
        let hookStats = hookGroups.compactMap { (type, swipes) -> (String, Double, Int)? in
            guard type != "Unknown" else { return nil }
            let avg = swipes.map(\.hookScore).reduce(0, +) / Double(swipes.count)
            return (type, avg, swipes.count)
        }.sorted { $0.1 > $1.1 }
        if !hookStats.isEmpty {
            let hookLine = hookStats.prefix(5).map { "\($0.0) avg \(String(format: "%.1f", $0.1))/10 (\($0.2))" }
            lines.append("Hook Performance: \(hookLine.joined(separator: ", "))")
        }

        // Persuasion technique frequency
        var persuasionCounts: [String: Int] = [:]
        for swipe in selectedSwipes {
            for technique in swipe.persuasionTechniques {
                let name = technique.components(separatedBy: " (").first ?? technique
                persuasionCounts[name, default: 0] += 1
            }
        }
        let topPersuasion = persuasionCounts.sorted { $0.value > $1.value }.prefix(5)
        if !topPersuasion.isEmpty {
            let persuasionLine = topPersuasion.map { "\($0.key) (\($0.value)/\(selectedSwipes.count))" }
            lines.append("Top Persuasion: \(persuasionLine.joined(separator: ", "))")
        }

        // Emotional arc consensus
        var arcPatternCounts: [String: Int] = [:]
        for swipe in selectedSwipes where !swipe.emotionalArc.isEmpty {
            let key = swipe.emotionalArc.prefix(4).joined(separator: "\u{2192}")
            arcPatternCounts[key, default: 0] += 1
        }
        if let dominantArc = arcPatternCounts.max(by: { $0.value < $1.value }) {
            lines.append("Dominant Emotional Arc: \(dominantArc.key) (in \(dominantArc.value)/\(selectedSwipes.count) swipes)")
        }

        // Engagement distribution
        let engagedSwipes = selectedSwipes.filter { $0.engagementRate > 0 }
        if !engagedSwipes.isEmpty {
            let avgEng = engagedSwipes.map(\.engagementRate).reduce(0, +) / Double(engagedSwipes.count)
            let maxEng = engagedSwipes.map(\.engagementRate).max() ?? 0
            lines.append("Avg Engagement: \(String(format: "%.1f", avgEng))% (best: \(String(format: "%.1f", maxEng))%)")
        }

        // Actionable directive
        if let topHook = hookStats.first, !topPersuasion.isEmpty {
            let topTech = topPersuasion.prefix(2).map(\.key).joined(separator: " + ")
            lines.append("")
            lines.append("APPLY: Use \(topTech) techniques (most frequent in top performers). Target \(topHook.0) hook style (avg \(String(format: "%.1f", topHook.1))/10).")
        }

        return lines.joined(separator: "\n")
    }

    /// Returns a compact swipe intelligence summary for agent-level tool results.
    /// Aggregates hook types, persuasion techniques, and engagement from loaded swipes.
    func swipeIntelligenceSummary() -> [String: Any] {
        guard !selectedSwipes.isEmpty else { return [:] }

        // Top hook types by performance
        let hookGroups = Dictionary(grouping: selectedSwipes, by: { $0.hookType })
        let hookStats = hookGroups.compactMap { (type, swipes) -> (String, Double, Int)? in
            guard type != "Unknown" else { return nil }
            let avg = swipes.map(\.hookScore).reduce(0, +) / Double(swipes.count)
            return (type, avg, swipes.count)
        }.sorted { $0.1 > $1.1 }
        let topHookTypes = hookStats.prefix(4).map { "\($0.0) avg \(String(format: "%.1f", $0.1))/10 (\($0.2)x)" }

        // Top persuasion techniques
        var persuasionCounts: [String: Int] = [:]
        for swipe in selectedSwipes {
            for technique in swipe.persuasionTechniques {
                let name = technique.components(separatedBy: " (").first ?? technique
                persuasionCounts[name, default: 0] += 1
            }
        }
        let topPersuasion = persuasionCounts.sorted { $0.value > $1.value }.prefix(4)
            .map { "\($0.key) (\($0.value)/\(selectedSwipes.count))" }

        // Avg engagement
        let engagedSwipes = selectedSwipes.filter { $0.engagementRate > 0 }
        let avgEngagement = engagedSwipes.isEmpty ? 0.0
            : engagedSwipes.map(\.engagementRate).reduce(0, +) / Double(engagedSwipes.count)

        var result: [String: Any] = [
            "loadedSwipeCount": selectedSwipes.count,
            "topHookTypes": topHookTypes.joined(separator: ", "),
            "topPersuasion": topPersuasion.joined(separator: ", ")
        ]
        if avgEngagement > 0 {
            result["avgEngagement"] = String(format: "%.1f%%", avgEngagement)
        }
        return result
    }

    /// Build a topic-free structural breakdown from SwipeAnalysis.
    /// Describes WHAT each section DOES (function, density, emotion) without WHAT IT SAYS (content).
    private func buildStructuralBreakdown(analysis: SwipeAnalysis, body: String) -> String {
        var lines: [String] = []

        // Per-section function breakdown from analysis.sections
        if let sections = analysis.sections, !sections.isEmpty {
            let slideCount = analysis.transcriptSlides?.count ?? sections.count
            lines.append("Structure (\(slideCount) slides/sections):")
            for (i, section) in sections.enumerated() {
                var parts: [String] = [section.purpose]
                if let emotion = section.emotion { parts.append(emotion.rawValue) }
                if let size = section.sizePercent, size > 0 {
                    parts.append(String(format: "%.0f%% of content", size * 100))
                }
                lines.append("  \(i + 1). [\(section.label)]: \(parts.joined(separator: ", "))")
            }
        }

        // Word density from transcript slides (if available)
        if let slides = analysis.transcriptSlides, !slides.isEmpty {
            let wordCounts = slides.map { $0.text.split(separator: " ").count }
            let avgWords = wordCounts.reduce(0, +) / max(wordCounts.count, 1)
            lines.append("Slide count: \(slides.count)")
            lines.append("Density: \(avgWords) avg words/slide (range: \(wordCounts.min() ?? 0)-\(wordCounts.max() ?? 0))")
        } else if !body.isEmpty {
            // Fallback: estimate from body text
            let paragraphs = body.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let totalWords = body.split(separator: " ").count
            if !paragraphs.isEmpty {
                lines.append("Sections: \(paragraphs.count), Total words: \(totalWords)")
            }
        }

        // Emotional arc
        if let arc = analysis.emotionalArc, !arc.isEmpty {
            let arcLabels = arc.prefix(6).map { $0.emotion.rawValue }
            lines.append("Emotional arc: \(arcLabels.joined(separator: " → "))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Validation

    /// Validate draft content against platform constraints.
    private func validateDraft(_ content: String, format: WritingContentFormat) -> ValidationResult {
        var violations: [ConstraintViolation] = []

        switch format {
        case .instagramCarousel:
            // Try parsing as JSON carousel
            if let data = content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let slides = json["slides"] as? [[String: Any]] {
                // Slide count: 5-15
                if slides.count < 5 {
                    violations.append(ConstraintViolation(constraintName: "Slide count", expected: "5-15", actual: "\(slides.count)", severity: .hard))
                } else if slides.count > 15 {
                    violations.append(ConstraintViolation(constraintName: "Slide count", expected: "5-15", actual: "\(slides.count)", severity: .hard))
                }
                // ALL slides (including hook): max 300 chars
                for (i, slide) in slides.enumerated() {
                    if let text = slide["text"] as? String, text.count > 300 {
                        violations.append(ConstraintViolation(constraintName: "Slide \(i + 1) length", expected: "max 300 chars", actual: "\(text.count) chars", severity: .hard))
                    }
                }
            } else if content.contains("{") {
                violations.append(ConstraintViolation(constraintName: "JSON format", expected: "valid carousel JSON", actual: "invalid JSON", severity: .hard))
            }
            // Also validate plaintext carousel format (SLIDE N pattern)
            if content.contains("SLIDE 1") || content.contains("Slide 1") {
                let slideLines = content.components(separatedBy: "\n")
                    .filter { $0.uppercased().hasPrefix("SLIDE ") }
                if slideLines.count > 15 {
                    violations.append(ConstraintViolation(constraintName: "Slide count (plaintext)", expected: "5-15 slides", actual: "\(slideLines.count) slides", severity: .hard))
                }
                // LLM should be using JSON format, not plaintext
                violations.append(ConstraintViolation(constraintName: "Draft format", expected: "carousel JSON {\"slides\": [...]}", actual: "plaintext SLIDE format", severity: .hard))
            }

        case .twitterThread:
            if let data = content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tweets = json["tweets"] as? [[String: Any]] {
                if tweets.count < 4 {
                    violations.append(ConstraintViolation(constraintName: "Thread length", expected: "4-12 tweets", actual: "\(tweets.count)", severity: .hard))
                }
                for (i, tweet) in tweets.enumerated() {
                    if let text = tweet["text"] as? String, text.count > 280 {
                        violations.append(ConstraintViolation(constraintName: "Tweet \(i + 1) length", expected: "max 280 chars", actual: "\(text.count) chars", severity: .hard))
                    }
                }
            }

        case .twitterSingle:
            if content.count > 280 {
                violations.append(ConstraintViolation(constraintName: "Tweet length", expected: "max 280 chars", actual: "\(content.count) chars", severity: .hard))
            }

        case .instagramReel:
            let words = content.split(separator: " ").count
            if words > 300 {
                violations.append(ConstraintViolation(constraintName: "Reel script length", expected: "150-300 words", actual: "\(words) words", severity: .soft))
            }
            if words < 50 {
                violations.append(ConstraintViolation(constraintName: "Reel script length", expected: "50+ words", actual: "\(words) words", severity: .soft))
            }
            let firstLine = content.components(separatedBy: "\n").first ?? ""
            if firstLine.count > 60 {
                violations.append(ConstraintViolation(constraintName: "Hook line length", expected: "max 60 chars", actual: "\(firstLine.count) chars", severity: .soft))
            }

        case .linkedinPost:
            if content.count > 3000 {
                violations.append(ConstraintViolation(constraintName: "LinkedIn length", expected: "max 3000 chars", actual: "\(content.count) chars", severity: .hard))
            }
            let paragraphs = content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if paragraphs.count < 3 {
                violations.append(ConstraintViolation(constraintName: "Paragraph count", expected: "3+ paragraphs", actual: "\(paragraphs.count) paragraphs", severity: .soft))
            }

        case .youtubeLongForm:
            let words = content.split(separator: " ").count
            let estimatedMinutes = words / 150
            if estimatedMinutes > 20 {
                violations.append(ConstraintViolation(constraintName: "Script length", expected: "8-15 min (~1200-2250 words)", actual: "~\(estimatedMinutes) min", severity: .soft))
            }
            if !content.contains("##") && !content.contains("SECTION") && !content.lowercased().contains("intro") {
                violations.append(ConstraintViolation(constraintName: "Section headers", expected: "section headers present", actual: "none found", severity: .soft))
            }

        case .tiktokScript:
            let words = content.split(separator: " ").count
            if words > 200 {
                violations.append(ConstraintViolation(constraintName: "TikTok script length", expected: "50-150 words", actual: "\(words) words", severity: .soft))
            }

        case .newsletter:
            let lines = content.components(separatedBy: "\n")
            if let subjectLine = lines.first, subjectLine.hasPrefix("Subject:") {
                let subject = subjectLine.replacingOccurrences(of: "Subject:", with: "").trimmingCharacters(in: .whitespaces)
                if subject.count > 50 {
                    violations.append(ConstraintViolation(constraintName: "Subject line length", expected: "max 50 chars", actual: "\(subject.count) chars", severity: .soft))
                }
            }
            let words = content.split(separator: " ").count
            if words > 1500 {
                violations.append(ConstraintViolation(constraintName: "Newsletter length", expected: "300-1500 words", actual: "\(words) words", severity: .soft))
            }

        default:
            break // Soft constraints only for other formats
        }

        if violations.contains(where: { $0.severity == .hard }) {
            return ValidationResult(status: .needsCorrection(violations))
        } else {
            return ValidationResult(status: .passed(warnings: violations))
        }
    }

    /// Detect the writing content format from the content atom's metadata.
    /// Checks for explicit format set by the agent tool first, then falls back to heuristic detection.
    private func detectContentFormat() -> WritingContentFormat {
        guard let atom = contentAtom else {
            return .staticPost
        }
        return WritingContentFormat.detect(from: atom)
    }

    // MARK: - Memory Management

    /// Summarize older conversation turns when estimated tokens exceed threshold.
    private func summarizeHistoryIfNeeded() async {
        let estimated = estimateTokenCount()
        // Trigger summarization if EITHER token count is high OR message count exceeds 25.
        // The message count threshold catches cases where token estimation is still off,
        // and prevents the UI from rendering 40+ message bubbles which causes 100% CPU.
        let needsSummarization = estimated > tokenSummarizationThreshold || messages.count > 80
        guard needsSummarization else { return }
        guard messages.count > 15 else { return }

        // Keep last 10 messages verbatim, but adjust split point to not break tool pairs
        var splitIndex = messages.count - 10

        // Don't start the kept messages on a toolResult (needs its preceding tool_use)
        while splitIndex > 0 && splitIndex < messages.count && messages[splitIndex].role == .toolResult {
            splitIndex -= 1
        }
        // Don't split between assistant-with-toolCalls and its toolResult
        if splitIndex > 0 && splitIndex < messages.count {
            let prevMsg = messages[splitIndex - 1]
            if prevMsg.role == .assistant && !(prevMsg.toolCalls ?? []).isEmpty {
                splitIndex -= 1
            }
        }

        let toSummarize = Array(messages.prefix(splitIndex))
        let toKeep = Array(messages.suffix(messages.count - splitIndex))

        // Build summary text from older messages
        let summaryInput = toSummarize.map { msg in
            "[\(msg.role.rawValue)] \(msg.content.prefix(300))"
        }.joined(separator: "\n")

        do {
            let summaryPrompt = """
            Summarize the following conversation history into a concise summary (max 700 words). \
            This summary will replace the original messages, so PRESERVE ALL of the following:

            CRITICAL — preserve in full detail:
            - Swipe analysis: which swipes were analyzed, their hook types, structural patterns, beat sequences, \
            section counts, and density metrics. This is the structural DNA the AI must maintain across revisions.
            - Specific data points and statistics from swipes that were referenced or used in the draft.

            Also preserve:
            - Creative decisions made, outline/hook choices, framework selection
            - Voice notes and client-specific preferences
            - Any user preferences or revision instructions expressed
            - Format constraints (slide count, character limits, line break style)

            \(summaryInput)
            """

            let summary = try await ResearchService.shared.generateWithCaching(
                systemBlocks: [("You are a conversation summarizer.", false)],
                messages: [["role": "user", "content": summaryPrompt]],
                model: ContentModelTier.strategist.rawValue,
                maxTokens: 1024
            )

            conversationSummary = summary
            messages = toKeep

            print("UnifiedWritingEngine: Summarized \(toSummarize.count) messages, keeping \(toKeep.count)")
        } catch {
            print("UnifiedWritingEngine: summarization failed: \(error)")
        }
    }

    /// Estimate the total token count of conversation + context.
    /// Includes tool call parameters and tool result content — these were previously
    /// ignored, causing the estimate to be ~50% of actual at 30+ messages. This meant
    /// summarization (threshold 50K) never triggered, letting the array grow unboundedly.
    private func estimateTokenCount() -> Int {
        var total = 0

        // Block 1 + Block 2
        total += (cachedBlock1?.count ?? 0) / 4
        total += (cachedBlock2?.count ?? 0) / 4

        // Messages — include ALL content: body, tool calls, and tool results
        for msg in messages {
            total += msg.content.count / 4
            if let toolCalls = msg.toolCalls {
                for tc in toolCalls {
                    total += tc.parameters.count / 4
                }
            }
            if let toolResults = msg.toolResults {
                for tr in toolResults {
                    total += tr.content.count / 4
                }
            }
        }

        // Conversation summary
        total += conversationSummary.count / 4

        // Reference material cache (lives in Block 3)
        total += referenceMaterialCharCount / 4

        return total
    }

    // MARK: - Client Profile Loading

    private func loadClientProfile(contentAtom: Atom) async {
        let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self)
        guard let clientUUID = metadata?.clientProfileUUID else {
            clientProfileAtom = nil
            clientMeta = nil
            return
        }

        clientProfileAtom = try? await database.asyncRead { db in
            try Atom.filter(Column("uuid") == clientUUID).filter(Column("is_deleted") == false).fetchOne(db)
        }

        if let profileAtom = clientProfileAtom {
            clientMeta = profileAtom.metadataValue(as: ClientProfileMetadata.self)
        }
    }

    // MARK: - Learning Bridge

    /// Load simple key-value user preferences (beliefs come from TasteContext).
    private func loadUserPreferences(clientUUID: String) async -> [(key: String, value: String)] {
        var prefs: [(key: String, value: String)] = []

        // Query .userPreference atoms scoped to this client
        if let atoms = try? await database.asyncRead({ db in
            try Atom.filter(Column("type") == AtomType.userPreference.rawValue)
                .fetchAll(db)
        }) {
            for atom in atoms {
                if let metadata = atom.metadataValue(as: [String: String].self),
                   let scope = metadata["scope"],
                   scope == clientUUID,
                   let key = metadata["key"],
                   let value = metadata["value"] {
                    prefs.append((key: key, value: value))
                }
            }
        }

        return prefs
    }

    /// Load batch analysis insights relevant to the current content format.
    /// These are `.agentLearning` atoms with subtype "batch_analysis" or "agent_analysis"
    /// that contain cross-swipe pattern analysis for the matching source type.
    private func loadBatchAnalyses(format: WritingContentFormat) -> String {
        // Map content format to swipe source types
        let sourceTypes: [String]
        switch format {
        case .instagramCarousel: sourceTypes = ["instagram_carousel", "carousel"]
        case .instagramReel: sourceTypes = ["instagram_reel", "reel"]
        case .instagramStory: sourceTypes = ["instagram_story", "story"]
        case .twitterThread: sourceTypes = ["twitter_thread", "thread"]
        case .twitterSingle: sourceTypes = ["twitter"]
        case .linkedinPost: sourceTypes = ["linkedin"]
        case .youtubeShort: sourceTypes = ["youtube_short"]
        case .youtubeLongForm: sourceTypes = ["youtube"]
        case .tiktokScript: sourceTypes = ["tiktok"]
        case .newsletter: sourceTypes = ["newsletter"]
        case .staticPost: sourceTypes = []
        }

        guard !sourceTypes.isEmpty else { return "" }

        // Load from UserDefaults (batch analysis reports stored by PromptTemplateStore)
        let reports = PromptTemplateStore.shared.loadBatchAnalysisReports()
        let relevant = reports.filter { report in
            sourceTypes.contains { report.sourceType.localizedCaseInsensitiveContains($0) }
        }

        guard !relevant.isEmpty else { return "" }

        var lines: [String] = []
        for report in relevant.prefix(3) {
            lines.append("[\(report.sourceType.uppercased()) — \(report.swipeCount) swipes analyzed, \(report.dateLabel)]")
            lines.append(report.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func appendTopTranscripts(to lines: inout [String], profileAtom: Atom, category: ProfileDocumentCategory, label: String) {
        let transcripts = ClientIntelligenceEngine.shared.getTopTranscripts(
            profile: profileAtom,
            count: 5,
            category: category
        )
        if !transcripts.isEmpty {
            lines.append("--- TOP PERFORMING \(label) (\(transcripts.count) posts) ---")
            for (i, transcript) in transcripts.enumerated() {
                let truncated = transcript.count > 2000 ? String(transcript.prefix(2000)) + "..." : transcript
                lines.append("\(label) #\(i + 1):\n\(truncated)")
                lines.append("")
            }
        }
    }

    private func appendLegacyProfile(to lines: inout [String], meta: ClientProfileMetadata) {
        if let niche = meta.niche { lines.append("Niche: \(niche)") }
        if let industry = meta.industry { lines.append("Industry: \(industry)") }
        if let audience = meta.targetAudience { lines.append("Target Audience: \(audience)") }
        if let brandStory = meta.brandStory, !brandStory.isEmpty { lines.append("Brand Story: \(brandStory)") }
        if let voiceNotes = meta.voiceNotes, !voiceNotes.isEmpty { lines.append("Voice & Tone: \(voiceNotes)") }
        if let uniqueAngle = meta.uniqueAngle, !uniqueAngle.isEmpty { lines.append("Unique Angle: \(uniqueAngle)") }
        if let beliefs = meta.coreBeliefs, !beliefs.isEmpty { lines.append("Core Beliefs: \(beliefs.joined(separator: ", "))") }
        if let phrases = meta.signaturePhrases, !phrases.isEmpty { lines.append("Signature Phrases: \(phrases.joined(separator: " | "))") }
        if let transcripts = meta.topPerformingTranscripts, !transcripts.isEmpty {
            lines.append("\n--- TOP PERFORMING CONTENT ---")
            for (i, transcript) in transcripts.prefix(3).enumerated() {
                lines.append("Top #\(i + 1):\n\(transcript)")
            }
        }
        if let bestFormats = meta.bestFormats, !bestFormats.isEmpty {
            lines.append("Best Formats: \(bestFormats.joined(separator: ", "))")
        }
    }

    /// Appends the client's top 5 best-performing posts to Block 2, filtered by the current
    /// content format (reel vs thread/carousel). Char limits: 3K for reels, 10K for threads/carousels.
    /// Sources in priority order: ProfileDocuments (.reel/.thread) → TopPost → topPerformingTranscripts.
    private func appendTopPerformingPosts(to lines: inout [String], meta: ClientProfileMetadata, format: WritingContentFormat) {
        let isReel = format == .instagramReel || format == .youtubeShort || format == .tiktokScript
        let charLimit = isReel ? 3_000 : 10_000
        let formatLabel = isReel ? "REELS" : "THREADS/CAROUSELS"
        let targetCategory: ProfileDocumentCategory = isReel ? .reel : .thread

        var collected: [String] = []

        // 1. ProfileDocuments with .reel or .thread category
        if let documents = meta.documents {
            for doc in documents where doc.category == targetCategory && collected.count < 5 {
                collected.append(doc.content)
            }
        }

        // 2. TopPost objects filtered by platform string
        if collected.count < 5, let posts = meta.topPerformingPosts, !posts.isEmpty {
            let platformMatches = isReel
                ? ["reel", "reels", "short", "shorts", "tiktok"]
                : ["thread", "threads", "carousel", "carousels", "post"]
            for post in posts where collected.count < 5 {
                let p = post.platform.lowercased()
                guard platformMatches.contains(where: { p.contains($0) }) else { continue }
                guard !collected.contains(where: { $0 == post.transcript }) else { continue }
                collected.append(post.transcript)
            }
        }

        // 3. Fallback: unfiltered TopPost (if we still have fewer than 5)
        if collected.count < 5, let posts = meta.topPerformingPosts {
            for post in posts where collected.count < 5 {
                guard !collected.contains(where: { $0 == post.transcript }) else { continue }
                collected.append(post.transcript)
            }
        }

        // 4. Last resort: plain transcript strings
        if collected.count < 5, let transcripts = meta.topPerformingTranscripts {
            for transcript in transcripts where collected.count < 5 {
                collected.append(transcript)
            }
        }

        guard !collected.isEmpty else { return }

        let top5 = Array(collected.prefix(5))
        lines.append("")
        lines.append("--- CLIENT BEST-PERFORMING \(formatLabel) (\(top5.count) posts) ---")
        lines.append("These are this client's top-performing posts for the format you're writing. Study the voice, structure, pacing, and patterns. Match this quality bar.")
        lines.append("")
        for (i, transcript) in top5.enumerated() {
            lines.append("POST #\(i + 1):")
            if transcript.count > charLimit {
                lines.append(String(transcript.prefix(charLimit)) + "...")
            } else {
                lines.append(transcript)
            }
            lines.append("")
        }
    }

    // MARK: - Token Budget Constants (C5)

    /// Maximum character budget for Block 2 (client intelligence model + brand story + voice guide + top posts).
    /// Opus 4.6 has 1M token context — no reason to truncate client intelligence data.
    private let block2MaxChars = 200_000

    private func buildCachedBlocks(contentAtom: Atom) {
        _ = assembleBlock1()
        _ = assembleBlock2()
        enforceTokenBudgets()
    }

    /// C5: Enforce token budgets on cached blocks.
    /// Block 1 is never truncated; Block 2 is still bounded to avoid runaway profile payloads.
    private func enforceTokenBudgets() {
        let adjusted = Self.applyBlockBudgets(block1: cachedBlock1, block2: cachedBlock2, block2MaxChars: block2MaxChars)
        cachedBlock1 = adjusted.block1
        cachedBlock2 = adjusted.block2

        // Log actual sizes for monitoring
        let b1Size = cachedBlock1?.count ?? 0
        let b2Size = cachedBlock2?.count ?? 0
        print("📊 [UnifiedWritingEngine] Block sizes — B1: \(b1Size) chars (full prompt retained), B2: \(b2Size) chars (\(b2Size * 100 / max(block2MaxChars, 1))% of budget)")
    }

    static func applyBlockBudgets(
        block1: String?,
        block2: String?,
        block2MaxChars: Int
    ) -> (block1: String?, block2: String?) {
        var adjustedBlock2 = block2
        if var block2 = adjustedBlock2, block2.count > block2MaxChars {
            print("⚠️ [UnifiedWritingEngine] Block 2 exceeds budget: \(block2.count)/\(block2MaxChars) chars — truncating verbose profile sections")
            block2 = String(block2.prefix(block2MaxChars))
            if let lastBreak = block2.range(of: "\n\n", options: .backwards, range: block2.startIndex..<block2.endIndex) {
                block2 = String(block2[block2.startIndex..<lastBreak.upperBound])
            }
            block2 += "\n[... profile data truncated for token budget]"
            adjustedBlock2 = block2
        }
        return (block1, adjustedBlock2)
    }

    private func labelForTool(_ name: String) -> String {
        let atomTitle = contentAtom?.title ?? ""
        let shortTitle = atomTitle.isEmpty ? "" : ": \(String(atomTitle.prefix(40)))"

        switch name {
        case "think": return "Reasoning\(shortTitle.isEmpty ? "..." : " about\(shortTitle)")"
        case "set_title": return "Setting title"
        case "update_outline": return "Updating outline\(shortTitle)"
        case "add_hooks": return "Generating hooks\(shortTitle)"
        case "set_description": return "Setting description"
        case "write_draft": return "Writing draft\(shortTitle)"
        case "edit_section": return "Editing section\(shortTitle)"
        case "search_swipes": return "Searching swipe library"
        case "search_connections": return "Searching knowledge graph"
        case "read_draft": return "Reading current draft\(shortTitle)"
        case "get_client_profile":
            let client = clientMeta?.clientName ?? ""
            return client.isEmpty ? "Loading client profile" : "Loading profile: \(client)"
        case "list_client_posts": return "Browsing client posts"
        case "read_client_post": return "Loading client post"
        case "read_swipe_body": return "Loading swipe body"
        case "analyze_swipe_patterns": return "Analyzing swipe patterns"
        default: return "Processing..."
        }
    }

    // MARK: - Conversation Persistence (B1)

    /// Persist the conversation to atom.structured["writingConversation"].
    /// Only saves user and assistant text messages (not tool calls/results).
    /// Each message content is truncated to 2000 chars to keep storage bounded.
    private func persistConversation() async {
        guard let atomUUID = contentAtom?.uuid else { return }

        // Filter to user + assistant text messages only (skip tool calls, tool results, system)
        let persistableMessages = messages.compactMap { msg -> [String: String]? in
            guard msg.role == .user || msg.role == .assistant else { return nil }
            // Skip empty assistant messages (tool-call-only turns)
            let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return [
                "id": msg.id.uuidString,
                "role": msg.role.rawValue,
                "content": String(content.prefix(2000)),
                "timestamp": ISO8601.string(from: msg.timestamp)
            ]
        }

        guard !persistableMessages.isEmpty else { return }

        do {
            try await database.asyncWrite { db in
                guard var atom = try Atom.filter(Column("uuid") == atomUUID).filter(Column("is_deleted") == false).fetchOne(db) else { return }

                var structuredDict: [String: Any] = [:]
                if let existingStr = atom.structured,
                   let existingData = existingStr.data(using: .utf8),
                   let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                    structuredDict = existing
                }

                structuredDict["writingConversation"] = persistableMessages

                if let data = try? JSONSerialization.data(withJSONObject: structuredDict),
                   let str = String(data: data, encoding: .utf8) {
                    atom.structured = str
                    atom.updatedAt = ISO8601.string(from: Date())
                    try atom.update(db)
                }
            }
            print("💾 [UnifiedWritingEngine] Persisted \(persistableMessages.count) conversation messages to atom \(atomUUID)")
        } catch {
            print("❌ [UnifiedWritingEngine] Failed to persist conversation: \(error)")
        }
    }

    /// Restore conversation messages from atom.structured["writingConversation"].
    /// Returns an array of WritingMessages, or empty if no persisted conversation exists.
    private func restorePersistedConversation(from atom: Atom) -> [WritingMessage] {
        guard let structuredStr = atom.structured,
              let data = structuredStr.data(using: .utf8),
              let structuredDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let conversationArray = structuredDict["writingConversation"] as? [[String: String]] else {
            return []
        }

        let isoFormatter = ISO8601DateFormatter()
        var restored: [WritingMessage] = []

        for entry in conversationArray {
            guard let idStr = entry["id"],
                  let id = UUID(uuidString: idStr),
                  let roleStr = entry["role"],
                  let role = WritingMessage.WritingMessageRole(rawValue: roleStr),
                  let content = entry["content"] else {
                continue
            }

            let timestamp: Date
            if let tsStr = entry["timestamp"] {
                timestamp = isoFormatter.date(from: tsStr) ?? Date()
            } else {
                timestamp = Date()
            }

            restored.append(WritingMessage(id: id, role: role, content: content, timestamp: timestamp))
        }

        return restored
    }

    // MARK: - Condensed Failure Fingerprint (C3)

    /// Append a condensed failure fingerprint to the lines array.
    /// Only includes HIGH severity rules and the top 3 MEDIUM rules, capped at 800 chars total.
    private func appendCondensedFailureFingerprint(to lines: inout [String], model: ClientIntelligenceModel) {
        var fingerprints: [(label: String, fingerprint: FailureFingerprint)] = []
        if let fp = model.failureFingerprint { fingerprints.append(("General", fp)) }
        if let fp = model.reelFailureFingerprint { fingerprints.append(("Reel", fp)) }
        if let fp = model.threadFailureFingerprint { fingerprints.append(("Thread", fp)) }

        guard !fingerprints.isEmpty else { return }

        var fingerprintLines: [String] = []
        fingerprintLines.append("--- FAILURE RULES (condensed) ---")

        for (label, fp) in fingerprints {
            let highRules = fp.rules(severity: .high)
            let mediumRules = fp.rules(severity: .medium)

            if highRules.isEmpty && mediumRules.isEmpty { continue }

            fingerprintLines.append("[\(label)]")
            for rule in highRules {
                fingerprintLines.append("  [HIGH] \(rule.rule)")
            }
            for rule in mediumRules.prefix(3) {
                fingerprintLines.append("  [MED] \(rule.rule)")
            }
        }

        // Cap total failure fingerprint at 800 chars
        var combined = fingerprintLines.joined(separator: "\n")
        if combined.count > 800 {
            combined = String(combined.prefix(800))
            // Find last complete line to avoid mid-rule cuts
            if let lastNewline = combined.lastIndex(of: "\n") {
                combined = String(combined[combined.startIndex...lastNewline])
            }
            combined += "\n  [... additional rules truncated]"
        }

        lines.append(combined)
        lines.append("")
    }
}

// MARK: - Engine Notification Names

extension Notification.Name {
    static let unifiedEngineTitleUpdate = Notification.Name("unifiedEngineTitleUpdate")
    static let unifiedEngineOutlineUpdate = Notification.Name("unifiedEngineOutlineUpdate")
    static let unifiedEngineHooksUpdate = Notification.Name("unifiedEngineHooksUpdate")
    static let unifiedEngineDescriptionUpdate = Notification.Name("unifiedEngineDescriptionUpdate")
    static let unifiedEngineDraftUpdate = Notification.Name("unifiedEngineDraftUpdate")
    static let unifiedEngineSectionEdit = Notification.Name("unifiedEngineSectionEdit")
}
