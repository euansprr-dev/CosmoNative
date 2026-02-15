// CosmoOS/Config/APIKeys.swift
// Centralized API key management
// Keys are stored securely in macOS Keychain with in-memory caching

import Foundation
import Security

struct APIKeys {
    // MARK: - Keychain Service Name
    private static let keychainService = "com.cosmo.apikeys"

    // MARK: - Key Identifiers
    private enum KeyIdentifier: String, CaseIterable {
        case openRouter = "openrouter_api_key"
        case youtube = "youtube_api_key"
        case perplexity = "perplexity_api_key"
        case supabaseUrl = "supabase_url"
        case supabaseKey = "supabase_anon_key"
        case instagram = "instagram_api_key"
        case tiktok = "tiktok_api_key"
        case xTwitter = "x_twitter_api_key"
        case youtubeChannelId = "youtube_channel_id"
        case agentLLM = "agent_llm_api_key"
        case agentLLMBaseURL = "agent_llm_base_url"
        case telegramBotToken = "telegram_bot_token"
        case whisperAPIKey = "whisper_api_key"
    }

    // MARK: - In-Memory Cache

    /// Cache populated once at first access, invalidated on save/delete
    nonisolated(unsafe) private static var cache: [KeyIdentifier: String] = [:]
    nonisolated(unsafe) private static var cacheLoaded = false

    /// Load all keys from Keychain into memory (called once)
    private static func ensureCacheLoaded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        for identifier in KeyIdentifier.allCases {
            if let value = readFromKeychain(identifier) {
                cache[identifier] = value
            }
        }
    }

    /// Get a cached value, falling back to environment variable
    private static func cachedValue(_ identifier: KeyIdentifier, envKey: String? = nil) -> String? {
        ensureCacheLoaded()
        if let value = cache[identifier] {
            return value
        }
        if let envKey = envKey {
            return ProcessInfo.processInfo.environment[envKey]
        }
        return nil
    }

    // MARK: - API Key Properties (read from cache, not Keychain)

    static var openRouter: String? {
        cachedValue(.openRouter, envKey: "OPENROUTER_API_KEY")
    }

    static var youtube: String? {
        cachedValue(.youtube, envKey: "YOUTUBE_API_KEY")
    }

    static var perplexity: String? {
        cachedValue(.perplexity, envKey: "PERPLEXITY_API_KEY")
    }

    static var instagram: String? {
        cachedValue(.instagram, envKey: "INSTAGRAM_API_KEY")
    }

    static var tiktok: String? {
        cachedValue(.tiktok, envKey: "TIKTOK_API_KEY")
    }

    static var xTwitter: String? {
        cachedValue(.xTwitter, envKey: "X_TWITTER_API_KEY")
    }

    static var youtubeChannelId: String? {
        cachedValue(.youtubeChannelId, envKey: "YOUTUBE_CHANNEL_ID")
    }

    static var agentLLM: String? {
        cachedValue(.agentLLM, envKey: "AGENT_LLM_API_KEY")
    }

    static var agentLLMBaseURL: String? {
        cachedValue(.agentLLMBaseURL, envKey: "AGENT_LLM_BASE_URL")
    }

    static var telegramBotToken: String? {
        cachedValue(.telegramBotToken, envKey: "TELEGRAM_BOT_TOKEN")
    }

    static var whisperAPIKey: String? {
        cachedValue(.whisperAPIKey, envKey: "WHISPER_API_KEY")
    }

    // MARK: - Supabase (hardcoded)

    static var supabaseUrl: String? {
        return "https://zjgymvqgrtreeanwkrzp.supabase.co"
    }

    static var supabaseAnonKey: String? {
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpqZ3ltdnFncnRyZWVhbndrcnpwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ3MTI3ODksImV4cCI6MjA4MDI4ODc4OX0.nkoIiaBC8WDK9sE3Shvip4mKcTK7EwW0ZbR8IHO4w48"
    }

    // MARK: - Validation (reads from cache, no Keychain hits)

    static var hasOpenRouter: Bool { openRouter != nil && !openRouter!.isEmpty }
    static var hasYouTube: Bool { youtube != nil && !youtube!.isEmpty }
    static var hasPerplexity: Bool { perplexity != nil && !perplexity!.isEmpty }
    static var hasInstagram: Bool { instagram != nil && !instagram!.isEmpty }
    static var hasTikTok: Bool { tiktok != nil && !tiktok!.isEmpty }
    static var hasXTwitter: Bool { xTwitter != nil && !xTwitter!.isEmpty }
    static var hasYouTubeChannelId: Bool { youtubeChannelId != nil && !youtubeChannelId!.isEmpty }
    static var hasAgentLLM: Bool { agentLLM != nil && !agentLLM!.isEmpty }
    static var hasTelegramBot: Bool { telegramBotToken != nil && !telegramBotToken!.isEmpty }
    static var hasWhisper: Bool { whisperAPIKey != nil && !whisperAPIKey!.isEmpty }

    static var hasSupabase: Bool {
        supabaseUrl != nil && !supabaseUrl!.isEmpty && supabaseAnonKey != nil && !supabaseAnonKey!.isEmpty
    }

    /// Print status of API key configuration
    static func logStatus() {
        print("API Key Status:")
        print("   OpenRouter: \(hasOpenRouter ? "Configured" : "Not set (configure in Settings)")")
        print("   YouTube: \(hasYouTube ? "Configured" : "Optional (configure in Settings)")")
        print("   Perplexity: \(hasPerplexity ? "Configured" : "Optional (configure in Settings)")")
        print("   Instagram: \(hasInstagram ? "Configured" : "Optional (for Creative dimension tracking)")")
        print("   TikTok: \(hasTikTok ? "Configured" : "Optional (for Creative dimension tracking)")")
        print("   X/Twitter: \(hasXTwitter ? "Configured" : "Optional (for Creative dimension tracking)")")
        print("   YT Channel ID: \(hasYouTubeChannelId ? "Configured" : "Optional (for YouTube analytics)")")
        print("   Agent LLM: \(hasAgentLLM ? "Configured" : "Optional (for Cosmo Agent)")")
        print("   Telegram: \(hasTelegramBot ? "Configured" : "Optional (for Telegram bot)")")
        print("   Whisper: \(hasWhisper ? "Configured" : "Optional (for voice transcription)")")
        print("   Supabase: \(hasSupabase ? "Configured" : "Not set (Sync Disabled)")")
    }

    // MARK: - Save & Delete (update Keychain + cache)

    /// Save an API key to Keychain and update the in-memory cache
    static func save(_ key: String, identifier: String) {
        guard let keyIdentifier = resolveIdentifier(identifier) else {
            print("Unknown identifier for API key: \(identifier)")
            return
        }
        writeToKeychain(key, identifier: keyIdentifier)
        cache[keyIdentifier] = key
    }

    /// Delete an API key from Keychain and remove from cache
    static func delete(identifier: String) {
        guard let keyIdentifier = resolveIdentifier(identifier) else { return }
        removeFromKeychain(identifier: keyIdentifier)
        cache.removeValue(forKey: keyIdentifier)
    }

    private static func resolveIdentifier(_ identifier: String) -> KeyIdentifier? {
        switch identifier {
        case "openrouter": return .openRouter
        case "youtube": return .youtube
        case "perplexity": return .perplexity
        case "instagram": return .instagram
        case "tiktok": return .tiktok
        case "x_twitter": return .xTwitter
        case "youtube_channel_id": return .youtubeChannelId
        case "agent_llm": return .agentLLM
        case "agent_llm_base_url": return .agentLLMBaseURL
        case "telegram_bot_token": return .telegramBotToken
        case "whisper_api_key": return .whisperAPIKey
        case "supabase_url": return .supabaseUrl
        case "supabase_anon_key": return .supabaseKey
        default: return nil
        }
    }

    // MARK: - Private Keychain Helpers

    private static func writeToKeychain(_ value: String, identifier: KeyIdentifier) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier.rawValue,
            kSecValueData as String: data
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            print("API key saved to Keychain: \(identifier.rawValue)")
        } else {
            print("Failed to save API key to Keychain: \(status)")
        }
    }

    private static func readFromKeychain(_ identifier: KeyIdentifier) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    private static func removeFromKeychain(identifier: KeyIdentifier) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier.rawValue
        ]

        SecItemDelete(query as CFDictionary)
    }
}
