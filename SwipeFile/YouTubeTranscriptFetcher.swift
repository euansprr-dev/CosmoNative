// CosmoOS/SwipeFile/YouTubeTranscriptFetcher.swift
// Fetches YouTube video transcripts via page-scraping
// Extracts ytInitialPlayerResponse from watch page HTML — no API key required

import Foundation

/// Fetches YouTube video transcripts and metadata
/// Uses page-scraping to extract captions (same approach as youtube-transcript-api)
actor YouTubeTranscriptFetcher {
    static let shared = YouTubeTranscriptFetcher()

    // MARK: - Result Types

    struct TranscriptResult {
        let fullText: String
        let segments: [TranscriptSegment]
        let duration: Int?
        let author: String?
        let title: String?

        struct TranscriptSegment {
            let text: String
            let start: Double
            let duration: Double
        }
    }

    // MARK: - Fetch Transcript

    func fetchTranscript(videoId: String) async throws -> TranscriptResult {
        // 1. Fetch the watch page HTML
        let playerResponse = try await fetchPlayerResponseFromPage(videoId: videoId)

        // 2. Extract video details
        let title = playerResponse.videoDetails?.title
        let author = playerResponse.videoDetails?.author
        let duration = Int(playerResponse.videoDetails?.lengthSeconds ?? "0")

        // 3. Find best caption track
        guard let captionTracks = playerResponse.captions?.playerCaptionsTracklistRenderer?.captionTracks,
              !captionTracks.isEmpty else {
            throw TranscriptError.noCaptionsAvailable
        }

        let track = chooseBestTrack(captionTracks)

        // 4. Fetch transcript from caption track
        let transcript = try await fetchTranscriptFromTrack(track.baseUrl)
        return TranscriptResult(
            fullText: transcript.fullText,
            segments: transcript.segments,
            duration: duration,
            author: author,
            title: title
        )
    }

    // MARK: - Page Scraping

    /// Fetch the YouTube watch page and extract ytInitialPlayerResponse JSON
    private func fetchPlayerResponseFromPage(videoId: String) async throws -> InnertubePlayerResponse {
        let watchUrl = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!

        var request = URLRequest(url: watchUrl)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TranscriptError.apiError
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw TranscriptError.parseError
        }

        // Extract ytInitialPlayerResponse JSON from the page
        guard let json = extractPlayerResponseJSON(from: html) else {
            throw TranscriptError.parseError
        }

        guard let jsonData = json.data(using: .utf8) else {
            throw TranscriptError.parseError
        }

        return try JSONDecoder().decode(InnertubePlayerResponse.self, from: jsonData)
    }

    /// Extract the balanced JSON object after `var ytInitialPlayerResponse = `
    private func extractPlayerResponseJSON(from html: String) -> String? {
        // Look for the assignment pattern
        let markers = [
            "var ytInitialPlayerResponse = ",
            "ytInitialPlayerResponse = "
        ]

        for marker in markers {
            guard let markerRange = html.range(of: marker) else { continue }
            let jsonStart = markerRange.upperBound

            // Extract balanced JSON by counting braces
            if let json = extractBalancedJSON(from: html, startingAt: jsonStart) {
                return json
            }
        }

        // Fallback: try regex for the pattern in a script tag
        // Some pages embed it differently
        let scriptPattern = #"ytInitialPlayerResponse\s*=\s*(\{.+?\});"#
        if let regex = try? NSRegularExpression(pattern: scriptPattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let captureRange = Range(match.range(at: 1), in: html) {
            let candidate = String(html[captureRange])
            // Validate it's parseable JSON
            if let data = candidate.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return candidate
            }
        }

        return nil
    }

    /// Extract a balanced JSON object from the string starting at the given index
    private func extractBalancedJSON(from string: String, startingAt start: String.Index) -> String? {
        guard start < string.endIndex, string[start] == "{" else { return nil }

        var depth = 0
        var inString = false
        var escape = false
        var index = start

        while index < string.endIndex {
            let char = string[index]

            if escape {
                escape = false
                index = string.index(after: index)
                continue
            }

            if char == "\\" && inString {
                escape = true
                index = string.index(after: index)
                continue
            }

            if char == "\"" {
                inString.toggle()
                index = string.index(after: index)
                continue
            }

            if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        let end = string.index(after: index)
                        return String(string[start..<end])
                    }
                }
            }

            index = string.index(after: index)
        }

        return nil
    }

    // MARK: - Track Selection

    /// Choose the best caption track: prefer English manual, then English auto, then any
    private func chooseBestTrack(_ tracks: [InnertubePlayerResponse.CaptionTrack]) -> InnertubePlayerResponse.CaptionTrack {
        // Prefer English manual captions
        if let manual = tracks.first(where: { $0.languageCode == "en" && $0.kind != "asr" }) {
            return manual
        }
        // Fall back to English auto-generated
        if let auto = tracks.first(where: { $0.languageCode == "en" && $0.kind == "asr" }) {
            return auto
        }
        // Fall back to any English variant
        if let english = tracks.first(where: { $0.languageCode?.hasPrefix("en") == true }) {
            return english
        }
        // Fall back to any manual
        if let manual = tracks.first(where: { $0.kind != "asr" }) {
            return manual
        }
        // Last resort: first available
        return tracks[0]
    }

    // MARK: - Transcript Track Fetching

    private func fetchTranscriptFromTrack(_ baseUrl: String) async throws -> (fullText: String, segments: [TranscriptResult.TranscriptSegment]) {
        // Add format parameter for timedtext
        var urlString = baseUrl
        if !urlString.contains("fmt=") {
            urlString += "&fmt=json3"
        }

        guard let url = URL(string: urlString) else {
            throw TranscriptError.invalidUrl
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // Try JSON3 format first
        if let json3 = try? JSONDecoder().decode(TranscriptJson3.self, from: data) {
            return parseJson3Transcript(json3)
        }

        // Fall back to XML parsing
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        return parseXmlTranscript(xmlString)
    }

    // MARK: - JSON3 Parsing

    private func parseJson3Transcript(_ json: TranscriptJson3) -> (fullText: String, segments: [TranscriptResult.TranscriptSegment]) {
        var segments: [TranscriptResult.TranscriptSegment] = []
        var fullTextParts: [String] = []

        for event in json.events ?? [] {
            guard let segs = event.segs else { continue }

            let text = segs.compactMap { $0.utf8 }.joined()
            if text.isEmpty { continue }

            let start = Double(event.tStartMs ?? 0) / 1000.0
            let duration = Double(event.dDurationMs ?? 0) / 1000.0

            segments.append(TranscriptResult.TranscriptSegment(
                text: text,
                start: start,
                duration: duration
            ))
            fullTextParts.append(text)
        }

        return (fullTextParts.joined(separator: " "), segments)
    }

    // MARK: - XML Parsing

    private func parseXmlTranscript(_ xml: String) -> (fullText: String, segments: [TranscriptResult.TranscriptSegment]) {
        var segments: [TranscriptResult.TranscriptSegment] = []
        var fullTextParts: [String] = []

        // Simple regex-based XML parsing for <text start="X" dur="Y">content</text>
        let pattern = #"<text start="([\d.]+)" dur="([\d.]+)"[^>]*>([^<]*)</text>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ("", [])
        }

        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, range: range)

        for match in matches {
            guard let startRange = Range(match.range(at: 1), in: xml),
                  let durRange = Range(match.range(at: 2), in: xml),
                  let textRange = Range(match.range(at: 3), in: xml) else {
                continue
            }

            let start = Double(xml[startRange]) ?? 0
            let duration = Double(xml[durRange]) ?? 0
            let text = decodeHtmlEntities(String(xml[textRange]))

            if !text.isEmpty {
                segments.append(TranscriptResult.TranscriptSegment(
                    text: text,
                    start: start,
                    duration: duration
                ))
                fullTextParts.append(text)
            }
        }

        return (fullTextParts.joined(separator: " "), segments)
    }

    // MARK: - HTML Entity Decoding

    private func decodeHtmlEntities(_ string: String) -> String {
        var result = string
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&#x27;": "'",
            "&#x2F;": "/",
            "&nbsp;": " "
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Handle numeric entities
        let numericPattern = #"&#(\d+);"#
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Error Types

    enum TranscriptError: LocalizedError {
        case noCaptionsAvailable
        case apiError
        case invalidUrl
        case parseError

        var errorDescription: String? {
            switch self {
            case .noCaptionsAvailable:
                return "No captions available for this video"
            case .apiError:
                return "YouTube page request failed"
            case .invalidUrl:
                return "Invalid transcript URL"
            case .parseError:
                return "Failed to parse transcript from page"
            }
        }
    }
}

// MARK: - Innertube Response Models

private struct InnertubePlayerResponse: Codable {
    let videoDetails: VideoDetails?
    let captions: Captions?

    struct VideoDetails: Codable {
        let videoId: String?
        let title: String?
        let lengthSeconds: String?
        let author: String?
        let shortDescription: String?
    }

    struct Captions: Codable {
        let playerCaptionsTracklistRenderer: CaptionTracklistRenderer?
    }

    struct CaptionTracklistRenderer: Codable {
        let captionTracks: [CaptionTrack]?
    }

    struct CaptionTrack: Codable {
        let baseUrl: String
        let name: CaptionName?
        let languageCode: String?
        let kind: String?

        struct CaptionName: Codable {
            let simpleText: String?
        }
    }
}

private struct TranscriptJson3: Codable {
    let events: [TranscriptEvent]?

    struct TranscriptEvent: Codable {
        let tStartMs: Int?
        let dDurationMs: Int?
        let segs: [TranscriptSeg]?
    }

    struct TranscriptSeg: Codable {
        let utf8: String?
    }
}
