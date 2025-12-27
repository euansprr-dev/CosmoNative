// CosmoOS/Voice/TieredASR/L1StreamingASR.swift
// L1 Streaming ASR using Qwen3-ASR-Flash for instant intent detection
// Ultra-fast ~30ms chunk latency, ~92% accuracy (good enough for intent)
// macOS 26+ optimized

import Foundation
import AVFoundation

// Note: L1TranscriptChunk is defined in Shared/VoiceTypes.swift
// to allow sharing between main app and XPC daemon

// MARK: - L1 ASR Configuration

public struct L1ASRConfig: Sendable {
    public let sampleRate: Double
    public let channelCount: Int
    public let chunkDuration: Duration
    public let minConfidenceForFinal: Double
    public let vadThresholdDB: Float
    public let vadSilenceDuration: Duration

    public static let `default` = L1ASRConfig(
        sampleRate: 16000,
        channelCount: 1,
        chunkDuration: .milliseconds(30),
        minConfidenceForFinal: 0.85,
        vadThresholdDB: -40,
        vadSilenceDuration: .milliseconds(500)
    )

    public init(
        sampleRate: Double = 16000,
        channelCount: Int = 1,
        chunkDuration: Duration = .milliseconds(30),
        minConfidenceForFinal: Double = 0.85,
        vadThresholdDB: Float = -40,
        vadSilenceDuration: Duration = .milliseconds(500)
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.chunkDuration = chunkDuration
        self.minConfidenceForFinal = minConfidenceForFinal
        self.vadThresholdDB = vadThresholdDB
        self.vadSilenceDuration = vadSilenceDuration
    }
}

// MARK: - L1 Streaming ASR Actor

public actor L1StreamingASR {
    // MARK: - Dependencies

    // Access DaemonXPCClient.shared via MainActor.run when needed
    private let config: L1ASRConfig

    // MARK: - State

    private var isStreaming = false
    private var startTime: Date?
    private var accumulatedText = ""
    private var lastChunkTime: Date?
    private var silenceStartTime: Date?
    private var audioBuffer: [Float] = []

    // MARK: - Callbacks

    private var onChunk: (@Sendable (L1TranscriptChunk) -> Void)?
    private var onSpeechStart: (@Sendable () -> Void)?
    private var onSpeechEnd: (@Sendable () -> Void)?

    // MARK: - Initialization

    public init(config: L1ASRConfig = .default) {
        self.config = config
    }

    // MARK: - Streaming Control

    /// Start L1 streaming ASR
    public func startStreaming(
        onChunk: @escaping @Sendable (L1TranscriptChunk) -> Void,
        onSpeechStart: @escaping @Sendable () -> Void = {},
        onSpeechEnd: @escaping @Sendable () -> Void = {}
    ) async throws {
        print("🟡 L1StreamingASR.startStreaming() CALLED - isStreaming: \(isStreaming)")

        guard !isStreaming else {
            print("🟡 L1StreamingASR: Already streaming, throwing error")
            throw L1ASRError.alreadyStreaming
        }

        self.onChunk = onChunk
        self.onSpeechStart = onSpeechStart
        self.onSpeechEnd = onSpeechEnd

        isStreaming = true
        startTime = Date()
        accumulatedText = ""
        audioBuffer = []

        // Prepare audio format data for daemon
        let formatData = try encodeAudioFormat()

        // Start streaming via daemon XPC
        let client = await MainActor.run { DaemonXPCClient.shared }
        try await client.startL1ASRStream(
            audioFormat: formatData,
            onChunk: { [weak self] chunk in
                Task {
                    await self?.handleDaemonChunk(chunk)
                }
            }
        )

        print("L1StreamingASR: Started streaming (config: \(config.sampleRate)Hz)")
    }

    /// Send audio samples to L1 ASR
    public func sendAudio(_ samples: [Float]) async throws {
        guard isStreaming else {
            throw L1ASRError.notStreaming
        }

        // Append to buffer for L2 escalation if needed
        audioBuffer.append(contentsOf: samples)

        // Check audio level for VAD
        let level = calculateAudioLevel(samples)
        await handleVAD(level: level)

        // Send to daemon
        let data = try encodeSamples(samples)
        let client = await MainActor.run { DaemonXPCClient.shared }
        try await client.sendAudioChunk(samples: data)

        lastChunkTime = Date()
    }

    /// Stop L1 streaming and get final transcript
    public func stopStreaming() async throws -> L1FinalResult {
        guard isStreaming else {
            throw L1ASRError.notStreaming
        }

        defer {
            isStreaming = false
            onChunk = nil
            onSpeechStart = nil
            onSpeechEnd = nil
            startTime = nil
            audioBuffer = []
        }

        // Get final transcript from daemon
        let client = await MainActor.run { DaemonXPCClient.shared }
        let finalText = try await client.stopL1ASRStream()

        let duration = Date().timeIntervalSince(startTime ?? Date())

        print("L1StreamingASR: Stopped streaming (duration: \(String(format: "%.1f", duration))s)")

        return L1FinalResult(
            text: finalText.isEmpty ? accumulatedText : finalText,
            duration: duration,
            audioBuffer: audioBuffer,
            averageConfidence: 0.9 // Daemon should provide this
        )
    }

    /// Cancel streaming without getting final result
    public func cancelStreaming() async {
        guard isStreaming else { return }

        isStreaming = false
        onChunk = nil
        onSpeechStart = nil
        onSpeechEnd = nil
        startTime = nil
        audioBuffer = []

        let client = await MainActor.run { DaemonXPCClient.shared }
        _ = try? await client.stopL1ASRStream()

        print("L1StreamingASR: Streaming cancelled")
    }

    // MARK: - State Queries

    public func getIsStreaming() -> Bool {
        isStreaming
    }

    public func getAudioBuffer() -> [Float] {
        audioBuffer
    }

    public func getStreamDuration() -> TimeInterval? {
        guard let start = startTime else { return nil }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Private Helpers

    private func handleDaemonChunk(_ chunk: L1TranscriptChunk) async {
        // Accumulate text
        if chunk.isFinal {
            accumulatedText = chunk.text
        }

        // Forward to callback (Sendable, can call directly)
        onChunk?(chunk)

        // Post notification for speculative UI
        if chunk.isIntentReady {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .l1PartialTranscript,
                    object: nil,
                    userInfo: [
                        "text": chunk.text,
                        "confidence": chunk.confidence,
                        "wordCount": chunk.wordCount
                    ]
                )
            }
        }
    }

    private func handleVAD(level: Float) async {
        let isVoice = level > config.vadThresholdDB

        if isVoice {
            // Voice detected
            if silenceStartTime != nil {
                // Resume from silence
                silenceStartTime = nil
            }
        } else {
            // Silence detected
            if silenceStartTime == nil {
                silenceStartTime = Date()
            } else if Date().timeIntervalSince(silenceStartTime!) >= config.vadSilenceDuration.seconds {
                // Silence exceeded threshold - end of speech (Sendable, can call directly)
                onSpeechEnd?()
            }
        }
    }

    private func calculateAudioLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -100 }

        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))

        // Convert to dB
        if rms > 0 {
            return 20 * log10(rms)
        }
        return -100
    }

    private func encodeAudioFormat() throws -> Data {
        let format: [String: Any] = [
            "sampleRate": config.sampleRate,
            "channelCount": config.channelCount,
            "bitsPerSample": 32,
            "isFloat": true
        ]
        return try JSONSerialization.data(withJSONObject: format)
    }

    private func encodeSamples(_ samples: [Float]) throws -> Data {
        var mutableSamples = samples
        return Data(bytes: &mutableSamples, count: samples.count * MemoryLayout<Float>.size)
    }
}

// MARK: - L1 Final Result

public struct L1FinalResult: Sendable {
    public let text: String
    public let duration: TimeInterval
    public let audioBuffer: [Float]
    public let averageConfidence: Double

    /// Check if L2 escalation is needed
    public var needsL2Escalation: Bool {
        averageConfidence < 0.85 || duration > 30
    }

    /// Convert audio buffer to Data for L2
    public func getAudioData() -> Data {
        var mutableBuffer = audioBuffer
        return Data(bytes: &mutableBuffer, count: audioBuffer.count * MemoryLayout<Float>.size)
    }
}

// MARK: - Errors

public enum L1ASRError: LocalizedError {
    case alreadyStreaming
    case notStreaming
    case daemonNotConnected
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .alreadyStreaming:
            return "L1 ASR is already streaming"
        case .notStreaming:
            return "L1 ASR is not streaming"
        case .daemonNotConnected:
            return "Daemon not connected"
        case .encodingFailed:
            return "Failed to encode audio data"
        }
    }
}

// MARK: - Notification Names
// Note: l1PartialTranscript and l1FinalTranscript are in Shared/VoiceTypes.swift

extension Notification.Name {
    static let l1SpeechStarted = Notification.Name("com.cosmo.l1SpeechStarted")
    static let l1SpeechEnded = Notification.Name("com.cosmo.l1SpeechEnded")
}

// MARK: - Duration Extension

extension Duration {
    var seconds: TimeInterval {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

// MARK: - AsyncStream Helper

extension L1StreamingASR {
    /// Get an AsyncStream of transcript chunks
    public func stream() -> AsyncStream<L1TranscriptChunk> {
        AsyncStream { continuation in
            Task {
                do {
                    try await startStreaming(
                        onChunk: { chunk in
                            continuation.yield(chunk)
                            if chunk.isFinal {
                                continuation.finish()
                            }
                        },
                        onSpeechEnd: {
                            continuation.finish()
                        }
                    )
                } catch {
                    continuation.finish()
                }
            }
        }
    }
}
