// CosmoOS/Agent/Bridges/TelegramWritingSessionManager.swift
// Manages active UnifiedWritingEngine sessions per Telegram chat
// February 2026

import Foundation

// MARK: - Telegram Writing Session

/// Per-chat session state for writing mode
struct TelegramWritingSession {
    let chatId: String
    let contentAtomUUID: String
    let engine: UnifiedWritingEngine
    var currentPhase: ContentStep = .brainstorm
    var capturedOutline: [OutlineItem] = []
    var capturedHooks: [String] = []
    var capturedDraft: String?
    var capturedDescription: String?
    var notificationTokens: [NSObjectProtocol] = []
    /// Tracks the last AI-generated draft for lesson extraction (before user edits)
    var lastAIGeneratedDraft: String?
    /// Client profile UUID resolved at session start
    var clientUUID: String?
    /// Content format/platform resolved at session start
    var contentFormat: String?
}

// MARK: - Telegram Writing Session Manager

@MainActor
class TelegramWritingSessionManager {
    static let shared = TelegramWritingSessionManager()

    private var sessions: [String: TelegramWritingSession] = [:]

    private init() {}

    // MARK: - Entry Detection

    /// Explicit mode-switch commands. These must be short, deliberate phrases —
    /// NOT casual language that appears naturally in draft feedback.
    /// "let's write" / "start writing" were removed because they trigger falsely
    /// inside longer messages like "let's write the final draft" or "start writing conversationally".
    private static let entryPatterns: [String] = [
        "opus mode", "writing mode", "draft mode", "writing session",
        "enter writing mode", "start a writing session"
    ]

    private static let commitPatterns: [String] = [
        "save", "commit", "put it in draft", "save to draft", "push to draft"
    ]

    private static let exitPatterns: [String] = [
        "done writing", "exit writing", "stop writing", "done", "back to normal"
    ]

    func isWritingTrigger(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Mode-switch commands are short and deliberate. If the message is longer
        // than ~80 chars it's clearly feedback/instructions that happen to contain
        // a trigger phrase, not an intentional mode switch.
        guard lower.count < 80 else { return false }
        return Self.entryPatterns.contains(where: { lower.hasPrefix($0) || lower.contains($0) })
    }

    func isCommitCommand(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.commitPatterns.contains(where: { lower == $0 || lower.hasPrefix($0) })
    }

    func isExitCommand(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.exitPatterns.contains(where: { lower == $0 || lower.hasPrefix($0) })
    }

    func hasActiveSession(for chatId: String) -> Bool {
        sessions[chatId] != nil
    }

    // MARK: - Start Session

    func startSession(chatId: String, text: String) async -> String {
        // Parse topic, client, platform from the trigger message
        let parsed = parseWritingIntent(text)

        // Resolve client profile if mentioned
        var clientUUID: String?
        var clientName: String?
        if let clientQuery = parsed.clientQuery {
            if let client = try? await AtomRepository.shared.fuzzyFindClient(query: clientQuery) {
                clientUUID = client.uuid
                clientName = client.title ?? clientQuery
            }
        }

        // Build content atom metadata
        var contentMeta = ContentAtomMetadata(
            phase: .ideation,
            wordCount: 0
        )
        contentMeta.platform = parsed.platform
        contentMeta.clientProfileUUID = clientUUID
        contentMeta.activatedAt = ISO8601.string(from: Date())

        let title = parsed.topic ?? "Telegram Writing Session"

        // Create content atom
        let atom: Atom
        do {
            atom = try await AtomRepository.shared.create(
                type: .content,
                title: title,
                metadata: contentMeta.toJSON()
            )
        } catch {
            return "Failed to create content atom: \(error.localizedDescription)"
        }

        // ── Pre-fetch intelligence context before engine starts ──────────────
        // Load lessons + beat patterns so the engine has full context on message 1,
        // not just after the user manually asks for it mid-session.
        var contextBrief = buildSessionContextBrief(
            topic: parsed.topic,
            clientName: clientName,
            platform: parsed.platform
        )

        // Load client-scoped lessons from AgentToolExecutor
        if let cName = clientName {
            if let lessonsResult = try? await AgentToolExecutor.shared.execute(
                toolName: "get_lessons",
                arguments: ["clientName": cName]
            ), let data = lessonsResult.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let lessons = json["results"] as? [[String: Any]], !lessons.isEmpty {
                let ruleLines = lessons.prefix(8).compactMap { $0["rule"] as? String }
                    .map { "• " + $0 }
                    .joined(separator: "\n")
                contextBrief += "\n\nLessons learnt for \(cName):\n" + ruleLines
            }
        }

        // Load top beat patterns for the platform
        let platformFormat = parsed.platform?.rawValue
        if let beatsResult = try? await AgentToolExecutor.shared.execute(
            toolName: "get_beat_patterns",
            arguments: platformFormat != nil ? ["format": platformFormat!, "limit": 3] : ["limit": 3]
        ), let data = beatsResult.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let patterns = json["patterns"] as? [[String: Any]], !patterns.isEmpty {
            let beatLines = patterns.prefix(3).compactMap { p -> String? in
                guard let fp = p["fingerprint"] as? String else { return nil }
                let freq = p["frequency"] as? Int ?? 0
                return "• \(fp) (\(freq) uses)"
            }.joined(separator: "\n")
            contextBrief += "\n\nTop beat patterns:\n" + beatLines
        }
        // ────────────────────────────────────────────────────────────────────

        // Initialize the UnifiedWritingEngine with A/B model selection
        let engine = UnifiedWritingEngine()
        engine.writerModelOverride = TelegramWriterModel.current.rawValue
        await engine.initialize(contentAtom: atom)

        // Create session and register notification observers
        var session = TelegramWritingSession(
            chatId: chatId,
            contentAtomUUID: atom.uuid,
            engine: engine
        )
        session.clientUUID = clientUUID
        session.contentFormat = parsed.platform?.rawValue ?? "unknown"
        registerNotificationObservers(for: &session)
        sessions[chatId] = session

        // Build the first engine message — include the full context brief so
        // the engine reasons from real data on turn 1, not from scratch.
        let firstMessage: String
        if let topic = parsed.topic, !contextBrief.isEmpty {
            firstMessage = "\(topic)\n\n\(contextBrief)"
        } else if let topic = parsed.topic {
            firstMessage = topic
        } else if !contextBrief.isEmpty {
            firstMessage = "I want to brainstorm and write content.\n\n\(contextBrief)"
        } else {
            firstMessage = "I want to brainstorm and write content. Help me explore ideas."
        }

        let response = await engine.sendMessage(firstMessage, phase: .brainstorm)
        let responseText = response?.content ?? "Engine initialized. What would you like to write about?"

        // Build welcome header
        var header = "Writing mode activated"
        if let clientName = clientName {
            header += " for \(clientName)"
        }
        if let platform = parsed.platform {
            header += " (\(platform.displayName))"
        }
        header += " · \(TelegramWriterModel.current.displayName)"
        var contextSummary: [String] = []
        if clientName != nil { contextSummary.append("client profile") }
        if contextBrief.contains("Lessons learnt") { contextSummary.append("lessons") }
        if contextBrief.contains("beat pattern") { contextSummary.append("beat patterns") }
        if !contextSummary.isEmpty {
            header += " — loaded: " + contextSummary.joined(separator: ", ")
        }
        header += "\n\nSay \"save\" to commit, \"done\" to exit.\n\n---\n\n"

        return header + responseText
    }

    // MARK: - Session Context Brief Builder

    /// Builds a brief context string summarizing the session goal for engine turn 1.
    /// This is separate from the full tool fetch so pure text context lands immediately.
    private func buildSessionContextBrief(
        topic: String?,
        clientName: String?,
        platform: SocialPlatform?
    ) -> String {
        var parts: [String] = []
        if let t = topic { parts.append("Topic: \(t)") }
        if let c = clientName { parts.append("Client: \(c)") }
        if let p = platform { parts.append("Platform: \(p.displayName)") }
        guard !parts.isEmpty else { return "" }
        return "[Session context]\n" + parts.joined(separator: " | ")
    }

    // MARK: - Route Message

    func routeMessage(chatId: String, text: String) async -> String {
        guard var session = sessions[chatId] else {
            return "No active writing session."
        }

        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // ── Tool-relay: high-value commands that need full tool access ───────
        // These requests are better answered by the full agent (Opus + tools)
        // than by the writing engine alone. We route them through CosmoAgentService
        // and return directly — they don't advance the engine conversation.
        let toolRelayPatterns = [
            "score", "score it", "score the draft", "score this",
            "hook variants", "generate hooks", "give me hooks",
            "show my lessons", "what lessons", "what do you know about",
            "swipes for this", "find swipes", "relevant swipes",
            "beat pattern", "what structure", "what framework"
        ]
        let isToolRelay = toolRelayPatterns.contains(where: { lower.contains($0) })
        if isToolRelay {
            // Route through full agent with draft context so it has tools + correct model tier
            let contextualQuery = "[Writing session for \(session.contentAtomUUID)] \(text)"
            let (response, _) = await CosmoAgentService.shared.processMessage(
                contextualQuery,
                conversationId: chatId,
                source: .telegram
            )
            return response
        }
        // ────────────────────────────────────────────────────────────────────

        // Check for phase transition commands
        if lower.hasPrefix("draft it") || lower.hasPrefix("write the draft") || lower == "draft" {
            session.currentPhase = .draft
            sessions[chatId] = session
        } else if lower.hasPrefix("polish") || lower.hasPrefix("score it") || lower == "score" {
            session.currentPhase = .polish
            sessions[chatId] = session
        } else if lower.hasPrefix("back to brainstorm") || lower == "brainstorm" {
            session.currentPhase = .brainstorm
            sessions[chatId] = session
        }

        let response = await session.engine.sendMessage(text, phase: session.currentPhase)
        let responseText = response?.content ?? "No response from engine."

        // Re-read session to pick up any notification-captured data
        if let updated = sessions[chatId] {
            var extras = ""
            if !updated.capturedOutline.isEmpty && updated.capturedOutline != sessions[chatId]?.capturedOutline {
                extras += formatOutline(updated.capturedOutline)
            }
            if !updated.capturedHooks.isEmpty {
                extras += formatHooks(updated.capturedHooks)
            }
            let fullResponse = extras.isEmpty ? responseText : responseText + "\n\n" + extras
            return fullResponse
        }

        return responseText
    }

    // MARK: - Commit Session

    func commitSession(chatId: String) async -> String {
        guard let session = sessions[chatId] else {
            return "No active writing session to save."
        }

        // Build ContentFocusModeState from accumulated session data
        var state = ContentFocusModeState(atomUUID: session.contentAtomUUID)
        state.currentStep = session.currentPhase
        state.outline = session.capturedOutline
        state.hooks = session.capturedHooks
        state.draftContent = session.capturedDraft ?? ""
        state.contentDescription = session.capturedDescription ?? ""
        state.conversationHistory = session.engine.messages
        state.conversationSummary = session.engine.conversationSummary

        // Get existing atom metadata
        let existingAtom = try? await AtomRepository.shared.fetch(uuid: session.contentAtomUUID)
        let existingMetadata = existingAtom?.metadata

        // Serialize to atom fields
        let fields = state.toAtomFields(existingMetadata: existingMetadata)

        // Write to atom
        do {
            _ = try await AtomRepository.shared.update(uuid: session.contentAtomUUID) { atom in
                if let body = fields.body {
                    atom.body = body
                }
                if let metadata = fields.metadata {
                    atom.metadata = metadata
                }
            }
        } catch {
            return "Failed to save: \(error.localizedDescription)"
        }

        var summary = "Saved to content pipeline."
        if !session.capturedOutline.isEmpty {
            summary += "\nOutline: \(session.capturedOutline.count) sections"
        }
        if !session.capturedHooks.isEmpty {
            summary += "\nHooks: \(session.capturedHooks.count) variants"
        }
        if session.capturedDraft != nil {
            let wordCount = (session.capturedDraft ?? "").split(separator: " ").count
            summary += "\nDraft: \(wordCount) words"
        }
        summary += "\nConversation: \(session.engine.messages.count) messages"
        summary += "\n\nOpen this content in CosmoOS desktop to continue."

        return summary
    }

    // MARK: - End Session

    func endSession(chatId: String) async -> String {
        // Auto-commit before exiting
        let commitResult = await commitSession(chatId: chatId)

        // Extract writing lessons if the user edited the AI-generated draft
        if let session = sessions[chatId] {
            await extractLessonsFromSession(session)

            // Send lesson confirmation prompts via Telegram
            await TelegramBridgeService.shared.sendPendingLessonConfirmations(chatId: chatId)

            // Clean up notification observers
            for token in session.notificationTokens {
                NotificationCenter.default.removeObserver(token)
            }
        }

        sessions.removeValue(forKey: chatId)

        return commitResult + "\n\nWriting mode ended. Back to normal."
    }

    // MARK: - Lesson Extraction

    /// Extract writing lessons from a session if the user made meaningful edits to the AI draft.
    /// Uses low initial confidence (0.3) — below the 0.5 load threshold, invisible to engine until confirmed.
    private func extractLessonsFromSession(_ session: TelegramWritingSession) async {
        guard let generatedDraft = session.lastAIGeneratedDraft,
              !generatedDraft.isEmpty,
              let finalDraft = session.capturedDraft,
              !finalDraft.isEmpty,
              generatedDraft != finalDraft else { return }

        let contentFormat = session.contentFormat ?? "unknown"

        // The taste engine learns from the edit itself — no confirmation loop.
        await TasteStore.recordDraftEdit(
            generated: generatedDraft,
            edited: finalDraft,
            clientUuid: session.clientUUID,
            format: contentFormat
        )
    }

    // MARK: - Notification Observers

    private func registerNotificationObservers(for session: inout TelegramWritingSession) {
        let chatId = session.chatId

        let outlineToken = NotificationCenter.default.addObserver(
            forName: .unifiedEngineOutlineUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let items = notification.userInfo?["items"] as? [OutlineItem] else { return }
            Task { @MainActor in
                self?.sessions[chatId]?.capturedOutline = items
            }
        }

        let hooksToken = NotificationCenter.default.addObserver(
            forName: .unifiedEngineHooksUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let hooks = notification.userInfo?["hooks"] as? [String] else { return }
            Task { @MainActor in
                self?.sessions[chatId]?.capturedHooks = hooks
            }
        }

        let draftToken = NotificationCenter.default.addObserver(
            forName: .unifiedEngineDraftUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let content = notification.userInfo?["content"] as? String else { return }
            Task { @MainActor in
                // Track the AI-generated draft as the baseline before user edits
                if self?.sessions[chatId]?.lastAIGeneratedDraft == nil {
                    self?.sessions[chatId]?.lastAIGeneratedDraft = content
                }
                self?.sessions[chatId]?.capturedDraft = content
            }
        }

        let descriptionToken = NotificationCenter.default.addObserver(
            forName: .unifiedEngineDescriptionUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let description = notification.userInfo?["description"] as? String else { return }
            Task { @MainActor in
                self?.sessions[chatId]?.capturedDescription = description
            }
        }

        session.notificationTokens = [outlineToken, hooksToken, draftToken, descriptionToken]
    }

    // MARK: - Intent Parsing

    private struct WritingIntent {
        var topic: String?
        var clientQuery: String?
        var platform: SocialPlatform?
    }

    private func parseWritingIntent(_ text: String) -> WritingIntent {
        let lower = text.lowercased()
        var intent = WritingIntent()

        // Strip trigger phrases to get the topic
        var cleaned = lower
        for pattern in Self.entryPatterns {
            if let range = cleaned.range(of: pattern) {
                cleaned.removeSubrange(range)
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse platform from keywords
        // "thread" = Instagram carousel (slides with text), not Twitter
        if cleaned.contains("carousel") || cleaned.contains("thread") {
            intent.platform = .instagram
        } else if cleaned.contains("reel") {
            intent.platform = .instagram
        } else if cleaned.contains("linkedin") {
            intent.platform = .linkedin
        } else if cleaned.contains("tiktok") || cleaned.contains("tik tok") {
            intent.platform = .tiktok
        } else if cleaned.contains("youtube") || cleaned.contains("yt") {
            intent.platform = .youtube
        } else if cleaned.contains("newsletter") {
            intent.platform = .substack
        }

        // Parse client name from "for <name>" pattern
        if let forRange = cleaned.range(of: " for ") {
            let afterFor = String(cleaned[forRange.upperBound...])
            // Take up to the next preposition or end
            let clientName = afterFor
                .components(separatedBy: CharacterSet(charactersIn: " ,.!?"))
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = clientName, !name.isEmpty, name.count > 1 {
                intent.clientQuery = name
                // Remove "for <name>" from cleaned text to get pure topic
                if let fullRange = cleaned.range(of: " for \(name)") {
                    cleaned.removeSubrange(fullRange)
                }
            }
        }

        // Remove platform keywords from topic
        let platformKeywords = ["carousel", "reel", "thread", "linkedin", "tiktok", "tik tok", "youtube", "yt", "newsletter", "a ", "about "]
        var topic = cleaned
        for keyword in platformKeywords {
            topic = topic.replacingOccurrences(of: keyword, with: "")
        }
        topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)

        if !topic.isEmpty {
            intent.topic = topic.prefix(1).uppercased() + topic.dropFirst()
        }

        return intent
    }

    // MARK: - Telegram Formatting

    private func formatOutline(_ items: [OutlineItem]) -> String {
        var lines: [String] = ["Outline:"]
        for (i, item) in items.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            lines.append("\(i + 1). \(item.title)")
        }
        return lines.joined(separator: "\n")
    }

    private func formatHooks(_ hooks: [String]) -> String {
        var lines: [String] = ["Hook variants:"]
        for (i, hook) in hooks.enumerated() {
            let truncated = hook.count > 100 ? String(hook.prefix(100)) + "..." : hook
            lines.append("\(i + 1). \(truncated)")
        }
        return lines.joined(separator: "\n")
    }

}
