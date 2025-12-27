// CosmoOS/Voice/TieredASR/L2WhisperASR.swift
// L2 High-Accuracy ASR using Whisper Large v3 for dictation and low-confidence recovery
// On-demand lazy loading to save ~1.5GB RAM when not in use
// macOS 26+ optimized

import Foundation

// MARK: - Whisper Result

public struct WhisperResult: Codable, Sendable {
    public let text: String
    public let segments: [WhisperTranscriptSegment]
    public let language: String
    public let duration: TimeInterval
    public let processingTime: TimeInterval

    public init(
        text: String,
        segments: [WhisperTranscriptSegment],
        language: String,
        duration: TimeInterval,
        processingTime: TimeInterval
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.duration = duration
        self.processingTime = processingTime
    }

    /// Real-time factor (lower is faster)
    public var realtimeFactor: Double {
        guard duration > 0 else { return 0 }
        return processingTime / duration
    }
}

// MARK: - Whisper Transcript Segment

public struct WhisperTranscriptSegment: Codable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double
    public let words: [WordTimestamp]?

    public init(
        id: UUID = UUID(),
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        confidence: Double,
        words: [WordTimestamp]? = nil
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
        self.words = words
    }

    public var duration: TimeInterval {
        end - start
    }
}

// MARK: - Word Timestamp

public struct WordTimestamp: Codable, Sendable {
    public let word: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double

    public init(word: String, start: TimeInterval, end: TimeInterval, confidence: Double) {
        self.word = word
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

// MARK: - L2 Whisper Configuration

public struct L2WhisperConfig: Sendable {
    public let model: WhisperModel
    public let language: String?
    public let task: TranscriptionTask
    public let wordTimestamps: Bool
    public let vadFilter: Bool
    public let temperatureFallback: Bool

    public static let `default` = L2WhisperConfig(
        model: .largev3,
        language: nil,  // Auto-detect
        task: .transcribe,
        wordTimestamps: true,
        vadFilter: true,
        temperatureFallback: true
    )

    public static let dictation = L2WhisperConfig(
        model: .largev3,
        language: "en",
        task: .transcribe,
        wordTimestamps: false,  // Faster for dictation
        vadFilter: false,
        temperatureFallback: false
    )

    public init(
        model: WhisperModel = .largev3,
        language: String? = nil,
        task: TranscriptionTask = .transcribe,
        wordTimestamps: Bool = true,
        vadFilter: Bool = true,
        temperatureFallback: Bool = true
    ) {
        self.model = model
        self.language = language
        self.task = task
        self.wordTimestamps = wordTimestamps
        self.vadFilter = vadFilter
        self.temperatureFallback = temperatureFallback
    }

    public enum WhisperModel: String, Codable, Sendable {
        case tiny = "tiny"
        case base = "base"
        case small = "small"
        case medium = "medium"
        case large = "large"
        case largev2 = "large-v2"
        case largev3 = "large-v3"

        public var approximateRAM: Int64 {
            switch self {
            case .tiny: return 75
            case .base: return 150
            case .small: return 500
            case .medium: return 1500
            case .large, .largev2, .largev3: return 3000
            }
        }
    }

    public enum TranscriptionTask: String, Codable, Sendable {
        case transcribe
        case translate
    }
}

// MARK: - L2 Whisper ASR Actor

public actor L2WhisperASR {
    // MARK: - Dependencies

    // Note: Access DaemonXPCClient.shared and SafetyMonitor.shared via MainActor.run when needed
    private let config: L2WhisperConfig

    // MARK: - State

    private var isLoaded = false
    private var isTranscribing = false
    private var loadTime: Date?

    // MARK: - Statistics

    private var totalTranscriptions = 0
    private var totalProcessingTime: TimeInterval = 0
    private var totalAudioDuration: TimeInterval = 0

    // MARK: - Initialization

    public init(config: L2WhisperConfig = .default) {
        self.config = config
    }

    /// Access SafetyMonitor from MainActor
    private func getSafetyMonitor() async -> SafetyMonitor {
        await MainActor.run { SafetyMonitor.shared }
    }

    // MARK: - Model Management

    /// Check if L2 Whisper is loaded in daemon
    public func checkLoaded() async -> Bool {
        let client = await MainActor.run { DaemonXPCClient.shared }
        isLoaded = await client.isL2Loaded()
        return isLoaded
    }

    /// Pre-load L2 Whisper for dictation mode
    public func ensureLoaded() async throws {
        if await checkLoaded() {
            return
        }

        // Check RAM before loading
        let monitor = await getSafetyMonitor()
        let canAllocate = await monitor.canAllocate(mb: 1500)
        guard canAllocate else {
            throw L2ASRError.insufficientMemory
        }

        // Request daemon to load Whisper
        let client = await MainActor.run { DaemonXPCClient.shared }
        try await client.preloadL2()
        isLoaded = true
        loadTime = Date()

        print("L2WhisperASR: Model loaded (~1.5GB)")

        // Post notification
        await MainActor.run {
            NotificationCenter.default.post(name: .l2ModelLoaded, object: nil)
        }
    }

    /// Unload L2 Whisper to free ~1.5GB RAM
    public func unload() async {
        guard isLoaded else { return }

        let client = await MainActor.run { DaemonXPCClient.shared }
        await client.unloadWhisperL2()
        isLoaded = false
        loadTime = nil

        print("L2WhisperASR: Model unloaded (freed ~1.5GB)")

        // Post notification
        await MainActor.run {
            NotificationCenter.default.post(name: .l2ModelUnloaded, object: nil)
        }
    }

    // MARK: - Transcription

    /// Transcribe audio with high accuracy
    public func transcribe(
        audioSamples: Data,
        language: String? = nil,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> WhisperResult {
        guard !isTranscribing else {
            throw L2ASRError.alreadyTranscribing
        }

        // Ensure model is loaded
        try await ensureLoaded()

        isTranscribing = true
        defer { isTranscribing = false }

        let startTime = Date()

        // Send to daemon for transcription
        let client = await MainActor.run { DaemonXPCClient.shared }
        let result = try await client.transcribeL2(
            audioSamples: audioSamples,
            language: language ?? config.language
        )

        let processingTime = Date().timeIntervalSince(startTime)

        // Update statistics
        totalTranscriptions += 1
        totalProcessingTime += processingTime
        totalAudioDuration += result.duration

        print("L2WhisperASR: Transcribed \(String(format: "%.1f", result.duration))s in \(String(format: "%.1f", processingTime))s (RTF: \(String(format: "%.2f", result.realtimeFactor)))")

        return result
    }

    /// Transcribe with L1 result for comparison/merging
    public func transcribeWithL1Comparison(
        audioSamples: Data,
        l1Result: L1FinalResult,
        language: String? = nil
    ) async throws -> MergedTranscriptResult {
        let l2Result = try await transcribe(audioSamples: audioSamples, language: language)

        // Compare results
        let similarity = calculateSimilarity(l1: l1Result.text, l2: l2Result.text)

        // Determine which to use
        let finalText: String
        let source: MergedTranscriptResult.TranscriptSource

        if similarity > 0.9 {
            // High similarity - L1 was good enough
            finalText = l1Result.text
            source = .l1Confirmed
        } else if l2Result.segments.allSatisfy({ $0.confidence > 0.9 }) {
            // L2 is high confidence - use it
            finalText = l2Result.text
            source = .l2Override
        } else {
            // Mixed - prefer L2 but note uncertainty
            finalText = l2Result.text
            source = .l2Uncertain
        }

        return MergedTranscriptResult(
            finalText: finalText,
            l1Result: l1Result,
            l2Result: l2Result,
            similarity: similarity,
            source: source
        )
    }

    /// Batch transcribe for long dictation sessions (1h+)
    public func transcribeLongSession(
        audioChunks: [Data],
        chunkDuration: TimeInterval = 30,
        onChunkComplete: @escaping @Sendable (Int, WhisperResult) async -> Void
    ) async throws -> WhisperResult {
        guard !isTranscribing else {
            throw L2ASRError.alreadyTranscribing
        }

        try await ensureLoaded()

        isTranscribing = true
        defer { isTranscribing = false }

        var allSegments: [WhisperTranscriptSegment] = []
        var fullText = ""
        var totalDuration: TimeInterval = 0
        let startTime = Date()

        for (index, chunk) in audioChunks.enumerated() {
            let chunkClient = await MainActor.run { DaemonXPCClient.shared }
            let result = try await chunkClient.transcribeL2(audioSamples: chunk, language: config.language)

            // Adjust segment timestamps
            let adjustedSegments = result.segments.map { segment in
                WhisperTranscriptSegment(
                    id: segment.id,
                    text: segment.text,
                    start: segment.start + totalDuration,
                    end: segment.end + totalDuration,
                    confidence: segment.confidence,
                    words: segment.words
                )
            }

            allSegments.append(contentsOf: adjustedSegments)
            fullText += result.text + " "
            totalDuration += result.duration

            // Report progress
            await onChunkComplete(index, result)

            // Post progress notification
            let progress = Double(index + 1) / Double(audioChunks.count)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .l2TranscriptionProgress,
                    object: nil,
                    userInfo: ["progress": progress, "chunkIndex": index]
                )
            }
        }

        let processingTime = Date().timeIntervalSince(startTime)

        return WhisperResult(
            text: fullText.trimmingCharacters(in: .whitespaces),
            segments: allSegments,
            language: config.language ?? "en",
            duration: totalDuration,
            processingTime: processingTime
        )
    }

    // MARK: - Statistics

    public struct Statistics: Sendable {
        public let totalTranscriptions: Int
        public let totalProcessingTime: TimeInterval
        public let totalAudioDuration: TimeInterval
        public let averageRTF: Double
        public let isLoaded: Bool
        public let loadTime: Date?
    }

    public func getStatistics() -> Statistics {
        let averageRTF = totalAudioDuration > 0 ? totalProcessingTime / totalAudioDuration : 0

        return Statistics(
            totalTranscriptions: totalTranscriptions,
            totalProcessingTime: totalProcessingTime,
            totalAudioDuration: totalAudioDuration,
            averageRTF: averageRTF,
            isLoaded: isLoaded,
            loadTime: loadTime
        )
    }

    // MARK: - Private Helpers

    private func calculateSimilarity(l1: String, l2: String) -> Double {
        let l1Words = Set(l1.lowercased().split(separator: " ").map(String.init))
        let l2Words = Set(l2.lowercased().split(separator: " ").map(String.init))

        guard !l1Words.isEmpty || !l2Words.isEmpty else { return 1.0 }

        let intersection = l1Words.intersection(l2Words).count
        let union = l1Words.union(l2Words).count

        return Double(intersection) / Double(union)
    }
}

// MARK: - Merged Transcript Result

public struct MergedTranscriptResult: Sendable {
    public let finalText: String
    public let l1Result: L1FinalResult
    public let l2Result: WhisperResult
    public let similarity: Double
    public let source: TranscriptSource

    public enum TranscriptSource: Sendable {
        case l1Confirmed      // L1 was correct, L2 confirmed
        case l2Override       // L2 was better, high confidence
        case l2Uncertain      // L2 used but with some uncertainty
    }
}

// MARK: - Errors

public enum L2ASRError: LocalizedError {
    case insufficientMemory
    case alreadyTranscribing
    case modelNotLoaded
    case transcriptionFailed(String)
    case invalidAudioFormat

    public var errorDescription: String? {
        switch self {
        case .insufficientMemory:
            return "Insufficient memory to load Whisper L2 (~1.5GB required)"
        case .alreadyTranscribing:
            return "L2 ASR is already transcribing"
        case .modelNotLoaded:
            return "Whisper model not loaded"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .invalidAudioFormat:
            return "Invalid audio format"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let l2ModelLoaded = Notification.Name("com.cosmo.l2ModelLoaded")
    static let l2ModelUnloaded = Notification.Name("com.cosmo.l2ModelUnloaded")
    static let l2TranscriptionProgress = Notification.Name("com.cosmo.l2TranscriptionProgress")
    static let l2TranscriptionComplete = Notification.Name("com.cosmo.l2TranscriptionComplete")
}

// MARK: - Auto-Unload Extension

extension L2WhisperASR {
    /// Auto-unload after idle period to save RAM
    public func startIdleUnloadTimer(idleTimeout: Duration = .minutes(5)) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: idleTimeout)
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }
}

// MARK: - Duration Extension

extension Duration {
    public static func minutes(_ minutes: Int) -> Duration {
        .seconds(minutes * 60)
    }
}
