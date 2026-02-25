// CosmoOS/SwipeFile/Instagram/InstagramExtractor.swift
// Extracts video URLs and metadata from Instagram pages
// Uses cobalt.tools API (same server-proxy pattern as SnapInsta) + embed page + GraphQL fallbacks

import Foundation

/// Extracts media data from Instagram URLs
/// Fallback chain: Cobalt API → Embed Page → GraphQL → HTML strategies → basic data
@MainActor
final class InstagramExtractor: Sendable {
    static let shared = InstagramExtractor()
    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Main Extraction

    /// Extract media data from an Instagram URL
    func extract(from url: URL) async throws -> InstagramMediaData {
        let normalizedURL = normalizeInstagramURL(url)
        let contentType = detectContentType(from: normalizedURL)
        var bestPartialResult: InstagramMediaData?

        if normalizedURL != url {
            print("InstagramExtractor: Normalized URL \(url.absoluteString) -> \(normalizedURL.absoluteString)")
        }

        // Strategy 1: Cobalt API (server-side proxy — same pattern as SnapInsta)
        do {
            let mediaData = try await extractViaCobalt(url: normalizedURL, contentType: contentType)
            if shouldReturnImmediately(mediaData, requestedType: contentType) {
                print("InstagramExtractor: Cobalt API succeeded")
                return mediaData
            }
            bestPartialResult = betterPartialResult(current: bestPartialResult, candidate: mediaData)
            print("InstagramExtractor: Cobalt API returned partial media (no playable video yet), continuing")
        } catch {
            print("InstagramExtractor: Cobalt API failed: \(error.localizedDescription)")
        }

        // Strategy 2: Embed page scraping (no auth needed, works for public content)
        if let shortcode = extractShortcode(from: normalizedURL) {
            do {
                let mediaData = try await extractFromEmbedPage(shortcode: shortcode, originalURL: normalizedURL, contentType: contentType)
                if shouldReturnImmediately(mediaData, requestedType: contentType) {
                    print("InstagramExtractor: Embed page succeeded")
                    return mediaData
                }
                bestPartialResult = betterPartialResult(current: bestPartialResult, candidate: mediaData)
                print("InstagramExtractor: Embed page returned partial media (no playable video yet), continuing")
            } catch {
                print("InstagramExtractor: Embed page failed: \(error.localizedDescription)")
            }
        }

        // Strategy 3: GraphQL API at /api/graphql (correct endpoint)
        do {
            let mediaData = try await extractFromGraphQL(url: normalizedURL, contentType: contentType)
            if shouldReturnImmediately(mediaData, requestedType: contentType) {
                print("InstagramExtractor: GraphQL succeeded")
                return mediaData
            }
            bestPartialResult = betterPartialResult(current: bestPartialResult, candidate: mediaData)
            print("InstagramExtractor: GraphQL returned partial media (no playable video yet), continuing")
        } catch {
            print("InstagramExtractor: GraphQL failed: \(error.localizedDescription)")
        }

        // Strategy 4: Fetch HTML page and try multiple parse strategies
        do {
            let mediaData = try await extractFromHTMLPage(url: normalizedURL, contentType: contentType)
            if shouldReturnImmediately(mediaData, requestedType: contentType) {
                print("InstagramExtractor: HTML page succeeded")
                return mediaData
            }
            bestPartialResult = betterPartialResult(current: bestPartialResult, candidate: mediaData)
            print("InstagramExtractor: HTML page returned partial media (no playable video yet), continuing")
        } catch {
            print("InstagramExtractor: HTML page failed: \(error.localizedDescription)")
        }

        // Strategy 5: yt-dlp extractor fallback (most robust for public reels)
        do {
            let mediaData = try await extractViaYtDlp(url: normalizedURL, contentType: contentType)
            if shouldReturnImmediately(mediaData, requestedType: contentType) {
                print("InstagramExtractor: yt-dlp fallback succeeded")
                return mediaData
            }
            bestPartialResult = betterPartialResult(current: bestPartialResult, candidate: mediaData)
            print("InstagramExtractor: yt-dlp fallback returned partial media (no playable video yet)")
        } catch {
            print("InstagramExtractor: yt-dlp fallback failed: \(error.localizedDescription)")
        }

        if let bestPartialResult {
            print("InstagramExtractor: Returning best partial media result for \(normalizedURL)")
            return bestPartialResult
        }

        print("InstagramExtractor: All strategies failed for \(normalizedURL)")

        // If all extraction fails, return basic data with the URL
        return InstagramMediaData(
            originalURL: normalizedURL,
            contentType: contentType,
            extractedAt: Date()
        )
    }

    private func shouldReturnImmediately(
        _ mediaData: InstagramMediaData,
        requestedType: InstagramContentType
    ) -> Bool {
        // If any strategy found carousel items, always accept — definitive result
        if !(mediaData.carouselItems?.isEmpty ?? true) { return true }

        switch requestedType {
        case .reel, .videoPost:
            return mediaData.videoURL != nil
        case .carousel:
            return mediaData.videoURL != nil
        case .image:
            // For /p/ URLs, thumbnail alone isn't enough — the post might be
            // a carousel where only the first image was extracted by a fast strategy.
            // Keep trying strategies until we find video, carousel items, or exhaust all.
            return mediaData.videoURL != nil
        case .story:
            return mediaData.thumbnailURL != nil ||
                !(mediaData.caption?.isEmpty ?? true) ||
                !(mediaData.authorUsername?.isEmpty ?? true)
        }
    }

    private func betterPartialResult(
        current: InstagramMediaData?,
        candidate: InstagramMediaData
    ) -> InstagramMediaData {
        guard let current else { return candidate }
        return partialScore(candidate) >= partialScore(current) ? candidate : current
    }

    private func partialScore(_ mediaData: InstagramMediaData) -> Int {
        var score = 0
        if mediaData.videoURL != nil { score += 100 }
        if mediaData.thumbnailURL != nil { score += 20 }
        if !(mediaData.caption?.isEmpty ?? true) { score += 10 }
        if !(mediaData.authorUsername?.isEmpty ?? true) { score += 5 }
        score += (mediaData.carouselItems?.count ?? 0) * 3
        return score
    }

    // MARK: - Content Type Detection

    private func detectContentType(from url: URL) -> InstagramContentType {
        let path = url.path.lowercased()

        if path.contains("/reel/") || path.contains("/reels/") || path.contains("/share/reel/") {
            return .reel
        }
        if path.contains("/stories/") {
            return .story
        }
        if path.contains("/p/") || path.contains("/share/p/") {
            // img_index query parameter indicates carousel content
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               components.queryItems?.contains(where: { $0.name == "img_index" }) == true {
                return .carousel
            }
            return .image
        }

        return .image
    }

    /// Normalize Instagram URLs so extraction/cache work across copied variants.
    /// Handles share links, query-heavy URLs, and redirect wrappers.
    private func normalizeInstagramURL(_ input: URL) -> URL {
        // Instagram redirect wrapper: https://l.instagram.com/?u=<encoded target>
        if let host = input.host?.lowercased(),
           host == "l.instagram.com",
           let components = URLComponents(url: input, resolvingAgainstBaseURL: false),
           let encoded = components.queryItems?.first(where: { $0.name == "u" })?.value,
           let decoded = encoded.removingPercentEncoding,
           let decodedURL = URL(string: decoded) {
            return normalizeInstagramURL(decodedURL)
        }

        guard var components = URLComponents(url: input, resolvingAgainstBaseURL: false) else {
            return input
        }

        components.scheme = "https"
        if let host = components.host?.lowercased(),
           host.contains("instagram.com") {
            components.host = "www.instagram.com"
        }

        var path = components.path
        if let match = path.range(of: #"/share/reel/([A-Za-z0-9_-]+)"#, options: .regularExpression) {
            let matched = String(path[match])
            let shortcode = matched.replacingOccurrences(
                of: #"/share/reel/([A-Za-z0-9_-]+)"#,
                with: "$1",
                options: .regularExpression
            )
            path = "/reel/\(shortcode)/"
        } else if let match = path.range(of: #"/share/p/([A-Za-z0-9_-]+)"#, options: .regularExpression) {
            let matched = String(path[match])
            let shortcode = matched.replacingOccurrences(
                of: #"/share/p/([A-Za-z0-9_-]+)"#,
                with: "$1",
                options: .regularExpression
            )
            path = "/p/\(shortcode)/"
        }

        if path.contains("/reels/") {
            path = path.replacingOccurrences(of: "/reels/", with: "/reel/")
        }

        components.path = path
        components.query = nil
        components.fragment = nil

        return components.url ?? input
    }

    // MARK: - Strategy 1: Cobalt API (like SnapInsta server-side proxy)

    /// Cobalt instance URLs — tried in order (handles TLS fingerprinting, doc_id rotation, etc.)
    private static let cobaltInstances = [
        "https://co.eepy.today/",
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

                // Check for picker (carousel) FIRST — status is "picker" for carousels
                if status == "picker",
                   let picker = json["picker"] as? [[String: Any]] {
                    return parseCobaltPicker(picker, originalURL: url, contentType: contentType)
                }

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
        let preferredPaths: [String] = {
            switch contentType {
            case .reel:
                return [
                    "/reel/\(shortcode)/embed/captioned/",
                    "/reel/\(shortcode)/embed/",
                    "/p/\(shortcode)/embed/captioned/",
                    "/p/\(shortcode)/embed/"
                ]
            default:
                return [
                    "/p/\(shortcode)/embed/captioned/",
                    "/p/\(shortcode)/embed/",
                    "/reel/\(shortcode)/embed/captioned/",
                    "/reel/\(shortcode)/embed/"
                ]
            }
        }()

        for path in preferredPaths {
            guard let embedURL = URL(string: "https://www.instagram.com\(path)") else { continue }

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

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                      let html = String(data: data, encoding: .utf8) else {
                    continue
                }

                if let mediaData = parseEmbedHTML(
                    html: html,
                    originalURL: originalURL,
                    contentType: contentType
                ) {
                    return mediaData
                }
            } catch {
                continue
            }
        }

        throw InstagramExtractionError.couldNotExtract
    }

    private func parseEmbedHTML(
        html: String,
        originalURL: URL,
        contentType: InstagramContentType
    ) -> InstagramMediaData? {
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
                    return InstagramMediaData(
                        originalURL: originalURL,
                        contentType: contentType,
                        thumbnailURL: thumbnailURL,
                        extractedAt: Date()
                    )
                }
            }
        }

        return nil
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
        let patterns = ["/reel/", "/reels/", "/p/", "/share/reel/", "/share/p/"]

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

    // MARK: - Strategy 5: yt-dlp Fallback

    private func extractViaYtDlp(url: URL, contentType: InstagramContentType) async throws -> InstagramMediaData {
        guard let ytdlpPath = findYtDlp() else {
            throw InstagramExtractionError.couldNotExtract
        }

        // Get metadata (caption, author, thumbnail, duration) via JSON dump
        let json = try await runYtDlpDump(ytdlpPath: ytdlpPath, url: url)

        // For carousels with multiple entries, use URL-based approach
        if let entries = json["entries"] as? [[String: Any]], !entries.isEmpty {
            return parseYtDlpResult(json, originalURL: url, contentType: contentType)
        }

        // For single videos: download via yt-dlp to get a proper MP4 with audio+video merged.
        // The JSON dump only gives raw CDN stream URLs which may be video-only DASH segments
        // or WebM/VP9 format that macOS AVFoundation can't play.
        let shortcode = extractShortcode(from: url) ?? ytDlpStableHash(url.absoluteString)
        let localURL = try await downloadViaYtDlp(ytdlpPath: ytdlpPath, url: url, cacheKey: shortcode)

        let author = resolveYtDlpAuthor(json)
        let caption = json["description"] as? String
        let thumbnail = (json["thumbnail"] as? String).flatMap(URL.init(string:))
        let duration = json["duration"] as? TimeInterval

        return InstagramMediaData(
            originalURL: url,
            contentType: contentType == .reel ? .reel : .videoPost,
            videoURL: localURL,
            thumbnailURL: thumbnail,
            duration: duration,
            authorUsername: author,
            caption: caption,
            extractedAt: Date()
        )
    }

    /// Resolve author from yt-dlp JSON, preferring username over numeric user ID.
    /// Instagram's yt-dlp output sets `uploader_id` to the numeric user ID (e.g. "63181063998")
    /// and `uploader` to the actual username. Also tries `channel` and caption @mention extraction.
    private func resolveYtDlpAuthor(_ json: [String: Any]) -> String? {
        // Prefer uploader (username) over uploader_id (numeric ID)
        let candidates: [String?] = [
            json["uploader"] as? String,
            json["channel"] as? String,
            json["uploader_id"] as? String
        ]

        for candidate in candidates {
            guard let value = candidate, !value.isEmpty else { continue }
            // Skip purely numeric IDs (Instagram internal user IDs)
            if value.allSatisfy(\.isNumber) { continue }
            return value
        }

        // Last resort: try to extract @username from caption
        if let caption = json["description"] as? String,
           let match = caption.range(of: #"@([A-Za-z0-9_.]+)"#, options: .regularExpression) {
            return String(caption[match]).replacingOccurrences(of: "@", with: "")
        }

        return nil
    }

    /// Download video via yt-dlp with proper format merging (audio+video → MP4).
    /// Uses format selection that prefers MP4 video + M4A audio, falling back to combined MP4.
    private func downloadViaYtDlp(ytdlpPath: String, url: URL, cacheKey: String) async throws -> URL {
        let cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo/InstagramVideoCache", isDirectory: true)
        try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let destination = cacheDir.appendingPathComponent("ig-\(cacheKey).mp4")

        // If cached file exists and is a valid MP4, skip download
        if fileManager.fileExists(atPath: destination.path),
           let attrs = try? fileManager.attributesOfItem(atPath: destination.path),
           let size = attrs[.size] as? NSNumber, size.int64Value > 10000,
           isValidMP4(at: destination) {
            return destination
        }

        // Remove any invalid remnant (e.g. WebM saved as .mp4 from old code path)
        try? fileManager.removeItem(at: destination)

        let outputTemplate = cacheDir.appendingPathComponent("ig-\(cacheKey).%(ext)s").path

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ytdlpPath)
                process.arguments = [
                    "-f", "bv*[vcodec^=avc1][ext=mp4]+ba[ext=m4a]/bv*[vcodec^=avc1]+ba/b[ext=mp4][vcodec^=avc1]/bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b",
                    "-S", "vcodec:h264,ext:mp4:m4a",
                    "--merge-output-format", "mp4",
                    "--no-playlist",
                    "--no-warnings",
                    "-o", outputTemplate,
                    url.absoluteString
                ]

                var env = ProcessInfo.processInfo.environment
                let homebrewPaths = "/opt/homebrew/bin:/usr/local/bin"
                if let existingPath = env["PATH"] {
                    env["PATH"] = "\(homebrewPaths):\(existingPath)"
                } else {
                    env["PATH"] = homebrewPaths
                }
                process.environment = env

                let errorPipe = Pipe()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorText = String(data: errorData, encoding: .utf8) ?? ""
                        if !errorText.isEmpty {
                            print("InstagramExtractor: yt-dlp download error: \(errorText.prefix(300))")
                        }
                        continuation.resume(throwing: InstagramExtractionError.couldNotExtract)
                        return
                    }

                    // Check for the expected .mp4 output
                    if FileManager.default.fileExists(atPath: destination.path) {
                        if self.isValidMP4(at: destination) {
                            print("InstagramExtractor: yt-dlp downloaded \(destination.lastPathComponent)")
                            continuation.resume(returning: destination)
                        } else if self.transcodeToH264(source: destination, destination: destination) {
                            print("InstagramExtractor: yt-dlp downloaded + transcoded \(destination.lastPathComponent)")
                            continuation.resume(returning: destination)
                        } else {
                            print("InstagramExtractor: Downloaded video has unsupported codec and transcode failed")
                            continuation.resume(throwing: InstagramExtractionError.couldNotExtract)
                        }
                        return
                    }

                    // Fallback: look for any file matching ig-{cacheKey}.*
                    if let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil),
                       let match = files.first(where: { $0.lastPathComponent.hasPrefix("ig-\(cacheKey).") }) {
                        if self.isValidMP4(at: match) {
                            print("InstagramExtractor: yt-dlp downloaded \(match.lastPathComponent)")
                            continuation.resume(returning: match)
                        } else if self.transcodeToH264(source: match, destination: destination) {
                            print("InstagramExtractor: yt-dlp downloaded + transcoded \(destination.lastPathComponent)")
                            continuation.resume(returning: destination)
                        } else {
                            // Return the file anyway as last resort
                            print("InstagramExtractor: Downloaded video may have unsupported codec")
                            continuation.resume(returning: match)
                        }
                        return
                    }

                    continuation.resume(throwing: InstagramExtractionError.couldNotExtract)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Validate that a file is an MP4 container with a codec AVFoundation can decode.
    /// Checks ftyp header AND scans for codec atoms — rejects VP9/AV1 which produce
    /// black frames on macOS (err=-12430 kFigMediaPlayerError_NoDecodableTrack).
    private func isValidMP4(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        let headerData = handle.readData(ofLength: 100_000)
        handle.closeFile()
        guard headerData.count >= 8 else { return false }

        // Must be a valid MP4 container (ftyp box)
        let ftyp = String(data: headerData[4..<8], encoding: .ascii)
        guard ftyp == "ftyp" else { return false }

        // Scan for video codec identifiers in moov/trak/stsd boxes
        let bytes = [UInt8](headerData)
        let len = bytes.count - 3
        var hasDecodable = false
        var hasUnsupported = false

        for i in 0..<len {
            let b0 = bytes[i], b1 = bytes[i+1], b2 = bytes[i+2], b3 = bytes[i+3]
            // H.264 "avc1" (0x61766331)
            if b0 == 0x61 && b1 == 0x76 && b2 == 0x63 && b3 == 0x31 { hasDecodable = true }
            // HEVC "hvc1" (0x68766331) / "hev1" (0x68657631)
            if b0 == 0x68 && b1 == 0x76 && b2 == 0x63 && b3 == 0x31 { hasDecodable = true }
            if b0 == 0x68 && b1 == 0x65 && b2 == 0x76 && b3 == 0x31 { hasDecodable = true }
            // VP9 "vp09" (0x76703039) — unsupported by AVFoundation
            if b0 == 0x76 && b1 == 0x70 && b2 == 0x30 && b3 == 0x39 { hasUnsupported = true }
            // AV1 "av01" (0x61763031) — unsupported by AVFoundation
            if b0 == 0x61 && b1 == 0x76 && b2 == 0x30 && b3 == 0x31 { hasUnsupported = true }
        }

        if hasDecodable { return true }
        if hasUnsupported {
            print("InstagramExtractor: Detected unsupported codec (VP9/AV1) in \(url.lastPathComponent)")
            return false
        }
        // Couldn't determine codec from first 100KB — assume valid (ftyp passed)
        return true
    }

    /// Find ffmpeg binary for transcoding VP9/AV1 to H.264
    private func findFfmpeg() -> String? {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in paths where fileManager.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    /// Transcode a non-H.264 video to H.264+AAC using ffmpeg.
    /// Writes to a temp file then replaces the destination.
    private func transcodeToH264(source: URL, destination: URL) -> Bool {
        guard let ffmpegPath = findFfmpeg() else {
            print("InstagramExtractor: ffmpeg not found — cannot transcode VP9/AV1 video")
            return false
        }

        let tempOutput = destination.deletingLastPathComponent()
            .appendingPathComponent("transcode_temp_\(UUID().uuidString.prefix(8)).mp4")
        try? fileManager.removeItem(at: tempOutput)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", source.path,
            "-c:v", "libx264",
            "-preset", "fast",
            "-crf", "23",
            "-c:a", "aac",
            "-b:a", "128k",
            "-movflags", "+faststart",
            "-y",
            tempOutput.path
        ]

        var env = ProcessInfo.processInfo.environment
        let homebrewPaths = "/opt/homebrew/bin:/usr/local/bin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(homebrewPaths):\(existingPath)"
        } else {
            env["PATH"] = homebrewPaths
        }
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  fileManager.fileExists(atPath: tempOutput.path) else {
                print("InstagramExtractor: ffmpeg transcode failed (exit \(process.terminationStatus))")
                try? fileManager.removeItem(at: tempOutput)
                return false
            }

            // Replace source and destination with transcoded file
            if source != destination { try? fileManager.removeItem(at: source) }
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: tempOutput, to: destination)
            print("InstagramExtractor: Transcoded VP9/AV1 → H.264 (\(destination.lastPathComponent))")
            return true
        } catch {
            print("InstagramExtractor: ffmpeg transcode error: \(error.localizedDescription)")
            try? fileManager.removeItem(at: tempOutput)
            return false
        }
    }

    private func ytDlpStableHash(_ input: String) -> String {
        var hash: UInt64 = 5381
        for scalar in input.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return String(hash, radix: 16)
    }

    private func runYtDlpDump(ytdlpPath: String, url: URL) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ytdlpPath)
                process.arguments = [
                    "--dump-single-json",
                    "--skip-download",
                    "--no-playlist",
                    "--no-warnings",
                    url.absoluteString
                ]

                var env = ProcessInfo.processInfo.environment
                let homebrewPaths = "/opt/homebrew/bin:/usr/local/bin"
                if let existingPath = env["PATH"] {
                    env["PATH"] = "\(homebrewPaths):\(existingPath)"
                } else {
                    env["PATH"] = homebrewPaths
                }
                process.environment = env

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorText = String(data: errorData, encoding: .utf8) ?? ""

                    guard process.terminationStatus == 0 else {
                        continuation.resume(throwing: InstagramExtractionError.couldNotExtract)
                        if !errorText.isEmpty {
                            print("InstagramExtractor: yt-dlp error: \(errorText.prefix(250))")
                        }
                        return
                    }

                    guard let json = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
                        continuation.resume(throwing: InstagramExtractionError.invalidResponse)
                        return
                    }

                    continuation.resume(returning: json)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func parseYtDlpResult(
        _ json: [String: Any],
        originalURL: URL,
        contentType: InstagramContentType
    ) -> InstagramMediaData {
        let author = resolveYtDlpAuthor(json)
        let caption = json["description"] as? String
        let thumbnail = (json["thumbnail"] as? String).flatMap(URL.init(string:))
        let duration = json["duration"] as? TimeInterval

        if let entries = json["entries"] as? [[String: Any]], !entries.isEmpty {
            var carouselItems: [CarouselItem] = []
            var firstVideoURL: URL?
            var fallbackThumb = thumbnail

            for (index, entry) in entries.enumerated() {
                guard let itemURL = extractYtDlpMediaURL(from: entry) else { continue }

                let ext = (entry["ext"] as? String ?? "").lowercased()
                let isVideo = ext == "mp4" || ext == "webm" || (entry["duration"] as? Double ?? 0) > 0
                let mediaType: CarouselMediaType = isVideo ? .video : .image

                if firstVideoURL == nil && isVideo {
                    firstVideoURL = itemURL
                }

                let thumb = (entry["thumbnail"] as? String).flatMap(URL.init(string:))
                if fallbackThumb == nil {
                    fallbackThumb = thumb
                }

                carouselItems.append(
                    CarouselItem(
                        index: index,
                        mediaType: mediaType,
                        mediaURL: itemURL,
                        thumbnailURL: thumb,
                        duration: entry["duration"] as? TimeInterval
                    )
                )
            }

            return InstagramMediaData(
                originalURL: originalURL,
                contentType: .carousel,
                videoURL: firstVideoURL,
                thumbnailURL: fallbackThumb,
                authorUsername: author,
                caption: caption,
                carouselItems: carouselItems.isEmpty ? nil : carouselItems,
                extractedAt: Date()
            )
        }

        let directURL = extractYtDlpMediaURL(from: json)
        let finalType: InstagramContentType
        if contentType == .reel {
            finalType = .reel
        } else {
            finalType = directURL == nil ? contentType : .videoPost
        }

        return InstagramMediaData(
            originalURL: originalURL,
            contentType: finalType,
            videoURL: directURL,
            thumbnailURL: thumbnail,
            duration: duration,
            authorUsername: author,
            caption: caption,
            extractedAt: Date()
        )
    }

    private func extractYtDlpMediaURL(from payload: [String: Any]) -> URL? {
        if let urlString = payload["url"] as? String,
           let direct = URL(string: urlString),
           direct.scheme?.hasPrefix("http") == true {
            return direct
        }

        if let requested = payload["requested_downloads"] as? [[String: Any]],
           let first = requested.first,
           let urlString = first["url"] as? String {
            return URL(string: urlString)
        }

        if let formats = payload["formats"] as? [[String: Any]] {
            let sortedFormats = formats.sorted {
                let lhsHeight = $0["height"] as? Int ?? 0
                let rhsHeight = $1["height"] as? Int ?? 0
                return lhsHeight > rhsHeight
            }

            for format in sortedFormats {
                let ext = (format["ext"] as? String ?? "").lowercased()
                guard ext == "mp4" || ext == "webm" else { continue }
                guard let urlString = format["url"] as? String else { continue }
                if let mediaURL = URL(string: urlString) {
                    return mediaURL
                }
            }
        }

        return nil
    }

    private func findYtDlp() -> String? {
        let paths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]

        for path in paths where fileManager.fileExists(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yt-dlp"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (output?.isEmpty == false) ? output : nil
        } catch {
            return nil
        }
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
        let cacheKey = normalizedCacheKey(for: originalURL)

        // Check cache
        if let cached = cache[cacheKey], !cached.isExpired {
            if isUsableCachedResult(cached) {
                return cached
            }
            print("InstagramCache: Cached media is incomplete for \(cacheKey.absoluteString), refreshing")
        }

        // Re-extract if expired or missing
        let fresh = try await InstagramExtractor.shared.extract(from: originalURL)
        cache[cacheKey] = fresh
        return fresh
    }

    /// Preemptively refresh media before expiration
    func preemptiveRefresh(for originalURL: URL) {
        let cacheKey = normalizedCacheKey(for: originalURL)
        Task {
            do {
                let fresh = try await InstagramExtractor.shared.extract(from: originalURL)
                cache[cacheKey] = fresh
            } catch {
                print("InstagramCache: Preemptive refresh failed: \(error)")
            }
        }
    }

    /// Clear cached data for a URL
    func invalidate(for originalURL: URL) {
        cache.removeValue(forKey: normalizedCacheKey(for: originalURL))
    }

    /// Clear all cached data
    func clearAll() {
        cache.removeAll()
    }

    private func isUsableCachedResult(_ mediaData: InstagramMediaData) -> Bool {
        // Carousel items mean we have a quality extraction
        if !(mediaData.carouselItems?.isEmpty ?? true) { return true }

        switch mediaData.contentType {
        case .reel, .videoPost:
            return mediaData.videoURL != nil
        case .carousel:
            return mediaData.videoURL != nil
        case .image:
            // For image posts, require more than just a thumbnail — a minimal result
            // from the embed page may have missed carousel slides. Re-extract if we
            // only have a thumbnail without caption/author context.
            if mediaData.videoURL != nil { return true }
            return mediaData.thumbnailURL != nil &&
                (!(mediaData.caption?.isEmpty ?? true) || !(mediaData.authorUsername?.isEmpty ?? true))
        case .story:
            return mediaData.thumbnailURL != nil ||
                !(mediaData.caption?.isEmpty ?? true) ||
                !(mediaData.authorUsername?.isEmpty ?? true)
        }
    }

    private func normalizedCacheKey(for input: URL) -> URL {
        guard var components = URLComponents(url: input, resolvingAgainstBaseURL: false) else {
            return input
        }

        components.scheme = "https"
        if let host = components.host?.lowercased(), host.contains("instagram.com") {
            components.host = "www.instagram.com"
        }

        var path = components.path
        if let match = path.range(of: #"/share/reel/([A-Za-z0-9_-]+)"#, options: .regularExpression) {
            let matched = String(path[match])
            let shortcode = matched.replacingOccurrences(
                of: #"/share/reel/([A-Za-z0-9_-]+)"#,
                with: "$1",
                options: .regularExpression
            )
            path = "/reel/\(shortcode)/"
        } else if let match = path.range(of: #"/share/p/([A-Za-z0-9_-]+)"#, options: .regularExpression) {
            let matched = String(path[match])
            let shortcode = matched.replacingOccurrences(
                of: #"/share/p/([A-Za-z0-9_-]+)"#,
                with: "$1",
                options: .regularExpression
            )
            path = "/p/\(shortcode)/"
        }
        if path.contains("/reels/") {
            path = path.replacingOccurrences(of: "/reels/", with: "/reel/")
        }
        if !path.hasSuffix("/") {
            path += "/"
        }

        components.path = path
        components.query = nil
        components.fragment = nil

        return components.url ?? input
    }
}

// MARK: - Local Video Resolver

/// Resolves remote Instagram CDN URLs to a local downloaded file for reliable playback/transcription.
/// Uses the Instagram shortcode as the cache key so the file persists across CDN URL changes.
enum InstagramVideoLocalCache {
    private static let fileManager = FileManager.default
    private static let cacheDirectory: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Cosmo/InstagramVideoCache", isDirectory: true)
    }()

    /// Resolve a playable URL. If a shortcode is provided, uses it as a stable cache key
    /// so the downloaded file survives across app restarts and CDN URL rotations.
    static func resolvePlayableURL(from sourceURL: URL, shortcode: String? = nil) async -> URL {
        guard !sourceURL.isFileURL else { return sourceURL }

        // If we have a shortcode, check for an existing valid local file first (fast path)
        if let shortcode, !shortcode.isEmpty {
            let localPath = localFilePath(for: shortcode)
            if fileManager.fileExists(atPath: localPath.path),
               let attrs = try? fileManager.attributesOfItem(atPath: localPath.path),
               let size = attrs[.size] as? NSNumber, size.int64Value > 10000,
               isValidMP4(at: localPath) {
                return localPath
            }
        }

        do {
            let cacheKey = shortcode ?? stableHash(sourceURL.absoluteString)
            let local = try await downloadIfNeeded(from: sourceURL, cacheKey: cacheKey)
            return local
        } catch {
            print("InstagramVideoLocalCache: Failed local download (\(error.localizedDescription)); using remote URL")
            return sourceURL
        }
    }

    /// Check if a local video exists for this shortcode (no download, no network).
    /// Validates the file is actually a playable MP4 (rejects WebM or video-only DASH saved as .mp4).
    static func localVideoURL(forShortcode shortcode: String) -> URL? {
        let path = localFilePath(for: shortcode)
        guard fileManager.fileExists(atPath: path.path),
              let attrs = try? fileManager.attributesOfItem(atPath: path.path),
              let size = attrs[.size] as? NSNumber, size.int64Value > 10000,
              isValidMP4(at: path) else {
            return nil
        }
        return path
    }

    /// Validate that a file is an MP4 with a codec AVFoundation can decode.
    /// Rejects VP9/AV1 which cause black frames (err=-12430).
    private static func isValidMP4(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        let headerData = handle.readData(ofLength: 100_000)
        handle.closeFile()
        guard headerData.count >= 8 else { return false }

        let ftyp = String(data: headerData[4..<8], encoding: .ascii)
        guard ftyp == "ftyp" else { return false }

        let bytes = [UInt8](headerData)
        let len = bytes.count - 3
        var hasDecodable = false
        var hasUnsupported = false

        for i in 0..<len {
            let b0 = bytes[i], b1 = bytes[i+1], b2 = bytes[i+2], b3 = bytes[i+3]
            if b0 == 0x61 && b1 == 0x76 && b2 == 0x63 && b3 == 0x31 { hasDecodable = true } // avc1
            if b0 == 0x68 && b1 == 0x76 && b2 == 0x63 && b3 == 0x31 { hasDecodable = true } // hvc1
            if b0 == 0x68 && b1 == 0x65 && b2 == 0x76 && b3 == 0x31 { hasDecodable = true } // hev1
            if b0 == 0x76 && b1 == 0x70 && b2 == 0x30 && b3 == 0x39 { hasUnsupported = true } // vp09
            if b0 == 0x61 && b1 == 0x76 && b2 == 0x30 && b3 == 0x31 { hasUnsupported = true } // av01
        }

        if hasDecodable { return true }
        if hasUnsupported { return false }
        return true
    }

    private static func localFilePath(for shortcode: String) -> URL {
        cacheDirectory.appendingPathComponent("ig-\(shortcode).mp4")
    }

    private static func downloadIfNeeded(from remoteURL: URL, cacheKey: String) async throws -> URL {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let destination = cacheDirectory.appendingPathComponent("ig-\(cacheKey).mp4")

        if fileManager.fileExists(atPath: destination.path) {
            let attrs = try? fileManager.attributesOfItem(atPath: destination.path)
            if let size = attrs?[.size] as? NSNumber, size.int64Value > 10000,
               isValidMP4(at: destination) {
                return destination
            }
            try? fileManager.removeItem(at: destination)
        }

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 60
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let (temporaryFile, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw InstagramExtractionError.invalidResponse
        }

        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: temporaryFile, to: destination)
        print("InstagramVideoLocalCache: Downloaded local video \(destination.lastPathComponent)")
        return destination
    }

    private static func stableHash(_ input: String) -> String {
        var hash: UInt64 = 5381
        for scalar in input.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return String(hash, radix: 16)
    }
}
