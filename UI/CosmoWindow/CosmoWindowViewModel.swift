// CosmoOS/UI/CosmoWindow/CosmoWindowViewModel.swift
// Singleton brain for the global floating Cosmo chat window
// Handles message routing, context tracking, and conversation persistence
// February 2026

import SwiftUI
import Combine

@MainActor
final class CosmoWindowViewModel: ObservableObject {
    static let shared = CosmoWindowViewModel()

    // MARK: - Published State

    @Published var messages: [CosmoWindowMessage] = []
    @Published var isProcessing: Bool = false
    @Published var activeContext: CosmoActiveContext = .none
    @Published var inputText: String = "" {
        didSet {
            collaboratorSessions.saveDraft(inputText, for: collaboratorSessionKey)
        }
    }
    @Published var error: String? = nil
    @Published var processingStartedAt: Date?
    @Published private(set) var collaboratorSessionKey: CollaboratorSessionKey?
    @Published private(set) var collaboratorTarget: CollaborationTarget?
    @Published private(set) var collaboratorPreset: CollaboratorPreset?

    // MARK: - Live Tool Activity (WP5)

    @Published var liveToolActivity: [ToolActivityGroup] = []
    @Published var activeToolLabel: String? = nil
    /// Coalesced scroll tick — incremented on group-level changes only (not per-item).
    /// CosmoWindowView observes this instead of liveToolActivity.count to avoid render loops.
    @Published var toolActivityScrollTick: Int = 0

    // MARK: - Mention State (WP2 - @ Mention System)

    @Published var mentionedAtoms: [Atom] = []
    @Published var showMentionOverlay = false
    @Published var mentionSearchText = ""
    @Published var modelOverride: AgentModelTier? = nil
    @Published var selectedAgentProfileID: String? = nil
    @Published private(set) var agentProfiles: [CustomAgentProfile] = []
    @Published var pendingCanvasPlan: PendingCanvasPlan? = nil

    // MARK: - Edit State

    @Published var pendingEditIndex: Int? = nil

    // MARK: - Dependencies

    private let agentService = CosmoAgentService.shared
    private let contextAssembler = AgentContextAssembler.shared
    private let conversationMemory = ConversationMemoryService.shared
    private let toolRegistry = AgentToolRegistry.shared
    private let collaboratorSessions = CollaboratorSessionStore.shared
    private let agentProfileStore = CustomAgentProfileStore.shared

    // MARK: - Chat History State

    @Published var showChatHistory = false
    @Published var chatHistoryEntries: [ChatHistoryEntry] = []
    @Published var historySearchText = ""

    // MARK: - Conversation Persistence

    private let globalConversationDefaultsKey = "cosmoWindow.lastConversationId"
    private var globalConversationId: String = UserDefaults.standard.string(forKey: "cosmoWindow.lastConversationId") ?? "cosmo-global-window"
    private var conversationId: String = UserDefaults.standard.string(forKey: "cosmoWindow.lastConversationId") ?? "cosmo-global-window"
    private var linkedAtomUUIDs: Set<String> = []
    private let messageArchiveKeyPrefix = "cosmoWindow.messageArchive."

    // MARK: - Context Tracking

    private weak var contextProvider: (any CosmoContextProvider)?
    private var previousContextType: CosmoContextType = .none

    // MARK: - Writing Engine Sessions (per-content keyed by atom UUID)

    private var writingEngineSessions: [String: UnifiedWritingEngine] = [:]

    // MARK: - Cancellation

    private var currentTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var pendingContextTraceSections: [ContextTraceSection] = []

    // MARK: - Init

    private init() {
        conversationId = globalConversationId
        setupNotificationObservers()
        Task { await loadAgentProfiles() }
    }

    // MARK: - Send Message (Unified Pipeline — matches Telegram routing)

    /// Main entry point for user messages. Routes through the same pipeline as Telegram:
    /// writing mode → inline capture → fast URL capture → FlashLiteRouter → full agent
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // /clear command — start a new chat session
        if trimmed.lowercased() == "/clear" {
            inputText = ""
            await startNewChat()
            messages.append(.system("New chat started. Previous conversation saved to history."))
            return
        }

        // Clear input immediately
        inputText = ""

        // Reset live tool activity for new message
        liveToolActivity = []
        activeToolLabel = nil
        toolActivityScrollTick = 0
        pendingContextTraceSections = []
        processingStartedAt = Date()

        // Capture mention info for the user message before clearing
        let mentionInfo: [MentionedAtomInfo]? = mentionedAtoms.isEmpty ? nil : mentionedAtoms.map {
            MentionedAtomInfo(uuid: $0.uuid, type: $0.type.rawValue, title: $0.title ?? "Untitled")
        }

        // Append user message to chat (with mention metadata)
        let userMessage = CosmoWindowMessage.user(trimmed, mentionedAtoms: mentionInfo)
        messages.append(userMessage)

        isProcessing = true
        error = nil

        // Create a placeholder assistant message for streaming
        let assistantId = UUID()
        let placeholder = CosmoWindowMessage(
            id: assistantId,
            type: .assistant,
            content: "",
            isStreaming: true
        )
        messages.append(placeholder)

        currentTask = Task {
            do {
                let response = await routeUnified(text: trimmed, assistantId: assistantId)

                // If routeUnified returned a response, update the placeholder
                if let response = response {
                    let frozenGroups = liveToolActivity.isEmpty ? nil : liveToolActivity
                    updateAssistantMessage(id: assistantId, content: response, isStreaming: false, toolActivityGroups: frozenGroups)
                    liveToolActivity = []
                    activeToolLabel = nil
                }

                // Persist conversation
                await persistConversation()

            } catch is CancellationError {
                updateAssistantMessage(id: assistantId, content: "Cancelled.", isStreaming: false)
            }

            isProcessing = false
            processingStartedAt = nil
            currentTask = nil
        }
    }

    // MARK: - Unified Routing Pipeline

    /// Routes a message through the same pipeline as Telegram's processBufferedMessage:
    /// 1. Writing mode entry  2. Active writing session (exit/commit/inline-capture/route)
    /// 3. Fast URL capture  4. FlashLiteRouter  5. Full agent
    /// Returns nil if the response was already set on the assistant message (e.g. autoCreateContentAndRoute).
    private func routeUnified(text: String, assistantId: UUID) async -> String? {
        let writingManager = TelegramWritingSessionManager.shared

        // 1. Writing mode entry ("opus mode", etc.)
        if writingManager.isWritingTrigger(text) {
            let response = await writingManager.startSession(chatId: conversationId, text: text)
            return response
        }

        // 2. Active writing session
        if writingManager.hasActiveSession(for: conversationId) {
            // 2a. Exit command
            if writingManager.isExitCommand(text) {
                let response = await writingManager.endSession(chatId: conversationId)
                return response
            }
            // 2b. Commit command
            if writingManager.isCommitCommand(text) {
                let response = await writingManager.commitSession(chatId: conversationId)
                return response
            }
            // 2c. Inline capture escape (!idea:, !task:, !swipe:, bare URL)
            if let captureResult = await tryInlineCaptureEscape(text: text) {
                return captureResult + "\n\n_(back in writing mode)_"
            }
            // 2d. Route to writing engine
            let response = await writingManager.routeMessage(chatId: conversationId, text: text)
            return response
        }

        // 3. Fast URL capture
        if text.range(of: "https?://[^\\s]+", options: .regularExpression) != nil {
            if let captureResult = await tryFastURLCapture(text: text) {
                await saveFlashRouterResult(text: text, response: captureResult, toolName: "capture_swipe")
                return captureResult
            }
        }

        // 4. FlashLiteRouter for quick single-shot operations
        // Skip flash router when mentions are present — mentions signal contextual reasoning
        let bypassFlash: Bool
        if !mentionedAtoms.isEmpty || selectedAgentProfile != nil || !forcedToolBundles(for: text).isEmpty {
            bypassFlash = true
        } else {
            bypassFlash = Self.shouldBypassFlashRouter(
                text: text,
                recentAssistantContents: recentAssistantContentsForFlashBypass
            )
        }
        if !bypassFlash, let (flashResponse, toolName) = await FlashLiteRouter.shared.tryRoute(text) {
            await saveFlashRouterResult(text: text, response: flashResponse, toolName: toolName)
            return flashResponse
        }

        // 5. Full agent — route to CosmoAgentService (same as Telegram fallback)
        let response = await routeToAgentService(text: text)
        return response
    }

    // MARK: - Inline Capture Escape (WP4 — shared with Telegram)

    /// Detects inline capture patterns during writing sessions: !idea:, !task:, !swipe:, bare URLs
    private func tryInlineCaptureEscape(text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // !idea: prefix
        if trimmed.lowercased().hasPrefix("!idea:") {
            let content = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            let result = (try? await AgentToolExecutor.shared.execute(toolName: "create_idea", arguments: ["title": content])) ?? "Created"
            return "Captured idea: \(content)\n\(result)"
        }

        // !task: prefix
        if trimmed.lowercased().hasPrefix("!task:") {
            let content = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            let result = (try? await AgentToolExecutor.shared.execute(toolName: "create_task", arguments: ["title": content])) ?? "Created"
            return "Captured task: \(content)\n\(result)"
        }

        // !swipe: prefix
        if trimmed.lowercased().hasPrefix("!swipe:") {
            let content = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            if let captureResult = await tryFastURLCapture(text: content) {
                return captureResult
            }
            return nil
        }

        // Bare URL (< 120 chars, in writing mode only)
        if trimmed.count < 120,
           trimmed.range(of: "^https?://[^\\s]+$", options: .regularExpression) != nil {
            if let captureResult = await tryFastURLCapture(text: trimmed) {
                return captureResult
            }
        }

        return nil
    }

    // MARK: - Fast URL Capture (local version for CosmoWindow)

    /// Attempts fast-path URL capture via FlashLiteRouter, bypassing the full agent.
    private func tryFastURLCapture(text: String) async -> String? {
        // Delegate to FlashLiteRouter which handles swipe capture for URLs
        if let (response, _) = await FlashLiteRouter.shared.tryRoute(text) {
            return response
        }
        return nil
    }

    // MARK: - FlashLiteRouter Follow-Up Detection

    private var recentAssistantContentsForFlashBypass: [String] {
        Array(messages.compactMap { message in
            guard case .assistant = message.type else { return nil }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        }.suffix(3))
    }

    /// Check if a message is a follow-up about already-captured content (should bypass FlashLiteRouter).
    nonisolated static func shouldBypassFlashRouter(text: String, recentAssistantContents: [String]) -> Bool {
        guard !recentAssistantContents.isEmpty else { return false }

        let capturePatterns = ["captured", "saved idea", "saved research", "swipe",
                               "idea:", "task created", "content created"]
        let hasCaptureHistory = recentAssistantContents.contains { content in
            let lower = content.lowercased()
            return capturePatterns.contains(where: { lower.contains($0) })
        }

        guard hasCaptureHistory else { return false }

        let lower = text.lowercased()
        let followUpSignals = [
            "this idea", "that idea", "the idea", "this swipe", "that swipe", "the swipe",
            "take action", "action on", "action this", "act on this",
            "using the", "using this as", "using that", "based on",
            "make the hook", "make a hook", "make the content", "make content",
            "similar to", "like the", "same style", "same hook", "same angle",
            "let's do", "let's make", "let's create", "let's write", "let's draft",
            "turn this into", "turn that into", "make this into"
        ]

        return followUpSignals.contains(where: { lower.contains($0) })
    }

    /// Save FlashLiteRouter-handled messages to conversation memory for follow-up context.
    private func saveFlashRouterResult(text: String, response: String, toolName: String) async {
        var conversation: AgentConversation
        if let existing = await conversationMemory.loadConversation(id: conversationId) {
            conversation = existing
        } else {
            conversation = AgentConversation(id: conversationId, source: .inApp)
        }
        conversation.append(.user(text))
        conversation.append(.assistant(response))
        await conversationMemory.saveConversation(conversation)
    }

    // MARK: - Mention Management (WP2)

    /// Adds an atom as @-mentioned context for the next message.
    func addMention(_ atom: Atom) {
        // Avoid duplicates
        guard !mentionedAtoms.contains(where: { $0.uuid == atom.uuid }) else { return }
        mentionedAtoms.append(atom)
        showMentionOverlay = false
        mentionSearchText = ""

        // Track linked atom UUID for conversation persistence
        linkedAtomUUIDs.insert(atom.uuid)
    }

    /// Removes a previously @-mentioned atom.
    func removeMention(_ atom: Atom) {
        mentionedAtoms.removeAll { $0.uuid == atom.uuid }
    }

    /// Clears all @-mentioned atoms after sending.
    func clearMentions() {
        mentionedAtoms.removeAll()
    }

    // MARK: - Context Management

    /// Called by views when they become active to register their context provider.
    func updateContext(provider: any CosmoContextProvider) {
        let newType = provider.contextType
        let oldType = activeContext.type

        contextProvider = provider

        activeContext = CosmoActiveContext(
            type: newType,
            summary: provider.contextSummary,
            data: provider.contextData,
            actions: provider.availableActions
        )

        previousContextType = newType

        // Post notification for any observers
        NotificationCenter.default.post(
            name: CosmoNotification.CosmoWindow.contextChanged,
            object: nil,
            userInfo: ["contextType": newType.rawValue]
        )
    }

    /// Clears the current context (e.g., when leaving a focus mode).
    func clearContext() {
        contextProvider = nil
        activeContext = .none
    }

    /// Lightweight context update from MainView (no full CosmoContextProvider needed).
    /// Used when the window opens or the user navigates between top-level views.
    func updateContextManually(type: CosmoContextType) {
        activeContext = CosmoActiveContext(
            type: type,
            summary: type.displayName,
            data: CosmoContextData(),
            actions: []
        )

        previousContextType = type
    }

    /// Refreshes context data from the current provider without changing the provider itself.
    func refreshContext() {
        guard let provider = contextProvider else { return }
        activeContext = CosmoActiveContext(
            type: provider.contextType,
            summary: provider.contextSummary,
            data: provider.contextData,
            actions: provider.availableActions
        )
    }

    var isCollaboratorActive: Bool {
        collaboratorSessionKey != nil && collaboratorTarget != nil && collaboratorPreset != nil
    }

    var currentPromptSuggestions: [String] {
        if let selectedAgentProfile {
            return agentSuggestions(for: selectedAgentProfile)
        }
        if let collaboratorPreset {
            return collaboratorPreset.seedPrompts
        }
        return defaultPromptSuggestions
    }

    var currentHeaderSubtitle: String {
        if let collaboratorTarget {
            return "\(collaboratorTarget.displayTypeLabel) · \(collaboratorTarget.title)"
        }
        if let selectedAgentProfile {
            return selectedAgentProfile.summary
        }
        if activeContext.type == .none {
            return "Global assistant"
        }
        return activeContext.type.displayName
    }

    var selectedAgentProfile: CustomAgentProfile? {
        guard let selectedAgentProfileID else { return nil }
        return agentProfiles.first(where: { $0.id == selectedAgentProfileID && $0.isEnabled })
    }

    var currentAgentLabel: String {
        selectedAgentProfile?.name ?? "Auto Cosmo"
    }

    var currentAgentIcon: String {
        selectedAgentProfile?.icon ?? "sparkles"
    }

    var isCurrentContextDockable: Bool {
        guard let currentAtomUUID = activeContext.data.currentAtomUUID else { return false }
        guard !currentAtomUUID.isEmpty else { return false }
        return dockableEntityType != nil
    }

    var dockableContextAtomUUID: String? {
        guard isCurrentContextDockable else { return nil }
        return activeContext.data.currentAtomUUID
    }

    var currentCollaboratorPresetID: String? {
        collaboratorPreset?.id
    }

    private var dockableEntityType: EntityType? {
        switch activeContext.type {
        case .connectionFocusMode:
            return .connection
        case .ideaFocusMode:
            return .idea
        case .noteFocusMode:
            return .note
        case .contentFocusMode:
            return .content
        default:
            return nil
        }
    }

    func activateCollaborator(target: CollaborationTarget, presetID: String? = nil) async {
        let preset = presetForID(presetID)
        let key = collaboratorSessions.activate(target: target, preset: preset)

        if conversationId != key.conversationID {
            await persistConversation()
            conversationId = key.conversationID
        }

        collaboratorSessionKey = key
        collaboratorTarget = target
        collaboratorPreset = preset
        inputText = collaboratorSessions.draft(for: key)
        linkedAtomUUIDs.insert(target.atomUUID)
        await loadConversation()
    }

    func deactivateCollaborator() async {
        guard collaboratorSessionKey != nil else { return }

        await persistConversation()

        collaboratorSessions.clearActive()
        collaboratorSessionKey = nil
        collaboratorTarget = nil
        collaboratorPreset = nil
        mentionedAtoms.removeAll()
        showMentionOverlay = false
        mentionSearchText = ""
        inputText = ""

        if conversationId != globalConversationId {
            conversationId = globalConversationId
        }

        await loadConversation()
    }

    func performAction(_ action: CosmoWindowAction, prompt: String = "") async {
        do {
            let response = try await action.handler(prompt)
            messages.append(.system(response))
            refreshContext()
            await persistConversation()
        } catch {
            messages.append(.system(error.localizedDescription))
        }
    }

    private func presetForID(_ presetID: String?) -> CollaboratorPreset {
        switch presetID {
        case nil, "deepen":
            return .deepen
        default:
            return .deepen
        }
    }

    func loadAgentProfiles() async {
        await agentProfileStore.loadProfiles()
        agentProfiles = agentProfileStore.profiles
        if let selectedAgentProfileID,
           !agentProfiles.contains(where: { $0.id == selectedAgentProfileID && $0.isEnabled }) {
            self.selectedAgentProfileID = nil
        }
    }

    func selectAgentProfile(_ profile: CustomAgentProfile?) {
        selectedAgentProfileID = profile?.id
        modelOverride = modelOverride ?? profile?.preferredModelTier
    }

    func saveAgentProfile(_ profile: CustomAgentProfile) async {
        await agentProfileStore.save(profile)
        await loadAgentProfiles()
    }

    func deleteAgentProfile(_ profile: CustomAgentProfile) async {
        await agentProfileStore.delete(profile)
        if selectedAgentProfileID == profile.id {
            selectedAgentProfileID = nil
        }
        await loadAgentProfiles()
    }

    func cancelPendingCanvasPlan() {
        pendingCanvasPlan = nil
    }

    func revisePendingCanvasPlan() {
        guard let plan = pendingCanvasPlan else { return }
        inputText = "Revise this canvas plan: \(plan.title). "
        pendingCanvasPlan = nil
    }

    func applyPendingCanvasPlan() {
        guard let plan = pendingCanvasPlan else { return }
        let applied = applyCanvasOperations(plan.operations)
        pendingCanvasPlan = nil
        messages.append(.system("Applied \(applied) of \(plan.operations.count) canvas operations."))
    }

    // MARK: - Conversation Lifecycle

    /// Loads the persisted global conversation on app launch.
    func loadConversation() async {
        let storedMessages = loadStoredMessages(for: conversationId)

        if let conversation = await conversationMemory.loadConversation(id: conversationId) {
            linkedAtomUUIDs = Set(conversation.linkedAtomUUIDs)

            if let storedMessages {
                messages = storedMessages
            } else {
                messages = conversation.messages.compactMap { agentMsg in
                    switch agentMsg.role {
                    case .user:
                        return CosmoWindowMessage.user(agentMsg.content)
                    case .assistant:
                        return CosmoWindowMessage.assistant(agentMsg.content)
                    case .system:
                        return CosmoWindowMessage.system(agentMsg.content)
                    case .tool:
                        return CosmoWindowMessage.toolResult(
                            name: "tool",
                            summary: String(agentMsg.content.prefix(120))
                        )
                    }
                }
            }
        } else if let storedMessages {
            messages = storedMessages
        } else {
            messages = []
        }
    }

    /// Clears the conversation history.
    func clearConversation() async {
        messages.removeAll()
        linkedAtomUUIDs.removeAll()
        error = nil
        writingEngineSessions.removeAll()
        processingStartedAt = nil
        pendingContextTraceSections = []

        // Persist the empty state
        await persistConversation()
    }

    /// Cancels any currently running operation.
    func cancelCurrentOperation() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        processingStartedAt = nil
        pendingContextTraceSections = []
        liveToolActivity = []
        activeToolLabel = nil
        messages.append(.system("Operation cancelled."))
    }

    // MARK: - Edit & Resend

    /// Copies a past user message's content into the input field for editing.
    func editAndResend(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        inputText = messages[index].content
        pendingEditIndex = index
    }

    /// Truncates the conversation to the pending edit index and sends a new message.
    func sendEditedMessage(_ text: String) async {
        guard let editIndex = pendingEditIndex else {
            await sendMessage(text)
            return
        }
        // Remove the edited message and everything after it
        messages = Array(messages.prefix(editIndex))
        pendingEditIndex = nil
        await sendMessage(text)
    }

    // MARK: - Token Usage

    /// Estimated token count for the current conversation (rough: 4 chars per token).
    var estimatedTokenUsage: Int {
        messages.reduce(0) { $0 + ($1.content.count / 4) }
    }

    var currentModelLabel: String {
        switch modelOverride {
        case nil: return "Auto"
        case .sensor: return "Haiku"
        case .strategist: return "Sonnet"
        case .writer: return "Opus"
        }
    }

    var filteredChatHistoryEntries: [ChatHistoryEntry] {
        let query = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return chatHistoryEntries }
        return chatHistoryEntries.filter { entry in
            entry.preview.lowercased().contains(query)
        }
    }

    private var defaultPromptSuggestions: [String] {
        let title = activeContext.data.currentAtomTitle ?? "what I’m looking at"

        switch activeContext.type {
        case .commandCenter:
            return [
                "What deserves attention in Command Center?",
                "Summarize what changed recently",
                "What should I tackle next?"
            ]
        case .contentFocusMode:
            return [
                "Help me think through \(title)",
                "What problem does this solve?",
                "What would the better version look like?"
            ]
        case .ideaFocusMode, .connectionFocusMode, .noteFocusMode:
            return CollaboratorPromptLibrary.seedPrompts
        case .swipeGallery, .swipeStudy:
            return [
                "What pattern is showing up here?",
                "Find the strongest hook angle",
                "How would I adapt this swipe?"
            ]
        case .researchFocusMode:
            return [
                "Summarize the important takeaways",
                "What contradictions should I examine?",
                "Turn this into actionable notes"
            ]
        case .thinkspaceCanvas:
            return [
                "Summarize what I’m looking at",
                "What should I focus on next?",
                "Turn this into a plan"
            ]
        case .sanctuary:
            return [
                "What deserves attention today?",
                "Summarize my current state",
                "What should I improve first?"
            ]
        case .none:
            return [
                "What should I focus on next?",
                "Help me turn a thought into a plan",
                "Summarize what I’m working on"
            ]
        default:
            return [
                "Help me think through \(title)",
                "What matters most here?",
                "Give me the next best move"
            ]
        }
    }

    // MARK: - Session Management

    /// Starts a new chat session, preserving the current conversation in history.
    func startNewChat() async {
        if isCollaboratorActive {
            await clearConversation()
            return
        }

        // Persist current conversation if it has messages
        if !messages.isEmpty {
            await persistConversation()
        }

        // Generate a new conversation ID
        globalConversationId = "cosmo-window-\(UUID().uuidString.prefix(8).lowercased())"
        conversationId = globalConversationId
        UserDefaults.standard.set(globalConversationId, forKey: globalConversationDefaultsKey)

        // Clear all state
        messages.removeAll()
        linkedAtomUUIDs.removeAll()
        writingEngineSessions.removeAll()
        error = nil
        historySearchText = ""
        processingStartedAt = nil
        pendingContextTraceSections = []

        // Persist the fresh empty conversation (establishes the atom)
        await persistConversation()

        // Refresh history entries
        await loadChatHistory()
    }

    /// Loads recent in-app chat sessions for the history popover.
    func loadChatHistory() async {
        let recent = await conversationMemory.getRecentConversations(limit: 20)
        let inAppConversations = recent.filter { $0.source == .inApp }

        chatHistoryEntries = inAppConversations.map { conv in
            let preview: String
            if let summary = conv.summary, !summary.isEmpty {
                preview = String(summary.prefix(80))
            } else if let firstUser = conv.messages.first(where: { $0.role == .user }) {
                preview = String(firstUser.content.prefix(80))
            } else {
                preview = "Empty conversation"
            }

            // Use the most recent message timestamp if available, otherwise fall back to createdAt
            let lastMessageDate = conv.messages.last?.timestamp ?? conv.createdAt

            return ChatHistoryEntry(
                id: conv.id,
                preview: preview,
                messageCount: conv.messages.count,
                lastActivity: lastMessageDate,
                isActive: conv.id == conversationId
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Switches to a different chat session from history.
    func switchToChat(id: String) async {
        guard !isCollaboratorActive else { return }

        // Persist current conversation first
        if !messages.isEmpty {
            await persistConversation()
        }

        // Switch to the selected conversation
        conversationId = id
        globalConversationId = id
        UserDefaults.standard.set(globalConversationId, forKey: globalConversationDefaultsKey)
        await loadConversation()
        await loadChatHistory()
    }

    // MARK: - Private Helpers

    /// Routes a message through the general CosmoAgentService.
    private func routeToAgentService(text: String) async -> String {
        // Inject current context into the message if available
        let contextBlock = buildContextBlock()

        // Use the agent service with context-enriched prompt
        var enrichedText: String
        if !contextBlock.isEmpty {
            enrichedText = """
            \(text)

            <active_cosmo_context>
            \(contextBlock)
            </active_cosmo_context>
            """
        } else {
            enrichedText = text
        }

        // Inject @-mentioned atom context inline at mention positions
        if !mentionedAtoms.isEmpty {
            enrichedText = MentionContextHelper.expandMentionsInline(
                text: enrichedText,
                atoms: mentionedAtoms
            )
            clearMentions()
        }

        // Wire in-app action buttons callback so `send_action_buttons` tool delivers
        // interactive buttons directly into the CosmoWindow conversation
        let toolExecutor = AgentToolExecutor.shared
        toolExecutor.onActionButtons = { [weak self] message, buttons in
            Task { @MainActor in
                let actionButtons = buttons.map { CosmoActionButton(label: $0.label, action: $0.action) }
                self?.messages.append(.actionButtons(message, buttons: actionButtons))
            }
        }
        toolExecutor.onCanvasPlan = { [weak self] plan in
            Task { @MainActor in
                self?.pendingCanvasPlan = plan
            }
        }

        let activeProfile = selectedAgentProfile
        let forcedBundles = forcedToolBundles(for: text)
        let systemPromptOverride = runtimePromptLayer(
            collaboratorPrompt: collaboratorPreset?.runtimePrompt,
            agentProfile: activeProfile,
            forcedBundles: forcedBundles
        )

        let (response, trace) = await agentService.processMessage(
            enrichedText,
            conversationId: conversationId,
            source: .inApp,
            tierOverride: modelOverride ?? activeProfile?.preferredModelTier,
            systemPromptOverride: systemPromptOverride,
            profileToolBundles: activeProfile?.toolBundles ?? [],
            forcedToolBundles: forcedBundles,
            onToolActivity: { [weak self] event in
                Task { @MainActor in
                    self?.handleToolActivity(event)
                }
            }
        )

        // Clear the action buttons callback after processing
        toolExecutor.onActionButtons = nil
        toolExecutor.onCanvasPlan = nil

        pendingContextTraceSections = trace.hasContent ? CosmoWindowMessage.contextTraceSections(from: trace) : []

        return response
    }

    /// Routes a writing-specific request to a per-content UnifiedWritingEngine session.
    private func routeToWritingEngine(text: String, atomUUID: String) async -> String {
        // Get or create writing engine for this content atom
        let engine: UnifiedWritingEngine
        if let existing = writingEngineSessions[atomUUID] {
            engine = existing
        } else {
            let newEngine = UnifiedWritingEngine()
            // Wire context activity callback so thinking UI shows during writing
            newEngine.onContextActivity = { [weak self] event in
                Task { @MainActor in
                    self?.handleToolActivity(event)
                }
            }
            // Load the content atom and initialize the engine
            if let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                await newEngine.initialize(contentAtom: atom)
            }
            writingEngineSessions[atomUUID] = newEngine
            engine = newEngine
        }

        // Determine the current content step from context data
        // ContentContextProvider stores "step", fallback to "contentStep" for compat
        let stepRaw = activeContext.data.viewSpecificData["step"]
            ?? activeContext.data.viewSpecificData["contentStep"]
            ?? "brainstorm"
        let step: ContentStep
        switch stepRaw {
        case "brainstorm": step = .brainstorm
        case "polish": step = .polish
        default: step = .draft
        }

        // Send the message through the writing engine
        if let response = await engine.sendMessage(text, phase: step) {
            return response.content
        }

        return "I processed your writing request but didn't generate a response."
    }

    /// Builds the dynamic context block for system prompt injection.
    private func buildContextBlock() -> String {
        guard activeContext.type != .none else { return "" }

        var lines: [String] = []
        lines.append("## Current Context: \(activeContext.type.displayName)")
        if !activeContext.summary.isEmpty {
            lines.append(activeContext.summary)
        }

        let contextBlock = activeContext.data.toContextBlock()
        if !contextBlock.isEmpty {
            lines.append(contextBlock)
        }

        if !activeContext.actions.isEmpty {
            lines.append("\nAvailable actions: \(activeContext.actions.map(\.name).joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    private func runtimePromptLayer(
        collaboratorPrompt: String?,
        agentProfile: CustomAgentProfile?,
        forcedBundles: Set<AgentToolBundle>
    ) -> String? {
        var sections: [String] = []

        if let collaboratorPrompt,
           !collaboratorPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(collaboratorPrompt)
        }

        if let agentProfile {
            sections.append(agentProfile.routingPromptLayer)
        }

        if !forcedBundles.isEmpty {
            let bundleList = forcedBundles
                .map(\.displayName)
                .sorted()
                .joined(separator: ", ")
            sections.append("""
            ## Request-Forced Capabilities
            The user's wording or active context explicitly requires these capability bundles: \(bundleList).
            Prefer these tools when they are relevant before answering from memory.
            """)
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private func forcedToolBundles(for text: String) -> Set<AgentToolBundle> {
        let lower = text.lowercased()
        var bundles: Set<AgentToolBundle> = []

        if containsAny(lower, ["research online", "search online", "look up", "latest", "current", "find stats", "statistics", "sources", "citations"]) {
            bundles.insert(.webResearch)
        }
        if containsAny(lower, ["client profile", "client voice", "client memory", "for client", "brand profile"]) {
            bundles.insert(.clientProfiles)
            bundles.insert(.clientMemory)
        }
        if containsAny(lower, ["swipe", "swipes", "examples", "reference ads", "hooks", "frameworks"]) {
            bundles.insert(.swipes)
        }
        if containsAny(lower, ["canvas", "thinkspace", "move", "organize", "reorganize", "spatial", "cluster", "arrange", "place this"]) {
            bundles.insert(.canvasSpatial)
        }
        if containsAny(lower, ["docs", "notes", "database", "db", "content from", "reference docs", "library"]) {
            bundles.insert(.contentSearch)
        }
        if containsAny(lower, ["draft", "write", "rewrite", "edit", "polish", "outline"]) {
            bundles.insert(.writing)
        }

        if activeContext.type == .thinkspaceCanvas {
            bundles.insert(.canvasSpatial)
        }
        if activeContext.type == .contentFocusMode || activeContext.type == .noteFocusMode || activeContext.type == .ideaFocusMode {
            bundles.insert(.contentSearch)
        }
        if activeContext.type == .swipeGallery || activeContext.type == .swipeStudy {
            bundles.insert(.swipes)
        }

        return bundles
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func agentSuggestions(for profile: CustomAgentProfile) -> [String] {
        let prompts = profile.seedPrompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return prompts.isEmpty ? defaultPromptSuggestions : Array(prompts.prefix(3))
    }

    private func applyCanvasOperations(_ operations: [PendingCanvasOperation]) -> Int {
        var applied = 0
        for operation in operations {
            if applyCanvasOperation(operation) {
                applied += 1
            }
        }
        return applied
    }

    private func applyCanvasOperation(_ operation: PendingCanvasOperation) -> Bool {
        let payload = operation.payload

        switch operation.kind {
        case .arrange:
            NotificationCenter.default.post(
                name: .arrangeCanvasBlocks,
                object: nil,
                userInfo: ["style": payload["style"] ?? payload["layout"] ?? "orbital"]
            )
            return true

        case .placeSearch:
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.placeBlocksOnCanvas,
                object: nil,
                userInfo: [
                    "query": payload["query"] ?? "",
                    "entityType": payload["entityType"] ?? "idea",
                    "quantity": Int(payload["quantity"] ?? "") ?? 5,
                    "layout": payload["layout"] ?? "orbital"
                ]
            )
            return true

        case .createEntity:
            guard let entityType = entityType(from: payload["entityType"]) else { return false }
            var userInfo: [AnyHashable: Any] = ["type": entityType]
            if let title = payload["title"] { userInfo["title"] = title }
            if let content = payload["content"] { userInfo["content"] = content }
            if let position = canvasPosition(from: payload) { userInfo["position"] = position }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.createEntityAtPosition,
                object: nil,
                userInfo: userInfo
            )
            return true

        case .placeExistingAtom:
            guard let entityType = entityType(from: payload["entityType"]),
                  let uuid = payload["existingAtomUUID"], !uuid.isEmpty else { return false }
            var userInfo: [AnyHashable: Any] = ["type": entityType, "existingAtomUUID": uuid]
            if let position = canvasPosition(from: payload) { userInfo["position"] = position }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.createEntityAtPosition,
                object: nil,
                userInfo: userInfo
            )
            return true

        case .moveSelection:
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.moveCanvasBlocks,
                object: nil,
                userInfo: [
                    "direction": payload["direction"] ?? "right",
                    "distance": CGFloat(Double(payload["distance"] ?? "") ?? 160)
                ]
            )
            return true

        case .resizeSelection:
            var userInfo: [AnyHashable: Any] = [:]
            if let width = payload["width"].flatMap(Double.init) { userInfo["width"] = CGFloat(width) }
            if let height = payload["height"].flatMap(Double.init) { userInfo["height"] = CGFloat(height) }
            if let scale = payload["scale"].flatMap(Double.init) { userInfo["scale"] = CGFloat(scale) }
            guard !userInfo.isEmpty else { return false }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.resizeSelectedBlock,
                object: nil,
                userInfo: userInfo
            )
            return true

        case .createAIBlock:
            var userInfo: [AnyHashable: Any] = [:]
            if let query = payload["query"] { userInfo["query"] = query }
            if let mode = payload["mode"] { userInfo["mode"] = mode }
            if let position = canvasPosition(from: payload) { userInfo["position"] = position }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.createCosmoAIBlock,
                object: nil,
                userInfo: userInfo
            )
            return true

        case .unsupported:
            return false
        }
    }

    private func entityType(from rawValue: String?) -> EntityType? {
        guard let rawValue else { return .idea }
        return EntityType(rawValue: rawValue)
            ?? EntityType(rawValue: rawValue.replacingOccurrences(of: " ", with: "_"))
            ?? .idea
    }

    private func canvasPosition(from payload: [String: String]) -> CGPoint? {
        guard let xRaw = payload["x"], let yRaw = payload["y"],
              let x = Double(xRaw), let y = Double(yRaw) else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Live Tool Activity Handling (WP5)

    private func handleToolActivity(_ event: ToolActivityEvent) {
        switch event {
        case .started(let name, let displayLabel, _):
            activeToolLabel = displayLabel
            let category = toolActivityCategory(for: name)
            let icon = toolActivityIcon(for: name)
            let item = ToolActivityItem(icon: icon, label: displayLabel, status: .active)

            if let idx = liveToolActivity.firstIndex(where: { $0.category == category }) {
                liveToolActivity[idx].items.append(item)
            } else {
                liveToolActivity.append(ToolActivityGroup(category: category, items: [item]))
                // Only bump scroll tick on new group creation (not every item) to avoid render loop
                toolActivityScrollTick += 1
            }

        case .completed(let name, _, let preview):
            let category = toolActivityCategory(for: name)
            if let gIdx = liveToolActivity.firstIndex(where: { $0.category == category }),
               let iIdx = liveToolActivity[gIdx].items.lastIndex(where: { $0.status == .active }) {
                liveToolActivity[gIdx].items[iIdx] = ToolActivityItem(
                    icon: liveToolActivity[gIdx].items[iIdx].icon,
                    label: liveToolActivity[gIdx].items[iIdx].label,
                    detail: preview,
                    status: .done
                )
            }

        case .allDone:
            activeToolLabel = nil
            for i in liveToolActivity.indices {
                liveToolActivity[i].isComplete = true
            }
            toolActivityScrollTick += 1
        }
    }

    private func toolActivityCategory(for toolName: String) -> String {
        if toolName.hasPrefix("load_") { return "Context Loaded" }
        if toolName.hasPrefix("search_") || toolName.hasPrefix("find_") || toolName.hasPrefix("get_") || toolName.hasPrefix("list_") { return "Viewed" }
        if toolName.hasPrefix("generate_") || toolName.hasPrefix("create_") || toolName.hasPrefix("write_") { return "Generated" }
        if toolName == "web_search" { return "Searched" }
        if toolName.hasPrefix("score_") || toolName.hasPrefix("evaluate_") { return "Analyzed" }
        return "Processed"
    }

    private func toolActivityIcon(for toolName: String) -> String {
        // Context loading tools — specific icons per loaded resource type
        switch toolName {
        case "load_client_profile": return "person.fill"
        case "load_swipe": return "doc.text"
        case "load_client_post": return "star.fill"
        case "load_learned_rules": return "book.fill"
        case "load_skill_modules": return "wrench.and.screwdriver"
        default: break
        }
        if toolName.hasPrefix("search_") || toolName.hasPrefix("find_") || toolName.hasPrefix("get_") || toolName.hasPrefix("list_") { return "doc.text" }
        if toolName.hasPrefix("generate_") || toolName.hasPrefix("create_") || toolName.hasPrefix("write_") { return "sparkles" }
        if toolName == "web_search" { return "globe" }
        if toolName.hasPrefix("score_") || toolName.hasPrefix("evaluate_") { return "chart.bar" }
        return "gearshape"
    }

    // MARK: - Auto-Create Content from Writing Requests

    /// Extracts swipe-related context from the current @-mentioned atoms.
    private func extractSwipeContext() -> (swipeUUIDs: [String], clientUUID: String?, framework: String?, hooks: [String], titleHint: String?) {
        var swipeUUIDs: [String] = []
        var clientUUID: String?
        var framework: String?
        var hooks: [String] = []
        var titleHint: String?

        for atom in mentionedAtoms {
            if titleHint == nil {
                titleHint = atom.title
            }
            if let analysis = atom.swipeAnalysis {
                swipeUUIDs.append(atom.uuid)
                if clientUUID == nil { clientUUID = analysis.clientUUID }
                if framework == nil { framework = analysis.frameworkType?.rawValue }
                if let hook = analysis.hookText { hooks.append(hook) }
            }
        }

        return (swipeUUIDs, clientUUID, framework, hooks, titleHint)
    }

    /// Derives a content title from the user's request text, falling back to a swipe title hint.
    private func deriveTitleFromRequest(_ text: String, fallback: String?) -> String {
        let lower = text.lowercased()
        // Match patterns like "draft a reel about X", "write a carousel on Y"
        let prepositions = ["about ", "on ", "for ", "titled ", "called "]
        for prep in prepositions {
            if let range = lower.range(of: prep) {
                let afterPrep = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !afterPrep.isEmpty {
                    // Take up to first punctuation or end
                    let cleaned = afterPrep.components(separatedBy: CharacterSet(charactersIn: ".!?")).first ?? afterPrep
                    let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && trimmed.count <= 100 {
                        return trimmed
                    }
                }
            }
        }
        return fallback ?? "New Content"
    }

    /// Auto-creates a content atom with inherited swipe context, opens Content Focus Mode,
    /// and routes the message through the UnifiedWritingEngine.
    private func autoCreateContentAndRoute(text: String, assistantId: UUID) async {
        // 1. Extract context from @-mentioned atoms
        let ctx = extractSwipeContext()

        // 2. Build mention block before clearing mentions
        var enrichedText = text
        if !mentionedAtoms.isEmpty {
            let mentionBlock = MentionContextHelper.buildMentionBlock(atoms: mentionedAtoms)
            enrichedText = mentionBlock + "\n---\n" + text
            clearMentions()
        }

        // 3. Create content atom
        let title = deriveTitleFromRequest(text, fallback: ctx.titleHint)
        let pipelineService = ContentPipelineService()
        guard let contentAtom = try? await pipelineService.createContent(
            title: title,
            clientUUID: ctx.clientUUID
        ) else {
            updateAssistantMessage(id: assistantId, content: "Failed to create content atom.", isStreaming: false)
            return
        }

        // 4. Update metadata with inherited swipe context
        if !ctx.swipeUUIDs.isEmpty || ctx.framework != nil || !ctx.hooks.isEmpty {
            _ = try? await AtomRepository.shared.update(uuid: contentAtom.uuid) { atom in
                var meta = atom.metadataValue(as: ContentAtomMetadata.self) ?? ContentAtomMetadata(phase: .ideation, wordCount: 0)
                meta.inheritedSwipeUUIDs = ctx.swipeUUIDs.isEmpty ? nil : ctx.swipeUUIDs
                meta.inheritedFramework = ctx.framework
                meta.inheritedHooks = ctx.hooks.isEmpty ? nil : ctx.hooks
                meta.activatedAt = ISO8601DateFormatter().string(from: Date())
                atom = atom.withMetadata(meta)
            }
        }

        // 5. Open Content Focus Mode (renders behind CosmoWindow at lower zIndex)
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": contentAtom.uuid]
        )

        // 6. System message
        messages.append(.system("Created new content: '\(title)' and opened in Focus Mode."))

        // 7. Wait for focus mode to mount (~800ms for MainView handler delays + view mount)
        try? await Task.sleep(nanoseconds: 800_000_000)

        // 8. Route to writing engine with the new content atom UUID
        let response = await routeToWritingEngine(text: enrichedText, atomUUID: contentAtom.uuid)
        let frozenGroups = liveToolActivity.isEmpty ? nil : liveToolActivity
        updateAssistantMessage(id: assistantId, content: response, isStreaming: false, toolActivityGroups: frozenGroups)
        liveToolActivity = []
        activeToolLabel = nil
    }

    /// Heuristic check for writing-specific requests in content context.
    private func isContentWritingRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        let writingKeywords = [
            "write", "draft", "generate", "rewrite", "expand", "condense",
            "rephrase", "hook", "outline", "section", "slide", "carousel",
            "caption", "cta", "call to action", "body copy", "opening line",
            "brainstorm"
        ]
        return writingKeywords.contains { lower.contains($0) }
    }

    /// Updates an existing assistant message in the messages array (for streaming).
    private func updateAssistantMessage(id: UUID, content: String, isStreaming: Bool, toolActivityGroups: [ToolActivityGroup]? = nil) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            let responseMeta = isStreaming ? nil : buildResponseMeta(toolActivityGroups: toolActivityGroups)
            messages[index] = CosmoWindowMessage(
                id: id,
                type: .assistant,
                content: content,
                timestamp: messages[index].timestamp,
                isStreaming: isStreaming,
                toolActivityGroups: toolActivityGroups,
                responseMeta: responseMeta
            )
        }
        if !isStreaming {
            pendingContextTraceSections = []
        }
    }

    /// Persists the current conversation via ConversationMemoryService.
    private func persistConversation() async {
        // Preserve original createdAt from existing conversation to avoid timestamp reset
        let existingConv = await conversationMemory.loadConversation(id: conversationId)
        var conversation = AgentConversation(id: conversationId, source: .inApp, createdAt: existingConv?.createdAt ?? Date())

        for msg in messages {
            switch msg.type {
            case .user:
                conversation.append(.user(msg.content))
            case .assistant:
                conversation.append(.assistant(msg.content))
            case .system:
                conversation.append(.system(msg.content))
            case .toolResult(let name, _, _):
                conversation.append(.tool(callId: name, content: msg.content))
            case .contextTrace:
                // UI-only messages, not persisted to LLM context
                break
            case .contextChange:
                // UI-only messages, not persisted to LLM context
                break
            case .actionButtons:
                // Action buttons are persisted as assistant messages (content has the button text)
                conversation.append(.assistant(msg.content))
                break
            }
        }

        conversation.linkedAtomUUIDs = Array(linkedAtomUUIDs)
        await conversationMemory.saveConversation(conversation)
        saveStoredMessages(messages, for: conversationId)
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Toggle window
        NotificationCenter.default.publisher(for: CosmoNotification.CosmoWindow.toggle)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Toggle is handled by MainView -- this is for menu bar command routing
                _ = self
            }
            .store(in: &cancellables)
    }

    private func buildResponseMeta(toolActivityGroups: [ToolActivityGroup]?) -> CosmoResponseMeta? {
        let elapsedSeconds: Int?
        if let processingStartedAt {
            elapsedSeconds = max(1, Int(Date().timeIntervalSince(processingStartedAt).rounded()))
        } else {
            elapsedSeconds = nil
        }

        let meta = CosmoResponseMeta(
            elapsedSeconds: elapsedSeconds,
            toolGroups: toolActivityGroups,
            contextTraceSections: pendingContextTraceSections,
            modelLabel: currentModelLabel
        )
        return meta.hasVisibleContent ? meta : nil
    }

    private func messageArchiveKey(for conversationId: String) -> String {
        messageArchiveKeyPrefix + conversationId
    }

    private func loadStoredMessages(for conversationId: String) -> [CosmoWindowMessage]? {
        let key = messageArchiveKey(for: conversationId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let decoded = try? decoder.decode([CosmoWindowMessage].self, from: data) else {
            return nil
        }

        return decoded.compactMap { message in
            // Strip stale context change dividers from persisted history
            if case .contextChange = message.type { return nil }
            var normalized = message
            normalized.isStreaming = false
            normalized.toolActivityGroups = nil
            return normalized
        }
    }

    private func saveStoredMessages(_ messages: [CosmoWindowMessage], for conversationId: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: messageArchiveKey(for: conversationId))
    }

    private func appendContextChangeIfNeeded(from oldType: CosmoContextType, to newType: CosmoContextType) {
        guard shouldSurfaceContextChange(from: oldType, to: newType) else { return }
        messages.append(.contextChange(from: oldType.displayName, to: newType.displayName))
    }

    private func shouldSurfaceContextChange(from oldType: CosmoContextType, to newType: CosmoContextType) -> Bool {
        guard oldType != newType, oldType != .none, newType != .none else { return false }

        let hasConversation = messages.contains { message in
            switch message.type {
            case .user, .assistant, .actionButtons:
                return true
            default:
                return false
            }
        }
        guard hasConversation else { return false }

        if case .contextChange(_, let lastTo)? = messages.last?.type, lastTo == newType.displayName {
            return false
        }

        return true
    }
}

// MARK: - Chat History Entry

struct ChatHistoryEntry: Identifiable {
    let id: String
    let preview: String
    let messageCount: Int
    let lastActivity: Date
    var isActive: Bool
}

// MARK: - Equatable Helpers

extension CosmoWindowMessageType: Equatable {
    static func == (lhs: CosmoWindowMessageType, rhs: CosmoWindowMessageType) -> Bool {
        switch (lhs, rhs) {
        case (.user, .user), (.assistant, .assistant), (.system, .system):
            return true
        case (.toolResult(let n1, let s1, let e1), .toolResult(let n2, let s2, let e2)):
            return n1 == n2 && s1 == s2 && e1 == e2
        case (.contextTrace(let l1, _), .contextTrace(let l2, _)):
            return l1 == l2
        case (.contextChange(let f1, let t1), .contextChange(let f2, let t2)):
            return f1 == f2 && t1 == t2
        case (.actionButtons(let b1), .actionButtons(let b2)):
            return b1 == b2
        default:
            return false
        }
    }
}
