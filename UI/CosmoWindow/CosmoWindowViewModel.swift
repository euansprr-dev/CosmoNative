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
    @Published var inputText: String = ""
    @Published var error: String? = nil

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

    // MARK: - Dependencies

    private let agentService = CosmoAgentService.shared
    private let contextAssembler = AgentContextAssembler.shared
    private let conversationMemory = ConversationMemoryService.shared
    private let toolRegistry = AgentToolRegistry.shared

    // MARK: - Chat History State

    @Published var showChatHistory = false
    @Published var chatHistoryEntries: [ChatHistoryEntry] = []

    // MARK: - Conversation Persistence

    private var conversationId: String = "cosmo-global-window"
    private var linkedAtomUUIDs: Set<String> = []

    // MARK: - Context Tracking

    private weak var contextProvider: (any CosmoContextProvider)?
    private var previousContextType: CosmoContextType = .none

    // MARK: - Writing Engine Sessions (per-content keyed by atom UUID)

    private var writingEngineSessions: [String: UnifiedWritingEngine] = [:]

    // MARK: - Cancellation

    private var currentTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    private init() {
        setupNotificationObservers()
    }

    // MARK: - Send Message

    /// Main entry point for user messages. Routes to writing engine or general
    /// agent service based on current state.
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

        // Capture mention info for the user message before clearing
        let mentionInfo: [MentionedAtomInfo]? = mentionedAtoms.isEmpty ? nil : mentionedAtoms.map {
            MentionedAtomInfo(type: $0.type.rawValue, title: $0.title ?? "Untitled")
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
                // Determine if this is a writing request on a content atom
                let isWritingRequest = isContentWritingRequest(trimmed)
                let contentUUID = activeContext.data.currentAtomUUID

                if isWritingRequest,
                   activeContext.type == .contentFocusMode,
                   let uuid = contentUUID {
                    // Route to UnifiedWritingEngine for content-specific writing
                    let response = await routeToWritingEngine(text: trimmed, atomUUID: uuid)
                    updateAssistantMessage(id: assistantId, content: response, isStreaming: false)
                } else {
                    // Route to general CosmoAgentService
                    let response = await routeToAgentService(text: trimmed)
                    // Freeze live tool activity into the completed message
                    let frozenGroups = liveToolActivity.isEmpty ? nil : liveToolActivity
                    updateAssistantMessage(id: assistantId, content: response, isStreaming: false, toolActivityGroups: frozenGroups)
                    // Clear live activity after freezing
                    liveToolActivity = []
                    activeToolLabel = nil
                }

                // Persist conversation
                await persistConversation()

            } catch is CancellationError {
                updateAssistantMessage(id: assistantId, content: "Cancelled.", isStreaming: false)
            }

            isProcessing = false
        }
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

        // Insert a context change message if type actually changed (not on initial load)
        if oldType != .none && oldType != newType {
            let changeMessage = CosmoWindowMessage.contextChange(
                from: oldType.displayName,
                to: newType.displayName
            )
            messages.append(changeMessage)
        }

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
        let oldType = activeContext.type
        activeContext = CosmoActiveContext(
            type: type,
            summary: type.displayName,
            data: CosmoContextData(),
            actions: []
        )

        if oldType != .none && oldType != type {
            messages.append(.contextChange(from: oldType.displayName, to: type.displayName))
        }
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

    // MARK: - Conversation Lifecycle

    /// Loads the persisted global conversation on app launch.
    func loadConversation() async {
        if let conversation = await conversationMemory.loadConversation(id: conversationId) {
            // Convert AgentMessages to CosmoWindowMessages
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
            linkedAtomUUIDs = Set(conversation.linkedAtomUUIDs)
        }
    }

    /// Clears the conversation history.
    func clearConversation() async {
        messages.removeAll()
        linkedAtomUUIDs.removeAll()
        error = nil
        writingEngineSessions.removeAll()

        // Persist the empty state
        await persistConversation()
    }

    /// Cancels any currently running operation.
    func cancelCurrentOperation() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        messages.append(.system("Operation cancelled."))
    }

    // MARK: - Token Usage

    /// Estimated token count for the current conversation (rough: 4 chars per token).
    var estimatedTokenUsage: Int {
        messages.reduce(0) { $0 + ($1.content.count / 4) }
    }

    // MARK: - Session Management

    /// Starts a new chat session, preserving the current conversation in history.
    func startNewChat() async {
        // Persist current conversation if it has messages
        if !messages.isEmpty {
            await persistConversation()
        }

        // Generate a new conversation ID
        conversationId = "cosmo-window-\(UUID().uuidString.prefix(8).lowercased())"

        // Clear all state
        messages.removeAll()
        linkedAtomUUIDs.removeAll()
        writingEngineSessions.removeAll()
        error = nil

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

            return ChatHistoryEntry(
                id: conv.id,
                preview: preview,
                messageCount: conv.messages.count,
                lastActivity: conv.createdAt,
                isActive: conv.id == conversationId
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Switches to a different chat session from history.
    func switchToChat(id: String) async {
        // Persist current conversation first
        if !messages.isEmpty {
            await persistConversation()
        }

        // Switch to the selected conversation
        conversationId = id
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
            enrichedText = text  // Context is injected via system prompt by AgentContextAssembler
        } else {
            enrichedText = text
        }

        // Inject @-mentioned atom context into the message
        if !mentionedAtoms.isEmpty {
            var mentionBlock = "## Referenced Context\n"
            for atom in mentionedAtoms {
                let typeLabel = atom.type.rawValue.uppercased()
                let title = atom.title ?? "Untitled"
                let body = String((atom.body ?? "").prefix(500))
                mentionBlock += "[\(typeLabel): \"\(title)\"]\n\(body)\n\n"
            }
            enrichedText = mentionBlock + "\n---\n" + enrichedText
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

        let (response, trace) = await agentService.processMessage(
            enrichedText,
            conversationId: conversationId,
            source: .inApp,
            tierOverride: modelOverride,
            onToolActivity: { [weak self] event in
                Task { @MainActor in
                    self?.handleToolActivity(event)
                }
            }
        )

        // Clear the action buttons callback after processing
        toolExecutor.onActionButtons = nil

        // Insert context trace card before the assistant response if tools were used
        if trace.hasContent {
            messages.append(.contextTrace(from: trace))
        }

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
        let stepRaw = activeContext.data.viewSpecificData["contentStep"] ?? "draft"
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

    /// Heuristic check for writing-specific requests in content context.
    private func isContentWritingRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        let writingKeywords = [
            "write", "draft", "generate", "rewrite", "expand", "condense",
            "rephrase", "hook", "outline", "section", "slide", "carousel",
            "caption", "cta", "call to action", "body copy", "opening line"
        ]
        return writingKeywords.contains { lower.contains($0) }
    }

    /// Updates an existing assistant message in the messages array (for streaming).
    private func updateAssistantMessage(id: UUID, content: String, isStreaming: Bool, toolActivityGroups: [ToolActivityGroup]? = nil) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index] = CosmoWindowMessage(
                id: id,
                type: .assistant,
                content: content,
                timestamp: messages[index].timestamp,
                isStreaming: isStreaming,
                toolActivityGroups: toolActivityGroups
            )
        }
    }

    /// Persists the current conversation via ConversationMemoryService.
    private func persistConversation() async {
        // Convert CosmoWindowMessages to AgentMessages for storage
        var conversation = AgentConversation(id: conversationId, source: .inApp)

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
