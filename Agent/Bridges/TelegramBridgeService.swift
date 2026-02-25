// CosmoOS/Agent/Bridges/TelegramBridgeService.swift
// Telegram Bot API bridge using long polling

import Foundation
import Combine
import UserNotifications

// MARK: - Telegram Errors

enum TelegramError: Error, LocalizedError {
    case noBotToken
    case invalidResponse
    case fileNotFound
    case sendFailed(String)
    case rateLimited(retryAfter: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .noBotToken: return "No Telegram bot token configured"
        case .invalidResponse: return "Invalid response from Telegram API"
        case .fileNotFound: return "Telegram file not found"
        case .sendFailed(let msg): return "Failed to send message: \(msg)"
        case .rateLimited(let seconds): return "Rate limited. Retry after \(Int(seconds))s"
        }
    }
}

@MainActor
class TelegramBridgeService: ObservableObject {
    static let shared = TelegramBridgeService()

    @Published var isConnected = false
    @Published var lastError: String?
    @Published var messageCount = 0

    private var pollingTask: Task<Void, Never>?
    private var updateOffset: Int = 0
    private var backoffInterval: TimeInterval = 1.0
    private let maxBackoff: TimeInterval = 30.0

    /// Cached token — read from Keychain once on start(), not on every poll
    private var cachedToken: String?

    /// Concurrency guard — prevents overlapping message processing per chat
    private var processingChatIds: Set<String> = []

    /// Debounce buffers — accumulate rapid-fire messages per chat instead of rejecting
    private var debounceBuffers: [String: [String]] = [:]
    private var debounceTimers: [String: Task<Void, Never>] = [:]
    private let debounceWindow: TimeInterval = 2.5

    /// Pending lesson corrections: chatId → lessonID (UUID string)
    private var pendingLessonCorrections: [String: String] = [:]

    /// Pending module suggestions: suggestionId → PendingModuleSuggestion
    private var pendingModuleSuggestions: [String: AgentToolExecutor.PendingModuleSuggestion] = [:]

    /// Pending module edit corrections: chatId → suggestionId (awaiting user's corrected text)
    private var pendingModuleEdits: [String: String] = [:]

    /// Maximum retries for rate-limited (429) Telegram API calls
    private let maxSendRetries = 3

    /// Sanitize and extract a Telegram bot token from pasted text/URLs.
    /// Accepts inputs like:
    /// - `123456:ABCDEF...`
    /// - `bot123456:ABCDEF...`
    /// - `https://api.telegram.org/bot123456:ABCDEF.../getMe`
    static func sanitizeToken(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let stripped = stripBotPrefix(from: trimmed)

        if let token = firstTokenMatch(in: stripped) {
            return token
        }
        if let token = firstTokenMatch(in: trimmed) {
            return token
        }

        if looksLikeToken(stripped) {
            return stripped
        }

        return nil
    }

    private static func stripBotPrefix(from input: String) -> String {
        guard input.lowercased().hasPrefix("bot"), input.count > 3 else { return input }
        let candidate = String(input.dropFirst(3))
        if let first = candidate.first, first.isNumber {
            return candidate
        }
        return input
    }

    private static func firstTokenMatch(in input: String) -> String? {
        let pattern = #"\d{5,}:[A-Za-z0-9_-]{20,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, options: [], range: range),
              let tokenRange = Range(match.range, in: input) else {
            return nil
        }
        return String(input[tokenRange])
    }

    private static func looksLikeToken(_ value: String) -> Bool {
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let idPart = String(parts[0])
        let secretPart = String(parts[1])
        guard idPart.count >= 5, secretPart.count >= 20 else { return false }
        guard idPart.allSatisfy(\.isNumber) else { return false }
        return secretPart.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    /// Read token from Keychain (one-time read, result gets cached)
    private func loadTokenFromKeychain() -> String? {
        guard let raw = APIKeys.telegramBotToken else { return nil }
        return Self.sanitizeToken(raw)
    }

    private var botToken: String? { cachedToken }

    private var baseURL: String {
        guard let token = cachedToken else { return "" }
        return "https://api.telegram.org/bot\(token)"
    }

    // Store the chat ID of the most recent conversation for proactive messages
    @Published var activeChatId: String? {
        didSet {
            if let id = activeChatId {
                UserDefaults.standard.set(id, forKey: "agent_telegram_chat_id")
            }
        }
    }

    private init() {
        activeChatId = UserDefaults.standard.string(forKey: "agent_telegram_chat_id")
    }

    // MARK: - Start/Stop Polling

    func start() async {
        guard let token = loadTokenFromKeychain() else {
            if let raw = APIKeys.telegramBotToken,
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastError = "Invalid token format. Re-save your BotFather token."
            } else {
                lastError = "No bot token configured"
            }
            return
        }

        // Cancel existing polling without clearing the newly loaded token.
        pollingTask?.cancel()
        pollingTask = nil
        cachedToken = token

        isConnected = true
        lastError = nil
        backoffInterval = 1.0

        // Debug: log masked token for troubleshooting
        let masked = token.count > 10
            ? String(token.prefix(4)) + "..." + String(token.suffix(4))
            : "***"
        print("[Telegram] Using token: \(masked) (length: \(token.count))")

        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }

        print("[Telegram] Bridge started")
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        cachedToken = nil
        isConnected = false
        print("[Telegram] Bridge stopped")
    }

    // MARK: - Test Bot Token

    /// Validate the bot token by calling getMe (reads fresh from Keychain)
    func testBot() async -> (success: Bool, message: String) {
        guard let raw = APIKeys.telegramBotToken,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (false, "No bot token configured")
        }
        guard let token = Self.sanitizeToken(raw) else {
            return (false, "Invalid token format. Paste only the BotFather token (123456:ABC...)")
        }

        let masked = token.count > 10
            ? String(token.prefix(4)) + "..." + String(token.suffix(4))
            : "***"

        do {
            let url = URL(string: "https://api.telegram.org/bot\(token)/getMe")!
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "unknown"
                return (false, "HTTP \(httpResponse.statusCode) (token: \(masked)). Response: \(body)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = json["ok"] as? Bool, ok,
                  let result = json["result"] as? [String: Any] else {
                return (false, "Invalid response from Telegram (token: \(masked))")
            }

            let botName = result["first_name"] as? String ?? "Unknown"
            let botUsername = result["username"] as? String ?? ""
            return (true, "Connected to @\(botUsername) (\(botName))")

        } catch {
            return (false, "Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Polling Loop

    private func pollLoop() async {
        while !Task.isCancelled {
            do {
                let updates = try await getUpdates(offset: updateOffset, timeout: 30)

                backoffInterval = 1.0 // Reset backoff on success

                for update in updates {
                    await handleUpdate(update)
                    if let updateId = update["update_id"] as? Int {
                        updateOffset = updateId + 1
                    }
                }
            } catch {
                if Task.isCancelled { break }

                lastError = error.localizedDescription
                print("[Telegram] Polling error: \(error). Retrying in \(backoffInterval)s")

                try? await Task.sleep(nanoseconds: UInt64(backoffInterval * 1_000_000_000))
                backoffInterval = min(backoffInterval * 2, maxBackoff)
            }
        }
    }

    // MARK: - Telegram Bot API Methods

    private func getUpdates(offset: Int, timeout: Int) async throws -> [[String: Any]] {
        guard !baseURL.isEmpty else {
            throw TelegramError.noBotToken
        }

        var components = URLComponents(string: "\(baseURL)/getUpdates")!
        components.queryItems = [
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "timeout", value: "\(timeout)"),
            URLQueryItem(name: "allowed_updates", value: "[\"message\",\"callback_query\"]")
        ]

        guard let url = components.url else {
            throw TelegramError.sendFailed("Invalid Telegram URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(timeout + 10) // Buffer beyond long-poll timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        // Check HTTP status first
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            print("[Telegram] HTTP \(httpResponse.statusCode): \(body)")
            throw TelegramError.sendFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let body = String(data: data, encoding: .utf8) ?? "not UTF-8"
            print("[Telegram] Invalid JSON response: \(body)")
            throw TelegramError.invalidResponse
        }

        guard let ok = json["ok"] as? Bool, ok else {
            let desc = json["description"] as? String ?? "unknown error"
            let code = json["error_code"] as? Int ?? 0
            print("[Telegram] API error \(code): \(desc)")
            throw TelegramError.sendFailed("Telegram \(code): \(desc)")
        }

        guard let result = json["result"] as? [[String: Any]] else {
            throw TelegramError.invalidResponse
        }

        return result
    }

    private func handleUpdate(_ update: [String: Any]) async {
        // Handle regular messages
        if let message = update["message"] as? [String: Any] {
            await handleMessage(message)
        }

        // Handle callback queries (inline button presses)
        if let callback = update["callback_query"] as? [String: Any] {
            await handleCallbackQuery(callback)
        }
    }

    private func handleMessage(_ message: [String: Any]) async {
        guard let chat = message["chat"] as? [String: Any],
              let chatId = chat["id"] as? Int else { return }

        let chatIdStr = "\(chatId)"
        activeChatId = chatIdStr
        messageCount += 1

        // Voice messages bypass debounce entirely
        if let voice = message["voice"] as? [String: Any],
           let fileId = voice["file_id"] as? String {
            await handleVoiceMessage(fileId: fileId, chatId: chatIdStr)
            return
        }
        if let audio = message["audio"] as? [String: Any],
           let fileId = audio["file_id"] as? String {
            await handleVoiceMessage(fileId: fileId, chatId: chatIdStr)
            return
        }

        guard let text = message["text"] as? String else { return }

        // /start command bypasses debounce
        if text == "/start" {
            let welcome = """
            Hey! I'm Cosmo, your AI creative partner.

            I have full access to your CosmoOS knowledge graph. Ask me about your ideas, swipes, content pipeline, schedule, or just brainstorm.

            Say "opus mode" to enter writing mode with the full writing engine.

            Try: "What ideas do I have?" or "Schedule a writing block for tomorrow at 10am"
            """
            await sendMessage(chatId: chatIdStr, text: welcome)
            return
        }

        // /clear command bypasses debounce — resets conversation context
        if text == "/clear" {
            await CosmoAgentService.shared.clearConversation(chatId: chatIdStr, source: .telegram)
            await sendMessage(chatId: chatIdStr, text: "Context cleared ✓\nStarting fresh — previous messages won't be used as context.")
            return
        }

        // Fast-path URL capture bypasses debounce for instant swipe saves
        if text.range(of: "https?://[^\\s]+", options: .regularExpression) != nil {
            if let fastCaptureResult = await tryFastCapture(text: text, chatId: chatIdStr) {
                await sendLongMessage(chatId: chatIdStr, text: fastCaptureResult)
                return
            }
        }

        // MARK: Debounce Logic
        // If already processing a message for this chat, buffer instead of rejecting
        if processingChatIds.contains(chatIdStr) {
            if debounceBuffers[chatIdStr] != nil {
                debounceBuffers[chatIdStr]?.append(text)
            } else {
                debounceBuffers[chatIdStr] = [text]
            }
            print("[Telegram] Buffered message for \(chatIdStr) (buffer size: \(debounceBuffers[chatIdStr]?.count ?? 0))")
            return
        }

        // Not currently processing — start debounce timer to accumulate rapid messages
        if debounceBuffers[chatIdStr] != nil {
            debounceBuffers[chatIdStr]?.append(text)
        } else {
            debounceBuffers[chatIdStr] = [text]
        }

        // Cancel any existing timer for this chat
        debounceTimers[chatIdStr]?.cancel()

        // Start debounce timer — waits for debounceWindow, then flushes buffer
        debounceTimers[chatIdStr] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.debounceWindow ?? 2.5) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flushDebounceBuffer(chatId: chatIdStr)
        }
    }

    /// Flush buffered messages for a chat, joining them into a single input
    private func flushDebounceBuffer(chatId: String) async {
        guard let buffered = debounceBuffers[chatId], !buffered.isEmpty else { return }

        // Take all buffered messages and clear the buffer
        let joinedText = buffered.joined(separator: "\n\n")
        debounceBuffers.removeValue(forKey: chatId)
        debounceTimers.removeValue(forKey: chatId)

        // Process the combined message
        await processBufferedMessage(text: joinedText, chatId: chatId)

        // After processing, check if more messages arrived during processing
        if let deferred = debounceBuffers[chatId], !deferred.isEmpty {
            let deferredText = deferred.joined(separator: "\n\n")
            debounceBuffers.removeValue(forKey: chatId)
            await processBufferedMessage(text: deferredText, chatId: chatId)
        }
    }

    /// Process a single (possibly joined) message through the full pipeline
    private func processBufferedMessage(text: String, chatId: String) async {
        // Guard against concurrent processing for the same chat
        guard !processingChatIds.contains(chatId) else {
            // Shouldn't happen, but buffer if it does
            if debounceBuffers[chatId] != nil {
                debounceBuffers[chatId]?.append(text)
            } else {
                debounceBuffers[chatId] = [text]
            }
            return
        }
        processingChatIds.insert(chatId)
        defer { processingChatIds.remove(chatId) }

        // MARK: Lesson Correction Intercept
        // If user is replying with a corrected rule, handle it before anything else
        if let lessonIDStr = pendingLessonCorrections[chatId] {
            pendingLessonCorrections.removeValue(forKey: chatId)
            if let lessonID = UUID(uuidString: lessonIDStr) {
                await LessonExtractor.shared.correctLesson(lessonID: lessonID, correctedRule: text)
                await sendMessage(chatId: chatId, text: "Got it — rule updated and saved.")
            }
            return
        }

        // MARK: Module Edit Correction Intercept
        // If user is replying with corrected text for a module suggestion
        if let suggestionId = pendingModuleEdits[chatId] {
            pendingModuleEdits.removeValue(forKey: chatId)
            if let suggestion = pendingModuleSuggestions.removeValue(forKey: suggestionId) {
                // Apply with user's corrected text
                let corrected = AgentToolExecutor.PendingModuleSuggestion(
                    id: suggestion.id,
                    action: suggestion.action,
                    moduleId: suggestion.moduleId,
                    content: text,
                    reason: suggestion.reason,
                    newModuleTitle: suggestion.newModuleTitle,
                    newModuleId: suggestion.newModuleId
                )
                if corrected.action == "add_to_module", let moduleId = corrected.moduleId {
                    PromptTemplateStore.shared.appendLessonToModule(moduleId: moduleId, formattedRule: text)
                    let moduleName = PromptTemplateStore.shared.modules.first(where: { $0.id == moduleId })?.title ?? moduleId
                    await sendMessage(chatId: chatId, text: "Added (edited) to \(moduleName).")
                } else if corrected.action == "create_module",
                          let newId = corrected.newModuleId,
                          let newTitle = corrected.newModuleTitle {
                    PromptTemplateStore.shared.addCustomModule(id: newId, title: newTitle, content: text)
                    await sendMessage(chatId: chatId, text: "Created new module: \(newTitle) (with your edit).")
                }
            } else {
                await sendMessage(chatId: chatId, text: "Suggestion expired.")
            }
            return
        }

        // MARK: Writing Mode Intercept

        // 1. Check for writing mode entry
        if TelegramWritingSessionManager.shared.isWritingTrigger(text) {
            await sendChatAction(chatId: chatId, action: "typing")
            let response = await TelegramWritingSessionManager.shared.startSession(chatId: chatId, text: text)
            await sendLongMessage(chatId: chatId, text: response)
            return
        }

        // 2. Route to active writing session
        if TelegramWritingSessionManager.shared.hasActiveSession(for: chatId) {
            if TelegramWritingSessionManager.shared.isExitCommand(text) {
                let response = await TelegramWritingSessionManager.shared.endSession(chatId: chatId)
                await sendLongMessage(chatId: chatId, text: response)
                return
            }
            if TelegramWritingSessionManager.shared.isCommitCommand(text) {
                let response = await TelegramWritingSessionManager.shared.commitSession(chatId: chatId)
                await sendLongMessage(chatId: chatId, text: response)
                notifyDesktopContentCreated(title: "Writing session committed via Telegram")
                return
            }
            await sendChatAction(chatId: chatId, action: "typing")
            let response = await TelegramWritingSessionManager.shared.routeMessage(chatId: chatId, text: text)
            await sendLongMessage(chatId: chatId, text: response)
            return
        }

        // Fast-path URL capture (re-check for joined messages that contain URLs)
        if let fastCaptureResult = await tryFastCapture(text: text, chatId: chatId) {
            await sendLongMessage(chatId: chatId, text: fastCaptureResult)
            return
        }

        // Show typing indicator (refreshed every 4s while processing)
        let typingTask = Task { await self.keepTyping(chatId: chatId) }

        // Process through agent
        let (response, trace) = await CosmoAgentService.shared.processMessage(
            text,
            conversationId: chatId,
            source: .telegram
        )
        typingTask.cancel()

        // Send the response
        await sendLongMessage(chatId: chatId, text: response)

        // Send context transparency card if tools were used
        if let contextSummary = TelegramRichMessages.shared.formatContextTrace(trace) {
            await sendMessage(chatId: chatId, text: contextSummary)
        }

        // Send any pending lesson confirmations
        await sendPendingLessonConfirmations(chatId: chatId)

        // Send any pending module suggestions
        await sendPendingModuleSuggestions(chatId: chatId)
    }

    // MARK: - Lesson Confirmation Flow

    /// Send pending lesson confirmations to the user via Telegram inline buttons.
    /// Shows the target skill module so the user knows where the rule will be added.
    func sendPendingLessonConfirmations(chatId: String) async {
        let lessons = await LessonExtractor.shared.drainPendingConfirmations()
        guard !lessons.isEmpty else { return }

        for lesson in lessons.prefix(2) {
            let targetModule = PromptTemplateStore.shared.moduleForCategory(lesson.category)
            let moduleName = targetModule?.title ?? "Learned Skills"

            let text = "I noticed a pattern from your edits.\n\n_\(lesson.rule)_\n\nI'd add this to *\(moduleName)*."

            let buttons: [[Any]] = [[
                ["text": "Yes, add it", "callback_data": "lesson_yes:\(lesson.id.uuidString)"],
                ["text": "Different module", "callback_data": "lesson_reroute:\(lesson.id.uuidString)"],
            ], [
                ["text": "Edit rule", "callback_data": "lesson_correct:\(lesson.id.uuidString)"],
                ["text": "Discard", "callback_data": "lesson_no:\(lesson.id.uuidString)"]
            ]]
            await sendMessage(chatId: chatId, text: text, parseMode: "Markdown", replyMarkup: buttons)
        }
    }

    // MARK: - Module Suggestion Confirmation Flow

    /// Send pending module suggestions to the user via Telegram inline buttons.
    func sendPendingModuleSuggestions(chatId: String) async {
        let suggestions = AgentToolExecutor.shared.drainPendingModuleSuggestions()
        guard !suggestions.isEmpty else { return }

        for suggestion in suggestions.prefix(3) {
            // Store for callback resolution
            pendingModuleSuggestions[suggestion.id.uuidString] = suggestion

            let text: String
            if suggestion.action == "add_to_module", let moduleId = suggestion.moduleId {
                let moduleName = PromptTemplateStore.shared.modules.first(where: { $0.id == moduleId })?.title ?? moduleId
                text = "I'd like to add this to *\(moduleName)*:\n\n_\(suggestion.content)_\n\nReason: \(suggestion.reason)"
            } else {
                let title = suggestion.newModuleTitle ?? "Untitled"
                text = "I'd like to create a new skill module:\n\n*\(title)*\n_\(suggestion.content)_\n\nReason: \(suggestion.reason)"
            }

            let buttons: [[Any]] = [[
                ["text": "Approve", "callback_data": "module_approve:\(suggestion.id.uuidString)"] as [String: Any],
                ["text": "Edit", "callback_data": "module_edit:\(suggestion.id.uuidString)"] as [String: Any],
                ["text": "Reject", "callback_data": "module_reject:\(suggestion.id.uuidString)"] as [String: Any]
            ]]
            await sendMessage(chatId: chatId, text: text, parseMode: "Markdown", replyMarkup: buttons)
        }
    }

    // MARK: - Fast-Path URL Capture

    /// Detects simple URL capture messages ("swipe this [URL]", "capture [URL]", bare URL)
    /// and executes captureSwipe directly, bypassing the LLM entirely.
    /// Returns nil if the message doesn't match the fast-path pattern — falls through to LLM.
    private func tryFastCapture(text: String, chatId: String) async -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract URL from the message
        guard let urlRange = text.range(of: "https?://[^\\s]+", options: .regularExpression),
              let url = URL(string: String(text[urlRange])) else {
            return nil
        }

        let urlString = String(text[urlRange])

        // Check if this is a supported swipe platform
        let swipeDomains = ["instagram.com", "youtube.com", "youtu.be", "x.com",
                            "twitter.com", "threads.net", "tiktok.com"]
        guard let host = url.host?.lowercased(),
              swipeDomains.contains(where: { host.contains($0) }) else {
            return nil
        }

        // Check for simple capture keywords — if there's idea-related language,
        // let the LLM handle it so it can use capture_swipe_with_idea
        let captureKeywords = ["swipe", "capture", "save", "grab", "snag", "file this",
                               "swipe this", "grab this", "save this"]
        let ideaKeywords = ["idea", "could do", "similar", "angle", "topic",
                            "great for", "inspiration", "we should", "let's try",
                            "perfect for", "good for", "try this"]

        let hasCaptureSignal = captureKeywords.contains(where: { lower.contains($0) })
        let hasIdeaSignal = ideaKeywords.contains(where: { lower.contains($0) })

        // Only fast-path simple captures. If there's idea language, let the LLM route.
        guard hasCaptureSignal && !hasIdeaSignal else {
            // Also fast-path bare URLs with no other text
            let textWithoutURL = text.replacingOccurrences(of: urlString, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard textWithoutURL.isEmpty else { return nil }
            // Bare URL — treat as capture
            return await executeFastCapture(url: urlString, chatId: chatId)
        }

        // Also check for client mention — if a client name is mentioned alongside "for",
        // let the LLM handle for proper client resolution
        if lower.contains(" for ") {
            let afterFor = lower.components(separatedBy: " for ").last ?? ""
            let words = afterFor.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if let firstWord = words.first, firstWord.count > 2,
               !captureKeywords.contains(firstWord) && !["this", "that", "me", "it"].contains(firstWord) {
                // Likely a client name — let LLM handle
                return nil
            }
        }

        await sendChatAction(chatId: chatId, action: "typing")
        return await executeFastCapture(url: urlString, chatId: chatId)
    }

    /// Execute capture_swipe directly via the tool executor
    private func executeFastCapture(url: String, chatId: String) async -> String {
        await sendChatAction(chatId: chatId, action: "typing")
        do {
            let result = try await AgentToolExecutor.shared.execute(
                toolName: "capture_swipe",
                arguments: ["url": url]
            )
            // Parse the result to build a friendly message
            if let data = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["success"] as? Bool == true {
                let title = json["title"] as? String ?? "Untitled"
                let source = json["source"] as? String ?? "URL"

                // Track in conversation memory
                if let uuid = json["uuid"] as? String {
                    var conversation: AgentConversation
                    if let existing = await ConversationMemoryService.shared.loadConversation(id: chatId) {
                        conversation = existing
                    } else {
                        conversation = AgentConversation(id: chatId, source: .telegram)
                    }
                    conversation.append(.user(url))
                    if !conversation.linkedAtomUUIDs.contains(uuid) {
                        conversation.linkedAtomUUIDs.append(uuid)
                    }
                    let responseText = "Captured: \(title) (\(source))"
                    conversation.append(.assistant(responseText))
                    await ConversationMemoryService.shared.saveConversation(conversation)
                }

                let sourceDisplay = source.contains("youtube") ? "YouTube" :
                    source.contains("instagram") ? "Instagram" :
                    source.contains("twitter") || source.contains("x.com") ? "X / Twitter" :
                    source.contains("linkedin") ? "LinkedIn" :
                    source.contains("threads") ? "Threads" : source

                var msg = "📌 Swiped!\n\n\(title)"
                msg += "\n🔗 \(sourceDisplay)"
                return msg
            } else if let data = result.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let error = json["error"] as? String {
                return "Capture failed: \(error)"
            }
            return "Swiped."
        } catch {
            return "Capture failed: \(error.localizedDescription)"
        }
    }

    private func handleVoiceMessage(fileId: String, chatId: String) async {
        // Show typing indicator while processing voice
        await sendChatAction(chatId: chatId, action: "typing")

        do {
            // 1. Get file path from Telegram
            let filePath = try await getFilePath(fileId: fileId)

            // 2. Download the file
            let audioData = try await downloadFile(filePath: filePath)

            // 3. Transcribe via Whisper
            let text = try await WhisperTranscriptionService.shared.transcribe(audioData: audioData, format: .ogg)

            // 4. Send transcription preview
            await sendMessage(chatId: chatId, text: "*Heard:* \(text)", parseMode: "Markdown")

            // 5. Route — writing session takes precedence
            if TelegramWritingSessionManager.shared.hasActiveSession(for: chatId) {
                if TelegramWritingSessionManager.shared.isExitCommand(text) {
                    let response = await TelegramWritingSessionManager.shared.endSession(chatId: chatId)
                    await sendLongMessage(chatId: chatId, text: response)
                } else if TelegramWritingSessionManager.shared.isCommitCommand(text) {
                    let response = await TelegramWritingSessionManager.shared.commitSession(chatId: chatId)
                    await sendLongMessage(chatId: chatId, text: response)
                    notifyDesktopContentCreated(title: "Voice writing session committed via Telegram")
                } else {
                    let response = await TelegramWritingSessionManager.shared.routeMessage(chatId: chatId, text: text)
                    await sendLongMessage(chatId: chatId, text: response)
                }
                return
            }

            if TelegramWritingSessionManager.shared.isWritingTrigger(text) {
                let response = await TelegramWritingSessionManager.shared.startSession(chatId: chatId, text: text)
                await sendLongMessage(chatId: chatId, text: response)
                return
            }

            // ── VoiceToContentPipeline for substantial idea-expression voice memos ──
            // Messages ≥50 words that look like idea expression (not short commands or
            // questions) get routed through the full 7-step pipeline:
            // transcribe → NLP → swipe match → framework → content atom → draft.
            let wordCount = text.split(separator: " ").count
            let lowerText = text.lowercased()
            let isShortCommand = wordCount < 15
            let isQuestion = lowerText.hasSuffix("?") && wordCount < 25
            let isIdeaExpression = wordCount >= 50 &&
                !isShortCommand && !isQuestion &&
                !lowerText.hasPrefix("what") && !lowerText.hasPrefix("how") &&
                !lowerText.hasPrefix("can you") && !lowerText.hasPrefix("please")

            if isIdeaExpression {
                // Send progress header
                await sendMessage(
                    chatId: chatId,
                    text: "🎙 *Voice idea detected* — running full pipeline...",
                    parseMode: "Markdown"
                )
                let pipeline = VoiceToContentPipeline(chatId: chatId)
                let result = await pipeline.execute(transcribedText: text)

                // Build the confirmation message
                var confirmLines = ["✅ *Idea processed*"]
                if let draftBody = result.draftBody, !draftBody.isEmpty {
                    confirmLines.append("\n*Draft preview:*\n" + String(draftBody.prefix(600)))
                } else {
                    confirmLines.append("Draft is ready in your content pipeline.")
                }
                if result.matchingSwipeCount > 0 {
                    let count = result.matchingSwipeCount
                    confirmLines.append("📎 \(count) matching swipe\(count == 1 ? "" : "s") referenced")
                }
                if let framework = result.recommendedFramework {
                    confirmLines.append("🏗 Framework: \(framework)")
                }
                await sendLongMessage(chatId: chatId, text: confirmLines.joined(separator: "\n"))
                notifyDesktopContentCreated(
                    contentUUID: result.contentUUID.flatMap({ UUID(uuidString: $0) }),
                    title: result.summary ?? "Voice idea from Telegram"
                )
                return
            }
            // ──────────────────────────────────────────────────────────────────

            // Short messages and questions fall through to the general agent
            let typingTask = Task { await self.keepTyping(chatId: chatId) }
            let (response, trace) = await CosmoAgentService.shared.processMessage(
                text,
                conversationId: chatId,
                source: .telegram
            )
            typingTask.cancel()
            await sendLongMessage(chatId: chatId, text: response)
            if let contextSummary = TelegramRichMessages.shared.formatContextTrace(trace) {
                await sendMessage(chatId: chatId, text: contextSummary)
            }

        } catch {
            await sendMessage(chatId: chatId, text: "Couldn't process voice message: \(error.localizedDescription)")
        }
    }

    private func getFilePath(fileId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/getFile?file_id=\(fileId)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let filePath = result["file_path"] as? String else {
            throw TelegramError.fileNotFound
        }

        return filePath
    }

    private func downloadFile(filePath: String) async throws -> Data {
        guard let token = botToken else { throw TelegramError.noBotToken }
        let url = URL(string: "https://api.telegram.org/file/bot\(token)/\(filePath)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    // MARK: - Send Message

    /// Send a message with automatic 429 rate limit retry and exponential backoff.
    @discardableResult
    func sendMessage(chatId: String, text: String, parseMode: String? = nil, replyMarkup: Any? = nil) async -> Bool {
        // Lazy-load token for proactive messages sent outside the polling loop
        if cachedToken == nil {
            cachedToken = loadTokenFromKeychain()
        }
        guard !baseURL.isEmpty else { return false }

        let url = URL(string: "\(baseURL)/sendMessage")!

        var body: [String: Any] = [
            "chat_id": chatId,
            "text": text
        ]

        if let parseMode = parseMode {
            body["parse_mode"] = parseMode
        }

        if let markup = replyMarkup {
            body["reply_markup"] = ["inline_keyboard": markup]
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return false }

        var retryCount = 0
        while retryCount <= maxSendRetries {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = httpBody

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 429 {
                        // Rate limited — extract Retry-After or use exponential backoff
                        let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After")
                        // Also check Telegram's JSON body for retry_after field
                        var retryAfterFromBody: Double?
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let params = json["parameters"] as? [String: Any],
                           let ra = params["retry_after"] as? Double {
                            retryAfterFromBody = ra
                        }
                        let waitTime = retryAfterFromBody
                            ?? Double(retryAfterHeader ?? "")
                            ?? pow(2.0, Double(retryCount + 1))
                        print("[Telegram] Rate limited (429). Waiting \(waitTime)s before retry \(retryCount + 1)/\(maxSendRetries)")
                        try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                        retryCount += 1
                        continue
                    }

                    if httpResponse.statusCode == 200 {
                        return true
                    }

                    // Non-retryable error
                    let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
                    print("[Telegram] sendMessage failed HTTP \(httpResponse.statusCode): \(errorBody)")
                    return false
                }
            } catch {
                print("[Telegram] Failed to send message: \(error)")
                return false
            }
        }

        print("[Telegram] sendMessage retries exhausted after \(maxSendRetries) attempts")
        return false
    }

    // MARK: - Long Message (Chunked Send)

    /// Split long responses at paragraph boundaries to stay within Telegram's 4096 char limit.
    func sendLongMessage(chatId: String, text: String, parseMode: String? = nil) async {
        let maxLength = 4096

        if text.count <= maxLength {
            await sendMessage(chatId: chatId, text: text, parseMode: parseMode)
            return
        }

        // Split at paragraph boundaries
        let paragraphs = text.components(separatedBy: "\n\n")
        var currentChunk = ""

        for para in paragraphs {
            let candidate = currentChunk.isEmpty ? para : (currentChunk + "\n\n" + para)
            if candidate.count > maxLength {
                // Send accumulated chunk if non-empty
                if !currentChunk.isEmpty {
                    await sendMessage(chatId: chatId, text: currentChunk, parseMode: parseMode)
                }
                // If a single paragraph exceeds the limit, hard-split it
                if para.count > maxLength {
                    var remaining = para
                    while !remaining.isEmpty {
                        let chunk = String(remaining.prefix(maxLength))
                        await sendMessage(chatId: chatId, text: chunk, parseMode: parseMode)
                        remaining = String(remaining.dropFirst(maxLength))
                    }
                    currentChunk = ""
                } else {
                    currentChunk = para
                }
            } else {
                currentChunk = candidate
            }
        }

        if !currentChunk.isEmpty {
            await sendMessage(chatId: chatId, text: currentChunk, parseMode: parseMode)
        }
    }

    // MARK: - Chat Actions

    /// Send a chat action (e.g. "typing") to show activity indicator in Telegram.
    func sendChatAction(chatId: String, action: String = "typing") async {
        if cachedToken == nil {
            cachedToken = loadTokenFromKeychain()
        }
        guard !baseURL.isEmpty else { return }

        let url = URL(string: "\(baseURL)/sendChatAction")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "chat_id": chatId,
            "action": action
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let _ = try? await URLSession.shared.data(for: request)
    }

    /// Repeatedly send "typing" action every 4 seconds until cancelled.
    /// Telegram's typing indicator expires after ~5s, so this keeps it alive.
    private func keepTyping(chatId: String) async {
        await sendChatAction(chatId: chatId, action: "typing")
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { break }
            await sendChatAction(chatId: chatId, action: "typing")
        }
    }

    // MARK: - Edit Message

    /// Edit an existing message (for streaming or progress updates)
    func editMessage(chatId: String, messageId: Int, text: String, parseMode: String? = nil) async {
        if cachedToken == nil {
            cachedToken = loadTokenFromKeychain()
        }
        guard !baseURL.isEmpty else { return }

        let url = URL(string: "\(baseURL)/editMessageText")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "chat_id": chatId,
            "message_id": messageId,
            "text": text
        ]
        if let parseMode = parseMode {
            body["parse_mode"] = parseMode
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let _ = try await URLSession.shared.data(for: request)
        } catch {
            print("[Telegram] Failed to edit message: \(error)")
        }
    }

    /// Send a message and return the message ID for later editing
    func sendMessageReturningId(chatId: String, text: String) async -> Int? {
        if cachedToken == nil {
            cachedToken = loadTokenFromKeychain()
        }
        guard !baseURL.isEmpty else { return nil }

        let url = URL(string: "\(baseURL)/sendMessage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "chat_id": chatId,
            "text": text
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let messageId = result["message_id"] as? Int {
                return messageId
            }
        } catch {
            print("[Telegram] Failed to send message: \(error)")
        }
        return nil
    }

    // MARK: - Callback Query (Inline Buttons)

    private func handleCallbackQuery(_ callback: [String: Any]) async {
        guard let callbackId = callback["id"] as? String,
              let data = callback["data"] as? String,
              let message = callback["message"] as? [String: Any],
              let chat = message["chat"] as? [String: Any],
              let chatId = chat["id"] as? Int else { return }

        // Answer the callback to remove loading indicator
        await answerCallbackQuery(callbackId: callbackId)

        let chatIdStr = "\(chatId)"

        // Handle confirmation responses
        if data.hasPrefix("confirm:") {
            let confirmationId = String(data.dropFirst("confirm:".count))
            let result = await CosmoAgentService.shared.confirmAction(confirmationId: confirmationId)
            await sendLongMessage(chatId: chatIdStr, text: result)
        } else if data.hasPrefix("cancel:") {
            await sendMessage(chatId: chatIdStr, text: "Action cancelled.")
        }
        // Handle workflow approvals
        else if data.hasPrefix("workflow_approve:") {
            let (response, _) = await CosmoAgentService.shared.processMessage("approve", conversationId: chatIdStr, source: .telegram)
            await sendLongMessage(chatId: chatIdStr, text: response)
        } else if data.hasPrefix("workflow_cancel:") {
            let (response, _) = await CosmoAgentService.shared.processMessage("cancel", conversationId: chatIdStr, source: .telegram)
            await sendLongMessage(chatId: chatIdStr, text: response)
        }
        // Handle morning brief actions
        else if data == "morning_pipeline" {
            let (response, _) = await CosmoAgentService.shared.processMessage("show my content pipeline", conversationId: chatIdStr, source: .telegram)
            await sendLongMessage(chatId: chatIdStr, text: response)
        } else if data == "morning_start" {
            let (response, _) = await CosmoAgentService.shared.processMessage("what should I work on first?", conversationId: chatIdStr, source: .telegram)
            await sendLongMessage(chatId: chatIdStr, text: response)
        }
        // Handle lesson confirmation buttons
        else if data.hasPrefix("lesson_yes:") {
            let uuidStr = String(data.dropFirst("lesson_yes:".count))
            if let lessonID = UUID(uuidString: uuidStr) {
                await LessonExtractor.shared.updateConfidence(lessonID: lessonID, confirmed: true, fastConfirm: true)
                // Auto-route to matching skill module
                if let lesson = await LessonExtractor.shared.loadLesson(byID: lessonID),
                   let moduleId = PromptTemplateStore.categoryToModuleMap[lesson.category] {
                    let formatted = LessonExtractor.shared.formatLessonForModule(lesson)
                    PromptTemplateStore.shared.appendLessonToModule(moduleId: moduleId, formattedRule: formatted)
                    let moduleName = PromptTemplateStore.shared.modules.first(where: { $0.id == moduleId })?.title ?? moduleId
                    await sendMessage(chatId: chatIdStr, text: "Saved and added to \(moduleName).")
                } else {
                    await sendMessage(chatId: chatIdStr, text: "Got it — rule saved.")
                }
            }
        } else if data.hasPrefix("lesson_no:") {
            let uuidStr = String(data.dropFirst("lesson_no:".count))
            if let lessonID = UUID(uuidString: uuidStr) {
                await LessonExtractor.shared.updateConfidence(lessonID: lessonID, confirmed: false)
                await sendMessage(chatId: chatIdStr, text: "Discarded.")
            }
        } else if data.hasPrefix("lesson_correct:") {
            let uuidStr = String(data.dropFirst("lesson_correct:".count))
            pendingLessonCorrections[chatIdStr] = uuidStr
            await sendMessage(chatId: chatIdStr, text: "What should the rule be instead?")
        } else if data.hasPrefix("lesson_reroute:") {
            let uuidStr = String(data.dropFirst("lesson_reroute:".count))
            // Show module picker — list all modules as inline keyboard buttons (2 per row)
            let allModules = PromptTemplateStore.shared.modules
            var moduleButtons: [[Any]] = []
            for i in stride(from: 0, to: allModules.count, by: 2) {
                var row: [Any] = []
                row.append(["text": allModules[i].title, "callback_data": "lesson_tomod:\(uuidStr):\(allModules[i].id)"] as [String: Any])
                if i + 1 < allModules.count {
                    row.append(["text": allModules[i + 1].title, "callback_data": "lesson_tomod:\(uuidStr):\(allModules[i + 1].id)"] as [String: Any])
                }
                moduleButtons.append(row)
            }
            await sendMessage(chatId: chatIdStr, text: "Which module should this go to?", replyMarkup: moduleButtons)
        } else if data.hasPrefix("lesson_tomod:") {
            let payload = String(data.dropFirst("lesson_tomod:".count))
            let parts = payload.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let lessonID = UUID(uuidString: String(parts[0])) else { return }
            let moduleId = String(parts[1])

            await LessonExtractor.shared.updateConfidence(lessonID: lessonID, confirmed: true, fastConfirm: true)
            if let lesson = await LessonExtractor.shared.loadLesson(byID: lessonID) {
                let formatted = LessonExtractor.shared.formatLessonForModule(lesson)
                PromptTemplateStore.shared.appendLessonToModule(moduleId: moduleId, formattedRule: formatted)
                let moduleName = PromptTemplateStore.shared.modules.first(where: { $0.id == moduleId })?.title ?? moduleId
                await sendMessage(chatId: chatIdStr, text: "Added to \(moduleName).")
            }
        }
        // Handle module suggestion buttons
        else if data.hasPrefix("module_approve:") {
            let suggestionId = String(data.dropFirst("module_approve:".count))
            if let suggestion = pendingModuleSuggestions.removeValue(forKey: suggestionId) {
                if suggestion.action == "add_to_module", let moduleId = suggestion.moduleId {
                    PromptTemplateStore.shared.appendLessonToModule(moduleId: moduleId, formattedRule: suggestion.content)
                    let moduleName = PromptTemplateStore.shared.modules.first(where: { $0.id == moduleId })?.title ?? moduleId
                    await sendMessage(chatId: chatIdStr, text: "Added to \(moduleName).")
                } else if suggestion.action == "create_module",
                          let newId = suggestion.newModuleId,
                          let newTitle = suggestion.newModuleTitle {
                    PromptTemplateStore.shared.addCustomModule(id: newId, title: newTitle, content: suggestion.content)
                    await sendMessage(chatId: chatIdStr, text: "Created new module: \(newTitle).")
                }
            } else {
                await sendMessage(chatId: chatIdStr, text: "Suggestion expired or already handled.")
            }
        } else if data.hasPrefix("module_reject:") {
            let suggestionId = String(data.dropFirst("module_reject:".count))
            pendingModuleSuggestions.removeValue(forKey: suggestionId)
            await sendMessage(chatId: chatIdStr, text: "Discarded.")
        } else if data.hasPrefix("module_edit:") {
            let suggestionId = String(data.dropFirst("module_edit:".count))
            if pendingModuleSuggestions[suggestionId] != nil {
                pendingModuleEdits[chatIdStr] = suggestionId
                await sendMessage(chatId: chatIdStr, text: "Send the corrected text:")
            } else {
                await sendMessage(chatId: chatIdStr, text: "Suggestion expired or already handled.")
            }
        }
        // Handle agent-generated inline buttons — route action text as a regular user message
        else if data.hasPrefix("agent_btn:") {
            let action = String(data.dropFirst("agent_btn:".count))
            await sendChatAction(chatId: chatIdStr, action: "typing")
            let (response, trace) = await CosmoAgentService.shared.processMessage(action, conversationId: chatIdStr, source: .telegram)
            await sendLongMessage(chatId: chatIdStr, text: response)
            if let contextSummary = TelegramRichMessages.shared.formatContextTrace(trace) {
                await sendMessage(chatId: chatIdStr, text: contextSummary)
            }
        }
    }

    private func answerCallbackQuery(callbackId: String) async {
        let url = URL(string: "\(baseURL)/answerCallbackQuery")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["callback_query_id": callbackId])
        let _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Send Confirmation Prompt

    func sendConfirmationPrompt(chatId: String, confirmationId: String, description: String) async {
        let buttons: [[[String: String]]] = [
            [
                ["text": "Approve", "callback_data": "confirm:\(confirmationId)"],
                ["text": "Cancel", "callback_data": "cancel:\(confirmationId)"]
            ]
        ]
        await sendMessage(
            chatId: chatId,
            text: "*Confirmation Required*\n\n\(description)",
            parseMode: "Markdown",
            replyMarkup: buttons
        )
    }

    // MARK: - Desktop Push Notifications

    /// Post an in-app notification when content is created via Telegram, so the desktop
    /// app can surface it even if it's not in the foreground.
    func notifyDesktopContentCreated(contentUUID: UUID? = nil, title: String) {
        // 1. In-process notification for any open CosmoOS views
        NotificationCenter.default.post(
            name: CosmoNotification.Telegram.contentCreated,
            object: nil,
            userInfo: [
                "title": title,
                "source": "telegram",
                "contentUUID": contentUUID?.uuidString ?? ""
            ]
        )

        // 2. macOS user notification (shows even if app is in background)
        let content = UNMutableNotificationContent()
        content.title = "Cosmo -- Telegram"
        content.body = title
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "telegram-\(UUID().uuidString)",
            content: content,
            trigger: nil  // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Telegram] Failed to schedule notification: \(error)")
            }
        }
    }
}
