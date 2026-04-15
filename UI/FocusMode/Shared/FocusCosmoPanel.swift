// CosmoOS/UI/FocusMode/Shared/FocusCosmoPanel.swift
// The inline Cosmo chat panel shown in the right marginalia of both Idea Focus
// Mode (The Atelier) and Content Focus Mode (The Scriptorium).
//
// Key constraint: every model-facing call this panel makes — initial message
// routing, tool-use function calling, tool-result reasoning, the web_search
// tool itself — runs on google/gemini-3-flash and NOTHING else. No Claude, no
// Sonnet, no Opus, no Haiku, no Perplexity. This is enforced by constructing a
// dedicated OpenRouter provider at init and intercepting the `web_search` tool
// inside the panel's own tool loop so it routes through `GeminiGroundedSearch`
// instead of `AgentToolExecutor.webSearch`.
//
// The global ⌘J window is untouched — it still calls `CosmoAgentService.shared`
// with whatever model the user selected in settings.

import SwiftUI

// MARK: - Config

enum FocusCosmoConfig {
    /// The ONLY model the margin Cosmo panel is allowed to call. If the OpenRouter
    /// slug evolves, change it here and rebuild. FlashLiteRouter.swift has a
    /// precedent of reaching Gemini 3.x models via OpenRouter's Google passthrough.
    static let model = "google/gemini-3-flash"

    /// Max iterations for the tool loop. Matches the global window's query intent.
    static let maxToolIterations: Int = 12

    /// Cap on persisted messages — mirrors ContentFocusModeState.conversationHistory.
    static let maxPersistedMessages: Int = 30
}

// MARK: - Message

struct FocusCosmoMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable, Sendable { case user, assistant, toolTrace }

    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    let toolName: String?

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date(), toolName: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolName = toolName
    }

    var authorLabel: String {
        switch role {
        case .user: return "EUAN"
        case .assistant: return "COSMO"
        case .toolTrace: return ""
        }
    }
}

// MARK: - Context kind

enum FocusCosmoContextKind: String {
    case idea
    case content

    var label: String {
        switch self {
        case .idea: return "idea"
        case .content: return "content"
        }
    }
}

// MARK: - Session

@MainActor
final class FocusCosmoSession: ObservableObject {
    // Published UI state
    @Published var messages: [FocusCosmoMessage] = []
    @Published var isStreaming: Bool = false
    @Published var activeToolTrace: String?
    @Published var errorMessage: String?

    // Identity
    private let atomUUID: String
    private let atomTitle: String?
    private let contextKind: FocusCosmoContextKind

    // Persistence key — unique per atom
    private var conversationId: String {
        "focusCosmo-\(atomUUID)"
    }

    // Gemini-only LLM provider — constructed lazily
    private lazy var provider: LLMProvider = {
        LLMProviderFactory.create(
            provider: .openRouter,
            apiKey: APIKeys.openRouter,
            baseURL: nil
        )
    }()

    // Tool registry — reuse the global one, .query intent gives us `allTools`
    private let toolRegistry = AgentToolRegistry.shared
    private let toolExecutor = AgentToolExecutor.shared

    // Humanized tool → breadcrumb labels
    private let toolLabels: [String: String] = [
        "search_ideas": "searching ideas…",
        "get_idea": "reading idea…",
        "search_swipes": "searching swipes…",
        "find_similar_swipes": "finding similar swipes…",
        "filter_swipes_by_taxonomy": "filtering swipes…",
        "list_all_swipes": "listing swipes…",
        "get_swipe_analysis": "analyzing swipe…",
        "list_client_profiles": "listing client profiles…",
        "get_client_profile": "reading client profile…",
        "search_by_client": "searching by client…",
        "get_content": "reading content…",
        "get_content_pipeline": "reading pipeline…",
        "web_search": "asking the web…",
        "get_lessons": "reading lessons…",
        "get_saved_analyses": "reading past analyses…",
        "get_beat_patterns": "reading beat patterns…"
    ]

    init(atomUUID: String, atomTitle: String?, contextKind: FocusCosmoContextKind) {
        self.atomUUID = atomUUID
        self.atomTitle = atomTitle
        self.contextKind = contextKind
    }

    /// Load the persisted conversation for this atom (if any). Called on the
    /// view's `.task` so it doesn't block appearance.
    func load() async {
        guard messages.isEmpty else { return } // already loaded
        if let conv = await ConversationMemoryService.shared.loadConversation(id: conversationId) {
            let loaded = conv.messages.compactMap { msg -> FocusCosmoMessage? in
                switch msg.role {
                case .user:
                    return FocusCosmoMessage(role: .user, content: msg.content, timestamp: msg.timestamp)
                case .assistant:
                    let content = msg.content
                    guard !content.isEmpty else { return nil }
                    return FocusCosmoMessage(role: .assistant, content: content, timestamp: msg.timestamp)
                default:
                    return nil
                }
            }
            self.messages = loaded
        }
    }

    /// Send a user message through the Gemini-only tool loop.
    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        errorMessage = nil
        isStreaming = true
        defer {
            isStreaming = false
            activeToolTrace = nil
        }

        // Append the user message to the UI immediately
        let userMsg = FocusCosmoMessage(role: .user, content: trimmed)
        messages.append(userMsg)

        // Build the LLM messages from scratch — system prompt + all prior UI
        // messages that weren't tool traces + the new user message
        var llmMessages: [AgentMessage] = []
        for m in messages.dropLast() {
            switch m.role {
            case .user: llmMessages.append(.user(m.content))
            case .assistant: llmMessages.append(.assistant(m.content))
            case .toolTrace: break
            }
        }
        llmMessages.append(.user(trimmed))

        let systemPromptText = await buildSystemPrompt()
        let tools = toolRegistry.toolsForIntent(.query, source: .inApp)

        print("[FOCUS-COSMO] routing via \(FocusCosmoConfig.model) (contextKind=\(contextKind.rawValue) atom=\(atomUUID.prefix(8)) tools=\(tools.count))")

        // Tool loop
        var iterations = 0
        var finalResponse: String = ""

        while iterations < FocusCosmoConfig.maxToolIterations {
            iterations += 1
            do {
                let response = try await provider.complete(
                    messages: [AgentMessage.system(systemPromptText)] + llmMessages,
                    tools: tools.isEmpty ? nil : tools,
                    model: FocusCosmoConfig.model
                )

                if response.toolCalls.isEmpty {
                    finalResponse = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    break
                }

                // Record the assistant's tool-call turn
                let assistantMsg = AgentMessage.assistant(
                    response.content ?? "",
                    toolCalls: response.toolCalls
                )
                llmMessages.append(assistantMsg)

                // Execute each tool call
                for toolCall in response.toolCalls {
                    let label = toolLabels[toolCall.name] ?? "working…"
                    activeToolTrace = label

                    let result: String
                    if toolCall.name == "web_search" {
                        // GEMINI-ONLY INTERCEPT — never touch Perplexity from this panel
                        let query = (toolCall.arguments["query"] as? String) ?? ""
                        result = await GeminiGroundedSearch.shared.search(
                            query: query,
                            model: FocusCosmoConfig.model
                        )
                    } else {
                        do {
                            result = try await toolExecutor.execute(
                                toolName: toolCall.name,
                                arguments: toolCall.arguments
                            )
                        } catch {
                            result = "{\"error\": \"\(error.localizedDescription)\"}"
                        }
                    }

                    llmMessages.append(.tool(callId: toolCall.id, content: result))
                }

                activeToolTrace = nil
            } catch {
                errorMessage = "cosmo is unreachable — \(error.localizedDescription)"
                print("[FOCUS-COSMO] error: \(error)")
                return
            }
        }

        if finalResponse.isEmpty {
            finalResponse = "I ran out of steps. Try a more specific question?"
        }

        // Append the final assistant message to the UI
        let assistantUI = FocusCosmoMessage(role: .assistant, content: finalResponse)
        messages.append(assistantUI)

        // Persist: rebuild an AgentConversation and save via ConversationMemoryService
        await persist()
    }

    func reset() async {
        messages = []
        // Wipe the conversation atom
        if let conv = await ConversationMemoryService.shared.loadConversation(id: conversationId) {
            var cleared = conv
            cleared.messages = []
            await ConversationMemoryService.shared.saveConversation(cleared)
        }
    }

    // MARK: - System prompt

    private func buildSystemPrompt() async -> String {
        let identity = "You are Cosmo, a warm and direct creative partner embedded in the user's writing sanctuary. Be concise (2–6 sentences) unless the user asks for more detail. Never invent atom titles — use tools to look them up."

        let locus: String
        switch contextKind {
        case .idea:
            locus = "The user is currently focused on an IDEA atom titled \"\(atomTitle ?? "Untitled")\" (uuid: \(atomUUID)). Idea atoms are sketches — the user is thinking, not yet writing."
        case .content:
            locus = "The user is currently focused on a CONTENT atom titled \"\(atomTitle ?? "Untitled")\" (uuid: \(atomUUID)). Content atoms are manuscripts being drafted from ideas."
        }

        let toolhint = """
        You have full access to the user's knowledge graph via tools:
        - `search_ideas` — semantic search across their idea atoms (for "what's that idea about X")
        - `list_client_profiles` + `get_client_profile` — to find a client like "Ben" and read their brand voice, top-performing posts, voice notes, brand story
        - `search_swipes`, `find_similar_swipes`, `filter_swipes_by_taxonomy` — swipe library retrieval
        - `search_by_client` — everything linked to one client
        - `web_search` — grounded web research (routed through Gemini)
        - `get_content` / `get_content_pipeline` — read content atoms and pipeline status
        Use tools aggressively when the answer depends on real data in the user's system. Never guess.
        """

        return [identity, locus, toolhint].joined(separator: "\n\n")
    }

    // MARK: - Persistence

    private func persist() async {
        var conv = AgentConversation(id: conversationId, source: .inApp)
        // Cap to the last N messages
        let recent = messages.suffix(FocusCosmoConfig.maxPersistedMessages)
        for m in recent {
            switch m.role {
            case .user: conv.append(.user(m.content))
            case .assistant: conv.append(.assistant(m.content))
            case .toolTrace: break
            }
        }
        conv.linkedAtomUUIDs = [atomUUID]
        conv.topics = [contextKind.rawValue]
        await ConversationMemoryService.shared.saveConversation(conv)
    }
}

// MARK: - Panel View

struct FocusCosmoPanel: View {
    @ObservedObject var session: FocusCosmoSession
    @Binding var isExpanded: Bool

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            header
            if isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Header row

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            MarginaliaLabel(
                "COSMO",
                countText: session.messages.isEmpty ? nil : "\(session.messages.count) msgs"
            )
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isExpanded.toggle()
                    if isExpanded { inputFocused = true }
                }
            } label: {
                HStack(spacing: DS.space6) {
                    Text(isExpanded ? "close" : "ask cosmo anything")
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(DS.text)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(DS.gilt.opacity(0.7))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Expanded body

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            messageList
            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(height: 0.5)
            inputRow
            if let err = session.errorMessage {
                Text(err)
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(DS.red.opacity(0.7))
                    .lineLimit(3)
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space12) {
                    if session.messages.isEmpty && !session.isStreaming {
                        Text("what's on your mind?")
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.inkFaded.opacity(0.6))
                    }
                    ForEach(Array(session.messages.enumerated()), id: \.element.id) { idx, message in
                        messageRow(message)
                        if idx < session.messages.count - 1 {
                            Rectangle()
                                .fill(DS.sepiaSubtle.opacity(0.6))
                                .frame(height: 0.5)
                                .frame(maxWidth: 120)
                        }
                    }
                    if let trace = session.activeToolTrace {
                        Text("· \(trace)")
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.inkFaded)
                            .id("trace")
                    } else if session.isStreaming {
                        Text("· thinking…")
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.inkFaded)
                            .id("trace")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(minHeight: 160, maxHeight: 320)
            .onChange(of: session.messages.count) { _, _ in
                if let last = session.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: session.activeToolTrace) { _, _ in
                if session.activeToolTrace != nil {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("trace", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageRow(_ message: FocusCosmoMessage) -> some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            if !message.authorLabel.isEmpty {
                Text(message.authorLabel)
                    .font(DS.smallCaps)
                    .tracking(1.4)
                    .foregroundStyle(DS.giltMuted)
            }
            Text(message.content)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic(message.role == .user)
                .foregroundStyle(DS.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputRow: some View {
        HStack(alignment: .center, spacing: DS.space8) {
            TextField("ask cosmo anything…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.text)
                .focused($inputFocused)
                .lineLimit(1...4)
                .onSubmit { submit() }
                .disabled(session.isStreaming)
            Button(action: submit) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(canSubmit ? DS.gilt : DS.gilt.opacity(0.3))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityLabel("Send to Cosmo")
        }
    }

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isStreaming
    }

    private func submit() {
        guard canSubmit else { return }
        let text = draft
        draft = ""
        Task { await session.send(text) }
    }
}
