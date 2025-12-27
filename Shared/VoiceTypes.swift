// CosmoOS/Shared/VoiceTypes.swift
// Shared types for voice/ASR used by both main app and XPC daemon
// Keep this minimal to avoid circular dependencies

import Foundation

// MARK: - L1 Transcript Chunk (Streaming ASR Result)

/// Chunk of streaming transcript from L1 ASR (WhisperKit base model)
/// Used by both the daemon (produces) and app (consumes)
public struct L1TranscriptChunk: Codable, Sendable {
    public let text: String
    public let isFinal: Bool
    public let confidence: Double
    public let timestamp: TimeInterval
    public let wordCount: Int
    public let audioLevelDB: Float?

    public init(
        text: String,
        isFinal: Bool,
        confidence: Double,
        timestamp: TimeInterval,
        audioLevelDB: Float? = nil
    ) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.timestamp = timestamp
        self.wordCount = text.split(separator: " ").count
        self.audioLevelDB = audioLevelDB
    }

    /// Check if chunk has enough words for intent detection
    public var isIntentReady: Bool {
        wordCount >= 2
    }

    /// Check if confidence is high enough to skip L2
    public var isHighConfidence: Bool {
        confidence >= 0.85
    }
}

// MARK: - Notification Names for L1 ASR

public extension Notification.Name {
    /// Posted when L1 ASR produces a partial transcript
    static let l1PartialTranscript = Notification.Name("com.cosmo.l1PartialTranscript")

    /// Posted when L1 ASR produces a final transcript
    static let l1FinalTranscript = Notification.Name("com.cosmo.l1FinalTranscript")
}
