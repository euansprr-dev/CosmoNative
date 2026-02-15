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

    private var botToken: String? { APIKeys.telegramBotToken }
    private var baseURL: String {
        guard let token = botToken else { return "" }
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
        guard botToken != nil else {
            lastError = "No bot token configured"
            return
        }

        stop() // Cancel any existing polling

        isConnected = true
        lastError = nil
        backoffInterval = 1.0

        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }

        print("[Telegram] Bridge started")
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isConnected = false
        print("[Telegram] Bridge stopped")
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
        var components = URLComponents(string: "\(baseURL)/getUpdates")!
        components.queryItems = [
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "timeout", value: "\(timeout)"),
            URLQueryItem(name: "allowed_updates", value: "[\"message\",\"callback_query\"]")
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = TimeInterval(timeout + 10) // Buffer beyond long-poll timeout

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool, ok,
              let result = json["result"] as? [[String: Any]] else {
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
