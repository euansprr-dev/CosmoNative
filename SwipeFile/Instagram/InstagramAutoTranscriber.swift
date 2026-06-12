// CosmoOS/SwipeFile/Instagram/InstagramAutoTranscriber.swift
// Dual-pipeline auto-transcription engine for Instagram reels/videos
// Runs Vision OCR + SFSpeechRecognizer in parallel
// February 2026

import Foundation
import AVFoundation
import Vision
@preconcurrency import Speech
import ImageIO

// MARK: - Transcription Progress

/// Progress stages reported during auto-transcription
enum TranscriptionProgress: Sendable {
    case extractingFrames(Double)    // 0.0–1.0
    case recognizingText(Double)     // 0.0–1.0
    case recognizingSpeech(Double)   // 0.0–1.0
    case analyzingWithAI(Double)     // 0.0–1.0 Gemini vision pipeline
    case mergingResults
    case complete
}

// MARK: - Transcription Result

/// Result of the auto-transcription process
struct TranscriptionResult: Sendable {
    var rawSlides: [TranscriptSlide]
    var cleanedSlides: [TranscriptSlide]
    var speechSegments: [TranscriptSegment]
    var contentType: TranscriptionContentType
    var averageOCRConfidence: Float
    var quality: TranscriptionQuality
    var warnings: [String]

    var slides: [TranscriptSlide] { cleanedSlides }
}

// MARK: - OCR Frame Result

/// Text recognized in a single video frame
struct OCRFrameResult: Sendable {
    let timestamp: TimeInterval
    let lines: [String]
    let normalizedLineSet: Set<String>
    let confidence: Float
}

/// Aggregated OCR line statistics across multiple frames in the same visual slide
private struct OCRLineAggregate: Sendable {
    var variants: [String: Int]
    var count: Int
    var firstFrameIndex: Int
    var firstLineIndex: Int
    var totalLineIndex: Int
}

// MARK: - Speech Segment

/// A segment of recognized speech
struct SpeechSegment: Sendable {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
}

private struct SpeechPipelineResult: Sendable {
    let speech: [SpeechSegment]
    let transcriptSegments: [TranscriptSegment]
    let quality: TranscriptionQuality
    let warnings: [String]
    let source: SpeechPipelineSource

    var hasTimestamps: Bool {
        transcriptSegments.contains { $0.end > $0.start }
    }

    static let empty = SpeechPipelineResult(
        speech: [],
        transcriptSegments: [],
        quality: .accurate,
        warnings: [],
        source: .none
    )
}

private enum SpeechPipelineSource: Sendable {
    case none
    case whisperAPI
    case daemonWhisper
    case appleSpeech
}

private struct ReelModalityEvidence: Sendable {
    let visualWordCount: Int
    let speechWordCount: Int
    let visualSlideCount: Int
    let avgVisualWordsPerSlide: Double
    let shortVisualSlideRatio: Double
    let longVisualSlideRatio: Double
    let distinctVisualRatio: Double
    let subtitleOverlapRatio: Double
    let speechCoverageRatio: Double
    let speechWordsPerSecond: Double
    let avgSpeechWordsPerSegment: Double
    let speechUniqueWordRatio: Double
    let repeatedSpeechSegmentRatio: Double
    let lyricRisk: Int
    let voiceoverScore: Int
    let textScore: Int

    var shouldPreferVoiceover: Bool {
        if speechWordCount == 0 { return false }
        if visualWordCount == 0 { return true }

        // On-screen text mirrors the speech (burned captions or subtitles).
        if subtitleOverlapRatio >= 0.58 && speechCoverageRatio >= 0.25 {
            if speechWordCount >= 18 {
                return lyricRisk < 4 || voiceoverScore > textScore
            }
            // Mirrored speech too short to be real narration is a lyric or
            // music overlay — the slides carry the content, not the audio.
            return false
        }

        // Slides whose text is distinct from the speech are authored content;
        // never discard them just because the speech channel is strong.
        if distinctVisualRatio >= 0.75 && visualWordCount >= 12 { return false }

        return voiceoverScore >= textScore + 2 && lyricRisk < 4
    }

    var shouldTreatAsTextOnly: Bool {
        if visualWordCount == 0 { return false }
        if speechWordCount == 0 { return true }
        // Short speech that merely mirrors the on-screen text (lyric or music
        // overlay) adds nothing — the slides already carry all of the content.
        if subtitleOverlapRatio >= 0.7 && speechWordCount < 18 { return true }
        if lyricRisk >= 3 && textScore >= voiceoverScore { return true }
        return textScore >= voiceoverScore + 2 && !(speechWordCount >= 18 && subtitleOverlapRatio >= 0.4)
    }
}

// MARK: - Instagram Auto Transcriber

final class InstagramAutoTranscriber: Sendable {
    static let shared = InstagramAutoTranscriber()

    private let framesPerSecond: Double = 4.0
    private let jaccardThreshold: Double = 0.62
    private let minLineConfidence: Float = 0.18
    private let minStableLineRatio: Double = 0.18

    // Gemini Vision pipeline constants
    private let geminiModel = "google/gemini-2.0-flash-001"
    private let geminiFPS: Double = 4.0           // 4fps to catch short 1-frame text transitions
    private let maxGeminiFrames: Int = 240         // Accuracy-first cap for short reels with fast cuts
    private let geminiBatchSize: Int = 20          // Frames per API call
    private let geminiBatchOverlap: Int = 2        // Overlap frames between batches

    private init() {}

    // MARK: - Main Transcription

    /// Transcribe an Instagram video using both Vision OCR and Speech recognition
    /// - Parameters:
    ///   - videoURL: Direct CDN URL to the video file
    ///   - duration: Video duration in seconds (used for frame extraction)
    ///   - progressHandler: Called with progress updates on the main actor
    /// - Returns: TranscriptionResult with slides and detected content type
    func transcribe(
        videoURL: URL,
        duration: TimeInterval,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> TranscriptionResult {
        // Query real video duration from the file — the caller's duration may be wrong
        // (e.g., fast-path cached videos default to 60s regardless of actual length)
        let asset = AVURLAsset(url: videoURL)
        var actualDuration = duration
        if let cmDuration = try? await asset.load(.duration), cmDuration.seconds > 0.5 {
            actualDuration = cmDuration.seconds
        }
        if abs(actualDuration - duration) > 1 {
            print("InstagramAutoTranscriber: Duration corrected: \(duration)s → \(actualDuration)s (from video file)")
        }
        print("InstagramAutoTranscriber: Starting transcription (duration: \(actualDuration)s)")

        var warnings: [String] = []
        var quality: TranscriptionQuality = .accurate

        // Step 1: Extract frames as lightweight JPEG (~1.5MB total, not raw CGImages).
        let jpegFrames = await extractFramesAsJPEG(
            videoURL: videoURL,
            duration: actualDuration,
            fps: geminiFPS,
            maxFrames: maxGeminiFrames,
            progressHandler: progressHandler
        )
        let totalBytes = jpegFrames.reduce(0) { $0 + $1.jpegData.count }
        print("InstagramAutoTranscriber: Extracted \(jpegFrames.count) JPEG frames (\(totalBytes / 1024)KB total)")

        // Step 2: Try Gemini vision pipeline
        print("InstagramAutoTranscriber: Starting Gemini vision pipeline...")
        let geminiSlides = await runGeminiVisionPipeline(
            jpegFrames: jpegFrames,
            duration: actualDuration,
            progressHandler: progressHandler
        )

        // Step 3: If Gemini failed, fallback to Apple Vision OCR (extracts own frames at 2fps)
        let visualSlides: [TranscriptSlide]
        let ocrFrameResults: [OCRFrameResult]

        if let slides = geminiSlides, !slides.isEmpty {
            visualSlides = slides
            ocrFrameResults = []
            print("InstagramAutoTranscriber: Gemini vision produced \(slides.count) slides")
        } else {
            print("InstagramAutoTranscriber: Gemini unavailable/failed, falling back to Apple Vision OCR")
            ocrFrameResults = await runOCRPipeline(jpegFrames: jpegFrames, progressHandler: progressHandler)
            visualSlides = ocrToSlides(ocr: ocrFrameResults)
        }

        // Step 4: Run speech recognition SEQUENTIALLY (after vision completes)
        // Running in parallel caused AVFoundation resource contention and memory pressure.
        // Sequential is safer — the video file is only used by one subsystem at a time.
        print("InstagramAutoTranscriber: Starting speech pipeline...")
        let speechResult = await runSpeechPipelineWithFallback(videoURL: videoURL, progressHandler: progressHandler)
        print("InstagramAutoTranscriber: Speech pipeline returned \(speechResult.speech.count) segments")
        warnings.append(contentsOf: speechResult.warnings)
        if speechResult.quality == .degraded {
            quality = .degraded
        }

        // Step 5: Merge results
        progressHandler(.mergingResults)

        var result: TranscriptionResult
        if !visualSlides.isEmpty && visualSlides.first?.source == .geminiVision {
            result = mergeGeminiWithSpeech(
                geminiSlides: visualSlides,
                speech: speechResult.speech,
                duration: actualDuration,
                allowSpeechAlignment: speechResult.hasTimestamps
            )
        } else {
            result = mergeResults(
                ocr: ocrFrameResults,
                speech: speechResult.speech,
                duration: actualDuration,
                allowSpeechAlignment: speechResult.hasTimestamps
            )
        }

        result.speechSegments = speechResult.transcriptSegments
        result.cleanedSlides = await cleanedSlides(
            from: result.rawSlides,
            contentType: result.contentType,
            isCarousel: false
        )
        result.warnings.append(contentsOf: warnings)
        result.warnings = deduplicatedWarnings(result.warnings)
        result.quality = (result.quality == .degraded || quality == .degraded || !result.warnings.isEmpty)
            ? .degraded
            : .accurate

        progressHandler(.complete)
        print("InstagramAutoTranscriber: Transcription complete — \(result.cleanedSlides.count) slides, type: \(result.contentType)")

        return result
    }

    // MARK: - Frame Extraction (Memory-Safe)

    /// Extract frames and encode to JPEG immediately, releasing each raw CGImage after encoding.
    /// Returns lightweight JPEG Data (~25KB each) instead of raw CGImages (~8MB each).
    private func extractFramesAsJPEG(
        videoURL: URL,
        duration: TimeInterval,
        fps: Double,
        maxFrames: Int,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> [(jpegData: Data, timestamp: TimeInterval)] {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.08, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
        // Downscale to 540px wide (half of 1080) — sufficient for text OCR, saves ~75% memory during encoding
        generator.maximumSize = CGSize(width: 540, height: 960)

        let effectiveFPS = min(fps, Double(maxFrames) / max(duration, 0.1))
        let frameCount = min(maxFrames, Int(duration * effectiveFPS))
        guard frameCount > 0 else { return [] }

        let frameTimes: [CMTime] = (0..<frameCount).map { i in
            CMTime(seconds: Double(i) / effectiveFPS, preferredTimescale: 600)
        }

        var jpegFrames: [(jpegData: Data, timestamp: TimeInterval)] = []
        jpegFrames.reserveCapacity(frameCount)

        for (index, time) in frameTimes.enumerated() {
            // Report progress every 5th frame to reduce main actor contention
            if index % 5 == 0 || index == frameTimes.count - 1 {
                let progress = Double(index + 1) / Double(frameTimes.count)
                progressHandler(.extractingFrames(progress))
            }

            do {
                let (cgImage, _) = try await generator.image(at: time)

                // Encode to JPEG immediately — CGImage is released at end of this scope
                autoreleasepool {
                    let mutableData = NSMutableData()
                    if let destination = CGImageDestinationCreateWithData(
                        mutableData, "public.jpeg" as CFString, 1, nil
                    ) {
                        CGImageDestinationAddImage(destination, cgImage, [
                            kCGImageDestinationLossyCompressionQuality: 0.7
                        ] as CFDictionary)
                        if CGImageDestinationFinalize(destination) {
                            jpegFrames.append((mutableData as Data, time.seconds))
                        }
                    }
                }
                // cgImage + all CF objects freed
            } catch {
                continue
            }
        }

        // Safety net: ensure we captured a frame near the very start of the video.
        // AVAssetImageGenerator can miss frame 0 if the first keyframe is offset.
        if jpegFrames.isEmpty || jpegFrames[0].timestamp > 0.5 {
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: .zero) {
                autoreleasepool {
                    let mutableData = NSMutableData()
                    if let destination = CGImageDestinationCreateWithData(
                        mutableData, "public.jpeg" as CFString, 1, nil
                    ) {
                        CGImageDestinationAddImage(destination, cgImage, [
                            kCGImageDestinationLossyCompressionQuality: 0.7
                        ] as CFDictionary)
                        if CGImageDestinationFinalize(destination) {
                            jpegFrames.insert((mutableData as Data, 0.0), at: 0)
                        }
                    }
                }
            }
        }

        // Safety net: ensure we captured a frame near the very end of the video.
        let lastTs = jpegFrames.last?.timestamp ?? 0
        if duration - lastTs > 0.75 {
            let endTime = CMTime(seconds: max(0, duration - 0.15), preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: endTime) {
                autoreleasepool {
                    let mutableData = NSMutableData()
                    if let destination = CGImageDestinationCreateWithData(
                        mutableData, "public.jpeg" as CFString, 1, nil
                    ) {
                        CGImageDestinationAddImage(destination, cgImage, [
                            kCGImageDestinationLossyCompressionQuality: 0.7
                        ] as CFDictionary)
                        if CGImageDestinationFinalize(destination) {
                            jpegFrames.append((mutableData as Data, endTime.seconds))
                        }
                    }
                }
            }
        }

        // Release AVFoundation resources immediately
        generator.cancelAllCGImageGeneration()

        return jpegFrames
    }

    // MARK: - Gemini Vision Pipeline

    /// Run Gemini Flash 2.0 vision on pre-encoded JPEG frames
    private func runGeminiVisionPipeline(
        jpegFrames: [(jpegData: Data, timestamp: TimeInterval)],
        duration: TimeInterval,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> [TranscriptSlide]? {
        guard APIKeys.hasOpenRouter, let apiKey = APIKeys.openRouter else {
            print("InstagramAutoTranscriber: No OpenRouter API key, skipping Gemini pipeline")
            return nil
        }

        guard !jpegFrames.isEmpty else { return nil }

        progressHandler(.analyzingWithAI(0))

        // Batch frames (batch size 20, overlap 2)
        var batches: [[(jpegData: Data, timestamp: TimeInterval)]] = []
        var startIdx = 0
        while startIdx < jpegFrames.count {
            let endIdx = min(startIdx + geminiBatchSize, jpegFrames.count)
            batches.append(Array(jpegFrames[startIdx..<endIdx]))
            if endIdx >= jpegFrames.count { break } // All frames covered
            startIdx = endIdx - geminiBatchOverlap
        }

        print("InstagramAutoTranscriber: Gemini pipeline — \(jpegFrames.count) frames in \(batches.count) batches")

        var allBatchSlides: [[TranscriptSlide]] = []

        for (batchIndex, batch) in batches.enumerated() {
            let progress = Double(batchIndex + 1) / Double(batches.count)
            progressHandler(.analyzingWithAI(progress * 0.9)) // Reserve 10% for merge

            print("InstagramAutoTranscriber: Gemini batch \(batchIndex + 1)/\(batches.count) (\(batch.count) frames)...")

            do {
                let slides = try await callGeminiVision(
                    frameImages: batch.map(\.jpegData),
                    timestamps: batch.map(\.timestamp),
                    batchIndex: batchIndex,
                    apiKey: apiKey
                )
                print("InstagramAutoTranscriber: Batch \(batchIndex + 1) returned \(slides.count) slides")
                allBatchSlides.append(slides)
            } catch {
                print("InstagramAutoTranscriber: Gemini batch \(batchIndex + 1) failed: \(error.localizedDescription), retrying once...")
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s before retry
                do {
                    let retrySlides = try await callGeminiVision(
                        frameImages: batch.map(\.jpegData),
                        timestamps: batch.map(\.timestamp),
                        batchIndex: batchIndex,
                        apiKey: apiKey
                    )
                    print("InstagramAutoTranscriber: Batch \(batchIndex + 1) retry succeeded — \(retrySlides.count) slides")
                    allBatchSlides.append(retrySlides)
                } catch {
                    print("InstagramAutoTranscriber: Batch \(batchIndex + 1) retry also failed: \(error.localizedDescription)")
                    if batchIndex == 0 { return nil } // First batch failure = fall back to OCR
                }
            }

            // Brief delay between batches to avoid rate limits
            if batchIndex < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            }
        }

        progressHandler(.analyzingWithAI(1.0))

        guard !allBatchSlides.isEmpty else { return nil }

        let merged = mergeGeminiBatchResults(batches: allBatchSlides)
        print("InstagramAutoTranscriber: Gemini merged result — \(merged.count) slides")
        return merged.isEmpty ? nil : merged
    }

    /// Call Gemini Vision API for a batch of frames
    private func callGeminiVision(
        frameImages: [Data],
        timestamps: [TimeInterval],
        batchIndex: Int,
        apiKey: String
    ) async throws -> [TranscriptSlide] {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

        let timestampList = timestamps.enumerated().map { "Frame \($0.offset)=\(String(format: "%.1f", $0.element))s" }.joined(separator: ", ")

        let prompt = """
        You are analyzing \(frameImages.count) sequential frames from an Instagram reel, captured at ~4fps.
        Frame mapping: \(timestampList)

        TASK: Extract ALL creator-placed text overlays and segment them into slides (distinct text screens).

        CRITICAL REQUIREMENTS:
        1. FIRST FRAME IS THE HOOK: Frame 0's text is the opening hook of this reel. You MUST capture it completely as your first slide. Never skip or merge it with later slides.
        2. EVERY UNIQUE TEXT = ONE SLIDE: Each time the body text changes between frames, that is a new slide — even if a header (like a year) stays the same. Do NOT merge distinct text screens.
        3. COMPLETE TEXT: For each slide, include the FULL text visible — every word, every number, every line. Do NOT truncate, summarize, or abbreviate.
        4. LAST FRAMES MATTER: The final frames' text must be captured as the last slide. Do not omit ending slides.
        5. ANIMATION HANDLING: If text appears gradually (animation/fade-in), use the fully-visible version as the slide text.

        TEXT TO READ:
        - Year/date headers (e.g., "2016", "Age 12", "1618")
        - Main statement, fact, quote, or caption text
        - Title cards, chapter markers, call-to-action text

        TEXT TO IGNORE:
        - Instagram UI (like counts, username, share/comment buttons, progress bar)
        - Watermarks, @handles, brand logos
        - Music credits, audio attribution
        - Text that is part of background photographs (not overlaid by the creator)

        OUTPUT FORMAT — return ONLY valid JSON:
        {"slides": [{"text": "Full slide text", "startFrame": 0, "endFrame": 3}]}

        FORMATTING:
        - Join visual line breaks into one flowing sentence (do NOT preserve line wrapping from the video)
        - If there is a year/date header, put it first then newline then body: "2016\\nWe started a new business in sales"
        - startFrame/endFrame are 0-indexed within this batch
        - Same text across consecutive frames = ONE slide with wider frame range
        """

        // Build content array: text prompt + image_url entries
        var contentArray: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]

        for frameData in frameImages {
            let base64 = frameData.base64EncodedString()
            contentArray.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ])
        }

        let requestBody: [String: Any] = [
            "model": geminiModel,
            "messages": [
                ["role": "user", "content": contentArray]
            ],
            "temperature": 0.1,
            "max_tokens": 8000
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "GeminiVision", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "API error \(statusCode): \(body.prefix(200))"])
        }

        // Parse OpenRouter response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "GeminiVision", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response structure"])
        }

        // Parse JSON from response (handle markdown code blocks)
        return parseGeminiSlides(from: content, timestamps: timestamps, batchIndex: batchIndex)
    }

    /// Parse Gemini's JSON response into TranscriptSlides
    private func parseGeminiSlides(
        from response: String,
        timestamps: [TimeInterval],
        batchIndex: Int
    ) -> [TranscriptSlide] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract JSON object with "slides" key
        var jsonString = trimmed

        // Strip markdown code fences if present
        if jsonString.hasPrefix("```") {
            if let firstNewline = jsonString.firstIndex(of: "\n") {
                jsonString = String(jsonString[firstNewline...])
            }
            if jsonString.hasSuffix("```") {
                jsonString = String(jsonString.dropLast(3))
            }
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find JSON object boundaries
        guard let braceStart = jsonString.firstIndex(of: "{"),
              let braceEnd = jsonString.lastIndex(of: "}") else {
            // Fallback: try parsing as a raw array
            return parseGeminiSlidesArray(from: jsonString, timestamps: timestamps)
        }

        let jsonSubstring = String(jsonString[braceStart...braceEnd])

        guard let data = jsonSubstring.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let slidesArray = obj["slides"] as? [[String: Any]] else {
            return parseGeminiSlidesArray(from: jsonString, timestamps: timestamps)
        }

        return slidesArray.enumerated().compactMap { index, slideObj -> TranscriptSlide? in
            guard let text = slideObj["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let startFrame = slideObj["startFrame"] as? Int ?? 0
            let endFrame = slideObj["endFrame"] as? Int ?? startFrame

            let startTs = startFrame < timestamps.count ? timestamps[startFrame] : nil
            let endTs = endFrame < timestamps.count ? timestamps[endFrame] : startTs

            return TranscriptSlide(
                text: joinVisualLineBreaks(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                slideNumber: index + 1,
                timestamp: startTs,
                endTimestamp: endTs,
                source: .geminiVision
            )
        }
    }

    /// Join visual line breaks within slide body text.
    /// Keeps the year/date header on its own line but joins all body lines into one sentence.
    private func joinVisualLineBreaks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        guard lines.count > 1 else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Check if the first line is a year/date header (e.g., "2016", "Age 12", "1618")
        let firstLine = lines[0]
        let isYearHeader = firstLine.count <= 10 && firstLine.range(
            of: #"^(age\s*)?\d{2,4}"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        if isYearHeader {
            let body = lines.dropFirst().joined(separator: " ")
            return firstLine + "\n" + body
        } else {
            return lines.joined(separator: " ")
        }
    }

    /// Fallback: parse a raw JSON array of slide objects
    private func parseGeminiSlidesArray(
        from response: String,
        timestamps: [TimeInterval]
    ) -> [TranscriptSlide] {
        guard let bracketStart = response.firstIndex(of: "["),
              let bracketEnd = response.lastIndex(of: "]") else {
            return []
        }

        let arrayString = String(response[bracketStart...bracketEnd])
        guard let data = arrayString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.enumerated().compactMap { index, obj -> TranscriptSlide? in
            guard let text = obj["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let startFrame = obj["startFrame"] as? Int ?? 0
            let startTs = startFrame < timestamps.count ? timestamps[startFrame] : nil
            return TranscriptSlide(
                text: joinVisualLineBreaks(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                slideNumber: index + 1,
                timestamp: startTs,
                source: .geminiVision
            )
        }
    }

    /// Merge slides from multiple Gemini batches, deduplicating at boundaries
    func mergeGeminiBatchResults(batches: [[TranscriptSlide]]) -> [TranscriptSlide] {
        guard !batches.isEmpty else { return [] }

        var merged: [TranscriptSlide] = []

        for batch in batches {
            for slide in batch {
                let trimmedText = slide.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedText.isEmpty else { continue }

                if var lastSlide = merged.last, shouldMergeGeminiBoundarySlides(lastSlide, slide) {
                    if trimmedText.count > lastSlide.text.count {
                        lastSlide.text = trimmedText
                    }
                    if let newEnd = slide.endTimestamp ?? slide.timestamp {
                        lastSlide.endTimestamp = newEnd
                    }
                    merged[merged.count - 1] = lastSlide
                    continue
                }

                merged.append(slide)
            }
        }

        // Renumber sequentially
        for i in merged.indices {
            merged[i].slideNumber = i + 1
        }

        return merged
    }

    /// Merge Gemini visual slides with speech segments
    private func mergeGeminiWithSpeech(
        geminiSlides: [TranscriptSlide],
        speech: [SpeechSegment],
        duration: TimeInterval,
        allowSpeechAlignment: Bool
    ) -> TranscriptionResult {
        let hasGemini = !geminiSlides.isEmpty
        let hasSpeech = !speech.isEmpty

        if hasGemini && hasSpeech {
            let contentType = detectTranscriptionContentType(
                visualSlides: geminiSlides,
                speech: speech,
                duration: duration
            )

            if contentType == .voiceoverOnly {
                let evidence = reelModalityEvidence(
                    visualSlides: geminiSlides,
                    speech: speech,
                    duration: duration
                )
                print("InstagramAutoTranscriber: Voiceover dominant over Gemini (\(evidence.visualWordCount) visual words in \(geminiSlides.count) slides vs \(evidence.speechWordCount) speech words, overlap: \(String(format: "%.2f", evidence.subtitleOverlapRatio))) — treating as voiceover-only")
                return transcriptionResult(
                    rawSlides: speechToSlides(speech: speech),
                    contentType: .voiceoverOnly,
                    averageOCRConfidence: 1.0
                )
            }

            let slides: [TranscriptSlide]
            switch contentType {
            case .textOnly:
                slides = renumberedSlides(geminiSlides)
            case .voiceoverPlusText:
                slides = mergeVisualSlidesWithSpeech(
                    visualSlides: geminiSlides,
                    speech: speech,
                    allowSpeechAlignment: allowSpeechAlignment
                )
            case .voiceoverOnly, .empty:
                slides = speechToSlides(speech: speech)
            }

            return transcriptionResult(
                rawSlides: slides,
                contentType: contentType,
                averageOCRConfidence: 0.95
            )
        } else if hasGemini {
            return transcriptionResult(
                rawSlides: renumberedSlides(geminiSlides),
                contentType: .textOnly,
                averageOCRConfidence: 0.95
            )
        } else if hasSpeech {
            return transcriptionResult(
                rawSlides: speechToSlides(speech: speech),
                contentType: .voiceoverOnly,
                averageOCRConfidence: 1.0
            )
        } else {
            return transcriptionResult(
                rawSlides: [TranscriptSlide(text: "", slideNumber: 1, source: .manual)],
                contentType: .empty,
                averageOCRConfidence: 0
            )
        }
    }

    // MARK: - Vision OCR Pipeline (Fallback)

    /// Extract frames and run text recognition
    private func runOCRPipeline(
        jpegFrames: [(jpegData: Data, timestamp: TimeInterval)],
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> [OCRFrameResult] {
        guard !jpegFrames.isEmpty else { return [] }

        var results: [OCRFrameResult] = []

        for (index, frame) in jpegFrames.enumerated() {
            let progress = Double(index + 1) / Double(jpegFrames.count)
            progressHandler(.recognizingText(progress))

            guard let cgImage = createCGImage(from: frame.jpegData) else {
                continue
            }

            let ocrResult = await recognizeText(in: cgImage, at: frame.timestamp)
            if let result = ocrResult {
                results.append(result)
            }
        }

        progressHandler(.recognizingText(1.0))

        return results
    }

    /// Minimum bounding box height (normalized 0-1) for an OCR observation to be considered main text.
    /// Instagram reel overlays typically have heights > 3-4% of the frame. Background text, watermarks,
    /// and incidental text in images tend to be much smaller.
    private let minBoundingBoxHeight: CGFloat = 0.025

    /// Run VNRecognizeTextRequest on a single frame
    private func recognizeText(in image: CGImage, at timestamp: TimeInterval, minBoxOverride: CGFloat? = nil) async -> OCRFrameResult? {
        let minLineConfidence = self.minLineConfidence
        let minBoxHeight = minBoxOverride ?? self.minBoundingBoxHeight
        return await withCheckedContinuation { (continuation: CheckedContinuation<OCRFrameResult?, Never>) in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // Filter out small background text by bounding box height.
                // Main overlay text on reels is large/prominent; incidental background
                // text (watermarks, text in images, UI elements) is small.
                let filteredObservations = observations.filter { obs in
                    obs.boundingBox.height >= minBoxHeight
                }

                guard !filteredObservations.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let sortedObservations = filteredObservations.sorted { lhs, rhs in
                    let lhsY = lhs.boundingBox.midY
                    let rhsY = rhs.boundingBox.midY
                    if abs(lhsY - rhsY) > 0.02 {
                        return lhsY > rhsY // top -> bottom
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX // left -> right
                }

                var lines: [String] = []
                var normalizedLineSet = Set<String>()
                var totalConfidence: Float = 0
                var acceptedCount = 0

                for observation in sortedObservations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    guard candidate.confidence >= minLineConfidence else { continue }
                    guard let cleaned = self.cleanOCRLine(candidate.string) else { continue }

                    let normalized = self.normalizedLineKey(cleaned)
                    guard !normalized.isEmpty else { continue }
                    guard !normalizedLineSet.contains(normalized) else { continue }

                    lines.append(cleaned)
                    normalizedLineSet.insert(normalized)
                    totalConfidence += candidate.confidence
                    acceptedCount += 1
                }

                guard !lines.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let avgConfidence = totalConfidence / Float(max(acceptedCount, 1))
                continuation.resume(returning: OCRFrameResult(
                    timestamp: timestamp,
                    lines: lines,
                    normalizedLineSet: normalizedLineSet,
                    confidence: avgConfidence
                ))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Speech Pipeline

    private func runSpeechPipelineWithFallback(
        videoURL: URL,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> SpeechPipelineResult {
        guard await hasUsableAudioTrack(videoURL) else {
            print("InstagramAutoTranscriber: Skipping speech pipeline (no audio track)")
            return .empty
        }

        progressHandler(.recognizingSpeech(0.1))

        guard let audioURL = await extractAudioToTemporaryM4A(from: videoURL) else {
            print("InstagramAutoTranscriber: Audio extraction failed, using Apple Speech fallback")
            return await runAppleSpeechPipeline(
                videoURL: videoURL,
                progressHandler: progressHandler,
                extraWarnings: ["Audio export failed; using lower-accuracy Apple Speech fallback."]
            )
        }
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let audioData = try? Data(contentsOf: audioURL)
        var apiFallbackWithoutTimestamps: SpeechPipelineResult?

        if APIKeys.hasWhisper, let audioData, !audioData.isEmpty {
            print("InstagramAutoTranscriber: Extracted audio (\(audioData.count / 1024)KB), sending to Whisper API...")
            progressHandler(.recognizingSpeech(0.3))

            do {
                let verbose = try await WhisperTranscriptionService.shared.transcribeVerbose(
                    audioData: audioData,
                    format: .m4a
                )
                let transcriptSegments = transcriptSegments(from: verbose)
                let speech = speechSegments(from: transcriptSegments)

                if !speech.isEmpty {
                    if transcriptSegments.contains(where: { $0.end > $0.start }) {
                        progressHandler(.recognizingSpeech(1.0))
                        return SpeechPipelineResult(
                            speech: speech,
                            transcriptSegments: transcriptSegments,
                            quality: .accurate,
                            warnings: [],
                            source: .whisperAPI
                        )
                    }

                    apiFallbackWithoutTimestamps = SpeechPipelineResult(
                        speech: speech,
                        transcriptSegments: transcriptSegments,
                        quality: .degraded,
                        warnings: ["Whisper API returned transcript text without usable timestamps."],
                        source: .whisperAPI
                    )
                }
            } catch {
                print("InstagramAutoTranscriber: Whisper API failed: \(error.localizedDescription)")
            }
        }

        progressHandler(.recognizingSpeech(0.55))

        if let daemonResult = await runDaemonWhisperPipeline(audioURL: audioURL, progressHandler: progressHandler) {
            return daemonResult
        }

        if let apiFallbackWithoutTimestamps {
            progressHandler(.recognizingSpeech(1.0))
            return apiFallbackWithoutTimestamps
        }

        return await runAppleSpeechPipeline(
            videoURL: videoURL,
            progressHandler: progressHandler,
            extraWarnings: ["Used Apple Speech fallback; transcript quality may be degraded."]
        )
    }

    /// Extract audio track from video file to a temporary M4A file so the same export can be reused
    /// by Whisper API and local daemon fallback paths.
    private func extractAudioToTemporaryM4A(from videoURL: URL) async -> URL? {
        let asset = AVURLAsset(url: videoURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper_\(UUID().uuidString).m4a")

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }

        exporter.outputFileType = .m4a
        exporter.outputURL = outputURL

        await exporter.export()

        guard exporter.status == .completed else {
            print("InstagramAutoTranscriber: Audio export failed: \(exporter.error?.localizedDescription ?? "unknown")")
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        return outputURL
    }

    private func runDaemonWhisperPipeline(
        audioURL: URL,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> SpeechPipelineResult? {
        guard let audioSamples = extractWhisperSamples(from: audioURL) else {
            print("InstagramAutoTranscriber: Could not extract 16kHz samples for daemon Whisper")
            return nil
        }

        do {
            progressHandler(.recognizingSpeech(0.75))
            let whisper = try await L2WhisperASR().transcribe(audioSamples: audioSamples, language: "en")
            let transcriptSegments = whisper.segments.map {
                TranscriptSegment(
                    start: $0.start,
                    end: $0.end,
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: $0.confidence
                )
            }.filter { !$0.text.isEmpty }
            let speech = speechSegments(from: transcriptSegments)
            guard !speech.isEmpty else { return nil }
            progressHandler(.recognizingSpeech(1.0))
            return SpeechPipelineResult(
                speech: speech,
                transcriptSegments: transcriptSegments,
                quality: .accurate,
                warnings: [],
                source: .daemonWhisper
            )
        } catch {
            print("InstagramAutoTranscriber: Daemon Whisper fallback failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func transcriptSegments(from verbose: WhisperVerboseTranscription) -> [TranscriptSegment] {
        let cleanedSegments = verbose.segments.compactMap { segment -> TranscriptSegment? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(
                start: segment.start,
                end: segment.end,
                text: text,
                confidence: segment.confidence
            )
        }

        if !cleanedSegments.isEmpty {
            return cleanedSegments
        }

        let fallbackText = verbose.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackText.isEmpty else { return [] }
        return [TranscriptSegment(start: 0, end: 0, text: fallbackText, confidence: nil)]
    }

    private func speechSegments(from transcriptSegments: [TranscriptSegment]) -> [SpeechSegment] {
        transcriptSegments.map {
            SpeechSegment(
                text: $0.text,
                timestamp: $0.start,
                duration: max(0, $0.end - $0.start)
            )
        }
    }

    private func extractWhisperSamples(from audioURL: URL) -> Data? {
        guard let audioFile = try? AVAudioFile(forReading: audioURL) else {
            return nil
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        let sourceFormat = audioFile.processingFormat
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return nil
        }

        let frameCapacity = AVAudioFrameCount(audioFile.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: max(frameCapacity, 1)) else {
            return nil
        }

        do {
            try audioFile.read(into: inputBuffer)
        } catch {
            print("InstagramAutoTranscriber: Failed reading audio file for Whisper fallback: \(error.localizedDescription)")
            return nil
        }

        let outputCapacity = AVAudioFrameCount(
            Double(inputBuffer.frameLength) * targetFormat.sampleRate / max(sourceFormat.sampleRate, 1)
        ) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(outputCapacity, 1)) else {
            return nil
        }

        // AVAudioConverterInputBlock executes synchronously within convert() —
        // safe to capture mutable state and non-Sendable buffer.
        nonisolated(unsafe) var didConsumeInput = false
        nonisolated(unsafe) let capturedInput = inputBuffer
        var conversionError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if didConsumeInput {
                outStatus.pointee = .endOfStream
                return nil
            }
            didConsumeInput = true
            outStatus.pointee = .haveData
            return capturedInput
        }

        let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        guard conversionError == nil, status == .haveData || status == .inputRanDry else {
            print("InstagramAutoTranscriber: Audio conversion for Whisper fallback failed: \(conversionError?.localizedDescription ?? "unknown")")
            return nil
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else { return nil }
        let samples = UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength))
        guard let baseAddress = samples.baseAddress else { return nil }
        return Data(bytes: baseAddress, count: samples.count * MemoryLayout<Float>.size)
    }

    // MARK: - Speech Recognition Pipeline (Fallback)

    /// Run speech recognition on the video (with 45-second timeout to prevent hangs)
    private func runAppleSpeechPipeline(
        videoURL: URL,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void,
        extraWarnings: [String] = []
    ) async -> SpeechPipelineResult {
        guard await hasUsableAudioTrack(videoURL) else {
            print("InstagramAutoTranscriber: Skipping speech pipeline (no audio track)")
            return .empty
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            print("InstagramAutoTranscriber: SFSpeechRecognizer unavailable")
            return SpeechPipelineResult(
                speech: [],
                transcriptSegments: [],
                quality: .degraded,
                warnings: deduplicatedWarnings(extraWarnings + ["Apple Speech recognizer was unavailable."]),
                source: .appleSpeech
            )
        }

        let authStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authStatus == .authorized else {
            print("InstagramAutoTranscriber: Speech recognition not authorized")
            return SpeechPipelineResult(
                speech: [],
                transcriptSegments: [],
                quality: .degraded,
                warnings: deduplicatedWarnings(extraWarnings + ["Speech recognition permission was not granted."]),
                source: .appleSpeech
            )
        }

        // Thread-safe gate ensures the continuation is resumed exactly once,
        // even if the callback and timeout fire concurrently.
        final class ResumeGate: @unchecked Sendable {
            private let lock = NSLock()
            private var didResume = false

            func run(_ action: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                action()
            }
        }

        print("InstagramAutoTranscriber: Starting speech recognition...")

        let speech = await withCheckedContinuation { continuation in
            let resumeGate = ResumeGate()
            let request = SFSpeechURLRecognitionRequest(url: videoURL)
            request.requiresOnDeviceRecognition = true
            request.addsPunctuation = true
            request.shouldReportPartialResults = false

            let recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let result = result, result.isFinal {
                    print("InstagramAutoTranscriber: Speech recognition completed successfully")
                    Task { @MainActor in
                        progressHandler(.recognizingSpeech(1.0))
                    }
                    let segments = self.consolidateSegments(from: result)
                    resumeGate.run {
                        continuation.resume(returning: segments)
                    }
                } else if let error = error {
                    print("InstagramAutoTranscriber: Speech recognition error: \(error.localizedDescription)")
                    resumeGate.run {
                        continuation.resume(returning: [SpeechSegment]())
                    }
                }
                // If result is partial or (nil result + nil error), wait for next callback
            }

            // Safety timeout: cancel speech recognition after 45 seconds.
            // SFSpeechRecognizer can hang indefinitely on some files (especially with
            // requiresOnDeviceRecognition=true), which blocks the entire transcription
            // pipeline and causes unbounded memory growth.
            DispatchQueue.global().asyncAfter(deadline: .now() + 45) {
                if recognitionTask.state == .running || recognitionTask.state == .starting {
                    print("InstagramAutoTranscriber: Speech recognition timed out after 45s, cancelling")
                    recognitionTask.cancel()
                }
                // Backup: if cancel() doesn't trigger the callback within 3s, force-resume
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    resumeGate.run {
                        print("InstagramAutoTranscriber: Force-resuming speech continuation after timeout")
                        continuation.resume(returning: [SpeechSegment]())
                    }
                }
            }
        }

        let transcriptSegments = speech.map {
            TranscriptSegment(
                start: $0.timestamp,
                end: $0.timestamp + $0.duration,
                text: $0.text,
                confidence: nil
            )
        }

        return SpeechPipelineResult(
            speech: speech,
            transcriptSegments: transcriptSegments,
            quality: .degraded,
            warnings: deduplicatedWarnings(extraWarnings),
            source: .appleSpeech
        )
    }

    private func hasUsableAudioTrack(_ videoURL: URL) async -> Bool {
        let asset = AVURLAsset(url: videoURL)
        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            return !audioTracks.isEmpty
        } catch {
            print("InstagramAutoTranscriber: Failed loading audio tracks: \(error.localizedDescription)")
            return false
        }
    }

    /// Consolidate individual word segments into sentence-level segments
    private func consolidateSegments(from result: SFSpeechRecognitionResult) -> [SpeechSegment] {
        let transcript = result.bestTranscription
        guard !transcript.segments.isEmpty else { return [] }

        var sentences: [SpeechSegment] = []
        var currentText = ""
        var sentenceStart: TimeInterval = 0
        var lastTimestamp: TimeInterval = 0

        for segment in transcript.segments {
            let word = segment.substring
            let wordTime = segment.timestamp
            let wordDuration = segment.duration

            if currentText.isEmpty {
                sentenceStart = wordTime
            }

            currentText += (currentText.isEmpty ? "" : " ") + word
            lastTimestamp = wordTime + wordDuration

            // Sentence boundary: punctuation or long pause (> 1.5s gap)
            let isPunctuation = word.hasSuffix(".") || word.hasSuffix("!") || word.hasSuffix("?")
            let nextSegmentIndex = transcript.segments.firstIndex(where: { $0.timestamp > wordTime + wordDuration })
            let hasLongPause: Bool
            if let nextIdx = nextSegmentIndex {
                hasLongPause = transcript.segments[nextIdx].timestamp - lastTimestamp > 1.5
            } else {
                hasLongPause = true // Last segment
            }

            if isPunctuation || hasLongPause {
                let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(SpeechSegment(
                        text: trimmed,
                        timestamp: sentenceStart,
                        duration: lastTimestamp - sentenceStart
                    ))
                }
                currentText = ""
            }
        }

        // Flush remaining text
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(SpeechSegment(
                text: trimmed,
                timestamp: sentenceStart,
                duration: lastTimestamp - sentenceStart
            ))
        }

        return sentences
    }

    // MARK: - Merge Logic

    func detectTranscriptionContentType(
        visualSlides: [TranscriptSlide],
        speech: [SpeechSegment],
        duration: TimeInterval
    ) -> TranscriptionContentType {
        let hasVisual = visualSlides.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasSpeech = speech.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !hasVisual && !hasSpeech { return .empty }
        if !hasVisual { return .voiceoverOnly }
        if !hasSpeech { return .textOnly }

        let evidence = reelModalityEvidence(
            visualSlides: visualSlides,
            speech: speech,
            duration: duration
        )

        if evidence.shouldPreferVoiceover { return .voiceoverOnly }
        if evidence.shouldTreatAsTextOnly { return .textOnly }
        return .voiceoverPlusText
    }

    private func reelModalityEvidence(
        visualSlides: [TranscriptSlide],
        speech: [SpeechSegment],
        duration: TimeInterval
    ) -> ReelModalityEvidence {
        let visualTexts = visualSlides
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let speechTexts = speech
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let visualWordCounts = visualTexts.map(wordCount(in:))
        let speechWordCounts = speechTexts.map(wordCount(in:))

        let visualWordCount = visualWordCounts.reduce(0, +)
        let speechWordCount = speechWordCounts.reduce(0, +)
        let visualSlideCount = visualTexts.count
        let avgVisualWordsPerSlide = visualSlideCount > 0
            ? Double(visualWordCount) / Double(visualSlideCount)
            : 0
        let shortVisualSlideRatio = visualSlideCount > 0
            ? Double(visualWordCounts.filter { $0 <= 4 }.count) / Double(visualSlideCount)
            : 0
        let longVisualSlideRatio = visualSlideCount > 0
            ? Double(visualWordCounts.filter { $0 >= 8 }.count) / Double(visualSlideCount)
            : 0

        let distinctVisualCount = Set(visualTexts.map(normalizedLineKey)).filter { !$0.isEmpty }.count
        let distinctVisualRatio = visualSlideCount > 0
            ? Double(distinctVisualCount) / Double(visualSlideCount)
            : 0

        let subtitleOverlapRatio = subtitleOverlapRatio(visualSlides: visualSlides, speech: speech)

        let totalSpeechDuration = speech.reduce(0.0) { partial, segment in
            partial + max(segment.duration, 0)
        }
        let speechCoverageRatio = duration > 0
            ? min(totalSpeechDuration / duration, 1.0)
            : 0
        let speechWordsPerSecond = duration > 0
            ? Double(speechWordCount) / duration
            : Double(speechWordCount)
        let avgSpeechWordsPerSegment = !speechWordCounts.isEmpty
            ? Double(speechWordCount) / Double(speechWordCounts.count)
            : 0

        let speechTokens = tokenSet(from: speechTexts.joined(separator: " "))
        let speechUniqueWordRatio = speechWordCount > 0
            ? Double(speechTokens.count) / Double(speechWordCount)
            : 0

        let normalizedSegments = speechTexts.map(normalizedLineKey).filter { !$0.isEmpty }
        var segmentFrequency: [String: Int] = [:]
        for segment in normalizedSegments {
            segmentFrequency[segment, default: 0] += 1
        }
        let repeatedSegments = segmentFrequency.values.filter { $0 > 1 }.reduce(0, +)
        let repeatedSpeechSegmentRatio = normalizedSegments.isEmpty
            ? 0
            : Double(repeatedSegments) / Double(normalizedSegments.count)

        var lyricRisk = 0
        if speechWordCount > 0 && speechWordCount < 24 && avgSpeechWordsPerSegment <= 4.5 { lyricRisk += 1 }
        if speechUniqueWordRatio < 0.55 { lyricRisk += 1 }
        if repeatedSpeechSegmentRatio >= 0.2 { lyricRisk += 1 }
        if speechWordsPerSecond < 0.9 { lyricRisk += 1 }
        if subtitleOverlapRatio >= 0.7 && speechCoverageRatio < 0.25 { lyricRisk += 1 }

        var voiceoverScore = 0
        if speechWordCount >= 18 { voiceoverScore += 2 }
        else if speechWordCount >= 10 { voiceoverScore += 1 }
        if speechCoverageRatio >= 0.35 { voiceoverScore += 1 }
        if speechWordsPerSecond >= 1.4 { voiceoverScore += 1 }
        if subtitleOverlapRatio >= 0.58 { voiceoverScore += 2 }
        else if subtitleOverlapRatio >= 0.4 { voiceoverScore += 1 }
        if shortVisualSlideRatio >= 0.6 && visualSlideCount >= 5 { voiceoverScore += 1 }
        if speechWordCount >= max(visualWordCount, 20) { voiceoverScore += 1 }

        var textScore = 0
        if visualWordCount >= 30 { textScore += 1 }
        if avgVisualWordsPerSlide >= 7 { textScore += 1 }
        if visualSlideCount >= 4 && avgVisualWordsPerSlide >= 6 && subtitleOverlapRatio < 0.4 { textScore += 2 }
        if distinctVisualRatio >= 0.75 && longVisualSlideRatio >= 0.5 { textScore += 1 }
        if speechWordCount <= 8 { textScore += 1 }

        return ReelModalityEvidence(
            visualWordCount: visualWordCount,
            speechWordCount: speechWordCount,
            visualSlideCount: visualSlideCount,
            avgVisualWordsPerSlide: avgVisualWordsPerSlide,
            shortVisualSlideRatio: shortVisualSlideRatio,
            longVisualSlideRatio: longVisualSlideRatio,
            distinctVisualRatio: distinctVisualRatio,
            subtitleOverlapRatio: subtitleOverlapRatio,
            speechCoverageRatio: speechCoverageRatio,
            speechWordsPerSecond: speechWordsPerSecond,
            avgSpeechWordsPerSegment: avgSpeechWordsPerSegment,
            speechUniqueWordRatio: speechUniqueWordRatio,
            repeatedSpeechSegmentRatio: repeatedSpeechSegmentRatio,
            lyricRisk: lyricRisk,
            voiceoverScore: voiceoverScore,
            textScore: textScore
        )
    }

    /// Merge OCR and speech results based on what was detected
    private func mergeResults(
        ocr: [OCRFrameResult],
        speech: [SpeechSegment],
        duration: TimeInterval,
        allowSpeechAlignment: Bool
    ) -> TranscriptionResult {
        let hasOCR = !ocr.isEmpty
        let hasSpeech = !speech.isEmpty

        var contentType: TranscriptionContentType
        var slides: [TranscriptSlide]
        let avgConfidence: Float

        if hasOCR && hasSpeech {
            let ocrSlides = ocrToSlides(ocr: ocr)
            let detectedContentType = detectTranscriptionContentType(
                visualSlides: ocrSlides,
                speech: speech,
                duration: duration
            )

            if detectedContentType == .voiceoverOnly {
                let evidence = reelModalityEvidence(
                    visualSlides: ocrSlides,
                    speech: speech,
                    duration: duration
                )
                print("InstagramAutoTranscriber: Voiceover dominant (\(evidence.visualWordCount) visual words in \(ocrSlides.count) slides vs \(evidence.speechWordCount) speech words, overlap: \(String(format: "%.2f", evidence.subtitleOverlapRatio))) — treating as voiceover-only")
                contentType = .voiceoverOnly
                slides = speechToSlides(speech: speech)
                avgConfidence = 1.0
            } else if detectedContentType == .textOnly {
                contentType = .textOnly
                slides = ocrSlides
                avgConfidence = ocr.map(\.confidence).reduce(0, +) / Float(ocr.count)
            } else {
                contentType = .voiceoverPlusText
                slides = mergeVoiceoverPlusText(
                    ocr: ocr,
                    speech: speech,
                    allowSpeechAlignment: allowSpeechAlignment
                )
                avgConfidence = ocr.map(\.confidence).reduce(0, +) / Float(ocr.count)
            }
        } else if hasOCR {
            contentType = .textOnly
            slides = ocrToSlides(ocr: ocr)
            avgConfidence = ocr.map(\.confidence).reduce(0, +) / Float(ocr.count)
        } else if hasSpeech {
            contentType = .voiceoverOnly
            slides = speechToSlides(speech: speech)
            avgConfidence = 1.0 // Speech doesn't have per-word confidence in the same way
        } else {
            contentType = .empty
            slides = [TranscriptSlide(text: "", slideNumber: 1, source: .manual)]
            avgConfidence = 0
        }

        if slides.isEmpty {
            contentType = .empty
            slides = [TranscriptSlide(text: "", slideNumber: 1, source: .manual)]
        }

        return transcriptionResult(
            rawSlides: slides,
            contentType: contentType,
            averageOCRConfidence: avgConfidence
        )
    }

    /// Convert OCR results into slides by detecting slide changes via Jaccard similarity
    func ocrToSlides(ocr: [OCRFrameResult]) -> [TranscriptSlide] {
        guard !ocr.isEmpty else { return [] }

        let sortedFrames = ocr.sorted { $0.timestamp < $1.timestamp }
        var slides: [TranscriptSlide] = []
        var currentCluster: [OCRFrameResult] = []
        var slideStart: TimeInterval = sortedFrames[0].timestamp
        var slideNumber = 1

        func flushCluster(endTimestamp: TimeInterval?) {
            guard !currentCluster.isEmpty else { return }
            let text = buildSlideText(from: currentCluster)
            guard !text.isEmpty else { return }

            slides.append(TranscriptSlide(
                text: text,
                slideNumber: slideNumber,
                timestamp: slideStart,
                endTimestamp: endTimestamp,
                source: .visionOCR
            ))
            slideNumber += 1
        }

        for frame in sortedFrames {
            if currentCluster.isEmpty {
                currentCluster = [frame]
                slideStart = frame.timestamp
                continue
            }

            let previous = currentCluster.last!
            let similarity = jaccardSimilarity(previous.normalizedLineSet, frame.normalizedLineSet)

            if similarity < jaccardThreshold {
                flushCluster(endTimestamp: frame.timestamp)
                currentCluster = [frame]
                slideStart = frame.timestamp
            } else {
                currentCluster.append(frame)
            }
        }

        flushCluster(endTimestamp: sortedFrames.last?.timestamp)

        return slides
    }

    /// Convert speech segments into slides, grouping sentences to stay under the
    /// per-slide character limit. Short voiceovers become 1 slide; longer ones split
    /// at natural sentence boundaries.
    private func speechToSlides(speech: [SpeechSegment]) -> [TranscriptSlide] {
        guard !speech.isEmpty else { return [] }

        let charLimit = TranscriptSlide.characterLimit // 450

        var slides: [TranscriptSlide] = []
        var currentText = ""
        var slideStart: TimeInterval = speech[0].timestamp
        var slideEnd: TimeInterval = speech[0].timestamp + speech[0].duration
        var slideNumber = 1

        for segment in speech {
            let candidate = currentText.isEmpty ? segment.text : currentText + " " + segment.text

            if candidate.count > charLimit && !currentText.isEmpty {
                // Flush current slide
                slides.append(TranscriptSlide(
                    text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
                    slideNumber: slideNumber,
                    timestamp: slideStart,
                    endTimestamp: slideEnd,
                    source: .speechAudio
                ))
                slideNumber += 1
                currentText = segment.text
                slideStart = segment.timestamp
            } else {
                currentText = candidate
            }
            slideEnd = segment.timestamp + segment.duration
        }

        // Flush remaining
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            slides.append(TranscriptSlide(
                text: trimmed,
                slideNumber: slideNumber,
                timestamp: slideStart,
                endTimestamp: slideEnd,
                source: .speechAudio
            ))
        }

        return slides
    }

    /// Merge voiceover + text: visual slides are primary, speech appended as [Voiceover:] annotations.
    /// Consistent with the Gemini merge path — visual text defines the slide structure.
    private func mergeVoiceoverPlusText(
        ocr: [OCRFrameResult],
        speech: [SpeechSegment],
        allowSpeechAlignment: Bool
    ) -> [TranscriptSlide] {
        let visualSlides = ocrToSlides(ocr: ocr)
        guard !visualSlides.isEmpty else {
            // No visual slides detected — fall back to speech as single block
            return speechToSlides(speech: speech)
        }

        return mergeVisualSlidesWithSpeech(
            visualSlides: visualSlides,
            speech: speech,
            allowSpeechAlignment: allowSpeechAlignment
        )
    }

    func mergeVisualSlidesWithSpeech(
        visualSlides: [TranscriptSlide],
        speech: [SpeechSegment],
        allowSpeechAlignment: Bool
    ) -> [TranscriptSlide] {
        guard !allowSpeechAlignment else {
            var merged = renumberedSlides(visualSlides)
            for (idx, slide) in merged.enumerated() {
                let slideStart = slide.timestamp ?? 0
                let slideEnd = slide.endTimestamp ?? slideStart + 3

                let overlapping = speech.filter { segment in
                    let segmentEnd = segment.timestamp + max(segment.duration, 0)
                    return segment.timestamp <= slideEnd + 0.5 && segmentEnd >= slideStart - 0.5
                }

                if !overlapping.isEmpty {
                    let spokenText = overlapping.map(\.text).joined(separator: " ")
                    let slideNorm = normalizedLineKey(slide.text)
                    let speechNorm = normalizedLineKey(spokenText)
                    let overlapScore = tokenOverlapScore(lhs: slide.text, rhs: spokenText)
                    if !slideNorm.isEmpty, !speechNorm.isEmpty,
                       !slideNorm.contains(speechNorm), !speechNorm.contains(slideNorm),
                       overlapScore < 0.72 {
                        merged[idx].text += "\n[Voiceover: \(spokenText)]"
                        merged[idx].source = .merged
                    }
                }
            }

            return renumberedSlides(merged)
        }

        var appended = renumberedSlides(visualSlides)
        let speechSlides = speechToSlides(speech: speech)
        appended.append(contentsOf: speechSlides)
        return renumberedSlides(appended)
    }

    private func transcriptionResult(
        rawSlides: [TranscriptSlide],
        contentType: TranscriptionContentType,
        averageOCRConfidence: Float
    ) -> TranscriptionResult {
        let slides = renumberedSlides(rawSlides)
        return TranscriptionResult(
            rawSlides: slides,
            cleanedSlides: slides,
            speechSegments: [],
            contentType: contentType,
            averageOCRConfidence: averageOCRConfidence,
            quality: .accurate,
            warnings: []
        )
    }

    private func cleanedSlides(
        from rawSlides: [TranscriptSlide],
        contentType: TranscriptionContentType,
        isCarousel: Bool
    ) async -> [TranscriptSlide] {
        guard !rawSlides.isEmpty else { return [] }

        let postProcessed = postProcessSlides(rawSlides, contentType: contentType, isCarousel: isCarousel)
        let needsAIRefinement = contentType != .voiceoverOnly &&
            postProcessed.contains { ($0.source ?? .manual) != .speechAudio }

        guard needsAIRefinement else {
            return renumberedSlides(postProcessed)
        }

        if let refined = await cleanupWithClaude(slides: postProcessed, isCarousel: isCarousel) {
            let finalSlides = isCarousel ? trimSlideLines(refined) : refined
            return renumberedSlides(finalSlides)
        }

        return renumberedSlides(postProcessed)
    }

    private func renumberedSlides(_ slides: [TranscriptSlide]) -> [TranscriptSlide] {
        var updated = slides
        for index in updated.indices {
            updated[index].slideNumber = index + 1
        }
        return updated
    }

    func shouldMergeGeminiBoundarySlides(_ lhs: TranscriptSlide, _ rhs: TranscriptSlide) -> Bool {
        let lhsFingerprint = normalizedTextFingerprint(lhs.text)
        let rhsFingerprint = normalizedTextFingerprint(rhs.text)
        guard !lhsFingerprint.isEmpty, !rhsFingerprint.isEmpty else { return false }

        if lhsFingerprint == rhsFingerprint {
            return geminiSlidesOverlapInTime(lhs, rhs)
        }

        let lhsTokens = Set(lhsFingerprint.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhsFingerprint.split(separator: " ").map(String.init))
        let overlap = jaccardSimilarity(lhsTokens, rhsTokens)

        return overlap >= 0.92 && geminiSlidesOverlapInTime(lhs, rhs)
    }

    private func geminiSlidesOverlapInTime(_ lhs: TranscriptSlide, _ rhs: TranscriptSlide) -> Bool {
        guard let lhsStart = lhs.timestamp,
              let lhsEnd = lhs.endTimestamp ?? lhs.timestamp,
              let rhsStart = rhs.timestamp else {
            return false
        }

        return rhsStart <= lhsEnd + 0.35 && rhsStart >= lhsStart - 0.35
    }

    private func deduplicatedWarnings(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for warning in warnings.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !warning.isEmpty {
            if seen.insert(warning).inserted {
                ordered.append(warning)
            }
        }

        return ordered
    }

    // MARK: - Claude Cleanup

    /// Non-destructive refinement pass for OCR/Gemini slides.
    /// The response must preserve slide count and order.
    func cleanupWithClaude(slides: [TranscriptSlide], isCarousel: Bool = false) async -> [TranscriptSlide]? {
        guard !slides.isEmpty else { return nil }

        let slideTexts = slides.map(\.text)

        let lineBreakRule: String
        if isCarousel {
            lineBreakRule = """
            6. PRESERVE line breaks between sentences. Each sentence should be on its own line. \
            Do NOT merge sentences into flowing paragraphs. \
            However, if a single sentence is split across multiple lines due to OCR fragmentation, \
            join those fragments into one line.
            7. NEVER remove text that could be part of the creator's core message. When in doubt about \
            whether text is background/watermark vs. core content, KEEP IT. Only remove text you are \
            highly confident is a watermark, account handle overlay, or UI element.
            8. PRESERVE all numbers, numbered lists, statistics, currency amounts, and dates exactly as they appear.
            9. FORMAT for readability:
            - If a slide has a heading or title line (e.g. "#1- Topic", "Step 3:", a short bold statement), \
            put the body text on the next line after it.
            - LISTS: Any time multiple items are separated by delimiters (→, --, •, -, *, ▸), \
            put EACH item on its own line with its delimiter. This includes double-dash (--) lists. \
            Example input: "Criteria: -- Price: $300K -- 3+ bedrooms -- Large rooms" \
            Example output:
            Criteria:
            -- Price: $300K
            -- 3+ bedrooms
            -- Large rooms
            - ARROW BULLETS: The → character ALWAYS signals a new list item. Put a line break BEFORE each →. \
            Example input: "Benefits: → Lower costs → Better quality → More time" \
            Example output:
            Benefits:
            → Lower costs
            → Better quality
            → More time
            - NUMBERED RANKINGS/DATA: When you see numbered entries like "1 Hawaii $38,107 $544,386 2 Nebraska $33,885", \
            put EACH numbered entry on its own line:
            1 Hawaii $38,107 $544,386
            2 Nebraska $33,885 $484,071
            - Keep numbered items (1., 2., etc.) each on their own line.
            - Do NOT add leading spaces before lines. Each line should start at the left margin.
            """
        } else {
            lineBreakRule = """
            6. JOIN text into flowing sentences — do NOT preserve visual line breaks from the \
            image. Each slide's text should read as a natural paragraph. Only use a newline to \
            separate a distinct header/title from the body text below it.
            """
        }

        let contentLabel = isCarousel ? "carousel slides" : "Instagram slides"
        let prompt = """
        You are cleaning up auto-transcribed text from Instagram \(contentLabel). The OCR \
        captured ALL visible text from each slide image. Your job is to extract ONLY the \
        main text overlays that the creator intended viewers to read, while preserving the \
        original slide structure exactly.

        RULES:
        1. REMOVE background text: brand names, watermarks, URLs, UI elements, text visible \
        in background images, or any text that is clearly not the main overlay.
        2. DO NOT merge, delete, reorder, or add slides. Output exactly one cleaned string for \
        every input slide, in the same order.
        3. FIX OCR artifacts: truncated words, random symbols, garbled characters, wrong \
        numbers/letters from OCR misreads.
        4. FIX incomplete sentences only when the correction is obvious. If uncertain, keep the \
        original raw text for that slide.
        5. KEEP the creator's original wording — do not rephrase or add new content.
        \(lineBreakRule)
        10. Each slide should contain the COMPLETE text from that slide — do not \
        truncate or summarize.

        Return ONLY valid JSON in this format:
        {"slides":[{"index":1,"text":"cleaned text for slide 1"}, {"index":2,"text":"slide 2"}]}

        The number of slides in your output MUST equal the number of input slides.
        If a slide is uncertain, return the raw text for that slide.

        Raw OCR slides:
        \(slideTexts.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n"))
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            guard let cleaned = parseCleanedSlides(from: response, expectedCount: slides.count) else {
                return nil
            }

            return slides.enumerated().map { index, original in
                var updated = original
                let cleanedText = cleaned[index].trimmingCharacters(in: .whitespacesAndNewlines)
                updated.text = cleanedText.isEmpty ? original.text : cleanedText
                if updated.source != .speechAudio {
                    updated.source = .aiCleaned
                }
                updated.slideNumber = index + 1
                return updated
            }
        } catch {
            print("InstagramAutoTranscriber: Claude cleanup failed: \(error)")
            return nil
        }
    }

    /// Parse a JSON array/object of cleaned slides from Claude's response.
    func parseCleanedSlides(from response: String, expectedCount: Int) -> [String]? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsed = decodeCleanedSlidesPayload(trimmed, expectedCount: expectedCount) {
            return parsed
        }

        if let braceStart = trimmed.range(of: "{"),
           let braceEnd = trimmed.range(of: "}", options: .backwards) {
            let jsonString = String(trimmed[braceStart.lowerBound..<braceEnd.upperBound])
            if let parsed = decodeCleanedSlidesPayload(jsonString, expectedCount: expectedCount) {
                return parsed
            }
        }

        if let arrayStart = trimmed.range(of: "["),
           let arrayEnd = trimmed.range(of: "]", options: .backwards) {
            let jsonString = String(trimmed[arrayStart.lowerBound..<arrayEnd.upperBound])
            if let parsed = decodeCleanedSlidesPayload(jsonString, expectedCount: expectedCount) {
                return parsed
            }
        }

        return nil
    }

    private func decodeCleanedSlidesPayload(_ jsonString: String, expectedCount: Int) -> [String]? {
        struct SlidePayload: Codable {
            let index: Int?
            let text: String
        }

        struct Payload: Codable {
            let slides: [SlidePayload]
        }

        guard let data = jsonString.data(using: .utf8) else { return nil }

        if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            let sorted = payload.slides.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
            let texts = sorted.map(\.text)
            return texts.count == expectedCount ? texts : nil
        }

        if let array = try? JSONDecoder().decode([String].self, from: data), array.count == expectedCount {
            return array
        }

        return nil
    }

    /// Trim leading whitespace from each line in carousel slide text.
    /// Claude sometimes returns lines with leading spaces; this normalizes them.
    private func trimSlideLines(_ slides: [TranscriptSlide]) -> [TranscriptSlide] {
        slides.map { slide in
            var updated = slide
            updated.text = slide.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return updated
        }
    }

    // MARK: - Text Helpers

    func postProcessSlides(
        _ slides: [TranscriptSlide],
        contentType: TranscriptionContentType,
        isCarousel: Bool = false
    ) -> [TranscriptSlide] {
        guard !slides.isEmpty else { return [] }

        var sanitized: [TranscriptSlide] = slides.map { slide in
            var updated = slide
            let cleaned = sanitizeSlideText(slide.text, isCarousel: isCarousel)
            updated.text = cleaned.isEmpty
                ? slide.text.trimmingCharacters(in: .whitespacesAndNewlines)
                : cleaned
            return updated
        }
        sanitized = correctLikelyYearOutliers(in: sanitized)
        sanitized = deduplicateSlides(sanitized)

        for index in sanitized.indices {
            sanitized[index].slideNumber = index + 1
        }

        return sanitized
    }

    /// Remove duplicate slides by checking each slide against ALL previously accepted slides.
    /// Catches both consecutive and non-consecutive duplicates (Jaccard ≥ 0.92), plus superset
    /// cases where one slide's text contains another's (containment ≥ 0.90) — keeps the longer version.
    private func deduplicateSlides(_ slides: [TranscriptSlide]) -> [TranscriptSlide] {
        guard slides.count > 1 else { return slides }
        var result: [TranscriptSlide] = [slides[0]]

        for i in 1..<slides.count {
            let currNorm = normalizedLineKey(slides[i].text)
            let currWords = Set(currNorm.split(separator: " ").map(String.init))
            guard currWords.count >= 2 else {
                result.append(slides[i])
                continue
            }

            var isDuplicate = false
            for j in result.indices {
                let existNorm = normalizedLineKey(result[j].text)
                let existWords = Set(existNorm.split(separator: " ").map(String.init))
                guard existWords.count >= 2 else { continue }

                if jaccardSimilarity(existWords, currWords) >= 0.92 {
                    isDuplicate = true
                    break
                }

                let intersection = existWords.intersection(currWords).count
                let containment = Double(intersection) / Double(min(existWords.count, currWords.count))
                if containment >= 0.90 {
                    if currWords.count > existWords.count {
                        result[j] = slides[i]
                    }
                    isDuplicate = true
                    break
                }
            }

            if !isDuplicate {
                result.append(slides[i])
            }
        }
        return result
    }

    private func sanitizeSlideText(_ text: String, isCarousel: Bool = false) -> String {
        let rawLines = text
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        var mergedLines: [String] = []
        for line in rawLines {
            guard !isLikelyArtifactLine(line) else {
                #if DEBUG
                print("InstagramAutoTranscriber: Dropped artifact line: \"\(line)\"")
                #endif
                continue
            }
            if let last = mergedLines.last, shouldJoinLine(previous: last, next: line, isCarousel: isCarousel) {
                mergedLines.removeLast()
                let joiner = last.hasSuffix("-") ? "" : " "
                let stitched = (last + joiner + line).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                mergedLines.append(stitched.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                mergedLines.append(line)
            }
        }

        mergedLines = deduplicateLinesPreservingOrder(mergedLines)

        // For carousels: split joined text at sentence boundaries and list delimiters
        // for readability. After OCR lines are merged, sentences/items run together —
        // split them apart so each gets its own line. BUT protect list items from splitting.
        if isCarousel {
            mergedLines = mergedLines.flatMap { line -> [String] in
                // Don't split lines that are already list items
                let listPattern = #"^(\d+[\.\)]\s|[→▸►•·\-\*\+]\s|--\s|#\d|Step\s)"#
                if line.range(of: listPattern, options: .regularExpression) != nil {
                    return [line]  // Preserve list items as-is
                }
                // Force line breaks before → characters mid-line
                var working = line.replacingOccurrences(of: " → ", with: "\n→ ")
                // Force line breaks before mid-line dash/plus list items: " - Item" or " + Item"
                working = working.replacingOccurrences(
                    of: #"(?<=\S)\s+[\-\+] (?=[A-Z])"#,
                    with: "\n- ",
                    options: .regularExpression
                )
                // Split "Label: +24% Label: +26%" stat-list patterns
                working = working.replacingOccurrences(
                    of: #"(%\s+)(?=[A-Z][a-z])"#,
                    with: "%\n",
                    options: .regularExpression
                )
                if working.contains("\n") {
                    return working.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                return splitAtSentenceBoundaries(line)
            }
        }

        let joined = mergedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizeStandaloneYearArtifacts(in: joined)
    }

    /// Splits a line at sentence boundaries (". ", "! ", "? " followed by uppercase)
    /// into separate lines for carousel readability.
    private func splitAtSentenceBoundaries(_ text: String) -> [String] {
        guard text.count > 1 else { return [text] }

        let pattern = #"(?<=[.!?])\s+(?=[A-Z])"#

        let parts = text
            .replacingOccurrences(of: pattern, with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return parts.isEmpty ? [text] : parts
    }

    private func shouldJoinLine(previous: String, next: String, isCarousel: Bool = false) -> Bool {
        // Hyphenated word wrap (e.g., "anti-\nestablishment") — only if it's a word fragment, not a list dash
        if previous.hasSuffix("-") && previous.count > 1 {
            let beforeDash = previous.dropLast()
            // Only join if the character before the dash is alphanumeric (word hyphenation)
            if let lastChar = beforeDash.last, lastChar.isLetter { return true }
        }
        // Don't join numbered list items (e.g. "50. Mississippi ($186,618)" or "1- Item")
        let numberedPattern = #"^\d+[\.\)\-]\s?"#
        if previous.range(of: numberedPattern, options: .regularExpression) != nil ||
            next.range(of: numberedPattern, options: .regularExpression) != nil {
            return false
        }
        // Don't join arrow or bullet list items
        let bulletPattern = #"^[→▸►•·\-\*\+]\s"#
        if next.range(of: bulletPattern, options: .regularExpression) != nil ||
            previous.range(of: bulletPattern, options: .regularExpression) != nil {
            return false
        }
        // A line that is purely a number (year header, big stat) is intentional
        // slide layout — never fold it into surrounding text.
        if (!previous.isEmpty && previous.allSatisfy(\.isNumber)) ||
            (!next.isEmpty && next.allSatisfy(\.isNumber)) {
            return false
        }
        // For carousels: don't join after colon-ending lines (introduces a list or section)
        if isCarousel && previous.hasSuffix(":") { return false }
        if next.count <= 3 {
            // For carousels, don't merge short words starting with uppercase (likely list items)
            if isCarousel, let first = next.first, first.isUppercase { return false }
            return true
        }
        if next.first?.isLowercase == true && !endsSentence(previous) { return true }
        if previous.count <= 14 && next.count <= 14 {
            // For carousels, don't merge two short lines if both start with uppercase
            // (likely separate list items, not a wrapped sentence)
            if isCarousel,
               let prevFirst = previous.first, prevFirst.isUppercase,
               let nextFirst = next.first, nextFirst.isUppercase {
                return false
            }
            return true
        }
        return false
    }

    private func endsSentence(_ line: String) -> Bool {
        guard let last = line.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return [".", "!", "?", ":"].contains(last)
    }

    private func isLikelyArtifactLine(_ line: String) -> Bool {
        let compact = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= 1 { return true }

        // Common punctuation in real content — don't count as suspicious symbols
        let contentPunctuation = CharacterSet(charactersIn: ".,;:!?()[]$%&@#/'-\"—–…✓✗•·")
        let symbols = compact.unicodeScalars.filter {
            !CharacterSet.alphanumerics.contains($0) &&
                !$0.properties.isWhitespace &&
                !contentPunctuation.contains($0)
        }
        // Only flag as artifact if suspicious symbols dominate the line
        let ratio = Double(symbols.count) / Double(compact.count)
        if symbols.count >= 3 && ratio > 0.3 { return true }

        let words = compact.split(separator: " ").map(String.init)
        if words.count == 1 {
            let word = words[0]
            if word.count <= 3 {
                let hasDigit = word.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
                let hasVowel = word.lowercased().unicodeScalars.contains { "aeiouy".unicodeScalars.contains($0) }
                if !hasDigit && !hasVowel { return true }
            }
            let letters = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            let vowels = letters.filter { "aeiouAEIOU".unicodeScalars.contains($0) }
            if letters.count >= 5 && vowels.count == 0 { return true }
        }

        return false
    }

    private func normalizedTextFingerprint(_ text: String) -> String {
        normalizedLineKey(text)
    }

    private func normalizeStandaloneYearArtifacts(in text: String) -> String {
        guard !text.isEmpty else { return text }

        let pattern = #"\b[0-9OIlSB]{4}[^0-9A-Za-z\s]?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange).reversed()

        var updated = text
        for match in matches {
            guard let range = Range(match.range, in: updated) else { continue }
            let rawToken = String(updated[range])
            let normalizedDigits = rawToken
                .unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map { normalizeDigitConfusable($0) }
            let normalizedString = String(String.UnicodeScalarView(normalizedDigits))

            guard normalizedString.count == 4,
                  Int(normalizedString) != nil else {
                continue
            }
            updated.replaceSubrange(range, with: normalizedString)
        }

        return updated
    }

    private func normalizeDigitConfusable(_ scalar: UnicodeScalar) -> UnicodeScalar {
        switch scalar {
        case "O", "o": return "0"
        case "I", "l": return "1"
        case "S", "s": return "5"
        case "B": return "8"
        default: return scalar
        }
    }

    private func correctLikelyYearOutliers(in slides: [TranscriptSlide]) -> [TranscriptSlide] {
        guard !slides.isEmpty else { return [] }

        let referenceYears: [Int] = slides
            .flatMap { extractYears(from: $0.text) }
            .filter { (1990...2035).contains($0) }

        guard referenceYears.count >= 2 else { return slides }

        var updated = slides
        for index in updated.indices {
            let neighborYears = stride(from: max(0, index - 2), through: min(updated.count - 1, index + 2), by: 1)
                .flatMap { extractYears(from: updated[$0].text) }
                .filter { (1990...2035).contains($0) }

            let target = (neighborYears.isEmpty ? referenceYears : neighborYears).sorted()
            let reference = target[target.count / 2]
            updated[index].text = replaceOutlierYears(in: updated[index].text, referenceYear: reference)
        }

        return updated
    }

    private func extractYears(from text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"\b\d{4}\b"#) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return Int(text[range])
        }
    }

    private func replaceOutlierYears(in text: String, referenceYear: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b\d{4}\b"#) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange).reversed()

        var updated = text
        for match in matches {
            guard let range = Range(match.range, in: updated) else { continue }
            let token = String(updated[range])
            guard let year = Int(token) else { continue }
            guard year < 1900 else { continue }

            let candidates = stride(from: 100, through: 600, by: 100).compactMap { delta -> Int? in
                let candidate = year + delta
                return (1990...2035).contains(candidate) ? candidate : nil
            }

            guard let best = candidates.min(by: { abs($0 - referenceYear) < abs($1 - referenceYear) }),
                  abs(best - referenceYear) <= 4 else {
                continue
            }

            updated.replaceSubrange(range, with: String(best))
        }

        return updated
    }

    /// Build stable slide text from a cluster of OCR frames.
    /// Keeps visual line order and removes one-off OCR noise.
    private func buildSlideText(from frames: [OCRFrameResult]) -> String {
        guard !frames.isEmpty else { return "" }

        var aggregates: [String: OCRLineAggregate] = [:]

        for (frameIndex, frame) in frames.enumerated() {
            for (lineIndex, line) in frame.lines.enumerated() {
                guard let cleaned = cleanOCRLine(line) else { continue }
                let key = normalizedLineKey(cleaned)
                guard !key.isEmpty else { continue }

                if var existing = aggregates[key] {
                    existing.count += 1
                    existing.totalLineIndex += lineIndex
                    existing.variants[cleaned, default: 0] += 1
                    aggregates[key] = existing
                } else {
                    aggregates[key] = OCRLineAggregate(
                        variants: [cleaned: 1],
                        count: 1,
                        firstFrameIndex: frameIndex,
                        firstLineIndex: lineIndex,
                        totalLineIndex: lineIndex
                    )
                }
            }
        }

        let minAppearances = max(1, Int(ceil(Double(frames.count) * minStableLineRatio)))
        let includeSingletons = frames.count <= 2

        var orderedLines: [(text: String, firstFrame: Int, averageLineIndex: Double, firstLine: Int)] = []
        for aggregate in aggregates.values {
            guard includeSingletons || aggregate.count >= minAppearances else { continue }
            guard let bestVariant = aggregate.variants.max(by: {
                if $0.value == $1.value { return $0.key.count < $1.key.count }
                return $0.value < $1.value
            })?.key else {
                continue
            }

            let averageLineIndex = Double(aggregate.totalLineIndex) / Double(max(aggregate.count, 1))
            orderedLines.append((
                text: bestVariant,
                firstFrame: aggregate.firstFrameIndex,
                averageLineIndex: averageLineIndex,
                firstLine: aggregate.firstLineIndex
            ))
        }

        orderedLines.sort { lhs, rhs in
            if lhs.firstFrame != rhs.firstFrame {
                return lhs.firstFrame < rhs.firstFrame
            }
            if abs(lhs.averageLineIndex - rhs.averageLineIndex) > 0.01 {
                return lhs.averageLineIndex < rhs.averageLineIndex
            }
            return lhs.firstLine < rhs.firstLine
        }

        var finalLines = deduplicateLinesPreservingOrder(orderedLines.map(\.text))
        if finalLines.isEmpty, let fallback = frames.max(by: { $0.confidence < $1.confidence }) {
            finalLines = deduplicateLinesPreservingOrder(fallback.lines)
        }

        var text = finalLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > TranscriptSlide.characterLimit {
            text = String(text.prefix(TranscriptSlide.characterLimit))
        }
        return text
    }

    private func deduplicateLinesPreservingOrder(_ lines: [String]) -> [String] {
        var unique: [String] = []
        var normalizedSeen: [String] = []

        for line in lines {
            let cleaned = line
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\u{2019}", with: "'")
            guard !cleaned.isEmpty else { continue }
            let normalized = normalizedLineKey(cleaned)
            guard !normalized.isEmpty else { continue }

            let isDuplicate = normalizedSeen.contains { existing in
                if existing == normalized { return true }
                // Use word-level Jaccard similarity instead of substring matching
                let existingWords = Set(existing.split(separator: " ").map(String.init))
                let normalizedWords = Set(normalized.split(separator: " ").map(String.init))
                return jaccardSimilarity(existingWords, normalizedWords) >= 0.85
            }

            if !isDuplicate {
                unique.append(cleaned)
                normalizedSeen.append(normalized)
            }
        }

        return unique
    }

    private func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func tokenSet(from text: String) -> Set<String> {
        Set(normalizedLineKey(text).split(separator: " ").map(String.init))
    }

    private func tokenOverlapScore(lhs: String, rhs: String) -> Double {
        let lhsTokens = tokenSet(from: lhs)
        let rhsTokens = tokenSet(from: rhs)
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let intersection = lhsTokens.intersection(rhsTokens).count
        return Double(intersection) / Double(min(lhsTokens.count, rhsTokens.count))
    }

    private func subtitleOverlapRatio(visualSlides: [TranscriptSlide], speech: [SpeechSegment]) -> Double {
        guard !visualSlides.isEmpty, !speech.isEmpty else { return 0 }

        var overlapScores: [Double] = []
        for slide in visualSlides {
            let slideStart = slide.timestamp ?? 0
            let slideEnd = slide.endTimestamp ?? slideStart + 2
            let overlappingSpeech = speech.filter { segment in
                let segmentEnd = segment.timestamp + max(segment.duration, 0)
                return segment.timestamp <= slideEnd + 0.5 && segmentEnd >= slideStart - 0.5
            }

            let spokenText = overlappingSpeech.map(\.text).joined(separator: " ")
            guard !spokenText.isEmpty else { continue }
            overlapScores.append(tokenOverlapScore(lhs: slide.text, rhs: spokenText))
        }

        guard !overlapScores.isEmpty else { return 0 }
        return overlapScores.reduce(0, +) / Double(overlapScores.count)
    }

    private func jaccardSimilarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }

    // MARK: - Carousel Transcription

    /// Transcribe an Instagram carousel (image slides) using Vision OCR + Gemini Vision fallback
    /// - Parameters:
    ///   - items: Carousel items extracted from Instagram
    ///   - progressHandler: Called with progress updates
    /// - Returns: TranscriptionResult with one slide per carousel image
    func transcribeCarousel(
        items: [CarouselItem],
        shortcode: String? = nil,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> TranscriptionResult {
        let imageItems = items.filter { $0.mediaType == .image }
        guard !imageItems.isEmpty else {
            return transcriptionResult(rawSlides: [], contentType: .empty, averageOCRConfidence: 0)
        }

        print("InstagramAutoTranscriber: Starting carousel transcription (\(imageItems.count) images)")

        var slides: [TranscriptSlide] = []
        var totalConfidence: Float = 0
        var lowOCRItems: [(index: Int, jpegData: Data, slideIndex: Int)] = []
        var warnings: [String] = []

        // Phase 1: Download images and run Vision OCR
        for (idx, item) in imageItems.enumerated() {
            let progress = Double(idx) / Double(imageItems.count)
            progressHandler(.recognizingText(progress))

            let cacheKey = InstagramCarouselImageCache.cacheKey(
                shortcode: shortcode,
                index: item.index,
                url: item.mediaURL
            )

            // Download/cache image
            guard let imageData = await downloadImage(url: item.mediaURL, stableKey: cacheKey) else {
                slides.append(TranscriptSlide(text: "", slideNumber: idx + 1, source: .visionOCR))
                warnings.append("Some carousel slides could not be downloaded.")
                continue
            }

            // Create CGImage
            guard let cgImage = createCGImage(from: imageData) else {
                slides.append(TranscriptSlide(text: "", slideNumber: idx + 1, source: .visionOCR))
                warnings.append("Some carousel slides could not be decoded.")
                continue
            }

            // Run Vision OCR — use lower bounding box threshold for carousel slides
            // (carousel text is often smaller than reel overlay text)
            let ocrResult = await recognizeText(in: cgImage, at: 0, minBoxOverride: 0.02)
            // Join OCR lines with newlines to preserve the visual line breaks
            // from the carousel slide. Claude cleanup will remove OCR artifacts
            // while keeping intentional line breaks.
            let text = ocrResult?.lines.joined(separator: "\n") ?? ""
            let confidence = ocrResult?.confidence ?? 0

            slides.append(TranscriptSlide(
                text: text,
                slideNumber: idx + 1,
                source: .visionOCR
            ))
            totalConfidence += confidence

            // Queue for Gemini fallback if OCR returned < 5 words
            let wordCount = text.split(separator: " ").count
            if wordCount < 5 {
                lowOCRItems.append((index: idx, jpegData: imageData, slideIndex: slides.count - 1))
            }
        }

        progressHandler(.recognizingText(1.0))

        // Phase 2: Gemini Vision fallback for low-OCR slides
        if !lowOCRItems.isEmpty, APIKeys.hasOpenRouter, let apiKey = APIKeys.openRouter {
            print("InstagramAutoTranscriber: Running Gemini fallback for \(lowOCRItems.count) low-OCR carousel slides")
            progressHandler(.analyzingWithAI(0))

            for (batchIdx, item) in lowOCRItems.enumerated() {
                let progress = Double(batchIdx + 1) / Double(lowOCRItems.count)
                progressHandler(.analyzingWithAI(progress))

                if let geminiText = await callGeminiVisionForSingleImage(
                    jpegData: item.jpegData,
                    slideIndex: item.index,
                    apiKey: apiKey
                ) {
                    slides[item.slideIndex] = TranscriptSlide(
                        text: geminiText,
                        slideNumber: item.index + 1,
                        source: .geminiVision
                    )
                }

                // Brief delay between calls
                if batchIdx < lowOCRItems.count - 1 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }

        progressHandler(.complete)

        let nonEmptySlides = slides.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let avgConfidence = imageItems.isEmpty ? Float(0) : totalConfidence / Float(imageItems.count)
        let contentType: TranscriptionContentType = nonEmptySlides.isEmpty ? .empty : .textOnly

        print("InstagramAutoTranscriber: Carousel transcription complete — \(nonEmptySlides.count)/\(imageItems.count) slides with text")

        var result = transcriptionResult(
            rawSlides: slides,
            contentType: contentType,
            averageOCRConfidence: avgConfidence
        )
        result.cleanedSlides = await cleanedSlides(from: result.rawSlides, contentType: contentType, isCarousel: true)
        result.warnings = deduplicatedWarnings(warnings)
        result.quality = result.warnings.isEmpty ? .accurate : .degraded
        return result
    }

    // MARK: - Carousel Helpers

    /// Download an image from a URL
    private func downloadImage(url: URL, stableKey: String) async -> Data? {
        await InstagramCarouselImageCache.imageData(for: url, stableKey: stableKey)
    }

    /// Create a CGImage from image data
    private func createCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Call Gemini Vision for a single carousel image
    private func callGeminiVisionForSingleImage(
        jpegData: Data,
        slideIndex: Int,
        apiKey: String
    ) async -> String? {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

        let prompt = """
        You are reading text from a single Instagram carousel slide image.

        Read ALL visible text overlays — the main text the creator placed on this slide for viewers to read.
        This includes headings, statements, facts, quotes, captions, and call-to-action text.

        IGNORE:
        - Instagram UI (like counts, username, share button)
        - Watermarks, brand logos
        - Text in background images (not overlaid by creator)

        Return ONLY the text content as a single string. PRESERVE the line breaks from the original slide — \
        if text appears on separate lines in the image, keep them on separate lines in your output. \
        Do not merge lines into one flowing sentence.
        If no readable text is found, return an empty string.
        """

        let contentArray: [[String: Any]] = [
            ["type": "text", "text": prompt],
            [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(jpegData.base64EncodedString())"]
            ]
        ]

        let requestBody: [String: Any] = [
            "model": geminiModel,
            "messages": [
                ["role": "user", "content": contentArray]
            ],
            "temperature": 0.1,
            "max_tokens": 1000
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }

            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            print("InstagramAutoTranscriber: Gemini single-image failed for slide \(slideIndex): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - OCR Helpers

    private func cleanOCRLine(_ raw: String) -> String? {
        let compact = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")

        guard compact.count >= 2 else { return nil }

        let scalarCount = compact.unicodeScalars.count
        guard scalarCount > 0 else { return nil }

        let alphaNumericCount = compact.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        if Double(alphaNumericCount) / Double(scalarCount) < 0.45 {
            return nil
        }

        return compact
    }

    private func normalizedLineKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s$%'/]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
