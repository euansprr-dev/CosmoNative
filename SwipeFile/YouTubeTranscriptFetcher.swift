// CosmoOS/SwipeFile/YouTubeTranscriptFetcher.swift
// Fetches YouTube video transcripts using YouTube's internal API
// Falls back to video metadata if transcript unavailable

import Foundation

/// Fetches YouTube video transcripts and metadata
/// Uses YouTube's Innertube API (same as official apps)
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

    // MARK: - Innertube API Constants

    private let innertubeApiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    private let innertubeClientVersion = "2.20231219.04.00"

    // MARK: - Fetch Transcript

    func fetchTranscript(videoId: String) async throws -> TranscriptResult {
        // First, get video page to extract necessary tokens
        let playerResponse = try await fetchPlayerResponse(videoId: videoId)

        // Extract video details
        let title = playerResponse.videoDetails?.title
        let author = playerResponse.videoDetails?.author
        let duration = Int(playerResponse.videoDetails?.lengthSeconds ?? "0")

        // Try to get transcript
        if let captionTracks = playerResponse.captions?.playerCaptionsTracklistRenderer?.captionTracks,
           let track = captionTracks.first {
            let transcript = try await fetchTranscriptFromTrack(track.baseUrl)
            return TranscriptResult(
                fullText: transcript.fullText,
                segments: transcript.segments,
                duration: duration,
                author: author,
                title: title
            )
        }

        // No captions available - return empty transcript with metadata
        throw TranscriptError.noCaptionsAvailable
    }

    // MARK: - Player Response

    private func fetchPlayerResponse(videoId: String) async throws -> InnertubePlayerResponse {
        let url = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(innertubeApiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": innertubeClientVersion,
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": videoId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TranscriptError.apiError
        }

        return try JSONDecoder().decode(InnertubePlayerResponse.self, from: data)
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
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "") // Simplified
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
                return "YouTube API request failed"
            case .invalidUrl:
                return "Invalid transcript URL"
            case .parseError:
                return "Failed to parse transcript"
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
