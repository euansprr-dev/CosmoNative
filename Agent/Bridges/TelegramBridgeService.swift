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
    case webhookConflict // Cloud webhook is active — stop local polling

    var errorDescription: String? {
        switch self {
        case .noBotToken: return "No Telegram bot token configured"
        case .invalidResponse: return "Invalid response from Telegram API"
        case .fileNotFound: return "Telegram file not found"
        case .sendFailed(let msg): return "Failed to send message: \(msg)"
        case .rateLimited(let seconds): return "Rate limited. Retry after \(Int(seconds))s"
        case .webhookConflict: return "Cloud webhook active — local polling stopped"
        }
    }
}

// MARK: - Writing Progress Tracker

/// Sends progressive Telegram message edits showing writing pipeline milestones.
/// Lazily activated — only sends a message when the first writing-related tool event fires.
private actor TelegramWritingProgressTracker {

    private let chatId: String
    private weak var service: TelegramBridgeService?

    private var messageId: Int?
    private var completedLines: [String] = []
    private var activeLine: String?
    private var completedPhases: Set<String> = []
    private var isActive = false
    private var isFinalized = false

    // Throttled flush state
    private var isDirty = false
    private var flushTask: Task<Void, Never>?
    private var lastEditTime: Date = .distantPast
    private let throttleInterval: TimeInterval = 1.5

    // MARK: - Tool Filters

    private static let milestoneTools: Set<String> = [
        // Engine context-loading
        "load_client_profile", "select_swipes", "load_swipe", "load_best_performers",
        "load_preferences", "load_skill_modules",
        // Agent-level writing tools
        "generate_outline", "generate_draft", "generate_hooks", "revise_draft",
        // Engine inner-loop writing tools
        "update_outline", "write_draft", "add_hooks",
    ]

    // MARK: - Init

    init(chatId: String, service: TelegramBridgeService) {
        self.chatId = chatId
        self.service = service
    }

    // MARK: - Event Handling

    func handle(_ event: ToolActivityEvent) async {
        guard !isFinalized else { return }

        switch event {
        case .started(let name, let displayLabel, _):
            guard Self.milestoneTools.contains(name) else { return }
            if !isActive { isActive = true }
            activeLine = displayLabel
            scheduleFlush()

        case .completed(let name, let displayLabel, let resultPreview):
            guard Self.milestoneTools.contains(name) else { return }
            if !isActive { isActive = true }

            // Dedup: skip if this writing phase was already recorded
            if let phase = Self.phaseFor(name), completedPhases.contains(phase) { return }
            if let phase = Self.phaseFor(name) { completedPhases.insert(phase) }

            completedLines.append(Self.buildCompletedLine(name: name, displayLabel: displayLabel, resultPreview: resultPreview))
            activeLine = nil
            scheduleFlush()

        case .allDone:
            break // handled by finalize()
        }
    }

    /// Mark the progress message as complete after processMessage() returns.
    func finalize() async {
        guard isActive, !isFinalized else { return }
        isFinalized = true
        flushTask?.cancel()
        flushTask = nil
        activeLine = nil
        await flush(isFinal: true)
    }

    // MARK: - Phase Deduplication

    private static func phaseFor(_ toolName: String) -> String? {
        switch toolName {
        case "generate_outline", "update_outline": return "outline"
        case "generate_draft", "write_draft": return "draft"
        case "generate_hooks", "add_hooks": return "hooks"
        case "revise_draft": return "revise"
        default: return nil
        }
    }

    // MARK: - Message Building

    private static func buildCompletedLine(name: String, displayLabel: String?, resultPreview: String?) -> String {
        switch name {
        case "load_client_profile":
            if let preview = resultPreview, !preview.isEmpty { return "Loaded profile: \(preview)" }
            return "Client profile loaded"
        case "load_swipe":
            // Show full swipe title from displayLabel (e.g. "Swipe: FULL TITLE" or "Client post: FULL TITLE")
            if let label = displayLabel, !label.isEmpty { return label }
            return "Swipe loaded"
        case "select_swipes":
            // Summary count — individual swipes already shown above via load_swipe
            if let preview = resultPreview, !preview.isEmpty { return "Selected \(preview.components(separatedBy: ", ").count) swipe examples" }
            return "Reference swipes selected"
        case "load_best_performers":
            if let preview = resultPreview, !preview.isEmpty { return "Best performers indexed (\(preview))" }
            return "Best performers indexed"
        case "load_preferences":
            if let preview = resultPreview, !preview.isEmpty { return "Preferences loaded (\(preview))" }
            return "Preferences loaded"
        case "load_skill_modules":
            return "Skills & methodology loaded"
        case "generate_outline", "update_outline":
            if let preview = resultPreview, !preview.isEmpty { return "Outline complete (\(String(preview.prefix(50))))" }
            return "Outline complete"
        case "generate_draft", "write_draft":
            if let preview = resultPreview {
                if let range = preview.range(of: #"(\d[\d,]*)\s*words"#, options: .regularExpression) {
                    return "Draft written (\(preview[range]))"
                }
            }
            return "Draft written"
        case "generate_hooks", "add_hooks":
            return "Hooks generated"
        case "revise_draft":
            return "Draft revised"
        default:
            return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func buildMessageText(isFinal: Bool) -> String {
        var parts: [String] = []
        parts.append(isFinal ? "✅ Writing complete" : "🔄 Writing pipeline active")
        parts.append("")
        for line in completedLines {
            parts.append("  ✓ \(line)")
        }
        if !isFinal, let active = activeLine {
            parts.append("  ⏳ \(active)...")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Throttled Flush

    private func scheduleFlush() {
        isDirty = true
        guard flushTask == nil else { return }

        flushTask = Task {
            while isDirty {
                isDirty = false
                let elapsed = Date().timeIntervalSince(lastEditTime)
                if elapsed < throttleInterval {
                    try? await Task.sleep(for: .seconds(throttleInterval - elapsed))
                }
                guard !isFinalized else { break }
                await flush(isFinal: false)
            }
            flushTask = nil
        }
    }

    private func flush(isFinal: Bool) async {
        guard isActive, let service else { return }
        let text = buildMessageText(isFinal: isFinal)

        if let existingId = messageId {
            await service.editMessage(chatId: chatId, messageId: existingId, text: text)
        } else {
            let id = await service.sendMessageReturningId(chatId: chatId, text: text)
            messageId = id
        }
        lastEditTime = Date()
    }
}

@MainActor
class TelegramBridgeService: ObservableObject {
    static let shared = TelegramBridgeService()

    nonisolated static func shouldUseExplicitLessonFastPath(_ text: String) -> Bool {
        ExplicitLessonCaptureParser.parse(text) != nil
    }

    @Published var isConnected = false
    @Published var lastError: String?
    @Published var messageCount = 0

    private var pollingTask: Task<Void, Never>?
    private var updateOffset: Int = 0
    private var backoffInterval: TimeInterval = 1.0
    private let maxBackoff: TimeInterval = 30.0

    /// Cached token — read from Keychain once on start(), not on every poll
    private var cachedToken: String?

    /// Cached bot username (fetched once via getMe on start) for @mention detection in groups
    private var botUsername: String?

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
        // Skip local polling when cloud agent is deployed.
        // Check BOTH Supabase session state AND persistent keychain auth.
        // isSignedIn can be false during startup due to Supabase session restoration race,
        // but hasSupabaseAuth reads from keychain which is always available.
        if SupabaseAuthService.shared.isSignedIn || APIKeys.hasSupabaseAuth {
            print("[Telegram] Cloud agent active — skipping local polling (webhook handles messages)")
            isConnected = true
            return
        }

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

        // Fetch bot username for @mention gating in group chats
        await fetchBotUsername()

        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }

        print("[Telegram] Bridge started (local polling — no cloud agent)")
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

                // Webhook conflict = cloud agent is active, stop polling entirely
                if let telegramError = error as? TelegramError, case .webhookConflict = telegramError {
                    isConnected = true // Mark as connected (cloud handles it)
                    lastError = nil
                    return // Exit poll loop gracefully
                }

                lastError = error.localizedDescription
                print("[Telegram] Polling error: \(error). Retrying in \(backoffInterval)s")

                try? await Task.sleep(for: .seconds(backoffInterval))
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
            URLQueryItem(name: "allowed_updates", value: "[\"message\",\"channel_post\",\"callback_query\",\"my_chat_member\"]")
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
            // 409 = webhook is active (cloud agent is handling messages)
            // Stop polling gracefully instead of retrying forever
            if httpResponse.statusCode == 409 {
                print("[Telegram] Cloud webhook is active (409 conflict) — stopping local polling. Cloud agent handles messages.")
                throw TelegramError.webhookConflict
            }
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
        // Handle regular messages (DMs, groups, supergroups)
        if let message = update["message"] as? [String: Any] {
            await handleMessage(message)
        }

        // Handle channel posts (Telegram Channels — broadcast chats)
        // Channel posts use "channel_post" key, not "message".
        if let channelPost = update["channel_post"] as? [String: Any] {
            await handleMessage(channelPost)
        }

        // Handle callback queries (inline button presses)
        if let callback = update["callback_query"] as? [String: Any] {
            await handleCallbackQuery(callback)
        }
    }

    // MARK: - Forum Topic Thread ID Helpers

    /// Parses a composite conversation ID back into its chat ID and optional thread ID.
    /// Composite format: "chatId:threadId" (Forum Topics) or just "chatId" (DMs).
    static func parseChatThread(_ compositeId: String) -> (chatId: String, threadId: Int?) {
        let parts = compositeId.split(separator: ":", maxSplits: 1)
        if parts.count == 2, let threadId = Int(parts[1]) {
            return (String(parts[0]), threadId)
        }
        return (compositeId, nil)
    }

    // MARK: - Bot Username & Mention Detection

    /// Fetch the bot's username once via the getMe API for @mention detection in groups.
    private func fetchBotUsername() async {
        guard !baseURL.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/getMe") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let username = result["username"] as? String else { return }
        botUsername = username.lowercased()
        print("[Telegram] Bot username: @\(botUsername ?? "unknown")")
    }

    /// Check if the bot is @mentioned in the message entities.
    private func isBotMentioned(message: [String: Any], text: String) -> Bool {
        guard let botName = botUsername else { return true } // if unknown, allow all

        // Primary: Check Telegram entity metadata (most reliable)
        if let entities = message["entities"] as? [[String: Any]] {
            let lowerText = text.lowercased()
            for entity in entities {
                guard let type = entity["type"] as? String else { continue }
                if type == "mention",
                   let offset = entity["offset"] as? Int,
                   let length = entity["length"] as? Int {
                    let start = lowerText.index(lowerText.startIndex, offsetBy: offset, limitedBy: lowerText.endIndex) ?? lowerText.startIndex
                    let end = lowerText.index(start, offsetBy: length, limitedBy: lowerText.endIndex) ?? lowerText.endIndex
                    let mention = String(lowerText[start..<end]).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                    if mention == botName { return true }
                }
                if type == "text_mention",
                   let user = entity["user"] as? [String: Any],
                   user["is_bot"] as? Bool == true {
                    return true
                }
            }
        }

        // Fallback: Plain text @mention check (catches edge cases where entities are missing)
        if text.lowercased().contains("@\(botName)") {
            return true
        }

        return false
    }

    /// Check if the message is a reply to one of the bot's own messages.
    private func isReplyToBot(message: [String: Any]) -> Bool {
        guard let reply = message["reply_to_message"] as? [String: Any],
              let from = reply["from"] as? [String: Any] else { return false }
        return from["is_bot"] as? Bool == true
    }

    /// Strip the bot's @mention from the text so it doesn't confuse the LLM.
    private func stripBotMention(from text: String) -> String {
        guard let botName = botUsername else { return text }
        // Remove @botname (case-insensitive) and any trailing space
        let pattern = "(?i)@\(NSRegularExpression.escapedPattern(for: botName))\\s?"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: [String: Any]) async {
        guard let chat = message["chat"] as? [String: Any],
              let chatId = chat["id"] as? Int else { return }

        // Extract Forum Topic thread ID (present in Forum group messages)
        let threadId = message["message_thread_id"] as? Int

        // Composite conversation ID: "chatId:threadId" for Forum Topics, "chatId" for DMs
        let chatIdStr: String
        if let threadId = threadId {
            chatIdStr = "\(chatId):\(threadId)"
        } else {
            chatIdStr = "\(chatId)"
        }
        activeChatId = chatIdStr
        messageCount += 1

        let media = extractCapturedMedia(from: message)
        let caption = message["caption"] as? String
        let messageId = (message["message_id"] as? Int).map(String.init)
        let mediaGroupId = message["media_group_id"] as? String
        let sender = (message["from"] as? [String: Any]).flatMap { from -> String? in
            if let username = from["username"] as? String { return username }
            if let first = from["first_name"] as? String { return first }
            return nil
        }

        // Voice/audio messages without explicit capture captions preserve the existing
        // transcription route. Captioned voice can use custom lanes: `current inquiry:`.
        if media.contains(where: { $0.kind == .audio }),
           (caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
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
        }

        guard let rawText = (message["text"] as? String) ?? caption else {
            if !media.isEmpty {
                let outcome = await TelegramCaptureRouter.shared.routeTelegramCapture(
                    text: nil,
                    media: media,
                    chatId: chatIdStr,
                    messageId: messageId,
                    mediaGroupId: mediaGroupId,
                    sender: sender
                )
                if case .handled(let reply, let capturedItemId) = outcome {
                    await sendMessage(chatId: chatIdStr, text: reply)
                    await scheduleMediaDownloads(capturedItemId: capturedItemId)
                }
            }
            return
        }

        // In groups/supergroups, only respond to @mentions or replies to the bot.
        // In channels, process all messages (the bot must be an admin to see them).
        let chatType = chat["type"] as? String ?? "private"
        if chatType == "group" || chatType == "supergroup" {
            let mentioned = isBotMentioned(message: message, text: rawText)
            let replying = isReplyToBot(message: message)
            print("[Telegram] Group message in \(chatIdStr) — mentioned: \(mentioned), reply: \(replying), botUsername: \(botUsername ?? "nil")")
            guard mentioned || replying else { return }
        } else if chatType == "channel" {
            print("[Telegram] Channel message in \(chatIdStr): \(rawText.prefix(60))...")
        }
        print("[Telegram] Processing message from \(chatType) chat \(chatIdStr): \(rawText.prefix(60))...")

        // Strip bot @mention from text so it doesn't confuse the LLM
        let text = (chatType == "group" || chatType == "supergroup")
            ? stripBotMention(from: rawText)
            : rawText

        if !media.isEmpty {
            let outcome = await TelegramCaptureRouter.shared.routeTelegramCapture(
                text: text,
                media: media,
                chatId: chatIdStr,
                messageId: messageId,
                mediaGroupId: mediaGroupId,
                sender: sender
            )
            if case .handled(let reply, let capturedItemId) = outcome {
                await sendMessage(chatId: chatIdStr, text: reply)
                await scheduleMediaDownloads(capturedItemId: capturedItemId)
                return
            }
        } else if TelegramCaptureCommandParser.parse(text, allowsEmptyBody: false) != nil {
            let outcome = await TelegramCaptureRouter.shared.routeTelegramCapture(
                text: text,
                chatId: chatIdStr,
                messageId: messageId,
                mediaGroupId: mediaGroupId,
                sender: sender
            )
            if case .handled(let reply, _) = outcome {
                await sendMessage(chatId: chatIdStr, text: reply)
                return
            }
        }

        // /start command bypasses debounce
        if text == "/start" {
            let welcome = """
            Hey! I'm Cosmo, your AI creative partner.

            I have full access to your CosmoOS knowledge graph. Ask me about your ideas, swipes, content pipeline, schedule, or just brainstorm.

            Say "opus mode" to enter writing mode with the full writing engine.
            Writer model: \(TelegramWriterModel.current.displayName) — /model to switch.

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

        // /model command — toggle writing model for A/B split testing
        if text == "/model" || text.hasPrefix("/model ") {
            let arg = String(text.dropFirst("/model".count)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let newModel: TelegramWriterModel
            if arg.isEmpty {
                newModel = TelegramWriterModel.toggle()
            } else if arg.contains("opus") || arg.contains("claude") {
                TelegramWriterModel.setCurrent(.opus)
                newModel = .opus
            } else if arg.contains("gpt") || arg.contains("5.4") || arg.contains("openai") {
                TelegramWriterModel.setCurrent(.gpt5)
                newModel = .gpt5
            } else {
                await sendMessage(chatId: chatIdStr, text: "Unknown model. Use /model to toggle, or /model opus / /model gpt")
                return
            }
            await sendMessage(chatId: chatIdStr, text: "Writer model → \(newModel.displayName) ✓\nApplies to new writing sessions.")
            return
        }

        // Inquiry Workspace: alias-prefixed captures (`breathwork:` / `bw/q:` etc.)
        // bypass FlashLiteRouter and route directly to Topic Inbox / Question / Source / Lexicon / Extract.
        if let topicCapture = TelegramTopicAliasParser.parse(text) {
            let outcome = await TelegramTopicRouter.route(topicCapture)
            switch outcome {
            case .routed(let destination, _):
                await sendMessage(chatId: chatIdStr, text: "✓ Saved to \(destination).")
                return
            case .unknownAlias(let alias, let suggestion):
                // Save to the inbox NOW — the old fall-through promised an
                // inbox save but handed the text to routers that might never save it.
                let ingestOutcome = await InboxIngestService.shared.ingest(
                    .init(source: .telegramText, rawText: text)
                )
                let savedLine: String
                switch ingestOutcome {
                case .enqueued:
                    savedLine = "Saved to Inbox."
                case .consumed:
                    savedLine = "Already in your system — nothing new to capture."
                case .failed:
                    savedLine = "⚠️ Couldn't save it — please resend."
                }
                if let s = suggestion {
                    await sendMessage(chatId: chatIdStr, text: "? No alias '\(alias)' — did you mean '\(s)'? \(savedLine)")
                } else {
                    await sendMessage(chatId: chatIdStr, text: "? No Deep Dive alias '\(alias)'. \(savedLine)")
                }
                return
            case .failed(let reason):
                await sendMessage(chatId: chatIdStr, text: "✗ Couldn't route: \(reason)")
                return
            }
        }

        // Fast-path URL capture bypasses debounce for instant swipe saves
        if text.range(of: "https?://[^\\s]+", options: .regularExpression) != nil {
            if let fastCaptureResult = await tryFastCapture(text: text, chatId: chatIdStr) {
                await sendLongMessage(chatId: chatIdStr, text: fastCaptureResult)
                return
            }
        }

        if Self.shouldUseExplicitLessonFastPath(text),
           let lessonResponse = await CosmoAgentService.shared.tryExplicitLessonSave(
                text,
                conversationId: chatIdStr,
                source: .telegram
           ) {
            await sendLongMessage(chatId: chatIdStr, text: lessonResponse)
            return
        }

        // Flash-Lite router bypasses debounce for single messages (no rapid-fire buffer)
        // Handles ideas, tasks, queries, and any single-shot tool call via cheap LLM classification
        // Skip FlashLiteRouter for follow-up messages about already-captured content
        if !processingChatIds.contains(chatIdStr) && debounceBuffers[chatIdStr] == nil {
            let bypassFlash = await shouldBypassFlashRouter(text: text, chatId: chatIdStr)
            if !bypassFlash, let (response, toolName) = await FlashLiteRouter.shared.tryRoute(text) {
                await saveFlashRouterResult(text: text, response: response, toolName: toolName, chatId: chatIdStr)
                await sendMessage(chatId: chatIdStr, text: response)
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
            try? await Task.sleep(for: .seconds(self?.debounceWindow ?? 2.5))
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
            if UUID(uuidString: lessonIDStr) != nil {
                // Corrected rules land as pinned taste beliefs now.
                await TasteStore.addPinnedRule(text, category: "voice", clientUuid: nil)
                await sendMessage(chatId: chatId, text: "Got it — rule updated and saved to your taste profile.")
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
                    // Store as canonical lesson atom (no longer duplicated into module content)
                    let category = PromptTemplateStore.categoryToModuleMap.first(where: { $0.value == moduleId })?.key ?? "general"
                    _ = category
                    await TasteStore.addPinnedRule(text, category: "voice", clientUuid: nil)
                    let moduleName = PromptTemplateStore.shared.modules.first(where: { $0.id == moduleId })?.title ?? moduleId
                    await sendMessage(chatId: chatId, text: "Saved to your taste profile (was: \(moduleName)).")
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
            // 2c. Inline capture escape (!idea:, !task:, !swipe:, bare URL)
            if let captureResult = await tryInlineCaptureEscape(text: text, chatId: chatId) {
                await sendLongMessage(chatId: chatId, text: captureResult + "\n\n_(back in writing mode)_")
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

        if Self.shouldUseExplicitLessonFastPath(text),
           let lessonResponse = await CosmoAgentService.shared.tryExplicitLessonSave(
                text,
                conversationId: chatId,
                source: .telegram
           ) {
            await sendLongMessage(chatId: chatId, text: lessonResponse)
            return
        }

        // Flash-Lite router for debounced messages (ideas, tasks, queries, etc.)
        // Skip FlashLiteRouter for follow-up messages about already-captured content
        let bypassFlash = await shouldBypassFlashRouter(text: text, chatId: chatId)
        if !bypassFlash, let (flashResponse, toolName) = await FlashLiteRouter.shared.tryRoute(text) {
            await saveFlashRouterResult(text: text, response: flashResponse, toolName: toolName, chatId: chatId)
            await sendLongMessage(chatId: chatId, text: flashResponse)
            return
        }

        // Show typing indicator (refreshed every 4s while processing)
        let typingTask = Task { await self.keepTyping(chatId: chatId) }

        // Create progress tracker for writing pipeline visibility
        let progressTracker = TelegramWritingProgressTracker(chatId: chatId, service: self)
        let onProgress: @Sendable (ToolActivityEvent) -> Void = { event in
            Task { await progressTracker.handle(event) }
        }

        // Process through agent with progress tracking
        let (response, trace) = await CosmoAgentService.shared.processMessage(
            text,
            conversationId: chatId,
            source: .telegram,
            onToolActivity: onProgress
        )

        // Finalize progress message (mark as complete)
        await progressTracker.finalize()
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

    /// Lesson confirmations retired — the taste engine learns from edits
    /// directly, no Telegram confirmation loop.
    func sendPendingLessonConfirmations(chatId: String) async {}
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

    // MARK: - FlashLiteRouter Conversation Memory

    /// Save FlashLiteRouter-handled messages to conversation memory so follow-up messages have context.
    private func saveFlashRouterResult(text: String, response: String, toolName: String, chatId: String) async {
        var conversation: AgentConversation
        if let existing = await ConversationMemoryService.shared.loadConversation(id: chatId) {
            conversation = existing
        } else {
            conversation = AgentConversation(id: chatId, source: .telegram)
        }
        conversation.append(.user(text))
        conversation.append(.assistant(response))
        await ConversationMemoryService.shared.saveConversation(conversation)
    }

    /// Check if a message is a follow-up about already-captured content, meaning it should
    /// bypass FlashLiteRouter and go to the full agent for multi-turn reasoning.
    private func shouldBypassFlashRouter(text: String, chatId: String) async -> Bool {
        let lower = text.lowercased()

        // Always bypass for writing/drafting requests — these need the full agent pipeline
        // (Opus + UnifiedWritingEngine) which FlashLiteRouter cannot provide.
        // Long messages with writing keywords get misclassified by Gemini Flash Lite
        // (e.g. as create_content instead of agent), bypassing brainstorming and self-correction.
        let writingKeywords = [
            "let's write", "write a thread", "write a reel", "write about",
            "write this", "write for ", "draft", "let's draft",
            "generate an outline", "give me an outline", "write the draft",
            "generate hooks", "hook variants", "let's make this",
            "brainstorm", "let's think", "riff on",
            "using this as the swipe", "using the swipe", "using that as",
            "using the blueprint", "use the blueprint", "using this blueprint"
        ]
        if writingKeywords.contains(where: { lower.contains($0) }) {
            return true
        }

        guard let conversation = await ConversationMemoryService.shared.loadConversation(id: chatId) else {
            return false
        }
        guard !conversation.messages.isEmpty else { return false }

        // Check if recent assistant messages contain capture/creation results
        let recentAssistant = conversation.messages
            .filter { $0.role == .assistant }
            .suffix(3)

        let capturePatterns = ["captured", "saved idea", "saved research", "swipe",
                               "idea:", "task created", "content created"]
        let hasCaptureHistory = recentAssistant.contains { msg in
            let lower = msg.content.lowercased()
            return capturePatterns.contains(where: { lower.contains($0) })
        }

        guard hasCaptureHistory else { return false }

        // Check if current message contains follow-up reference signals
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

    // MARK: - Inline Capture Escape (During Writing Sessions)

    /// Detects inline capture patterns while in a writing session:
    /// !idea: [text], !task: [text], !swipe: [URL], or bare URL (< 120 chars).
    /// Returns a short confirmation string, or nil if no escape pattern matched.
    private func tryInlineCaptureEscape(text: String, chatId: String) async -> String? {
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
            if let captureResult = await tryFastCapture(text: content, chatId: chatId) {
                return captureResult
            }
            return nil
        }

        // Bare URL (< 120 chars, in writing mode — quick capture without breaking session)
        if trimmed.count < 120,
           trimmed.range(of: "^https?://[^\\s]+$", options: .regularExpression) != nil {
            if let captureResult = await tryFastCapture(text: trimmed, chatId: chatId) {
                return captureResult
            }
        }

        return nil
    }

    // MARK: - Fast-Path URL Capture

    /// Detects simple URL capture messages ("swipe this [URL]", "capture [URL]", bare URL)
    /// and executes captureSwipe directly, bypassing the LLM entirely.
    /// Supports multiple URLs in a single message.
    /// Returns nil if the message doesn't match the fast-path pattern — falls through to LLM.
    private func tryFastCapture(text: String, chatId: String) async -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract ALL URLs from the message
        let urlPattern = try! NSRegularExpression(pattern: "https?://[^\\s]+")
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = urlPattern.matches(in: text, range: nsRange)

        let extractedURLs: [(url: URL, string: String)] = matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let urlString = String(text[range])
            guard let url = URL(string: urlString) else { return nil }
            return (url, urlString)
        }

        guard !extractedURLs.isEmpty else { return nil }

        // Filter to supported swipe platforms
        let swipeDomains = ["instagram.com", "youtube.com", "youtu.be", "x.com",
                            "twitter.com", "threads.net", "tiktok.com"]
        let swipeURLs = extractedURLs.filter { pair in
            guard let host = pair.url.host?.lowercased() else { return false }
            return swipeDomains.contains(where: { host.contains($0) })
        }

        guard !swipeURLs.isEmpty else { return nil }

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
            let textWithoutURLs = swipeURLs.reduce(text) { result, pair in
                result.replacingOccurrences(of: pair.string, with: "")
            }.trimmingCharacters(in: .whitespacesAndNewlines)
            guard textWithoutURLs.isEmpty else { return nil }
            // Bare URL(s) — treat as capture
            await sendChatAction(chatId: chatId, action: "typing")
            return await executeFastCaptureBatch(urls: swipeURLs.map(\.string), chatId: chatId)
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
        return await executeFastCaptureBatch(urls: swipeURLs.map(\.string), chatId: chatId)
    }

    /// Execute capture_swipe for one or more URLs via the tool executor
    private func executeFastCaptureBatch(urls: [String], chatId: String) async -> String {
        await sendChatAction(chatId: chatId, action: "typing")

        var captured: [(source: String, uuid: String)] = []
        var failCount = 0

        for url in urls {
            do {
                let result = try await AgentToolExecutor.shared.execute(
                    toolName: "capture_swipe",
                    arguments: ["url": url]
                )
                if let data = result.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["success"] as? Bool == true {
                    let source = json["source"] as? String ?? "URL"
                    let uuid = json["uuid"] as? String ?? ""
                    captured.append((source: source, uuid: uuid))

                    // Track in conversation memory
                    if !uuid.isEmpty {
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
                        let responseText = "Captured swipe (\(source))"
                        conversation.append(.assistant(responseText))
                        await ConversationMemoryService.shared.saveConversation(conversation)
                    }
                } else {
                    failCount += 1
                }
            } catch {
                failCount += 1
            }

            // Refresh typing indicator between captures
            if urls.count > 1 {
                await sendChatAction(chatId: chatId, action: "typing")
            }
        }

        guard !captured.isEmpty else {
            return "Capture failed — couldn't process \(urls.count == 1 ? "the link" : "any of the links")."
        }

        // Platform display helper
        let platformName: (String) -> String = { source in
            source.contains("youtube") ? "YouTube" :
            source.contains("instagram") ? "Instagram" :
            source.contains("twitter") || source.contains("x.com") ? "X" :
            source.contains("threads") ? "Threads" :
            source.contains("tiktok") ? "TikTok" : source
        }

        if captured.count == 1 {
            let platform = platformName(captured[0].source)
            return "Got it — captured the \(platform) swipe to your database."
        } else {
            // Group by platform for a clean summary
            var platformCounts: [String: Int] = [:]
            for item in captured {
                platformCounts[platformName(item.source), default: 0] += 1
            }
            let breakdown = platformCounts
                .sorted(by: { $0.value > $1.value })
                .map { "\($0.value) \($0.key)" }
                .joined(separator: ", ")

            var msg = "Got it — captured \(captured.count) swipes to your database."
            msg += "\n📎 \(breakdown)"
            if failCount > 0 {
                msg += "\n⚠️ \(failCount) \(failCount == 1 ? "link" : "links") couldn't be processed."
            }
            return msg
        }
    }

    private func extractCapturedMedia(from message: [String: Any]) -> [TelegramCapturedMedia] {
        let caption = message["caption"] as? String

        if let photos = message["photo"] as? [[String: Any]],
           let largest = photos.max(by: { ($0["file_size"] as? Int ?? 0) < ($1["file_size"] as? Int ?? 0) }),
           let fileId = largest["file_id"] as? String {
            return [
                TelegramCapturedMedia(
                    kind: .image,
                    fileId: fileId,
                    fileUniqueId: largest["file_unique_id"] as? String,
                    filename: nil,
                    mimeType: "image/jpeg",
                    fileSize: (largest["file_size"] as? Int).map(Int64.init),
                    caption: caption
                )
            ]
        }

        if let document = message["document"] as? [String: Any],
           let fileId = document["file_id"] as? String {
            let filename = document["file_name"] as? String
            let mime = document["mime_type"] as? String
            return [
                TelegramCapturedMedia(
                    kind: mediaKind(filename: filename, mimeType: mime),
                    fileId: fileId,
                    fileUniqueId: document["file_unique_id"] as? String,
                    filename: filename,
                    mimeType: mime,
                    fileSize: (document["file_size"] as? Int).map(Int64.init),
                    caption: caption
                )
            ]
        }

        if let voice = message["voice"] as? [String: Any],
           let fileId = voice["file_id"] as? String {
            return [
                TelegramCapturedMedia(
                    kind: .audio,
                    fileId: fileId,
                    fileUniqueId: voice["file_unique_id"] as? String,
                    filename: "telegram-voice.ogg",
                    mimeType: voice["mime_type"] as? String ?? "audio/ogg",
                    fileSize: (voice["file_size"] as? Int).map(Int64.init),
                    caption: caption
                )
            ]
        }

        if let audio = message["audio"] as? [String: Any],
           let fileId = audio["file_id"] as? String {
            return [
                TelegramCapturedMedia(
                    kind: .audio,
                    fileId: fileId,
                    fileUniqueId: audio["file_unique_id"] as? String,
                    filename: audio["file_name"] as? String ?? "telegram-audio",
                    mimeType: audio["mime_type"] as? String,
                    fileSize: (audio["file_size"] as? Int).map(Int64.init),
                    caption: caption
                )
            ]
        }

        if let video = message["video"] as? [String: Any],
           let fileId = video["file_id"] as? String {
            return [
                TelegramCapturedMedia(
                    kind: .video,
                    fileId: fileId,
                    fileUniqueId: video["file_unique_id"] as? String,
                    filename: video["file_name"] as? String ?? "telegram-video.mp4",
                    mimeType: video["mime_type"] as? String ?? "video/mp4",
                    fileSize: (video["file_size"] as? Int).map(Int64.init),
                    caption: caption
                )
            ]
        }

        return []
    }

    private func mediaKind(filename: String?, mimeType: String?) -> MediaAttachmentKind {
        let lowerName = filename?.lowercased() ?? ""
        let lowerMime = mimeType?.lowercased() ?? ""
        if lowerMime == "application/pdf" || lowerName.hasSuffix(".pdf") { return .pdf }
        if lowerName.hasSuffix(".md") || lowerName.hasSuffix(".markdown") || lowerMime == "text/markdown" { return .markdown }
        if lowerMime.hasPrefix("text/") || lowerName.hasSuffix(".txt") { return .textFile }
        if lowerMime.hasPrefix("image/") { return .image }
        if lowerMime.hasPrefix("audio/") { return .audio }
        if lowerMime.hasPrefix("video/") { return .video }
        if lowerName.hasSuffix(".epub") { return .epub }
        return .document
    }

    private func scheduleMediaDownloads(capturedItemId: String) async {
        guard !capturedItemId.isEmpty else { return }
        let attachments = (try? await MediaAttachmentRepository.shared.fetch(capturedItemId: capturedItemId)) ?? []
        for attachment in attachments {
            Task { [weak self] in
                await self?.downloadAndStoreCapturedMedia(attachment)
            }
        }
    }

    private func downloadAndStoreCapturedMedia(_ attachment: MediaAttachment) async {
        guard let fileId = attachment.telegramFileId else { return }
        do {
            let filePath = try await getFilePath(fileId: fileId)
            let data = try await downloadFile(filePath: filePath)
            let stored = try CaptureMediaStorage.shared.store(
                data: data,
                capturedItemId: attachment.capturedItemId,
                attachmentId: attachment.uuid,
                originalFilename: attachment.originalFilename,
                mimeType: attachment.mimeType,
                telegramFilePath: filePath,
                kind: attachment.kind
            )
            let status: MediaProcessingStatus = stored.thumbnailPath == nil ? .downloaded : .thumbnailGenerated
            try await MediaAttachmentRepository.shared.updateDownload(
                uuid: attachment.uuid,
                localStoragePath: stored.originalPath,
                thumbnailPath: stored.thumbnailPath,
                status: status
            )

            if attachment.kind == .audio {
                let transcript = try await WhisperTranscriptionService.shared.transcribe(audioData: data, format: .ogg)
                try await MediaAttachmentRepository.shared.updateTranscript(
                    uuid: attachment.uuid,
                    transcript: transcript,
                    status: .transcribed
                )
            }
        } catch {
            print("[Telegram] Captured media download failed: \(error)")
            try? await MediaAttachmentRepository.shared.updateDownload(
                uuid: attachment.uuid,
                localStoragePath: nil,
                status: .failed
            )
        }
    }

    private func handleVoiceMessage(fileId: String, chatId: String) async {
        // Show typing indicator while processing voice
        await sendChatAction(chatId: chatId, action: "typing")

        // Durable row FIRST: the Telegram file_id is the only handle to the
        // audio, so it must survive download/transcription failures.
        let voiceMetadata = "{\"telegramVoiceFileId\":\"\(fileId)\"}"
        var capturedRowUuid: String?
        do {
            let row = try await CapturedItemRepository.shared.create(
                .makeTelegram(
                    rawText: nil,
                    caption: "Voice message (transcription pending)",
                    chatId: chatId,
                    messageId: nil,
                    metadata: voiceMetadata
                )
            )
            capturedRowUuid = row.uuid
        } catch {
            print("[Telegram] Voice captured_items create failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "TelegramBridgeService.handleVoiceMessage", detail: "captured item create failed: \(error.localizedDescription)")
        }

        do {
            // 1. Get file path from Telegram
            let filePath = try await getFilePath(fileId: fileId)

            // 2. Download the file
            let audioData = try await downloadFile(filePath: filePath)

            // 3. Transcribe via Whisper
            let text = try await WhisperTranscriptionService.shared.transcribe(audioData: audioData, format: .ogg)

            // Transcription succeeded — close out the durable row so it
            // doesn't linger in Needs review.
            if let capturedRowUuid {
                await markVoiceCaptureRow(uuid: capturedRowUuid, transcript: text, status: .routed)
            }

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

            // ── FlashLiteRouter for voice memos ──
            // Route transcribed voice through the same LLM router as text messages.
            // Handles: content ideas → pipeline, general thoughts → inbox, swipes, tasks, etc.
            // Questions and multi-turn requests fall through to the general agent.
            if !FlashLiteRouter.shouldForceAgentFallback(text) {
                if let (flashResponse, toolName) = await FlashLiteRouter.shared.tryRoute(text) {
                    await sendLongMessage(chatId: chatId, text: flashResponse)
                    // Save to conversation memory for follow-up context
                    await saveFlashRouterResult(text: text, response: flashResponse, toolName: toolName, chatId: chatId)
                    return
                }
            }

            // Fall through to the general agent for questions, commands, multi-turn
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
            if let capturedRowUuid {
                await markVoiceCaptureRow(uuid: capturedRowUuid, transcript: nil, status: .failed)
                await sendMessage(chatId: chatId, text: "⚠️ Couldn't process that voice message (\(error.localizedDescription)). It's saved in Cosmo's Needs review for retry.")
            } else {
                await sendMessage(chatId: chatId, text: "⚠️ Couldn't process or save that voice message — please resend it.")
            }
        }
    }

    /// Update the durable voice-capture row's lifecycle status. `.failed` rows
    /// surface in the inbox Needs-review section; `.routed` rows are done.
    private func markVoiceCaptureRow(uuid: String, transcript: String?, status: CapturedItemStatus) async {
        do {
            try await CapturedItemRepository.shared.updateRouting(
                uuid: uuid,
                destinationId: nil,
                parsedCommand: nil,
                parsedIntent: transcript != nil ? "voice_transcribed" : "voice_failed",
                confidence: transcript != nil ? 1.0 : 0,
                status: status
            )
        } catch {
            print("[Telegram] Voice capture row status update failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "TelegramBridgeService.markVoiceCaptureRow", detail: "\(uuid): \(error.localizedDescription)")
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
    /// If `chatId` is a composite "chatId:threadId" string, the thread ID is automatically
    /// extracted and included in the API call so replies land in the correct Forum Topic.
    @discardableResult
    func sendMessage(chatId: String, text: String, parseMode: String? = nil, replyMarkup: Any? = nil) async -> Bool {
        // Lazy-load token for proactive messages sent outside the polling loop
        if cachedToken == nil {
            cachedToken = loadTokenFromKeychain()
        }
        guard !baseURL.isEmpty else { return false }

        let url = URL(string: "\(baseURL)/sendMessage")!

        // Parse composite ID for Forum Topic support
        let (rawChatId, threadId) = TelegramBridgeService.parseChatThread(chatId)

        var body: [String: Any] = [
            "chat_id": rawChatId,
            "text": text
        ]

        // Include thread ID for Forum Topic replies
        if let threadId = threadId {
            body["message_thread_id"] = threadId
        }

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
                        try? await Task.sleep(for: .seconds(waitTime))
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

        print("[Telegram] sendMessage retries exhausted after \(maxSendRetries) attempts for chat \(rawChatId)")
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

    // MARK: - Automation Notifications

    /// Send an automation notification to the active Telegram chat.
    /// Used by AutomationActionExecutor when a rule fires with sendTelegram action.
    func sendAutomationNotification(_ message: String) async {
        guard let chatId = activeChatId else {
            print("⚡ [Telegram] No active chat ID — cannot send automation notification")
            return
        }
        await sendLongMessage(chatId: chatId, text: "⚡ \(message)")
    }

    // MARK: - Chat Actions

    /// Send a chat action (e.g. "typing") to show activity indicator in Telegram.
    /// Supports composite "chatId:threadId" format for Forum Topics.
    func sendChatAction(chatId: String, action: String = "typing") async {
        if cachedToken == nil {
            cachedToken = loadTokenFromKeychain()
        }
        guard !baseURL.isEmpty else { return }

        let url = URL(string: "\(baseURL)/sendChatAction")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (rawChatId, threadId) = TelegramBridgeService.parseChatThread(chatId)
        var body: [String: Any] = [
            "chat_id": rawChatId,
            "action": action
        ]
        if let threadId = threadId {
            body["message_thread_id"] = threadId
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let _ = try? await URLSession.shared.data(for: request)
    }

    /// Repeatedly send "typing" action every 4 seconds until cancelled.
    /// Telegram's typing indicator expires after ~5s, so this keeps it alive.
    private func keepTyping(chatId: String) async {
        await sendChatAction(chatId: chatId, action: "typing")
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
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

        let (rawChatId, _) = TelegramBridgeService.parseChatThread(chatId)
        var body: [String: Any] = [
            "chat_id": rawChatId,
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

        let (rawChatId, threadId) = TelegramBridgeService.parseChatThread(chatId)
        var body: [String: Any] = [
            "chat_id": rawChatId,
            "text": text
        ]
        if let threadId = threadId {
            body["message_thread_id"] = threadId
        }
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

        // Build composite ID for Forum Topic support
        let threadId = message["message_thread_id"] as? Int
        let chatIdStr: String
        if let threadId = threadId {
            chatIdStr = "\(chatId):\(threadId)"
        } else {
            chatIdStr = "\(chatId)"
        }

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
        // Handle lesson confirmation buttons (legacy — the taste engine
        // learns from edits directly; stale buttons answer gracefully)
        else if data.hasPrefix("lesson_yes:") {
            await sendMessage(chatId: chatIdStr, text: "Noted — taste now learns from your edits automatically, no confirmations needed.")
        } else if data.hasPrefix("lesson_no:") {
            await sendMessage(chatId: chatIdStr, text: "Discarded.")
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
            await sendMessage(chatId: chatIdStr, text: "Modules no longer hold rules — your taste profile does. It's already learning from your edits.")
        }
        // Handle module suggestion buttons
        else if data.hasPrefix("module_approve:") {
            let suggestionId = String(data.dropFirst("module_approve:".count))
            if let suggestion = pendingModuleSuggestions.removeValue(forKey: suggestionId) {
                if suggestion.action == "add_to_module", let moduleId = suggestion.moduleId {
                    // Approved suggestions land as pinned taste beliefs.
                    await TasteStore.addPinnedRule(suggestion.content, category: "voice", clientUuid: nil)
                    let moduleName = PromptTemplateStore.shared.modules.first(where: { $0.id == moduleId })?.title ?? moduleId
                    await sendMessage(chatId: chatIdStr, text: "Saved to your taste profile (was: \(moduleName)).")
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
