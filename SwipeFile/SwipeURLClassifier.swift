// CosmoOS/SwipeFile/SwipeURLClassifier.swift
// URL pattern detection and content type classification for Swipe Files

import Foundation

/// Classifies clipboard content into swipe file content types
/// Detects YouTube, X/Twitter, Threads, Instagram URLs and raw text
struct SwipeURLClassifier {

    // MARK: - Classification Result

    struct Classification {
        let sourceType: ResearchRichContent.SourceType
        let contentId: String?
        let originalUrl: String?
        let isUrl: Bool

        static func rawText() -> Classification {
            Classification(sourceType: .rawNote, contentId: nil, originalUrl: nil, isUrl: false)
        }

        static func url(_ type: ResearchRichContent.SourceType, id: String?, url: String) -> Classification {
            Classification(sourceType: type, contentId: id, originalUrl: url, isUrl: true)
        }
    }

    // MARK: - URL Patterns

    // YouTube patterns
    private let youtubeVideoPattern = try! NSRegularExpression(
        pattern: #"(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/v/)([a-zA-Z0-9_-]{11})"#,
        options: .caseInsensitive
    )

    private let youtubeShortsPattern = try! NSRegularExpression(
        pattern: #"youtube\.com/shorts/([a-zA-Z0-9_-]{11})"#,
        options: .caseInsensitive
    )

    // X/Twitter patterns
    private let xTwitterPattern = try! NSRegularExpression(
        pattern: #"(?:twitter\.com|x\.com)/\w+/status/(\d+)"#,
        options: .caseInsensitive
    )

    // Threads pattern
    private let threadsPattern = try! NSRegularExpression(
        pattern: #"threads\.net/@?[\w.]+/post/([a-zA-Z0-9_-]+)"#,
        options: .caseInsensitive
    )

    // Instagram patterns
    private let instagramReelPattern = try! NSRegularExpression(
        pattern: #"instagram\.com/(?:(?:reel|reels)|(?:share/reel))/([a-zA-Z0-9_-]+)"#,
        options: .caseInsensitive
    )

    private let instagramPostPattern = try! NSRegularExpression(
        pattern: #"instagram\.com/(?:(?:p)|(?:share/p))/([a-zA-Z0-9_-]+)"#,
        options: .caseInsensitive
    )

    private let instagramStoriesPattern = try! NSRegularExpression(
        pattern: #"instagram\.com/stories/[\w.]+/(\d+)"#,
        options: .caseInsensitive
    )

    // Loom patterns
    private let loomPattern = try! NSRegularExpression(
        pattern: #"loom\.com/(?:share|embed)/([a-zA-Z0-9]+)"#,
        options: .caseInsensitive
    )

    // General URL pattern
    private let urlPattern = try! NSRegularExpression(
        pattern: #"^https?://[^\s]+"#,
        options: .caseInsensitive
    )

    // MARK: - Classification

    /// Classify clipboard content into a swipe file content type
    func classify(_ content: String) -> Classification {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        // Check YouTube Shorts first (more specific)
        if let match = youtubeShortsPattern.firstMatch(in: trimmed, range: range),
           let videoIdRange = Range(match.range(at: 1), in: trimmed) {
            let videoId = String(trimmed[videoIdRange])
            return .url(.youtubeShort, id: videoId, url: trimmed)
        }

        // Check YouTube regular videos
        if let match = youtubeVideoPattern.firstMatch(in: trimmed, range: range),
           let videoIdRange = Range(match.range(at: 1), in: trimmed) {
            let videoId = String(trimmed[videoIdRange])
            return .url(.youtube, id: videoId, url: trimmed)
        }

        // Check X/Twitter
        if let match = xTwitterPattern.firstMatch(in: trimmed, range: range),
           let tweetIdRange = Range(match.range(at: 1), in: trimmed) {
            let tweetId = String(trimmed[tweetIdRange])
            return .url(.xPost, id: tweetId, url: trimmed)
        }

        // Check Threads
        if let match = threadsPattern.firstMatch(in: trimmed, range: range),
           let postIdRange = Range(match.range(at: 1), in: trimmed) {
            let postId = String(trimmed[postIdRange])
            return .url(.threads, id: postId, url: trimmed)
        }

        // Check Loom
        if let match = loomPattern.firstMatch(in: trimmed, range: range),
           let videoIdRange = Range(match.range(at: 1), in: trimmed) {
            let videoId = String(trimmed[videoIdRange])
            return .url(.loom, id: videoId, url: trimmed)
        }

        // Check Instagram Reel
        if let match = instagramReelPattern.firstMatch(in: trimmed, range: range),
           let reelIdRange = Range(match.range(at: 1), in: trimmed) {
            let reelId = String(trimmed[reelIdRange])
            return .url(.instagramReel, id: reelId, url: trimmed)
        }

        // Check Instagram Post
        if let match = instagramPostPattern.firstMatch(in: trimmed, range: range),
           let postIdRange = Range(match.range(at: 1), in: trimmed) {
            let postId = String(trimmed[postIdRange])
            // Could be a post or carousel - default to post, can be changed in modal
            return .url(.instagramPost, id: postId, url: trimmed)
        }

        // Check Instagram Stories (treated as post)
        if let match = instagramStoriesPattern.firstMatch(in: trimmed, range: range),
           let storyIdRange = Range(match.range(at: 1), in: trimmed) {
            let storyId = String(trimmed[storyIdRange])
            return .url(.instagramPost, id: storyId, url: trimmed)
        }

        // Check if it's a general URL
        if urlPattern.firstMatch(in: trimmed, range: range) != nil {
            // It's a URL but not a recognized social platform
            return .url(.website, id: nil, url: trimmed)
        }

        // Not a URL - treat as raw text note
        return .rawText()
    }

    // MARK: - URL Validation

    /// Check if a string looks like a URL
    func isURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return urlPattern.firstMatch(in: trimmed, range: range) != nil
    }

    /// Extract video ID from YouTube URL
    func extractYouTubeVideoId(_ url: String) -> String? {
        let range = NSRange(url.startIndex..., in: url)

        // Try shorts first
        if let match = youtubeShortsPattern.firstMatch(in: url, range: range),
           let idRange = Range(match.range(at: 1), in: url) {
            return String(url[idRange])
        }

        // Try regular video
        if let match = youtubeVideoPattern.firstMatch(in: url, range: range),
           let idRange = Range(match.range(at: 1), in: url) {
            return String(url[idRange])
        }

        return nil
    }

    /// Extract tweet ID from X/Twitter URL
    func extractTweetId(_ url: String) -> String? {
        let range = NSRange(url.startIndex..., in: url)
        if let match = xTwitterPattern.firstMatch(in: url, range: range),
           let idRange = Range(match.range(at: 1), in: url) {
            return String(url[idRange])
        }
        return nil
    }

    /// Extract post ID from Instagram URL
    func extractInstagramId(_ url: String) -> String? {
        let range = NSRange(url.startIndex..., in: url)

        // Try reel
        if let match = instagramReelPattern.firstMatch(in: url, range: range),
           let idRange = Range(match.range(at: 1), in: url) {
            return String(url[idRange])
        }

        // Try post
        if let match = instagramPostPattern.firstMatch(in: url, range: range),
           let idRange = Range(match.range(at: 1), in: url) {
            return String(url[idRange])
        }

        return nil
    }

    /// Extract video ID from Loom URL
    func extractLoomId(_ url: String) -> String? {
        let range = NSRange(url.startIndex..., in: url)
        if let match = loomPattern.firstMatch(in: url, range: range),
           let idRange = Range(match.range(at: 1), in: url) {
            return String(url[idRange])
        }
        return nil
    }
}
