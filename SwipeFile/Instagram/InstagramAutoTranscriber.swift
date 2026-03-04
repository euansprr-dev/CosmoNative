// CosmoOS/SwipeFile/Instagram/InstagramAutoTranscriber.swift
// Dual-pipeline auto-transcription engine for Instagram reels/videos
// Runs Vision OCR + SFSpeechRecognizer in parallel
// February 2026

import Foundation
import AVFoundation
import Vision
import Speech
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
    let slides: [TranscriptSlide]
    let contentType: TranscriptionContentType
    let averageOCRConfidence: Float
}

// MARK: - OCR Frame Result

/// Text recognized in a single video frame
private struct OCRFrameResult: Sendable {
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
private struct SpeechSegment: Sendable {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
}

// MARK: - Instagram Auto Transcriber

@MainActor
final class InstagramAutoTranscriber {
    static let shared = InstagramAutoTranscriber()

    private let framesPerSecond: Double = 2.0
    private let jaccardThreshold: Double = 0.62
    private let minLineConfidence: Float = 0.22
    private let minStableLineRatio: Double = 0.30

    // Gemini Vision pipeline constants
    private let geminiModel = "google/gemini-2.0-flash-001"
    private let geminiFPS: Double = 2.0           // 2fps — each 2-3s slide gets 4-6 frames
    private let maxGeminiFrames: Int = 120         // Cap for cost/memory control (~$0.015/reel)
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
            ocrFrameResults = await runOCRPipeline(videoURL: videoURL, duration: actualDuration, progressHandler: progressHandler)
            visualSlides = ocrToSlides(ocr: ocrFrameResults)
        }

        // Step 4: Run speech recognition SEQUENTIALLY (after vision completes)
        // Running in parallel caused AVFoundation resource contention and memory pressure.
        // Sequential is safer — the video file is only used by one subsystem at a time.
        print("InstagramAutoTranscriber: Starting speech pipeline...")
        let speech: [SpeechSegment]
        if APIKeys.hasWhisper {
            // Prefer OpenAI Whisper API — higher quality, handles full audio without truncation
            speech = await runWhisperPipeline(videoURL: videoURL, progressHandler: progressHandler)
        } else {
            // Fallback: on-device Apple Speech (can truncate long audio)
            speech = await runSpeechPipeline(videoURL: videoURL, progressHandler: progressHandler)
        }
        print("InstagramAutoTranscriber: Speech pipeline returned \(speech.count) segments")

        // Step 5: Merge results
        progressHandler(.mergingResults)

        let result: TranscriptionResult
        if !visualSlides.isEmpty && visualSlides.first?.source == .geminiVision {
            result = mergeGeminiWithSpeech(geminiSlides: visualSlides, speech: speech, duration: actualDuration)
        } else {
            result = mergeResults(ocr: ocrFrameResults, speech: speech, duration: actualDuration)
        }

        progressHandler(.complete)
        print("InstagramAutoTranscriber: Transcription complete — \(result.slides.count) slides, type: \(result.contentType)")

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
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
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
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)
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
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)
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
    private nonisolated func callGeminiVision(
        frameImages: [Data],
        timestamps: [TimeInterval],
        batchIndex: Int,
        apiKey: String
    ) async throws -> [TranscriptSlide] {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

        let timestampList = timestamps.enumerated().map { "Frame \($0.offset)=\(String(format: "%.1f", $0.element))s" }.joined(separator: ", ")

        let prompt = """
        You are analyzing \(frameImages.count) sequential frames from an Instagram reel, captured at ~2fps.
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
    private nonisolated func parseGeminiSlides(
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
    private nonisolated func joinVisualLineBreaks(_ text: String) -> String {
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
    private nonisolated func parseGeminiSlidesArray(
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
    private nonisolated func mergeGeminiBatchResults(batches: [[TranscriptSlide]]) -> [TranscriptSlide] {
        guard !batches.isEmpty else { return [] }

        var merged: [TranscriptSlide] = []

        for batch in batches {
            for slide in batch {
                let trimmedText = slide.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedText.isEmpty else { continue }

                // Check overlap with last merged slide
                if var lastSlide = merged.last {
                    let lastNorm = lastSlide.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let currentNorm = trimmedText.lowercased()

                    // Split on ALL whitespace (spaces, newlines, tabs) so that
                    // "home\nand" tokenizes the same as "home and"
                    let lastTokens = Set(lastNorm.split(whereSeparator: { $0.isWhitespace }).map(String.init))
                    let currentTokens = Set(currentNorm.split(whereSeparator: { $0.isWhitespace }).map(String.init))

                    // Use Jaccard similarity (intersection/union) — NOT subset overlap.
                    // Subset overlap falsely merges short slides into longer ones
                    // (e.g., "2016" would get 100% subset match against "2016 We started a business").
                    let union = lastTokens.union(currentTokens).count
                    let overlap = union > 0
                        ? Double(lastTokens.intersection(currentTokens).count) / Double(union)
                        : 0

                    if overlap >= 0.80 {
                        // Merge: extend timestamp range, keep longer text
                        if trimmedText.count > lastSlide.text.count {
                            lastSlide.text = trimmedText
                        }
                        if let newEnd = slide.endTimestamp ?? slide.timestamp {
                            lastSlide.endTimestamp = newEnd
                        }
                        merged[merged.count - 1] = lastSlide
                        continue
                    }
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
        duration: TimeInterval
    ) -> TranscriptionResult {
        let hasGemini = !geminiSlides.isEmpty
        let hasSpeech = !speech.isEmpty

        if hasGemini && hasSpeech {
            // Check if visual text is just noise and speech is the real content
            let geminiWordCount = geminiSlides.map(\.text).joined(separator: " ")
                .split(separator: " ").count
            let speechWordCount = speech.map(\.text).joined(separator: " ")
                .split(separator: " ").count

            if isVoiceoverDominant(visualWordCount: geminiWordCount, speechWordCount: speechWordCount, visualSlideCount: geminiSlides.count) {
                print("InstagramAutoTranscriber: Voiceover dominant over Gemini (\(geminiWordCount) visual words in \(geminiSlides.count) slides vs \(speechWordCount) speech words) — treating as voiceover-only")
                return TranscriptionResult(
                    slides: speechToSlides(speech: speech),
                    contentType: .voiceoverOnly,
                    averageOCRConfidence: 1.0
                )
            }

            // Deduplicate adjacent slides first (Gemini can return dupes at batch boundaries)
            var slides = collapseNearDuplicateAdjacentSlides(geminiSlides)

            // Append speech as annotation where it overlaps
            for (idx, slide) in slides.enumerated() {
                let slideStart = slide.timestamp ?? 0
                let slideEnd = slide.endTimestamp ?? slideStart + 3

                let overlapping = speech.filter { segment in
                    segment.timestamp >= slideStart - 0.5 &&
                    segment.timestamp <= slideEnd + 0.5
                }

                if !overlapping.isEmpty {
                    let spokenText = overlapping.map(\.text).joined(separator: " ")
                    let slideNorm = normalizedLineKey(slide.text)
                    let speechNorm = normalizedLineKey(spokenText)
                    if !slideNorm.contains(speechNorm) && !speechNorm.contains(slideNorm) {
                        slides[idx].text += "\n[Voiceover: \(spokenText)]"
                        slides[idx].source = .merged
                    }
                }
            }

            for i in slides.indices { slides[i].slideNumber = i + 1 }

            return TranscriptionResult(
                slides: slides,
                contentType: .voiceoverPlusText,
                averageOCRConfidence: 0.95
            )
        } else if hasGemini {
            var slides = collapseNearDuplicateAdjacentSlides(geminiSlides)
            for i in slides.indices { slides[i].slideNumber = i + 1 }

            return TranscriptionResult(
                slides: slides,
                contentType: .textOnly,
                averageOCRConfidence: 0.95
            )
        } else if hasSpeech {
            return TranscriptionResult(
                slides: speechToSlides(speech: speech),
                contentType: .voiceoverOnly,
                averageOCRConfidence: 1.0
            )
        } else {
            return TranscriptionResult(
                slides: [TranscriptSlide(text: "", slideNumber: 1, source: .manual)],
                contentType: .empty,
                averageOCRConfidence: 0
            )
        }
    }

    // MARK: - Vision OCR Pipeline (Fallback)

    /// Extract frames and run text recognition
    private func runOCRPipeline(
        videoURL: URL,
        duration: TimeInterval,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> [OCRFrameResult] {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        // Calculate frame times at 2fps
        let frameCount = Int(duration * framesPerSecond)
        guard frameCount > 0 else { return [] }

        let frameTimes: [CMTime] = (0..<frameCount).map { i in
            CMTime(seconds: Double(i) / framesPerSecond, preferredTimescale: 600)
        }

        var results: [OCRFrameResult] = []

        for (index, time) in frameTimes.enumerated() {
            let progress = Double(index) / Double(frameTimes.count)
            await MainActor.run { progressHandler(.extractingFrames(progress)) }

            do {
                let (cgImage, _) = try await generator.image(at: time)
                let ocrResult = await recognizeText(in: cgImage, at: time.seconds)
                if let result = ocrResult {
                    results.append(result)
                }
            } catch {
                // Skip frames that fail to extract
                continue
            }
        }

        await MainActor.run { progressHandler(.recognizingText(1.0)) }

        return results
    }

    /// Minimum bounding box height (normalized 0-1) for an OCR observation to be considered main text.
    /// Instagram reel overlays typically have heights > 3-4% of the frame. Background text, watermarks,
    /// and incidental text in images tend to be much smaller.
    private let minBoundingBoxHeight: CGFloat = 0.035

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

    // MARK: - Whisper API Pipeline (Preferred)

    /// Extract audio from video and transcribe via OpenAI Whisper API.
    /// Returns sentence-level SpeechSegments for the existing merge pipeline.
    /// Falls back to Apple SFSpeechRecognizer if Whisper fails.
    private func runWhisperPipeline(
        videoURL: URL,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> [SpeechSegment] {
        guard await hasUsableAudioTrack(videoURL) else {
            print("InstagramAutoTranscriber: Skipping Whisper pipeline (no audio track)")
            return []
        }

        progressHandler(.recognizingSpeech(0.1))

        // Step 1: Extract audio as M4A
        guard let audioData = await extractAudioAsM4A(from: videoURL) else {
            print("InstagramAutoTranscriber: Audio extraction failed, falling back to Apple Speech")
            return await runSpeechPipeline(videoURL: videoURL, progressHandler: progressHandler)
        }

        print("InstagramAutoTranscriber: Extracted audio (\(audioData.count / 1024)KB), sending to Whisper API...")
        progressHandler(.recognizingSpeech(0.3))

        // Step 2: Transcribe via Whisper API
        do {
            let transcript = try await WhisperTranscriptionService.shared.transcribe(
                audioData: audioData,
                format: .m4a
            )

            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("InstagramAutoTranscriber: Whisper returned empty transcript")
                return []
            }

            print("InstagramAutoTranscriber: Whisper transcription complete (\(transcript.count) chars)")
            progressHandler(.recognizingSpeech(1.0))

            // Step 3: Split into sentence-level segments for the merge pipeline
            return splitIntoSentenceSegments(transcript)
        } catch {
            print("InstagramAutoTranscriber: Whisper API failed: \(error.localizedDescription), falling back to Apple Speech")
            return await runSpeechPipeline(videoURL: videoURL, progressHandler: progressHandler)
        }
    }

    /// Extract audio track from video file as M4A data.
    private func extractAudioAsM4A(from videoURL: URL) async -> Data? {
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
            return nil
        }

        defer { try? FileManager.default.removeItem(at: outputURL) }
        return try? Data(contentsOf: outputURL)
    }

    /// Split a Whisper transcript (fully punctuated text) into sentence-level SpeechSegments.
    /// Timestamps are not available from the basic Whisper API, so they're set to 0.
    private func splitIntoSentenceSegments(_ text: String) -> [SpeechSegment] {
        var segments: [SpeechSegment] = []
        var current = ""

        for char in text {
            current.append(char)
            if char == "." || char == "!" || char == "?" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(SpeechSegment(text: trimmed, timestamp: 0, duration: 0))
                }
                current = ""
            }
        }

        // Flush remaining text
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            segments.append(SpeechSegment(text: trimmed, timestamp: 0, duration: 0))
        }

        return segments
    }

    // MARK: - Speech Recognition Pipeline (Fallback)

    /// Run speech recognition on the video (with 45-second timeout to prevent hangs)
    private func runSpeechPipeline(
        videoURL: URL,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> [SpeechSegment] {
        guard await hasUsableAudioTrack(videoURL) else {
            print("InstagramAutoTranscriber: Skipping speech pipeline (no audio track)")
            return []
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            print("InstagramAutoTranscriber: SFSpeechRecognizer unavailable")
            return []
        }

        let authStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authStatus == .authorized else {
            print("InstagramAutoTranscriber: Speech recognition not authorized")
            return []
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

        return await withCheckedContinuation { continuation in
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
                        continuation.resume(returning: [])
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
                        continuation.resume(returning: [])
                    }
                }
            }
        }
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

    /// Detect when speech is the primary content and visual text is incidental noise
    /// (watermarks, handles, background text) or auto-captions (subtitles that mirror speech).
    /// Returns true when the reel should be treated as voiceover-only.
    private func isVoiceoverDominant(visualWordCount: Int, speechWordCount: Int, visualSlideCount: Int = 0) -> Bool {
        if visualWordCount == 0 { return true }
        // Negligible visual text — almost certainly noise (real text reels have 15-200+ words)
        if visualWordCount <= 10 && speechWordCount > 0 { return true }
        // Visual text is minor compared to speech (noise + meaningful voiceover)
        if speechWordCount >= visualWordCount * 4 && visualWordCount <= 25 { return true }
        // Auto-caption detection: many tiny slides (1-3 words each) = subtitles, not content.
        // Real text-on-screen reels have 5-30 words per slide; auto-captions have 1-3.
        if visualSlideCount >= 10 && speechWordCount > 0 {
            let avgWordsPerSlide = visualWordCount / max(visualSlideCount, 1)
            if avgWordsPerSlide < 4 { return true }
        }
        return false
    }

    /// Merge OCR and speech results based on what was detected
    private func mergeResults(
        ocr: [OCRFrameResult],
        speech: [SpeechSegment],
        duration: TimeInterval
    ) -> TranscriptionResult {
        let hasOCR = !ocr.isEmpty
        let hasSpeech = !speech.isEmpty

        var contentType: TranscriptionContentType
        var slides: [TranscriptSlide]
        let avgConfidence: Float

        if hasOCR && hasSpeech {
            // Compute OCR slides to get both word count and slide count for heuristics
            let ocrSlides = ocrToSlides(ocr: ocr)
            let ocrWordCount = ocrSlides.map(\.text).joined(separator: " ")
                .split(separator: " ").count
            let speechWordCount = speech.map(\.text).joined(separator: " ")
                .split(separator: " ").count

            if isVoiceoverDominant(visualWordCount: ocrWordCount, speechWordCount: speechWordCount, visualSlideCount: ocrSlides.count) {
                // OCR text is noise or auto-captions — use speech as single block
                print("InstagramAutoTranscriber: Voiceover dominant (\(ocrWordCount) visual words in \(ocrSlides.count) slides vs \(speechWordCount) speech words) — treating as voiceover-only")
                contentType = .voiceoverOnly
                slides = speechToSlides(speech: speech)
                avgConfidence = 1.0
            } else {
                contentType = .voiceoverPlusText
                slides = mergeVoiceoverPlusText(ocr: ocr, speech: speech)
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

        slides = postProcessSlides(slides, contentType: contentType)
        if slides.isEmpty {
            contentType = .empty
            slides = [TranscriptSlide(text: "", slideNumber: 1, source: .manual)]
        }

        return TranscriptionResult(
            slides: slides,
            contentType: contentType,
            averageOCRConfidence: avgConfidence
        )
    }

    /// Convert OCR results into slides by detecting slide changes via Jaccard similarity
    private func ocrToSlides(ocr: [OCRFrameResult]) -> [TranscriptSlide] {
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
        speech: [SpeechSegment]
    ) -> [TranscriptSlide] {
        let visualSlides = ocrToSlides(ocr: ocr)
        guard !visualSlides.isEmpty else {
            // No visual slides detected — fall back to speech as single block
            return speechToSlides(speech: speech)
        }

        var merged = visualSlides
        for (idx, slide) in merged.enumerated() {
            let slideStart = slide.timestamp ?? 0
            let slideEnd = slide.endTimestamp ?? slideStart + 3

            let overlapping = speech.filter { segment in
                segment.timestamp >= slideStart - 0.5 &&
                segment.timestamp <= slideEnd + 0.5
            }

            if !overlapping.isEmpty {
                let spokenText = overlapping.map(\.text).joined(separator: " ")
                let slideNorm = normalizedLineKey(slide.text)
                let speechNorm = normalizedLineKey(spokenText)
                if !slideNorm.contains(speechNorm) && !speechNorm.contains(slideNorm) {
                    merged[idx].text += "\n[Voiceover: \(spokenText)]"
                    merged[idx].source = .merged
                }
            }
        }

        for i in merged.indices { merged[i].slideNumber = i + 1 }
        return merged
    }

    // MARK: - Claude Cleanup

    /// Clean up and deduplicate OCR slides using Claude.
    /// Always called for Instagram reels to filter background noise and fix artifacts.
    func cleanupWithClaude(slides: [TranscriptSlide], isCarousel: Bool = false) async -> [TranscriptSlide]? {
        let slideTexts = slides.map(\.text)

        let lineBreakRule: String
        if isCarousel {
            lineBreakRule = """
            6. PRESERVE intentional line breaks from the original slide. Carousel slides often have \
            deliberate formatting — bullet points, short punchy lines, lists, or headers on separate lines. \
            Keep those line breaks. Only join lines that are clearly a single sentence fragmented by OCR. \
            However, if multiple lines are clearly part of the same flowing paragraph (full sentences that \
            continue from one line to the next), join them into one paragraph.
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
        main text overlays that the creator intended viewers to read.

        RULES:
        1. REMOVE background text: brand names, watermarks, URLs, UI elements, text visible \
        in background images, or any text that is clearly not the main overlay.
        2. REMOVE duplicate slides: if two consecutive slides say essentially the same thing \
        (even with slight OCR variations), keep only the better/more complete version.
        3. FIX OCR artifacts: truncated words, random symbols, garbled characters, wrong \
        numbers/letters from OCR misreads.
        4. FIX incomplete sentences: if a sentence is clearly cut off mid-word due to OCR, \
        complete the word naturally or remove the fragment.
        5. KEEP the creator's original wording — do not rephrase or add new content.
        \(lineBreakRule)
        7. Each slide should contain the COMPLETE text from that slide — do not \
        truncate or summarize.

        Return ONLY a JSON array of strings — one string per cleaned slide. You may return \
        FEWER slides than the input if you removed duplicates. Empty slides should be omitted.

        Raw OCR slides:
        \(slideTexts.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n"))
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            let cleaned = parseCleanedSlides(from: response).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !cleaned.isEmpty else { return nil }

            // Claude may return fewer slides (duplicates removed) — build new slide array
            return cleaned.enumerated().map { index, text in
                // Try to carry over timestamp from matching original slide
                let originalSlide = index < slides.count ? slides[index] : nil
                return TranscriptSlide(
                    text: text,
                    slideNumber: index + 1,
                    timestamp: originalSlide?.timestamp,
                    endTimestamp: originalSlide?.endTimestamp,
                    source: .aiCleaned
                )
            }
        } catch {
            print("InstagramAutoTranscriber: Claude cleanup failed: \(error)")
            return nil
        }
    }

    /// Parse a JSON array of strings from Claude's response
    private func parseCleanedSlides(from response: String) -> [String] {
        // Try to find JSON array in response
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try direct parse first
        if let data = trimmed.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            return array
        }

        // Try extracting JSON from markdown code block
        if let jsonStart = trimmed.range(of: "["),
           let jsonEnd = trimmed.range(of: "]", options: .backwards) {
            let jsonString = String(trimmed[jsonStart.lowerBound...jsonEnd.upperBound])
            if let data = jsonString.data(using: .utf8),
               let array = try? JSONDecoder().decode([String].self, from: data) {
                return array
            }
        }

        return []
    }

    // MARK: - Text Helpers

    private func postProcessSlides(
        _ slides: [TranscriptSlide],
        contentType: TranscriptionContentType
    ) -> [TranscriptSlide] {
        guard !slides.isEmpty else { return [] }

        var sanitized: [TranscriptSlide] = slides.compactMap { slide in
            var updated = slide
            updated.text = sanitizeSlideText(slide.text)
            return updated.text.isEmpty ? nil : updated
        }

        sanitized = collapseNearDuplicateAdjacentSlides(sanitized)
        sanitized = correctLikelyYearOutliers(in: sanitized)

        for index in sanitized.indices {
            sanitized[index].slideNumber = index + 1
        }

        return sanitized
    }

    private func sanitizeSlideText(_ text: String) -> String {
        let rawLines = text
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        var mergedLines: [String] = []
        for line in rawLines {
            guard !isLikelyArtifactLine(line) else { continue }
            if let last = mergedLines.last, shouldJoinLine(previous: last, next: line) {
                mergedLines.removeLast()
                let joiner = last.hasSuffix("-") ? "" : " "
                let stitched = (last + joiner + line).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                mergedLines.append(stitched.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                mergedLines.append(line)
            }
        }

        mergedLines = deduplicateLinesPreservingOrder(mergedLines)
        let joined = mergedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizeStandaloneYearArtifacts(in: joined)
    }

    private func shouldJoinLine(previous: String, next: String) -> Bool {
        if previous.hasSuffix("-") { return true }
        if next.count <= 3 { return true }
        if next.first?.isLowercase == true && !endsSentence(previous) { return true }
        if previous.count <= 14 && next.count <= 14 { return true }
        return false
    }

    private func endsSentence(_ line: String) -> Bool {
        guard let last = line.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return [".", "!", "?", ":"].contains(last)
    }

    private func isLikelyArtifactLine(_ line: String) -> Bool {
        let compact = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= 1 { return true }

        let symbols = compact.unicodeScalars.filter { !CharacterSet.alphanumerics.contains($0) && !$0.properties.isWhitespace }
        if symbols.count >= 3 { return true }

        let words = compact.split(separator: " ").map(String.init)
        if words.count == 1 {
            let word = words[0]
            if word.count <= 3 { return true }
            let letters = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            let vowels = letters.filter { "aeiouAEIOU".unicodeScalars.contains($0) }
            if letters.count >= 5 && vowels.count == 0 { return true }
        }

        return false
    }

    private func collapseNearDuplicateAdjacentSlides(_ slides: [TranscriptSlide]) -> [TranscriptSlide] {
        guard !slides.isEmpty else { return [] }

        var collapsed: [TranscriptSlide] = []
        for slide in slides {
            guard var last = collapsed.last else {
                collapsed.append(slide)
                continue
            }

            if areLikelyDuplicateSlides(last, slide) {
                if slide.text.count > last.text.count {
                    last.text = slide.text
                }
                if let newerEnd = slide.endTimestamp {
                    last.endTimestamp = newerEnd
                } else if let newerTimestamp = slide.timestamp {
                    last.endTimestamp = newerTimestamp
                }
                collapsed[collapsed.count - 1] = last
            } else {
                collapsed.append(slide)
            }
        }

        return collapsed
    }

    private func areLikelyDuplicateSlides(_ lhs: TranscriptSlide, _ rhs: TranscriptSlide) -> Bool {
        let lhsFingerprint = normalizedTextFingerprint(lhs.text)
        let rhsFingerprint = normalizedTextFingerprint(rhs.text)
        guard !lhsFingerprint.isEmpty, !rhsFingerprint.isEmpty else { return false }

        if lhsFingerprint == rhsFingerprint { return true }

        let lhsTokens = Set(lhsFingerprint.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhsFingerprint.split(separator: " ").map(String.init))

        // Check if one slide's text is a subset of the other (handles partial OCR reads).
        // Only apply when BOTH slides have enough tokens — prevents short slides
        // (e.g., "2016" or a brief hook) from being absorbed into longer neighbors.
        if lhsTokens.count >= 6 && rhsTokens.count >= 6 {
            let smaller = min(lhsTokens.count, rhsTokens.count)
            let intersection = lhsTokens.intersection(rhsTokens).count
            if smaller > 0 && Double(intersection) / Double(smaller) >= 0.85 {
                return true
            }
        }

        let overlap = jaccardSimilarity(lhsTokens, rhsTokens)

        let lhsTime = lhs.endTimestamp ?? lhs.timestamp ?? 0
        let rhsTime = rhs.timestamp ?? rhs.endTimestamp ?? lhsTime
        let timeGap = max(0, rhsTime - lhsTime)

        return overlap >= 0.75 && timeGap <= 5.0
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
            guard let cleaned = cleanOCRLine(line) else { continue }
            let normalized = normalizedLineKey(cleaned)
            guard !normalized.isEmpty else { continue }

            let isDuplicate = normalizedSeen.contains { existing in
                existing == normalized ||
                    existing.contains(normalized) ||
                    normalized.contains(existing)
            }

            if !isDuplicate {
                unique.append(cleaned)
                normalizedSeen.append(normalized)
            }
        }

        return unique
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
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> TranscriptionResult {
        let imageItems = items.filter { $0.mediaType == .image }
        guard !imageItems.isEmpty else {
            return TranscriptionResult(slides: [], contentType: .empty, averageOCRConfidence: 0)
        }

        print("InstagramAutoTranscriber: Starting carousel transcription (\(imageItems.count) images)")

        var slides: [TranscriptSlide] = []
        var totalConfidence: Float = 0
        var lowOCRItems: [(index: Int, jpegData: Data, slideIndex: Int)] = []

        // Phase 1: Download images and run Vision OCR
        for (idx, item) in imageItems.enumerated() {
            let progress = Double(idx) / Double(imageItems.count)
            progressHandler(.recognizingText(progress))

            // Download image
            guard let imageData = await downloadImage(url: item.mediaURL) else {
                slides.append(TranscriptSlide(text: "", slideNumber: idx + 1, source: .visionOCR))
                continue
            }

            // Create CGImage
            guard let cgImage = createCGImage(from: imageData) else {
                slides.append(TranscriptSlide(text: "", slideNumber: idx + 1, source: .visionOCR))
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

        return TranscriptionResult(
            slides: slides,
            contentType: contentType,
            averageOCRConfidence: avgConfidence
        )
    }

    // MARK: - Carousel Helpers

    /// Download an image from a URL
    private func downloadImage(url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return data
        } catch {
            print("InstagramAutoTranscriber: Image download failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Create a CGImage from image data
    private func createCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Call Gemini Vision for a single carousel image
    private nonisolated func callGeminiVisionForSingleImage(
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

    nonisolated private func cleanOCRLine(_ raw: String) -> String? {
        let compact = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")

        guard compact.count >= 3 else { return nil }

        let scalarCount = compact.unicodeScalars.count
        guard scalarCount > 0 else { return nil }

        let alphaNumericCount = compact.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        if Double(alphaNumericCount) / Double(scalarCount) < 0.45 {
            return nil
        }

        return compact
    }

    nonisolated private func normalizedLineKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s$%'/]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
