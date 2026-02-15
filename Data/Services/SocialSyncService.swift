// CosmoOS/Data/Services/SocialSyncService.swift
// Social platform sync architecture
// OAuth flows will be implemented when API credentials are available

import SwiftUI

// MARK: - Social Platform

enum SocialSyncPlatform: String, CaseIterable, Codable, Sendable {
    case instagram
    case youtube
    case tiktok
    case x

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .youtube: return "YouTube"
        case .tiktok: return "TikTok"
        case .x: return "X"
        }
    }

    var icon: String {
        switch self {
        case .instagram: return "camera.fill"
        case .youtube: return "play.rectangle.fill"
        case .tiktok: return "music.note"
        case .x: return "at"
        }
    }

    var accentColor: Color {
        switch self {
        case .instagram: return Color(red: 0.88, green: 0.19, blue: 0.42)  // #E1306C
        case .youtube: return Color.red
        case .tiktok: return Color(red: 0, green: 0.95, blue: 0.92)        // #00F2EA
        case .x: return Color(red: 0.11, green: 0.63, blue: 0.95)          // #1DA1F2
        }
    }
}

// MARK: - Social Connection

struct SocialConnection: Codable, Sendable {
    let platform: SocialSyncPlatform
    let accountId: String
    let accountHandle: String
    var accessToken: String
    var refreshToken: String
    let connectedAt: Date
    var lastSyncAt: Date
}

// MARK: - Social Sync Service

@MainActor
class SocialSyncService: ObservableObject {
    static let shared = SocialSyncService()

    @Published var connections: [SocialSyncPlatform: SocialConnection] = [:]
    @Published var isSyncing: Bool = false

    private let storageKey = "com.cosmoos.socialConnections"

    private init() {
        loadConnections()
    }

    // MARK: - Connection State

    func isConnected(_ platform: SocialSyncPlatform) -> Bool {
        connections[platform] != nil
    }

    var connectedPlatforms: [SocialSyncPlatform] {
        Array(connections.keys).sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Connect / Disconnect

    /// Placeholder for OAuth flow — will be implemented when API credentials are available
    func connect(_ platform: SocialSyncPlatform) async {
        // TODO: Implement OAuth2 flow per platform
        // 1. Open authorization URL in browser
        // 2. Handle callback with auth code
        // 3. Exchange code for access + refresh tokens
        // 4. Store connection
    }

    func disconnect(_ platform: SocialSyncPlatform) {
        connections.removeValue(forKey: platform)
        saveConnections()
    }

    // MARK: - Sync

    /// Placeholder for syncing all connected platforms
    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        for (platform, _) in connections {
            await syncPlatform(platform)
        }
    }

    /// Placeholder for syncing a single platform
    private func syncPlatform(_ platform: SocialSyncPlatform) async {
        // TODO: Implement per-platform API calls
        // 1. Fetch recent posts from platform API
        // 2. Create/update .contentPerformance atoms with real metrics
        // 3. Update lastSyncAt
        // 4. Trigger auto-linking via CreativeDimensionDataProvider

        if var connection = connections[platform] {
            connection.lastSyncAt = Date()
            connections[platform] = connection
            saveConnections()
        }
    }

    // MARK: - Persistence

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SocialSyncPlatform: SocialConnection].self, from: data) else {
            return
        }
        connections = decoded
    }

    private func saveConnections() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
