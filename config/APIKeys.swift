// CosmoOS/Config/APIKeys.swift
// Centralized API key management
// Keys are stored securely in macOS Keychain with in-memory caching

import Foundation
import Security
import os

struct APIKeys {
    // MARK: - Keychain Service Name
    private static let keychainService = "com.cosmo.apikeys"
    nonisolated(unsafe) private static var _migrationDone = false

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
        case apify = "apify_api_key"
    }

    // MARK: - In-Memory Cache (thread-safe via lock)

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var _cache: [KeyIdentifier: String] = [:]
    nonisolated(unsafe) private static var _cacheLoaded = false

    /// Load all keys from Keychain into memory (called once, under lock)
    private static func ensureCacheLoaded() {
        guard !_cacheLoaded else { return }
        _cacheLoaded = true

        // Migrate legacy keychain items to Data Protection Keychain (one-time)
        if !_migrationDone {
            _migrationDone = true
            for identifier in KeyIdentifier.allCases {
                if readFromKeychain(identifier) == nil,
                   let legacyValue = readFromLegacyKeychain(identifier) {
                    // Re-save to Data Protection Keychain (also deletes legacy entry)
                    writeToKeychain(legacyValue, identifier: identifier)
                    print("Migrated \(identifier.rawValue) to Data Protection Keychain")
                }
            }
        }

        for identifier in KeyIdentifier.allCases {
            if let value = readFromKeychain(identifier) {
                _cache[identifier] = value
            }
        }
    }

    /// Get a cached value, falling back to environment variable
    private static func cachedValue(_ identifier: KeyIdentifier, envKey: String? = nil) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        ensureCacheLoaded()
        if let value = _cache[identifier] {
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

    static var apify: String? {
        cachedValue(.apify, envKey: "APIFY_API_KEY")
    }

    // MARK: - Supabase (Keychain-backed)

    static var supabaseUrl: String? {
        cachedValue(.supabaseUrl, envKey: "SUPABASE_URL")
    }

    static var supabaseAnonKey: String? {
        cachedValue(.supabaseKey, envKey: "SUPABASE_ANON_KEY")
    }

    /// One-time migration: seed Supabase credentials into Keychain if not already present.
    /// Call once at app startup to ensure existing installs retain connectivity.
    static func seedSupabaseIfNeeded() {
        let existingUrl = readFromKeychain(.supabaseUrl)
        let existingKey = readFromKeychain(.supabaseKey)

        if existingUrl == nil {
            writeToKeychain("https://zjgymvqgrtreeanwkrzp.supabase.co", identifier: .supabaseUrl)
            cacheLock.lock()
            _cache[.supabaseUrl] = "https://zjgymvqgrtreeanwkrzp.supabase.co"
            cacheLock.unlock()
        }

        if existingKey == nil {
            let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpqZ3ltdnFncnRyZWVhbndrcnpwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ3MTI3ODksImV4cCI6MjA4MDI4ODc4OX0.nkoIiaBC8WDK9sE3Shvip4mKcTK7EwW0ZbR8IHO4w48"
            writeToKeychain(anonKey, identifier: .supabaseKey)
            cacheLock.lock()
            _cache[.supabaseKey] = anonKey
            cacheLock.unlock()
        }
    }

    // MARK: - Validation (reads from cache, no Keychain hits)

    static var hasOpenRouter: Bool { openRouter?.isEmpty == false }
    static var hasYouTube: Bool { youtube?.isEmpty == false }
    static var hasPerplexity: Bool { perplexity?.isEmpty == false }
    static var hasInstagram: Bool { instagram?.isEmpty == false }
    static var hasTikTok: Bool { tiktok?.isEmpty == false }
    static var hasXTwitter: Bool { xTwitter?.isEmpty == false }
    static var hasYouTubeChannelId: Bool { youtubeChannelId?.isEmpty == false }
    static var hasAgentLLM: Bool { agentLLM?.isEmpty == false }
    static var hasTelegramBot: Bool { telegramBotToken?.isEmpty == false }
    static var hasWhisper: Bool { whisperAPIKey?.isEmpty == false }
    static var hasApify: Bool { apify?.isEmpty == false }

    static var hasSupabase: Bool {
        supabaseUrl?.isEmpty == false && supabaseAnonKey?.isEmpty == false
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
        print("   Apify: \(hasApify ? "Configured" : "Optional (for creator import)")")
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
        cacheLock.lock()
        _cache[keyIdentifier] = key
        cacheLock.unlock()
    }

    /// Delete an API key from Keychain and remove from cache
    static func delete(identifier: String) {
        guard let keyIdentifier = resolveIdentifier(identifier) else { return }
        removeFromKeychain(identifier: keyIdentifier)
        cacheLock.lock()
        _cache.removeValue(forKey: keyIdentifier)
        cacheLock.unlock()
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
        case "apify": return .apify
        case "supabase_url": return .supabaseUrl
        case "supabase_anon_key": return .supabaseKey
        default: return nil
        }
    }

    // MARK: - Private Keychain Helpers

    private static func writeToKeychain(_ value: String, identifier: KeyIdentifier) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item (both legacy and data protection)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier.rawValue,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Also clean up legacy keychain entry if present
        let legacyDeleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier.rawValue
        ]
        SecItemDelete(legacyDeleteQuery as CFDictionary)

        // Add new item to Data Protection Keychain (no per-app ACL prompts)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier.rawValue,
            kSecValueData as String: data,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            print("API key saved to Keychain: \(identifier.rawValue)")
        } else {
            print("Failed to save API key to Keychain: \(status)")
        }
    }

    private static func readFromKeychain(_ identifier: KeyIdentifier) -> String? {
        // Try Data Protection Keychain first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }

        return nil
    }

    /// Read from legacy keychain (without Data Protection) for migration
    private static func readFromLegacyKeychain(_ identifier: KeyIdentifier) -> String? {
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
        // Delete from Data Protection Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier.rawValue,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)

        // Also delete from legacy keychain if present
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier.rawValue
        ]
        SecItemDelete(legacyQuery as CFDictionary)
    }
}
