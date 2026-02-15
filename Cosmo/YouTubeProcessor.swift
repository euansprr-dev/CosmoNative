// CosmoOS/Cosmo/YouTubeProcessor.swift
// YouTube video processing - metadata, audio download, transcription, summarization
// Uses local Whisper (via Apple Speech) for transcription, LocalLLM for summaries

import Foundation
import AVFoundation
import Speech

// MARK: - YouTube Data
struct YouTubeData {
    let videoId: String
    let title: String
    let channelName: String?
    let description: String?
    let duration: Int?             // seconds
    let thumbnailURL: URL?
    let transcript: [TranscriptSegment]
    let summary: String?
    let publishedAt: String?
    let formattedTranscript: String?            // AI-formatted markdown version
    let transcriptSections: [TranscriptSectionData]?  // Chapter breakdown
    let transcriptStatus: TranscriptStatus      // Track transcript availability

    enum TranscriptStatus: String, Codable {
        case available = "available"
        case unavailable = "unavailable"
        case pending = "pending"
    }
}

// MARK: - YouTube Processor
@MainActor
final class YouTubeProcessor {
    static let shared = YouTubeProcessor()

    private let fileManager = FileManager.default
    private var tempDirectory: URL {
        fileManager.temporaryDirectory.appendingPathComponent("CosmoOS/YouTube", isDirectory: true)
    }

    private init() {
        // Ensure temp directory exists
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Process Video
    /// Full pipeline: metadata -> captions/transcribe -> summarize
    /// Uses fast caption fetching first, falls back to audio transcription if unavailable
    func process(videoId: String, progressHandler: ((YouTubeProcessingStep) -> Void)? = nil) async throws -> YouTubeData {
        print("🎬 Processing YouTube video: \(videoId)")

        // Step 1: Fetch metadata
        progressHandler?(.fetchingMetadata)
        let metadata = try await fetchMetadata(videoId: videoId)
        print("   Title: \(metadata.title)")

        // Step 2: Try fast caption fetching first (< 2 seconds)
        progressHandler?(.fetchingCaptions)
        var transcript: [TranscriptSegment] = []
        var transcriptStatus: YouTubeData.TranscriptStatus = .unavailable

        if let captions = await fetchCaptions(videoId: videoId) {
            transcript = captions
            transcriptStatus = .available
            print("   ✅ Captions fetched: \(transcript.count) segments (fast path)")
        } else {
            // Step 2b: Fallback to audio download + transcription (slow path)
            print("   ⚠️ No captions available, falling back to audio transcription...")
            progressHandler?(.downloadingAudio)

            do {
                let audioPath = try await downloadAudio(videoId: videoId)
                print("   Audio downloaded: \(audioPath.lastPathComponent)")

                progressHandler?(.transcribing)
                transcript = try await transcribeAudio(at: audioPath)
                transcriptStatus = .available
                print("   Transcribed: \(transcript.count) segments (slow path)")

                // Cleanup temp audio
                try? fileManager.removeItem(at: audioPath)
            } catch {
                // Audio transcription failed - continue without transcript
                // Video embed + metadata still works, user can retry later
                print("   ⚠️ Audio transcription failed: \(error.localizedDescription)")
                print("   ℹ️ Saving video without transcript (embed + metadata available)")
                transcriptStatus = .unavailable
            }
        }

        // Step 3: Generate summary
        progressHandler?(.summarizing)
        let fullText = transcript.map { $0.text }.joined(separator: " ")
        let summary = try await generateSummary(text: fullText, title: metadata.title)
        print("   Summary generated")

        // Step 4: Generate formatted transcript and sections
        progressHandler?(.formattingTranscript)
        let (formattedTranscript, sections) = await generateFormattedTranscript(
            segments: transcript,
            title: metadata.title
        )
        print("   Transcript formatted: \(sections?.count ?? 0) sections")

        progressHandler?(.complete)

        return YouTubeData(
            videoId: videoId,
            title: metadata.title,
            channelName: metadata.channelName,
            description: metadata.description,
            duration: metadata.duration,
            thumbnailURL: URLClassifier.youtubeThumbnailURL(videoId: videoId, quality: .maxRes),
            transcript: transcript,
            summary: summary,
            publishedAt: metadata.publishedAt,
            formattedTranscript: formattedTranscript,
            transcriptSections: sections,
            transcriptStatus: transcriptStatus
        )
    }

    // MARK: - Fetch Captions (Fast Path)
    /// Fetch YouTube's built-in captions using yt-dlp - takes < 2 seconds
    /// Returns nil if no captions are available for the video
    func fetchCaptions(videoId: String) async -> [TranscriptSegment]? {
        guard let ytdlp = findYtDlp() else {
            print("   ⚠️ yt-dlp not found, skipping caption fetch")
            return nil
        }

        let outputTemplate = tempDirectory.appendingPathComponent(videoId).path

        // Clean up any existing caption files
        let possibleExtensions = [".en.json3", ".en-orig.json3", ".en.vtt"]
        for ext in possibleExtensions {
            try? fileManager.removeItem(atPath: outputTemplate + ext)
        }

        // Fetch captions using yt-dlp
        let success = await fetchCaptionsWithYtDlp(ytdlp: ytdlp, videoId: videoId, outputTemplate: outputTemplate)

        guard success else {
            return nil
        }

        // Find the downloaded caption file
        let captionPath = findCaptionFile(basePath: outputTemplate)
        guard let path = captionPath else {
            print("   ⚠️ Caption file not found after download")
            return nil
        }

        // Parse the caption file
        let segments = parseCaptionFile(at: path)

        // Cleanup
        try? fileManager.removeItem(atPath: path)

        return segments
    }

    private func fetchCaptionsWithYtDlp(ytdlp: String, videoId: String, outputTemplate: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ytdlp)
                process.arguments = [
                    "--write-subs",                // Download manual subtitles (higher quality)
                    "--write-auto-subs",           // Also download auto-generated captions as fallback
                    "--sub-langs", "en,en-US,en-orig,en.*",  // English captions (prefer en, then en-US)
                    "--sub-format", "json3",       // JSON3 format with timestamps
                    "--skip-download",             // Don't download video/audio
                    "--no-warnings",               // Suppress warnings (like impersonation)
                    "--ignore-errors",             // Continue even if some subtitle variants fail
                    "-o", outputTemplate,          // Output path template
                    "https://www.youtube.com/watch?v=\(videoId)"
                ]

                // Set PATH to include Homebrew locations
                var env = ProcessInfo.processInfo.environment
                let homebrewPaths = "/opt/homebrew/bin:/usr/local/bin"
                if let existingPath = env["PATH"] {
                    env["PATH"] = "\(homebrewPaths):\(existingPath)"
                } else {
                    env["PATH"] = homebrewPaths
                }
                process.environment = env

                let errorPipe = Pipe()
                let outputPipe = Pipe()
                process.standardError = errorPipe
                process.standardOutput = outputPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    // Always check if any caption file was created (regardless of exit code)
                    // yt-dlp may exit with non-zero code if ONE variant fails, but others succeed
                    let possibleFiles = [".en.json3", ".en-US.json3", ".en-orig.json3"]
                    var captionFileExists = false
                    for ext in possibleFiles {
                        let path = outputTemplate + ext
                        if FileManager.default.fileExists(atPath: path) {
                            print("   ✅ Found caption file: \(ext)")
                            captionFileExists = true
                            break
                        }
                    }

                    if captionFileExists {
                        continuation.resume(returning: true)
                    } else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? ""
                        if errorMessage.contains("no subtitles") || errorMessage.contains("Subtitles are disabled") {
                            print("   ℹ️ Video has no captions available")
                        } else if !errorMessage.isEmpty && !errorMessage.contains("impersonat") {
                            print("   ⚠️ yt-dlp caption error: \(errorMessage.prefix(200))")
                        }
                        continuation.resume(returning: false)
                    }
                } catch {
                    print("   ⚠️ Failed to run yt-dlp for captions: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func findCaptionFile(basePath: String) -> String? {
        // yt-dlp creates files like: VIDEO_ID.en.json3 or VIDEO_ID.en-orig.json3
        // Prefer manual captions (en, en-US) over auto-generated (en-orig)
        let possibleExtensions = [".en.json3", ".en-US.json3", ".en-orig.json3"]

        for ext in possibleExtensions {
            let path = basePath + ext
            if fileManager.fileExists(atPath: path) {
                print("   📝 Using caption file: \(ext)")
                return path
            }
        }

        // Try to find any .json3 file in the temp directory matching the video ID
        let videoId = (basePath as NSString).lastPathComponent
        if let contents = try? fileManager.contentsOfDirectory(atPath: tempDirectory.path) {
            for file in contents where file.hasPrefix(videoId) && file.hasSuffix(".json3") {
                print("   📝 Found caption file: \(file)")
                return tempDirectory.appendingPathComponent(file).path
            }
        }

        return nil
    }

    // MARK: - Parse Caption File
    /// Parse JSON3 caption format from yt-dlp into TranscriptSegments
    private func parseCaptionFile(at path: String) -> [TranscriptSegment]? {
        guard let data = fileManager.contents(atPath: path) else {
            print("   ⚠️ Could not read caption file")
            return nil
        }

        // JSON3 format structure
        struct JSON3Caption: Codable {
            let events: [JSON3Event]?
        }

        struct JSON3Event: Codable {
            let tStartMs: Int?
            let dDurationMs: Int?
            let segs: [JSON3Segment]?
        }

        struct JSON3Segment: Codable {
            let utf8: String?
        }

        guard let json3 = try? JSONDecoder().decode(JSON3Caption.self, from: data),
              let events = json3.events else {
            print("   ⚠️ Could not parse JSON3 caption format")
            return nil
        }

        var segments: [TranscriptSegment] = []
        var currentText = ""
        var currentStartMs: Int = 0
        var currentEndMs: Int = 0

        // Target segment duration (15-20 seconds for readable chunks)
        let targetSegmentMs = 15000

        for event in events {
            guard let startMs = event.tStartMs,
                  let durationMs = event.dDurationMs,
                  let segs = event.segs else {
                continue
            }

            // Combine segment text
            let eventText = segs.compactMap { $0.utf8 }.joined()
            let cleanText = eventText.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")

            guard !cleanText.isEmpty && cleanText != " " else { continue }

            if currentText.isEmpty {
                currentStartMs = startMs
            }

            currentText += (currentText.isEmpty ? "" : " ") + cleanText
            currentEndMs = startMs + durationMs

            // Check if we should create a new segment
            let segmentDuration = currentEndMs - currentStartMs
            let endsWithPunctuation = cleanText.last.map { ".!?".contains($0) } ?? false

            if segmentDuration >= targetSegmentMs && endsWithPunctuation {
                segments.append(TranscriptSegment(
                    start: Double(currentStartMs) / 1000.0,
                    end: Double(currentEndMs) / 1000.0,
                    text: currentText.trimmingCharacters(in: .whitespaces)
                ))
                currentText = ""
            }
        }

        // Don't forget the last segment
        if !currentText.isEmpty {
            segments.append(TranscriptSegment(
                start: Double(currentStartMs) / 1000.0,
                end: Double(currentEndMs) / 1000.0,
                text: currentText.trimmingCharacters(in: .whitespaces)
            ))
        }

        print("   📝 Parsed \(events.count) caption events into \(segments.count) segments")
        return segments.isEmpty ? nil : segments
    }

    // MARK: - Fetch Metadata
    /// Fetch video metadata using oEmbed (no API key required)
    func fetchMetadata(videoId: String) async throws -> YouTubeMetadata {
        let oembedURL = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoId)&format=json")!

        let (data, response) = try await URLSession.shared.data(from: oembedURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw YouTubeError.metadataFetchFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        return YouTubeMetadata(
            title: json?["title"] as? String ?? "Untitled Video",
            channelName: json?["author_name"] as? String,
            description: nil,  // oEmbed doesn't provide description
            duration: nil,     // Would need iframe API or page scrape
            publishedAt: nil
        )
    }

    // MARK: - Download Audio
    /// Download audio using yt-dlp (if installed) or fallback
    func downloadAudio(videoId: String) async throws -> URL {
        let outputPath = tempDirectory.appendingPathComponent("\(videoId).m4a")

        // Check if yt-dlp is available
        let ytdlpPath = findYtDlp()

        if let ytdlp = ytdlpPath {
            // Use yt-dlp for download
            try await downloadWithYtDlp(ytdlp: ytdlp, videoId: videoId, output: outputPath)
        } else {
            // Fallback: inform user yt-dlp is needed
            throw YouTubeError.ytDlpNotInstalled
        }

        return outputPath
    }

    private func findYtDlp() -> String? {
        // Check common locations
        let paths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]

        for path in paths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // Check PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yt-dlp"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }

        return nil
    }

    private func downloadWithYtDlp(ytdlp: String, videoId: String, output: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ytdlp)
                process.arguments = [
                    "-x",                           // Extract audio
                    "--audio-format", "m4a",        // M4A format (native to macOS)
                    "--audio-quality", "0",         // Best quality
                    "-o", output.path,              // Output path
                    "https://www.youtube.com/watch?v=\(videoId)"
                ]

                // Set PATH to include Homebrew locations so yt-dlp can find ffmpeg
                var env = ProcessInfo.processInfo.environment
                let homebrewPaths = "/opt/homebrew/bin:/usr/local/bin"
                if let existingPath = env["PATH"] {
                    env["PATH"] = "\(homebrewPaths):\(existingPath)"
                } else {
                    env["PATH"] = homebrewPaths
                }
                process.environment = env

                let errorPipe = Pipe()
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        print("❌ yt-dlp error: \(errorMessage)")
                        continuation.resume(throwing: YouTubeError.downloadFailed(errorMessage))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Transcribe Audio
    /// Transcribe audio file using Apple Speech Framework with timeout
    /// Note: Apple Speech has ~1 minute limit for on-device recognition
    func transcribeAudio(at url: URL) async throws -> [TranscriptSegment] {
        // Check audio duration first - Apple Speech fails on long files
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let durationSeconds = duration.map { CMTimeGetSeconds($0) } ?? 0

        if durationSeconds > 120 {
            print("   ⚠️ Audio too long for Speech framework (\(Int(durationSeconds))s > 120s limit)")
            print("   ℹ️ Apple Speech has ~1 minute limit for on-device recognition")
            throw YouTubeError.transcriptionFailed
        }

        // Request authorization
        let authorized = await requestSpeechAuthorization()
        guard authorized else {
            throw YouTubeError.speechNotAuthorized
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw YouTubeError.speechNotAvailable
        }

        // Create recognition request from audio file
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
            request.addsPunctuation = true
        }

        print("   🎤 Starting speech recognition for \(Int(durationSeconds))s audio...")

        // Use withTaskGroup to implement timeout (2 minutes for short audio)
        let timeoutSeconds: UInt64 = 120

        // Pre-capture consolidation function to avoid self capture in async closure
        let consolidate = { (wordSegments: [SFTranscriptionSegment]) -> [TranscriptSegment] in
            self.consolidateIntoSentences(wordSegments: wordSegments)
        }

        return try await withThrowingTaskGroup(of: [TranscriptSegment].self) { group in
            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                print("   ⏰ Transcription timeout after 2 minutes")
                throw YouTubeError.transcriptionFailed
            }

            // Actual transcription task
            group.addTask { [recognizer, request, consolidate] in
                try await withCheckedThrowingContinuation { continuation in
                    var hasResumed = false
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        guard !hasResumed else { return }

                        if let error = error {
                            hasResumed = true
                            print("   ❌ Speech recognition error: \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                            return
                        }

                        guard let result = result, result.isFinal else { return }
                        hasResumed = true
                        print("   ✅ Speech recognition completed")

                        // Apple Speech returns word-by-word segments - consolidate into sentences/paragraphs
                        let wordSegments = result.bestTranscription.segments
                        let consolidatedSegments = consolidate(wordSegments)

                        // If no segments, create one from full text
                        if consolidatedSegments.isEmpty && !result.bestTranscription.formattedString.isEmpty {
                            let lastTimestamp = wordSegments.last.map { $0.timestamp + $0.duration } ?? 0
                            continuation.resume(returning: [TranscriptSegment(
                                start: 0,
                                end: lastTimestamp,
                                text: result.bestTranscription.formattedString
                            )])
                        } else {
                            continuation.resume(returning: consolidatedSegments)
                        }
                    }

                    // If task is nil (shouldn't happen), resume with empty
                    if task == nil {
                        hasResumed = true
                        print("   ⚠️ Recognition task was nil")
                        continuation.resume(returning: [])
                    }
                }
            }

            // Return first result (either success or timeout)
            if let result = try await group.next() {
                group.cancelAll()
                return result
            }

            throw YouTubeError.transcriptionFailed
        }
    }

    /// Consolidate word-by-word segments into sentence-level segments
    /// Groups words together based on punctuation (., !, ?) or significant time gaps
    private func consolidateIntoSentences(wordSegments: [SFTranscriptionSegment]) -> [TranscriptSegment] {
        guard !wordSegments.isEmpty else { return [] }

        var consolidatedSegments: [TranscriptSegment] = []
        var currentWords: [String] = []
        var currentStart: Double = wordSegments[0].timestamp
        var lastEnd: Double = 0

        // Sentence-ending punctuation
        let sentenceEnders: Set<Character> = [".", "!", "?"]

        // Time gap threshold for starting a new segment (2.5 seconds)
        let timeGapThreshold: Double = 2.5

        // Target segment duration for longer segments (roughly 15-20 seconds for paragraph-level)
        let maxSegmentDuration: Double = 20.0

        for wordSegment in wordSegments {
            let word = wordSegment.substring
            let wordStart = wordSegment.timestamp
            let wordEnd = wordSegment.timestamp + wordSegment.duration

            // Check for significant time gap (new paragraph/topic)
            let hasTimeGap = !currentWords.isEmpty && (wordStart - lastEnd) > timeGapThreshold

            // Check if previous text ended with sentence-ending punctuation
            let lastWord = currentWords.last ?? ""
            let endsWithPunctuation = lastWord.last.map { sentenceEnders.contains($0) } ?? false

            // Check if current segment is getting too long
            let currentDuration = lastEnd - currentStart
            let segmentTooLong = currentDuration > maxSegmentDuration && endsWithPunctuation

            // Start new segment if: time gap, or sentence ended and (next is new sentence or segment too long)
            if hasTimeGap || segmentTooLong {
                // Save current segment if it has content
                if !currentWords.isEmpty {
                    let text = currentWords.joined(separator: " ")
                    consolidatedSegments.append(TranscriptSegment(
                        start: currentStart,
                        end: lastEnd,
                        text: text
                    ))
                }

                // Start new segment
                currentWords = [word]
                currentStart = wordStart
            } else {
                // Continue building current segment
                currentWords.append(word)
            }

            lastEnd = wordEnd
        }

        // Don't forget the last segment
        if !currentWords.isEmpty {
            let text = currentWords.joined(separator: " ")
            consolidatedSegments.append(TranscriptSegment(
                start: currentStart,
                end: lastEnd,
                text: text
            ))
        }

        print("📝 Consolidated \(wordSegments.count) words into \(consolidatedSegments.count) sentence segments")
        return consolidatedSegments
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Generate Summary
    /// Generate AI summary using LocalLLM
    func generateSummary(text: String, title: String) async throws -> String? {
        // Check if text is too short
        guard text.count > 100 else {
            return nil
        }

        // Truncate if too long for local model
        let maxChars = 8000
        let truncatedText = text.count > maxChars ? String(text.prefix(maxChars)) + "..." : text

        let prompt = """
        Summarize this YouTube video transcript in 3-5 key bullet points.

        Video Title: \(title)

        Transcript:
        \(truncatedText)

        Summary:
        """

        // Use LocalLLM
        let summary = await LocalLLM.shared.generate(prompt: prompt, maxTokens: 500)
        return summary.isEmpty ? nil : summary
    }
    
    // MARK: - Generate Formatted Transcript
    /// Format raw transcript with structure - preserves ALL content, no summarization
    /// This creates a readable markdown version while keeping every word from the original
    func generateFormattedTranscript(
        segments: [TranscriptSegment],
        title: String
    ) async -> (String?, [TranscriptSectionData]?) {
        guard !segments.isEmpty else { return (nil, nil) }

        let fullText = segments.map { $0.text }.joined(separator: " ")
        guard fullText.count > 100 else { return (nil, nil) }

        // Process the full transcript in chunks if needed to preserve ALL content
        let formattedTranscript = await formatFullTranscript(fullText: fullText, title: title)

        // Generate section breakdown for navigation (this is separate from the full transcript)
        let sections = await generateSectionBreakdown(segments: segments, title: title)

        return (formattedTranscript, sections)
    }

    /// Format the FULL transcript preserving all content - no summarization
    private func formatFullTranscript(fullText: String, title: String) async -> String? {
        // Chunk size for processing (model context limit consideration)
        let chunkSize = 10000

        // If text is short enough, process in one go
        if fullText.count <= chunkSize {
            return await formatTranscriptChunk(text: fullText, title: title, isFirstChunk: true)
        }

        // For longer transcripts, process in chunks and combine
        var formattedParts: [String] = []
        var currentIndex = fullText.startIndex
        var chunkNumber = 0

        while currentIndex < fullText.endIndex {
            let chunkEndOffset = min(chunkSize, fullText.distance(from: currentIndex, to: fullText.endIndex))
            var chunkEnd = fullText.index(currentIndex, offsetBy: chunkEndOffset)

            // Try to break at a sentence boundary (., !, ?)
            if chunkEnd < fullText.endIndex {
                let searchRange = fullText.index(chunkEnd, offsetBy: -200, limitedBy: currentIndex) ?? currentIndex
                if let sentenceEnd = fullText[searchRange..<chunkEnd].lastIndex(where: { ".!?".contains($0) }) {
                    chunkEnd = fullText.index(after: sentenceEnd)
                }
            }

            let chunk = String(fullText[currentIndex..<chunkEnd])
            let isFirst = chunkNumber == 0

            if let formattedChunk = await formatTranscriptChunk(text: chunk, title: title, isFirstChunk: isFirst) {
                formattedParts.append(formattedChunk)
            } else {
                // Fallback: just add the raw chunk with basic paragraph breaks
                formattedParts.append(chunk)
            }

            currentIndex = chunkEnd
            chunkNumber += 1
        }

        return formattedParts.isEmpty ? nil : formattedParts.joined(separator: "\n\n")
    }

    /// Format a single chunk of transcript - preserves ALL words
    private func formatTranscriptChunk(text: String, title: String, isFirstChunk: Bool) async -> String? {
        let prompt = """
        FORMAT this transcript section into readable markdown.

        CRITICAL RULES - YOU MUST FOLLOW THESE:
        1. PRESERVE EVERY SINGLE WORD from the input - do NOT summarize or skip content
        2. Keep the EXACT same tone, language, and depth as the original
        3. You may only change words minimally for grammar/readability (e.g., "gonna" → "going to")
        4. This is NOT a summary - it's a reformatted version of the COMPLETE transcript

        FORMATTING TO ADD:
        - Add ## headings when the topic clearly changes (identify topic shifts naturally)
        - Add ### subheadings for subtopics within a section
        - Break into readable paragraphs (4-6 sentences each)
        - Use **bold** for key terms or important concepts mentioned
        - Use > blockquotes for notable quotes or memorable statements
        - Use bullet points only if the speaker is listing multiple items

        \(isFirstChunk ? "Video Title: \(title)\n" : "")
        TRANSCRIPT TO FORMAT (output ALL of this content, reformatted):
        \(text)

        FORMATTED MARKDOWN (preserve all content):
        """

        let result = await LocalLLM.shared.generate(prompt: prompt, maxTokens: 4000)
        return result.isEmpty ? nil : result
    }

    /// Generate section breakdown for navigation (separate from full transcript)
    private func generateSectionBreakdown(segments: [TranscriptSegment], title: String) async -> [TranscriptSectionData]? {
        let fullText = segments.map { $0.text }.joined(separator: " ")

        // Use a sample for section detection (first portion is usually enough to identify structure)
        let sampleText = String(fullText.prefix(8000))

        let sectionsPrompt = """
        Analyze this video transcript and identify 3-7 main sections/chapters. For each section provide:
        - A clear title (2-5 words)
        - A one-sentence summary

        Format your response as JSON array:
        [{"title": "Section Title", "summary": "Brief summary of this section"}]

        Video Title: \(title)

        Transcript:
        \(sampleText)

        JSON Response:
        """

        let jsonResponse = await LocalLLM.shared.generate(prompt: sectionsPrompt, maxTokens: 500)
        if !jsonResponse.isEmpty {
            return parseSectionsFromJSON(jsonResponse, segments: segments)
        }
        return nil
    }
    
    /// Parse AI-generated section JSON and map to timestamps
    private func parseSectionsFromJSON(_ json: String, segments: [TranscriptSegment]) -> [TranscriptSectionData]? {
        // Extract JSON array from response (in case there's extra text)
        guard let jsonStart = json.firstIndex(of: "["),
              let jsonEnd = json.lastIndex(of: "]") else {
            return nil
        }
        
        let jsonString = String(json[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        struct SectionJSON: Codable {
            let title: String
            let summary: String?
        }
        
        guard let parsed = try? JSONDecoder().decode([SectionJSON].self, from: data) else {
            return nil
        }
        
        // Map sections to estimated timestamps based on position
        let totalDuration = segments.last?.end ?? 0
        let sectionDuration = totalDuration / Double(parsed.count)
        
        return parsed.enumerated().map { index, section in
            TranscriptSectionData(
                title: section.title,
                startTime: Double(index) * sectionDuration,
                endTime: Double(index + 1) * sectionDuration,
                summary: section.summary
            )
        }
    }
}

// MARK: - Supporting Types
struct YouTubeMetadata {
    let title: String
    let channelName: String?
    let description: String?
    let duration: Int?
    let publishedAt: String?
}

enum YouTubeProcessingStep {
    case fetchingMetadata
    case fetchingCaptions      // Fast path - < 2 seconds
    case downloadingAudio      // Slow path fallback
    case transcribing          // Slow path fallback
    case summarizing
    case formattingTranscript
    case complete

    var description: String {
        switch self {
        case .fetchingMetadata: return "Fetching video info..."
        case .fetchingCaptions: return "Fetching captions..."
        case .downloadingAudio: return "Downloading audio..."
        case .transcribing: return "Transcribing..."
        case .summarizing: return "Generating summary..."
        case .formattingTranscript: return "Formatting transcript..."
        case .complete: return "Complete"
        }
    }

    var progress: Double {
        switch self {
        case .fetchingMetadata: return 0.1
        case .fetchingCaptions: return 0.3
        case .downloadingAudio: return 0.35
        case .transcribing: return 0.5
        case .summarizing: return 0.75
        case .formattingTranscript: return 0.9
        case .complete: return 1.0
        }
    }
}

enum YouTubeError: LocalizedError {
    case metadataFetchFailed
    case ytDlpNotInstalled
    case downloadFailed(String)
    case speechNotAuthorized
    case speechNotAvailable
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .metadataFetchFailed:
            return "Failed to fetch video metadata"
        case .ytDlpNotInstalled:
            return "yt-dlp is required for YouTube download. Install with: brew install yt-dlp"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .speechNotAuthorized:
            return "Speech recognition not authorized"
        case .speechNotAvailable:
            return "Speech recognition not available"
        case .transcriptionFailed:
            return "Failed to transcribe audio"
        }
    }
}

// MARK: - Transcript Helpers
extension Array where Element == TranscriptSegment {
    /// Get full transcript text
    var fullText: String {
        map { $0.text }.joined(separator: " ")
    }

    /// Encode to JSON string
    var jsonString: String? {
        do {
            let data = try JSONEncoder().encode(self)
            let json = String(data: data, encoding: .utf8)
            print("📝 Encoded \(self.count) transcript segments to JSON (\(data.count) bytes)")
            return json
        } catch {
            print("❌ Failed to encode transcript segments: \(error)")
            return nil
        }
    }
}
