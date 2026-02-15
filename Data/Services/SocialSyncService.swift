// CosmoOS/Data/Services/SocialSyncService.swift
// Real social platform API clients with token-based authentication
// Supports YouTube Data API v3, Instagram Graph API, TikTok Display API, X API v2

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

    /// Map to SocialPlatform used by ContentPerformanceMetadata
    var toSocialPlatform: SocialPlatform {
        switch self {
        case .instagram: return .instagram
        case .youtube: return .youtube
        case .tiktok: return .tiktok
        case .x: return .twitter
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

// MARK: - Platform Sync Result

/// Aggregated metrics from a single platform sync
struct PlatformSyncResult: Sendable {
    let platform: SocialSyncPlatform
    let followerCount: Int
    let totalReach: Int
    let totalImpressions: Int
    let engagementRate: Double
    let recentPosts: [SyncedPost]
    let accountHandle: String
    let error: String?
}

/// A single post fetched from a platform API
struct SyncedPost: Sendable {
    let postId: String
    let platform: SocialSyncPlatform
    let caption: String?
    let publishedAt: Date
    let views: Int
    let likes: Int
    let comments: Int
    let shares: Int
    let saves: Int
    let reach: Int
    let impressions: Int
    let engagementRate: Double
    let thumbnailURL: String?
}

// MARK: - Social Sync Service

@MainActor
class SocialSyncService: ObservableObject {
    static let shared = SocialSyncService()

    @Published var connections: [SocialSyncPlatform: SocialConnection] = [:]
    @Published var isSyncing: Bool = false
    @Published var lastSyncResults: [SocialSyncPlatform: PlatformSyncResult] = [:]
    @Published var syncErrors: [SocialSyncPlatform: String] = [:]

    private let storageKey = "com.cosmoos.socialConnections"
    private let session = URLSession.shared

    private init() {
        loadConnections()
    }

    // MARK: - Connection State

    func isConnected(_ platform: SocialSyncPlatform) -> Bool {
        switch platform {
        case .youtube:
            return APIKeys.hasYouTube && APIKeys.hasYouTubeChannelId
        case .instagram:
            return APIKeys.hasInstagram
        case .tiktok:
            return APIKeys.hasTikTok
        case .x:
            return APIKeys.hasXTwitter
        }
    }

    var connectedPlatforms: [SocialSyncPlatform] {
        SocialSyncPlatform.allCases.filter { isConnected($0) }
    }

    var hasAnyConnection: Bool {
        !connectedPlatforms.isEmpty
    }

    // MARK: - Connect / Disconnect

    /// Connect a platform by validating its token
    func connect(platform: SocialSyncPlatform, token: String) async -> (success: Bool, message: String) {
        switch platform {
        case .youtube:
            // YouTube uses API key + channel ID, not a single token
            return (false, "Use API Key + Channel ID fields in Settings")
        case .instagram:
            APIKeys.save(token, identifier: "instagram")
            let result = await fetchInstagramProfile(token: token)
            if let handle = result {
                let connection = SocialConnection(
                    platform: .instagram,
                    accountId: handle,
                    accountHandle: handle,
                    accessToken: token,
                    refreshToken: "",
                    connectedAt: Date(),
                    lastSyncAt: Date()
                )
                connections[.instagram] = connection
                saveConnections()
                return (true, "Connected as @\(handle)")
            }
            return (false, "Invalid token or API error")
        case .tiktok:
            APIKeys.save(token, identifier: "tiktok")
            let connection = SocialConnection(
                platform: .tiktok,
                accountId: "tiktok_user",
                accountHandle: "TikTok User",
                accessToken: token,
                refreshToken: "",
                connectedAt: Date(),
                lastSyncAt: Date()
            )
            connections[.tiktok] = connection
            saveConnections()
            return (true, "Connected")
        case .x:
            APIKeys.save(token, identifier: "x_twitter")
            let result = await fetchXProfile(token: token)
            if let (id, handle) = result {
                let connection = SocialConnection(
                    platform: .x,
                    accountId: id,
                    accountHandle: handle,
                    accessToken: token,
                    refreshToken: "",
                    connectedAt: Date(),
                    lastSyncAt: Date()
                )
                connections[.x] = connection
                saveConnections()
                return (true, "Connected as @\(handle)")
            }
            return (false, "Invalid Bearer token")
        }
    }

    func disconnect(_ platform: SocialSyncPlatform) {
        connections.removeValue(forKey: platform)
        lastSyncResults.removeValue(forKey: platform)
        syncErrors.removeValue(forKey: platform)
        saveConnections()

        // Remove the stored token
        switch platform {
        case .instagram: APIKeys.delete(identifier: "instagram")
        case .tiktok: APIKeys.delete(identifier: "tiktok")
        case .x: APIKeys.delete(identifier: "x_twitter")
        case .youtube:
            APIKeys.delete(identifier: "youtube")
            APIKeys.delete(identifier: "youtube_channel_id")
        }
    }

    // MARK: - Sync All

    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        syncErrors = [:]

        for platform in connectedPlatforms {
            let result = await syncPlatform(platform)
            lastSyncResults[platform] = result
            if let error = result.error {
                syncErrors[platform] = error
            }
        }
    }

    /// Sync a single platform and return aggregated results
    func syncPlatform(_ platform: SocialSyncPlatform) async -> PlatformSyncResult {
        switch platform {
        case .youtube:
            return await syncYouTube()
        case .instagram:
            return await syncInstagram()
        case .tiktok:
            return await syncTikTok()
        case .x:
            return await syncX()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - YouTube Data API v3
    // ═══════════════════════════════════════════════════════════════

    private func syncYouTube() async -> PlatformSyncResult {
        guard let apiKey = APIKeys.youtube, !apiKey.isEmpty,
              let channelId = APIKeys.youtubeChannelId, !channelId.isEmpty else {
            return PlatformSyncResult(
                platform: .youtube, followerCount: 0, totalReach: 0,
                totalImpressions: 0, engagementRate: 0, recentPosts: [],
                accountHandle: "", error: "Missing YouTube API Key or Channel ID"
            )
        }

        // Step 1: Fetch channel statistics
        let channelStats = await fetchYouTubeChannel(apiKey: apiKey, channelId: channelId)
        guard let stats = channelStats else {
            return PlatformSyncResult(
                platform: .youtube, followerCount: 0, totalReach: 0,
                totalImpressions: 0, engagementRate: 0, recentPosts: [],
                accountHandle: "", error: "Failed to fetch YouTube channel data"
            )
        }

        // Step 2: Fetch recent videos
        let videoIds = await fetchYouTubeRecentVideoIds(apiKey: apiKey, channelId: channelId)
        var posts: [SyncedPost] = []

        if !videoIds.isEmpty {
            posts = await fetchYouTubeVideoStats(apiKey: apiKey, videoIds: videoIds)
        }

        let totalViews = posts.reduce(0) { $0 + $1.views }
        let totalLikes = posts.reduce(0) { $0 + $1.likes }
        let totalComments = posts.reduce(0) { $0 + $1.comments }
        let engagementRate = totalViews > 0
            ? Double(totalLikes + totalComments) / Double(totalViews) * 100
            : 0

        return PlatformSyncResult(
            platform: .youtube,
            followerCount: stats.subscriberCount,
            totalReach: totalViews,
            totalImpressions: Int(stats.viewCount),
            engagementRate: engagementRate,
            recentPosts: posts,
            accountHandle: stats.title,
            error: nil
        )
    }

    private struct YouTubeChannelStats {
        let subscriberCount: Int
        let viewCount: Int64
        let videoCount: Int
        let title: String
    }

    private func fetchYouTubeChannel(apiKey: String, channelId: String) async -> YouTubeChannelStats? {
        let urlString = "https://www.googleapis.com/youtube/v3/channels?part=statistics,snippet&id=\(channelId)&key=\(apiKey)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let item = items.first,
                  let statistics = item["statistics"] as? [String: Any],
                  let snippet = item["snippet"] as? [String: Any] else { return nil }

            let subscriberCount = Int(statistics["subscriberCount"] as? String ?? "0") ?? 0
            let viewCount = Int64(statistics["viewCount"] as? String ?? "0") ?? 0
            let videoCount = Int(statistics["videoCount"] as? String ?? "0") ?? 0
            let title = snippet["title"] as? String ?? channelId

            return YouTubeChannelStats(
                subscriberCount: subscriberCount,
                viewCount: viewCount,
                videoCount: videoCount,
                title: title
            )
        } catch {
            print("[SocialSync] YouTube channel fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchYouTubeRecentVideoIds(apiKey: String, channelId: String) async -> [String] {
        let urlString = "https://www.googleapis.com/youtube/v3/search?part=snippet&channelId=\(channelId)&type=video&maxResults=10&order=date&key=\(apiKey)"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return [] }

            return items.compactMap { item -> String? in
                guard let idObj = item["id"] as? [String: Any] else { return nil }
                return idObj["videoId"] as? String
            }
        } catch {
            print("[SocialSync] YouTube search error: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchYouTubeVideoStats(apiKey: String, videoIds: [String]) async -> [SyncedPost] {
        let ids = videoIds.joined(separator: ",")
        let urlString = "https://www.googleapis.com/youtube/v3/videos?part=statistics,snippet&id=\(ids)&key=\(apiKey)"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return [] }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoFormatterBasic = ISO8601DateFormatter()

            return items.compactMap { item -> SyncedPost? in
                guard let videoId = item["id"] as? String,
                      let statistics = item["statistics"] as? [String: Any],
                      let snippet = item["snippet"] as? [String: Any] else { return nil }

                let views = Int(statistics["viewCount"] as? String ?? "0") ?? 0
                let likes = Int(statistics["likeCount"] as? String ?? "0") ?? 0
                let comments = Int(statistics["commentCount"] as? String ?? "0") ?? 0
                let title = snippet["title"] as? String
                let publishedAtStr = snippet["publishedAt"] as? String ?? ""
                let publishedAt = isoFormatter.date(from: publishedAtStr)
                    ?? isoFormatterBasic.date(from: publishedAtStr)
                    ?? Date()
                let thumbnailURL = (snippet["thumbnails"] as? [String: Any])?["medium"] as? [String: Any]
                let thumbURL = thumbnailURL?["url"] as? String

                let engRate = views > 0 ? Double(likes + comments) / Double(views) * 100 : 0

                return SyncedPost(
                    postId: videoId,
                    platform: .youtube,
                    caption: title,
                    publishedAt: publishedAt,
                    views: views,
                    likes: likes,
                    comments: comments,
                    shares: 0,
                    saves: 0,
                    reach: views,
                    impressions: views,
                    engagementRate: engRate,
                    thumbnailURL: thumbURL
                )
            }
        } catch {
            print("[SocialSync] YouTube video stats error: \(error.localizedDescription)")
            return []
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Instagram Graph API
    // ═══════════════════════════════════════════════════════════════

    private func syncInstagram() async -> PlatformSyncResult {
        guard let token = APIKeys.instagram, !token.isEmpty else {
            return PlatformSyncResult(
                platform: .instagram, followerCount: 0, totalReach: 0,
                totalImpressions: 0, engagementRate: 0, recentPosts: [],
                accountHandle: "", error: "Missing Instagram access token"
            )
        }

        // Step 1: Fetch profile
        let profile = await fetchInstagramFullProfile(token: token)

        // Step 2: Fetch recent media
        let posts = await fetchInstagramMedia(token: token)

        let totalLikes = posts.reduce(0) { $0 + $1.likes }
        let totalComments = posts.reduce(0) { $0 + $1.comments }
        let totalReach = posts.reduce(0) { $0 + $1.reach }
        let followerCount = profile?.followers ?? 0
        let engagementRate = followerCount > 0
            ? Double(totalLikes + totalComments) / Double(followerCount) / max(1.0, Double(posts.count)) * 100
            : 0

        return PlatformSyncResult(
            platform: .instagram,
            followerCount: followerCount,
            totalReach: totalReach,
            totalImpressions: totalReach,
            engagementRate: engagementRate,
            recentPosts: posts,
            accountHandle: profile?.username ?? "",
            error: profile == nil ? "Failed to fetch Instagram profile" : nil
        )
    }

    private struct InstagramProfile {
        let id: String
        let username: String
        let followers: Int
        let mediaCount: Int
    }

    /// Validate token and return username (used during connect)
    private func fetchInstagramProfile(token: String) async -> String? {
        let urlString = "https://graph.instagram.com/me?fields=id,username&access_token=\(token)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return json["username"] as? String
        } catch {
            return nil
        }
    }

    private func fetchInstagramFullProfile(token: String) async -> InstagramProfile? {
        let urlString = "https://graph.instagram.com/me?fields=id,username,media_count,followers_count&access_token=\(token)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            return InstagramProfile(
                id: json["id"] as? String ?? "",
                username: json["username"] as? String ?? "",
                followers: json["followers_count"] as? Int ?? 0,
                mediaCount: json["media_count"] as? Int ?? 0
            )
        } catch {
            print("[SocialSync] Instagram profile error: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchInstagramMedia(token: String) async -> [SyncedPost] {
        let urlString = "https://graph.instagram.com/me/media?fields=id,caption,media_type,timestamp,like_count,comments_count,permalink&limit=10&access_token=\(token)"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]] else { return [] }

            let isoFormatter = ISO8601DateFormatter()

            return dataArray.compactMap { item -> SyncedPost? in
                guard let postId = item["id"] as? String else { return nil }

                let caption = item["caption"] as? String
                let likes = item["like_count"] as? Int ?? 0
                let comments = item["comments_count"] as? Int ?? 0
                let timestampStr = item["timestamp"] as? String ?? ""
                let publishedAt = isoFormatter.date(from: timestampStr) ?? Date()

                // Instagram Graph API basic display doesn't include reach/impressions
                // Estimate reach from engagement
                let estimatedReach = (likes + comments) * 10

                return SyncedPost(
                    postId: postId,
                    platform: .instagram,
                    caption: caption,
                    publishedAt: publishedAt,
                    views: 0,
                    likes: likes,
                    comments: comments,
                    shares: 0,
                    saves: 0,
                    reach: estimatedReach,
                    impressions: estimatedReach,
                    engagementRate: estimatedReach > 0 ? Double(likes + comments) / Double(estimatedReach) * 100 : 0,
                    thumbnailURL: nil
                )
            }
        } catch {
            print("[SocialSync] Instagram media error: \(error.localizedDescription)")
            return []
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - TikTok Display API
    // ═══════════════════════════════════════════════════════════════

    private func syncTikTok() async -> PlatformSyncResult {
        guard let token = APIKeys.tiktok, !token.isEmpty else {
            return PlatformSyncResult(
                platform: .tiktok, followerCount: 0, totalReach: 0,
                totalImpressions: 0, engagementRate: 0, recentPosts: [],
                accountHandle: "", error: "Missing TikTok access token"
            )
        }

        let profile = await fetchTikTokProfile(token: token)

        return PlatformSyncResult(
            platform: .tiktok,
            followerCount: profile?.followerCount ?? 0,
            totalReach: profile?.likesCount ?? 0,
            totalImpressions: profile?.likesCount ?? 0,
            engagementRate: 0,
            recentPosts: [],
            accountHandle: profile?.displayName ?? "TikTok User",
            error: profile == nil ? "Failed to fetch TikTok profile" : nil
        )
    }

    private struct TikTokProfile {
        let displayName: String
        let followerCount: Int
        let followingCount: Int
        let likesCount: Int
        let videoCount: Int
    }

    private func fetchTikTokProfile(token: String) async -> TikTokProfile? {
        let urlString = "https://open.tiktokapis.com/v2/user/info/?fields=display_name,follower_count,following_count,likes_count,video_count"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let user = dataObj["user"] as? [String: Any] else { return nil }

            return TikTokProfile(
                displayName: user["display_name"] as? String ?? "",
                followerCount: user["follower_count"] as? Int ?? 0,
                followingCount: user["following_count"] as? Int ?? 0,
                likesCount: user["likes_count"] as? Int ?? 0,
                videoCount: user["video_count"] as? Int ?? 0
            )
        } catch {
            print("[SocialSync] TikTok profile error: \(error.localizedDescription)")
            return nil
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - X (Twitter) API v2
    // ═══════════════════════════════════════════════════════════════

    private func syncX() async -> PlatformSyncResult {
        guard let token = APIKeys.xTwitter, !token.isEmpty else {
            return PlatformSyncResult(
                platform: .x, followerCount: 0, totalReach: 0,
                totalImpressions: 0, engagementRate: 0, recentPosts: [],
                accountHandle: "", error: "Missing X Bearer token"
            )
        }

        // Step 1: Fetch user profile
        guard let (userId, username, followers) = await fetchXProfileFull(token: token) else {
            return PlatformSyncResult(
                platform: .x, followerCount: 0, totalReach: 0,
                totalImpressions: 0, engagementRate: 0, recentPosts: [],
                accountHandle: "", error: "Failed to fetch X profile"
            )
        }

        // Step 2: Fetch recent tweets
        let posts = await fetchXTweets(token: token, userId: userId)

        let totalImpressions = posts.reduce(0) { $0 + $1.impressions }
        let totalLikes = posts.reduce(0) { $0 + $1.likes }
        let totalReplies = posts.reduce(0) { $0 + $1.comments }
        let totalRetweets = posts.reduce(0) { $0 + $1.shares }
        let engagementRate = totalImpressions > 0
            ? Double(totalLikes + totalReplies + totalRetweets) / Double(totalImpressions) * 100
            : 0

        return PlatformSyncResult(
            platform: .x,
            followerCount: followers,
            totalReach: totalImpressions,
            totalImpressions: totalImpressions,
            engagementRate: engagementRate,
            recentPosts: posts,
            accountHandle: username,
            error: nil
        )
    }

    /// Validate X token and return (id, username) — used during connect
    private func fetchXProfile(token: String) async -> (String, String)? {
        let urlString = "https://api.x.com/2/users/me?user.fields=public_metrics"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let id = dataObj["id"] as? String,
                  let username = dataObj["username"] as? String else { return nil }
            return (id, username)
        } catch {
            return nil
        }
    }

    private func fetchXProfileFull(token: String) async -> (userId: String, username: String, followers: Int)? {
        let urlString = "https://api.x.com/2/users/me?user.fields=public_metrics"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let id = dataObj["id"] as? String,
                  let username = dataObj["username"] as? String else { return nil }

            let publicMetrics = dataObj["public_metrics"] as? [String: Any]
            let followers = publicMetrics?["followers_count"] as? Int ?? 0

            return (id, username, followers)
        } catch {
            print("[SocialSync] X profile error: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchXTweets(token: String, userId: String) async -> [SyncedPost] {
        let urlString = "https://api.x.com/2/users/\(userId)/tweets?tweet.fields=public_metrics,created_at&max_results=10"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]] else { return [] }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoFormatterBasic = ISO8601DateFormatter()

            return dataArray.compactMap { tweet -> SyncedPost? in
                guard let tweetId = tweet["id"] as? String else { return nil }

                let text = tweet["text"] as? String
                let createdAtStr = tweet["created_at"] as? String ?? ""
                let publishedAt = isoFormatter.date(from: createdAtStr)
                    ?? isoFormatterBasic.date(from: createdAtStr)
                    ?? Date()

                let metrics = tweet["public_metrics"] as? [String: Any]
                let likes = metrics?["like_count"] as? Int ?? 0
                let retweets = metrics?["retweet_count"] as? Int ?? 0
                let replies = metrics?["reply_count"] as? Int ?? 0
                let impressions = metrics?["impression_count"] as? Int ?? 0
                let bookmarks = metrics?["bookmark_count"] as? Int ?? 0

                let engRate = impressions > 0
                    ? Double(likes + retweets + replies) / Double(impressions) * 100
                    : 0

                return SyncedPost(
                    postId: tweetId,
                    platform: .x,
                    caption: text,
                    publishedAt: publishedAt,
                    views: impressions,
                    likes: likes,
                    comments: replies,
                    shares: retweets,
                    saves: bookmarks,
                    reach: impressions,
                    impressions: impressions,
                    engagementRate: engRate,
                    thumbnailURL: nil
                )
            }
        } catch {
            print("[SocialSync] X tweets error: \(error.localizedDescription)")
            return []
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Aggregated Metrics (for CreativeDimensionDataProvider)
    // ═══════════════════════════════════════════════════════════════

    /// Total follower count across all connected platforms
    var totalFollowerCount: Int {
        lastSyncResults.values.reduce(0) { $0 + $1.followerCount }
    }

    /// Total reach across all connected platforms
    var totalReach: Int {
        lastSyncResults.values.reduce(0) { $0 + $1.totalReach }
    }

    /// Weighted average engagement rate across platforms
    var averageEngagementRate: Double {
        let results = Array(lastSyncResults.values)
        guard !results.isEmpty else { return 0 }
        let totalImpressions = results.reduce(0) { $0 + $1.totalImpressions }
        guard totalImpressions > 0 else { return 0 }
        let weightedEngagement = results.reduce(0.0) { $0 + $1.engagementRate * Double($1.totalImpressions) }
        return weightedEngagement / Double(totalImpressions)
    }

    /// All recent posts across platforms, sorted by date
    var allRecentPosts: [SyncedPost] {
        lastSyncResults.values
            .flatMap { $0.recentPosts }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    /// Platform metrics for the Creative dimension dashboard
    var platformMetrics: [PlatformMetrics] {
        let totalReach = max(1, self.totalReach)
        return lastSyncResults.values.map { result in
            let contentPlatform: ContentPlatform = {
                switch result.platform {
                case .youtube: return .youtube
                case .instagram: return .instagram
                case .tiktok: return .tiktok
                case .x: return .twitter
                }
            }()
            return PlatformMetrics(
                platform: contentPlatform,
                followerCount: result.followerCount,
                engagementRate: result.engagementRate,
                reachPercentage: Double(result.totalReach) / Double(totalReach) * 100,
                isConnected: true
            )
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Persistence
    // ═══════════════════════════════════════════════════════════════

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
