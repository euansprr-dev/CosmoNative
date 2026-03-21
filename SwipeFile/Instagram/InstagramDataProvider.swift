// CosmoOS/SwipeFile/Instagram/InstagramDataProvider.swift
// Protocol abstraction for fetching Instagram creator data from external APIs
// Pluggable: can swap Apify for RapidAPI, direct scraping, etc.

import Foundation

// MARK: - Provider Protocol

/// Abstraction for fetching Instagram creator profiles and posts with engagement data.
/// Implementations handle API auth, rate limiting, and data normalization.
protocol InstagramDataProvider: Sendable {
    /// Fetch a creator's public profile info
    func fetchProfile(handle: String) async throws -> ImportedCreatorProfile

    /// Fetch posts with engagement metrics, supporting pagination
    /// - Parameters:
    ///   - handle: Instagram username (without @)
    ///   - maxPosts: Maximum number of posts to retrieve
    ///   - onProgress: Callback with (fetched, estimated total) counts
    func fetchPosts(
        handle: String,
        maxPosts: Int,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [ImportedPost]

    /// Estimate API cost for a given number of posts
    func estimateCost(postCount: Int) -> ImportCostEstimate

    /// Whether the provider has a valid API key configured
    var isConfigured: Bool { get }
}

// MARK: - Imported Creator Profile

/// Profile data fetched from an external API (ephemeral, not persisted directly)
struct ImportedCreatorProfile: Codable, Sendable, Equatable {
    let username: String
    let fullName: String?
    let biography: String?
    let followerCount: Int
    let followingCount: Int
    let postsCount: Int
    let profilePicUrl: String?
    let isPrivate: Bool
    let isVerified: Bool
}

// MARK: - Imported Post

/// A single post fetched from an external API with engagement metrics.
/// Ephemeral until user selects it for import into the swipe system.
struct ImportedPost: Identifiable, Codable, Sendable, Equatable {
    let id: String                          // Instagram post ID
    let shortcode: String                   // e.g. "CxYz123AbC"
    let url: URL                            // https://instagram.com/p/{shortcode}/
    let contentType: InstagramContentType
    let caption: String?
    let thumbnailUrl: URL?
    let videoUrl: URL?
    let timestamp: Date
    let engagement: InstagramEngagement
    let hashtags: [String]
    let carouselMediaCount: Int?
    let carouselItems: [CarouselItem]?
    let locationName: String?
    let ownerUsername: String

    /// Total engagement for sorting (likes + comments + views)
    var totalEngagement: Int {
        engagement.likesCount + engagement.commentsCount + (engagement.viewsCount ?? 0)
    }

    /// Likes-based engagement for quick sorting
    var likesForSort: Int { engagement.likesCount }

    /// Views-based engagement for quick sorting
    var viewsForSort: Int { engagement.viewsCount ?? 0 }

    /// Comments-based engagement for quick sorting
    var commentsForSort: Int { engagement.commentsCount }
}

// MARK: - Import Cost Estimate

/// Cost estimate shown to user before confirming an import
struct ImportCostEstimate: Sendable, Equatable {
    let postCount: Int
    let estimatedCostUSD: Double
    let estimatedDurationSeconds: Int
    let warning: String?                    // e.g., "Large account, may take 2+ minutes"
}

// MARK: - Import Errors

enum ImportError: LocalizedError, Sendable {
    case privateAccount(String)
    case accountNotFound(String)
    case rateLimited(retryAfterSeconds: Int)
    case networkUnavailable
    case apiKeyMissing
    case apiError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .privateAccount(let handle):
            return "@\(handle) is a private account. Only public accounts can be imported."
        case .accountNotFound(let handle):
            return "Could not find Instagram account @\(handle). Check the handle and try again."
        case .rateLimited(let seconds):
            return "Rate limited. Try again in \(seconds) seconds."
        case .networkUnavailable:
            return "No internet connection. Check your network and try again."
        case .apiKeyMissing:
            return "Apify API key not configured. Add it in Settings → API Keys."
        case .apiError(let message):
            return "API error: \(message)"
        case .decodingError(let message):
            return "Failed to parse response: \(message)"
        }
    }
}

// MARK: - Import Sort Options

enum ImportSortOption: String, CaseIterable, Sendable {
    case bestPerformers = "Best Performers"
    case mostRecent = "Most Recent"
    case mostComments = "Most Comments"
    case mostViews = "Most Views"

    func sort(_ posts: [ImportedPost]) -> [ImportedPost] {
        switch self {
        case .bestPerformers:
            return posts.sorted { $0.likesForSort > $1.likesForSort }
        case .mostRecent:
            return posts.sorted { $0.timestamp > $1.timestamp }
        case .mostComments:
            return posts.sorted { $0.commentsForSort > $1.commentsForSort }
        case .mostViews:
            return posts.sorted { $0.viewsForSort > $1.viewsForSort }
        }
    }
}
