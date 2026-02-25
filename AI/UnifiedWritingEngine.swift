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
    systemBlocks: [(content: String, cacheControl: Bool)],
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
    var systemContentBlocks: [[String: Any]] = []
    for block in systemBlocks {
        var contentBlock: [String: Any] = ["type": "text", "text": block.content]
        if block.cacheControl {
            contentBlock["cache_control"] = ["type": "ephemeral"]
        }
        systemContentBlocks.append(contentBlock)
    }

    let systemMessage: [String: Any] = ["role": "system", "content": systemContentBlocks]
    var allMessages: [[String: Any]] = [systemMessage]
    allMessages.append(contentsOf: messages)

    // Mark last tool with cache_control so providers cache static tool definitions
    var cachedTools = tools
    if !cachedTools.isEmpty {
        var lastTool = cachedTools[cachedTools.count - 1]
        lastTool["cache_control"] = ["type": "ephemeral"]
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

    let (data, httpResponse) = try await URLSession.shared.data(for: request)
    let httpStatus = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
    print("🌐 [WritingAPICall] HTTP \(httpStatus)")

    if httpStatus != 200 {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        print("❌ [WritingAPICall] Error: \(errorText.prefix(500))")
        throw ResearchError.apiError(statusCode: httpStatus, message: errorText)
    }

    // Parse response
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let choices = json?["choices"] as? [[String: Any]]
    let firstChoice = choices?.first
    let message = firstChoice?["message"] as? [String: Any]
    let finishReason = firstChoice?["finish_reason"] as? String

    if let usage = json?["usage"] as? [String: Any],
       let details = usage["prompt_tokens_details"] as? [String: Any],
       let cached = details["cached_tokens"] as? Int, cached > 0 {
        print("🌐 [WritingAPICall] Cache hit: \(cached) tokens")
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

    print("🌐 [WritingAPICall] Parsed: text=\(textContent.count) chars, tools=\(toolCalls.count)")
    return ClaudeToolUseResponse(textContent: textContent, toolCalls: toolCalls, stopReason: finishReason)
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
    private var cachedContextVersion: UUID?
    private var contentAtom: Atom?
    private var clientProfileAtom: Atom?
    private var clientMeta: ClientProfileMetadata?
    private var selectedSwipes: [CompressedSwipe] = []
    private(set) var conversationSummary: String = ""
    private var isCancelled = false
    private var refinementIterations = 0
    private var cachedExperienceBuffer: String = ""

    private let database = CosmoDatabase.shared

    // MARK: - Constants

    private let writerModel = ContentModelTier.writer.rawValue
    private let brainstormModel = ContentModelTier.strategist.rawValue  // Sonnet for outline/hooks — analytical, not creative
    private let scorecardModel = ContentModelTier.strategist.rawValue
    private let maxRetries = 2
    private let tokenSummarizationThreshold = 20_000

    // MARK: - Phase-Aware Model Selection

    /// Returns the appropriate model for each writing phase.
    /// Brainstorm (outline/hooks) is analytical work where Sonnet matches Opus.
    /// Draft/polish is where Opus's creative reasoning justifies the cost.
    private func modelForPhase(_ phase: ContentStep) -> String {
        switch phase {
        case .brainstorm:
            return brainstormModel  // Sonnet — structural/analytical
        case .draft, .polish:
            return writerModel      // Opus — creative writing
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
        self.cachedExperienceBuffer = ""

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
        onContextActivity?(.completed(name: "load_client_profile", displayLabel: "Client profile loaded", resultPreview: clientName == "none" ? "No profile linked" : clientName))
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

        buildCachedBlocks(contentAtom: contentAtom)
        print("🔧 [UnifiedWritingEngine] Block1 length: \(cachedBlock1?.count ?? 0) chars, Block2 length: \(cachedBlock2?.count ?? 0) chars")

        // Load learned preferences for this client
        let contentMeta = contentAtom.metadataValue(as: ContentAtomMetadata.self)
        if let clientUUID = contentMeta?.clientProfileUUID {
            onContextActivity?(.started(name: "load_preferences", displayLabel: "Loading learned preferences", args: [:]))
            let prefs = await loadLearnedPreferences(clientUUID: clientUUID)
            if !prefs.isEmpty, var block2 = cachedBlock2, !block2.isEmpty {
                // Separate writing rules (with examples) from simple key-value preferences
                let writingRules = prefs.filter { $0.key == "writing_rule" }
                let otherPrefs = prefs.filter { $0.key != "writing_rule" }

                if !writingRules.isEmpty {
                    let rulesText = writingRules.enumerated().map { i, rule in
                        "\(i + 1). \(rule.value)"
                    }.joined(separator: "\n\n")
                    block2 += "\n\n## LEARNED WRITING RULES — MANDATORY\n"
                    block2 += "These rules were learned from the user's past edits. "
                    block2 += "Violating these will result in rejection.\n\n\(rulesText)"
                }
                if !otherPrefs.isEmpty {
                    let prefsText = otherPrefs.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
                    block2 += "\n\n## User Preferences\n\(prefsText)"
                }
                cachedBlock2 = block2
                print("🔧 [UnifiedWritingEngine] Injected \(prefs.count) learned preferences into Block 2")
            }
            onContextActivity?(.completed(name: "load_preferences", displayLabel: "Learned preferences loaded", resultPreview: "\(prefs.count) rules/preferences"))

            // Inject batch analyses relevant to this content's format
            let batchInsights = loadBatchAnalyses(format: detectContentFormat())
            if !batchInsights.isEmpty, var block2 = cachedBlock2, !block2.isEmpty {
                block2 += "\n\n## Batch Analysis Insights (from swipe library patterns)\n\(batchInsights)"
                cachedBlock2 = block2
                print("🔧 [UnifiedWritingEngine] Injected batch analysis insights into Block 2")
            }

            // Pre-fetch experience buffer for Block 3
            let contentTitle = contentAtom.title ?? contentAtom.body ?? ""
            let formatStr = detectContentFormat().rawValue
            let experiences = await loadRelevantExperiences(clientUUID: clientUUID, format: formatStr, topic: contentTitle)
            if !experiences.isEmpty {
                var expLines: [String] = []
                expLines.append("--- PAST WRITING EXPERIENCES ---")
                expLines.append("Learn from these examples — they show how this client modifies AI-generated content:")
                for exp in experiences.prefix(2) {
                    expLines.append("Generated: \(String(exp.generated.prefix(200)))...")
                    expLines.append("Client edited to: \(String(exp.edited.prefix(200)))...")
                    expLines.append("Key changes: \(exp.diffSummary)")
                    expLines.append("")
                }
                cachedExperienceBuffer = expLines.joined(separator: "\n")
                print("🔧 [UnifiedWritingEngine] Pre-fetched \(experiences.count) experience entries for Block 3")
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
        await loadClientProfile(contentAtom: self.contentAtom!)
        cachedBlock2 = nil
        buildCachedBlocks(contentAtom: self.contentAtom!)
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

        // Inject context reminder on first user message so the AI knows exactly what's available
        // and is forced to analyze it before responding
        if messages.isEmpty || messages.filter({ $0.role == .user }).count == 0 {
            let contextReminder = buildContextReminder()
            if !contextReminder.isEmpty {
                messages.append(WritingMessage(role: .system, content: contextReminder))
            }
        } else if clientMeta != nil {
            // Update any stale "None linked" context reminder now that a profile is loaded.
            // Without this, the AI sees the old reminder and re-calls get_client_profile on every turn.
            if let reminderIdx = messages.firstIndex(where: {
                $0.role == .system && $0.content.contains("CONTENT PROFILE: None linked")
            }) {
                let updatedContent = messages[reminderIdx].content.replacingOccurrences(
                    of: "CONTENT PROFILE: None linked. Use the get_client_profile tool to search for and load a client profile by name. If the user mentions a creator name, search for it immediately.",
                    with: "CONTENT PROFILE: \(clientMeta!.clientName) — LOADED. Full intelligence model, voice fingerprint, and top-performing posts are in the system prompt."
                )
                messages[reminderIdx] = WritingMessage(
                    id: messages[reminderIdx].id,
                    role: .system,
                    content: updatedContent,
                    timestamp: messages[reminderIdx].timestamp
                )
            }
        }

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

            // Commit results on main actor (single batch update)
            if !result.newMessages.isEmpty {
                messages.append(contentsOf: result.newMessages)
                print("💬 [UnifiedWritingEngine] Committed \(result.newMessages.count) messages (total: \(messages.count))")
            }

            // B1: Persist conversation to atom.structured for cross-session restoration
            await persistConversation()

            isProcessing = false
            print("💬 [UnifiedWritingEngine] ✅ sendMessage complete. Response: \(result.lastMessage?.content.prefix(100) ?? "nil")")
            return result.lastMessage
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
    func handlePhaseTransition(from: ContentStep, to: ContentStep, state: ContentFocusModeState) {
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
            Focus on refinement: scorecard evaluation, voice drift correction, CTA strengthening.
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

    /// Run the scorecard evaluation on the current draft.
    func runScorecard() async {
        let prompt = "Evaluate the current draft using run_scorecard. Review the results and suggest specific improvements."
        _ = await sendMessage(prompt, phase: .polish)
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
        systemBlocks: [(content: String, cacheControl: Bool)],
        tools: [[String: Any]],
        model: String,
        apiKey: String,
        phase: ContentStep
    ) async throws -> ConversationLoopResult {
        var pendingMessages: [WritingMessage] = []
        var lastAssistantMessage: WritingMessage?

        let toolNames = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        print("🔄 [UnifiedWritingEngine] Starting conversation loop (nonisolated). System blocks: \(systemBlocks.count), tools: \(toolNames)")

        for iteration in 0..<10 {
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
                    tools: tools,
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

            print("🔄 [UnifiedWritingEngine] Response: text=\(response.textContent.count)chars, tools=\(response.toolCalls.count), stop=\(response.stopReason ?? "nil")")

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

            let hasText = !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasToolCalls = !response.toolCalls.isEmpty

            // Build assistant message
            if hasText || !hasToolCalls {
                let assistantMsg = WritingMessage(
                    role: .assistant,
                    content: cleanedText,
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
                break
            }

            // Execute tool calls — hops to main actor briefly for notifications + @Published updates.
            // Returns to cooperative pool after each call.
            print("🔄 [UnifiedWritingEngine] Executing \(response.toolCalls.count) tool calls...")
            let toolResults = await self.executeToolCalls(response.toolCalls, phase: phase)
            for result in toolResults {
                let resultMsg = WritingMessage(role: .toolResult, content: result.content, toolResults: [result])
                pendingMessages.append(resultMsg)
            }
        }

        print("🔄 [UnifiedWritingEngine] Loop done. \(pendingMessages.count) new messages.")
        return ConversationLoopResult(newMessages: pendingMessages, lastMessage: lastAssistantMessage)
    }

    /// Build API messages from a WritingMessage array.
    /// `nonisolated static` so it can be called from the off-main conversation loop.
    nonisolated private static func buildAPIMessages(from messages: [WritingMessage]) -> [[String: Any]] {
        var apiMessages: [[String: Any]] = []

        for msg in messages {
            switch msg.role {
            case .user:
                apiMessages.append(["role": "user", "content": msg.content])

            case .assistant:
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
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

    // MARK: - Context Assembly

    /// Assemble the 3-tier system blocks for the API call.
    private func assembleSystemBlocks() -> [(content: String, cacheControl: Bool)] {
        var blocks: [(content: String, cacheControl: Bool)] = []

        // Block 1: Methodology + platform constraints (cached, stable across all requests)
        let block1 = cachedBlock1 ?? assembleBlock1()
        blocks.append((content: block1, cacheControl: true))

        // Block 2: Intelligence model + transcripts (cached, stable per client)
        if let block2 = cachedBlock2, !block2.isEmpty {
            blocks.append((content: block2, cacheControl: true))
        }

        // Block 3: Dynamic context (per-request)
        let block3 = assembleBlock3()
        if !block3.isEmpty {
            blocks.append((content: block3, cacheControl: false))
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

            // C3: Condensed failure fingerprint — HIGH severity + top 3 MEDIUM, capped at 800 chars
            appendCondensedFailureFingerprint(to: &lines, model: model)

            // C2: Top transcripts REMOVED from Block 2 — they now live in Block 3 as client examples

            // C3: Brand story — capped at 1 doc, 1000 chars
            if let documents = meta.documents {
                let storyDocs = documents.filter { $0.category == .story }
                if let firstStory = storyDocs.first {
                    lines.append("--- BRAND STORY CONTEXT ---")
                    let truncated = firstStory.content.count > 1000 ? String(firstStory.content.prefix(1000)) + "..." : firstStory.content
                    lines.append(truncated)
                    lines.append("")
                }
            }
        } else {
            // Legacy fallback — no intelligence model
            appendLegacyProfile(to: &lines, meta: meta)
        }

        let result = lines.joined(separator: "\n")
        cachedBlock2 = result
        return result
    }

    /// Block 3: Dynamic context — swipes + current state + knowledge + beat patterns.
    /// Changes per request.
    private func assembleBlock3() -> String {
        guard let atom = contentAtom else { return "" }

        var lines: [String] = []
        lines.append("=== DYNAMIC CONTEXT ===")
        lines.append("")

        // Selected swipe examples (compressed)
        if !selectedSwipes.isEmpty {
            lines.append("--- SWIPE EXAMPLES (\(selectedSwipes.count) selected) ---")
            for (i, swipe) in selectedSwipes.enumerated() {
                lines.append("SWIPE #\(i + 1):")
                lines.append(swipe.formatted())
                lines.append("")
            }
        }

        // Current content state
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
                // 6000 chars covers ~25-slide carousels. Full text available via read_draft tool.
                let draftExcerpt = focusState.draftContent.count > 6000
                    ? String(focusState.draftContent.prefix(6000)) + "\n... [truncated, \(focusState.draftContent.count) chars total. Use read_draft for full text.]"
                    : focusState.draftContent
                lines.append("Current Draft:\n\(draftExcerpt)")
            }
        }

        // Inherited context from idea activation
        if let framework = contentMeta?.inheritedFramework {
            lines.append("Selected Framework: \(framework)")
        }
        if let hooks = contentMeta?.inheritedHooks, !hooks.isEmpty {
            lines.append("Inherited Hooks: \(hooks.joined(separator: " | "))")
        }

        // Beat patterns (top 3 for niche)
        // NOTE: findTopPatterns is async but Block 3 assembly is synchronous.
        // Beat patterns are pre-fetched during initialize() and stored on selectedSwipes metadata.

        // Knowledge context (connections) — assembled lazily if budget allows
        // Omitted from Block 3 to save tokens; available via explicit search_connections tool

        // Experience buffer (pre-fetched during initialize)
        if !cachedExperienceBuffer.isEmpty {
            lines.append("")
            lines.append(cachedExperienceBuffer)
        }

        // Conversation summary (if history was summarized)
        if !conversationSummary.isEmpty {
            lines.append("")
            lines.append("--- CONVERSATION SUMMARY (earlier turns) ---")
            lines.append(conversationSummary)
        }

        return lines.joined(separator: "\n")
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
                description: "Write or replace the full draft content. For carousel/thread use JSON format. IMPORTANT: When revising, include ALL slides/sections — even unchanged ones. Never reduce the slide count unless explicitly asked.",
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
            description: "Search the swipe file library for relevant examples. Returns compressed swipe summaries.",
            properties: [
                "query": ["type": "string", "description": "Search query for finding relevant swipes"],
                "format": ["type": "string", "description": "Filter by format (optional)"],
                "hookType": ["type": "string", "description": "Filter by hook type (optional)"],
                "minScore": ["type": "number", "description": "Minimum hook score filter (optional)"]
            ],
            required: ["query"]
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

        // run_scorecard — polish
        if phase == .polish {
            tools.append(buildTool(
                name: "run_scorecard",
                description: "Evaluate the current draft against quality criteria (Hook, Copy, CTA, Voice Match, Structural Alignment). Returns detailed scores and suggestions.",
                properties: [:],
                required: []
            ))
        }

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
                    resultContent = handleThink(call.input)
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
                    resultContent = handleEditSection(call.input)
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

                case "run_scorecard":
                    resultContent = await handleRunScorecard()
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

        // Post notification for the view model to pick up
        NotificationCenter.default.post(
            name: .unifiedEngineOutlineUpdate,
            object: nil,
            userInfo: ["items": outlineItems, "reasoning": reasoning]
        )

        // Persist outline directly to atom metadata in GRDB
        // This is critical for the agent/Telegram path where no UI observer exists
        if let atomUUID = contentAtom?.uuid {
            do {
                // Serialize to JSON Data on the main actor (Sendable-safe) before passing into the closure
                let outlineData = try JSONSerialization.data(withJSONObject: sectionsArray)
                let outlineJSONString = String(data: outlineData, encoding: .utf8)
                try await database.asyncWrite { db in
                    if var atom = try Atom.filter(Column("uuid") == atomUUID).filter(Column("is_deleted") == false).fetchOne(db) {
                        var meta = atom.metadataDict ?? [:]
                        // Deserialize back inside the closure to avoid capturing non-Sendable [[String: Any]]
                        if let jsonStr = outlineJSONString,
                           let jsonData = jsonStr.data(using: .utf8),
                           let outlineJSON = try? JSONSerialization.jsonObject(with: jsonData) {
                            meta["outline"] = outlineJSON
                        }
                        if let metaData = try? JSONSerialization.data(withJSONObject: meta),
                           let metaStr = String(data: metaData, encoding: .utf8) {
                            atom.metadata = metaStr
                        }
                        atom.updatedAt = ISO8601DateFormatter().string(from: Date())
                        try atom.update(db)
                    }
                }
                // Refresh in-memory contentAtom
                contentAtom = try? await database.asyncRead { db in
                    try Atom.filter(Column("uuid") == atomUUID).filter(Column("is_deleted") == false).fetchOne(db)
                }
                print("💾 [UnifiedWritingEngine] Persisted outline (\(outlineItems.count) sections) to atom \(atomUUID)")
            } catch {
                print("❌ [UnifiedWritingEngine] Failed to persist outline: \(error)")
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
            userInfo: ["hooks": hookTexts, "variants": hookVariants]
        )

        // Persist hooks directly to atom metadata in GRDB
        // This is critical for the agent/Telegram path where no UI observer exists
        if let atomUUID = contentAtom?.uuid {
            do {
                // Capture immutable copy for Sendable closure
                let hookTextsCopy = hookTexts
                try await database.asyncWrite { db in
                    if var atom = try Atom.filter(Column("uuid") == atomUUID).filter(Column("is_deleted") == false).fetchOne(db) {
                        var meta = atom.metadataDict ?? [:]
                        meta["hooks"] = hookTextsCopy
                        if let metaData = try? JSONSerialization.data(withJSONObject: meta),
                           let metaStr = String(data: metaData, encoding: .utf8) {
                            atom.metadata = metaStr
                        }
                        atom.updatedAt = ISO8601DateFormatter().string(from: Date())
                        try atom.update(db)
                    }
                }
                print("💾 [UnifiedWritingEngine] Persisted \(hookTexts.count) hooks to atom \(atomUUID)")
            } catch {
                print("❌ [UnifiedWritingEngine] Failed to persist hooks: \(error)")
            }
        }

        return "Added \(hookTexts.count) hook variants."
    }

    private func handleSetDescription(_ input: [String: Any]) async -> String {
        let description = input["description"] as? String ?? ""

        NotificationCenter.default.post(
            name: .unifiedEngineDescriptionUpdate,
            object: nil,
            userInfo: ["description": description]
        )

        // Persist description to atom metadata in GRDB
        if let atomUUID = contentAtom?.uuid, !description.isEmpty {
            do {
                try await database.asyncWrite { db in
                    if var atom = try Atom.filter(Column("uuid") == atomUUID).filter(Column("is_deleted") == false).fetchOne(db) {
                        var meta = atom.metadataDict ?? [:]
                        meta["contentDescription"] = description
                        if let metaData = try? JSONSerialization.data(withJSONObject: meta),
                           let metaStr = String(data: metaData, encoding: .utf8) {
                            atom.metadata = metaStr
                        }
                        atom.updatedAt = ISO8601DateFormatter().string(from: Date())
                        try atom.update(db)
                    }
                }
                print("💾 [UnifiedWritingEngine] Persisted description to atom \(atomUUID)")
            } catch {
                print("❌ [UnifiedWritingEngine] Failed to persist description: \(error)")
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

        NotificationCenter.default.post(
            name: .unifiedEngineDraftUpdate,
            object: nil,
            userInfo: ["content": content, "format": format.rawValue]
        )

        // Persist draft content directly to atom body in GRDB
        // This is critical for the agent/Telegram path where no UI observer exists
        if let atomUUID = contentAtom?.uuid, !content.isEmpty {
            do {
                try await database.asyncWrite { db in
                    if var atom = try Atom.filter(Column("uuid") == atomUUID).filter(Column("is_deleted") == false).fetchOne(db) {
                        atom.body = content
                        atom.updatedAt = ISO8601DateFormatter().string(from: Date())
                        try atom.update(db)
                    }
                }
                // Refresh the in-memory contentAtom so handleReadDraft sees the latest
                contentAtom = try? await database.asyncRead { db in
                    try Atom.filter(Column("uuid") == atomUUID).filter(Column("is_deleted") == false).fetchOne(db)
                }
                print("💾 [UnifiedWritingEngine] Persisted draft (\(wordCount) words) to atom \(atomUUID)")
            } catch {
                print("❌ [UnifiedWritingEngine] Failed to persist draft: \(error)")
            }
        }

        // Voice verification — lightweight heuristic check against brand voice
        let voiceNote = verifyVoiceCompliance(draft: content)

        var result = "Draft written (\(wordCount) words, format: \(formatStr))\(evalSummary)\(validationNote)\(voiceNote)"

        // Auto-refine: evaluate and improve if needed
        if refinementIterations < 2, let atom = contentAtom {
            do {
                // Refresh atom to get latest draft content
                let freshAtom = try? await database.asyncRead { db in
                    try Atom.filter(Column("uuid") == atom.uuid).filter(Column("is_deleted") == false).fetchOne(db)
                }
                if let fresh = freshAtom, let focusState = ContentFocusModeState.from(atom: fresh) {
                    let engine = ContentScorecardEngine()
                    let scorecard = try await engine.evaluate(contentAtom: fresh, state: focusState)

                    let weakDimensions = scorecard.slideAnalysis.isEmpty
                        ? [(name: "Hook", score: scorecard.hookScore.score, suggestions: scorecard.hookScore.suggestions),
                           (name: "Copy", score: scorecard.copyScore.score, suggestions: scorecard.copyScore.suggestions),
                           (name: "CTA", score: scorecard.ctaScore.score, suggestions: scorecard.ctaScore.suggestions)]
                            .filter { $0.score < 7 }
                        : [(name: "Hook", score: scorecard.hookScore.score, suggestions: scorecard.hookScore.suggestions),
                           (name: "Copy", score: scorecard.copyScore.score, suggestions: scorecard.copyScore.suggestions),
                           (name: "CTA", score: scorecard.ctaScore.score, suggestions: scorecard.ctaScore.suggestions)]
                            .filter { $0.score < 7 }

                    if !weakDimensions.isEmpty {
                        let feedback = weakDimensions.map { dim in
                            "[\(dim.name)] \(String(format: "%.1f", dim.score))/10: \(dim.suggestions.joined(separator: "; "))"
                        }.joined(separator: "\n")

                        refinementIterations += 1
                        result += "\n\nAUTO-REFINEMENT PASS \(refinementIterations)/2:\nThe following dimensions scored below threshold:\n\(feedback)\n\nRevise ONLY the weak sections. Keep everything scoring 7+ unchanged. Use the write_draft tool with your improved version."
                    }
                }
            } catch {
                print("Self-refine scorecard failed: \(error)")
            }
        }

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

        guard !issues.isEmpty else { return "" }

        let issueList = issues.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "\n\nVOICE COMPLIANCE CHECK (\(issues.count) issue\(issues.count == 1 ? "" : "s")):\n\(issueList)\nPlease address these voice issues in the draft."
    }

    private func handleEditSection(_ input: [String: Any]) -> String {
        let sectionId = input["sectionIdentifier"] as? String ?? ""
        let newContent = input["newContent"] as? String ?? ""
        let reasoning = input["reasoning"] as? String ?? ""

        NotificationCenter.default.post(
            name: .unifiedEngineSectionEdit,
            object: nil,
            userInfo: [
                "sectionIdentifier": sectionId,
                "newContent": newContent,
                "reasoning": reasoning
            ]
        )

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
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 10,
                entityTypes: [.research]
            )

            var swipeResults: [String] = []
            for result in results {
                guard let uuid = result.entityUUID else { continue }
                guard let atom = try? await database.asyncRead({ db in
                    try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db)
                }) else { continue }
                guard atom.isSwipeFileAtom else { continue }

                let analysis = atom.swipeAnalysis
                let hookScore = analysis?.hookScore ?? 0

                // Apply filters
                if let minScore = minScore, hookScore < minScore { continue }
                if let formatFilter = formatFilter, !(analysis?.frameworkType?.displayName.lowercased().contains(formatFilter.lowercased()) ?? false) { continue }
                if let hookTypeFilter = hookTypeFilter, analysis?.hookType?.rawValue != hookTypeFilter { continue }

                let compressed = compressSwipe(atom)
                if let compressed = compressed {
                    swipeResults.append(compressed.formatted())
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
                return """
                '\(currentMeta.clientName)' is already loaded in your system context. \
                You have full access to their intelligence model, voice fingerprint, \
                top-performing posts, brand context, and failure rules. \
                All of this data is in the system prompt above — read it directly. \
                Do NOT call get_client_profile again for this client.
                """
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

        let match = matches.first!
        let profileAtom = match.atom
        let meta = match.meta

        // Update engine state — this profile will be used for the rest of the conversation
        self.clientProfileAtom = profileAtom
        self.clientMeta = meta
        self.cachedBlock2 = nil
        _ = assembleBlock2()

        // Build comprehensive response
        var lines: [String] = []
        lines.append("=== CLIENT PROFILE: \(meta.clientName) ===")
        if let handle = meta.handle { lines.append("Handle: \(handle)") }
        if let niche = meta.niche { lines.append("Niche: \(niche)") }
        if let industry = meta.industry { lines.append("Industry: \(industry)") }
        if let audience = meta.targetAudience { lines.append("Target Audience: \(audience)") }

        let platforms = meta.platforms.map(\.displayName).joined(separator: ", ")
        if !platforms.isEmpty { lines.append("Platforms: \(platforms)") }

        // Voice & brand context
        if let voiceNotes = meta.voiceNotes, !voiceNotes.isEmpty { lines.append("Voice & Tone: \(voiceNotes)") }
        if let brandStory = meta.brandStory, !brandStory.isEmpty {
            lines.append("Brand Story: \(String(brandStory.prefix(500)))")
        }
        if let uniqueAngle = meta.uniqueAngle, !uniqueAngle.isEmpty { lines.append("Unique Angle: \(uniqueAngle)") }
        if let beliefs = meta.coreBeliefs, !beliefs.isEmpty { lines.append("Core Beliefs: \(beliefs.joined(separator: ", "))") }
        if let phrases = meta.signaturePhrases, !phrases.isEmpty { lines.append("Signature Phrases: \(phrases.joined(separator: " | "))") }

        // Intelligence Model
        if meta.intelligenceModel != nil {
            let modelSummary = ClientIntelligenceEngine.shared.getModelForDrafting(profile: profileAtom)
            if !modelSummary.isEmpty {
                lines.append("\n--- INTELLIGENCE MODEL ---")
                lines.append(modelSummary)
            }
        }

        // Top performing posts
        let reelTranscripts = ClientIntelligenceEngine.shared.getTopTranscripts(profile: profileAtom, count: 3, category: .reel)
        if !reelTranscripts.isEmpty {
            lines.append("\n--- TOP PERFORMING REELS (\(reelTranscripts.count)) ---")
            for (i, t) in reelTranscripts.enumerated() {
                let truncated = t.count > 1500 ? String(t.prefix(1500)) + "..." : t
                lines.append("REEL #\(i + 1):\n\(truncated)\n")
            }
        }

        let threadTranscripts = ClientIntelligenceEngine.shared.getTopTranscripts(profile: profileAtom, count: 3, category: .thread)
        if !threadTranscripts.isEmpty {
            lines.append("--- TOP PERFORMING THREADS (\(threadTranscripts.count)) ---")
            for (i, t) in threadTranscripts.enumerated() {
                let truncated = t.count > 1500 ? String(t.prefix(1500)) + "..." : t
                lines.append("THREAD #\(i + 1):\n\(truncated)\n")
            }
        }

        // Documents
        if let documents = meta.documents, !documents.isEmpty {
            lines.append("--- UPLOADED DOCUMENTS (\(documents.count)) ---")
            for doc in documents.prefix(5) {
                lines.append("[\(doc.category.rawValue)] \(doc.title): \(String(doc.content.prefix(500)))")
            }
        }

        // Best formats
        if let bestFormats = meta.bestFormats, !bestFormats.isEmpty {
            lines.append("Best Formats: \(bestFormats.joined(separator: ", "))")
        }

        // Update loaded context info for UI transparency
        var info = self.loadedContext
        info.clientName = meta.clientName
        self.loadedContext = info

        // Tell the AI the data persists — prevents redundant tool calls on follow-up messages
        lines.append("")
        lines.append("IMPORTANT: This client profile is now loaded into your system context for the rest of this conversation. All subsequent messages will include this data automatically in the system prompt. Do NOT call get_client_profile again — just reference the data directly.")

        print("🔧 [UnifiedWritingEngine] get_client_profile loaded: \(meta.clientName)")
        return lines.joined(separator: "\n")
    }

    private func handleRunScorecard() async -> String {
        guard let atom = contentAtom else { return "Error: no content atom loaded" }

        guard let focusState = ContentFocusModeState.from(atom: atom),
              !focusState.draftContent.isEmpty else {
            return "Error: no draft content to evaluate"
        }

        do {
            let engine = ContentScorecardEngine()
            let scorecard = try await engine.evaluate(contentAtom: atom, state: focusState)

            var lines: [String] = []
            lines.append("=== SCORECARD RESULTS ===")
            lines.append("Hook: \(String(format: "%.1f", scorecard.hookScore.score))/10")
            lines.append("Copy: \(String(format: "%.1f", scorecard.copyScore.score))/10")
            lines.append("CTA: \(String(format: "%.1f", scorecard.ctaScore.score))/10")
            lines.append("Voice Match: \(String(format: "%.0f", scorecard.voiceMatch.percentage))%")
            lines.append("Structural Alignment: \(String(format: "%.0f", scorecard.structuralAlignment.alignmentScore))%")
            lines.append("Overall Confidence: \(scorecard.overallConfidence)%")

            if !scorecard.hookScore.suggestions.isEmpty {
                lines.append("\nHook suggestions: \(scorecard.hookScore.suggestions.joined(separator: "; "))")
            }
            if !scorecard.copyScore.suggestions.isEmpty {
                lines.append("Copy suggestions: \(scorecard.copyScore.suggestions.joined(separator: "; "))")
            }
            if !scorecard.voiceMatch.drifts.isEmpty {
                lines.append("Voice drifts found: \(scorecard.voiceMatch.drifts.count)")
                for drift in scorecard.voiceMatch.drifts.prefix(3) {
                    lines.append("  Line \(drift.lineNumber): \(drift.issue)")
                }
            }

            // Post scorecard result for view
            NotificationCenter.default.post(
                name: .unifiedEngineScorecardResult,
                object: nil,
                userInfo: ["scorecard": scorecard]
            )

            return lines.joined(separator: "\n")
        } catch {
            return "Scorecard error: \(error.localizedDescription)"
        }
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

    /// Select up to 5 diverse swipe examples using 4-axis scoring:
    /// format match, structural fingerprint similarity, stylistic similarity, and performance score.
    /// After library swipe selection, loads the client's top-performing posts as client examples.
    private func selectSwipes(contentAtom: Atom) async {
        let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self)

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
            }
        }

        // Collect candidate swipe atoms
        var candidates: [Atom] = []

        // First: inherited swipes from idea activation
        if let swipeUUIDs = metadata?.inheritedSwipeUUIDs {
            for uuid in swipeUUIDs.prefix(15) {
                if let swipe = try? await database.asyncRead({ db in
                    try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db)
                }) {
                    candidates.append(swipe)
                }
            }
        }

        // Second: search for more if needed
        if candidates.count < 10 {
            let query = contentAtom.title ?? contentAtom.body ?? ""
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let existingUUIDs = Set(candidates.map(\.uuid))
                if let results = try? await HybridSearchEngine.shared.search(
                    query: query,
                    limit: 15,
                    entityTypes: [.research]
                ) {
                    for result in results {
                        guard let uuid = result.entityUUID, !existingUUIDs.contains(uuid) else { continue }
                        if let atom = try? await database.asyncRead({ db in
                            try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db)
                        }), atom.isSwipeFileAtom {
                            candidates.append(atom)
                        }
                        if candidates.count >= 25 { break }
                    }
                }
            }
        }

        // Filter: must have analysis with hook type
        let analyzed = candidates.filter { $0.swipeAnalysis?.hookType != nil }

        // Detect target format for filtering and scoring
        let targetWritingFormat = detectContentFormat()
        let targetFormatFamily = targetWritingFormat.swipeFormatFamily
        let contentFormat = targetWritingFormat.rawValue

        // C1: Increased limits — up to 5 library swipes, minimum 3 for quality
        let maxSwipes = 5
        let minSwipes = 3

        guard !analyzed.isEmpty else {
            // C1: Even with no analyzed swipes, try broader fallback before giving up
            selectedSwipes = await selectSwipesFallback(
                contentAtom: contentAtom,
                targetFormat: targetWritingFormat,
                needed: minSwipes,
                existingUUIDs: Set()
            )
            await appendClientTopPosts(targetFormat: targetWritingFormat)
            return
        }

        // Hard-filter: exclude cross-format swipes when target format is known
        var formatFiltered: [Atom]
        if targetWritingFormat != .staticPost {  // .staticPost is the generic fallback — don't filter on it
            formatFiltered = analyzed.filter { atom in
                guard let swipeFormat = atom.swipeAnalysis?.swipeContentFormat else { return true }  // keep unknowns
                // Allow: exact family match OR both video
                if targetFormatFamily.contains(swipeFormat) { return true }
                if swipeFormat.isVideoFormat && targetWritingFormat.isVideoFormat { return true }
                return false  // reject cross-format (e.g., carousel when target is reel)
            }
            // Fallback: if hard-filter leaves nothing, use all analyzed (better than nothing)
            if formatFiltered.isEmpty { formatFiltered = analyzed }
        } else {
            formatFiltered = analyzed
        }

        // Pre-fetch top patterns for this content format
        let topPatterns = await BeatPatternService.shared.findTopPatterns(format: contentFormat, limit: 10)
        let topFingerprints = Set(topPatterns.map(\.fingerprint))

        var scored: [(atom: Atom, finalScore: Double, hookType: String)] = []

        for atom in formatFiltered {
            let analysis = atom.swipeAnalysis!

            // Axis 1: Format match — compare swipeContentFormat against target format family
            var formatScore = 0.3  // default when swipe has no format data
            if let swipeFormat = analysis.swipeContentFormat {
                if targetFormatFamily.contains(swipeFormat) {
                    formatScore = 1.0  // exact family match (reel swipe for reel content)
                } else if swipeFormat.isVideoFormat && targetWritingFormat.isVideoFormat {
                    formatScore = 0.4  // both video but different family
                } else {
                    formatScore = 0.1  // cross-format mismatch (carousel swipe for reel content)
                }
            }

            // Axis 2: Structural score via BeatPatternService (0.0-1.0)
            var structuralScore = 0.3
            if let fp = analysis.beatFingerprint, !fp.isEmpty {
                structuralScore = topFingerprints.contains(fp) ? 1.0 : 0.3
            }

            // Axis 3: Stylistic score (0.0-1.0)
            let transcript = atom.body ?? ""
            let stylisticScore = computeStylisticScore(swipeTranscript: transcript, clientProfile: clientMeta)

            // Axis 4: Performance score (normalized 0.0-1.0)
            let perfScore = min((analysis.hookScore ?? 0.0) / 10.0, 1.0)

            // Weighted fusion
            var finalScore = 0.3 * formatScore + 0.25 * structuralScore + 0.2 * stylisticScore + 0.25 * perfScore

            // Priority boost for primary swipes (inherited from idea activation or linked by user)
            if primarySwipeUUIDs.contains(atom.uuid) {
                finalScore += 0.5
            }

            let hookType = analysis.hookType?.rawValue ?? "unknown"

            scored.append((atom: atom, finalScore: finalScore, hookType: hookType))
        }

        // Sort by final score descending
        let sortedCandidates = scored.sorted { $0.finalScore > $1.finalScore }

        // Select diverse examples ensuring >= 2 different hook types
        var selected: [Atom] = []
        var selectedHookTypes = Set<String>()
        var usedFingerprints: Set<String> = []

        for candidate in sortedCandidates {
            if selected.count >= maxSwipes { break }
            let fp = candidate.atom.swipeAnalysis?.beatFingerprint ?? UUID().uuidString
            let hookType = candidate.hookType

            // Prefer diverse fingerprints and hook types
            if usedFingerprints.contains(fp) && selected.count > 0 { continue }
            if selectedHookTypes.count >= 2 && !selectedHookTypes.contains(hookType) && selected.count >= maxSwipes - 1 { continue }

            selected.append(candidate.atom)
            selectedHookTypes.insert(hookType)
            usedFingerprints.insert(fp)
        }

        // Fill remaining slots with top scorers
        for candidate in sortedCandidates {
            if selected.count >= maxSwipes { break }
            if !selected.contains(where: { $0.uuid == candidate.atom.uuid }) {
                selected.append(candidate.atom)
            }
        }

        // C1: If below minimum, do broader fallback search
        if selected.count < minSwipes {
            let existingUUIDs = Set(selected.map(\.uuid))
            let fallbacks = await selectSwipesFallback(
                contentAtom: contentAtom,
                targetFormat: targetWritingFormat,
                needed: minSwipes - selected.count,
                existingUUIDs: existingUUIDs
            )
            // Fallbacks are already compressed — we'll merge them after compressing `selected`
            // Compress selected swipes and mark primary ones
            selectedSwipes = selected.compactMap { atom in
                guard var compressed = compressSwipe(atom) else { return nil }
                if primarySwipeUUIDs.contains(atom.uuid) {
                    compressed.isPrimary = true
                }
                return compressed
            }
            selectedSwipes.append(contentsOf: fallbacks)
        } else {
            // Compress selected swipes and mark primary ones
            selectedSwipes = selected.compactMap { atom in
                guard var compressed = compressSwipe(atom) else { return nil }
                if primarySwipeUUIDs.contains(atom.uuid) {
                    compressed.isPrimary = true
                }
                return compressed
            }
        }

        // C2: Append client's top-performing posts as client examples
        await appendClientTopPosts(targetFormat: targetWritingFormat)
    }

    /// C1: Broader fallback search when scored selection doesn't meet minimum.
    /// Searches HybridSearchEngine by format name (e.g., "carousel", "reel") and includes
    /// format-matching swipes even without hookType analysis.
    private func selectSwipesFallback(
        contentAtom: Atom,
        targetFormat: WritingContentFormat,
        needed: Int,
        existingUUIDs: Set<String>
    ) async -> [CompressedSwipe] {
        guard needed > 0 else { return [] }

        let formatQuery = targetFormat.displayName.lowercased()
        var fallbackSwipes: [CompressedSwipe] = []

        // Search by format name as query
        if let results = try? await HybridSearchEngine.shared.search(
            query: formatQuery,
            limit: 15,
            entityTypes: [.research]
        ) {
            for result in results {
                guard fallbackSwipes.count < needed else { break }
                guard let uuid = result.entityUUID, !existingUUIDs.contains(uuid) else { continue }
                guard let atom = try? await database.asyncRead({ db in
                    try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db)
                }), atom.isSwipeFileAtom else { continue }

                // C1: Include format-matching swipes even without hookType analysis
                if let compressed = compressSwipe(atom) {
                    fallbackSwipes.append(compressed)
                } else {
                    // Minimal compression for swipes without full analysis
                    let body = atom.body ?? ""
                    guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let title = atom.title ?? "Untitled"
                    let hookText = String(body.prefix(200))
                    fallbackSwipes.append(CompressedSwipe(
                        id: UUID(uuidString: atom.uuid) ?? UUID(),
                        title: title,
                        hookText: hookText,
                        hookType: "Unknown",
                        hookScore: 0,
                        beatSequence: [],
                        keyTransitions: [],
                        ctaText: "",
                        framework: "Unknown",
                        format: formatQuery,
                        fullBodyExcerpt: String(body.prefix(1500))
                    ))
                }
            }
        }

        print("🔧 [UnifiedWritingEngine] Fallback search found \(fallbackSwipes.count) additional swipes for format '\(formatQuery)'")
        return fallbackSwipes
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
            count: 5,
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

        return CompressedSwipe(
            id: UUID(uuidString: atom.uuid) ?? UUID(),
            title: atom.title ?? "Untitled",
            hookText: String(hookText.prefix(500)),
            hookType: analysis.hookType?.displayName ?? "Unknown",
            hookScore: analysis.hookScore ?? 0,
            beatSequence: beats,
            keyTransitions: transitions,
            ctaText: String(ctaText.prefix(150)),
            framework: analysis.frameworkType?.displayName ?? "Unknown",
            format: analysis.frameworkType?.displayName ?? "Unknown",
            fullBodyExcerpt: String(body.prefix(1500))
        )
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
                // Slide 1 (hook): max 80 chars
                if let firstSlide = slides.first, let text = firstSlide["text"] as? String, text.count > 80 {
                    violations.append(ConstraintViolation(constraintName: "Hook slide length", expected: "max 80 chars", actual: "\(text.count) chars", severity: .hard))
                }
                // Body slides: max 150 chars each
                for (i, slide) in slides.dropFirst().dropLast().enumerated() {
                    if let text = slide["text"] as? String, text.count > 150 {
                        violations.append(ConstraintViolation(constraintName: "Slide \(i + 2) length", expected: "max 150 chars", actual: "\(text.count) chars", severity: .hard))
                    }
                }
            } else if content.contains("{") {
                violations.append(ConstraintViolation(constraintName: "JSON format", expected: "valid carousel JSON", actual: "invalid JSON", severity: .hard))
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
    private func detectContentFormat() -> WritingContentFormat {
        guard let atom = contentAtom,
              let meta = atom.metadataValue(as: ContentAtomMetadata.self) else {
            return .staticPost
        }

        switch meta.platform {
        case .instagram:
            // Determine carousel vs reel vs story from content format hints
            let focusState = ContentFocusModeState.from(atom: atom)
            let draft = focusState?.draftContent ?? ""
            if draft.contains("\"slides\"") { return .instagramCarousel }
            if draft.contains("[VISUAL:") { return .instagramReel }
            return .instagramReel // Default for Instagram

        case .twitter:
            let focusState = ContentFocusModeState.from(atom: atom)
            let draft = focusState?.draftContent ?? ""
            if draft.contains("\"tweets\"") { return .twitterThread }
            return .twitterSingle

        case .linkedin: return .linkedinPost
        case .youtube: return .youtubeLongForm
        case .tiktok: return .tiktokScript
        default: return .staticPost
        }
    }

    // MARK: - Memory Management

    /// Summarize older conversation turns when estimated tokens exceed threshold.
    private func summarizeHistoryIfNeeded() async {
        let estimated = estimateTokenCount()
        // Trigger summarization if EITHER token count is high OR message count exceeds 25.
        // The message count threshold catches cases where token estimation is still off,
        // and prevents the UI from rendering 40+ message bubbles which causes 100% CPU.
        let needsSummarization = estimated > tokenSummarizationThreshold || messages.count > 25
        guard needsSummarization else { return }
        guard messages.count > 15 else { return }

        // Keep last 10 messages verbatim, summarize the rest
        let toSummarize = Array(messages.prefix(messages.count - 10))
        let toKeep = Array(messages.suffix(10))

        // Build summary text from older messages
        let summaryInput = toSummarize.map { msg in
            "[\(msg.role.rawValue)] \(msg.content.prefix(300))"
        }.joined(separator: "\n")

        do {
            let summaryPrompt = """
            Summarize the following conversation history into a concise summary (max 500 words). \
            Focus on: creative decisions made, outline/hook choices, framework selection, voice notes, \
            and any user preferences expressed. This summary will replace the original messages.

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

    private func loadLearnedPreferences(clientUUID: String) async -> [(key: String, value: String)] {
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

        // Load inferred lessons from agent learning atoms.
        // Use [String: Any] decode (not [String: String]) because confidence is stored as Double.
        // Match "lessonType" key (not "type") — matches what storeLesson() writes.
        // Include BOTH client-scoped AND universal lessons (empty clientUUID).
        if let lessons = try? await database.asyncRead({ db in
            try Atom.filter(Column("type") == AtomType.agentLearning.rawValue)
                .order(Column("created_at").desc)
                .limit(30)
                .fetchAll(db)
        }) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for atom in lessons {
                guard let metaStr = atom.metadata,
                      let metaData = metaStr.data(using: .utf8),
                      let metaDict = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
                      let lessonType = metaDict["lessonType"] as? String,
                      lessonType == "inferred_lesson" else {
                    continue
                }

                // Match client-scoped lessons + universal lessons (empty clientUUID)
                let lessonClientUUID = metaDict["clientUUID"] as? String ?? ""
                guard lessonClientUUID == clientUUID || lessonClientUUID.isEmpty else {
                    continue
                }

                // Check confidence (stored as Double or NSNumber)
                let confidence: Double
                if let confDouble = metaDict["confidence"] as? Double {
                    confidence = confDouble
                } else if let confStr = metaDict["confidence"] as? String {
                    confidence = Double(confStr) ?? 0
                } else {
                    confidence = 0.6
                }
                guard confidence >= 0.5 else { continue }

                // Try to decode the full InferredLesson for optimizedInstruction
                let scope = lessonClientUUID.isEmpty ? "[universal]" : "[client-specific]"
                if let structuredStr = atom.structured,
                   let structuredData = structuredStr.data(using: .utf8),
                   let lesson = try? decoder.decode(InferredLesson.self, from: structuredData) {
                    if let optimized = lesson.optimizedInstruction, !optimized.isEmpty {
                        // Best path: use the optimized instruction (has RULE/BAD/GOOD/WHY format)
                        prefs.append((key: "writing_rule", value: "\(scope) \(optimized)"))
                    } else {
                        // Structured fallback: format as RULE/EVIDENCE/CATEGORY
                        let formatted = "RULE: \(lesson.rule)\nEVIDENCE: \(lesson.evidence)\nCATEGORY: \(lesson.category)"
                        prefs.append((key: "writing_rule", value: "\(scope) \(formatted)"))
                    }
                } else {
                    // Last resort: prefix raw body with RULE:
                    let rule = atom.body ?? ""
                    if !rule.isEmpty {
                        prefs.append((key: "writing_rule", value: "\(scope) RULE: \(rule)"))
                    }
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

    private func loadRelevantExperiences(clientUUID: String, format: String, topic: String) async -> [(generated: String, edited: String, diffSummary: String)] {
        var experiences: [(generated: String, edited: String, diffSummary: String)] = []

        if let atoms = try? await database.asyncRead({ db in
            try Atom.filter(Column("type") == AtomType.agentLearning.rawValue)
                .order(Column("created_at").desc)
                .limit(10)
                .fetchAll(db)
        }) {
            for atom in atoms {
                if let metadata = atom.metadataValue(as: [String: String].self),
                   let expType = metadata["type"],
                   expType == "experience",
                   let expClientUUID = metadata["clientUUID"],
                   expClientUUID == clientUUID {
                    if let body = atom.body,
                       let data = body.data(using: .utf8),
                       let exp = try? JSONDecoder().decode(ExperienceEntry.self, from: data) {
                        experiences.append((generated: exp.generatedExcerpt, edited: exp.editedExcerpt, diffSummary: exp.diffSummary))
                    }
                }
            }
        }

        return experiences
    }

    // MARK: - Helpers

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

    // MARK: - Token Budget Constants (C5)

    /// Maximum character budget for Block 1 (methodology + platform constraints).
    /// ~22K chars ≈ ~5.5K tokens at 4 chars/token.
    private let block1MaxChars = 22_000

    /// Maximum character budget for Block 2 (client intelligence model + brand story).
    /// ~18K chars ≈ ~4.5K tokens at 4 chars/token.
    private let block2MaxChars = 18_000

    private func buildCachedBlocks(contentAtom: Atom) {
        _ = assembleBlock1()
        _ = assembleBlock2()
        enforceTokenBudgets()
    }

    /// C5: Enforce token budgets on cached blocks. Truncates verbose sections to stay within limits.
    /// Block 1: truncate methodology theory first. Block 2: truncate verbose profile sections.
    /// Block 3 is unlimited and never truncated below minimums.
    private func enforceTokenBudgets() {
        // Enforce Block 1 budget
        if var block1 = cachedBlock1, block1.count > block1MaxChars {
            print("⚠️ [UnifiedWritingEngine] Block 1 exceeds budget: \(block1.count)/\(block1MaxChars) chars — truncating methodology theory")
            // Truncate from the end (methodology theory is typically at the tail)
            block1 = String(block1.prefix(block1MaxChars))
            // Find last complete section boundary (double newline) to avoid mid-sentence cuts
            if let lastBreak = block1.range(of: "\n\n", options: .backwards, range: block1.startIndex..<block1.endIndex) {
                block1 = String(block1[block1.startIndex..<lastBreak.upperBound])
            }
            block1 += "\n[... methodology truncated for token budget]"
            cachedBlock1 = block1
        }

        // Enforce Block 2 budget
        if var block2 = cachedBlock2, block2.count > block2MaxChars {
            print("⚠️ [UnifiedWritingEngine] Block 2 exceeds budget: \(block2.count)/\(block2MaxChars) chars — truncating verbose profile sections")
            block2 = String(block2.prefix(block2MaxChars))
            if let lastBreak = block2.range(of: "\n\n", options: .backwards, range: block2.startIndex..<block2.endIndex) {
                block2 = String(block2[block2.startIndex..<lastBreak.upperBound])
            }
            block2 += "\n[... profile data truncated for token budget]"
            cachedBlock2 = block2
        }

        // Log actual sizes for monitoring
        let b1Size = cachedBlock1?.count ?? 0
        let b2Size = cachedBlock2?.count ?? 0
        print("📊 [UnifiedWritingEngine] Block sizes — B1: \(b1Size) chars (\(b1Size * 100 / max(block1MaxChars, 1))% of budget), B2: \(b2Size) chars (\(b2Size * 100 / max(block2MaxChars, 1))% of budget)")
    }

    /// Build a context reminder message injected before the first user message.
    /// This tells the AI EXACTLY what context is loaded and demands it use it.
    private func buildContextReminder() -> String {
        var parts: [String] = []
        parts.append("[CONTEXT LOADED — You MUST analyze ALL of this before responding]")
        parts.append("")

        // Swipe library
        if !selectedSwipes.isEmpty {
            let titles = selectedSwipes.map { "\"\($0.title)\"" }.joined(separator: ", ")
            parts.append("SWIPE EXAMPLES (\(selectedSwipes.count) loaded): \(titles)")
            parts.append("→ You MUST use the think tool to analyze these swipes first. Reference specific hooks, structures, and scores from the swipe data in your response.")
        } else {
            parts.append("SWIPE EXAMPLES: None loaded. Use the search_swipes tool to find relevant examples before making recommendations.")
        }
        parts.append("")

        // Client profile
        if let meta = clientMeta {
            var profileParts: [String] = []
            profileParts.append("Client: \(meta.clientName)")
            if let niche = meta.niche { profileParts.append("Niche: \(niche)") }
            if let beliefs = meta.coreBeliefs, !beliefs.isEmpty {
                profileParts.append("Core Beliefs: \(beliefs.joined(separator: ", "))")
            }
            if let phrases = meta.signaturePhrases, !phrases.isEmpty {
                profileParts.append("Signature Phrases: \(phrases.joined(separator: " | "))")
            }
            let hasIntelligenceModel = meta.intelligenceModel != nil
            let hasTopPosts = meta.topPerformingTranscripts?.isEmpty == false || hasIntelligenceModel
            parts.append("CONTENT PROFILE: \(profileParts.joined(separator: " | "))")
            if hasIntelligenceModel {
                parts.append("→ Intelligence Model loaded with voice fingerprint, failure rules, and performance data.")
            }
            if hasTopPosts {
                parts.append("→ Top-performing posts loaded. Study their structure and voice before generating.")
            }
            parts.append("→ You MUST reference the client's voice, beliefs, and stance in every response. Do NOT respond as a generic AI — respond as someone who deeply knows this creator.")
        } else {
            parts.append("CONTENT PROFILE: None linked. Use the get_client_profile tool to search for and load a client profile by name. If the user mentions a creator name, search for it immediately.")
        }
        parts.append("")

        // Platform
        if let atom = contentAtom {
            let contentMeta = atom.metadataValue(as: ContentAtomMetadata.self)
            if let platform = contentMeta?.platform {
                parts.append("TARGET PLATFORM: \(platform.displayName) — Hard format constraints apply.")
            }
        }

        parts.append("")
        parts.append("MANDATORY FIRST STEP: Before answering, use the think tool to:")
        parts.append("1. Review all loaded swipe examples — note their hook types, scores, and structural patterns")
        parts.append("2. Review the client profile — note their voice, beliefs, stances, and what makes their content unique")
        parts.append("3. Review top-performing posts — identify what patterns drove their success")
        parts.append("4. Only THEN respond to the user's request, citing specific evidence from this analysis")

        return parts.joined(separator: "\n")
    }

    private func labelForTool(_ name: String) -> String {
        switch name {
        case "think": return "Reasoning..."
        case "update_outline": return "Updating outline"
        case "add_hooks": return "Generating hooks"
        case "set_description": return "Setting description"
        case "write_draft": return "Writing draft"
        case "edit_section": return "Editing section"
        case "search_swipes": return "Searching swipe library"
        case "search_connections": return "Searching knowledge graph"
        case "read_draft": return "Reading current draft"
        case "get_client_profile": return "Loading client profile"
        case "run_scorecard": return "Running scorecard"
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
                "timestamp": ISO8601DateFormatter().string(from: msg.timestamp)
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
                    atom.updatedAt = ISO8601DateFormatter().string(from: Date())
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
    static let unifiedEngineOutlineUpdate = Notification.Name("unifiedEngineOutlineUpdate")
    static let unifiedEngineHooksUpdate = Notification.Name("unifiedEngineHooksUpdate")
    static let unifiedEngineDescriptionUpdate = Notification.Name("unifiedEngineDescriptionUpdate")
    static let unifiedEngineDraftUpdate = Notification.Name("unifiedEngineDraftUpdate")
    static let unifiedEngineSectionEdit = Notification.Name("unifiedEngineSectionEdit")
    static let unifiedEngineScorecardResult = Notification.Name("unifiedEngineScorecardResult")
}
