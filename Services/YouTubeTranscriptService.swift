// CosmoOS/Services/YouTubeTranscriptService.swift
// Free YouTube transcripts. Caption URLs scraped from the watch page now
// require a browser proof-of-origin ("pot") token — without it YouTube
// answers 200 with an empty body, which read as "no transcript" everywhere.
// The InnerTube player endpoint with the ANDROID client returns caption
// URLs that need no token, so that is the primary path; it serves srv3 XML
// rather than json3. The watch-page scrape stays as a fallback. Tracks are
// picked manual English → any manual → auto-generated, and parsed segments
// are cached on disk so a video is only ever fetched once. No API key.

import Foundation

struct YouTubeTranscriptSegment: Codable, Sendable, Equatable {
    /// Start of the segment, in seconds.
    var start: Double
    var text: String
    /// Segment duration in seconds, when the source format carries one.
    var duration: Double?

    init(start: Double, text: String, duration: Double? = nil) {
        self.start = start
        self.text = text
        self.duration = duration
    }
}

/// One caption track from the InnerTube player response.
struct YouTubeCaptionTrack: Decodable, Sendable {
    let baseUrl: String
    let languageCode: String?
    let kind: String?
}

/// Transcript paragraphs the reader renders: segments grouped into readable
/// blocks (~45s / ~420 chars) with the block's start time.
struct YouTubeTranscriptParagraph: Identifiable, Sendable, Equatable {
    var id: Int
    var start: Double
    var text: String

    var timestampLabel: String {
        let total = Int(start)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum YouTubeTranscriptError: Error, LocalizedError {
    case noVideoID
    case pageUnavailable
    case noCaptions
    case trackUnavailable

    var errorDescription: String? {
        switch self {
        case .noVideoID: return "Couldn't read a video id from this link."
        case .pageUnavailable: return "YouTube didn't return the video page."
        case .noCaptions: return "This video has no transcript."
        case .trackUnavailable: return "The transcript track couldn't be loaded."
        }
    }
}

actor YouTubeTranscriptService {
    static let shared = YouTubeTranscriptService()

    private var memoryCache: [String: [YouTubeTranscriptSegment]] = [:]

    // MARK: - Public

    /// Extracts a video id from any YouTube URL shape we meet.
    static func videoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        if let host = url.host, host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : id
        }
        if url.path.hasPrefix("/embed/") || url.path.hasPrefix("/shorts/") {
            return url.pathComponents.count > 2 ? url.pathComponents[2] : nil
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value
    }

    func transcript(forVideoID videoID: String) async throws -> [YouTubeTranscriptSegment] {
        if let cached = memoryCache[videoID] { return cached }
        if let disk = loadFromDisk(videoID: videoID) {
            memoryCache[videoID] = disk
            return disk
        }
        let segments = try await fetchFresh(videoID: videoID)
        memoryCache[videoID] = segments
        saveToDisk(videoID: videoID, segments: segments)
        return segments
    }

    /// Segments → readable paragraphs for the transcript pane.
    static func paragraphs(
        from segments: [YouTubeTranscriptSegment],
        maxSeconds: Double = 45,
        maxCharacters: Int = 420
    ) -> [YouTubeTranscriptParagraph] {
        var out: [YouTubeTranscriptParagraph] = []
        var currentText = ""
        var currentStart: Double = 0

        func flush() {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            out.append(YouTubeTranscriptParagraph(id: out.count, start: currentStart, text: trimmed))
            currentText = ""
        }

        for segment in segments {
            let piece = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            if currentText.isEmpty {
                currentStart = segment.start
            }
            if !currentText.isEmpty {
                currentText += " "
            }
            currentText += piece
            let spanned = segment.start - currentStart
            if currentText.count >= maxCharacters || spanned >= maxSeconds {
                flush()
            }
        }
        flush()
        return out
    }

    // MARK: - Fetch

    private func fetchFresh(videoID: String) async throws -> [YouTubeTranscriptSegment] {
        // InnerTube ANDROID first: its caption URLs skip the web pot-token
        // check that makes watch-page URLs come back empty.
        if let segments = try? await fetchViaInnerTube(videoID: videoID), !segments.isEmpty {
            return segments
        }
        return try await fetchViaWatchPage(videoID: videoID)
    }

    private static let innertubeEndpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!
    private static let androidUserAgent = "com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip"

    private struct InnertubePlayerResponse: Decodable {
        struct Captions: Decodable { let playerCaptionsTracklistRenderer: Renderer? }
        struct Renderer: Decodable { let captionTracks: [YouTubeCaptionTrack]? }
        let captions: Captions?
    }

    private func fetchViaInnerTube(videoID: String) async throws -> [YouTubeTranscriptSegment] {
        var request = URLRequest(url: Self.innertubeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.androidUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": ["client": [
                "clientName": "ANDROID",
                "clientVersion": "20.10.38",
                "androidSdkVersion": 30,
                "hl": "en",
            ] as [String: Any]],
            "videoId": videoID,
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        let player = try JSONDecoder().decode(InnertubePlayerResponse.self, from: data)
        guard let tracks = player.captions?.playerCaptionsTracklistRenderer?.captionTracks,
              let track = Self.bestTrack(in: tracks) else {
            throw YouTubeTranscriptError.noCaptions
        }
        guard let url = URL(string: track.baseUrl) else {
            throw YouTubeTranscriptError.trackUnavailable
        }
        let (trackData, _) = try await URLSession.shared.data(from: url)
        let segments = Self.parseTrack(trackData)
        guard !segments.isEmpty else { throw YouTubeTranscriptError.trackUnavailable }
        return segments
    }

    /// Manual English → any manual → auto-generated English → first.
    static func bestTrack(in tracks: [YouTubeCaptionTrack]) -> YouTubeCaptionTrack? {
        func isASR(_ track: YouTubeCaptionTrack) -> Bool { track.kind == "asr" }
        func isEnglish(_ track: YouTubeCaptionTrack) -> Bool { (track.languageCode ?? "").hasPrefix("en") }
        return tracks.first { !isASR($0) && isEnglish($0) }
            ?? tracks.first { !isASR($0) }
            ?? tracks.first { isASR($0) && isEnglish($0) }
            ?? tracks.first
    }

    /// A caption body in whichever format YouTube chose to serve.
    static func parseTrack(_ data: Data) -> [YouTubeTranscriptSegment] {
        let json3 = parseJSON3(data)
        if !json3.isEmpty { return json3 }
        return parseSRV3(data)
    }

    private func fetchViaWatchPage(videoID: String) async throws -> [YouTubeTranscriptSegment] {
        guard let pageURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)&hl=en") else {
            throw YouTubeTranscriptError.noVideoID
        }
        var request = URLRequest(url: pageURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        // Skips the EU consent interstitial that would hide the player response.
        request.setValue("CONSENT=YES+cb", forHTTPHeaderField: "Cookie")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw YouTubeTranscriptError.pageUnavailable
        }
        guard let trackURL = Self.bestCaptionTrackURL(inWatchPage: html) else {
            throw YouTubeTranscriptError.noCaptions
        }
        guard let url = URL(string: trackURL + "&fmt=json3") else {
            throw YouTubeTranscriptError.trackUnavailable
        }
        let (trackData, _) = try await URLSession.shared.data(from: url)
        let segments = Self.parseTrack(trackData)
        guard !segments.isEmpty else { throw YouTubeTranscriptError.trackUnavailable }
        return segments
    }

    // MARK: - Parsing (pure, testable)

    /// Finds the caption tracks array in a watch page and picks the best
    /// track: manual English → any manual → auto-generated English → first.
    static func bestCaptionTrackURL(inWatchPage html: String) -> String? {
        guard let range = html.range(of: "\"captionTracks\":") else { return nil }
        let tail = html[range.upperBound...]
        guard let arrayEnd = tail.range(of: "]") else { return nil }
        let arrayJSON = String(tail[..<arrayEnd.upperBound])
        guard let data = arrayJSON.data(using: .utf8),
              let tracks = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              !tracks.isEmpty else { return nil }

        func baseURL(_ track: [String: Any]) -> String? {
            (track["baseUrl"] as? String)?.replacingOccurrences(of: "\\u0026", with: "&")
        }
        func isASR(_ track: [String: Any]) -> Bool {
            (track["kind"] as? String) == "asr"
        }
        func isEnglish(_ track: [String: Any]) -> Bool {
            ((track["languageCode"] as? String) ?? "").hasPrefix("en")
        }

        let manualEnglish = tracks.first { !isASR($0) && isEnglish($0) }
        let anyManual = tracks.first { !isASR($0) }
        let asrEnglish = tracks.first { isASR($0) && isEnglish($0) }
        let chosen = manualEnglish ?? anyManual ?? asrEnglish ?? tracks.first
        return chosen.flatMap(baseURL)
    }

    /// json3 events → segments. Events carry tStartMs + segs[].utf8.
    static func parseJSON3(_ data: Data) -> [YouTubeTranscriptSegment] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let events = object["events"] as? [[String: Any]] else { return [] }
        var out: [YouTubeTranscriptSegment] = []
        for event in events {
            guard let startMs = event["tStartMs"] as? Double ?? (event["tStartMs"] as? Int).map(Double.init),
                  let segs = event["segs"] as? [[String: Any]] else { continue }
            let durationMs = event["dDurationMs"] as? Double ?? (event["dDurationMs"] as? Int).map(Double.init)
            let text = segs.compactMap { $0["utf8"] as? String }.joined()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            out.append(YouTubeTranscriptSegment(start: startMs / 1000, text: text, duration: durationMs.map { $0 / 1000 }))
        }
        return out
    }

    /// srv3 timedtext XML (what InnerTube ANDROID caption URLs serve) →
    /// segments. Paragraphs are `<p t="ms" d="ms">`, either with plain text
    /// or nested per-word `<s>` elements; filler paragraphs hold only
    /// whitespace and are dropped.
    static func parseSRV3(_ data: Data) -> [YouTubeTranscriptSegment] {
        let delegate = SRV3ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.segments
    }

    private final class SRV3ParserDelegate: NSObject, XMLParserDelegate {
        var segments: [YouTubeTranscriptSegment] = []
        private var insideParagraph = false
        private var currentStart: Double?
        private var currentDuration: Double?
        private var currentText = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            guard elementName == "p" else { return }
            insideParagraph = true
            currentStart = attributes["t"].flatMap(Double.init).map { $0 / 1000 }
            currentDuration = attributes["d"].flatMap(Double.init).map { $0 / 1000 }
            currentText = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard insideParagraph else { return }
            currentText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            guard elementName == "p", insideParagraph else { return }
            insideParagraph = false
            let text = currentText
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard let start = currentStart, !text.isEmpty else { return }
            segments.append(YouTubeTranscriptSegment(start: start, text: text, duration: currentDuration))
        }
    }

    // MARK: - Disk cache

    private func cacheURL(for videoID: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("Cosmo/transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Video ids are URL-safe already; keep the filename honest anyway.
        let safe = videoID.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(safe).json")
    }

    private func loadFromDisk(videoID: String) -> [YouTubeTranscriptSegment]? {
        guard let url = cacheURL(for: videoID),
              let data = try? Data(contentsOf: url),
              let segments = try? JSONDecoder().decode([YouTubeTranscriptSegment].self, from: data),
              !segments.isEmpty else { return nil }
        return segments
    }

    private func saveToDisk(videoID: String, segments: [YouTubeTranscriptSegment]) {
        guard let url = cacheURL(for: videoID),
              let data = try? JSONEncoder().encode(segments) else { return }
        try? data.write(to: url)
    }
}
