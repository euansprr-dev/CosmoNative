// CosmoOS/Agent/Bridges/WhisperTranscriptionService.swift
// Voice-to-text via OpenAI Whisper API

import Foundation

enum AudioFormat: String, Sendable {
    case ogg = "ogg"
    case m4a = "m4a"
    case wav = "wav"
    case mp3 = "mp3"

    var mimeType: String {
        switch self {
        case .ogg: return "audio/ogg"
        case .m4a: return "audio/m4a"
        case .wav: return "audio/wav"
        case .mp3: return "audio/mpeg"
        }
    }

    var fileExtension: String { rawValue }
}

enum TranscriptionError: Error, LocalizedError {
    case noAPIKey
    case transcriptionFailed(String)
    case networkError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Whisper API key not configured"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .invalidResponse: return "Invalid response from Whisper API"
        }
    }
}

public struct WhisperVerboseSegment: Codable, Sendable, Equatable {
    public let id: Int?
    public let start: Double
    public let end: Double
    public let text: String
    public let avgLogprob: Double?
    public let compressionRatio: Double?
    public let noSpeechProb: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case text
        case avgLogprob = "avg_logprob"
        case compressionRatio = "compression_ratio"
        case noSpeechProb = "no_speech_prob"
    }

    public var confidence: Double? {
        guard let avgLogprob else { return nil }
        return max(0, min(1, exp(avgLogprob)))
    }
}

public struct WhisperVerboseTranscription: Codable, Sendable, Equatable {
    public let text: String
    public let language: String?
    public let duration: Double?
    public let segments: [WhisperVerboseSegment]
}

@MainActor
class WhisperTranscriptionService {
    static let shared = WhisperTranscriptionService()

    private let whisperURL = "https://api.openai.com/v1/audio/transcriptions"

    private var apiKey: String? { APIKeys.whisperAPIKey }

    private init() {}

    /// Transcribe audio data to text using OpenAI Whisper.
    /// This wrapper is preserved for legacy callers that only need plain text.
    func transcribe(audioData: Data, format: AudioFormat) async throws -> String {
        try await transcribeVerbose(audioData: audioData, format: format).text
    }

    /// Transcribe audio and return segment timestamps for downstream alignment.
    func transcribeVerbose(audioData: Data, format: AudioFormat) async throws -> WhisperVerboseTranscription {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: whisperURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendFormField(named: "file", filename: "audio.\(format.fileExtension)", mimeType: format.mimeType, data: audioData, boundary: boundary)
        body.appendFormValue("whisper-1", for: "model", boundary: boundary)
        body.appendFormValue("verbose_json", for: "response_format", boundary: boundary)
        body.appendFormValue("segment", for: "timestamp_granularities[]", boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw TranscriptionError.transcriptionFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
            }

            let decoder = JSONDecoder()
            guard let parsed = try? decoder.decode(WhisperVerboseTranscription.self, from: data) else {
                throw TranscriptionError.invalidResponse
            }

            print("[Whisper] Transcription: \(parsed.text.prefix(100))...")
            return parsed
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.networkError(error)
        }
    }
}

private extension Data {
    mutating func appendFormField(named name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendFormValue(_ value: String, for name: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
