// CosmoOS/Voice/TieredASR/ASRCoordinator.swift
// Orchestrates L1 (Qwen3-ASR-Flash) and L2 (Whisper Large v3) ASR systems
// Handles mode switching, confidence-based escalation, and dictation support
// macOS 26+ optimized

import Foundation
import AVFoundation
import Combine

// MARK: - ASR Mode

public enum ASRMode: String, Sendable {
    case quickCommand      // L1 only, <30s, for voice commands
    case dictation         // L1 streaming + L2 batch, for long-form input
    case highAccuracy      // L2 only, for explicit high-accuracy requests
    case hybrid            // L1 with L2 fallback on low confidence
}

// MARK: - ASR State

public enum ASRState: Sendable, Equatable {
    case idle
    case listening
    case processing
    case escalatingToL2
    case transcribing
    case error(String)
}

// MARK: - ASR Coordinator

@MainActor
public final class ASRCoordinator: ObservableObject {
    // MARK: - Published State

    @Published public private(set) var state: ASRState = .idle
    @Published public private(set) var mode: ASRMode = .quickCommand
    @Published public private(set) var isL2Loaded = false
    @Published public private(set) var currentTranscript = ""
    @Published public private(set) var partialTranscript = ""
    @Published public private(set) var confidence: Double = 0
    @Published public private(set) var audioLevel: Float = -60

    // MARK: - Components

    private let l1: L1StreamingASR
    private let l2: L2WhisperASR
    private let safetyMonitor: SafetyMonitor

    // MARK: - Audio Capture

    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var isRecording = false

    // MARK: - Configuration

    private let l2EscalationThreshold: Double = 0.85
    private let quickCommandMaxDuration: TimeInterval = 30
    private let dictationChunkDuration: TimeInterval = 30

    // MARK: - Callbacks

    private var onPartialTranscript: ((String, Double) -> Void)?
    private var onFinalTranscript: ((String) -> Void)?
    private var onIntentDetected: ((String, Int) -> Void)?

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()
    private var l2PreloadTask: Task<Void, Never>?
    private var recordingStartTime: Date?

    // MARK: - Initialization

    public init(
        l1: L1StreamingASR = L1StreamingASR(),
        l2: L2WhisperASR = L2WhisperASR(),
        safetyMonitor: SafetyMonitor? = nil
    ) {
        self.l1 = l1
        self.l2 = l2
        self.safetyMonitor = safetyMonitor ?? SafetyMonitor.shared

        setupNotificationObservers()
    }

    // MARK: - Recording Control

    /// Start recording with specified mode
    public func startRecording(
        mode: ASRMode = .quickCommand,
        onPartial: ((String, Double) -> Void)? = nil,
        onFinal: ((String) -> Void)? = nil,
        onIntent: ((String, Int) -> Void)? = nil
    ) async throws {
        guard state == .idle else {
            throw ASRCoordinatorError.alreadyRecording
        }

        self.mode = mode
        self.onPartialTranscript = onPartial
        self.onFinalTranscript = onFinal
        self.onIntentDetected = onIntent

        state = .listening
        currentTranscript = ""
        partialTranscript = ""
        confidence = 0
        audioBuffer = []
        recordingStartTime = Date()

        // Pre-load L2 in background for dictation mode
        if mode == .dictation || mode == .highAccuracy {
            l2PreloadTask = Task {
                try? await l2.ensureLoaded()
                await MainActor.run {
                    self.isL2Loaded = true
                }
            }
        }

        // Setup audio capture
        try await setupAudioCapture()

        // Start L1 streaming (unless high-accuracy mode)
        if mode != .highAccuracy {
            try await l1.startStreaming(
                onChunk: { [weak self] chunk in
                    Task { @MainActor in
                        await self?.handleL1Chunk(chunk)
                    }
                },
                onSpeechStart: { [weak self] in
                    Task { @MainActor in
                        self?.state = .listening
                    }
                },
                onSpeechEnd: { [weak self] in
                    Task { @MainActor in
                        await self?.handleSpeechEnd()
                    }
                }
            )
        }

        print("ASRCoordinator: Started recording (mode: \(mode))")
    }

    /// Stop recording and get final transcript
    public func stopRecording() async throws -> ASRResult {
        guard state != .idle else {
            throw ASRCoordinatorError.notRecording
        }

        defer {
            cleanup()
        }

        state = .processing

        // Stop audio capture
        stopAudioCapture()

        // Get result based on mode
        let result: ASRResult

        switch mode {
        case .quickCommand:
            result = try await processQuickCommand()

        case .dictation:
            result = try await processDictation()

        case .highAccuracy:
            result = try await processHighAccuracy()

        case .hybrid:
            result = try await processHybrid()
        }

        currentTranscript = result.text
        onFinalTranscript?(result.text)

        state = .idle

        print("ASRCoordinator: Recording stopped (text: \"\(result.text.prefix(50))...\")")

        return result
    }

    /// Cancel recording without processing
    public func cancelRecording() async {
        guard state != .idle else { return }

        await l1.cancelStreaming()
        stopAudioCapture()
        cleanup()

        state = .idle
        print("ASRCoordinator: Recording cancelled")
    }

    /// Detect recording mode from user interaction
    public func detectModeFromInteraction(isLongPress: Bool, duration: TimeInterval) -> ASRMode {
        if isLongPress || duration > 1.0 {
            return .dictation
        }
        return .quickCommand
    }

    // MARK: - Mode Processing

    private func processQuickCommand() async throws -> ASRResult {
        // Stop L1 and get result
        let l1Result = try await l1.stopStreaming()

        // Check if L2 escalation needed
        if l1Result.needsL2Escalation && l1Result.averageConfidence < l2EscalationThreshold {
            state = .escalatingToL2

            // Try L2 if available and RAM permits
            if safetyMonitor.canAllocate(mb: 1500) {
                do {
                    let l2Result = try await l2.transcribe(audioSamples: l1Result.getAudioData())
                    return ASRResult(
                        text: l2Result.text,
                        source: .l2,
                        confidence: l2Result.segments.map(\.confidence).reduce(0, +) / Double(max(1, l2Result.segments.count)),
                        duration: l2Result.duration,
                        segments: l2Result.segments
                    )
                } catch {
                    print("ASRCoordinator: L2 escalation failed, using L1 result: \(error)")
                }
            }
        }

        return ASRResult(
            text: l1Result.text,
            source: .l1,
            confidence: l1Result.averageConfidence,
            duration: l1Result.duration,
            segments: nil
        )
    }

    private func processDictation() async throws -> ASRResult {
        // Stop L1 streaming
        let l1Result = try await l1.stopStreaming()

        // For dictation, always use L2 for final accuracy
        state = .transcribing

        // Wait for L2 to be loaded
        await l2PreloadTask?.value

        // Convert audio buffer to chunks for batch processing
        let chunkSize = Int(dictationChunkDuration * 16000) // samples per chunk
        var audioChunks: [Data] = []

        for i in stride(from: 0, to: audioBuffer.count, by: chunkSize) {
            let endIndex = min(i + chunkSize, audioBuffer.count)
            var chunk = Array(audioBuffer[i..<endIndex])
            let data = Data(bytes: &chunk, count: chunk.count * MemoryLayout<Float>.size)
            audioChunks.append(data)
        }

        if audioChunks.isEmpty {
            // Short recording - use L1 result
            return ASRResult(
                text: l1Result.text,
                source: .l1,
                confidence: l1Result.averageConfidence,
                duration: l1Result.duration,
                segments: nil
            )
        }

        // Batch transcribe with L2
        let l2Result = try await l2.transcribeLongSession(
            audioChunks: audioChunks,
            chunkDuration: dictationChunkDuration
        ) { [weak self] index, chunkResult in
            guard let coordinator = self else { return }
            await MainActor.run {
                // Update progress
                let progress = Double(index + 1) / Double(audioChunks.count)
                coordinator.partialTranscript = chunkResult.text
                NotificationCenter.default.post(
                    name: .dictationProgress,
                    object: nil,
                    userInfo: ["progress": progress]
                )
            }
        }

        // Unload L2 after dictation to free RAM
        await l2.unload()
        isL2Loaded = false

        return ASRResult(
            text: l2Result.text,
            source: .l2,
            confidence: l2Result.segments.map(\.confidence).reduce(0, +) / Double(max(1, l2Result.segments.count)),
            duration: l2Result.duration,
            segments: l2Result.segments
        )
    }

    private func processHighAccuracy() async throws -> ASRResult {
        state = .transcribing

        // Wait for L2 to be loaded
        await l2PreloadTask?.value

        // Convert full audio buffer
        var buffer = audioBuffer
        let audioData = Data(bytes: &buffer, count: buffer.count * MemoryLayout<Float>.size)

        let l2Result = try await l2.transcribe(audioSamples: audioData)

        return ASRResult(
            text: l2Result.text,
            source: .l2,
            confidence: l2Result.segments.map(\.confidence).reduce(0, +) / Double(max(1, l2Result.segments.count)),
            duration: l2Result.duration,
            segments: l2Result.segments
        )
    }

    private func processHybrid() async throws -> ASRResult {
        // Get L1 result
        let l1Result = try await l1.stopStreaming()

        // Decide whether to escalate based on confidence
        if l1Result.averageConfidence >= l2EscalationThreshold {
            return ASRResult(
                text: l1Result.text,
                source: .l1,
                confidence: l1Result.averageConfidence,
                duration: l1Result.duration,
                segments: nil
            )
        }

        // Escalate to L2
        state = .escalatingToL2

        if safetyMonitor.canAllocate(mb: 1500) {
            do {
                let mergedResult = try await l2.transcribeWithL1Comparison(
                    audioSamples: l1Result.getAudioData(),
                    l1Result: l1Result
                )

                let source: ASRSource = mergedResult.source == .l1Confirmed ? .l1 : .l2

                return ASRResult(
                    text: mergedResult.finalText,
                    source: source,
                    confidence: mergedResult.l2Result.segments.map(\.confidence).reduce(0, +) / Double(max(1, mergedResult.l2Result.segments.count)),
                    duration: mergedResult.l2Result.duration,
                    segments: mergedResult.l2Result.segments
                )
            } catch {
                print("ASRCoordinator: L2 escalation failed: \(error)")
            }
        }

        // Fallback to L1
        return ASRResult(
            text: l1Result.text,
            source: .l1,
            confidence: l1Result.averageConfidence,
            duration: l1Result.duration,
            segments: nil
        )
    }

    // MARK: - L1 Chunk Handling

    private func handleL1Chunk(_ chunk: L1TranscriptChunk) async {
        partialTranscript = chunk.text
        confidence = chunk.confidence

        if let level = chunk.audioLevelDB {
            audioLevel = level
        }

        // Fire partial callback
        onPartialTranscript?(chunk.text, chunk.confidence)

        // Fire intent detection for speculative UI
        if chunk.isIntentReady {
            onIntentDetected?(chunk.text, chunk.wordCount)

            // Post notification for LiveFlashController
            NotificationCenter.default.post(
                name: .asrIntentDetected,
                object: nil,
                userInfo: [
                    "text": chunk.text,
                    "wordCount": chunk.wordCount,
                    "confidence": chunk.confidence
                ]
            )
        }

        // Check for auto-escalation in hybrid mode
        if mode == .hybrid && chunk.isFinal && !chunk.isHighConfidence {
            // Will escalate when stopRecording is called
        }
    }

    private func handleSpeechEnd() async {
        // Auto-stop for quick commands when speech ends
        if mode == .quickCommand {
            Task {
                _ = try? await stopRecording()
            }
        }
    }

    // MARK: - Audio Capture

    private func setupAudioCapture() async throws {
        audioEngine = AVAudioEngine()

        guard let engine = audioEngine else {
            throw ASRCoordinatorError.audioEngineSetupFailed
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Target format for mono 16kHz (used by WhisperKit)
        _ = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        // Install tap for audio capture
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Convert and process audio
            Task {
                await self.processAudioBuffer(buffer)
            }
        }

        try engine.start()
        isRecording = true

        print("ASRCoordinator: Audio capture started (\(format.sampleRate)Hz, \(format.channelCount) channels)")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Resample to 16kHz if needed
        let resampledSamples = resampleTo16kHz(samples, fromRate: buffer.format.sampleRate)

        // Append to buffer
        audioBuffer.append(contentsOf: resampledSamples)

        // Send to L1 ASR
        if mode != .highAccuracy {
            try? await l1.sendAudio(resampledSamples)
        }

        // Calculate audio level
        let level = calculateAudioLevel(resampledSamples)
        await MainActor.run {
            self.audioLevel = level
        }
    }

    private func resampleTo16kHz(_ samples: [Float], fromRate: Double) -> [Float] {
        guard fromRate != 16000 else { return samples }

        let ratio = 16000 / fromRate
        let newLength = Int(Double(samples.count) * ratio)
        var resampled = [Float](repeating: 0, count: newLength)

        for i in 0..<newLength {
            let srcIndex = Double(i) / ratio
            let srcIndexFloor = Int(srcIndex)
            let srcIndexCeil = min(srcIndexFloor + 1, samples.count - 1)
            let t = Float(srcIndex - Double(srcIndexFloor))

            resampled[i] = samples[srcIndexFloor] * (1 - t) + samples[srcIndexCeil] * t
        }

        return resampled
    }

    private func calculateAudioLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -100 }

        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))

        if rms > 0 {
            return 20 * log10(rms)
        }
        return -100
    }

    private func stopAudioCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
    }

    // MARK: - Cleanup

    private func cleanup() {
        stopAudioCapture()
        l2PreloadTask?.cancel()
        l2PreloadTask = nil
        onPartialTranscript = nil
        onFinalTranscript = nil
        onIntentDetected = nil
        recordingStartTime = nil
        audioBuffer = []
    }

    // MARK: - Observers

    private func setupNotificationObservers() {
        // Listen for memory pressure
        NotificationCenter.default.publisher(for: .emergencyMemoryUnload)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    // Cancel any ongoing L2 operations
                    await self?.l2.unload()
                    self?.isL2Loaded = false
                }
            }
            .store(in: &cancellables)
    }

    // Note: Cleanup happens automatically when the coordinator is deallocated
    // The deinit was removed because MainActor methods can't be called from nonisolated deinit
}

// MARK: - ASR Result

public struct ASRResult: Sendable {
    public let text: String
    public let source: ASRSource
    public let confidence: Double
    public let duration: TimeInterval
    public let segments: [WhisperTranscriptSegment]?

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum ASRSource: String, Sendable {
    case l1 = "L1-Qwen3"
    case l2 = "L2-Whisper"
}

// MARK: - Errors

public enum ASRCoordinatorError: LocalizedError {
    case alreadyRecording
    case notRecording
    case audioEngineSetupFailed
    case transcriptionFailed

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Already recording"
        case .notRecording:
            return "Not currently recording"
        case .audioEngineSetupFailed:
            return "Failed to setup audio engine"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let asrIntentDetected = Notification.Name("com.cosmo.asrIntentDetected")
    static let dictationProgress = Notification.Name("com.cosmo.dictationProgress")
    static let dictationCommit = Notification.Name("com.cosmo.dictationCommit")
    static let dictationPreview = Notification.Name("com.cosmo.dictationPreview")
}

// MARK: - State Helpers

extension ASRState {
    public var isActive: Bool {
        switch self {
        case .idle, .error:
            return false
        default:
            return true
        }
    }
}
