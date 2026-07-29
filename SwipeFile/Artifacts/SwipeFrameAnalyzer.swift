// CosmoOS/SwipeFile/Artifacts/SwipeFrameAnalyzer.swift
// Frame swipes (screenshots and photos): read the images, then judge them.
//
// TWO PASSES, DELIBERATELY NOT MERGED. The vision model is right for
// transcription — it is cheap, it is literal, and it never editorialises — and
// wrong for craft judgment, where it produces the "builds credibility" register
// this whole system exists to avoid. So pass 1 reads (Gemini Flash vision) and
// pass 2 judges (Sonnet 5, via the shared SwipeArtifactAnalyzer, emitting the
// same contract a post gets).
//
// The attribution-strip rule below is the seventh member of a parity family:
// worker transcribe.ts / reelPipeline.ts / reelVideoUnderstanding.ts, Mac
// InstagramAutoTranscriber ×2, and the displayTitle rules in analyze.ts and
// SwipeInsightEngine all carry the same instruction. Edit one, read all seven.

import Foundation
import AppKit

@MainActor
enum SwipeFrameAnalyzer {

    /// Same model the carousel slide OCR uses. 2.0-flash-001 was sunset on
    /// OpenRouter (silent 404s that emptied every slide) — do not "restore" it.
    static let visionModel = "google/gemini-2.5-flash"

    /// Vision cost and prompt budget both scale with image count, and a swipe
    /// of more than ten screenshots is a board, not one artifact.
    static let maxFramesPerCall = 10

    /// Longest edge before the base64 payload stops being worth it. A retina
    /// screenshot is ~3 MB; at 1400px the copy is still perfectly legible to
    /// the model and the request is roughly a tenth the size.
    static let maxImageEdge: CGFloat = 1400

    // MARK: - Vision response

    struct FrameReading: Codable {
        var copy: String?
        var composition: String?
        var medium: String?
        var detectedSource: Source?

        struct Source: Codable {
            var platform: String?
            var handle: String?
        }
    }

    private struct VisionResponse: Codable {
        var frames: [FrameReading]?
    }

    // MARK: - Entry point

    /// Read + judge a frame swipe, returning the artifact and analysis to
    /// persist. Returns nil only when there is nothing readable at all — a
    /// vision failure still yields captured units so the images are never lost.
    static func analyze(
        atom: Atom,
        artifact: SwipeArtifact,
        images: [Data],
        userNote: String?
    ) async -> SwipeArtifactAnalyzer.Result? {
        let readings = await read(images: images)

        var units = artifact.orderedUnits
        for (index, reading) in readings.enumerated() where index < units.count {
            if let copy = reading.copy?.trimmed, !copy.isEmpty {
                units[index].copy = copy
            }
            // A frame with no readable copy is not a failure — the image IS the
            // content. Its composition becomes the mechanic seed so the craft
            // pass has something concrete to judge, and its role defaults to
            // `.visual` unless the craft pass says otherwise.
            if let composition = reading.composition?.trimmed, !composition.isEmpty {
                units[index].mechanic = composition
            }
            if units[index].copy?.trimmed.isEmpty != false {
                units[index].role = .visual
            }
        }

        var readArtifact = artifact
        readArtifact.units = units
        readArtifact.detectedSource = firstDetectedSource(in: readings)

        guard let result = await SwipeArtifactAnalyzer.analyze(
            atom: atom,
            artifact: readArtifact,
            userNote: userNote
        ) else {
            // Vision landed but craft failed (or there was nothing to judge).
            // Keep the transcription — it is the expensive, irreplaceable part.
            guard units.contains(where: \.hasSubstance) else { return nil }
            return SwipeArtifactAnalyzer.Result(
                analysis: SwipeAnalysis(
                    analysisVersion: SwipeInsightEngine.insightVersion,
                    isFullyAnalyzed: false
                ),
                units: units,
                anatomy: nil
            )
        }
        return result
    }

    /// The first actionable source any frame reported. One swipe upgrades to
    /// one post, so the first wins rather than merging conflicting handles.
    static func firstDetectedSource(in readings: [FrameReading]) -> DetectedSource? {
        for reading in readings {
            guard let source = reading.detectedSource else { continue }
            let candidate = DetectedSource(
                platform: source.platform?.trimmed,
                handle: source.handle?.trimmed
            )
            if candidate.isActionable { return candidate }
        }
        return nil
    }

    // MARK: - Pass 1: vision

    /// Transcribe a batch of images. Never throws — an unreadable batch
    /// returns empty readings and the caller keeps the images.
    static func read(images: [Data]) async -> [FrameReading] {
        let batch = Array(images.prefix(maxFramesPerCall))
        guard !batch.isEmpty else { return [] }
        guard let apiKey = APIKeys.openRouter, !apiKey.isEmpty else {
            print("SwipeFrameAnalyzer: no OpenRouter key — frames stay untranscribed")
            return []
        }

        var content: [[String: Any]] = [["type": "text", "text": visionPrompt(frameCount: batch.count)]]
        for data in batch {
            guard let encoded = downscaledJPEGBase64(data) else { continue }
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(encoded)"]
            ])
        }
        guard content.count > 1 else { return [] }

        let body: [String: Any] = [
            "model": visionModel,
            "messages": [["role": "user", "content": content]],
            "temperature": 0.1,
            "max_tokens": 4000
        ]

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("SwipeFrameAnalyzer: vision HTTP \(status)")
                return []
            }
            guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = payload["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String else {
                return []
            }
            return parseVisionResponse(text, expected: batch.count)
        } catch {
            print("SwipeFrameAnalyzer: vision call failed: \(error)")
            return []
        }
    }

    /// Strip code fences, decode, and pad/truncate to the frame count so the
    /// caller's index-aligned merge can never read past the end.
    static func parseVisionResponse(_ raw: String, expected: Int) -> [FrameReading] {
        var text = raw.trimmed
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if text.hasSuffix("```") { text = String(text.dropLast(3)) }
            text = text.trimmed
        }
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(VisionResponse.self, from: data),
              let frames = decoded.frames else {
            return []
        }
        if frames.count >= expected { return Array(frames.prefix(expected)) }
        return frames + Array(repeating: FrameReading(), count: expected - frames.count)
    }

    static func visionPrompt(frameCount: Int) -> String {
        """
        You are reading \(frameCount) screenshot\(frameCount == 1 ? "" : "s") a marketer saved as \
        reference. For EACH image, in order, return one object.

        `copy` — every word visible in the image, transcribed exactly. Preserve capitalisation \
        and punctuation as written.
        - JOIN wrapped lines: text that wraps across several lines inside ONE text block is one \
        flowing sentence. Never keep the image's visual line wrapping. A card reading \
        "My stockmarket portfolio / made a gain of almost $700k / in 12 months" is ONE line: \
        "My stockmarket portfolio made a gain of almost $700k in 12 months".
        - One line per sentence: when a block holds several sentences, each gets its own line.
        - One line per distinct element: separate cards, headings, and standalone labels or big \
        stats each get their own line (a card showing "RETURN" above "$695,613.43" is two lines).
        - List items keep their bullet/number/arrow markers, one item per line. Never merge two \
        list items into one line.
        - Numbers and years are transcribed EXACTLY as shown — never corrected, never rounded, \
        never modernised. If the card says 2025, write 2025.

        IGNORE author attribution on screenshotted posts: many screenshots are of a tweet, \
        thread, or other social post. The attribution header/footer of that embedded post — \
        profile photo, display name, @username handle, verified badge, timestamp, and \
        like/reply/retweet counts — is attribution, NOT content. Skip it entirely and read ONLY \
        the post's body text, verbatim. Example: for a tweet screenshot reading \
        "Brennan Schlagbaum, CPA @Budgetdog_ / How To Retire Early…", `copy` starts at \
        "How To Retire Early" — the name and handle are never included.
        Also ignore browser and app interface chrome: address bars, tab titles, sidebars, \
        toolbars, notification badges, system status bars. If the screenshot shows a screen \
        recording or an app UI, that interface is background — transcribe only text the \
        creator authored.
        If the image has no readable text at all, `copy` is an empty string.

        `composition` — one sentence describing what is on screen: the layout, the imagery, the \
        colour treatment, and where the eye lands first.

        `medium` — exactly one of: social_post, ad, email, web_page, app_ui, chart, document, \
        product, photo, other.

        `detectedSource` — if the image is a screenshot of a post from a named platform, return \
        {"platform": "...", "handle": "@..."} read off the chrome you excluded from `copy`. \
        Otherwise null.

        Return ONLY this JSON, no prose, no code fence:
        {"frames": [{"copy": "...", "composition": "...", "medium": "...", "detectedSource": null}]}

        The `frames` array must hold exactly \(frameCount) object\(frameCount == 1 ? "" : "s"), \
        in the order the images were given.
        """
    }

    // MARK: - Image prep

    /// Downscale to `maxImageEdge` and JPEG-encode for the request body.
    /// Reuses the NSImage helpers WebsiteCapture already defines.
    static func downscaledJPEGBase64(_ data: Data) -> String? {
        guard let image = NSImage(data: data) else { return nil }
        let scaled = image.scaled(toFit: CGSize(width: maxImageEdge, height: maxImageEdge))
        return scaled.base64String
    }
}
