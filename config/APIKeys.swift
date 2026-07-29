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
        case whisperAPIKey = "whisper_api_key"
        case embeddings = "embeddings_api_key"
        case apify = "apify_api_key"
        case supabaseServiceRole = "supabase_service_role_key"
        case supabaseAuthToken = "supabase_auth_token"
        case supabaseUserId = "supabase_user_id"
        case discoveryApiBaseURL = "discovery_api_base_url"
        case discoveryApiKey = "discovery_api_key"
        // APNs (Mac → iPhone camera relay): the Mac signs its own push JWTs.
        case apnsTeamId = "apns_team_id"
        case apnsKeyId = "apns_key_id"
        case apnsPrivateKey = "apns_private_key_p8"
        case apnsBundleId = "apns_bundle_id"
        // Google Drive (OAuth 2.0 + PKCE, installed-app flow). The client ID
        // is public by design; the refresh token is the real secret and is the
        // only thing that survives a quit.
        case googleDriveClientId = "google_drive_client_id"
        case googleDriveRefreshToken = "google_drive_refresh_token"
        case googleDriveAccessToken = "google_drive_access_token"
        case googleDriveTokenExpiry = "google_drive_token_expiry"
        case googleDriveAccount = "google_drive_account_email"
        case googleDriveScope = "google_drive_granted_scope"
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

    static var whisperAPIKey: String? {
        cachedValue(.whisperAPIKey, envKey: "WHISPER_API_KEY")
    }

    static var apify: String? {
        cachedValue(.apify, envKey: "APIFY_API_KEY")
    }

    /// Embeddings API key (Recall semantic index). OpenAI wire format —
    /// OpenAI, Voyage, Mistral, and Together keys all work with the matching
    /// base URL in Settings.
    static var embeddings: String? {
        cachedValue(.embeddings, envKey: "EMBEDDINGS_API_KEY")
    }

    // MARK: - Supabase (Keychain-backed)

    /// Service role key for server-side operations (used by cloud agent, stored for reference)
    static var supabaseServiceRoleKey: String? {
        cachedValue(.supabaseServiceRole, envKey: "SUPABASE_SERVICE_ROLE_KEY")
    }

    /// Auth token from Supabase Auth (Sign in with Apple JWT)
    static var supabaseAuthToken: String? {
        cachedValue(.supabaseAuthToken)
    }

    /// Supabase user UUID from auth session
    static var supabaseUserId: String? {
        cachedValue(.supabaseUserId)
    }

    /// Save auth session credentials after Sign in with Apple
    static func saveSupabaseAuth(token: String, userId: String) {
        save(token, identifier: "supabase_auth_token")
        save(userId, identifier: "supabase_user_id")
    }

    /// Clear auth session on sign out
    static func clearSupabaseAuth() {
        delete(identifier: "supabase_auth_token")
        delete(identifier: "supabase_user_id")
    }

    static var hasSupabaseAuth: Bool {
        supabaseAuthToken?.isEmpty == false && supabaseUserId?.isEmpty == false
    }

    static var supabaseUrl: String? {
        cachedValue(.supabaseUrl, envKey: "SUPABASE_URL")
    }

    static var supabaseAnonKey: String? {
        cachedValue(.supabaseKey, envKey: "SUPABASE_ANON_KEY")
    }

    static var discoveryApiBaseURL: String? {
        cachedValue(.discoveryApiBaseURL, envKey: "DISCOVERY_API_BASE_URL")
    }

    // MARK: - APNs (Mac → iPhone camera relay)

    static var apnsTeamId: String? { cachedValue(.apnsTeamId) }
    static var apnsKeyId: String? { cachedValue(.apnsKeyId) }
    static var apnsPrivateKey: String? { cachedValue(.apnsPrivateKey) }
    static var apnsBundleId: String? { cachedValue(.apnsBundleId) }
    static var hasAPNs: Bool {
        apnsTeamId?.isEmpty == false && apnsKeyId?.isEmpty == false && apnsPrivateKey?.isEmpty == false
    }

    static var discoveryApiKey: String? {
        cachedValue(.discoveryApiKey, envKey: "DISCOVERY_API_KEY")
    }

    // MARK: - Google Drive (OAuth)

    /// Public OAuth client identifier — safe to ship, safe to log.
    static var googleDriveClientID: String? {
        cachedValue(.googleDriveClientId, envKey: "GOOGLE_DRIVE_CLIENT_ID")
    }

    static var googleDriveRefreshToken: String? { cachedValue(.googleDriveRefreshToken) }
    static var googleDriveAccessToken: String? { cachedValue(.googleDriveAccessToken) }
    static var googleDriveTokenExpiry: String? { cachedValue(.googleDriveTokenExpiry) }
    static var googleDriveAccount: String? { cachedValue(.googleDriveAccount) }
    static var googleDriveScope: String? { cachedValue(.googleDriveScope) }

    /// A connection exists only if the durable half of it does. An access
    /// token alone is a leftover, not a session.
    static var hasGoogleDrive: Bool { googleDriveRefreshToken?.isEmpty == false }

    /// Persist a freshly minted or refreshed session.
    static func saveGoogleDriveSession(
        refreshToken: String,
        accessToken: String,
        expiresAt: Date,
        scope: String,
        accountEmail: String?
    ) {
        save(refreshToken, identifier: "google_drive_refresh_token")
        save(accessToken, identifier: "google_drive_access_token")
        save(String(expiresAt.timeIntervalSince1970), identifier: "google_drive_token_expiry")
        save(scope, identifier: "google_drive_granted_scope")
        if let accountEmail, !accountEmail.isEmpty {
            save(accountEmail, identifier: "google_drive_account_email")
        }
    }

    /// Tear down the session. Deliberately leaves the client ID in place —
    /// disconnecting an account should not un-configure the app.
    static func clearGoogleDriveSession() {
        delete(identifier: "google_drive_refresh_token")
        delete(identifier: "google_drive_access_token")
        delete(identifier: "google_drive_token_expiry")
        delete(identifier: "google_drive_granted_scope")
        delete(identifier: "google_drive_account_email")
    }

    // MARK: - Supabase Project Configuration
    // Project: https://cskxozkzpzxyefqmgsgg.supabase.co
    // Publishable (anon) key for client-side auth + REST
    // Secret (service role) key for cloud agent only — NEVER ship in client

    private static let supabaseProjectUrl = "https://cskxozkzpzxyefqmgsgg.supabase.co"
    private static let supabasePublishableKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNza3hvemt6cHp4eWVmcW1nc2dnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQwNjU4MzMsImV4cCI6MjA4OTY0MTgzM30.-79YrwJjjY8nus9Ej9tiyCG8Rsrrqxb0QP3lb-t9ivE"

    /// One-time migration: seed Supabase credentials into Keychain.
    /// Also migrates from the old project URL if present.
    static func seedSupabaseIfNeeded() {
        let existingUrl = readFromKeychain(.supabaseUrl)

        // Always update to the current project URL + key
        // (handles migration from old project to new project)
        let needsUpdate = existingUrl != supabaseProjectUrl

        if existingUrl == nil || needsUpdate {
            writeToKeychain(supabaseProjectUrl, identifier: .supabaseUrl)
            cacheLock.lock()
            _cache[.supabaseUrl] = supabaseProjectUrl
            cacheLock.unlock()
        }

        let existingKey = readFromKeychain(.supabaseKey)
        if existingKey == nil || needsUpdate {
            writeToKeychain(supabasePublishableKey, identifier: .supabaseKey)
            cacheLock.lock()
            _cache[.supabaseKey] = supabasePublishableKey
            cacheLock.unlock()
        }

        // Clear stale auth if project changed (tokens from old project won't work)
        if needsUpdate && existingUrl != nil {
            clearSupabaseAuth()
            print("🔄 Supabase project migrated — cleared stale auth tokens")
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
    static var hasDiscoveryAPI: Bool {
        discoveryApiBaseURL?.isEmpty == false && discoveryApiKey?.isEmpty == false
    }
    static var hasWhisper: Bool { whisperAPIKey?.isEmpty == false }
    static var hasApify: Bool { apify?.isEmpty == false }
    static var hasEmbeddings: Bool { embeddings?.isEmpty == false }

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
        print("   Whisper: \(hasWhisper ? "Configured" : "Optional (for voice transcription)")")
        print("   Apify: \(hasApify ? "Configured" : "Optional (for creator import)")")
        print("   Supabase: \(hasSupabase ? "Configured" : "Not set (Sync Disabled)")")
        print("   Discovery API: \(hasDiscoveryAPI ? "Configured" : "Optional (for Swipe File Discover)")")
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
        case "whisper_api_key": return .whisperAPIKey
        case "apify": return .apify
        case "embeddings": return .embeddings
        case "supabase_url": return .supabaseUrl
        case "supabase_anon_key": return .supabaseKey
        case "supabase_service_role_key": return .supabaseServiceRole
        case "supabase_auth_token": return .supabaseAuthToken
        case "supabase_user_id": return .supabaseUserId
        case "discovery_api_base_url": return .discoveryApiBaseURL
        case "discovery_api_key": return .discoveryApiKey
        case "apns_team_id": return .apnsTeamId
        case "apns_key_id": return .apnsKeyId
        case "apns_private_key_p8": return .apnsPrivateKey
        case "apns_bundle_id": return .apnsBundleId
        case "google_drive_client_id": return .googleDriveClientId
        case "google_drive_refresh_token": return .googleDriveRefreshToken
        case "google_drive_access_token": return .googleDriveAccessToken
        case "google_drive_token_expiry": return .googleDriveTokenExpiry
        case "google_drive_account_email": return .googleDriveAccount
        case "google_drive_granted_scope": return .googleDriveScope
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
