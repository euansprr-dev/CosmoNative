// CosmoOS/SwipeFile/Instagram/InstagramExtractor.swift
// Extracts video URLs and metadata from Instagram pages
// Per Instagram Research PRD Addendum

import Foundation

/// Extracts media data from Instagram URLs
/// Uses multiple extraction strategies since Instagram blocks programmatic access
@MainActor
final class InstagramExtractor: Sendable {
    static let shared = InstagramExtractor()

    private init() {}

    // MARK: - Main Extraction

    /// Extract media data from an Instagram URL
    func extract(from url: URL) async throws -> InstagramMediaData {
        // Detect content type from URL pattern first
        let contentType = detectContentType(from: url)

        // Fetch the HTML page
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstagramExtractionError.invalidResponse
        }

        // Check for rate limiting or blocked access
        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            throw InstagramExtractionError.deletedContent
        case 429:
            throw InstagramExtractionError.rateLimited
        case 401, 403:
            throw InstagramExtractionError.privateContent
        default:
            throw InstagramExtractionError.invalidResponse
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw InstagramExtractionError.invalidResponse
        }

        // Try multiple extraction strategies
        if let mediaData = try? extractFromLDJSON(html: html, originalURL: url, contentType: contentType) {
            return mediaData
        }

        if let mediaData = try? extractFromSharedData(html: html, originalURL: url, contentType: contentType) {
            return mediaData
        }

        if let mediaData = try? extractFromVideoURL(html: html, originalURL: url, contentType: contentType) {
            return mediaData
        }

        // If extraction fails, return basic data with the URL
        // User can still add notes, and we can retry extraction later
        return InstagramMediaData(
            originalURL: url,
            contentType: contentType,
            extractedAt: Date()
        )
    }

    // MARK: - Content Type Detection

    private func detectContentType(from url: URL) -> InstagramContentType {
        let path = url.path.lowercased()

        if path.contains("/reel/") || path.contains("/reels/") {
            return .reel
        }
        if path.contains("/stories/") {
            return .story
        }
        if path.contains("/p/") {
            // Could be image, video, or carousel - default to image, will update if we find video
            return .image
        }

        return .image // Default
    }

    // MARK: - Extraction Strategies

    /// Strategy 1: Extract from LD+JSON structured data
    private func extractFromLDJSON(html: String, originalURL: URL, contentType: InstagramContentType) throws -> InstagramMediaData {
        // Look for: <script type="application/ld+json">{"@type":"VideoObject"...}</script>
        guard let ldJsonMatch = html.range(of: #"<script type="application/ld\+json">\s*(\{[^<]+\})\s*</script>"#, options: .regularExpression) else {
            throw InstagramExtractionError.couldNotExtract
        }

        let jsonString = String(html[ldJsonMatch])
            .replacingOccurrences(of: #"<script type="application/ld\+json">\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*</script>"#, with: "", options: .regularExpression)

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw InstagramExtractionError.couldNotExtract
        }

        // Parse video data
        let videoURL: URL?
        if let contentUrl = json["contentUrl"] as? String {
            videoURL = URL(string: contentUrl)
        } else if let video = json["video"] as? [String: Any],
                  let contentUrl = video["contentUrl"] as? String {
            videoURL = URL(string: contentUrl)
        } else {
            videoURL = nil
        }

        let thumbnailURL: URL?
        if let thumbnail = json["thumbnailUrl"] as? String {
            thumbnailURL = URL(string: thumbnail)
        } else {
            thumbnailURL = nil
        }

        let duration: TimeInterval?
        if let durationStr = json["duration"] as? String {
            // ISO 8601 duration (e.g., "PT30S" for 30 seconds)
            duration = parseDuration(durationStr)
        } else {
            duration = nil
        }

        let caption = json["caption"] as? String ?? json["description"] as? String
        let author = (json["author"] as? [String: Any])?["name"] as? String

        // Update content type if we found video
        let finalContentType = videoURL != nil ? .videoPost : contentType

        return InstagramMediaData(
            originalURL: originalURL,
            contentType: finalContentType,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            duration: duration,
            authorUsername: author,
            caption: caption,
            extractedAt: Date()
        )
    }

    /// Strategy 2: Extract from window._sharedData or __additionalDataLoaded
    private func extractFromSharedData(html: String, originalURL: URL, contentType: InstagramContentType) throws -> InstagramMediaData {
        // Look for: window._sharedData = {...}
        // Or: window.__additionalDataLoaded({...})

        var jsonString: String?

        // Try _sharedData first
        if let sharedDataMatch = html.range(of: #"window\._sharedData\s*=\s*(\{.+?\});"#, options: .regularExpression) {
            let matched = String(html[sharedDataMatch])
            jsonString = matched
                .replacingOccurrences(of: #"window\._sharedData\s*=\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: ";$", with: "", options: .regularExpression)
        }

        // Try __additionalDataLoaded
        if jsonString == nil, let additionalMatch = html.range(of: #"window\.__additionalDataLoaded\s*\(\s*['\"].*?['\"]\s*,\s*(\{.+?\})\s*\)"#, options: .regularExpression) {
            let matched = String(html[additionalMatch])
            // Extract just the JSON object
            if let jsonStart = matched.firstIndex(of: "{"),
               let jsonEnd = matched.lastIndex(of: "}") {
                jsonString = String(matched[jsonStart...jsonEnd])
            }
        }

        guard let json = jsonString,
              let jsonData = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw InstagramExtractionError.couldNotExtract
        }

        // Navigate the JSON tree to find media data
        // Path varies: entry_data.PostPage[0].graphql.shortcode_media
        // Or: entry_data.ReelMedia or various other paths

        if let entryData = parsed["entry_data"] as? [String: Any] {
            // Try PostPage
            if let postPage = entryData["PostPage"] as? [[String: Any]],
               let first = postPage.first,
               let graphql = first["graphql"] as? [String: Any],
               let media = graphql["shortcode_media"] as? [String: Any] {
                return try parseMediaObject(media, originalURL: originalURL, baseType: contentType)
            }

            // Try ReelMedia
            if let reelMedia = entryData["ReelMedia"] as? [[String: Any]],
               let first = reelMedia.first {
                return try parseMediaObject(first, originalURL: originalURL, baseType: .reel)
            }
        }

        throw InstagramExtractionError.couldNotExtract
    }

    /// Strategy 3: Regex fallback for video_url
    private func extractFromVideoURL(html: String, originalURL: URL, contentType: InstagramContentType) throws -> InstagramMediaData {
        // Look for "video_url":"https://..." in page source
        // This is less reliable but catches some edge cases

        guard let videoUrlMatch = html.range(of: #""video_url"\s*:\s*"([^"]+)""#, options: .regularExpression) else {
            throw InstagramExtractionError.couldNotExtract
        }

        let matched = String(html[videoUrlMatch])
        let videoUrlString = matched
            .replacingOccurrences(of: #""video_url"\s*:\s*""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\"$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\u0026", with: "&")  // Unescape

        guard let videoURL = URL(string: videoUrlString) else {
            throw InstagramExtractionError.couldNotExtract
        }

        // Try to find thumbnail
        var thumbnailURL: URL?
        if let thumbMatch = html.range(of: #""display_url"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let thumbMatched = String(html[thumbMatch])
            let thumbString = thumbMatched
                .replacingOccurrences(of: #""display_url"\s*:\s*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\"$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\u0026", with: "&")
            thumbnailURL = URL(string: thumbString)
        }

        // Try to find author
        var author: String?
        if let authorMatch = html.range(of: #""username"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let authorMatched = String(html[authorMatch])
            author = authorMatched
                .replacingOccurrences(of: #""username"\s*:\s*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\"$", with: "", options: .regularExpression)
        }

        return InstagramMediaData(
            originalURL: originalURL,
            contentType: .videoPost,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            authorUsername: author,
            extractedAt: Date()
        )
    }

    // MARK: - Helper Methods

    private func parseMediaObject(_ media: [String: Any], originalURL: URL, baseType: InstagramContentType) throws -> InstagramMediaData {
        // Check if it's a video
        let isVideo = media["is_video"] as? Bool ?? false

        // Get video URL
        var videoURL: URL?
        if isVideo, let videoUrlString = media["video_url"] as? String {
            videoURL = URL(string: videoUrlString)
        }

        // Get thumbnail
        var thumbnailURL: URL?
        if let displayUrl = media["display_url"] as? String {
            thumbnailURL = URL(string: displayUrl)
        }

        // Get duration
        var duration: TimeInterval?
        if let dur = media["video_duration"] as? Double {
            duration = dur
        }

        // Get author
        var author: String?
        if let owner = media["owner"] as? [String: Any] {
            author = owner["username"] as? String
        }

        // Get caption
        var caption: String?
        if let edgeMediaToCaption = media["edge_media_to_caption"] as? [String: Any],
           let edges = edgeMediaToCaption["edges"] as? [[String: Any]],
           let first = edges.first,
           let node = first["node"] as? [String: Any] {
            caption = node["text"] as? String
        }

        // Check for carousel (sidecar)
        var carouselItems: [CarouselItem]?
        var finalType = isVideo ? .videoPost : baseType

        if let edgeSidecar = media["edge_sidecar_to_children"] as? [String: Any],
           let edges = edgeSidecar["edges"] as? [[String: Any]] {
            finalType = .carousel
            carouselItems = edges.enumerated().compactMap { index, edge -> CarouselItem? in
                guard let node = edge["node"] as? [String: Any] else { return nil }
                let nodeIsVideo = node["is_video"] as? Bool ?? false
                let mediaType: CarouselMediaType = nodeIsVideo ? .video : .image

                var itemURL: URL?
                if nodeIsVideo, let url = node["video_url"] as? String {
                    itemURL = URL(string: url)
                } else if let url = node["display_url"] as? String {
                    itemURL = URL(string: url)
                }

                guard let url = itemURL else { return nil }

                var itemThumb: URL?
                if let thumb = node["display_url"] as? String {
                    itemThumb = URL(string: thumb)
                }

                let itemDuration: TimeInterval? = node["video_duration"] as? Double

                return CarouselItem(
                    index: index,
                    mediaType: mediaType,
                    mediaURL: url,
                    thumbnailURL: itemThumb,
                    duration: itemDuration
                )
            }
        }

        // For reels, the type is always reel
        if baseType == .reel {
            finalType = .reel
        }

        return InstagramMediaData(
            originalURL: originalURL,
            contentType: finalType,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            duration: duration,
            authorUsername: author,
            caption: caption,
            carouselItems: carouselItems,
            extractedAt: Date()
        )
    }

    /// Parse ISO 8601 duration string (e.g., "PT30S" -> 30.0)
    private func parseDuration(_ iso8601: String) -> TimeInterval? {
        // Simple parser for common formats: PT1M30S, PT30S, PT1H2M3S
        var total: TimeInterval = 0
        var currentNum = ""

        for char in iso8601 {
            if char.isNumber {
                currentNum.append(char)
            } else if let num = Double(currentNum) {
                switch char {
                case "H": total += num * 3600
                case "M": total += num * 60
                case "S": total += num
                default: break
                }
                currentNum = ""
            }
        }

        return total > 0 ? total : nil
    }
}

// MARK: - Instagram Media Cache

/// Caches extracted Instagram media data with automatic refresh
@MainActor
final class InstagramMediaCache {
    static let shared = InstagramMediaCache()

    private var cache: [URL: InstagramMediaData] = [:]

    private init() {}

    /// Get media for an Instagram URL, extracting or refreshing as needed
    func getMedia(for originalURL: URL) async throws -> InstagramMediaData {
        // Check cache
        if let cached = cache[originalURL], !cached.isExpired {
            return cached
        }

        // Re-extract if expired or missing
        let fresh = try await InstagramExtractor.shared.extract(from: originalURL)
        cache[originalURL] = fresh
        return fresh
    }

    /// Preemptively refresh media before expiration
    func preemptiveRefresh(for originalURL: URL) {
        Task {
            do {
                let fresh = try await InstagramExtractor.shared.extract(from: originalURL)
                cache[originalURL] = fresh
            } catch {
                print("InstagramCache: Preemptive refresh failed: \(error)")
            }
        }
    }

    /// Clear cached data for a URL
    func invalidate(for originalURL: URL) {
        cache.removeValue(forKey: originalURL)
    }

    /// Clear all cached data
    func clearAll() {
        cache.removeAll()
    }
}
