// CosmoOS/SwipeFile/Instagram/InstagramAutoTranscriber.swift
// Dual-pipeline auto-transcription engine for Instagram reels/videos
// Runs Vision OCR + SFSpeechRecognizer in parallel
// February 2026

import Foundation
import AVFoundation
import Vision
import Speech

// MARK: - Transcription Progress

/// Progress stages reported during auto-transcription
enum TranscriptionProgress: Sendable {
    case extractingFrames(Double)    // 0.0–1.0
    case recognizingText(Double)     // 0.0–1.0
    case recognizingSpeech(Double)   // 0.0–1.0
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
    let texts: Set<String>
    let confidence: Float
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
    private let jaccardThreshold: Double = 0.5

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
        // Run both pipelines in parallel
        async let ocrResults = runOCRPipeline(videoURL: videoURL, duration: duration, progressHandler: progressHandler)
        async let speechResults = runSpeechPipeline(videoURL: videoURL, progressHandler: progressHandler)

        let ocr = await ocrResults
        let speech = await speechResults

        // Merge results
        await MainActor.run { progressHandler(.mergingResults) }

        let result = mergeResults(ocr: ocr, speech: speech, duration: duration)

        await MainActor.run { progressHandler(.complete) }

        return result
    }

    // MARK: - Vision OCR Pipeline

    /// Extract frames and run text recognition
    private func runOCRPipeline(
        videoURL: URL,
        duration: TimeInterval,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> [OCRFrameResult] {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

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

    /// Run VNRecognizeTextRequest on a single frame
    private func recognizeText(in image: CGImage, at timestamp: TimeInterval) async -> OCRFrameResult? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                var texts = Set<String>()
                var totalConfidence: Float = 0

                for observation in observations {
                    if let candidate = observation.topCandidates(1).first {
                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty && text.count > 1 { // Skip single chars
                            texts.insert(text)
                            totalConfidence += candidate.confidence
                        }
                    }
                }

                guard !texts.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let avgConfidence = totalConfidence / Float(texts.count)
                continuation.resume(returning: OCRFrameResult(
                    timestamp: timestamp,
                    texts: texts,
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

    // MARK: - Speech Recognition Pipeline

    /// Run speech recognition on the video
    private func runSpeechPipeline(
        videoURL: URL,
        progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async -> [SpeechSegment] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            return []
        }

        let authStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authStatus == .authorized else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: videoURL)
            request.requiresOnDeviceRecognition = true
            request.addsPunctuation = true
            request.shouldReportPartialResults = false

            recognizer.recognitionTask(with: request) { result, error in
                guard let result = result, result.isFinal else {
                    if error != nil || (result == nil && error != nil) {
                        continuation.resume(returning: [])
                    }
                    return
                }

                Task { @MainActor in
                    progressHandler(.recognizingSpeech(1.0))
                }

                // Consolidate word-level segments into sentences
                let segments = self.consolidateSegments(from: result)
                continuation.resume(returning: segments)
            }
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

    /// Merge OCR and speech results based on what was detected
    private func mergeResults(
        ocr: [OCRFrameResult],
        speech: [SpeechSegment],
        duration: TimeInterval
    ) -> TranscriptionResult {
        let hasOCR = !ocr.isEmpty
        let hasSpeech = !speech.isEmpty

        let contentType: TranscriptionContentType
        let slides: [TranscriptSlide]
        let avgConfidence: Float

        if hasOCR && hasSpeech {
            contentType = .voiceoverPlusText
            slides = mergeVoiceoverPlusText(ocr: ocr, speech: speech)
            avgConfidence = ocr.map(\.confidence).reduce(0, +) / Float(ocr.count)
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

        return TranscriptionResult(
            slides: slides,
            contentType: contentType,
            averageOCRConfidence: avgConfidence
        )
    }

    /// Convert OCR results into slides by detecting slide changes via Jaccard similarity
    private func ocrToSlides(ocr: [OCRFrameResult]) -> [TranscriptSlide] {
        guard !ocr.isEmpty else { return [] }

        var slides: [TranscriptSlide] = []
        var currentTexts = Set<String>()
        var slideStart: TimeInterval = ocr[0].timestamp
        var slideNumber = 1

        for (index, frame) in ocr.enumerated() {
            if index == 0 {
                currentTexts = frame.texts
                continue
            }

            // Jaccard similarity between current slide texts and this frame
            let intersection = currentTexts.intersection(frame.texts).count
            let union = currentTexts.union(frame.texts).count
            let similarity = union > 0 ? Double(intersection) / Double(union) : 0

            if similarity < jaccardThreshold {
                // Slide change detected — commit current slide
                let text = deduplicateAndJoin(currentTexts)
                if !text.isEmpty {
                    slides.append(TranscriptSlide(
                        text: text,
                        slideNumber: slideNumber,
                        timestamp: slideStart,
                        endTimestamp: frame.timestamp,
                        source: .visionOCR
                    ))
                    slideNumber += 1
                }
                currentTexts = frame.texts
                slideStart = frame.timestamp
            } else {
                // Same slide — accumulate texts
                currentTexts = currentTexts.union(frame.texts)
            }
        }

        // Flush last slide
        let text = deduplicateAndJoin(currentTexts)
        if !text.isEmpty {
            slides.append(TranscriptSlide(
                text: text,
                slideNumber: slideNumber,
                timestamp: slideStart,
                endTimestamp: ocr.last?.timestamp,
                source: .visionOCR
            ))
        }

        return slides
    }

    /// Convert speech segments into slides
    private func speechToSlides(speech: [SpeechSegment]) -> [TranscriptSlide] {
        speech.enumerated().map { index, segment in
            TranscriptSlide(
                text: segment.text,
                slideNumber: index + 1,
                timestamp: segment.timestamp,
                endTimestamp: segment.timestamp + segment.duration,
                source: .speechAudio
            )
        }
    }

    /// Merge voiceover + text: speech is primary, OCR text appended as annotations
    private func mergeVoiceoverPlusText(
        ocr: [OCRFrameResult],
        speech: [SpeechSegment]
    ) -> [TranscriptSlide] {
        speech.enumerated().map { index, segment in
            // Find OCR frames that overlap with this speech segment
            let overlapping = ocr.filter { frame in
                frame.timestamp >= segment.timestamp &&
                frame.timestamp <= segment.timestamp + segment.duration
            }

            var text = segment.text
            if !overlapping.isEmpty {
                let ocrTexts = Set(overlapping.flatMap(\.texts))
                let onScreenText = deduplicateAndJoin(ocrTexts)
                if !onScreenText.isEmpty {
                    text += "\n[On-screen: \(onScreenText)]"
                }
            }

            return TranscriptSlide(
                text: text,
                slideNumber: index + 1,
                timestamp: segment.timestamp,
                endTimestamp: segment.timestamp + segment.duration,
                source: .merged
            )
        }
    }

    // MARK: - Claude Cleanup

    /// Clean up noisy OCR text using Claude when confidence is low
    func cleanupWithClaude(slides: [TranscriptSlide]) async -> [TranscriptSlide]? {
        let slideTexts = slides.map(\.text)
        let prompt = """
        Clean up these auto-transcribed text slides from an Instagram reel. \
        Fix OCR artifacts, typos, and formatting issues. Keep the original meaning. \
        Return ONLY a JSON array of strings, one per slide, in the same order.

        Slides:
        \(slideTexts.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n"))
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            // Parse JSON array from response
            let cleaned = parseCleanedSlides(from: response)
            guard cleaned.count == slides.count else { return nil }

            return zip(slides, cleaned).enumerated().map { index, pair in
                var slide = pair.0
                let cleanedText = pair.1
                slide = TranscriptSlide(
                    id: slide.id,
                    text: cleanedText,
                    slideNumber: slide.slideNumber,
                    timestamp: slide.timestamp,
                    endTimestamp: slide.endTimestamp,
                    source: .aiCleaned
                )
                return slide
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

    /// Deduplicate and join a set of OCR text strings
    private func deduplicateAndJoin(_ texts: Set<String>) -> String {
        // Sort by length (longest first) and remove substrings
        let sorted = texts.sorted { $0.count > $1.count }
        var unique: [String] = []

        for text in sorted {
            let isSubstring = unique.contains { existing in
                existing.localizedCaseInsensitiveContains(text)
            }
            if !isSubstring {
                unique.append(text)
            }
        }

        return unique.joined(separator: "\n")
    }
}
