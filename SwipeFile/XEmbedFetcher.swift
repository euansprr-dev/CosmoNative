// CosmoOS/SwipeFile/XEmbedFetcher.swift
// Fetches X (Twitter) post content using the public oEmbed API

import Foundation

/// Fetches X/Twitter post embeds and content
/// Uses Twitter's public oEmbed endpoint (no auth required)
actor XEmbedFetcher {
    static let shared = XEmbedFetcher()

    // MARK: - Result Types

    struct EmbedResult {
        let html: String?
        let text: String?
        let authorName: String?
        let authorUrl: String?
        let url: String
    }

    // MARK: - oEmbed Endpoint

    private let oembedBaseUrl = "https://publish.twitter.com/oembed"

    // MARK: - Fetch Embed

    func fetchEmbed(url: String) async throws -> EmbedResult {
        // Normalize URL to use twitter.com (oEmbed may not support x.com)
        let normalizedUrl = url.replacingOccurrences(of: "x.com", with: "twitter.com")

        guard var components = URLComponents(string: oembedBaseUrl) else {
            throw EmbedError.invalidUrl
        }

        components.queryItems = [
            URLQueryItem(name: "url", value: normalizedUrl),
            URLQueryItem(name: "omit_script", value: "true"),
            URLQueryItem(name: "hide_media", value: "false"),
            URLQueryItem(name: "hide_thread", value: "false")
        ]

        guard let requestUrl = components.url else {
            throw EmbedError.invalidUrl
        }

        var request = URLRequest(url: requestUrl)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbedError.networkError
        }

        if httpResponse.statusCode == 404 {
            throw EmbedError.tweetNotFound
        }

        guard httpResponse.statusCode == 200 else {
            throw EmbedError.apiError(statusCode: httpResponse.statusCode)
        }

        let oembedResponse = try JSONDecoder().decode(OEmbedResponse.self, from: data)

        // Extract tweet text from HTML
        let tweetText = extractTweetText(from: oembedResponse.html)

        return EmbedResult(
            html: oembedResponse.html,
            text: tweetText,
            authorName: oembedResponse.authorName,
            authorUrl: oembedResponse.authorUrl,
            url: oembedResponse.url ?? url
        )
    }

    // MARK: - Text Extraction

    private func extractTweetText(from html: String?) -> String? {
        guard let html = html else { return nil }

        // The oEmbed HTML contains the tweet text in a <p> tag within the blockquote
        // Pattern: <blockquote...><p...>TWEET TEXT</p>...

        // Simple approach: extract text between <p> tags
        let pPattern = #"<p[^>]*>([^<]+)</p>"#

        guard let regex = try? NSRegularExpression(pattern: pPattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        var textParts: [String] = []

        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match = match,
                  let textRange = Range(match.range(at: 1), in: html) else {
                return
            }
            let text = String(html[textRange])
            let cleaned = cleanHtml(text)
            if !cleaned.isEmpty {
                textParts.append(cleaned)
            }
        }

        if textParts.isEmpty {
            // Fallback: strip all HTML tags
            return cleanHtml(html)
        }

        return textParts.joined(separator: "\n")
    }

    private func cleanHtml(_ html: String) -> String {
        var result = html

        // Remove HTML tags
        let tagPattern = #"<[^>]+>"#
        if let regex = try? NSRegularExpression(pattern: tagPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        // Decode HTML entities
        result = decodeHtmlEntities(result)

        // Clean up whitespace
        result = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHtmlEntities(_ string: String) -> String {
        var result = string
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…"
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        return result
    }

    // MARK: - Error Types

    enum EmbedError: LocalizedError {
        case invalidUrl
        case networkError
        case tweetNotFound
        case apiError(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidUrl:
                return "Invalid tweet URL"
            case .networkError:
                return "Network request failed"
            case .tweetNotFound:
                return "Tweet not found or is private"
            case .apiError(let code):
                return "Twitter API error (status \(code))"
            }
        }
    }
}

// MARK: - oEmbed Response Model

private struct OEmbedResponse: Codable {
    let url: String?
    let authorName: String?
    let authorUrl: String?
    let html: String?
    let width: Int?
    let height: Int?
    let type: String?
    let cacheAge: String?
    let providerName: String?
    let providerUrl: String?
    let version: String?

    enum CodingKeys: String, CodingKey {
        case url
        case authorName = "author_name"
        case authorUrl = "author_url"
        case html
        case width
        case height
        case type
        case cacheAge = "cache_age"
        case providerName = "provider_name"
        case providerUrl = "provider_url"
        case version
    }
}
