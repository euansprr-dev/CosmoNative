// CosmoOS/Agent/Bridges/TelegramBridgeService.swift
// Telegram Bot API bridge using long polling

import Foundation
import Combine

// MARK: - Telegram Errors

enum TelegramError: Error, LocalizedError {
    case noBotToken
    case invalidResponse
    case fileNotFound
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .noBotToken: return "No Telegram bot token configured"
        case .invalidResponse: return "Invalid response from Telegram API"
        case .fileNotFound: return "Telegram file not found"
        case .sendFailed(let msg): return "Failed to send message: \(msg)"
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

        // Check for voice message
        if let voice = message["voice"] as? [String: Any],
           let fileId = voice["file_id"] as? String {
            await handleVoiceMessage(fileId: fileId, chatId: chatIdStr)
            return
        }

        // Check for audio message
        if let audio = message["audio"] as? [String: Any],
           let fileId = audio["file_id"] as? String {
            await handleVoiceMessage(fileId: fileId, chatId: chatIdStr)
            return
        }

        // Handle text message
        guard let text = message["text"] as? String else { return }

        // Handle /start command
        if text == "/start" {
            let welcome = """
            Hey! I'm Cosmo, your AI creative partner.

            I have full access to your CosmoOS knowledge graph. Ask me about your ideas, swipes, content pipeline, schedule, or just brainstorm.

            Try: "What ideas do I have?" or "Schedule a writing block for tomorrow at 10am"
            """
            await sendMessage(chatId: chatIdStr, text: welcome)
            return
        }

        // Process through agent
        let response = await CosmoAgentService.shared.processMessage(text, conversationId: chatIdStr, source: .telegram)
        await sendMessage(chatId: chatIdStr, text: response)
    }

    private func handleVoiceMessage(fileId: String, chatId: String) async {
        do {
            // 1. Get file path from Telegram
            let filePath = try await getFilePath(fileId: fileId)

            // 2. Download the file
            let audioData = try await downloadFile(filePath: filePath)

            // 3. Transcribe via Whisper
            let text = try await WhisperTranscriptionService.shared.transcribe(audioData: audioData, format: .ogg)

            // 4. Send transcription preview
            await sendMessage(chatId: chatId, text: "*Heard:* \(text)", parseMode: "Markdown")

            // 5. Process through agent
            let response = await CosmoAgentService.shared.processMessage(text, conversationId: chatId, source: .telegram)
            await sendMessage(chatId: chatId, text: response)

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

    func sendMessage(chatId: String, text: String, parseMode: String? = nil, replyMarkup: Any? = nil) async {
        // Lazy-load token for proactive messages sent outside the polling loop
        if cachedToken == nil {
            cachedToken = loadTokenFromKeychain()
        }
        guard !baseURL.isEmpty else { return }

        let url = URL(string: "\(baseURL)/sendMessage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

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

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let _ = try await URLSession.shared.data(for: request)
        } catch {
            print("[Telegram] Failed to send message: \(error)")
        }
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
            await sendMessage(chatId: chatIdStr, text: result)
        } else if data.hasPrefix("cancel:") {
            await sendMessage(chatId: chatIdStr, text: "Action cancelled.")
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
}
