// CosmoOS/Cosmo/URLClassifier.swift
// URL type detection for intelligent research capture
// Identifies YouTube, Twitter/X, PDF, and website URLs

import Foundation

// MARK: - URL Type Classification
enum URLType: Equatable {
    case youtube(videoId: String)
    case twitter(tweetId: String)
    case loom(videoId: String)
    case pdf
    case website

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .twitter: return "Twitter"
        case .loom: return "Loom"
        case .pdf: return "PDF"
        case .website: return "Website"
        }
    }

    var icon: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .twitter: return "bubble.left.fill"
        case .loom: return "video.fill"
        case .pdf: return "doc.fill"
        case .website: return "globe"
        }
    }

    var researchSourceType: ResearchRichContent.SourceType {
        switch self {
        case .youtube: return .youtube
        case .twitter: return .twitter
        case .loom: return .loom
        case .pdf: return .pdf
        case .website: return .website
        }
    }
}

// MARK: - URL Classifier
struct URLClassifier {

    /// Classify a URL into its type
    static func classify(_ url: URL) -> URLType {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        // YouTube
        if isYouTube(host: host) {
            if let videoId = extractYouTubeId(from: url) {
                return .youtube(videoId: videoId)
            }
        }

        // Twitter/X
        if isTwitter(host: host) {
            if let tweetId = extractTweetId(from: url) {
                return .twitter(tweetId: tweetId)
            }
        }

        // Loom
        if isLoom(host: host) {
            if let videoId = extractLoomId(from: url) {
                return .loom(videoId: videoId)
            }
        }

        // PDF
        if path.hasSuffix(".pdf") {
            return .pdf
        }

        // Default to website
        return .website
    }

    /// Classify a URL string
    static func classify(_ urlString: String) -> URLType? {
        guard let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else {
            return nil
        }
        return classify(url)
    }

    /// Check if a string is a valid URL
    static func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    // MARK: - YouTube Detection

    private static func isYouTube(host: String) -> Bool {
        host.contains("youtube.com") ||
        host.contains("youtu.be") ||
        host.contains("youtube-nocookie.com")
    }

    /// Extract YouTube video ID from various URL formats
    static func extractYouTubeId(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        // youtu.be/VIDEO_ID format
        if host.contains("youtu.be") {
            let path = url.path
            if path.count > 1 {
                return String(path.dropFirst()) // Remove leading /
            }
        }

        // youtube.com/watch?v=VIDEO_ID format
        if host.contains("youtube.com") {
            // Check for /watch?v= format
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems {
                for item in queryItems {
                    if item.name == "v", let value = item.value, !value.isEmpty {
                        return value
                    }
                }
            }

            // Check for /embed/VIDEO_ID format
            let path = url.path
            if path.hasPrefix("/embed/") {
                let videoId = String(path.dropFirst(7)) // Remove /embed/
                if !videoId.isEmpty && !videoId.contains("/") {
                    return videoId
                }
            }

            // Check for /v/VIDEO_ID format
            if path.hasPrefix("/v/") {
                let videoId = String(path.dropFirst(3))
                if !videoId.isEmpty && !videoId.contains("/") {
                    return videoId
                }
            }

            // Check for /shorts/VIDEO_ID format
            if path.hasPrefix("/shorts/") {
                let videoId = String(path.dropFirst(8))
                if !videoId.isEmpty && !videoId.contains("/") {
                    return videoId
                }
            }
        }

        return nil
    }

    // MARK: - Twitter/X Detection

    private static func isTwitter(host: String) -> Bool {
        host.contains("twitter.com") ||
        host.contains("x.com") ||
        host.contains("mobile.twitter.com")
    }

    /// Extract Tweet ID from Twitter/X URL
    static func extractTweetId(from url: URL) -> String? {
        let path = url.path

        // Pattern: /username/status/TWEET_ID
        let components = path.split(separator: "/")
        if components.count >= 3 {
            let statusIndex = components.firstIndex(of: "status")
            if let idx = statusIndex, idx + 1 < components.count {
                let tweetId = String(components[idx + 1])
                // Tweet IDs are numeric
                if tweetId.allSatisfy({ $0.isNumber }) {
                    return tweetId
                }
            }
        }

        return nil
    }

    // MARK: - Loom Detection

    private static func isLoom(host: String) -> Bool {
        host.contains("loom.com")
    }

    /// Extract Loom video ID from URL
    /// Loom URLs: https://www.loom.com/share/VIDEO_ID or https://www.loom.com/embed/VIDEO_ID
    static func extractLoomId(from url: URL) -> String? {
        let path = url.path

        // Pattern: /share/VIDEO_ID or /embed/VIDEO_ID
        let components = path.split(separator: "/")
        if components.count >= 2 {
            let shareIndex = components.firstIndex(of: "share")
            let embedIndex = components.firstIndex(of: "embed")

            if let idx = shareIndex ?? embedIndex, idx + 1 < components.count {
                let videoId = String(components[idx + 1])
                // Loom IDs are alphanumeric (32 chars typically)
                if !videoId.isEmpty && videoId.count >= 10 {
                    // Remove any query parameters
                    return videoId.components(separatedBy: "?").first ?? videoId
                }
            }
        }

        return nil
    }

    /// Build Loom thumbnail URL (uses their CDN)
    static func loomThumbnailURL(videoId: String) -> URL? {
        URL(string: "https://cdn.loom.com/sessions/thumbnails/\(videoId)-with-play.gif")
    }

    /// Build Loom embed URL
    static func loomEmbedURL(videoId: String) -> URL? {
        URL(string: "https://www.loom.com/embed/\(videoId)")
    }

    // MARK: - Metadata Extraction

    /// Get a clean title suggestion from URL
    static func suggestedTitle(from url: URL) -> String {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? ""
        let path = url.path

        // For YouTube, return generic title (will be replaced by metadata)
        if isYouTube(host: host) {
            return "YouTube Video"
        }

        // For Twitter, return generic title
        if isTwitter(host: host) {
            return "Tweet"
        }

        // For Loom, return generic title (will be replaced by metadata)
        if isLoom(host: host) {
            return "Loom Recording"
        }

        // For PDFs, try to extract filename
        if path.hasSuffix(".pdf") {
            let filename = (path as NSString).lastPathComponent
            let name = (filename as NSString).deletingPathExtension
            if !name.isEmpty {
                return name.replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
            }
        }

        // For websites, use domain
        return host.capitalized
    }

    /// Build YouTube thumbnail URL
    static func youtubeThumbnailURL(videoId: String, quality: YouTubeThumbnailQuality = .high) -> URL? {
        URL(string: "https://img.youtube.com/vi/\(videoId)/\(quality.rawValue).jpg")
    }

    enum YouTubeThumbnailQuality: String {
        case defaultQuality = "default"     // 120x90
        case medium = "mqdefault"           // 320x180
        case high = "hqdefault"             // 480x360
        case standard = "sddefault"         // 640x480
        case maxRes = "maxresdefault"       // 1280x720
    }
}

// MARK: - URL Validation Extension
extension String {
    /// Check if string looks like a URL
    var looksLikeURL: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must start with http:// or https://
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            return false
        }

        // Must be parseable as URL
        guard URL(string: trimmed) != nil else {
            return false
        }

        return true
    }
}
