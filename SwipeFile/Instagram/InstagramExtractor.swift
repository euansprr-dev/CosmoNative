// CosmoOS/SwipeFile/Instagram/InstagramExtractor.swift
// Extracts video URLs and metadata from Instagram pages
// Uses cobalt.tools API (same server-proxy pattern as SnapInsta) + embed page + GraphQL fallbacks

import Foundation

/// Extracts media data from Instagram URLs
/// Fallback chain: Cobalt API → Embed Page → GraphQL → HTML strategies → basic data
@MainActor
final class InstagramExtractor: Sendable {
    static let shared = InstagramExtractor()

    private init() {}

    // MARK: - Main Extraction

    /// Extract media data from an Instagram URL
    func extract(from url: URL) async throws -> InstagramMediaData {
        let contentType = detectContentType(from: url)

        // Strategy 1: Cobalt API (server-side proxy — same pattern as SnapInsta)
        if let mediaData = try? await extractViaCobalt(url: url, contentType: contentType) {
            print("InstagramExtractor: Cobalt API succeeded")
            return mediaData
        }

        // Strategy 2: Embed page scraping (no auth needed, works for public content)
        if let shortcode = extractShortcode(from: url),
           let mediaData = try? await extractFromEmbedPage(shortcode: shortcode, originalURL: url, contentType: contentType) {
            print("InstagramExtractor: Embed page succeeded")
            return mediaData
        }

        // Strategy 3: GraphQL API at /api/graphql (correct endpoint)
        if let mediaData = try? await extractFromGraphQL(url: url, contentType: contentType) {
            print("InstagramExtractor: GraphQL succeeded")
            return mediaData
        }

        // Strategy 4: Fetch HTML page and try multiple parse strategies
        if let mediaData = try? await extractFromHTMLPage(url: url, contentType: contentType) {
            print("InstagramExtractor: HTML page succeeded")
            return mediaData
        }

        print("InstagramExtractor: All strategies failed for \(url)")

        // If all extraction fails, return basic data with the URL
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
            return .image
        }

        return .image
    }

    // MARK: - Strategy 1: Cobalt API (like SnapInsta server-side proxy)

    /// Cobalt instance URLs — tried in order (handles TLS fingerprinting, doc_id rotation, etc.)
    private static let cobaltInstances = [
        "https://cobalt-backend.canine.tools/",
        "https://kityune.imput.net/",
        "https://cobalt-api.meowing.de/",
        "https://blossom.imput.net/",
        "https://capi.3kh0.net/"
    ]

    /// Uses cobalt API instances — tries multiple with fallback
    private func extractViaCobalt(url: URL, contentType: InstagramContentType) async throws -> InstagramMediaData {
        let body: [String: Any] = [
            "url": url.absoluteString,
            "videoQuality": "max",
            "filenameStyle": "basic"
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        for instanceURL in Self.cobaltInstances {
            guard let cobaltURL = URL(string: instanceURL) else { continue }

            var request = URLRequest(url: cobaltURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 12
            request.httpBody = bodyData

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                let status = json["status"] as? String
                guard status == "tunnel" || status == "redirect" || status == "stream" else {
                    continue
                }

                if let videoUrlString = json["url"] as? String,
                   let videoURL = URL(string: videoUrlString) {
                    let thumbnailURL: URL?
                    if let thumbStr = json["thumb"] as? String {
                        thumbnailURL = URL(string: thumbStr)
                    } else {
                        thumbnailURL = nil
                    }

                    return InstagramMediaData(
                        originalURL: url,
                        contentType: contentType == .image ? .videoPost : contentType,
                        videoURL: videoURL,
                        thumbnailURL: thumbnailURL,
                        extractedAt: Date()
                    )
                }

                // Check for picker (carousel)
                if let picker = json["picker"] as? [[String: Any]] {
                    return parseCobaltPicker(picker, originalURL: url, contentType: contentType)
                }
            } catch {
                print("InstagramExtractor: Cobalt instance \(instanceURL) failed: \(error.localizedDescription)")
                continue
            }
        }

        throw InstagramExtractionError.couldNotExtract
    }

    /// Parse cobalt's picker response for carousel content
    private func parseCobaltPicker(_ picker: [[String: Any]], originalURL: URL, contentType: InstagramContentType) -> InstagramMediaData {
        var carouselItems: [CarouselItem] = []
        var firstVideoURL: URL?

        for (index, item) in picker.enumerated() {
            guard let urlStr = item["url"] as? String, let itemURL = URL(string: urlStr) else { continue }
            let type = item["type"] as? String
            let isVideo = type == "video"
            let mediaType: CarouselMediaType = isVideo ? .video : .image

            if isVideo && firstVideoURL == nil {
                firstVideoURL = itemURL
            }

            var thumbURL: URL?
            if let thumbStr = item["thumb"] as? String {
                thumbURL = URL(string: thumbStr)
            }

            carouselItems.append(CarouselItem(
                index: index,
                mediaType: mediaType,
                mediaURL: itemURL,
                thumbnailURL: thumbURL
            ))
        }

        return InstagramMediaData(
            originalURL: originalURL,
            contentType: .carousel,
            videoURL: firstVideoURL,
            carouselItems: carouselItems,
            extractedAt: Date()
        )
    }

    // MARK: - Strategy 2: Embed Page Scraping

    /// Fetch the embed page which has less restrictions than the main page
    private func extractFromEmbedPage(shortcode: String, originalURL: URL, contentType: InstagramContentType) async throws -> InstagramMediaData {
        let embedURL = URL(string: "https://www.instagram.com/p/\(shortcode)/embed/captioned/")!
        var request = URLRequest(url: embedURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("iframe", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw InstagramExtractionError.couldNotExtract
        }

        // Try to find video URL in embed page
        // Embed pages often contain the video URL in various formats

        // Pattern 1: "video_url":"..." in embedded JSON
        if let videoURL = extractVideoURLFromJSON(html: html) {
            let thumbnailURL = extractThumbnailFromHTML(html: html)
            let caption = extractCaptionFromEmbed(html: html)
            let author = extractAuthorFromEmbed(html: html)

            return InstagramMediaData(
                originalURL: originalURL,
                contentType: contentType == .image ? .videoPost : contentType,
                videoURL: videoURL,
                thumbnailURL: thumbnailURL,
                authorUsername: author,
                caption: caption,
                extractedAt: Date()
            )
        }

        // Pattern 2: data-video-url attribute
        if let videoMatch = html.range(of: #"data-video-url="([^"]+)""#, options: .regularExpression) {
            let matched = String(html[videoMatch])
            let urlStr = matched
                .replacingOccurrences(of: "data-video-url=\"", with: "")
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "&amp;", with: "&")
            if let videoURL = URL(string: urlStr) {
                return InstagramMediaData(
                    originalURL: originalURL,
                    contentType: contentType == .image ? .videoPost : contentType,
                    videoURL: videoURL,
                    thumbnailURL: extractThumbnailFromHTML(html: html),
                    extractedAt: Date()
                )
            }
        }

        // Pattern 3: EmbeddedMediaImage with video class
        if let srcMatch = html.range(of: #"class="EmbeddedMediaImage"[^>]*src="([^"]+)""#, options: .regularExpression) {
            let matched = String(html[srcMatch])
            if let srcStart = matched.range(of: "src=\"") {
                let urlStr = String(matched[srcStart.upperBound...])
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "&amp;", with: "&")
                if let thumbnailURL = URL(string: urlStr) {
                    // Got thumbnail at least — return with no video (better than nothing)
                    return InstagramMediaData(
                        originalURL: originalURL,
                        contentType: contentType,
                        thumbnailURL: thumbnailURL,
                        extractedAt: Date()
                    )
                }
            }
        }

        throw InstagramExtractionError.couldNotExtract
    }

    // MARK: - Strategy 3: GraphQL API

    /// Extract via Instagram's internal GraphQL API (correct endpoint: /api/graphql)
    private func extractFromGraphQL(url: URL, contentType: InstagramContentType) async throws -> InstagramMediaData {
        guard let shortcode = extractShortcode(from: url) else {
            throw InstagramExtractionError.couldNotExtract
        }

        let graphqlURL = URL(string: "https://www.instagram.com/api/graphql")!
        var request = URLRequest(url: graphqlURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("936619743392459", forHTTPHeaderField: "X-IG-App-ID")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("1", forHTTPHeaderField: "Sec-GPC")
        request.timeoutInterval = 10

        let variables = "{\"shortcode\":\"\(shortcode)\"}"
        let docId = "8845758582119845"
        let bodyString = "variables=\(variables.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? variables)&doc_id=\(docId)"
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw InstagramExtractionError.couldNotExtract
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let media = dataObj["xdt_shortcode_media"] as? [String: Any] else {
            throw InstagramExtractionError.couldNotExtract
        }

        return try parseMediaObject(media, originalURL: url, baseType: contentType)
    }

    // MARK: - Strategy 4: HTML Page Fetching + Multiple Parse Strategies

    private func extractFromHTMLPage(url: URL, contentType: InstagramContentType) async throws -> InstagramMediaData {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("?1", forHTTPHeaderField: "Sec-Fetch-User")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstagramExtractionError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200: break
        case 404: throw InstagramExtractionError.deletedContent
        case 429: throw InstagramExtractionError.rateLimited
        case 401, 403: throw InstagramExtractionError.privateContent
        default: throw InstagramExtractionError.invalidResponse
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw InstagramExtractionError.invalidResponse
        }

        // Try LD+JSON
        if let mediaData = try? extractFromLDJSON(html: html, originalURL: url, contentType: contentType) {
            return mediaData
        }

        // Try og:video meta tag
        if let mediaData = try? extractFromOGVideo(html: html, originalURL: url, contentType: contentType) {
            return mediaData
        }

        // Try _sharedData / __additionalDataLoaded
        if let mediaData = try? extractFromSharedData(html: html, originalURL: url, contentType: contentType) {
            return mediaData
        }

        // Try regex for video_url in page source
        if let mediaData = try? extractFromVideoURL(html: html, originalURL: url, contentType: contentType) {
            return mediaData
        }

        throw InstagramExtractionError.couldNotExtract
    }

    // MARK: - HTML Parse Strategies

    /// Parse from LD+JSON structured data
    private func extractFromLDJSON(html: String, originalURL: URL, contentType: InstagramContentType) throws -> InstagramMediaData {
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
            duration = parseDuration(durationStr)
        } else {
            duration = nil
        }

        let caption = json["caption"] as? String ?? json["description"] as? String
        let author = (json["author"] as? [String: Any])?["name"] as? String
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

    /// Parse from og:video meta tag
    private func extractFromOGVideo(html: String, originalURL: URL, contentType: InstagramContentType) throws -> InstagramMediaData {
        guard let ogVideoMatch = html.range(of: #"<meta[^>]+property="og:video"[^>]+content="([^"]+)""#, options: .regularExpression) else {
            throw InstagramExtractionError.couldNotExtract
        }

        let matched = String(html[ogVideoMatch])
        guard let contentStart = matched.range(of: "content=\"") else {
            throw InstagramExtractionError.couldNotExtract
        }
        let afterContent = String(matched[contentStart.upperBound...])
        let urlString = afterContent.components(separatedBy: "\"").first?
            .replacingOccurrences(of: "&amp;", with: "&") ?? ""

        guard !urlString.isEmpty, let videoURL = URL(string: urlString) else {
            throw InstagramExtractionError.couldNotExtract
        }

        let thumbnailURL = extractThumbnailFromHTML(html: html)

        return InstagramMediaData(
            originalURL: originalURL,
            contentType: .videoPost,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            extractedAt: Date()
        )
    }

    /// Parse from window._sharedData or __additionalDataLoaded
    private func extractFromSharedData(html: String, originalURL: URL, contentType: InstagramContentType) throws -> InstagramMediaData {
        var jsonString: String?

        if let sharedDataMatch = html.range(of: #"window\._sharedData\s*=\s*(\{.+?\});"#, options: .regularExpression) {
            let matched = String(html[sharedDataMatch])
            jsonString = matched
                .replacingOccurrences(of: #"window\._sharedData\s*=\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: ";$", with: "", options: .regularExpression)
        }

        if jsonString == nil, let additionalMatch = html.range(of: #"window\.__additionalDataLoaded\s*\(\s*['\"].*?['\"]\s*,\s*(\{.+?\})\s*\)"#, options: .regularExpression) {
            let matched = String(html[additionalMatch])
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

        if let entryData = parsed["entry_data"] as? [String: Any] {
            if let postPage = entryData["PostPage"] as? [[String: Any]],
               let first = postPage.first,
               let graphql = first["graphql"] as? [String: Any],
               let media = graphql["shortcode_media"] as? [String: Any] {
                return try parseMediaObject(media, originalURL: originalURL, baseType: contentType)
            }

            if let reelMedia = entryData["ReelMedia"] as? [[String: Any]],
               let first = reelMedia.first {
                return try parseMediaObject(first, originalURL: originalURL, baseType: .reel)
            }
        }

        throw InstagramExtractionError.couldNotExtract
    }

    /// Regex fallback for video_url in page source
    private func extractFromVideoURL(html: String, originalURL: URL, contentType: InstagramContentType) throws -> InstagramMediaData {
        guard let videoUrlMatch = html.range(of: #""video_url"\s*:\s*"([^"]+)""#, options: .regularExpression) else {
            throw InstagramExtractionError.couldNotExtract
        }

        let matched = String(html[videoUrlMatch])
        let videoUrlString = matched
            .replacingOccurrences(of: #""video_url"\s*:\s*""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\"$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\u0026", with: "&")

        guard let videoURL = URL(string: videoUrlString) else {
            throw InstagramExtractionError.couldNotExtract
        }

        var thumbnailURL: URL?
        if let thumbMatch = html.range(of: #""display_url"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let thumbMatched = String(html[thumbMatch])
            let thumbString = thumbMatched
                .replacingOccurrences(of: #""display_url"\s*:\s*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\"$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\u0026", with: "&")
            thumbnailURL = URL(string: thumbString)
        }

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

    // MARK: - Shortcode Extraction

    /// Extract shortcode from Instagram URL path (/reel/ABC123/ or /p/ABC123/)
    func extractShortcode(from url: URL) -> String? {
        let path = url.path
        let patterns = ["/reel/", "/reels/", "/p/"]

        for pattern in patterns {
            if let range = path.range(of: pattern) {
                let after = path[range.upperBound...]
                let shortcode = after.prefix(while: { $0 != "/" && $0 != "?" })
                if !shortcode.isEmpty {
                    return String(shortcode)
                }
            }
        }
        return nil
    }

    // MARK: - Media Object Parser

    func parseMediaObject(_ media: [String: Any], originalURL: URL, baseType: InstagramContentType) throws -> InstagramMediaData {
        let isVideo = media["is_video"] as? Bool ?? false

        var videoURL: URL?
        if isVideo, let videoUrlString = media["video_url"] as? String {
            videoURL = URL(string: videoUrlString)
        }

        var thumbnailURL: URL?
        if let displayUrl = media["display_url"] as? String {
            thumbnailURL = URL(string: displayUrl)
        }

        var duration: TimeInterval?
        if let dur = media["video_duration"] as? Double {
            duration = dur
        }

        var author: String?
        if let owner = media["owner"] as? [String: Any] {
            author = owner["username"] as? String
        }

        var caption: String?
        if let edgeMediaToCaption = media["edge_media_to_caption"] as? [String: Any],
           let edges = edgeMediaToCaption["edges"] as? [[String: Any]],
           let first = edges.first,
           let node = first["node"] as? [String: Any] {
            caption = node["text"] as? String
        }

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

    // MARK: - HTML Parse Helpers

    /// Extract video_url from JSON embedded in HTML
    private func extractVideoURLFromJSON(html: String) -> URL? {
        // Try "video_url":"..." pattern (most common in embed pages)
        if let match = html.range(of: #""video_url"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let matched = String(html[match])
            let urlStr = matched
                .replacingOccurrences(of: #""video_url"\s*:\s*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\"$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\u0026", with: "&")
                .replacingOccurrences(of: "\\/", with: "/")
            return URL(string: urlStr)
        }

        // Try contentUrl in JSON-LD
        if let match = html.range(of: #""contentUrl"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let matched = String(html[match])
            let urlStr = matched
                .replacingOccurrences(of: #""contentUrl"\s*:\s*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\"$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\u0026", with: "&")
            return URL(string: urlStr)
        }

        return nil
    }

    /// Extract thumbnail URL from HTML meta tags
    private func extractThumbnailFromHTML(html: String) -> URL? {
        // og:image
        if let match = html.range(of: #"<meta[^>]+property="og:image"[^>]+content="([^"]+)""#, options: .regularExpression) {
            let matched = String(html[match])
            if let contentStart = matched.range(of: "content=\"") {
                let urlStr = String(matched[contentStart.upperBound...])
                    .components(separatedBy: "\"").first?
                    .replacingOccurrences(of: "&amp;", with: "&") ?? ""
                return URL(string: urlStr)
            }
        }

        // display_url in JSON
        if let match = html.range(of: #""display_url"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let matched = String(html[match])
            let urlStr = matched
                .replacingOccurrences(of: #""display_url"\s*:\s*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\"$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\u0026", with: "&")
            return URL(string: urlStr)
        }

        return nil
    }

    /// Extract caption from embed page
    private func extractCaptionFromEmbed(html: String) -> String? {
        if let match = html.range(of: #"<div class="Caption"[^>]*>.*?<span[^>]*>(.*?)</span>"#, options: .regularExpression) {
            let matched = String(html[match])
            // Strip HTML tags
            return matched.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Extract author from embed page
    private func extractAuthorFromEmbed(html: String) -> String? {
        // Look for username in embed
        if let match = html.range(of: #""username"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let matched = String(html[match])
            return matched
                .replacingOccurrences(of: #""username"\s*:\s*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\"", with: "")
        }
        return nil
    }

    // MARK: - Duration Parser

    /// Parse ISO 8601 duration string (e.g., "PT30S" -> 30.0)
    private func parseDuration(_ iso8601: String) -> TimeInterval? {
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
