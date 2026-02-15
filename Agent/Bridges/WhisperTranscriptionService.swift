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

@MainActor
class WhisperTranscriptionService {
    static let shared = WhisperTranscriptionService()

    private let whisperURL = "https://api.openai.com/v1/audio/transcriptions"

    private var apiKey: String? { APIKeys.whisperAPIKey }

    private init() {}

    /// Transcribe audio data to text using OpenAI Whisper
    func transcribe(audioData: Data, format: AudioFormat) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        // Build multipart/form-data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: whisperURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(format.fileExtension)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(format.mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Make request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw TranscriptionError.transcriptionFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
            }

            // Parse response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                throw TranscriptionError.invalidResponse
            }

            print("[Whisper] Transcription: \(text.prefix(100))...")
            return text

        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.networkError(error)
        }
    }
}
