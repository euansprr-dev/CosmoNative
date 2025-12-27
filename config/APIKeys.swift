// CosmoOS/Config/APIKeys.swift
// Centralized API key management
// Keys are stored securely in macOS Keychain

import Foundation
import Security

struct APIKeys {
    // MARK: - Keychain Service Name
    private static let keychainService = "com.cosmo.apikeys"

    // MARK: - Key Identifiers
    private enum KeyIdentifier: String {
        case openRouter = "openrouter_api_key"
        case youtube = "youtube_api_key"
        case perplexity = "perplexity_api_key"
        case supabaseUrl = "supabase_url"
        case supabaseKey = "supabase_anon_key"
        case instagram = "instagram_api_key"
    }

    // MARK: - OpenRouter (for LLM calls)
    /// Get or set OpenRouter API key (stored in Keychain)
    static var openRouter: String? {
        get {
            // First try keychain
            if let key = loadFromKeychain(.openRouter) {
                return key
            }
            // Fallback to environment variable (for backward compatibility)
            return ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        }
    }

    // MARK: - YouTube Data API (optional, for extended metadata)
    /// Get or set YouTube API key (stored in Keychain)
    static var youtube: String? {
        get {
            if let key = loadFromKeychain(.youtube) {
                return key
            }
            return ProcessInfo.processInfo.environment["YOUTUBE_API_KEY"]
        }
    }

    // MARK: - Perplexity (for research)
    /// Get or set Perplexity API key (stored in Keychain)
    static var perplexity: String? {
        get {
            if let key = loadFromKeychain(.perplexity) {
                return key
            }
            return ProcessInfo.processInfo.environment["PERPLEXITY_API_KEY"]
        }
    }

    // MARK: - Instagram (for content performance tracking)
    /// Get or set Instagram API key (stored in Keychain)
    /// Used for tracking post performance in the Creative dimension
    static var instagram: String? {
        get {
            if let key = loadFromKeychain(.instagram) {
                return key
            }
            return ProcessInfo.processInfo.environment["INSTAGRAM_API_KEY"]
        }
    }

    // MARK: - Supabase (for Sync)
    // Hardcoded for production - all users connect to the same Supabase instance
    static var supabaseUrl: String? {
        // Supabase REST API URL (not PostgreSQL connection string)
        return "https://zjgymvqgrtreeanwkrzp.supabase.co"
    }

    static var supabaseAnonKey: String? {
        // TODO: Replace with your actual Supabase anon/public key
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpqZ3ltdnFncnRyZWVhbndrcnpwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ3MTI3ODksImV4cCI6MjA4MDI4ODc4OX0.nkoIiaBC8WDK9sE3Shvip4mKcTK7EwW0ZbR8IHO4w48"
    }


    // MARK: - Validation
    static var hasOpenRouter: Bool {
        openRouter != nil && !openRouter!.isEmpty
    }

    static var hasYouTube: Bool {
        youtube != nil && !youtube!.isEmpty
    }

    static var hasPerplexity: Bool {
        perplexity != nil && !perplexity!.isEmpty
    }

    static var hasInstagram: Bool {
        instagram != nil && !instagram!.isEmpty
    }

    static var hasSupabase: Bool {
        supabaseUrl != nil && !supabaseUrl!.isEmpty && supabaseAnonKey != nil && !supabaseAnonKey!.isEmpty
    }

    /// Print status of API key configuration
    static func logStatus() {
        print("🔑 API Key Status:")
        print("   OpenRouter: \(hasOpenRouter ? "✅ Configured" : "❌ Not set (configure in Settings)")")
        print("   YouTube: \(hasYouTube ? "✅ Configured" : "⚪ Optional (configure in Settings)")")
        print("   Perplexity: \(hasPerplexity ? "✅ Configured" : "⚪ Optional (configure in Settings)")")
        print("   Instagram: \(hasInstagram ? "✅ Configured" : "⚪ Optional (for Creative dimension tracking)")")
        print("   Supabase: \(hasSupabase ? "✅ Configured" : "❌ Not set (Sync Disabled)")")
    }

    // MARK: - Keychain Operations

    /// Save an API key to the Keychain
    static func save(_ key: String, identifier: String) {
        let keyIdentifier: KeyIdentifier

        switch identifier {
        case "openrouter":
            keyIdentifier = .openRouter
        case "youtube":
            keyIdentifier = .youtube
        case "perplexity":
            keyIdentifier = .perplexity
        case "instagram":
            keyIdentifier = .instagram
        case "supabase_url":
            keyIdentifier = .supabaseUrl
        case "supabase_anon_key":
            keyIdentifier = .supabaseKey
        default:
            print("❌ Unknown identifier for API key: \(identifier)")
            return
        }

        saveToKeychain(key, identifier: keyIdentifier)
    }

    /// Delete an API key from the Keychain
    static func delete(identifier: String) {
        let keyIdentifier: KeyIdentifier

        switch identifier {
        case "openrouter":
            keyIdentifier = .openRouter
        case "youtube":
            keyIdentifier = .youtube
        case "perplexity":
            keyIdentifier = .perplexity
        case "instagram":
            keyIdentifier = .instagram
        case "supabase_url":
            keyIdentifier = .supabaseUrl
        case "supabase_anon_key":
            keyIdentifier = .supabaseKey
        default:
            return
        }

        deleteFromKeychain(identifier: keyIdentifier)
    }

    // MARK: - Private Keychain Helpers

    private static func saveToKeychain(_ value: String, identifier: KeyIdentifier) {
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
            print("✅ API key saved to Keychain: \(identifier.rawValue)")
        } else {
            print("❌ Failed to save API key to Keychain: \(status)")
        }
    }

    private static func loadFromKeychain(_ identifier: KeyIdentifier) -> String? {
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

    private static func deleteFromKeychain(identifier: KeyIdentifier) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier.rawValue
        ]

        SecItemDelete(query as CFDictionary)
    }
}
